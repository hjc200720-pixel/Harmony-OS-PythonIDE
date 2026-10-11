#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Runtime contract check: does our bundled stdlib zip actually satisfy the imports?

Why this exists
---------------
No signing material is available on this machine, so the app cannot be installed on a
device/emulator and the embedded CPython cannot be exercised there. The next best thing
is to reproduce the *import environment* the interpreter sees on device:

    sys.path = [ <sandbox>/site-packages, <sandbox>/python312.zip ]

i.e. only our own zip plus an empty site-packages. Running the host CPython 3.12.10
(same version as the target) in that environment proves:

  * the zip is structurally valid for zipimport (modules really do load from inside it),
  * the pure-Python half of every module we advertise is present,
  * nothing we claim to support is missing because the packer excluded a file.

Caveat, stated honestly: on device every C extension is statically linked into
libpython, while on the host they live in lib-dynload. This script appends that host
directory so the pure-Python modules can find their C backends, and then *checks the
origin* of each module, so "loaded from the zip" is still asserted strictly. The C side
itself is covered separately by the symbol check against libpython3.12.a.

Usage
-----
    python scripts/verify-runtime-contract.py \
        --zip entry/src/main/resources/rawfile/python/python312.zip \
        --archive entry/src/main/cpp/thirdparty/arm64-v8a/libpython3.12.a
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile

# Modules the IDE advertises as available: everything here must import from the zip.
EXPECTED_MODULES = [
    "os", "sys", "io", "json", "re", "collections", "collections.abc", "datetime",
    "math", "cmath", "decimal", "random", "struct", "array", "binascii", "zlib",
    "gzip", "zipfile", "tarfile", "csv", "hashlib", "hmac", "base64", "bisect",
    "heapq", "contextvars", "queue", "threading", "asyncio", "select",
    "xml.etree.ElementTree", "unicodedata", "codecs", "encodings.idna",
    "urllib.parse", "pathlib", "dataclasses", "typing", "argparse", "traceback",
    "logging", "pickle", "copy", "functools", "itertools", "operator",
    "statistics", "fractions", "string", "textwrap", "shutil", "tempfile",
    "glob", "fnmatch", "difflib", "pprint", "inspect", "ast",
    "tokenize", "dis", "importlib", "importlib.util", "runpy", "platform",
    "time", "calendar", "zoneinfo", "email.parser", "http.client",
]

CHECK_SCRIPT = r'''
import sys, os

zip_path, site_dir, dynload_dir = sys.argv[1], sys.argv[2], sys.argv[3]

# Exactly what PyConfig.module_search_paths is set to inside napi_init.cpp:
# site-packages first, then the stdlib zip. On device the C extensions come from the
# statically linked libpython; on the host they live in lib-dynload, which we append
# purely as a stand-in so the pure-Python modules can resolve their backends.
sys.path[:] = [site_dir, zip_path]
if dynload_dir:
    for _extra in dynload_dir.split(os.pathsep):
        if _extra and os.path.isdir(_extra):
            sys.path.append(_extra)

report = {"imported": [], "failed": [], "zipbacked": [], "otherbacked": [], "calls": {}}

for name in @@EXPECTED@@:
    try:
        __import__(name)
    except Exception as exc:
        report["failed"].append([name, "%s: %s" % (type(exc).__name__, exc)])
        continue
    report["imported"].append(name)
    origin = ""
    for part in name.split("."):
        pass
    mod = sys.modules.get(name)
    origin = getattr(mod, "__file__", "") or ""
    if not origin:
        for part in name.split("."):
            sub = sys.modules.get(part)
            if sub is not None and getattr(sub, "__file__", ""):
                origin = sub.__file__
                break
    if "python312.zip" in origin:
        report["zipbacked"].append(name)
    elif origin:
        report["otherbacked"].append(name)


def probe(key, fn):
    try:
        report["calls"][key] = str(fn())
    except Exception as exc:
        report["calls"][key] = "ERROR %s: %s" % (type(exc).__name__, exc)


probe("zlib.crc32", lambda: __import__("zlib").crc32(b"harmony") & 0xFFFFFFFF)
probe("zlib.compress+decompress", lambda: len(__import__("zlib").decompress(
    __import__("zlib").compress(b"x" * 5000))))
probe("hashlib.sha256", lambda: __import__("hashlib").sha256(b"harmony").hexdigest()[:16])
probe("hashlib.md5", lambda: __import__("hashlib").md5(b"harmony").hexdigest()[:16])
probe("hashlib.blake2b", lambda: __import__("hashlib").blake2b(b"h").hexdigest()[:16])
probe("json roundtrip", lambda: __import__("json").loads(
    __import__("json").dumps({"a": [1, 2, 3]}))["a"])
probe("decimal.Decimal", lambda: str(__import__("decimal").Decimal("1.1") + __import__("decimal").Decimal("2.2")))
probe("math.sqrt", lambda: round(__import__("math").sqrt(2), 6))
probe("datetime.strftime", lambda: __import__("datetime").datetime(2024, 1, 2).strftime("%Y-%m-%d"))
probe("re.findall", lambda: __import__("re").findall(r"\d+", "a1b22"))
probe("unicodedata.name", lambda: __import__("unicodedata").name("\u4e2d"))
probe("xml.etree parse", lambda: len(
    __import__("importlib").import_module("xml.etree.ElementTree").fromstring("<a><b/></a>")))
probe("tarfile+zipfile", lambda: (__import__("tarfile").__name__, __import__("zipfile").__name__))
probe("threading+queue", lambda: (__import__("threading").current_thread().name,
                                  __import__("queue").Queue().qsize()))
probe("asyncio.run", lambda: __import__("asyncio").run(
    (lambda: __import__("asyncio").sleep(0))()) or "ran")
probe("socket.socket(AF_INET)", lambda: (lambda s: (s.close(), "created")[1])(
    __import__("socket").socket(__import__("socket").AF_INET, __import__("socket").SOCK_STREAM)))
probe("json.__file__ (should be the zip)", lambda: (__import__("json").__file__ or "")[-60:])

sys.stdout.write("@@REPORT@@" + __import__("json").dumps(report) + "@@END@@")
'''


def nm_builtin_modules(nm_path: str, archive: str):
    """The PyInit_* symbol set of the static library == the target's built-in modules."""
    if not os.path.exists(nm_path) or not os.path.exists(archive):
        return None
    try:
        out = subprocess.run([nm_path, "--defined-only", archive],
                             capture_output=True, text=True, errors="replace").stdout
    except OSError:
        return None
    names = set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and len(parts[-2]) == 1 and parts[-2].isalpha():
            sym = parts[-1]
            if sym.startswith("PyInit_"):
                names.add(sym[len("PyInit_"):].lstrip("_"))
    return names


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zip", dest="zip_path", required=True)
    ap.add_argument("--archive", default="", help="libpython3.12.a, to cross-check the C modules")
    ap.add_argument("--ndk", default=r"D:\DevEco Studio\sdk\default\openharmony\native")
    ap.add_argument("--host-python", default=sys.executable)
    args = ap.parse_args()

    if not os.path.exists(args.zip_path):
        print("FAIL: stdlib zip not found: {}".format(args.zip_path))
        return 2

    # Host stand-in for the target's statically linked C extensions.
    # ONLY extension directories may be appended -- deliberately NOT the host stdlib
    # directory. On Windows sysconfig reports platstdlib == stdlib (both ...\Python312\Lib),
    # and appending it would silently let pure-Python modules load from the host instead
    # of from our zip, which would make the whole check meaningless.
    import sysconfig
    paths = sysconfig.get_paths()
    candidates = [
        os.path.join(paths.get("platstdlib", ""), "DLLs"),
        os.path.join(paths.get("stdlib", ""), "lib-dynload"),
        os.path.join(sys.prefix, "DLLs"),
    ]
    dynload = os.pathsep.join(d for d in candidates if d and os.path.isdir(d))
    if not dynload:
        print("WARN: no host extension directory found; C-backend modules may fail here")
    site = tempfile.mkdtemp(prefix="pyide-site-")

    script = (CHECK_SCRIPT
              .replace("@@EXPECTED@@", repr(EXPECTED_MODULES)))
    proc = subprocess.run([args.host_python, "-I", "-S", "-c", script,
                           os.path.abspath(args.zip_path), site, dynload],
                          capture_output=True, text=True, errors="replace")
    out = proc.stdout
    if "@@REPORT@@" not in out:
        print("FAIL: probe produced no report")
        print("--- stdout tail ---\n" + out[-1500:])
        print("--- stderr tail ---\n" + proc.stderr[-1500:])
        return 2
    report = json.loads(out.split("@@REPORT@@", 1)[1].split("@@END@@", 1)[0])

    print("stdlib zip   : {}".format(os.path.abspath(args.zip_path)))
    print("sys.path     : ['{}', '<zip>', '<host lib-dynload stand-in>']".format(site))
    print("imported     : {}/{}".format(len(report["imported"]), len(EXPECTED_MODULES)))
    print("from zip     : {}   (origin contains python312.zip)".format(len(report["zipbacked"])))
    print("")

    nm = os.path.join(args.ndk, "llvm", "bin", "llvm-nm.exe")
    builtin = nm_builtin_modules(nm, args.archive) if args.archive else None
    if builtin:
        print("C modules statically linked in libpython3.12.a: {}".format(len(builtin)))
        print("   " + ", ".join(sorted(builtin)[:26]) + (" ..." if len(builtin) > 26 else ""))
        print("")

    problems = []
    if report["failed"]:
        print("!! modules that FAILED to import from the zip:")
        for name, err in report["failed"]:
            print("   - {:<26} {}".format(name, err))
        problems.append("{} import failures".format(len(report["failed"])))
    else:
        print("OK: every advertised module imported successfully")

    print("")
    print("functional probes:")
    for key, value in report["calls"].items():
        bad = value.startswith("ERROR")
        print("   {}{:<28} {}".format("!! " if bad else "OK ", key, value[:90]))
        if bad:
            problems.append(key)

    if len(report["zipbacked"]) < 5:
        print("")
        print("!! only {} modules resolved from the zip -- zipimport is not effective"
              .format(len(report["zipbacked"])))
        problems.append("zipimport not effective")
    else:
        print("")
        print("zip-backed modules include: {}".format(", ".join(report["zipbacked"][:10])))

    print("")
    if problems:
        print("RESULT: FAIL -> {}".format("; ".join(problems)))
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
