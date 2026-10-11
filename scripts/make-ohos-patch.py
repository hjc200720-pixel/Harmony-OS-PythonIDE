#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate the OpenHarmony cross-compile patch for CPython 3.12.10.

The upstream OpenHarmony port ships ``patches/cross_compile_support_ohos.patch``
against CPython **3.11.4**.  Three of its hunks matter and are ported here to
3.12.10 (the file layout around them is unchanged):

  1. ``config.sub``    -- accept ``ohos*`` as an OS and ``*-ohos*`` as a kernel/OS pair
  2. ``configure.ac``  -- recognise the ``aarch64-linux-ohos`` / ``arm-linux-ohos``
                          platform triplets and pass ``$CFLAGS`` to
                          ``--print-multiarch``
  3. generated ``configure`` -- the very same three edits, applied by hand because
                          autoconf is not available on this build host

The 3.11.4 patch also carried two ``setup.py`` hunks (a hard-coded
``DISABLED_MODULE_LIST`` and a multiarch path tweak).  ``setup.py`` **does not
exist in 3.12** -- module selection moved into ``configure`` +
``Modules/Setup.stdlib`` -- so those hunks are intentionally dropped.  Their job
is done by ``DISABLED_MODULES`` in ``ohos_cpython_build.py``.

Usage:
    python make-ohos-patch.py --src <cpython-3.12.10 tree> --out <patch file>
"""
from __future__ import annotations

import argparse
import difflib
import os
import sys

# ---------------------------------------------------------------------------
# (file, old text, new text) -- every edit must match exactly once
# ---------------------------------------------------------------------------
EDITS = [
    # ---- config.sub ------------------------------------------------------
    (
        "config.sub",
        "| nsk* | powerunix* | genode* | zvmoe* | qnx* | emx* | zephyr*)",
        "| nsk* | powerunix* | genode* | zvmoe* | qnx* | emx* | zephyr* | ohos*)",
    ),
    (
        "config.sub",
        "\t*-eabi* | *-gnueabi*)\n\t\t;;\n",
        "\t*-eabi* | *-gnueabi*)\n\t\t;;\n\t*-ohos*)\n\t\t;;\n",
    ),
    # ---- configure.ac / configure: platform triplet detection ------------
    (
        "*",
        "#  if defined(__ILP32__)\n"
        "        aarch64_ilp32-linux-gnu\n"
        "#  else\n"
        "        aarch64-linux-gnu\n",
        "#  if defined(__ILP32__)\n"
        "        aarch64_ilp32-linux-gnu\n"
        "#  elif defined(__OHOS__)\n"
        "        aarch64-linux-ohos\n"
        "#  else\n"
        "        aarch64-linux-gnu\n",
    ),
    (
        "*",
        "#  if defined(__ARMEL__)\n"
        "        arm-linux-gnueabi\n"
        "#  else\n",
        "#  if defined(__ARMEL__) && !defined(__OHOS__)\n"
        "        arm-linux-gnueabi\n"
        "#  elif defined(__OHOS__)\n"
        "        arm-linux-ohos\n"
        "#  else\n",
    ),
    # ---- multiarch probe: clang needs the target flags -------------------
    (
        "*",
        "MULTIARCH=$($CC --print-multiarch 2>/dev/null)",
        "MULTIARCH=$($CC $CFLAGS --print-multiarch 2>/dev/null)",
    ),
]

FILES = ["config.sub", "configure.ac", "configure"]

HEADER = """\
OpenHarmony / HarmonyOS cross-compile support for CPython 3.12.10
================================================================

Ported from the OpenHarmony third_party_python port
(https://gitee.com/openharmony/third_party_python),
patches/cross_compile_support_ohos.patch, which targets CPython 3.11.4.

What this patch does
--------------------
* config.sub      : accept `ohos` as an operating system, and `*-ohos*` as a
                    valid kernel/OS combination.  Without this, `configure`
                    dies with "Invalid configuration `aarch64-linux-ohos'".
* configure.ac    : teach the platform-triplet probe that `__OHOS__` (defined by
                    clang for -target *-linux-ohos) means the triplet is
                    `aarch64-linux-ohos` / `arm-linux-ohos` instead of the
                    glibc `aarch64-linux-gnu` / `arm-linux-gnueabi`.
                    Also pass $CFLAGS to `--print-multiarch`, because clang only
                    knows the target when the -target flag is present.
* configure       : the same three edits, applied to the pre-generated script.
                    CPython ships a generated `configure` and this build host has
                    no autoconf, so the edits are made in both places.

Hunks deliberately NOT ported
-----------------------------
The 3.11.4 patch also modified `setup.py`:

    -DISABLED_MODULE_LIST = []
    +DISABLED_MODULE_LIST = ['_uuid', '_socket', 'zlib', '_ctypes', 'binascii']

`setup.py` was removed in CPython 3.12; extension-module selection now lives in
`configure` + `Modules/Setup.stdlib`.  The equivalent for this port is the
`DISABLED_MODULES` table in `HarmonyPyIDE/scripts/ohos_cpython_build.py`.

Apply with:
    patch -p1 -d <cpython-3.12.10> < cpython-3.12.10-ohos-cross.patch
    # or
    git apply -p1 --directory=<cpython-3.12.10> cpython-3.12.10-ohos-cross.patch

"""


def apply_edit(text: str, old: str, new: str, where: str) -> str:
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR: anchor matched {n} times (expected 1) in {where}:\n{old!r}")
    return text.replace(old, new)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="pristine CPython 3.12.10 source tree")
    ap.add_argument("--out", required=True, help="patch file to write")
    args = ap.parse_args()

    chunks = [HEADER]
    for rel in FILES:
        path = os.path.join(args.src, rel)
        if not os.path.exists(path):
            raise SystemExit(f"missing {path}")
        raw = open(path, encoding="utf-8", newline="").read()
        if "\r\n" in raw:
            raise SystemExit(f"{rel} has CRLF line endings; refusing to patch")
        orig = raw.split("\n")
        new_text = raw
        for target, old, new in EDITS:
            # "*" = the three edits shared by configure.ac and the generated configure
            applies = (rel in ("configure.ac", "configure")) if target == "*" else (target == rel)
            if applies:
                new_text = apply_edit(new_text, old, new, rel)
        if new_text == raw:
            raise SystemExit(f"no edit applied to {rel}")
        new = new_text.split("\n")
        diff = difflib.unified_diff(orig, new,
                                    fromfile="a/" + rel, tofile="b/" + rel,
                                    lineterm="", n=3)
        chunks.append("\n".join(diff) + "\n")

    text = "\n".join(chunks)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"wrote {args.out} ({len(text)} bytes)")
    for rel in FILES:
        print(f"  patched {rel}")


if __name__ == "__main__":
    main()
