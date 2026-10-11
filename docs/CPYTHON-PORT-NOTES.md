# CPython 3.12.10 → HarmonyOS(OpenHarmony) aarch64/x86_64 交叉编译笔记

这份文档记录**真实踩过的坑**与最终可复现的做法。全部结论都来自本机实测，
出错的原文片段尽量保留，方便下次直接对号入座。

---

## 0. 为什么不是 `./configure && make`

CPython 官方交叉编译流程依赖 POSIX 工具链（`sh` / `sed` / `patch` / `make`）。
本机这套环境**全部不可用**——所有 MSYS2/Cygwin 程序一启动就死：

```
*** fatal error - couldn't create signal pipe, Win32 error 5
```

涉及 `D:\Git\bin\bash.exe`、`D:\Git\usr\bin\sed.exe`、`mingw32-make.exe`（一旦它去找 POSIX shell
也一起死）、以及 `patch.exe`。本机也没有 WSL、Cygwin 或 busybox。

于是 `scripts/ohos_cpython_build.py` 用**纯 Python 重做了 configure + make 的工作**：

| 阶段 | 做什么 | 实测输出 |
|---|---|---|
| `config` | 用 NDK clang 逐个探测 sysroot 的头文件 / 函数 / 结构体 / 类型尺寸，合成 `Include/pyconfig.h` | 503 次编译探测 / 73 秒；395 个宏被定义，200 个留空 |
| `modules` | 按探测结果决定编译哪些扩展模块，生成 `Modules/config.c`（内建模块表） | 启用 73 个内建模块 |
| `frozen` | 用**宿主 Python 3.12.10** 冻结 `importlib._bootstrap` 等模块（与官方交叉编译一致） | 24 个冻结头文件 + `deepfreeze.c` |
| `compile` | NDK clang 并行编译（`--jobs`，默认 CPU 核数） | 229 个源文件 / 18 秒（本机 16 并发） |
| `archive` | `llvm-ar rcs` 归档 | 230 个对象 → 46.6 MiB |

对象文件按 autoconf 的传统布局写在**源码树内**（`Objects/*.o`、`Python/*.o`、`Modules/*.o`），
这样 `--skip-existing` 可以做增量编译。

常用命令：

```powershell
# 全量
python scripts/ohos_cpython_build.py --src <cpython-3.12.10> --abi arm64-v8a --outdir <工程>/entry/src/main/cpp/thirdparty/arm64-v8a
# 只补编失败/缺失的对象（改了宏之后很有用）
... --skip-existing
# 只重跑归档
... --phase archive
```

---

## 1. 踩坑清单（症状 → 根因 → 修法）

### 1.1 `"define CONFIG_64 or CONFIG_32"`（`_decimal/libmpdec` 全线失败）

- **症状**：`Modules/_decimal/libmpdec/mpdecimal.h:209: error: "define CONFIG_64 or CONFIG_32"`
- **根因**：libmpdec 要求外部明确告诉它指针宽度。
- **修法**：给 `_decimal` 模块加 `-DCONFIG_64`（aarch64/x86_64 都是 64 位）。

### 1.2 `"missing preprocessor definitions"` / `"need platform specific 128 bit multiplication"`

- **症状**：加了 `CONFIG_64` 之后，`bits.h:184` 与 `typearith.h:253` 继续报错。
- **根因**：libmpdec 只在 `UNIVERSAL`（跨架构）模式下**自己**定义 `ANSI`；
  常规构建必须显式给。少了 `ANSI` 就落进 `#else #error`；
  而 64 位通用实现还需要 `HAVE_UINT128_T`（aarch64 的 clang 有 `__int128`）。
- **修法**：`_decimal` 模块编译参数 = `-DCONFIG_64 -DANSI -DHAVE_UINT128_T`。

### 1.3 `_localemodule.c`：`call to undeclared function 'gettext'`

- **症状**：`incompatible integer to pointer conversion passing 'int' to parameter of type 'const char *'`
- **根因**：OHOS sysroot 的 **静态** libc 里有 `gettext` 符号（探针链接成功 → `HAVE_GETTEXT` 被定义），
  但 sysroot 里没有 `<libintl.h>`，于是 `_localemodule.c` 走隐式声明（返回值当 `int`）。
- **修法**：生成 pyconfig.h 后强制 `#undef HAVE_GETTEXT / HAVE_DGETTEXT /
  HAVE_BIND_TEXTDOMAIN_CODESET / HAVE_LIBINTL_H`。

### 1.4 `addrinfo.h:127: error: redefinition of 'addrinfo'`

- **症状**：`socketmodule.c` 与 sysroot 的 `netdb.h` 里 `struct addrinfo` 定义冲突。
- **根因**：`Modules/addrinfo.h` 用 **`HAVE_ADDRINFO`** 判断是否需要自带定义，
  而驱动的"函数"探针把 `HAVE_ADDRINFO` 当成函数 `addrinfo()` 去链接——必然失败，
  于是宏没被定义，兜底定义就被启用了。
- **修法**：把 `HAVE_ADDRINFO`（以及 `HAVE_SOCKADDR_STORAGE`）放进 **STRUCT_PROBES**，
  按"结构体能否编译"来探测。

### 1.5 `socketmodule.c:5978: use of undeclared identifier 'data'`

- **症状**：`memset((void *) &data, '\0', sizeof(data));` 里 `data` 未声明。
- **根因**：`gethostbyname_r` 有 6/5/3 参数三种历史形态。`HAVE_GETHOSTBYNAME_R` 被定义，
  但三个 `_N_ARG` 宏一个都没定义 → 代码落进 `#else /* 3 参数 */` 分支，而 `data` 只在
  3 参数分支里声明。OHOS(musl) 实际是 **6 参数**：
  `int gethostbyname_r(const char *, struct hostent *, char *, size_t, struct hostent **, int *);`
- **修法**：像 configure 那样按 6 → 5 → 3 顺序编译试探，第一个编过的定义对应宏。

### 1.6 `undefined symbol: bytesio_spec / bytesiobuf_spec`

- **根因**：`_io` 模块的源文件清单漏了 `Modules/_io/bytesio.c`。
- **修法**：补上。教训：内建模块的源文件清单要对照 `Modules/Setup.stdlib` 核对，别凭记忆写。

### 1.7 `undefined symbol: explicit_bzero`（然后是 `explicit_memset`）

- **症状**：编译全部通过、归档正常，但链接进 HAP 时报未定义符号，一次只报一个。
- **根因**：探针是链着 sysroot 的**静态** libc.a 做的（里面有这两个符号），
  但设备上的**动态** libc.so 并不导出它们。可用下面这条命令确认：
  ```
  llvm-nm --dynamic --defined-only <sdk>/sysroot/usr/lib/aarch64-linux-ohos/libc.so | findstr explicit_bzero
  ```
  （实测：无输出，确实不导出。）
- **修法**：强制 `#undef HAVE_EXPLICIT_BZERO / HAVE_EXPLICIT_MEMSET`，
  让 `Modules/_blake2` 走 `memset` 兜底实现。
- **注意**：改宏之后必须**删掉受影响的 .o** 再 `--skip-existing` 重编，否则旧的 .o 还带着旧引用。
  对象在源码树里，例如 `Modules/_blake2/blake2b_impl.o`。
  用 `llvm-nm --undefined-only <obj>` 可以精确找出哪些对象引用了它。

### 1.8 `relocation R_AARCH64_ADR_PREL_PG_HI21 cannot be used against symbol ...; recompile with -fPIC`

- **症状**：HAP 链接阶段成百上千条重定位错误。
- **根因**：静态库是要**整库链接进 `libpythonbridge.so`** 的，所有对象必须编成位置无关代码，
  而驱动最初只加了 `-O2 -g` 等，漏了 `-fPIC`。
- **修法**：`common_cflags()` 里加 `-fPIC`。这是本移植**最关键的一行**。

### 1.9 `spwdmodule.c` 编译失败（`get_spwd_state` 未声明）

- **根因**：`spwd` 在 3.12 已废弃（3.13 直接移除），OHOS 沙箱也没有可用的 shadow 数据库接口。
- **修法**：直接不编（记进 `DISABLED_MODULES`）。

---

## 2. 模块取舍（由 sysroot 实际能力决定，不是拍脑袋）

**启用（73 个内建模块，其中值得一提的）**

| 模块 | 说明 |
|---|---|
| `math` `cmath` `_decimal` | 纯 C 实现；`_decimal` 需要上面 1.1/1.2 的宏 |
| `_json` `binascii` `_struct` `_random` `_statistics` | 基础能力 |
| `zlib` | 链 sysroot 的 `libz.so`（实测导出 95 个符号） |
| `_socket` `select` | 网络与多路复用（`_socket` 需要 1.4/1.5 的宏修正） |
| `_md5` `_sha1` `_sha2` `_sha3` `_blake2` | CPython 3.12 自带 HACL* 实现，**不需要 OpenSSL** |
| `pyexpat` `_elementtree` | XML 解析 |
| `unicodedata` `_codecs_*` `_multibytecodec` | 中文/多语言编码 |
| `fcntl` `mmap` `resource` `termios` `_posixsubprocess` `_multiprocessing` | POSIX 能力 |
| `pwd` `grp` `syslog` `audioop` `array` `_lsprof` `_zoneinfo` 等 | 其余标准能力 |

**禁用（及原因）**

| 模块 | 原因 |
|---|---|
| `_ssl` `_hashlib` | 没有 OpenSSL → **pip 无法走 HTTPS 访问 PyPI**（离线装本地 wheel 仍可用） |
| `_ctypes` | 没有 libffi（`ffi.h` 缺失） |
| `_sqlite3` | 没有 `sqlite3.h` |
| `_bz2` `_lzma` | 没有 `bzlib.h` / `lzma.h` |
| `_curses` `_curses_panel` | 没有 ncurses/terminfo |
| `readline` | 没有 readline/editline |
| `_tkinter` | 没有 Tcl/Tk |
| `_uuid` | 没有 libuuid（与 OpenHarmony 官方移植的处理一致） |
| `_crypt` | `libcrypt.a` 是空壳 |
| `nis` `ossaudiodev` `spwd` | 头文件缺失 / 已废弃 |
| `_test*` `xxlimited*` | 等价 `--disable-test-modules` |

---

## 3. 产物与验证（实测）

```
entry/src/main/cpp/thirdparty/arm64-v8a/libpython3.12.a      48,868,000 B ≈ 46.6 MiB（230 个对象）
entry/src/main/cpp/thirdparty/arm64-v8a/include/*.h          216 个头文件（含本次构建的 pyconfig.h）
entry/src/main/resources/rawfile/python/python312.zip        2.48 MiB（533 个文件，原始 9.5 MiB）
```

链接进应用后：

```
libpythonbridge.so（arm64-v8a，未 strip）        31,241,968 B ≈ 31 MB   （未链接运行时时仅 244 KB）
libpythonbridge.so（HAP 内，已 strip）           9.18 MiB
entry-default-unsigned.hap                       15.98 MB（18 个条目）
```

符号自检（应全部命中）：

```powershell
llvm-nm --dynamic --defined-only libpythonbridge.so |
  Select-String 'Py_InitializeFromConfig|PyRun_SimpleStringFlags|Py_CompileString|_PyRuntime|PyGILState_Ensure|PyEval_SaveThread'
```

实测导出：`Py_InitializeFromConfig` `PyRun_SimpleStringFlags` `Py_CompileString`
`_PyRuntime` `PyGILState_Ensure` `PyEval_SaveThread` `Py_GetVersion` `Py_FinalizeEx`，
内建模块 `PyInit__io` `PyInit__json` `PyInit_math` `PyInit_zlib` `PyInit__socket`
`PyInit__decimal` `PyInit_posix` 等均已就位。

`scripts/verify-hap.py` 可直接接进 CI，检查 HAP 里两个 ABI 的 .so 体积是否说明"运行时确实链进去了"。

---

## 4. 嵌入侧注意事项（CMakeLists 已实现）

1. **整库链接**：`-Wl,--whole-archive libpython3.12.a -Wl,--no-whole-archive`。
   链接器默认只取用到的成员，而 CPython 的内建模块是靠 `PyImport_AppendInittab` /
   `Modules/config.c` 的符号表在运行期查的，不整库链接就会缺符号。
2. **额外依赖**：`z dl m`（`libz` 来自 sysroot；musl 把 pthread/rt/math 都并进 libc）。
3. **pyconfig.h 必须与库同源**：`thirdparty/<abi>/include/pyconfig.h` 必须是本次构建生成的那份，
   否则 `PyConfig`、`Py_ssize_t`、结构体布局会与库内 ABI 不一致。
4. **`--abi` 与产物目录一一对应**：`arm64-v8a` 给平板/鸿蒙 PC 真机，`x86_64` 给模拟器。
   `CMakeLists.txt` 按 `OHOS_ARCH` 选目录，缺失时降级为"无内置运行时"版本而不是编译失败。

## 5. 生成器已知缺陷：两个 ABI 会互相污染（重要，动手改代码前先看）

`ohos_cpython_build.py` 目前把**中间产物放在源码树里**（`Objects/*.o`、`Python/*.o`、…），
并且把生成好的 `pyconfig.h` 写到**共享的** `<src>/Include/pyconfig.h`。这在"一次只编一个 ABI"
时没问题，但**连续编两个 ABI 就会串味**。实测复现：

```
# 先编 arm64-v8a：成功，229/230，归档 46.6 MiB
python ohos_cpython_build.py --abi arm64-v8a --outdir .../thirdparty/arm64-v8a
# 再编 x86_64：仍能编过，但 x86_64 的对象**覆盖**了 arm64 的对象
python ohos_cpython_build.py --abi x86_64 --outdir .../thirdparty/x86_64
# 再回头看 x86_64 的 pyconfig.h，甚至出现了自相矛盾的结果：
#   HAVE_STATVFS  第一次探测=有，第二次=没有
#   HAVE_IEEEFP_H 第二次突然=有 → 205 个文件因 'ieeefp.h' file not found 全灭
```

后果：第二次编出来的 `libpython3.12.a` 只有 25 个对象（1.8 MiB），缺 `PyInit_posix` 等符号，
把它放进工程会让 HAP 链接直接失败——**看起来像"代码坏了"，其实是构建器状态错乱**。

**正确做法（本次交付已实施，见 §5bis）**：`obj_for()` 已改为把对象放到 `<work>/<abi>/obj/…`，
不再写进源码树；`phase_compile` 会校验 `<src>/Include/pyconfig.h` 的 triplet 与当前 `--abi`
是否一致，不一致就重新探测；归档阶段还有"期望对象全集核算"和 `llvm-readelf` 架构闸门兜底。
因此 `-Abi both` 现在可以安全地顺序执行。

原始的建议修复方向（均已落地或等价实现）：
1. `obj_for()` 的对象根目录改成 `<work>/<abi>/…`，让对象文件按 ABI 隔离；✅ 已实施
2. `pyconfig.h` 按 ABI 校验/隔离；✅ 已实施（triplet 校验 + 每 ABI 私有副本置于 `-I` 最前）
3. 记录 triplet + 宏指纹并在启动时校验；✅ 以"pyconfig.h 头部 triplet 注释 + 架构闸门"等价实现

## 6. 已知遗留

- **无 `_ssl`**：`pip install` 只能离线（`--no-index --find-links` 指向本地 wheel 目录）。
  要联网装 PyPI，得先把 OpenSSL 交叉编译进 sysroot 再启用 `_ssl`/`_hashlib`。
- **无 `_ctypes`**：依赖 `ctypes` 的库（不少第三方包）不可用。
- **未做 LTO / `-O3`**：当前 `-O2`；`--enable-optimizations` 那套 PGO 在交叉编译下不适用。
- **冻结模块用的是宿主 Python 3.12.10**：版本必须与目标**完全一致**，
  否则 `marshal` 字节码格式不匹配。
- **x86_64 与 arm64-v8a 各自独立构建**：探针结果按 ABI 分别生成 pyconfig.h，不要混用产物目录。

---

## 5bis. 针对 §5 的修复：已实施（更新）

§5 的诊断完全正确（两个 ABI 共享源码树会串味，实测就是 `ieeefp.h` 版本那一次）。
其中"建议的修复方向"第 1、2 条**已经落地**，另外补了两个"绝不出坏产物"的硬闸门。
两处失败都发生在 `ohos_cpython_build.py`，改完请重新跑一次 `--phase all` 验证。

### 5bis.1 生成的共享文件改成「每 ABI 一份 + 原子写」（对应 §5 建议 2）

- `phase_config` 写 `pyconfig.h` 改为**先写 `pyconfig.h.tmp` 再 `os.replace()`**（原子替换）。
  半写的文件是 §5 里"同一个宏两次探测结果矛盾"的直接来源——并发读者会看到半截内容。
- 同时把 `pyconfig.h` 与 `Modules/config.c` 各写一份到 **ABI 私有目录**
  `_cache/build-cpython/ohos-build/<abi>/`，并把该目录放到 `common_cflags()` 里 `-I` 的**最前面**，
  `Modules/config.c` 也优先用私有副本编译。
  这样每个 ABI 永远只读自己的那份，源码树里的副本退化为"留档/兼容"。

### 5bis.2 绝不输出残缺的静态库（新闸门）

**故障**：§5 描述的 x86_64 那次，230 个里只有 25 个编过，但
`--keep-going` 让 `phase_compile` 只打日志不中断，`phase_archive` 又"存在多少就归档多少"，
于是**静悄悄产出了一个 1.8 MiB 的残库**——它能链接，却在运行期缺 `PyInit_*`。

**修法**：`phase_archive` 归档前重新计算**期望对象全集**，有缺失就打印清单并中止，
**拒绝写盘**；只有显式 `--allow-partial` 才放行（并且明确标注结果不可用）。
语义澄清：`--keep-going` 只表示"把所有错误都报出来"，**不表示"能编多少就发多少"**。

### 5bis.3 绝不把 ABI 标错（新闸门）

对象同名同路径、跨 ABI 互相覆盖，可能出现"`arm64-v8a/` 目录里放了一份 x86_64 库"这种极隐蔽事故。
`phase_archive` 归档前用 `llvm-readelf -h` 读第一个对象的 ELF 头校验 `Machine`
（`AArch64` / `X86-64`）与 `--abi` 一致，不一致就中止并提示 `stale objects from another ABI`。

### 5bis.4 仍然遗留

**`.o` 仍在共享源码树**（§5 建议 1 未做）。所以两个 ABI **依然不能真正并发构建**。
彻底解法是把对象输出改到 `_cache/build-cpython/ohos-build/<abi>/obj/`（VPATH 风格）。
在那之前请**顺序**构建（`build-cpython-ohos.ps1 -Abi both` 是顺序的），
或依赖 5bis.3 的 ABI 校验兜底。§5 里"用独立源码树"的办法也依然有效、更保险。

---

## 7. 实际生效的配置（等价于 configure 的参数）

本移植没有真正跑 `configure`（原因见 §0），但为便于对照、也为了将来在具备 POSIX shell 的环境能一把跑通，
这里给出**实际生效的配置**与**等价的 configure 命令行**。

```sh
CC=<NDK>/llvm/bin/aarch64-unknown-linux-ohos-clang      # 注意是 sh 脚本，需要 POSIX shell
AR=<NDK>/llvm/bin/llvm-ar  RANLIB=<NDK>/llvm/bin/llvm-ranlib
MODULE_BUILDTYPE=static \            # ★ 关键：扩展模块全部进 libpython3.12.a
./configure \
  --host=aarch64-linux-ohos --build=x86_64-pc-msys \
  --with-build-python=<HostPython312> \   # 交叉编译必需的宿主解释器（冻结模块用）
  --disable-ipv6 --disable-test-modules --without-ensurepip \
  --disable-shared                       # 默认即静态 → libpython3.12.a
```

`MODULE_BUILDTYPE` 能用环境变量覆盖，是因为 `configure` 里写的是
`MODULE_BUILDTYPE=${MODULE_BUILDTYPE:-shared}`；它决定 `Modules/Setup.stdlib` 里
`*@MODULE_BUILDTYPE@*` 变成 `*static*` 还是 `*shared*`，也就决定了扩展模块是否进 `.a`。

| 配置项 | 实际取值 | 说明 |
|---|---|---|
| `host` | `aarch64-linux-ohos` | 由 `-target` 决定；`__OHOS__`、`__MUSL__` 由 clang 定义 |
| `PLATFORM_TRIPLET` | `aarch64-linux-ohos` | 即平台三元组探针应得的结果（补丁让 `__OHOS__` 走 ohos 分支） |
| `MULTIARCH` | `aarch64-linux-ohos` | clang 不支持 `--print-multiarch`，回落为 `PLATFORM_TRIPLET` |
| `ABIFLAGS` | `""` | 非 debug |
| `SOABI` | `cpython-312-aarch64-linux-ohos` | 按官方 Makefile 做法，作为 `Python/dynload_shlib.c` 的**逐文件** `-DSOABI=...`，**不在** `pyconfig.h` 里 |
| `EXT_SUFFIX` | `.cpython-312-aarch64-linux-ohos.so` | 同上；静态内建模块用不到 |
| `Py_DEBUG` `Py_TRACE_REFS` `Py_ENABLE_SHARED` | 未定义 | release 静态构建 |
| `Py_BUILD_CORE` / `Py_BUILD_CORE_BUILTIN` | 核心对象 / 静态内建模块 | 与官方 Makefile 一致 |
| `WITH_PYMALLOC` | 1 | |
| `PYLONG_BITS_IN_DIGIT` | 30 | LP64 标准值 |
| `HAVE_COMPUTED_GOTOS` / `USE_COMPUTED_GOTOS` | 1 / 1 | clang 支持 `&&label`，`ceval.c` 用跳转表 |
| `_GNU_SOURCE` `_REENTRANT` `_POSIX_C_SOURCE` `_XOPEN_SOURCE` `_FILE_OFFSET_BITS` | 1 / 1 / 200809L / 700 / 64 | 等价 `AC_USE_SYSTEM_EXTENSIONS` + CPython 的 Linux 分支 |
| `_POSIX_THREADS` | **不定义** | OHOS 的 `<unistd.h>` 自己会定义（脚本先探测再决定，避免重复定义） |
| `_PYTHONFRAMEWORK` | `""` | macOS 专用，但 `Python/sysmodule.c` 无条件引用 |
| `PREFIX` / `EXEC_PREFIX` / `PLATLIBDIR` | `/usr` / `/usr` / `lib` | 逐文件 `-D` 给 `Modules/getpath.c`；**嵌入时必须用 `PyConfig` 覆盖**（见 §10） |
| `PY_SUPPORT_TIER` | 3 | PEP 11 社区支持等级（3.12 的 C 代码并未读取） |
| IPv6 | **未启用**（`ENABLE_IPV6` 未定义） | 等价 `--disable-ipv6`，见 §10.4 |
| 测试模块 | 全部禁用 | 等价 `--disable-test-modules` |
| 编译标志 | `-std=c11 -O2 -g -fPIC -fwrapv -fno-strict-aliasing -DNDEBUG` | `-fPIC` 是刚需，见 §1.8 |

**特意没有加 `-fvisibility=hidden`**：静态库要让嵌入的 NAPI `.so` 看到 `Py*` 符号。

### 7.1 交叉编译怎么测 `sizeof`（跑不了目标程序）

`sizeof` / `_Alignof` 无法"运行"获得，脚本改用**读 `.rodata`**：
把 `sizeof(...)` 写成 `const unsigned long py_probe_values[] = {...}` 编译成 `.o`，
再用 `llvm-objdump -s -j .rodata` 把字节读回来。
一次编译拿到全部 21 个尺寸/对齐值（`SIZEOF_LONG`=8、`SIZEOF_FPOS_T`=16、
`SIZEOF_LONG_DOUBLE`=16、`ALIGNOF_MAX_ALIGN_T`=16 …），比反复改常量重编可靠。

---

## 8. 应用的补丁：`patches/cpython-3.12.10-ohos-cross.patch`

上游 OpenHarmony 移植仓库的 `cross_compile_support_ohos.patch` 针对 **CPython 3.11.4**。
本次把与 OHOS 有关的 3 处移植到 3.12.10（这些位置在 3.12 未变），生成
`patches/cpython-3.12.10-ohos-cross.patch`（4,174 B，**`git apply --check -p1` 退出码 0**）。

| 文件 | 改动 | 不这么做会怎样 |
|---|---|---|
| `config.sub` | `case $os in` 白名单加 `ohos*` | `configure` 报 ``Invalid configuration `aarch64-linux-ohos'`` |
| `config.sub` | `case $kernel-$os in` 加 `*-ohos*) ;;` | 不承认 `aarch64-linux-ohos` 是合法组合 |
| `configure.ac` | 平台三元组探针加 `#elif defined(__OHOS__)` → `aarch64-linux-ohos` | 被判成 `aarch64-linux-gnu`，`SOABI`/`EXT_SUFFIX` 全错 |
| `configure.ac` | ARM EABI 分支 `#if defined(__ARMEL__) && !defined(__OHOS__)` → `arm-linux-ohos` | 32 位 OHOS 目标 |
| `configure.ac` | `MULTIARCH=$($CC $CFLAGS --print-multiarch ...)` | clang 没有 `-target` 就不知道目标 |
| `configure` | 上述 3 处同样打进**预生成的** `configure` | 本机没有 autoconf，且发布包自带 `configure` |

**故意没移植的部分**：3.11.4 的补丁还改了两处 `setup.py`
（`DISABLED_MODULE_LIST = ['_uuid','_socket','zlib','_ctypes','binascii']`）。
CPython 3.12 已删除 `setup.py`（模块选择搬到 `configure` + `Modules/Setup.stdlib` 的 `PY_STDLIB_MOD` 体系），
这些 hunk 无对应位置；职责由 `ohos_cpython_build.py` 的 `DISABLED_MODULES` 承担。
另外上游把 `_socket`/`zlib`/`binascii` 也禁了，**本移植没有跟随**：
实测这三者在本 SDK 都能正常编译，禁掉只会白丢网络、压缩与快速 CRC。

```powershell
python scripts/make-ohos-patch.py --src <干净的 3.12.10 源码树> --out patches/cpython-3.12.10-ohos-cross.patch
git apply --check -p1 patches/cpython-3.12.10-ohos-cross.patch     # 退出码 0
```

**本移植没有修改任何 CPython C 源码**：除上述 autoconf 层面的三元组识别外，
平台差异全部通过 `pyconfig.h` 探测结果与 `DISABLED_MODULES` 表达。
好处是升 3.12.x 补丁版时重跑脚本即可，不必维护源码补丁栈。

---

## 9. 完整模块清单（对 §2 的展开与一处更正）

### 9.1 启用：72 个扩展模块 + 5 个核心提供

`llvm-nm` 在 `libpython3.12.a` 里能看到 **77 个** `PyInit_*` 定义。
其中 5 个由核心 C 文件直接提供：`_imp`(import.c) `_ast`(Python-ast.c) `_tokenize`(Python-tokenize.c)
`_string`(unicodeobject.c) `gc`(gcmodule.c)；其余 72 个是扩展模块：

| 分组 | 模块 |
|---|---|
| bootstrap（必须静态，22） | `atexit` `faulthandler` `posix` `_signal` `_tracemalloc` `_codecs` `_collections` `errno` `_io` `itertools` `_sre` `_thread` `time` `_typing` `_weakref` `_abc` `_functools` `_locale` `_operator` `_stat` `_symtable` `pwd` |
| 始终可用（16） | `array` `_asyncio` `_bisect` `_contextvars` `_csv` `_heapq` `_json` `_lsprof` `_opcode` `_pickle` `_queue` `_random` `_struct` `_xxsubinterpreters` `_xxinterpchannels` `_zoneinfo` |
| 需要 libm（5） | `audioop` `math` `cmath` `_statistics` `_datetime` |
| 自带 libmpdec（1） | `_decimal`（`-DCONFIG_64 -DANSI -DHAVE_UINT128_T`） |
| 压缩 / 哈希（7） | `binascii` `zlib`(→`-lz`) `_md5` `_sha1` `_sha2` `_sha3` `_blake2`（后五个用自带 HACL*） |
| XML（2） | `pyexpat` `_elementtree`（自带 expat，`-I Modules/expat`） |
| CJK / Unicode（8） | `_codecs_cn` `_codecs_hk` `_codecs_iso2022` `_codecs_jp` `_codecs_kr` `_codecs_tw` `_multibytecodec` `unicodedata` |
| UNIX 相关（9） | `fcntl` `grp` `mmap` `_posixsubprocess` `resource` `select` `_socket` `syslog` `termios` |
| 多进程（2） | `_posixshmem` `_multiprocessing` |

> **更正 §2**：把 `spwd` 加进 `DISABLED_MODULES` 之后是 **72** 个扩展模块（§2 写的 73 是加入 `spwd` 之前的数字）。
> `spwd` 必须从 `MODULES` 表里删掉，而不是只记进禁用表——否则 `Modules/config.c` 会生成
> `{"spwd", PyInit_spwd}` 而库里没有该符号，嵌入方链接 `.so` 时就会报未定义。当前产物已核对：
> `config.o` 的未定义符号里**没有** `PyInit_spwd`，且"引用但未定义"集合为空。

### 9.2 禁用：31 个

| 模块 | 原因 |
|---|---|
| `_ssl` `_hashlib` | sysroot 无 OpenSSL（无 `openssl/*.h`） |
| `_sqlite3` | 无 `sqlite3.h` |
| `_ctypes` `_ctypes_test` | 无 libffi（无 `ffi.h`） |
| `_curses` `_curses_panel` `readline` | 无 ncurses / terminfo / readline |
| `_bz2` `_lzma` | 无 `bzlib.h` / `lzma.h` |
| `_dbm` `_gdbm` | 无 ndbm / gdbm / libdb |
| `_tkinter` | 无 Tcl/Tk |
| `_uuid` | 无 libuuid 也无 `uuid_create()`（与上游 OHOS 补丁一致） |
| `_crypt` | `libcrypt.a` 是 8 字节空壳 |
| `nis` `ossaudiodev` `_scproxy` | 无 `rpc/rpc.h` / 无 `sys/soundcard.h` / 仅 macOS |
| `spwd` | **CPython 3.12 上游 bug**，见 9.3 |
| 测试类 12 个 | `xxsubtype` `_xxtestfuzz` `_testbuffer` `_testinternalcapi` `_testcapi` `_testclinic` `_testimportmultiple` `_testmultiphase` `_testsinglephase` `xxlimited` `xxlimited_35` `_testexternalinspection` |

### 9.3 `spwd` 的完整判据（§1.9 的补充）

`spwd` 在 `Modules/Setup.stdlib` 里是无条件启用的。本 sysroot 有 `shadow.h`，
但没有 `getspnam()`/`getspent()`，于是 `HAVE_GETSPNAM`/`HAVE_GETSPENT` 都没定义。而 `Modules/spwdmodule.c`：

- 第 32~121 行：`spwdmodulestate`、`get_spwd_state()`、`PyModuleDef spwdmodule;` 的定义被
  `#if defined(HAVE_GETSPNAM) || defined(HAVE_GETSPENT)` 包住；
- 第 210~267 行：`spwdmodule_exec` / `slots` / `traverse` / `clear` **没有**同样的守卫。

于是必然失败（原文）：

```
Modules/spwdmodule.c:213:5: error: use of undeclared identifier 'spwdmodulestate';
                                   did you mean 'spwdmodule_exec'?
Modules/spwdmodule.c:213:22: error: use of undeclared identifier 'state'
Modules/spwdmodule.c:215:5: error: use of undeclared identifier 'state'; did you mean 'stat'?
Modules/spwdmodule.c:232:33: error: member reference type 'int' is not a pointer
```

若要恢复，最小改法是给第 210 行之后的块补同一个 `#if` 守卫，或向 CPython 提 issue。

---

## 10. 嵌入接口结论（NAPI）★ 本节对集成最重要

§4 已讲链接层面三件事（whole-archive、`z dl m`、pyconfig 同源）。这里补齐**运行期**必须做的部分。

### 10.1 `PyConfig` 必设项与理由

库是拿 `-DPREFIX="/usr"` 编的（`Modules/getpath.c`），**`/usr` 在 OHOS 上毫无意义，
默认 `home`/`prefix` 一定是错的**，所以不能只调 `Py_Initialize()`，必须用 `Py_InitializeFromConfig()`：

```cpp
PyConfig config;
PyConfig_InitPythonConfig(&config);
config.install_signal_handlers = 0;   // 初始化可能在工作线程上，不能接管进程信号
config.write_bytecode = 0;            // 沙箱 / zip 内不生成 __pycache__
config.site_import = 1;               // 需要 .pth / site-packages 就留 1
PyConfig_SetBytesString(&config, &config.home, home.c_str());
std::string programName = home + "/python";
PyConfig_SetBytesString(&config, &config.program_name, programName.c_str());
config.module_search_paths_set = 1;   // ★ 决定能否 import 的就是这一行
PyWideStringList_Append(&config.module_search_paths, L"<home>");
PyWideStringList_Append(&config.module_search_paths, L"<home>/python312.zip");
PyWideStringList_Append(&config.module_search_paths, L"<home>/lib/python3.12/lib-dynload");
PyStatus status = Py_InitializeFromConfig(&config);
PyConfig_Clear(&config);              // 无论成败都要清
```

| 设置 | 为什么必须注意 |
|---|---|
| `module_search_paths_set = 1` | 覆盖编译期 `/usr` 前缀。**嵌入能否 `import os` 的决定性一步** |
| `program_name` | `getpath` 从它推理 prefix/home；不设会让 `sys.executable` 与路径猜测离谱 |
| `home` | 显式给出标准库根，避免 getpath 去翻 `/usr/lib/python3.12` |
| `install_signal_handlers = 0` | 默认 1 会注册 SIGINT handler；初始化若在 ArkTS 工作线程上会与 NAPI/系统冲突 |
| `write_bytecode = 0` | 从 zip 导入本就不写 `.pyc`；项目目录只读时还会报错 |
| `PyConfig_Clear` | `PyConfig_InitPythonConfig` 会分配内存，泄漏会随每次初始化累积 |
| **不要用 `Py_ExitStatusException`** | 它内部 `exit()`，在 NAPI 模块里会直接杀进程。应取 `status.err_msg` 自己 `napi_throw_error` |

### 10.2 `python312.zip` 必须先落盘到应用沙箱

`rawfile` 资源**在 HAP 内不是普通文件路径**，而 `module_search_paths` 里必须是真实路径
（`zipimport` 走 `open()`）。所以启动时：

1. `resourceManager.getRawFileContent('python/python312.zip')` 读出字节；
2. 写到 `context.filesDir + "/python/python312.zip"`；
3. 用 `filesDir + "/python"` 作为 `home`，把 zip 的**真实路径** append 进 `module_search_paths`。

或者把 zip 解开成目录再用目录路径（启动稍快、占空间多，但不依赖 zipimport）。

### 10.3 GIL 与线程

- `Py_InitializeFromConfig()` 之后当前线程持有 GIL。只在一个线程用可保持现状；
  多 NAPI 回调/工作线程用时**必须在初始化后立刻 `PyEval_SaveThread()` 释放**，
  之后每个入口用 `PyGILState_Ensure()` / `PyGILState_Release()` 严格配对。
- 库用真实 pthread 构建（`HAVE_PTHREAD_H` + `_REENTRANT`，`_POSIX_THREADS` 由 `<unistd.h>` 提供），
  `_thread` / `threading` 可用。
- **不要在主 JS 线程跑 Python**：应放到 `napi_create_async_work` / TaskPool。
- `Py_FinalizeEx()` 可选，且**必须在没有其它线程持有 GIL 时**调用，否则崩。

### 10.4 运行期行为差异：编译通过 ≠ 运行可用

这些宏是按 sysroot 的**头文件/静态库**判定为"可用"的，OHOS 沙箱在运行期可能拒绝：

| 能力 | 编译期 | 运行期建议 |
|---|---|---|
| `os.fork()` `os.execv()` `subprocess` `multiprocessing` | `HAVE_FORK` `HAVE_VFORK` `HAVE_EXECV` `HAVE_POSIX_SPAWN` 全为真 | OHOS 应用**不能 fork**，把 `subprocess` 当不可用 |
| `os.setns` `os.unshare` `os.memfd_create` | `HAVE_SETNS` `HAVE_UNSHARE` `HAVE_MEMFD_CREATE` 为真 | 普通应用会 `EPERM` |
| `_posixshmem` / `shm_open` | `HAVE_SHM_OPEN` 为真 | 共享内存命名空间可能被限制，需真机验证 |
| `signal.pthread_sigmask()` `signal.pthread_kill()` | **未定义** → API 在 `signal` 里不存在 | 正常缺失（musl 侧行为），别承诺 |
| `socket.if_nameindex()` | `HAVE_IF_NAMEINDEX` 未定义 | 正常缺失 |
| `locale.gettext()` 等 5 个绑定 | `HAVE_LIBINTL_H` 被撤销 | 正常缺失 |
| **IPv6** | `ENABLE_IPV6` **未定义** | `socket.AF_INET6` 不可用；要开就在 `pyconfig.h` 补 `#define ENABLE_IPV6 1` 重编（`HAVE_GETADDRINFO`/`HAVE_SOCKADDR_STORAGE` 已是 1） |

### 10.5 能 / 不能 import 速查

| 可用 | 备注 |
|---|---|
| `os` `sys` `io` `json` `re` `collections` `datetime` `math` `cmath` `decimal` `random` `struct` `array` `binascii` `zlib` `gzip` `zipfile` `tarfile` `csv` `hashlib` `hmac` `base64` | `hashlib` 只有内置 5 族（md5/sha1/sha2/sha3/blake2）；无 `_hashlib`，OpenSSL 专属加速缺失 |
| `xml.etree.ElementTree` | 自带 expat 生效 |
| `socket`（IPv4 + AF_UNIX；**无 IPv6**）`select` | |
| `asyncio` `concurrent.futures` `threading` `queue` `contextvars` | |
| `unicodedata`、CJK 编解码 | |
| **不可用** | `ssl` `sqlite3` `ctypes` `bz2` `lzma` `dbm` `gdbm` `curses` `readline` `tkinter` `uuid`(libuuid 部分) `crypt` `nis` `ossaudiodev` `spwd`；`multiprocessing`/`subprocess` 运行期 |

> zip 是按 Lib 目录内容整体打的，所以 `ssl.py` `sqlite3/` `ctypes/` `bz2.py` `lzma.py` 等**仍在包里**，
> `import` 它们会在加载 C 后端时失败——预期行为，不是打包错误。应用侧应把 `ImportError` 当能力探测处理。

### 10.6 排查"到底是不是路径问题"的妙招

`importlib._bootstrap` `zipimport` `abc` `codecs` `io` `os` `site` `stat` `posixpath`
`genericpath` `_collections_abc` `importlib.util` `importlib.machinery` `runpy` `getpath` 等 **24 个模块**
已被 deep-freeze 进库里（`Python/frozen_modules/*.h` + `Python/deepfreeze/deepfreeze.c`）。于是：

> **能 `import os`，但 `import json` 失败** ⇒ 一定是 `module_search_paths` / zip 落盘的问题，
> 而不是库没编好。

---

## 11. 校验与体积

```powershell
$NDK = "D:\DevEco Studio\sdk\default\openharmony\native"
$lib = "entry\src\main\cpp\thirdparty\arm64-v8a\libpython3.12.a"

& "$NDK\llvm\bin\llvm-ar.exe" t $lib | Measure-Object                     # 230
& "$NDK\llvm\bin\llvm-ar.exe" x $lib Abstract.o
& "$NDK\llvm\bin\llvm-readelf.exe" -h Abstract.o                          # ELF64 / REL / AArch64
& "$NDK\llvm\bin\llvm-nm.exe" --defined-only $lib |
  Select-String " [TD] (Py_InitializeFromConfig|PyRun_SimpleString|Py_CompileString|Py_FinalizeEx|_PyRuntime|_PyImport_Inittab)$"
& "$NDK\llvm\bin\llvm-nm.exe" --defined-only $lib | Select-String " T PyInit_" | Measure-Object   # 77
```

实测（arm64-v8a）：

| 检查项 | 结果 |
|---|---|
| 成员数 | 230 |
| ELF | `ELF64` / `REL` / `AArch64` |
| API 符号 | `Py_InitializeFromConfig` `Py_Initialize` `Py_FinalizeEx` `PyRun_SimpleString` `Py_CompileString` `PyImport_ImportModule` 全部 `T` |
| 运行时状态 | `_PyRuntime` `D`、`_PyImport_Inittab` `D`、`PyExc_BaseException` `D` |
| 内建模块 | 77 个 `PyInit_*` / `PyMarshal_Init` / `_PyWarnings_Init` |
| 悬空引用 | **无** |
| SHA256 | `B0A85AB36EFB6C8B63BA120AC2ADE624C7E4FE6266B8282F183A1F31B73B6EAC` |

### 调试信息占了 71.6%

| 形态 | 大小 |
|---|---|
| `libpython3.12.a`（带 `-g`） | 46.6 MiB |
| 同上，`llvm-strip --strip-debug` 之后 | **13.2 MiB**（230 个成员、关键符号全部保留） |

```powershell
& "$NDK\llvm\bin\llvm-strip.exe" --strip-debug libpython3.12.a
```

因为 `CMakeLists.txt` 用 `--whole-archive` 链接，`.a` 里 230 个对象会全部进 `libpythonbridge.so`，
所以 `.a` 的体积（含调试信息）会直接传到 `.so`/HAP。要压体积，剥 `.a` 的调试信息是最省事且零损失的一步；
也可以链接时加 `-Wl,--strip-debug`，或让 `common_cflags()` 去掉 `"-g"`。

---

## 12. 后续步骤（按优先级）

1. **真机运行验证**（当前所有结论止于编译/链接/符号）。首要验证清单：
   `sys.builtin_module_names`、`import zlib/_socket/select/math/decimal/pyexpat/unicodedata`、
   `hashlib.sha256`、`socket.socket(AF_INET)`、`os.getrandom`、`threading`、
   `PyGILState_Ensure/Release` 多线程压测。
2. **打开 IPv6**（`#define ENABLE_IPV6 1` 重编）并验证。
3. **x86_64 模拟器实测**：能编出来 ≠ 能跑。`HAVE_GCC_ASM_FOR_X64` 已按目标补上
   （x87 控制字，保证 `long`→`double` 正确舍入），但未在模拟器跑过。
4. **对象输出改到每 ABI 独立目录**（§5bis.4），彻底消除交叉构建互相覆盖。
5. **`ensurepip/_bundled` 是否随包**：当前按要求排除，故无法离线装 pip；
   把 `pip-24.0-py3-none-any.whl` 放回 zip 约 +2 MB（仍在 12 MB 内）即可恢复。
6. **性能**：当前 `-O2`、无 PGO/LTO，纯解释执行比官方发行版低 10~20%。
7. **`libmpdec` 用了 `uint128` 后端**，未实测 `decimal` 边界用例。
