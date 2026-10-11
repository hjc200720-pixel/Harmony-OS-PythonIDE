# 架构与关键取舍

## 1. 总体分层

```
┌──────────────────────────── ArkTS / ArkUI（UI 线程） ────────────────────────────┐
│  pages/Index.ets                 界面外壳、状态中心、动作分发                     │
│  view/*                          纯展示组件（主题全部来自 common/Theme.ets）      │
│  service/PyRuntimeService        运行时生命周期、输出订阅、run/repl/pip          │
│  service/FileService             沙箱文件系统、工程树、导入导出                   │
│  service/SettingsService         设置持久化                                       │
│  service/PyHighlighter           Python 词法着色（纯函数）                        │
└───────────────────────────────┬──────────────────────────────────────────────────┘
                                │  NAPI（Promise + ThreadSafeFunction 回调）
┌───────────────────────────────▼────────────── 原生层（Worker 线程） ─────────────┐
│  cpp/napi_init.cpp               模块注册、异步任务、GIL 管理、输出回流           │
│  libpython3.12.a（静态库，整库链接）  CPython 3.12.10 解释器 + 内建扩展模块        │
│  内建模块 _pyide_bridge          Python 侧 sys.stdout/stderr 的写入口            │
└──────────────────────────────────────────────────────────────────────────────────┘
```

**为什么用静态库整库链接（`-Wl,--whole-archive`）而不是动态库？**
鸿蒙应用沙箱里 `dlopen` 自有 `.so` 需要处理 `libs/<abi>` 打包与命名空间，
而静态库 + `--whole-archive` 直接把 CPython 编进 `libpythonbridge.so`：
少一个动态依赖、少一次加载、也避免了 `PyInit_*` 与内建模块符号被链接器丢弃。

## 2. 线程模型（最容易踩坑的地方）

1. `initialize()` 在 **NAPI 异步工作线程**上执行：`PyImport_AppendInittab("_pyide_bridge", ...)`
   → 填 `PyConfig`（`home`、`program_name`、`module_search_paths`、`argv`、关掉 `use_environment`）
   → `Py_InitializeFromConfig()`。
2. 初始化完成后立刻 **`PyEval_SaveThread()` 交出 GIL**——否则 JS 线程会永久持有 GIL，
   后续任何工作线程执行 Python 都会死锁。
3. 之后每次执行（`runFile` / `runCode` / `runRepl` / `pipInstall`）都在工作线程上
   `PyGILState_Ensure/Release`，并且额外用一把互斥锁串行化——解释器状态是全局的，
   同一时刻只允许一段脚本在跑。
4. UI 线程**永远不执行 Python**，所以界面不会被 `time.sleep(60)` 冻住。
5. 中断：`PyErr_SetInterrupt()` 是异步信号安全的，可以从任意线程调用。

## 3. 输出回流（为什么 print 是实时的）

```
Python  print("x")
  └─ sys.stdout 已被替换为 _PyIdeWriter → import _pyide_bridge; _pyide_bridge.emit(0, "x\n")
       └─ C: BridgeEmit() → EmitStream() → napi_call_threadsafe_function(tsfn, msg)
            └─ JS 线程 CallJsOutput() → ArkTS 回调 → PyRuntimeService.dispatch()
                 └─ Index.appendOutput() → @State logEntries 增长 → 控制台重绘
```
同时 C 侧会把输出累积到本次运行的 `stdout/stderr` 缓冲，Promise 的返回值里也带上，
这样"实时滚动"和"拿到完整结果"两种需求都满足。

## 4. 编辑器的实现取舍（本项目最关键的 UI 决策）

ArkUI 里做语法高亮有两条路：

| 方案 | 问题 |
|---|---|
| `RichEditor` + 逐 token `updateSpanStyle` | 每次按键要对成百上千 token 发 N 次样式更新，每次都可能触发布局；长文件必然掉帧；且无法方便地加行号槽/断点槽 |
| **分层叠加（本项目采用）** | 见下 |

```
Scroll(垂直)
└─ Scroll(水平)
   └─ Row
      ├─ Column  行号 + 断点槽（逐行 Row，高度固定 = 行高）
      └─ Stack
         ├─ Column  高亮层（逐行 Row → Text{ Span... }，maxLines(1)，高度固定 = 行高）
         └─ TextArea  字体颜色全透明（只负责光标、选区、IME、键盘），高度固定 = 行数 × 行高
```

要点：
- **行高由我们自己固定**（`fontSize × 1.5`），两层每一行都强制同高，因此光标与高亮**必然对齐**，
  不依赖字体度量是否精确。
- 每次按键只做一次 `O(n)` 词法扫描（`PyHighlighter.tokenize`）并把结果切成"每行 spans"，
  渲染期不再做任何词法计算。
- 高亮层用 `maxLines(1) + TextOverflow.Clip` 禁止换行，输入层宽度取 `最长行 × 字符宽 + 余量`，
  两者都不换行，纵向位置一一对应。
- 代价：**不虚拟化**，整个文件都在渲染树里；超大文件会有压力（见 README 已知限制）。

## 5. 文件系统：为什么工程放在沙箱里

原生 CPython 是普通 POSIX 进程内代码，它看到的是真实文件系统。要让 Python 的 `open()` 与
ArkTS 的 `@ohos.file.fs` 指向同一批文件，最省事、最可靠、且**不需要任何权限**的位置就是
应用沙箱：`context.filesDir/PyProjects`。
因此：

- 工程树、编辑器读写、Python 运行三者路径完全一致，**没有映射层**，也就没有"编辑器保存了但
  Python 读不到"这类问题。
- 想交付成果时用系统文件选择器导出（`DocumentViewPicker.save`），导入同理
  （`DocumentViewPicker.select` + `copyFileSync`），全程无需申请存储权限。
- 设置与断点也存在 `filesDir` 下（`preferences` 数据库 + `breakpoints.json`）。

## 6. 主题系统

`common/Theme.ets` 是唯一色值来源：`PyTheme` 类持有全部令牌，导出 `DARCULA` / `INTELLIJ_LIGHT`
两个实例，`themeByName()` 取用。组件一律 `@Prop theme: PyTheme` 传入，**禁止写死色值**，
所以切换主题只需在 `Index` 里换一个实例，整棵树自动重绘。

## 7. 原生运行时缺失时的降级路径

`CMakeLists.txt` 先探测 `thirdparty/<abi>/libpython3.12.a`：
存在 → 定义 `PY_RUNTIME_AVAILABLE` 并整库链接；不存在 → 打一条 CMake WARNING 照常编译。

`napi_init.cpp` 里所有 Python 调用点都被 `#ifdef PY_RUNTIME_AVAILABLE` 包住，
未链接时每个接口都返回明确的"运行时未就绪 + 怎么修"的中文提示。
这样保证：**任何时刻工程都可编译、可安装、可演示**，而不是"缺一个库就编译不过"。

## 8. ArkTS 严格模式踩坑记录（写给后来者）

ArkTS 不是 TypeScript，以下限制在本项目里都真实踩到了：

| 限制 | 表现 | 规避 |
|---|---|---|
| `arkts-no-structural-typing` | 本地声明的接口即使字段与原生 d.ts 完全一致也不能互相赋值 | 入参**内联对象字面量**由参数类型推断；出参**只读字段**不整体赋值 |
| `arkts-no-any-unknown` | 未解析的类型会被当成 `any` 报错 | 显式标注；确认 `@kit.*` 是否真的导出了该类型 |
| struct 成员不能与通用属性同名 | `@Prop size` / 方法 `backgroundColor()` 与 `CustomComponent` 冲突 | 改名（本项目：`size` → `iconSize`） |
| `arkts-no-standalone-this` | 文件级函数里用 `this` 报错 | `@Builder` 写成 struct 成员方法 |
| 组件属性不能挂错 | `Stack` 没有 `alignItems`、`ForEach` 没有 `onClick` | 查 SDK `component/*.d.ts` 再写 |
| `build()` 单根节点 | 根容器前写局部语句会报"只能有一个根节点" | 需要预处理就调用私有方法，或把 `const` 挪到方法里 |
| `KeyEvent` 无 `ctrlKey` | 无法直接判断 Ctrl 组合 | 用 `.keyboardShortcut('s', [ModifierKey.CTRL], cb)` |


## 9. 调试器（行级断点 / 单步 / 变量快照）

```
ArkTS: 断点槽点击 → EditorTab.breakpoints[]   ──┐
                                                │ collectBreakpoints() → {"<路径>": [行号]}
                                                ▼
        PyRuntimeService.runDebug(path, args, breakpointsJson, rootsJson)
                                                │ NAPI（工作线程）
                                                ▼
C++:    debugRun() → 注入 kDebugHookScript 到 __main__
                    → _pyide_configure(断点, 工程根)
                    → _pyide_install()          （sys.settrace）
                    → PyRun 用户脚本
                                                │
Python: _pyide_trace(frame, 'line', ...) 命中 → _pyide_snapshot(frame)
                    → _pyide_bridge.pause(kind, payload_json)
                                                │ emit(stream=2, payload)
                                                ▼
ArkTS:  调试面板刷新（变量 / 调用栈 / 暂停行高亮）
                                                │ 用户点 继续/单步/停止
                                                ▼
C++:    debugCommand(cmd) → 条件变量唤醒 pause() → 返回 'continue'|'step'|'stop'
```

设计要点与取舍：

- **为什么 `sys.settrace` 而不是 `sys.monitoring`**：settrace 在 3.12 上语义稳定、实现短；
  调试本来就慢，性能不是约束。
- **作用域过滤**：`call` 事件只对**工程根目录内**的帧返回局部 trace 函数，标准库不跟。
  既避免"单步掉进 importlib"，也把开销降了一个量级（实测 5 次暂停全在工程内）。
- **暂停 = 阻塞**：`pause()` 在 C++ 条件变量上等待，解释器线程原地挂起（仍持有 GIL）。
  因为 `debugCommand` 只设一个 C++ 标志并 notify、不需要 GIL，所以 UI 线程永远不会被卡住；
  超时（10 分钟）按 stop 处理，避免 UI 异常时解释器永久挂死。
- **停止语义**：钩子抛 `SystemExit(130)`，复用既有的 SystemExit 路径（退出码 130、无 traceback）。
  于是"调试停止"与"普通中断"在控制台里表现一致，不污染输出。
- **对普通运行零影响**：不装 trace 时（`runFile`/`runCode`）没有任何额外开销；
  钩子自身异常会立即卸载 trace，绝不拖垮用户程序。
- **变量只做 repr 快照**：一次暂停取 200 个局部变量、每个 repr 截断 400 字符、栈深 32 层，
  保证跨 NAPI 边界的 JSON 不会失控；更丰富的对象展开留给路线图。
