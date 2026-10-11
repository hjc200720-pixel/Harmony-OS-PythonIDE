# 构建 / 签名 / 安装

## 0. 环境实测版本

| 组件 | 本机实测 | 说明 |
|---|---|---|
| DevEco Studio | `DS-261.23567.138.36.2600851`（DevEco 6） | 自带 JBR(JDK 25)、Node v24.14.1、ohpm、hvigor |
| HarmonyOS SDK | `sdk/default` → **26.0.0 / apiVersion 26** | `compatibleSdkVersion` 必须写 `26.0.0` |
| OHOS NDK | `sdk/default/openharmony/native` | clang 交叉编译器、cmake 3.28 + ninja、sysroot |
| 宿主机 Python | 3.12.10（`...\Programs\Python\Python312\python.exe`） | 交叉编译 CPython 时用于冻结 bootstrap 模块，**版本必须与目标一致** |

> ⚠️ **两个必踩的坑，先看这两条能省一小时：**
>
> 1. **版本号格式**：DevEco 6 要求 `compatibleSdkVersion` / `targetSdkVersion` 写成
>    `<major>[.<minor>][.<patch>]`（如 `26.0.0`），**不能**再用旧版的 `6.0.2(22)`，
>    否则报 `api version parameter is illegal`。
> 2. **必须让 hvigor 找得到 java**：`PackageHap` 阶段会 `spawn java`，系统 PATH 里没有 java
>    时报 `spawn java ENOENT`。此时 **ArkTS 其实已经编译通过了**，很容易被误判成代码错误。
>    把 DevEco 自带的 JBR 放进 PATH 最前面即可（`scripts/build-hap.ps1` 已自动处理）：
>    `JAVA_HOME=D:\DevEco Studio\jbr`，`PATH` 前置 `D:\DevEco Studio\jbr\bin`。

## 1. 命令行构建 HAP（已验证可用）

```powershell
# 本机只有 Windows PowerShell 5.1；装了 PowerShell 7 的话 pwsh -File 同样可用
powershell -File scripts\build-hap.ps1                      # debug
powershell -File scripts\build-hap.ps1 -Mode release
powershell -File scripts\build-hap.ps1 -Clean               # 先清理再构建
powershell -File scripts\build-hap.ps1 -ResetHvigorCache    # 遇到 hvigor 缓存 ENOENT 时
```

脚本等价于：

```powershell
$env:JAVA_HOME = "D:\DevEco Studio\jbr"
$env:NODE_HOME = "D:\DevEco Studio\tools\node"
$env:DEVECO_SDK_HOME = "D:\DevEco Studio\sdk"
$env:Path = "D:\DevEco Studio\jbr\bin;D:\DevEco Studio\tools\node;D:\DevEco Studio\tools\ohpm\bin;D:\DevEco Studio\tools\hvigor\bin;" + $env:Path

ohpm install --all
hvigorw --mode module -p product=default -p buildMode=debug assembleHap --no-daemon
```

产物：`entry\build\default\outputs\default\entry-default-unsigned.hap`

**未配置签名时**只能得到 unsigned HAP：可以验证编译链路，但不能安装到设备。

### 实测构建结果（本次交付，内嵌 CPython 之后）

```
ArkTS 编译错误：0（只有 WARN）
原生编译：arm64-v8a 230/230 与 x86_64 230/230 均通过，架构自检 AArch64 / X86-64
HAP 链接：无未定义符号
BUILD SUCCESSFUL

entry-default-unsigned.hap                 26.90 MB / 22 个条目
├─ libs/arm64-v8a/libpythonbridge.so       9.18 MiB（HAP 内已 strip）← 内嵌 CPython 3.12.10
│    同目录未 strip 的中间产物为 31.2 MB；未链接运行时时仅 244 KB
├─ libs/x86_64/libpythonbridge.so          9.38 MiB ← 内嵌 CPython（模拟器）
├─ resources/rawfile/python/wheels/pip-25.0.1-py3-none-any.whl  1.76 MiB ← 离线 pip
├─ resources/rawfile/python/python312.zip  2.48 MiB（533 个标准库文件）
├─ ets/modules.abc                         638 KB
└─ module.json / resources.index / pack.info
```

符号自检（实测命中，可用于 CI）：

```powershell
llvm-nm --dynamic --defined-only libpythonbridge.so |
  Select-String 'Py_InitializeFromConfig|PyRun_SimpleStringFlags|Py_CompileString|_PyRuntime|PyGILState_Ensure|PyEval_SaveThread'
```

> ✅ **`-Abi both` 现在可以放心用**：对象文件按 ABI 隔离在 `<work>\<abi>\obj\`，
> 且 `phase_compile` 会校验 `Include/pyconfig.h` 的 triplet 是否匹配当前 `--abi`
> （不匹配就重新探测），归档前还有"期望对象全集核算"与 `llvm-readelf` 架构闸门兜底。
> 实测两个 ABI 各 230/230 编译成功、架构自检分别为 AArch64 / X86-64。
> 历史坑与修复过程见 [CPYTHON-PORT-NOTES.md §5/§5bis](CPYTHON-PORT-NOTES.md)。

> ⚠️ **`.ps1` 一律保持 ASCII-only**：Windows PowerShell 5.1 会用 ANSI 代码页（中文系统是 GBK）
> 读取**无 BOM** 的 UTF-8 文件，脚本里的中文会被解成乱码并导致**语法错误**
> （现象是 `Unexpected token` 之类，很容易误判成脚本写错）。
> 本项目两个入口脚本已刻意写成纯 ASCII，既不需要 BOM，也不会被编辑器保存动作悄悄弄坏。
> 如果将来要在里面写中文，务必保存为 **UTF-8 with BOM**。

## 2. 交叉编译 CPython 运行时

```powershell
powershell -File scripts\build-cpython-ohos.ps1                  # 默认 arm64-v8a（真机）
powershell -File scripts\build-cpython-ohos.ps1 -Abi x86_64       # 模拟器
powershell -File scripts\build-cpython-ohos.ps1 -Abi both         # 两个 ABI（顺序执行，已支持）
powershell -File scripts\build-cpython-ohos.ps1 -SkipStdlib       # 只重编库，不重打标准库 zip
```

### 为什么不是 `./configure && make`

CPython 官方交叉编译流程依赖 POSIX：`sh`/`sed`/`patch`/`make`。
**本机这些 MSYS/Cygwin 程序全部无法启动**：

```
*** fatal error - couldn't create signal pipe, Win32 error 5
```

（`D:\Git\bin\bash.exe`、`mingw32-make`、`sed` 都是这个下场；本机也没有 WSL/Cygwin。）

所以 `scripts/ohos_cpython_build.py` 用**纯 Python** 重做了 configure+make 的工作：

| 阶段 | 做什么 |
|---|---|
| 1/5 `config` | 用 NDK clang 逐个探测 OHOS sysroot 的头文件与类型尺寸，合成 `Include/pyconfig.h` |
| 2/5 `modules` | 按 sysroot 实际能力决定编译哪些扩展模块，生成 `Modules/config.c`（内建模块表） |
| 3/5 `frozen` | 用**宿主 Python 3.12.10** 冻结 `importlib._bootstrap` 等 bootstrap 模块（与 CPython 官方交叉编译做法一致） |
| 4/5 `compile` | NDK clang 并行编译全部 .c（Parser / Objects / Python / Modules） |
| 5/5 `archive` | `llvm-ar rcs` 归档成 `libpython3.12.a` |

脚本的 `--phase` 参数可以单独重跑某一阶段，改代码后调试很方便。

### 产物

```
entry\src\main\cpp\thirdparty\arm64-v8a\libpython3.12.a     静态库（整库链接进应用）
entry\src\main\cpp\thirdparty\arm64-v8a\include\*.h         头文件（含本次构建的 pyconfig.h）
entry\src\main\resources\rawfile\python\python312.zip       标准库（zipimport 直接加载）
```

### 模块取舍（由 sysroot 实际能力决定）

sysroot 里有 `zlib`，**没有** openssl / sqlite3 / libffi / libexpat / bz2 / lzma，于是：

| 启用 | 说明 |
|---|---|
| `math` `cmath` `_decimal` | 纯 C 实现 |
| `_json` `binascii` `_struct` `_random` | 基础能力 |
| `zlib` | 链接 sysroot 的 `libz.so` |
| `_socket` | 网络套接字（OHOS 支持） |
| `hashlib` 内置算法 | CPython 3.12 自带 HACL* 实现，**不需要 OpenSSL** |

| 禁用 | 原因 |
|---|---|
| `_ssl` `_hashlib` | 没有 OpenSSL → **pip 不能走 HTTPS 访问 PyPI**（离线装本地 wheel 仍可用） |
| `_ctypes` | 没有 libffi |
| `_sqlite3` | 没有 sqlite3.h |
| `_bz2` `_lzma` | 没有 bzlib.h / lzma.h |
| `pyexpat` | 没有 expat |
| `test` 系列 | `--disable-test-modules` 等价处理 |

### 嵌入方注意（CMakeLists 已处理）

- 静态库必须 **整库链接**：`-Wl,--whole-archive libpython3.12.a -Wl,--no-whole-archive`，
  否则 `PyInit_*` 与内建扩展模块符号会被链接器丢弃。
- 额外链接 `z dl m`。
- `pyconfig.h` 必须与本次构建一致（`--outdir` 旁边的 `include/` 里那份）。

## 3. 签名与安装

1. DevEco Studio → `File > Project Structure > Signing Configs` → 勾选
   `Automatically generate signature`（需登录华为开发者账号）
2. 重新构建，产物变为 `entry-default-signed.hap`
3. 安装：

```powershell
hdc list targets
hdc install -r entry\build\default\outputs\default\entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.harmonyide.python
```

## 4. 模拟器（平板 / 鸿蒙 PC）

本机已下载的模拟器镜像：

- `HarmonyOS-6.1.1 tablet_x86` —— 鸿蒙平板
- `HarmonyOS-6.1.1 pc_all_x86` —— 鸿蒙 PC

注意模拟器是 **x86_64**：要用 `-Abi x86_64`（或 `both`）编一份 `libpython3.12.a`，
否则模拟器里只会看到"运行时未就绪"的提示。
`entry\build-profile.json5` 的 `abiFilters` 已同时包含 `arm64-v8a` 与 `x86_64`。

## 5. 常见构建错误

| 报错 | 原因 | 解决 |
|---|---|---|
| `api version parameter is illegal!` | `compatibleSdkVersion` 用了旧格式 | 改成 `26.0.0` |
| `spawn java ENOENT`（PackageHap 阶段） | PATH 里没有 java | 把 `D:\DevEco Studio\jbr\bin` 前置到 PATH；用 `scripts\build-hap.ps1` |
| `ENOENT ... \.hvigor\project_caches\<hash>\workspace\node_modules\@ohos\hvigor\bin\hvigor.js` | hvigor 工程缓存被并发/中断构建写坏 | 删掉 `%USERPROFILE%\.hvigor\project_caches` 重试；**不要并发跑两个 hvigor** |
| `The resource reference '$media:background' is not defined` | 少了 layered icon 的两张 PNG | `python scripts\make-icons.py` |
| `use of undeclared identifier 'Py_file_input'` | 未定义 `PY_RUNTIME_AVAILABLE` 时缺 Python 宏 | 已在 `napi_init.cpp` 提供兜底宏 |
| `Cannot find name 'KeyCode'` | `KeyCode` 不是全局枚举 | `import { KeyCode } from '@kit.InputKit'` |
| `Property 'size' in type 'IconXxx' is not assignable to ... 'CustomComponent'` | struct 成员名与通用属性同名 | 改名（本项目：`size` → `iconSize`） |
| `arkts-no-structural-typing` | 本地接口与原生 d.ts 接口互赋值 | 内联字面量 / 只读字段，别声明同名接口 |
| CMake WARNING：未找到 `libpython3.12.a` | 还没编运行时 | 跑 `scripts\build-cpython-ohos.ps1`；或忽略（App 仍可编译运行，只是不能执行 Python） |
| `couldn't create signal pipe` (MSYS) | 本机 MSYS 环境不可用 | 不要用 configure/make，用纯 Python 的 `ohos_cpython_build.py` |

## 6. 运行时契约校验（没有签名条件时的替代验证）

本机没有可用签名材料，无法把 HAP 装到真机/模拟器，因此**没有真机运行验证**。
为了尽可能把风险前移，提供两个可在上机前跑完的检查：

```powershell
# 1) HAP 打包是否完整、运行时是否真的链进去了
python scripts\verify-hap.py entry\build\default\outputs\default\entry-default-unsigned.hap --expect-runtime

# 2) 随包标准库在"设备同款搜索路径"下是否够用
python scripts\verify-runtime-contract.py `
    --zip entry\src\main\resources\rawfile\python\python312.zip `
    --archive entry\src\main\cpp\thirdparty\arm64-v8a\libpython3.12.a
```

第 2 条的做法：用**同版本的宿主 Python 3.12.10**，把 `sys.path` 设成
`[<临时 site-packages>, <我们的 python312.zip>]`（**刻意不含宿主标准库**），再导入
69 个 IDE 宣称可用的模块并跑 16 项功能探针。实测：

```
imported 69/69, 其中 53 个 __file__ 落在 python312.zip 内（zipimport 生效）
libpython3.12.a 内含 77 个 PyInit_* 内建模块
RESULT: PASS（arm64-v8a / x86_64 均通过）
```

它的边界也要说清楚：C 扩展在**真机**上的运行行为（`socket` 实际收发、`_posixshmem`、
`os.fork` 这类在鸿蒙沙箱里会失败的能力）无法在宿主上验证，必须上机。

### 6.1 调试钩子的语义校验

调试器的 Python 半内嵌在 `entry\src\main\cpp\napi_init.cpp`（设备上没有源码树可读），
所以另写了 `scripts\verify-debug-hook.py`：它从 C++ 源码里**抽取真实钩子**，用桩 `_pyide_bridge` 驱动，断言断点命中、单步行序列、作用域过滤（不跟标准库）、
停止语义（SystemExit(130) 且后续代码不执行）、无断点不暂停、调用栈快照，共 6 个场景 → **RESULT: PASS**。改调试钩子后务必重跑这一条。
