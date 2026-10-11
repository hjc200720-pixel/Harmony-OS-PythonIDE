#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""检查构建出来的 HAP 是否符合预期（可直接接进 CI）。

检查项：
  1. 必需条目是否存在：module.json / ets/modules.abc / resources.index
  2. 两个 ABI 的 libpythonbridge.so 是否都在
  3. libpythonbridge.so 的体积是否说明"内嵌 CPython 已链接进去"
     （未链接约 0.24 MB；整库链接 CPython 后应在 8 MB 以上）
  4. rawfile 里的标准库 zip 是否随包（py_compile 依赖它才能运行 Python）

用法：
    python scripts/verify-hap.py <hap 路径> [--expect-runtime]
"""
from __future__ import annotations

import argparse
import sys
import zipfile

REQUIRED = ("module.json", "ets/modules.abc", "resources.index")
BRIDGE = "libs/{abi}/libpythonbridge.so"
ABIS = ("arm64-v8a", "x86_64")
# 未链接 libpython 时 libpythonbridge.so 约 0.24 MB；阈值取 4 MB 以明确区分
RUNTIME_LINKED_THRESHOLD = 4 * 1024 * 1024


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hap")
    ap.add_argument("--expect-runtime", action="store_true",
                    help="要求内嵌 CPython 已链接（未链接则判定失败）")
    args = ap.parse_args()

    problems = []
    notes = []
    with zipfile.ZipFile(args.hap) as zf:
        names = set(zf.namelist())
        print("HAP: {}  ({} 个条目, {:.2f} MiB)".format(
            args.hap, len(names), sum(zf.getinfo(n).file_size for n in names) / 1048576))

        for item in REQUIRED:
            if item in names:
                print("  [OK]   {}".format(item))
            else:
                problems.append("缺少必需条目 {}".format(item))
                print("  [FAIL] {}".format(item))

        linked_any = False
        for abi in ABIS:
            entry = BRIDGE.format(abi=abi)
            if entry not in names:
                notes.append("{} 缺失（若不需要该 ABI 可忽略）".format(entry))
                print("  [SKIP] {}".format(entry))
                continue
            size = zf.getinfo(entry).file_size
            if size >= RUNTIME_LINKED_THRESHOLD:
                linked_any = True
                print("  [OK]   {}  {:.2f} MiB  ← 已内嵌 CPython".format(entry, size / 1048576))
            else:
                print("  [WARN] {}  {:.0f} KB  ← 看起来没有链接 libpython3.12.a".format(
                    entry, size / 1024))

        stdlib = [n for n in names if n.endswith("python312.zip")]
        if stdlib:
            size = zf.getinfo(stdlib[0]).file_size
            print("  [OK]   {}  {:.2f} MiB".format(stdlib[0], size / 1048576))
        else:
            notes.append("rawfile 里没有 python312.zip：App 能装能开，但执行 Python 会提示运行时未就绪")
            print("  [WARN] resources/rawfile/python/python312.zip 未随包")

    for note in notes:
        print("提示: {}".format(note))
    if args.expect_runtime and not linked_any:
        problems.append("--expect-runtime 要求内联 CPython，但没有任何 ABI 的 .so 达到体积阈值")
    if problems:
        print("\n结果: FAIL")
        for p in problems:
            print("  - {}".format(p))
        return 1
    print("\n结果: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
