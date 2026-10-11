# 平板与鸿蒙 PC 适配清单

一套 ArkTS 代码同时服务两类形态差异很大的设备：**鸿蒙平板（tablet）** 与 **鸿蒙 PC（2in1）**。

## 1. 设备声明

`entry/src/main/module.json5`：

```json5
"deviceTypes": ["tablet", "2in1"],
"supportWindowMode": ["fullscreen", "split", "floating"],
"orientation": "auto_rotation_unspecified"
```

- `2in1` 让应用出现在鸿蒙 PC 的应用列表里，并获得桌面窗口语义（可拖动、可缩放、可最小化）。
- `floating` 让 PC 上可以悬浮窗运行，`split` 让平板上可以分屏。
- `auto_rotation_unspecified` 让平板横竖屏都能用（IDE 横屏体验最佳，竖屏自动切窄布局）。

## 2. 布局断点

`pages/Index.ets` 通过根容器的 `onAreaChange` 拿实时宽度，映射为三档：

| 断点 | 宽度 | 布局行为 |
|---|---|---|
| `compact` | < 720vp | 左侧工具窗变窄（220vp）或收起；底部控制台压到 160vp；弹窗宽度 320vp |
| `medium` | 720 ~ 1100vp | 左侧工具窗 ≤ 240vp；控制台常规高度 |
| `expanded` | ≥ 1100vp | 平铺：工具窗 + 编辑器 + 底部控制台三区同屏（PC 全屏、平板横屏） |

平板竖屏（约 800vp 宽）落在 `medium`，横屏（约 1280vp）落在 `expanded`；
鸿蒙 PC 的 MateBook Pro（约 3120×2080 物理像素）在窗口化时仍在 `expanded` 之上。

## 3. 指针与键盘

| 交互 | 触屏（平板） | 键鼠（PC / 平板接键盘） |
|---|---|---|
| 打开文件 | 点击工程树节点 | 单击（传统 IDE 行为） |
| 上下文菜单 | **长按**节点 | 右键（`bindContextMenu` + `ResponseType.RightClick`）/ 长按兜底 |
| 运行 | 点击工具栏 ▶ | `F5` |
| 保存 | 工具栏💾 | `Ctrl+S`（`keyboardShortcut`） |
| 查找 | 查找栏 | `Ctrl+F` |
| 新建 / 打开 | 菜单项 | `Ctrl+N` / `Ctrl+O` |
| 关闭查找栏 | 点 ✕ | `Esc` |
| 分栏宽度 | 拖动分隔条 | 拖动分隔条（鼠标拖拽，`PanGesture`） |

> `KeyEvent` 在 ArkUI 里不暴露 `ctrlKey`，所以 Ctrl 组合一律用
> `.keyboardShortcut('s', [ModifierKey.CTRL], cb)` 实现，而不是自己判断修饰键。

## 4. 触屏可用性细节

- 所有可点元素高度 ≥ 26vp（状态栏）～36vp（工具窗按钮），工具栏图标 16vp 但外框 28×28vp 可点。
- 编辑器：`TextArea` 在点击后自动拉起软键盘；`enableKeyboardOnFocus(true)` 保证聚焦即弹键盘。
- 底部控制台的日志用 `.textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)`，
  触屏可长按选中、复制。
- 自动缩进、括号配对、Tab 插入都对软键盘可用（不依赖物理 Tab 键）。

## 5. 窗口与安全区

- `EntryAbility.onWindowStageCreate` 里把窗口背景设为 `#FF1E1F22`，消除启动瞬间白闪。
- 颜色模式用 `COLOR_MODE_NOT_SET`（跟随系统），但 IDE 自身主题由设置里的 Darcula/Light 控制，
  两者不冲突。
- 未使用沉浸式全屏，避免平板横屏时内容被刘海/挖孔遮挡；分栏与状态栏都留系统安全区。

## 6. 性能与功耗

- Python 执行全部在 NAPI 工作线程，UI 线程不阻塞（`time.sleep` 也不会卡界面）。
- 输出回流走线程安全函数，控制台只保留最近 3000 条日志，超出后从头截断，避免内存膨胀。
- 编辑器不虚拟化是当前最大性能短板（见 README 已知限制），2000 行以内体验良好。

## 7. 平板/PC 上建议的验收用例

1. 冷启动 → 欢迎页出现 → 打开示例工程 → `main.py` 自动打开并高亮。
2. 点工具栏 ▶ 或按 F5 → 控制台实时输出 `你好, 鸿蒙!` 与 Python 版本、平台信息。
3. 制造异常（把 `print(` 写坏）→ 控制台出现完整 traceback、退出码非 0、状态栏提示失败。
4. 在行号槽点几下 → 出现红点；关掉再打开 App → 断点还在。
5. 新建文件 → 编译运行 → 保存，重启 App 后文件仍在（沙箱持久化）。
6. 平板：横竖屏来回切换，布局在 expanded/medium 之间平滑切换。
7. PC：把窗口拖到很窄（< 720vp），左侧工具窗收起、控制台变矮，功能仍可用。
8. Python 控制台输入 `1+1`、`x=5` 再 `x*2`，验证同一会话变量保持。
9. 终端输入 `python --version`、`pip install <本地whl包名>`（离线时用 `--no-index --find-links`）。
10. 切换主题（`Ctrl+Alt+T` 或状态栏主题项）→ 全界面配色即时切换，无残留深色块。
