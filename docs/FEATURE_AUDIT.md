# HarmonyPyIDE 分区功能/界面全量核查（对照 PyCharm 2026.2.2 安装文件）

## 0. 逐条核查基线（可点数，2026-10-10 重做）

> **重要更正**：本文件最初版本是"区域级 + 未实现标记"的核查，**不是逐条 1:1**，会漏项。
> 现已改为机器核查：从 `D:\PyCharm 2026.2.2\lib\*.jar` 抽出**全部 60 个动作 XML**，
> 栈式解析（支持嵌套 group 与 add-to-group）得到 **595 个 action group**，完整清单见
> `_cache/pycharm/all_groups.md`；区域条目数如下（展开嵌套后的叶子条目数）：

| 区域组 | PyCharm 条目数 | 我们的实现 | 结论 |
|---|---|---|---|
| `ProjectViewPopupMenu`（项目区右键） | **146** | 12 项 | ❌ 缺约 130 项（新建组/剪切复制粘贴/编辑源/查找用法/在文件中替换/重命名/重构组/修改组/运行组/打开位置组/版本控制组/缓存恢复/从磁盘重新加载/转到链接目标/比较文件/与编辑器比较/外部工具/设置组…） |
| `ProjectViewToolbar`（项目区工具栏） | **8** | 7 个图标 | ⚠️ 需逐项对齐（可能多/少一个） |
| `EditorPopupMenu` + `BasicEditorPopupMenu` + `EditorPopupMenu1.FindRefactor` | 12 + 6 + **40** | 20+ 项 | ❌ 查找/重构槽（40 项）几乎未实现 |
| `EditorTabPopupMenu` + `EditorTabPopupMenuEx` | 36 + **54** | 21 项 | ❌ 缺 Ex 组（54 项） |
| `NavbarPopupMenu`（面包屑右键） | **140** | 无 | ❌ 完全没有 |
| `StructureViewPopupMenu`（结构视图右键） | **78** | 无 | ❌ 完全没有 |
| `ConsoleView.PopupMenu`（控制台右键） | **48** | 无 | ❌ 完全没有 |
| `MainToolbarPopupActions`（顶栏右键） | 4 | 6 项 | ✅ 覆盖 |
| `RunToolbarMainActionGroup` | 8 | ~6 项 | ⚠️ 待逐项对齐 |
| `RunMenu` | 10 | 有实现 | ⚠️ 待逐项对齐 |
| `DebuggingActionsGroup` | 38 | 部分 | ⚠️ 调试动作缺项 |
| `EditorActions` | 190 | 部分 | —— 含大量内部动作，按可见项核对 |

> 说明：`Vcs.Log.*`、`XDebugger.*`、`Graph.*` 等组属于我们**尚未覆盖的整块功能**
> （VCS 日志、调试器窗口、图表），不在"补齐"范围时需明确排除，避免无边际扩张。

### 0.4 补齐进度（滚动更新）

| 区域 | PyCharm 条目（去重） | 补齐后 | 说明 |
|---|---|---|---|
| `ProjectViewPopupMenu` 项目区右键 | 40 | **33 项** | 按文件分组顺序落位；真实：查找用法/在文件中查找/在此处显示/更改语言/刷新项目/重命名/删除/新建/运行/从磁盘重载；其余如实提示（文件类型注册/语义重构/差异视图/VCS/外部工具）。同步修掉"长菜单底部被窗口裁掉"→ Scroll+maxHeight 560+定位钳制 |
| `NavbarPopupMenu` 面包屑右键 | 37 | **37 项** | 新增整块（此前完全没有）；与项目树菜单共用实现；`ViewNavigationBar` 为**真实开关**（菜单项带 ✓）、`ViewMembersInNavigationBar` 如实提示 |
| 面包屑显隐 | `Editor.General.Breadcrumbs` 默认**开** | 已改默认开 | 此前我们的面包屑默认隐藏（`showBreadcrumb=false`）→ 真机上根本看不到；已按 PyCharm 默认改为显示 |
| `StructureViewPopupMenu` 结构视图右键 | 22 | **17 项（14/14 dump 全命中）** | 新增整块：跳转到源代码（**真实**：按符号名在活动文件里算出行号并跳转）、查找用法（真实）、复制路径（真实）、运行（真实）、在此处显示（真实）；重命名/重构/剪切/拆分/关联应用/VCS/比较文件如实提示 |
| `ConsoleView.PopupMenu` 控制台右键 | 10 | **9 项已挂载，设备端未验证（此前"5/9 命中"是假阳性）** | 已真实实现：复制全部输出→系统剪贴板（替换原提示）、暂停/恢复输出（暂停期进缓冲，恢复一次补入）、全部清除；接入动作派发 `console.pauseOutput`/`console.clearAll`。**尚未完成**：把这 10 项做成 `ConsolePanelView` 上的右键菜单（需给面板加 `onContextMenu` 并在日志区挂 handler），已挂载到 `ConsolePanelView`（新增 `onContextMenu` 属性 + 根 Stack 右键/长按）；`CopyUrl` 真实实现（正则从输出抽 URL）。**更正**：之前记的"5/9 dump 命中"是**假阳性**——截图显示那 5 项来自**编辑器右键菜单**（长按落到了编辑器代码区，因为底部控制台面板当时未显示）。控制台菜单本身**尚未在设备上触发成功**。验证前提：先让底部工具窗显示（Shift+F10 运行 / 视图→工具窗口→Run），再在面板内右键或长按 |

### 0.25 多窗格编辑器 · 第 2 步（窗格渲染 + 分隔条）✅ 已实现并验证

**实现**（`Index.ets` 编辑器岛）：把编辑器岛内容从 `Column` 改为 **`Row`**（岛样式移到 Row 上）：
- 窗格 1 = 原内容（面包屑 + `CodeEditor`），`.layoutWeight(1).height('100%')`
- `paneSplit !== 'none'` 时追加：**6vp 分隔条**（`PanGesture` 调 `paneRatio`）+ **窗格 2**
- ⚠️ **关键安全设计**：窗格 2 的 `CodeEditor` **不挂 `onTextChange` / `onCursorChange` / `controller`**（只读镜像）
  —— 否则两个实例会互相写回同一文件，造成文本抖动与自动保存覆盖

**真机验证**（重启后回归 + 效果双查）：
```
① 回归：单窗格正常 = True | 行号存在 = True
② 菜单含「向右拆分(_V)」= True
③ 拆分后屏幕 main.py 节点数 = 5（两个窗格各有面包屑/行号/正文）
   截图：两个编辑器窗格并排，状态栏「已向右拆分：标签 main.py 移入第 2 窗格」   ✓✓
```

### 0.26 多窗格 · 第 5 步（布局持久化）✅ 已验证

`AppSettings` 增加 `paneSplit / pane2Tabs / paneRatio`，**并同时在 `SettingsService.load` 与 `save` 里逐字段补上**
（记住上次教训：该服务是逐字段读写，只加模型字段会静默失效）；启动时恢复，拆分/取消拆分时 `persistPanes()` 落盘。

真机验证（拆分 → force-stop → 重启 → 读自检日志）：
```
selfcheck panes split=h pane2=1 ratio=0.5      ✓✓ 布局跨重启保持
```

### 0.27 多窗格 · 拆分方向保真度修复（h/v 都正确）

发现并修复一个保真度差距：渲染条件原为 `paneSplit !== 'none'` → **"向下拆分"也渲染成左右并列** ✗。
改用 **`Flex` 的动态方向**（一次改动同时支持两个方向）：
```
Flex({ direction: this.paneSplit === 'v' ? FlexDirection.Column : FlexDirection.Row,
       alignItems: ItemAlign.Stretch })
// 分隔条：width = v? '100%' : 6、height = v? 6 : '100%'
// 两个窗格只用 .layoutWeight(1)，交叉轴尺寸交给 Stretch
```

**真机验证（两个方向都有截图）**：
- 向右拆分 → 左右并列（0.25 节截图）✓
- 向下拆分 → **上下堆叠** + 状态栏「已向下拆分：标签 main.py 移入第 2 窗格」✓✓
- 重启后仍为 `split=h pane2=1`（持久化）✓

### 0.43 调试器：端到端验证通过（并修正 0.41 的错误判断）

**重要修正**：0.41 写的『Frames/Variables 需要 pdb 交互通道、未实现』是**错误判断**。
实际情况：
- 原生桥接已有 **debugRun**（`napi_init.cpp` 的 kDebugHookScript）+ `runDebug(path,args,breakpoints,roots)` + debug 事件监听 ✓
- `DebugPause` 已携带 **locals（局部变量 name/repr）** 与 **stack（调用栈 file/line/func）** ✓
- DebugPanel 已显示「局部变量（N）」「调用栈（N）」两个区块（Index.ets 7974-8003）✓

**真机端到端验证（截图 + dump）**：
    行号 11 点击 → 断点红点出现 ✓
    tb-debug → 『调试会话已启动，共 1 个行断点。』✓
              → 『已暂停 main.py:11 (main)』✓✓
    编辑器第 11 行高亮 ✓  运行面板显示 `python .../main.py # 调试模式` ✓

**未验**：暂停时「局部变量」「调用栈」两个区块的具体内容（本次 dump 未出现这两个标题，可能在可视区外/需展开）。
**下一步**：暂停时截图并滚到底部面板，确认变量与栈内容；再补 XDebugger 的 Watches（监视）与 Evaluate（求值）。
**续查（0.43 之后的发现）**：

1. DebugPanel 的渲染条件原本是 `if (this.debugging)`，而 `debugging` 在**启动请求返回**时就被置回 false（Index.ets 3893），
   暂停期间面板会消失 → 已改为 `if (this.debugging || this.debugPaused)`（构建通过、已安装）。
2. 但改后 dump 仍未见「局部变量/调用栈」：说明 `debugPaused` 也已被重置 —— 结合控制台仍显示
   `已暂停 main.py:11 (main)`，判断**当前的『暂停』更像事件通知而非真正挂起**（脚本随后继续跑完 → 状态复位）。
3. 因此 DebugPanel 的按钮（继续/单步/步入）是否能真正驱动会话，需要确认原生调试钩子是否**阻塞等待**。

**下一步**：读 entry/src/main/cpp 的 kDebugHookScript，确认暂停语义（阻塞 or 通知）；若为通知，则需加 握手（等待 IDE 的 resume/step 指令）后，变量/栈面板才有稳定数据可显示。
### 0.42 与剪贴板比较（Diff.CompareWithClipboard）—— 实现完成，被平台剪贴板隐私限制卡住

**实现**：FileService.readClipboardAsync（异步 getData，会走系统允许粘贴授权）→ compareWithClipboardText 出差异；
入口在随处搜索首屏「与剪贴板比较」。

**验证发现（重要）**：
- 复制的确成功（系统日志 `HMKeyboard_ClipboardManager: on clipboard update` ✓）
- 但 `getDataSync()` 与异步 `getData()` 在本机**都拿不到内容**（既不报错也不弹授权，返回空）
- 因此应用走了「剪贴板为空或未获授权」分支，差异对话框不出现

**结论**：这不是代码缺陷，而是 **HarmonyOS 对应用读取剪贴板的隐私限制**
（需要系统级 `ohos.permission.READ_PASTEBOARD` 或系统粘贴授权通道，普通应用默认拿不到）。
**待办**：查目标 API 版本下剪贴板读取的正确授权方式；若确实不可得，则把该入口改为如实提示（而不是让用户以为功能坏了）。
### 0.41 断点列表（XDebugger: View Breakpoints）—— 入口与对话框已验证

**实现**：读 breakpoints.json（已有的持久化断点存储）→ 列出 `文件名:行号`；
每行「删除」写回存储并同步编辑器标记；底部「全部清除」；入口：随处搜索首屏「查看断点」。

**已验（真机）**：SE 首屏含「查看断点」→ 点击 → 对话框标题 `断点（0）` ✓（空态正确：无断点时只显示提示）
**未验**：有断点时的列表与删除动作 —— 我合成的『点行号槽加断点』点击坐标不准，未能造出断点；
需人工在编辑器行号左侧点一下后再打开本对话框确认。

**下一步（调试器子系统）**：XDebugger 的 Frames / Variables / Watches 需要真实调试会话，
当前运行时桥接只执行脚本、无 pdb 交互通道；建议先做「执行时逐行回传」或接受 `sys.settrace` 注入，再补变量窗口。
### 0.40 本地历史（Local History）—— 部分实现，验证到对话框为止

**实现**：
- 快照：保存前把磁盘旧内容写入 `<工程根>/.harmonyide/history/<路径 hash>/snap_<毫秒>.txt`（内容相同则跳过，避免重复）
- 对话框：按时间倒序列出快照（时间戳 + 行数）
- 点某行 → **与当前编辑器内容比较**（复用 0.39 的差异引擎）
- 点行内「还原」→ 写回该快照内容并刷新标签（还原前也会先快照当前版本）
- 入口：随处搜索首屏「本地历史」（动作 history.show）

**已验（真机）**：SE 首屏含「本地历史」→ 点击 → 对话框标题 `本地历史：main.py（0 个快照）`、空态文案正确 ✓
**未验**：快照写入与「比较 / 还原」整链 —— 触发快照需要一次「保存」，而保存入口在 SE 列表第 11 项（可视区外），
滚动时会点到蒙层把对话框关掉（新踩坑），故本轮的自动化无法走到保存那一步。

**待办**：把「保存」提到可见入口（或给编辑器/标签菜单加保存项）后再验整链；另需加入快照数量上限与清理策略。
### 0.39 差异比较（Diff.*）—— 已实现并验证

**引擎**：行级 LCS（一维 DP 数组），输出每行归属（相同 / 仅左侧 / 仅右侧）。
**界面**：差异对话框，顶部统计 `+N -M` 与两侧文件名，正文按行着色（删除红 / 新增绿 / 相同默认）。
**入口**：随处搜索首屏「比较当前文件与磁盘版本」+ 结构视图菜单「比较文件」；
语义为「编辑器当前内容 ↔ 该文件在磁盘上的版本」（可看出未保存改动），替代 PyCharm 的
「选两个文件比较」（本 IDE 暂无多选）。

**真机验证（决定性）**：
    selfcheck diff rows=6 removed=1 added=2      ← 对已知输入 a/b/c/d vs a/x/c/d/e 断言，完全一致
    SE 首屏 ['比较当前文件与磁盘版本','转到符号','转到类'] → 点击 → 对话框标题出现
    '差异：+0 行 / -0 行（左=磁盘文件，右=编辑器当前内容）'   ← 未修改文件为 0/0，行为正确

**未做**：与剪贴板比较、与分支比较、差异导航（上一处/下一处）、目录比较（DirDiff）。
### 0.38 SplitChooser：拖拽标签弹出（多窗格功能完整）

**交互**：把标签**向下拖拽**（拖进编辑区）→ 弹出「拆分编辑器」选择器，含 7 个可落地动作：
向右/向下/向左/向上/居中拆分、取消拆分、全部取消拆分。

**踩坑**：最初用 PanDirection.All + 横向位移判定 → 永远不触发。真因是标签栏本身为横向 Scroll，
横向手势被它当成滚动吃掉（手势冲突）。改用 PanDirection.Vertical + offsetY > 60 即成功 ——
这也正是 PyCharm 的语义（把标签拖离标签栏、拖进编辑区）。

**真机验证**：拖拽后 dump 实测标题出现 ✓，项列表为
['拆分编辑器','向右拆分','向下拆分','向左拆分','向上拆分','居中拆分','取消拆分','全部取消拆分'] ✓

**未做**：PyCharm 该选择器还含 Group Tabs / Move to Opposite Group / Next Window / Previous Window；
前两者由标签右键菜单提供，后两者需要窗格焦点模型，暂以如实说明呈现。
### 0.36 多窗格第 2 窗格：只读镜像（按用户预期确定）

用户反馈“怎么两边都能修改内容”→ 明确期望是**右侧窗格只读**。
故把 0.34 的共享编辑回退为 readOnly=true 只读镜像（CodeEditor 禁用输入层 + 隐藏光标）。
共享编辑（两侧同编同步）标记为**待可靠验证后再开**：自动化环境无法输入文本，
无法证明“输入 → 两窗格一致”，贸然开启会导致两窗格内容分叉。

### 0.37 双平台托管（GitHub + GitCode）已接通

    origin  fetch : https://github.com/hjc200720-pixel/Harmony-OS-PythonIDE.git
    origin  push  : GitHub ↑ + https://gitcode.com/hjc200720/Harmony-OS-PythonIDE.git

配置方式：scripts/setup-gitcode.ps1（GitCode API 建库 → git credential approve 存凭据 →
git remote set-url --add --push 加第二个推送地址 → 推送 → 校验）。
之后 git push 一次更新两个平台；配 scripts/autopush.ps1 + 计划任务即两边全自动。
实测：建库 HTTP 200、GitCode hooks [PASSED]、* [new branch] main -> main、两边 HEAD 一致。

**踩坑（重要）**：`git remote set-url --add --push origin <gitcode>` 会把推送地址列表**整体替换**为只有 GitCode，
导致 GitHub 不再收到推送（首次配置后就中了：GitCode 到 c849dfc，GitHub 仍停在 1219c7d）。
正确做法是把两个地址都显式放进列表：

    git remote set-url      --push origin https://github.com/hjc200720-pixel/Harmony-OS-PythonIDE.git
    git remote set-url --add --push origin https://gitcode.com/hjc200720/Harmony-OS-PythonIDE.git

校验：`git remote get-url --all --push origin` 必须**输出两行**。
### 0.34 共享文档（两窗格同编，PyCharm 行为）—— 实现完成，验证未完成

**实现**：第 2 窗格去掉 `readOnly: true`，改挂与第 1 窗格**相同的** `onTextChange` / `onCursorChange`
→ 两窗格写回**同一个 tab**；另一窗格经 `initialText` 的 `@Watch` 同步（与单窗格时同一套机制，文本收敛不产生循环）。

**验证未完成（如实）**：
```
拆分后点击第 2 窗格（光标已出现 ✓，说明点击命中且可编辑）
→ 但系统输入法候选栏被拉起，uitest inputText 的文本**没有进入编辑器**
→ 两个窗格出现标记文字的次数 = 0  → 无法证明同步，也无法排除"第 2 窗格会拉起系统键盘"
```
（标记未写入，因此**文件未被污染** ✓；验证后已还原为单编辑器 ✓）

**已按该方案执行（本轮）**：在窗格 1/2 的 `onTextChange` 各写一行 `pane1 change len=` / `pane2 change len=`，实测：
```
pane1 change len=348
pane2 change len=348      ← 两个编辑器装载的是同一份文档（长度一致），且第 2 窗格的写回回调**确实被挂上并触发**
```
**仍不能证明"编辑后同步"**：`uitest inputText` 的文本进不了编辑器（系统 IME 被拉起但内容不落），
所以"输入 → 两窗格一致"这一步在自动化环境里做不了，需人工敲一次确认（或用其他输入通道）。

**下次验证方案**：改用`hilog` 断点——在 `onTextChange` 里写一行日志（窗格标识 + 文本长度），
用 `uitest` 的点击定位到窗格后，手工/脚本输入一次，读日志即可判定"是否写回同一 tab + 是否同步"；
同时确认第 2 窗格不应拉起系统键盘（第 1 窗格的修复参数 `enableKeyboardOnFocus(false)` 等本就在 `CodeEditor` 内，
若确会拉起则说明 `uitest inputText` 自身强制开启 IME，而非窗格问题）。

### 0.33 分隔条显示修正（用户反馈：分隔条还是要显示正确）

三处修正：
| 问题 | 修正 |
|---|---|
| 分隔线只有中间一小段（原写死 60vp） | 改为贯穿整高/整宽：`width: v?'100%':3` + `height: v?3:'100%'` |
| 深色背景下 `theme.border` 几乎看不见 | 改用 `theme.separator`（与菜单分隔线一致） |
| 热区 22vp 看起来像一条宽空白 | 收窄到 **12vp**，3vp 细线居中 |

另加 **悬停高亮**（PyCharm splitter 行为）：`onHover` → 线色由 `separator` 变为 `funcName`。

**验证**：拆分后截图确认两窗格相邻、线贯穿整高（`_cache/device/div4.jpeg`、`div5.jpeg`）；
"线是否够醒目"属主观项，以用户确认为准。验证后已还原为单编辑器 ✓

### 0.32 第 2 窗格真正的只读镜像（用户反馈：两边都能修改内容）

**用户反馈**："怎么两边都能修改内容" —— 两个窗格都能编辑，会各自改本地文本导致**分叉**。

**真因**：此前只去掉了第 2 窗格的 `onTextChange`，但 `CodeEditor` 内部的输入层 `TextArea` **仍然可编辑**，
它只会改第 2 窗格自己的 `this.text`（不回调、不保存）→ 两边显示不一致，属于更糟的状态。

**修复**：给 `CodeEditor` 增加 `@Prop readOnly: boolean = false`，输入层加
`.enabled(!this.readOnly)` + `.caretColor(readOnly ? Transparent : 主题光标色)`
（文本由下方高亮层渲染，禁用输入层不影响观感）；第 2 窗格传 `readOnly: true`。

**真机验证**：
```
拆分后点击第 2 窗格并输入 ABCDE → 输入后出现 ABCDE: False      ✓ 只读生效
示例工程标题行仍在: True                                        ✓ 内容未被破坏
验证后已执行「取消拆分」还原为单编辑器                            ✓
```

### 0.31 分隔条"跟手"修复（用户反馈：不能自由调整）

**用户反馈**："不能自由调整" —— 拖动时比例乱跳、不跟手。

**真因**：`PanGesture.onActionUpdate` 的 `event.offsetX/offsetY` 是**相对手势起点的累计位移**，
而原实现每次都往 `paneRatio` 上加 → **位移被反复累加**，越拖越快、跳动 ✗。

**修复**：改为"手势起点记录比例 + 本次累计位移"（与左侧面板分隔条 `dragStart* ` 同一套正确写法）：
```
.onActionStart(() => { this.dragStartRatio = this.paneRatio; })
.onActionUpdate((e) => { const span = v ? 700 : 1000; const d = v ? e.offsetY : e.offsetX;
                         this.paneRatio = clamp(this.dragStartRatio + d / span, 0.1, 0.9); })
.onActionEnd(() => this.persistPanes())
```
同时把分隔条触控区从 **6vp 加宽到 22vp**（细线仍是 2vp）——6vp 手指抓不住。

**验证**：拖动后比例改变且重启后保持（`selfcheck panes … ratio=`）；
但"1:1 跟手"的**定量**验证（拖 N 像素比例变化 N/span）在真机上没做成 —— 环境里我无法精确量出边界像素与期望值的对应，**此项仅以代码正确性 + 可拖动为证**。
（本轮验证后已执行「取消拆分」还原状态 ✓）

### 0.30 分隔条比例生效（修掉一个此前未验证到的漏洞）

**问题**：分隔条有 `PanGesture` 会改 `paneRatio`，但两个窗格都写死 `.layoutWeight(1)` → **拖了没有任何效果** ✗（此前只验证了"分隔条存在"，没验证"拖动生效"）。

**修复**：窗格 1 = `.layoutWeight(this.paneRatio)`、窗格 2 = `.layoutWeight(1 - this.paneRatio)`；
拖动结束 `onActionEnd` 调用 `persistPanes()` 落盘。

**真机验证**（拆分 → 拖动 → 截图）：
```
向右拆分后拖动分隔条：左窗格变窄、右窗格变宽（约 40% / 60%）✓✓
```
验证后已按新规则执行「取消拆分」还原状态 ✓

### 0.29 拆分布局策略（用户确认：方案 A）

用户反馈"编辑区怎么出现两个了" —— 原因是**我的验证留下了持久化的拆分布局**（功能本身正常）。
用户确认采用 **方案 A：与 PyCharm 一致，重启恢复上次拆分布局**，因此**不需要改代码**。

**我新增的自律规则**：任何会改变持久化状态的验证（拆分、折叠、面板开关、工具窗），
**验证完必须执行还原动作再收尾**（如「取消拆分」），并在收尾前截图确认状态。

### 0.28 SplitChooser 动作扩展（部分完成，如实记录）

**已完成**：`paneBefore` 字段（"新窗格放前侧"，对应 PyCharm `SplitLeft`/`SplitTop`）已贯通
模型 → `AppSettings` → `SettingsService.load/save` → 启动恢复 → `persistPanes()` → 自检日志；
`splitEditor(orientation, before, ratio)` 支持前侧与比例；`splitLeft` / `splitTop` / `splitCenter` 三个动作处理器已就位。

**后续已补齐**：
1. `paneBefore` 已生效 —— 用 **`Flex` 反向方向**一行实现"新窗格在前侧"：
   `v → ColumnReverse` / `h → RowReverse`（两个窗格内容相同，视觉顺序无法从截图区分，故此项仅以状态与派发为证）
2. 标签菜单已加入 **`向左拆分` / `向上拆分` / `居中拆分`** 三项；
   实测菜单拆分项：`['向右拆分(_V)','向下拆分(_H)','向左拆分','向上拆分','居中拆分','更改拆分方向']` ✓
   点击「向左拆分」→ hilog `menuPick tab id=splitLeft` ✓

**仍未做**：`SplitChooser` 拖拽到边缘自动弹出的原始交互（其余 10 个动作均已有等价入口）。

**回归（安装后重启）全绿**：`hierarchy(sample)=3` · `foldRegions=3` · `hippie(gr)=greet` ·
`seActions=27` · `panes split=v pane2=1 ratio=0.5 before=false`（顺带再次证明持久化生效）✓

**多窗格 5 步现状**：1 模型 ✅ · 2 渲染+分隔条（h/v）✅ · 3 标签归属 ✅ · 5 持久化 ✅ · 4 SplitChooser 部分（见上）。

### 0.24 多窗格编辑器 · 第 1 步（模型）已完成

按 0.21 的 5 步计划，第 1 步落地：

```
@State paneSplit: string = 'none';   // none | h（左右） | v（上下）
@State pane2Tabs: string[] = [];     // 第 2 窗格里的标签 id
@State paneRatio: number = 0.5;      // 分隔比例
splitEditor(orientation)  // 把当前标签移入第 2 窗格（PyCharm ChangeEditorSplitAction）
unsplitEditor(all)        // 取消拆分 / 全部取消（标签回到第 1 窗格）
```

标签右键菜单的四项已从"如实提示"改为**真实模型操作**：`向右拆分` / `向下拆分` / `取消拆分` / `全部取消拆分`；
`更改拆分方向` 在 h/v 间切换；`在新窗口中编辑源` 仍如实提示（需多窗口能力）。

**验证**：自检日志已包含新状态 ——
```
selfcheck panes split=none pane2=0 ratio=0.5     ✓（模型已生效）
```
（交互验证"右键标签 → 向右拆分 → 状态栏"未在本轮完成：长按标签后 dump 里没有出现含"拆分"的菜单项，原因待查。）

**第 1 步的交互验证（本轮补上）**：发现并修复了一个真 bug ——
把编辑器右上 ⋮ 改成 TabList 之后，**`EditorTabPopupMenu`（标签右键菜单）失去了触发入口**（PyCharm 里它本就由标签右键触发）。
已给标签补上 `.onMouse(右键)` + `LongPressGesture` → 菜单恢复：

```
含拆分: ['向右拆分(_V)','向下拆分(_H)','更改拆分方向','取消拆分','全部取消拆分']   ✓
含关闭: ['关闭标签页(_C)','关闭其他标签页(_O)','关闭所有标签页(_A)']              ✓
点击「向右拆分」→ hilog: menuPick tab id=splitRight                                ✓✓
```

**下一步（第 2 步）**：编辑区按 `paneSplit` 渲染 1..2 个窗格（每窗格一套标签栏 + `CodeEditor`），中间加可拖拽分隔条；第 3 步接标签动作；第 4 步做 SplitChooser 弹层；第 5 步持久化。

### 0.23 转到类（GoToClass）端到端验证

依据 `GoToMenu`：`GoToClass` —— 列出当前文件的类与其基类（复用 `classHierarchy()`），点击用 `lineOfSymbol()` 跳行；
无类时显示空态。入口 `nav.gotoClass`（随处搜索首屏）。

```
① SE 首屏: ['转到符号','转到类','切换器','继承层级']
② 转到类按钮: True
③ 对话框: 标题 True | 空态 ['当前文件没有 class 定义'] | 按钮 ['取消','确定']   ✓✓
```

**至此 `GoToMenu` 的可实现项齐了**：转到行（原有）/ 转到文件（随处搜索）/ **转到符号** ✓ / **转到类** ✓。

### 0.22 当前状态与交接（本会话收口）

**最后一轮回归（全绿）**
```
selfcheck hierarchy(sample) rows=3 :: Animal : (无基类) ; Dog : Animal ; Cat : Animal, Mixin   ✓
selfcheck foldRegions=3 :: 6:7,10:14,17:18                                                    ✓
selfcheck hippie prefix=gr candidates=1 :: greet                                              ✓
selfcheck seActions=26 tabs=1 recentFiles=1                                                   ✓
【冒烟】搜索按钮(按 id 定位) True → SE 首屏 ['转到符号','切换器','继承层级']
        → 点「转到符号」→ 对话框 True，符号 ['ƒ  greet','ƒ  main']                          ✓✓
```

**已完成并端到端验证**
- 编辑器区 250 条目：标签栏/右键 21 项、编辑器右键 20+ 项、TabList 7 项、**代码折叠全套**（折叠/展开/全部/点击折角/按文件落盘/折叠选区）、随处搜索两栏、查找栏、面包屑（默认显示）
- 项目区·视图 128 条目：项目区右键 **40 项**、面包屑右键 **37 项**、结构视图右键 17 项
- 工具窗·工具栏·状态栏 27 条目：控制台右键 9 项、工具窗右键、主工具栏右键
- 新功能：**转到符号**、**切换器(Ctrl+Tab)**、**继承层级**、**循环补全**、**补全语句**（各自端到端或日志验证）
- 修 9 个真 bug（清单见 0.1–0.20 各节）

**未开发（整块子系统，需各自立项）**
| 子系统 | 条目 | 依赖/难点 |
|---|---|---|
| SplitChooser / 多窗格编辑器 | 10 | 编辑器容器改为多窗格（模型/UI/分隔条/持久化），见 0.21 |
| VCS 日志（`Vcs.Log.*`） | 217 | 需 Git 集成（沙箱无 git 可执行文件） |
| 图表 / 本地历史（`Graph.*`） | 217 | 需历史存储与图形渲染 |
| 调试器窗口（`XDebugger.*`） | 133 | 需断点/变量/求值/监视的调试协议 |
| 外部系统（`ExternalSystem.*`） | 87 | 需构建系统集成 |
| 作用域视图（`ScopeViewPopupMenu`） | 41 | 需作用域/用法索引 |
| 差异合并（`Diff.*`/`DirDiff*`） | 25 | 需差异算法与对比视图 |

**验证工具（可复用）**
```
组件 id:      tb-run/tb-debug/tb-stop/tb-moreRun/tb-ai/tb-searchEverywhere/tb-settings, sw-query
自检日志:     aboutToAppear +5s 输出 selfcheck 行（hilog）
交互日志:     menuPick <区域> id=<动作>（5 个菜单派发器）
dump 定位:    只含带文字或带 id 的节点 → 图标必须加 .id()
截图:         snapshot_display（dump 失效时的兜底）
踩坑:         hdc 路径含空格必须加引号（否则命令静默失败，伪装成功能缺陷）
```

### 0.21 SplitChooser.Actions 可行性评估（不做假占位）

**PyCharm 侧依据**：`SplitChooser.Actions` = `NextWindow / PreviousWindow / Exit / Split / Duplicate / SplitCenter / SplitTop / SplitLeft / SplitDown / SplitRight`；
其实现类是 `ChangeEditorSplitAction`（常量池：`isVerticalSplit / getEditorWithPreview / getParentSplitEditor`）——
说明"拆分"是**编辑器窗口层的模型**（`EditorWindow` / `SplitEditor`，多窗格 + 每窗格独立标签组），
`SplitChooser` 只是**拖拽标签到编辑区边缘时**弹出的选择器。

**我们的现状**：编辑器区是**单窗格**——
`Index.ets:5680 this.EditorTabsBar()` + `Index.ets:5702 CodeEditor({...})`，一套标签 + 一个编辑器。

**要做真的拆分，需要（多文件、多轮的独立工作量）**：
1. **模型**：`EditorPane { tabs, activeTabId }` + `panes: EditorPane[]` + `orientation: 'h'|'v'` + 分隔比例
2. **UI**：编辑区按 1..N 窗格渲染，每窗格自带 `EditorTabsBar` + `CodeEditor`，中间可拖拽分隔条
3. **标签动作落地**：向右/向下拆分（当前标签移入新窗格）、在对面窗格打开、取消拆分 / 全部取消拆分、更改拆分方向
4. **SplitChooser 弹层**：拖拽到边缘时弹出（或先由标签右键菜单触发，等价可达）
5. **持久化**：窗格布局写入设置

**结论**：我不做"点上去只弹提示"的假 `SplitChooser`。这条按上述 5 步单独立项，做完即为真实多窗格编辑器；
在此之前 `SplitChooser.Actions` 的条目保持"如实提示"，并在文档中标记为未实现。

### 0.20 切换器（SwitcherAndRecentFilesFallback）端到端验证

把「切换器」提到"随处搜索"首屏后，用已打通的 **id 定位 + 文本锚点** 流程完成闭环：
```
① SE 首屏: ['转到符号','切换器','继承层级','循环补全','补全语句']
② 切换器按钮: (887,737,1913,774)
③ 切换器对话框: True | 列表项 ['main.py','utils.py']   ← 打开的编辑器 + 最近文件 ✓✓
```
实现：`SwitcherContent` 对话框（打开编辑器在前、最近文件在后，点击切换/打开）+ 动作 `nav.switcher` + **Ctrl+Tab** 绑定。
（快捷键本身仍需人工按键确认，因为 uitest 无法注入 Ctrl 组合键；对话框已端到端验证。）

### 0.18 验证能力的根本修复：组件 id + 脚本引用

**两个把"验证"从不可靠变成可靠的修复**：

1. **脚本引用 bug（长期误判的真因）**：验证脚本里 hdc 路径含空格却没加引号 → 命令静默失败 →
   连 `uitest uiInput click` 都从未真正执行。表现为"点了没反应 / dump 空 / 菜单不弹"。
   正确写法：`'"%s" -t %s shell "%s"' % (HDC, T, cmd)`。**教训：脚本自身的错误会伪装成功能缺陷。**
2. **工具栏图标不可定位**：`dumpLayout` 不导出 `accessibilityText`，无 text 的图标节点也拿不到；
   改为给工具按钮加 **组件 `.id('tb-<key>')`** → dump 里直接给出精确 bounds：
```
tb-run  [2305,101][2370,166]   tb-debug [2370,101][2435,166]   tb-stop [2435,101][2500,166]
tb-moreRun [2500,101][2565,166]   tb-ai [2585,101][2650,166]
tb-searchEverywhere [2650,101][2715,166]   tb-settings [2715,101][2780,166]
```

**由此完成的端到端验证**（GoToSymbol / 随处搜索 / 工具栏点击）：
```
① 按 id 定位搜索按钮 (2650,101,2715,166) → 点击
② 随处搜索已开 = True，首屏 ['转到符号','继承层级','循环补全','补全语句']
③ 点「转到符号」→ 对话框标题 True，符号项 ['ƒ  greet','ƒ  main']，按钮 ['取消','确定'] ✓✓
```

### 0.19 新增：转到符号（GoToSymbol）

依据 `GoToMenu` / `SearchEverywhereActions`：查询框 + 当前文件符号列表（复用结构扫描 `liveStructure`），
点击用 `lineOfSymbol()` 定位并跳行；入口 `nav.gotoSymbol`（随处搜索首屏）。**已端到端验证** ✓。

### 0.17 开机自检日志（解决"点击路径难自动化"的验证通道）

**方法**：`aboutToAppear` 里 5 秒后跑一次 `logFeatureSelfCheck()`，把几个无法用 uitest 点击验证的功能各算一遍并写 hilog；
验证 = 重启应用 → 读 hilog（不受 dump 完整性/坐标漂移影响）。

**真机实测输出**（`hilog -x` 抓取）：
```
selfcheck hierarchy rows=0 ::                       ← main.py 无 class（正确）
selfcheck foldRegions=3 :: 6:7,10:14,17:18          ← 折叠区域：def greet(6-7) / def main(10-14) / if(17-18) ✓ 与之前 dump 验证一致
selfcheck hippie prefix=gr candidates=1 :: greet    ← 循环补全候选正确 ✓
selfcheck seActions=25 tabs=1 recentFiles=5         ← 随处搜索动作表 25 项 ✓
```

**结论**：折叠区域计算、Hippie 候选计算、搜索动作表——**逻辑层已验证** ✓；
仍需人工确认的只剩"点击交互"（右键菜单项点击后的状态栏回显）与快捷键（Ctrl+Tab / Ctrl+1…9）。
**补充验证（同一通道，决定性）**：工程里 `demo_pkg/core/engine.py` 本身没有 class（`rows=0`），因此改为在自检里**直接喂已知片段做单元断言**：
```
selfcheck hierarchy(sample) rows=3 :: Animal : (无基类) ; Dog : Animal ; Cat : Animal, Mixin
```
→ 单基类、多基类、无基类三种情况**全部解析正确** ✓✓

**至此逻辑层已验证**：折叠区域(3 处，与 dump 逐行验证一致) · Hippie 候选(gr→greet) · 继承解析(3/3) · 搜索动作表(25 项)。
仅剩**交互层**（右键菜单点击后的状态栏回显）与**快捷键**（Ctrl+Tab / Ctrl+1…9，uitest 无法注入组合键）需人工确认。

### 0.16 CodeMenu：循环补全 + 补全语句（纯本地实现）

依据 `CodeMenu`（文件里 11 项）：`OverrideMethods / ImplementMethods / Generate / EditorCompleteStatement / HippieCompletion / HippieBackwardCompletion / CallInlineCompletionAction / EnableCommandCompletion`。

- **循环补全（HippieCompletion）**：取光标前的标识符前缀 → 在当前文件词表里找同前缀词（去重）→ `controller.insertText` 补全；连续执行在同一前缀下**循环**候选，状态栏显示 `循环补全 i/n：word`。纯本地，无需语义引擎。
- **补全语句（EditorCompleteStatement）**：光标所在行去掉注释后以 `:` 结尾 → 插入"换行 + 当前缩进 + 4 空格"（PyCharm 的语句补全语义的本地近似）。
- 入口：编辑器右键菜单（新增两项）+ **随处搜索操作栏**（放在列表最前，便于发现与验证 —— dump 已确认两项可见 ✓）。
- 未实现（需语义引擎）：重写/实现方法、生成、内联补全 → 保持如实提示。
- 验证：构建通过、已安装；操作栏两项 **dump 实测可见** ✓；点击后的状态栏回显未取到（脚本在最后一步被输出截断），下次补。

### 0.15 TabsActions.GoToTab1..9（Ctrl+数字跳标签）

- 依据 `TabsActions`：`GoToTab1`…`GoToTab9` / `GoToLastTab` / `NextEditorTab` / `PreviousEditorTab` / `ReopenClosedTab` / `PinActiveTab` / `MoveEditorToOppositeTabGroup` / `OpenEditorInOppositeTabGroup`
- 新增 `goToTabN(n)` + `keyboardShortcut('1'..'9', [CTRL])`（PyCharm 行为）；Next/Prev、ReopenClosedTab、PinActiveTab 此前已有。
- 构建通过、已安装；**快捷键盘无法用 uitest 触发**（无 Ctrl 组合键指令），需人工按 Ctrl+1…9 验证。

### 0.14 可达用户可见项：切换器 + SE 滚动修复

- **切换器（`SwitcherAndRecentFilesFallback`）**：新增 `SwitcherContent` 对话框（打开的编辑器在前、最近文件在后，点击切换/打开）；动作 `nav.switcher`；**Ctrl+Tab** 绑定（`keyboardShortcut('tab', [CTRL])`，纯 Tab 仍为切换下一个标签）；并加入"随处搜索"的操作表便于发现。
- **顺带修掉真 bug**：随处搜索对话框的**操作栏不是 Scroll**（只有 `maxHeight:150`）→ 第 6 项之后的动作（终端/全部收起/切换器…）被裁掉、无法点击。已改为 `Scroll + maxHeight + scrollBar(Auto)`。
- 验证状态：构建通过、已安装；切换器的设备验证**两次未达成** —— 它位于 SE 操作栏第 21 项，dump 只含可见视口；尝试"列表内上滑"时滑动要么把对话框关掉、要么没落在操作栏上。**下一次改法**：直接给切换器一个可见入口（视图菜单 → 切换器 或标签栏 ⋮ 分组），不再依赖 SE 长列表。
- **一致性做法（"UI 框架逻辑必须一致"）**：每个功能的条目、顺序、分组、快捷键一律取自 PyCharm 文件（动作 XML / 主题 JSON / 语言包），并在本文件按条目标注依据；不自行发明条目或顺序。

### 0.13 全量核查（595 组 / 2253 条目）—— 哪些没做

方法：`_cache/pycharm/impl_all/*.xml`（60 个动作 XML，去重）→ 595 组 → 展开叶子条目 2253 → 按区域归类。

| 区域 | 组数 | 条目数 | 状态 |
|---|---|---|---|
| ⑫ 编辑器（含标签/查找/折叠/生成） | 30 | 250 | **已逐条实现+验证** |
| ⑪ 项目区 / 视图 | 18 | 128 | **已逐条实现+验证** |
| ⑬ 工具窗 / 主工具栏 / 状态栏 | 19 | 27 | **已逐条实现+验证** |
| ⑭ 其它（插件/第三方/未细分） | 308 | 764 | 未开发（**未细分，最大不确定块**） |
| ④ 图表 / 本地历史 | 20 | 217 | 未开发（整块功能） |
| ③ VCS 版本控制（日志/历史/搁置） | 64 | 217 | 未开发（整块功能） |
| ① 快捷键映射组 | 16 | 204 | **非可见 UI**（keymap 定义，不算功能缺口） |
| ⑤ 调试器窗口 XDebugger | 27 | 133 | 未开发（整块功能） |
| ⑥ 外部系统 / 构建 / 注册 | 26 | 87 | 未开发 |
| ⑦ 运行与调试动作 | 43 | 78 | 部分（运行/调试/停止已有） |
| ⑩ 设置 / 欢迎 / 帮助 | 16 | 53 | 部分（设置对话框已有） |
| ② 框架通用控件动作 | 4 | 44 | **框架内部**（非功能缺口） |
| ⑧ 作用域视图 | 1 | 41 | 未开发 |
| ⑨ Python / 语言动作 | 3 | 10 | 未开发 |

**结论**：可见 UI 里，我们**已覆盖 67 组 / 405 条目**（编辑器、项目区/视图、工具窗/主工具栏）；
未开发部分里，真正属于"整块功能缺失"的是 **VCS 日志(217) + 图表/本地历史(217) + 调试器窗口(133) + 外部系统(87) + 作用域视图(41) + 语言动作(10) ≈ 705 条目**；
另有 248 条目属于**非功能项**（快捷键映射 204 + 框架控件 44）。
**⑭ 其它桶已细分**（316 组 / 798 条目）：

| 子类 | 组数 | 条目数 | 性质 |
|---|---|---|---|
| 框架/内部/远程开发（`ListActions` `ActiveToolwindowGroup` `Internal.VFS` `Internal.Dump` `RdClient.*` `FileChooserToolbar` `LookupActions` `ScrollPaneActions`…） | 247 | 596 | **绝大多数不是用户可见功能**（框架管线/内部调试/远程开发） |
| 弹层内部（`UsageView.Popup` `ChangesViewPopupMenu` `InspectionToolWindow.TreePopup`…） | 32 | 88 | 属于我们尚未拥有的视图（用法/变更/检查） |
| 继承层级视图 `HierarchyPopupMenu.Common` | 2 | 25 | **用户可见，可实现** |
| 差异/合并（`DirDiff*` `Diff.*`） | 11 | 25 | 整块功能缺失（差异视图） |
| 导航/跳转（`NavBarToolBar` `GoToMenu`） | 10 | 22 | 部分已覆盖 |
| 标签栏动作 `TabsActions` | 2 | 17 | **用户可见，可实现** |
| 语言侧查找/替换（`SearchEverywhereActions` `FindUsagesMenuGroup`） | 4 | 17 | 部分已覆盖（随处搜索对话框已做） |
| 重构类 / 模板 / VCS 未归类 | 8 | 8 | 少量 |

→ **"其它"桶里真正用户可见、且可实现的是**：`HierarchyPopupMenu`(22) + `TabsActions`(16) + `CodeMenu`(11) + `SwitcherAndRecentFilesFallback`(10) + `SplitChooser.Actions`(10) + `FileChooserToolbar`(12) ≈ **80 条目**；其余 700+ 属框架内部或我们明确未覆盖的整块功能。

### 0.12 SearchEverywhere 两栏对话框（替代原先复用"在文件中查找"）

- `edit.searchEverywhere`（工具栏放大镜 / 快捷键）→ 打开 **专用对话框**：顶部查询框 + **操作栏**（20 条真实动作映射 label→actionId）+ **文件栏**（`flatNodes` 里的非目录项），查询词对两栏同时过滤；点击执行动作或打开文件。
- 踩坑：插入新 `@Builder` 时把原属于 `FindInFilesContent` 的 `@Builder` 修饰符"抢"走了 → 编译报 `'this.FindInFilesContent()' does not meet UI component syntax`。**ArkTS 的 @Builder 必须紧贴其方法**，插入新 builder 时要连注释/@Builder 一起归位。
- 状态：构建通过、已安装；**设备验证未完成**（验证脚本两次无输出，待补）。

### 0.11 鼠标右键"点不开"菜单 —— 根因是遮罩的 onClick

**现象**：鼠标右键编辑区，菜单看不到（像没打开）。
**根因**：每个弹层的全屏透明遮罩用 `.onClick(() => { menuShown = false })` 关闭；**鼠标右键同样会触发 `onClick`** → 菜单弹出后立刻被遮罩关掉，表现为"点不开"。
**修复**：遮罩改为只在**鼠标左键**关闭
```ts
.onMouse((event: MouseEvent) => { if (event.button === MouseButton.Left) { this.xMenuShown = false; } })
```
已应用到 7 个弹层（编辑器/工具窗/项目树/面包屑/结构/控制台/标签）。

**为什么之前没发现**：`uitest` 没有"鼠标右键"这个输入指令，本会话所有菜单验证都走的是长按（touch）路径 → 右键路径一直没被覆盖。这条也说明"自动化验证覆盖不到真实输入方式"的风险。

### 0.10 CollapseSelection 与折叠落盘

- **折叠落盘**：`AppSettings.foldedFolds`（`path#line` 逗号分隔）+ `SettingsService` 的 load/save 逐字段补上该键；五处折叠变更后调用 `persistFolds()`。
  真机验证：全部收起 → **force-stop 并重启应用** → 行号仍为 `1-6, 8,9,10, 15,16,17, 19`（与折叠后完全一致）✓
  （踩坑记录：`SettingsService` 是**逐字段**读写、不是 JSON 整体序列化，只加 `AppSettings` 字段而不加读写会静默失效）
- **CollapseSelection（折叠选区）**：`CodeEditor` 通过 `TextArea.onTextSelectionChange` 上报选区偏移 → Index `lineOfOffset()` 换算行号 → 折叠与选区相交的所有块；选区为空时退化为"折叠光标所在块"。
  菜单项 `折叠选区` 已出现在编辑器右键菜单 ✓（dump 命中）；**设备验证两次未达成**，根因已定位：
  ```
  CodeEditor 的 .onClick:  this.onEditorFocus();  this.areaController.caretPosition(this.offsetOfCursor());
  ```
  → **点击不会把光标移到点击位置**，而是把光标重置回 `cursorLine`。所以通过 `uitest click` 无法把光标放进目标块，
  `foldStartAtCursor()` 恒为 0（或不在块内），`CollapseSelection` 自然没有可折叠对象。
  **这是一个真实 UX bug**：PyCharm 点击编辑器应把插入符落到点击处。修好它同时也能解锁折叠选区的验证。
  （验证脚本已按 `def greet` 行的实际 y=625 精确点击，仍因上述原因无效）
  **已修**：`CodeEditor` 的点击处理改为 `onClick((event: ClickEvent) => ...)` —— 用 `event.y / lineHeight` 求行、`(event.x - gutterWidth) / charWidth` 求列，累加前面各行长度得到字符偏移，再 `caretPosition(off)` + 更新 `cursorLine`（PyCharm 行为）。
  修复后重跑自动化验证：菜单项可命中，但端到端仍未产生折叠且状态栏无提示 → 说明**我的测试脚本点菜单项这一步仍不可靠**（本会话反复出现的点击漂移问题），功能本身未证实也无反证。**待人工确认**：点进 `def greet` 块体 → 右键 → 折叠选区，应折叠该块并在状态栏显示"已折叠选区内的代码块（第 x-y 行）"。

### 0.8 项目区右键 33 → 40（对齐文件条目数）

本轮补齐 7 项（`ProjectViewPopupMenu` 去重 40 项）：
- **WeighingNewGroup（新建组）展开**：新建 Python 文件（真实）、新建 Python 包（真实：建目录 + `__init__.py`）、新建临时文件（真实：写入 filesDir/scratches）
- **RefactoringMenu 展开**：更改签名…（提示）、引入常量…（提示）
- **运行组**：调试（真实：`runActiveFile(true)`）
- **VersionControlsGroup**：拉取…（提示）

真机验证（长按工程树 main.py）：`新建文件 / 新建文件夹 / 新建 Python 文件 / 新建 Python 包 / 新建临时文件 / 与文件类型关联…` 全部命中 ✓；代码内条目数 **40**，与 PyCharm 去重后一致 ✓。

### 0.9 IME 误弹修复（用户反馈）

现象：编辑区右键/长按会连带拉起 HarmonyOS 系统键盘与"选择/自动填充/拍摄输入"工具条，和我们自己的菜单叠在一起。
原因：编辑器输入层是**透明 TextArea**，右键/长按会拿到焦点从而触发 IME。
修复（`CodeEditor.ets`）：`.enableKeyboardOnFocus(false)` + 新增 `dismissSystemInput()`（`inputMethod.getController().stopInputSession()`），在右键与长按两条路径**弹菜单前**调用。
验证：真机长按编辑区，截图只见编辑器菜单，无系统工具条 ✓。

### 0.6 代码折叠 —— 已实现并验证

依据 `EditorPopupMenu1.FindRefactor → FoldingGroup`（9 个动作）。

**实现**：`Index.foldRegions()` 按缩进算块（def/class/async def/if/elif/else/for/while/try/except/finally/with + `# region`…`# endregion`）；`foldedStarts` 用 **`path#line`** 存储 → 按文件持久化；5 个菜单项全部接真（折叠代码块/展开/全部展开/全部收起/折叠文档注释）。
**渲染**：`CodeEditor` 新增 `hiddenLines`/`foldableLines`/`onToggleFold`，三处渲染循环把折叠行渲染为 `height 0 + Visibility.None`；gutter 可折叠行显示 `▾/▸` 折角并**点击切换**（ExpandCollapseToggleAction）。
**安全**：模型 `this.lines` 不动 → 保存写回原文；已验证折叠后沙箱文件内容与折叠前一致。
**真机验证**：全部收起后行号 1-6,8,9,10,15,16,17,19（greet 体/main 体/if 体被隐藏）→ 点击 `▸` 后第 7 行重新出现（该块展开）✓

**未做**：`CollapseSelection`（折叠选区，编辑器选区 API 未暴露）、折叠状态**落盘**（现仅会话内按文件保持）。

### 0.7 控制台右键 —— 已验证 8/8（含工具栏按钮定位）

**工具栏按钮的行为定位**（按状态栏/输出判定，不再靠猜坐标）：
```
2155 = 运行配置选择器的下拉箭头 ⌄
2318 = 运行 ▶        （点击后底部面板弹出，输出 python <path>）
2383 = 调试 🐞       （输出「调试会话已启动」）
```
**控制台右键菜单真机验证**：长按面板内部 → dump **8/8 命中**
`剪切(_T) / 复制(_C) / 复制路径(_O) / 将剪贴板与所选内容比较 / 使用 Google 搜索(_S) / 复制 URL / 暂停输出 / 全部清除`
其中 **`复制 URL`、`暂停输出`、`全部清除` 是控制台独有项**（编辑器菜单没有）→ 排除此前"假阳性"的可能。
**同时修复**：运行时自动打开底部工具窗（PyCharm 行为），否则用户看不到输出。

### 0.7-旧 控制台右键：仍未在设备上验证（阻塞点已定位）

- 已修：运行时自动打开底部工具窗（`runActiveFile` 里补 `showBottomToolWindow = true` + `consoleTab='run'`），对齐 PyCharm 行为。
- **仍未验证**：点击候选"运行按钮"坐标后底部面板未出现，长按落到编辑器 → 弹出的仍是编辑器菜单（此前记的"5/9 命中"即此假阳性）。
- 下一步（可执行）：用**行为探测**定位运行按钮（依次点 4 个候选 x，检查状态栏是否出现"正在运行"），确认面板弹出后再验证控制台菜单 10 项。

### 0.5 编辑器查找/重构槽 与 标签 Ex 组（去重后重新核对）

| 组 | 去重后条目 | 我们 | 说明 |
|---|---|---|---|
| `EditorPopupMenu1.FindRefactor`（编辑器查找/重构槽） | **11**（此前虚高记 40 ✗） | 查找用法 ✅ 已有 | 真身 = 查找用法 + **FoldingGroup（9 个折叠动作）** |
| `EditorTabPopupMenuEx`（标签 Ex 组） | **15**（此前虚高记 54 ✗） | 已覆盖 + 本轮补 4 项 | MarkFileAs（重写/还原文件类型）、运行组、拆分显示组、复制路径此前已覆盖；本轮补：更改文件语言（真实）、与文件类型关联（提示）、显示历史（提示）、外部工具（提示） |

**代码折叠 = 唯一剩下的编辑器大件**，依据 `FoldingGroup` 的 9 个动作：
```
ExpandRegion · ExpandRegionRecursively · ExpandAllRegions
CollapseRegion · CollapseRegionRecursively · CollapseAllRegions
ExpandCollapseToggleAction · CollapseSelection · CollapseBlock
```
现状：菜单项已在，但**是占位提示**（"编辑器为自绘高亮层，尚未实现折叠"）。
真实实现需给 `view/CodeEditor.ets` 加行模型：可折叠区域计算（def/class/if/for/while/try、# region）+ 折叠态跳过行渲染 + gutter 折叠标记 + 与 ExpandCollapseToggleAction 联动 —— 单独立项，下一轮实施。

### 0.3 数字纠正（重复累加 bug，2026-10-10 二次自查）

抽取器把**同一个组在多个 XML 里的重复声明累加**了，导致数字虚高。改为"首次定义为准"去重后：

| 组 | 虚高值（错） | **去重后（对）** | 我们 |
|---|---|---|---|
| `ProjectViewPopupMenu` | 146 | **40** | 12 → **本轮补到 33** |
| `NavbarPopupMenu` | 140 | **37** | 0 |
| `StructureViewPopupMenu` | 78 | **22** | 0 |
| `ConsoleView.PopupMenu` | 48 | **10** | 0 |
| `EditorTabPopupMenu` | 36+54 | **17** | 21 ✅ 已超 |
| `EditorPopupMenu`+`Basic` | 12+6+40 | **6+3** | 20+ ✅ 已超 |
| `ProjectViewToolbar` | 8 | **4** | 7 ⚠️ 多 2 |
| `RunToolbarMainActionGroup` / `RunMenu` | 8 / 10 | **4 / 5** | ~6 / 有 ⚠️ |
| `MainToolbarPopupActions` | 4 | **2** | 6 ✅ |
| group 总数 | 1095 | **595** | — |

**教训**：审计脚本自身也会骗人。凡"数量差"结论必须做**去重 + 抽查**（本轮就是抽查项目区菜单 33 项逐条打开，才发现虚高 3 倍）。

### 0.2 覆盖自查（我主动做的"查自己有没有漏"）

| 检查项 | 结果 | 含义 |
|---|---|---|
| 只扫 `lib/*.jar` | 60 个含动作 XML / **595** 组 | ❌ **不够** |
| 扫 `lib/*.jar + plugins/**/lib/*.jar` | 157 个 XML / **1095** 组 | ✅ 正确基线（比上一版**多 500 组**） |
| 组是否含条目 | **261 个组是 `class=` 代码定义组** | ❌ XML 里查不到条目，**必须读 class 才能枚举**（如 `RunToolbarMoreActionGroup`、`DebuggerToolbarQuickActionsGroup`、`MoreActionGroup`） |
| 非菜单类 UI | 未纳入 595/1095 统计 | ❌ 竖条按钮、状态栏微件、对话框、gutter/inlay、意图/检查、拖拽手势等**不在这套 XML 里** |
| 插件动作 | 220 个插件 jar 已并入 | ✅ |

**结论（诚实版）**：`all_groups.md` 只覆盖"lib 里 XML 声明的组"，**不是全局完备**。
要做到"确定没漏"，必须按下面三步收敛：

1. 用 **1095 组** 的基线（`_cache/pycharm/all_groups_v2.md`，含来源 jar）替代旧清单；
2. 对 **261 个代码定义组**逐一读 class（常量池/字符串）枚举条目；
3. 对**非菜单 UI** 另建一张"界面元素表"（区域 → 元素 → 依据文件），逐个打勾。

### 0.1 核查方法（可复现）

```powershell
# 1) 抽出全部动作 XML
python _cache/pycharm/audit_all.py     # → _cache/pycharm/impl_all/*.xml (60 个)
# 2) 全量 group 清单与条目数
python _cache/pycharm/audit_all2.py    # → _cache/pycharm/all_groups.md (595 组)
# 3) 指定区域逐条展开（带英文文案）
python _cache/pycharm/audit_v3.py      # → _cache/pycharm/audit_groups_full.md
```

> 核查方法：每个区域先定位 PyCharm 的权威定义文件（动作 XML / 主题 JSON / 语言包），
> 再与实现逐一比对；"缺口"只列**代码里确认没有实现**的项（grep 全仓 `未实现/暂未/尚未` 30 处标记 + 人工核对）。

## 1. 顶栏（标题栏 + 主工具栏）

依据：`PlatformActions.xml:1072-1087 (MainToolbarNewUI)`、`ExecutionActions.xml:75-82 (RunToolbarMainActionGroup)`、
`MainToolbarPopupActions.MainToolbarNewUI`、`MainMenuDisplayMode`、`MacToolbarFrameHeader.isCompactHeader`、`ManyIslandsDark.RunWidget`

| 已实现 | 缺口 |
|---|---|
| 产品图标 / ☰（`windowsMenu@20x20`，在产品图标之后） / 菜单标题 / 工程微件 / VCS 微件 / 运行配置选择器 / 运行·调试·停止 / ⋮ / AI / 搜索 / 设置 / 顶栏右键 6 项 + 3 子菜单 / 三种菜单模式（默认隐藏到汉堡）/ 9 色工程配色 / 运行小部件形态（绿底白▶、彩虫子、红底白■、跑过变圈圈箭头） / 中间文件名微件按 `isCompactHeader` 规则隐藏 | **ExecutionTargetsToolbarGroup**（运行目标下拉，位于运行小部件左侧）✗ · 菜单标题栏"合并到窗口标题"✗ |

## 2. 主菜单栏（11 个顶级菜单）

依据：`MainMenu` 组 + `ActionsBundle.properties`（中文名取自语言包）

| 已实现 | 缺口 |
|---|---|
| 文件/编辑/视图/导航/代码/重构/运行/工具/VCS/窗口/帮助 11 个菜单，条目按各 Bundle 文案 | **未做逐条 100% 比对**（各菜单下的条目数很多，见第 9 节待办） |

## 3. 项目区（Project 工具窗）

依据：`ProjectViewToolbar`、`ProjectViewPopupMenu`、`ProjectView` 主题键

| 已实现 | 缺口 |
|---|---|
| 工具栏动作（新建/定位/折叠展开/全部展开全部收起/⋮/筛选/隐藏） · 树右键 12 项 · 合成节点（外部库/临时文件和控制台） · 目录压缩（忽略 `__init__.py`） · 图标（`ideaProject`/`excludeRoot`…） · 双击打开、高亮定位 | **文件级剪贴板**（复制/剪切/粘贴文件）✗（当前只给"复制路径"提示） · 只读标记 ✗（沙箱限制，已如实说明） |

## 4. 编辑器区

依据：`EditorTabPopupMenu`(PlatformActions.xml:1134-1155)、`TabList`(:883)、`EditorPopupMenu`(:1091-1112)、
`EditorTabs.underlineArc=4`、`Component.arc=8`

| 已实现 | 缺口 |
|---|---|
| 标签（左对齐、上圆角 8、下划线圆角 4、预览斜体、未保存点、关闭） · 标签右键 21 项（含移动标签/固定/配置/重新打开，真实可用） · ⋮=TabList 7 项（最近的文件/最近的位置/转到文件/关闭所有/书签/配置标签/显示缩略图）**均已实现真实功能** · 编辑器右键 20+ 项（剪切复制粘贴/特殊粘贴/列选择(提示)/复制路径引用/查找/折叠组(提示)/上下文操作/更改语言/搜索/剪贴板比较(提示)/书签 F11·Shift+F11） · 面包屑 · 查找替换栏 | **代码折叠** ✗ · **多光标** ✗ · **列选择模式** ✗ · **不可见字符** ✗ · **自动换行开关未生效** ✗ · **富文本粘贴/结构化搜索** ✗ · **内嵌图表** ✗ · **书签 gutter 标记未绘制**（功能已通）✗ |

## 5. 左右竖条 + 工具窗

依据：`Stripe`、`ToolWindowContextMenu`、`ToolWindowView`

| 已实现 | 缺口 |
|---|---|
| 两侧竖条按钮（选中态药丸） · 工具窗标题右键 6 项 · 面板拖宽（热区 6vp） · 底部工具窗四边间距对齐 | **5 个工具窗仅有占位内容**（数据库/AI/绘图等）✗ · **最大化工具窗** ✗ · **移至编辑器** ✗ |

## 6. 底部工具窗

依据：`Run`/`Terminal`/`Problems`/`TODO` 各工具窗定义

| 已实现 | 缺口 |
|---|---|
| 运行输出 / 终端 / 问题 / TODO 四个面板 · 高度可拖 | 运行输出缺少"重新运行/停止"工具条（PyCharm 的 Run 工具窗工具栏）⚠️ |

## 7. 状态栏

依据：`StatusBar` + `StatusBarWidgets`

| 已实现 | 缺口 |
|---|---|
| 行列号 / 编码 / 换行符 / 运行时 / 消息与进度 | **VCS 分支微件** ⚠️ · **通知微件**（已有右侧通知岛，非状态栏内）⚠️ |

## 8. 对话框与设置

| 已实现 | 缺口 |
|---|---|
| 设置（分类与 PyCharm 语言包一一对应）· 新建文件语言 · 工具窗口 · 关于 · 运行时 · 在文件中查找 · 文件结构 · 最近文件 · 项目结构 · 文档 · 许可 · 通知 · 快捷键 · 自定义 UI · 转到行 · 运行配置 · 打开的编辑器 · **最近的位置** · **书签** | **设置页的具体选项未实现**（只有分类骨架）✗ · **SearchEverywhere 专用两栏对话框** ✗（现接在"在文件中查找"） |

## 9. 待办优先级（建议顺序）

1. **编辑器折叠**（PyCharm `FoldingGroup`；编辑器为自绘高亮层，需要行模型支持）
2. **SearchEverywhere 两栏对话框**（文件 + 操作）
3. **ExecutionTargets 下拉**（顶栏运行目标）
4. **项目区文件级剪贴板**（复制/剪切/粘贴文件）
5. **工具窗最大化 / 移至编辑器**
6. **设置页选项落地**（按 `Settings` 各分类）
7. **书签 gutter 标记**、自动换行生效、列选择模式

## 10. 本轮（本次核查）新增修复

- 书签三处动作接通真实实现：`edit.toggleBookmark`(F11) / `edit.showBookmarks`(Shift+F11) / `edit.nextBookmark`（跳下一个书签）✓
- TabList 派发 bug 修复：`tabListItem` 独立派发到 `onTabListPick`（此前共用 `tabMenuItem` → 全部落到"最近的文件"）✓
- ⋮(TabList) 三项占位改为真实功能：最近的位置 / 书签 / 显示缩略图 ✓

### 0.44 调试器：暂停语义已确认（真挂起），面板不可见属布局问题

**读原生钩子 kDebugHookScript（entry/src/main/cpp/napi_init.cpp:176-300）确认**：
    command = _pyide_bridge.pause('step' if stepping else 'breakpoint', payload)
Python 侧把原生 pause() 的返回值当命令（stop/step/stepinto/stepout/continue）
⇒ **暂停是真挂起**（阻塞等 IDE 指令），DebugPanel 的「继续/单步/步入」确实能驱动会话 ✓。
断点命中条件、作用域过滤（只在工程根内跟踪）、帧深度（单步跳过）均已实现 ✓。

**因此剩余问题是显示/布局，不是调试能力**：
onDebugPause 确实被调用（控制台出现「已暂停 main.py:11 (main)」✓），debugPaused 也置 true ✓，
但暂停瞬间 dump 里没有任何面板元素（继续/单步/局部变量/调用栈 全不见）✗。
推断：DebugPanel 处在编辑器岛内部的条件分支里，被布局裁掉或压成 0 高 ✗。

**下一步（明确）**：把 DebugPanel 移到必然可见处 —— 建议做成底部工具窗的一个标签页
（与 运行/版本控制/问题/终端/Python 控制台 并列的「调试」页），再重跑「断点→调试→单步」验证变量与调用栈。

### 0.45 调试面板改为底部「调试」页签 —— 变量/调用栈已能显示

**改动**：
- ConsolePanelView 增加 TAB_DEBUG（页签「调试」，位置在「运行」之后）与 `@Prop debugLines: string[]`
- Index 增加 `debugPanelLines()`：把 debugLocals / debugStack 格式化成
  「已暂停 file:line (func)」+「· 变量（N）」+「    name = repr」+「· 调用栈（N）」+「    func  file:line」
- 原来塞在编辑器岛里的 DebugPanel 保留，但**底部页签成为必然可见的入口** ✓

**真机验证**：
    底部页签 ['运行','调试','版本控制','问题','终端','服务','Python 控制台'] ✓
    点「调试」→ 显示 '已暂停 main.py:11 (main)' + '· 变量（0）' ✓✓
    状态栏 '调试暂停于 main.py:11' ✓，编辑器第 11 行高亮 + 断点红点 ✓
**变量为 0 是正确的**：断点停在 main() 的第 11 行（函数第一行），该帧尚无局部变量。
**待优化**：面板内容区被页签栏裁掉一部分（调用栈行在可视区外）—— 需调整底部面板内容高度。

### 0.46 断点列表补验 + 调试页签变量区（本轮）

**断点列表（0.41 的未验部分已补上）**：真机实测
    打开「查看断点」→ 标题「断点（0）」+ 空态「暂无断点（在编辑器行号左侧点一下即可添加）」✓
    点「全部清除」→ 状态栏「已清除全部断点」✓（断点存储写回成功）

**调试页签变量区**：断点在第 11 行（main 函数第一行）时显示「已暂停 main.py:11 (main)」+「· 变量（0）」——
0 是**正确**的（该帧此刻没有局部变量）。

**未完成（如实）**：看到**真实变量值**（如 greet 内第 7 行的 name = '鸿蒙'）——
本轮尝试「全部清除 → 只留第 7 行 → 重启调试」时，脚本误触把应用切到后台，验证中断；
另外发现旧断点会残留在 store 里影响下一次会话（需在每次调试前用「断点列表 → 全部清除」清干净，或让收集逻辑剔除已关闭文件的旧行）。

**下一步（收尾一件事）**：断点仅设在第 7 行 → 调试 → 调试页签应显示 `name = '鸿蒙'` 与两帧调用栈。

### 0.47 调试器闭环达成（断点 → 真挂起 → 变量显示）

**真机验证（关键一跑）**：
    断点设在第 7 行（greet 函数体内，此处有局部变量 name）
    tb-debug → 「调试会话已启动，共 1 个行断点。」✓
             → 「已暂停 main.py:7 (greet)」✓✓   ← 停在函数内部
    切「调试」页签 → 「· 变量（1）」✓✓        ← 正好 1 个局部变量（name）
    编辑器第 7 行高亮 + 红点 ✓，状态栏 7:1 ✓

**交叉验证**：同一功能在第 11 行（main 函数第一行）显示「变量（0）」，在第 7 行显示「变量（1）」
⇒ 变量数量随栈帧变化，证明展示的是**真实调试数据**（而非占位）✓✓

**结论：调试器主链全部打通** —— 设断点 · 启动调试 · 命中断点并真挂起（原生 pause 阻塞等指令）·
暂停位置高亮 · 变量/调用栈数据回流 · 底部「调试」页签展示。
**仅剩外观细节**：变量值的具体文本行被页签栏裁掉一部分（面板内容高度需调整）。

### 0.48 调试页签布局修正（内容归位到内容区）

**问题**：0.45 里「已暂停 + 变量」文本出现在页签栏**上方**，变量值行被页签栏裁掉 ✗。
**真因**：分支插错了位置 —— ConsolePanelView 里有两个 `if (this.activeTab === TAB_*)` 分支链，
我插到了**标题区**那条（原来只有 TAB_RUN 那一个），而不是真正的内容区（与 TAB_REPL/TAB_TERMINAL 并列的那条）。
**修复**：把 TAB_DEBUG 分支从标题区移除，改插到内容区（TAB_REPL 之前）。

**真机验证**：安装后切「调试」页签 → 内容区正确显示空态「未在调试中（在行号左侧点一下加断点，再点工具栏的调试按钮）」✓✓
（位置在页签栏下方，不再被裁切）。

**教训**：同一个组件里存在多条同构的分支链时，锚点文本会命中错误的一条 —— 插入前应先确认该分支链的语义（标题栏 vs 内容区）。

### 0.49 调试器全部功能打通（含单步、变量、调用栈）—— 决定性验证

**新增**：底部「调试」页签内加入四个动作按钮（继续 / 单步 / 步入 / 步出），
通过 ConsolePanelView 的回调 props 转发到 Index 的 resumeDebug/stepDebug/stepIntoDebug/stepOutDebug。

**真机验证（一次跑完，全部通过）**：
    按钮渲染: [继续] [单步] [步入] [步出] ✓
    断点在第 7 行 → 启动调试 → 暂停: '已暂停 main.py:7 (greet)' ✓
    点「单步」→ 暂停变为 '已暂停 main.py:12 (main)' ✓✓  ← 单步真实驱动了原生钩子
    面板内容: 已暂停信息 ✓ · 变量（0）✓ · 调用栈（2）✓ · 栈帧 'main  main.py:12' ✓✓
    编辑器第 12 行高亮 ✓  状态栏 '调试暂停于 main.py:12' ✓

**至此调试器闭环完备**：设断点 → 启动 → 命中断点真挂起 → 暂停位置高亮 → 变量/调用栈显示
→ 单步推进 → 循环往复。与 PyCharm XDebugger 的核心交互一致。
**未做**：Watches（监视表达式）、Evaluate（表达式求值）、多线程视图、断点条件/日志断点。

### 0.50 调试四命令全部验证（步入 / 步出 / 继续）

断点设在第 11 行（main 内调用 greet 处），依次点击底部「调试」页签的按钮：
    初始暂停:      '已暂停 main.py:11 (main)'   ✓
    点「步入」→     '已暂停 main.py:7 (greet)'   ✓✓  进入被调函数
    点「步出」→     '已暂停 main.py:12 (main)'   ✓✓  返回调用者
    点「继续」→     无暂停态（会话结束，程序跑完）✓✓

结合 0.49 的「单步」（7 → 12，跳过函数调用），**XDebugger 的四个核心命令全部真机验证通过** ✓✓✓：
Resume / Step Over / Step Into / Step Out 均真实驱动原生调试钩子并改变暂停位置。

**至此调试器子系统（本可做部分）完整收口**：断点（设置/列表/清除）· 调试会话 · 真挂起 ·
暂停位置同步 · 变量 · 调用栈 · 四命令。剩余 Watches/Evaluate/条件断点需扩展原生钩子命令通道。

### 0.51 调用栈帧可点击跳转（XDebugger Frames 行为）

**实现（纯应用侧，无需改原生）**：
- ConsolePanelView 新增 `@Prop debugStack: string[][]` 与回调 `gotoFrame(file, line)`，把每帧渲染为**独立可点行**
- Index 传入 `debugStack: this.debugStack` 与 gotoFrame 实现：openFile + revealLine + 状态栏提示

**真机验证**：
    调试页签调用栈两行: 'main   main.py:11' 与 '<module>   main.py:18' ✓✓
    点击最外层帧 → 状态栏 '已跳转到 main.py:18' ✓✓，编辑器光标移到 18:1 ✓✓
    （同时确认：已暂停 main.py:11 (main) · 变量（0）· 调用栈（2）· 四命令按钮均在）

**调试器功能至此收口**：断点体系 · 会话 · 真挂起 · 位置同步 · 变量 · 调用栈（含点击跳转）· 四命令。
仍缺（需扩展原生命令通道）：Watches / Evaluate / 条件断点 / 多线程。

### 0.52 Evaluate（求值）打通 —— 原生 eval 往返真机验证

**实现**：
- 原生钩子 kDebugHookScript 扩展命令：`eval:<表达式>` 时在**当前暂停帧**里求值，
  把 {evalExpr, evalResult} 并入新的暂停事件，然后继续阻塞等下一个命令（while 循环处理连续求值）
- DebugPause 模型新增可选字段 evalExpr / evalResult
- ArkTS：求值输入框 + [求值] 按钮 + 求值历史；**变量行可点击即对该变量求值**（无需输入，便于触屏与自动化）

**真机验证（决定性）**：断点在第 7 行（greet 内，`name` 在作用域）
    暂停: '已暂停 main.py:7 (greet)' ✓
    变量行(求值前): ["name = '鸿蒙'"]        ← 1 条（来自 locals 快照）
    点击变量行 → 求值后 `name =` 行数: 2 ✓✓   ← 多出的一条即 eval 往返结果
    相关行: ["name = '鸿蒙'", "name = '鸿蒙'"] ✓✓

**结论**：调试命令通道（ArkTS → C++ 阻塞放行 → Python 钩子）**可扩展且已验证**，
Evaluate 成为调试器第 5 个可用动作（继续/单步/步入/步出/求值）。
**遗留**：输入框打字在自动化里进不去（UI 限制），故加了"点变量行求值"的等价入口；
Watches（监视表达式）可用同一通道实现（把表达式存列表 + 每次暂停自动 eval）。

### 0.53 Watches（监视表达式）—— 实现完成，端到端验证待补

**实现（复用已验证的 eval: 通道）**：
- 点**变量行** = 加入监视（无需打字，触屏/自动化友好）；每次暂停后自动对所有监视表达式发 `eval:<expr>` 刷新
- 求值结果回来时按表达式回填到 Watches（与 Evaluate 历史共用同一事件）
- 调试页签新增「监视」区：每行 `expr = 值` + 「移除」

**状态**：构建通过、已安装、已推送。**端到端验证未完成** —— 本轮脚本中调试会话没有产生暂停
（断点未设上，前一步『全部清除』后 gutter 点击未生效），因此「监视区出现 name = 鸿蒙」尚未取得真机证据。

**下一步（明确）**：断点设第 7 行 → 调试 → 调试页签 → 点变量行 `name = '鸿蒙'` → 监视区应出现同名行 + 「移除」。

**遗留清单（本会话未完成项，全部有明确下一步）**：
1. Watches 端到端验证（上）
2. Evaluate 输入框打字（自动化限制，已有等价的点击入口）
3. 多窗格「向下拆分」以外的 SplitChooser 拖拽弹层（动作已全部可由标签菜单+拖拽触发）
4. 与剪贴板比较（受 HarmonyOS 剪贴板隐私限制，等授权方式确认）
5. 大子系统：VCS 日志 217 / 图表 217 / 外部系统 87 / 作用域视图 41（需对应引擎）

### 0.54 Watches 端到端验证通过（遗留项 #1 关闭）

**真机验证**：断点在第 7 行（greet 内）
    暂停: '已暂停 main.py:7 (greet)' ✓
    点变量行 name = '鸿蒙' → 「监视」区出现 ✓✓ + 监视行 name = '鸿蒙' ✓✓ + 「移除」按钮 ✓✓
    （同时可见：四命令按钮 · Evaluate 输入框与求值历史 · 状态栏 调试暂停于 main.py:7）

**踩坑（第 6 条教训）**：前两次验证失败并非功能问题 —— 我把断点点击坐标放在**行号文字左侧**（x-20 / x-40），
而实际可点区域是**行号文字本身**（点其中心才切换断点）。坐标差 50px 就点空，
与此前 hdc 路径未加引号同类：**环境/脚本细节会伪装成功能缺陷**。以后 gutter 点击统一取行号文本中心。

**调试器最终可用动作（全部真机验证）**：继续 / 单步 / 步入 / 步出 / Evaluate 求值 / Watches 监视。

### 0.55 图表子系统（Graph 217）可行性结论 + 第一片实现并验证

**依据核实（PyCharm 文件）**：该子系统来自 intellij.platform.graph.impl.jar，组为：
    Graph.NeighborhoodViewPopup(61) · Graph.DefaultGraphPopup(39) · NeighborhoodViewPopup.LayoutGroup(25)
    · NeighborhoodViewPopup.AppearanceGroup(14) · Graph.AppearanceGroup(13) · Graph.DefaultGraphToolbar(12)
    · Graph.OrthogonalLayoutGroup(6) · Graph.TreeLayoutGroup(6) · Graph.EdgeRealizerGroup(6) …
即「图表/邻域视图」：节点+边 + 布局（树形/正交）+ 外观 + 工具栏。

**可行性：高** —— 纯应用侧渲染（ArkUI Canvas），数据由自己的解析器产出（类继承 + 函数调用），不需要任何外部引擎。

**第一片已实现并真机验证**（入口：随处搜索首屏「图表：当前文件关系图」）：
    对话框标题 '图表：当前文件的关系' ✓
    统计 '2 节点 / 1 边' ✓✓（与 main.py 实际结构一致：greet、main 两函数 + main 调用 greet）
    工具栏 [树形布局][正交布局][重新布局] ✓，Canvas 真实绘制两个带标签节点框与连边 ✓✓
    状态栏 '关系图：2 个节点 / 1 条边（类继承 + 函数调用）' ✓

**实现要点**：节点 = 类/函数（类另加其基类节点）；边 = 继承（类>基类）+ 函数调用（函数名+括号命中）；
布局 = 树形（单列）/ 正交（双列），两布局差异可见。

**待做（Graph 各组）**：NeighborhoodViewPopup 的导出图/打印/放大缩小 · Appearance 组（配色/边样式）·
EdgeRealizer 组（直线/折线/曲线）· DefaultGraphPopup（在新标签页打开/浮动窗口）· 布局扩展（层次/力导向）。
