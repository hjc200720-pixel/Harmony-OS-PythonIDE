#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cross-build CPython 3.12.10 as a static library for HarmonyOS / OpenHarmony.

Why this script exists
----------------------
CPython's native build needs `configure` + `make`, i.e. a working POSIX shell.
In this build host every MSYS2/Cygwin binary dies at startup with

    *** fatal error - couldn't create signal pipe, Win32 error 5

so `sh.exe`, `bash.exe`, `sed.exe`, `patch.exe` and `make` (when it picks up a
POSIX shell) are all unusable, and neither WSL, Cygwin nor busybox is installed.
Rather than give up, this script performs the same job as configure+make in
pure Python:

  * it probes the OHOS sysroot with the NDK clang to synthesise Include/pyconfig.h
  * it decides which stdlib extension modules can be built (static, so they all
    end up inside libpython3.12.a)
  * it generates Modules/config.c (the builtin-module table)
  * it freezes the stdlib bootstrap modules using the *host* Python 3.12.10 --
    this is exactly what CPython itself does for cross builds
    (`Programs/_freeze_module.py`, `Tools/build/deepfreeze.py`)
  * it compiles everything with the NDK clang and archives with llvm-ar

Everything is derived from the real toolchain, so the result is reproducible.

Usage
-----
    python ohos_cpython_build.py --src <cpython-3.12.10 tree> --abi arm64-v8a [--phase ...]
"""
from __future__ import annotations

import argparse
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ohos_probe import Toolchain, Probes  # noqa: E402

# ---------------------------------------------------------------------------
# Defaults (all overridable from the command line / the .ps1 wrapper)
# ---------------------------------------------------------------------------
DEFAULT_WS = r"D:\HuaweiMoveData\Users\HUAWEI\OneDrive\Documents\deepseek-harness\default-workspace"
DEFAULT_NDK = r"D:\DevEco Studio\sdk\default\openharmony\native"
DEFAULT_HOSTPY = r"C:\Users\HUAWEI\AppData\Local\Programs\Python\Python312\python.exe"

ABIS = {
    "arm64-v8a": {"triplet": "aarch64-linux-ohos", "dir": "arm64-v8a"},
    "x86_64": {"triplet": "x86_64-linux-ohos", "dir": "x86_64"},
}

PY_VERSION = "3.12"
PY_FULL_VERSION = "3.12.10"
PY_VER_NODOT = "312"


def log(msg=""):
    print(msg, flush=True)


# ---------------------------------------------------------------------------
# Object lists (mirrored verbatim from CPython's Makefile.pre.in)
# ---------------------------------------------------------------------------
PARSER_OBJS = [
    "Parser/token.c", "Parser/pegen.c", "Parser/pegen_errors.c",
    "Parser/action_helpers.c", "Parser/parser.c", "Parser/string_parser.c",
    "Parser/peg_api.c", "Parser/myreadline.c", "Parser/tokenizer.c",
]

OBJECT_OBJS = [
    "Objects/abstract.c", "Objects/boolobject.c", "Objects/bytes_methods.c",
    "Objects/bytearrayobject.c", "Objects/bytesobject.c", "Objects/call.c",
    "Objects/capsule.c", "Objects/cellobject.c", "Objects/classobject.c",
    "Objects/codeobject.c", "Objects/complexobject.c", "Objects/descrobject.c",
    "Objects/enumobject.c", "Objects/exceptions.c", "Objects/genericaliasobject.c",
    "Objects/genobject.c", "Objects/fileobject.c", "Objects/floatobject.c",
    "Objects/frameobject.c", "Objects/funcobject.c",
    "Objects/interpreteridobject.c", "Objects/iterobject.c", "Objects/listobject.c",
    "Objects/longobject.c", "Objects/dictobject.c", "Objects/odictobject.c",
    "Objects/memoryobject.c", "Objects/methodobject.c", "Objects/moduleobject.c",
    "Objects/namespaceobject.c", "Objects/object.c", "Objects/obmalloc.c",
    "Objects/picklebufobject.c", "Objects/rangeobject.c", "Objects/setobject.c",
    "Objects/sliceobject.c", "Objects/structseq.c", "Objects/tupleobject.c",
    "Objects/typeobject.c", "Objects/typevarobject.c", "Objects/unicodeobject.c",
    "Objects/unicodectype.c", "Objects/unionobject.c", "Objects/weakrefobject.c",
]

PYTHON_OBJS = [
    "Python/_warnings.c", "Python/Python-ast.c", "Python/Python-tokenize.c",
    "Python/asdl.c", "Python/assemble.c", "Python/ast.c", "Python/ast_opt.c",
    "Python/ast_unparse.c", "Python/bltinmodule.c", "Python/ceval.c",
    "Python/codecs.c", "Python/compile.c", "Python/context.c",
    "Python/dynamic_annotations.c", "Python/errors.c", "Python/flowgraph.c",
    "Python/frame.c", "Python/frozenmain.c", "Python/future.c",
    "Python/getargs.c", "Python/getcompiler.c", "Python/getcopyright.c",
    "Python/getplatform.c", "Python/getversion.c", "Python/ceval_gil.c",
    "Python/hamt.c", "Python/hashtable.c", "Python/import.c",
    "Python/importdl.c", "Python/initconfig.c", "Python/instrumentation.c",
    "Python/intrinsics.c", "Python/legacy_tracing.c", "Python/marshal.c",
    "Python/modsupport.c", "Python/mysnprintf.c", "Python/mystrtoul.c",
    "Python/pathconfig.c", "Python/preconfig.c", "Python/pyarena.c",
    "Python/pyctype.c", "Python/pyfpe.c", "Python/pyhash.c",
    "Python/pylifecycle.c", "Python/pymath.c", "Python/pystate.c",
    "Python/pythonrun.c", "Python/pytime.c", "Python/bootstrap_hash.c",
    "Python/specialize.c", "Python/structmember.c", "Python/symtable.c",
    "Python/sysmodule.c", "Python/thread.c", "Python/traceback.c",
    "Python/tracemalloc.c", "Python/getopt.c", "Python/pystrcmp.c",
    "Python/pystrtod.c", "Python/pystrhex.c", "Python/dtoa.c",
    "Python/formatter_unicode.c", "Python/fileutils.c", "Python/suggestions.c",
    "Python/perf_trampoline.c",
    "Python/dynload_shlib.c",          # DYNLOADFILE
]

MODULE_OBJS = ["Modules/config.c", "Modules/main.c", "Modules/gcmodule.c"]
CORE_EXTRA = [
    "Modules/getbuildinfo.c",
    "Modules/getpath.c",
    "Python/frozen.c",
    "Python/deepfreeze/deepfreeze.c",
]

# ---------------------------------------------------------------------------
# Module table: (module, [sources relative to Modules/], extra cflags, extra libs)
# ---------------------------------------------------------------------------
MPDEC_SRCS = [
    "_decimal/libmpdec/basearith.c", "_decimal/libmpdec/constants.c",
    "_decimal/libmpdec/context.c", "_decimal/libmpdec/convolute.c",
    "_decimal/libmpdec/crt.c", "_decimal/libmpdec/difradix2.c",
    "_decimal/libmpdec/fnt.c", "_decimal/libmpdec/fourstep.c",
    "_decimal/libmpdec/io.c", "_decimal/libmpdec/mpalloc.c",
    "_decimal/libmpdec/mpdecimal.c", "_decimal/libmpdec/mpsignal.c",
    "_decimal/libmpdec/numbertheory.c", "_decimal/libmpdec/sixstep.c",
    "_decimal/libmpdec/transpose.c",
]
EXPAT_SRCS = ["expat/xmlparse.c", "expat/xmlrole.c", "expat/xmltok.c"]

HACL_CFLAGS = ["-I@SRC@/Modules/_hacl/include", "-I@SRC@/Modules/_hacl/internal",
               "-D_BSD_SOURCE", "-D_DEFAULT_SOURCE"]

MODULES = [
    # --- Modules/Setup.bootstrap (always static, cannot be shared) ---------
    ("atexit", ["atexitmodule.c"], [], []),
    ("faulthandler", ["faulthandler.c"], [], []),
    ("posix", ["posixmodule.c"], [], []),
    ("_signal", ["signalmodule.c"], [], []),
    ("_tracemalloc", ["_tracemalloc.c"], [], []),
    ("_codecs", ["_codecsmodule.c"], [], []),
    ("_collections", ["_collectionsmodule.c"], [], []),
    ("errno", ["errnomodule.c"], [], []),
    ("_io", ["_io/_iomodule.c", "_io/iobase.c", "_io/fileio.c", "_io/bufferedio.c",
             "_io/bytesio.c", "_io/textio.c", "_io/stringio.c"], ["-I@SRC@/Modules/_io"], []),
    ("itertools", ["itertoolsmodule.c"], [], []),
    ("_sre", ["_sre/sre.c"], [], []),
    ("_thread", ["_threadmodule.c"], [], []),
    ("time", ["timemodule.c"], [], []),
    ("_typing", ["_typingmodule.c"], [], []),
    ("_weakref", ["_weakref.c"], [], []),
    ("_abc", ["_abc.c"], [], []),
    ("_functools", ["_functoolsmodule.c"], [], []),
    ("_locale", ["_localemodule.c"], [], []),
    ("_operator", ["_operator.c"], [], []),
    ("_stat", ["_stat.c"], [], []),
    ("_symtable", ["symtablemodule.c"], [], []),
    ("pwd", ["pwdmodule.c"], [], []),
    # --- always-available stdlib extensions --------------------------------
    ("array", ["arraymodule.c"], [], []),
    ("_asyncio", ["_asynciomodule.c"], [], []),
    ("_bisect", ["_bisectmodule.c"], [], []),
    ("_contextvars", ["_contextvarsmodule.c"], [], []),
    ("_csv", ["_csv.c"], [], []),
    ("_heapq", ["_heapqmodule.c"], [], []),
    ("_json", ["_json.c"], [], []),
    ("_lsprof", ["_lsprof.c", "rotatingtree.c"], [], []),
    ("_opcode", ["_opcode.c"], [], []),
    ("_pickle", ["_pickle.c"], [], []),
    ("_queue", ["_queuemodule.c"], [], []),
    ("_random", ["_randommodule.c"], [], []),
    ("_struct", ["_struct.c"], [], []),
    ("_xxsubinterpreters", ["_xxsubinterpretersmodule.c"], [], []),
    ("_xxinterpchannels", ["_xxinterpchannelsmodule.c"], [], []),
    ("_zoneinfo", ["_zoneinfo.c"], [], []),
    # --- needs libm --------------------------------------------------------
    ("audioop", ["audioop.c"], [], ["-lm"]),
    ("math", ["mathmodule.c"], [], ["-lm"]),
    ("cmath", ["cmathmodule.c"], [], ["-lm"]),
    ("_statistics", ["_statisticsmodule.c"], [], ["-lm"]),
    ("_datetime", ["_datetimemodule.c"], [], ["-lm"]),
    # --- bundled libmpdec --------------------------------------------------
    # libmpdec 的宏组合（踩坑记录）：
    #   CONFIG_64     —— 必须显式给，否则 mpdecimal.h 直接 #error
    #   ANSI          —— libmpdec 只在 UNIVERSAL 模式下自己定义它；不给就会落到
    #                    bits.h / typearith.h 的 "#else #error"，报
    #                    "missing preprocessor definitions" /
    #                    "need platform specific 128 bit multiplication and division"
    #   HAVE_UINT128_T—— aarch64 的 clang 有 __int128，走通用 128 位实现
    ("_decimal", ["_decimal/_decimal.c"] + MPDEC_SRCS,
     ["-DCONFIG_64", "-DANSI", "-DHAVE_UINT128_T",
      "-I@SRC@/Modules/_decimal/libmpdec"], ["-lm"]),
    # --- compression -------------------------------------------------------
    ("binascii", ["binascii.c"], [], []),
    ("zlib", ["zlibmodule.c"], [], ["-lz"]),
    # --- hashlib builtins (bundled HACL*) ----------------------------------
    ("_md5", ["md5module.c", "_hacl/Hacl_Hash_MD5.c"], HACL_CFLAGS, []),
    ("_sha1", ["sha1module.c", "_hacl/Hacl_Hash_SHA1.c"], HACL_CFLAGS, []),
    ("_sha2", ["sha2module.c", "_hacl/Hacl_Hash_SHA2.c"], HACL_CFLAGS, []),
    ("_sha3", ["sha3module.c", "_hacl/Hacl_Hash_SHA3.c"], HACL_CFLAGS, []),
    ("_blake2", ["_blake2/blake2module.c", "_blake2/blake2b_impl.c",
                 "_blake2/blake2s_impl.c"], [], []),
    # --- XML (bundled expat) ----------------------------------------------
    ("pyexpat", ["pyexpat.c"] + EXPAT_SRCS, ["-I@SRC@/Modules/expat"], ["-lm"]),
    ("_elementtree", ["_elementtree.c"], ["-I@SRC@/Modules/expat"], []),
    # --- CJK codecs + unicodedata -----------------------------------------
    ("_codecs_cn", ["cjkcodecs/_codecs_cn.c"], [], []),
    ("_codecs_hk", ["cjkcodecs/_codecs_hk.c"], [], []),
    ("_codecs_iso2022", ["cjkcodecs/_codecs_iso2022.c"], [], []),
    ("_codecs_jp", ["cjkcodecs/_codecs_jp.c"], [], []),
    ("_codecs_kr", ["cjkcodecs/_codecs_kr.c"], [], []),
    ("_codecs_tw", ["cjkcodecs/_codecs_tw.c"], [], []),
    ("_multibytecodec", ["cjkcodecs/multibytecodec.c"], [], []),
    ("unicodedata", ["unicodedata.c"], [], []),
    # --- UNIX-ish ----------------------------------------------------------
    ("fcntl", ["fcntlmodule.c"], [], []),
    ("grp", ["grpmodule.c"], [], []),
    ("mmap", ["mmapmodule.c"], [], []),
    ("_posixsubprocess", ["_posixsubprocess.c"], [], []),
    ("resource", ["resource.c"], [], []),
    ("select", ["selectmodule.c"], [], []),
    ("_socket", ["socketmodule.c"], [], []),
    ("syslog", ["syslogmodule.c"], [], []),
    ("termios", ["termios.c"], [], []),
    # --- multiprocessing ---------------------------------------------------
    ("_posixshmem", ["_multiprocessing/posixshmem.c"],
     ["-I@SRC@/Modules/_multiprocessing"], []),
    ("_multiprocessing", ["_multiprocessing/multiprocessing.c",
                          "_multiprocessing/semaphore.c"],
     ["-I@SRC@/Modules/_multiprocessing"], []),
]

# Modules that configure would try to build but that this sysroot cannot supply.
DISABLED_MODULES = {
    "_bz2": "no bzlib.h / libbz2 in the OHOS sysroot",
    "_lzma": "no lzma.h / liblzma in the OHOS sysroot",
    "_dbm": "no ndbm/gdbm/db library",
    "_gdbm": "no libgdbm",
    "readline": "no readline/editline",
    "_crypt": "no usable crypt()/libcrypt (libcrypt.a is an empty stub)",
    "_ctypes": "no libffi (ffi.h absent)",
    "_curses": "no ncurses/terminfo",
    "_curses_panel": "no ncurses/panel",
    "_sqlite3": "no sqlite3.h",
    "_ssl": "no OpenSSL",
    "_hashlib": "no OpenSSL",
    "_tkinter": "no Tcl/Tk",
    "_uuid": "no libuuid / uuid_create (matches the official OHOS port patch)",
    "nis": "no rpc/rpc.h",
    "ossaudiodev": "no sys/soundcard.h",
    "_scproxy": "macOS only",
    "xxsubtype": "--disable-test-modules",
    "_xxtestfuzz": "--disable-test-modules",
    "_testbuffer": "--disable-test-modules",
    "_testinternalcapi": "--disable-test-modules",
    "_testcapi": "--disable-test-modules",
    "_testclinic": "--disable-test-modules",
    "_testimportmultiple": "--disable-test-modules",
    "_testmultiphase": "--disable-test-modules",
    "_testsinglephase": "--disable-test-modules",
    "_ctypes_test": "--disable-test-modules",
    "xxlimited": "--disable-test-modules",
    "xxlimited_35": "--disable-test-modules",
    "_testexternalinspection": "--disable-test-modules",
    "spwd": "已废弃模块（CPython 3.13 已移除）；OHOS 沙箱里也没有可用的 shadow 数据库接口，"
            "编译 spwdmodule.c 会因 get_spwd_state 未声明而失败",
}

# ---------------------------------------------------------------------------
# pyconfig.h
# ---------------------------------------------------------------------------
# A few configure macros are not named after the function they probe.
FUNCTION_ALIASES = {
    "HAVE_EPOLL": "epoll_create",
}

# Macros decided by non-trivial probes (struct members, compiler features, ...).
# gethostbyname_r 有 6/5/3 参数三种历史形态。OHOS(musl) 用的是 6 参数：
#   int gethostbyname_r(const char *, struct hostent *, char *, size_t,
#                       struct hostent **, int *);
# 因为 netdb.h 声明了这个原型，参数个数不对的调用会直接编译失败，
# 所以按 6 -> 5 -> 3 的顺序试探，第一个编过的就是目标平台的形式。
GHBN_PROBES = [
    ("HAVE_GETHOSTBYNAME_R_6_ARG",
     "#include <netdb.h>\nint main(void){struct hostent he; struct hostent *r; char buf[256]; int e;"
     " (void)gethostbyname_r(\"x\", &he, buf, sizeof buf, &r, &e); return 0;}"),
    ("HAVE_GETHOSTBYNAME_R_5_ARG",
     "#include <netdb.h>\nint main(void){struct hostent he; char buf[256]; int e;"
     " (void)gethostbyname_r(\"x\", &he, buf, sizeof buf, &e); return 0;}"),
    ("HAVE_GETHOSTBYNAME_R_3_ARG",
     "#include <netdb.h>\nint main(void){struct hostent_data d; struct hostent he;"
     " (void)gethostbyname_r(\"x\", &he, &d); return 0;}"),
]

STRUCT_PROBES = {
    # addrinfo.h 用 #ifndef HAVE_ADDRINFO 决定是否自带 struct addrinfo 定义。
    # 驱动的"函数"探针会把 HAVE_ADDRINFO 当成函数 addrinfo() 去链接（必然失败），
    # 于是宏不会被定义，最终和 OHOS netdb.h 里的定义撞车：
    #   Modules/addrinfo.h:127: error: redefinition of 'addrinfo'
    # 因此这里按"结构体"探测，让 socketmodule 用 sysroot 的真实实现。
    "HAVE_ADDRINFO":
        "#include <sys/types.h>\n#include <sys/socket.h>\n#include <netdb.h>\n"
        "int main(void){struct addrinfo a; return (int)sizeof(a.ai_flags);}",
    "HAVE_SOCKADDR_STORAGE":
        "#include <sys/socket.h>\nint main(void){struct sockaddr_storage s; return (int)sizeof(s);}",
    "HAVE_STRUCT_STAT_ST_BLKSIZE": "#include <sys/stat.h>\nint main(void){struct stat s; return (int)s.st_blksize;}",
    "HAVE_STRUCT_STAT_ST_BLOCKS": "#include <sys/stat.h>\nint main(void){struct stat s; return (int)s.st_blocks;}",
    "HAVE_STRUCT_STAT_ST_RDEV": "#include <sys/stat.h>\nint main(void){struct stat s; return (int)s.st_rdev;}",
    "HAVE_STRUCT_STAT_ST_BIRTHTIME": "#include <sys/stat.h>\nint main(void){struct stat s; return (int)s.st_birthtime;}",
    "HAVE_STRUCT_STAT_ST_FLAGS": "#include <sys/stat.h>\nint main(void){struct stat s; return (int)s.st_flags;}",
    "HAVE_STRUCT_STAT_ST_GEN": "#include <sys/stat.h>\nint main(void){struct stat s; return (int)s.st_gen;}",
    "HAVE_STAT_TV_NSEC": "#include <sys/stat.h>\nint main(void){struct stat s; return (int)s.st_atim.tv_nsec;}",
    "HAVE_STAT_TV_NSEC2": "#include <sys/stat.h>\nint main(void){struct stat s; return (int)s.st_atimespec.tv_nsec;}",
    "HAVE_STRUCT_TM_TM_ZONE": "#include <time.h>\nint main(void){struct tm t; return (int)(t.tm_zone != 0);}",
    "HAVE_TM_ZONE": "#include <time.h>\nint main(void){struct tm t; return (int)(t.tm_zone != 0);}",
    "HAVE_TZNAME": "#include <time.h>\nint main(void){return (int)(tzname[0] != 0);}",
    "HAVE_DECL_TZNAME": "#include <time.h>\nint main(void){return (int)(tzname[0] != 0);}",
    "HAVE_ALTZONE": "#include <time.h>\nint main(void){return (int)altzone;}",
    "HAVE_WORKING_TZSET": "#include <time.h>\nint main(void){tzset(); return 0;}",
    "HAVE_STRUCT_PASSWD_PW_GECOS": "#include <pwd.h>\nint main(void){struct passwd p; return (int)(p.pw_gecos != 0);}",
    "HAVE_STRUCT_PASSWD_PW_PASSWD": "#include <pwd.h>\nint main(void){struct passwd p; return (int)(p.pw_passwd != 0);}",
    "HAVE_DIRENT_D_TYPE": "#include <dirent.h>\nint main(void){struct dirent d; return (int)d.d_type;}",
    "HAVE_SIGINFO_T_SI_BAND": "#include <signal.h>\nint main(void){siginfo_t i; return (int)i.si_band;}",
    "HAVE_SOCKADDR_STORAGE": "#include <sys/socket.h>\nint main(void){struct sockaddr_storage s; return (int)sizeof(s);}",
    "HAVE_SOCKADDR_SA_LEN": "#include <sys/socket.h>\nint main(void){struct sockaddr s; return (int)s.sa_len;}",
    "HAVE_SOCKADDR_ALG": "#include <linux/if_alg.h>\nint main(void){struct sockaddr_alg a; return (int)sizeof(a);}",
    "HAVE_ADDRINFO": "#include <sys/socket.h>\n#include <netdb.h>\nint main(void){struct addrinfo a; return (int)sizeof(a);}",
    "HAVE_DEVICE_MACROS": "#include <sys/sysmacros.h>\nint main(void){return (int)(major(1) + minor(1) + makedev(1,2));}",
    "HAVE_MAKEDEV": "#include <sys/types.h>\nint main(void){return (int)makedev(1,2);}",
    "HAVE_HTOLE64": "#include <endian.h>\n#include <stdint.h>\nint main(void){return (int)htole64(1);}",
    "HAVE_GCC_UINT128_T": "int main(void){__uint128_t x = 1; return (int)(x >> 100);}",
    "HAVE_BUILTIN_ATOMIC": "int main(void){int x = 0; __atomic_add_fetch(&x, 1, __ATOMIC_SEQ_CST); return x;}",
    "HAVE_STD_ATOMIC": "#include <stdatomic.h>\nint main(void){atomic_int x = 0; return atomic_load(&x);}",
    "HAVE_LONG_DOUBLE": "int main(void){long double x = 1.0L; return (int)(x / 3.0L);}",
    "HAVE_COMPUTED_GOTOS": (
        "int main(void){static void *tab[] = {&&lbl_a, &&lbl_b}; goto *tab[0];\n"
        " lbl_a: return 0;\n lbl_b: return 1;}"
    ),
    "USE_COMPUTED_GOTOS": (
        "int main(void){static void *tab[] = {&&lbl_a, &&lbl_b}; goto *tab[0];\n"
        " lbl_a: return 0;\n lbl_b: return 1;}"
    ),
    "HAVE_GETRANDOM_SYSCALL": "#include <sys/syscall.h>\n#include <unistd.h>\nint main(void){char b[8]; return (int)syscall(SYS_getrandom, b, 8, 0);}",
    "HAVE_LINUX_CAN_RAW_FD_FRAMES": "#include <linux/can/raw.h>\nint main(void){return CAN_RAW_FD_FRAMES;}",
    "HAVE_LINUX_CAN_RAW_JOIN_FILTERS": "#include <linux/can/raw.h>\nint main(void){return CAN_RAW_JOIN_FILTERS;}",
    "HAVE_EXPLICIT_BZERO": "#include <string.h>\nint main(void){char b[4]; explicit_bzero(b, 4); return 0;}",
    "HAVE_EXPLICIT_MEMSET": "#include <string.h>\nint main(void){char b[4]; explicit_memset(b, 0, 4); return 0;}",
    "HAVE_ALIGNED_REQUIRED": "#error aligned required is an ARM OABI property, never true here",
    "HAVE_BROKEN_MBSTOWCS": "#error not broken on musl",
    "HAVE_BROKEN_NICE": "#error not broken on musl",
    "HAVE_BROKEN_PIPE_BUF": "#error not broken on musl",
    "HAVE_BROKEN_POLL": "#error not broken on musl",
    "HAVE_BROKEN_POSIX_SEMAPHORES": "#error not broken on musl",
    "HAVE_BROKEN_PTHREAD_SIGMASK": "#error not broken on musl",
    "HAVE_BROKEN_SEM_GETVALUE": "#error not broken on musl",
    "HAVE_BROKEN_UNSETENV": "#error not broken on musl",
    "HAVE_GLIBC_MEMMOVE_BUG": "#error glibc-only bug, musl unaffected",
    "HAVE_IPA_PURE_CONST_BUG": "#error not applicable",
    "HAVE_NON_UNICODE_WCHAR_T_REPRESENTATION": "#error wchar_t is UCS-4 on this target",
    "HAVE_LARGEFILE_SUPPORT": "#error handled via _FILE_OFFSET_BITS=64",
    "HAVE_GCC_ASM_FOR_X64": "#error x86-64 only",
    "HAVE_GCC_ASM_FOR_X87": "#error x86 only",
    "HAVE_GCC_ASM_FOR_MC68881": "#error m68k only",
    "HAVE_FFI_CLOSURE_ALLOC": "#error libffi not available",
    "HAVE_FFI_PREP_CIF_VAR": "#error libffi not available",
    "HAVE_FFI_PREP_CLOSURE_LOC": "#error libffi not available",
    "HAVE_LIBB2": "#error libb2 not available",
    "HAVE_LIBDB": "#error libdb not available",
    "HAVE_LIBSQLITE3": "#error sqlite3 not available",
    "HAVE_LIBIEEE": "#error libieee not available",
    "HAVE_LIBDLD": "#error libdld not available",
    "HAVE_LIBSENDFILE": "#error sendfile lives in libc on musl",
    "HAVE_LIBRESOLV": "#error resolver lives in libc on musl",
    "HAVE_LIBUTIL": "#error not available",
    "HAVE_DYLD_SHARED_CACHE_CONTAINS_PATH": "#error macOS only",
    "HAVE_PTHREAD_DESTRUCTOR": "#error not available",
    "HAVE_PTHREAD_INIT": "#error not available",
    "HAVE_PTHREAD_STUBS": "#error real pthreads are present",
    "HAVE_DEV_PTC": "#error no /dev/ptc",
    "HAVE_DEV_PTMX": "#error no /dev/ptmx probe needed; OHOS has no pty devices for apps",
    "HAVE_LOGIN_TTY": "#error no login_tty",
    "HAVE_RTPSPAWN": "#error not available",
    "HAVE_SIGRELSE": "#error not available",
    "HAVE_PLOCK": "#error SunOS only",
    "HAVE_CHFLAGS": "#error BSD only",
    "HAVE_LCHFLAGS": "#error BSD only",
    "HAVE_LCHMOD": "#error BSD only",
    "HAVE_STRLCPY": "#error BSD only",
    "HAVE_FTIME": "#error BSD only",
    "HAVE_GETWD": "#error removed from musl",
    "HAVE_PTHREAD_SIGMASK": "#error not available",
    "HAVE_PTHREAD_KILL": "#error not available",
    "HAVE_AUDIOOP": "#error removed in 3.13; audioop is a real extension module",
}
# Macros whose values are forced (platform identity, build options, sizes).
def static_defines(triplet: str, soabi: str, abiflags: str) -> dict:
    d = {
        "PACKAGE_NAME": '"python"',
        "PACKAGE_TARNAME": '"python"',
        "PACKAGE_VERSION": f'"{PY_FULL_VERSION}"',
        "PACKAGE_STRING": f'"python {PY_FULL_VERSION}"',
        "PACKAGE_BUGREPORT": '"https://github.com/python/cpython/issues/"',
        "PACKAGE_URL": '""',
        # macOS framework builds: always defined (empty here)
        "_PYTHONFRAMEWORK": '""',
        # system-extension macros (what AC_USE_SYSTEM_EXTENSIONS + CPython's
        # Linux branch produce)
        "_GNU_SOURCE": "1",
        "_REENTRANT": "1",
        "_POSIX_C_SOURCE": "200809L",
        "_XOPEN_SOURCE": "700",
        "_LARGEFILE_SOURCE": "1",
        "_FILE_OFFSET_BITS": "64",
        "STDC_HEADERS": "1",
        "SYS_SELECT_WITH_SYS_TIME": "1",
        "DOUBLE_IS_LITTLE_ENDIAN_IEEE754": "1",
        "HAVE_DYNAMIC_LOADING": "1",
        "HAVE_LIBDL": "1",
        "HAVE_SSIZE_T": "1",
        "HAVE_PROTOTYPES": "1",
        "HAVE_USABLE_WCHAR_T": "1",
        "HAVE_LONG_DOUBLE": "1",
        "PY_COERCE_C_LOCALE": "1",
        "PYLONG_BITS_IN_DIGIT": "30",
        "PY_SUPPORT_TIER": "3",
        "WITH_DOC_STRINGS": "1",
        "WITH_FREELISTS": "1",
        "WITH_PYMALLOC": "1",
        "WITH_DECIMAL_CONTEXTVAR": "1",
        "PY_BUILTIN_HASHLIB_HASHES": '"md5,sha1,sha2,sha3,blake2"',
        "ABIFLAGS": f'"{abiflags}"',
        "SOABI": f'"{soabi}"',
        "ALT_SOABI": f'"{soabi}"',
        "EXT_SUFFIX": f'".{soabi}.so"',
        "PLATFORM_TRIPLET": f'"{triplet}"',
        "MULTIARCH": f'"{triplet}"',
    }
    # x86-64 keeps its x87 control word in order to get correctly rounded
    # `long` -> `double` conversions; CPython guards that with
    # HAVE_GCC_ASM_FOR_X64.  (The 32-bit x87 variant is not needed on x86-64.)
    if triplet.startswith("x86_64"):
        d["HAVE_GCC_ASM_FOR_X64"] = "1"
    return d


# ---------------------------------------------------------------------------
class Builder:
    def __init__(self, args):
        self.args = args
        self.src = os.path.abspath(args.src)
        self.ndk = args.ndk
        self.hostpy = args.host_python
        abi = ABIS[args.abi]
        self.abi = args.abi
        self.triplet = abi["triplet"]
        self.tc = Toolchain(self.ndk, self.triplet)
        self.work = os.path.join(args.work, args.abi)
        os.makedirs(self.work, exist_ok=True)
        self.probes = Probes(self.tc, os.path.join(self.work, "probe"))
        self.defines: dict[str, str] = {}
        self.enabled_modules = []
        self.jobs = args.jobs or max(1, (os.cpu_count() or 4))
        self.failures = []

    # -- helpers -----------------------------------------------------------
    def srcp(self, *parts) -> str:
        return os.path.join(self.src, *parts)

    def obj_for(self, rel_c_source: str) -> str:
        """对象文件按 ABI 隔离存放。

        历史教训：早期版本把 .o 直接写进源码树（`<src>/Objects/foo.o`），两个 ABI 共用同一批
        路径。连续构建 arm64-v8a 与 x86_64 时后者会覆盖前者，而 `--skip-existing` 更会把另一个
        ABI 的对象误判成"已编译"，最终产出缺符号的残缺静态库（实测：x86_64 的
        libpython3.12.a 只剩 25 个对象、缺 PyInit_posix，HAP 链接失败，现象却像"代码写错了"）。

        现在对象统一放在 `<work>/<abi>/obj/…`（`self.work` 已按 ABI 分目录），源码树保持只读。
        """
        rel = os.path.splitext(rel_c_source)[0]
        return os.path.join(self.work, "obj", *rel.split("/")) + ".o"

    def host(self, *cmd, cwd=None, env=None):
        return subprocess.run(list(cmd), capture_output=True, text=True,
                              errors="replace", cwd=cwd, env=env)

    # ==================================================================
    # PHASE 1: Include/pyconfig.h
    # ==================================================================
    def phase_config(self):
        log("== [1/5] generating Include/pyconfig.h by probing the OHOS sysroot ==")
        t0 = time.time()
        defines = static_defines(self.triplet, f"cpython-{PY_VER_NODOT}-{self.triplet}", "")

        # ---- sizes / alignments (read back from .rodata) -------------------
        sizes = self.probes.sizes({
            "SIZEOF_INT": "sizeof(int)",
            "SIZEOF_LONG": "sizeof(long)",
            "SIZEOF_SHORT": "sizeof(short)",
            "SIZEOF_VOID_P": "sizeof(void *)",
            "SIZEOF_SIZE_T": "sizeof(size_t)",
            "SIZEOF_OFF_T": "sizeof(off_t)",
            "SIZEOF_TIME_T": "sizeof(time_t)",
            "SIZEOF_LONG_LONG": "sizeof(long long)",
            "SIZEOF_FLOAT": "sizeof(float)",
            "SIZEOF_DOUBLE": "sizeof(double)",
            "SIZEOF_LONG_DOUBLE": "sizeof(long double)",
            "SIZEOF_WCHAR_T": "sizeof(wchar_t)",
            "SIZEOF_PID_T": "sizeof(pid_t)",
            "SIZEOF_FPOS_T": "sizeof(fpos_t)",
            "SIZEOF_PTHREAD_T": "sizeof(pthread_t)",
            "SIZEOF_PTHREAD_KEY_T": "sizeof(pthread_key_t)",
            "SIZEOF_UINTPTR_T": "sizeof(uintptr_t)",
            "ALIGNOF_LONG": "_Alignof(long)",
            "ALIGNOF_SIZE_T": "_Alignof(size_t)",
            "ALIGNOF_MAX_ALIGN_T": "_Alignof(max_align_t)",
            "SIZEOF__BOOL": "sizeof(_Bool)",
        })
        defines.update({k: str(v) for k, v in sizes.items()})

        # ---- the full macro universe from pyconfig.h.in --------------------
        in_path = self.srcp("pyconfig.h.in")
        template = open(in_path, encoding="utf-8", errors="replace").read()
        all_macros = re.findall(r"^#undef\s+(\w+)", template, re.M)
        have = [m for m in all_macros if m.startswith("HAVE_")]
        headers = [m for m in have if m.endswith("_H")]
        decls = [m for m in have if m.startswith("HAVE_DECL_")]
        structs = [m for m in all_macros if m in STRUCT_PROBES]
        funcs = [m for m in have
                 if m not in headers and m not in decls and m not in structs]

        # ---- headers -------------------------------------------------------
        bad_headers = 0
        for m in headers:
            hdr = macro_to_header(m)
            if hdr and self.probes.has_header(hdr):
                defines[m] = "1"
            else:
                bad_headers += 1
        log(f"   headers : {len(headers) - bad_headers}/{len(headers)} present")

        # ---- AC_CHECK_DECLS ------------------------------------------------
        for m in decls:
            if m.startswith("HAVE_DECL_RTLD_"):
                flag = m[len("HAVE_DECL_"):]
                body = f"#include <dlfcn.h>\nint main(void){{int x = {flag}; return x == 0;}}"
                if self.probes.compile(body, includes=False)[0]:
                    defines[m] = "1"
        if "HAVE_DECL_TZNAME" in decls:
            body = "#include <time.h>\nint main(void){return (int)(tzname[0] != 0);}"
            if self.probes.compile(body, includes=False)[0]:
                defines["HAVE_DECL_TZNAME"] = "1"

        # ---- structured / compiler probes ---------------------------------
        for m in structs:
            body = STRUCT_PROBES[m]
            if body.startswith("#error"):
                continue
            if self.probes.compile(body, includes=False, tag=f"struct:{m}")[0]:
                defines[m] = "1"

        # ---- plain functions (link probe with the usual system libs) -------
        link_libs = ["-lm", "-ldl", "-lpthread", "-lrt", "-lresolv", "-lutil"]
        missing = []
        for m in funcs:
            # a few macros are named after a related-but-different function
            fn = FUNCTION_ALIASES.get(m, m[len("HAVE_"):].lower())
            if not re.fullmatch(r"[a-z_][a-z0-9_]*", fn):
                continue
            if self.probes.has_func(fn, extra=link_libs):
                defines[m] = "1"
            else:
                missing.append(m)

        # HAVE_LIBINTL_H exists in the OHOS sysroot, but libintl is not there;
        # configure only records it when gettext() actually links.
        if "HAVE_LIBINTL_H" in defines and not self.probes.has_func("gettext", extra=link_libs):
            del defines["HAVE_LIBINTL_H"]
        log(f"   functions: {len(funcs) - len(missing)}/{len(funcs)} linkable")
        log(f"   notably absent: {', '.join(sorted(missing))[:0] or ''}"
            + ", ".join(sorted(x[5:].lower() for x in missing)[:18]))

        # ---- _POSIX_THREADS: configure defines it only when <unistd.h> does not
        if self.probes.compile("#include <unistd.h>\n#ifdef _POSIX_THREADS\nOK\n#endif\n",
                               includes=False, extra=["-E"]) [0]:
            pt = subprocess.run(
                self.tc.cc_args() + ["-E", "-dM", "-x", "c", "-"],
                input="#include <unistd.h>\n", capture_output=True, text=True,
                errors="replace")
            if "#define _POSIX_THREADS" not in pt.stdout:
                defines["_POSIX_THREADS"] = "1"

        # ---- 强制纠正：符号能链接、但头文件里没有声明的宏必须关掉 ----------
        # OHOS 的 sysroot 里 libc 有 gettext 符号，却没有 <libintl.h>；
        # 若据此定义 HAVE_GETTEXT，Modules/_localemodule.c 会因为隐式声明
        # （int gettext(...) 被当成返回 int）而编译失败。CPython 的 configure
        # 是靠 AC_CHECK_HEADERS + AC_CHECK_LIB 双重判断的，这里补上同样的保守处理。
        for forced_off in ("HAVE_GETTEXT", "HAVE_DGETTEXT", "HAVE_BIND_TEXTDOMAIN_CODESET",
                           "HAVE_LIBINTL_H",
                           # 探针是链着 sysroot 里的**静态** libc.a 做的，那个里面有
                           # explicit_bzero；但设备上的动态 libc.so 并不导出它，
                           # 于是 Modules/_blake2 会留下未定义符号。
                           # 关掉后 blake2 走 memset 兜底实现。
                           "HAVE_EXPLICIT_BZERO", "HAVE_EXPLICIT_MEMSET"):
            if forced_off in defines:
                del defines[forced_off]

        # ---- statvfs / fstatvfs 必须成对 ----------------------------------
        # posixmodule.c 里 os.statvfs 的调用点由 HAVE_STATVFS && HAVE_SYS_STATVFS_H 守护，
        # 而 _pystatvfs_fromstructstatvfs 的**定义**由 HAVE_FSTATVFS 守护。
        # 只探到前者时会因隐式声明报：
        #   posixmodule.c: incompatible integer to pointer conversion returning 'int'
        # （x86_64 上实测踩到；arm64 上两个宏都探到了所以没暴露。）
        if "HAVE_STATVFS" in defines and "HAVE_FSTATVFS" not in defines:
            defines["HAVE_FSTATVFS"] = "1"

        # ---- gethostbyname_r 的签名形态 -----------------------------------
        # configure 靠"逐个编译试探"确定是 3/5/6 参数版本；驱动的通用函数探针会把
        # HAVE_GETHOSTBYNAME_R_3_ARG 当成函数名去链接，必然失败，结果一个宏都没定义，
        # socketmodule.c 就会落进 3 参数分支却引用不到 data 变量。
        for macro, body in GHBN_PROBES:
            if self.probes.compile(body, includes=False, tag=f"ghbn:{macro}")[0]:
                defines[macro] = "1"
                break

        # ---- render pyconfig.h --------------------------------------------
        # NOTE: pyconfig.h.in already carries its own `Py_PYCONFIG_H` guard --
        # do not wrap it in another one, or the whole file gets skipped.
        out = []
        out.append("/* pyconfig.h -- generated by ohos_cpython_build.py for "
                   f"{self.triplet} */")
        out.append("/* Source: CPython %s pyconfig.h.in, probed with the OpenHarmony "
                   "NDK clang. */" % PY_FULL_VERSION)
        for line in template.split("\n"):
            m = re.match(r"^#undef\s+(\w+)\s*$", line)
            if m:
                name = m.group(1)
                if name in defines:
                    val = defines[name]
                    out.append(f"#define {name} {val}".rstrip())
                else:
                    out.append(f"/* #undef {name} */")
            else:
                out.append(line)
        out.append("")
        text = "\n".join(out)
        target = self.srcp("Include", "pyconfig.h")
        # Atomic write: several ABI builds may share one source tree, and a
        # half-written pyconfig.h makes clang pick up a bogus `HAVE_*` set
        # (symptom seen: "fatal error: 'sys/termio.h' file not found").
        tmp = target + ".tmp"
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        os.replace(tmp, target)
        # Keep an ABI-private copy too; common_cflags() puts self.work first on
        # the include path, so each ABI always reads *its own* pyconfig.h even
        # if two builds run concurrently against the same source tree.
        with open(os.path.join(self.work, "pyconfig.h"), "w",
                  encoding="utf-8", newline="\n") as f:
            f.write(text)
        self.defines = defines
        defined = len(defines)
        log(f"   -> {target} ({defined} macros defined, {len(all_macros) - defined} left undefined)")
        log(f"   {self.probes.count} compiler probes in {time.time() - t0:.0f}s")
        return target

    # ==================================================================
    # PHASE 2: Modules/config.c + module list
    # ==================================================================
    def resolve_modules(self):
        """Decide which stdlib extension modules this sysroot can build."""
        if self.enabled_modules:
            return
        have_zlib = self.probes.has_header("zlib.h")
        self.enabled_modules = []
        for name, srcs, cflags, libs in MODULES:
            if name == "zlib" and not have_zlib:
                continue
            self.enabled_modules.append((name, srcs, cflags, libs))

    def phase_modules(self):
        log("== [2/5] generating Modules/config.c and the builtin module table ==")
        self.resolve_modules()
        names = [m[0] for m in self.enabled_modules]
        lines = []
        lines.append("/* Module configuration -- generated by ohos_cpython_build.py */")
        lines.append('#include "Python.h"')
        lines.append("")
        lines.append("#ifdef __cplusplus")
        lines.append('extern "C" {')
        lines.append("#endif")
        lines.append("")
        lines.append("/* -- ADDMODULE MARKER 1 -- */")
        lines.append("")
        for n in names:
            lines.append(f"extern PyObject* PyInit_{n}(void);")
        lines.append("")
        lines.append("struct _inittab _PyImport_Inittab[] = {")
        lines.append("")
        lines.append("/* -- ADDMODULE MARKER 2 -- */")
        for n in names:
            lines.append(f'    {{"{n}", PyInit_{n}}},')
        lines.append("")
        lines.append("    /* These entries are here for sys.builtin_module_names */")
        lines.append('    {"builtins", NULL},')
        lines.append('    {"sys", NULL},')
        lines.append('    {"_imp", PyInit__imp},')
        lines.append('    {"_ast", PyInit__ast},')
        lines.append('    {"_tokenize", PyInit__tokenize},')
        lines.append('    {"gc", PyInit_gc},')
        lines.append('    {"_warnings", _PyWarnings_Init},')
        lines.append('    {"_string", PyInit__string},')
        lines.append('    {"marshal", PyMarshal_Init},')
        lines.append("")
        lines.append("    /* Sentinel */")
        lines.append("    {0, 0}")
        lines.append("};")
        lines.append("")
        lines.append("#ifdef __cplusplus")
        lines.append("}")
        lines.append("#endif")
        # marshal/_imp/_ast/_tokenize/gc/_warnings/_string need extern decls
        hdr = []
        hdr.append("extern PyObject* PyMarshal_Init(void);")
        hdr.append("extern PyObject* PyInit__imp(void);")
        hdr.append("extern PyObject* PyInit_gc(void);")
        hdr.append("extern PyObject* PyInit__ast(void);")
        hdr.append("extern PyObject* PyInit__tokenize(void);")
        hdr.append("extern PyObject* _PyWarnings_Init(void);")
        hdr.append("extern PyObject* PyInit__string(void);")
        text = "\n".join(lines).replace(
            "/* -- ADDMODULE MARKER 1 -- */",
            "/* -- ADDMODULE MARKER 1 -- */\n" + "\n".join(hdr))
        with open(self.srcp("Modules", "config.c"), "w", encoding="utf-8",
                  newline="\n") as f:
            f.write(text)
        # ABI-private copy: compiled instead of the shared source-tree file, so
        # concurrent aarch64/x86_64 builds cannot clobber each other's inittab.
        with open(os.path.join(self.work, "config.c"), "w", encoding="utf-8",
                  newline="\n") as f:
            f.write(text)
        with open(self.srcp("Modules", "Setup.local"), "w", encoding="utf-8",
                  newline="\n") as f:
            f.write("# generated by ohos_cpython_build.py\n")
        log(f"   {len(names)} builtin modules: {', '.join(names)}")
        log(f"   disabled: {len(DISABLED_MODULES)} (see DISABLED_MODULES for reasons)")

    # ==================================================================
    # PHASE 3: frozen modules (host Python, exactly like a CPython cross build)
    # ==================================================================
    def phase_frozen(self):
        log("== [3/5] freezing stdlib bootstrap modules with the host Python ==")
        frozen = [
            ("getpath", "Modules/getpath.py"),
            ("importlib._bootstrap", "Lib/importlib/_bootstrap.py"),
            ("importlib._bootstrap_external", "Lib/importlib/_bootstrap_external.py"),
            ("zipimport", "Lib/zipimport.py"),
            ("abc", "Lib/abc.py"),
            ("codecs", "Lib/codecs.py"),
            ("io", "Lib/io.py"),
            ("_collections_abc", "Lib/_collections_abc.py"),
            ("_sitebuiltins", "Lib/_sitebuiltins.py"),
            ("genericpath", "Lib/genericpath.py"),
            ("ntpath", "Lib/ntpath.py"),
            ("posixpath", "Lib/posixpath.py"),
            ("os", "Lib/os.py"),
            ("site", "Lib/site.py"),
            ("stat", "Lib/stat.py"),
            ("importlib.util", "Lib/importlib/util.py"),
            ("importlib.machinery", "Lib/importlib/machinery.py"),
            ("runpy", "Lib/runpy.py"),
            ("__hello__", "Lib/__hello__.py"),
            ("__phello__", "Lib/__phello__/__init__.py"),
            ("__phello__.ham", "Lib/__phello__/ham/__init__.py"),
            ("__phello__.ham.eggs", "Lib/__phello__/ham/eggs.py"),
            ("__phello__.spam", "Lib/__phello__/spam.py"),
            ("frozen_only", "Tools/freeze/flag.py"),
        ]
        freezer = self.srcp("Programs", "_freeze_module.py")
        os.makedirs(self.srcp("Python", "frozen_modules"), exist_ok=True)
        for name, relsrc in frozen:
            outp = self.srcp("Python", "frozen_modules", name + ".h")
            r = self.host(self.hostpy, freezer, name, self.srcp(*relsrc.split("/")), outp)
            if r.returncode != 0:
                log(f"   FAIL freeze {name}: {r.stderr.strip()[:400]}")
                raise SystemExit(1)
        log(f"   {len(frozen)} frozen headers written to Python/frozen_modules/")

        # deepfreeze.c
        args = [self.hostpy, self.srcp("Tools", "build", "deepfreeze.py")]
        for name, _ in frozen:
            if name == "getpath":
                continue
            args.append(f"Python/frozen_modules/{name}.h:{name}")
        args += ["-o", "Python/deepfreeze/deepfreeze.c"]
        os.makedirs(self.srcp("Python", "deepfreeze"), exist_ok=True)
        r = self.host(*args, cwd=self.src)
        if r.returncode != 0:
            log("   FAIL deepfreeze:\n" + (r.stderr or "")[-2000:])
            raise SystemExit(1)
        log("   Python/deepfreeze/deepfreeze.c generated")

    # ==================================================================
    # PHASE 4: compile
    # ==================================================================
    def module_srcs(self):
        """Expand the module table into a list of compile jobs."""
        self.resolve_modules()
        jobs = []
        for name, srcs, cflags, libs in self.enabled_modules:
            for s in srcs:
                rel = "Modules/" + s
                jobs.append({
                    "src": rel,
                    "out": self.obj_for(rel),
                    "cflags": [c.replace("@SRC@", self.src) for c in cflags],
                    "libs": libs,
                    "kind": "builtin",
                })
        return jobs

    def common_cflags(self, kind):
        f = [
            "-std=c11",
            "-O2",
            "-g",
            "-fwrapv",
            "-fno-strict-aliasing",
            "-DNDEBUG",
            # 必须编成位置无关代码：libpython3.12.a 是要整库链接进 libpythonbridge.so 的，
            # 漏了 -fPIC 会在 HAP 链接阶段报
            #   relocation R_AARCH64_ADR_PREL_PG_HI21 cannot be used against symbol ...;
            #   recompile with -fPIC
            "-fPIC",
            "-D_GNU_SOURCE",
            "-D_FILE_OFFSET_BITS=64",
            "-D_LARGEFILE_SOURCE",
            "-Wall",
            "-Wno-unused-result",
            "-Wno-unused-parameter",
            "-Wno-missing-field-initializers",
            "-Wno-sign-compare",
            "-Wno-unreachable-code",
            "-Wno-cast-function-type",
            "-Wno-incompatible-function-pointer-types",
            "-Wno-deprecated-declarations",
            "-Wno-unknown-warning-option",
            # self.work holds this ABI's private pyconfig.h / config.c, so it
            # must come first: two ABI builds can then share one source tree.
            f"-I{self.work}",
            f"-I{self.srcp('Include', 'internal')}",
            f"-I{self.srcp('Include')}",
            f"-I{self.src}",
        ]
        if kind == "core":
            f.append("-DPy_BUILD_CORE")
        elif kind == "builtin":
            f.append("-DPy_BUILD_CORE_BUILTIN")
        return f

    def per_file_flags(self, rel):
        """Extra flags the CPython Makefile applies to specific translation units."""
        if rel == "Python/dynload_shlib.c":
            return [f'-DSOABI="cpython-{PY_VER_NODOT}-{self.triplet}"']
        if rel == "Python/sysmodule.c":
            return ['-DABIFLAGS=""', f'-DMULTIARCH="{self.triplet}"',
                    '-DPYTHONFRAMEWORK=""']
        if rel == "Modules/getpath.c":
            return [
                '-DPYTHONPATH=""',
                '-DPREFIX="/usr"',
                '-DEXEC_PREFIX="/usr"',
                f'-DVERSION="{PY_VERSION}"',
                '-DVPATH=""',
                '-DPLATLIBDIR="lib"',
                '-DPYTHONFRAMEWORK=""',
            ]
        if rel == "Modules/getbuildinfo.c":
            return ['-DGITVERSION="CPython-3.12.10-OHOS"']
        return []

    def phase_compile(self):
        # make this phase usable on its own (each --phase call is a new process)
        pyconfig = self.srcp("Include", "pyconfig.h")
        stale = True
        if os.path.exists(pyconfig):
            try:
                head = open(pyconfig, encoding="utf-8", errors="replace").read(400)
            except OSError:
                head = ""
            # phase_config 会在文件头写明 triplet；不一致说明这份 pyconfig.h 是给另一个
            # ABI 生成的（两个 ABI 共用源码树里的这一个文件），必须重新探测，
            # 否则会用错误的目标配置去编译，产出看似正常实则 ABI 不匹配的对象。
            stale = f"for {self.triplet}" not in head
            if stale:
                log(f"!! Include/pyconfig.h 不是给 {self.triplet} 生成的 -> 重新探测")
        if stale:
            self.phase_config()
        if not os.path.exists(self.srcp("Python", "frozen_modules", "importlib._bootstrap.h")):
            self.phase_frozen()
        if not os.path.exists(self.srcp("Modules", "config.c")):
            self.phase_modules()
        log(f"== [4/5] compiling with {os.path.basename(self.tc.clang)} "
            f"(-target {self.triplet}), jobs={self.jobs} ==")
        jobs = []
        for rel in PARSER_OBJS + OBJECT_OBJS + PYTHON_OBJS + MODULE_OBJS + CORE_EXTRA:
            jobs.append({"src": rel, "out": self.obj_for(rel), "cflags": [],
                         "libs": [], "kind": "core"})
        jobs += self.module_srcs()

        # de-duplicate (deepfreeze.c / config.c appear once)
        seen = {}
        for j in jobs:
            seen[j["out"]] = j
        jobs = list(seen.values())

        todo = [j for j in jobs if not (self.args.skip_existing and os.path.exists(j["out"]))]
        if self.args.only:
            todo = [j for j in todo if any(p in j["src"] for p in self.args.only)]
        log(f"   {len(jobs)} objects total, {len(todo)} to build")

        t0 = time.time()
        done = 0
        fails = []

        def build(j):
            srcpath = self.srcp(*j["src"].split("/"))
            # prefer this ABI's private copies of the generated sources
            priv = os.path.join(self.work, os.path.basename(j["src"]))
            if j["src"] in ("Modules/config.c",) and os.path.exists(priv):
                srcpath = priv
            args = self.tc.cc_args() + ["-c"] + self.common_cflags(j["kind"]) \
                + j["cflags"] + self.per_file_flags(j["src"]) \
                + ["-o", j["out"], srcpath]
            os.makedirs(os.path.dirname(j["out"]), exist_ok=True)
            r = subprocess.run(args, capture_output=True, text=True, errors="replace")
            return j, r

        with concurrent.futures.ThreadPoolExecutor(max_workers=self.jobs) as ex:
            for j, r in ex.map(build, todo):
                done += 1
                if r.returncode != 0:
                    fails.append((j["src"], r.stderr))
                    log(f"   FAIL {j['src']}")
                elif r.stderr.strip():
                    warn = r.stderr.strip()
                    if "implicit-function-declaration" in warn or "error" in warn:
                        log(f"   warn {j['src']}: {warn.splitlines()[0][:160]}")
                if done % 25 == 0:
                    log(f"   ... {done}/{len(todo)} ({time.time() - t0:.0f}s)")

        log(f"   compiled {len(todo) - len(fails)}/{len(todo)} in {time.time() - t0:.0f}s")
        if fails:
            log(f"\n   === {len(fails)} failures ===")
            for src, err in fails[: self.args.max_errors]:
                log(f"\n   --- {src} ---")
                for line in err.strip().splitlines()[: self.args.error_lines]:
                    log("     " + line[:240])
            self.failures = fails
            if not self.args.keep_going:
                raise SystemExit(f"{len(fails)} compilation failures")

    # ==================================================================
    # PHASE 5: archive
    # ==================================================================
    def phase_archive(self):
        out_dir = self.args.outdir
        os.makedirs(out_dir, exist_ok=True)
        out_lib = os.path.join(out_dir, "libpython3.12.a")
        log(f"== [5/5] archiving -> {out_lib} ==")
        self.resolve_modules()
        objs = []
        for rel in PARSER_OBJS + OBJECT_OBJS + PYTHON_OBJS + MODULE_OBJS + CORE_EXTRA:
            objs.append(self.obj_for(rel))
        for name, srcs, cflags, libs in self.enabled_modules:
            for s in srcs:
                objs.append(self.obj_for("Modules/" + s))
        objs = [o for o in objs if os.path.exists(o)]
        missing = len(objs)
        # ---- integrity gate -------------------------------------------------
        # A partial archive is worse than no archive: it looks fine, links, and
        # then fails at runtime with a missing builtin module.  Never emit one
        # silently -- `--keep-going` only means "report all errors", not
        # "ship what compiled".
        expected = []
        for rel in PARSER_OBJS + OBJECT_OBJS + PYTHON_OBJS + MODULE_OBJS + CORE_EXTRA:
            expected.append(self.obj_for(rel))
        for name, srcs, cflags, libs in self.enabled_modules:
            for s in srcs:
                expected.append(self.obj_for("Modules/" + s))
        absent = [o for o in expected if not os.path.exists(o)]
        if absent:
            log(f"   !! {len(absent)}/{len(expected)} expected objects are MISSING; "
                f"refusing to write a partial archive")
            for o in absent[:20]:
                log("      " + os.path.relpath(o, self.src))
            if len(absent) > 20:
                log(f"      ... and {len(absent) - 20} more")
            if not self.args.allow_partial:
                raise SystemExit(
                    f"archive aborted: {len(absent)} of {len(expected)} objects were "
                    f"not built (re-run --phase compile; see its failure list)")
        # ---- architecture gate ---------------------------------------------
        # Objects live next to the sources, so an arm64 and an x86_64 build of
        # the same tree overwrite each other.  Never label a library with an
        # ABI it does not contain.  NOTE: this check must run BEFORE the old
        # output is deleted, otherwise a failed check destroys a good library.
        want_machine = {"aarch64": "AArch64", "x86_64": "X86-64"}.get(
            self.triplet.split("-")[0], None)
        probe_src = objs[0]
        tmpdir = os.path.join(self.work, "archcheck")
        os.makedirs(tmpdir, exist_ok=True)
        r = self.host(os.path.join(self.tc.llvm_bin, "llvm-objdump.exe"),
                      "-f", probe_src)
        if want_machine and ("file format elf64-" not in r.stdout.lower()
                             and "elf64" not in r.stdout.lower()):
            raise SystemExit(f"archive aborted: {probe_src} is not ELF64:\n{r.stdout[:400]}")
        if want_machine:
            r2 = self.host(os.path.join(self.tc.llvm_bin, "llvm-readelf.exe"),
                           "-h", probe_src)
            is_aarch = "AArch64" in r2.stdout
            is_x86 = ("X86-64" in r2.stdout) or ("Advanced Micro Devices X86-64" in r2.stdout)
            ok = (want_machine == "AArch64" and is_aarch) or \
                 (want_machine == "X86-64" and is_x86)
            if not ok:
                raise SystemExit(
                    f"archive aborted: {os.path.relpath(probe_src, self.src)} is not "
                    f"{want_machine} -- re-run --phase compile for --abi {self.abi} "
                    f"(stale objects from another ABI)")
            log(f"   arch check: {want_machine} OK ({os.path.basename(probe_src)})")
        # All gates passed -- only now is it safe to drop the previous archive
        # (llvm-ar 'r' would otherwise keep stale members from an older build).
        if os.path.exists(out_lib):
            os.remove(out_lib)
        rsp = os.path.join(self.work, "objects.rsp")
        with open(rsp, "w", encoding="utf-8") as f:
            f.write("\n".join(objs))
        r = self.host(self.tc.ar, "rcs", out_lib, "@" + rsp)
        if r.returncode != 0:
            log("   llvm-ar failed:\n" + (r.stderr or "")[:3000])
            raise SystemExit(1)
        size = os.path.getsize(out_lib)
        log(f"   {missing} objects -> {size:,} bytes ({size/1048576:.1f} MiB)")
        return out_lib


def macro_to_header(macro: str):
    """HAVE_SYS_RANDOM_H -> sys/random.h"""
    body = macro[len("HAVE_"):]
    if not body.endswith("_H"):
        return None
    stem = body[:-2]
    if not stem:
        return None
    return stem.lower().replace("_", "/") + ".h"


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True, help="CPython 3.12.10 source tree")
    ap.add_argument("--abi", default="arm64-v8a", choices=sorted(ABIS))
    ap.add_argument("--ndk", default=DEFAULT_NDK)
    ap.add_argument("--host-python", default=DEFAULT_HOSTPY)
    ap.add_argument("--work", default=os.path.join(DEFAULT_WS, "_cache", "build-cpython", "ohos-build"))
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--jobs", type=int, default=0)
    ap.add_argument("--phase", default="all",
                    choices=["all", "config", "modules", "frozen", "compile", "archive"])
    ap.add_argument("--only", nargs="*", help="only compile sources matching these substrings")
    ap.add_argument("--skip-existing", action="store_true")
    ap.add_argument("--keep-going", action="store_true")
    ap.add_argument("--allow-partial", action="store_true",
                    help="permit archiving even when objects are missing "
                         "(debugging only; the result is NOT usable)")
    ap.add_argument("--max-errors", type=int, default=12)
    ap.add_argument("--error-lines", type=int, default=8)
    args = ap.parse_args()

    b = Builder(args)
    phases = ["config", "modules", "frozen", "compile", "archive"]
    want = phases if args.phase == "all" else [args.phase]
    for p in phases:
        if p not in want:
            continue
        if p == "compile" and args.only:
            # still need pyconfig.h etc.
            pass
        getattr(b, "phase_" + p)()
    log("\ndone.")


if __name__ == "__main__":
    main()
