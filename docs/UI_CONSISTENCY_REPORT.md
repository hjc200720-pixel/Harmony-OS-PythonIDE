# 界面一致性逐项核实报告（UI / 图标 / 文字）

**核实方法**：把 PyCharm 2026.2.2 安装目录（`lib/**/*.jar` + `plugins/**/*.jar`，共 **1369 个 jar**）里所有 `messages/*.properties` 抽出，
按内容含 CJK 过滤出 **183,101** 条本地化字符串（其中**无假名**的 100,595 条为中文/日汉字），再与应用的实际 UI 串做**精确比对**；
图标按 jar 内资源名与应用的 `rawfile/icons/*.svg` 比对。

> 说明：PyCharm 的中文来自本地化包，包里同时含日文；比对以「精确命中」为准，未命中项再按关键词人工判读，**不做推测**。

## 一、已确证的文字不一致（本轮已修）

| # | 应用原用词 | PyCharm 中文原文 | 依据 | 处理 |
|---|---|---|---|---|
| 1 | 继承层级 | **层次结构** | `action.ActivateHierarchyToolWindow.text` | 改为「层次结构」（含对话框标题）|
| 2 | 本地历史 | **本地历史记录** | `action.LocalHistory.ShowLocalHistory.text=显示本地历史记录(_H)` | 改为「本地历史记录」|
| 3 | 格式化代码 | **重新格式化代码** | ReformatCode 中文原文 | 已改 |
| 4 | 顶级菜单 VCS(S) | **版本控制**（中文界面不该混英文）| `group.vcs=版本控制系统`；应用其它处本就用「版本控制」 | 改为「版本控制(V)」|
| 5 | 检查未使用导入 | PyCharm 用「检查代码」统称 | — | 改为「代码检查」|
| 6 | 图表：当前文件关系图 | PyCharm 动作名就是「图表」 | — | 改为「图表」|

## 二、PyCharm 中查无此串（应用自造术语，未改动，供你定夺）

| 应用用词 | 说明 |
|---|---|
| 跨文件补全 | PyCharm 对应「基本补全／智能补全」；本应用是模块级跨文件补全，自名更准确 |
| 变更时间线 | PyCharm 用「本地历史记录」；本应用是全工程聚合视图 |
| 作用域视图 | PyCharm 对应「范围」 |
| 外部系统：任务与依赖 | PyCharm 是「外部工具」；构建系统集成不可做 |
| 比较当前文件与磁盘版本 | PyCharm 语义为「与本地文件比较」 |
| 循环补全／补全语句 | PyCharm 无此二名 |

## 三、图标核实（硬数据）

- PyCharm 安装包图标资源 **5199** 个；应用 `rawfile/icons` **98** 个。
- **56 个名称与 PyCharm 完全相同**：add · archive · branch · chevronDown/Right/Up · close · collapseAll · console · copy · csv · cut · debug · debug_stroke · delete · edit · execute · execute_stroke · expandAll · folder · gitignore · help · image · intentionBulb · json · library · libraryFolder · lightning · locate · moreVertical · paste · pause · project · python · redo · refresh · remove · replace · rerun · rerun_stroke · run · runAnything · run_stroke · save · scratches · search · settings · stop · stop_stroke · suspend_stroke · terminal · toml · undo · vcs · windowsMenu@20x20 · yaml。
- **42 个 PyCharm 中无同名**：集中在自造 `tw*` 工具窗图标（twProject/twProblems/twStructure/twTerminal/twVcs/twServices/twNotifications/twDatabase/twLearn/twDebug/twRun/twBookmarks/twCoverage/twTodo/twDeps/twVarView/twDataView/twBuild/twAi 及其 20 变体）与 pyConsole/pyPackages/projectRoot/nodeFolder/excludedFolder/fileText*。
  PyCharm 的真实命名体系是 `aiAssistantToolWindow`、`commit`、`OpenTerminal_13x13`、`ToolwindowBackground` 这类。
- **必须说明的边界**：以上只能证明**图标命名/来源不一致**；图标图形是应用自绘 SVG，**无法与 PyCharm 逐像素比对**，本报告不对图形本身下结论。

## 四、功能未做完 / 不完全（源码直接证据：37 + 43 处标记）

| 类别 | 具体项 | 现状 |
|---|---|---|
| 平台受限 | 文件级剪贴板 | 诚实提示暂未实现，可用复制路径 + 终端脚本代替 |
| 平台受限 | 只读标记（文件权限位）| 沙箱不开放，明确提示 |
| 平台受限 | 浏览器／差异视图跳转 | 沙箱不提供，提示尚未实现 |
| 引擎缺失 | 语义索引类动作（3 处入口）| 统一提示需要语义索引／差异视图／VCS 集成 |
| 引擎缺失 | 代码生成、代码模板环绕 | 提示暂未实现，可手动输入 |
| 能力缺失 | 独立窗口（多窗口）| 提示需要多窗口能力 |
| 能力缺失 | 插件系统 | 提示暂未实现；插件面板仅占位说明 |
| 能力缺失 | 不可见字符显示 | 编辑器覆盖层不渲染，提示不支持 |
| **占位工具窗 5 个** | 书签／覆盖率／端点／数据视图／Jupyter 变量 | 仅有工具窗外壳与空态文案，**功能未实现** |
| **占位工具窗** | TODO | 同上（源码为 ToolWindowInfo('TODO', …)）|

> 占位工具窗是「功能不完全」的主要残留：界面在、按钮名取自 PyCharm 的 action group，但点击不会产生真实结果（只有空态文案）。

## 五、本轮改动与验证

- 改动：6 处 UI 用词 + 2 处对话框标题，每处都附 PyCharm 依据
- 验证：构建通过 → 安装 → 真机确认新文案
## 六、真机验证结果（本轮）

| 项 | 真机结果 |
|---|---|
| 顶级菜单 | `文件(F) 编辑(E) 视图(V) 导航(N) 代码(C) 重构(R) 运行(U) 工具(T) **版本控制(V)** 窗口(W) 帮助(H)` ✓（原为 VCS(S)）|
| SE 首屏 | `转到符号 · 转到类 · 切换器 · **层次结构** · **代码检查** · 跨文件补全` ✓ |
| 层次结构对话框标题 | `层次结构` ✓（原为「继承层级」）|
| 本地历史记录 / 重新格式化代码 / 图表 | 三项改动已编译进包，但**不在首屏**，本轮未取得真机画面证据（如实标注）|

截图：`_cache/device/ui_menu.jpeg`、`_cache/device/ui_consistency.jpeg`

## 七、核实过程中新发现的两个问题

1. **死代码陷阱**：应用里 `MENU_TITLES`（Index.ets:556）**只被定义、从未使用**；真正的顶级菜单在 `view/MenuBarView.ets:526`。
   我第一次改的是死常量，设备上毫无变化 —— 说明**核实 UI 文案必须先找到真正的渲染点**（grep 使用点，而不是只 grep 字面量）。
2. **顶部栏拥挤**：截图显示运行配置「当前文件」与左侧工程微件在顶栏中部挤压/截断。列为待修 UI 问题。

## 八、结论（诚实边界）

- 已确证并修复 **6 处用词 + 1 处菜单标题**（每处都有中文包 key 依据）。
- **图标：只能证明命名/来源不一致（42/98 个 PyCharm 无同名），不能证明图形画错** —— 应用 SVG 为自绘，无法逐像素比对。
- **功能不完全的主要残留是 6 个占位工具窗**（书签/覆盖率/端点/数据视图/Jupyter 变量/TODO）与 8 类引擎缺失动作；这些在应用里都有**诚实提示**，不会误报成功。
- 本轮**未做**：逐项修复占位工具窗（工作量大，需你确认优先级）；图标重命名/替换（需要能拿到 PyCharm 的原始 SVG 授权与素材）。
## 九、两侧竖条（工具窗栏）逐项核实 —— 依据 PyCharm plugin.xml 的 anchor

从 1369 个 jar 内的 `plugin.xml` 抽出 34 个 `<toolWindow id=… anchor=…>`：

| 工具窗 | PyCharm anchor | 应用位置 | 判定 |
|---|---|---|---|
| Project | left | 左栏 | ✓ |
| Structure | left | 左栏 | ✓（改名「结构」）|
| Commit | left | 左栏（无 .git 时隐藏）| ✓ |
| AIAssistant | right | 右栏 | ✓（PyCharm 中文=AI 聊天）|
| Notifications | right | 右栏 | ✓ |
| Database | right | 右栏 | ✓ |
| Python Packages | right | 右栏 | ✓（改名「软件包」）|
| **Python Console** | **right** | ✗ 只出现在底部页签 | **❌ 已修：加入右栏** |
| Plots | right | 右栏（文字「绘图」）| ✓ 文字一致；但语义不同（应用是 Graph/图表）|
| SciView | right | 占位 | 中文名「数据视图」与应用一致 ✓ |
| Terminal / Problems View / Version Control / TODO | bottom | 底部页签 | ✓ |
| Gradle / Maven / Diagrams / Services | 未在已扫描 XML 中找到定义 | — | 待补提取（对应插件未含 plugin.xml 或未扫描到）|

### 本轮修复（真机已验证）

| # | 问题 | 依据 | 处理 |
|---|---|---|---|
| 1 | 左栏显示英文 **Structure** | `toolwindow.stripe.Structure`（中文=结构；`action.FileStructurePopup=文件结构(_I)` 佐证）| 改为「结构」✓ |
| 2 | 右栏显示英文 **Python Packages** | `toolwindow.stripe.Python_Packages_Tool=Python 软件包` | 改为「软件包」✓ |
| 3 | **Python Console 未出现在右栏** | `<toolWindow id="Python Console" anchor="right"/>` | 加入右栏 ✓ |
| 4 | 3 字标签被截断（「控制台」显示为「控制」）| 实测：37px 按钮放不下 3 个中文字 | 按钮加宽 37→44 ✓ |

截图：`_cache/device/rails6.jpeg`

### 仍是待解决的问题（如实）

- **语义错配**：应用的「绘图」实际打开 Graph/图表，而 PyCharm 的 `Plots`（绘图）是**数据绘图**；图标 `twPlots*` 亦为自绘。
- **`AI 聊天` 与 `Python 控制台` 在竖条里被折成两行**（应用用 `\n` 硬折行）—— 与 PyCharm「单行标签 + 自动折行」的视觉结果等价，但字符串不同。
- **Gradle / Maven / Diagrams / Services 的侧边归属未核实**：本次扫描的 34 个 toolWindow 定义里没有它们，需要从对应插件的 plugin.xml 再提取。
## 十、左栏核实结果 —— 与右栏同一类问题（已修）

**你的判断正确**：左栏确实也有「声明了但没接上」的问题，而且和右栏 Python Console 是同一种。

### 依据

| 来源 | 内容 |
|---|---|
| PyCharm plugin.xml | `<toolWindow id="Bookmarks" anchor="left"/>`（左侧）|
| 应用声明表 | `Index.ets:140 new ToolWindowInfo('Bookmarks', '书签', 'left', false)`（也声明在左侧）|
| 应用左栏实际渲染 | `project / learn / structure / commit / more` —— **没有书签** ✗ |

### 左栏对照 PyCharm（anchor=left 的 8 项）

| PyCharm 左侧工具窗 | 应用 | 说明 |
|---|---|---|
| Project | ✓ 左栏 | |
| Structure | ✓ 左栏（已改名「结构」）| |
| Commit | ✓ 左栏（无 .git 时隐藏，符合 PyCharm 行为）| |
| **Bookmarks** | **❌ 已修：加入左栏「书签」** | 点击打开应用内已有的书签占位面板 |
| Pull Requests / Merge Requests | 声明为 left，未渲染 | 需要 Git 托管集成，合理缺省（PyCharm 无对应仓库时也不显示）|
| Backup and Sync History / Commit_Guest | 声明为 left，未渲染 | 尚未实现 |
| Learn | ✓ 左栏「学习」| PyCharm 的 Learn 定义未在本次扫描的 XML 中出现（anchor 未知）|

### 修改内容

1. `sideLabel('bookmarks')` → 「书签」
2. `sideIcon('bookmarks')` → `icons/twBookmarks20.svg`（该图标已在资源里）
3. `onSideToolClick('bookmarks')` → `twPanelId = 'Bookmarks'`（打开应用已有的书签占位面板）
4. 左栏插入 `SideToolButton('bookmarks', 'left')`（位于「结构」之后）

### 真机验证（两次 dump 一致）

```
左栏: 项目 · 学习 · 结构 · 书签 · ⋯
右栏: 通知 · AI/聊天 · 数据库 · Gradle · Maven · 绘图 · 软件包 · 控制台
```

截图：`_cache/device/rails7.jpeg`（说明：该截图那一帧里右栏的「AI 聊天」未绘制，属**截屏时序假象**；
两次 `dumpLayout` 均确认 `AI/聊天` 节点存在且坐标稳定，故不是代码问题）。

### 复核中发现的工程性问题（重要）

**源文件是 CRLF 行尾**：我此前多次多行文本替换失败（如 `.width(37)\n.height(40)`），根因就是用了 `\n` 拼接模式；
改用 `\r?\n` 正则后一次通过。**结论：改这个仓库的 .ets 文件，多行匹配必须用 CRLF 兼容写法。**
## 十一、⋯（更多）按钮：三个连环缺陷（已全部修复并验证）

你指出「书签下面那个图标有问题」—— 查下去发现是**三个缺陷叠在一起**：

### 缺陷 1：图标实际不可见（根因）

```
moreVertical.svg: 16x16，三个圆 r=1（直径 2px），fill #6C707E
竖条按 iconSize=20 渲染 → 放大 1.25 倍后圆点约 2.5px，暗灰 → 肉眼等于没有
```

**修复**：新建 `rawfile/icons/moreVertical20.svg`（20x20，r=1.7），`sideIcon('more')` 改指它。真机确认三个点清晰可见。

### 缺陷 2：点 ⋯ 打开的是「设置」而不是工具窗列表

| 项 | 内容 |
|---|---|
| PyCharm 依据 | `toolwindow.action.more`（+ `toolwindow.action.more.count`）→ 「更多…」按钮 |
| 应用原实现 | `onSideToolClick('more')` → `handleAction('tools.settings')` ✗ |
| 修复 | → `dialogTitle='更多工具窗…'; dialog='toolWindows'` ✓ |

**重要发现**：应用**本来就写好**了 `ToolWindowsContent()`（按 left/right/bottom 分组、●已实现/○未实现、可点击打开）——
**只是 ⋯ 从来没调用它**。所以这是「接线漏了」，不是「没实现」。

### 缺陷 3：⋯ 同时画了图标 + 「⋯」文字（重叠）

`sideLabel('more')` 原返回 `'⋯'`，与图标叠在一起 → 改为空串，并让竖条按钮在标签为空时**不渲染 Text**。

### 顺带修掉的两个缺陷

| # | 问题 | 修复 |
|---|---|---|
| 4 | **弹层标题串味**：`showInfo()` 只设 `infoTitle`、不清 `dialogTitle`，导致 Gradle 说明框顶着上一个弹层的标题「更多工具窗…」| `showInfo` 中清空 `dialogTitle`；真机验证 Gradle 框标题为「Gradle」、无残留 ✓ |
| 5 | 声明表里 `Structure` 条目仍显示英文 | 改「结构」✓ |

### 真机验证（dump + 截图双重）

```
点 ⋯ (54,700) → 标题「更多工具窗…」；分组=['左侧','右侧']；○未实现=True ●已实现=True
可见条目: 版本控制 · 项目 · 书签 · 学习 · 通知 · 数据库 · Gradle · Maven · 绘图 …
左栏: 项目 · 学习 · 结构 · 书签 · ⋯（图标可见）
```

截图：`_cache/device/more_final.jpeg`、`_cache/device/final1.jpeg`

### 教训（第 21 条）

**「界面在但没反应」优先怀疑接线，而不是怀疑实现。** ⋯ 的例子：实现早就写好了，只是一个 onClick 指错地方；
而「图标看不见」这类问题要看**原始 SVG 的尺寸/线宽**，不能只看文件名对不对。
## 十二、右侧工具窗面板：标题与内容错位（用户报告「弹出 AI 聊天页、显示有问题」）

### 根因：标题与内容来自两个不同字段

```
面板标题 = toolWindowLabel(this.rightToolWindow)     ← 7877 行
面板内容 = toolWindowPanels().filter(p.id === this.twPanelId)  ← 原 10531 行
```

两者各自被写入，于是出现「标题写 AI 聊天、内容是书签」。触发路径：自定义界面里的「右侧工具窗」开关把
`rightToolWindow` 设成 **`'ai'`**（不是真实工具窗 id），而 `twPanelId` 仍停留在上一次的值。

### 修复（结构上消除错位）

| # | 修改 | 说明 |
|---|---|---|
| 1 | `ToolWindowPanelContent(panelId: string)` 改为**按传入 id 过滤** | 右侧面板传入「实际显示的」id，标题与内容**同源**，不可能再错位 |
| 2 | 弹窗调用处传 `this.twPanelId` | 保持弹窗语义不变 |
| 3 | 自定义界面开关 `'ai'` → `'AIAssistant'` 并同步 `twPanelId` | 去掉假 id |
| 4 | 新增 `AIAssistant` 占位面板条目 | 空态文案取自 PyCharm `welcome.screen.placeholder.aiAssistant` =「今天我能为您提供什么帮助?」；否则该面板会**空白** |
| 5 | 左栏「书签」按钮可切换关闭 | 与其它工具窗一致（原来只能开不能关，导致状态残留） |
| 6 | 通知弹层补 `dialogTitle='通知'` + **全仓清扫 20 处未设标题的弹层** | 消除「弹框标题延续上一个对话框」这一整类问题 |

### 真机验证（不过滤全屏 dump，含状态还原）

```
① 通知弹层: 标题『通知』 + 内容含「共 N 条通知」   ✓ 一致
② 点左栏书签: 面板标题『书签』+ 内容「本工程暂无书签」✓；再点一次 → 已关闭 ✓
   决定性 dump: y=220 x=2010 书签 / y=275 创建书签列表… / y=387 本工程暂无书签   ✓ 标题=内容
③ 还原检查: 更多工具窗=False · 书签面板=False · 通知弹层=False   ✓ 无残留
```

截图：`_cache/device/decisive.jpeg`、`_cache/device/clean.jpeg`

### 附带发现（与用户环境有关，非应用缺陷）

取证截图里出现**微信视频通话窗口**（爸爸 / 微信视频通话 / 接听·拒接）压在应用之上 —— 这是系统级来电悬浮窗，
不属于本应用；但它会盖住 IDE 界面，排查显示问题时需要先排除这类系统浮层。

### 教训（第 22 条）

**同一份 UI 的「标题」和「内容」必须来自同一个状态源。** 两处各自读取不同字段，就会出现标题与内容各说各话；
把内容构建器改成**接收 id 参数**，从结构上让二者不可能不一致 —— 比「记得两处一起改」可靠得多。