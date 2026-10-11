#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 CPython 的 Lib/ 打包成 python312.zip，供 IDE 随包发布。

为什么是 zip 而不是解压目录：
    CPython 的 zipimport 可以直接从 zip 里导入纯 Python 模块，不需要解压、
    不需要 __pycache__ 写权限，App 首次启动只要把 zip 从 rawfile 复制到沙箱即可
    （见 entry/src/main/ets/service/PyRuntimeService.ets 的 releaseStdlibFromRawfile）。

用法：
    python scripts/package-stdlib.py --src <cpython-3.12.10 源码树> \
        --out <工程>/entry/src/main/resources/rawfile/python/python312.zip
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import zipfile

# 这些目录对 IDE 场景无用，去掉能省 ~60% 体积
EXCLUDE_DIRS = {
    "test", "tests", "idlelib", "tkinter", "turtledemo", "lib2to3",
    "ensurepip/_bundled", "site-packages", "distutils", "unittest/test",
    "__pycache__", "config-3.12", "config-3.12-x86_64-linux-gnu",
}
EXCLUDE_SUFFIX = (".pyc", ".pyo", ".o", ".a", ".so")
# 这些顶层文件必须保留
KEEP_ALWAYS = {"site.py", "os.py", "encodings/__init__.py"}


def should_skip(rel: str) -> bool:
    parts = rel.split("/")
    for i in range(len(parts)):
        prefix = "/".join(parts[: i + 1])
        if prefix in EXCLUDE_DIRS:
            return True
    name = parts[-1]
    if name.endswith(EXCLUDE_SUFFIX):
        return True
    if name == "LICENSE.txt":
        return True
    return False


def copy_pip_wheel(src: str, out_dir: str) -> str:
    """把 CPython 自带的 pip wheel 复制到 rawfile 目录。

    为什么不把它塞进标准库 zip：ensurepip 需要读取自己 `_bundled/` 下的 **真实文件**，
    而 zipimport 下 `__file__` 不是可用路径，ensurepip 必然失败。所以由 IDE 在首次启动时
    把 wheel 解压进 site-packages，pip 才真正可用（离线安装本地 wheel 的前提）。
    """
    bundled = os.path.join(src, "Lib", "ensurepip", "_bundled")
    if not os.path.isdir(bundled):
        return ""
    wheels = sorted(f for f in os.listdir(bundled)
                    if f.startswith("pip-") and f.endswith(".whl"))
    if not wheels:
        return ""
    os.makedirs(out_dir, exist_ok=True)
    name = wheels[-1]
    dest = os.path.join(out_dir, name)
    shutil.copyfile(os.path.join(bundled, name), dest)
    print("pip wheel: {} -> {} ({:.2f} MiB)".format(
        name, dest, os.path.getsize(dest) / 1048576))
    return dest


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True, help="CPython 源码树根目录")
    ap.add_argument("--out", required=True, help="输出的 python312.zip 路径")
    ap.add_argument("--pip-wheel-dir", default="",
                    help="把 CPython 自带的 pip wheel 复制到这个目录（IDE 首次启动时解压到 "
                         "site-packages，pip 才真正可用）")
    args = ap.parse_args()

    lib = os.path.join(args.src, "Lib")
    if not os.path.isdir(lib):
        print("找不到 Lib 目录：{}".format(lib), file=sys.stderr)
        return 2

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    count = 0
    total_raw = 0
    missing_required = []
    with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for base, dirs, files in os.walk(lib):
            dirs[:] = [d for d in dirs if d != "__pycache__"]
            for name in sorted(files):
                full = os.path.join(base, name)
                rel = os.path.relpath(full, lib).replace(os.sep, "/")
                if should_skip(rel):
                    continue
                zf.write(full, rel)
                count += 1
                total_raw += os.path.getsize(full)

    with zipfile.ZipFile(args.out) as zf:
        names = set(zf.namelist())
    for required in sorted(KEEP_ALWAYS):
        if required not in names:
            missing_required.append(required)

    size = os.path.getsize(args.out)
    print("已写入 {} 个文件，原始 {:.1f} MiB -> 压缩 {:.2f} MiB".format(
        count, total_raw / 1048576, size / 1048576))
    print("输出：{}".format(os.path.abspath(args.out)))
    if missing_required:
        print("警告：缺少关键模块 {}".format(", ".join(missing_required)), file=sys.stderr)
        return 1
    # 快速自检：确认几个启动必需的模块确实在包里
    for probe in ("encodings/__init__.py", "os.py", "codecs.py", "zipimport.py"):
        if probe not in names:
            print("警告：缺少 {}".format(probe), file=sys.stderr)
            return 1
    print("自检通过：encodings / os / codecs / zipimport 均在包内")
    if args.pip_wheel_dir:
        if not copy_pip_wheel(args.src, args.pip_wheel_dir):
            print("警告：未找到 ensurepip 自带的 pip wheel，IDE 内将无法使用 pip",
                  file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
