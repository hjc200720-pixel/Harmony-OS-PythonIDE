#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""诊断 libpython3.12.a 链接进应用时的"未定义符号"风险。

背景：交叉编译时用的 sysroot 里有**静态** libc.a 和**动态** libc.so 两套。
探针链到静态库能成功的符号，设备上的 libc.so 未必导出，于是 HAP 链接阶段才会
报 `undefined symbol: xxx`，一次只报一个，非常费时间。

本脚本一次性算出：
    未定义符号(来自 libpython3.12.a)
  - 归档内已定义符号
  - 动态库(libc.so / libm.so / libdl.so / libz.so)导出的符号
  - 由 libc++_shared.so 提供的一套 C++ 运行时符号前缀
  = 真正需要处理的候选清单
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

CXX_PREFIXES = ("_Z", "_ZN", "__cxa_", "_Unwind_", "operator ", "std::", "_ZSt", "_ZNK")


def nm(nm_path, args, target):
    r = subprocess.run([nm_path] + args + [target], capture_output=True, text=True, errors="replace")
    return (r.stdout or "") + (r.stderr or "")


def symbols(nm_path, target, mode, dynamic=False):
    """解析 llvm-nm 输出。

    llvm-nm 对归档的排版是两种形式混排，必须显式识别，否则会把成员名
    （如 `boolobject.o:`）当成符号：
        归档:   boolobject.o: 0000000000000000 T PyBool_FromLong
                boolobject.o: U memcpy
        动态库: 0000000000011d80 T gethostbyname_r
    """
    args = ["--dynamic"] if dynamic else []
    args.append("--defined-only" if mode == "defined" else "--undefined-only")
    raw = nm(nm_path, args, target)
    result = set()
    for line in raw.splitlines():
        parts = line.split()
        if not parts:
            continue
        if mode == "defined":
            # 倒数第二个字段是单字母类型（T/D/B/R/W/V/A/i/C），最后一个是符号名
            if len(parts) >= 3 and len(parts[-2]) == 1 and parts[-2].isalpha():
                result.add(parts[-1])
        else:
            if len(parts) >= 2 and parts[-2] == "U":
                result.add(parts[-1])
    return {s for s in result if s and not s.endswith(":")}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--archive", required=True)
    ap.add_argument("--ndk", required=True)
    ap.add_argument("--triplet", default="aarch64-linux-ohos")
    args = ap.parse_args()

    nm_path = os.path.join(args.ndk, "llvm", "bin", "llvm-nm.exe")
    if not os.path.exists(nm_path):
        nm_path = os.path.join(args.ndk, "llvm", "bin", "llvm-nm")
    libdir = os.path.join(args.ndk, "sysroot", "usr", "lib", args.triplet)

    arch_defined = symbols(nm_path, args.archive, "defined")
    arch_undefined = symbols(nm_path, args.archive, "undefined")
    lib_defined = set()
    for name in ("libc.so", "libm.so", "libdl.so", "libz.so", "libpthread.so", "librt.so"):
        path = os.path.join(libdir, name)
        if os.path.exists(path):
            got = symbols(nm_path, path, "defined", dynamic=True)
            if got:
                lib_defined |= got
                print("dynamic lib {:<16} {} symbols".format(name, len(got)), file=sys.stderr)

    suspicious = set()
    for sym in arch_undefined:
        if sym in arch_defined or sym in lib_defined:
            continue
        if any(sym.startswith(p) for p in CXX_PREFIXES):
            continue
        if sym.startswith("__") and sym.endswith("_chk"):
            continue
        suspicious.add(sym)

    print("archive defined : {}".format(len(arch_defined)))
    print("archive undefined: {}".format(len(arch_undefined)))
    print("dynamic libs     : {}".format(len(lib_defined)))
    print("")
    if not suspicious:
        print("OK: 归档里的未定义符号都能被 libc/动态库解析")
        return 0
    print("需要处理的候选符号（共 {} 个）:".format(len(suspicious)))
    for sym in sorted(suspicious):
        print("  {}".format(sym))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
