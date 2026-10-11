# 鸿蒙 Python IDE — PyCharm 对齐审计

> 全部依据 PyCharm 实现文件（`_cache/pycharm/impl/all_menus2.txt` = 解析 `<add-to-group>` 后的完整菜单；
> `ManyIslandsDark.theme.json` / `IslandSchemeDark.xml` = 主题与配色）。

## 1. 菜单对齐度（权威项 vs 已实现）

| 菜单 | 权威项 | 已实现 | 覆盖率 | 主要缺失 |
| --- | --- | --- | --- | --- |
| FileMenu | 41 | 42 | 68% | CreateWebProject、RenameProject、OpenFullIdeFromEmbeddedFrontend、ToolboxWelcomeRemdevAction、WelcomeOpenToolbox、WelcomeOpenGateway、ShowSettings、ConvertToWindowsLineSeparators… |
| EditMenu | 50 | 53 | 84% | DownloadBackendFileToClient、复制 JSON 指针、HTTPClientConvertToCurlAndCopy、JsonPathEvaluateAction、在更改中搜索、EmojiPicker.Open、FileEditor.OpenDataEditor、FileEditor.OpenDataViewer |
| ViewMenu | 44 | 31 | 55% | Presentation Assistant、导航栏中的成员、快速定义(_K)、快速类型定义、快速文档(_D)、外部文档(_X)、形参信息(_P)、类型信息(_E)… |
| GoToMenu | 42 | 18 | 33% | 转到类…、文本…、GotoDatabaseObject、GotoRow、GotoUrlAction、下一个 Emmet 编辑点、上一个 Emmet 编辑点、将文本光标移至匹配的大括号… |
| CodeMenu | 51 | 27 | 43% | 循环扩展词(_E)、循环扩展词(向后)(_E)、启用命令补全(_C)、HfOpenModelSelectionWindow、递归展开(_R)、递归收起(_A)、_1、_2… |
| RefactoringMenu | 37 | 15 | 35% | 重构…、ReactClassToFunctionComponentAction、ReactFunctionToClassComponentAction、DatabaseView.Ddl.AlterObject、sql.ExtractFunctionAction、sql.IntroduceAliasAction、PyIntroduceAttribute、引入形参对象(_J)…… |
| RunMenu | 25 | 22 | 48% | XDebugger.AttachToProcess、从文件导入测试、强制步过(_V)、StepIntoMyCode、强制步入(_N)、智能步入(_P)、强制运行到光标(_S)、重置帧(_F)… |
| ToolsMenu | 260 | 9 | 1% | PsiViewer、PsiViewerForContext、CWMThinClientShowPopupAction、CWMHostShowPopupAction、com.intellij.clouds.docker.gateway.actions.NewDevcontainerAction、Dev.Container.ManageBackends、Dev.Container.ShowRecent、Docker.AddDockerRegistry… |
| Vcs.MainMenu | 16 | 15 | 44% | Github.Sync.Fork、Github.Create.Pull.Request、Github.View.Pull.Request、GitLab.Merge.Request.Create、UML.ShowChanges、Git.Log、Github.Share、GitLab.Share… |
| WindowMenu | 77 | 23 | 31% | 最小化、缩放、移至内置显示屏、默认、作为编辑器标签页打开、固定有效工具窗口标签页(_I)、跳转到上一个工具窗口(_J)、MaximizeToolWindow… |
| HelpMenu | 38 | 18 | 39% | OpenWelcome、ShowLearnPanel、我的工作效率(_P)、最新变化(_N)、YouTube 上的产品、ShowSQLLog、CodeWithMeBackendCollectZippedLogs、运行内存测试程序…… |
| **合计** | **681** | **273** | **30%** | |

## 2. 各菜单缺失项明细（前 25 项）

### FileMenu（缺 13）

```
CreateWebProject
RenameProject
OpenFullIdeFromEmbeddedFrontend
ToolboxWelcomeRemdevAction
WelcomeOpenToolbox
WelcomeOpenGateway
ShowSettings
ConvertToWindowsLineSeparators
ConvertToUnixLineSeparators
ConvertToMacLineSeparators
SettingsSyncOpenSettingsAction
TemplateProjectProperties
RunConfigurationTemplatesForNewProjects
```

### EditMenu（缺 8）

```
DownloadBackendFileToClient
复制 JSON 指针
HTTPClientConvertToCurlAndCopy
JsonPathEvaluateAction
在更改中搜索
EmojiPicker.Open
FileEditor.OpenDataEditor
FileEditor.OpenDataViewer
```

### ViewMenu（缺 20）

```
Presentation Assistant
导航栏中的成员
快速定义(_K)
快速类型定义
快速文档(_D)
外部文档(_X)
形参信息(_P)
类型信息(_E)
上下文信息(_C)
错误描述(_R)
切换仅更改的文件
迭代最近的文件
最近的文件(_N)
最近更改的文件
RecentChanges
显示路径导航
显示 import 弹出窗口
基于内容
左到右
右到左
```

### GoToMenu（缺 28）

```
转到类…
文本…
GotoDatabaseObject
GotoRow
GotoUrlAction
下一个 Emmet 编辑点
上一个 Emmet 编辑点
将文本光标移至匹配的大括号
下一个实时模板形参
上一个实时模板形参
下一个更改(_H)
上一个更改(_A)
选择位置(_L)…
ShowNavBar
前往声明或用法
转到实现(_M)
转到类型声明
转到 Super 方法
转到测试
相关符号(_R)…
文件结构(_I)
文件路径(_P)
类型层次结构(_H)
方法层次结构(_M)
调用层次结构(_Y)
```

### CodeMenu（缺 29）

```
循环扩展词(_E)
循环扩展词(向后)(_E)
启用命令补全(_C)
HfOpenModelSelectionWindow
递归展开(_R)
递归收起(_A)
_1
_2
_3
_4
_5
_1
_2
_3
_4
_5
展开文档注释(_D)
收起文档注释(_O)
切换折叠
折叠选区/移除区域(_S)
折叠代码块(_B)
JsonJacksonReformatAction
重新设置文件格式…
向左移动元素
向右移动元素
```

### RefactoringMenu（缺 24）

```
重构…
ReactClassToFunctionComponentAction
ReactFunctionToClassComponentAction
DatabaseView.Ddl.AlterObject
sql.ExtractFunctionAction
sql.IntroduceAliasAction
PyIntroduceAttribute
引入形参对象(_J)…
PyExtractFunction
包含文件(_I)…
提取接口(_I)…
提取模块(_M)…
Angular2ExtractComponentAction
TypeScriptExtractTypeAlias
ReactExtractComponentAction
sql.ExtractNamedQueryAction
VueExtractComponentAction
向上拉取成员(_L)…
向下推送成员(_S)…
反转布尔值(_B)…
ConvertJupyterToPythonAction
ConvertPythonToJupyterAction
PyConvertModuleToPackage
PyConvertPackageToModuleAction
```

### RunMenu（缺 13）

```
XDebugger.AttachToProcess
从文件导入测试
强制步过(_V)
StepIntoMyCode
强制步入(_N)
智能步入(_P)
强制运行到光标(_S)
重置帧(_F)
还原断点
切换临时行断点
切换断点启用状态(_B)
SetNextStatement
AttachProfilerToLocalProcess
```

### ToolsMenu（缺 258）

```
PsiViewer
PsiViewerForContext
CWMThinClientShowPopupAction
CWMHostShowPopupAction
com.intellij.clouds.docker.gateway.actions.NewDevcontainerAction
Dev.Container.ManageBackends
Dev.Container.ShowRecent
Docker.AddDockerRegistry
Docker.AddDockerConnection
Docker.ImportContexts
Markdown.ImportFromDocx
Markdown.Export
Markdown.ConfigurePandoc
ToggleSmartMode.SplitMode
ToggleSmartMode.TcpLink
PyProfiler.OpenPStat
ConvertSchemaAction
HTTPClient.NewRequestInToolMenuAction
HTTPClient.OpenCollection
RESTClient.ShowHistory
HttpClient.Add.Public.Variable
HttpClient.Add.Private.Variable
HttpClient.Add.AuthConfig
ConvertSwaggerToHttpFileAction
com.intellij.httpClient.actions.ConvertCurlToHttpRequestAction
```

### Vcs.MainMenu（缺 9）

```
Github.Sync.Fork
Github.Create.Pull.Request
Github.View.Pull.Request
GitLab.Merge.Request.Create
UML.ShowChanges
Git.Log
Github.Share
GitLab.Share
Git.Init
```

### WindowMenu（缺 53）

```
最小化
缩放
移至内置显示屏
默认
作为编辑器标签页打开
固定有效工具窗口标签页(_I)
跳转到上一个工具窗口(_J)
MaximizeToolWindow
Dock
拆分并右移
拆分并下移
转到下一个拆分器(_G)
转到上一个拆分器
标签页分组
显示标签页列表
保持标签页打开
显示隐藏的标签页
关闭标签页(_C)
关闭未修改标签页(_U)
关闭所有未固定
关闭左侧标签页
关闭右侧标签页
关闭所有只读标签页
重新打开关闭的标签页
拆分并右移
```

### HelpMenu（缺 23）

```
OpenWelcome
ShowLearnPanel
我的工作效率(_P)
最新变化(_N)
YouTube 上的产品
ShowSQLLog
CodeWithMeBackendCollectZippedLogs
运行内存测试程序…
调试日志设置(_E)…
特殊文件和文件夹…
收集故障排除信息
performancePlugin.OpenIndexingDiagnosticsAction
重新启动 Microsoft Defender 通知
Python.EnableDebugpyLogs
LogTraceScenarios
ShowPatchEngineDiagnosticDialog
NodeServicesProfilerAction
CaptureMemorySnapShot
更改内存设置
编辑自定义虚拟机选项…
删除残留的 IDE 目录…
注册(_R)…
注册(_R)…
```

## 3. 未实现功能的清单（取自代码里如实的提示分支）

代码中所有「说明型」面板（点开是解释而不是执行）共 27 个：

```
  文件剪贴板
  重构
  文件类型
  版本控制
  生成
  附加项目
  插件
  文件编码
  与文件类型关联
  切换只读特性
  显示空格
  显示装订区域图标
  视图 · 外观
  管理目标
  对表达式求值
  帮助
  诊断工具
  文件 · 工程操作
  编辑
  宏
  服务
  数据库
  图表
  AI 聊天
  AtomCode
  Junie
  单词本
```

明确的「未实现」提示：

```
  书签：本版本未实现（断点与灯泡标记已支持）
```

## 4. 主题/几何：已落地 vs 未落地

已落地（有实现文件依据）：

```
  ✓ 颜色：layer-0-bg #191A1C / layer-1-bg #26282C / 边框 #26282C·#33353B
  ✓ 文字：#D1D3D9 / #9FA2A8 / #4C4F56；强调 #3871E1；树选中 #2A4371；编辑器选区 #233558
  ✓ 标签：选中底 #233558、下划线 #2E4D89、下划线高 4、左右内边距 8（tabInsets -6,8,-6,8）
  ✓ 小岛：圆角 8、间隙 4（Island.arc.compact 16 / borderWidth.compact 4）
  ✓ 工具栏：按钮圆角 8、图标 16+5×2 内边距、标题栏项目着色 #2C3830
  ✓ 竖条：项高 42、图标 20、文字偏移 2（leftStripeIconWithName.padding 4,6,4,2）
  ✓ 状态栏：main-window-bg #26282C、topBorderWidth 0
  ✓ 语法：关键字 #CF8E6D / 字符串 #6AAB73 / 数字 #2AACB8 / 注释 #7A7E85 / 函数 #57AAF7 / 正文 #BCBEC4
  ✓ 控制台：底 #191A1C / 正常 #BCBEC4 / 错误 #F75464 / 用户输入 #6AAB73
  ✓ 工具窗布局：左 Project/Commit/Structure、右 7 项、底部 6 标签
```

尚未落地（主题里读到但界面还没用上）：

```
  ✗ Island.inactiveAlpha = 0.56（非活动工具窗淡出）
  ✗ Island.toolWindowAlpha = 0.2（工具窗描边透明度）
  ✗ Island.borderArcLength 14 / compact 10（小岛描边弧长）
  ✗ MainWindow.Tab 颜色（#131314 / 选中 ToolWindowBackground）
  ✗ EditorTabs.underlineArc = 4（下划线圆角）
  ✗ tabContentMinWidth = 24、tabContentActionsRightInsets 仅用于底部工具窗
  ✗ ToolWindow.HeaderToolbarPanel / ContentTitle.gap 已记录但未逐项套用
  ✗ popup 边框 #33353B 与 dialog 边框 #26282C 未区分到每个弹层
```

## 5. 图标来源

- `rawfile/icons` 共 **67** 个图标，全部解包自 PyCharm（expui / fileTypes / nodes / toolwindow）。
- `IdeIcons.ets` 中手绘矢量（Path/Shape）计数：**0**（0 = 全部改为读文件）。

## 6. 已知的运行能力缺口（非 UI）

```
  ✗ CPython 静态库未含 _ssl / _ctypes / _sqlite3 / _bz2 / _lzma 等扩展模块
  ✗ 无 fork/subprocess（鸿蒙沙箱限制），因此 pip 安装、多进程不可用
  ✗ 编辑器非虚拟化渲染（大文件性能受限）
  ✗ 无插件系统（按要求先做内置功能）
  ✗ 沙箱内无 Git 可执行文件，版本控制面板为说明性实现
  ✗ 符号级重构 / 结构化搜索 / 宏 / 书签：未实现（菜单项给出说明）
```

## 7. 缺口分类（结论）

| 类别 | 数量 | 说明 |
| --- | --- | --- |
| A. Python 相关、可做 | 184 | 需要新写的编辑器/导航能力（如括号跳转、最近文件、路径导航开关） |
| B. 需语义引擎/额外能力 | 67 | 类型推断、引用解析、实时模板、调试增强 —— 短期不做 |
| C. 不适用或为内部/插件动作 | 227 | Java/Kotlin/DB/Docker/远端，以及无中文译名的内部 action（在主菜单里通常也不显示） |

### A 类明细（可做）

```
[EditMenu] 复制 JSON 指针
[ViewMenu] 导航栏中的成员
[ViewMenu] 切换仅更改的文件
[ViewMenu] 迭代最近的文件
[ViewMenu] 最近的文件(_N)
[ViewMenu] 最近更改的文件
[ViewMenu] 显示路径导航
[ViewMenu] 显示 import 弹出窗口
[ViewMenu] 基于内容
[ViewMenu] 左到右
[ViewMenu] 右到左
[GoToMenu] 转到类…
[GoToMenu] 文本…
[GoToMenu] 将文本光标移至匹配的大括号
[GoToMenu] 下一个更改(_H)
[GoToMenu] 上一个更改(_A)
[GoToMenu] 选择位置(_L)…
[GoToMenu] 转到 Super 方法
[GoToMenu] 文件结构(_I)
[GoToMenu] 文件路径(_P)
[CodeMenu] 递归展开(_R)
[CodeMenu] 递归收起(_A)
[CodeMenu] 切换折叠
[CodeMenu] 折叠选区/移除区域(_S)
[CodeMenu] 折叠代码块(_B)
[CodeMenu] 重新设置文件格式…
[CodeMenu] 向左移动元素
[CodeMenu] 向右移动元素
[CodeMenu] 下移行(_W)
[CodeMenu] 上移行(_U)
[RefactoringMenu] 包含文件(_I)…
[RefactoringMenu] 反转布尔值(_B)…
[ToolsMenu] 重新加载项目
[ToolsMenu] 显示已注册的远程 API
[ToolsMenu] 显示主菜单
[ToolsMenu] 静默模式
[ToolsMenu] 进入不完全依赖关系模式
[ToolsMenu] 触发项目可索引文件筛选器运行状况检查
[ToolsMenu] Tremble Dumb 模式
[ToolsMenu] 开始 I/O 泛滥
[ToolsMenu] 跳过窗口停用事件
[ToolsMenu] 重置“知道了”工具提示
[ToolsMenu] 列出持久状态组件
[ToolsMenu] 滞后模式
[ToolsMenu] 输入延迟报告
[ToolsMenu] 重新输入当前文件
[ToolsMenu] 添加嵌入…
[ToolsMenu] 添加行尾内嵌提示…
[ToolsMenu] 添加块嵌入…
[ToolsMenu] 转储编辑器状态
[ToolsMenu] 设置文本光标视觉特性…
[ToolsMenu] 编辑器渲染基准
[ToolsMenu] 添加自定义包装
[ToolsMenu] 移除文本光标处的自定义换行
[ToolsMenu] 显示倒计时对话框
[ToolsMenu] 显示标准面板
[ToolsMenu] UI 沙盒
[ToolsMenu] UI 检查器(&I)
[ToolsMenu] 复制 UI 标签
[ToolsMenu] 启用 UI 主题颜色选择器
[ToolsMenu] 灰色筛选器(&G)
[ToolsMenu] 文本灰色筛选器(&T)
[ToolsMenu] 显示初始屏幕
[ToolsMenu] 显示 Unix 信息
[ToolsMenu] 展开树
[ToolsMenu] LaF 默认设置
[ToolsMenu] Metal 呈现流水线
[ToolsMenu] 原生 Wayland 支持
[ToolsMenu] 标尺参考线
[ToolsMenu] 运行长时间后台写入操作
[ToolsMenu] 运行频繁的后台写入操作
[ToolsMenu] 运行频繁的后台读取操作
[ToolsMenu] 显示捆绑包消息
[ToolsMenu] 显示动态压缩工具栏
[ToolsMenu] 测量 OSR JCEF FPS
[ToolsMenu] 查找图像重复项
[ToolsMenu] 显示非 Retina 图像
[ToolsMenu] 显示“更新”对话框
[ToolsMenu] 注册表…
[ToolsMenu] 实验性功能…
… 还有 104 项
```

### B 类明细（需引擎）

```
[EditMenu] 在更改中搜索
[ViewMenu] 快速定义(_K)
[ViewMenu] 快速类型定义
[ViewMenu] 快速文档(_D)
[ViewMenu] 外部文档(_X)
[ViewMenu] 形参信息(_P)
[ViewMenu] 类型信息(_E)
[ViewMenu] 上下文信息(_C)
[ViewMenu] 错误描述(_R)
[GoToMenu] 下一个实时模板形参
[GoToMenu] 上一个实时模板形参
[GoToMenu] 前往声明或用法
[GoToMenu] 转到实现(_M)
[GoToMenu] 转到类型声明
[GoToMenu] 转到测试
[GoToMenu] 相关符号(_R)…
[GoToMenu] 类型层次结构(_H)
[GoToMenu] 方法层次结构(_M)
[GoToMenu] 调用层次结构(_Y)
[CodeMenu] 循环扩展词(_E)
[CodeMenu] 循环扩展词(向后)(_E)
[CodeMenu] 启用命令补全(_C)
[CodeMenu] 展开文档注释(_D)
[CodeMenu] 收起文档注释(_O)
[RefactoringMenu] 重构…
[RefactoringMenu] 引入形参对象(_J)…
[RefactoringMenu] 提取接口(_I)…
[RefactoringMenu] 提取模块(_M)…
[RefactoringMenu] 向上拉取成员(_L)…
[RefactoringMenu] 向下推送成员(_S)…
[RunMenu] 从文件导入测试
[RunMenu] 强制步过(_V)
[RunMenu] 强制步入(_N)
[RunMenu] 智能步入(_P)
[RunMenu] 强制运行到光标(_S)
[RunMenu] 重置帧(_F)
[RunMenu] 还原断点
[RunMenu] 切换临时行断点
[RunMenu] 切换断点启用状态(_B)
[ToolsMenu] 显示 EDT 使用情况图表
[ToolsMenu] 打开缓存值分析器
[ToolsMenu] 添加测试通知
[ToolsMenu] 显示测试对话框
[ToolsMenu] 验证对话框测试
[ToolsMenu] 测试 Mac 消息
[ToolsMenu] 测试色盲
[ToolsMenu] UI 中的调试信息
[ToolsMenu] 正在测试写入操作
[ToolsMenu] 测试进度窗口
[ToolsMenu] 测试协程进度
```

### C 类（不适用）示例

```
[FileMenu] CreateWebProject
[FileMenu] RenameProject
[FileMenu] OpenFullIdeFromEmbeddedFrontend
[FileMenu] ToolboxWelcomeRemdevAction
[FileMenu] WelcomeOpenToolbox
[FileMenu] WelcomeOpenGateway
[FileMenu] ShowSettings
[FileMenu] ConvertToWindowsLineSeparators
[FileMenu] ConvertToUnixLineSeparators
[FileMenu] ConvertToMacLineSeparators
[FileMenu] SettingsSyncOpenSettingsAction
[FileMenu] TemplateProjectProperties
[FileMenu] RunConfigurationTemplatesForNewProjects
[EditMenu] DownloadBackendFileToClient
[EditMenu] HTTPClientConvertToCurlAndCopy
[EditMenu] JsonPathEvaluateAction
[EditMenu] EmojiPicker.Open
[EditMenu] FileEditor.OpenDataEditor
[EditMenu] FileEditor.OpenDataViewer
[ViewMenu] Presentation Assistant
[ViewMenu] RecentChanges
[GoToMenu] GotoDatabaseObject
[GoToMenu] GotoRow
[GoToMenu] GotoUrlAction
[GoToMenu] 下一个 Emmet 编辑点
```
