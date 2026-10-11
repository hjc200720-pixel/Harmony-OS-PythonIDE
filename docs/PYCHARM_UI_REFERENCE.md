# PyCharm 新 UI 实现参照（读文件，不靠截图）

> 本文档由 `_cache/pycharm/` 下的脚本从 **PyCharm 2026.2.2 的安装文件**中直接提取，
> 是"界面/功能对齐"的唯一权威依据。截图仅作辅助验证。

## 1. 来源文件

| 文件（jar 内路径） | 内容 |
| --- | --- |
| `lib/intellij.platform.ide.impl.jar!idea/PlatformActions.xml` | 核心菜单与动作（MainMenu=7 个菜单） |
| `lib/intellij.platform.ide.impl.jar!idea/LangActions.xml` | 代码菜单 CodeMenu、编辑器动作 |
| `lib/intellij.platform.execution.impl.jar!META-INF/PlatformExecutionActions.xml` | 运行相关动作组 |
| `lib/intellij.platform.vcs.impl.jar!META-INF/VcsActions.xml` | VCS 菜单组（`Vcs.MainMenu` 等） |
| `lib/intellij.platform.ide.impl.jar!themes/islands/ManyIslandsDark.theme.json` | **本项目使用的主题**（色板 + 圆角 + 尺寸） |
| `lib/intellij.platform.ide.impl.jar!themes/islands/IslandSchemeDark.xml` | 编辑器配色方案 |
| `plugins/localization-zh/lib/localization-zh.jar!messages/ActionsBundle.properties` | 中文动作文案（5801 条，含助记符） |
| `%CONFIG%/options/window.layouts.xml` | 工具窗布局（左右竖条 + 底部的项与顺序） |
| `%CONFIG%/options/ui.lnf.xml` | UI 开关（单行工具栏、竖条宽度、是否显示工具窗名称） |

提取脚本：`_cache/pycharm/extract_all_impl.py`（抽取）、`dump_all_menus.py`（导出菜单）、
`parse_actions.py`（单菜单解析）、`patch_*.py`（按数据回填 ArkTS 代码）。

## 2. 主题色板（ManyIslandsDark）

### 命名色（节选）

| 名称 | 值 | 名称 | 值 |
| --- | --- | --- | --- |
| gray-160 | `#F7F8F9` | blue-160 | `#F7F8FF` |
| gray-150 | `#E9EAEE` | blue-150 | `#E3EBFE` |
| gray-140 | `#DDDFE4` | blue-140 | `#D0DFFE` |
| gray-130 | `#D1D3D9` | blue-130 | `#BDD3FF` |
| gray-120 | `#C3C5CB` | blue-120 | `#A7C5FF` |
| gray-110 | `#B5B7BD` | blue-110 | `#92B7FF` |
| gray-100 | `#9FA2A8` | blue-100 | `#71A1FE` |
| gray-90 | `#8B8E94` | blue-90 | `#538AF9` |
| gray-80 | `#73767C` | blue-80 | `#3871E1` |
| gray-70 | `#5F6269` | blue-70 | `#2F5EB9` |
| gray-60 | `#4C4F56` | blue-60 | `#2E4D89` |
| gray-50 | `#40434A` | blue-50 | `#2A4371` |
| gray-40 | `#33353B` | blue-40 | `#233558` |
| gray-30 | `#26282C` | blue-30 | `#1B283F` |
| gray-20 | `#212326` | blue-20 | `#182337` |
| gray-10 | `#191A1C` | blue-10 | `#131A28` |

### 语义映射（界面元素 → 实际色值）

| 界面元素 | 主题键 | 解析结果 |
| --- | --- | --- |
| 工具窗 / 编辑器 / 对话框 背景 | `toolWindowBackground / editor-bg / dialog-bg` | layer-0-bg = gray-10 = **#191A1C** |
| 主窗口 / 状态栏 / 工具栏 / 弹出层 背景 | `mainWindow / StatusBar.background / MainToolbar.background / popup-bg` | layer-1-bg = gray-30 = **#26282C** |
| 编辑器/对话框边框 | `editor-border / dialog-border` | layer-0-border = gray-30 = #26282C |
| 弹出层边框 | `popup-border` | layer-1-border = gray-40 = #33353B |
| 正文文字 | `text-default` | gray-130 = #D1D3D9 |
| 次要文字 | `text-muted` | gray-100 = #9FA2A8 |
| 禁用文字 | `text-disabled` | gray-60 = #4C4F56 |
| 强调/选中蓝 | `accent-brand-bg` | blue-80 = **#3871E1** |
| 树选中行 | `-` | blue-50 = #2A4371 |
| 编辑器选区 | `-` | blue-40 = #233558 |
| 选中标签底 / 下划线 | `EditorTabs.underlinedTabBackground / underlinedBorderColor` | blue-40 #233558 / blue-60 #2E4D89 |
| 状态栏顶边框 | `StatusBar.topBorderWidth` | **0**（无分隔线） |
| 工具栏边框 | `MainToolbar.borderColor` | transparent |

### 尺寸 / 圆角（主题实测值）

| 键 | 值 | 含义 |
| --- | --- | --- |
| `arc` | 20 | 圆角半径（Island，完整模式） |
| `arc.compact` | 16 | 圆角半径（紧凑模式） |
| `borderWidth` | 6 | 小岛之间的边框/间隙（完整） |
| `borderWidth.compact` | 4 | 小岛之间的边框/间隙（紧凑） |
| `underlineArc` | 4 | 标签下划线圆角 |
| `underlineHeight` | 4 | 标签下划线高度 |

## 3. 工具窗布局（window.layouts.xml）

| 位置 | 项（按 order） |
| --- | --- |
| 左侧 | Project / Commit / Structure（+ Learn） |
| 右侧 | Notifications / AIAssistant / Database / Gradle / Maven / Plots / Python Packages |
| 底部 | Version Control / Problems / Problems View / Terminal / Services / Python Console |

`ui.lnf.xml`：`SHOW_MAIN_MENU_MODE = MERGED_WITH_MAIN_TOOLBAR`（单行工具栏）、`SHOW_TOOL_WINDOW_NAMES = true`（图标下带文字）。

## 4. 菜单结构（实现文件原文 + 中文文案）

### CodeMenu

```
生成…  <Generate>
  ---
  [CodeCompletionGroup]
    基本(_B)  <CodeCompletion>
    类型匹配  <SmartTypeCompletion>
    ---
    ---
    循环扩展词(_E)  <HippieCompletion>
    循环扩展词(向后)(_E)  <HippieBackwardCompletion>
    ---
    启用命令补全(_C)  <EnableCommandCompletion>
  [InspectCodeInCodeMenuGroup]
    ---
    [InspectCodeGroup]
      检查代码(_I)…  <InspectCode>
      代码清理(_C)…  <CodeCleanup>
    [AnalyzeActionsPopup]
      [AnalyzeActions]
        静默代码清理  <SilentCodeCleanup>
        RunInspection  <RunInspection>
        配置当前文件分析…  <PopupHector>
        查看离线检查结果(_O)…  <ViewOfflineInspection>
        ---
        分析流入此处的数据(_T)…  <SliceBackward>
        分析流出此处的数据(_F)…  <SliceForward>
    [AnalyzePlatformMenu]
      分析堆栈跟踪或线程转储(_S)…  <Unscramble>
  ---
  插入实时模板(_T)…  <InsertLiveTemplate>
  保存为实时模板(_I)…  <SaveAsTemplate>
  ---
  环绕方式(_S)…  <SurroundWith>
  解包/移除(_W)…  <Unwrap>
  ---
  [FoldingGroup]
    展开(_X)  <ExpandRegion>
    递归展开(_R)  <ExpandRegionRecursively>
    全部展开(_E)  <ExpandAllRegions>
    ---
    收起(_C)  <CollapseRegion>
    递归收起(_A)  <CollapseRegionRecursively>
    全部收起(_A)  <CollapseAllRegions>
    ---
    [ExpandToLevel]
      _1  <ExpandToLevel1>
      _2  <ExpandToLevel2>
      _3  <ExpandToLevel3>
      _4  <ExpandToLevel4>
      _5  <ExpandToLevel5>
    [ExpandAllToLevel]
      _1  <ExpandAllToLevel1>
      _2  <ExpandAllToLevel2>
      _3  <ExpandAllToLevel3>
      _4  <ExpandAllToLevel4>
      _5  <ExpandAllToLevel5>
    ---
    [LanguageSpecificFoldingGroup]
      展开文档注释(_D)  <ExpandDocComments>
      收起文档注释(_O)  <CollapseDocComments>
    ---
```

### EditMenu

```
撤消  <$Undo>
  重做  <$Redo>
  ---
  [CutCopyPasteGroup]
    剪切(_T)  <$Cut>
    复制(_C)  <$Copy>
    复制路径(_O)  <CopyPaths>
    [PasteGroup]
      粘贴(_P)  <$Paste>
      从历史记录粘贴(_E)…  <PasteMultiple>
  [EditCreateDeleteGroup]
    删除(_D)  <$Delete>
  ---
  仅在选区内搜索  <ToggleFindInSelection>
  [FindMenuGroup]
    查找(_F)…  <Find>
    替换(_R)…  <Replace>
    查找下一个/移至下一个匹配项(_N)  <FindNext>
    查找上一个/移至上一个匹配项(_V)  <FindPrevious>
    选择所有匹配项  <SelectAllOccurrences>
    取消选择匹配项  <UnselectPreviousOccurrence>
    输入时滚动至结果  <ToggleScrollToResultsDuringTypingAction>
    ---
    查找文本光标处的字  <FindWordAtCaret>
    文本光标处单词的上一个匹配项  <FindPrevWordAtCaret>
    ---
    在文件中查找…  <FindInPath>
    在文件中替换(_A)…  <ReplaceInPath>
  [Editor.Search.Filter.Results]
  ---
  [EditSelectGroup]
    全选(_A)  <$SelectAll>
    在所选行的末尾添加文本光标  <EditorAddCaretPerSelectedLine>
  ---
  [EditSmartGroup]
    ---
    [ConvertIndentsGroup]
      转换为空格  <ConvertIndentsToSpaces>
      转换为制表符  <ConvertIndentsToTabs>
  ---
  [Macros]
    [StandardMacroActions]
      回放上一个宏(_Y)  <PlaybackLastMacro>
      启动/停止宏录制(_R)  <StartStopMacroRecording>
      编辑宏(_E)  <EditMacros>
      播放保存的宏…  <PlaySavedMacrosAction>
    ---
    [MacrosGroup]
  ---
  表情和符号  <EmojiAndSymbols>
```

### FileMenu

```
[FileOpenGroup]
    打开(_O)…  <OpenFile>
    附加项目…  <AttachProject>
    [$LRU]
      [RecentProjectListGroup]
      ---
      管理项目…  <ManageRecentProjects>
    关闭项目(_J)  <CloseProject>
    关闭所有项目  <CloseAllProjects>
    关闭其他项目  <CloseOtherProjects>
  ---
  [FileMenu.RemoteDevelopmentActions]
  ---
  [FileMainSettingsGroup]
    ShowSettings  <ShowSettings>
    插件…  <ShowPlugins>
  [FilePropertiesGroup]
    文件编码  <ChangeFileEncodingAction>
    与文件类型关联…  <AssociateWithFileType>
    切换只读特性  <ToggleReadOnlyAttribute>
    [ChangeLineSeparators]
      ConvertToWindowsLineSeparators  <ConvertToWindowsLineSeparators>
      ConvertToUnixLineSeparators  <ConvertToUnixLineSeparators>
      ConvertToMacLineSeparators  <ConvertToMacLineSeparators>
  ---
  全部保存(_S)  <SaveAll>
  从磁盘全部重新加载  <Synchronize>
  [CacheRecovery]
  使缓存失效…  <InvalidateCaches>
  ---
  [ExportImportGroup]
    导入设置…  <ImportSettings>
    导出设置(_E)…  <ExportSettings>
    ---
    恢复默认设置…  <RestoreDefaultSettings>
  [FileOtherSettingsGroup]
    TemplateProjectProperties  <TemplateProjectProperties>
    [FileSettingsGroup]
  ---
  [PrintExportGroup]
    ---
    [FileExportGroup]
      将文件或选区导出到 HTML(_H)…  <ExportToHTML>
    打印(_P)…  <Print>
  [PowerSaveGroup]
    ---
    省电模式  <TogglePowerSave>
    基本高亮显示  <ToggleEssentialHighlighting>
  ---
  退出(_X)  <Exit>
```

### GoToMenu

```
后退(_B)  <Back>
  前进(_W)  <Forward>
  ---
  ---
  [GoToTargetEx]
    转到文件…  <GotoFile>
  转到行\:列…  <GotoLine>
  ---
  [GoToErrorGroup]
    下一个高亮显示错误(_N)  <GotoNextError>
    上一个高亮显示错误(_P)  <GotoPreviousError>
  上一个编辑位置(_O)  <JumpToLastChange>
  下一个编辑位置  <JumpToNextChange>
  ---
  [NavigateInFileGroup]
    下一个方法(_E)  <MethodDown>
    上一个方法(_I)  <MethodUp>
    ---
    [TemplateParametersNavigation]
      下一个实时模板形参  <NextTemplateParameter>
      上一个实时模板形参  <PrevTemplateParameter>
    自定义折叠…  <GotoCustomRegion>
  上一个匹配项(_O)  <PreviousOccurence>
  下一个匹配项(_X)  <NextOccurence>
  ---
```

### HelpMenu

```
查找操作(_F)…  <GotoAction>
  ---
  帮助(_H)  <HelpTopics>
  ---
  [LearnGroup]
  ---
  入门指南(_G)  <OnlineDocAction>
  YouTube 上的产品  <Help.JetBrainsTV>
  键盘快捷键 PDF(_K)  <Help.KeymapReference>
  ---
  联系支持(_S)…  <TechnicalSupport>
  提交 bug 报告…  <ReportProblem>
  提交反馈(_F)…  <SendFeedback>
  ---
  在编辑器中打开日志  <OpenLog>
  在文件管理器中显示日志(_L)  <ShowLog>
  收集日志和诊断数据  <CollectZippedLogs>
  ---
  [HelpDiagnosticTools]
    活动监视器…  <Performance.ActivityMonitor>
    转储线程  <Performance.DumpThreads>
    运行内存测试程序…  <Performance.MemTester>
    ---
    调试日志设置(_E)…  <LogDebugConfigure>
    特殊文件和文件夹…  <BrowseSpecialPaths>
    收集故障排除信息  <CollectTroubleshootingInformation>
    重新启动 Microsoft Defender 通知  <ResetWindowsDefenderNotification>
  更改内存设置  <performancePlugin.ShowMemoryDialogAction>
  编辑自定义属性…  <EditCustomProperties>
  编辑自定义虚拟机选项…  <EditCustomVmOptions>
  删除残留的 IDE 目录…  <DeleteOldAppDirs>
  ---
  检查更新(_C)…  <CheckForUpdate>
  关于(_A)  <About>
  ---
```

### RefactoringMenu

```
重构…  <Refactorings.QuickListPopupAction>
  重命名(_R)…  <RenameElement>
  更改签名(_G)…  <ChangeSignature>
  ---
  [IntroduceActionsGroup]
    引入变量(_V)…  <IntroduceVariable>
    引入常量(_C)…  <IntroduceConstant>
    引入字段(_F)…  <IntroduceField>
    引入形参(_P)…  <IntroduceParameter>
    ---
    引入形参对象(_J)…  <IntroduceParameterObject>
    ---
    提取方法(_M)…  <ExtractMethod>
    ---
    提取委托(_D)…  <ExtractClass>
    包含文件(_I)…  <ExtractInclude>
    提取接口(_I)…  <ExtractInterface>
    提取超类(_U)…  <ExtractSuperclass>
    提取模块(_M)…  <ExtractModule>
  内联(_N)…  <Inline>
  ---
  移动(_M)…  <Move>
  复制(_O)…  <CopyElement>
  安全删除(_D)…  <SafeDelete>
  ---
  向上拉取成员(_L)…  <MembersPullUp>
  向下推送成员(_S)…  <MemberPushDown>
  反转布尔值(_B)…  <InvertBoolean>
```

### ToolsMenu

```
创建命令行启动器…  <CreateLauncherScript>
  创建桌面条目…  <CreateDesktopEntry>
  ---
  [OtherMenu]
  [ToolsMenu.Services]
```

### ViewMenu

```
[ToolWindowsGroup]
  [ViewAppearanceGroup]
    [ToggleFullScreenGroup]
      ---
      切换演示模式  <TogglePresentationMode>
      切换免打扰模式  <ToggleDistractionFreeMode>
      切换全屏模式  <ToggleFullScreen>
      切换 Zen 模式  <ToggleZenMode>
      ---
      紧凑模式  <ToggleCompactMode>
    缩放 IDE  <SwitchIdeScaleAction>
    [UIToggleActions]
      ---
      Presentation Assistant  <TogglePresentationAssistantAction>
      ---
      主菜单  <ViewMainMenu>
      [ChangeMainMenuModeActionGroup]
      工具栏  <ViewNewToolbarAction>
      工具栏经典  <ViewObsoleteToolbarAction>
      导航栏  <ViewObsoleteNavBarAction>
      [ViewToolbarActionsGroup]
        工具栏(_T)  <ViewToolBar>
      工具窗口  <ViewToolButtons>
      状态栏(_S)  <ViewStatusBar>
      [ViewStatusBarWidgetsGroup]
        状态文本  <StatusTextModeAction>
  跳转到源(_J)  <EditSource>
  在右侧拆分部分打开  <OpenInRightSplit>
  显示源(_W)  <ViewSource>
  ---
  [ViewRecentActions]
    最近的位置  <RecentLocations>
  ---
  [CompareActions]
    [PairFileActions]
  ---
  快速切换方案(_Q)…  <QuickChangeScheme>
  [EditorToggleActions]
    自动换行  <EditorToggleUseSoftWraps>
    ---
    显示空格(_O)  <EditorToggleShowWhitespaces>
    显示行号(_I)  <EditorToggleShowLineNumbers>
    显示装订区域图标 (_O)  <EditorToggleShowGutterIcons>
    显示缩进参考线(_O)  <EditorToggleShowIndentLines>
    ---
  ---
  在所有编辑器中重置字体大小  <EditorResetFontSizeGlobal>
  仅高亮显示当前声明  <ToggleFocusMode>
  ---
  [EditorBidiTextDirection]
    基于内容  <EditorSetContentBasedBidiTextDirection>
    左到右  <EditorSetLtrBidiTextDirection>
    右到左  <EditorSetRtlBidiTextDirection>
  ---
```

### WindowMenu

```
最小化  <MinimizeCurrentWindow>
  缩放  <ZoomCurrentWindow>
  移至内置显示屏  <MoveWindowBuiltinDisplayAction>
  [LayoutsGroup]
    默认  <RestoreFactoryDefaultLayout>
    ---
    [CustomLayoutsGroup]
    ---
    恢复当前布局(_R)  <RestoreDefaultLayout>
    保存当前布局中的更改(_S)  <StoreDefaultLayout>
    将当前布局另存为新布局(_N)…  <StoreNewLayout>
  ---
  [ActiveToolwindowGroup]
    隐藏有效工具窗口(_D)  <HideActiveWindow>
    隐藏本侧工具窗口  <HideSideWindows>
    隐藏底部工具窗口  <HideBottomWindows>
    隐藏所有工具窗口(_T)  <HideAllWindows>
    作为编辑器标签页打开  <MoveToolWindowTabToEditorAction>
    固定有效工具窗口标签页(_I)  <PinToolwindowTab>
    跳转到上一个工具窗口(_J)  <JumpToLastWindow>
    MaximizeToolWindow  <MaximizeToolWindow>
    Dock  <DockToolWindow>
    ---
    关闭活动标签页(_O)  <CloseActiveTab>
    关闭其他标签页(_O)  <TW.CloseOtherTabs>
    关闭所有标签页(_A)  <TW.CloseAllTabs>
    ---
    向右拆分  <TW.SplitRight>
    拆分并右移  <TW.SplitAndMoveRight>
    向下拆分  <TW.SplitDown>
    拆分并下移  <TW.SplitAndMoveDown>
    取消拆分(_S)  <TW.Unsplit>
    转到下一个拆分器(_G)  <TW.MoveToNextSplitter>
    转到上一个拆分器  <TW.MoveToPreviousSplitter>
    ---
    [TW.ViewModeGroup]
    [TW.MoveToGroup]
    标签页分组  <ToggleContentUiTypeMode>
    显示标签页列表  <ShowContent>
    [ResizeToolWindowGroup]
      延伸至左侧  <ResizeToolWindowLeft>
      延伸至右侧  <ResizeToolWindowRight>
      延伸至顶部  <ResizeToolWindowUp>
      延伸至底部  <ResizeToolWindowDown>
  [EditorTabsGroup]
    固定活动标签页(_I)  <PinActiveEditorTab>
    保持标签页打开  <KeepTabOpen>
    显示隐藏的标签页  <TabList>
    ---
    [CloseEditorsGroup]
      关闭标签页(_C)  <CloseContent>
      关闭其他标签页(_O)  <CloseAllEditorsButActive>
      关闭所有标签页(_A)  <CloseAllEditors>
      关闭所有未固定  <CloseAllUnpinnedEditors>
      关闭左侧标签页  <CloseAllToTheLeft>
      关闭右侧标签页  <CloseAllToTheRight>
      关闭所有只读标签页  <CloseAllReadonly>
    ---
    重新打开关闭的标签页  <ReopenClosedTab>
    向右拆分  <SplitVertically>
```

## 5. 使用方式

1. 改 UI 颜色/圆角：查第 2 节，直接落 `entry/src/main/ets/common/Theme.ets` 与各组件。
2. 改菜单项/文案/快捷键：查第 4 节，落 `entry/src/main/ets/view/MenuBarView.ets` 与 `pages/Index.ets`。
3. 改工具窗/竖条：查第 3 节，落 `Index.ets` 的左右竖条与 `ConsolePanelView.ets` 标签。
4. 需要新数据时重跑：`python _cache/pycharm/extract_all_impl.py`（约 1–2 分钟）。
5. 截图仅用于"确认最终观感"，不作为取值来源。
