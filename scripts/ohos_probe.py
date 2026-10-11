#!/usr/bin/env python3
"""Cross-build CPython 3.12.10 for HarmonyOS/OpenHarmony (aarch64-linux-ohos).

This replaces `configure` + `make` because those require a POSIX shell, and the
MSYS2 shell in this environment cannot start (`couldn't create signal pipe`).

What this script does:
  1. probe the OHOS sysroot with the NDK clang to synthesise `Include/pyconfig.h`
  2. generate `Modules/config.c` (the inittab) + the extension-module source list
  3. generate frozen stdlib headers (`Python/frozen_modules/*.h`) with the host
     Python 3.12.10 (this is exactly what CPython does for cross builds)
  4. generate `Python/deepfreeze/deepfreeze.c` with the host Python
  5. compile all core + extension objects with the NDK clang
  6. archive them into `libpython3.12.a` with llvm-ar
"""
from __future__ import annotations

import argparse
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import textwrap
import time

# --------------------------------------------------------------------------
# Paths / defaults
# --------------------------------------------------------------------------
DEFAULT_WS = r"D:\HuaweiMoveData\Users\HUAWEI\OneDrive\Documents\deepseek-harness\default-workspace"
DEFAULT_NDK = r"D:\DevEco Studio\sdk\default\openharmony\native"
DEFAULT_HOSTPY = r"C:\Users\HUAWEI\AppData\Local\Programs\Python\Python312\python.exe"

ARCHES = {
    "arm64-v8a": "aarch64-linux-ohos",
    "x86_64": "x86_64-linux-ohos",
}

VERBOSE = False


def log(*a):
    print(*a, flush=True)


def vlog(*a):
    if VERBOSE:
        print(*a, flush=True)


# --------------------------------------------------------------------------
# Toolchain wrapper
# --------------------------------------------------------------------------
class Toolchain:
    def __init__(self, ndk: str, host: str):
        self.ndk = ndk
        self.llvm_bin = os.path.join(ndk, "llvm", "bin")
        self.sysroot = os.path.join(ndk, "sysroot")
        self.clang = os.path.join(self.llvm_bin, "clang.exe")
        self.ar = os.path.join(self.llvm_bin, "llvm-ar.exe")
        self.ranlib = os.path.join(self.llvm_bin, "llvm-ranlib.exe")
        self.nm = os.path.join(self.llvm_bin, "llvm-nm.exe")
        self.readelf = os.path.join(self.llvm_bin, "llvm-readelf.exe")
        self.target = host

    def cc_args(self):
        return [
            self.clang,
            "-target", self.target,
            f"--sysroot={self.sysroot}",
            "-D__MUSL__",
        ]

    def run(self, args, **kw):
        return subprocess.run(args, capture_output=True, text=True, errors="replace", **kw)


# --------------------------------------------------------------------------
# Probe helper: compile (and optionally link) a snippet for the target
# --------------------------------------------------------------------------
class Probes:
    """Caches compiler probes; every result is derived from the real toolchain."""

    PRELUDE_HEADERS = [
        "stdio.h", "stdlib.h", "string.h", "strings.h", "unistd.h", "fcntl.h",
        "errno.h", "math.h", "time.h", "sys/time.h", "sys/types.h", "sys/stat.h",
        "sys/wait.h", "sys/socket.h", "sys/select.h", "sys/ioctl.h", "sys/mman.h",
        "sys/random.h", "sys/param.h", "sys/un.h", "sys/utsname.h", "sys/resource.h",
        "sys/times.h", "sys/file.h", "sys/uio.h", "sys/epoll.h", "sys/eventfd.h",
        "sys/syscall.h", "sys/sysmacros.h", "sys/auxv.h", "sys/prctl.h", "sys/sendfile.h",
        "netinet/in.h", "netinet/tcp.h", "arpa/inet.h", "netdb.h", "grp.h", "pwd.h",
        "signal.h", "setjmp.h", "locale.h", "langinfo.h", "wchar.h", "wctype.h",
        "dirent.h", "dlfcn.h", "termios.h", "poll.h", "pthread.h", "semaphore.h",
        "sched.h", "spawn.h", "utime.h", "limits.h", "float.h", "inttypes.h",
        "stdint.h", "stddef.h", "stdarg.h", "ctype.h", "assert.h", "complex.h",
        "endian.h", "shadow.h", "syslog.h", "crypt.h", "utmp.h", "pty.h",
        "linux/random.h", "linux/netlink.h", "linux/limits.h", "linux/auxvec.h",
        "linux/memfd.h", "linux/falloc.h", "linux/if_packet.h", "linux/can.h",
        "linux/fs.h", "linux/wait.h", "linux/vm_sockets.h",
        "zlib.h",
    ]

    def __init__(self, tc: Toolchain, workdir: str):
        self.tc = tc
        self.workdir = workdir
        os.makedirs(workdir, exist_ok=True)
        self._cache: dict[str, bool] = {}
        self.count = 0

    def _write(self, name: str, text: str) -> str:
        p = os.path.join(self.workdir, name)
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        return p

    def compile(self, body: str, *, link: bool = False, extra=None, includes=True,
                tag: str = "probe") -> tuple[bool, str]:
        """Compile `body`; if link, also link into an executable."""
        if includes:
            prelude = "\n".join(f"#include <{h}>" for h in self.PRELUDE_HEADERS)
        else:
            prelude = ""
        src = f"{prelude}\n{body}\n"
        cpath = self._write("t.c", src)
        opath = os.path.join(self.workdir, "t.o")
        args = self.tc.cc_args() + [
            "-c", "-o", opath, cpath,
            "-D_GNU_SOURCE", "-D_FILE_OFFSET_BITS=64",
        ]
        if extra:
            args += extra
        if link:
            epath = os.path.join(self.workdir, "t.exe")
            args = self.tc.cc_args() + ["-o", epath, cpath,
                                        "-D_GNU_SOURCE", "-D_FILE_OFFSET_BITS=64"]
            if extra:
                args += extra
        r = self.tc.run(args)
        self.count += 1
        ok = r.returncode == 0
        vlog(f"[probe {tag}] {'ok' if ok else 'FAIL'}")
        return ok, (r.stderr or "") + (r.stdout or "")

    def cached(self, key: str, fn) -> bool:
        if key not in self._cache:
            self._cache[key] = fn()
        return self._cache[key]

    # -- headers -----------------------------------------------------------
    def has_header(self, header: str) -> bool:
        def f():
            ok, _ = self.compile(f'#include <{header}>', includes=False,
                                 extra=["-Werror"], tag=f"hdr:{header}")
            return ok
        return self.cached(f"hdr:{header}", f)

    # -- functions ---------------------------------------------------------
    def has_func(self, func: str, extra=None) -> bool:
        def f():
            body = (
                "int main(void) {\n"
                f"  void *p = (void *)&{func};\n"
                "  (void)p;\n"
                "  return 0;\n"
                "}\n"
            )
            ok, err = self.compile(body, link=True, extra=extra, tag=f"fn:{func}")
            if not ok and "undefined symbol" not in err and "undefined reference" not in err:
                # some functions are macros; a direct address-of fails to compile.
                body2 = f"int main(void) {{ {func}; return 0; }}\n"
                ok, err = self.compile(body2, link=True, extra=extra, tag=f"fn2:{func}")
            return ok
        return self.cached(f"fn:{func}", f)

    # -- build-config data -------------------------------------------------
    def sizes(self, exprs: dict[str, str]) -> dict[str, int]:
        """Determine sizeof()/alignment of arbitrary expressions without running
        target code: read the values back out of .rodata via llvm-objdump."""
        names = list(exprs)
        arr = "\n".join(f"  (unsigned long)({exprs[n]})," for n in names)
        src = (
            "#include <stdio.h>\n#include <stdlib.h>\n#include <stddef.h>\n"
            "#include <sys/types.h>\n#include <wchar.h>\n#include <pthread.h>\n"
            "#include <stdint.h>\n#include <time.h>\n#include <sys/stat.h>\n"
            "const unsigned long py_probe_values[] __attribute__((used)) = {\n"
            f"{arr}\n"
            "};\n"
        )
        cpath = self._write("sizes.c", src)
        opath = os.path.join(self.workdir, "sizes.o")
        r = self.tc.run(self.tc.cc_args() + ["-c", "-O0", "-o", opath, cpath, "-D_GNU_SOURCE"])
        if r.returncode != 0:
            raise RuntimeError("sizes probe failed:\n" + r.stderr)
        self.count += 1
        out = self.tc.run([os.path.join(self.tc.llvm_bin, "llvm-objdump.exe"),
                           "-s", "-j", ".rodata", opath]).stdout
        data = []
        for line in out.splitlines():
            m = re.match(r"\s*[0-9a-f]+((?:\s+[0-9a-f]{2,8})+)", line)
            if m:
                for tok in m.group(1).split():
                    # llvm-objdump prints 4-byte groups in host endianness order
                    data.extend(int(tok[i:i + 2], 16) for i in range(0, len(tok), 2))
        vals = {}
        for i, n in enumerate(names):
            chunk = bytes(data[i * 8:(i + 1) * 8])
            vals[n] = int.from_bytes(chunk, "little")
            if vals[n] > 1 << 40:
                raise RuntimeError(f"size probe for {n} looks wrong: {vals[n]}")
        return vals
