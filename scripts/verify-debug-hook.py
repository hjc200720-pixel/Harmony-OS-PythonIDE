#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Verify the debug hook that is embedded in napi_init.cpp -- on the host, for real.

The debugger's Python half (breakpoint matching, stepping, scope filtering, variable
snapshots, stop semantics) lives in a raw C++ string inside entry/src/main/cpp/napi_init.cpp
because on device there is no source tree to read it from. That makes it easy to get wrong
and impossible to notice until someone debugs on a device.

This script closes that gap:
  1. it EXTRACTS the hook source from napi_init.cpp (so exactly the shipped code is tested),
  2. installs a stub _pyide_bridge module that records every pause and replies with a
     scripted command sequence,
  3. runs a fixture "project" under a real CPython 3.12,
  4. asserts breakpoint hits, single-step line sequences, scope filtering (no stdlib frames)
     and stop semantics (SystemExit(130) plus "code after the stop point did not run").

Usage:
    python scripts/verify-debug-hook.py
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
DEFAULT_CPP = os.path.join(PROJECT, "entry", "src", "main", "cpp", "napi_init.cpp")

FIXTURE = '''import json


def compute(a, b):
    total = a + b
    text = json.dumps({"t": total})
    for i in range(2):
        total += i
    return total, text


def main():
    result = compute(2, 3)
    print("RESULT", result[0])
    print("AFTER_MARKER")


if __name__ == "__main__":
    main()
'''

STUB_BRIDGE = '''"""Stub for the native _pyide_bridge module: records pauses, replays scripted commands."""
import json
import os


class _Stub(object):
    def __init__(self):
        self.commands = json.loads(os.environ.get("PYIDE_DEBUG_COMMANDS", "[]"))
        self.log_path = os.environ["PYIDE_DEBUG_LOG"]
        self.index = 0

    def emit(self, stream, text):
        return None

    def pause(self, kind, payload):
        event = json.loads(payload)
        event["kind"] = kind
        with open(self.log_path, "a", encoding="utf-8") as fp:
            fp.write(json.dumps(event) + "\\n")
        if self.index < len(self.commands):
            command = self.commands[self.index]
            self.index += 1
        else:
            command = "stop"
        return command


_bridge = _Stub()


def pause(kind, payload):
    return _bridge.pause(kind, payload)


def emit(stream, text):
    return _bridge.emit(stream, text)
'''

RUNNER = '''import json
import os
import sys

hook_source = open(os.environ["PYIDE_HOOK_SRC"], encoding="utf-8").read()
exec(compile(hook_source, "<pyide-debug-hook>", "exec"), globals())

_pyide_configure(os.environ["PYIDE_BREAKPOINTS"], os.environ["PYIDE_ROOTS"])

target = os.environ["PYIDE_TARGET"]
source = open(target, encoding="utf-8").read()
code = compile(source, target, "exec")

_pyide_install()
try:
    exec(code, globals())
except SystemExit as exc:
    sys.stderr.write("SYSTEMEXIT:%s\\n" % exc.code)
finally:
    _pyide_uninstall()
'''


def extract_hook(cpp_path: str) -> str:
    text = open(cpp_path, encoding="utf-8").read()
    match = re.search(r'R"PYDEBUG\((.*?)\)PYDEBUG"', text, re.S)
    if not match:
        raise SystemExit("FAIL: could not find the R\"PYDEBUG(...)PYDEBUG\" block in " + cpp_path)
    return match.group(1)


def run_scenario(workdir: str, hook_path: str, target: str, breakpoints: dict,
                 commands: list, timeout: int = 60):
    log_path = os.path.join(workdir, "events.log")
    if os.path.exists(log_path):
        os.remove(log_path)
    env = dict(os.environ)
    env.update({
        "PYTHONPATH": workdir,
        "PYIDE_HOOK_SRC": hook_path,
        "PYIDE_BREAKPOINTS": json.dumps(breakpoints),
        "PYIDE_ROOTS": json.dumps([os.path.dirname(target)]),
        "PYIDE_TARGET": target,
        "PYIDE_DEBUG_COMMANDS": json.dumps(commands),
        "PYIDE_DEBUG_LOG": log_path,
    })
    proc = subprocess.run([sys.executable, "-c", RUNNER],
                          capture_output=True, text=True, errors="replace",
                          env=env, timeout=timeout)
    events = []
    if os.path.exists(log_path):
        for line in open(log_path, encoding="utf-8"):
            line = line.strip()
            if line:
                events.append(json.loads(line))
    return proc, events


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cpp", default=DEFAULT_CPP)
    ap.add_argument("--keep", action="store_true", help="keep the temp workspace")
    args = ap.parse_args()

    hook = extract_hook(args.cpp)
    workdir = tempfile.mkdtemp(prefix="pyide-debug-")
    hook_path = os.path.join(workdir, "hook_source.py")
    open(hook_path, "w", encoding="utf-8").write(hook)
    open(os.path.join(workdir, "_pyide_bridge.py"), "w", encoding="utf-8").write(STUB_BRIDGE)
    project = os.path.join(workdir, "project")
    os.makedirs(project, exist_ok=True)
    target = os.path.join(project, "fixture.py")
    open(target, "w", encoding="utf-8").write(FIXTURE)

    lines = FIXTURE.split("\n")
    bp_line = next(i + 1 for i, l in enumerate(lines) if l.strip() == "total = a + b")
    next_line = bp_line + 1

    print("hook extracted from : {}".format(os.path.basename(args.cpp)))
    print("hook size           : {} bytes, {} lines".format(len(hook.encode("utf-8")), hook.count("\n")))
    print("fixture breakpoint  : {}:{}".format(os.path.basename(target), bp_line))
    print("")

    results = []

    # 1) breakpoint hit + continue
    proc, events = run_scenario(workdir, hook_path, target, {target: [bp_line]}, ["continue"])
    # The snapshot is taken *before* the paused line executes, so at `total = a + b`
    # the locals must contain a and b but NOT yet total. That timing is the point.
    # compute(2, 3) -> total = 5, then the loop adds 0 and 1 -> RESULT 6.
    names = {name for name, _ in events[0]["locals"]} if events else set()
    ok = (len(events) == 1 and events[0]["line"] == bp_line
          and events[0]["func"] == "compute" and events[0]["kind"] == "breakpoint"
          and names >= {"a", "b"} and "total" not in names
          and os.path.abspath(events[0]["file"]) == os.path.abspath(target)
          and "RESULT 6" in proc.stdout)
    results.append(("breakpoint hit + continue", ok,
                    "events={} lines={} func={} kind={} locals={} (total absent: {}) stdout={!r}".format(
                        len(events), [e["line"] for e in events],
                        [e["func"] for e in events], [e["kind"] for e in events],
                        sorted(names), "total" not in names, proc.stdout.strip()[:24])))

    # 2) single step: breakpoint, then step twice, then continue
    proc, events = run_scenario(workdir, hook_path, target, {target: [bp_line]},
                               ["step", "step", "continue"])
    ok = (len(events) == 3
          and [e["line"] for e in events] == [bp_line, next_line, next_line + 1]
          and all(e["func"] == "compute" for e in events)
          and all(e["kind"] == "breakpoint" or e["kind"] == "step" for e in events))
    results.append(("single step (3 pauses)", ok,
                    "lines={} kinds={}".format([e["line"] for e in events],
                                               [e["kind"] for e in events])))

    # 3) scope filtering: stepping must never pause inside the stdlib
    proc, events = run_scenario(workdir, hook_path, target, {target: [bp_line]},
                               ["step", "step", "step", "step", "continue"])
    outside = [e["file"] for e in events if not os.path.abspath(e["file"]).startswith(project)]
    ok = (len(events) >= 3 and not outside)
    results.append(("scope filter (no stdlib frames)", ok,
                    "pauses={} outside_project={}".format(len(events), outside)))

    # 4) stop: the code after the stop point must not run
    proc, events = run_scenario(workdir, hook_path, target, {target: [bp_line]}, ["stop"])
    stopped = "SYSTEMEXIT:130" in proc.stderr
    ok = (len(events) == 1 and stopped and "AFTER_MARKER" not in proc.stdout
          and "RESULT" not in proc.stdout)
    results.append(("stop -> SystemExit(130), no further execution", ok,
                    "events={} systemexit={} stdout={!r}".format(
                        len(events), stopped, proc.stdout.strip()[:40])))

    # 5) no breakpoints -> no pauses, program runs to completion
    proc, events = run_scenario(workdir, hook_path, target, {}, ["continue"])
    ok = (len(events) == 0 and "AFTER_MARKER" in proc.stdout)
    results.append(("no breakpoints -> no pauses", ok,
                    "events={} after_marker={}".format(len(events), "AFTER_MARKER" in proc.stdout)))

    # 6) call stack snapshot is present and innermost-first
    proc, events = run_scenario(workdir, hook_path, target, {target: [bp_line]}, ["continue"])
    ok = bool(events) and len(events[0]["stack"]) >= 2 and events[0]["stack"][0][2] == "compute"
    results.append(("call stack snapshot", ok,
                    "stack={}".format([[os.path.basename(f), l, n]
                                       for f, l, n in events[0]["stack"]] if events else [])))

    print("scenario results:")
    failures = 0
    for name, ok, detail in results:
        print("   {} {:<46} {}".format("OK " if ok else "!! ", name, detail))
        if not ok:
            failures += 1

    if args.keep:
        print("\nworkspace kept at: {}".format(workdir))
    else:
        shutil.rmtree(workdir, ignore_errors=True)

    print("")
    if failures:
        print("RESULT: FAIL ({} of {} scenarios)".format(failures, len(results)))
        return 1
    print("RESULT: PASS ({} scenarios)".format(len(results)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
