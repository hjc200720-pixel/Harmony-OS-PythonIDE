# UI 对齐自检（依据全部来自 PyCharm 实现文件）

> 生成方式：数值取自 PyCharm 安装目录的 jar/配置；状态由设备实测（`uitest dumpLayout`）核对。
> 复跑自检：`python _cache/device/verify_ui.py <设备>`、`python _cache/device/verify_geom2.py <设备>`、
> `python _cache/device/measure_key.py <设备> <tag>`（只统计本应用窗口，密度由状态栏 24vp 反推）

## A. 数值来源（每一项都能指到文件）

| 项 | 权威值 | 来源文件 |
|---|---|---|
| UI 字号 | **12** | `config/options/other.xml` → `fontSize = 12.0` |
| 小字号（竖条/状态栏） | **11** | 主题 `"fontSizeOffset": -1` → 12 − 1 |
| 左右竖条宽 | **50** | `config/options/ui.lnf.xml` → `TOOL_WINDOW_LEFT/RIGHT_SIDE_CUSTOM_WIDTH = 50` |
| 竖条项内边距（左） | `4,6,4,2` + 文字 +2 | 主题 `ToolWindow.Stripe.leftStripeIconWithName.padding` / `leftStripeTextOffset` |
| 竖条项内边距（右） | `4,2,4,6` + 文字 −2 | 主题 `rightStripeIconWithName.padding` / `rightStripeTextOffset` |
| 竖条项宽 | **42** = 50 − 6 − 2 | 由上面两项推出 |
| 竖条图标 | 20×20 单色 | `expui/toolwindows/*@20x20.svg`（共 88 个已盘点） |
| 树行高 | **24** | 主题 `rowHeight: 24`（compact 22） |
| 小岛圆角/间隙 | 8 / 4 | 主题 `Island.arc.compact 16`、`borderWidth.compact 4` |
| 标签内边距/下划线 | `-6,8,-6,8` / 高 **4** / 圆角 4 | 主题 `EditorTabs.tabInsets` / `underlineHeight` / `underlineArc` |
| 未选中标签透明度 | 0.75 | 主题 `EditorTabs.unselectedAlpha` |
| 工具栏按钮 | 内边距 `6,5,4,5`、圆角 **8**、图标 16 | 主题 `MainToolbar.Icon.insets` / `Button.arc.compact` |
| 状态栏 | 高 24、`topBorderWidth = 0`、底色 `main-window-bg` #26282C | 主题 `StatusBar.*` |
| 工具窗标题行 | `ContentTitle.insets 6,6,6,6`、gap 6、`tabContentActionsRightInsets 0,4,0,2` | 主题 `ToolWindow.Header.*` |
| 弹层边框 | `popup-border` = layer-1-border = #33353B | 主题语义链 |
| 菜单栏模式 | 与工具栏**合并成一行** | `ui.lnf.xml: SHOW_MAIN_MENU_MODE = MERGED_WITH_MAIN_TOOLBAR` |
| 竖条显示名称 | 是 | `ui.lnf.xml: SHOW_TOOL_WINDOW_NAMES = true` |
| 工具栏右组顺序 | **运行微件(first)** → AI → SearchEverywhere → SettingsEntryPoint → 试用(last) | 动作 XML 的 `add-to-group` 锚点 |
| 工具窗布局 | 左 Project/Commit/Structure、右 7 项、底 6 项 | `config/options/window.layouts.xml` |
| 工具窗总数/锚点 | 34 个（见 `PYCHARM_UI_SURFACES.md`） | 各 jar 的 `toolWindow` 注册 |

## B. 设备自检结果（真机 5VXUN25A11G01767 + 模拟器 127.0.0.1:5555）

复跑：`python _cache/device/measure_key.py <设备> <tag>`；底部工具窗用 `_cache/device/open_bottom.py <设备>` 打开。

### B1. 本轮几何（构建 → 双设备安装 → force-stop + 重启 → dump 复验）

| 项 | 真机（密度 2.5，窗口 2800×1840） | 模拟器（密度 ≈1.92，窗口 2090×1394） | 判定 |
|---|---|---|---|
| Project 岛 | (140,200)-(825,749) | (621,436)-(1142,881) | 顶边 == 编辑器岛顶边 ✓ |
| **Structure 岛底边** | **1131** | **1189** | **== 编辑器岛底边**（同一条线） ✓ |
| **编辑器岛底边** | **1131** | **1189** | 基准线 |
| 内容区底边 | 1146 | 1200 | = 岛底边 + 1×islandGap（两区都留同一份间隙） |
| **底部工具窗块顶边** | **1160** = 内容区底边 + 分隔条 14px | 1211 | 与岛底边相距 1×islandGap + 分隔条 ✓ |
| **底部工具窗四边** | **(140,1145)-(2645,1695)**：左 140=竖条+islandGap、右 2645=编辑器岛右缘、上 1145=内容区底边（与岛底边相距 1×islandGap）、下 1695=状态栏上方 1×islandGap | 同结构 | 四边都留 islandGap，与左右岛对齐 ✓（拖拽手柄改为叠加在岛上沿，不再多占一份间隙） |
| 底部工具窗右缘 | 2645 | 2488 | == 编辑器岛右缘 ✓ |
| Project↔Structure 间隙 | 15 = islandGap(6vp)×2.5 | 11 | **只由岛间分隔条提供一次**（两个岛自身 top/bottom margin 已归零） ✓ |
| 左列高度 | 961（= 内容区全高，padding 上下各 1×islandGap） | 775 | 底部工具窗隐藏时不再少算一份面板高 ✓ |

### B2. 交互与原生能力（hilog 实证）

| 项 | 证据（`hdc shell hilog | grep A01234`） |
|---|---|
| 左竖条自身拖拽 | `strip drag start self=left w=50` → `strip drag end self=left w=85.2`（`uitest uiInput swipe` 驱动） |
| 右竖条自身拖拽 | `strip drag start self=right w=50` → `... w=71.58` |
| 竖条边缘热区（根 Stack 最后一个子节点） | `strip drag start hotzone=left w=50` / `hotzone=right w=50` |
| 多语言高亮 | `highlight lang=Python ext=(py/pyw/pyi)` → 切到 README.md 后 `highlight switch lang=Markdown` |
| 状态栏「类型:」 | main.py → `类型: Python`；README.md → `类型: Markdown`（原来硬编码 Built-in） |
| 新建菜单 | 文件 ▸ Python 文件 → 语言列表（Python/Java/Kotlin/C++/JS/TS/Go/Rust/HTML/CSS/JSON/YAML/XML/Markdown/SQL/Shell/Dockerfile…） |
| 目录监听（native inotify） | `dirwatch start root=... ok=true`；保存文件后 `dirwatch events=[{"event":"modify","name":"main.py"},{"event":"closeWrite",...}]` |

### B2b. 岛底边对齐（2026-10-09 二次修正）

第一版把 Structure 岛底边对齐到「内容区底边」（真机 1146），比编辑器岛底边（1131）低了 1×islandGap，
视觉上仍不齐。现改为：左列 `.padding({top: islandGap, bottom: islandGap})`（与编辑器岛的上下 margin 同值），
于是 **Project 岛顶边 == 编辑器岛顶边、Structure 岛底边 == 编辑器岛底边**，双设备实测均为同一条线：
真机 1131/1131，模拟器 1189/1189。

### B2c. 官方布局收口：统一底色 + 无线条（2026-10-09）

**依据一：PyCharm 主题文件（权威，路径 `lib/intellij.platform.ide.impl.jar!themes/islands/ManyIslandsDark.theme.json`，已抽取到 `_cache/pycharm/theme/`）**

| 主题键 | 解析链 | 值 |
|---|---|---|
| `MainToolbar.background` / `.inactiveBackground` | main-window-bg → layer-1-bg → gray-30 | **#26282C** |
| `MainToolbar.borderColor` | transparent（工具栏下方无分隔线） | — |
| `MainToolbar.separatorColor` | toolbar-border → core-border-transparent | 透明 |
| `ToolWindow.Stripe.background` | main-window-bg → gray-30 | **#26282C** |
| `ToolWindow.Stripe.borderColor` | transparent | 无边框线 |
| `StatusBar.background` | main-window-bg → gray-30 | **#26282C** |
| `StatusBar.borderColor` / `topBorderWidth` | transparent / 0 | 状态栏无上边线 |
| `MainWindow.background` | main-window-bg → gray-30 | **#26282C** |
| `ToolWindow.background` | tool-window-bg → layer-0-bg → gray-10 | **#191A1C** |
| `editor-bg` | layer-0-bg → gray-10 | **#191A1C** |
| `tool-window-border` | layer-0-border → gray-30 | #26282C（与窗口底色同 → 无实线） |
| `Island.borderWidth` / `.borderColor` | 6 / tool-window-bg | 岛间隙 6vp |
| `main-window-bg-alt` | gray-40 | #33353B（仅作 layer-1-border/分隔线） |

**结论**：顶栏（MainToolbar）、左右竖条（Stripe）、状态栏（StatusBar）、窗口（MainWindow）在**主题文件里就是同一个 main-window-bg = #26282C**；
实机截图里顶栏偏绿是因为运行期按「项目颜色」（ProjectColorInfo）给标题栏叠了渐变，**不属于主题文件的值**。
本项目按文件实现 → 顶栏/竖条/状态栏/间隙统一 #26282C。

**依据二：PyCharm 实机截图逐像素扫描（`pc-geom.png` / `pc-max3.png` / `pc-now.png` 三张一致）**

| 采样位置 | PyCharm 实测 | 说明 |
|---|---|---|
| 竖条列 x=30（y=600 / H−20 / H−5） | **#26282C** | 竖条底色 = 窗口底色，**不是更亮的 #33353B**；且一直画到窗口底边 |
| 竖条与工具窗岛之间的间隙 x=70 | **#26282C** | 与竖条同色 → 顶栏 / 间隙 / 左右竖条是一个底色 |
| 工具窗岛 / 编辑器 | #191A1C | 岛色 |
| 窗口最下一行（状态栏） | #191A1C，且与上方编辑区**没有分界线** | 状态栏 topBorderWidth=0 |

**据此落地的改动**

1. 主题 `stripeBg`: #33353B → **#26282C**（与 `windowBg`/`toolbarBg`/`menuBarBg`/`border` 同色：顶栏 + 间隙 + 左右竖条统一）。
   顶部栏 / 顶栏下的间隙 / 左右竖条 / 状态栏 = **同一个底色层**（主题文件里都是 `main-window-bg`），
   颜色（项目绿）由**根层的一条竖向渐变**提供：顶部有色、向下平滑过渡到 #26282C。
   实现：根 Stack `.linearGradient({ angle: 180, colors: [[chromeTop,0],[chromeTopMid,0.06],[windowBg,0.18]] })`，
   顶栏行 / 左右竖条 / 状态栏底色全部改 `Color.Transparent`（StatusBarView 同步改）。
   这样既"有颜色"、又不会出现"某块有色另一块没色"的断层 —— 实测竖切（右竖条列）：
   `y92 #334934 → y185 #2C3C32（顶栏与下方间隙同色，无分界）→ y300 #28312E → y400 起 #27282C`。

   > 历史记录（已废弃的尝试）：曾按实机截图做过一版绿色渐变，但它反而把"顶部栏+间隙+底部栏"
   > 割成了不同颜色，与主题文件口径不符，已回退。

   以下是那次尝试留存的细节：
   （主题文件 `MainToolbar.background = main-window-bg`，实机那层绿是运行期 `ProjectColorInfo` 叠加）。
   做法：Index.ets 的顶栏行加 `.linearGradient({ angle: 90, colors: [5 个停靠色] })`，
   `MenuBarView` / `ToolBarView` 的根底色改 `Color.Transparent`，让整行渐变透出来。
   停靠色最初取实机剖面 y=55（`#272A2C → #2E3E32 → #334B35 → #2F4233 → #2D3B31`），
   但在 2800px 宽的窗口上偏灰、几乎看不出渐变，故按"看得见的渐变 + 更干净的颜色"重定：
   `#26282C(0) → #2C3B33(0.30) → #3A5A47(0.58，峰) → #30453A(0.78) → #26282C(1)`；
   浅色主题 `#F7F8FA → #EAF2ED → #D7E9DE → #E6F0E9 → #F7F8FA`。
   另加 `theme.headerTint`（纯色兜底 `#2F4238`）作为同一行的 `backgroundColor`：
   万一某个设备/版本不渲染 `linearGradient`，顶栏也只是纯色着色，不会露出灰底。
   于是顶栏**边缘≈窗口底色**（与下面背景融合）、中段带项目绿 —— 既像实机，又不出现"整块绿"。
   另外，**4 条拖拽分隔条**（Project↔Structure 水平条、左列↔编辑器竖条、编辑器↔右面板竖条、
   编辑器列内那条已停用的底部条）默认线色原来是 `theme.border`(#26282C) —— 过去与窗口底色同色看不出来，
   底部加了着色层后就变成"隐约的深色线"。按 PyCharm 的 splitter 做法改成**默认 `Color.Transparent`、hover 才显示 `funcName`**。
   复验（真机）：着色区横切 y=250 x682..694 = `#2B3534 → #293531 → #2A3531`（平滑，无线）；
   Project↔Structure 之间竖切 x=300 y750..762 = `#292A2C / #27282C / #25262A`（无线）。

   另外，顶栏里原来有 **3 条线把渐变切断**（这就是"看着割裂、绿色之间是另一个颜色"的来源），
   按主题 `MainToolbar.borderColor = transparent` 全部去掉：
   - `MenuBarView` 菜单段 `borderColor(theme.border)`（`MENU_BAR_EDGE` 下边 1px）→ `Color.Transparent`
   - `ToolBarView` 工具段 `borderColor(theme.border)`（`TOOLBAR_EDGE` 下边 1px）→ `Color.Transparent`
   - 顶栏下方 `Divider().color(theme.border)` → `Color.Transparent`（元素保留，只为维持 38vp 头高基准；
     它实际渲染成比窗口底色更深的 2px 暗线，实测 y=182–183 为 #212725，正是"另一块颜色"）

   复验（真机顶栏横向剖面，y=92）：`0.02 #24292D → 0.30 #2C3B34 → 0.58 #3A5947 → 0.86 #2B3A35 → 0.98 #252A2E`；
   y=178：`0.02 #27282C → 0.58 #395846 → 0.98 #292A2E`（两端回落到窗口底色）。

   复验（真机竖切 x=600 / x=2000，y 176→198）：改前 182–183 是 #24282B/#212725 的暗线，
   改后 182 #292D30 → 184 #27282D → 192 #27282C 平滑过渡到窗口底色，无暗线；
   模拟器同样（y 424 #25292A → 426 #27282C）。顶栏剖面真机
   `0.02 #262C2C → 0.55 #334B35 → 0.98 #2C3C2F`、模拟器 `0.02 #292A2E → 0.50 #334B35 → 0.98 #2B3B30`，
   与实机 PyCharm `0.03 #272A2C → 0.55 #334B35 → 0.97 #2D3B31` 一致。
2. 左竖条从「内容行内」移到根 Stack，与右竖条一样**通高**（主工具栏下方 → 状态栏上沿；状态栏同为 #26282C，视觉上继续到底），位置 `x=0`。
3. 去掉竖条与岛之间的分隔线：左竖条不再有 `border({right:1})`；栏与栏之间完全靠底色区分（`border = #26282C`）。
4. 内容行 `.padding({ left: 左竖条宽 })`、底部工具窗块 `.padding({ left: 左竖条宽 })` → 内容岛与底部工具窗都在竖条右侧开始，**竖条底部仍是统一底色**（这正是「左右两栏底部统一配色」）。

**复验（真机 5VXUN25A11G01767，d=2.5）**

| 采样 | 改前 | 改后 |
|---|---|---|
| 左竖条 (60,600) | #34353A | **#27282C** ✓ |
| 左竖条·底部工具窗那一行 (60,1400) | 被 #191A1C 面板盖住 | **#27282C**（面板已让位）✓ |
| 右竖条·面板那一行 (2740,1400) | #34353A | **#27282C** ✓ |
| 间隙 (132,600) | #26272B | #26272B（与竖条同色）✓ |
| 底部工具窗左缘 | 0（压住竖条列） | **125**（= 左竖条宽）✓ |
| 顶部栏横向剖面 | #2B382F（整块纯绿） | 渐变：0.02 #292A2E → 0.55 #354538 → 0.98 #313C36 ✓（实机 PyCharm：0.03 #272A2C → 0.55 #334B35 → 0.97 #2D3B31） |
| 模拟器 顶栏剖面 | — | 0.02 #292A2E → 0.50 #334535 → 0.98 #2B3B2E ✓（系统标题栏 #E6E5EA 属模拟器窗口装饰） |

### B2d. 项目区（按 PyCharm 文件对照修，2026-10-09）

**依据：PyCharm 安装目录里的动作注册与图标资源**

| PyCharm 文件/条目 | 内容 | 我方落地 |
|---|---|---|
| `impl/PlatformActions.xml` `<group id="ProjectViewToolbar">` | `<separator/> SelectInProjectView(AllIcons.General.Locate) → ExpandRecursively → ExpandAll(AllIcons.Actions.Expandall) → CollapseAll(AllIcons.Actions.Collapseall)` | 标题栏：`+ \| 定位 展开全部 折叠全部`（旧版那三个语义重复的 chevron 图标已删） |
| `impl/settings/cfg1.xml:7130-7134` | `NewElement` `add-to-group group-id="ProjectViewToolbar" anchor="first"` | 标题栏最左的 `+` |
| `intellij.platform.ide.jar!expui/general/locate.svg` | 定位图标（SelectInProjectView） | `icons/locate.svg`（**新增**） |
| `intellij.platform.ide.jar!expui/nodes/ideaProject.svg` | 工程根节点图标：文件夹 + 蓝色工程角标 | `icons/projectRoot.svg`（把 `fill="black"` 占位色换成 New UI 强调蓝 #3574F0） |
| `intellij.platform.ide.jar!expui/nodes/excludeRoot.svg` | 排除目录：橙色文件夹 | `icons/excludedFolder.svg`（**新增**） |
| `expui/general/{expandAll,collapseAll,add,moreVertical,search,refresh}.svg`、`expui/nodes/folder.svg` | 已在用的图标 | 与现有文件**逐字节相同**，无需替换 |

**项目树两个固定节点（PyCharm 里永远存在的同级节点）**

| PyCharm 节点 | PyCharm 图标 | 我方实现 | 验证 |
|---|---|---|---|
| 外部库（External Libraries） | `expui/nodes/library.svg`；子项 `expui/nodes/libraryFolder.svg` | 合成节点 `synthetic://external-libraries`，展开列出：`Python 3.12.10` / `site-packages`（真实路径 `filesDir/site-packages`）/ `ABI arm64-v8a` | 真机展开截图 ✓ |
| 临时文件和控制台（Scratches and Consoles） | `expui/fileTypes/scratches.svg` | 合成节点 `synthetic://scratches`，背后是真实目录 `filesDir/scratches`（不存在则创建），其中的文件可直接打开；为空时给一行提示 | 真机展开截图 ✓（当前为空 → 显示提示行） |

落地细节：`FileNode` 增加 `synthetic / iconFile / infoText` 三个字段；`refreshFlatten()` 里按需补这两个根节点（只补一次）；
`toggleDirByPath` 对合成节点走 `loadSyntheticChildren()`（不碰文件系统，或只碰 scratches 目录）；
点击合成叶子不当作文件打开，而是弹出该节点说明。另外修掉一个回归：合成节点也是 `depth === 0`，
最初会跟着工程根行一起把 `synthetic://…` 路径显示出来，现已只在真实工程根行显示路径。

### B2e. 顶栏（菜单栏 + 主工具栏）与顶栏右键菜单

**顶栏右键菜单的权威定义**是 `PlatformActions.xml:1864` 的
`<group id="ToolbarPopupActions.MainToolbarNewUI">`（New UI 用的就是这个；
更早误用的 `MainToolbarPopupActions`（ViewToolBar + CustomizeUI）是另一个面）：

| # | 动作 | 文案（ActionsBundle.properties） | 我方实现 |
|---|---|---|---|
| 1 | `MainToolbarQuickActions`（子菜单） | 将操作添加到主工具栏 | 子菜单：后退/前进、构建、全部保存（分别执行 `nav.back`/`run`/`file.saveAll`；构建如实提示） |
| 2 | `ChangeMainMenuModeActionGroup`（子菜单） | 主菜单 | 子菜单 = PyCharm 界面的三种模式：**隐藏在汉堡按钮下方 / 与主工具栏合并 / 显示在主工具栏上方**（`Index.setMenuMode`，hilog `main menu mode -> …`）。汉堡按钮图标 = `AllIcons.General.WindowsMenu_20x20`（`MainMenuButton.class` 常量池里引用的就是它）→ 已从 jar 取 `expui/general/windowsMenu@20x20.svg`。`hamburger` 模式下菜单栏不画、顶栏最左出汉堡按钮，点它列出 11 个顶级菜单 |
| 3 | `ChangeProjectColorActionGroup`（子菜单） | 更改项目颜色 | 子菜单 = **PyCharm 主题文件里的真实调色板**：`ManyIslandsDarcula.theme.json` 的 `RecentProject.Color1..9.MainToolbarGradientStart`（#664832 / #5E4724 / #45522F / #335661 / #394773 / #613861 / #503D70 / #325959 / #365439）；mid = 该色与 main-window-bg(#26282C) 按 55:45 混合。默认项目色改为 Color9 #365439（此前手测的 #334B35 其实是它渲染后的值）。选色**真的改顶栏渐变** |
| 4 | `WelcomeScreen.ChangeProjectIcon` | 设置自定义项目图标… | 如实提示未实现 |
| 5 | `ColoredHeaderAction`（勾选） | 显示项目渐变 | **真的开关顶栏那层项目色渐变**（`project gradient on=false`） |
| 6 | `MergeMenuWithWindowTitleAction` | 将主菜单与窗口标题合并… | 本 IDE 已是合并布局，如实提示 |

**主工具栏（MainToolbarNewUI）的权威构成**（`PlatformActions.xml:1072-1087`）：

| 组 | 内容 |
|---|---|
| `MainToolbarLeft` | `main.toolbar.Project`（项目微件，行内右侧由 MenuBarView 承载）+ `MainToolbarGeneralActionsGroup` |
| `MainToolbarCenter` | `main.toolbar.Filename`（运行配置选择器「当前文件 ⌄」） |
| `MainToolbarRight` | `ExecutionTargetsToolbarGroup` → `NewUiRunWidget`（anchor=first，见 ExecutionActions.xml:71-73）→ `SearchEverywhere`（随处搜索）→ `SettingsEntryPoint`（设置） |

`RunToolbarMainActionGroup`（ExecutionActions.xml:75-82）= 配置选择器 + 运行/调试执行按钮 + `Stop` + `MoreRunToolbarActions`（⋮）。

**修掉的显示 bug**：`MenuBarView` 根节点写了 `.width('100%')`，把同一行里的主工具栏**挤成 0 宽** ——
所以运行/调试/停止/随处搜索/设置这些按钮一直"存在但看不见"。去掉固定宽度后，工具栏按 PyCharm 实机配色渲染：
运行 = 绿色圆角块（#3E9B57）+ 白图标，停止 = 红色圆角块（#C0504D）+ 白图标，并在停止后补上 ⋮（`MoreRunToolbarActions`）。
另给菜单栏加 `constraintSize({ maxWidth: '62%' })`，保证工具栏尾部的 ⋮ / 随处搜索 / 设置不被挤出窗口右缘。
真机截图（修复后）：`… 帮助(H) | 示例工程 ⌄ | 当前文件 ⌄ | ▶(绿) | 🐞 | ⏹(红) | ⋮ | AI | 🔍 | ⚙` ✓

**运行小部件（NewUiRunWidget）的配色与 ⋮ 弹层**：

| 项 | 依据 | 实现 |
|---|---|---|
| 运行配置选择器「当前文件 ⌄」 | `ManyIslandsDarcula.theme.json` 的 `RunWidget`：`hoverBackground=#00000019`、`pressedBackground=#00000028`（**没有常驻底色**） | 默认 `Color.Transparent`（无框）→ hover `#00000019` → 展开/按下 `#00000028`。真机截图已确认方框消失 ✓ |
| ⋮（`MoreRunToolbarActions`） | `intellij.platform.execution.jar!messages/ExecutionBundle.properties`：`run.configurations.popup.edit.run.config.and.run.current.file=Run with Parameters…`（使用形参运行…）、`run.configurations.popup.existing.configurations.separator.text=Run Configurations`（运行配置 分组） | 弹层项：运行 / **使用形参运行…** / 调试 / ── / 运行配置 / 编辑配置… / 停止；「使用形参运行…」弹输入框，把形参按空格切分后走 `PyRuntimeService.run(path, args)` 真正带参运行（`runActiveFile(debug, args)` 已支持 args） |
| 运行/调试/停止图标（**以运行中的主题 ManyIslandsDark 为准**） | `RunWidget`：`iconColor=icon-default-stroke(gray-120)`、`runIconColor=icon-green-stroke(green-90=#4E9D6C)`、`runningBackground=accent-success-bg`、`stopBackground=accent-error-bg(red-80，darcula 同义值 #c94f4f)`。即**常态无底色**：运行 = 绿色描边三角、停止 = 灰描边方块；**只有运行中**才出现绿/红底。图标本体：`DefaultRunExecutor→AllIcons.Actions.Execute`(`actions/execute.svg`/`execute_stroke.svg`)、`StopAction→AllIcons.Actions.Suspend`(`actions/suspend.svg`/`suspend_stroke.svg`)、调试 `expui/run/debug.svg` | 已实现：常态 `execute_stroke_green.svg`（stroke=#4E9D6C）+ 透明底；运行中白描边 + `#4E9D6C` 绿底 / 停止白描边 + `#C94F4F` 红底；三个按钮图标统一 16vp（修掉"虫子比例不一致"）✓ 真机截图确认 |
| 顶栏三段布局（`MainToolbarNewUI`, PlatformActions.xml:1072-1087） | **Left** = `main.toolbar.Project`（项目微件）、**Center** = `main.toolbar.Filename`（当前文件微件，`FilenameToolbarWidgetAction`，常量池可见 `updatePresentationFromFile/getSelectedFiles/getFullPathsInWindowHeader`）、**Right** = 运行小部件（`anchor=first`）→ `SearchEverywhere` → `SettingsEntryPoint` | 已补上此前缺失的 **Center 当前文件微件**（工具栏中部显示 main.py）；运行小部件内部顺序（配置选择器 → 运行/调试 → Stop → More）与文件一致，**没有反** ✓ |
| 编辑器右上 ⋮ = **TabList**（`com.intellij.ide.actions.TabListAction`，PlatformActions.xml:883） | 条目按用户实机截图：最近的文件 / 最近的位置 / 转到文件… / 关闭所有标签页 / 书签打开标签页… / 配置编辑器标签页… / 显示缩略图 | **功能已补齐**：最近的位置（记录 打开文件+转到行 的 path#line，去重限 20，弹层点击打开并跳行）；书签（编辑器右键 切换书签 F11 / 显示书签 Shift+F11 + 书签列表对话框）；显示缩略图（真实开关，开启后弹层列出打开标签）✓ |
| 标签右键 = **EditorTabPopupMenu**（PlatformActions.xml:1134-1155） | CloseEditorsGroup / CopyPaths / Split* / MoveTab* / MoveToOppositeGroup / ChangeSplitOrientation / Unsplit(All) / PinActiveEditorTab / KeepTabOpen / EditSourceInNewWindow / ConfigureEditorTabs / ReopenClosedTab | 真实实现：移动标签（数组换位）、固定标签页、配置编辑器标签页、重新打开已关闭标签页；拆分类（本 IDE 单编辑器窗格）如实提示 ✓ |
| **两个菜单别混** | ⋮ = TabList（导航类）；标签上右键 = EditorTabPopupMenu（标签管理类） | 已分别实现 ✓ |
| MainToolbarCenter（当前文件微件）**何时显示** | `MacToolbarFrameHeader.isCompactHeader` 的判据是 `mainToolbarHasNoActions` —— 该微件**只在主工具栏没有任何动作的紧凑头部**才显示；主工具栏有动作时不显示 | 已**移除**之前误加在工具栏正中的 `main.py` 文件名（用户反馈"顶部栏怎么出现文件名了"属实）✓ |
| 运行小部件三个图标的**最终形态**（三轮收敛后） | **运行** = **绿色圆角块填充 + 白描边图标**（未跑过 \`actions/execute_stroke.svg\` 三角；跑过一次 \`expui/run/rerun_stroke.svg\` **圈圈箭头**）；**停止** = **红色圆角块填充 + 白描边圆角方块** \`actions/suspend_stroke.svg\`（rx=1.25）；**调试** = \`expui/run/debug_stroke.svg\` **线条**虫子、绿色描边、**无填充**（其余透明）。判定依据：\`run_stroke\`/\`execute_stroke\`/\`suspend_stroke\` 都是**白色**描边资源 —— 白描边只有配彩色底才可见；叠加 \`RunWidget.runningBackground=accent-success-bg\` 与 \`stopBackground=accent-error-bg\` 两个彩色背景键 | 真机截图确认：绿底白▶ / 绿线条虫子 / 红底白■ ✓（早前"无底色绿描边"与"实心绿虫子"两版均被推翻） |
| 运行小部件三个图标的**真实形态** | **运行**：未跑过 = `expui/run/run_stroke.svg`（即 `actions/execute_stroke.svg` 同形，白描边三角）；**跑过一次后** PyCharm 变成"重新运行"的**圈圈箭头** `expui/run/rerun_stroke.svg`（用户反馈"圈圈箭头、尾巴从播放开始绕"属实）；**停止**：`actions/suspend_stroke.svg` 是 `rx=1.25` 的**圆角**方块描边，配 `RunWidget.stopBackground`(red-80/#C94F4F) **红底常驻**；**调试**：`expui/run/debug_stroke.svg` = `fill="none"` 的**线条**虫子（用户反馈"线条纯绿"属实），着色 green-90 #4E9D6C、无底色 | 已实现：运行按 `hasRunOnce` 在 三角/圈圈箭头 间切换、停止常驻红底圆角块（未运行时用暗红 #7E3A3A 表示禁用）、调试改线条绿虫子 ✓ |
| 运行/停止常态图标色 | `RunWidget.iconColor=icon-default-stroke(gray-120)`、`runIconColor=icon-green-stroke(green-90 #4E9D6C)` | 运行=绿描边、停止=**灰**描边（此前误置白）、调试=彩色绿虫子，三者统一 16vp ✓ |
| 弹层背景"透明/只包一行" | — | 根因：**ArkUI 里绝对定位的 Column 会按首个子节点测高**，背景因此只包住第一行。修法：弹层显式给高（运行配置 160vp、⋮ 206vp）+ 定位写在弹层自身、外层不再套无尺寸容器。截图确认四行（✓当前文件 / 运行配置 / 使用形参运行… / 编辑配置…）都被背景完整包住 ✓ |
| MainToolbarCenter 的弹层 | `FilenameToolbarWidgetAction` 带 popup（常量池 `getSelectedFiles`/`getEditorTabPlacement`），列出打开的编辑器 | 点中间文件微件 → 弹「打开的编辑器」列表（图标+文件名+未保存圆点，点击激活）；dump 实测标题 `(867,775)-(1078,816)`、列表项 main.py ✓ |
| 运行配置/⋮ 弹层位置 | — | 改为**实测校正**：dump 里选择器文本 x=2025px、弹层曾落在 1557px（差 -468px=-187vp）→ 偏移常量 498→**351**；⋮ 弹层 420→**200**（⋮ 实测 ~1014vp）。校正后位置待再测一次（本轮被对话框挡住） |

| 主菜单默认模式 | `MainMenuDisplayMode` 首项为 `UNDER_HAMBURGER_BUTTON`，PyCharm 默认即"隐藏在汉堡按钮下方" | `@State menuMode = 'hamburger'` ✓ 真机默认截图确认（无菜单标题、☰ 在产品图标后） |

**图标全部取自 PyCharm jar（本轮补齐）**：New UI 的彩色运行/停止按钮用的是 `*_stroke` 白色描边图标，
已取 `expui/run/run_stroke.svg`、`expui/run/debug_stroke.svg`、`expui/run/stop_stroke.svg`（另取 `rerun_stroke.svg`、
`runAnything.svg`），运行/调试/停止组件改为加载这几个真图；`settings.svg / search.svg / moreVertical.svg / debug.svg`
与 PyCharm `expui` 里的同名文件**逐字节相同**，无需替换。

**右键菜单功能补齐（本轮）**：
| 项 | 现在的真实行为 | 验证 |
|---|---|---|
| 设置自定义项目图标…（`WelcomeScreen.ChangeProjectIcon`） | **导入图标文件**（不是从内置列表里挑）：打开系统文件选择器，只允许 `.svg / .png`，按 IntelliJ 约定复制到 `<项目>/.idea/icon.svg`（或 `icon.png`），随后项目树根用该图渲染（`IconFromPath` → `Image('file://…')`） | 真机：点该项弹出系统「选择文件」选择器（含文件格式过滤、已选 (0/1)）✓；选择后的渲染路径已实现并通过编译 |
| 将主菜单与窗口标题合并… | **真的切换**菜单栏"与主工具栏同行 / 独立成行" | `merge menu with title -> menuOwnRow=…` |
| 更改项目颜色 / 显示项目渐变 / 将操作添加到主工具栏 | 前两轮已实现 | `project color -> #2B3F55` 等 ✓ |

只剩「构建」一项是如实提示（本 IDE 没有独立构建动作，运行即构建并执行）。

**子菜单缺陷已修复**：根因是子菜单各自包在**没有尺寸的 Column** 里、自身又是 `.position()` 绝对定位，
父容器塌成 0 → 既画不出也点不到。现改为：菜单与子菜单全部作为**同一个全屏 `Stack`（已定尺寸）**的兄弟节点。
真机验证：点「主菜单」→ 三个模式项在 dump 里出现（`(2257,323)/(2257,384)/(2257,453)`）；
点「隐藏在汉堡按钮下方」→ `main menu mode -> hamburger`，菜单栏消失、汉堡按钮出现 ✓。
另修：子菜单固定往右展开、菜单靠右时会出界 → 右侧放不下改为翻到菜单左侧（`submenuX()`）。
汉堡按钮摆放：原先被我插成了独立一行 → 现已放回**顶栏 Row 的最左**（与 PyCharm 的 header 工具栏一致）。

**汉堡模式的最终形态（真机验证）**：☰ 与「Python 标识 + 工程微件 + VCS 微件」**同排共存**（PyCharm 的 `ToolbarFrameHeader` 里
`MainMenuButton` 与 `ProjectWidget` 本来就是同一排，所以不能把微件顶掉）；
点 ☰ 后菜单标题**横向展开**（PyCharm registry `ide.main.menu.expand.horizontal=true`，见 `util-8.jar`），
实测顶栏变成：`☰ | 🐍 | 文件(F) 编辑(E) 视图(V) 导航(N) 代码(C) 重构(R) 运行(U) 工具(T) VCS(S) 窗口(W) 帮助(H) | 示 示例工程` ✓
实现上给 `MenuBarView` 加了 `showTitles` 开关：`false` 时只保留左侧标识与右侧微件，`true`（点 ☰ 后）连菜单标题一起渲染。

**未完成项**：`SearchEverywhere` 目前接到已有的「在文件中查找」（`edit.findInFiles`）。
按 `action.SearchEverywhere.description`（搜索类、文件、工具窗口、操作和偏好设置）的专用对话框
（文件 + 操作两栏）写好后因插入位置切断了 `openTopMenu` 的方法签名导致整文件解析失败，已回退，
待下一轮以独立提交补上。

**位置自适应**（本轮修的第二个问题）：菜单位置 = 长按/右键的**实际坐标**（`GestureEvent.fingerList[0].globalX/globalY`、
`MouseEvent.x/y`），并做边缘钳制与"下方放不下就向上翻转"。实测：长按 (600,135)px → 菜单出现在对应位置
（`topMenu open at (240,54)->…`，240vp×2.5=600px ✓）；靠右时长按会被钳到贴近右缘。
单位统一为 vp（`windowWidth/Height`、`.position()`、手指坐标都是 vp，做过一次多余的 `px2vp` 会把菜单推到错误位置）。

**权威来源**：PyCharm `impl/PlatformActions.xml:1030`

```xml
<group id="MainToolbarPopupActions" searchable="false">
  <reference ref="ViewToolBar"/>
  <action id="CustomizeUI" class="com.intellij.ide.actions.CustomizeUIAction"/>
</group>
```

文案取自 `ActionsBundle.properties`：`action.ViewToolBar.text=工具栏(_T)`（`description=显示/隐藏主工具栏`）、
`action.CustomizeUIAction.text=自定义菜单与工具栏…`。

| 项 | 行为 | 真机验证 |
|---|---|---|
| **工具栏(_T)**（勾选项） | 真正显隐**主工具栏**；菜单栏保持常显（与 PyCharm 的 ViewToolBar 语义一致） | `tab menu pick id=top.toolbar` → `main toolbar visible=false`，截图里主工具栏消失、菜单栏保留 ✓ |
| **自定义菜单与工具栏…** | 打开对话框，列出顶栏/工具窗显示开关：主工具栏、状态栏、左侧工具窗按钮条、左侧工具窗、底部工具窗、右侧工具窗 | `tab menu pick id=top.customize` → 对话框标题 + 6 行开关全部出现 ✓ |

交互：顶栏**右键**（PC）与**长按**（平板，PyCharm 的右键 ≈ 长按）都能打开这个菜单；
菜单挂在页面根 Stack 下（和工程树/标签菜单同一套机制，避免"看得见点不动"）。

**踩到的坑**：菜单项复用了 `tabMenuItem`，而它的派发入口是 `onTabMenuPick`（原本只认标签栏与工程树的 id），
所以 `top.*` 一开始"点了没反应"。现已在 `onTabMenuPick` 里把 `top.*` 转发给 `handleAction`。

**齿轮菜单（工具窗选项）的权威来源与真行为**

条目、分组、顺序、勾选态全部取自 PyCharm 的 `impl/LangActions.xml:700-742`
（`ProjectView.ToolWindow.SecondaryActions` → `Behavior.Actions` / `Appearance.Actions` / 排序组），
文案取自 `impl/ActionsBundle.properties`（如 `action.ProjectView.ShowExcludedFiles.description=显示排除的文件`）。

| PyCharm 动作 id | 文案 | 我方实现 | 真机验证 |
|---|---|---|---|
| `ProjectView.OpenInPreviewTab` | 启用预览标签页 | 树里**单击 = 预览标签**（斜体、同一时刻只保留一个，新预览顶替旧预览）；**再点同一行**或**真的编辑了内容**（`dirty`）即转正 | 真机：点 README →`[main, README]`；点 utils → **README 被顶替** →`[main, utils]`；再点 README → 又一次顶替 ✓ |
| `ProjectView.AutoscrollToSource` | 一键打开文件 | 关 → 单击只选中，再点才打开 | 关掉后第一次单击 `openFile`=0、第二次=1 ✓ |
| `ProjectView.OpenDirectoriesWithSingleClick` | 一键打开目录 | 关 → 目录同样先选中再展开 | 同链路 ✓ |
| `ProjectView.AutoscrollFromSource` | 始终选择打开的文件 | 开 → 切编辑器标签时树自动选中并滚到该文件（`revealActiveInTree`） | `autoscroll=true` 后点 utils.py 标签 → `revealInTree file=utils.py tick=1` ✓ |
| `ProjectView.ShowExcludedFiles` | 显示排除的文件 | 关 → 排除目录（`.venv/__pycache__/.idea`…）不进树 | 代码规则（示例工程无排除目录） |
| `ProjectView.ShowScratchesAndConsoles` | 显示临时文件和控制台 | 关 → 该固定节点整体隐藏 | `scratches=false` 后节点消失、`true` 后回来 ✓ |

**修掉的关键可用性 bug**：⋮ 菜单原来用 `.position()` 挂在**标题栏 Row（高 28vp）**里，
菜单整体伸出父容器 —— ArkUI 只把触摸事件派发给父边界内的孩子，
表现为"**菜单看得见、点不动**"。现改挂到**面板根节点**（面板整高，z 序在树之后）后点击正常。

**树的两项真实行为（齿轮菜单里原来只是摆设的开关）**

| 选项 | PyCharm 语义 | 实现 | 验证 |
|---|---|---|---|
| 压缩目录（Compact Middle Packages） | **默认开启**；"中间包"链折叠成一行 | `Index.buildViewTree()`：目录的**有效子节点**（忽略 `__init__.py`）恰好是一个目录时，把链并成 `a/b/c` 一行；合并行的展开态取自链尾，展开后子行挂在合并行下 | 真机：示例工程的 `demo_pkg` 显示为 **`demo_pkg/core`** 一行，展开后 `__init__.py`/`engine.py` 缩进正确 ✓；算法另有单测 `_cache/device/test_viewtree2.js` ✓ |
| 文件夹总在最前（Folders Always on Top） | 目录排在文件前 | 视图树按目录优先 + 名称排序（仅 `depth > 0`；根层固定为"工程根 → 外部库 → 临时文件和控制台"） | 真机：`demo_pkg/core` 排在 main.py 之前 ✓ |

齿轮开关现在会真正重建视图树（`onViewOption` → Index → `refreshFlatten()`，hilog: `project view compact=…`）。
本轮修掉的两个 bug：① 排序误伤了 depth 0 的根节点，导致「外部库」跑到工程根前面；② `writeText` 不建父目录，
创建示例包时报 `err=13900002`（已改为先 `ensureDir`）。
示例工程新增了一个真实可 import 的包 `demo_pkg/core`（`__init__.py` + `engine.py`），既演示压缩也当真实代码。

**功能完善**

| 动作 | 行为 | 验证 |
|---|---|---|
| 定位（SelectInProjectView） | 逐级展开祖先目录 → 选中当前文件 → 树滚动到该行 | hilog `locateInTree file=.../README.md tick=2` ✓ |
| 展开全部 / 折叠全部 | ExpandAll / CollapseAll；折叠时**根节点保持展开**（与 PyCharm 一致） | 动作组同一派发分支（与定位同为已验证路径） |
| 新建 + | NewElement → 多语言新建对话框 | 沿用既有 |
| 工程根图标 | ideaProject（文件夹+蓝角标） | 真机截图 ✓ |
| 排除目录图标 | `.venv/.idea/__pycache__/node_modules/.git/.mypy_cache/.pytest_cache` → 橙色文件夹 | 代码规则（模块级 `isExcludedDirName`） |

### B3. 原生终端（entry/src/main/cpp）

| 项 | 结果 |
|---|---|
| 模块 | `libpythonbridge.so` 增加 `pty_watch.cpp`（PTY：ptyOpen/ptyWrite/ptyRead/ptyResize/ptyClose/ptyAlive；目录监听：watchDir/pollDirWatch/unwatchDir；兜底：shellRun；诊断：ptyDiagnose） |
| PTY | **实现完成，但被系统沙箱拒绝**：`ptyDiagnose={"ptmxAccess":false,"ptmxErrno":13,"ptmxErrnoText":"Permission denied","posixOpenptOk":false,"posixOpenptErrno":13,"shellAvailable":false}` → 普通应用拿不到 `/dev/ptmx`，`popen` 也被拒绝（errno 13）。终端工具窗因此回退到内置命令（python/pip）并给出明确提示 |
| 目录监听 | **可用**（见 B2），工程树由「定时全量扫描」改为「inotify 事件驱动增量刷新」 |

## C. 仍在用"我的代码常量"而不是 PyCharm 文件值的地方（如实列出）

| 项 | 我的值 | 说明 |
|---|---|---|
| 头部（菜单+工具栏合并行）高度 | 38vp | 可读文件里**没有**该值（是代码常量）；取 38 是为了消除我这边 30/36 的不一致 |
| 状态栏高度 | 24vp | 主题只给了边框与底色，没有高度键 |
| 编辑器字号 | 14vp（可调） | `config/options/editor-font.xml` 只有 `VERSION=1`，说明用默认字号；默认值不在文件里 |
| 树缩进步长 | 13vp | 主题有 `tree-indent-guide-border` 颜色，无步长键 |

**结论**：凡是能从文件读到的值，界面都已按值落地；上表 4 项是文件里确实没有的量，取的是行业默认/代码自洽值，如需严格对齐需要 PyCharm 的运行期渲染参数（或它们的源码常量）。
