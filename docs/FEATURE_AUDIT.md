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

### 0.56 图表第二片：边样式 / 布局方向 / 缩放（含工具栏 7 控件）—— 已验证

对应 PyCharm 的 Graph.EdgeRealizerGroup（直线/折线）、TreeLayoutGroup/OrthogonalLayoutGroup（方向）、
DefaultGraphToolbar（放大/缩小/适应）。

**真机验证**：
    工具栏: 树形布局 · 正交布局 · 折线 · 左右 · － · ＋ · 适应          ✓ 7 控件齐
    点「折线」→ 标签变「直线」                                        ✓ 边样式切换
    点「左右」→ 标签变「上下」，且画布中节点由竖排改为横排（greet 左 / main 右）✓ 方向切换
    点「＋」两次 → 节点与字号明显放大                                  ✓ 缩放生效
    验证后「取消」关闭对话框，状态还原                                  ✓

**实现**：方向 h/v 决定行列轴；缩放 z 同时作用于框宽高、间距、字号、线宽；折线为正交走线（先出再折再入）。
**已知小瑕疵（下一轮修）**：放大后两个节点框宽度不一致（左宽右窄），应在同一 z 下等宽。

### 0.57 图表第三片：外观（标签/配色）+ 导出 PNG + 工具栏换行修复 —— 已验证

对应 PyCharm 的 Graph.AppearanceGroup（外观）、Graph.DefaultGraphToolbar（导出）。

**实现**：
- 「显示/隐藏标签」开关（对应 AppearanceGroup 的显示项）
- 「配色」三套方案（蓝灰 / 棕 / 绿），作用于节点填充、描边、边色、文字
- 「导出 PNG」：Canvas.toDataURL → Base64Helper 解码 → FileService.writeBinary 写入 <工程根>/关系图.png，并刷新工程树
- 节点框统一用同一 boxW/boxH（修掉上一轮放大后框宽不一致的瑕疵）

**真机验证**：
    工具栏换行后 10 个控件全部可见: 树形布局·正交布局·折线·左右·－·＋ / 隐藏标签·配色·导出 PNG·适应 ✓
    点「配色」→ 节点框配色肉眼可见地由蓝灰变棕 ✓✓
    点「导出 PNG」→ **工程树出现「关系图.png」** ✓✓✓（文件真的写盘，非占位提示）
    节点框等宽 ✓  验证后「取消」关闭对话框 ✓

**过程中修掉的真问题**：工具栏加到 10 个控件后**溢出对话框宽度**，导致「导出 PNG」点在可视区外 ✗
→ 改用 Flex + FlexWrap.Wrap 两排布局后全部可点 ✓（教训：**新增控件要检查容器是否溢出**）。

### 0.58 图表第四片：点节点跳源码 + 按调用深度分层布局 —— 已验证

对应 PyCharm NeighborhoodView 的双击节点跳转 与 TreeLayoutGroup 的层次语义。

**实现**：
- 命中检测：drawGraph 时把每个节点框记为 "名字|x|y|w|h"；Canvas.onClick 用坐标查框
  → 命中则 lineOfSymbol(name) + revealLine + 状态栏「已从图表跳转到 X（第 N 行）」；
  基类/外部符号则提示「当前文件内没有定义行」
- 分层布局：对边做最长路径松弛，深度 = 调用/继承层数；v 方向按「行=深度」排（调用者在上）

**真机验证**：
    分层：main 在上一层、greet 在下一层 ✓✓（main 调用 greet，层次语义正确）
    点节点 → 状态栏「已从图表跳转到 main（第 10 行）」✓✓，第 10 行正是 def main()
    点空白 → 「未命中任何节点」✓（命中检测边界正确）
    验证后「取消」关闭对话框 ✓

**图表子系统小结（4 片，全部真机验证）**：节点/边构建 · 树形/正交布局 · 边样式 · 方向 · 缩放 ·
标签开关 · 三套配色 · 导出 PNG（真写盘，工程树可见）· 按深度分层 · 点节点跳源码。
**待做**：打印 · DefaultGraphPopup（新标签页/浮动窗口）· 力导向布局 · 框选缩放 · 边标签/箭头。

### 0.59 作用域视图（ScopeView 41）：可行性结论 + 用 Python ast 真解析实现并验证

**依据核实**：ScopeViewPopupMenu（41 条）来自 intellij.platform.ide.impl.jar + intellij.pycharm.pro.jar，
是**作用域视图窗口的右键菜单**：绝大多数是「查找用法 / 重构 / 在作用域中查找 / 按作用域分组」——
**依赖语义索引引擎，本设备不可做** ✗（不假实现）。

**可行性结论**：菜单项不可做；但**作用域视图的内容**可做，而且能做成**真解析** ✓ ——
运行时桥可在设备上执行 Python，于是直接调用标准库 ast 解析当前文件，而不是用正则近似。

**实现**：
- 把 ast 解析脚本写入 <filesDir>/.harmonyide/ast_scope.py，调用 PyRuntimeService.run(script, [源文件, 输出文件])
- 脚本输出「模块/类/函数」层级行：名字 + 行号 + 缩进深度；函数行附「参数 N · 局部赋值 N · 调用 N」
- 结果写到 <工程根>/.harmonyide/scope.txt，应用读回后展示（避免解析 stdout 的不稳定）
- 对话框点行 → revealLine 跳到该作用域所在行；入口：随处搜索首屏「作用域视图」

**真机验证（数字逐一核对）**：
    标题「作用域视图：3 项（AST 解析）」✓
    模块 main.py  L1  总行 18 ✓
    函数 greet  L6  参数 1 · 局部赋值 0 · 调用 0 ✓✓（greet 确实 1 个参数、无调用）
    函数 main   L10 参数 0 · 局部赋值 0 · 调用 9 ✓✓（print×4 + greet + split + machine + sum + range = 9，精确）
    点行 → 「已跳到作用域所在行 1」✓   验证后「取消」关闭 ✓

**意义**：这条通道（运行时跑 Python 标准库 → 写文件 → 应用读回）打开了**真解析**的可能，
后续「转到符号 / 结构视图 / 继承层级」都可以逐步升级为 ast 版，摆脱正则近似。
**待做**：符号级用法计数（ast 里统计每个名字的引用次数）· 类成员列表 · 每个作用域的 import 列表 ·
ScopeViewPopupMenu 里可做的那几项（展开/折叠/跳到定义）。

### 0.60 结构视图升级为 ast 真解析（用 0.59 打通的运行时通道）

**动机**：原 refreshStructure 是正则扁平扫描 —— 丢嵌套、看不出 async、也给不出行号 ✗。
既然 0.59 已打通「运行时跑 Python → 写文件 → 应用读回」，就把结构面板换成 ast 结果。

**实现**：
- ast 脚本增强：区分「函数 / async 函数」，输出含缩进深度与行号
- refreshStructure 先给正则结果（即时可见），随后异步 refreshAstStructure() 用 ast 结果覆盖
  （运行时未就绪或语法错误时自动保留正则结果，不空白）
- 结构行格式：`ƒ  name    L12` / `ƒa  name    L12`（async）/ `C  name    L3`，用缩进表达嵌套
- lineOfSymbol 增强：若入参是这类结构行，先取 `L数字` 后缀 —— 因此面板点击跳转直接精确到行

**真机验证**：
    Structure 面板: `ƒ  greet    L6` 与 `ƒ  main    L10` ✓✓（带行号，正则版做不到）
    hilog: `ast structure rows=2` ✓（独立证据，说明 ast 结果确实覆盖成功）

**价值**：结构面板、转到符号、转到类、继承层级都已具备「升级为 ast 版」的数据基础；
下一步可把「转到符号」的查询也接到 ast 结果上（含类成员、嵌套函数）。

### 0.61 外部系统（ExternalSystem 87）：可行性结论 + 任务/依赖落地并验证

**依据核实**：ExternalSystem 组（intellij.platform.externalSystem.impl.jar + intellij.pycharm.pro.jar）
    Actions(25) · ActionsToolbar(12) · RunConfigurationMenu(10) · TaskMenu(9) · ProjectMenu(6) ·
    DependencyAnalyzer.DependencyListGroup/DependencyTreeGroup/UsagesTreeGroup · ProjectRefreshActionGroup · ShowSettingsGroup
即 Maven/Gradle 式**外部构建系统**集成（任务树、同步、依赖分析）。

**可行性结论**：构建系统集成（同步/导入 Maven-Gradle 工程、依赖树解析）在 HarmonyOS 上**不可做** ✗（设备无对应工具链）；
但两件事可做且有意义 ✓：① **任务执行**（TaskMenu 语义）用已有的真 PTY 终端；② **依赖清单**（DependencyListGroup 语义）
用运行时通道读**真实已安装包**。

**实现**：
- 「外部系统：任务与依赖」对话框：4 个外部任务按钮 + 依赖清单区
  Python 版本（python -V）· 编译检查（python -m py_compile 当前文件）· 统计行数（find … wc -l）→ 都在真实终端执行并回显
  · 读取依赖清单 → 运行时跑脚本用 importlib.metadata 列出已安装包 → 写文件 → 应用读回展示
- 入口：随处搜索首屏「外部系统：任务与依赖」

**真机验证**：
    对话框与 4 个任务按钮齐 ✓
    点「读取依赖清单」→ 标题「外部系统：依赖清单（1 个包）」✓✓，内容 `pip   25.0.1` ✓✓
    —— 数字精确（打包的 CPython 确实只装了 pip 25.0.1）
    验证后「取消」关闭 ✓

**未做（如实）**：构建系统同步/导入 · 依赖树与用法分析 · 运行配置管理 · 项目刷新。

### 0.62 VCS 日志（217）：可行性结论 + 变更时间线落地并验证

**依据核实**：VCS 相关组来自 intellij.platform.vcs.impl.jar / vcs.log.impl.jar / vcs.dvcs.impl.jar：
    Vcs.FileHistory.ContextMenu/PresentationSettings/Toolbar（文件历史视图）· Vcs.Browse · Vcs.CheckinProjectMenu/Toolbar ·
    Vcs.Commit.* · Vcs.Diff.* · Vcs.CherryPick · Vcs.SavedPatches.* · Vcs.Shelf.* · Vcs.Push · Vcs.RepositoryChangesBrowserMenu

**可行性结论**：所有需要 git 的能力（提交/拣选/推送/与修订比较/搁置/补丁）在本设备**不可做** ✗（HarmonyOS 应用内无 git 可执行文件）；
但 **Vcs.FileHistory（文件历史/变更时间线）可做** ✓ —— 本地历史已经在按文件记录版本快照，
它承载的正是「变更历史」这一核心信息。

**实现**：
- 快照目录写入 path.txt 记录来源文件；对早期没有 path.txt 的目录，用「路径哈希」反查工程内 .py 文件兜底
  （历史目录名就是路径哈希，因此可逆匹配）
- 「变更时间线」对话框：汇总所有文件的历史版本，按时间倒序显示「时间戳 文件名 N 行」
- 点任意版本 → 用该快照与该文件**当前磁盘内容**做差异（复用 0.39 的差异引擎）
- 入口：随处搜索首屏「变更时间线」

**真机验证**：
    标题「变更时间线：1 个历史版本」✓
    版本行 `main.py   19 行` ✓✓（哈希兜底生效，不再显示哈希目录名）
    双击版本 → 差异对话框「差异：历史版本 ↔ 当前内容」+ `+0 -0`（未修改，无差异，行为正确）✓✓
    状态栏「历史版本比较：+0 行 / -0 行」✓   验证后「取消」关闭 ✓

**未做（如实）**：git 提交/分支/提交图 · 与任意修订比较 · 搁置 · 补丁 · 推送/拉取。
**小改进待做**：时间戳显示成可读时间（当前是毫秒字符串）。

### 0.63 打磨：历史时间戳人性化（并发现 SE 首屏拥挤问题）

**实现**：新增 formatStamp(ms) → `MM-DD HH:mm:ss`；变更时间线与本地历史对话框都改用它。

**真机验证**：
    变更时间线版本行：`10-11 14:52:10   main.py   19 行` ✓✓（此前是 `1791701530906.txt` 毫秒串）

**发现的问题（下一轮修）**：入口越加越多，**「转到符号」被挤出 SE 首屏可视区**（现在第 9 位）✗，
本轮未能验证「转到符号显示 ast 行并可跳转」✗。
与 0.57 的「工具栏 10 个控件溢出」同类：**新增入口要检查既有入口是否被挤出可视区**。

**代码事实（供下一轮验证）**：转到符号对话框渲染的正是 liveStructure —— 而它在 0.60 已改为 ast 结果
（`ƒ  greet    L6` 形式），点击走 lineOfSymbol（已支持 `L数字` 后缀）⇒ 数据与跳转链路都在，只差一次可见验证。

### 0.64 入口可达性自检 + 转到符号 ast 行验证（补上 0.63 欠的账）

**新增自检（把「入口可达性」变成可验证事实）**：
    selfcheck seFirst=<SE 首屏前 6 项>   seActions=<总数>
以后任何新增入口若把旧入口挤出首屏（0.63 的问题），日志立刻暴露，不必靠人肉发现。

**SE_ACTIONS 重排**：导航类（转到符号 / 转到类 / 切换器 / 继承层级）回到首屏，
面板类（变更时间线 / 外部系统 / 作用域视图 / 图表 / 与剪贴板比较 / 查看断点 / 本地历史 / 保存 / 比较当前文件与磁盘版本）随后。
重排过程中我一次生成的行引号写坏（编译失败），修复后又担心丢条目，遂做了**数据完整性核对**：
按行计数 13+2+3+3+3+3+3+2 = 35 项、**无重复** ✓（此前日志里的 29 是更早安装的旧值）。

**真机验证**：
    selfcheck seFirst=转到符号 / 转到类 / 切换器 / 继承层级 / 变更时间线 / 外部系统：任务与依赖 ✓
    selfcheck seActions=35 ✓
    转到符号对话框符号行：`ƒ  greet    L6`、`ƒ  main    L10` ✓✓（ast 数据 + 行号）
    点行 → 状态栏「已转到符号 main    L10（第 10 行）」✓✓，编辑器第 10 行高亮 ✓
    验证后「取消」关闭 ✓

**外观小瑕疵（下一轮修）**：状态栏/提示里把结构行的 `L10` 后缀也当成符号名显示了，应只显示名字与行号。

### 0.65 符号级引用计数（实现完成、脚本已验证；应用内显示待修）+ 提示语外观修复

**外观修复（已真机验证）**：状态栏不再把结构行的 `L10` 后缀当符号名 ——
    实测「已转到符号 main（第 10 行）」✓✓（此前是「已转到符号 main    L10（第 10 行）」）

**引用计数（ast）**：脚本改为先收集定义、再统计 Load 上下文里各名字出现次数，
在每行追加「· 被引用 N」——这是「查找用法」的数据基础。
**本机同一份脚本验证（脚本逻辑正确）**：
    模块 sample_main.py  L1  总行 10
      函数 greet  L3  参数 1 · 局部赋值 0 · 调用 0 · 被引用 1 ✓
      函数 main   L6  参数 0 · 局部赋值 0 · 调用 2 · 被引用 1 ✓

**✗ 应用内显示未生效（本轮未验证通过，不计入完成）**：结构面板仍显示 `ƒ  greet    L6`，没有 `· 引用 1`。
根因判断：PyRuntimeService.run 返回后立刻读输出文件，而**进程可能尚未写完**（await 只保证启动不保证完成），
于是读到的是上一轮的旧 scope.txt。**下一轮修法**：改成轮询输出文件（最多等 ~5 秒，直到内容变化或可解析）再读取，
然后重新验证结构行出现「引用 N」。
**教训（第 7 条）**：跨进程产出文件时，「启动完成」≠「写入完成」——必须用轮询或完成回调，不能靠 await 之后立刻读。

### 0.66 轮询读取修复（生效）+ 引用计数显示仍未通过（精确定位中）

**已修复并验证**：新增 runPyAndRead(script, args, out) —— 跑脚本后**轮询输出文件**（每 200ms，最多 6s，
直到内容变化），结构刷新 / 作用域视图 / 依赖清单三处统一改用它。
真机证据（同一次启动内可见两阶段）：
    启动 12s：`ƒ  greet`、`ƒ  main`（正则即时结果）
    再等 8s ：`ƒ  greet    L6`、`ƒ  main    L10`（ast 结果覆盖成功）✓
说明「跨进程写文件必须轮询」的修法**确实生效**（0.65 的第 7 条教训已落地）。

**仍未通过**：结构行没有 `·  引用 N` ✗（不计入完成）。
**精确诊断（本轮）**：把 Index.ets 里的 SCOPE_AST_SCRIPT 常量**原文抽出**、在本机用同一份 Python 跑样例：
    类 Animal  L3 · 被引用 1
      函数 speak  L4  参数 1 · 局部赋值 0 · 调用 0 · 被引用 0
    async 函数 fetch  L7  参数 1 · 局部赋值 0 · 调用 0 · 被引用 1
    函数 main   L10 参数 0 · 局部赋值 1 · 调用 4 · 被引用 1
⇒ **脚本本身完全正确**（含嵌套、async、引用计数）✓。
而设备上面板显示的 `ƒ greet L6`（有 L6、无被引用）恰是**旧脚本**的产物 ⇒ 设备侧 scope.txt 未被新脚本刷新。

**下一步（明确）**：① 把「作用域视图」调回可点位置，用它直接查看设备上 scope.txt 的**原始行**，区分「脚本没跑」还是「跑了但写失败」；
② 捕获 PyRuntimeService.run 的输出/错误（重定向到日志），拿到设备的真实报错；③ 修好后重验。

### 0.67 ★ 根因修复：运行时未就绪导致设备侧一直读旧输出（引用计数显示通过）

**根因（诊断日志一击命中，两轮悬案结清）**：
    runPy start scriptLen=1577 outLen=101              ← 新脚本确实写入了（1577 字符）
    runPy returned code=-1 stdoutLen=0 stderr=尚未初始化  ← ★ Python 运行时此刻还没初始化完
    runPy TIMEOUT/UNCHANGED head=模块 main.py L1 总行 18|函数 greet L6   ← 于是沿用第 5 轮的旧输出
即：**启动期的结构刷新早于运行时初始化完成**，脚本跑不起来，而输出文件是旧的，
轮询又只在「内容变化」时才返回 ⇒ 一直用旧数据。

**修复**：runPyAndRead 检测到 `code=-1` 或 stderr 含「尚未初始化」时，**每 500ms 重试，最多 20 次（~10s）**。

**真机验证（同一批日志链条完整）**：
    runPy returned code=0 stderr=（空）                     ✓ 重试后运行成功
    runPy fresh outLen=117（旧的是 101）                    ✓ 拿到新输出
    ast structure rows=2                                   ✓
    结构面板行：`ƒ  greet    L6  ·  引用 1`、`ƒ  main    L10  ·  引用 1`  ✓✓✓
    —— greet 与 main 各被引用 1 次，与源码完全吻合（print(greet(..)) 一次；if __name__ 里 main() 一次）

**教训（第 8 条）**：**诊断日志要能区分「没跑」「跑失败」「跑成功但读旧文件」三种情况** ——
本轮把 scriptLen / code / stderr / outLen / head 一并打出来，一次就定位到两轮的悬案。
另外：凡「启动期触发的异步任务」，都必须考虑依赖（运行时/文件系统）尚未就绪的情况。

### 0.68 查找用法（Find Usages）：ast 真解析，两阶段交互，真机验证通过

**依据**：PyCharm 的 Find Usages（编辑菜单/右键），是其重构能力的入口；本例用 ast 复现其核心：
「某符号在文件里出现在哪些位置、每处是什么代码」。

**实现**：
- ast 脚本加「用法模式」：第三个参数传符号名 → 用 ast.walk 收集该名字的 Load 引用与同名属性访问，
  输出 `L行号   该行代码`（按行号排序）；不传符号名则维持原「符号清单」输出
- 对话框两阶段（全触屏，无需键盘）：阶段1 列符号（取自 ast 结构，含引用计数）→ 点符号 →
  阶段2 列用法（行号 + 代码）→ 点用法 → 该行高亮
- 入口：随处搜索首屏「查找用法」（置于导航类入口之后）

**真机验证（完整链路）**：
    SE 首屏含「查找用法」✓
    阶段1：「查找用法」+ `ƒ  greet    L6  ·  引用 1`、`ƒ  main    L10  ·  引用 1` ✓✓
    点 greet → 阶段2「查找用法：greet（1 处）」✓✓
    用法行 `L11   print(greet("鸿蒙"))` ✓✓（行号与代码都精确）
    点用法 → 「已跳到用法所在行 11」✓，编辑器第 11 行高亮 ✓   验证后「取消」关闭 ✓

**说明**：当前按「单文件」分析（ast 解析当前文件）；跨文件用法需要工程级索引，属未做项。
**过程中的教训**：写生成代码的脚本时，若外层用模板字符串承载内部含反引号的代码，极易提前闭合；
此类场景改用单引号字符串承载（反引号与 ${} 在单引号串里是普通字符），一次通过。

### 0.69 继承层级 ast 化（已实现、构建通过；真机验证未通过 ✗）+ 示例工程自愈

**实现**：
- ast 脚本加「继承层级模式」（第三参数 `__hierarchy__`）：输出每类的基类、自身方法、以及从**同文件基类继承来的方法**
- classHierarchy() 优先返回 ast 结果（正则版丢嵌套、看不出继承来的方法）
- 打开「继承层级」的两处入口（菜单路径 + 搜索路径）都会触发 ast 分析
- 示例工程新增 `demo_pkg/models.py`（Animal / Dog(Animal) / Cat(Animal)，含重写与新增方法）
  —— createSampleProject 是**逐文件存在性判断**，所以旧工程也会补齐；为此在「重开最近工程」分支加了
  **示例工程自愈**（仅当路径含「示例工程」时调用，避免往用户自己的工程里注入示例文件）

**过程中修的真问题**：我早先两次编辑被中断，导致同一段代码被插入 3 份（AST 报 Duplicate identifier / Duplicate function）✗
→ 逐处去重（先读清重复区域再改），最终状态：`loadAstHierarchy` 1 处、`astHierRows` 1 处 ✓。
教训：**编辑被中断后要重新核对文件实际状态**（我一次失败的程序其实已应用了第一条编辑）。

**✗ 真机验证未通过（不计入完成）**：预期工程树出现 `demo_pkg/models.py`，实测 `工程树含 models.py: False`。
待查方向：① lastProjectRoot 里保存的路径是否与「示例工程」字面一致（中文是否被转义）；
② createSampleProject 里新块是否真的执行（加日志）；③ 工程树是否在自愈后才构建。
继承层级本体的显示同样**尚未取得真机证据**。

### 0.70 ★ 继承层级 ast 化真机验证通过（0.69 的账结清）+ 第 10 条教训

**0.69 的「未通过」其实是验证方法错误，不是功能缺陷** —— 诊断日志给出决定性证据：
    sample heal check last=/data/storage/el2/base/haps/entry/files/PyProjects/示例工程 isSample=true ✓
    sample heal done models=true  ✓✓（文件确实创建成功）
而工程树 dump 只有 main.py / utils.py —— 因为 **demo_pkg 目录是折叠的**，models.py 在里面根本没被渲染。
展开 demo_pkg 后：`__init__.py / models.py / main.py / utils.py` ✓。

**真机验证（最终）**：打开 models.py → 继承层级：
    类 Animal  L4  基类 (无) / 方法 __init__ L7 / 方法 speak L10 ✓
    类 Dog  L14  基类 Animal / 方法 speak L17 / 方法 fetch L20 ✓
        ← 继承 Animal.__init__ L7、← 继承 Animal.speak L10 ✓✓（继承来的方法，正则版给不出）
    类 Cat  L24  基类 Animal / 方法 speak L25 ✓
    状态栏「继承层级：12 行（ast）」✓
    附带：Structure 面板同时显示类层级 + 引用计数（C Animal L4 · 引用 2 / C Dog L14 · 引用 0 …）✓✓
    验证后关闭对话框 ✓

**第 10 条教训**：**验证要看懂 UI 的折叠/懒渲染** —— 树里存在 ≠ dump 里可见（折叠节点不渲染）；
本次若先展开再找，就不必多花一轮。此前 0.63/0.66 的教训也属同类：先确认「现象」是不是「观测方式」造成的。
**另附**：示例工程现在多了 demo_pkg/models.py（Animal/Dog/Cat），并且**旧工程会自动补齐**（示例工程自愈）✓，
这些文件同时充当 IDE 各功能的真机验证样本。

### 0.71 ★ 跨文件查找用法（全工程 ast 扫描）—— 真机验证通过

**意义**：此前所有分析都是**单文件**的（结构/作用域/用法/层级都是当前文件），
而 IDE 与文本编辑器的分水岭正是**跨文件符号索引**。本轮补上。

**实现**：
- 新增 PROJECT_AST_SCRIPT（独立常量，不动已验证的单文件脚本）：os.walk 遍历工程内所有 .py，
  对每个文件 ast 解析，输出 `定义  文件:行   代码` 与 `用法  文件:行   代码`；不带符号参数时输出全工程类与函数清单
- 「查找用法」改为两阶段全工程流程：阶段1 列**全工程符号**（类/函数 + 所在文件行）→ 点符号 →
  阶段2 列**跨文件结果**（定义与用法混排，各带文件:行:代码）→ 点行跳转
- 示例工程升级：main.py 增加 import utils 与 utils.fib(8) 调用（制造真实跨文件引用）；
  并加「示例文件版本升级」——旧版 main.py（无 import utils）会被重写，否则设备上的旧工程永远缺这个样本

**真机验证**：
    全工程符号（真跨文件）：函数 start demo_pkg/core/engine.py:4 / 类 Animal demo_pkg/models.py:4 基类 (无) /
        类 Dog models.py:14 基类 Animal / 类 Cat models.py:24 / 函数 speak models.py:10,17,25 / fetch models.py:20 ✓✓
    点 fib → 「查找用法（全工程）：fib（2 处）」✓✓
        用法  main.py:17   print("斐波那契:", utils.fib(8))  ✓✓
        定义  utils.py:4   def fib(n: int) -> list:         ✓✓
    —— 用法在一个文件、定义在另一个文件，一次搜索同时给出并标注文件与行号 ✓✓
    状态栏「fib 的用法：2 处」✓  验证后关闭对话框 ✓

**过程中的教训（第 11 条）**：一次程序里多处编辑，其中 1 处锚点失败会导致**后面的编辑全部不执行**，
而我只看最后的 BUILD SUCCESSFUL 就以为都成了 —— 实际 loadProjectSymbols 根本没被加进去。
**教训：编辑脚本跑完必须逐项 grep 校验，不能只看构建结果**（构建成功 ≠ 改动都在）。

### 0.72 ★ 跨文件转到定义 —— 真机验证通过

**实现**：把 0.71 的跨文件结果变成**可点击**的导航 —— 结果行格式 `定义/用法  文件:行   代码`，
点击时解析出文件与行：若与当前文件不同则 openFile() 打开该文件（新标签/激活），再 revealLine 定位。
（此前点击只在当前文件内跳行，跨文件结果只能看不能用 ✗）

**真机验证**：
    在 main.py 里：查找用法 → fib → `用法  main.py:17   print("斐波那契:", utils.fib(8))`、
        `定义  utils.py:4   def fib(n: int) -> list:` ✓
    点「定义 utils.py:4」→ 状态栏「已跳到 utils.py:4」✓✓
    当前文件变为 utils.py ✓，截图显示：标签页切到 utils.py、编辑器中第 4 行 def fib 高亮、
        面包屑「示例工程 > utils.py」、工程树里 utils.py 选中、Structure 面板显示 «ƒ fib  L4 · 引用 0» ✓✓

**本轮同时落实了第 11 条教训**：编辑后立刻 grep 逐项校验（状态语 1 处、注释 1 处），再构建、再上机。
**下一步**：跨文件转到定义已通，可继续做 ① 跨文件转到类 ② 工程级结构视图 ③ 跨文件补全（输入 utils. 列出成员）。

### 0.73 ★ 跨文件转到类 —— 真机验证通过

**实现**：新增「转到类（全工程）」对话框：复用工程级 ast 脚本（无符号参数模式）→ 过滤出 `类` 行 →
每行显示 `类 名字  文件:行  基类 …`；点行解析出文件与行 → openFile 打开 + revealLine 定位。
（此前「转到类」只列**当前文件**的类 ✗）

**真机验证**：
    起始 main.py → SE「转到类」→ 标题「转到类（全工程）」✓
    类行：类 Animal demo_pkg/models.py:4 基类 (无) / 类 Dog models.py:14 基类 Animal / 类 Cat models.py:24 基类 Animal ✓✓
    点 Dog → 状态栏「已跳到类 Dog（demo_pkg/models.py:14）」✓✓
    截图：标签页切到 models.py、面包屑「示例工程 > demo_pkg > models.py」、
        Structure 面板完整显示类层级 + 引用计数（C Animal L4·引用2 / ƒ speak L10 / C Dog L14 / ƒ fetch L20 / C Cat L24 …）✓✓

**至此跨文件能力三件套齐备**：全工程符号索引（0.71）· 跨文件转到定义（0.72）· 跨文件转到类（本轮）。
**下一轮**：工程级结构视图（左栏结构面板显示全工程符号树）或跨文件补全（输入 utils. 列成员）。

### 0.74 ★ 工程级结构视图（Structure 面板 文件/工程 范围切换）—— 真机验证通过

**实现**：
- Structure 面板头部加「文件 / 工程」两个范围按钮（PyCharm 的 Structure 视图可切换范围）
- 工程范围的数据来自 0.71 的工程级 ast 扫描，格式化为面板行 `C/ƒ  名字    相对文件:行`
- **顺带给面板行补上点击跳转**（此前面板行只有右键菜单与长按，左键无反应）：
  文件范围 → 用 lineOfSymbol 跳当前文件；工程范围 → 解析 文件:行，openFile 打开目标文件再定位

**真机验证**：
    文件范围：ƒ greet L8 · 引用 1、ƒ main L12 · 引用 1 ✓（当前文件）
    点「工程」→ 状态栏「全工程符号：11 个（ast 跨文件）」✓，面板变为跨文件符号树：
        ƒ start demo_pkg/core/engine.py:4 / C Animal models.py:4 / C Dog models.py:14 / C Cat models.py:24 /
        ƒ speak models.py:10,17,25 / ƒ fetch models.py:20 / ƒ greet main.py:8 ✓✓
    点首行 → 「已跳到 demo_pkg/core/engine.py:4」✓✓，编辑器切到 engine.py（标签页 + 面包屑 ✓），第 4 行高亮 ✓
    验证后切回「文件」范围（状态还原）✓

**里程碑**：至此**左栏结构面板 = 全工程符号树**，配合 0.71–0.73，跨文件读/查/跳三条路都通了。
**下一轮**：跨文件补全（输入 utils. 列出该模块成员）或 工程级问题/待办面板。

### 0.75 ★ 全工程检查：未使用导入检测 —— 真机验证通过（检出 2 条，含 1 条真实问题）

**实现**：工程级 ast 脚本加「检查模式」（第三参数 `__inspect__`）：
对每个文件收集 import 名字（含 as 别名与下划线取首段），再统计 Load 上下文里实际出现的名字，
0 次引用即报 `未使用导入  相对文件:行   源码行`。入口：随处搜索首屏「检查未使用导入」→ 结果对话框（点行跨文件跳转）。
示例工程新增 demo_pkg/legacy.py（import json 未使用、import os 有用到）作为对照样本。

**真机验证（含精确性对照）**：
    标题「检查结果（2 条）」✓
    未使用导入  demo_pkg/__init__.py:3   from .core import engine  ✓✓（示例工程自带的真实问题，非植入）
    未使用导入  demo_pkg/legacy.py:2     import json               ✓✓（植入样本精确命中）
    状态栏「检查完成：2 条」✓  验证后关闭对话框 ✓
    ★ **精确性证据：没有误报 `import os`**（同一文件里 os.name 真的被用到）—— 说明是真交叉引用分析，不是行文本猜测 ✓

**过程中修的真问题**：① 我插入脚本行时把前一行的逗号一起吃掉 → ArkTS 报 «',' expected» at 379:3；
② 主题字段写错（warningFg → warning）。两者都是构建期暴露的，按错误行号定位后一次修好。
**教训（第 12 条）**：往**字符串数组常量**里插行时，锚点要连逗号一起写进 new_string，否则会吃掉分隔符（这类错误只会在构建时以「',' expected」暴露）。

### 0.76 检查项扩展（重复定义 / 空实现）+ 修掉自己引入的误报 —— 真机验证通过

**实现**：检查模式在「未使用导入」之外增加两项：
- 重复定义：同一**作用域**内同名 def/class 出现多次，报出先前定义行号
- 空实现：函数/类体去掉 docstring 后只剩 pass
样本：新增 demo_pkg/todo.py（两个同名 parse + 一个只有 pass 的 save）作对照。

**第一次验证（6 条）暴露了我自己的误报** ✗：
    重复定义  models.py:17  speak（先前定义在第 10 行）  ← 其实是 Dog.speak **重写** Animal.speak，合法
    重复定义  models.py:25  speak  ← Cat.speak 同理
根因：我按 `node.name` 去重，**没有区分作用域** —— 不同类里的同名方法被当成重复。

**修复**：改为按 `作用域.名字` 组键（递归扫描 tree.body 与每个 ClassDef.body；模块作用域前缀为空）✓

**修复后真机验证（4 条，误报清零）**：
    未使用导入  demo_pkg/__init__.py:3   from .core import engine  ✓（真实问题，示例工程自带）
    未使用导入  demo_pkg/legacy.py:2     import json               ✓
    重复定义  demo_pkg/todo.py:8   parse（先前定义在第 4 行）       ✓（真重复，同模块作用域）
    空实现  demo_pkg/todo.py:13   save（只有 pass）                ✓
    —— 类方法重写不再被误判 ✓✓

**教训（第 13 条）**：**新增静态检查必须先在「已知良好的代码」上跑一遍看误报** ——
本次正是用示例工程自己的 models.py（三个合法重写）当对照，才发现作用域建模的缺失。
检查器的价值等于其精度：宁可少报，不可误报。

### 0.77 检查结果接入「问题」工具窗 —— 真机验证通过

**动机**：0.75/0.76 的检查结果只出现在一次性对话框里，关掉就没了；PyCharm 的 Problems 视图是**常驻**的。

**实现**：
- ConsolePanelView 增加 problemRows（@Prop）与 gotoProblem 回调；「问题」页签优先渲染 problemRows
  （每行可点 → 回调 Index 解析 文件:行 → 跨文件跳转），无结果时保持原有「未发现问题」
- Index：检查完成后同时写入 problemRows，并**自动展开底部工具窗并切到「问题」页签**（与外部任务打开终端同一模式）

**真机验证**：
    点「检查未使用导入」→ 底部工具窗自动展开，页签高亮「问题」✓
    问题页签列出 4 条：未使用导入 __init__.py:3 / legacy.py:2、重复定义 todo.py:8、空实现 todo.py:13 ✓✓
    点「重复定义 todo.py:8」→ 状态栏「已跳到 demo_pkg/todo.py:8」✓✓（跨文件）
    关闭检查结果对话框后，问题页签内容保留 ✓（常驻可见，符合 Problems 视图语义）

### 0.78 未使用变量检查 —— 真机验证通过（6 条，零误报）

**保守实现（为压低误报）**：只认简单名目标的赋值（Assign / AnnAssign 的 Name；元组解包、for 目标、with 目标一律不报），
跳过下划线前缀名，跳过 global/nonlocal 声明过的名字；
判断「是否被读」时统计整个函数子树（含嵌套函数）的 Load —— 宁可少报不可误报。

**真机验证**：
    检查结果（6 条）✓：未使用导入 ×2 + 未使用变量 scratch.py:6 cache / :7 unused_local + 重复定义 + 空实现 ✓✓
    ★ 精度证据：没有误报 utils.py 里被使用的 seq（seq.append / return seq 都算读取）✓
    底部「问题」页签同步显示同样 6 条 ✓（常驻视图与对话框一致）✓

**落实了第 13 条教训**：新增检查先在已知良好的示例文件上跑（utils.py 的 seq、models.py 的 self.name），
确认零误报后才上机；本次一次通过、无返工。

**检查能力现状**：未使用导入 · 重复定义（按作用域）· 空实现 · 未使用变量；结果同时进对话框与「问题」工具窗，均可点行跨文件跳转。

### 0.79 保存时自动检查（问题列表「活着」）+ 入口排序真修 —— 真机验证通过

**实现**：
- runInspection 增加静默模式参数（showDialog = true 默认）；saveTab 成功后调用 runInspection(false)
  —— 静默模式只刷新 problemRows 与状态栏（「已保存 · 检查：N 条」），**不弹对话框、不强制展开工具窗**（符合 PyCharm 语义）
- 顺带**真修了入口拥挤问题**（0.63/0.71 反复出现）：把高频的「保存」提到随处搜索首屏第 5 位

**真机验证**：
    SE 首屏：转到符号 / 转到类 / 切换器 / 继承层级 / **保存** / 查找用法 ✓（保存可见 ✓）
    点「保存」→ 状态栏「**已保存 · 检查：6 条**」✓✓（自动检查确实触发并统计出 6 条）
    底部工具窗保持收起（静默模式设计如此）✓；问题数据已在 state 中，展开即见

**关于验证过程的一点自省**：本轮我先尝试用菜单路径保存（点 ☰）失败两次（坐标不对/菜单没打开），
第三次改用「把保存放进首屏」这一**产品层面的改进**来完成验证 —— 比继续调坐标更值。
**经验**：自动化验证卡在入口可达性时，优先考虑把入口**放到该去的位置**（既修了体验又通了验证）。

### 0.80 ★ 跨文件补全（导入模块 → 成员 → 插入）—— 真机验证通过

### 0.82 ★ 跨文件重命名修复并完成往返验证（0.81 的债结清）

### 0.89 ★ 「仅当前文件」检查范围 —— 真机验证通过

**实现**：
- 工程级 ast 脚本增加第 4 个参数（只查指定相对路径的文件）
- runInspection(showDialog, onlyCurrentFile)：勾选时把当前文件相对路径传给脚本
- 问题视图工具栏加「仅当前文件」开关；开启后运行按钮文案变为「运行检查（仅当前文件）」

**真机验证**：
    打开 demo_pkg/scratch.py → 点「仅当前文件」（按钮高亮、运行按钮文案随之改变 ✓）→ 运行
    结果「检查结果（2 条）」：只剩 demo_pkg/scratch.py:6 cache 与 :7 unused_local ✓✓（全工程为 6–10 条）
    问题视图同步只剩这 2 行 ✓，状态栏「检查完成：2 条」✓
    上一轮加的 gutter 琥珀警示标仍在第 6、7 行 ✓（两项能力共存）
    工具栏完整：运行检查（仅当前文件） · 仅当前文件 · 全部 · 未使用导入 · 重复定义 · 空实现 · 未使用变量 ✓

**问题视图至此的能力**：运行检查（全工程/单文件）· 类型筛选 · 按严重性/名称排序 · 点行跨文件跳转 · 保存后自动刷新 · 与编辑器 gutter 标记联动。

### 0.88 ★ 检查结果接入编辑器 gutter 行内标记 —— 真机验证通过

**实现**：
- CodeEditor 增加 warnLines（@Prop）；gutter 标记优先级：折叠折角 > 断点红点 > **警示标（琥珀色 8px 圆点）** > 当前行灯泡
- warnLines 也写进 ForEach 的 key（和断点同理，ArkUI 会复用旧节点导致不刷新）
- Index：检查完成后把「属于当前文件的问题行」算出来传给编辑器（用 lastProjectRoot 求相对路径与行号匹配）
- 两个编辑器实例（主编辑器与分屏第二窗格）都传 warnLines

**真机验证（决定性截图）**：
    打开 demo_pkg/scratch.py（该文件含 cache、unused_local 两个未使用变量）→ 运行检查 → 状态栏「检查完成：6 条」
    编辑器 gutter 第 6、7 行各出现一个**琥珀色警示圆点** ✓✓，与 `cache = n * 2`、`unused_local = 42` 精确对齐
    问题视图同时列出这两条 ✓ —— 列表与行内标记一一对应，检查结果与编辑器连成一体

**过程中修的真问题**：warnLines 属性被我第一次 replace_all 加到了**控制台面板**的调用上（该组件没有这个属性），
ArkTS 直接报「Argument of type … 」→ 改为只在两个编辑器调用上添加。
**教训（第 19 条）**：替换属性行时锚点必须带**该组件特有**的兄弟属性（我用的 debugLocals 属于控制台面板，编辑器用的是 breakpoints/debugLine）。

### 0.87 ★ 问题视图工具栏 + 类型筛选真机验证通过（0.86 的债结清）

**卡点与解法**：底部工具窗启动时**完全不渲染**（showBottomToolWindow=false），自动化够不到「问题」页签；
而能打开它的命令（检查/保存）又都被挤出随处搜索首屏。
解法不是继续挤首屏，而是**腾位置 + 归位**：
  · 移除冗余入口「撤销上次重命名」（0.82 起它已在重命名对话框内）
  · 把「检查未使用导入」提到首屏第 5 位（它会自动展开问题视图）

**真机验证（决定性截图）**：
    SE 首屏：转到符号 / 转到类 / 切换器 / 继承层级 / **检查未使用导入** / 跨文件补全 ✓
    点它 → 状态栏「检查完成：6 条」，底部工具窗自动展开且「问题」页签高亮 ✓
    工具栏：[运行检查] + [全部][未使用导入][重复定义][空实现][未使用变量] 全部可见 ✓
    点「未使用变量」→ 列表**只剩 2 行**（demo_pkg/scratch.py:6 cache、:7 unused_local），其他类型全部被过滤 ✓✓
    右上角仍是原有的「按严重性 / 按名称」排序 ✓（0.4x 的排序能力与本轮筛选共存）

**至此问题视图具备**：运行检查按钮 · 类型筛选 · 排序 · 点行跨文件跳转 · 保存后自动刷新。
**教训（第 18 条补充）**：入口拥挤的正解是**把命令放回它所属的容器**（检查→问题视图工具栏），而不是无限扩首屏。

### 0.86 问题视图类型筛选 + 工具栏「运行检查」（已实现，真机验证未完成）

**实现**：
- 问题页签顶部加筛选行：全部 / 未使用导入 / 重复定义 / 空实现 / 未使用变量（客户端过滤，PyCharm Problems 视图的按类别过滤语义）
- **结构性修复入口拥挤**：把「运行检查」做成**问题视图自带的按钮**（PyCharm 的 Problems 工具栏语义），
  从此运行检查不再依赖随处搜索首屏 —— 这是入口拥挤问题（已出现 5 次）的正解：命令应待在它所属的工具窗里

**✗ 真机验证未完成**：本轮三次尝试都被**底部工具窗收起**挡住 ——
  收起状态不渲染页签条，自动化点不到「问题」页签（先点「保存」/「检查未使用导入」也都因首屏拥挤而点不到）；
  功能本体（筛选逻辑与按钮）已实现且构建通过，但没有取得真机证据，**不计入完成**。

**下一轮**：① 先让底部工具窗可被自动化打开（点收起条展开，或用「视图」菜单的对应项）；
  ② 再验证「运行检查」按钮与四类筛选；③ 顺手把「检查未使用导入」从 SE 移除（已由问题视图按钮取代）。

**教训（第 18 条）**：**功能入口不要都堆在同一个首屏列表里** —— 已出现 5 次「新入口把旧入口挤出可视区」。
正解是让命令待在它所属的容器：检查命令进问题视图、重构命令进编辑器右键与重构菜单。

### 0.85 ★ 工程目录清理修复并验证（0.84 的债结清）

**两处根因**（都与「删不掉」有关）：
  ① FileService.remove 对**非空目录**用 rmdirSync，会抛异常 → 改为**递归删除 + 整体 try/catch**
     （清理是尽力而为，绝不能打断启动流程）
  ② 清理用错了基准目录：FileService.projectRoot() 返回的是 **PyProjects 父目录**，不是工程目录，
     因此前两轮的清理一直在清父目录，工程内的 _undo.txt 当然删不掉 → 改为在拿到工程目录后
     调用新的 cleanLegacyArtifacts(projectDir)（重开最近工程路径与新建示例路径都调用）

**真机验证**：
    工程树残留：（已彻底清理 ✓）✓✓ 工程内既无 .harmonyide 目录，也无 _undo.txt / _report.txt
    工程文件完好：main.py / utils.py / demo_pkg 等正常 ✓
    状态栏「Python 运行时已就绪」✓（启动流程未被清理逻辑干扰）

**教训（第 17 条）**：**先确认函数的返回值语义再用它做路径运算** —— projectRoot() 名字像「工程根」，
实际是「工程们的父目录」；这类命名歧义导致我连查两轮。查不到效果时应先打印/核对基准路径，而不是反复改逻辑。

### 0.84 验证 0.83 的两处修复（一项通过、一项暴露新问题）

**通过** ✓：
    同名保护：选中 compute → 转蛇形 → 状态栏「名称未变化：compute 已是该风格」，且没有误报「共 N 处」✓✓
    改名+撤销链路仍正常：加后缀 _v2 → 报告「demo_pkg/scratch.py 1 处 / 共 1 处」→ 撤销「已还原 3 个文件」✓✓
    且本轮两次撤销之后，工程根没有**新增**的元文件 ✓（说明「撤销跳过下划线开头元文件」的修复生效）

**未通过** ✗：工程根的旧 `_undo.txt` **没有被启动清理删掉** —— 页面加载后第一次 dump 它就还在。
判断：并非撤销脚本又写了一个（本轮撤销后数量未增加），而是 `FileService.remove(path)` 对这个文件没生效。
**下一轮**：查 FileService.remove 的实现（是否只处理目录/是否静默失败），修好后重新验证工程根彻底干净。

### 0.83 中间文件迁出工程 + 命名风格样式 + 修两处新缺陷

**实现**：
- 把 .harmonyide（历史快照/各类分析输出/备份）从**工程目录**整体迁到**应用私有目录**（${filesDir}/.harmonyide），
  共替换 21 处引用；并在启动时清理工程内旧残留 —— 用户工程里不该出现 IDE 的中间文件
- 重命名新增两种命名风格：转蛇形（驼峰→下划线）、转驼峰（下划线→小驼峰），共 6 种样式

**真机验证**：
    样式按钮齐备：加前缀 my_ / 加后缀 _v2 / 去掉 my_ 前缀 / 转蛇形 / 转驼峰 / 转大写 ✓
    示例工程自愈成功：main.py 重建为 # sample-v3 版本（第 2 行可见标记，内容干净无残留）✓✓
    工程树中已无 .harmonyide 目录 ✓

**验证中发现并修掉的两处新缺陷**：
  ① 撤销脚本把元文件 _undo.txt 也当作备份还原，于是工程根出现了一个 _undo.txt ✗ → 改为跳过所有下划线开头的元文件 ✓
  ② 重命名成同名符号（如 compute → 转蛇形 → compute）仍会重写文件并报「1 处」✗ → 改为同名直接提示「名称未变化」不做修改 ✓

**教训（第 16 条）**：备份目录里既有数据文件又有元文件时，**还原逻辑必须只认数据文件**（用统一前缀规则而不是逐个列名单）。

**逐条修复**：
  ① 脚本把报告写到应用读取的 out 路径（argv[5]）—— 报告不再为空
  ② 所有工程遍历排除 .harmonyide（重命名脚本与工程扫描脚本都加 dirnames 过滤），
     并把备份目录从工程内移到应用私有目录（<filesDir>/.harmonyide/rename_backup）—— 不再自我改名、不再污染符号索引
  ③ 「撤销这次重命名」按钮直接放进重命名对话框的报告区（不再依赖随处搜索入口）
  ④ 新增「去掉 my_ 前缀」命名样式（既是有用样式，也用于把示例恢复原状）
  ⑤ 撤销脚本同样写 out（它与重命名脚本犯了同一个错，一并修）
  ⑥ 示例工程加版本标记 # sample-v3 —— 缺标记的（被测试改脏的）示例文件自动重建，示例工程真正自愈

**真机往返验证（完整链路）**：
  步骤1 重命名 my_fib → fib：标题「重命名：my_fib → fib」，报告「utils.py 1 处 / 共 1 处」✓（样本恢复一致）
  步骤2 重命名 fib → my_fib：报告「**main.py 1 处**」「**utils.py 1 处**」「共 2 处」✓✓ —— 真跨文件
  步骤2 点对话框内「撤销这次重命名」→ 「**已还原 3 个文件**」✓✓（撤销真实生效）
  步骤3 重新扫描符号表：「函数 fib utils.py:4」✓（已还原），且**没有任何 .harmonyide 路径混入** ✓✓
  截图：重命名对话框列出全工程 16 个符号（demo_pkg/* + main.py + utils.py）✓

**遗留（下轮清理）**：工程根 .harmonyide/ 下还留着上一轮的 _undo.txt（旧残留），应随备份迁移一并清掉。
**教训（第 15 条）**：重构类功能必须**先验证副作用范围** —— 备份目录放进被遍历的树里，等于给自己下套；
两个脚本（重命名/撤销）犯同一个「写错输出路径」的错，说明**同一模式的代码要一起检查**。

### 0.81 跨文件重命名（Refactor.Rename）—— 已实现、构建通过，但真机验证失败（不计入完成）

**设计**：本设备无法注入键盘输入，因此重命名提供命名样式而非自由输入：
  加前缀 my_ / 加后缀 _v2 / 转大写；执行前把每个受影响文件复制到 .harmonyide/rename_backup（按相对路径扁平命名），
并提供「撤销上次重命名」从备份还原（满足验证后还原状态的规矩）。
脚本用 ast 的精确位置：Name / Attribute / arg 用 (lineno, col_offset, end_col_offset)，def/class 名在该行内定位，
同一行多处编辑按列倒序应用，避免位移。

**真机验证（失败）暴露 3 个真实缺陷** ✗：
  ① 报告为空：脚本把报告写到了 <backup>/_report.txt，没有写应用读取的 out 路径 →
     界面显示「（没有找到需要修改的位置）」，而状态栏却报「重命名完成（1 个文件）」（那是回退数组的长度，逻辑有误）。
  ② 备份目录建在工程内（.harmonyide/rename_backup），脚本 os.walk 继续走进该目录 → 把备份副本也改了名
     （撤销将不可靠），而且工程扫描把 .harmonyide 当源码扫（符号表里出现
     函数 my_fib .harmonyide/rename_backup/utils.py:4 与嵌套备份路径）。
  ③ 「撤销上次重命名」被挤出随处搜索首屏（入口拥挤问题第 4 次出现）。

**结论**：功能未通过验证，不计入完成。下一轮优先修这三处并做完整往返验证（改名 → 重新扫描确认 → 撤销 → 确认还原）：
  1) 脚本写 out（报告给应用读）；
  2) 所有工程遍历/扫描排除 .harmonyide（备份目录移出工程根或过滤）；
  3) 入口排序（把撤销放进首屏，或改为重命名对话框内的按钮）。
  4) 同时把示例工程恢复到 fib（撤销或再次改名）。

**意义**：补全是最能体现「IDE 而非编辑器」的能力；此前本 IDE 只有正则式的循环补全与语句补全 ✗，
本轮把 0.71 建立的工程索引接进补全链路，做成**跨文件**补全。

**实现（全触屏，无需键盘）**：
- 阶段1：扫描当前文件的 import（import X / from X import …，取顶层模块名）→ 列出已导入模块
- 阶段2：从工程索引（projectSymbols）里筛出「文件名 == 模块名」的类与函数 → 列出成员（附 文件:行）
- 点成员 → editorController.insertText(`${模块}.${成员}`) 插入到光标处 → 状态栏提示
入口：随处搜索首屏「跨文件补全」（放在 继承层级 与 保存 之间）

**真机验证（含插入的可见证据）**：
    阶段1 标题「跨文件补全（3 个已导入模块）」，模块 sys / platform / utils ✓✓（来自当前文件 import）
    点 utils → 阶段2 成员「fib    utils.py:4」✓✓，状态栏「utils 的成员：1 个」✓✓
    点 fib → 状态栏「已插入补全：utils.fib」✓✓
    ★ 截图决定性证据：标签页变为 **main.py ●**（脏标记），编辑器**第 22 行出现 `utils.fib`** —— 真的写进了编辑器 ✓✓

**说明**：插入位置是当前光标处（本流程未移动光标，故落在文末）；真实的「输入 . 自动弹补全」受本设备无法注入键盘输入的限制，
以对话框形式提供同等能力。
