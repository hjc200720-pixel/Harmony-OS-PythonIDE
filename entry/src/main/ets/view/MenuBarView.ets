/**
 * MenuBarView —— PyCharm New UI 风格顶部菜单栏
 *
 * 结构：左侧应用标识 + 中间六个菜单按钮 + 自绘下拉弹层（绝对定位在菜单栏下方）。
 *
 * 这里刻意不使用 bindMenu / bindContextMenu：
 *  - 自绘弹层可以直接控制「紧凑行高 / 快捷键灰字右对齐 / 1px 分隔线」，
 *    与 PyCharm 观感一致，也不受系统菜单圆角与内边距影响；
 *  - bindMenu 的 CustomBuilder 在 API 26 上仍要求 @Builder 传参规则，自绘更省心。
 * 如果后续要换成系统菜单，签名出处：
 *  - bindMenu(content, options?)          : component/common.d.ts:21466
 *  - bindMenu(isShow, content, options?)  : component/common.d.ts:21480
 *  - MenuOptions / ContextMenuOptions     : component/common.d.ts:15637 / :14963
 *
 * API 出处（HarmonyOS 26.0.0 / API 26 SDK）：
 *  - Text(content?: string | Resource, value?: TextOptions) : component/text.d.ts:75
 *  - Text.fontSize / fontColor / fontFamily / maxLines / textOverflow
 *      : component/text.d.ts:146 / :132 / :528 / :545 / :511
 *  - TextOverflowOptions 接口                                 : component/text.d.ts:35
 *  - Row / Column 容器                                        : component/row.d.ts / column.d.ts
 *  - Divider.vertical / color / strokeWidth                   : component/divider.d.ts:69 / :84 / :103
 *  - Stack + Stack.alignContent(Alignment)                    : component/stack.d.ts:140 / :107
 *  - CommonMethod.position(Position | Edges | LocalizedEdges)  : component/common.d.ts:20390
 *  - CommonMethod.onHover((isHover, event) => void)            : component/common.d.ts:18556
 *  - CommonMethod.onClick((event: ClickEvent) => void)         : component/common.d.ts:18506
 *  - CommonMethod.shadow(ShadowOptions | ShadowStyle)          : component/common.d.ts:21070
 *  - ShadowOptions 接口                                       : component/common.d.ts:7484
 *  - CommonMethod.borderWidth / borderColor / borderStyle / borderRadius
 *      : component/common.d.ts:18218 / :18232 / :18203 / :18250
 *  - CommonMethod.backgroundColor(ResourceColor)               : component/common.d.ts:17653
 *  - CommonMethod.constraintSize(ConstraintSizeOptions)        : component/common.d.ts:17399
 *  - EdgeWidths / Padding / Margin / Position 都是 declare type（不是 class）
 *      : component/units.d.ts:699 / :414 / :651 / :2159
 *  - BorderStyle.Solid                                        : component/enums.d.ts:443
 *  - ForEach(arr, itemGenerator, keyGenerator?)                : component/for_each.d.ts:85
 *
 * ArkTS 严格模式：所有 union 型属性参数（padding/margin/borderWidth/position/shadow）
 * 都先声明成显式类型的常量再传入，避免 arkts-no-untyped-obj-literals。
 */

import { PyTheme, PyFont } from '../common/Theme';
import { IconPython, IconChevronDown } from './IdeIcons';

/** 菜单栏整体高度（PyCharm New UI 菜单栏约 30vp） */
// 头部（菜单+工具栏合并为一行）：与 ToolBarView 的 TOOLBAR_HEIGHT 保持一致，
// 否则右竖条顶部会露出缝隙
const MENU_BAR_HEIGHT: number = 38;
/** 单个菜单按钮的水平内边距 */
const MENU_BTN_PADDING_H: number = 10;
/** 下拉弹层最小宽度 */
/** 下拉弹层宽度（PyCharm 的下拉框约 250~300vp） */
const MENU_POPUP_WIDTH: number = 280;
const MENU_POPUP_MIN_WIDTH: number = 220;
/** 下拉弹层最大高度 */
/** 下拉弹层最大高度：要能装下最长的菜单（文件/视图约 24 项 ≈ 620vp），否则底部项被裁掉看不到 */
const MENU_POPUP_MAX_HEIGHT: number = 620;
/** 下拉弹层单项行高 */
const MENU_ITEM_HEIGHT: number = 26;

// ── 显式类型的布局常量（union 参数必须这样传，否则触发 arkts-no-untyped-obj-literals） ──
const ELLIPSIS: TextOverflowOptions = { overflow: TextOverflow.Ellipsis };
const MENU_BAR_EDGE: EdgeWidths = { top: 0, right: 0, bottom: 1, left: 0 };
const IDENTITY_PAD: Padding = { left: 10, right: 12 };
const MENU_BTN_PAD: Padding = { left: MENU_BTN_PADDING_H, right: MENU_BTN_PADDING_H };
const MENU_ITEM_PAD: Padding = { left: 12, right: 12 };
/** 子菜单项的缩进内边距（PyCharm 的子项比父项更靠右） */
const MENU_ITEM_INDENT_PAD: Padding = { left: 28, right: 12 };
const MENU_POPUP_PAD: Padding = { top: 4, bottom: 4 };
const MENU_DIVIDER_MARGIN: Margin = { top: 4, bottom: 4 };
const APP_TITLE_MARGIN: Margin = { left: 6 };
const MENU_POPUP_MIN: ConstraintSizeOptions = { minWidth: MENU_POPUP_MIN_WIDTH };
const MENU_POPUP_MAX: ConstraintSizeOptions = { maxHeight: MENU_POPUP_MAX_HEIGHT };
const MENU_CATCHER_POS: Position = { x: 0, y: MENU_BAR_HEIGHT };

/** 一个下拉菜单项：id 回调父组件，label 中文名，shortcut 右侧灰色快捷键提示 */
class PyMenuItem {
  id: string = '';
  label: string = '';
  shortcut: string = '';
  /** 分组标题（如 PyCharm 的「新建 ▸」「最近打开的文件 ▸」）：不可点，灰色小字 */
  header: boolean = false;
  /** 子项：左侧缩进显示（对应 PyCharm 的子菜单项） */
  indent: boolean = false;

  constructor(id: string, label: string, shortcut: string,
              header: boolean = false, indent: boolean = false) {
    this.id = id;
    this.label = label;
    this.shortcut = shortcut;
    this.header = header;
    this.indent = indent;
  }
}

/** 一个顶级菜单：title 菜单栏文字，items 下拉项 */
class PyMenuGroup {
  title: string = '';
  items: PyMenuItem[] = [];

  constructor(title: string, items: PyMenuItem[]) {
    this.title = title;
    this.items = items;
  }
}

/** 空快捷键占位（分隔线项用） */
const NO_SHORTCUT: string = '';

function buildNavMenu(): PyMenuItem[] {
  // 依据 <group id="GoToMenu"> 原文
  return [
    new PyMenuItem('nav.back', '后退(_B)', 'Ctrl+Alt+Left'),
    new PyMenuItem('nav.forward', '前进(_W)', 'Ctrl+Alt+Right'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('nav.gotoFile', '转到文件…', 'Ctrl+Shift+N'),
    new PyMenuItem('nav.gotoLine', '转到行:列…', 'Ctrl+G'),
    new PyMenuItem('nav.gotoSymbol', '转到符号…', 'Ctrl+Alt+Shift+N'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('nav.nextError', '下一个高亮显示错误(_N)', 'F2'),
    new PyMenuItem('nav.prevError', '上一个高亮显示错误(_P)', 'Shift+F2'),
    new PyMenuItem('nav.prevEditLocation', '上一个编辑位置(_O)', 'Ctrl+Shift+Backspace'),
    new PyMenuItem('nav.nextEditLocation', '下一个编辑位置', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('nav.nextMethod', '下一个方法(_E)', 'Alt+Down'),
    new PyMenuItem('nav.prevMethod', '上一个方法(_I)', 'Alt+Up'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('nav.customFolding', '自定义折叠…', 'Ctrl+Alt+.'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('nav.prevMatch', '上一个匹配项(_O)', NO_SHORTCUT),
    new PyMenuItem('nav.matchedBrace', '将文本光标移至匹配的大括号', 'Ctrl+Shift+M'),
    new PyMenuItem('nav.nextMatch', '下一个匹配项(_X)', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('nav.nextTab', '下一个标签页', 'Ctrl+Tab'),
    new PyMenuItem('nav.prevTab', '上一个标签页', 'Ctrl+Shift+Tab'),
    new PyMenuItem('nav.refreshProject', '刷新工程树', 'Ctrl+Shift+R'),
    new PyMenuItem('nav.closeOthers', '关闭其他标签页', NO_SHORTCUT)
  ];
}

/**
 * 文件菜单 —— 按 PyCharm 的 File 菜单逐项对齐。
 * PyCharm 有「新建 ▸」「最近打开的文件 ▸」两个子菜单；这里用"分组标题 + 缩进子项"
 * 的扁平化写法呈现同样的项集（ArkUI 这版弹层不做飞出式二级菜单）。
 */
function buildFileMenu(): PyMenuItem[] {
  // 依据 <group id="FileMenu"> 完整还原（含 add-to-group 追加项）
  return [
    new PyMenuItem('', '新建', NO_SHORTCUT, true),
    new PyMenuItem('file.new', 'Python 文件', 'Ctrl+N', false, true),
    new PyMenuItem('file.newFolder', '目录', NO_SHORTCUT, false, true),
    new PyMenuItem('file.newProject', '新建(_N)…', NO_SHORTCUT, false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('file.open', '打开(_O)…', 'Ctrl+O'),
    new PyMenuItem('file.fromVcs', '来自版本控制的项目…', NO_SHORTCUT),
    new PyMenuItem('file.saveAs', '另存为…', 'Ctrl+Shift+S'),
    new PyMenuItem('file.attachProject', '附加项目…', NO_SHORTCUT),
    new PyMenuItem('', '最近的项目', NO_SHORTCUT, true),
    new PyMenuItem('file.recent0', '最近的工程 1', NO_SHORTCUT, false, true),
    new PyMenuItem('file.recent1', '最近的工程 2', NO_SHORTCUT, false, true),
    new PyMenuItem('file.manageProjects', '管理项目…', NO_SHORTCUT, false, true),
    new PyMenuItem('file.closeProject', '关闭项目(_J)', NO_SHORTCUT),
    new PyMenuItem('file.closeAllProjects', '关闭所有项目', NO_SHORTCUT),
    new PyMenuItem('file.closeOtherProjects', '关闭其他项目', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('tools.settings', '设置', 'Ctrl+Alt+S'),
    new PyMenuItem('file.plugins', '插件…', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('file.fileEncoding', '文件编码', NO_SHORTCUT),
    new PyMenuItem('file.removeBom', '移除 BOM', NO_SHORTCUT),
    new PyMenuItem('file.addBom', '添加 BOM', NO_SHORTCUT),
    new PyMenuItem('file.associateFileType', '与文件类型关联…', NO_SHORTCUT),
    new PyMenuItem('file.templateDataLanguage', '更改模板数据语言', NO_SHORTCUT),
    new PyMenuItem('file.toggleReadOnly', '切换只读特性', NO_SHORTCUT),
    new PyMenuItem('', '换行符', NO_SHORTCUT, true),
    new PyMenuItem('file.eolWindows', '转换为 Windows (CRLF)', NO_SHORTCUT, false, true),
    new PyMenuItem('file.eolUnix', '转换为 Unix (LF)', NO_SHORTCUT, false, true),
    new PyMenuItem('file.eolMac', '转换为 Mac (CR)', NO_SHORTCUT, false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('file.localHistory', '本地历史', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('file.save', '保存', 'Ctrl+S'),
    new PyMenuItem('file.saveAll', '全部保存(_S)', 'Ctrl+Shift+S'),
    new PyMenuItem('file.reloadAll', '从磁盘全部重新加载', NO_SHORTCUT),
    new PyMenuItem('file.invalidateCaches', '使缓存失效…', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('file.importSettings', '导入设置…', NO_SHORTCUT),
    new PyMenuItem('file.exportSettings', '导出设置(_E)…', NO_SHORTCUT),
    new PyMenuItem('file.restoreDefaults', '恢复默认设置…', NO_SHORTCUT),
    new PyMenuItem('file.saveAsTemplate', '将文件另存为模板(_L)…', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('file.exportHtml', '将文件或选区导出到 HTML(_H)…', NO_SHORTCUT),
    new PyMenuItem('file.print', '打印(_P)…', 'Ctrl+P'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('file.powerSave', '省电模式', NO_SHORTCUT),
    new PyMenuItem('file.essentialHighlighting', '基本高亮显示', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('file.close', '关闭标签', 'Ctrl+W'),
    new PyMenuItem('file.exit', '退出(_X)', 'Alt+F4')
  ];
}

function buildEditMenu(): PyMenuItem[] {
  // 依据 <group id="EditMenu"> 完整还原（含 CutCopyPasteGroup / FindMenuGroup / FindUsagesMenuGroup / Macros）
  return [
    new PyMenuItem('edit.undo', '撤消', 'Ctrl+Z'),
    new PyMenuItem('edit.redo', '重做', 'Ctrl+Shift+Z'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('edit.cut', '剪切(_T)', 'Ctrl+X'),
    new PyMenuItem('edit.copy', '复制(_C)', 'Ctrl+C'),
    new PyMenuItem('edit.copyPath', '复制路径(_O)', 'Ctrl+Shift+C'),
    new PyMenuItem('edit.copyReference', '复制引用(_Y)', 'Ctrl+Alt+Shift+C'),
    new PyMenuItem('edit.copyPlain', '复制为纯文本', NO_SHORTCUT),
    new PyMenuItem('edit.copyRich', '复制为富文本', NO_SHORTCUT),
    new PyMenuItem('edit.paste', '粘贴(_P)', 'Ctrl+V'),
    new PyMenuItem('edit.pasteHistory', '从历史记录粘贴(_E)…', 'Ctrl+Shift+V'),
    new PyMenuItem('edit.delete', '删除(_D)', 'Delete'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('edit.toggleFindInSelection', '仅在选区内搜索', NO_SHORTCUT),
    new PyMenuItem('edit.find', '查找(_F)…', 'Ctrl+F'),
    new PyMenuItem('edit.replace', '替换(_R)…', 'Ctrl+R'),
    new PyMenuItem('edit.findNext', '查找下一个/移至下一个匹配项(_N)', 'F3'),
    new PyMenuItem('edit.findPrev', '查找上一个/移至上一个匹配项(_V)', 'Shift+F3'),
    new PyMenuItem('edit.selectAllOccurrences', '选择所有匹配项', 'Ctrl+Alt+Shift+J'),
    new PyMenuItem('edit.unselectOccurrences', '取消选择匹配项', NO_SHORTCUT),
    new PyMenuItem('edit.scrollToResults', '输入时滚动至结果', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('edit.findWordAtCaret', '查找文本光标处的字', 'Ctrl+F3'),
    new PyMenuItem('edit.findPrevWordAtCaret', '文本光标处单词的上一个匹配项', 'Ctrl+Shift+F3'),
    new PyMenuItem('edit.findInFiles', '在文件中查找…', 'Ctrl+Shift+F'),
    new PyMenuItem('edit.replaceInFiles', '在文件中替换(_A)…', 'Ctrl+Shift+R'),
    new PyMenuItem('edit.structuralSearch', '结构化搜索(_T)…', NO_SHORTCUT),
    new PyMenuItem('edit.structuralReplace', '结构化替换(_C)…', NO_SHORTCUT),
    new PyMenuItem('', '查找用法', NO_SHORTCUT, true),
    new PyMenuItem('edit.findUsages', '查找用法(_U)', 'Alt+F7', false, true),
    new PyMenuItem('edit.findUsagesSettings', '查找用法设置…', NO_SHORTCUT, false, true),
    new PyMenuItem('edit.showUsages', '显示用法(_S)', NO_SHORTCUT, false, true),
    new PyMenuItem('edit.findUsagesInFile', '在文件中查找用法(_I)', NO_SHORTCUT, false, true),
    new PyMenuItem('edit.highlightUsagesInFile', '高亮显示文件中的用法(_H)', NO_SHORTCUT, false, true),
    new PyMenuItem('edit.nextHighlightUsage', '下一个高亮显示用例', NO_SHORTCUT, false, true),
    new PyMenuItem('edit.prevHighlightUsage', '转到上一个高亮的元素用法', NO_SHORTCUT, false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('edit.selectAll', '全选(_A)', 'Ctrl+A'),
    new PyMenuItem('edit.addCaretPerLine', '在所选行的末尾添加文本光标', 'Ctrl+Shift+A'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('edit.convertIndentsToSpaces', '转换为空格', NO_SHORTCUT),
    new PyMenuItem('edit.convertIndentsToTabs', '转换为制表符', NO_SHORTCUT),
    new PyMenuItem('', '宏', NO_SHORTCUT, true),
    new PyMenuItem('edit.playbackMacro', '回放上一个宏(_Y)', NO_SHORTCUT, false, true),
    new PyMenuItem('edit.recordMacro', '启动/停止宏录制(_R)', NO_SHORTCUT, false, true),
    new PyMenuItem('edit.editMacros', '编辑宏(_E)', NO_SHORTCUT, false, true),
    new PyMenuItem('edit.playSavedMacro', '播放保存的宏…', NO_SHORTCUT, false, true),
    new PyMenuItem('', '书签', NO_SHORTCUT, true),
    new PyMenuItem('edit.toggleBookmark', '切换书签', 'F11', false, true),
    new PyMenuItem('edit.showBookmarks', '显示书签', 'Shift+F11', false, true),
    new PyMenuItem('edit.nextBookmark', '下一个书签', NO_SHORTCUT, false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('edit.emoji', '表情和符号', NO_SHORTCUT),
    new PyMenuItem('edit.escapeEntities', '编码 XML/HTML 特殊字符', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('edit.format', '重新设置代码格式(_R)', 'Ctrl+Alt+L'),
    new PyMenuItem('edit.optimizeImports', '优化 import(_Z)', 'Ctrl+Alt+O'),
    new PyMenuItem('edit.autoIndent', '自动缩进行(_A)', 'Ctrl+Alt+I'),
    new PyMenuItem('edit.comment', '注释 / 取消注释', 'Ctrl+/'),
    new PyMenuItem('edit.duplicate', '复制当前行', 'Ctrl+D')
  ];
}

function buildViewMenu(): PyMenuItem[] {
  // 依据 <group id="ViewMenu"> 原文
  return [
    new PyMenuItem('view.presentationMode', '切换演示模式', NO_SHORTCUT),
    new PyMenuItem('view.distractionFree', '切换免打扰模式', NO_SHORTCUT),
    new PyMenuItem('view.fullscreen', '切换全屏模式', NO_SHORTCUT),
    new PyMenuItem('view.zenMode', '切换 Zen 模式', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('view.compactMode', '紧凑模式', NO_SHORTCUT),
    new PyMenuItem('view.zoomIde', '缩放 IDE', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('', '外观', NO_SHORTCUT, true),
    new PyMenuItem('view.mainMenu', '主菜单', NO_SHORTCUT, false, true),
    new PyMenuItem('view.mainToolbar', '工具栏', NO_SHORTCUT, false, true),
    new PyMenuItem('view.toolbarClassic', '工具栏经典', NO_SHORTCUT, false, true),
    new PyMenuItem('view.breadcrumb', '导航栏', NO_SHORTCUT, false, true),
    new PyMenuItem('view.left', '工具窗口', 'Alt+1', false, true),
    new PyMenuItem('view.statusBar', '状态栏(_S)', NO_SHORTCUT, false, true),
    new PyMenuItem('view.statusText', '状态文本', NO_SHORTCUT, false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('view.gotoSource', '跳转到源(_J)', NO_SHORTCUT),
    new PyMenuItem('view.showSource', '显示源(_W)', NO_SHORTCUT),
    new PyMenuItem('view.splitRightPart', '在右侧拆分部分打开', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('view.recentLocations', '最近的位置', 'Ctrl+Shift+E'),
    new PyMenuItem('view.recentFiles', '最近的文件(_N)', 'Ctrl+E'),
    new PyMenuItem('view.quickSwitchScheme', '快速切换方案(_Q)…', 'Ctrl+`'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('view.wordwrap', '自动换行', NO_SHORTCUT),
    new PyMenuItem('view.showWhitespace', '显示空格(_O)', NO_SHORTCUT),
    new PyMenuItem('view.showLineNumbers', '显示行号(_I)', NO_SHORTCUT),
    new PyMenuItem('view.showGutterIcons', '显示装订区域图标(_O)', NO_SHORTCUT),
    new PyMenuItem('view.indentGuides', '显示缩进参考线(_O)', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('view.resetFontSize', '在所有编辑器中重置字体大小', NO_SHORTCUT),
    new PyMenuItem('view.highlightCurrentDeclaration', '仅高亮显示当前声明', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('view.theme', '切换深色 / 浅色', 'Ctrl+Alt+T'),
    new PyMenuItem('view.zoomIn', '放大字号', 'Ctrl+='),
    new PyMenuItem('view.zoomOut', '缩小字号', 'Ctrl+-'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('view.splitRight', '向右分屏', NO_SHORTCUT),
    new PyMenuItem('tools.settings', '设置…', 'Ctrl+Alt+S')
  ];
}

function buildRunMenu(): PyMenuItem[] {
  // 依据 <group id="RunMenu"> 与 <group id="DebugMainMenu"> 原文
  return [
    new PyMenuItem('run.run', '运行', 'Shift+F10'),
    new PyMenuItem('run.debug', '调试', 'Shift+F9'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('run.config', '编辑配置(_R)…', 'Alt+Shift+F10'),
    new PyMenuItem('run.manageTargets', 'ManageTargets', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('run.stop', '停止', 'Ctrl+F2'),
    new PyMenuItem('run.stopBackground', '停止后台进程…', NO_SHORTCUT),
    new PyMenuItem('run.showLive', '显示正在运行的列表', NO_SHORTCUT),
    new PyMenuItem('', '调试', NO_SHORTCUT, true),
    new PyMenuItem('debug.stepOver', '步过(_O)', 'F8', false, true),
    new PyMenuItem('debug.stepInto', '步入(_I)', 'F7', false, true),
    new PyMenuItem('debug.stepOut', '步出(_T)', 'Shift+F8', false, true),
    new PyMenuItem('debug.runToCursor', '运行到光标处(_C)', 'Alt+F9', false, true),
    new PyMenuItem('debug.resume', '恢复程序(_G)', 'F9', false, true),
    new PyMenuItem('debug.pause', '暂停程序(_P)', 'Ctrl+F8', false, true),
    new PyMenuItem('debug.evaluate', '对表达式求值(_X)…', 'Alt+F8', false, true),
    new PyMenuItem('debug.showExecutionPoint', '显示执行点(_X)', 'Alt+F10', false, true),
    new PyMenuItem('debug.toggleBreakpoint', '切换行断点(_L)', 'Ctrl+F8', false, true),
    new PyMenuItem('debug.viewBreakpoints', '查看断点(_K)…', 'Ctrl+Shift+F8', false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('run.showConsole', '显示运行窗口', 'Alt+4'),
    new PyMenuItem('run.analyzeStack', '分析堆栈跟踪或线程转储(_S)…', NO_SHORTCUT),
    new PyMenuItem('run.runtime', 'Python 运行时状态…', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('run.pip', '安装依赖包…', NO_SHORTCUT)
  ];
}

function buildToolsMenu(): PyMenuItem[] {
  // 依据 <group id="ToolsMenu"> 原文（OtherMenu/Services 组在本 IDE 映射为下方 Python 相关项）
  return [
    new PyMenuItem('tools.createLauncher', '创建命令行启动器…', NO_SHORTCUT),
    new PyMenuItem('tools.createDesktopEntry', '创建桌面条目…', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('tools.repl', 'Python 控制台', 'Alt+4'),
    new PyMenuItem('tools.terminal', '终端', 'Alt+F12'),
    new PyMenuItem('run.pip', '安装依赖包…', NO_SHORTCUT),
    new PyMenuItem('tools.resetRuntime', '重新初始化运行时', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('tools.services', '服务', NO_SHORTCUT),
    new PyMenuItem('tools.resetLayout', '恢复默认布局', NO_SHORTCUT),
    new PyMenuItem('tools.settings', '设置…', 'Ctrl+Alt+S')
  ];
}

function buildHelpMenu(): PyMenuItem[] {
  // 依据 <group id="HelpMenu"> 原文
  return [
    new PyMenuItem('help.findAction', '查找操作(_F)…', 'Ctrl+Shift+A'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('help.account', '华为账号登录…', NO_SHORTCUT),
    new PyMenuItem('help.docs', '帮助(_H)', 'F1'),
    new PyMenuItem('help.gettingStarted', '入门指南(_G)', NO_SHORTCUT),
    new PyMenuItem('help.shortcuts', '键盘快捷键 PDF(_K)', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('help.support', '联系支持(_S)…', NO_SHORTCUT),
    new PyMenuItem('help.bug', '提交 bug 报告…', NO_SHORTCUT),
    new PyMenuItem('help.feedback', '提交反馈(_F)…', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('help.openLog', '在编辑器中打开日志', NO_SHORTCUT),
    new PyMenuItem('help.showLog', '在文件管理器中显示日志(_L)', NO_SHORTCUT),
    new PyMenuItem('help.collectLogs', '收集日志和诊断数据', NO_SHORTCUT),
    new PyMenuItem('', '诊断工具', NO_SHORTCUT, true),
    new PyMenuItem('help.activityMonitor', '活动监视器…', NO_SHORTCUT, false, true),
    new PyMenuItem('help.dumpThreads', '转储线程', NO_SHORTCUT, false, true),
    new PyMenuItem('help.customProperties', '编辑自定义属性…', NO_SHORTCUT, false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('help.runtime', 'Python 运行时状态…', NO_SHORTCUT),
    new PyMenuItem('help.licenses', '第三方组件与许可', NO_SHORTCUT),
    new PyMenuItem('help.checkUpdate', '检查更新(_C)…', NO_SHORTCUT),
    new PyMenuItem('help.about', '关于(_A)', NO_SHORTCUT)
  ];
}

/** 代码菜单（实测 PyCharm 有「代码(C)」，位于「导航(N)」之后） */
function buildCodeMenu(): PyMenuItem[] {
  // 依据 <group id="CodeMenu">（LangActions.xml / PlatformActions.xml）重建，文案取自中文语言包
  return [
    new PyMenuItem('code.generate', '生成…', 'Alt+Insert'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('', '代码补全', NO_SHORTCUT, true),
    new PyMenuItem('edit.complete', '基本', 'Ctrl+空格', false, true),
    new PyMenuItem('code.smartType', '类型匹配', 'Ctrl+Shift+空格', false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('code.inspect', '检查代码(_I)…', NO_SHORTCUT),
    new PyMenuItem('code.cleanup', '代码清理(_C)…', NO_SHORTCUT),
    new PyMenuItem('code.analyzeStack', '分析堆栈跟踪或线程转储(_S)…', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('code.liveTemplate', '插入实时模板(_T)…', 'Ctrl+J'),
    new PyMenuItem('code.saveTemplate', '保存为实时模板(_I)…', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('code.surround', '环绕方式(_S)…', 'Ctrl+Alt+T'),
    new PyMenuItem('code.unwrap', '解包/移除(_W)…', 'Ctrl+Shift+Delete'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('', '折叠', NO_SHORTCUT, true),
    new PyMenuItem('code.expand', '展开(_X)', 'Ctrl+=', false, true),
    new PyMenuItem('code.expandAll', '全部展开(_E)', 'Ctrl+Shift+=', false, true),
    new PyMenuItem('code.collapse', '收起(_C)', 'Ctrl+-', false, true),
    new PyMenuItem('code.collapseAll', '全部收起(_A)', 'Ctrl+Shift+-', false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('edit.comment', '使用行注释进行注释(_L)', 'Ctrl+/'),
    new PyMenuItem('code.commentBlock', '使用块注释进行注释(_B)', 'Ctrl+Shift+/'),
    new PyMenuItem('edit.format', '重新设置代码格式(_R)', 'Ctrl+Alt+L'),
    new PyMenuItem('edit.autoIndent', '自动缩进行(_A)', 'Ctrl+Alt+I'),
    new PyMenuItem('edit.optimizeImports', '优化 import(_Z)', 'Ctrl+Alt+O'),
    new PyMenuItem('code.rearrange', '重新排列代码', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('code.moveUp', '向上移动语句(_U)', 'Ctrl+Shift+Up'),
    new PyMenuItem('code.moveDown', '向下移动语句(_W)', 'Ctrl+Shift+Down'),
    new PyMenuItem('edit.duplicate', '复制当前行', 'Ctrl+D'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('code.structure', '文件结构…', 'Alt+7'),
    new PyMenuItem('code.problems', '问题视图', 'Alt+6')
  ];
}

/** 重构菜单（实测 PyCharm 有「重构(R)」） */
function buildRefactorMenu(): PyMenuItem[] {
  // 依据 <group id="RefactoringMenu"> 原文
  return [
    new PyMenuItem('refactor.rename', '重命名(_R)…', 'Shift+F6'),
    new PyMenuItem('refactor.changeSignature', '更改签名(_G)…', 'Ctrl+F6'),
    new PyMenuItem('', '引入', NO_SHORTCUT, true),
    new PyMenuItem('refactor.introduceVar', '引入变量(_V)…', 'Ctrl+Alt+V', false, true),
    new PyMenuItem('refactor.introduceConst', '引入常量(_C)…', 'Ctrl+Alt+C', false, true),
    new PyMenuItem('refactor.introduceField', '引入字段(_F)…', 'Ctrl+Alt+F', false, true),
    new PyMenuItem('refactor.introduceParam', '引入形参(_P)…', 'Ctrl+Alt+P', false, true),
    new PyMenuItem('refactor.extractMethod', '提取方法(_M)…', 'Ctrl+Alt+M', false, true),
    new PyMenuItem('refactor.extractDelegate', '提取委托(_D)…', NO_SHORTCUT, false, true),
    new PyMenuItem('refactor.extractSuperclass', '提取超类(_U)…', NO_SHORTCUT, false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('refactor.inline', '内联(_N)…', 'Ctrl+Alt+N'),
    new PyMenuItem('refactor.move', '移动(_M)…', 'F6'),
    new PyMenuItem('refactor.copy', '复制(_O)…', 'F5'),
    new PyMenuItem('refactor.safeDelete', '安全删除(_D)…', 'Alt+Delete'),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('code.structure', '文件结构…', 'Alt+7')
  ];
}

/** VCS 菜单（PyCharm 中文包 group.VcsGroup.text=「版本控制」；英文包为 VCS） */
function buildVcsMenu(): PyMenuItem[] {
  // 依据 <group id="Vcs.MainMenu"> 原文（含 VcsGlobalGroup / Vcs.Browse / Vcs.Import）
  return [
    new PyMenuItem('vcs.enable', '启用版本控制集成(_E)…', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('vcs.popup', 'VCS 操作弹出窗口…', 'Alt+`'),
    new PyMenuItem('vcs.share', '集成项目(_G)', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('vcs.createPatch', '从本地更改创建补丁…', NO_SHORTCUT),
    new PyMenuItem('vcs.applyPatch', '应用补丁…', NO_SHORTCUT),
    new PyMenuItem('vcs.applyPatchClipboard', '从剪贴板应用补丁…', NO_SHORTCUT),
    new PyMenuItem('vcs.shelve', '搁置更改…', NO_SHORTCUT),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('', '浏览', NO_SHORTCUT, true),
    new PyMenuItem('vcs.history', '显示历史记录', NO_SHORTCUT, false, true),
    new PyMenuItem('vcs.showAnnotation', '显示注解', NO_SHORTCUT, false, true),
    new PyMenuItem('vcs.commit', '提交…', 'Ctrl+K', false, true),
    new PyMenuItem('vcs.update', '更新项目', 'Ctrl+T', false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('tools.vcs', '版本控制面板…', 'Alt+9'),
    new PyMenuItem('vcs.pull', '拉取…', NO_SHORTCUT),
    new PyMenuItem('vcs.push', '推送…', 'Ctrl+Shift+K')
  ];
}

/** 窗口菜单（实测 PyCharm 有「窗口(W)」） */
function buildWindowMenu(): PyMenuItem[] {
  // 依据 <group id="WindowMenu"> 原文（LayoutsGroup / ActiveToolwindowGroup / EditorTabsGroup）
  return [
    new PyMenuItem('', '布局', NO_SHORTCUT, true),
    new PyMenuItem('window.restoreLayout', '恢复当前布局(_R)', NO_SHORTCUT, false, true),
    new PyMenuItem('window.storeLayout', '保存当前布局中的更改(_S)', NO_SHORTCUT, false, true),
    new PyMenuItem('window.storeNewLayout', '将当前布局另存为新布局(_N)…', NO_SHORTCUT, false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('', '活动工具窗口', NO_SHORTCUT, true),
    new PyMenuItem('window.hideActive', '隐藏有效工具窗口(_D)', NO_SHORTCUT, false, true),
    new PyMenuItem('window.hideSide', '隐藏本侧工具窗口', NO_SHORTCUT, false, true),
    new PyMenuItem('window.hideBottom', '隐藏底部工具窗口', NO_SHORTCUT, false, true),
    new PyMenuItem('window.hideAll', '隐藏所有工具窗口(_T)', NO_SHORTCUT, false, true),
    new PyMenuItem('window.closeTab', '关闭活动标签页(_O)', 'Ctrl+W', false, true),
    new PyMenuItem('window.closeOtherTabs', '关闭其他标签页(_O)', NO_SHORTCUT, false, true),
    new PyMenuItem('window.closeAllTabs', '关闭所有标签页(_A)', NO_SHORTCUT, false, true),
    new PyMenuItem('window.pinTab', '固定活动标签页(_I)', NO_SHORTCUT, false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('', '拆分', NO_SHORTCUT, true),
    new PyMenuItem('window.splitRight', '向右拆分', NO_SHORTCUT, false, true),
    new PyMenuItem('window.splitDown', '向下拆分', NO_SHORTCUT, false, true),
    new PyMenuItem('window.unsplit', '取消拆分(_S)', NO_SHORTCUT, false, true),
    new PyMenuItem('', '', NO_SHORTCUT),
    new PyMenuItem('window.nextTab2', '下一个标签页', 'Ctrl+Tab'),
    new PyMenuItem('window.prevTab2', '上一个标签页', 'Ctrl+Shift+Tab'),
    new PyMenuItem('window.expandLeft', '延伸至左侧', NO_SHORTCUT),
    new PyMenuItem('window.expandRight', '延伸至右侧', NO_SHORTCUT),
    new PyMenuItem('window.expandTop', '延伸至顶部', NO_SHORTCUT),
    new PyMenuItem('window.expandBottom', '延伸至底部', NO_SHORTCUT)
  ];
}

function buildMenus(): PyMenuGroup[] {
  return [
    new PyMenuGroup('文件(F)', buildFileMenu()),
    new PyMenuGroup('编辑(E)', buildEditMenu()),
    new PyMenuGroup('视图(V)', buildViewMenu()),
    new PyMenuGroup('导航(N)', buildNavMenu()),
    new PyMenuGroup('代码(C)', buildCodeMenu()),
    new PyMenuGroup('重构(R)', buildRefactorMenu()),
    new PyMenuGroup('运行(U)', buildRunMenu()),
    new PyMenuGroup('工具(T)', buildToolsMenu()),
    new PyMenuGroup('版本控制(V)', buildVcsMenu()),
    new PyMenuGroup('窗口(W)', buildWindowMenu()),
    new PyMenuGroup('帮助(H)', buildHelpMenu())
  ];
}

@Component
export struct MenuBarView {
  @Prop theme: PyTheme = new PyTheme();
  @Prop appTitle: string = '鸿蒙Python IDE';
  /** 当前工程名（PyCharm 主工具栏的工程部件显示它） */
  @Prop projectName: string = '';
  /**
   * 是否渲染中间的菜单标题。false 时只保留左侧应用标识（Python 图标）与右侧工程/VCS 微件 ——
   * 「隐藏在汉堡按钮下方」模式用：☰ 与微件同排共存，点 ☰ 时菜单标题**横向展开**
   * （PyCharm registry: ide.main.menu.expand.horizontal=true）。
   */
  @Prop showTitles: boolean = true;
  /**
   * 隐藏模式（UNDER_HAMBURGER_BUTTON）：在产品图标**后面**再放一个 ☰ 按钮。
   * 顺序依据 ToolbarFrameHeader：menuBarHeaderTitle（产品图标）→ mainMenuWithButton（☰）→ toolbar。
   */
  @Prop hamburger: boolean = false;
  /** ☰ 点击：由 Index 切换展开/收回（PyCharm ExpandableMenu.switchState） */
  onHamburgerToggle: () => void = () => {};

  /** 工程部件方块里的首字 */
  private projectInitial(): string {
    return this.projectName.length > 0 ? this.projectName.substring(0, 1) : 'P';
  }

  /** 「文件(F)」-> 前缀「文件(」 */
  private menuLabelOf(title: string): string {
    const idx: number = title.indexOf('(');
    return idx >= 0 ? title.substring(0, idx + 1) : title;
  }

  /** 「文件(F)」-> 「F」：助记符字母，渲染时加下划线（PyCharm 同款） */
  private mnemonicOf(title: string): string {
    const idx: number = title.indexOf('(');
    if (idx >= 0 && idx + 1 < title.length) {
      return title.substring(idx + 1, title.length - 1);
    }
    return '';
  }

  /** 「文件(F)」-> 「)」 */
  private menuSuffixOf(title: string): string {
    return title.indexOf('(') >= 0 ? ')' : '';
  }
  /** 展开中的顶级菜单标题（由页面持有，弹层在页面级渲染，否则点不到） */
  @Link openMenuTitle: string;
  /** 弹层水平位置（本组件算好，页面级弹层用） */
  @Link popupX: number;
  /** 当前 hover 的菜单标题，用于 hover 高亮 */
  @State hoverMenu: string = '';
  /** 当前 hover 的下拉项 id */
  @State hoverItem: string = '';
  onMenuAction: (action: string) => void = () => {};

  private menus: PyMenuGroup[] = buildMenus();

  private isOpen(title: string): boolean {
    return this.openMenuTitle === title;
  }

  private toggle(title: string): void {
    this.openMenuTitle = this.openMenuTitle === title ? '' : title;
    this.popupX = this.popupOffsetX(title);
    this.hoverItem = '';
  }

  private close(): void {
    this.openMenuTitle = '';
    this.hoverItem = '';
  }

  private pick(id: string): void {
    if (id.length === 0) {
      return;
    }
    this.close();
    this.onMenuAction(id);
  }

  /**
   * 菜单按钮背景。ResourceColor 联合类型允许 Color 枚举成员，
   * 出处 component/common.d.ts:17653 backgroundColor(value: ResourceColor)。
   */
  private menuBtnBg(title: string): ResourceColor {
    if (this.isOpen(title)) {
      return this.theme.selectedBg;
    }
    return this.hoverMenu === title ? this.theme.menuHoverBg : Color.Transparent;
  }

  private menuBtnFg(title: string): string {
    if (this.isOpen(title)) {
      return this.theme.textPrimary;
    }
    return this.hoverMenu === title ? this.theme.textPrimary : this.theme.textSecondary;
  }

  private itemBg(id: string): ResourceColor {
    return this.hoverItem === id ? this.theme.menuHoverBg : Color.Transparent;
  }

  /** 弹层投影：跟着主题深浅切换，显式类型避免 arkts-no-untyped-obj-literals */
  private popupShadow(): ShadowOptions {
    const opt: ShadowOptions = {
      radius: 12,
      color: this.theme.isDark ? '#66000000' : '#33000000',
      offsetX: 0,
      offsetY: 4
    };
    return opt;
  }

  /** 估算菜单标题宽度：中文按 13vp、ASCII 按 7vp（原来一律按 13 会把 "文件(F)" 算宽） */
  private estimateLabelWidth(title: string): number {
    let width: number = 0;
    for (let i = 0; i < title.length; i++) {
      width += title.charCodeAt(i) > 127 ? 13 : 7;
    }
    return width;
  }

  /** 弹层水平位置：应用标识宽度之后，逐个菜单累加估算宽度 */
  private popupOffsetX(title: string): number {
    // 左侧标识区约 130vp，每个菜单按钮按 2*10 内边距 + 文字宽度估算
    let x: number = 130;
    for (let i = 0; i < this.menus.length; i++) {
      const group: PyMenuGroup = this.menus[i];
      if (group.title === title) {
        return x - MENU_BTN_PADDING_H;
      }
      x += this.estimateLabelWidth(group.title) + MENU_BTN_PADDING_H * 2;
    }
    return 130;
  }

  private popupPos(title: string): Position {
    const pos: Position = { x: this.popupOffsetX(title), y: MENU_BAR_HEIGHT };
    return pos;
  }

  /** 下拉弹层内容：用 Column（不用 Scroll），避免 Scroll 在 Stack 子节点位置的限制 */
  @Builder
  popupColumn(group: PyMenuGroup) {
    Column() {
      ForEach(group.items, (item: PyMenuItem, index: number) => {
        if (item.header) {
          // 分组标题（PyCharm 的子菜单标题，不可点）
          Text(item.label)
            .fontSize(11)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textSecondary)
            .width('100%')
            .padding({ left: 12, right: 12, top: 6, bottom: 2 })
        } else if (item.id.length === 0) {
          Divider()
            .vertical(false)                                  // divider.d.ts:69
            .strokeWidth(1)                                   // divider.d.ts:103
            .color(this.theme.separator)                      // divider.d.ts:84
            .margin(MENU_DIVIDER_MARGIN)
        } else {
          Row() {
            Text(item.label)
              .fontSize(12)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textPrimary)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow(ELLIPSIS)
            Text(item.shortcut)
              .fontSize(11)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textSecondary)
          }
          .width('100%')
          .height(MENU_ITEM_HEIGHT)
          .padding(item.indent ? MENU_ITEM_INDENT_PAD : MENU_ITEM_PAD)
          .backgroundColor(this.itemBg(item.id))
          .onHover((isHover: boolean) => {
            this.hoverItem = isHover ? item.id : '';
          })
          .onClick(() => {
            this.pick(item.id);
          })
        }
      }, (item: PyMenuItem, index: number) => `${index}-${item.id}`)
    }
    // ⚠️ 之前用 constraintSize(最小宽)，子项 width('100%') 会解析成整个窗口宽度，
    // 弹层变成全屏宽——看起来完全不像 PyCharm。这里固定成下拉框宽度。
    .width(MENU_POPUP_WIDTH)
    .padding(MENU_POPUP_PAD)
    .backgroundColor(this.theme.popupBg)
      .border({ width: 1, color: this.theme.separator })
    .borderWidth(1)
    .borderColor(this.theme.border)
    .borderStyle(BorderStyle.Solid)
    .borderRadius(6)
    .shadow(this.popupShadow())
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ── 第一层：菜单栏本体 ──────────────────────────────
      Row() {
        // 左侧应用标识：PyCharm 只放 logo（工程名由右侧的工程部件承担，避免重复）
        Row() {
          IconPython({ iconSize: 18, color: this.theme.funcName, colorAlt: this.theme.warning })
        }
        .padding(IDENTITY_PAD)

        // ☰ 在产品图标之后（ToolbarFrameHeader: menuBarHeaderTitle → mainMenuWithButton）
        // 图标 = AllIcons.General.WindowsMenu_20x20 → expui/general/windowsMenu@20x20.svg
        if (this.hamburger) {
          Image($rawfile('icons/windowsMenu@20x20.svg'))
            .width(20)
            .height(20)
            .objectFit(ImageFit.Contain)
            .draggable(false)
            .margin({ left: 2, right: 6 })
            .onClick(() => {
              this.onHamburgerToggle();
            })
        }

        // 中间菜单（PyCharm 的助记符字母带下划线：(F)(E)(V)…）
        if (this.showTitles) {
          ForEach(this.menus, (group: PyMenuGroup, index: number) => {
          Text() {
            Span(this.menuLabelOf(group.title))
              .fontSize(12)
              .fontFamily(PyFont.ui)
              .fontColor(this.menuBtnFg(group.title))
            Span(this.mnemonicOf(group.title))
              .fontSize(12)
              .fontFamily(PyFont.ui)
              .fontColor(this.menuBtnFg(group.title))
              .decoration({
                type: TextDecorationType.Underline,
                color: this.menuBtnFg(group.title)
              })
            Span(this.menuSuffixOf(group.title))
              .fontSize(12)
              .fontFamily(PyFont.ui)
              .fontColor(this.menuBtnFg(group.title))
          }
          .height(MENU_BAR_HEIGHT)
          .padding(MENU_BTN_PAD)
          .backgroundColor(this.menuBtnBg(group.title))
          .onHover((isHover: boolean) => {
            this.hoverMenu = isHover ? group.title : '';
            // PyCharm 行为：已经有菜单展开时，划过去直接切换
            if (isHover && this.openMenuTitle.length > 0) {
              this.openMenuTitle = group.title;
              this.popupX = this.popupOffsetX(group.title);
              this.hoverItem = '';
            }
          })
          .onClick(() => {
            this.toggle(group.title);
          })
          }, (group: PyMenuGroup, index: number) => `${index}-${group.title}`)
        }

        // PyCharm New UI 的工程部件：绿色圆角方块（工程名首字）+ 工程名 + 折叠箭头
        Row() {
          Text(this.projectInitial())
            .fontSize(11)
            .fontFamily(PyFont.ui)
            .fontColor('#FFFFFF')
            .width(18)
            .height(18)
            .textAlign(TextAlign.Center)
            .borderRadius(5)
            .backgroundColor('#499E7D')
          Text(this.projectName.length > 0 ? this.projectName : '未打开项目')
            .fontSize(12)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textPrimary)
            .maxLines(1)
            .textOverflow(ELLIPSIS)
            .margin({ left: 6 })
          IconChevronDown({ iconSize: 12, color: this.theme.textSecondary })
            .margin({ left: 2 })
        }
        .height(24)
        .padding({ left: 6, right: 6 })
        .margin({ left: 12 })
        .borderRadius(4)
        .onClick(() => {
          this.pick('file.openProject');
        })

        // 版本控制部件：图标 = PyCharm 的 expui/general/vcs.svg（真图，从 jar 取出）
        Row() {
          Image($rawfile('icons/vcs.svg'))
            .width(14)
            .height(14)
            .objectFit(ImageFit.Contain)
            .draggable(false)
          Text('版本控制')
            .fontSize(12)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textPrimary)
            .maxLines(1)
            .margin({ left: 6 })
          IconChevronDown({ iconSize: 12, color: this.theme.textSecondary })
            .margin({ left: 4 })
        }
        .height(24)
        .padding({ left: 8, right: 8 })
        .margin({ left: 18 })
        .borderRadius(4)
        .onClick(() => {
          this.pick('tools.vcs');
        })
      }
      .height(MENU_BAR_HEIGHT)
      .backgroundColor(Color.Transparent)
      .alignItems(VerticalAlign.Center)

    }
    // 不能写 width('100%')：顶栏这一行里它后面还有主工具栏（NewUiRunWidget +
    // SearchEverywhere + SettingsEntryPoint），写满整行会把工具栏挤成 0 宽 → 那些按钮全都不显示。
    // 同时限制最大宽度，保证工具栏那边的 ⋮ / 随处搜索 / 设置不会被挤出窗口右缘。
    .constraintSize({ maxWidth: '62%' })
    .height(MENU_BAR_HEIGHT)
    .backgroundColor(Color.Transparent)
    // 弹层要画在菜单栏这一条之外，因此不能裁剪
    .clip(false)
    // EdgeWidths 是 declare type（component/units.d.ts:699），不是 class
    .borderWidth(MENU_BAR_EDGE)
    // 主题 MainToolbar.borderColor = transparent：顶栏下沿不画线，
    // 否则 1px 的 border 色会把渐变横向切成两段（实测就是这个"隔断"）
    .borderColor(Color.Transparent)
    .borderStyle(BorderStyle.Solid)
  }
}

/**
 * 页面级菜单弹层。
 *
 * 为什么必须单独一层：弹层从菜单栏往下铺 600+vp，而菜单栏组件自身只有 30vp 高。
 * ArkUI 的命中测试以父容器边界为限（`.clip(false)` 只影响绘制、不影响触摸），
 * 画在菜单栏 Stack 里的弹层因此点不到任何项。挂到页面根 Stack（整页大小）下即可正常响应。
 */
@Component
export struct MenuPopupLayer {
  @Prop theme: PyTheme = new PyTheme();
  /** 展开中的菜单标题；'' 时调用方不会渲染本组件 */
  @Prop openTitle: string = '';
  /** 弹层左边界（由菜单栏按各标题宽度算好） */
  @Prop anchorX: number = 0;
  @State hoverItem: string = '';
  onAction: (action: string) => void = () => {};
  onClose: () => void = () => {};

  private menus: PyMenuGroup[] = buildMenus();

  private itemBg(id: string): ResourceColor {
    return this.hoverItem === id ? this.theme.menuHoverBg : Color.Transparent;
  }

  private popupShadow(): ShadowOptions {
    const opt: ShadowOptions = {
      radius: 12,
      color: this.theme.isDark ? '#66000000' : '#33000000',
      offsetX: 0,
      offsetY: 4
    };
    return opt;
  }

  private popupPos(): Position {
    const pos: Position = { x: this.anchorX, y: MENU_BAR_HEIGHT };
    return pos;
  }

  private pick(id: string): void {
    if (id.length === 0) {
      return;
    }
    this.hoverItem = '';
    this.onAction(id);
  }

  /** 弹层内容：与菜单栏里的写法一致（分组标题 / 分隔线 / 可点项） */
  @Builder
  popupColumn(group: PyMenuGroup) {
    Column() {
      ForEach(group.items, (item: PyMenuItem, index: number) => {
        if (item.header) {
          Text(item.label)
            .fontSize(11)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textSecondary)
            .width('100%')
            .padding({ left: 12, right: 12, top: 6, bottom: 2 })
        } else if (item.id.length === 0) {
          Divider()
            .vertical(false)
            .strokeWidth(1)
            .color(this.theme.separator)
            .margin(MENU_DIVIDER_MARGIN)
        } else {
          Row() {
            Text(item.label)
              .fontSize(12)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textPrimary)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow(ELLIPSIS)
            Text(item.shortcut)
              .fontSize(11)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textSecondary)
          }
          .width('100%')
          .height(MENU_ITEM_HEIGHT)
          .padding(item.indent ? MENU_ITEM_INDENT_PAD : MENU_ITEM_PAD)
          .backgroundColor(this.itemBg(item.id))
          .onHover((isHover: boolean) => {
            this.hoverItem = isHover ? item.id : '';
          })
          .onClick(() => {
            this.pick(item.id);
          })
        }
      }, (item: PyMenuItem, index: number) => `layer-${index}-${item.id}`)
    }
    .width(MENU_POPUP_WIDTH)
    .padding(MENU_POPUP_PAD)
    .backgroundColor(this.theme.popupBg)
      .border({ width: 1, color: this.theme.separator })
    .borderWidth(1)
    .borderColor(this.theme.border)
    .borderStyle(BorderStyle.Solid)
    .borderRadius(6)
    .shadow(this.popupShadow())
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 遮罩：点击菜单以外任意位置关闭（PyCharm 行为）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onClose();
        })

      ForEach(this.menus, (group: PyMenuGroup, index: number) => {
        if (group.title === this.openTitle && group.items.length > 0) {
          Column() {
            this.popupColumn(group)
          }
          .constraintSize(MENU_POPUP_MAX)
          .position(this.popupPos())
          .clip(false)
        }
      }, (group: PyMenuGroup, index: number) => `popup-${index}-${group.title}`)
    }
    .width('100%')
    .height('100%')
  }
}
