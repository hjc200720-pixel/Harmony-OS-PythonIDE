# PyCharm 界面清单（读自实现文件）

> 来源：各 jar 内的 `toolWindow` 注册、动作/组 XML、语言包（`configurable.*`、`action.*`）。
> 用途：确认 PyCharm 有哪些界面、它们在哪一侧/哪个位置、里面有哪些按钮，再逐个区域实现。

## 1. 工具窗（Tool Windows）

| 工具窗 id | 中文名 | 锚点 | 次要 | 图标 |
| --- | --- | --- | --- | --- |
| `AIAssistant` |  | right | false | 有 |
| `Backup and Sync History` |  | left | false | 有 |
| `Bookmarks` |  | left | true | 有 |
| `Code Provenance` |  | right | true | 有 |
| `Commit` |  | left |  | 有 |
| `Commit_Guest` |  | left | false | 有 |
| `Coverage` |  | right | true | 有 |
| `Database` |  | right |  | 有 |
| `Database Changes` |  | bottom |  | 有 |
| `Endpoints` |  | right |  | 有 |
| `EventQueue Watcher` |  | bottom |  |  |
| `File Transfer` |  | bottom |  | 有 |
| `HfCacheToolWindow` |  | bottom |  | 有 |
| `Jupyter Variables` |  | right | true | 有 |
| `Learn` |  |  |  | 有 |
| `Merge Requests` |  | left |  | 有 |
| `Notifications` |  | right | true | 有 |
| `Plots` |  | right |  | 有 |
| `Problems View` |  | bottom |  | 有 |
| `Project` |  | left |  | 有 |
| `Pull Requests` |  | left |  | 有 |
| `Python Console` |  | right | false | 有 |
| `Python Packages` |  | right | false | 有 |
| `PythonProcessOutput` |  | bottom | false | 有 |
| `Remote Host` |  | right | false | 有 |
| `SciView` |  | right |  | 有 |
| `Statistics Event Log` |  | bottom |  |  |
| `Structure` |  | left | true | 有 |
| `TODO` |  | bottom |  | 有 |
| `Terminal` |  | bottom | false | 有 |
| `Time Tracking` |  | right | false | 有 |
| `TypeScript` |  | bottom |  | 有 |
| `UI Theme Color Picker` |  | right |  | 有 |
| `Version Control` |  | bottom |  | 有 |

## 2. 弹出菜单 / 上下文菜单（从动作 XML 解析）

| 组 id | 已解析项数 |
| --- | --- |
| `ActivityView.ChangesBrowser.Popup` | - |
| `ActivityView.Popup` | - |
| `AnalyzeActionsPopup` | - |
| `AnalyzePlatformMenu` | - |
| `Arrangement.Alias.Rule.Context.Menu` | - |
| `Arrangement.Rule.Match.Control.Context.Menu` | - |
| `BasicEditorPopupMenu` | - |
| `BlankDiffViewerEditorPopupMenu` | - |
| `Bookmarks.ToolWindow.PopupMenu` | - |
| `BuildMenu` | - |
| `CallHierarchyPopupMenu` | - |
| `ChangesViewPopupMenu` | - |
| `Code.Review.Diff.Editor.Popup` | - |
| `CodeMenu` | - |
| `Console.TableResult.CellEditor.Popup` | - |
| `Console.TableResult.ColumnHeaderPopup` | - |
| `Console.TableResult.Csv.PreviewColumnHeaderPopup` | - |
| `ConsoleEditorPopupMenu` | - |
| `ConsoleView.PopupMenu` | - |
| `CoverageMenu` | - |
| `CoveragePlatformMenu` | - |
| `DataWrangler.Operations.Popup` | - |
| `DataWrangler.Transformations.Popup` | - |
| `Database.EditorTabPopupMenu` | - |
| `DatabaseView.AddActionGroupPopup` | - |
| `DatabaseViewPopupMenu` | - |
| `DebugMainMenu` | - |
| `Diff.EditorGutterPopupMenu` | - |
| `Diff.EditorPopupMenu` | - |
| `Diff.ViewerPopupMenu` | - |
| `DirDiffMenu` | - |
| `DirDiffOperationsMenu` | - |
| `Django.ToolsMenu` | - |
| `DocCommentGutterIconContextMenu` | - |
| `Docker.RemoteServersViewPopup` | - |
| `Dvcs.FileHistory.ContextMenu` | - |
| `Dvcs.Log.ContextMenu` | - |
| `EditMenu` | - |
| `Editor.JSLibrariesMenu` | - |
| `EditorContextBarMenu` | - |
| `EditorGutterPopupMenu` | - |
| `EditorGutterVcsPopupMenu` | - |
| `EditorLangPopupMenu` | - |
| `EditorPopupMenu` | - |
| `EditorTabPopupMenu` | - |
| `EndpointsActions.ContextMenu` | - |
| `EndpointsActions.OptionsMenu` | - |
| `ExternalSystemView.BaseProjectMenu` | - |
| `ExternalSystemView.DependencyMenu` | - |
| `ExternalSystemView.ModuleMenu` | - |
| `ExternalSystemView.ProjectMenu` | - |
| `ExternalSystemView.RunConfigurationMenu` | - |
| `ExternalSystemView.TaskMenu` | - |
| `ExtractMethodToolWindow.TreePopup` | - |
| `FileMenu` | - |
| `FindInFiles.Results.ContextMenu` | - |
| `Git.ContextMenu` | - |
| `Git.FileHistory.ContextMenu` | - |
| `Git.Log.ContextMenu` | - |
| `Git.LogContextMenu` | - |
| `Git.MainMenu` | - |
| `Git.Menu` | - |
| `Git.Stage.Index.File.Menu` | - |
| `Git.Stage.Local.File.Menu` | - |
| `Git.Stage.Tree.Menu` | - |
| `Git.Stash.ChangesBrowser.ContextMenu` | - |
| `Git.Stash.Operations.ContextMenu` | - |
| `Git.WorkingTrees.ToolwindowGroup.Popup` | - |
| `GitHub.MainMenu` | - |
| `GitLab.Merge.Request.Changes.Popup` | - |
| `GitLab.Merge.Request.Details.Popup` | - |
| `GitLab.Merge.Request.Timeline.Error.Popup` | - |
| `GitLab.Merge.Request.Timeline.Popup` | - |
| `Github.PullRequest.Changes.Popup` | - |
| `Github.PullRequest.Details.Popup` | - |
| `Github.PullRequest.Timeline.Popup` | - |
| `Github.PullRequest.ToolWindow.List.Popup` | - |
| `GoToMenu` | - |
| `Graph.DefaultGraphPopup` | - |
| `Graph.NeighborhoodViewPopup` | - |
| `HelpMenu` | - |
| `HfCacheManagementContextMenu` | - |
| `Images.EditorPopupMenu` | - |
| `InlayMenu` | - |
| `InspectionToolWindow.TreePopup` | - |
| `JupyterStructureViewPopupMenu` | - |
| `JupyterToolbar.AddActionsPopup` | - |
| `LightEditModePopup` | - |
| `MainMenu` | - |
| `Markdown.TableColumnActions.ColumnAlignmentActions.Popup` | - |
| `MethodHierarchyPopupMenu` | - |
| `MicroservicesExamplesOptionsMenu` | - |
| `NavBarContextMenu` | - |
| `NavbarPopupMenu` | - |
| `OtherMenu` | - |
| `Patch.MainMenu` | - |
| `ProblemsView.Frontend.TreePopup` | - |
| `ProblemsView.ToolWindow.TreePopup` | - |
| `ProjectViewPopupMenu` | - |
| `PublishGroupPopupMenu` | - |
| `PyPackagingMenu` | - |
| `RefactoringMenu` | - |
| `RemoteHostViewPopupMenu` | - |
| `RemoteServersViewPopup` | - |
| `RunDashboardPopup` | - |
| `RunMenu` | - |
| `Runner.View.Popup` | - |
| `ScopeViewPopupMenu` | - |
| `ScriptGenerator.Options.Popup` | - |
| `ServiceViewItemPopup` | - |
| `ShelvedChangesPopupMenu` | - |
| `ShowFilterPopup` | - |
| `StructureViewPopupMenu` | - |
| `Terminal.HyperlinkContextMenu` | - |
| `Terminal.OutputContextMenu` | - |
| `Terminal.PromptContextMenu` | - |
| `Terminal.ReworkedTerminalContextMenu` | - |
| `TestTreePopupMenu` | - |
| `TextViewerEditorPopupMenu` | - |
| `ToolWindowContextMenu` | - |
| `ToolsMenu` | - |
| `TypeHierarchyPopupMenu` | - |
| `UML.DefaultGraphPopup` | - |
| `Uml.NodeCellEditorPopup` | - |
| `Unversioned.Files.Dialog.Popup` | - |
| `UsageView.Popup` | - |
| `Vcs.CheckinProjectMenu` | - |
| `Vcs.FileHistory.ContextMenu` | - |
| `Vcs.Log.ChangesBrowser.Popup` | - |
| `Vcs.Log.ContextMenu` | - |
| `Vcs.MainMenu` | - |
| `Vcs.Operations.Popup` | - |
| `Vcs.RepositoryChangesBrowserMenu` | - |
| `Vcs.SavedPatches.ChangesBrowser.ContextMenu` | - |
| `Vcs.SavedPatches.ContextMenu` | - |
| `Vcs.Shelf.ChangesBrowser.ContextMenu` | - |
| `Vcs.Shelf.Operations.ContextMenu` | - |
| `VcsFileGroupPopup` | - |
| `VcsHistoryInternalGroup.Popup` | - |
| `VcsSelectionHistoryDialog.Popup` | - |
| `ViewMenu` | - |
| `WindowMenu` | - |
| `XDebugger.Evaluate.Code.Fragment.Editor.Popup` | - |
| `XDebugger.Evaluation.Dialog.Tree.Popup` | - |
| `XDebugger.Frames.Tree.Popup` | - |
| `XDebugger.Hover.Breakpoint.Context.Menu` | - |
| `XDebugger.Inspect.Tree.Popup` | - |
| `XDebugger.Threads.View.Popup` | - |
| `XDebugger.Variables.Tree.Popup` | - |
| `XDebugger.Watches.Inline.Popup` | - |
| `XDebugger.Watches.Tree.Popup` | - |
| `popup@BookmarkContextMenu` | - |
| `popup@ExpandableBookmarkContextMenu` | - |

## 3. 主菜单/工具窗菜单（含项数）

| 菜单 | 项数 |
| --- | --- |
| `FileMenu` | 41 |
| `EditMenu` | 50 |
| `ViewMenu` | 44 |
| `GoToMenu` | 42 |
| `CodeMenu` | 51 |
| `RunMenu` | 25 |
| `ToolsMenu` | 260 |
| `WindowMenu` | 77 |
| `HelpMenu` | 38 |
| `RefactoringMenu` | 37 |
| `Vcs.MainMenu` | 16 |
| `Copy.Paste.Special` | 3 |
| `EditorPopupMenu2` | 7 |
| `EditorPopupMenu3` | 1 |
| `ToolWindowContextMenu` | 5 |
| `EditorPopupMenu` | 91 |

## 4. 可打开对话框的动作（节选）

| 动作 id | 名称 |
| --- | --- |
| `AIHub.NotInstalled.InlineCompletionSettings` | 设置… |
| `ActivateHierarchyToolWindow` | 层次结构 |
| `ActivityView.RevertDifferences` | 还原选区 |
| `AllRunConfigurationsToggle` | 切换所有运行/调试配置 |
| `CWMHostOpenSettingsAction` | 打开 Code With Me 设置 |
| `CWMOpenSettingsAction` | 设置… |
| `CallHierarchy` | 调用层次结构(_Y) |
| `CallHierarchy.BaseOnThisMethod` | 基于此方法 |
| `ChangeColorScheme` | 编辑器配色方案 |
| `ChangeInspectionProfile` | 错误高亮显示 |
| `ChangeKeymap` | 按键映射 |
| `ChangesView.SaveToShelve` | 保存到搁置 |
| `ChangesView.Shelve` | 搁置更改… |
| `ChangesView.ShelveSilently` | 无提示搁置 |
| `ChangesView.ShowCommitOptions` | 显示提交选项 |
| `ChangesView.ToggleCommitUi` | 切换提交 UI… |
| `ChangesView.UnshelveSilently` | 无提示取消搁置 |
| `Charts.ShowChartSettings` | 打开图表样式设置… |
| `Charts.ShowSeriesSettings` | 显示系列设置 |
| `CheckSuggestedPlugins` | 检查推荐的插件 |
| `ChooseDebugConfiguration` | 调试… |
| `ChooseRunConfiguration` | 运行… |
| `CloseDiffEditor` | 关闭差异编辑器 |
| `CodeInspection.OnEditor` | 使用编辑器设置检查代码(_E) |
| `CodeProvenance.Dev.ExportUncommittedAuthorshipAction` | 导出未提交的作者身份报告 |
| `CombinedWelcomeRemdevAction` | 远程开发 |
| `CommitView.CloseWindowedFloatingTwOnCommit` | 提交后关闭“窗口/浮动”模式下的“提交”工具窗口 |
| `CommitView.ShowOnDoubleClick.EditorPreview` | 双击时显示差异 |
| `CommitView.ShowOnDoubleClick.Source` | 双击时显示源 |
| `CommittedChanges.Clear` | 清除 |
| `CommittedChanges.Details` | 显示详细信息 |
| `CommittedChanges.Filter` | 筛选 |
| `CommittedChanges.Refresh` | 刷新 |
| `CommittedChanges.Revert` | 还原更改 |
| `CompareKeymaps` | 比较按键映射… |
| `ComputeDiffWithPreviousRevisionAction` | 与上一个规范修订比较 |
| `ComputeSwaggerDiffBetweenPhysicalFiles` | 比较 OpenAPI 规范 |
| `ConfigureInspectionsAction` | 配置检查… |
| `Console.TableResult.Copy.Csv.Settings` | 配置 CSV 格式… |
| `Console.TableResult.SubmitAndCommit` | 发送并提交 |
| `Console.Transaction.Commit` | 提交 |
| `CopySettingsPath` | 复制选项路径 |
| `DS.Open.Tables.Settings` | 设置… |
| `DataViews.Settings` | 打开数据视图设置… |
| `DataViews.Settings.Appearance` | 打开数据视图外观设置… |
| `DatabaseView.CreateDataSourceFromSettings` | 从剪贴板导入 |
| `DatabaseView.SetColor.Settings` | 数据库颜色设置… |
| `DatabaseView.ShowContentDiff` | 比较数据 |
| `DatabaseView.ShowDiff` | 比较架构结构 |
| `DatabaseView.ShowDiff.Configured` | 应用 DDL 映射… |
| `Debugger.EvaluateInConsole` | 在控制台中求值 |
| `Debugger.RemoveAllBreakpoints` | 移除所有断点 |
| `Debugger.RemoveAllBreakpointsInFile` | 移除当前文件中的所有断点 |
| `Debugger.Tree.EvaluateInConsole` | 在控制台中求值 |
| `DeleteRunConfiguration` | 删除 |
| `Dev.Container.ideSettings.AddSettingsAction` | 从 IDE 添加修改后的设置 |
| `Diagram.OpenSettings` | 打开图表设置 |
| `Diff.AppendLeftSide` | 追加左侧 |
| `Diff.AppendRightSide` | 追加右侧 |
| `Diff.ApplyLeftSide` | 接受左侧 |
| `Diff.ApplyNonConflicts` | 应用所有不冲突的更改 |
| `Diff.ApplyNonConflicts.Left` | 从左侧应用不冲突的更改 |
| `Diff.ApplyNonConflicts.Right` | 从右侧应用不冲突的更改 |
| `Diff.ApplyRightSide` | 接受右侧 |
| `Diff.ComparePartial.Base.Left` | 左和中 |
| `Diff.ComparePartial.Base.Right` | 中和右 |
| `Diff.ComparePartial.Left.Right` | 左和右 |
| `Diff.CompareWithBase.Left` | 基础和左 |
| `Diff.CompareWithBase.Result` | 基础和中 |
| `Diff.CompareWithBase.Right` | 基础和右 |
| `Diff.FocusOppositePane` | 选择相对差异窗格 |
| `Diff.FocusOppositePaneAndScroll` | 在相对差异窗格中选择位置 |
| `Diff.IgnoreLeftSide` | 忽略左侧 |
| `Diff.IgnoreRightSide` | 忽略右侧 |
| `Diff.MagicResolveConflicts` | 解决简单的冲突 |
| `Diff.NextChange` | 比较下一个文件 |
| `Diff.NextConflict` | 下一个冲突 |
| `Diff.OpenDiffInEditor` | 作为编辑器标签页打开选定的差异请求 |
| `Diff.PrevChange` | 比较上一个文件 |
| `Diff.PreviousConflict` | 上一个冲突 |

## 5. 覆盖状态（本 IDE 已显示 / 已实现）

入口：**视图(V) → 工具窗口**（应用内弹窗列出全部 34 个；●=已实现真实内容，○=已显示但内容待做）

| 工具窗 | 锚点 | 状态 |
| --- | --- | --- |
| Project | left | ✅ 工程树（真实） |
| Structure | left | ✅ 结构面板（AST 解析） |
| Commit | left | ✅ 版本控制说明页 |
| Bookmarks | left | ○ 占位（书签未实现） |
| Merge Requests | left | ○ 不适用（需 Git 托管） |
| Pull Requests | left | ○ 不适用 |
| Backup and Sync History | left | ○ 不适用 |
| Commit_Guest | left | ○ 不适用 |
| Learn | left | ✅ 学习页 |
| Notifications | right | ✅ 通知中心（真实） |
| AIAssistant | right | ○ 占位（插件） |
| Database | right | ○ 占位（无数据库驱动） |
| Gradle | right | ○ 不适用（JVM 构建） |
| Maven | right | ○ 不适用 |
| Plots | right | ✅ 绘图说明页 |
| Python Packages | right | ✅ 包管理（真实） |
| Python Console | right | ✅ REPL 控制台（真实） |
| Coverage | right | ○ 占位（覆盖率未实现） |
| Endpoints | right | ○ 占位（Web 端点） |
| SciView | right | ○ 占位（科学计算） |
| Jupyter Variables | right | ○ 占位 |
| HfCacheToolWindow | right | ○ 占位（插件） |
| Remote Host | right | ○ 不适用 |
| Code Provenance | right | ○ 不适用 |
| Time Tracking | right | ○ 不适用 |
| UI Theme Color Picker | right | ○ 不适用 |
| Run | bottom | ✅ 运行工具窗（真实输出） |
| Version Control | bottom | ✅ 说明页 |
| Problems View | bottom | ✅ 问题视图（真实） |
| Terminal | bottom | ✅ 内置终端（真实） |
| Services | bottom | ✅ 服务说明页 |
| TODO | bottom | ✅ TODO 扫描（真实，新增） |
| PythonProcessOutput | bottom | ✅ 复用运行输出（真实，新增） |
| Database Changes | bottom | ○ 不适用 |
| File Transfer | bottom | ○ 不适用 |
| Statistics Event Log | bottom | ○ 不适用 |

## 6. 弹出菜单（153 组，已实现的主要项）

| 组 id | 状态 |
| --- | --- |
| `MainMenu / FileMenu / EditMenu / ViewMenu / GoToMenu / CodeMenu / RefactoringMenu / RunMenu / ToolsMenu / Vcs.MainMenu / WindowMenu / HelpMenu` | ✅ 全部按动作 XML + add-to-group 还原 |
| `EditorTabPopupMenu (+Ex)` | ✅ 14 项（关闭左/右侧等真实实现） |
| `ProjectViewPopupMenu` | ✅ 长按/右键 12 项（新建/重命名/删除/重载/运行真实实现） |
| `EditorPopupMenu / EditorPopupMenu1/2/3` | ○ 待做（编辑器内右键） |
| `ToolWindowContextMenu` | ○ 待做（工具窗标题右键：隐藏/移至/最大化） |
| `StructureViewPopupMenu / NavbarPopupMenu` | ○ 待做 |
| `EditorGutterPopupMenu / InlayMenu` | ○ 待做 |
| `ConsoleView.PopupMenu / FindInFiles.Results.ContextMenu` | ○ 待做 |
| `CallHierarchy/MethodHierarchy/TypeHierarchy PopupMenu` | ○ 需语义引擎 |

## 7. 区域实现顺序（建议）

1. **已显示待补内容**：书签、覆盖率、端点、数据视图、Jupyter 变量（按 PyCharm 的树/工具条结构做占位界面）
2. **编辑器内右键菜单**（EditorPopupMenu）与**工具窗标题右键**（ToolWindowContextMenu）
3. **底部工具窗的标题栏按钮**（Run 的 ⟲/⏹/🗑、Problems 的过滤等）——按各工具窗的 action group 逐个对齐
4. **对话框**：查找/替换、在文件中查找、运行配置、项目结构、插件、键位映射（快捷键表已实现）
5. **状态栏组件**（行尾/编码/缩进/解释器等已实现；其余按 StatusBarWidget 注册补）
6. 语义类功能（符号表 → 快速定义/查找用法/重命名）
