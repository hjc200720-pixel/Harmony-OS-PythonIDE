# 鸿蒙 Python IDE（HarmonyPyIDE）

面向 **鸿蒙平板（HarmonyOS tablet）** 与 **鸿蒙 PC（HarmonyOS 2in1）** 的原生 Python 集成开发环境。
界面按 **PyCharm New UI** 复刻（Darcula / Light 双主题、中文界面），Python 运行时是
**交叉编译后静态链接进应用进程的 CPython 3.12.10**——不是网页方案、不是远程解释器、也不是脚本壳。

| | |
|---|---|
| 工程名 | HarmonyPyIDE |
| 包名 | `com.harmonyide.python` |
| 目标设备 | `tablet`（鸿蒙平板）、`2in1`（鸿蒙 PC / MateBook Pro） |
| 编译 SDK | HarmonyOS 26.0.0（API 26），DevEco Studio 6 |
| 界面 | ArkTS / ArkUI 声明式 UI（纯原生，无 WebView） |
| 运行时 | CPython 3.12.10 静态库（46.6 MiB / 230 对象）+ NAPI 桥接（`libpythonbridge.so`） |
| 目标 ABI | `arm64-v8a`（平板 / 鸿蒙 PC 真机）与 `x86_64`（模拟器）**均已内嵌运行时**并通过符号自检 |

---

## 一、交付验收结果（本机实测）

```
ArkTS 编译错误        0（仅 WARN）
原生编译              arm64-v8a / x86_64 两个 ABI 均通过
HAP 链接              无未定义符号
BUILD                 SUCCESSFUL

entry-default-unsigned.hap                 26.90 MB / 22 个条目
├─ libs/arm64-v8a/libpythonbridge.so        9.18 MiB（HAP 内，已 strip）  ← 内嵌 CPython
│  └─ 未链接运行时时仅 244 KB；链接后 31.28 MB（未 strip）
├─ libs/x86_64/libpythonbridge.so           9.38 MiB（HAP 内，已 strip）  ← 内嵌 CPython，模拟器
│  └─ 未 strip 31.76 MB
├─ resources/rawfile/python/wheels/pip-25.0.1-py3-none-any.whl  1.76 MiB（首次启动解压进 site-packages）
├─ resources/rawfile/fonts/FiraCode-Regular.ttf + -Bold.ttf  0.60 MiB（OFL，代码区等宽字体）
├─ resources/rawfile/fonts/OFL-FiraCode.txt  4 KB（OFL 要求随字体分发许可证全文）
├─ resources/rawfile/python/python312.zip   2.48 MiB（533 个标准库文件）
├─ ets/modules.abc                          638 KB
└─ module.json / resources.index / pack.info
```

运行时符号自检（`llvm-nm --dynamic --defined-only`）实测命中：
`Py_InitializeFromConfig`、`PyRun_SimpleStringFlags`、`Py_CompileString`、`_PyRuntime`、
`PyGILState_Ensure`、`PyEval_SaveThread`、`Py_GetVersion`、`Py_FinalizeEx`；
内建模块 `PyInit__io` / `PyInit__json` / `PyInit_math` / `PyInit_zlib` / `PyInit__socket` /
`PyInit__decimal` / `PyInit_posix` 等已就位。

复核方式（本次交付实际执行的、单写者、干净重建）：
`powershell -File scriptsuild-cpython-ohos.ps1 -Abi both` → `powershell -File scriptsuild-hap.ps1 -Clean` → `python scriptserify-hap.py <hap> --expect-runtime`（已 PASS）。


**运行时契约校验**（本机没有签名材料、无法上机，这是最接近实机的替代验证）：

```powershell
python scripts\verify-runtime-contract.py `
    --zip entry\src\main\resources\rawfile\python\python312.zip `
    --archive entry\src\main\cpp\thirdparty\arm64-v8a\libpython3.12.a
```

它在**与设备上 `PyConfig.module_search_paths` 完全一致**的搜索路径下
（`[<沙箱>/site-packages, <沙箱>/python312.zip]`，不带宿主标准库）导入 IDE 宣称可用的模块：

```
imported     : 69/69
from zip     : 53        （模块 __file__ 确实落在 python312.zip 内，即 zipimport 生效）
C modules    : 77        （libpython3.12.a 里静态链接的 PyInit_* 内建模块数）
功能探针     : zlib.crc32 / zlib 压缩往返 / hashlib sha256+md5+blake2b / json /
               decimal / math / datetime / re / unicodedata / xml.etree /
               tarfile+zipfile / threading+queue / asyncio / socket(AF_INET) —— 全部 OK
RESULT       : PASS（arm64-v8a 与 x86_64 两个静态库均通过）
```

它证明的是"包里的标准库是完整的、且 zipimport 真能加载"；
C 扩展在真机上的行为仍需上机验证（本机无签名条件，清单见 DEVICE-ADAPTATION.md 第 7 节）。

**断点调试器的验证**：调试器的 Python 半（断点匹配、单步、作用域过滤、变量快照、停止语义）
内嵌在 `napi_init.cpp` 里，因此专门写了 `scriptserify-debug-hook.py`——它**从 C++ 源码里抽出
真实钩子**，用桩 `_pyide_bridge` 驱动，跑 6 个场景：

```
OK  breakpoint hit + continue        命中断点 1 次；快照取在该行执行**之前**（locals 无 total）
OK  single step (3 pauses)           断点后两次单步 → 行号 5,6,7，kind = breakpoint,step,step
OK  scope filter (no stdlib frames)  5 次暂停全部落在工程目录内，未进入标准库
OK  stop -> SystemExit(130)          停止后断点行之后的代码确实没有执行
OK  no breakpoints -> no pauses      无断点则完全不暂停，脚本正常跑完
OK  call stack snapshot              调用栈最内层在前，链到 <module>
RESULT: PASS (6 scenarios)
```

另外确认钩子与暂停逻辑确实被编进了 `.so`（在 arm64 `libpythonbridge.so` 里能找到
`_pyide_trace` / `_pyide_snapshot` / `_pyide_configure` 等字符串）。

## 二、它现在能做什么

| 能力 | 状态 | 说明 |
|---|---|---|
| PyCharm 风格主界面 | ✅ | 主菜单栏、工具栏、左侧工具窗图标条、工程树、多标签编辑器、底部工具窗、状态栏 |
| Python 语法高亮 | ✅ | 自研词法着色：关键字/字符串/三引号文档串/f-string/数字/注释/函数名/类名/装饰器/self/内置函数 |
| 代码编辑 | ✅ | 行号槽、当前行高亮、断点槽（点击切换并持久化）、Tab 缩进、回车自动缩进（识别 `:` 补一级）、括号与引号自动配对 |
| 查找 / 替换 | ✅ | 面板式查找栏，上一个/下一个/替换/全部替换，命中计数 |
| 工程文件管理 | ✅ | 沙箱内工程树、新建文件/目录、重命名、删除、刷新、按名称过滤、示例工程一键生成 |
| 运行 Python | ✅ | 真 CPython；`print` **实时**回流到控制台，异常输出完整 traceback 与退出码 |
| Python 控制台（REPL） | ✅ | 同一解释器会话内输入，变量跨行保持，表达式自动打印 repr |
| 内置终端（受限） | ✅ | 支持 `python <文件>`、`python --version`、`pip install <包>` |
| 中断运行 | ✅ | 工具栏停止按钮 → `PyErr_SetInterrupt()`（等价 Ctrl+C） |
| 深/浅主题 | ✅ | 一键切换，配色对齐 PyCharm Darcula / IntelliJ Light |
| 平板/PC 响应式 | ✅ | 宽度断点 compact/medium/expanded；PC 可拖拽分栏、窗口自由拉伸、键鼠快捷键 |
| pip 安装 | ✅（离线） | 随包内置官方 pip wheel（`rawfile/python/wheels/pip-25.0.1-py3-none-any.whl`），首次启动由解释器解压进 `site-packages`，因此 `pip install --no-index --find-links <本地wheel目录> <包名>` 可用；**联网访问 PyPI 仍需先交叉编译 OpenSSL 启用 `_ssl`** |
| 断点调试 | ✅（行级） | 行断点命中即暂停，可**继续/单步/停止**；暂停时显示局部变量（含 repr）与调用栈；编辑器高亮暂停行并自动定位。调试钩子语义已用`scripts/verify-debug-hook.py` 在宿主上 6/6 验证 |
| 代码覆盖率 | ✅ | 「运行」菜单 →「运行当前文件并统计覆盖率」：用内嵌解释器的 `sys.settrace` 逐行统计**工程内** .py 的执行情况（含它 import 的模块），覆盖率工具窗按文件列出「命中/可执行行」与百分比条形，点文件跳到第一个未命中行；编辑器装订区绿竖条=命中行、红竖条=未命中行。统计脚本的语义已用 `scripts/verify-coverage.py` 在宿主上 87 项检查全通过（含跨文件精确覆盖、异常/sys.exit、只统计工程内文件、400 文件截断） |
| 端点（Endpoints） | ✅ | 静态 `ast` 扫描 Flask/Quart `@x.route(...)`、FastAPI/Starlette `@x.get/post/...`、Django `path()/re_path()/url()`，工具窗按「方法 + 路由 + 文件:行 + 框架」列出并支持点击跳转；零误报设计（拼接/变量路由不命中）。规则已用 `scripts/verify-endpoints.py` 在宿主上 9 个场景全通过 |
| 调试增强（条件断点/步入步出/watch 表达式） | ❌ | 路线图 |
| 自动补全 / 跳转定义 / 重构 | ❌ | 路线图 |
| 完整 shell 终端 | ❌ | 当前只做白名单命令，路线图 |

> **降级策略**：没有编译原生运行时时，工程照样能编译、能安装、能演示；IDE 会明确写出
> 缺什么、怎么补（`scripts/build-cpython-ohos.ps1`），编辑器与文件管理功能照常可用。

## 三、目录结构

```
HarmonyPyIDE/
├─ AppScope/                                 应用级配置与图标（layered icon）
├─ entry/
│  ├─ build-profile.json5                    模块构建配置（含 externalNativeOptions，双 ABI）
│  └─ src/main/
│     ├─ module.json5                        deviceTypes: ["tablet","2in1"]
│     ├─ ets/
│     │  ├─ entryability/EntryAbility.ets     入口 Ability（窗口背景、颜色模式）
│     │  ├─ pages/Index.ets                  主界面外壳 + 全部交互逻辑
│     │  ├─ view/                            UI 组件
│     │  │  ├─ CodeEditor.ets                代码编辑器（分层叠加式高亮）
│     │  │  ├─ MenuBarView.ets / ToolBarView.ets
│     │  │  ├─ ProjectTreeView.ets / ConsolePanelView.ets
│     │  │  ├─ StatusBarView.ets / WelcomeView.ets
│     │  │  └─ IdeIcons.ets                  矢量图标库（Path 绘制，零资源依赖）
│     │  ├─ service/
│     │  │  ├─ PyRuntimeService.ets          运行时生命周期、输出分发、运行/REPL/pip
│     │  │  ├─ FileService.ets               沙箱文件读写、工程树、导入导出
│     │  │  ├─ SettingsService.ets           设置持久化（首选项数据库）
│     │  │  ├─ CoverageService.ets           覆盖率：settrace 统计脚本 + 报告解析
│     │  │  ├─ EndpointService.ets           端点：Web 路由静态 ast 扫描 + 行解析
│     │  │  └─ PyHighlighter.ets             Python 词法着色器
│     │  ├─ model/Models.ets                 领域模型
│     │  └─ common/Theme.ets                 设计令牌（两套主题配色）
│     ├─ cpp/
│     │  ├─ napi_init.cpp                    NAPI 桥接 + 内嵌解释器 + 输出重定向
│     │  ├─ CMakeLists.txt                   链接 libpython3.12.a（存在才链接，否则降级）
│     │  ├─ types/libpythonbridge/           原生模块的 ArkTS 类型声明
│     │  └─ thirdparty/<abi>/                交叉编译产物（脚本生成，不入库）
│     └─ resources/rawfile/python/           随包标准库 zip（脚本生成，不入库）
├─ scripts/
│  ├─ build-cpython-ohos.ps1                 一键交叉编译运行时（含头文件收集 + 标准库打包）
│  ├─ ohos_cpython_build.py                  纯 Python 的 configure+make 替代实现（核心）
│  ├─ ohos_probe.py                           NDK clang 探测工具（头文件/函数/结构体/尺寸）
│  ├─ package-stdlib.py                      把 Lib/ 打成 python312.zip
│  ├─ build-hap.ps1                          命令行构建 HAP（自动处理 java/JBR 与缓存）
│  ├─ verify-hap.py                          HAP 结构与"运行时是否真的链进去"的校验
│  ├─ diagnose-undefined.py                  静态库未定义符号 vs 动态 libc 导出符号诊断
│  ├─ make-icons.py                          生成应用图标（Pillow）
│  ├─ verify-runtime-contract.py             无签名条件下验证随包标准库是否够用
│  ├─ verify-debug-hook.py                   从 napi_init.cpp 抽取真实调试钩子做语义验证
│  ├─ verify-coverage.py                     抽取覆盖率脚本，在宿主按设备搜索路径跑 6 场景
│  ├─ verify-endpoints.py                    抽取端点扫描脚本，宿主验证规则/负例/零误报
│  └─ device/                                模拟器真机验证脚本（启动/安装/dump/截图/点击）
└─ docs/
   ├─ ARCHITECTURE.md                         架构与关键取舍
   ├─ BUILD.md                                构建 / 签名 / 安装
   ├─ CPYTHON-PORT-NOTES.md                   CPython→OHOS 移植的踩坑与结论（强烈建议先读）
   ├─ DEVICE-ADAPTATION.md                    平板与鸿蒙 PC 适配清单
   ├─ FEATURE_AUDIT.md                        逐轮功能核查/实现/真机验证记录（最详细的一手记录）
   ├─ DELIVERY.md                             交付总览：能力地图 / 验证方法 / 已知边界
   └─ ROADMAP.md                              未完成项与后续计划
```

## 四、快速开始

### 1）打开工程
DevEco Studio → `File > Open` → 选择 `HarmonyPyIDE` 目录 → 等 Sync 完成。

### 2）命令行构建（已验证）
```powershell
# 本机只有 Windows PowerShell 5.1，用 powershell -File；装了 PowerShell 7 的话 pwsh -File 同样可用
powershell -File scripts\build-hap.ps1                     # debug
powershell -File scripts\build-hap.ps1 -Mode release
powershell -File scripts\build-hap.ps1 -ResetHvigorCache    # 遇到 hvigor 缓存 ENOENT 时
```
> ⚠️ 两个必踩的坑：① `compatibleSdkVersion` 必须写 `26.0.0`（不是 `6.0.2(22)`）；
> ② 必须把 DevEco 自带的 JBR 放进 PATH，否则 `PackageHap` 阶段会 `spawn java ENOENT`——
> 那时 ArkTS 其实已经编译通过了，很容易误判。`build-hap.ps1` 已自动处理这两点。

### 3）重新编译原生 CPython 运行时（可选；仓库里不带二进制产物）
```powershell
powershell -File scripts\build-cpython-ohos.ps1                # arm64-v8a（真机）
powershell -File scripts\build-cpython-ohos.ps1 -Abi x86_64     # 模拟器
powershell -File scripts\build-cpython-ohos.ps1 -Abi both       # 两个 ABI（顺序执行，已支持）
```
本机没有可用的 POSIX 环境（MSYS 程序一律 `couldn't create signal pipe` 启动失败），
所以 `scripts/ohos_cpython_build.py` **用纯 Python 重做了 configure+make**：
探测 sysroot 合成 `pyconfig.h` → 决定可编译模块 → 冻结 bootstrap 模块 → clang 并行编译 → llvm-ar 归档。
细节与全部踩坑记录见 [docs/CPYTHON-PORT-NOTES.md](docs/CPYTHON-PORT-NOTES.md)。

### 4）安装到设备
```powershell
hdc list targets
hdc install -r entry\build\default\outputs\default\entry-default-signed.hap
```
未配置签名时只有 unsigned HAP（能验证编译链路，不能装机）；
在 DevEco 里 `File > Project Structure > Signing Configs` 勾选自动签名后重新构建即可。

## 五、平板与鸿蒙 PC 的适配要点

- **一套代码两处运行**：`deviceTypes: ["tablet","2in1"]`，
  `supportWindowMode: ["fullscreen","split","floating"]` + `orientation: auto_rotation_unspecified`。
- **宽度断点驱动布局**：`compact(<720vp)` / `medium(<1100vp)` / `expanded`。
- **键鼠优先**：`F5` 运行、`Ctrl+S` 保存、`Ctrl+F` 查找、`Ctrl+N` 新建、`Ctrl+O` 打开
  （ArkUI 的 `KeyEvent` 不暴露 `ctrlKey`，所以走 `.keyboardShortcut(...)`）。
- 触屏：所有可点区域 ≥ 26vp，工程树长按呼出上下文菜单，日志可长按选中复制。

## 六、已知限制（诚实清单）

1. **调试器为行级实现**：已支持行断点、继续/单步/停止、局部变量与调用栈快照；
   仍缺条件断点、步入/步出、watch 表达式、暂停中修改对象等能力。
2. **编辑器不做虚拟化**：为保证光标与高亮像素级对齐，整篇文本一次性渲染；约 2000 行以上会卡。
3. **撤销/重做**依赖系统输入框能力，应用层未维护独立撤销栈。
4. **横向滚动时行号槽会一起移动**（纵向完全同步）。
5. **`wordWrap` 开关暂未生效**。
6. **pip 只能离线**：运行时未编入 `_ssl`（sysroot 无 OpenSSL）；
   `_ctypes`/`_sqlite3`/`_bz2`/`_lzma` 同样缺失（详见移植笔记的模块表）。
7. **工程目录在应用沙箱内**（`filesDir/PyProjects`）——这是唯一能让原生 Python 直接读写、
   且不需要任何权限的位置；导出/导入走系统文件选择器。
8. **签名**：当前用 DevEco 调试证书签名（可安装到模拟器/调试设备）；发布签名需在 AGC 申请证书后
   跑 `scripts/prepare-release-signing.ps1` 写入 `build-profile.json5`（见 [上架交接包](docs/RELEASE_HANDOFF.md)）。
9. **运行期能力受 sysroot 限制**：无 `_ssl`/`_hashlib`（→ 联网 pip 不可用）、`_ctypes`/`_sqlite3`/`_bz2`/`_lzma`
   缺失，IPv6 未启用（`socket.AF_INET6` 不可用）。另外 `os.fork`/`subprocess` 的宏虽然为真，
   但**鸿蒙应用进程不能 fork**，相关调用会在运行期失败——请当能力探测处理。完整清单见
   [移植笔记的模块表](docs/CPYTHON-PORT-NOTES.md)。
10. **验证设备**：功能验证主要在**物理平板 HUAWEI MatePad 11.5 S**（SLG-W50，2800×1840，HarmonyOS 7.0.0.111 / API 26，
    arm64）上完成；另用 DevEco「MateBook Pro」2in1 模拟器（3120×2080，x86_64）验证 2in1 形态与「首次安装」路径。
    尚未在鸿蒙 PC（arm64 2in1）物理真机上跑过，首次上机仍建议按 [DEVICE-ADAPTATION.md 第 7 节](docs/DEVICE-ADAPTATION.md) 复核。
11. **覆盖率**：统计会显著拖慢执行，因此只在手动点「运行并统计覆盖率」时挂 `sys.settrace`；
    数据只保留在本次应用会话内（未做落盘恢复）；目标自行调用 `sys.settrace` 或 `os._exit()` 属极端未覆盖情况。
12. **端点是纯静态扫描**：不解析 `include()` / 蓝图前缀（`Blueprint(url_prefix=...)`、`APIRouter(prefix=...)`），
    `methods=[变量]` 的路由直接跳过（宁缺勿错）；如需精确的框架感知能力，需在设备内装对应框架。

## 七、文档

- [架构与关键取舍](docs/ARCHITECTURE.md)
- [构建 / 签名 / 安装](docs/BUILD.md)
- [CPython 交叉编译移植笔记](docs/CPYTHON-PORT-NOTES.md)
- [平板与鸿蒙 PC 适配](docs/DEVICE-ADAPTATION.md)
- [路线图](docs/ROADMAP.md)
- [第三方许可与来源](docs/LICENSES.md)
