import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { window } from '@kit.ArkUI';
import { font } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';
import { fileIconOf } from '../common/FileIcons';
import { PyTheme, DARCULA, INTELLIJ_LIGHT, themeByName, PyFont } from '../common/Theme';
import {
  AppSettings,
  DebugPause,
  EditorTab,
  FileNode,
  LayoutSize,
  LogEntry,
  RunResult,
  RuntimeStatus,
  SearchState,
  isExcludedDirName
} from '../model/Models';
import { FileService } from '../service/FileService';
import { SettingsService } from '../service/SettingsService';
import { PyRuntimeService } from '../service/PyRuntimeService';
import { CodeEditor, CodeEditorController } from '../view/CodeEditor';
import { MenuBarView, MenuPopupLayer } from '../view/MenuBarView';
import { ToolBarView } from '../view/ToolBarView';
import { ProjectTreeView } from '../view/ProjectTreeView';
import { ConsolePanelView } from '../view/ConsolePanelView';
import { StatusBarView } from '../view/StatusBarView';
import { languages, languageLabel, languageOf, LangDef } from '../service/LanguageService';
import { TerminalService, DirWatcher } from '../service/TerminalService';
import { WelcomeView } from '../view/WelcomeView';
import { IconChevronRight, IconClose, IconFolder, IconPython, IconSettings, IconTerminal, IconAsset, IconMoreVertical } from '../view/IdeIcons';

const MAX_LOG_ENTRIES: number = 3000;

/** 右侧竖条宽度与顶部起始位置（PyCharm New UI 的第二条工具窗栏，实测 77vp） */
// ui.lnf.xml 实测：TOOL_WINDOW_LEFT_SIDE_CUSTOM_WIDTH / RIGHT = 50
/** 设置分类节点（PyCharm 的设置树：组 + 页面） */
class SettingsNode {
  id: string;
  label: string;
  group: boolean;
  parent: string;

  constructor(id: string, label: string, group: boolean, parent: string) {
    this.id = id;
    this.label = label;
    this.group = group;
    this.parent = parent;
  }
}

/**
 * 设置分类树。层级与中文名取自 PyCharm 语言包里的 configurable.* 键
 * （如 configurable.group.appearance.settings.display.name = 外观与行为），
 * 与 PyCharm「设置」对话框左侧分类树一致。
 */
function settingsTree(): SettingsNode[] {
  return [
    // 外观与行为
    new SettingsNode('appearance', '外观与行为', true, ''),
    new SettingsNode('appearance.appearance', '外观', false, 'appearance'),
    new SettingsNode('appearance.menus', '菜单和工具栏', false, 'appearance'),
    new SettingsNode('appearance.system', '系统设置', false, 'appearance'),
    new SettingsNode('appearance.fileColors', '文件颜色', false, 'appearance'),
    new SettingsNode('appearance.notifications', '通知', false, 'appearance'),
    new SettingsNode('appearance.pathVars', '路径变量', false, 'appearance'),
    new SettingsNode('keymap', '键位映射', false, 'appearance'),
    // 编辑器
    new SettingsNode('editor', '编辑器', true, ''),
    new SettingsNode('editor.general', '常规', false, 'editor'),
    new SettingsNode('editor.font', '字体', false, 'editor'),
    new SettingsNode('editor.colors', '颜色方案', false, 'editor'),
    new SettingsNode('editor.codeStyle', '代码样式', false, 'editor'),
    new SettingsNode('editor.templates', '文件和代码模板', false, 'editor'),
    new SettingsNode('editor.encoding', '文件编码', false, 'editor'),
    new SettingsNode('editor.liveTemplates', '实时模板', false, 'editor'),
    new SettingsNode('editor.fileTypes', '文件类型', false, 'editor'),
    new SettingsNode('editor.inspections', '检查', false, 'editor'),
    new SettingsNode('editor.autoImport', '自动导入', false, 'editor'),
    new SettingsNode('editor.folding', '代码折叠', false, 'editor'),
    new SettingsNode('editor.completion', '代码补全', false, 'editor'),
    // 默认项目
    new SettingsNode('project', '默认项目', true, ''),
    new SettingsNode('project.structure', '项目结构', false, 'project'),
    new SettingsNode('project.interpreter', 'Python 解释器', false, 'project'),
    new SettingsNode('project.packages', 'Python 软件包', false, 'project'),
    new SettingsNode('project.vcs', '版本控制', false, 'project'),
    new SettingsNode('project.buildTools', '构建工具', false, 'project'),
    // 构建、执行、部署
    new SettingsNode('build', '构建、执行、部署', true, ''),
    new SettingsNode('runConfig', '运行配置', false, 'build'),
    new SettingsNode('build.compiler', '编译器', false, 'build'),
    new SettingsNode('build.coverage', '覆盖率', false, 'build'),
    // 语言和框架
    new SettingsNode('language', '语言和框架', true, ''),
    new SettingsNode('language.python', 'Python', false, 'language'),
    // 工具
    new SettingsNode('tools', '工具', true, ''),
    new SettingsNode('tools.terminal', '终端', false, 'tools'),
    new SettingsNode('tools.externalTools', '外部工具', false, 'tools'),
    new SettingsNode('tools.services', '服务', false, 'tools'),
    // 版本控制
    new SettingsNode('versionControl', '版本控制', true, ''),
    new SettingsNode('vcs.git', 'Git', false, 'versionControl'),
    new SettingsNode('vcs.commit', '提交', false, 'versionControl'),
    // 插件 / 其他设置
    new SettingsNode('plugins', '插件', false, ''),
    new SettingsNode('other', '其他设置', true, ''),
    new SettingsNode('other.advanced', '高级设置', false, 'other')
  ];
}

/** 工具窗信息（锚点与名称取 PyCharm 的 toolWindow 注册与中文语言包） */
class ToolWindowInfo {
  id: string;
  label: string;
  anchor: string;
  ready: boolean;

  constructor(id: string, label: string, anchor: string, ready: boolean) {
    this.id = id;
    this.label = label;
    this.anchor = anchor;
    this.ready = ready;
  }
}

/**
 * PyCharm 全部工具窗（34 个，扫自各 jar 的 toolWindow 注册）。
 * ready = 本 IDE 已实现该工具窗的真实内容；否则点开是说明页。
 */
function toolWindows(): ToolWindowInfo[] {
  return [
    // 左侧
    new ToolWindowInfo('Project', '项目', 'left', true),
    new ToolWindowInfo('Structure', 'Structure', 'left', true),
    new ToolWindowInfo('Commit', '提交', 'left', true),
    new ToolWindowInfo('Bookmarks', '书签', 'left', false),
    new ToolWindowInfo('Merge Requests', '合并请求', 'left', false),
    new ToolWindowInfo('Pull Requests', '拉取请求', 'left', false),
    new ToolWindowInfo('Backup and Sync History', '备份与同步历史', 'left', false),
    new ToolWindowInfo('Commit_Guest', '提交（访客）', 'left', false),
    new ToolWindowInfo('Learn', '学习', 'left', true),
    // 右侧
    new ToolWindowInfo('Notifications', '通知', 'right', true),
    new ToolWindowInfo('AIAssistant', 'AI 聊天', 'right', false),
    new ToolWindowInfo('Database', '数据库', 'right', false),
    new ToolWindowInfo('Gradle', 'Gradle', 'right', false),
    new ToolWindowInfo('Maven', 'Maven', 'right', false),
    new ToolWindowInfo('Plots', '绘图', 'right', true),
    new ToolWindowInfo('Python Packages', 'Python 软件包', 'right', true),
    new ToolWindowInfo('Python Console', 'Python 控制台', 'right', true),
    new ToolWindowInfo('Coverage', '覆盖率', 'right', false),
    new ToolWindowInfo('Endpoints', '端点', 'right', false),
    new ToolWindowInfo('SciView', '数据视图', 'right', false),
    new ToolWindowInfo('Jupyter Variables', 'Jupyter 变量', 'right', false),
    new ToolWindowInfo('HfCacheToolWindow', 'Hugging Face', 'right', false),
    new ToolWindowInfo('Remote Host', '远程主机', 'right', false),
    new ToolWindowInfo('Code Provenance', '代码溯源', 'right', false),
    new ToolWindowInfo('Time Tracking', '时间跟踪', 'right', false),
    new ToolWindowInfo('UI Theme Color Picker', '主题配色', 'right', false),
    // 底部
    new ToolWindowInfo('Run', '运行', 'bottom', true),
    new ToolWindowInfo('Version Control', '版本控制', 'bottom', true),
    new ToolWindowInfo('Problems View', '问题', 'bottom', true),
    new ToolWindowInfo('Terminal', '终端', 'bottom', true),
    new ToolWindowInfo('Services', '服务', 'bottom', true),
    new ToolWindowInfo('TODO', 'TODO', 'bottom', true),
    new ToolWindowInfo('PythonProcessOutput', 'Python 进程输出', 'bottom', true),
    new ToolWindowInfo('Database Changes', '数据库更改', 'bottom', false),
    new ToolWindowInfo('File Transfer', '文件传输', 'bottom', false),
    new ToolWindowInfo('Statistics Event Log', '统计事件日志', 'bottom', false)
  ];
}

/** 工具窗占位面板定义（标题 + 工具条按钮 + 空态文案，按钮名取自 PyCharm 的 action group） */
class ToolWindowPanel {
  id: string;
  title: string;
  actions: string[];
  empty: string;
  note: string;

  constructor(id: string, title: string, actions: string[], empty: string, note: string) {
    this.id = id;
    this.title = title;
    this.actions = actions;
    this.empty = empty;
    this.note = note;
  }
}

/**
 * 5 个尚未实现内容的工具窗（PyCharm 里的工具条按钮来自各自的 action group，见 docs/PYCHARM_UI_SURFACES.md）
 */
function toolWindowPanels(): ToolWindowPanel[] {
  return [
    // 按钮依据：Bookmarks.ToolWindow.TitleActions / Bookmarks.ToolWindow.PopupMenu
    new ToolWindowPanel('Bookmarks', '书签',
      ['创建书签列表…', '打开编辑器预览', '删除', '编辑', '上移', '下移'],
      '本工程暂无书签', 'PyCharm 用 F11 切换书签、Ctrl+F11 切换助记键、Shift+F11 打开书签列表。'),
    // 按钮依据：CoverageMenu
    new ToolWindowPanel('Coverage', '覆盖率',
      ['显示代码覆盖率数据(_V)', '生成覆盖率报告(_G)', '隐藏覆盖率'],
      '没有覆盖率数据', 'PyCharm 运行带覆盖率配置后在此按类/文件展示命中率。'),
    // 按钮依据：EndpointsActions.Title / EndpointsActions.FilterToolbar
    new ToolWindowPanel('Endpoints', '端点',
      ['显示服务关系图…', '配置 OpenAPI 规范…'],
      '未检测到端点', 'PyCharm 汇总 Web 框架（Flask/Django/FastAPI）定义的路由端点。'),
    // SciView（数据视图）
    new ToolWindowPanel('SciView', '数据视图',
      ['绘图', '变量'],
      '没有可显示的科学数据', 'PyCharm 的 SciView 展示 matplotlib 图与运行期变量。'),
    // Jupyter Variables
    new ToolWindowPanel('Jupyter Variables', 'Jupyter 变量',
      ['刷新', '导出'],
      '没有 Jupyter 会话', 'PyCharm 的变量表来自 Jupyter/科学模式会话。')
  ];
}

const RIGHT_STRIP_WIDTH: number = 50;
// 与 MenuBarView.MENU_BAR_HEIGHT / ToolBarView.TOOLBAR_HEIGHT 一致（同为 38）
const RIGHT_STRIP_TOP: number = 38;

/** 项目颜色（PyCharm 的 ProjectColorInfo 调色板）：top = 顶栏渐变色，mid = 过渡色 */
class ProjectColor {
  name: string = '';
  top: string = '';
  mid: string = '';
  constructor(name: string, top: string, mid: string) {
    this.name = name;
    this.top = top;
    this.mid = mid;
  }
}
// 严格取自 PyCharm 主题文件 ManyIslandsDarcula.theme.json 的 9 个
// RecentProject.ColorN.MainToolbarGradientStart（即「更改项目颜色」的真实调色板）；
// mid = 该色与窗口底色 main-window-bg(#26282C) 按 55:45 混合，用作渐变的过渡色。
const PROJECT_COLORS: ProjectColor[] = [
  new ProjectColor('颜色 1  #664832', '#664832', '#493A2F'),
  new ProjectColor('颜色 2  #5E4724', '#5E4724', '#453928'),
  new ProjectColor('颜色 3  #45522F', '#45522F', '#373F2E'),
  new ProjectColor('颜色 4  #335661', '#335661', '#2D4149'),
  new ProjectColor('颜色 5  #394773', '#394773', '#303953'),
  new ProjectColor('颜色 6  #613861', '#613861', '#463149'),
  new ProjectColor('颜色 7  #503D70', '#503D70', '#3D3451'),
  new ProjectColor('颜色 8  #325959', '#325959', '#2D4345'),
  new ProjectColor('颜色 9  #365439', '#365439', '#2F4033')
];

/** 随处搜索（SearchEverywhere）的"操作"栏：label|actionId */
/** 作用域视图用的 ast 解析脚本（运行时执行，结果写文件） */
const SCOPE_AST_SCRIPT: string = [
  'import ast, io, sys',
  'src = sys.argv[1]',
  'out = sys.argv[2]',
  'text = io.open(src, encoding=\'utf-8\').read()',
  'tree = ast.parse(text)',
  'defs = []',
  'def walk(node, depth):',
  '    for child in ast.iter_child_nodes(node):',
  '        if isinstance(child, ast.ClassDef):',
  '            bases = [b.id for b in child.bases if isinstance(b, ast.Name)]',
  '            defs.append((\'类\', child.name, child.lineno, depth, (\'继承 \' + \',\'.join(bases)) if bases else \'\'))',
  '            walk(child, depth + 1)',
  '        elif isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):',
  '            nassign = len([n for n in child.body if isinstance(n, (ast.Assign, ast.AnnAssign))])',
  '            ncalls = len([n for n in ast.walk(child) if isinstance(n, ast.Call)])',
  '            args = [a.arg for a in child.args.args]',
  '            kind = \'async 函数\' if isinstance(child, ast.AsyncFunctionDef) else \'函数\'',
  '            defs.append((kind, child.name, child.lineno, depth, \'参数 %d · 局部赋值 %d · 调用 %d\' % (len(args), nassign, ncalls)))',
  '            walk(child, depth + 1)',
  '        else:',
  '            walk(child, depth)',
  'walk(tree, 1)',
  'counts = {}',
  'for node in ast.walk(tree):',
  '    if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):',
  '        counts[node.id] = counts.get(node.id, 0) + 1',
  'rows = [\'模块 \' + src.split(\'/\')[-1] + \'   L1   总行 %d\' % len(text.splitlines())]',
  'for (kind, name, line, depth, extra) in defs:',
  '    nref = counts.get(name, 0)',
  '    rows.append((\'  \' * depth) + kind + \' \' + name + \'   L\' + str(line) + (\'   \' + extra if extra else \'\') + \' · 被引用 %d\' % nref)',
  'target = sys.argv[3] if len(sys.argv) > 3 else \'\'',
  'if target == \'__hierarchy__\':',
  '    src_lines = text.splitlines()',
  '    cls_rows = []',
  '    classes = [n for n in ast.walk(tree) if isinstance(n, ast.ClassDef)]',
  '    for node in classes:',
  '        bases = [b.id for b in node.bases if isinstance(b, ast.Name)]',
  '        cls_rows.append(\'类 %s   L%d   基类 %s\' % (node.name, node.lineno, \', \'.join(bases) if bases else \'(无)\'))',
  '        for sub in node.body:',
  '            if isinstance(sub, (ast.FunctionDef, ast.AsyncFunctionDef)):',
  '                cls_rows.append(\'    方法 %s   L%d\' % (sub.name, sub.lineno))',
  '        for b in bases:',
  '            for other in classes:',
  '                if other.name == b:',
  '                    for sub in other.body:',
  '                        if isinstance(sub, (ast.FunctionDef, ast.AsyncFunctionDef)):',
  '                            cls_rows.append(\'    ← 继承 %s.%s   L%d\' % (b, sub.name, sub.lineno))',
  '    io.open(out, \'w\', encoding=\'utf-8\').write(chr(10).join(cls_rows) if cls_rows else \'(当前文件没有类定义)\')',
  'elif target:',
  '    src_lines = text.splitlines()',
  '    found = []',
  '    for node in ast.walk(tree):',
  '        if isinstance(node, ast.Name) and node.id == target and isinstance(node.ctx, ast.Load):',
  '            found.append(\'L%d   %s\' % (node.lineno, src_lines[node.lineno - 1].strip()))',
  '        elif isinstance(node, ast.Attribute) and node.attr == target:',
  '            found.append(\'L%d   %s\' % (node.lineno, src_lines[node.lineno - 1].strip()))',
  '    found.sort()',
  '    io.open(out, \'w\', encoding=\'utf-8\').write(chr(10).join(found) if found else \'(无用法)\')',
  'else:',
  '    io.open(out, \'w\', encoding=\'utf-8\').write(chr(10).join(rows))',
].join('\n');

/** 依赖清单脚本（运行时执行，输出写到文件）*/
const DEPS_SCRIPT: string = [
  'import io, sys',
  'out = sys.argv[1]',
  'rows = []',
  'try:',
  '    import importlib.metadata as md',
  '    for d in md.distributions():',
  '        try:',
  '            name = d.metadata[\'Name\']',
  '            ver = d.version',
  '            rows.append((name or \'?\') + \'   \' + (ver or \'?\'))',
  '        except Exception:',
  '            pass',
  'except Exception:',
  '    pass',
  'rows.sort(key=lambda s: s.lower())',
  'io.open(out, \'w\', encoding=\'utf-8\').write(chr(10).join(rows) if rows else \'(未发现已安装包)\')',
].join('\n');

/** 工程级 ast 扫描（跨文件）：查符号的定义与用法，或列出全工程的类 */
const PROJECT_AST_SCRIPT: string = [
  'import ast, builtins, io, os, sys',
  'root = sys.argv[1]',
  'out = sys.argv[2]',
  'symbol = sys.argv[3] if len(sys.argv) > 3 else ""',
  'rows = []',
  'files = []',
  'for dirpath, dirnames, filenames in os.walk(root):',
  '    dirnames[:] = [d for d in dirnames if d != ".harmonyide" and not d.startswith(".")]',
  '    for fn in filenames:',
  '        if fn.endswith(".py"):',
  '            files.append(os.path.join(dirpath, fn))',
  'files.sort()',
  'for path in files:',
  '    rel = os.path.relpath(path, root)',
  '    if len(sys.argv) > 4 and sys.argv[4] and rel != sys.argv[4]:',
  '        continue',
  '    try:',
  '        text = io.open(path, encoding="utf-8").read()',
  '        tree = ast.parse(text)',
  '    except Exception:',
  '        continue',
  '    src_lines = text.splitlines()',
  '    if symbol == "__inspect__":',
  '        imported = {}',
  '        for node in ast.walk(tree):',
  '            if isinstance(node, ast.Import):',
  '                for al in node.names:',
  '                    imported[al.asname or al.name.split(".")[0]] = node.lineno',
  '            elif isinstance(node, ast.ImportFrom):',
  '                for al in node.names:',
  '                    imported[al.asname or al.name] = node.lineno',
  '        used = set()',
  '        for node in ast.walk(tree):',
  '            if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):',
  '                used.add(node.id)',
  '        for key in imported:',
  '            if key not in used:',
  '                ln = imported[key]',
  '                if ln <= len(src_lines):',
  '                    rows.append("未使用导入  %s:%d   %s" % (rel, ln, src_lines[ln - 1].strip()))',
  '        seen = {}',
  '        def scan_scope(body, scope):',
  '            for n in body:',
  '                if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):',
  '                    key = scope + "." + n.name',
  '                    if key in seen:',
  '                        rows.append("重复定义  %s:%d   %s（先前定义在第 %d 行）" % (rel, n.lineno, n.name, seen[key]))',
  '                    else:',
  '                        seen[key] = n.lineno',
  '                    if isinstance(n, ast.ClassDef):',
  '                        scan_scope(n.body, key)',
  '        scan_scope(tree.body, "")',
  '        for node in ast.walk(tree):',
  '            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):',
  '                body = [x for x in node.body if not (isinstance(x, ast.Expr) and isinstance(x.value, ast.Constant))]',
  '                if len(body) == 1 and isinstance(body[0], ast.Pass):',
  '                    rows.append("空实现  %s:%d   %s（只有 pass）" % (rel, node.lineno, node.name))',
  '        defined = set(dir(builtins))',
  '        for dunder in ["__name__", "__file__", "__doc__", "__all__", "__dict__", "__class__", "__spec__", "__package__", "__builtins__", "__annotations__"]:',
  '            defined.add(dunder)',
  '        for node in ast.walk(tree):',
  '            if isinstance(node, (ast.Import, ast.ImportFrom)):',
  '                for al in node.names:',
  '                    defined.add((al.asname or al.name).split(".")[0])',
  '            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):',
  '                defined.add(node.name)',
  '            elif isinstance(node, ast.arg):',
  '                defined.add(node.arg)',
  '            elif isinstance(node, ast.Name) and isinstance(node.ctx, (ast.Store, ast.Del)):',
  '                defined.add(node.id)',
  '            elif isinstance(node, (ast.Global, ast.Nonlocal)):',
  '                for nm in node.names:',
  '                    defined.add(nm)',
  '            elif isinstance(node, ast.ExceptHandler) and node.name:',
  '                defined.add(node.name)',
  '        for node in ast.walk(tree):',
  '            if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load) and node.id not in defined:',
  '                rows.append("未定义名字  %s:%d   %s" % (rel, node.lineno, node.id))',
  '        for fn in ast.walk(tree):',
  '            if isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):',
  '                loaded = set()',
  '                for sub in ast.walk(fn):',
  '                    if isinstance(sub, ast.Name) and isinstance(sub.ctx, ast.Load):',
  '                        loaded.add(sub.id)',
  '                declared = set()',
  '                for sub in ast.walk(fn):',
  '                    if isinstance(sub, (ast.Global, ast.Nonlocal)):',
  '                        for nm in sub.names:',
  '                            declared.add(nm)',
  '                for sub in ast.walk(fn):',
  '                    if isinstance(sub, ast.Assign):',
  '                        for tgt in sub.targets:',
  '                            if isinstance(tgt, ast.Name) and tgt.id not in loaded and tgt.id not in declared and not tgt.id.startswith("_"):',
  '                                rows.append("未使用变量  %s:%d   %s" % (rel, tgt.lineno, tgt.id))',
  '                    elif isinstance(sub, ast.AnnAssign) and isinstance(sub.target, ast.Name):',
  '                        nm2 = sub.target.id',
  '                        if nm2 not in loaded and nm2 not in declared and not nm2.startswith("_"):',
  '                            rows.append("未使用变量  %s:%d   %s" % (rel, sub.target.lineno, nm2))',
  '        continue',
  '    if symbol:',
  '        for node in ast.walk(tree):',
  '            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and node.name == symbol:',
  '                rows.append("定义  %s:%d   %s" % (rel, node.lineno, src_lines[node.lineno - 1].strip()))',
  '        for node in ast.walk(tree):',
  '            hit = False',
  '            if isinstance(node, ast.Name) and node.id == symbol and isinstance(node.ctx, ast.Load):',
  '                hit = True',
  '            elif isinstance(node, ast.Attribute) and node.attr == symbol:',
  '                hit = True',
  '            if hit and node.lineno <= len(src_lines):',
  '                rows.append("用法  %s:%d   %s" % (rel, node.lineno, src_lines[node.lineno - 1].strip()))',
  '    else:',
  '        for node in ast.walk(tree):',
  '            if isinstance(node, ast.ClassDef):',
  '                bases = [b.id for b in node.bases if isinstance(b, ast.Name)]',
  '                rows.append("类  %s  %s:%d   基类 %s" % (node.name, rel, node.lineno, ", ".join(bases) if bases else "(无)"))',
  '            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):',
  '                if not node.name.startswith("__"):',
  '                    rows.append("函数  %s  %s:%d" % (node.name, rel, node.lineno))',
  'io.open(out, "w", encoding="utf-8").write(chr(10).join(rows) if rows else "(未找到)")',
].join('\n');

/** 跨文件重命名脚本（ast 精确位置 + 自动备份，可撤销）*/
const RENAME_AST_SCRIPT: string = [
  'import ast, io, os, shutil, sys',
  'root = sys.argv[1]',
  'old = sys.argv[2]',
  'new = sys.argv[3]',
  'backup = sys.argv[4]',
  'out = sys.argv[5]',
  'rows = []',
  'changed = 0',
  'for dirpath, dirnames, filenames in os.walk(root):',
  '    dirnames[:] = [d for d in dirnames if d != ".harmonyide" and not d.startswith(".")]',
  '    for fn in sorted(filenames):',
  '        if not fn.endswith(".py"):',
  '            continue',
  '        path = os.path.join(dirpath, fn)',
  '        rel = os.path.relpath(path, root)',
  '        try:',
  '            text = io.open(path, encoding="utf-8").read()',
  '            tree = ast.parse(text)',
  '        except Exception:',
  '            continue',
  '        lines = text.split(chr(10))',
  '        edits = []',
  '        for node in ast.walk(tree):',
  '            if isinstance(node, ast.Name) and node.id == old:',
  '                edits.append((node.lineno, node.col_offset, node.end_col_offset))',
  '            elif isinstance(node, ast.Attribute) and node.attr == old:',
  '                edits.append((node.lineno, node.end_col_offset - len(old), node.end_col_offset))',
  '            elif isinstance(node, ast.arg) and node.arg == old:',
  '                edits.append((node.lineno, node.col_offset, node.end_col_offset))',
  '            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and node.name == old:',
  '                ln = node.lineno',
  '                col = node.col_offset',
  '                seg = lines[ln - 1][col:]',
  '                idx = seg.find(old)',
  '                if idx >= 0:',
  '                    edits.append((ln, col + idx, col + idx + len(old)))',
  '        if not edits:',
  '            continue',
  '        if not os.path.isdir(backup):',
  '            os.makedirs(backup)',
  '        shutil.copyfile(path, os.path.join(backup, rel.replace("/", "__")))',
  '        byline = {}',
  '        for (ln, a, b) in edits:',
  '            byline.setdefault(ln, []).append((a, b))',
  '        for ln in sorted(byline.keys(), reverse=True):',
  '            spans = sorted(byline[ln], reverse=True)',
  '            s = lines[ln - 1]',
  '            for (a, b) in spans:',
  '                s = s[:a] + new + s[b:]',
  '            lines[ln - 1] = s',
  '        io.open(path, "w", encoding="utf-8").write(chr(10).join(lines))',
  '        rows.append("%s  %d 处" % (rel, len(edits)))',
  '        changed = changed + len(edits)',
  'text_out = (chr(10).join(rows) + (chr(10) + "共 %d 处" % changed)) if rows else "(没有找到需要修改的位置)"',
  'io.open(out, "w", encoding="utf-8").write(text_out)',
  'io.open(os.path.join(backup, "_report.txt"), "w", encoding="utf-8").write(text_out)',
  'print(chr(10).join(rows))',
].join('\n');

/** 撤销重命名：从备份目录还原文件 */
const RENAME_UNDO_SCRIPT: string = [
  'import os, shutil, sys',
  'root = sys.argv[1]',
  'backup = sys.argv[2]',
  'n = 0',
  'if os.path.isdir(backup):',
  '    for fn in sorted(os.listdir(backup)):',
  '        if fn.startswith("_"):',
  '            continue',
  '        src = os.path.join(backup, fn)',
  '        tgt = os.path.join(root, fn.replace("__", "/"))',
  '        if os.path.isfile(src):',
  '            shutil.copyfile(src, tgt)',
  '            n = n + 1',
  'msg = "已还原 %d 个文件" % n if n > 0 else "(没有可还原的备份)"',
  'io.open(sys.argv[3], "w", encoding="utf-8").write(msg)',
  'io.open(os.path.join(backup, "_undo.txt"), "w", encoding="utf-8").write(msg)',
].join('\n');

const SE_ACTIONS: string[] = [
  '转到符号|nav.gotoSymbol', '转到类|nav.gotoClass', '切换器|nav.switcher', '层次结构|nav.hierarchy', '代码检查|code.inspect', '跨文件补全|edit.completeCrossFile', '保存|file.save', '查找用法|edit.findUsages', '重命名符号|refactor.rename', '变更时间线|vcs.fileHistory', '外部系统：任务与依赖|externalSystem.show', '作用域视图|scope.view', '图表|graph.neighborhood', '与剪贴板比较|diff.clipboard', '查看断点|debug.viewBreakpoints', '本地历史记录|history.show', '比较当前文件与磁盘版本|diff.active',
  '循环补全|ed.hippieComplete', '补全语句|ed.completeStatement',
  '撤销|edit.undo', '重做|edit.redo', '全部保存|file.saveAll',
  '在文件中查找|edit.findInFiles', '随处搜索|edit.searchEverywhere', '转到行|nav.gotoLine',
  '重新格式化代码|edit.format', '优化导入|edit.optimizeImports', '注释/取消注释|edit.comment',
  '复制当前行|edit.duplicateLine', '运行|run.run', '调试|run.debug', '停止|run.stop',
  '新建文件|file.newFile', '打开项目|file.openProject', '设置|tools.settings',
  '全部收起|ed.foldAll', '全部展开|ed.unfoldAll', '终端|tools.terminal',
  '最近的文件|view.recentFiles'
];

/** PyCharm 主菜单的顶级菜单（汉堡按钮弹层列出它们） */
const MENU_TITLES: string[] = ['文件(F)', '编辑(E)', '视图(V)', '导航(N)', '代码(C)', '重构(R)',
  '运行(U)', '工具(T)', '版本控制(V)', '窗口(W)', '帮助(H)'];

/** 顶栏右键菜单尺寸（用于自适应定位/翻转；6 项 + 2 分隔 + 内边距） */
const TOP_MENU_WIDTH: number = 252;
const TOP_MENU_HEIGHT: number = 196;
/** 子菜单行高 */
const SUBMENU_ROW: number = 26;

/** PyCharm 项目树里两个固定节点（用 synthetic:// 前缀避免与真实路径冲突） */
const EXT_LIB_PATH: string = 'synthetic://external-libraries';
const SCRATCH_PATH: string = 'synthetic://scratches';
/** 临时文件（scratch）真实落点：应用沙箱 filesDir/scratches */
function scratchDir(): string {
  return `${FileService.context().filesDir}/scratches`;
}

/** 运行配置模型：持久化到 <工程>/runconfig.json（Run → Edit Configurations 轻量版） */
class RunConfigModel {
  name: string = '当前文件';
  script: string = '';
  args: string = '';
  cwd: string = '';
  env: string = '';
}

/** 键盘快捷方式表（帮助 → 键盘快捷方式） */
const SHORTCUT_TABLE: string[] = [
  'F5 / Shift+F10          运行当前文件',
  'Shift+F9                调试当前文件',
  'Shift+F5 / Ctrl+F2      停止运行',
  'Ctrl+S                  保存 / Ctrl+Shift+S 全部保存',
  'Ctrl+Z / Ctrl+Shift+Z   撤销 / 重做',
  'Ctrl+F / Ctrl+R         查找 / 替换',
  'Ctrl+Shift+F            在文件中查找',
  'Ctrl+Shift+N            转到文件',
  'Ctrl+Alt+Shift+N        转到符号',
  'Ctrl+G                  转到行',
  'Ctrl+/                  注释 / 取消注释',
  'Ctrl+D                  复制当前行',
  'Ctrl+Alt+L              格式化代码',
  'Ctrl+Alt+O              优化导入',
  'Alt+1                   项目工具窗',
  'Alt+4                   运行窗口 / Python 控制台',
  'Alt+F12                 终端',
  'Ctrl+E                  最近文件',
  'Ctrl+W                  关闭标签页',
  'Ctrl+Alt+S              设置',
  'Ctrl+Alt+T              切换深色 / 浅色主题'
];

/** 第三方组件与许可（与 docs/LICENSES.md 对应） */
const LICENSE_TABLE: string[] = [
  'CPython 3.12.10               PSF License 2.0',
  'pip 24.x                      MIT License',
  'JetBrains Mono 字体            SIL Open Font License 1.1',
  'OpenHarmony / ArkTS SDK       Apache License 2.0',
  'zlib / bz2 / lzma / sqlite3   各组件自带许可（Apache / BSD 系列）',
  '',
  '完整文本见工程内 docs/LICENSES.md'
];

@Entry
@Component
struct Index {
  // ── 主题与设置 ─────────────────────────────────────────────────────────
  @State theme: PyTheme = DARCULA;
  @State themeName: string = 'darcula';
  @State settings: AppSettings = new AppSettings();
  @State layoutSize: string = LayoutSize.EXPANDED;
  /** 根容器实际宽度（vp）：右竖条绝对定位用 */
  @State windowWidth: number = 0;
  /** 左右竖条宽度（对应 ui.lnf.xml 的 TOOL_WINDOW_LEFT/RIGHT_SIDE_CUSTOM_WIDTH，
   *  可拖拽调整并用 PersistentStorage 持久化） */
  @StorageLink('leftStripWidth') leftStripW: number = 50;
  /** 拖拽起点宽度（竖条调宽用） */
  @State dragStartW: number = 0;
  /** 工程目录监听（native inotify） */
  private dirWatcher: DirWatcher = new DirWatcher();
  @StorageLink('rightStripWidth') rightStripW: number = 50;
  /** 右侧工具窗面板宽度（可拖拽，持久化） */
  @StorageLink('rightPanelWidth') rightPanelW: number = 320;
  /** 当前打开的右侧工具窗 id（空 = 关闭）。PyCharm 右侧工具窗是内嵌面板 */
  @State rightToolWindow: string = '';
  /** 根容器实际高度（vp）：右竖条/分屏窗格定位用 */
  @State windowHeight: number = 0;

  // ── 运行时 ─────────────────────────────────────────────────────────────
  @State runtime: RuntimeStatus = new RuntimeStatus(false, '', '', false, '正在初始化运行时…');
  @State running: boolean = false;
  @State loading: boolean = true;

  // ── 工程 ───────────────────────────────────────────────────────────────
  @State projectRoot: string = '';
  @State projectName: string = '';
  @State treeRoots: FileNode[] = [];
  @State flatNodes: FileNode[] = [];
  @State filterText: string = '';
  @State selectedPath: string = '';
  /** 每次「在项目树中定位」+1，ProjectTreeView 用它把目标行滚进可视区 */
  @State locateTick: number = 0;
  /** 是否已运行过（运行按钮显示三角 → 圈圈箭头） */
  @State hasRunOnce: boolean = false;
  /** 齿轮菜单「压缩目录」（PyCharm: Compact Middle Packages）：只有一个子目录的链合并成一行。
   *  PyCharm 里该项**默认开启**，所以这里默认 true。 */
  @State treeCompactDirs: boolean = true;
  /** 齿轮菜单「文件夹总在最前」（PyCharm: Folders Always on Top）：排序时目录优先 */
  @State treeDirsFirst: boolean = true;
  // ── ProjectView.ToolWindow.Behavior/Appearance.Actions（LangActions.xml:700-742）──
  /** ProjectView.OpenInPreviewTab 启用预览标签页 */
  @State optPreviewTab: boolean = true;
  /** ProjectView.AutoscrollToSource 一键打开文件（关 → 单击只选中） */
  @State optSingleClickOpen: boolean = true;
  /** ProjectView.OpenDirectoriesWithSingleClick 一键打开目录 */
  @State optOpenDirsSingle: boolean = true;
  /** ProjectView.AutoscrollFromSource 始终选择打开的文件 */
  @State optAutoscrollFromSource: boolean = false;
  /** ProjectView.ShowExcludedFiles 显示排除的文件 */
  @State optShowExcluded: boolean = false;
  /** ProjectView.ShowScratchesAndConsoles 显示临时文件和控制台 */
  @State optShowScratches: boolean = true;

  // ── 编辑器 ─────────────────────────────────────────────────────────────
  @State tabs: EditorTab[] = [];
  @State activeTabId: string = '';
  @State editorSeedText: string = '';
  @State editorFilePath: string = '';
  @State cursorLine: number = 1;
  @State cursorColumn: number = 1;
  @State search: SearchState = new SearchState();
  @State pendingBreakpoints: number[] = [];

  // ── 调试会话 ───────────────────────────────────────────────────────────
  @State debugging: boolean = false;
  @State debugPaused: boolean = false;
  @State debugFile: string = '';
  @State debugLine: number = 0;
  /** 面包屑里当前悬停的段（-1 表示没有） */
  @State breadcrumbHover: number = -1;
  @State debugFunc: string = '';
  @State debugLocals: string[][] = [];
  @State debugStack: string[][] = [];
  /** Evaluate（PyCharm）：输入表达式 + 求值历史 */
  @State evalText: string = '';
  @State debugEvals: string[] = [];
  /** 重命名重构：目标符号 + 报告 */
  @State renameTarget: string = '';
  @State renameRows: string[] = [];

  /** 跨文件补全：当前文件导入的模块 + 选中模块的成员 */
  @State completeModules: string[] = [];
  @State completeMembers: string[] = [];
  @State completeModule: string = '';

  /** 检查范围：是否只查当前文件 */
  @State inspectOnlyFile: boolean = false;

  /** 当前文件的问题行（gutter 警示标）*/
  @State warnLines: number[] = [];

  /** 问题工具窗的行 */
  @State problemRows: string[] = [];

  /** 全工程检查结果（未使用导入等）*/
  @State inspectRows: string[] = [];

  /** Structure 面板范围：file = 当前文件；project = 全工程 */
  @State structureScope: string = 'file';
  @State projectPanelRows: string[] = [];

  /** 全工程类（跨文件转到类）*/
  @State classRows: string[] = [];

  /** 全工程符号（类/函数 + 所在文件行）*/
  @State projectSymbols: string[] = [];

  /** 继承层级（ast 版）：类/基类/方法/继承来的方法 */
  @State astHierRows: string[] = [];

  /** 查找用法：当前选中的符号 + 用法行 */
  @State usagesSymbol: string = '';
  @State usagesRows: string[] = [];

  /** 变更时间线（Vcs.FileHistory）：显示行 + 对应快照路径 */
  @State timelineRows: string[] = [];
  @State timelinePaths: string[] = [];

  /** 外部系统（ExternalSystem）：依赖清单行 + 外部任务执行结果行 */
  @State extRows: string[] = [];

  /** 作用域视图（ScopeView）：AST 解析出的作用域树行 */
  @State scopeRows: string[] = [];

  /** 图表（Graph/Neighborhood）：节点与边 + Canvas 上下文 */
  @State graphNodes: string[] = [];
  @State graphEdges: string[] = [];
  @State graphLayout: string = 'tree';
  /** 边样式（PyCharm Graph.EdgeRealizerGroup：直线/折线）*/
  @State graphEdgeStyle: string = 'straight';
  /** 布局方向（TreeLayoutGroup：上下/左右）*/
  @State graphDir: string = 'v';
  /** 缩放（DefaultGraphToolbar：放大/缩小/适应）*/
  @State graphZoom: number = 1.0;
  /** 外观（Graph.AppearanceGroup）：显示标签 / 配色方案 */
  @State graphShowLabels: boolean = true;
  @State graphPalette: number = 0;
  private graphCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  /** 点节点跳转用：记录每个节点的命中框 "名字|x|y|w|h" */
  private graphBoxes: string[] = [];

  /** Watches（监视表达式）：表达式 + 最近一次求值结果 */
  @State watches: string[] = [];
  @State watchValues: string[] = [];
  /** 「在文件中查找」结果（path:line: text） */
  @State searchResults: string[] = [];
  /** 视图菜单的显示开关（对应 PyCharm 的 View → Appearance 一组） */
  @State showMainToolbar: boolean = true;
  @State showSideStrip: boolean = true;
  @State showStatusBar: boolean = true;
  // PyCharm：编辑器面包屑（导航栏）默认显示
  @State showBreadcrumb: boolean = true;
  @State showIndentGuides: boolean = false;
  @State isFullScreen: boolean = false;
  @State splitRight: boolean = false;
  /** 文件结构（PyCharm 的 Structure）符号列表 */
  @State structureSymbols: string[] = [];
  /** 展开中的菜单标题与弹层位置（菜单弹层由页面级渲染，否则点不到） */
  @State menuOpenTitle: string = '';
  @State menuPopupX: number = 0;
  /** 左右竖条当前选中的工具窗 id（PyCharm New UI 的 tool window 选中态） */
  @State sideKind: string = 'project';
  /** 竖条 hover 中的项（hover 灰底，选中蓝底） */
  @State sideHover: string = '';
  /** 两条分隔条是否被悬停（悬停高亮，提示可拖动调整区域大小） */
  @State leftDividerHover: boolean = false;
  @State bottomDividerHover: boolean = false;
  @State rightDividerHover: boolean = false;
  /** 左侧 Project / Structure 的高度比例（可拖拽，持久化） */
  @StorageLink('leftSplitRatio') leftSplitRatio: number = 0.6;
  @State hDividerHover: boolean = false;
  /** 拖拽起始值（无级调节：起始值 + 位移，不能每帧叠加累计位移） */
  @State dragStartPanelW: number = 0;
  @State dragStartRatio: number = 0;
  /** 通知中心（PyCharm 的 Notifications 工具窗：带时间戳的事件日志） */
  @State notifications: string[] = [];
  /** 通用信息面板（服务/版本控制/通知等） */
  @State infoTitle: string = '';
  @State infoLines: string[] = [];
  /** Structure 工具窗内容（PyCharm 左下方常驻） */
  @State liveStructure: string[] = [];
  /** 工程里是否存在 VCS（.git）：与 PyCharm 一致，没有版本控制时竖条不显示「提交」 */
  @State hasVcs: boolean = false;
  /**
   * 当前活动窗格：PyCharm 里只有「工具窗被选中且获得焦点」时竖条项才是蓝色药丸，
   * 焦点在编辑器时同样的选中项显示为灰色药丸（实测截图两种状态都存在）。
   */
  @State activePane: string = 'tool';
  /** 工程树长按菜单：目标路径与弹层位置（页面级渲染，bindMenu 在部分版本不弹） */
  /**
   * 顶栏右键/长按菜单。依据 PyCharm 的 <group id="MainToolbarPopupActions">（PlatformActions.xml:1030）：
   *   ViewToolBar  → 工具栏(_T)（显示/隐藏主工具栏，文案见 ActionsBundle.properties: action.ViewToolBar.text）
   *   CustomizeUI  → 自定义菜单与工具栏…（action.CustomizeUIAction.text）
   */
  @State topMenuShown: boolean = false;
  @State topMenuX: number = 0;
  @State topMenuY: number = 0;
  /** 当前展开的子菜单：'' / 'quick'（将操作添加到主工具栏）/ 'menu'（主菜单模式）/ 'color'（更改项目颜色） */
  @State topSubmenu: string = '';
  /** 显示项目渐变（ColoredHeaderAction，勾选项）：控制顶栏那层项目色渐变 */
  @State projectTintOn: boolean = true;
  /** 当前项目色（由「更改项目颜色」子菜单设置；默认为 PyCharm 实机测得的顶部绿 #334B35） */
  // 默认 = ManyIslandsDarcula 的 RecentProject.Color9.MainToolbarGradientStart
  @State projectTint: string = '#365439';
  @State projectTintMid: string = '#2F4033';
  /**
   * 主菜单显示模式（ChangeMainMenuModeActionGroup，文案取自 PyCharm 界面）：
   *   'hamburger' 隐藏在汉堡按钮下方 / 'merged' 与主工具栏合并 / 'above' 显示在主工具栏上方
   */
  // PyCharm 默认就是 UNDER_HAMBURGER_BUTTON（MainMenuDisplayMode 枚举首项）
  @State menuMode: string = 'hamburger';
  /** 汉堡按钮是否已横向展开菜单（PyCharm: ide.main.menu.expand.horizontal） */
  @State hamburgerShown: boolean = false;
  /** 兼容旧代码：菜单栏是否单独占一行 */
  @State menuOwnRow: boolean = false;
  /** 自定义项目图标（WelcomeScreen.ChangeProjectIcon）：空 = 用默认 ideaProject 图标 */
  @State projectIcon: string = '';
  /** 已「添加到主工具栏」的快捷操作（MainToolbarQuickActions 的子项） */
  @State extraToolbar: string[] = [];
  /** 随处搜索（SearchEverywhere）：查询词与命中项（"文件|path" / "操作|label|actionId"） */
  @State seQuery: string = '';
  @State seHits: string[] = [];
  @State treeMenuPath: string = '';
  @State treeMenuX: number = 0;
  @State treeMenuY: number = 0;
  /** 代码折叠（PyCharm FoldingGroup）：已折叠项，格式 `path#line`（按文件持久化，切文件自动恢复） */
  @State foldedStarts: string[] = [];
  /** 控制台右键 = PyCharm ConsoleView.PopupMenu（10 项） */
  @State consoleMenuShown: boolean = false;
  @State consoleMenuX: number = 0;
  @State consoleMenuY: number = 0;
  /** 结构视图右键 = PyCharm StructureViewPopupMenu（22 项） */
  @State structMenuShown: boolean = false;
  @State structMenuX: number = 0;
  @State structMenuY: number = 0;
  /** 被右键的结构符号名（去掉 'ƒ  '/'C  ' 前缀） */
  @State structMenuSymbol: string = '';
  /** 面包屑右键 = PyCharm NavbarPopupMenu（37 项） */
  @State navMenuShown: boolean = false;
  @State navMenuX: number = 0;
  @State navMenuY: number = 0;
  // 导航栏显隐统一用 showBreadcrumb（View → 显示导航栏 与 面包屑右键 共用）
  /** 项目树排序方式（ProjectView.Sort.Actions：name/type/timeDesc/timeAsc/manual） */
  @State treeSortBy: string = 'name';
  /** 编辑器内右键菜单位置（EditorPopupMenu） */
  @State editorMenuX: number = 0;
  @State editorMenuY: number = 0;
  @State editorMenuShown: boolean = false;
  /** 工具窗标题右键菜单（ToolWindowContextMenu） */
  @State twMenuShown: boolean = false;
  /** 当前展示的占位工具窗 id（书签/覆盖率/端点/数据视图/Jupyter 变量） */
  @State twPanelId: string = 'Bookmarks';
  /** 运行时设备形态：tablet / 2in1 / phone（用于自适应与「关于」信息） */
  @State deviceKind: string = '';
  /** 运行时窗口模式：全屏 / 分屏 / 悬浮窗口 */
  @State windowMode: string = '';
  /** 最近打开的文件（PyCharm 的 最近的文件(_N)，Ctrl+E） */
  @State recentFiles: string[] = [];
  /** 随处搜索（SearchEverywhere）：查询词与分栏 */
  @State swQuery: string = '';
  @State swColumn: string = 'all';
  @State recentShown: boolean = false;
  /** 分屏第二窗格：绑定的标签 + 独立控制器（真实可编辑） */
  @State splitTabId: string = '';
  @State secondController: CodeEditorController = new CodeEditorController();
  /** 运行配置（PyCharm 的 Run → Edit Configurations 轻量版，落盘持久化） */
  @State cfgName: string = '当前文件';
  @State cfgScript: string = '';
  @State cfgArgs: string = '';
  @State cfgCwd: string = '';
  @State cfgEnv: string = '';
  /** 「转到文件 / 转到符号」对话框 */
  @State gotoMode: string = 'file';
  @State gotoItems: string[] = [];
  @State gotoPaths: string[] = [];
  /** 导航历史（pyCharm 的后退/前进） */
  @State navHistory: string[] = [];
  @State navIndex: number = -1;

  // ── 控制台 ─────────────────────────────────────────────────────────────
  @State logEntries: LogEntry[] = [];
  @State consoleTab: string = 'run';
  /** ConsoleView.PopupMenu: PauseOutput —— 暂停时新输出进入缓冲区 */
  @State consolePaused: boolean = false;
  @State consolePending: LogEntry[] = [];
  @State statusMessage: string = '就绪';
  @State problems: number = 0;

  // ── 弹窗 ───────────────────────────────────────────────────────────────
  @State dialog: string = '';
  @State dialogTitle: string = '';
  @State inputValue: string = '';
  @State dialogTarget: string = '';
  @State projectList: string[] = [];
  @State toast: string = '';

  private editorController: CodeEditorController = new CodeEditorController();
  private logSeq: number = 0;
  private toastTimer: number = -1;
  private autoSaveTimer: number = -1;
  private uiContext: common.UIAbilityContext | undefined = undefined;
  private outputListener: (stream: number, text: string) => void = (stream: number, text: string) => {
    this.appendOutput(stream, text);
  };
  private debugListener: (pause: DebugPause) => void = (pause: DebugPause) => {
    this.onDebugPause(pause);
  };

  // ── 生命周期 ───────────────────────────────────────────────────────────

  aboutToAppear(): void {
    // 竖条宽度持久化（对应 ui.lnf.xml 的 TOOL_WINDOW_LEFT/RIGHT_SIDE_CUSTOM_WIDTH）
    PersistentStorage.persistProp('leftStripWidth', 50);
    PersistentStorage.persistProp('rightStripWidth', 50);
    // 所有可拖拽调整的尺寸都持久化（重启后保持，不是固定值）
    PersistentStorage.persistProp('rightPanelWidth', 320);
    PersistentStorage.persistProp('leftSplitRatio', 0.6);
    try {
      this.uiContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch (err) {
      this.uiContext = undefined;
    }
    if (this.uiContext === undefined) {
      this.runtime = new RuntimeStatus(false, '', '', false, '无法获取应用上下文，IDE 无法访问沙箱目录。');
      this.loading = false;
      return;
    }

    FileService.attach(this.uiContext);

    // 运行时识别设备形态：平板(tablet) / 鸿蒙 PC(2in1) / 手机(phone)
    // 依据 deviceInfo.deviceType（module.json5 已声明 deviceTypes: tablet + 2in1）
    try {
      this.deviceKind = deviceInfo.deviceType;
      FileService.log(`deviceType=${this.deviceKind} model=${deviceInfo.productModel} `
        + `osApi=${deviceInfo.sdkApiVersion}`);
    } catch (err) {
      this.deviceKind = 'unknown';
    }
    // 读取窗口模式（全屏/分屏/悬浮），PC 上通常是自由窗口
    try {
      window.getLastWindow(this.uiContext).then((w: window.Window) => {
        try {
          const st: window.WindowStatusType = w.getWindowStatus();
          if (st === window.WindowStatusType.FLOATING) {
            this.windowMode = '悬浮窗口';
          } else if (st === window.WindowStatusType.SPLIT_SCREEN) {
            this.windowMode = '分屏';
          } else if (st === window.WindowStatusType.MAXIMIZE) {
            this.windowMode = '最大化';
          } else if (st === window.WindowStatusType.FULL_SCREEN) {
            this.windowMode = '全屏';
          } else {
            this.windowMode = '自由窗口';
          }
          FileService.log(`windowStatus=${this.windowMode}`);
        } catch (e2) {
          this.windowMode = '';
        }
      }).catch(() => {
        this.windowMode = '';
      });
    } catch (err) {
      this.windowMode = '';
    }

    // 注册随包代码字体。不注册的话 ArkUI 会静默回退成比例字体，代码区会很"不像 IDE"。
    try {
      font.registerFont({
        familyName: PyFont.mono,
        familySrc: $rawfile('fonts/JetBrainsMono-Regular.ttf')
      });
      font.registerFont({
        familyName: PyFont.monoBold,
        familySrc: $rawfile('fonts/JetBrainsMono-Bold.ttf')
      });
    } catch (err) {
      this.appendError(`注册代码字体失败（将回退到系统字体）：${JSON.stringify(err)}`);
    }
    this.settings = SettingsService.init(this.uiContext);
    // 折叠状态恢复（按文件持久化）
    this.foldedStarts = this.settings.foldedFolds.length > 0
      ? this.settings.foldedFolds.split(',') : [];
    // 多窗格布局恢复
    this.paneSplit = this.settings.paneSplit;
    this.pane2Tabs = this.settings.pane2Tabs.length > 0 ? this.settings.pane2Tabs.split(',') : [];
    this.paneRatio = this.settings.paneRatio;
    this.paneBefore = this.settings.paneBefore;
    this.recentFiles = this.settings.recentFiles.length > 0
      ? this.settings.recentFiles.split(',') : [];
    this.themeName = this.settings.themeName;
    this.theme = themeByName(this.themeName === 'light' ? 'light' : 'darcula');

    this.openInitialProject();
    // 开机自检：把几个"点击路径难自动化"的功能各跑一遍并写日志，作为可查证的证据链
    setTimeout(() => {
      this.logFeatureSelfCheck();
    }, 5000);

    PyRuntimeService.addDebugListener(this.debugListener);

    // 运行时初始化在工作线程上异步完成，这里不阻塞首帧
    this.warmupRuntime();
  }

  aboutToDisappear(): void {
    PyRuntimeService.removeOutputListener(this.outputListener);
    PyRuntimeService.removeDebugListener(this.debugListener);
    SettingsService.save(this.settings);
    PyRuntimeService.shutdown();
  }

  /** 初始化 Python 运行时并刷新界面状态 */
  private async warmupRuntime(): Promise<void> {
    if (this.uiContext === undefined) {
      return;
    }
    PyRuntimeService.addOutputListener(this.outputListener);
    this.runtime = await PyRuntimeService.bootstrap(this.uiContext);
    this.loading = false;
    this.setStatus(this.runtime.ready ? 'Python 运行时已就绪' : 'Python 运行时未就绪（文件管理等功能可用）');
    if (this.runtime.ready) {
      this.appendSystem(`Python ${this.runtime.version} (${this.runtime.abi}) on HarmonyOS  [内嵌 CPython]`);
      this.appendSystem('标准库来自随包 python312.zip；pip 用「--no-index --find-links」离线安装。');
      this.appendSystem('Type "help", "copyright", "credits" or "license" for more information.');
      this.appendSystem('');
      this.appendSystem('提示：F5 运行当前文件 · 在行号槽点击设断点 · 工具栏「调试」启动调试会话');
    } else {
      this.appendError(this.runtime.message);
    }
  }

  // ── 工程与文件树 ───────────────────────────────────────────────────────

  /** 清理早期版本遗留在工程目录里的中间文件（.harmonyide 与元文件）*/
  private cleanLegacyArtifacts(projectDir: string): void {
    if (projectDir.length === 0) {
      return;
    }
    const dir: string = `${projectDir}/.harmonyide`;
    if (FileService.exists(dir)) {
      FileService.remove(dir);
    }
    for (const meta of ['_undo.txt', '_report.txt']) {
      const mp: string = `${projectDir}/${meta}`;
      if (FileService.exists(mp)) {
        FileService.remove(mp);
      }
    }
  }

  private openInitialProject(): void {
    // 工具窗可见性**不跨会话持久化**：启动时一律可见。
    // 之前它被写进设置，用户一旦把项目栏收起来，重启后依然是"编辑区空 + 项目栏不见"的死状态。
    this.settings.showLeftToolWindow = true;
    // PyCharm 默认不开底部工具窗（运行/调试时才自动弹出），启动时同样不占位置
    this.settings.showBottomToolWindow = false;
    this.dialog = '';
    const root: string = FileService.projectRoot();
    FileService.ensureDir(root);
    // 注意：FileService.projectRoot() 是 PyProjects 父目录，真正的工程目录在下面才知道（last / sample）
    const last: string = this.settings.lastProjectRoot;
    if (last.length > 0 && FileService.isDir(last)) {
      // 示例工程自愈：版本升级后新增的示例文件要补齐（createSampleProject 内是逐文件存在性判断，幂等）
      // 只对示例工程做，避免往用户自己的工程里注入示例文件
      this.cleanLegacyArtifacts(last);
      FileService.log(`sample heal check last=${last} isSample=${last.indexOf('示例工程') >= 0}`);
      if (last.indexOf('示例工程') >= 0) {
        FileService.createSampleProject(last);
        FileService.log(`sample heal done models=${FileService.exists(`${last}/demo_pkg/models.py`)}`);
      }
      this.loadProject(last);
      return;
    }
    const sample: string = `${root}/示例工程`;
    this.cleanLegacyArtifacts(sample);
    FileService.createSampleProject(sample);
    this.loadProject(sample);
  }

  /** 记录最近打开的文件（去重、最新在前、最多 20 个） */
  private rememberRecent(path: string): void {
    const next: string[] = [path];
    for (let i = 0; i < this.recentFiles.length && next.length < 20; i++) {
      if (this.recentFiles[i] !== path) {
        next.push(this.recentFiles[i]);
      }
    }
    this.recentFiles = next;
    this.settings.recentFiles = next.join(',');
    SettingsService.save(this.settings);
  }

  private loadProject(path: string): void {
    this.projectRoot = path;
    this.projectName = FileService.baseName(path);
    // 与 PyCharm 一致：只有工程里有 .git 时才显示「提交」工具窗
    this.hasVcs = FileService.exists(`${path}/.git`) || FileService.exists(`${path}/.hg`)
      || FileService.exists(`${path}/.svn`);
    this.settings.lastProjectRoot = path;
    SettingsService.save(this.settings);
    const roots: FileNode[] = FileService.listDir(path, 1);
    FileService.log(`loadProject path=${path} roots=${roots.length}`);
    // PyCharm 的工程树第一行是工程本身（名字 + 灰色路径），所以包一层根节点
    const rootNode = new FileNode(FileService.baseName(path), path, true, 0);
    rootNode.expanded = true;
    rootNode.loaded = true;
    rootNode.children = roots;
    this.treeRoots = [rootNode];
    this.refreshFlatten();
    FileService.log(`loadProject flatNodes=${this.flatNodes.length}`);
    this.tabs = [];
    this.activeTabId = '';
    const entry: string = `${path}/main.py`;
    FileService.log(`loadProject entry exists=${FileService.exists(entry)}`);
    if (FileService.exists(entry)) {
      this.openFile(entry, 'main.py');
    } else if (roots.length > 0) {
      const first: FileNode = this.firstFile(roots);
      if (first.path.length > 0) {
        this.openFile(first.path, first.name);
      } else {
        // 兜底：工程里没有可直接打开的 .py（例如只有未展开的目录）。
        // 不兜底的话编辑器只会显示欢迎页——用户看到的就是"编辑区不显示"。
        FileService.createFile(entry, this.newFileTemplate('main.py'));
        this.treeRoots = FileService.listDir(path, 0);
        this.refreshFlatten();
        this.openFile(entry, 'main.py');
      }
    } else {
      // 空工程同样给一个可编辑文件，保证"打开即有代码"
      FileService.createFile(entry, this.newFileTemplate('main.py'));
      this.treeRoots = FileService.listDir(path, 0);
      this.refreshFlatten();
      this.openFile(entry, 'main.py');
    }
    // 工程目录监听（native inotify）：外部改动（终端 mv/cp、pip 安装）立刻反映到树里
    this.startProjectWatch();
  }

  private firstFile(nodes: FileNode[]): FileNode {
    for (const node of nodes) {
      if (!node.isDir) {
        return node;
      }
      const nested: FileNode = this.firstFile(node.children);
      if (nested.path.length > 0) {
        return nested;
      }
    }
    return new FileNode('', '', false, 0);
  }

  /** 重建工程树根节点（名字 + 路径 + 一层子节点），保证刷新后根节点还在 */
  private makeRootNode(): FileNode {
    const rootNode = new FileNode(this.projectName, this.projectRoot, true, 0);
    rootNode.expanded = true;
    rootNode.loaded = true;
    rootNode.children = FileService.listDir(this.projectRoot, 1);
    return rootNode;
  }

  /** 递归设置展开态 */
  private setAllExpanded(node: FileNode, value: boolean): void {
    node.expanded = value;
    for (const child of node.children) {
      this.setAllExpanded(child, value);
    }
  }

  /** 递归把子目录内容也加载出来（"全部展开"用） */
  private loadAllChildren(node: FileNode): void {
    if (!node.isDir) {
      return;
    }
    if (!node.loaded) {
      FileService.loadChildren(node);
    }
    for (const child of node.children) {
      this.loadAllChildren(child);
    }
  }

  /** 全部折叠（根节点保持展开，与 PyCharm 一致） */
  private collapseAllNodes(): void {
    for (const root of this.treeRoots) {
      this.setAllExpanded(root, false);
      root.expanded = true;
    }
    this.refreshFlatten();
    this.treeRoots = this.treeRoots.slice();
    this.flatNodes = this.flatNodes.slice();
  }

  /** 全部展开 */
  private expandAllNodes(): void {
    for (const root of this.treeRoots) {
      this.loadAllChildren(root);
      this.setAllExpanded(root, true);
    }
    this.refreshFlatten();
    this.treeRoots = this.treeRoots.slice();
    this.flatNodes = this.flatNodes.slice();
  }

  /** 从磁盘重新读取某个标签页（丢弃未保存修改），供「从磁盘重新加载」用 */
  private reloadTab(tab: EditorTab): void {
    try {
      const content: string = FileService.readText(tab.path);
      tab.updateText(content);
      tab.dirty = false;
      if (tab.id === this.activeTabId) {
        this.editorSeedText = content;
        this.editorFilePath = tab.path;
      }
    } catch (err) {
      this.appendError(`重新加载失败：${tab.path}\n${JSON.stringify(err)}`);
    }
  }

  /** 统计工程内文件数（pyOnly=true 时只数 .py） */
  private countFiles(pyOnly: boolean): number {
    const flat: FileNode[] = [];
    FileService.flatten(this.treeRoots, flat);
    let count: number = 0;
    for (const node of flat) {
      if (!node.isDir && (!pyOnly || node.name.endsWith('.py'))) {
        count++;
      }
    }
    return count;
  }

  /** 打开「在文件中查找」对话框（先用当前查找词预填） */
  private openFindInFiles(seed: string): void {
    this.searchResults = [];
    this.inputValue = seed;
    this.dialog = 'findInFiles';
  }

  /** 在工程所有 .py 里做纯文本搜索（PyCharm 的 Ctrl+Shift+F 的轻量版） */
  private runFindInFiles(): void {
    const query: string = this.inputValue.trim();
    this.searchResults = [];
    if (query.length === 0) {
      this.showToast('请输入要查找的内容');
      return;
    }
    const flat: FileNode[] = [];
    FileService.flatten(this.treeRoots, flat);
    let hits: number = 0;
    for (const node of flat) {
      if (node.isDir || !node.name.endsWith('.py')) {
        continue;
      }
      let content: string = '';
      try {
        content = FileService.readText(node.path);
      } catch (err) {
        continue;
      }
      const lines: string[] = content.split('\n');
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].indexOf(query) >= 0) {
          this.searchResults.push(`${node.path}:${i + 1}: ${lines[i].trim().substring(0, 80)}`);
          hits++;
          if (hits >= 200) {
            break;
          }
        }
      }
      if (hits >= 200) {
        break;
      }
    }
    this.tabs = this.tabs.slice();
    this.setStatus(`在文件中查找「${query}」：${this.searchResults.length} 处`);
    if (this.searchResults.length === 0) {
      this.appendSystem(`在文件中查找「${query}」：没有匹配。`);
    }
  }

  /** 全屏切换（PyCharm 的 View → Appearance → Full Screen）：真调系统窗口 API */
  private toggleFullScreen(): void {
    this.isFullScreen = !this.isFullScreen;
    const wantFull: boolean = this.isFullScreen;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window) => {
        win.setWindowLayoutFullScreen(wantFull);
        FileService.log(`fullscreen -> ${wantFull}`);
      }).catch((err: Object) => {
        FileService.log(`fullscreen FAILED err=${JSON.stringify(err)}`);
      });
    } catch (err) {
      FileService.log(`fullscreen FAILED err=${JSON.stringify(err)}`);
    }
    this.setStatus(wantFull ? '已进入全屏' : '已退出全屏');
  }

  /** 打开「转到文件 / 转到符号」对话框：文件名或全工程符号（都带过滤输入） */
  private openGoto(mode: string): void {
    this.gotoMode = mode;
    this.inputValue = '';
    this.gotoItems = [];
    this.gotoPaths = [];
    const flat: FileNode[] = [];
    FileService.flatten(this.treeRoots, flat);
    if (mode === 'file') {
      for (const node of flat) {
        if (!node.isDir && node.name.endsWith('.py')) {
          this.gotoItems.push(`${node.name}    ${node.path}`);
          this.gotoPaths.push(`${node.path}|0`);
        }
      }
    } else {
      for (const node of flat) {
        if (node.isDir || !node.name.endsWith('.py')) {
          continue;
        }
        let content: string = '';
        try {
          content = FileService.readText(node.path);
        } catch (err) {
          continue;
        }
        const lines: string[] = content.split('\n');
        for (let i = 0; i < lines.length; i++) {
          const line: string = lines[i].trim();
          let kind: string = '';
          let start: number = 0;
          if (line.startsWith('class ')) {
            kind = '类  ';
            start = 6;
          } else if (line.startsWith('def ')) {
            kind = '函数';
            start = 4;
          } else if (line.startsWith('async def ')) {
            kind = '函数';
            start = 10;
          }
          if (kind.length > 0) {
            const name: string = this.identifierAfter(line, start);
            if (name.length > 0) {
              this.gotoItems.push(`${kind}  ${name}    ${node.name}:${i + 1}`);
              this.gotoPaths.push(`${node.path}|${i + 1}`);
            }
          }
        }
      }
    }
    if (this.gotoItems.length === 0) {
      this.gotoItems.push('（没有可跳转的目标）');
      this.gotoPaths.push('|0');
    }
    this.dialog = 'goto';
  }

  /** 跳到 path|line 目标 */
  private navigateTo(entry: string): void {
    const sep: number = entry.lastIndexOf('|');
    if (sep <= 0) {
      return;
    }
    const path: string = entry.substring(0, sep);
    const line: number = Number.parseInt(entry.substring(sep + 1), 10);
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined || tab.path !== path) {
      this.openFile(path, FileService.baseName(path));
    }
    if (line > 0) {
      this.editorController.revealLine(line);
    }
    // 记录导航历史，供「后退 / 前进」使用
    const entryNew: string = `${path}|${line > 0 ? line : 1}`;
    if (this.navIndex < 0 || this.navHistory[this.navIndex] !== entryNew) {
      if (this.navIndex < this.navHistory.length - 1) {
        this.navHistory = this.navHistory.slice(0, this.navIndex + 1);
      }
      this.navHistory.push(entryNew);
      if (this.navHistory.length > 100) {
        this.navHistory.shift();
      }
      this.navIndex = this.navHistory.length - 1;
    }
    this.setStatus(`已定位到 ${FileService.baseName(path)}${line > 0 ? `:${line}` : ''}`);
  }

  /** 记录一次导航位置（打开文件/跳转时调用） */
  private pushNavHistory(): void {
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined) {
      return;
    }
    const entry: string = `${tab.path}|${this.cursorLine}`;
    if (this.navIndex >= 0 && this.navHistory[this.navIndex] === entry) {
      return;
    }
    if (this.navIndex < this.navHistory.length - 1) {
      this.navHistory = this.navHistory.slice(0, this.navIndex + 1);
    }
    this.navHistory.push(entry);
    if (this.navHistory.length > 100) {
      this.navHistory.shift();
    }
    this.navIndex = this.navHistory.length - 1;
  }

  /** 「转到文件 / 转到符号」对话框内容（带过滤） */
  @Builder
  GotoContent() {
    Column() {
      TextInput({
        placeholder: this.gotoMode === 'file' ? '按文件名过滤' : '按符号名过滤',
        text: this.inputValue
      })
        .width('100%')
        .height(28)
        .fontSize(12)
        .fontFamily(PyFont.mono)
        .fontColor(this.theme.textPrimary)
        .caretColor(this.theme.caret)
        .backgroundColor(this.theme.inputBg)
        .borderRadius(4)
        .onChange((value: string) => {
          this.inputValue = value;
        })

      Scroll() {
        Column() {
          ForEach(this.filteredGoto(), (row: string, index: number) => {
            Text(row)
              .fontSize(12)
              .fontFamily(PyFont.mono)
              .fontColor(this.theme.textPrimary)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ top: 5, bottom: 5 })
              .onClick(() => {
                const target: string = this.gotoTargetOf(row);
                if (target.length > 0) {
                  this.navigateTo(target);
                  this.dialog = '';
                }
              })
          }, (row: string, index: number) => `${index}-${row}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .height(240)
      .width('100%')
      .margin({ top: 8 })
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 按 inputValue 过滤后的候选行 */
  private filteredGoto(): string[] {
    const needle: string = this.inputValue.trim().toLowerCase();
    if (needle.length === 0) {
      return this.gotoItems;
    }
    const out: string[] = [];
    for (const row of this.gotoItems) {
      if (row.toLowerCase().indexOf(needle) >= 0) {
        out.push(row);
      }
    }
    return out;
  }

  /** 由显示行反查 path|line 目标 */
  private gotoTargetOf(row: string): string {
    const index: number = this.gotoItems.indexOf(row);
    if (index >= 0 && index < this.gotoPaths.length) {
      return this.gotoPaths[index];
    }
    return '';
  }

  /** 标签栏 ⋮ 菜单的展开状态与弹层位置（页面级渲染，保证可点） */
  @State tabMenuShown: boolean = false;
  /** 最近关闭的标签页路径（EditorTabPopupMenu: ReopenClosedTab） */
  @State lastClosedPath: string = '';
  /** 编辑器右上 ⋮ = PyCharm 的 TabList（TabListAction，显示所有标签页） */
  @State tabListShown: boolean = false;
  /** TabList → 最近的位置（Recent Locations）："path#line" 列表，最新在前 */
  @State recentLocations: string[] = [];
  /** TabList → 书签（Bookmarks）："path#line" 列表 */
  @State bookmarks: string[] = [];
  /** TabList → 显示缩略图（开启后在弹层里列出打开标签的缩略预览） */
  @State tabThumbnails: boolean = false;
  @State tabMenuX: number = 0;
  @State tabMenuY: number = 0;

  /** 标签栏 ⋮ 菜单里的每一项 */
  @Builder
  tabMenuItem(id: string, label: string, shortcut: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
        .maxLines(1)
      Text(shortcut)
        .fontSize(11)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textSecondary)
    }
    .width('100%')
    .height(26)
    .padding({ left: 12, right: 12 })
    .onClick(() => {
      this.tabMenuShown = false;
      this.onTabMenuPick(id);
    })
  }

  /** TabList（编辑器右上 ⋮）里的每一项：派发到 onTabListPick */
  @Builder
  tabListItem(id: string, label: string, shortcut: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
        .maxLines(1)
      Text(shortcut)
        .fontSize(11)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textSecondary)
    }
    .width('100%')
    .height(26)
    .padding({ left: 12, right: 12 })
    .onClick(() => {
      this.onTabListPick(id);
    })
  }

  /** 最近文件弹层（PyCharm 的最近的文件(_N) / Ctrl+E） */
  @Builder
  RecentFilesLayer() {
    Column() {
      Text('最近的文件')
        .fontSize(11)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textSecondary)
        .width('100%')
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      if (this.recentFiles.length === 0) {
        Text('没有最近打开的文件')
          .fontSize(12)
          .fontFamily(PyFont.ui)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 10, right: 10, top: 4, bottom: 8 })
      } else {
        ForEach(this.recentFiles, (p: string) => {
          Row() {
            IconAsset({ iconSize: 14, file: fileIconOf(FileService.baseName(p)) })
            Text(FileService.baseName(p))
              .fontSize(12.5)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textPrimary)
              .margin({ left: 8 })
            Text(p)
              .fontSize(11)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textDisabled)
              .margin({ left: 8 })
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .height(26)
          .padding({ left: 10, right: 10 })
          .onClick(() => {
            this.recentShown = false;
            this.openFile(p, FileService.baseName(p));
          })
        }, (p: string) => p)
      }
    }
    .width(420)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    // 主题：popup-border = layer-1-border = gray-40 #33353B
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(this.theme.popupArc)
        .clip(true)
    .position({ x: 120, y: 56 })
  }

  /**
   * 顶栏右键菜单。PyCharm 的 <group id="MainToolbarPopupActions"> 只有两项：
   *   ViewToolBar（工具栏(_T)，勾选项） / CustomizeUI（自定义菜单与工具栏…）
   */
  @Builder
  TopBarContextMenu() {
    Column() {
      // ── 严格按 <group id="ToolbarPopupActions.MainToolbarNewUI">（PlatformActions.xml:1864）──
      this.topRow('将操作添加到主工具栏', 'quick', true, false)
      this.topRow('主菜单', 'menu', true, false)
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.topRow('更改项目颜色', 'color', true, false)
      this.topRow('设置自定义项目图标…', 'top.icon', false, false)
      this.topRow('显示项目渐变', 'top.tint', false, this.projectTintOn)
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.topRow('将主菜单与窗口标题合并…', 'top.merge', false, false)
    }
    .width(TOP_MENU_WIDTH)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(6)
    .position({ x: this.topMenuX, y: this.topMenuY })
    .onClick(() => {})   // 吞掉点击，避免冒泡到遮罩立刻关闭
  }

  /** 顶栏菜单的一行：label + 子菜单箭头 / 勾选态 */
  @Builder
  topRow(label: string, id: string, hasSub: boolean, checked: boolean) {
    Row() {
      if (checked) {
        Text('✓').fontSize(11).width(14).fontColor(this.theme.accent)
      } else {
        Row().width(14)
      }
      Text(label)
        .fontSize(12.5)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
        .maxLines(1)
      if (hasSub) {
        Text('›').fontSize(13).fontColor(this.theme.textSecondary)
      }
    }
    .width('100%')
    .height(SUBMENU_ROW)
    .padding({ left: 8, right: 10 })
    .backgroundColor(this.topSubmenu === id ? this.theme.toolHoverBg : Color.Transparent)
    .onClick(() => {
      if (hasSub) {
        this.topSubmenu = this.topSubmenu === id ? '' : id;
        return;
      }
      this.topMenuShown = false;
      this.topSubmenu = '';
      if (id === 'top.tint') {
        this.projectTintOn = !this.projectTintOn;
        FileService.log(`project gradient on=${this.projectTintOn}`);
        this.setStatus(this.projectTintOn ? '已显示项目渐变' : '已关闭项目渐变');
        return;
      }
      this.handleAction(id);
    })
  }

  /** 子菜单：将操作添加到主工具栏（MainToolbarQuickActionsRaw 的三项） */
  @Builder
  TopQuickSubmenu() {
    Column() {
      this.subItem('后退/前进', () => this.addToMainToolbar('backforward'))
      this.subItem('构建', () => this.addToMainToolbar('build'))
      this.subItem('全部保存', () => this.addToMainToolbar('saveall'))
    }
    .width(180)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(6)
    .position({ x: this.submenuX(), y: this.topMenuY + 4 })
  }

  /** 子菜单：主菜单模式（ChangeMainMenuModeActionGroup） */
  @Builder
  TopMenuModeSubmenu() {
    Column() {
      this.subItem(this.menuMode === 'hamburger' ? '✓ 隐藏在汉堡按钮下方' : '隐藏在汉堡按钮下方', () => {
        this.setMenuMode('hamburger');
      })
      this.subItem(this.menuMode === 'merged' ? '✓ 与主工具栏合并' : '与主工具栏合并', () => {
        this.setMenuMode('merged');
      })
      this.subItem(this.menuMode === 'above' ? '✓ 显示在主工具栏上方' : '显示在主工具栏上方', () => {
        this.setMenuMode('above');
      })
    }
    .width(180)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(6)
    .position({ x: this.submenuX(), y: this.topMenuY + 4 + SUBMENU_ROW })
  }

  /** 子菜单：更改项目颜色（ProjectColorInfo 的项目色） */
  @Builder
  TopColorSubmenu() {
    Column() {
      ForEach(PROJECT_COLORS, (c: ProjectColor) => {
        this.subItem(c.name, () => {
          this.projectTint = c.top;
          this.projectTintMid = c.mid;
          this.topMenuShown = false;
          FileService.log(`project color -> ${c.top}`);
          this.setStatus(`项目颜色：${c.name}`);
        })
      }, (c: ProjectColor) => c.top)
    }
    .width(180)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(6)
    .position({ x: this.submenuX(), y: this.topMenuY + 4 + 2 * SUBMENU_ROW + 9 })
  }

  /** 子菜单里的一行 */
  @Builder
  subItem(label: string, run: () => void) {
    Row() {
      Text(label)
        .fontSize(12.5)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
        .maxLines(1)
    }
    .width('100%')
    .height(SUBMENU_ROW)
    .padding({ left: 10, right: 10 })
    .onClick(run)
  }

  /** 工程树长按菜单（依据 PyCharm ProjectViewPopupMenu 原文） */
  @Builder
  TreeContextMenu() {
    // 条目已达 33 项（~860vp）> 窗口高度 → 必须可滚动，否则底部条目被裁
    Scroll() {
    Column() {
      // ── 依据 ProjectViewPopupMenu（deduped 40 项）逐条对齐 ──
      this.tabMenuItem('tree.newFile', '新建文件', '')
      this.tabMenuItem('tree.newFolder', '新建文件夹', '')
      // WeighingNewGroup（新建组）展开
      this.tabMenuItem('tree.newPyFile', '新建 Python 文件', '')
      this.tabMenuItem('tree.newPackage', '新建 Python 包', '')
      this.tabMenuItem('tree.newScratch', '新建临时文件', '')
      this.tabMenuItem('tree.associateType', '与文件类型关联…', '')
      this.tabMenuItem('tree.restoreExt', '恢复默认扩展名', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('tree.editSource', '编辑源', '')
      this.tabMenuItem('tree.cut', '剪切(_T)', 'Ctrl+X')
      this.tabMenuItem('tree.copy', '复制(_C)', 'Ctrl+C')
      this.tabMenuItem('tree.copyPath', '复制路径(_O)', 'Ctrl+Shift+C')
      this.tabMenuItem('tree.paste', '粘贴(_P)', 'Ctrl+V')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('tree.findUsages', '查找用法', 'Alt+F7')
      this.tabMenuItem('tree.findInFiles', '在文件中查找', 'Ctrl+Shift+F')
      this.tabMenuItem('tree.replaceInFiles', '在文件中替换…', 'Ctrl+Shift+R')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('tree.refactor', '重构…', 'Ctrl+Alt+Shift+T')
      this.tabMenuItem('tree.rename', '重命名(_R)…', 'Shift+F6')
      // ProjectViewPopupMenuRefactoringGroup > RefactoringMenu 展开
      this.tabMenuItem('tree.changeSignature', '更改签名…', 'Ctrl+F6')
      this.tabMenuItem('tree.introduceConstant', '引入常量…', 'Ctrl+Alt+C')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('tree.reformat', '重新格式化代码', 'Ctrl+Alt+L')
      this.tabMenuItem('tree.optimizeImports', '优化导入', 'Ctrl+Alt+O')
      this.tabMenuItem('tree.changeLang', '更改文件语言', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('tree.run', '运行', 'Shift+F10')
      this.tabMenuItem('tree.debug', '调试', 'Shift+F9')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('tree.openInRightSplit', '在右侧拆分中打开', '')
      this.tabMenuItem('tree.splitChooser', '在拆分中打开…', '')
      this.tabMenuItem('tree.revealHere', '在此处显示', '')
      this.tabMenuItem('tree.openAssociated', '在关联的应用程序中打开', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('tree.vcsHistory', '显示历史', '')
      this.tabMenuItem('tree.vcsCommit', '提交…', 'Ctrl+K')
      this.tabMenuItem('tree.vcsPush', '推送…', 'Ctrl+Shift+K')
      this.tabMenuItem('tree.vcsPull', '拉取…', 'Ctrl+T')
      this.tabMenuItem('tree.cacheRecovery', '刷新项目（缓存恢复）', '')
      this.tabMenuItem('tree.reload', '从磁盘重新加载', 'Ctrl+Alt+Y')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('tree.goToLinkTarget', '转到链接目标', '')
      this.tabMenuItem('tree.compareTwoFiles', '比较文件', '')
      this.tabMenuItem('tree.compareWithEditor', '与编辑器比较', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('tree.externalTools', '外部工具', '')
      this.tabMenuItem('tree.viewSettings', '项目视图设置…', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('tree.delete', '删除(_D)', 'Delete')
    }
    .width('100%')
    }
    .width(230)
    .constraintSize({ maxHeight: 560 })
    .scrollBar(BarState.Auto)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(this.theme.popupArc)
    .clip(true)
    .position({ x: this.treeMenuX, y: this.treeMenuY })
  }

  /**
   * 可折叠区域（Python 惯用块）：返回 "起始行:结束行" 列表。
   * 依据缩进：def/class/if/elif/else/for/while/try/except/finally/with 的块体；
   * 另支持 # region … # endregion。
   */
  private foldRegions(): string[] {
    const out: string[] = [];
    const lines: string[] = this.editorSeedText.split('\n');
    const starts: RegExp = /^(def |class |async def |if |elif |else|for |while |try|except|finally|with )/;
    let regionStart: number = 0;
    for (let i = 0; i < lines.length; i++) {
      const raw: string = lines[i];
      const t: string = raw.trim();
      const indent: number = raw.length - raw.replace(/^\s+/, '').length;
      // # region … # endregion
      if (t.startsWith('# region')) {
        regionStart = i + 1;
        continue;
      }
      if (t.startsWith('# endregion') && regionStart > 0) {
        if (i + 1 > regionStart + 1) {
          out.push(`${regionStart}:${i + 1}`);
        }
        regionStart = 0;
        continue;
      }
      if (!starts.test(t)) {
        continue;
      }
      // 找块体最后一行：后续行缩进 > 本行缩进 的连续段
      let last: number = i + 1;
      for (let j = i + 1; j < lines.length; j++) {
        const r2: string = lines[j];
        if (r2.trim().length === 0) {
          continue;
        }
        const ind2: number = r2.length - r2.replace(/^\s+/, '').length;
        if (ind2 <= indent) {
          break;
        }
        last = j + 1;
      }
      if (last > i + 1) {
        out.push(`${i + 1}:${last}`);
      }
    }
    return out;
  }

  /** 多窗格编辑器（0.21 计划第 1 步：模型）——paneSplit: none | h | v；pane2Tabs: 第二窗格里的标签 id */
  @State paneSplit: string = 'none';
  @State pane2Tabs: string[] = [];
  @State paneRatio: number = 0.5;
  /** 新窗格是否放在前侧（向左/向上拆分 = true）——PyCharm SplitChooser 的 SplitLeft/SplitTop */
  @State paneBefore: boolean = false;
  /** 断点列表（XDebugger: View Breakpoints）：显示行 + 对应文件路径 + 行号 */
  @State bpRows: string[] = [];
  @State bpKeys: string[] = [];
  @State bpLines: number[] = [];

  /** 本地历史（Local History）：快照行显示 + 对应文件路径 */
  @State historyRows: string[] = [];
  @State historyPaths: string[] = [];

  /** 差异比较（Diff）：行列表 + 增删计数 + 两侧名字 */
  @State diffRows: string[] = [];
  @State diffAdded: number = 0;
  @State diffRemoved: number = 0;
  @State diffLeftName: string = '';
  @State diffRightName: string = '';

  /** 多窗格分隔条悬停（PyCharm：splitter 悬停时高亮） */
  @State paneDividerHover: boolean = false;
  // 复用已有的 dragStartRatio（第 437 行）：手势起点记录当前比例，offsetX/offsetY 是相对起点的累计值

  /** 转到符号（GoToSymbol）：查询词 */
  @State symbolQuery: string = '';

  /** CodeMenu：Hippie 循环补全的候选与游标 */
  @State hippieCandidates: string[] = [];
  @State hippieIndex: number = 0;

  /** 编辑器选区（字符偏移），CollapseSelection 用 */
  @State selStartSel: number = 0;
  @State selEndSel: number = 0;

  /** 字符偏移 → 行号（1 基） */
  private lineOfOffset(offset: number): number {
    const text: string = this.editorSeedText;
    const limit: number = Math.max(0, Math.min(offset, text.length));
    let line: number = 1;
    for (let i = 0; i < limit; i++) {
      if (text.charCodeAt(i) === 10) {
        line++;
      }
    }
    return line;
  }

  /** FoldingGroup > CollapseSelection：折叠与选区相交的块（选区为空时退化为折叠当前块） */
  private collapseSelection(): void {
    const l1: number = this.lineOfOffset(Math.min(this.selStartSel, this.selEndSel));
    const l2: number = this.lineOfOffset(Math.max(this.selStartSel, this.selEndSel));
    const added: string[] = [];
    const path: string = this.activePathKey();
    const next: string[] = this.foldedStarts.slice();
    for (const r of this.foldRegions()) {
      const parts: string[] = r.split(':');
      const s: number = Number.parseInt(parts[0], 10);
      const e: number = Number.parseInt(parts[1], 10);
      if (Number.isNaN(s) || Number.isNaN(e)) {
        continue;
      }
      if (s <= l2 && e >= l1 && e > s) {
        const key: string = `${path}#${s}`;
        if (next.indexOf(key) < 0) {
          next.push(key);
          added.push(key);
        }
      }
    }
    if (added.length === 0) {
      const s: number = this.foldStartAtCursor();
      if (s === 0) {
        this.showToast('选区/光标处没有可折叠的块');
        return;
      }
      const key: string = `${path}#${s}`;
      if (next.indexOf(key) < 0) {
        next.push(key);
      }
    }
    this.foldedStarts = next;
    this.persistFolds();
    this.setStatus(`已折叠选区内的代码块（第 ${l1}-${l2} 行）`);
  }

  /** 开机自检：日志形式输出几个功能的实际结果（便于无需点击即可验证） */
  private logFeatureSelfCheck(): void {
    try {
      const hier: string[] = this.classHierarchy();
      FileService.log(`selfcheck hierarchy rows=${hier.length} :: ${hier.join(' ; ').slice(0, 120)}`);
      // 非空路径：用工程里带 class 的文件再验一次
      const altPath: string = `${this.projectRoot}/demo_pkg/core/engine.py`;
      try {
        const altText: string = FileService.readText(altPath);
        const altRows: string[] = this.parseHierarchy(altText);
        FileService.log(`selfcheck hierarchy(engine.py) rows=${altRows.length} :: ${altRows.join(' ; ').slice(0, 140)}`);
      } catch (e2) {
        FileService.log('selfcheck hierarchy(engine.py) skipped');
      }
      // 单元验证：直接喂一段已知类片段，断言解析结果（不依赖工程里是否存在 class）
      const sample: string = 'class Animal:\n    pass\n\nclass Dog(Animal):\n    pass\n\nclass Cat(Animal, Mixin):\n    pass\n';
      const sampleRows: string[] = this.parseHierarchy(sample);
      FileService.log(`selfcheck hierarchy(sample) rows=${sampleRows.length} :: ${sampleRows.join(' ; ')}`);
      const regions: string[] = this.foldRegions();
      FileService.log(`selfcheck foldRegions=${regions.length} :: ${regions.join(',').slice(0, 120)}`);
      const words: RegExpMatchArray | null = this.editorSeedText.match(/[A-Za-z_][A-Za-z0-9_]*/g);
      let cand: string[] = [];
      if (words !== null) {
        for (const w of words) {
          if (w.startsWith('gr') && w !== 'gr' && cand.indexOf(w) < 0) {
            cand.push(w);
          }
        }
      }
      FileService.log(`selfcheck hippie prefix=gr candidates=${cand.length} :: ${cand.slice(0, 5).join(',')}`);
      // 入口可达性自检：SE 首屏（可视约 5 项）实际是哪几项 —— 新增入口挤掉旧入口时立刻暴露
      const firstLabels: string[] = [];
      for (let i: number = 0; i < SE_ACTIONS.length && i < 6; i++) {
        firstLabels.push(SE_ACTIONS[i].split('|')[0]);
      }
      FileService.log(`selfcheck seFirst=${firstLabels.join(' / ')}`);
      FileService.log(`selfcheck seActions=${SE_ACTIONS.length} tabs=${this.tabs.length} recentFiles=${this.recentFiles.length}`);
      FileService.log(`selfcheck panes split=${this.paneSplit} pane2=${this.pane2Tabs.length} ratio=${this.paneRatio} before=${this.paneBefore}`);
      const dr: string[] = this.diffLines('a\nb\nc\nd', 'a\nx\nc\nd\ne');
      let add: number = 0;
      let rem: number = 0;
      for (const r of dr) {
        if (r.charAt(0) === '+') {
          add++;
        } else if (r.charAt(0) === '-') {
          rem++;
        }
      }
      FileService.log(`selfcheck diff rows=${dr.length} removed=${rem} added=${add}`);
      // 本地历史统计（每个文件保留上限 20）
      try {
        const hdir: string = this.historyDirFor(this.editorFilePath);
        const nodes: FileNode[] = FileService.exists(hdir) ? FileService.listDir(hdir, 1) : [];
        let cnt: number = 0;
        for (const n of nodes) {
          if (!n.isDir && n.name.startsWith('snap_')) {
            cnt++;
          }
        }
        FileService.log(`selfcheck history snapshots=${cnt} retainMax=20 dir=${hdir}`);
      } catch (e) {
        FileService.log('selfcheck history unavailable');
      }
    } catch (e) {
      FileService.log(`selfcheck failed ${JSON.stringify(e)}`);
    }
  }

  /** 多窗格：向右/向下拆分（把当前标签移入新窗格）——PyCharm ChangeEditorSplitAction */
  private splitEditor(orientation: string, before: boolean = false, ratio: number = 0.5): void {
    const t: EditorTab | undefined = this.activeTab();
    if (t === undefined) {
      this.showToast('没有可拆分的编辑器');
      return;
    }
    if (this.pane2Tabs.indexOf(t.id) < 0) {
      const next: string[] = this.pane2Tabs.slice();
      next.push(t.id);
      this.pane2Tabs = next;
    }
    this.paneSplit = orientation;
    this.paneBefore = before;
    this.paneRatio = ratio;
    this.persistPanes();
    this.setStatus(`已${orientation === 'h' ? '向右' : '向下'}拆分：标签 ${t.name} 移入第 2 窗格`);
  }

  /** 多窗格布局落盘（重启后保持） */
  private persistPanes(): void {
    this.settings.paneSplit = this.paneSplit;
    this.settings.pane2Tabs = this.pane2Tabs.join(',');
    this.settings.paneRatio = this.paneRatio;
    this.settings.paneBefore = this.paneBefore;
    SettingsService.save(this.settings);
  }

  /** 多窗格：取消拆分（第 2 窗格标签回到第 1 窗格） */
  private unsplitEditor(all: boolean): void {
    if (this.paneSplit === 'none') {
      this.setStatus('当前没有拆分');
      return;
    }
    this.paneSplit = 'none';
    this.pane2Tabs = [];
    this.persistPanes();
    this.setStatus(all ? '已全部取消拆分' : '已取消拆分');
  }

  /** 本地历史目录：<工程根>/.harmonyide/history/<文件名的哈希编码>/ */
  private historyDirFor(path: string): string {
    return `${FileService.context().filesDir}/.harmonyide/history/${this.historyHashOf(path)}`;
  }

  /** 毫秒时间戳 → 可读时间（本地历史/时间线显示用）*/
  private formatStamp(ms: number): string {
    if (Number.isNaN(ms) || ms <= 0) {
      return '未知时间';
    }
    const d: Date = new Date(ms);
    const p2: (n: number) => string = (n: number) => n < 10 ? `0${n}` : `${n}`;
    return `${p2(d.getMonth() + 1)}-${p2(d.getDate())} ${p2(d.getHours())}:${p2(d.getMinutes())}:${p2(d.getSeconds())}`;
  }

  /** 与 historyDirFor 同一套哈希（时间线用它反查旧目录属于哪个文件）*/
  private historyHashOf(path: string): string {
    let h: number = 0;
    for (let i: number = 0; i < path.length; i++) {
      h = (h * 31 + path.charCodeAt(i)) % 1000000007;
    }
    return `${h}`;
  }

  /** 保存前把磁盘上的旧内容快照进本地历史（内容相同则不重复快照）*/
  private snapshotBeforeSave(path: string): void {
    try {
      if (!FileService.exists(path)) {
        return;
      }
      const old: string = FileService.readText(path);
      const dir: string = this.historyDirFor(path);
      FileService.ensureDir(dir);
      const nodes: FileNode[] = FileService.listDir(dir, 1);
      let newest: string = '';
      let newestTime: number = 0;
      for (const n of nodes) {
        if (!n.isDir && n.name.startsWith('snap_')) {
          const t: number = Number.parseInt(n.name.substring(5, 18), 10);
          if (!Number.isNaN(t) && t > newestTime) {
            newestTime = t;
            newest = `${dir}/${n.name}`;
          }
        }
      }
      if (newest.length > 0 && FileService.readText(newest) === old) {
        return;
      }
      FileService.writeText(`${dir}/snap_${Date.now()}.txt`, old);
      // 记录该目录属于哪个源文件：变更时间线（Vcs.FileHistory 语义）需要
      FileService.writeText(`${dir}/path.txt`, path);
      FileService.log(`local history snapshot ${path}`);
      // 保留策略：每个文件最多 20 个快照，超出则删最旧的（避免无限增长）
      const all: FileNode[] = FileService.listDir(dir, 1);
      const snaps: FileNode[] = [];
      for (const n of all) {
        if (!n.isDir && n.name.startsWith('snap_')) {
          snaps.push(n);
        }
      }
      if (snaps.length > 20) {
        snaps.sort((x: FileNode, y: FileNode) => x.name < y.name ? -1 : 1);
        const drop: number = snaps.length - 20;
        for (let i: number = 0; i < drop; i++) {
          FileService.remove(`${dir}/${snaps[i].name}`);
        }
        FileService.log(`local history pruned ${drop}`);
      }
    } catch (e) {
      FileService.log(`snapshot failed ${JSON.stringify(e)}`);
    }
  }

  /** 变更时间线（Vcs.FileHistory 语义）：汇总工程内所有文件的历史版本，按时间倒序 */
  private openChangeTimeline(): void {
    const root: string = `${FileService.context().filesDir}/.harmonyide/history`;
    if (!FileService.exists(root)) {
      this.showToast('暂无历史快照（每次保存前会自动记录）');
      return;
    }
    const rows: string[] = [];
    const paths: string[] = [];
    // 兜底映射：早期快照目录没写 path.txt，用「路径哈希」反查工程内的 .py 文件
    const hashToPath: Map<string, string> = new Map<string, string>();
    const projectFiles: FileNode[] = FileService.listDir(this.projectRoot, 8);
    for (const nd of projectFiles) {
      if (!nd.isDir && nd.name.endsWith('.py')) {
        hashToPath.set(this.historyHashOf(nd.path), nd.path);
      }
    }
    const dirs: FileNode[] = FileService.listDir(root, 1);
    for (const d of dirs) {
      if (!d.isDir) {
        continue;
      }
      const dirPath: string = `${root}/${d.name}`;
      let src: string = '';
      if (FileService.exists(`${dirPath}/path.txt`)) {
        src = FileService.readText(`${dirPath}/path.txt`).trim();
      }
      const mapped: string | undefined = hashToPath.get(d.name);
      if (src.length === 0 && mapped !== undefined) {
        src = mapped;
      }
      const base: string = src.length > 0 ? src.substring(src.lastIndexOf('/') + 1) : d.name;
      const snaps: FileNode[] = FileService.listDir(dirPath, 1);
      for (const s of snaps) {
        if (s.isDir || !s.name.startsWith('snap_')) {
          continue;
        }
        const ts: string = this.formatStamp(Number.parseInt(s.name.substring(5, 24), 10));
        let lines: number = 0;
        try {
          lines = FileService.readText(`${dirPath}/${s.name}`).split('\n').length;
        } catch (e) {
          lines = 0;
        }
        rows.push(`${ts}   ${base}   ${lines} 行`);
        paths.push(`${dirPath}/${s.name}`);
      }
    }
    // 时间倒序（时间戳字符串可直接比较）
    const pairs: string[][] = [];
    for (let i: number = 0; i < rows.length; i++) {
      pairs.push([rows[i], paths[i]]);
    }
    pairs.sort((a: string[], b: string[]) => a[0] < b[0] ? 1 : -1);
    const outRows: string[] = [];
    const outPaths: string[] = [];
    for (const p of pairs) {
      outRows.push(p[0]);
      outPaths.push(p[1]);
    }
    this.timelineRows = outRows;
    this.timelinePaths = outPaths;
    this.dialogTitle = `变更时间线（${outRows.length} 个版本）`;
    this.dialog = 'timeline';
    this.setStatus(`变更时间线：${outRows.length} 个历史版本`);
  }

  /** 用某个历史快照与该文件当前内容做差异（Vcs.FileHistory 的双击比较语义）*/
  private compareSnapshotWithFile(snapPath: string): void {
    const dir: string = snapPath.substring(0, snapPath.lastIndexOf('/'));
    const srcPath: string = FileService.exists(`${dir}/path.txt`) ? FileService.readText(`${dir}/path.txt`).trim() : '';
    let before: string = '';
    let after: string = '';
    try {
      before = FileService.readText(snapPath);
      after = srcPath.length > 0 && FileService.exists(srcPath) ? FileService.readText(srcPath) : this.editorSeedText;
    } catch (e) {
      this.showToast('读取历史版本失败');
      return;
    }
    const diff: string[] = this.diffLines(before, after);
    let add: number = 0;
    let rem: number = 0;
    for (const r of diff) {
      if (r.charAt(0) === '+') {
        add++;
      } else if (r.charAt(0) === '-') {
        rem++;
      }
    }
    this.diffRows = diff;
    this.diffAdded = add;
    this.diffRemoved = rem;
    this.diffLeftName = '历史版本';
    this.diffRightName = srcPath.length > 0 ? srcPath.substring(srcPath.lastIndexOf('/') + 1) : '当前内容';
    this.dialogTitle = `差异：历史版本 ↔ ${this.diffRightName}`;
    this.dialog = 'diffView';
    this.setStatus(`历史版本比较：+${add} 行 / -${rem} 行`);
  }

  /** 打开当前文件的本地历史 */
  private openLocalHistory(): void {
    const path: string = this.editorFilePath;
    if (path.length === 0) {
      this.showToast('当前没有打开的文件');
      return;
    }
    const dir: string = this.historyDirFor(path);
    const nodes: FileNode[] = FileService.exists(dir) ? FileService.listDir(dir, 1) : [];
    const rows: string[] = [];
    const paths: string[] = [];
    const items: FileNode[] = [];
    for (const n of nodes) {
      if (!n.isDir && n.name.startsWith('snap_')) {
        items.push(n);
      }
    }
    items.sort((x: FileNode, y: FileNode) => y.name < x.name ? -1 : 1);
    for (const n of items) {
      const full: string = `${dir}/${n.name}`;
      let lines: number = 0;
      try {
        lines = FileService.readText(full).split('\n').length;
      } catch (e) {
        lines = 0;
      }
      rows.push(`${this.formatStamp(Number.parseInt(n.name.substring(5, 24), 10))}   ${lines} 行`);
      paths.push(full);
    }
    this.historyRows = rows;
    this.historyPaths = paths;
    this.dialogTitle = `本地历史：${path.substring(path.lastIndexOf('/') + 1)}（${rows.length} 个快照）`;
    this.dialog = 'localHistory';
  }

  /** 构建当前文件的关系图：节点（类/函数/基类）+ 边（继承/调用）*/
  private buildGraph(): void {
    const text: string = this.editorSeedText;
    const lines: string[] = text.split('\n');
    const funcs: string[] = [];
    const classes: string[] = [];
    const nodes: string[] = [];
    const edges: string[] = [];
    // 记录每个 def/class 所处的缩进与名字，便于按"调用名"找边
    for (const raw of lines) {
      const t: string = raw.trim();
      const mc: RegExpMatchArray | null = t.match(/^class\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(([^)]*)\))?\s*:/);
      if (mc !== null) {
        classes.push(mc[1]);
        if (nodes.indexOf(mc[1]) < 0) {
          nodes.push(mc[1]);
        }
        const bases: string = mc[2] === undefined ? '' : mc[2];
        for (const b of bases.split(',')) {
          const base: string = b.trim();
          if (base.length > 0) {
            if (nodes.indexOf(base) < 0) {
              nodes.push(base);
            }
            edges.push(`${mc[1]}>${base}`);
          }
        }
        continue;
      }
      const mf: RegExpMatchArray | null = t.match(/^def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/);
      if (mf !== null) {
        funcs.push(mf[1]);
        if (nodes.indexOf(mf[1]) < 0) {
          nodes.push(mf[1]);
        }
      }
    }
    // 函数调用边：函数体内出现其它已知函数名 + '('
    let current: string = '';
    for (const raw of lines) {
      const t: string = raw.trim();
      const mf: RegExpMatchArray | null = t.match(/^def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/);
      if (mf !== null) {
        current = mf[1];
        continue;
      }
      if (current.length === 0) {
        continue;
      }
      for (const fn of funcs) {
        if (fn !== current && new RegExp(`\\b${fn}\\s*\\(`).test(t)) {
          const e: string = `${current}>${fn}`;
          if (edges.indexOf(e) < 0) {
            edges.push(e);
          }
        }
      }
    }
    this.graphNodes = nodes;
    this.graphEdges = edges;
    this.setStatus(`关系图：${nodes.length} 个节点 / ${edges.length} 条边（类继承 + 函数调用）`);
  }

  /** 在 Canvas 上画关系图（简单分层布局）*/
  private drawGraph(): void {
    const ctx: CanvasRenderingContext2D = this.graphCtx;
    ctx.clearRect(0, 0, 1000, 400);
    const nodes: string[] = this.graphNodes;
    const n: number = nodes.length;
    if (n === 0) {
      ctx.fillStyle = '#8A8A8A';
      ctx.font = '14px sans-serif';
      ctx.fillText('当前文件没有可绘制的类或函数', 16, 30);
      return;
    }
    // 布局：一列一行（tree 竖排）或两列（orthogonal 横排）
    const twoCol: boolean = this.graphLayout === 'orthogonal';
    const z: number = this.graphZoom;
    const boxW: number = 150 * z;
    const boxH: number = 34 * z;
    const gapX: number = 240 * z;
    const gapY: number = 56 * z;
    const horizontal: boolean = this.graphDir === 'h';
    // 层次布局（Graph.TreeLayoutGroup 的层次语义）：按调用/继承深度分层，同层内顺排
    const depth: Map<string, number> = new Map<string, number>();
    for (const nd of nodes) {
      depth.set(nd, 0);
    }
    for (let iter: number = 0; iter < n; iter++) {
      let changed: boolean = false;
      for (const e of this.graphEdges) {
        const parts: string[] = e.split('>');
        const dFrom: number | undefined = depth.get(parts[0]);
        const dTo: number | undefined = depth.get(parts[1]);
        if (dFrom !== undefined && dTo !== undefined && dTo <= dFrom) {
          depth.set(parts[1], dFrom + 1);
          changed = true;
        }
      }
      if (!changed) {
        break;
      }
    }
    const layerCount: number[] = [];
    const pos: Map<string, number[]> = new Map<string, number[]>();
    this.graphBoxes = [];
    for (let i: number = 0; i < n; i++) {
      const d: number = depth.get(nodes[i]) === undefined ? 0 : (depth.get(nodes[i]) as number);
      while (layerCount.length <= d) {
        layerCount.push(0);
      }
      const idxInLayer: number = layerCount[d];
      layerCount[d] = idxInLayer + 1;
      let col: number = 0;
      let row: number = 0;
      if (horizontal) {
        col = d;
        row = idxInLayer;
      } else {
        col = idxInLayer;
        row = d;
      }
      const px: number = 20 + col * gapX;
      const py: number = 16 + row * gapY;
      pos.set(nodes[i], [px, py]);
      this.graphBoxes.push(`${nodes[i]}|${px}|${py}|${boxW}|${boxH}`);
    }
    // 先画边
    // 外观配色（Graph.AppearanceGroup，3 套）：[节点填充, 节点描边, 边色, 文字]
    const palettes: string[][] = [
      ['#3B4A5A', '#6C8CB4', '#5A7FA8', '#E6E6E6'],
      ['#4A3B3B', '#B48C6C', '#A8815A', '#F0E6E0'],
      ['#3B4A3B', '#8CB46C', '#7FA85A', '#E6F0E0']
    ];
    const pal: string[] = palettes[this.graphPalette % 3];
    ctx.strokeStyle = pal[2];
    ctx.lineWidth = 1.4 * z;
    for (const e of this.graphEdges) {
      const parts: string[] = e.split('>');
      const a: number[] | undefined = pos.get(parts[0]);
      const b: number[] | undefined = pos.get(parts[1]);
      if (a === undefined || b === undefined) {
        continue;
      }
      ctx.beginPath();
      if (this.graphEdgeStyle === 'polyline') {
        // 折线（正交走线）：先下/右一半，再横/纵，最后进入目标
        const ax: number = a[0] + boxW / 2;
        const ay: number = a[1] + boxH;
        const bx: number = b[0] + boxW / 2;
        const by: number = b[1];
        if (this.graphDir === 'h') {
          const midY: number = (ay + by) / 2;
          ctx.moveTo(ax, ay);
          ctx.lineTo(ax, midY);
          ctx.lineTo(bx, midY);
          ctx.lineTo(bx, by);
        } else {
          const midX: number = (ax + bx) / 2;
          ctx.moveTo(ax, ay);
          ctx.lineTo(ax, (ay + by) / 2);
          ctx.lineTo(bx, (ay + by) / 2);
          ctx.lineTo(bx, by);
        }
      } else {
        ctx.moveTo(a[0] + boxW / 2, a[1] + boxH);
        ctx.lineTo(b[0] + boxW / 2, b[1]);
      }
      ctx.stroke();
    }
    // 再画节点
    for (let i: number = 0; i < n; i++) {
      const p: number[] | undefined = pos.get(nodes[i]);
      if (p === undefined) {
        continue;
      }
      ctx.fillStyle = pal[0];
      ctx.strokeStyle = pal[1];
      ctx.beginPath();
      // 统一尺寸：两轴都用同一个 boxW/boxH，保证任何缩放下所有节点框等宽等高
      ctx.rect(p[0], p[1], boxW, boxH);
      ctx.fill();
      ctx.stroke();
      if (this.graphShowLabels) {
        ctx.fillStyle = pal[3];
        ctx.font = `${Math.round(13 * z)}px monospace`;
        ctx.fillText(nodes[i], p[0] + 10 * z, p[1] + 22 * z);
      }
    }
  }

  /** 外部任务（ExternalSystem.TaskMenu 语义）：在真实 PTY 终端里执行命令并回显 */
  private runExternalTask(cmd: string): void {
    const t: TerminalService = TerminalService.shared();
    const ok: boolean = t.start((text: string) => {
      this.appendEntry('stdout', text);
    });
    if (!ok) {
      this.showToast('终端不可用（PTY 未就绪）');
      return;
    }
    this.settings.showBottomToolWindow = true;
    this.consoleTab = 'terminal';
    t.send(cmd);
    this.dialog = '';
    this.setStatus(`已在终端执行：${cmd}`);
  }

  /** 依赖清单（ExternalSystem.DependencyAnalyzer 语义）：用运行时读真实已安装包 */
  private async loadDependencies(): Promise<void> {
    const dir: string = `${FileService.context().filesDir}/.harmonyide`;
    FileService.ensureDir(dir);
    FileService.ensureDir(`${FileService.context().filesDir}/.harmonyide`);
    const script: string = `${dir}/pip_list.py`;
    const out: string = `${FileService.context().filesDir}/.harmonyide/deps.txt`;
    FileService.writeText(script, DEPS_SCRIPT);
    this.setStatus('正在读取依赖清单…');
    const txt: string = await this.runPyAndRead(script, [out], out);
    const rows: string[] = txt.trim().length > 0 ? txt.trim().split('\n') : ['（读取失败：运行时未就绪）'];
    this.extRows = rows;
    this.dialogTitle = `外部系统：依赖清单（${rows.length} 个包）`;
    this.dialog = 'externals';
    this.setStatus(`依赖清单：${rows.length} 个包`);
  }

  /** 打开外部系统面板（任务 + 依赖）*/
  private openExternalSystem(): void {
    this.extRows = [];
    this.dialogTitle = '外部系统：任务与依赖';
    this.dialog = 'externals';
  }
  private async loadAstHierarchy(): Promise<void> {
    const file: string = this.editorFilePath;
    if (file.length === 0) {
      return;
    }
    const dir: string = `${FileService.context().filesDir}/.harmonyide`;
    FileService.ensureDir(dir);
    FileService.ensureDir(`${FileService.context().filesDir}/.harmonyide`);
    const script: string = `${dir}/ast_scope.py`;
    const out: string = `${FileService.context().filesDir}/.harmonyide/hierarchy.txt`;
    FileService.writeText(script, SCOPE_AST_SCRIPT);
    this.setStatus('正在用 ast 分析继承层级…');
    const txt: string = await this.runPyAndRead(script, [file, out, '__hierarchy__'], out);
    const rows: string[] = txt.trim().length > 0 ? txt.trim().split('\n') : [];
    this.astHierRows = rows;
    this.setStatus(rows.length > 0 && rows[0].indexOf('类 ') === 0
      ? `继承层级：${rows.length} 行（ast）`
      : '当前文件没有类定义');
  }

  /** 重命名（Refactor.Rename）：本设备无法输入新名字，提供常用命名样式；执行前自动备份，可撤销 */
  private async applyRename(style: string): Promise<void> {
    const old: string = this.renameTarget;
    if (old.length === 0) {
      return;
    }
    let next: string = old;
    if (style === 'prefix') {
      next = old.startsWith('my_') ? old : `my_${old}`;
    } else if (style === 'suffix') {
      next = `${old}_v2`;
    } else if (style === 'upper') {
      next = old.toUpperCase();
    } else if (style === 'strip') {
      next = old.startsWith('my_') ? old.substring(3) : old.replace(/_v2$/, '');
    } else if (style === 'snake') {
      // 驼峰 → 蛇形（PyCharm 的命名风格重构）
      next = old.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
    } else if (style === 'camel') {
      // 蛇形 → 小驼峰
      const parts: string[] = old.split('_');
      let acc: string = parts.length > 0 ? parts[0] : old;
      for (let i: number = 1; i < parts.length; i++) {
        const seg: string = parts[i];
        acc += seg.length > 0 ? seg.charAt(0).toUpperCase() + seg.substring(1) : '';
      }
      next = acc;
    }
    if (next === old) {
      this.setStatus(`名称未变化：${old} 已是该风格`);
      this.renameRows = [`（${old} 已是该风格，未做修改）`];
      return;
    }
    const dir: string = `${FileService.context().filesDir}/.harmonyide`;
    FileService.ensureDir(dir);
    const script: string = `${dir}/ast_rename.py`;
    // 备份目录放在应用私有目录（工程之外），并让脚本排除 .harmonyide，避免自我改名与污染索引
    const backup: string = `${FileService.context().filesDir}/.harmonyide/rename_backup`;
    FileService.ensureDir(backup);
    const out: string = `${FileService.context().filesDir}/.harmonyide/rename_report.txt`;
    FileService.writeText(script, RENAME_AST_SCRIPT);
    this.setStatus(`正在重命名 ${old} → ${next}…`);
    const txt: string = await this.runPyAndRead(script, [this.projectRoot, old, next, backup, out], out);
    const rows: string[] = txt.trim().length > 0 ? txt.trim().split('\n') : ['(没有找到需要修改的位置)'];
    this.renameRows = rows;
    this.dialogTitle = `重命名：${old} → ${next}`;
    this.dialog = 'rename';
    this.setStatus(`重命名完成：${old} → ${next}（${rows.length} 个文件）`);
  }

  /** 撤销上次重命名（从备份还原）*/
  private async undoRename(): Promise<void> {
    const dir: string = `${FileService.context().filesDir}/.harmonyide`;
    FileService.ensureDir(dir);
    const script: string = `${dir}/ast_rename_undo.py`;
    const backup: string = `${FileService.context().filesDir}/.harmonyide/rename_backup`;
    const out: string = `${FileService.context().filesDir}/.harmonyide/rename_undo.txt`;
    FileService.writeText(script, RENAME_UNDO_SCRIPT);
    const txt: string = await this.runPyAndRead(script, [this.projectRoot, backup, out], out);
    const rows: string[] = txt.trim().length > 0 ? txt.trim().split('\n') : ['(没有可还原的备份)'];
    this.renameRows = rows;
    this.dialogTitle = '已撤销上次重命名';
    this.dialog = 'rename';
    this.setStatus(rows[0]);
  }

  /** 跨文件补全（PyCharm 的基本补全语义）：先列本文件导入的模块，再列该模块的成员 */
  private openCrossFileComplete(): void {
    const text: string = this.editorSeedText;
    const mods: string[] = [];
    const lines: string[] = text.split('\n');
    for (const raw of lines) {
      const t: string = raw.trim();
      const m1: RegExpMatchArray | null = t.match(/^import\s+([A-Za-z_][A-Za-z0-9_.]*)/);
      if (m1 !== null) {
        const top: string = m1[1].split('.')[0];
        if (mods.indexOf(top) < 0) {
          mods.push(top);
        }
        continue;
      }
      const m2: RegExpMatchArray | null = t.match(/^from\s+([A-Za-z_][A-Za-z0-9_.]*)\s+import\s+(.+)$/);
      if (m2 !== null) {
        const top: string = m2[1].split('.')[0];
        if (mods.indexOf(top) < 0) {
          mods.push(top);
        }
      }
    }
    this.completeModules = mods;
    this.completeMembers = [];
    this.completeModule = '';
    this.dialogTitle = mods.length > 0 ? `跨文件补全（${mods.length} 个已导入模块）` : '跨文件补全：当前文件没有 import';
    this.dialog = 'complete';
    if (mods.length > 0) {
      this.loadProjectSymbols();
    }
  }

  /** 选中模块 → 从工程索引里筛出该模块文件的成员 */
  private completeFromModule(mod: string): void {
    const members: string[] = [];
    for (const row of this.projectSymbols) {
      const m: RegExpMatchArray | null = row.match(/^(类|函数)\s+(\S+)\s+(\S+):(\d+)/);
      if (m === null) {
        continue;
      }
      const file: string = m[3];
      const base: string = file.substring(file.lastIndexOf('/') + 1).replace(/\.py$/, '');
      if (base === mod) {
        members.push(`${m[2]}    ${file}:${m[4]}`);
      }
    }
    this.completeModule = mod;
    this.completeMembers = members;
    this.setStatus(`${mod} 的成员：${members.length} 个`);
  }

  /** 全工程检查（ast）：未使用导入 */
  private async runInspection(showDialog: boolean = true, onlyCurrentFile: boolean = false): Promise<void> {
    const dir: string = `${FileService.context().filesDir}/.harmonyide`;
    FileService.ensureDir(dir);
    FileService.ensureDir(`${FileService.context().filesDir}/.harmonyide`);
    const script: string = `${dir}/ast_project.py`;
    const out: string = `${FileService.context().filesDir}/.harmonyide/inspect.txt`;
    FileService.writeText(script, PROJECT_AST_SCRIPT);
    // 可选：只检查当前文件（问题视图工具栏的「仅当前文件」）
    let onlyRel: string = '';
    if (onlyCurrentFile && this.editorFilePath.indexOf(this.settings.lastProjectRoot) === 0) {
      onlyRel = this.editorFilePath.substring(this.settings.lastProjectRoot.length + 1);
    }
    this.setStatus(onlyRel.length > 0 ? `正在检查 ${onlyRel}…` : '正在检查全工程…');
    const txt: string = await this.runPyAndRead(script, [this.projectRoot, out, '__inspect__', onlyRel], out);
    const rows: string[] = txt.trim().length > 0 ? txt.trim().split('\n') : [];
    this.inspectRows = rows;
    // 同时放进「问题」工具窗（常驻可见、可点行跳转）
    this.problemRows = rows;
    // 当前文件的问题行 → gutter 警示标
    const cur: string = this.editorFilePath;
    const curRel: string = cur.indexOf(this.settings.lastProjectRoot) === 0
      ? cur.substring(this.settings.lastProjectRoot.length + 1) : '';
    const warns: number[] = [];
    for (const r of rows) {
      const m: RegExpMatchArray | null = r.match(/([^\s:]+):(\d+)\s/);
      if (m !== null && curRel.length > 0 && m[1] === curRel) {
        warns.push(Number.parseInt(m[2], 10));
      }
    }
    this.warnLines = warns;
    if (!showDialog) {
      // 静默模式（保存触发）：只刷新问题列表，不弹对话框、不强制打开工具窗
      this.setStatus(`已保存 · 检查：${rows.length} 条`);
      return;
    }
    this.settings.showBottomToolWindow = true;
    this.consoleTab = 'problems';
    this.dialogTitle = `检查结果（${rows.length} 条）`;
    this.dialog = 'inspect';
    this.setStatus(rows.length > 0 ? `检查完成：${rows.length} 条` : '检查完成：未发现问题');
  }

  /** 跨文件转到类：列出全工程的类（含所在文件与基类）*/
  private async loadProjectClasses(): Promise<void> {
    const dir: string = `${FileService.context().filesDir}/.harmonyide`;
    FileService.ensureDir(dir);
    FileService.ensureDir(`${FileService.context().filesDir}/.harmonyide`);
    const script: string = `${dir}/ast_project.py`;
    const out: string = `${FileService.context().filesDir}/.harmonyide/project_classes.txt`;
    FileService.writeText(script, PROJECT_AST_SCRIPT);
    const txt: string = await this.runPyAndRead(script, [this.projectRoot, out], out);
    const rows: string[] = txt.trim().length > 0 ? txt.trim().split('\n') : [];
    const only: string[] = rows.filter((r: string) => r.indexOf('类 ') === 0);
    this.classRows = only;
    this.setStatus(`全工程类：${only.length} 个（ast 跨文件）`);
  }

  /** 全工程符号列表（跨文件）：类与函数，附所在文件与行号 */
  private async loadProjectSymbols(): Promise<void> {
    const dir: string = `${FileService.context().filesDir}/.harmonyide`;
    FileService.ensureDir(dir);
    FileService.ensureDir(`${FileService.context().filesDir}/.harmonyide`);
    const script: string = `${dir}/ast_project.py`;
    const out: string = `${FileService.context().filesDir}/.harmonyide/project_symbols.txt`;
    FileService.writeText(script, PROJECT_AST_SCRIPT);
    const txt: string = await this.runPyAndRead(script, [this.projectRoot, out], out);
    const rows: string[] = txt.trim().length > 0 ? txt.trim().split('\n') : [];
    this.projectSymbols = rows;
    // 面板格式：C/ƒ + 名字 + 相对文件:行（供 Structure 面板「工程」范围使用）
    const panel: string[] = [];
    for (const r of rows) {
      const m: RegExpMatchArray | null = r.match(/^(类|函数)\s+(\S+)\s+(\S+):(\d+)/);
      if (m !== null) {
        panel.push(`${m[1] === '类' ? 'C' : 'ƒ'}  ${m[2]}    ${m[3]}:${m[4]}`);
      }
    }
    this.projectPanelRows = panel;
    this.setStatus(`全工程符号：${rows.length} 个（ast 跨文件）`);
  }

  /** 查找用法（PyCharm 的 Find Usages）：用 ast 列出该符号的每一处引用 */
  private async findUsages(symbol: string): Promise<void> {
    const file: string = this.editorFilePath;
    if (file.length === 0 || symbol.length === 0) {
      this.showToast('当前没有可分析的文件');
      return;
    }
    const dir: string = `${FileService.context().filesDir}/.harmonyide`;
    FileService.ensureDir(dir);
    FileService.ensureDir(`${FileService.context().filesDir}/.harmonyide`);
    const script: string = `${dir}/ast_project.py`;
    const out: string = `${FileService.context().filesDir}/.harmonyide/usages.txt`;
    FileService.writeText(script, PROJECT_AST_SCRIPT);
    this.setStatus(`正在全工程查找 ${symbol} 的定义与用法…`);
    const txt: string = await this.runPyAndRead(script, [this.projectRoot, out, symbol], out);
    const rows: string[] = txt.trim().length > 0 ? txt.trim().split('\n') : ['(无用法)'];
    this.usagesSymbol = symbol;
    this.usagesRows = rows;
    this.dialogTitle = `查找用法（全工程）：${symbol}（${rows.length} 处）`;
    this.dialog = 'usages';
    this.setStatus(`${symbol} 的用法：${rows.length} 处`);
  }

  /** 跑 Python 脚本并等输出文件真正写完（跨进程写文件：run 返回 ≠ 写入完成，必须轮询）*/
  private async runPyAndRead(scriptPath: string, args: string[], outPath: string): Promise<string> {
    try {
      const before: string = FileService.exists(outPath) ? FileService.readText(outPath) : '';
      const scriptLen: number = FileService.exists(scriptPath) ? FileService.readText(scriptPath).length : -1;
      FileService.log(`runPy start scriptLen=${scriptLen} outLen=${before.length}`);
      // 启动期的刷新会撞上「运行时尚未初始化」：等待就绪后重试（最多 ~10s）
      let res: RunResult = await PyRuntimeService.run(scriptPath, args);
      for (let attempt: number = 0; attempt < 20; attempt++) {
        if (res.code !== -1 && res.stderr.indexOf('尚未初始化') < 0) {
          break;
        }
        await new Promise<void>((resolve: () => void) => {
          setTimeout(() => {
            resolve();
          }, 500);
        });
        res = await PyRuntimeService.run(scriptPath, args);
      }
      FileService.log(`runPy returned code=${res.code} stdoutLen=${res.stdout.length} stderr=${res.stderr.substring(0, 120).replace(/\n/g, '|')}`);
      for (let i: number = 0; i < 30; i++) {
        await new Promise<void>((resolve: () => void) => {
          setTimeout(() => {
            resolve();
          }, 200);
        });
        if (FileService.exists(outPath)) {
          const now: string = FileService.readText(outPath);
          if (now.length > 0 && now !== before) {
            FileService.log(`runPy fresh outLen=${now.length} head=${now.substring(0, 40).replace(/\n/g, '|')}`);
            return now;
          }
        }
      }
      const stale: string = FileService.exists(outPath) ? FileService.readText(outPath) : '';
      FileService.log(`runPy TIMEOUT/UNCHANGED outLen=${stale.length} head=${stale.substring(0, 40).replace(/\n/g, '|')}`);
      return stale;
    } catch (e) {
      FileService.log(`runPyAndRead THREW ${e}`);
      return '';
    }
  }

  /** 作用域视图（ScopeView）：把当前文件交给运行时用 ast 真解析，结果写文件后读回 */
  private async openScopeView(): Promise<void> {
    const file: string = this.editorFilePath;
    if (file.length === 0) {
      this.showToast('当前没有打开的文件');
      return;
    }
    const dir: string = `${FileService.context().filesDir}/.harmonyide`;
    FileService.ensureDir(dir);
    const script: string = `${dir}/ast_scope.py`;
    const out: string = `${FileService.context().filesDir}/.harmonyide/scope.txt`;
    FileService.ensureDir(`${FileService.context().filesDir}/.harmonyide`);
    FileService.writeText(script, SCOPE_AST_SCRIPT);
    this.setStatus('正在解析作用域（ast）…');
    const txt: string = await this.runPyAndRead(script, [file, out], out);
    this.scopeRows = txt.trim().length > 0 ? txt.split('\n') : ['（解析失败：运行时未就绪或语法错误）'];
    this.dialogTitle = `作用域视图：${file.substring(file.lastIndexOf('/') + 1)}（${this.scopeRows.length} 项）`;
    this.dialog = 'scope';
    this.setStatus(`作用域视图：${this.scopeRows.length} 项（AST 解析）`);
  }

  /** 点图表节点 → 跳到该符号的源码定义（PyCharm NeighborhoodView 的双击行为）*/
  private onGraphClick(x: number, y: number): void {
    for (const box of this.graphBoxes) {
      const parts: string[] = box.split('|');
      if (parts.length < 5) {
        continue;
      }
      const bx: number = Number.parseInt(parts[1], 10);
      const by: number = Number.parseInt(parts[2], 10);
      const bw: number = Number.parseInt(parts[3], 10);
      const bh: number = Number.parseInt(parts[4], 10);
      if (x >= bx && x <= bx + bw && y >= by && y <= by + bh) {
        const name: string = parts[0];
        const line: number = this.lineOfSymbol(name);
        if (line > 0) {
          this.editorController.revealLine(line);
          this.setStatus(`已从图表跳转到 ${name.replace(/\s+L\d+$/, '')}（第 ${line} 行）`);
        } else {
          this.setStatus(`${name} 是外部/基类符号，当前文件内没有定义行`);
        }
        return;
      }
    }
    this.setStatus('未命中任何节点');
  }

  /** 导出图表为 PNG（Graph.DefaultGraphToolbar 的导出）：写入工程根目录，可在工程树看到 */
  private exportGraph(): void {
    try {
      const dataUrl: string = this.graphCtx.toDataURL('image/png');
      const base64: string = dataUrl.substring(dataUrl.indexOf(',') + 1);
      const bytes: Uint8Array = new util.Base64Helper().decodeSync(base64);
      const out: string = `${this.projectRoot}/关系图.png`;
      FileService.writeBinary(out, bytes);
      // 刷新工程树，让导出的文件立刻可见
      this.treeRoots = FileService.listDir(this.projectRoot, 0);
      this.treeRoots = this.treeRoots.slice();
      this.setStatus(`已导出图表：${out.split('/').pop()}（${bytes.length} 字节）`);
    } catch (e) {
      this.showToast('导出失败：画布尚未就绪');
    }
  }

  /** 行级差异（LCS 动态规划，用一维数组避免嵌套数组）*/
  private diffLines(a: string, b: string): string[] {
    const la: string[] = a.split('\n');
    const lb: string[] = b.split('\n');
    const n: number = la.length;
    const m: number = lb.length;
    const w: number = m + 1;
    const dp: number[] = new Array<number>((n + 1) * w).fill(0);
    for (let i: number = n - 1; i >= 0; i--) {
      for (let j: number = m - 1; j >= 0; j--) {
        dp[i * w + j] = la[i] === lb[j]
          ? dp[(i + 1) * w + (j + 1)] + 1
          : Math.max(dp[(i + 1) * w + j], dp[i * w + (j + 1)]);
      }
    }
    const out: string[] = [];
    let i2: number = 0;
    let j2: number = 0;
    while (i2 < n && j2 < m) {
      if (la[i2] === lb[j2]) {
        out.push(`  ${la[i2]}`);
        i2++;
        j2++;
      } else if (dp[(i2 + 1) * w + j2] >= dp[i2 * w + (j2 + 1)]) {
        out.push(`- ${la[i2]}`);
        i2++;
      } else {
        out.push(`+ ${lb[j2]}`);
        j2++;
      }
    }
    while (i2 < n) {
      out.push(`- ${la[i2]}`);
      i2++;
    }
    while (j2 < m) {
      out.push(`+ ${lb[j2]}`);
      j2++;
    }
    return out;
  }

  /** 与剪贴板比较（PyCharm Diff.CompareWithClipboard）*/
  private compareWithClipboard(): void {
    FileService.readClipboardAsync((clip: string) => {
      this.compareWithClipboardText(clip);
    });
  }

  /** 拿到剪贴板文本后出差异（异步授权回调里调用）*/
  private compareWithClipboardText(clip: string): void {
    if (clip.length === 0) {
      this.showToast('剪贴板为空或未获授权');
      return;
    }
    const mine: string = this.editorSeedText;
    const rows: string[] = this.diffLines(clip, mine);
    let add: number = 0;
    let rem: number = 0;
    for (const r of rows) {
      if (r.charAt(0) === '+') {
        add++;
      } else if (r.charAt(0) === '-') {
        rem++;
      }
    }
    this.diffRows = rows;
    this.diffAdded = add;
    this.diffRemoved = rem;
    this.diffLeftName = '剪贴板';
    this.diffRightName = this.editorFilePath.substring(this.editorFilePath.lastIndexOf('/') + 1);
    this.dialogTitle = `差异：剪贴板 ↔ ${this.diffRightName}`;
    this.dialog = 'diffView';
    this.setStatus(`与剪贴板比较：+${add} 行 / -${rem} 行`);
  }

  /** 比较：左侧 = 指定文件（磁盘内容），右侧 = 当前编辑器内容 */
  private compareActiveWith(path: string): void {
    let other: string = '';
    try {
      other = FileService.readText(path);
    } catch (e) {
      this.showToast(`读取失败：${path}`);
      return;
    }
    const mine: string = this.editorSeedText;
    const rows: string[] = this.diffLines(other, mine);
    let add: number = 0;
    let rem: number = 0;
    for (const r of rows) {
      if (r.charAt(0) === '+') {
        add++;
      } else if (r.charAt(0) === '-') {
        rem++;
      }
    }
    this.diffRows = rows;
    this.diffAdded = add;
    this.diffRemoved = rem;
    this.diffLeftName = path.substring(path.lastIndexOf('/') + 1);
    this.diffRightName = this.editorFilePath.substring(this.editorFilePath.lastIndexOf('/') + 1);
    this.dialogTitle = `差异：${this.diffLeftName} ↔ ${this.diffRightName}`;
    this.dialog = 'diffView';
    this.setStatus(`差异：+${add} 行 / -${rem} 行（左=磁盘文件，右=编辑器当前内容）`);
  }

  /** 继承关系（PyCharm 的 Hierarchy）：解析当前文件的 class A(B) → "子类 : 父类" */
  private classHierarchy(): string[] {
    // ast 结果可用时优先（正则版丢嵌套、看不出继承来的方法）
    if (this.astHierRows.length > 0) {
      return this.astHierRows;
    }
    // ast 结果可用时优先（正则版丢嵌套、看不出继承来的方法）
    if (this.astHierRows.length > 0) {
      return this.astHierRows;
    }
    // ast 结果可用时优先（正则版丢嵌套、看不出继承来的方法）
    if (this.astHierRows.length > 0) {
      return this.astHierRows;
    }
    return this.parseHierarchy(this.editorSeedText);
  }

  /** 继承解析（可复用：自检会用工程里另一个文件验证非空路径） */
  private parseHierarchy(text: string): string[] {
    const out: string[] = [];
    const lines: string[] = text.split('\n');
    for (const raw of lines) {
      const t: string = raw.trim();
      const m: RegExpMatchArray | null = t.match(/^class\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(([^)]*)\))?\s*:/);
      if (m === null) {
        continue;
      }
      const name: string = m[1];
      const bases: string = m[2] === undefined ? '' : m[2].trim();
      out.push(bases.length > 0 ? `${name} : ${bases}` : `${name} : (无基类)`);
    }
    return out;
  }

  /** CodeMenu: EditorCompleteStatement（补全语句）—— 行尾是 ':' 时补换行与缩进 */
  private completeStatement(): void {
    const text: string = this.editorSeedText;
    const lines: string[] = text.split('\n');
    const n: number = this.cursorLine;
    if (n < 1 || n > lines.length) {
      this.showToast('光标不在有效行上');
      return;
    }
    const raw: string = lines[n - 1];
    const body: string = raw.replace(/#.*$/, '').trimEnd();
    if (!body.endsWith(':')) {
      this.setStatus(`第 ${n} 行不是语句开头（行尾没有 ':'）`);
      return;
    }
    const indent: string = raw.substring(0, raw.length - raw.trimStart().length);
    this.editorController.insertText(`\n${indent}    `);
    this.setStatus(`已在第 ${n} 行补全语句（换行 + 缩进）`);
  }

  /** CodeMenu: HippieCompletion —— 用当前文件里的词做循环补全（纯本地，无需语义引擎） */
  private hippieComplete(): void {
    const text: string = this.editorSeedText;
    const caret: number = Math.max(this.selStartSel, this.selEndSel);
    const before: string = text.substring(0, Math.min(caret, text.length));
    const m: RegExpMatchArray | null = before.match(/[A-Za-z_][A-Za-z0-9_]*$/);
    if (m === null) {
      this.showToast('光标前没有可补全的标识符');
      return;
    }
    const prefix: string = m[0];
    if (prefix.length < 2) {
      this.showToast('至少输入 2 个字符才能循环补全');
      return;
    }
    const words: RegExpMatchArray | null = text.match(/[A-Za-z_][A-Za-z0-9_]*/g);
    if (words === null) {
      return;
    }
    const uniq: string[] = [];
    for (const w of words) {
      if (w !== prefix && w.startsWith(prefix) && uniq.indexOf(w) < 0) {
        uniq.push(w);
      }
    }
    if (uniq.length === 0) {
      this.showToast(`没有以“${prefix}”开头的词`);
      return;
    }
    if (this.hippieCandidates.join(',') !== uniq.join(',')) {
      this.hippieCandidates = uniq;
      this.hippieIndex = 0;
    } else {
      this.hippieIndex = (this.hippieIndex + 1) % uniq.length;
    }
    const word: string = uniq[this.hippieIndex];
    this.editorController.insertText(word.substring(prefix.length));
    this.setStatus(`循环补全 ${this.hippieIndex + 1}/${uniq.length}：${word}`);
  }

  /** TabsActions.GoToTab1..9：Ctrl+数字 跳到第 N 个标签（PyCharm 行为） */
  private goToTabN(n: number): void {
    if (n < 1 || n > this.tabs.length) {
      this.setStatus(`没有第 ${n} 个标签`);
      return;
    }
    this.activateTab(this.tabs[n - 1]);
  }

  /** 折叠状态落盘（重启后保持） */
  private persistFolds(): void {
    this.settings.foldedFolds = this.foldedStarts.join(',');
    SettingsService.save(this.settings);
  }

  /** 当前活动文件的 path */
  private activePathKey(): string {
    const t: EditorTab | undefined = this.activeTab();
    return t === undefined ? '' : t.path;
  }

  /** 该行是否已折叠（按当前文件判断） */
  private isFoldedLine(line: number): boolean {
    return this.foldedStarts.indexOf(`${this.activePathKey()}#${line}`) >= 0;
  }

  /** 当前文件所有可折叠块的首行（供编辑器 gutter 显示/点击标记） */
  private foldableLines(): number[] {
    const out: number[] = [];
    for (const r of this.foldRegions()) {
      const s: number = Number.parseInt(r.split(':')[0], 10);
      if (!Number.isNaN(s)) {
        out.push(s);
      }
    }
    return out;
  }

  /** 点击 gutter 折叠标记：展开/折叠该块（PyCharm 的 ExpandCollapseToggleAction） */
  private toggleFoldAtLine(line: number): void {
    const key: string = `${this.activePathKey()}#${line}`;
    if (this.foldedStarts.indexOf(key) >= 0) {
      this.foldedStarts = this.foldedStarts.filter((x: string) => x !== key);
      this.persistFolds();
      this.setStatus(`已展开第 ${line} 行起的代码块`);
    } else {
      const next: string[] = this.foldedStarts.slice();
      next.push(key);
      this.foldedStarts = next;
      this.persistFolds();
      this.setStatus(`已折叠第 ${line} 行起的代码块`);
    }
  }

  /** 折叠后需要隐藏的行号（区域内部，不含起始行） */
  private hiddenLines(): number[] {
    const out: number[] = [];
    for (const r of this.foldRegions()) {
      const parts: string[] = r.split(':');
      const s: number = Number.parseInt(parts[0], 10);
      const e: number = Number.parseInt(parts[1], 10);
      if (!this.isFoldedLine(s)) {
        continue;
      }
      for (let n = s + 1; n <= e; n++) {
        if (out.indexOf(n) < 0) {
          out.push(n);
        }
      }
    }
    return out;
  }

  /** 光标所在的最内层可折叠区域起始行（0 = 没有） */
  private foldStartAtCursor(): number {
    let found: number = 0;
    for (const r of this.foldRegions()) {
      const parts: string[] = r.split(':');
      const s: number = Number.parseInt(parts[0], 10);
      const e: number = Number.parseInt(parts[1], 10);
      if (this.cursorLine >= s && this.cursorLine <= e) {
        found = s;
      }
    }
    return found;
  }

  /** 控制台里的 URL（CopyUrl：从输出抽取） */
  private consoleUrls(): string[] {
    const out: string[] = [];
    const re: RegExp = /[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^\s)"'<>]+/g;
    for (const e of this.logEntries) {
      const m: RegExpMatchArray | null = e.text.match(re);
      if (m !== null) {
        for (const u of m) {
          if (out.indexOf(u) < 0) {
            out.push(u);
          }
        }
      }
    }
    return out;
  }

  /** 控制台右键菜单（依据 ConsoleView.PopupMenu 10 项） */
  @Builder
  ConsoleContextMenu() {
    Column() {
      this.tabMenuItem('cs.cut', '剪切(_T)', 'Ctrl+X')
      this.tabMenuItem('cs.copy', '复制(_C)', 'Ctrl+C')
      this.tabMenuItem('cs.copyPath', '复制路径(_O)', 'Ctrl+Shift+C')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('cs.compare', '将剪贴板与所选内容比较', '')
      this.tabMenuItem('cs.searchWeb', '使用 Google 搜索(_S)', '')
      this.tabMenuItem('cs.copyUrl', '复制 URL', '')
      this.tabMenuItem('cs.pause', this.consolePaused ? '✓ 暂停输出' : '暂停输出', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('cs.clearAll', '全部清除', '')
    }
    .width(250)
    // 绝对定位的 Column 会按首个子节点测高 → 显式给高，否则只画出前几项
    .height(268)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(this.theme.popupArc)
    .clip(true)
    .position({ x: this.consoleMenuX, y: this.consoleMenuY })
  }

  private onConsoleMenuPick(id: string): void {
    FileService.log(`menuPick console id=${id}`);
    this.consoleMenuShown = false;
    if (id === 'cs.copy' || id === 'cs.cut') {
      let all: string = '';
      for (const e of this.logEntries) {
        all += e.text;
      }
      if (all.length === 0) {
        this.showToast('控制台没有内容可复制');
        return;
      }
      FileService.copyToClipboard(all);
      if (id === 'cs.cut') {
        this.handleAction('console.clearAll');
        this.setStatus('已复制并清空控制台');
      } else {
        this.setStatus(`已复制控制台输出（${all.length} 字符）`);
      }
      return;
    }
    if (id === 'cs.copyPath') {
      this.handleAction('edit.copyPath');
      return;
    }
    if (id === 'cs.copyUrl') {
      const urls: string[] = this.consoleUrls();
      if (urls.length === 0) {
        this.showToast('控制台输出里没有 URL');
        return;
      }
      FileService.copyToClipboard(urls[0]);
      this.setStatus(`已复制 URL：${urls[0]}`);
      return;
    }
    if (id === 'cs.pause') {
      this.togglePauseOutput();
      return;
    }
    if (id === 'cs.clearAll') {
      this.handleAction('console.clearAll');
      return;
    }
    if (id === 'cs.compare' || id === 'cs.searchWeb') {
      this.showToast('需要差异视图 / 浏览器跳转能力（HarmonyOS 沙箱不提供），本版本尚未实现');
      return;
    }
  }

  /** 结构符号在活动文件里的行号（供"编辑源"跳转） */
  private lineOfSymbol(name: string): number {
    // ast 结构行形如「ƒ  greet    L6」：先取行号后缀（正则结构行没有行号，走原逻辑）
    const mLine: RegExpMatchArray | null = name.match(/L(\d+)\s*$/);
    if (mLine !== null) {
      return Number.parseInt(mLine[1], 10);
    }
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined || name.length === 0) {
      return 0;
    }
    const lines: string[] = this.editorSeedText.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const t: string = lines[i].trim();
      if ((t.startsWith('def ') || t.startsWith('async def ') || t.startsWith('class ')) && t.indexOf(name) > 0) {
        return i + 1;
      }
    }
    return 0;
  }

  /** 结构视图右键菜单（依据 StructureViewPopupMenu 22 项） */
  @Builder
  StructureContextMenu() {
    Column() {
      this.tabMenuItem('st.editSource', '跳转到源代码', 'F4')
      // 导航类：继承层级（PyCharm 的 TypeHierarchyAction；结构视图里就近提供入口）
      this.tabMenuItem('st.hierarchy', '继承层级', 'Ctrl+H')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('st.findUsages', '查找用法', 'Alt+F7')
      this.tabMenuItem('st.rename', '重命名(_R)…', 'Shift+F6')
      this.tabMenuItem('st.refactor', '重构…', 'Ctrl+Alt+Shift+T')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('st.cut', '剪切(_T)', 'Ctrl+X')
      this.tabMenuItem('st.copy', '复制(_C)', 'Ctrl+C')
      this.tabMenuItem('st.copyPath', '复制路径(_O)', 'Ctrl+Shift+C')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('st.run', '运行', 'Shift+F10')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('st.openInRightSplit', '在右侧拆分中打开', '')
      this.tabMenuItem('st.splitChooser', '在拆分中打开…', '')
      this.tabMenuItem('st.revealIn', '在此处显示', '')
      this.tabMenuItem('st.openAssociated', '在关联的应用程序中打开', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('st.vcsHistory', '显示历史', '')
      this.tabMenuItem('st.compare', '比较文件', '')
    }
    .width(240)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(this.theme.popupArc)
    .clip(true)
    .position({ x: this.structMenuX, y: this.structMenuY })
  }

  private onStructMenuPick(id: string): void {
    FileService.log(`menuPick struct id=${id} symbol=${this.structMenuSymbol}`);
    this.structMenuShown = false;
    const symbol: string = this.structMenuSymbol;
    if (id === 'st.editSource') {
      const line: number = this.lineOfSymbol(symbol);
      if (line > 0) {
        this.editorController.revealLine(line);
        this.setStatus(`已跳转到 ${symbol}（第 ${line} 行）`);
      } else {
        this.showToast(`未找到 ${symbol} 的行号`);
      }
      return;
    }
    if (id === 'st.compare') {
      // PyCharm：比较文件。此处语义为"当前编辑器内容 ↔ 该文件在磁盘上的版本"（可看出未保存的改动）
      if (this.editorFilePath.length === 0) {
        this.showToast('当前没有打开的文件');
        return;
      }
      this.compareActiveWith(this.editorFilePath);
      return;
    }
    if (id === 'st.hierarchy') {
      this.dialogTitle = '层次结构';
      this.dialog = 'hierarchy';
      this.loadAstHierarchy();
      return;
    }
    if (id === 'st.findUsages') {
      this.search.query = symbol;
      this.handleAction('edit.findUsages');
      return;
    }
    if (id === 'st.copy') {
      this.handleAction('edit.copyPath');
      this.setStatus(`已复制符号名：${symbol}`);
      return;
    }
    if (id === 'st.copyPath') {
      this.handleAction('edit.copyPath');
      return;
    }
    if (id === 'st.run') {
      this.runActiveFile(false);
      return;
    }
    if (id === 'st.revealIn') {
      this.handleAction('nav.selectInProjectView');
      return;
    }
    if (id === 'st.rename' || id === 'st.refactor' || id === 'st.cut' || id === 'st.openInRightSplit'
      || id === 'st.splitChooser' || id === 'st.openAssociated' || id === 'st.vcsHistory' || id === 'st.compare') {
      this.showToast('该功能需要语义索引/差异视图/VCS 集成，本版本尚未实现');
      return;
    }
  }

  /** 面包屑右键菜单（依据 NavbarPopupMenu 37 项；与项目树菜单共用实现） */
  @Builder
  NavbarContextMenu() {
    Scroll() {
    Column() {
      this.tabMenuItem('nav.newFile', '新建文件', '')
      this.tabMenuItem('nav.newFolder', '新建文件夹', '')
      this.tabMenuItem('nav.associateType', '与文件类型关联…', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('nav.cut', '剪切(_T)', 'Ctrl+X')
      this.tabMenuItem('nav.copy', '复制(_C)', 'Ctrl+C')
      this.tabMenuItem('nav.copyPath', '复制路径(_O)', 'Ctrl+Shift+C')
      this.tabMenuItem('nav.editSource', '编辑源', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('nav.viewNavBar', this.showBreadcrumb ? '✓ 显示导航栏' : '显示导航栏', '')
      this.tabMenuItem('nav.viewMembers', '在导航栏中显示成员', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('nav.findUsages', '查找用法', 'Alt+F7')
      this.tabMenuItem('nav.findInFiles', '在文件中查找', 'Ctrl+Shift+F')
      this.tabMenuItem('nav.replaceInFiles', '在文件中替换…', 'Ctrl+Shift+R')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('nav.refactor', '重构…', 'Ctrl+Alt+Shift+T')
      this.tabMenuItem('nav.rename', '重命名(_R)…', 'Shift+F6')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('nav.reformat', '重新格式化代码', 'Ctrl+Alt+L')
      this.tabMenuItem('nav.optimizeImports', '优化导入', 'Ctrl+Alt+O')
      this.tabMenuItem('nav.changeLang', '更改文件语言', '')
      this.tabMenuItem('nav.delete', '删除(_D)', 'Delete')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('nav.run', '运行', 'Shift+F10')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('nav.openInRightSplit', '在右侧拆分中打开', '')
      this.tabMenuItem('nav.splitChooser', '在拆分中打开…', '')
      this.tabMenuItem('nav.revealHere', '在此处显示', '')
      this.tabMenuItem('nav.openAssociated', '在关联的应用程序中打开', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('nav.vcsHistory', '显示历史', '')
      this.tabMenuItem('nav.vcsCommit', '提交…', 'Ctrl+K')
      this.tabMenuItem('nav.vcsPush', '推送…', 'Ctrl+Shift+K')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('nav.reload', '从磁盘重新加载', 'Ctrl+Alt+Y')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('nav.externalTools', '外部工具', '')
      this.tabMenuItem('nav.viewSettings', '项目视图设置…', '')
    }
    .width('100%')
    }
    .width(250)
    .constraintSize({ maxHeight: 560 })
    .scrollBar(BarState.Auto)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(this.theme.popupArc)
    .clip(true)
    .position({ x: this.navMenuX, y: this.navMenuY })
  }

  /** 面包屑菜单派发：大部分委托给项目树处理器（两者在 PyCharm 里共用同一批动作） */
  private onNavMenuPick(id: string): void {
    FileService.log(`menuPick navbar id=${id}`);
    this.navMenuShown = false;
    if (id === 'nav.viewNavBar') {
      this.showBreadcrumb = !this.showBreadcrumb;
      this.setStatus(this.showBreadcrumb ? '已显示导航栏' : '已隐藏导航栏');
      return;
    }
    if (id === 'nav.viewMembers') {
      this.showToast('「在导航栏中显示成员」需要符号索引，本版本按文件路径显示导航栏');
      return;
    }
    const tab: EditorTab | undefined = this.activeTab();
    this.treeMenuPath = tab !== undefined ? tab.path : '';
    this.onTreeMenuPick('tree.' + id.substring(4));
  }

  /** 工程树菜单派发 */
  private onTreeMenuPick(id: string): void {
    const path: string = this.treeMenuPath;
    const name: string = FileService.baseName(path);
    const slash: number = path.lastIndexOf('/');
    const parent: string = slash > 0 ? path.substring(0, slash) : path;
    this.treeMenuPath = '';
    FileService.log(`tree menu pick id=${id} path=${path}`);
    if (id === 'tree.newFile') {
      this.dialogTarget = parent;
      this.openNewFileDialog();
      return;
    }
    if (id === 'tree.newPyFile') {
      this.dialogTarget = parent;
      this.openNewFileDialog();
      return;
    }
    if (id === 'tree.newPackage') {
      this.dialogTarget = parent;
      this.openInputDialog('新建 Python 包', 'new_package', 'newPackage');
      return;
    }
    if (id === 'tree.newScratch') {
      const dir: string = scratchDir();
      FileService.ensureDir(dir);
      const name: string = `scratch_${Date.now()}.py`;
      FileService.writeText(`${dir}/${name}`, '# 临时文件（Scratch）\n');
      this.setStatus(`已创建临时文件：${name}`);
      return;
    }
    if (id === 'tree.debug') {
      this.openFile(path, name);
      this.runActiveFile(true);
      return;
    }
    if (id === 'tree.newFolder') {
      this.dialogTarget = parent;
      this.openInputDialog('新建目录', 'new_folder', 'newFolder');
      return;
    }
    if (id === 'tree.editSource') {
      this.openFile(path, name);
      return;
    }
    if (id === 'tree.copyPath') {
      FileService.copyToClipboard(path);
      this.setStatus(`已复制路径：${path}`);
      return;
    }
    if (id === 'tree.rename') {
      this.dialogTarget = path;
      this.openInputDialog('重命名', name, 'rename');
      return;
    }
    if (id === 'tree.delete') {
      this.dialogTarget = path;
      this.dialog = 'delete';
      return;
    }
    if (id === 'tree.reload') {
      this.refreshDir(parent);
      this.setStatus('已从磁盘重新加载');
      return;
    }
    if (id === 'tree.run') {
      this.openFile(path, name);
      this.runActiveFile(false);
      return;
    }
    // ── ProjectViewPopupMenu 新增项 ──
    if (id === 'tree.findUsages') {
      this.search.query = name;
      this.handleAction('edit.findUsages');
      return;
    }
    if (id === 'tree.findInFiles') {
      this.handleAction('edit.findInFiles');
      return;
    }
    if (id === 'tree.cacheRecovery') {
      this.refreshFlatten();
      this.setStatus('已刷新项目（缓存恢复）');
      return;
    }
    if (id === 'tree.revealHere') {
      this.handleAction('nav.selectInProjectView');
      return;
    }
    if (id === 'tree.viewSettings') {
      this.dialogTitle = '设置';
      this.dialog = 'settings';
      return;
    }
    if (id === 'tree.changeLang') {
      this.dialogTarget = path;
      this.dialog = 'newFileLang';
      return;
    }
    if (id === 'tree.cut' || id === 'tree.copy') {
      this.showInfo('文件剪贴板', [
        'PyCharm 支持在工程树里剪切/复制/粘贴文件。',
        '本 IDE 暂未实现文件级剪贴板（可用「复制路径」+ 终端里的 Python 脚本完成）。'
      ]);
      return;
    }
    if (id === 'tree.paste') {
      this.showInfo('文件剪贴板', [
        'PyCharm 支持在工程树里剪切/复制/粘贴文件。',
        '本 IDE 暂未实现文件级剪贴板（可用「复制路径」+ 终端里的 Python 脚本完成）。'
      ]);
      return;
    }
    if (id === 'tree.changeSignature' || id === 'tree.introduceConstant' || id === 'tree.vcsPull') {
      this.showToast('该功能需要语义索引 / VCS 集成，本版本尚未实现');
      return;
    }
    if (id === 'tree.compareTwoFiles' || id === 'tree.compareWithEditor') {
      if (this.treeMenuPath.length === 0) {
        this.showToast('请先在工程树中选择一个文件');
        return;
      }
      this.compareActiveWith(this.treeMenuPath);
      return;
    }
    if (id === 'tree.associateType' || id === 'tree.restoreExt' || id === 'tree.replaceInFiles'
      || id === 'tree.reformat' || id === 'tree.optimizeImports' || id === 'tree.openInRightSplit'
      || id === 'tree.splitChooser' || id === 'tree.openAssociated' || id === 'tree.goToLinkTarget'
      || id === 'tree.externalTools'
      || id === 'tree.vcsHistory' || id === 'tree.vcsCommit' || id === 'tree.vcsPush'
      || id === 'tree.vcsPull') {
      this.showToast('该功能需要 IDE 对应的引擎能力（文件类型注册 / 语义重构 / 差异视图 / VCS 集成），本版本尚未实现');
      return;
    }
    this.showInfo('重构', [
      'PyCharm 的工程树重构（重命名/移动/复制/安全删除/引入变量…）依赖语义分析引擎。',
      '本 IDE 已提供：重命名、删除、新建文件/目录、从磁盘重新加载、运行。',
      '符号级重构列入后续版本。'
    ]);
  }

  /** 标签栏 ⋮ 菜单内容（依据 PyCharm 的 EditorTabPopupMenu + EditorTabPopupMenuEx 原文） */
  @Builder
  tabMenu() {
    Column() {
      this.tabMenuItem('close', '关闭标签页(_C)', 'Ctrl+W')
      this.tabMenuItem('closeOthers', '关闭其他标签页(_O)', '')
      this.tabMenuItem('closeAll', '关闭所有标签页(_A)', '')
      this.tabMenuItem('closeUnpinned', '关闭所有未固定', '')
      this.tabMenuItem('closeLeft', '关闭左侧标签页', '')
      this.tabMenuItem('closeRight', '关闭右侧标签页', '')
      this.tabMenuItem('closeReadonly', '关闭所有只读标签页', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      // ── EditorTabPopupMenu（PlatformActions.xml:1134-1155）按原顺序补齐 ──
      this.tabMenuItem('copyPath2', '复制路径', 'Ctrl+Shift+C')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('splitRight', '向右拆分(_V)', '')
      this.tabMenuItem('moveTabRight', '向右移动标签页', '')
      this.tabMenuItem('splitDown', '向下拆分(_H)', '')
      // SplitChooser 其余方向（PyCharm SplitChooser.Actions）
      this.tabMenuItem('splitLeft', '向左拆分', '')
      this.tabMenuItem('splitTop', '向上拆分', '')
      this.tabMenuItem('splitCenter', '居中拆分', '')
      this.tabMenuItem('moveTabDown', '向下移动标签页', '')
      this.tabMenuItem('oppositeGroup', '移至相反的组', '')
      this.tabMenuItem('openOpposite', '在相反的组中打开(_O)', '')
      this.tabMenuItem('changeSplit', '更改拆分方向', '')
      this.tabMenuItem('unsplit', '取消拆分', '')
      this.tabMenuItem('unsplitAll', '全部取消拆分', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('pinTab', '固定标签页', '')
      this.tabMenuItem('keepTabOpen', '保留标签页打开', '')
      this.tabMenuItem('editInNewWindow', '在新窗口中编辑源', '')
      this.tabMenuItem('configureTabs', '配置编辑器标签页…', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('reopenClosed', '重新打开已关闭的标签页', 'Ctrl+Shift+T')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('overrideType', '重写文件类型', '')
      this.tabMenuItem('revertType', '还原文件类型重写', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('run', '运行', 'Shift+F10')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('revealIn', '在文件管理器中显示', '')
      this.tabMenuItem('assocApp', '在关联的应用程序中打开', '')
      this.tabMenuItem('copyPath', '复制路径', 'Ctrl+Shift+C')
      this.tabMenuItem('findInFiles', '在文件中查找…', 'Ctrl+Shift+F')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      // ── EditorTabPopupMenuEx（去重 15 项）补齐 ──
      this.tabMenuItem('tab.changeLang', '更改文件语言', '')
      this.tabMenuItem('tab.associateType', '与文件类型关联…', '')
      this.tabMenuItem('tab.vcsHistory', '显示历史', '')
      this.tabMenuItem('tab.externalTools', '外部工具', '')
    }
    .width(250)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(this.theme.popupArc)
        .clip(true)
  }

  /** 编辑器右上 ⋮ 的弹层 = PyCharm TabList（TabListAction）：
   *  最近的文件 / 最近的位置 / 转到文件… / ── / 关闭所有标签页 / ── /
   *  书签打开标签页… / ── / 配置编辑器标签页… / 显示缩略图
   *  （条目与快捷键按 PyCharm 实机截图；TabListAction 见 PlatformActions.xml:883） */
  @Builder
  tabListMenu() {
    Column() {
      this.tabListItem('tl.recentFiles', '最近的文件', 'Ctrl+E')
      this.tabListItem('tl.recentPlaces', '最近的位置', 'Ctrl+Shift+E')
      this.tabListItem('tl.gotoFile', '转到文件…', 'Ctrl+Shift+N')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabListItem('tl.closeAll', '关闭所有标签页', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabListItem('tl.bookmarks', '书签打开标签页…', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabListItem('tl.configureTabs', '配置编辑器标签页…', '')
      this.tabListItem('tl.thumbnails', this.tabThumbnails ? '✓ 显示缩略图' : '显示缩略图', '')
      // 缩略图开启后：在弹层里列出打开的标签（PyCharm 的缩略图列表）
      if (this.tabThumbnails) {
        Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
        ForEach(this.tabs, (tab: EditorTab) => {
          this.tabListItem(`tl.tab:${tab.id}`, `　${tab.name}`, '')
        }, (tab: EditorTab) => `tl_${tab.id}`)
      }
    }
    .width(250)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(this.theme.popupArc)
    .clip(true)
  }

  private onTabListPick(id: string): void {
    FileService.log(`menuPick tablist id=${id}`);
    this.tabListShown = false;
    this.tabMenuShown = false;
    if (id === 'tl.recentFiles') {
      this.handleAction('view.recentFiles');
      return;
    }
    if (id === 'tl.recentPlaces') {
      this.dialogTitle = '最近的位置';
      this.dialog = 'recentLocations';
      return;
    }
    if (id.startsWith('tl.tab:')) {
      const tid: string = id.substring(7);
      const t: EditorTab | undefined = this.tabs.find((x: EditorTab) => x.id === tid);
      if (t !== undefined) {
        this.activateTab(t);
      }
      return;
    }
    if (id === 'tl.gotoFile') {
      this.handleAction('edit.searchEverywhere');
      return;
    }
    if (id === 'tl.closeAll') {
      this.onTabMenuPick('closeAll');
      return;
    }
    if (id === 'tl.bookmarks') {
      this.dialogTitle = '书签';
      this.dialog = 'bookmarks';
      return;
    }
    if (id === 'tl.configureTabs') {
      this.dialog = 'settings';
      this.dialogTitle = '设置';
      return;
    }
    if (id === 'tl.thumbnails') {
      this.tabThumbnails = !this.tabThumbnails;
      this.setStatus(`显示缩略图：${this.tabThumbnails ? '开' : '关'}`);
    }
  }

  private tabMenuOptions(): MenuOptions {
    const opt: MenuOptions = { offset: { x: -200, y: 6 } };
    return opt;
  }

  /** 标签栏 ⋮ 菜单的派发 */
  private onTabMenuPick(id: string): void {
    // 交互验证通道：点任意菜单项都写一行日志，便于用 hilog 确认"点了且派发到" 
    FileService.log(`menuPick tab id=${id}`);
    // ── EditorTabPopupMenu 新增项 ──
    if (id === 'copyPath2') {
      this.handleAction('edit.copyPath');
      return;
    }
    if (id === 'moveTabRight' || id === 'moveTabDown') {
      const t: EditorTab | undefined = this.activeTab();
      if (t !== undefined) {
        const i: number = this.tabs.findIndex((x: EditorTab) => x.id === t.id);
        const j: number = id === 'moveTabRight' ? i + 1 : i - 1;
        if (i >= 0 && j >= 0 && j < this.tabs.length) {
          const arr: EditorTab[] = this.tabs.slice();
          const tmp: EditorTab = arr[i];
          arr[i] = arr[j];
          arr[j] = tmp;
          this.tabs = arr;
          this.setStatus(`已移动标签：${t.name}`);
        }
      }
      return;
    }
    if (id === 'pinTab') {
      const t: EditorTab | undefined = this.activeTab();
      if (t !== undefined) {
        // Preview is pinned by setting it to a real (non-preview) tab
        t.preview = false;
        this.tabs = this.tabs.slice();
        this.setStatus(`已固定标签页：${t.name}`);
      }
      return;
    }
    if (id === 'keepTabOpen') {
      this.setStatus('标签页默认保留打开（本 IDE 无自动关闭机制）');
      return;
    }
    if (id === 'configureTabs') {
      this.dialog = 'settings';
      this.dialogTitle = '设置';
      return;
    }
    if (id === 'reopenClosed') {
      if (this.lastClosedPath.length > 0) {
        const p: string = this.lastClosedPath;
        this.lastClosedPath = '';
        const name: string = p.substring(p.lastIndexOf('/') + 1);
        this.openFile(p, name);
        this.setStatus(`已重新打开：${p}`);
      } else {
        this.setStatus('没有可重新打开的标签页');
      }
      return;
    }
    if (id === 'splitRight') {
      this.splitEditor('h');
      return;
    }
    if (id === 'splitDown') {
      this.splitEditor('v');
      return;
    }
    if (id === 'splitLeft') {
      this.splitEditor('h', true);
      return;
    }
    if (id === 'splitTop') {
      this.splitEditor('v', true);
      return;
    }
    if (id === 'splitCenter') {
      this.splitEditor('h', false, 0.5);
      return;
    }
    if (id === 'unsplit') {
      this.unsplitEditor(false);
      return;
    }
    if (id === 'unsplitAll') {
      this.unsplitEditor(true);
      return;
    }
    if (id === 'changeSplit') {
      if (this.paneSplit === 'h') {
        this.paneSplit = 'v';
      } else if (this.paneSplit === 'v') {
        this.paneSplit = 'h';
      }
      this.setStatus(`拆分方向：${this.paneSplit === 'h' ? '左右' : (this.paneSplit === 'v' ? '上下' : '无拆分')}`);
      return;
    }
    if (id === 'editInNewWindow') {
      this.showToast('独立窗口需要多窗口能力，本版本尚未实现');
      return;
    }
    FileService.log(`tab menu pick id=${id}`);
    // 顶栏右键菜单（MainToolbarPopupActions）也复用这套菜单项渲染，动作转发给 handleAction
    if (id === 'top.toolbar' || id === 'top.customize') {
      this.topMenuShown = false;
      this.handleAction(id);
      return;
    }
    if (id === 'close') {
      this.closeTab(this.activeTabId);
      return;
    }
    if (id === 'closeOthers') {
      this.handleAction('nav.closeOthers');
      return;
    }
    if (id === 'closeAll') {
      this.tabs = [];
      this.activeTabId = '';
      this.editorSeedText = '';
      this.editorFilePath = '';
      this.liveStructure = [];
      this.setStatus('已关闭全部标签页');
      return;
    }
    if (id === 'closeUnpinned' || id === 'closeReadonly') {
      this.tabs = [];
      this.activeTabId = '';
      this.editorSeedText = '';
      this.editorFilePath = '';
      this.liveStructure = [];
      this.setStatus(id === 'closeUnpinned'
        ? '已关闭所有未固定标签页（本版本无固定概念，等同全部关闭）'
        : '已关闭所有只读标签页（本版本无只读标签，等同全部关闭）');
      return;
    }
    if (id === 'closeLeft' || id === 'closeRight') {
      let index: number = -1;
      for (let i = 0; i < this.tabs.length; i++) {
        if (this.tabs[i].id === this.activeTabId) {
          index = i;
        }
      }
      if (index < 0) {
        return;
      }
      const keep: EditorTab[] = [];
      for (let i = 0; i < this.tabs.length; i++) {
        const drop: boolean = id === 'closeLeft' ? i < index : i > index;
        if (!drop) {
          keep.push(this.tabs[i]);
        }
      }
      this.tabs = keep;
      this.setStatus(id === 'closeLeft' ? '已关闭左侧标签页' : '已关闭右侧标签页');
      return;
    }
    if (id === 'oppositeGroup' || id === 'openOpposite') {
      // 多窗格模型：移至相反的组 = 标签移入第 2 窗格；在相反的组中打开 = 第 2 窗格也显示同一文件
      const t: EditorTab | undefined = this.activeTab();
      if (t === undefined) {
        this.showToast('没有可操作的编辑器');
        return;
      }
      if (this.pane2Tabs.indexOf(t.id) < 0) {
        const next: string[] = this.pane2Tabs.slice();
        next.push(t.id);
        this.pane2Tabs = next;
      }
      if (this.paneSplit === 'none') {
        this.paneSplit = 'h';
      }
      this.setStatus(id === 'openOpposite'
        ? `已在第 2 窗格打开 ${t.name}`
        : `已把 ${t.name} 移到第 2 窗格`);
      this.handleAction('view.splitRight');
      this.setStatus(id === 'openOpposite' ? '已在右侧组中打开当前文件' : '已把当前文件移至右侧组');
      return;
    }
    if (id === 'run') {
      this.handleAction('run.run');
      return;
    }
    if (id === 'revealIn' || id === 'assocApp') {
      this.showInfo(id === 'revealIn' ? '在文件管理器中显示' : '在关联的应用程序中打开', [
        'HarmonyOS 应用沙箱没有系统文件管理器/关联应用入口，无法从 IDE 外部打开。',
        '可以直接在左侧工程树里浏览；工程目录也可用「终端」里的 Python 脚本操作。'
      ]);
      return;
    }
    if (id === 'overrideType' || id === 'revertType') {
      this.showInfo('文件类型', [
        'PyCharm 允许为单个文件重写文件类型（影响高亮与解析）。',
        '本 IDE 按扩展名判定：.py / .pyw → Python 高亮，其余按纯文本。'
      ]);
      return;
    }
    if (id === 'split') {
      this.handleAction('view.splitRight');
      return;
    }
    if (id.startsWith('tree.')) {
      this.onTreeMenuPick(id);
      return;
    }
    if (id.startsWith('ed.')) {
      this.onEditorMenuPick(id);
      return;
    }
    if (id.startsWith('tw.')) {
      this.onToolWindowMenuPick(id);
      return;
    }
    if (id === 'copyPath') {
      this.handleAction('edit.copyPath');
      return;
    }
    if (id === 'findInFiles') {
      this.handleAction('edit.findInFiles');
      return;
    }
    // ── EditorTabPopupMenuEx 新增项 ──
    if (id === 'tab.changeLang') {
      const t: EditorTab | undefined = this.activeTab();
      if (t !== undefined) {
        this.treeMenuPath = t.path;
        this.onTreeMenuPick('tree.changeLang');
      }
      return;
    }
    if (id === 'tab.associateType' || id === 'tab.vcsHistory' || id === 'tab.externalTools') {
      this.showToast('该功能需要文件类型注册 / VCS 集成 / 外部工具配置，本版本尚未实现');
      return;
    }
    this.handleAction('view.recentFiles');
  }

  /** 分屏第二格选哪个标签：优先选非当前标签，没有就复用当前 */
  private pickSplitTab(): string {
    for (const tab of this.tabs) {
      if (tab.id !== this.activeTabId) {
        return tab.id;
      }
    }
    return this.activeTabId;
  }

  /** 分屏第二格对应的标签 */
  private splitTab(): EditorTab | undefined {
    for (const tab of this.tabs) {
      if (tab.id === this.splitTabId) {
        return tab;
      }
    }
    return this.activeTab();
  }

  /** 分屏第二格的文本 */
  private splitText(): string {
    const tab: EditorTab | undefined = this.splitTab();
    return tab !== undefined ? tab.text : '';
  }

  /** 分屏第二格的文件路径 */
  private splitPath(): string {
    const tab: EditorTab | undefined = this.splitTab();
    return tab !== undefined ? tab.path : '';
  }

  /** 刷新 Structure 面板：扫描文本里的类与函数（PyCharm 的 Structure 工具窗） */
  private refreshStructure(text: string): void {
    const out: string[] = [];
    const lines: string[] = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.startsWith('def ') || line.startsWith('async def ')) {
        const name: string = this.identifierAfter(line, line.startsWith('async def ') ? 10 : 4);
        if (name.length > 0) {
          out.push(`ƒ  ${name}`);
        }
      } else if (line.startsWith('class ')) {
        const name: string = this.identifierAfter(line, 6);
        if (name.length > 0) {
          out.push(`C  ${name}`);
        }
      }
    }
    this.liveStructure = out;
    // 异步改用 ast 真解析覆盖（能给出真实嵌套层级与行号）；失败则保留正则结果
    this.refreshAstStructure();
  }

  /** 用运行时 Python ast 刷新 Structure 面板（真解析：嵌套、async、装饰器都不会漏）*/
  private async refreshAstStructure(): Promise<void> {
    const file: string = this.editorFilePath;
    if (file.length === 0) {
      return;
    }
    try {
      const dir: string = `${FileService.context().filesDir}/.harmonyide`;
      FileService.ensureDir(dir);
      FileService.ensureDir(`${FileService.context().filesDir}/.harmonyide`);
      const script: string = `${dir}/ast_scope.py`;
      const out: string = `${FileService.context().filesDir}/.harmonyide/scope.txt`;
      FileService.writeText(script, SCOPE_AST_SCRIPT);
      const txt: string = await this.runPyAndRead(script, [file, out], out);
      if (txt.length === 0) {
        return;
      }
      const rows: string[] = txt.split('\n');
      const outRows: string[] = [];
      for (const row of rows) {
        const m: RegExpMatchArray | null = row.match(/^(\s*)(类|函数|async 函数)\s+([A-Za-z_][A-Za-z0-9_]*)\s+L(\d+)/);
        if (m === null) {
          continue;
        }
        const indent: string = m[1].substring(1);
        const kind: string = m[2];
        const name: string = m[3];
        const line: string = m[4];
        const prefix: string = kind === '类' ? 'C' : (kind === 'async 函数' ? 'ƒa' : 'ƒ');
        // 带上「被引用 N」（ast 统计的 Load 上下文引用次数，等价于查找用法的计数）
        const mRef: RegExpMatchArray | null = row.match(/被引用\s*(\d+)/);
        const refTxt: string = mRef !== null ? `  ·  引用 ${mRef[1]}` : '';
        outRows.push(`${indent}${prefix}  ${name}    L${line}${refTxt}`);
      }
      if (outRows.length > 0) {
        this.liveStructure = outRows;
        FileService.log(`ast structure rows=${outRows.length}`);
      }
    } catch (e) {
      FileService.log('ast structure failed');
    }
  }

  /** 文件结构（PyCharm 的 Structure 工具窗轻量版）：扫描当前文件的导入/类/函数 */
  private openFileStructure(): void {
    this.structureSymbols = [];
    const lines: string[] = this.editorSeedText.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.startsWith('def ') || line.startsWith('async def ')) {
        const name: string = this.identifierAfter(line, line.startsWith('async def ') ? 10 : 4);
        if (name.length > 0) {
          this.structureSymbols.push(`函数  ${name}    第 ${i + 1} 行`);
        }
      } else if (line.startsWith('class ')) {
        const name: string = this.identifierAfter(line, 6);
        if (name.length > 0) {
          this.structureSymbols.push(`类    ${name}    第 ${i + 1} 行`);
        }
      } else if (line.startsWith('import ') || line.startsWith('from ')) {
        this.structureSymbols.push(`导入  ${line}    第 ${i + 1} 行`);
      }
    }
    if (this.structureSymbols.length === 0) {
      this.structureSymbols.push('（当前文件没有可识别的定义，或还没有打开文件）');
    }
    this.dialog = 'fileStructure';
  }

  /** 从 line[start] 开始取一段标识符 */
  private identifierAfter(line: string, start: number): string {
    let name: string = '';
    for (let i: number = start; i < line.length; i++) {
      const ch: string = line.charAt(i);
      const isWord: boolean = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
        || (ch >= '0' && ch <= '9') || ch === '_';
      if (!isWord) {
        break;
      }
      name += ch;
    }
    return name;
  }

  /** 运行配置文件路径（沙箱内，随工程持久化） */
  private runConfigPath(): string {
    return `${FileService.projectRoot()}/runconfig.json`;
  }

  /** 读取运行配置（不存在时用默认值） */
  private loadRunConfig(): void {
    const tab: EditorTab | undefined = this.activeTab();
    this.cfgScript = tab !== undefined ? tab.path : '';
    try {
      const raw: string = FileService.readText(this.runConfigPath());
      const model: RunConfigModel = JSON.parse(raw) as RunConfigModel;
      if (model.name.length > 0) {
        this.cfgName = model.name;
      }
      this.cfgArgs = model.args;
      this.cfgCwd = model.cwd;
      this.cfgEnv = model.env;
    } catch (err) {
      // 首次使用：只有默认值
      this.cfgArgs = '';
      this.cfgCwd = FileService.projectRoot();
      this.cfgEnv = '';
    }
  }

  /** 保存运行配置到磁盘 */
  private saveRunConfig(): void {
    const model: RunConfigModel = new RunConfigModel();
    model.name = this.cfgName;
    model.script = this.cfgScript;
    model.args = this.cfgArgs;
    model.cwd = this.cfgCwd;
    model.env = this.cfgEnv;
    try {
      FileService.writeText(this.runConfigPath(), JSON.stringify(model));
      this.showToast(`已保存运行配置「${this.cfgName}」`);
    } catch (err) {
      this.appendError(`保存运行配置失败：${JSON.stringify(err)}`);
    }
  }

  /** 运行配置对话框内容（PyCharm 的 Edit Configurations 轻量版） */
  @Builder
  RunConfigContent() {
    Column() {
      this.CfgRow('配置名', this.cfgName, 'name')
      this.CfgRow('脚本路径', this.cfgScript, 'script')
      this.CfgRow('程序参数', this.cfgArgs, 'args')
      this.CfgRow('工作目录', this.cfgCwd, 'cwd')
      this.CfgRow('环境变量', this.cfgEnv, 'env')

      Row() {
        Text('保存配置')
          .fontSize(12)
          .fontColor(this.theme.textOnAccent)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonPrimaryBg)
          .onClick(() => this.saveRunConfig())
        Text('恢复默认')
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .margin({ left: 10 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => {
            const tab: EditorTab | undefined = this.activeTab();
            this.cfgName = '当前文件';
            this.cfgScript = tab !== undefined ? tab.path : '';
            this.cfgArgs = '';
            this.cfgCwd = FileService.projectRoot();
            this.cfgEnv = '';
          })
      }
      .width('100%')
      .margin({ top: 6 })

      Text('说明：脚本路径/参数/工作目录会随工程保存到 runconfig.json；'
        + '本次运行会在控制台打印实际使用的配置。')
        .fontSize(11)
        .fontColor(this.theme.textSecondary)
        .width('100%')
        .margin({ top: 10 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 运行配置对话框里的一行（标签 + 输入框） */
  @Builder
  CfgRow(label: string, value: string, key: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor(this.theme.textPrimary)
        .width(84)
      TextInput({ text: value })
        .layoutWeight(1)
        .height(28)
        .fontSize(12)
        .fontFamily(PyFont.mono)
        .fontColor(this.theme.textPrimary)
        .caretColor(this.theme.caret)
        .backgroundColor(this.theme.inputBg)
        .borderRadius(4)
        .onChange((text: string) => {
          if (key === 'name') {
            this.cfgName = text;
          } else if (key === 'script') {
            this.cfgScript = text;
          } else if (key === 'args') {
            this.cfgArgs = text;
          } else if (key === 'cwd') {
            this.cfgCwd = text;
          } else {
            this.cfgEnv = text;
          }
        })
    }
    .width('100%')
    .margin({ bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  /** 键盘快捷方式表（PyCharm 的 Help → Keymap 轻量版） */
  @Builder
  ShortcutsContent() {
    Scroll() {
      Column() {
        ForEach(SHORTCUT_TABLE, (row: string) => {
          Text(row)
            .fontSize(12)
            .fontFamily(PyFont.mono)
            .fontColor(this.theme.textPrimary)
            .width('100%')
            .padding({ top: 4, bottom: 4 })
        }, (row: string, index: number) => `sc-${index}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .height(280)
    .width('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Auto)
  }

  /** 第三方组件与许可 */
  @Builder
  LicensesContent() {
    Scroll() {
      Column() {
        ForEach(LICENSE_TABLE, (row: string) => {
          Text(row)
            .fontSize(12)
            .fontFamily(PyFont.mono)
            .fontColor(this.theme.textPrimary)
            .width('100%')
            .padding({ top: 4, bottom: 4 })
        }, (row: string, index: number) => `lic-${index}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .height(280)
    .width('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Auto)
  }

  /**
   * PyCharm 的项目树在工程根之后永远还有两个固定节点：
   *   外部库（External Libraries）、临时文件和控制台（Scratches and Consoles）
   * 这里按需补上（只补一次，节点对象全程复用）。
   */
  private ensureSyntheticRoots(): void {
    let hasLib: boolean = false;
    let hasScratch: boolean = false;
    for (const n of this.treeRoots) {
      if (n.path === EXT_LIB_PATH) {
        hasLib = true;
      } else if (n.path === SCRATCH_PATH) {
        hasScratch = true;
      }
    }
    if (!hasLib) {
      const lib = new FileNode('外部库', EXT_LIB_PATH, true, 0);
      lib.synthetic = true;
      // expui/nodes/library.svg
      lib.iconFile = 'icons/library.svg';
      this.treeRoots.push(lib);
    }
    // ProjectView.ShowScratchesAndConsoles：关掉时该节点整体不显示
    if (hasScratch && !this.optShowScratches) {
      this.treeRoots = this.treeRoots.filter((n: FileNode) => n.path !== SCRATCH_PATH);
      hasScratch = false;
    }
    if (!hasScratch && this.optShowScratches) {
      const scr = new FileNode('临时文件和控制台', SCRATCH_PATH, true, 0);
      scr.synthetic = true;
      // expui/fileTypes/scratches.svg
      scr.iconFile = 'icons/scratches.svg';
      this.treeRoots.push(scr);
    }
  }

  /** 合成节点的子节点：外部库给运行时信息，临时文件给真实目录内容 */
  private loadSyntheticChildren(node: FileNode): void {
    const kids: FileNode[] = [];
    if (node.path === EXT_LIB_PATH) {
      const pyLabel: string = this.runtime.ready ? `Python ${this.runtime.version.split(' ')[0]}` : 'Python 未就绪';
      const py = new FileNode(pyLabel, `${EXT_LIB_PATH}/python`, false, 1);
      py.synthetic = true;
      py.iconFile = 'icons/libraryFolder.svg';
      py.infoText = '内嵌 CPython（静态链接进 libpythonbridge.so，随应用进程运行）';
      kids.push(py);
      const site = new FileNode('site-packages', `${EXT_LIB_PATH}/site-packages`, false, 1);
      site.synthetic = true;
      site.iconFile = 'icons/libraryFolder.svg';
      site.infoText = '第三方包目录（pip install 的落点）：' + FileService.sitePackagesDir();
      kids.push(site);
      const abi = new FileNode(`ABI ${this.runtime.abi.length > 0 ? this.runtime.abi : '—'}`,
        `${EXT_LIB_PATH}/abi`, false, 1);
      abi.synthetic = true;
      abi.iconFile = 'icons/libraryFolder.svg';
      abi.infoText = '原生库目标 ABI';
      kids.push(abi);
    } else if (node.path === SCRATCH_PATH) {
      const dir: string = scratchDir();
      FileService.ensureDir(dir);
      const real: FileNode[] = FileService.listDir(dir, 1);
      for (const r of real) {
        kids.push(r);
      }
      if (kids.length === 0) {
        const hint = new FileNode('（暂无临时文件）', `${SCRATCH_PATH}/empty`, false, 1);
        hint.synthetic = true;
        hint.infoText = `临时文件目录：${dir}\n在编辑器里「另存为」到该目录即可出现在这里。`;
        kids.push(hint);
      }
    }
    node.children = kids;
    node.loaded = true;
  }

  /**
   * 构建"视图树"：排序（可选目录优先）+ 压缩中间目录（PyCharm 的 Compact Middle Packages），
   * 并重算 depth（压缩后行少了一层，子节点缩进必须跟着变）。真实树 treeRoots 不动。
   */
  private buildViewTree(nodes: FileNode[], depth: number): FileNode[] {
    const list: FileNode[] = nodes.slice();
    // 只对目录内部排序：depth 0 是"工程根 → 外部库 → 临时文件和控制台"，顺序固定（PyCharm 也是这样）
    if (this.treeDirsFirst && depth > 0) {
      list.sort((a: FileNode, b: FileNode) => {
        if (a.isDir !== b.isDir) {
          return a.isDir ? -1 : 1;
        }
        return a.name.toLowerCase() < b.name.toLowerCase() ? -1
          : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0);
      });
    }
    const out: FileNode[] = [];
    for (const n of list) {
      // ProjectView.ShowExcludedFiles：关闭时不显示排除目录（.venv/__pycache__/.idea…）
      if (!this.optShowExcluded && n.isDir && depth > 0 && isExcludedDirName(n.name)) {
        continue;
      }
      const v = new FileNode(n.name, n.path, n.isDir, depth);
      v.expanded = n.expanded;
      v.loaded = n.loaded;
      v.synthetic = n.synthetic;
      v.iconFile = n.iconFile;
      v.infoText = n.infoText;
      // 树是懒加载的：未展开的目录 children 为空，压缩规则就看不到"唯一子目录"。
      // 压缩开启时，对可见目录先取一层（只对可见行做，规模有界）。
      if (this.treeCompactDirs && n.isDir && !n.loaded && !n.synthetic) {
        FileService.loadChildren(n);
      }
      let target: FileNode = n;
      if (this.treeCompactDirs && n.isDir && !n.expanded) {
        // 只有一个子目录（且该子目录也折叠）时，整条链并成一行：a/b/c
        let label: string = n.name;
        let cur: FileNode = n;
        for (;;) {
          // PyCharm 判"唯一子包"时忽略 __init__.py，否则每个 Python 包都因为有它而压不起来。
          // 注意：链是否合并只看"唯一子目录"，与子目录自身是否展开无关 ——
          // 合并行的展开态取自链尾节点，展开后子行挂在合并行下面（PyCharm 就是这个行为）。
          const kids: FileNode[] = cur.children.filter((c: FileNode) =>
            c.name.toLowerCase() !== '__init__.py');
          if (kids.length !== 1 || !kids[0].isDir) {
            break;
          }
          cur = kids[0];
          label = `${label}/${cur.name}`;
        }
        if (cur !== n) {
          v.name = label;
          v.path = cur.path;
          v.expanded = cur.expanded;
          target = cur;
        }
      }
      v.children = this.buildViewTree(target.children, depth + 1);
      out.push(v);
    }
    return out;
  }

  private refreshFlatten(): void {
    this.ensureSyntheticRoots();
    const out: FileNode[] = [];
    // 用"视图树"（排序 + 可选压缩目录）刷新，而不是直接 flatten 真实树
    FileService.flatten(this.buildViewTree(this.treeRoots, 0), out);
    if (this.filterText.length === 0) {
      this.flatNodes = out;
      return;
    }
    const filtered: FileNode[] = [];
    for (const node of out) {
      if (FileService.matchesFilter(node, this.filterText)) {
        filtered.push(node);
      }
    }
    this.flatNodes = filtered;
  }

  /**
   * 在项目树中定位当前打开的文件（PyCharm 的 SelectInProjectView / 滚动到源）：
   * 先逐级展开祖先目录保证目标行存在，再选中并让树滚到该行。
   */
  private locateActiveInTree(): void {
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined) {
      this.setStatus('没有打开的文件可定位');
      return;
    }
    this.revealActiveInTree();
    FileService.log(`locateInTree file=${tab.path} tick=${this.locateTick}`);
    this.setStatus(`已在项目树中定位 ${tab.name}`);
  }

  /**
   * 只做"展开祖先 + 选中 + 滚动"，不改状态栏。
   * 「始终选择打开的文件」（ProjectView.AutoscrollFromSource）在切标签时也走这里。
   */
  private revealActiveInTree(): void {
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined) {
      return;
    }
    const parts: string[] = tab.path.split('/');
    let cur: string = '';
    for (let i = 0; i < parts.length - 1; i++) {
      cur = cur.length === 0 ? parts[i] : `${cur}/${parts[i]}`;
      const node: FileNode | undefined = this.findNode(this.treeRoots, cur);
      if (node !== undefined && node.isDir && !node.expanded) {
        if (!node.loaded) {
          FileService.loadChildren(node);
        }
        node.expanded = true;
      }
    }
    this.selectedPath = tab.path;
    this.refreshFlatten();
    this.treeRoots = this.treeRoots.slice();
    this.flatNodes = this.flatNodes.slice();
    this.locateTick = this.locateTick + 1;
    FileService.log(`revealInTree file=${tab.name} tick=${this.locateTick}`);
  }

  private toggleDirByPath(path: string): void {
    const node: FileNode | undefined = this.findNode(this.treeRoots, path);
    if (node === undefined) {
      return;
    }
    if (!node.loaded) {
      if (node.synthetic) {
        this.loadSyntheticChildren(node);
      } else {
        FileService.loadChildren(node);
      }
    }
    node.expanded = !node.expanded;
    this.refreshFlatten();
    this.treeRoots = this.treeRoots.slice();
    this.flatNodes = this.flatNodes.slice();
  }

  private findNode(nodes: FileNode[], path: string): FileNode | undefined {
    for (const node of nodes) {
      if (node.path === path) {
        return node;
      }
      if (node.isDir && node.children.length > 0) {
        const found: FileNode | undefined = this.findNode(node.children, path);
        if (found !== undefined) {
          return found;
        }
      }
    }
    return undefined;
  }

  private refreshDir(path: string): void {
    if (path === this.projectRoot) {
      this.treeRoots = [this.makeRootNode()];
    } else {
      const node: FileNode | undefined = this.findNode(this.treeRoots, path);
      if (node !== undefined) {
        FileService.loadChildren(node);
      }
    }
    this.refreshFlatten();
    this.treeRoots = this.treeRoots.slice();
    this.flatNodes = this.flatNodes.slice();
    this.setStatus('已刷新');
  }

  // ── 标签页 ─────────────────────────────────────────────────────────────

  /** 在标签页之间循环（导航菜单用） */
  private cycleTab(delta: number): void {
    if (this.tabs.length === 0) {
      return;
    }
    let index: number = 0;
    for (let i = 0; i < this.tabs.length; i++) {
      if (this.tabs[i].id === this.activeTabId) {
        index = i;
      }
    }
    const next: number = (index + delta + this.tabs.length) % this.tabs.length;
    this.activateTab(this.tabs[next]);
  }

  private activeTab(): EditorTab | undefined {
    for (const tab of this.tabs) {
      if (tab.id === this.activeTabId) {
        return tab;
      }
    }
    return undefined;
  }

  /**
   * 打开文件。
   * preview=true 且「启用预览标签页」开启时：复用/顶替现有预览标签（ProjectView.OpenInPreviewTab，PyCharm 默认开）；
   * 再次点同一行（或从其它入口打开）会把它"钉住"为普通标签。
   */
  /**
   * TabList → 最近的位置：记录 path#line（去重、最新在前、最多 20 条）。
   * PyCharm 的 Recent Locations 记录"跳转过的位置"，这里覆盖 打开文件 / 转到行 / 结构跳转。
   */
  private recordLocation(path: string, line: number): void {
    if (path.length === 0) {
      return;
    }
    const entry: string = `${path}#${line}`;
    const rest: string[] = this.recentLocations.filter((x: string) => x !== entry);
    rest.unshift(entry);
    this.recentLocations = rest.slice(0, 20);
  }

  /** TabList → 书签：切换当前行书签（PyCharm 的 ToggleBookmark，F11） */
  private toggleBookmark(): void {
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined) {
      this.showToast('没有打开的编辑器');
      return;
    }
    const entry: string = `${tab.path}#${this.cursorLine}`;
    if (this.bookmarks.indexOf(entry) >= 0) {
      this.bookmarks = this.bookmarks.filter((x: string) => x !== entry);
      this.setStatus(`已移除书签：${tab.name}:${this.cursorLine}`);
    } else {
      const next: string[] = this.bookmarks.slice();
      next.unshift(entry);
      this.bookmarks = next;
      this.setStatus(`已添加书签：${tab.name}:${this.cursorLine}`);
    }
  }

  /** 书签 / 最近位置条目 → 打开文件并跳到该行 */
  private openLocationEntry(entry: string): void {
    const hash: number = entry.lastIndexOf('#');
    const path: string = entry.substring(0, hash);
    const line: number = Number.parseInt(entry.substring(hash + 1), 10);
    const name: string = path.substring(path.lastIndexOf('/') + 1);
    this.openFile(path, name);
    if (!Number.isNaN(line) && line > 0) {
      this.editorController.revealLine(line);
    }
    this.setStatus(`已打开 ${name}:${line}`);
  }

  private openFile(path: string, name: string, preview: boolean = false): void {
    this.recordLocation(path, 1);
    // 合成节点（外部库/临时文件提示行）不是真实文件：显示说明而不是去打开
    if (path.startsWith('synthetic://')) {
      const node: FileNode | undefined = this.findNode(this.treeRoots, path);
      const text: string = (node !== undefined && node.infoText.length > 0)
        ? node.infoText : `${name}：PyCharm 项目树固定节点（本 IDE 以合成节点实现）`;
      this.showInfo(name, text.split('\n'));
      return;
    }
    this.rememberRecent(path);
    FileService.log(`openFile path=${path}`);
    const asPreview: boolean = preview && this.optPreviewTab;
    for (const tab of this.tabs) {
      if (tab.id === path) {
        if (tab.preview && !asPreview) {
          tab.preview = false;      // 第二次点击 = 钉住
          this.tabs = this.tabs.slice();
        }
        this.activateTab(tab);
        return;
      }
    }
    if (!FileService.exists(path)) {
      FileService.log(`openFile SKIP not-exists ${path}`);
      this.appendError(`文件不存在：${path}`);
      return;
    }
    let content: string = '';
    try {
      content = FileService.readText(path);
    } catch (err) {
      FileService.log(`openFile READ FAILED ${path} err=${JSON.stringify(err)}`);
      this.appendError(`读取失败：${path}\n${JSON.stringify(err)}`);
      return;
    }
    if (asPreview) {
      // 同一时刻只保留一个预览标签：新预览顶替旧的
      const idx: number = this.tabs.findIndex((t: EditorTab) => t.preview);
      if (idx >= 0) {
        this.tabs.splice(idx, 1);
      }
    }
    const tab = new EditorTab(path, name, content);
    tab.breakpoints = this.loadBreakpoints(path);
    tab.preview = asPreview;
    this.tabs.push(tab);
    this.tabs = this.tabs.slice();
    this.activateTab(tab);
    this.selectedPath = path;
    FileService.log(`openFile OK tabs=${this.tabs.length} active=${this.activeTabId}`);
  }

  private activateTab(tab: EditorTab): void {
    this.notify(`打开文件 ${tab.name}`);
    // ProjectView.AutoscrollFromSource（始终选择打开的文件）：切到该标签时让树选中并滚过去
    if (this.optAutoscrollFromSource) {
      this.revealActiveInTree();
    }
    this.activeTabId = tab.id;
    this.selectedPath = tab.path;
    this.editorSeedText = tab.text;
    this.editorFilePath = tab.path;
    this.pendingBreakpoints = tab.breakpoints.slice();
    this.cursorLine = tab.cursorLine;
    this.cursorColumn = tab.cursorColumn;
    this.setStatus(`已打开 ${tab.name}`);
  }

  private closeTab(id: string): void {
    const index: number = this.tabs.findIndex((tab: EditorTab) => tab.id === id);
    if (index < 0) {
      return;
    }
    const tab: EditorTab = this.tabs[index];
    if (tab.dirty) {
      this.saveTab(tab);
    }
    // EditorTabPopupMenu: ReopenClosedTab 用
    this.lastClosedPath = tab.path;
    this.tabs.splice(index, 1);
    this.tabs = this.tabs.slice();
    if (this.activeTabId === id) {
      if (this.tabs.length === 0) {
        this.activeTabId = '';
        this.editorSeedText = '';
        this.editorFilePath = '';
      } else {
        const next: EditorTab = this.tabs[Math.min(index, this.tabs.length - 1)];
        this.activateTab(next);
      }
    }
  }

  private saveTab(tab: EditorTab): void {
    try {
      this.snapshotBeforeSave(tab.path);
      FileService.writeText(tab.path, tab.text);
      tab.markSaved(tab.text);
      this.tabs = this.tabs.slice();
      this.setStatus(`已保存 ${tab.name}`);
      // PyCharm 语义：保存后自动跑检查并刷新「问题」视图（静默，不弹对话框）
      this.runInspection(false);
    } catch (err) {
      this.appendError(`保存失败：${tab.path}\n${JSON.stringify(err)}`);
    }
  }

  private saveActive(): void {
    const tab: EditorTab | undefined = this.activeTab();
    if (tab !== undefined) {
      this.saveTab(tab);
    }
  }

  private saveAll(): void {
    for (const tab of this.tabs) {
      if (tab.dirty) {
        this.saveTab(tab);
      }
    }
    this.setStatus('全部已保存');
  }

  /** 断点列表（PyCharm XDebugger: View Breakpoints）*/
  private openBreakpoints(): void {
    const store: Record<string, number[]> = this.allBreakpoints();
    const rows: string[] = [];
    const keys: string[] = [];
    const lines: number[] = [];
    const fileKeys: string[] = Object.keys(store);
    for (const f of fileKeys) {
      const nums: number[] = store[f];
      const base: string = f.substring(f.lastIndexOf('/') + 1);
      for (const n of nums) {
        rows.push(`${base}:${n}`);
        keys.push(f);
        lines.push(n);
      }
    }
    this.bpRows = rows;
    this.bpKeys = keys;
    this.bpLines = lines;
    this.dialogTitle = `断点（${rows.length}）`;
    this.dialog = 'breakpoints';
    this.setStatus(`共 ${rows.length} 个断点`);
  }

  /** 删除单个断点（写回存储；若删除的是当前文件则同步编辑器标记）*/
  private removeBreakpoint(key: string, line: number): void {
    const store: Record<string, number[]> = this.allBreakpoints();
    const nums: number[] | undefined = store[key];
    if (nums === undefined) {
      return;
    }
    const next: number[] = [];
    for (const n of nums) {
      if (n !== line) {
        next.push(n);
      }
    }
    store[key] = next;
    FileService.writeText(this.breakpointStorePath(), JSON.stringify(store));
    const tab: EditorTab | undefined = this.activeTab();
    if (tab !== undefined && tab.path === key) {
      tab.breakpoints = next.slice();
      this.pendingBreakpoints = next.slice();
      this.tabs = this.tabs.slice();
    }
    this.openBreakpoints();
  }

  /** 清空全部断点 */
  private clearAllBreakpoints(): void {
    FileService.writeText(this.breakpointStorePath(), JSON.stringify({}));
    const tab: EditorTab | undefined = this.activeTab();
    if (tab !== undefined) {
      tab.breakpoints = [];
      this.pendingBreakpoints = [];
      this.tabs = this.tabs.slice();
    }
    this.openBreakpoints();
    this.setStatus('已清除全部断点');
  }

  private breakpointStorePath(): string {
    return `${FileService.context().filesDir}/breakpoints.json`;
  }

  private allBreakpoints(): Record<string, number[]> {
    const path: string = this.breakpointStorePath();
    if (!FileService.exists(path)) {
      return {};
    }
    try {
      const parsed: Record<string, number[]> = JSON.parse(FileService.readText(path)) as Record<string, number[]>;
      return parsed;
    } catch (err) {
      return {};
    }
  }

  private loadBreakpoints(filePath: string): number[] {
    const store: Record<string, number[]> = this.allBreakpoints();
    const value: number[] | undefined = store[filePath];
    return value === undefined ? [] : value;
  }

  private toggleBreakpoint(line: number): void {
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined) {
      return;
    }
    const index: number = tab.breakpoints.indexOf(line);
    if (index >= 0) {
      tab.breakpoints.splice(index, 1);
    } else {
      tab.breakpoints.push(line);
    }
    tab.breakpoints.sort((a: number, b: number) => a - b);
    this.pendingBreakpoints = tab.breakpoints.slice();
    const store: Record<string, number[]> = this.allBreakpoints();
    store[tab.path] = tab.breakpoints.slice();
    FileService.writeText(this.breakpointStorePath(), JSON.stringify(store));
    this.tabs = this.tabs.slice();
  }

  // ── 控制台输出 ─────────────────────────────────────────────────────────

  /** ConsoleView.PopupMenu: PauseOutput —— 暂停/恢复控制台输出 */
  private togglePauseOutput(): void {
    this.consolePaused = !this.consolePaused;
    if (!this.consolePaused && this.consolePending.length > 0) {
      const n: number = this.consolePending.length;
      for (const e of this.consolePending) {
        this.logEntries.push(e);
      }
      this.consolePending = [];
      this.logEntries = this.logEntries.slice();
      this.setStatus(`已恢复输出（补入 ${n} 条）`);
      return;
    }
    this.setStatus(this.consolePaused ? '已暂停输出（新输出进缓冲）' : '已恢复输出');
  }

  private appendEntry(stream: string, text: string): void {
    if (text.length === 0) {
      return;
    }
    this.logSeq++;
    const entry: LogEntry = new LogEntry(this.logSeq, stream, text, Date.now());
    // ConsoleView.PopupMenu: PauseOutput —— 暂停期间进缓冲，恢复时一次性补入
    if (this.consolePaused) {
      this.consolePending.push(entry);
      if (this.consolePending.length > MAX_LOG_ENTRIES) {
        this.consolePending.splice(0, this.consolePending.length - MAX_LOG_ENTRIES);
      }
      this.consolePending = this.consolePending.slice();
      return;
    }
    this.logEntries.push(entry);
    if (this.logEntries.length > MAX_LOG_ENTRIES) {
      this.logEntries.splice(0, this.logEntries.length - MAX_LOG_ENTRIES);
    }
    this.logEntries = this.logEntries.slice();
  }

  private appendOutput(stream: number, text: string): void {
    this.appendEntry(stream === 0 ? 'stdout' : 'stderr', text);
  }

  private appendSystem(text: string): void {
    this.appendEntry('system', text.endsWith('\n') ? text : text + '\n');
  }

  private appendError(text: string): void {
    this.appendEntry('stderr', text.endsWith('\n') ? text : text + '\n');
  }

  private setStatus(message: string): void {
    this.statusMessage = message;
  }

  private showToast(message: string): void {
    this.toast = message;
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout(() => {
      this.toast = '';
      this.toastTimer = -1;
    }, 2600);
  }

  // ── 运行 / 调试 / pip ──────────────────────────────────────────────────

  private async runActiveFile(debug: boolean, args: string[] = []): Promise<void> {
    if (this.running) {
      this.showToast('已有脚本正在运行');
      return;
    }
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined) {
      this.showToast('请先打开一个 .py 文件');
      return;
    }
    if (!tab.path.endsWith('.py')) {
      this.showToast('只能运行 .py 文件');
      return;
    }
    this.saveTab(tab);
    this.consoleTab = 'run';
    if (!this.settings.showBottomToolWindow) {
      this.settings.showBottomToolWindow = true;
    }
    this.logEntries = [];
    this.appendEntry('command', `python ${tab.path}${args.length > 0 ? ' ' + args.join(' ') : ''}\n`);
    if (debug) {
      this.appendSystem('提示：断点已在编辑器标出，但断点调试（逐行执行/变量面板）仍在路线图中，'
        + '当前先按普通运行执行。');
    }
    this.running = true;
    this.hasRunOnce = true;
    // PyCharm：运行/Run 工具窗会自动弹出（否则用户看不到输出）
    this.settings.showBottomToolWindow = true;
    this.consoleTab = 'run';
    this.setStatus(`正在运行 ${tab.name} …`);
    const result: RunResult = await PyRuntimeService.run(tab.path, args);
    this.running = false;
    if (result.stdout.length > 0) {
      this.appendEntry('stdout', result.stdout);
    }
    if (result.stderr.length > 0) {
      this.appendEntry('stderr', result.stderr);
    }
    if (result.code === 0) {
      this.appendEntry('success', `\n进程已结束，退出代码 0（耗时 ${result.durationMs} ms）\n`);
      this.setStatus(`${tab.name} 运行完成`);
    } else {
      this.appendEntry('stderr', `\n进程已结束，退出代码 ${result.code}\n`);
      this.problems++;
      this.setStatus(`${tab.name} 运行失败（退出代码 ${result.code}）`);
    }
  }

  private stopRun(): void {
    if (!this.running) {
      this.showToast('当前没有正在运行的脚本');
      return;
    }
    if (this.debugging) {
      // 调试会话优先走 debugCommand('stop')：暂停时解释器阻塞在 C++ 等待上，
      // 单纯 PyErr_SetInterrupt 唤不醒它。
      this.stopDebug();
      return;
    }
    PyRuntimeService.stop();
    this.appendSystem('\n已请求中断（等价于 Ctrl+C）…');
    this.setStatus('已请求中断');
  }

  // ── 调试会话 ───────────────────────────────────────────────────────────

  /**
   * 手动重新初始化运行时：清掉已释放的标准库/pip wheel，再从 rawfile 完整释放一遍。
   * 真机上遇到"释放标准库失败"时用它重试，不必重装应用。
   */
  private reinitRuntime(): void {
    this.dialog = '';
    this.appendSystem('重新初始化 Python 运行时（重新释放标准库与 pip wheel）…');
    this.setStatus('正在重新初始化运行时…');
    this.loading = true;
    PyRuntimeService.resetBootstrap(true);
    this.warmupRuntime();
  }

  /** 调试页内容：暂停时列出 变量 / 调用栈（XDebugger 的 Variables + Frames）*/
  private debugPanelLines(): string[] {
    const out: string[] = [];
    if (!this.debugging && !this.debugPaused) {
      return out;
    }
    out.push(this.debugPaused
      ? `已暂停 ${FileService.baseName(this.debugFile)}:${this.debugLine} (${this.debugFunc})`
      : '运行中…（命中断点后会在此暂停）');
    out.push(`· 变量（${this.debugLocals.length}）`);
    for (const pair of this.debugLocals) {
      if (pair.length >= 2) {
        out.push(`    ${pair[0]} = ${pair[1]}`);
      }
    }
    out.push(`· 调用栈（${this.debugStack.length}）`);
    for (const frame of this.debugStack) {
      if (frame.length >= 3) {
        out.push(`    ${frame[2]}  ${FileService.baseName(frame[0])}:${frame[1]}`);
      }
    }
    return out;
  }

  private onDebugPause(pause: DebugPause): void {
    // Evaluate 结果（PyCharm Evaluate 行为）：追加到求值历史
    if (pause.evalExpr !== undefined && pause.evalResult !== undefined) {
      const next: string[] = this.debugEvals.slice();
      next.push(`${pause.evalExpr} = ${pause.evalResult}`);
      this.debugEvals = next;
      // 若是监视表达式的求值结果，回填到 Watches
      const wi: number = this.watches.indexOf(pause.evalExpr);
      if (wi >= 0) {
        const vals: string[] = this.watchValues.slice();
        while (vals.length <= wi) {
          vals.push('');
        }
        vals[wi] = pause.evalResult;
        this.watchValues = vals;
      }
    }
    // 每次暂停后刷新所有监视表达式
    for (const w of this.watches) {
      PyRuntimeService.sendDebugCommand(`eval:${w}`);
    }
    this.debugPaused = true;
    this.debugFile = pause.file;
    this.debugLine = pause.line;
    this.debugFunc = pause.func;
    this.debugLocals = pause.locals;
    this.debugStack = pause.stack;
    this.appendEntry('system',
      `已暂停 ${FileService.baseName(pause.file)}:${pause.line} (${pause.func})\n`);
    // 暂停点可能在另一个文件里：切过去再定位
    if (pause.file !== this.activeTabId) {
      this.openFile(pause.file, FileService.baseName(pause.file));
    }
    this.editorController.revealLine(pause.line);
    this.setStatus(`调试暂停于 ${FileService.baseName(pause.file)}:${pause.line}`);
  }

  /** 收集所有已知断点（打开中的标签页 + 持久化里的），组成调试钩子要的 {路径: [行号]} */
  private collectBreakpoints(): string {
    const store: Record<string, number[]> = this.allBreakpoints();
    for (const tab of this.tabs) {
      if (tab.breakpoints.length > 0) {
        store[tab.path] = tab.breakpoints.slice();
      }
    }
    const active: EditorTab | undefined = this.activeTab();
    if (active !== undefined && active.breakpoints.length > 0) {
      store[active.path] = active.breakpoints.slice();
    }
    return JSON.stringify(store);
  }

  private async runDebugFile(): Promise<void> {
    if (this.running) {
      this.showToast('已有脚本正在运行');
      return;
    }
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined) {
      this.showToast('请先打开一个 .py 文件');
      return;
    }
    if (!tab.path.endsWith('.py')) {
      this.showToast('只能调试 .py 文件');
      return;
    }
    this.saveTab(tab);
    this.consoleTab = 'run';
    if (!this.settings.showBottomToolWindow) {
      this.settings.showBottomToolWindow = true;
    }
    this.logEntries = [];
    this.debugging = true;
    this.debugPaused = false;
    this.debugLine = 0;
    this.debugLocals = [];
    this.debugStack = [];

    const breakpointsJson: string = this.collectBreakpoints();
    const rootsJson: string = JSON.stringify([this.projectRoot, FileService.runtimeDir()]);
    // 直接从打开中的标签页统计，避免依赖 Object.values 这类动态迭代
    let breakpointCount: number = 0;
    for (const openTab of this.tabs) {
      breakpointCount += openTab.breakpoints.length;
    }
    this.appendEntry('command', `python ${tab.path}   # 调试模式\n`);
    this.appendSystem(breakpointCount > 0
      ? `调试会话已启动，共 ${breakpointCount} 个行断点。`
      : '调试会话已启动，当前没有行断点；可点「单步」进入逐步执行。');
    this.running = true;
    this.setStatus(`正在调试 ${tab.name} …`);

    const result: RunResult = await PyRuntimeService.runDebug(
      tab.path, [], breakpointsJson, rootsJson);

    this.running = false;
    this.debugging = false;
    this.debugPaused = false;
    this.debugLine = 0;
    if (result.stdout.length > 0) {
      this.appendEntry('stdout', result.stdout);
    }
    if (result.stderr.length > 0) {
      this.appendEntry('stderr', result.stderr);
    }
    if (result.code === 130) {
      this.appendEntry('system', '\n调试会话已停止（退出代码 130）。\n');
      this.setStatus('调试会话已停止');
    } else if (result.code === 0) {
      this.appendEntry('success', `\n调试结束，退出代码 0（耗时 ${result.durationMs} ms）\n`);
      this.setStatus('调试结束');
    } else {
      this.appendEntry('stderr', `\n调试结束，退出代码 ${result.code}\n`);
      this.problems++;
      this.setStatus(`调试结束，退出代码 ${result.code}`);
    }
  }

  private resumeDebug(): void {
    if (!this.debugPaused) {
      this.showToast('当前没有暂停');
      return;
    }
    this.debugPaused = false;
    this.debugLine = 0;
    PyRuntimeService.sendDebugCommand('continue');
    this.setStatus('继续执行');
  }

  private stepDebug(): void {
    if (!this.debugging) {
      this.showToast('没有正在进行的调试会话');
      return;
    }
    if (!this.debugPaused) {
      this.showToast('程序正在运行，暂停时才能单步');
      return;
    }
    this.debugPaused = false;
    PyRuntimeService.sendDebugCommand('step');
    this.setStatus('单步执行');
  }

  /** 步入：进入被调用函数内部 */
  private stepIntoDebug(): void {
    if (!this.debugPaused) {
      this.showToast('程序正在运行，暂停时才能单步');
      return;
    }
    this.debugPaused = false;
    PyRuntimeService.sendDebugCommand('stepinto');
    this.setStatus('步入');
  }

  /** 步出：执行到当前函数返回上一层 */
  /** Evaluate（PyCharm）：在暂停帧里求值表达式 */
  private evalDebug(): void {
    const expr: string = this.evalText.trim();
    if (expr.length === 0 || !this.debugPaused) {
      return;
    }
    PyRuntimeService.sendDebugCommand(`eval:${expr}`);
    this.evalText = '';
    this.setStatus(`求值中：${expr}`);
  }

  private stepOutDebug(): void {
    if (!this.debugPaused) {
      this.showToast('程序正在运行，暂停时才能步出');
      return;
    }
    this.debugPaused = false;
    PyRuntimeService.sendDebugCommand('stepout');
    this.setStatus('步出');
  }

  private stopDebug(): void {
    if (!this.debugging) {
      this.showToast('没有正在进行的调试会话');
      return;
    }
    PyRuntimeService.sendDebugCommand('stop');
    this.appendSystem('\n已请求停止调试。');
    this.setStatus('已请求停止调试');
  }

  private async replSubmit(line: string): Promise<void> {
    if (line.trim().length === 0) {
      return;
    }
    this.appendEntry('command', `>>> ${line}\n`);
    const output: string = await PyRuntimeService.repl(line);
    if (output.length > 0) {
      this.appendEntry('stdout', output);
    }
  }

  private async terminalSubmit(line: string): Promise<void> {
    if (line.trim().length === 0) {
      return;
    }
    this.appendEntry('command', `$ ${line}\n`);
    const trimmed: string = line.trim();
    if (trimmed === 'python --version' || trimmed === 'python -V') {
      this.appendEntry('stdout', `${this.runtime.version}\n`);
      return;
    }
    if (trimmed.startsWith('python ')) {
      const target: string = trimmed.substring(7).trim();
      const path: string = target.startsWith('/') ? target : `${this.projectRoot}/${target}`;
      const result: RunResult = await PyRuntimeService.run(path, []);
      this.appendEntry('stdout', result.stdout);
      this.appendEntry('stderr', result.stderr);
      return;
    }
    if (trimmed.startsWith('pip ')) {
      await this.pipRun(trimmed.substring(4).split(' '));
      return;
    }
    // 其余命令交给 native PTY（真 shell，见 cpp/pty_watch.cpp）
    const term: TerminalService = TerminalService.shared();
    const ready: boolean = term.start((text: string) => {
      this.appendEntry('stdout', text);
    });
    if (ready && term.send(line)) {
      FileService.log(`terminal submit via native pty cmd=${trimmed}`);
      return;
    }
    // PTY 不可用（沙箱无 /dev/ptmx 权限）→ 用 native 行式 shell 执行
    const out: string = term.runOnce(line);
    FileService.log(`terminal submit fallback shellRun cmd=${trimmed} bytes=${out.length}`);
    if (out.length > 0) {
      this.appendEntry('stdout', out);
      return;
    }
    this.appendSystem('内置终端支持：python <文件> / python --version / pip install <包>；'
      + '行式 shell 需要 native 模块（libpythonbridge）。');
  }

  /** 目录监听：native inotify 事件 → 增量刷新工程树（不再定时全量扫描） */
  private startProjectWatch(): void {
    if (this.projectRoot.length === 0) {
      return;
    }
    const ok: boolean = this.dirWatcher.start(this.projectRoot, (json: string) => {
      FileService.log(`dirwatch events=${json}`);
      this.refreshDir(this.projectRoot);
      this.refreshFlatten();
    });
    FileService.log(`dirwatch start root=${this.projectRoot} ok=${ok}`);
  }

  private async pipRun(args: string[]): Promise<void> {
    this.consoleTab = 'run';
    this.appendEntry('command', `pip ${args.join(' ')}\n`);
    this.running = true;
    const result: RunResult = await PyRuntimeService.pip(args);
    this.running = false;
    this.appendEntry('stdout', result.stdout);
    this.appendEntry('stderr', result.stderr);
    this.appendEntry('success', `\npip 退出代码 ${result.code}\n`);
  }

  // ── 菜单 / 工具栏动作分发 ──────────────────────────────────────────────

  /**
   * 打开顶栏右键菜单：位置 = 点击/长按点，并做边缘翻转与钳制（不再固定位置）。
   * 菜单与本组件根 Stack 同为窗口级坐标；顶栏在窗口最顶部，所以直接可用。
   */
  private openTopMenu(x: number, y: number): void {
    // 单位统一为 vp：GestureEvent.fingerList / MouseEvent 坐标、.position()、windowWidth/Height 都是 vp，
    // 不要做 px2vp 换算（重复换算会把菜单推到错误位置、子菜单也会离开菜单）。
    const w: number = TOP_MENU_WIDTH;
    const h: number = TOP_MENU_HEIGHT;
    const winW: number = this.windowWidth;
    const winH: number = this.windowHeight;
    let px: number = x;
    let py: number = y;
    if (px + w > winW - 8) {
      px = winW - w - 8;
    }
    if (px < 8) {
      px = 8;
    }
    if (py + h > winH - 8) {
      // 下面放不下 → 从点击点往上展开（PyCharm 的弹出菜单同样会翻转）
      py = y - h;
    }
    if (py < 8) {
      py = 8;
    }
    this.topMenuX = px;
    this.topMenuY = py;
    this.topSubmenu = '';
    this.topMenuShown = true;
    FileService.log(`topMenu open at (${Math.round(x)},${Math.round(y)}) -> (${Math.round(px)},${Math.round(py)})`);
  }

  /**
   * 设置自定义项目图标：走系统文件选择器导入 SVG / PNG，
   * 落点 <项目>/.idea/icon.svg（IntelliJ 约定），随后项目树根使用该图标。
   */
  private async importProjectIcon(): Promise<void> {
    if (this.uiContext === undefined) {
      this.setStatus('导入图标不可用（缺少 UIAbilityContext）');
      return;
    }
    try {
      const dest: string = await FileService.importIcon(this.uiContext, this.projectRoot);
      if (dest.length === 0) {
        this.setStatus('未选择图标（只支持 SVG / PNG）');
        return;
      }
      this.projectIcon = dest;
      FileService.log(`project icon file=${dest}`);
      this.setStatus(`项目图标已设为 ${FileService.baseName(dest)}`);
      this.refreshFlatten();
      this.treeRoots = this.treeRoots.slice();
    } catch (err) {
      FileService.log(`importProjectIcon failed err=${JSON.stringify(err)}`);
      this.setStatus('导入图标失败');
    }
  }

  /** 子菜单横向位置：右侧空间不够时翻到菜单左侧（否则会被挤出窗口） */
  private submenuX(): number {
    const w: number = 180;
    if (this.topMenuX + TOP_MENU_WIDTH + w > this.windowWidth - 4) {
      return this.topMenuX - w;
    }
    return this.topMenuX + TOP_MENU_WIDTH;
  }

  /** 切换主菜单显示模式（ChangeMainMenuModeActionGroup 的三项） */
  private setMenuMode(mode: string): void {
    this.menuMode = mode;
    this.menuOwnRow = mode === 'above';
    this.topMenuShown = false;
    this.topSubmenu = '';
    this.hamburgerShown = false;
    FileService.log(`main menu mode -> ${mode}`);
    this.setStatus(`主菜单：${mode === 'hamburger' ? '隐藏在汉堡按钮下方'
      : (mode === 'merged' ? '与主工具栏合并' : '显示在主工具栏上方')}`);
  }

  /** 把某个快捷操作加入主工具栏（并立即执行一次） */
  private addToMainToolbar(key: string): void {
    this.topMenuShown = false;
    this.topSubmenu = '';
    let label: string = key;
    let action: string = '';
    if (key === 'backforward') {
      label = '后退/前进';
      action = 'nav.back';
    } else if (key === 'build') {
      label = '构建';
    } else if (key === 'saveall') {
      label = '全部保存';
      action = 'file.saveAll';
    }
    FileService.log(`main toolbar quick action ${key}`);
    if (action.length > 0) {
      this.handleAction(action);
    } else {
      // 构建：本 IDE 没有独立构建动作，如实说明
      this.setStatus('「构建」在本 IDE 暂无独立动作（运行即构建并执行）');
    }
  }

  private handleAction(action: string): void {
    // ── 顶栏右键菜单（MainToolbarPopupActions）──
    if (action === 'top.toolbar') {
      this.topMenuShown = false;
      this.showMainToolbar = !this.showMainToolbar;
      this.setStatus(this.showMainToolbar ? '已显示主工具栏' : '已隐藏主工具栏');
      FileService.log(`main toolbar visible=${this.showMainToolbar}`);
      return;
    }
    if (action === 'top.icon') {
      // WelcomeScreen.ChangeProjectIcon：导入一个图标文件（不是从内置列表里挑）
      this.importProjectIcon();
      return;
    }
    if (action === 'top.merge') {
      // MergeMenuWithWindowTitleAction：主菜单与窗口标题合并 / 独立成行
      this.menuOwnRow = !this.menuOwnRow;
      FileService.log(`merge menu with title -> menuOwnRow=${this.menuOwnRow}`);
      this.setStatus(this.menuOwnRow ? '主菜单已独立成行' : '主菜单已与窗口标题合并');
      return;
    }
    if (action === 'top.customize') {
      this.topMenuShown = false;
      this.dialogTitle = '自定义菜单与工具栏';
      this.dialog = 'customizeUI';
      return;
    }
    if (action === 'file.new') {
      // 多语言：先选语言（LanguageService.languages()），再输入文件名
      this.dialogTarget = this.projectRoot;
      this.openNewFileDialog();
      return;
    }
    if (action === 'file.open') {
      this.importFiles();
      return;
    }
    if (action === 'file.openProject') {
      this.openProjectDialog();
      return;
    }
    if (action === 'file.newProject') {
      this.openInputDialog('新建项目（目录名）', '我的项目', 'newProject');
      return;
    }
    if (action === 'file.save') {
      this.saveActive();
      return;
    }
    if (action === 'file.saveAll') {
      this.saveAll();
      return;
    }
    if (action === 'file.close') {
      if (this.activeTabId.length > 0) {
        this.closeTab(this.activeTabId);
      }
      return;
    }
    if (action === 'file.export') {
      this.exportActive();
      return;
    }
    if (action === 'file.exit') {
      this.showToast('正在退出…');
      if (this.uiContext !== undefined) {
        this.uiContext.terminateSelf();
      }
      return;
    }
    if (action === 'edit.find' || action === 'edit.replace') {
      this.search.visible = true;
      this.search = this.search;
      return;
    }
    if (action === 'edit.selectAll') {
      this.editorController.selectAll();
      return;
    }
    if (action === 'edit.format') {
      this.formatActive();
      return;
    }
    if (action === 'edit.undo' || action === 'edit.redo') {
      this.showToast('撤销/重做请直接使用系统输入法的 Ctrl+Z / Ctrl+Y');
      return;
    }
    if (action === 'view.left' || action === 'view.toolWindows') {
      this.dialogTitle = '工具窗口';
      this.dialog = 'toolWindows';
      return;
    }
    if (action === 'view.left.real') {
      this.settings.showLeftToolWindow = !this.settings.showLeftToolWindow;
      SettingsService.save(this.settings);
      return;
    }
    if (action === 'view.bottom') {
      this.settings.showBottomToolWindow = !this.settings.showBottomToolWindow;
      SettingsService.save(this.settings);
      return;
    }
    if (action === 'view.theme') {
      this.toggleTheme();
      return;
    }
    if (action === 'view.zoomIn') {
      this.settings.fontSize = Math.min(28, this.settings.fontSize + 1);
      SettingsService.save(this.settings);
      return;
    }
    if (action === 'view.zoomOut') {
      this.settings.fontSize = Math.max(10, this.settings.fontSize - 1);
      SettingsService.save(this.settings);
      return;
    }
    if (action === 'view.wordwrap') {
      this.settings.wordWrap = !this.settings.wordWrap;
      SettingsService.save(this.settings);
      this.showToast(this.settings.wordWrap ? '自动换行：开（v1 尚未生效）' : '自动换行：关');
      return;
    }
    if (action === 'run.run') {
      this.notify('开始运行当前文件');
      this.runActiveFile(false);
      return;
    }
    // 编辑菜单里的剪贴板三项（之前是断头：菜单点了没反应）
    if (action === 'edit.copy') {
      this.editorController.copySelection();
      return;
    }
    if (action === 'edit.cut') {
      this.editorController.cutSelection();
      return;
    }
    if (action === 'edit.paste') {
      this.editorController.pasteClipboard();
      return;
    }
    if (action === 'run.more.args') {
      // PyCharm ExecutionBundle: run.configurations.popup.edit.run.config.and.run.current.file = Run with Parameters…
      this.dialogTarget = '';
      this.openInputDialog('使用形参运行', '', 'runArgs');
      return;
    }
    if (action === 'run.more') {
      // MoreRunToolbarActions：运行相关的更多操作（PyCharm 里是 运行/调试/编辑配置… 的弹层）
      this.dialogTitle = '运行';
      this.dialog = 'runConfig';
      return;
    }
    if (action === 'refactor.rename') {
      this.renameTarget = '';
      this.renameRows = [];
      this.dialogTitle = '重命名符号（跨文件）';
      this.dialog = 'rename';
      this.loadProjectSymbols();
      return;
    }
    if (action === 'refactor.renameUndo') {
      this.renameRows = [];
      this.undoRename();
      return;
    }
    if (action === 'edit.completeCrossFile' || action === 'edit.complete') {
      this.openCrossFileComplete();
      return;
    }
    if (action === 'code.inspect' || action === 'code.inspectUnusedImports') {
      this.runInspection();
      return;
    }
    if (action === 'edit.findUsages' || action === 'edit.usages') {
      this.usagesSymbol = '';
      this.usagesRows = [];
      this.dialogTitle = '查找用法（全工程）';
      this.dialog = 'usages';
      this.loadProjectSymbols();
      return;
    }
    if (action === 'vcs.fileHistory' || action === 'vcs.log' || action === 'vcs.showHistory') {
      this.openChangeTimeline();
      return;
    }
    if (action === 'externalSystem.show' || action === 'externalSystem.tasks') {
      this.openExternalSystem();
      return;
    }
    if (action === 'scope.view' || action === 'scope.show') {
      this.openScopeView();
      return;
    }
    if (action === 'graph.neighborhood' || action === 'graph.show' || action === 'diagram.show') {
      this.buildGraph();
      this.dialogTitle = '图表：当前文件的关系';
      this.dialog = 'graph';
      return;
    }
    if (action === 'diff.clipboard' || action === 'diff.compareWithClipboard') {
      this.compareWithClipboard();
      return;
    }
    if (action === 'debug.viewBreakpoints' || action === 'debug.showBreakpoints') {
      this.openBreakpoints();
      return;
    }
    if (action === 'history.show' || action === 'vcs.showHistory' || action === 'history.local') {
      this.openLocalHistory();
      return;
    }
    if (action === 'diff.active' || action === 'diff.compareWithSaved') {
      if (this.editorFilePath.length === 0) {
        this.showToast('当前没有打开的文件');
        return;
      }
      this.compareActiveWith(this.editorFilePath);
      return;
    }
    if (action === 'nav.gotoClass' || action === 'edit.gotoClass') {
      // 跨文件转到类：列全工程的类，点行打开该文件并定位
      this.dialogTitle = '转到类（全工程）';
      this.dialog = 'gotoclass';
      this.loadProjectClasses();
      return;
    }
    if (action === 'nav.gotoClass.legacy') {
      this.dialogTitle = '转到类';
      this.dialog = 'gotoClass';
      return;
    }
    if (action === 'nav.gotoSymbol' || action === 'edit.gotoSymbol') {
      this.symbolQuery = '';
      this.dialogTitle = '转到符号';
      this.dialog = 'gotoSymbol';
      return;
    }
    if (action === 'nav.hierarchy' || action === 'view.hierarchy') {
      this.dialogTitle = '层次结构';
      this.dialog = 'hierarchy';
      this.loadAstHierarchy();
      return;
    }
    if (action === 'nav.switcher' || action === 'view.switcher') {
      this.dialogTitle = '切换器';
      this.dialog = 'switcher';
      return;
    }
    if (action === 'edit.searchEverywhere') {
      // PyCharm：随处搜索是**专用对话框**（文件 + 操作两栏），不再复用"在文件中查找"
      this.swQuery = '';
      this.dialogTitle = '随处搜索';
      this.dialog = 'searchEverywhere';
      return;
    }
    if (action === 'run.debug') {
      this.runDebugFile();
      return;
    }
    if (action === 'run.stop') {
      this.stopRun();
      return;
    }
    if (action === 'run.config') {
      // 真实实现：读取/编辑运行配置并落盘（原来这里只是一句占位提示）
      this.loadRunConfig();
      this.dialog = 'runConfig';
      return;
    }
    if (action === 'run.pip') {
      this.dialog = 'pip';
      this.inputValue = '';
      return;
    }
    if (action === 'tools.repl') {
      this.settings.showBottomToolWindow = true;
      this.consoleTab = 'repl';
      return;
    }
    if (action === 'tools.terminal') {
      this.settings.showBottomToolWindow = true;
      this.consoleTab = 'terminal';
      return;
    }
    if (action === 'nav.gotoLine') {
      this.openInputDialog('转到行', `${this.cursorLine}`, 'goto');
      return;
    }
    if (action === 'nav.nextTab' || action === 'nav.prevTab') {
      this.cycleTab(action === 'nav.nextTab' ? 1 : -1);
      return;
    }
    if (action === 'nav.refreshProject') {
      this.loadProject(this.projectRoot);
      this.setStatus('工程树已刷新');
      return;
    }
    // ── 文件菜单（按 PyCharm 的 File 菜单逐项实现）──────────────────────
    if (action === 'file.newFolder') {
      this.dialogTarget = this.projectRoot;
      this.openInputDialog('新建目录', 'new_folder', 'newFolder');
      return;
    }
    if (action === 'file.newScratch') {
      const dir: string = `${this.projectRoot}/scratch`;
      FileService.ensureDir(dir);
      const target: string = FileService.uniquePath(dir, 'scratch', '.py');
      FileService.createFile(target, this.newFileTemplate('scratch.py'));
      this.refreshDir(dir);
      this.openFile(target, FileService.baseName(target));
      this.setStatus('已新建临时文件');
      return;
    }
    if (action === 'file.reload') {
      const tab: EditorTab | undefined = this.activeTab();
      if (tab === undefined) {
        this.showToast('没有打开的文件');
        return;
      }
      this.reloadTab(tab);
      this.setStatus(`已从磁盘重新加载 ${tab.name}`);
      return;
    }
    if (action === 'file.reloadAll') {
      for (const tab of this.tabs) {
        this.reloadTab(tab);
      }
      this.tabs = this.tabs.slice();
      this.setStatus('已重新加载所有文件');
      return;
    }
    if (action === 'file.closeProject') {
      this.tabs = [];
      this.activeTabId = '';
      this.editorSeedText = '';
      this.editorFilePath = '';
      this.appendSystem('已关闭项目；可用主工具栏左侧的工程部件或「打开…」重新进入。');
      this.setStatus('已关闭项目');
      return;
    }
    if (action === 'file.projectStructure') {
      this.dialog = 'structure';
      return;
    }
    if (action === 'file.recent0' || action === 'file.recent1' || action === 'file.recent2') {
      const recentIndex: number = action === 'file.recent0' ? 0
        : (action === 'file.recent1' ? 1 : 2);
      if (recentIndex < this.projectList.length) {
        this.loadProject(this.projectList[recentIndex]);
      } else {
        this.showToast('该位置暂无最近工程');
      }
      return;
    }
    if (action === 'file.print') {
      // 沙箱内没有系统打印服务：落到真实的「导出」路径上
      this.handleAction('file.export');
      return;
    }
    // ── 编辑菜单（按 PyCharm 的 Edit 菜单逐项实现）────────────────────
    if (action === 'edit.copyPath') {
      const tab: EditorTab | undefined = this.activeTab();
      if (tab === undefined) {
        this.showToast('没有打开的文件');
        return;
      }
      FileService.copyToClipboard(tab.path);
      this.setStatus(`已复制路径：${tab.path}`);
      return;
    }
    if (action === 'edit.pastePlain') {
      // 纯文本粘贴：本项目编辑器本来就只处理纯文本
      this.editorController.pasteClipboard();
      return;
    }
    if (action === 'console.pauseOutput' || action === 'console.clearAll') {
      if (action === 'console.pauseOutput') {
        this.togglePauseOutput();
      } else {
        this.logEntries = [];
        this.problems = 0;
        this.setStatus('已清除控制台');
      }
      return;
    }
    if (action === 'edit.findInFiles') {
      this.openFindInFiles(this.search.query);
      return;
    }
    if (action === 'edit.findUsages') {
      this.openFindInFiles(this.search.query);
      this.setStatus('查找用法：在结果里按 文件:行 定位');
      return;
    }
    if (action === 'edit.findNext') {
      this.editorController.findNext(this.search.query, true);
      return;
    }
    if (action === 'edit.findPrev') {
      this.editorController.findNext(this.search.query, false);
      return;
    }
    if (action === 'edit.expandSelection') {
      this.editorController.expandSelection();
      return;
    }
    if (action === 'edit.format') {
      this.editorController.formatDocument();
      this.setStatus('已格式化代码');
      return;
    }
    if (action === 'edit.optimizeImports') {
      this.editorController.optimizeImports();
      this.setStatus('已优化导入（排序并去重）');
      return;
    }
    if (action === 'edit.autoIndent') {
      // 保守实现：与格式化同一套归一化（Tab→空格、去行尾空白、结尾单换行）
      this.editorController.formatDocument();
      this.setStatus('已自动缩进（Tab 转空格）');
      return;
    }
    if (action === 'edit.comment') {
      this.editorController.toggleComment();
      return;
    }
    if (action === 'edit.duplicate') {
      this.editorController.duplicateLine();
      return;
    }
    // ── 视图菜单（按 PyCharm 的 View 菜单逐项实现）────────────────────
    if (action === 'view.problems') {
      this.consoleTab = 'problems';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    if (action === 'view.mainToolbar') {
      this.showMainToolbar = !this.showMainToolbar;
      this.setStatus(this.showMainToolbar ? '已显示主工具栏' : '已隐藏主工具栏');
      return;
    }
    if (action === 'view.sideStrip') {
      this.showSideStrip = !this.showSideStrip;
      this.setStatus(this.showSideStrip ? '已显示工具窗口栏' : '已隐藏工具窗口栏');
      return;
    }
    if (action === 'view.statusBar') {
      this.showStatusBar = !this.showStatusBar;
      this.setStatus(this.showStatusBar ? '已显示状态栏' : '已隐藏状态栏');
      return;
    }
    if (action === 'view.breadcrumb') {
      this.showBreadcrumb = !this.showBreadcrumb;
      this.setStatus(this.showBreadcrumb ? '已显示导航栏' : '已隐藏导航栏');
      return;
    }
    if (action === 'view.indentGuides') {
      this.showIndentGuides = !this.showIndentGuides;
      this.setStatus(this.showIndentGuides ? '已显示缩进参考线' : '已隐藏缩进参考线');
      return;
    }
    if (action === 'view.fullscreen') {
      this.toggleFullScreen();
      return;
    }
    if (action === 'view.focusEditor') {
      this.dialog = '';
      this.setStatus('编辑器已激活');
      return;
    }
    if (action === 'view.recentFiles') {
      this.dialog = 'recentFiles';
      return;
    }
    if (action === 'view.structure') {
      FileService.log('menu action view.structure -> openFileStructure');
      this.openFileStructure();
      FileService.log(`after openFileStructure dialog=${this.dialog} symbols=${this.structureSymbols.length}`);
      return;
    }
    if (action === 'view.splitRight') {
      this.splitRight = !this.splitRight;
      if (this.splitRight) {
        this.splitTabId = this.pickSplitTab();
        this.setStatus('已向右分屏：两个窗格都可编辑');
      } else {
        this.setStatus('已取消分屏');
      }
      return;
    }
    // ── 导航菜单（按 PyCharm 的 Navigate 菜单逐项实现）────────────────
    if (action === 'nav.gotoFile' || action === 'nav.gotoSymbol') {
      this.openGoto(action === 'nav.gotoFile' ? 'file' : 'symbol');
      return;
    }
    if (action === 'nav.back' || action === 'nav.forward') {
      const step: number = action === 'nav.back' ? -1 : 1;
      const next: number = this.navIndex + step;
      if (next < 0 || next >= this.navHistory.length) {
        this.showToast(action === 'nav.back' ? '没有更早的位置' : '没有更新的位置');
        return;
      }
      this.navIndex = next;
      this.navigateTo(this.navHistory[next]);
      return;
    }
    if (action === 'nav.closeOthers') {
      const tab: EditorTab | undefined = this.activeTab();
      if (tab === undefined) {
        return;
      }
      this.tabs = [tab];
      this.activeTabId = tab.id;
      this.refreshFlatten();
      this.setStatus('已关闭其他标签页');
      return;
    }
    // ── 运行菜单（按 PyCharm 的 Run 菜单）────────────────────────────
    if (action === 'run.showConsole') {
      this.consoleTab = 'run';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    if (action === 'run.analyzeStack') {
      this.consoleTab = 'problems';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      this.setStatus('已打开问题视图（堆栈分析基于最后一次运行的诊断）');
      return;
    }
    if (action === 'run.runtime') {
      this.dialog = 'runtime';
      return;
    }
    // ── 工具菜单 ────────────────────────────────────────────────────
    if (action === 'tools.resetRuntime') {
      PyRuntimeService.resetBootstrap(true);
      this.setStatus('已重置运行时引导：下次运行会重新释放标准库');
      this.appendSystem('运行时引导已重置。若之前标准库释放失败，请点「运行」重试。');
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    // ── 帮助菜单 ────────────────────────────────────────────────────
    if (action === 'help.shortcuts') {
      this.dialog = 'shortcuts';
      return;
    }
    if (action === 'help.licenses') {
      this.dialog = 'licenses';
      return;
    }
    if (action === 'help.runtime') {
      this.dialog = 'runtime';
      return;
    }
    if (action === 'tools.vcs') {
      this.showInfo('版本控制', [
        `工程目录：${this.projectRoot}`,
        '沙箱内未捆绑 Git 可执行文件，因此没有提交/分支界面（PyCharm 的版本控制属内置功能，这里如实说明）。',
        '可以用「终端」运行 Python 脚本来读写 .git 内容；',
        '或在设备可访问路径上用外部工具管理版本后回到本 IDE 编辑。'
      ]);
      return;
    }
    // ── 代码菜单（对照实测 PyCharm 的「代码(C)」）──────────────────────
    if (action === 'edit.complete') {
      this.editorController.triggerCompletion();
      this.setStatus('已触发代码补全');
      return;
    }
    if (action === 'code.generate') {
      this.showInfo('生成', [
        'PyCharm 的「生成」用于插入构造方法、getter/setter、重写方法等。',
        '本 IDE 暂未实现代码生成，可在编辑器里手动输入。'
      ]);
      return;
    }
    if (action === 'code.structure') {
      this.openFileStructure();
      return;
    }
    if (action === 'code.problems') {
      this.consoleTab = 'problems';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    // ── 重构菜单（对照实测 PyCharm 的「重构(R)」）──────────────────────
    if (action === 'refactor.rename') {
      const tab0: EditorTab | undefined = this.activeTab();
      if (tab0 === undefined) {
        this.showToast('没有打开的文件');
        return;
      }
      this.dialogTarget = tab0.path;
      this.openInputDialog('重命名', tab0.name, 'rename');
      return;
    }
    if (action === 'refactor.extractVar' || action === 'refactor.extractMethod'
      || action === 'refactor.inline' || action === 'refactor.move'
      || action === 'refactor.copy' || action === 'refactor.safeDelete') {
      this.showInfo('重构', [
        'PyCharm 的重构（提取变量/方法、内联、移动、复制、安全删除）依赖语义分析引擎。',
        '本 IDE 目前提供：重命名（文件级）、格式化代码、优化导入、注释/取消注释。',
        '符号级重构需要类型推断，列入后续版本。'
      ]);
      return;
    }
    // ── VCS 菜单（对照实测 PyCharm 的「VCS(S)」）──────────────────────
    if (action === 'vcs.commit' || action === 'vcs.update' || action === 'vcs.pull'
      || action === 'vcs.push' || action === 'vcs.history') {
      this.showInfo('版本控制', [
        `工程目录：${this.projectRoot}`,
        '沙箱内未捆绑 Git 可执行文件，因此提交/更新/拉取/推送/历史都不可用。',
        '可以在「终端」里用 Python 脚本读写 .git，或用外部工具管理版本后回到本 IDE 编辑。'
      ]);
      return;
    }
    // ── 窗口菜单（对照实测 PyCharm 的「窗口(W)」）─────────────────────
    if (action === 'window.splitRight') {
      if (!this.splitRight) {
        this.handleAction('view.splitRight');
      } else {
        this.setStatus('已经是分屏状态');
      }
      return;
    }
    if (action === 'window.unsplit') {
      this.splitRight = false;
      this.setStatus('已取消分屏');
      return;
    }
    if (action === 'window.nextTab') {
      this.handleAction('nav.nextTab');
      return;
    }
    if (action === 'window.prevTab') {
      this.handleAction('nav.prevTab');
      return;
    }
    // ── 文件/编辑菜单里按 PyCharm 实现文件新增的项 ──────────────────────
    if (action === 'file.attachProject') {
      this.showInfo('附加项目', [
        'PyCharm 的「附加项目」用于把另一个目录作为第二个根加入当前工程。',
        '本 IDE 目前同时只打开一个工程；可用「打开…」切换。'
      ]);
      return;
    }
    if (action === 'file.closeAllProjects') {
      this.tabs = [];
      this.activeTabId = '';
      this.editorSeedText = '';
      this.editorFilePath = '';
      this.liveStructure = [];
      this.setStatus('已关闭所有项目（标签全部关闭，回到欢迎页）');
      return;
    }
    if (action === 'file.closeOtherProjects') {
      this.handleAction('nav.closeOthers');
      return;
    }
    if (action === 'file.plugins') {
      this.showInfo('插件', [
        'PyCharm 的插件市场可安装第三方插件。',
        '本 IDE 暂未实现插件系统（按你的要求先做内置功能）。',
        '插件提供的工具窗（AI 聊天/Junie/AtomCode/单词本等）已按内置优先原则处理。'
      ]);
      return;
    }
    if (action === 'file.fileEncoding') {
      this.showInfo('文件编码', [
        '当前文件编码：UTF-8（本 IDE 读写均为 UTF-8）。',
        '沙箱内文件由编辑器自动保存，不提供单独转码操作。'
      ]);
      return;
    }
    if (action === 'file.associateFileType') {
      this.showInfo('与文件类型关联', [
        'PyCharm 用它把某个扩展名关联到指定文件类型。',
        '本 IDE 内置识别：.py / .pyw → Python，其余按纯文本编辑。'
      ]);
      return;
    }
    if (action === 'file.toggleReadOnly') {
      this.showInfo('切换只读特性', [
        'PyCharm 用它把文件标记为只读。',
        '鸿蒙应用沙箱不开放文件权限位修改，因此本 IDE 暂不支持只读标记。',
        '需要避免误改时，可先复制一份备份文件。'
      ]);
      return;
    }
    if (action === 'file.lineSeparators') {
      this.setStatus('换行符：LF（Unix）——本 IDE 统一使用 LF');
      return;
    }
    if (action === 'file.invalidateCaches') {
      PyRuntimeService.resetBootstrap(true);
      this.setStatus('已使缓存失效：下次运行会重新释放标准库');
      return;
    }
    if (action === 'file.importSettings' || action === 'file.exportSettings') {
      this.showInfo(action === 'file.importSettings' ? '导入设置' : '导出设置', [
        '设置保存在沙箱内 settings.json，可随工程目录一起备份。',
        action === 'file.importSettings'
          ? '导入：把 settings.json 放回沙箱设置目录后重启应用即可生效。'
          : '导出：settings.json 位于应用沙箱，可用「终端」复制到工程目录。'
      ]);
      return;
    }
    if (action === 'file.restoreDefaults') {
      this.settings = new AppSettings();
      SettingsService.save(this.settings);
      this.setStatus('已恢复默认设置');
      return;
    }
    if (action === 'file.powerSave' || action === 'file.essentialHighlighting') {
      this.setStatus(action === 'file.powerSave'
        ? '省电模式：本 IDE 无后台索引，始终处于省电状态'
        : '基本高亮显示：已启用（语法高亮为轻量本地实现）');
      return;
    }
    if (action === 'nav.matchedBrace') {
      this.editorController.moveToMatchingBrace();
      this.setStatus('已跳到匹配的括号');
      return;
    }
    if (action === 'view.recentFiles' || action === 'nav.recentFiles') {
      this.recentShown = !this.recentShown;
      return;
    }
    if (action === 'edit.delete') {
      this.editorController.cutSelection();
      return;
    }
    if (action === 'edit.toggleFindInSelection') {
      this.setStatus('仅在选区内搜索：切换查找范围（当前整文件）');
      return;
    }
    // ── 代码(C) 菜单里按 CodeMenu 新增的项 ─────────────────────────────
    if (action === 'code.smartType') {
      this.editorController.triggerCompletion();
      this.setStatus('类型匹配补全：已触发（本地补全引擎）');
      return;
    }
    if (action === 'code.inspect' || action === 'code.cleanup') {
      const problems: string[] = [];
      if (this.problems > 0) {
        problems.push(`当前有 ${this.problems} 条问题（见「问题」视图）`);
      } else {
        problems.push('未发现问题');
      }
      problems.push('本 IDE 的静态检查为轻量实现：语法高亮 + 缩进/括号配对提示。');
      this.showInfo(action === 'code.inspect' ? '检查代码' : '代码清理', problems);
      return;
    }
    if (action === 'code.analyzeStack') {
      this.handleAction('run.analyzeStack');
      return;
    }
    if (action === 'code.liveTemplate' || action === 'code.saveTemplate') {
      this.showInfo(action === 'code.liveTemplate' ? '插入实时模板' : '保存为实时模板', [
        'PyCharm 的实时模板（Live Template）用于展开 if/main/for 等代码片段。',
        '本 IDE 目前提供缩进与括号自动配对；模板系统列入后续版本。'
      ]);
      return;
    }
    if (action === 'code.surround' || action === 'code.unwrap') {
      this.showInfo(action === 'code.surround' ? '环绕方式' : '解包/移除', [
        'PyCharm 用「环绕方式」给选中代码套上 if/try/while 等结构。',
        '本 IDE 暂未实现代码模板环绕；可手动输入结构后再粘贴代码。'
      ]);
      return;
    }
    if (action === 'code.commentBlock') {
      this.editorController.toggleComment();
      this.setStatus('块注释：已按三引号注释切换');
      return;
    }
    if (action === 'code.rearrange') {
      this.editorController.optimizeImports();
      this.setStatus('已重新排列（当前实现：import 排序去重）');
      return;
    }
    if (action === 'code.moveUp' || action === 'code.moveDown') {
      this.setStatus(action === 'code.moveUp' ? '上移行：Ctrl+Shift+Up' : '下移行：Ctrl+Shift+Down');
      return;
    }
    // ── 新增菜单项的通用处理（视图/导航/编辑里按实现文件补的项）──────────
    if (action === 'view.showWhitespace') {
      this.showInfo('显示空格', [
        'PyCharm 用它显示空格/制表符等不可见字符。',
        '本 IDE 的编辑器覆盖层不渲染不可见字符，暂不支持该开关。'
      ]);
      return;
    }
    if (action === 'view.showLineNumbers' || action === 'view.showGutterIcons') {
      if (action === 'view.showLineNumbers') {
        this.settings.showLineNumbers = !this.settings.showLineNumbers;
        SettingsService.save(this.settings);
        this.setStatus(this.settings.showLineNumbers ? '已显示行号' : '已隐藏行号');
      } else {
        this.showInfo('显示装订区域图标', [
          '装订区域（gutter）图标包括断点、灯泡、VCS 标记等。',
          '断点与灯泡已启用；VCS 标记沙箱内不可用。'
        ]);
      }
      return;
    }
    if (action === 'view.mainMenu' || action === 'view.toolbarClassic') {
      this.handleAction('view.mainToolbar');
      return;
    }
    if (action === 'view.compactMode' || action === 'view.zoomIde'
      || action === 'view.presentationMode' || action === 'view.distractionFree'
      || action === 'view.zenMode' || action === 'view.resetFontSize'
      || action === 'view.quickSwitchScheme' || action === 'view.recentLocations'
      || action === 'view.gotoSource' || action === 'view.showSource'
      || action === 'view.splitRightPart' || action === 'view.statusText'
      || action === 'view.highlightCurrentDeclaration') {
      this.showInfo('视图 · 外观', [
        `你选择的是「${action.replace('view.', '')}」。`,
        '本 IDE 已实现：工具栏/工具窗口栏/状态栏/导航栏开关、深色浅色、字号缩放、',
        '缩进参考线、自动换行、全屏、左右分屏、运行/控制台/终端/问题面板。',
        '其余外观项（演示模式、Zen、紧凑模式、缩放 IDE 等）列入后续版本。'
      ]);
      return;
    }
    if (action === 'nav.nextError' || action === 'nav.prevError') {
      this.consoleTab = 'problems';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      this.setStatus(this.problems > 0
        ? `共 ${this.problems} 条问题（已打开问题视图）`
        : '没有高亮显示的错误');
      return;
    }
    if (action === 'nav.nextMethod' || action === 'nav.prevMethod') {
      this.openFileStructure();
      this.setStatus('方法导航：已打开文件结构面板');
      return;
    }
    if (action === 'nav.nextEditLocation' || action === 'nav.prevEditLocation'
      || action === 'nav.nextMatch' || action === 'nav.prevMatch'
      || action === 'nav.customFolding') {
      this.setStatus(`导航：${action.replace('nav.', '')}（本版本未实现位置栈/折叠导航）`);
      return;
    }
    if (action === 'edit.pasteHistory') {
      this.editorController.pasteClipboard();
      this.setStatus('粘贴：本 IDE 只有系统剪贴板一份历史，退化为普通粘贴');
      return;
    }
    if (action === 'edit.selectAllOccurrences' || action === 'edit.unselectOccurrences') {
      this.setStatus(action === 'edit.selectAllOccurrences' ? '已选择所有匹配项（当前为单处选择）' : '已取消选择匹配项');
      return;
    }
    if (action === 'edit.replaceInFiles') {
      this.handleAction('edit.findInFiles');
      return;
    }
    if (action === 'edit.convertIndentsToSpaces' || action === 'edit.convertIndentsToTabs') {
      this.editorController.formatDocument();
      this.setStatus(action === 'edit.convertIndentsToSpaces'
        ? '已转换为空格（Tab → 4 空格）'
        : '已转换为制表符（当前实现统一转为空格）');
      return;
    }
    if (action === 'edit.addCaretPerLine') {
      this.setStatus('多光标：本 IDE 暂不支持多光标编辑');
      return;
    }
    if (action === 'edit.findWordAtCaret' || action === 'edit.findPrevWordAtCaret') {
      this.setStatus('查找光标处单词：可在编辑器里选中单词后用 Ctrl+F');
      return;
    }
    if (action === 'edit.scrollToResults') {
      return;
    }
    // 未识别的动作：明确提示，避免误弹设置
    if (action.length > 0) {
      this.showToast(`该功能本版本未实现：${action}`);
    }
    // ── 窗口菜单（WindowMenu 原文）──────────────────────────────────────
    if (action === 'window.hideActive' || action === 'window.hideSide') {
      this.settings.showLeftToolWindow = false;
      this.settings = this.settings;
      this.setStatus('已隐藏工具窗口');
      return;
    }
    if (action === 'window.hideBottom') {
      this.settings.showBottomToolWindow = false;
      this.settings = this.settings;
      this.setStatus('已隐藏底部工具窗口');
      return;
    }
    if (action === 'window.hideAll') {
      this.settings.showLeftToolWindow = false;
      this.settings.showBottomToolWindow = false;
      this.settings = this.settings;
      this.setStatus('已隐藏所有工具窗口');
      return;
    }
    if (action === 'window.closeTab') {
      this.closeTab(this.activeTabId);
      return;
    }
    if (action === 'window.closeOtherTabs') {
      this.handleAction('nav.closeOthers');
      return;
    }
    if (action === 'window.closeAllTabs') {
      this.tabs = [];
      this.activeTabId = '';
      this.editorSeedText = '';
      this.editorFilePath = '';
      this.liveStructure = [];
      this.setStatus('已关闭所有标签页');
      return;
    }
    if (action === 'window.restoreLayout') {
      this.handleAction('tools.resetLayout');
      return;
    }
    if (action === 'window.splitDown' || action === 'window.storeLayout'
      || action === 'window.storeNewLayout' || action === 'window.pinTab'
      || action === 'window.expandLeft' || action === 'window.expandRight'
      || action === 'window.expandTop' || action === 'window.expandBottom') {
      this.setStatus(`${action.replace('window.', '')}：本版本未实现（拆分为水平和垂直两种，已支持向右拆分）`);
      return;
    }
    if (action === 'window.nextTab2') {
      this.handleAction('nav.nextTab');
      return;
    }
    if (action === 'window.prevTab2') {
      this.handleAction('nav.prevTab');
      return;
    }
    // ── 运行/调试菜单（RunMenu + DebugMainMenu 原文）────────────────────
    if (action === 'run.manageTargets') {
      this.showInfo('管理目标', [
        'PyCharm 用它管理远程解释器/Docker/WSL 等运行目标。',
        '本 IDE 使用内嵌 CPython（设备本地），没有外部目标可管理。'
      ]);
      return;
    }
    if (action === 'run.stopBackground') {
      this.handleAction('run.stop');
      return;
    }
    if (action === 'run.showLive') {
      this.setStatus(this.running ? '正在运行：当前文件' : '当前没有正在运行的配置');
      return;
    }
    if (action === 'debug.stepOver' || action === 'debug.stepInto' || action === 'debug.stepOut'
      || action === 'debug.resume' || action === 'debug.pause'
      || action === 'debug.runToCursor' || action === 'debug.toggleBreakpoint'
      || action === 'debug.viewBreakpoints' || action === 'debug.showExecutionPoint') {
      this.setStatus(`${action.replace('debug.', '')}：请在调试会话中使用底部调试工具条（继续/单步/步入/步出/停止）`);
      return;
    }
    if (action === 'debug.evaluate') {
      this.showInfo('对表达式求值', [
        'PyCharm 的 Evaluate 可在暂停时求值任意表达式。',
        '本 IDE 的调试器支持查看局部变量与调用栈；表达式求值列入后续版本。'
      ]);
      return;
    }
    // ── 工具菜单（ToolsMenu 原文）───────────────────────────────────────
    if (action === 'tools.createLauncher' || action === 'tools.createDesktopEntry') {
      this.showInfo(action === 'tools.createLauncher' ? '创建命令行启动器' : '创建桌面条目', [
        'PyCharm 用它生成 shell 启动脚本 / 系统桌面快捷方式。',
        '鸿蒙沙箱内不允许创建系统级启动器或桌面条目，因此暂不可用。',
        '应用图标与名称已由 HarmonyOS 包清单（module.json5）声明。'
      ]);
      return;
    }
    if (action === 'tools.services') {
      this.consoleTab = 'services';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    // ── 帮助菜单（HelpMenu 原文）────────────────────────────────────────
    if (action === 'tools.todo') {
      this.scanTodo();
      this.dialogTitle = 'TODO';
      this.dialog = 'todo';
      return;
    }
    if (action === 'tools.processOutput') {
      this.consoleTab = 'run';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      this.setStatus('Python 进程输出（运行工具窗显示了脚本的输出）');
      return;
    }
    if (action === 'help.findAction') {
      this.openGoto('symbol');
      this.setStatus('查找操作：本 IDE 用「转到符号」近似替代');
      return;
    }
    if (action === 'help.gettingStarted' || action === 'help.support'
      || action === 'help.bug' || action === 'help.feedback'
      || action === 'help.checkUpdate') {
      this.showInfo('帮助', [
        `你选择的是「${action.replace('help.', '')}」。`,
        '本 IDE 为离线本地工具：帮助文档见「帮助 / 使用文档」，快捷键见「键盘快捷键」。',
        '在线支持、bug 报告、检查更新需要联网与 JetBrains 账号，不适用。'
      ]);
      return;
    }
    if (action === 'help.openLog' || action === 'help.showLog' || action === 'help.collectLogs'
      || action === 'help.activityMonitor' || action === 'help.dumpThreads'
      || action === 'help.customProperties') {
      this.showInfo('诊断工具', [
        '应用日志：`hdc shell hilog -x -T PyIDE`（标签 A01234/PyIDE）',
        '运行时日志会记录标准库释放、Python 启动、运行/调试等关键步骤。',
        '活动监视器/线程转储/自定义属性属于 JVM 工具，本 IDE（CPython + ArkTS）不适用。'
      ]);
      return;
    }
    // ── 重构菜单（RefactoringMenu 原文）─────────────────────────────────
    if (action === 'refactor.changeSignature' || action === 'refactor.introduceVar'
      || action === 'refactor.introduceConst' || action === 'refactor.introduceField'
      || action === 'refactor.introduceParam' || action === 'refactor.extractMethod'
      || action === 'refactor.extractDelegate' || action === 'refactor.extractSuperclass'
      || action === 'refactor.inline' || action === 'refactor.move'
      || action === 'refactor.copy' || action === 'refactor.safeDelete') {
      this.showInfo('重构', [
        `你选择的是「${action.replace('refactor.', '')}」。`,
        'PyCharm 的符号级重构依赖完整的语义分析引擎（类型推断、引用解析）。',
        '本 IDE 已提供：文件级重命名、格式化、优化 import、注释/取消注释、行复制。',
        '符号级重构列入后续版本。'
      ]);
      return;
    }
    // ── 文件菜单补：另存为 / BOM / 换行符 / 导出 HTML（按还原后的 FileMenu）──
    if (action === 'file.saveAs') {
      const tab: EditorTab | undefined = this.activeTab();
      if (tab === undefined) {
        this.showToast('没有打开的文件');
        return;
      }
      this.dialogTarget = tab.path;
      this.openInputDialog('另存为', `${tab.name.replace('.py', '_copy.py')}`, 'saveAs');
      return;
    }
    if (action === 'file.addBom' || action === 'file.removeBom') {
      const tab2: EditorTab | undefined = this.activeTab();
      if (tab2 === undefined) {
        this.showToast('没有打开的文件');
        return;
      }
      try {
        const src: string = FileService.readText(tab2.path);
        if (action === 'file.addBom') {
          if (src.startsWith('\uFEFF')) {
            this.setStatus('该文件已经有 BOM');
          } else {
            FileService.writeText(tab2.path, `\uFEFF${src}`);
            this.setStatus('已添加 UTF-8 BOM');
          }
        } else {
          if (src.startsWith('\uFEFF')) {
            FileService.writeText(tab2.path, src.substring(1));
            this.setStatus('已移除 BOM');
          } else {
            this.setStatus('该文件没有 BOM');
          }
        }
      } catch (err) {
        this.appendError(`BOM 操作失败：${JSON.stringify(err)}`);
      }
      return;
    }
    if (action === 'file.eolWindows' || action === 'file.eolUnix' || action === 'file.eolMac') {
      const tab3: EditorTab | undefined = this.activeTab();
      if (tab3 === undefined) {
        this.showToast('没有打开的文件');
        return;
      }
      try {
        const text: string = FileService.readText(tab3.path).replace(/\r\n/g, '\n').replace(/\r/g, '\n');
        const nl: string = action === 'file.eolWindows' ? '\r\n' : (action === 'file.eolMac' ? '\r' : '\n');
        FileService.writeText(tab3.path, text.replace(/\n/g, nl));
        this.setStatus(action === 'file.eolWindows' ? '已转换为 Windows (CRLF)'
          : (action === 'file.eolMac' ? '已转换为 Mac (CR)' : '已转换为 Unix (LF)'));
      } catch (err) {
        this.appendError(`换行符转换失败：${JSON.stringify(err)}`);
      }
      return;
    }
    if (action === 'file.exportHtml') {
      const tab4: EditorTab | undefined = this.activeTab();
      if (tab4 === undefined) {
        this.showToast('没有打开的文件');
        return;
      }
      try {
        const code: string = FileService.readText(tab4.path)
          .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const html: string = `<!doctype html>\n<html><head><meta charset="utf-8">`
          + `<title>${tab4.name}</title></head>\n<body style="background:#191A1C;color:#BCBEC4">`
          + `<pre style="font-family:JetBrains Mono,monospace">${code}</pre></body></html>\n`;
        const outPath: string = `${this.projectRoot}/${tab4.name}.html`;
        FileService.writeText(outPath, html);
        this.setStatus(`已导出到 ${outPath}`);
        this.refreshDir(this.projectRoot);
      } catch (err) {
        this.appendError(`导出 HTML 失败：${JSON.stringify(err)}`);
      }
      return;
    }
    if (action === 'file.fromVcs' || action === 'file.newProject' || action === 'file.manageProjects'
      || action === 'file.templateDataLanguage' || action === 'file.localHistory'
      || action === 'file.saveAsTemplate') {
      this.showInfo('文件 · 工程操作', [
        `你选择的是「${action.replace('file.', '')}」。`,
        '本 IDE 一次打开一个本地工程：可用「打开…」切换，用「最近的项目」快速回到上次工程。',
        '版本控制、模板与本地历史需要 Git/索引支撑，沙箱内不可用。'
      ]);
      return;
    }
    // ── 编辑菜单补：复制引用/纯文本、用法高亮、宏与书签 ──────────────────
    if (action === 'edit.copyReference') {
      const tab5: EditorTab | undefined = this.activeTab();
      if (tab5 === undefined) {
        this.showToast('没有打开的文件');
        return;
      }
      const ref: string = `${tab5.name}:${this.cursorLine}`;
      FileService.copyToClipboard(ref);
      this.setStatus(`已复制引用：${ref}`);
      return;
    }
    if (action === 'edit.copyPlain') {
      this.editorController.copySelection();
      return;
    }
    if (action === 'edit.copyRich' || action === 'edit.escapeEntities'
      || action === 'edit.structuralSearch' || action === 'edit.structuralReplace'
      || action === 'edit.emoji') {
      this.showInfo('编辑', [
        `你选择的是「${action.replace('edit.', '')}」。`,
        '格式化文本/结构化搜索/表情符号需要 IDE 富文本与结构化搜索能力，暂未实现。',
        '已实现的编辑能力：复制/剪切/粘贴、复制路径与引用、格式化、优化 import、注释、行复制。'
      ]);
      return;
    }
    if (action === 'edit.showUsages' || action === 'edit.findUsagesSettings'
      || action === 'edit.findUsagesInFile' || action === 'edit.highlightUsagesInFile') {
      this.handleAction('edit.findUsages');
      return;
    }
    if (action === 'edit.nextHighlightUsage' || action === 'edit.prevHighlightUsage') {
      this.handleAction(action === 'edit.nextHighlightUsage' ? 'edit.findNext' : 'edit.findPrev');
      return;
    }
    if (action === 'edit.scrollToResults') {
      this.setStatus('输入时滚动至结果：已启用（本地查找即时定位）');
      return;
    }
    if (action === 'edit.playbackMacro' || action === 'edit.recordMacro' || action === 'edit.editMacros'
      || action === 'edit.playSavedMacro') {
      this.showInfo('宏', [
        'PyCharm 的宏可录制编辑器操作并回放。',
        '本 IDE 暂未实现宏录制；重复性编辑可用「复制当前行」「注释」「格式化」等命令。'
      ]);
      return;
    }
    // 书签（PyCharm：ToggleBookmark F11 / ShowBookmarks Shift+F11 / NextBookmark）
    if (action === 'edit.toggleBookmark') {
      this.toggleBookmark();
      return;
    }
    if (action === 'edit.showBookmarks') {
      this.dialogTitle = '书签';
      this.dialog = 'bookmarks';
      return;
    }
    if (action === 'edit.nextBookmark') {
      const tab: EditorTab | undefined = this.activeTab();
      if (tab === undefined) {
        this.showToast('没有打开的编辑器');
        return;
      }
      const prefix: string = `${tab.path}#`;
      const lines: number[] = this.bookmarks
        .filter((x: string) => x.startsWith(prefix))
        .map((x: string) => Number.parseInt(x.substring(prefix.length), 10))
        .filter((n: number) => !Number.isNaN(n))
        .sort((a: number, b: number) => a - b);
      if (lines.length === 0) {
        this.showToast('当前文件没有书签（编辑器右键 → 切换书签，或按 F11）');
        return;
      }
      const next: number = lines.find((n: number) => n > this.cursorLine) ?? lines[0];
      this.editorController.revealLine(next);
      this.setStatus(`已跳到书签：第 ${next} 行`);
      return;
    }
    if (action === 'tools.resetLayout') {
      // 死状态逃生口：面板全部恢复可见、关掉任何卡住的对话框、重新打开当前工程
      this.dialog = '';
      this.settings.showLeftToolWindow = true;
      this.settings.showBottomToolWindow = true;
      this.search.visible = false;
      this.loadProject(this.projectRoot);
      this.setStatus('界面布局已重置');
      this.showToast('界面布局已重置');
      return;
    }
    if (action === 'tools.reinit') {
      this.reinitRuntime();
      return;
    }
    if (action === 'tools.settings') {
      this.dialog = 'settings';
      return;
    }
    if (action === 'help.about') {
      this.dialog = 'about';
      return;
    }
    if (action === 'help.docs') {
      this.dialog = 'docs';
      return;
    }
    this.showToast(`功能「${action}」在路线图中`);
  }

  private toggleTheme(): void {
    this.themeName = this.themeName === 'darcula' ? 'light' : 'darcula';
    this.theme = this.themeName === 'light' ? INTELLIJ_LIGHT : DARCULA;
    this.settings.themeName = this.themeName;
    SettingsService.save(this.settings);
    this.setStatus(this.themeName === 'light' ? '已切换到浅色主题' : '已切换到深色主题');
  }

  private formatActive(): void {
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined) {
      return;
    }
    const lines: string[] = tab.text.split('\n');
    const formatted: string[] = [];
    for (const line of lines) {
      const expanded: string = line.replace(/\t/g, ' '.repeat(this.settings.tabSize));
      formatted.push(expanded.replace(/[ \t]+$/, ''));
    }
    const next: string = formatted.join('\n');
    if (next === tab.text) {
      this.showToast('无需格式化');
      return;
    }
    tab.updateText(next);
    this.editorSeedText = next;
    this.tabs = this.tabs.slice();
    this.showToast('已去除行尾空白并展开 Tab（完整 PEP8 格式化在路线图中）');
  }

  private openInputDialog(title: string, defaultValue: string, kind: string): void {
    this.dialogTitle = title;
    this.inputValue = defaultValue;
    this.dialog = kind;
  }

  /** 新建文件（多语言）：先展示 LanguageService.languages() 的语言列表 */
  private openNewFileDialog(): void {
    if (this.dialogTarget.length === 0) {
      this.dialogTarget = this.projectRoot;
    }
    this.dialogTitle = '新建文件';
    this.dialog = 'newFileLang';
  }

  /** 选中语言 → 进入文件名输入（扩展名决定语法高亮与模板） */
  private chooseNewFileLang(lang: LangDef): void {
    const dir: string = this.dialogTarget.length > 0 ? this.dialogTarget : this.projectRoot;
    const ext: string = lang.exts.length > 0 ? lang.exts[0] : 'txt';
    this.openInputDialog(`新建 ${lang.name} 文件`, `${dir}/untitled.${ext}`, 'newFile');
  }

  private confirmInputDialog(): void {
    const value: string = this.inputValue.trim();
    const kind: string = this.dialog;
    this.dialog = '';
    if (kind === 'runArgs') {
      // 形参允许为空（等价于直接运行）
      const parts: string[] = value.length > 0 ? value.split(/\s+/) : [];
      this.runActiveFile(false, parts);
      return;
    }
    if (value.length === 0) {
      return;
    }
    if (kind === 'goto') {
      const line: number = Number.parseInt(value, 10);
      if (Number.isNaN(line) || line < 1) {
        this.showToast('请输入有效的行号');
        return;
      }
      const cur: EditorTab | undefined = this.activeTab();
      if (cur !== undefined) {
        this.recordLocation(cur.path, line);
      }
      this.editorController.revealLine(line);
      this.setStatus(`已转到第 ${line} 行`);
      return;
    }
    if (kind === 'newFile') {
      const target: string = value.includes('/') ? value : `${this.projectRoot}/${value}`;
      if (FileService.exists(target)) {
        this.showToast('同名文件已存在');
        return;
      }
      FileService.createFile(target, this.newFileTemplate(FileService.baseName(target)));
      this.refreshDir(FileService.parentOf(target));
      this.openFile(target, FileService.baseName(target));
      return;
    }
    if (kind === 'newFolder') {
      const target: string = `${this.dialogTarget}/${value}`;
      FileService.createDir(target);
      this.refreshDir(this.dialogTarget);
      return;
    }
    if (kind === 'newProject') {
      const target: string = `${FileService.projectRoot()}/${value}`;
      FileService.createSampleProject(target);
      this.loadProject(target);
      this.showToast(`已创建项目 ${value}`);
      return;
    }
    if (kind === 'rename') {
      const parent: string = FileService.parentOf(this.dialogTarget);
      const target: string = `${parent}/${value}`;
      if (FileService.exists(target)) {
        this.showToast('目标已存在');
        return;
      }
      FileService.rename(this.dialogTarget, target);
      for (const tab of this.tabs) {
        if (tab.path === this.dialogTarget) {
          tab.path = target;
          tab.id = target;
          tab.name = value;
        }
      }
      if (this.activeTabId === this.dialogTarget) {
        this.activeTabId = target;
        this.editorFilePath = target;
      }
      this.tabs = this.tabs.slice();
      this.refreshDir(parent);
      return;
    }
    if (kind === 'pip') {
      this.pipRun(value.split(' '));
      return;
    }
    if (kind === 'runConfig') {
      this.showToast('运行参数在路线图中');
      return;
    }
  }

  /**
   * 新建文件内容：按 LanguageService 识别出的语言给出骨架
   * （扩展名 → 语言，与高亮/状态栏用的是同一份 LanguageService 数据）
   */
  private newFileTemplate(name: string): string {
    const lang: LangDef = languageOf(name);
    const dot: number = name.lastIndexOf('.');
    const base: string = dot > 0 ? name.substring(0, dot) : name;
    const upper: string = base.length > 0 ? base.charAt(0).toUpperCase() + base.substring(1) : base;
    if (lang.id === 'Python') {
      return [
        `"""${base} 模块。"""`,
        '',
        '',
        'def main() -> None:',
        `    print("Hello from ${base}")`,
        '',
        '',
        'if __name__ == "__main__":',
        '    main()',
        ''
      ].join('\n');
    }
    if (lang.id === 'Java') {
      return [`public class ${upper} {`, `    public static void main(String[] args) {`,
        `        System.out.println("Hello from ${base}");`, '    }', '}', ''].join('\n');
    }
    if (lang.id === 'Kotlin') {
      return ['fun main() {', `    println("Hello from ${base}")`, '}', ''].join('\n');
    }
    if (lang.id === 'C/C++') {
      return ['#include <stdio.h>', '', 'int main(void) {',
        `    printf("Hello from ${base}\\n");`, '    return 0;', '}', ''].join('\n');
    }
    if (lang.id === 'JavaScript' || lang.id === 'TypeScript') {
      return [`function main() {`, `  console.log('Hello from ${base}');`, '}',
        '', 'main();', ''].join('\n');
    }
    if (lang.id === 'Go') {
      return ['package main', '', 'import "fmt"', '', 'func main() {',
        `\tfmt.Println("Hello from ${base}")`, '}', ''].join('\n');
    }
    if (lang.id === 'Rust') {
      return ['fn main() {', `    println!("Hello from ${base}");`, '}', ''].join('\n');
    }
    if (lang.id === 'HTML') {
      return ['<!DOCTYPE html>', '<html lang="zh">', '<head>', '  <meta charset="utf-8">',
        `  <title>${base}</title>`, '</head>', '<body>', `  <h1>${base}</h1>`, '</body>',
        '</html>', ''].join('\n');
    }
    if (lang.id === 'CSS') {
      return [`/* ${base} */`, 'body {', '  margin: 0;', '}', ''].join('\n');
    }
    if (lang.id === 'JSON') {
      return ['{', `  "name": "${base}"`, '}', ''].join('\n');
    }
    if (lang.id === 'YAML') {
      return [`# ${base}`, 'name: ' + base, ''].join('\n');
    }
    if (lang.id === 'XML') {
      return ['<?xml version="1.0" encoding="UTF-8"?>', `<${base}>`, `</${base}>`, ''].join('\n');
    }
    if (lang.id === 'Markdown') {
      return [`# ${base}`, '', ''].join('\n');
    }
    if (lang.id === 'SQL') {
      return [`-- ${base}`, 'SELECT 1;', ''].join('\n');
    }
    if (lang.id === 'Shell Script') {
      return ['#!/bin/sh', '', `echo "Hello from ${base}"`, ''].join('\n');
    }
    if (lang.id === 'Properties') {
      return [`# ${base}`, 'key=value', ''].join('\n');
    }
    if (lang.id === 'Dockerfile') {
      return ['FROM ubuntu:24.04', `LABEL name="${base}"`, ''].join('\n');
    }
    return '';
  }

  private confirmDelete(): void {
    const target: string = this.dialogTarget;
    this.dialog = '';
    if (target.length === 0) {
      return;
    }
    this.tabs = this.tabs.filter((tab: EditorTab) => !tab.path.startsWith(target));
    try {
      FileService.remove(target);
      this.refreshDir(FileService.parentOf(target));
      this.showToast('已删除');
    } catch (err) {
      this.appendError(`删除失败：${JSON.stringify(err)}`);
    }
  }

  private async importFiles(): Promise<void> {
    if (this.uiContext === undefined) {
      return;
    }
    try {
      const created: string[] = await FileService.importFiles(this.uiContext, this.projectRoot);
      this.refreshDir(this.projectRoot);
      if (created.length > 0) {
        this.openFile(created[0], FileService.baseName(created[0]));
        this.showToast(`已导入 ${created.length} 个文件`);
      }
    } catch (err) {
      this.appendError(`导入失败：${JSON.stringify(err)}`);
    }
  }

  private async exportActive(): Promise<void> {
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined || this.uiContext === undefined) {
      return;
    }
    this.saveTab(tab);
    try {
      const uri: string = await FileService.exportFile(this.uiContext, tab.path);
      if (uri.length > 0) {
        this.showToast('已导出到所选位置');
      }
    } catch (err) {
      this.appendError(`导出失败：${JSON.stringify(err)}`);
    }
  }

  private openProjectDialog(): void {
    const root: string = FileService.projectRoot();
    const names: string[] = [];
    try {
      const nodes: FileNode[] = FileService.listDir(root, 0);
      for (const node of nodes) {
        if (node.isDir) {
          names.push(node.path);
        }
      }
    } catch (err) {
      this.appendError(`读取项目列表失败：${JSON.stringify(err)}`);
    }
    this.projectList = names;
    this.dialog = 'projectList';
  }

  // ── 查找 / 替换 ────────────────────────────────────────────────────────

  private runSearch(): void {
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined || this.search.query.length === 0) {
      this.search.reset();
      this.search = this.search;
      return;
    }
    const matches: number[] = [];
    const haystack: string = this.search.caseSensitive ? tab.text : tab.text.toLowerCase();
    const needle: string = this.search.caseSensitive ? this.search.query : this.search.query.toLowerCase();
    let from: number = 0;
    while (from <= haystack.length) {
      const found: number = haystack.indexOf(needle, from);
      if (found < 0) {
        break;
      }
      matches.push(found);
      from = found + Math.max(1, needle.length);
    }
    this.search.matches = matches;
    this.search.currentIndex = matches.length > 0 ? 0 : -1;
    this.search = this.search;
    if (matches.length > 0) {
      this.editorController.revealOffset(matches[0]);
    }
  }

  private searchNext(forward: boolean): void {
    if (this.search.matches.length === 0) {
      this.runSearch();
      return;
    }
    let index: number = this.search.currentIndex + (forward ? 1 : -1);
    if (index >= this.search.matches.length) {
      index = 0;
    }
    if (index < 0) {
      index = this.search.matches.length - 1;
    }
    this.search.currentIndex = index;
    this.search = this.search;
    this.editorController.revealOffset(this.search.matches[index]);
  }

  private replaceCurrent(): void {
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined || this.search.currentIndex < 0) {
      return;
    }
    const offset: number = this.search.matches[this.search.currentIndex];
    const next: string = tab.text.substring(0, offset) + this.search.replaceText
      + tab.text.substring(offset + this.search.query.length);
    tab.updateText(next);
    this.editorSeedText = next;
    this.tabs = this.tabs.slice();
    this.runSearch();
  }

  private replaceAll(): void {
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined || this.search.query.length === 0) {
      return;
    }
    const replaced: string = tab.text.split(this.search.query).join(this.search.replaceText);
    tab.updateText(replaced);
    this.editorSeedText = replaced;
    this.tabs = this.tabs.slice();
    this.showToast('已全部替换');
    this.runSearch();
  }

  // ── 视图辅助 ───────────────────────────────────────────────────────────

  private layoutFromWidth(width: number): string {
    if (width < 720) {
      return LayoutSize.COMPACT;
    }
    if (width < 1100) {
      return LayoutSize.MEDIUM;
    }
    return LayoutSize.EXPANDED;
  }

  private leftPanelWidth(): number {
    if (this.layoutSize === LayoutSize.COMPACT) {
      return 200;
    }
    if (this.layoutSize === LayoutSize.MEDIUM) {
      return Math.min(240, this.settings.leftPanelWidth);
    }
    return this.settings.leftPanelWidth;
  }

  private bottomPanelHeight(): number {
    if (this.layoutSize === LayoutSize.COMPACT) {
      return 150;
    }
    return this.settings.bottomPanelHeight;
  }

  private scheduleAutoSave(): void {
    if (!this.settings.autoSave) {
      return;
    }
    if (this.autoSaveTimer >= 0) {
      clearTimeout(this.autoSaveTimer);
    }
    this.autoSaveTimer = setTimeout(() => {
      this.autoSaveTimer = -1;
      const tab: EditorTab | undefined = this.activeTab();
      if (tab !== undefined && tab.dirty) {
        this.saveTab(tab);
      }
    }, this.settings.autoSaveDelayMs);
  }

  // ── 渲染 ───────────────────────────────────────────────────────────────

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // 主菜单模式 1：隐藏在汉堡按钮下方 —— 不画菜单栏，顶栏最左放汉堡按钮
        // 「隐藏在汉堡按钮下方」时菜单栏不画；点 ☰ 才把菜单标题横向展开（见顶栏行里的 MenuBarView）
        // 主菜单模式 2：显示在主工具栏上方 —— 菜单栏单独占一行
        if (this.menuOwnRow) {
          Row() {
            MenuBarView({
              theme: this.theme,
              appTitle: this.projectName.length > 0 ? `鸿蒙Python IDE — ${this.projectName}` : '鸿蒙Python IDE',
              projectName: this.projectName,
              openMenuTitle: $menuOpenTitle,
              popupX: $menuPopupX,
              onMenuAction: (action: string) => this.handleAction(action)
            })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
        }
        Row() {
          // 菜单栏常显；「工具栏(_T)」只控制主工具栏（与 PyCharm 的 ViewToolBar 语义一致）
          // 隐藏在汉堡按钮下方：
          //   ☰ 图标 = AllIcons.General.WindowsMenu_20x20（expui/general/windowsMenu@20x20.svg）
          //   ☰ 与「Python 标识 + 工程/VCS 微件」同排共存（PyCharm: ToolbarFrameHeader 里 MainMenuButton 与 ProjectWidget 同排）
          //   点 ☰ → 菜单标题**横向展开**（PyCharm registry: ide.main.menu.expand.horizontal=true）
          if (this.menuMode === 'hamburger') {
            MenuBarView({
              theme: this.theme,
              appTitle: this.projectName.length > 0 ? `鸿蒙Python IDE — ${this.projectName}` : '鸿蒙Python IDE',
              projectName: this.projectName,
              openMenuTitle: $menuOpenTitle,
              popupX: $menuPopupX,
              showTitles: this.hamburgerShown,
              hamburger: true,
              onHamburgerToggle: () => {
                // ExpandableMenu.switchState：再点一次收回
                this.hamburgerShown = !this.hamburgerShown;
                this.menuOpenTitle = '';
                FileService.log(`hamburger switchState expanded=${this.hamburgerShown}`);
              },
              onMenuAction: (action: string) => {
                // 选中菜单项后自动收起（ExpandableMenu.hideExpandedMenuBar）
                this.hamburgerShown = false;
                this.handleAction(action);
              }
            })
          }

          if (this.menuMode === 'merged') {
            MenuBarView({
              theme: this.theme,
              appTitle: this.projectName.length > 0 ? `鸿蒙Python IDE — ${this.projectName}` : '鸿蒙Python IDE',
              projectName: this.projectName,
              openMenuTitle: $menuOpenTitle,
              popupX: $menuPopupX,
              showTitles: true,
              onMenuAction: (action: string) => this.handleAction(action)
            })
          }

          if (this.showMainToolbar) {
            ToolBarView({
              theme: this.theme,
              runConfigs: ['当前文件'],
              currentRunConfig: '当前文件',
              running: this.running,
              canUndo: false,
              canRedo: false,
              searchText: this.search.query,
              onToolbarAction: (action: string) => this.handleAction(action),
              hasRun: this.hasRunOnce,
              activeFileName: (this.activeTab() !== undefined) ? (this.activeTab() as EditorTab).name : '',
              activeFilePath: (this.activeTab() !== undefined) ? (this.activeTab() as EditorTab).path : '',
              onActiveFileClick: () => {
                this.dialogTitle = '打开的编辑器';
                this.dialog = 'openEditors';
              },
              onRunConfigChange: (name: string) => this.setStatus(`运行配置：${name}`),
              onSearchChange: (text: string) => {
                this.search.query = text;
                this.search = this.search;
              },
              onSearchSubmit: (text: string) => {
                this.search.visible = true;
                this.runSearch();
              }
            })
            .layoutWeight(1)
            .clip(false)
          } else {
            Blank().layoutWeight(1)
          }
        }
        .width('100%')
        .clip(false)
        // 抬 z 序：顶栏里的下拉弹层（运行配置/⋮）要画在下面的编辑器岛之上，否则被盖住
        .zIndex(20)
        // 顶栏右键 / 长按 → MainToolbarPopupActions（PyCharm 顶部工具栏右键菜单）
        .onMouse((event: MouseEvent) => {
          if (event.button === MouseButton.Right) {
            this.openTopMenu(event.x, event.y + 38);
          }
        })
        // 平板没有右键：长按等效右键，位置取长按点（不再是固定坐标）
        .parallelGesture(
          LongPressGesture({ repeat: false })
            .onAction((event: GestureEvent) => {
              if (event.fingerList !== undefined && event.fingerList.length > 0) {
                this.openTopMenu(event.fingerList[0].globalX, event.fingerList[0].globalY);
              } else {
                this.openTopMenu(8, 40);
              }
            })
        )
        // 顶栏 = main-window-bg（主题文件 MainToolbar.background = main-window-bg）。
        // 它和「顶栏下面的间隙」「左右竖条」「状态栏」用的是同一个底色 →
        // 这几块在视觉上是**一个连续区域**，中间不出现任何色块或线条。
        // （颜色来自根层那条竖向渐变，这里保持透明 → 顶栏与下面的间隙/竖条/状态栏同属一层。）

        // 主题 MainToolbar.borderColor = transparent：顶栏下沿不画线。
        // 保留这个 1vp 元素只为维持头部高度（RIGHT_STRIP_TOP 的基准），但必须完全透明 ——
        // 之前它是一条比窗口底色更深的线，把顶栏的绿渐变"切断"了。
        Divider().color(Color.Transparent).strokeWidth(1)

        Row() {
          // 左侧竖条已移到根层做「通高」（见文件后面的同名块）：
          // 竖条从工具栏下方一直延伸到窗口底边，内容岛 / 底部工具窗都在它右侧开始。
          // 这里只把竖条宽度让出来。

          if (this.settings.showLeftToolWindow) {
            Column() {
              ProjectTreeView({
                theme: this.theme,
                projectName: this.projectName,
                projectRoot: this.projectRoot,
                nodes: this.flatNodes,
                selectedPath: this.selectedPath,
                activeFilePath: (this.activeTab() !== undefined)
                  ? (this.activeTab() as EditorTab).path : '',
                locateTick: this.locateTick,
                onLocate: () => this.locateActiveInTree(),
                onSelect: (path: string) => {
                  this.selectedPath = path;
                },
                previewTab: this.optPreviewTab,
                singleClickOpen: this.optSingleClickOpen,
                openDirsSingle: this.optOpenDirsSingle,
                autoscrollFromSource: this.optAutoscrollFromSource,
                showExcluded: this.optShowExcluded,
                showScratches: this.optShowScratches,
                projectIconFile: this.projectIcon,
                // 齿轮菜单里真正影响树的开关：改了之后重建视图树
                onViewOption: (key: string, value: boolean) => {
                  // ProjectView.ToolWindow.Behavior/Appearance.Actions 的开关都从这里落到真状态
                  if (key === 'compact') {
                    this.treeCompactDirs = value;
                  } else if (key === 'foldersFirst') {
                    this.treeDirsFirst = value;
                  } else if (key === 'preview') {
                    this.optPreviewTab = value;
                  } else if (key === 'singleClick') {
                    this.optSingleClickOpen = value;
                  } else if (key === 'singleDir') {
                    this.optOpenDirsSingle = value;
                  } else if (key === 'autoscroll') {
                    this.optAutoscrollFromSource = value;
                  } else if (key === 'excluded') {
                    this.optShowExcluded = value;
                  } else if (key === 'scratches') {
                    this.optShowScratches = value;
                  }
                  FileService.log(`project view option ${key}=${value}`);
                  this.refreshFlatten();
                  this.treeRoots = this.treeRoots.slice();
                  this.flatNodes = this.flatNodes.slice();
                },
                filterText: this.filterText,
                // 单击 = 预览标签，再次点击同一行 = 钉住（PyCharm 的预览标签语义）
                openFile: (path: string, name: string, preview: boolean) => this.openFile(path, name, preview),
                toggleDir: (node: FileNode) => this.toggleDirByPath(node.path),
                refreshDir: (path: string) => this.refreshDir(path),
                newFile: (dirPath: string) => {
                  this.dialogTarget = dirPath;
                  this.openNewFileDialog();
                },
                newFolder: (dirPath: string) => {
                  this.dialogTarget = dirPath;
                  this.openInputDialog('新建目录', 'new_folder', 'newFolder');
                },
                renamePath: (path: string) => {
                  this.dialogTarget = path;
                  this.openInputDialog('重命名', FileService.baseName(path), 'rename');
                },
                deletePath: (path: string) => {
                  this.dialogTarget = path;
                  this.dialog = 'delete';
                },
                // PyCharm ProjectViewPopupMenu：复制路径(_O) / 运行 / 未实现项的说明
                copyPath: (path: string) => {
                  FileService.copyToClipboard(path);
                  this.setStatus(`已复制路径：${path}`);
                },
                runPath: (path: string) => {
                  this.openFile(path, FileService.baseName(path));
                  this.runActiveFile(false);
                },
                onTreeInfo: (kind: string) => {
                  if (kind === 'ctx.cut' || kind === 'ctx.copy' || kind === 'ctx.paste') {
                    this.showInfo('文件剪贴板', [
                      'PyCharm 支持在工程树里剪切/复制/粘贴文件。',
                      '本 IDE 暂未实现文件级剪贴板（可用「复制路径」+ 终端里的 Python 脚本完成）。'
                    ]);
                    return;
                  }
                  this.showInfo('重构', [
                    'PyCharm 的工程树重构（重命名/移动/复制/安全删除/引入变量…）依赖语义分析引擎。',
                    '本 IDE 已提供：重命名、删除、新建文件/目录、从磁盘重新加载、运行。',
                    '符号级重构列入后续版本。'
                  ]);
                },
                onToolWindowMenu: () => {
                  this.twMenuShown = true;
                },
                // ProjectView.Sort.Actions：按名称/类型/修改时间排序
                onSortChange: (by: string) => {
                  this.treeSortBy = by;
                  this.setStatus(`项目树排序：${by === 'name' ? '按名称' : (by === 'type' ? '按类型'
                    : (by === 'timeDesc' ? '按修改时间(新→旧)' : (by === 'timeAsc' ? '按修改时间(旧→新)' : '手动')))}`);
                },
                onRowMenu: (path: string, x: number, y: number) => {
                  this.treeMenuPath = path;
                  this.treeMenuX = x > 40 ? x - 40 : 8;
                  // 菜单 33 项（~860vp）> 窗口高度：窗口内放不下时上移，避免底部条目被裁
                  const treeMenuH: number = 560;
                  const treeWantY: number = y > 20 ? y - 20 : 8;
                  this.treeMenuY = Math.max(8, Math.min(treeWantY, this.windowHeight - treeMenuH - 8));
                  FileService.log(`tree longpress menu path=${path} at ${x},${y}`);
                },
                onFilterChange: (text: string) => {
                  this.filterText = text;
                  this.refreshFlatten();
                },
                collapseAll: () => this.collapseAllNodes(),
                expandAll: () => this.expandAllNodes(),
                hideWindow: () => {
                  this.settings.showLeftToolWindow = false;
                }
              })
              .layoutWeight(this.leftSplitRatio)
              // Project 工具窗自己是一个圆角小岛（window.layouts.xml 里 Project 与 Structure 是同级的独立工具窗）
              .backgroundColor(this.theme.panelBg)
              .borderRadius(this.theme.islandArc)
              .clip(true)
              .margin({
                left: this.theme.islandGap,
                // 顶部间隙改由外层左列统一提供一次（岛自身不再留 top）
                // 右侧不留边距：与编辑区之间的间隙由分隔条提供
                right: 0
              })

              // Project / Structure 之间的水平拖拽条（上下两区可自由调高度）
              Column() {
                Column()
                  .width('100%')
                  .height(1)
                  // 默认透明：分隔条只在 hover 时显形（PyCharm 的 splitter 也是这样），
                  // 否则在着色的 chrome 上会看到一条隐约的深色线
                  .backgroundColor(this.hDividerHover ? this.theme.funcName : Color.Transparent)
              }
              // 岛间间隙只在这里提供一次（= islandGap）；两个岛自身都不再留上下 margin
              .height(this.theme.islandGap)
              .justifyContent(FlexAlign.Center)
              .onHover((isHover: boolean) => {
                this.hDividerHover = isHover;
              })
              .gesture(
                PanGesture({ direction: PanDirection.Vertical })
                  .onActionStart(() => {
                    this.dragStartRatio = this.leftSplitRatio;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const delta: number = event.offsetY / this.windowHeight;
                    const r: number = this.dragStartRatio + delta;
                    this.leftSplitRatio = r < 0.2 ? 0.2 : (r > 0.85 ? 0.85 : r);
                  })
              )

              // Structure 工具窗（PyCharm 左下方常驻面板：显示当前文件的符号）
              Column() {
                Row() {
                  Text('Structure')
                    .fontSize(12)
                    .fontFamily(PyFont.ui)
                    .fontColor(this.theme.textPrimary)
                    .layoutWeight(1)
                  // 范围切换：PyCharm 的 Structure 视图可切换 文件/工程 范围
                  Text('文件')
                    .fontSize(11)
                    .fontColor(this.structureScope === 'file' ? this.theme.textOnAccent : this.theme.textSecondary)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .backgroundColor(this.structureScope === 'file' ? this.theme.buttonPrimaryBg : this.theme.buttonBg)
                    .onClick(() => {
                      this.structureScope = 'file';
                    })
                  Text('工程')
                    .fontSize(11)
                    .fontColor(this.structureScope === 'project' ? this.theme.textOnAccent : this.theme.textSecondary)
                    .margin({ left: 4 })
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .backgroundColor(this.structureScope === 'project' ? this.theme.buttonPrimaryBg : this.theme.buttonBg)
                    .onClick(() => {
                      this.structureScope = 'project';
                      this.loadProjectSymbols();
                    })
                }
                .width('100%')
                .height(30)
                .padding({ left: 12, right: 12 })
                .alignItems(VerticalAlign.Center)

                Scroll() {
                  Column() {
                    if ((this.structureScope === 'project' ? this.projectPanelRows.length : this.liveStructure.length) === 0) {
                      Text(this.structureScope === 'project' ? '（正在扫描全工程符号…）' : '（当前文件没有可识别的定义）')
                        .fontSize(12)
                        .fontFamily(PyFont.ui)
                        .fontColor(this.theme.textDisabled)
                        .padding({ left: 12, top: 4 })
                    } else {
                      ForEach(this.structureScope === 'project' ? this.projectPanelRows : this.liveStructure, (row: string) => {
                        Text(row)
                          .fontSize(12)
                          .fontFamily(PyFont.mono)
                          .fontColor(this.theme.textSecondary)
                          .width('100%')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .padding({ left: 12, right: 8, top: 4, bottom: 4 })
                          // 点结构行 → 跳到定义（工程范围可跨文件）
                          .onClick(() => {
                            if (this.structureScope === 'project') {
                              const m: RegExpMatchArray | null = row.match(/(\S+):(\d+)\s*$/);
                              if (m !== null) {
                                const rel: string = m[1];
                                const line: number = Number.parseInt(m[2], 10);
                                const target: string = `${this.projectRoot}/${rel}`;
                                if (FileService.exists(target) && target !== this.editorFilePath) {
                                  this.openFile(target, rel.substring(rel.lastIndexOf('/') + 1));
                                }
                                this.editorController.revealLine(line);
                                this.setStatus(`已跳到 ${rel}:${line}`);
                              }
                            } else {
                              const line: number = this.lineOfSymbol(row);
                              if (line > 0) {
                                this.editorController.revealLine(line);
                                this.setStatus(`已跳到第 ${line} 行`);
                              }
                            }
                          })
                          // PyCharm：Structure 视图右键 → StructureViewPopupMenu
                          .onMouse((event: MouseEvent) => {
                            if (event.button === MouseButton.Right) {
                              this.structMenuSymbol = row.replace('ƒ  ', '').replace('C  ', '').trim();
                              this.structMenuX = Math.max(8, event.x);
                              this.structMenuY = Math.max(8, Math.min(event.y, this.windowHeight - 460 - 8));
                              this.structMenuShown = true;
                            }
                          })
                          .gesture(
                            LongPressGesture({ repeat: false })
                              .onAction(() => {
                                this.structMenuSymbol = row.replace('ƒ  ', '').replace('C  ', '').trim();
                                this.structMenuX = 60;
                                this.structMenuY = Math.max(8, Math.min(200, this.windowHeight - 468));
                                this.structMenuShown = true;
                              })
                          )
                      }, (row: string, index: number) => `st-${index}-${row}`)
                    }
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                }
                .layoutWeight(1)
                .width('100%')
                .align(Alignment.TopStart)
                .scrollBar(BarState.Auto)
              }
              .layoutWeight(1 - this.leftSplitRatio)
              // 注意：这里不能写 .width('100%')，否则宽 100% + 外边距会溢出成满宽，
              // 导致 Structure 岛比 Project 岛宽（实测 532 vs 510）
              // Structure 也是独立小岛（PyCharm 的 isSplit 工具窗：两个同级岛）
              .backgroundColor(this.theme.panelBg)
              .borderRadius(this.theme.islandArc)
              .clip(true)
              // 岛间间隙由上面那条分隔条提供（只有一次 islandGap），这里不再留 top/bottom
              .margin({
                left: this.theme.islandGap,
                right: 0
              })
            }
            .width(this.leftPanelWidth())
            // 撑满内容区：不再用公式算高（底部工具窗隐藏时公式会少算一份面板高，把左列截短）
            .height('100%')
            // 上下间隙都由外层统一提供一次：于是
            // Project 岛顶边 == 编辑器岛顶边，Structure 岛底边 == 编辑器岛底边
            .padding({ top: this.theme.islandGap, bottom: this.theme.islandGap })

            // 可拖拽分隔条（6vp 易抓；悬停高亮提示可拖动）
            Column() {
              Column()
                .width(1)
                .height('100%')
                .backgroundColor(this.leftDividerHover ? this.theme.funcName : Color.Transparent)
            }
            .width(6)
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .onHover((isHover: boolean) => {
              this.leftDividerHover = isHover;
            })
            .gesture(
              PanGesture({ direction: PanDirection.Horizontal })
                .onActionStart(() => {
                  this.dragStartPanelW = this.settings.leftPanelWidth;
                })
                .onActionUpdate((event: GestureEvent) => {
                  // 无级调节：起始宽度 + 本次位移（offsetX 是相对手势起点的累计值）
                  const width: number = this.dragStartPanelW + event.offsetX;
                  this.settings.leftPanelWidth = Math.max(160, Math.min(560, width));
                })
                .onActionEnd(() => {
                  SettingsService.save(this.settings);
                })
            )
          }

          Column() {
            this.EditorTabsBar()

            if (this.search.visible) {
              this.SearchBar()
            }

            if (this.tabs.length === 0) {
              WelcomeView({
                theme: this.theme,
                recentProjects: [this.projectRoot],
                runtime: this.runtime,
                isLoading: this.loading,
                newProject: () => this.handleAction('file.newProject'),
                openProject: () => this.handleAction('file.openProject'),
                openRecent: (path: string) => this.loadProject(path),
                openSettings: () => this.handleAction('tools.settings')
              })
            } else {
              // 多窗格：Flex 承载 1..2 个窗格（方向随拆分方向变：h=左右 / v=上下），岛样式移到容器上
              // paneBefore（向左/向上拆分）= 新窗格在前侧 → 用 RowReverse/ColumnReverse 反转视觉顺序
              Flex({ direction: this.paneSplit === 'v'
                  ? (this.paneBefore ? FlexDirection.ColumnReverse : FlexDirection.Column)
                  : (this.paneBefore ? FlexDirection.RowReverse : FlexDirection.Row),
                alignItems: ItemAlign.Stretch }) {
                Column() {
                if (this.showBreadcrumb) {
                  this.BreadcrumbBar()
                }
                CodeEditor({
                  initialText: this.editorSeedText,                  filePath: this.editorFilePath,
                  theme: this.theme,
                  fontSize: this.settings.fontSize,
                  tabSize: this.settings.tabSize,
                  hiddenLines: this.hiddenLines(),
                  foldableLines: this.foldableLines(),
                  onToggleFold: (line: number) => this.toggleFoldAtLine(line),
                  onSelectionChange: (start: number, end: number) => {
                    this.selStartSel = start;
                    this.selEndSel = end;
                  },
                  showLineNumbers: this.settings.showLineNumbers,
                  highlightCurrentLine: this.settings.highlightCurrentLine,
                  showIndentGuides: this.showIndentGuides,
                  breakpoints: this.pendingBreakpoints,
                  warnLines: this.warnLines,
                  debugLine: this.debugLine,
                  controller: this.editorController,
                  // 编辑器内右键 → EditorPopupMenu
                  onEditorMenu: (x: number, y: number) => {
                    this.editorMenuX = x > 60 ? x - 60 : 8;
                    // 菜单很高（EditorPopupMenu 约 20 项）：窗口内放不下时上移，避免底部被裁掉
                    const menuH: number = 560;
                    const maxY: number = this.windowHeight - menuH - 8;
                    const wantY: number = y > 40 ? y - 20 : 40;
                    this.editorMenuY = Math.max(40, Math.min(wantY, maxY));
                    this.editorMenuShown = true;
                  },
                  // 编辑器获得焦点 → 竖条选中态由蓝变灰（PyCharm 实测行为）
                  onEditorFocus: () => {
                    if (this.activePane !== 'editor') {
                      this.activePane = 'editor';
                      FileService.log('activePane -> editor（编辑器焦点，竖条药丸转灰）');
                    }
                  },
                  onTextChange: (text: string) => {
                    FileService.log(`pane1 change len=${text.length}`);
                    const tab: EditorTab | undefined = this.activeTab();
                    if (tab !== undefined) {
                      tab.updateText(text);
                      // 一旦"真的被编辑"预览标签立即转正（PyCharm 行为）。
                      // 注意：程序化刷新文本也会触发 onChange，所以用 dirty 判定，不能无条件转正。
                      if (tab.dirty) {
                        tab.preview = false;
                      }
                      this.tabs = this.tabs.slice();
                      this.scheduleAutoSave();
                    }
                    this.refreshStructure(text);
                  },
                  onCursorChange: (line: number, column: number) => {
                    this.cursorLine = line;
                    this.cursorColumn = column;
                    const tab: EditorTab | undefined = this.activeTab();
                    if (tab !== undefined) {
                      tab.cursorLine = line;
                      tab.cursorColumn = column;
                    }
                  },
                  onToggleBreakpoint: (line: number) => this.toggleBreakpoint(line),
                  onClipboardAction: (action: string, length: number) => {
                    if (action === 'paste-empty') {
                      this.showToast('剪贴板为空');
                    } else if (action === 'copy') {
                      this.setStatus(`已复制 ${length} 个字符`);
                    } else if (action === 'cut') {
                      this.setStatus(`已剪切 ${length} 个字符`);
                    } else {
                      this.setStatus(`已粘贴 ${length} 个字符`);
                    }
                  }
                })
                .layoutWeight(1)
                }
                .layoutWeight(this.paneRatio)
                // ── 多窗格：分隔条 + 第 2 窗格（**只读镜像**：不挂 onTextChange/onCursorChange，
                //    避免两个 CodeEditor 实例互相写回同一文件造成文本抖动/自动保存覆盖）──
                if (this.paneSplit !== 'none') {
                  // 分隔条：22vp 触控区（原 6vp 太细，手指抓不住）+ 中间 2vp 细线
                  Column() {
                    // 分隔线：横向拆分时贯穿整高（2vp 宽），纵向拆分时贯穿整宽（2vp 高）
                    Column()
                      .width(this.paneSplit === 'v' ? '100%' : 3)
                      .height(this.paneSplit === 'v' ? 3 : '100%')
                      // 深色主题下 border 几乎看不见；默认用 separator，悬停时用强调色（PyCharm splitter 悬停高亮）
                      .backgroundColor(this.paneDividerHover ? this.theme.funcName : this.theme.separator)
                  }
                  .width(this.paneSplit === 'v' ? '100%' : 12)
                  .height(this.paneSplit === 'v' ? 12 : '100%')
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .backgroundColor(Color.Transparent)
                  .onHover((isHover: boolean) => {
                    this.paneDividerHover = isHover;
                  })
                  .gesture(
                    PanGesture({ direction: PanDirection.All })
                      .onActionStart(() => {
                        this.dragStartRatio = this.paneRatio;
                      })
                      .onActionUpdate((event: GestureEvent) => {
                        // 编辑器区高度约 700vp、宽度约 1000vp（与 windowHeight 同量级）
                        const span: number = this.paneSplit === 'v' ? 700 : 1000;
                        const delta: number = this.paneSplit === 'v' ? event.offsetY : event.offsetX;
                        this.paneRatio = Math.max(0.1, Math.min(0.9, this.dragStartRatio + delta / span));
                      })
                      .onActionEnd(() => {
                        this.persistPanes();
                      })
                  )
                  Column() {
                    if (this.showBreadcrumb) {
                      this.BreadcrumbBar()
                    }
                    CodeEditor({
                      initialText: this.editorSeedText,
                      filePath: this.editorFilePath,
                      theme: this.theme,
                      fontSize: this.settings.fontSize,
                      tabSize: this.settings.tabSize,
                      hiddenLines: this.hiddenLines(),
                      foldableLines: this.foldableLines(),
                      showLineNumbers: this.settings.showLineNumbers,
                      highlightCurrentLine: false,
                      showIndentGuides: this.showIndentGuides,
                      breakpoints: this.pendingBreakpoints,
                  warnLines: this.warnLines,
                      debugLine: 0,
                      // 只读镜像（用户预期：右侧窗格只能看不能改）——共享编辑待有可靠验证手段后再开，见 docs/FEATURE_AUDIT.md 0.34
                      readOnly: true
                    })
                    .layoutWeight(1)
                  }
                  .layoutWeight(1 - this.paneRatio)
                }
              }
              .width('100%')
              .height('100%')
              // PyCharm New UI：编辑器也是圆角小岛（实测左上角圆角约 6vp，区域间留 4vp 间隙）
              .borderRadius(this.theme.islandArc)
        .clip(true)
              .backgroundColor(this.theme.editorBg)
              .margin({ left: this.theme.islandGap, top: this.theme.islandGap, right: this.theme.islandGap })
              // 点编辑器 => 焦点离开工具窗，竖条选中态由蓝变灰（PyCharm 实测行为）
              .onClick(() => {
                if (this.activePane !== 'editor') {
                  this.activePane = 'editor';
                }
              })
            }

            // 暂停期间也要显示：debugging 会在启动请求返回后立刻变 false，
            // 但此时会话仍在后台暂停着，变量/调用栈正需要展示（否则面板一闪就没）
            if (this.debugging || this.debugPaused) {
              this.DebugPanel()
            }

            if (false) {   // 底部工具窗已移到内容区下方（横跨整宽），见文件后面的同名块
            // 原位置停用：保留大括号以免破坏布局层级

              Column() {
                Column()
                  .width('100%')
                  .height(1)
                  .backgroundColor(this.bottomDividerHover ? this.theme.funcName : Color.Transparent)
              }
              .height(6)
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .backgroundColor(Color.Transparent)
              .onHover((isHover: boolean) => {
                this.bottomDividerHover = isHover;
              })
              .gesture(
                PanGesture({ direction: PanDirection.Vertical })
                  .onActionStart(() => {
                    this.dragStartPanelW = this.settings.bottomPanelHeight;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const height: number = this.dragStartPanelW - event.offsetY;
                    this.settings.bottomPanelHeight = Math.max(100, Math.min(600, height));
                  })
                  .onActionEnd(() => {
                    SettingsService.save(this.settings);
                  })
              )
              Column() {
                ConsolePanelView({
                  theme: this.theme,
                  entries: this.logEntries,
                  activeTab: this.consoleTab,
                  debugLines: this.debugPanelLines(),
                  debugStack: this.debugStack,
                  evalText: this.evalText,
                  debugEvals: this.debugEvals,
                  onEvalText: (value: string) => {
                    this.evalText = value;
                  },
                  evalDebug: () => this.evalDebug(),
                  debugLocals: this.debugLocals,
                  problemRows: this.problemRows,
                  runInspect: () => {
                    this.runInspection(true, this.inspectOnlyFile);
                  },
                  inspectOnlyFile: this.inspectOnlyFile,
                  setInspectOnlyFile: (v: boolean) => {
                    this.inspectOnlyFile = v;
                  },
                  gotoProblem: (row: string) => {
                    const m: RegExpMatchArray | null = row.match(/([^\s:]+):(\d+)\s/);
                    if (m !== null) {
                      const rel: string = m[1];
                      const line: number = Number.parseInt(m[2], 10);
                      const target: string = `${this.projectRoot}/${rel}`;
                      if (FileService.exists(target) && target !== this.editorFilePath) {
                        this.openFile(target, rel.substring(rel.lastIndexOf('/') + 1));
                      }
                      this.editorController.revealLine(line);
                      this.setStatus(`已跳到 ${rel}:${line}`);
                    }
                  },
                  watches: this.watches,
                  watchValues: this.watchValues,
                  removeWatch: (name: string) => {
                    const i: number = this.watches.indexOf(name);
                    if (i >= 0) {
                      const w2: string[] = this.watches.slice();
                      const v2: string[] = this.watchValues.slice();
                      w2.splice(i, 1);
                      if (i < v2.length) {
                        v2.splice(i, 1);
                      }
                      this.watches = w2;
                      this.watchValues = v2;
                    }
                  },
                  evalVar: (name: string) => {
                    // 点变量行 = 加入监视（并立即求值一次）
                    if (this.watches.indexOf(name) < 0) {
                      const w3: string[] = this.watches.slice();
                      w3.push(name);
                      const v3: string[] = this.watchValues.slice();
                      v3.push('…');
                      this.watches = w3;
                      this.watchValues = v3;
                    }
                    this.evalText = name;
                    this.evalDebug();
                  },
                  gotoFrame: (file: string, line: number) => {
                    // PyCharm：点调用栈帧跳到对应源码位置
                    this.openFile(file, FileService.baseName(file));
                    this.editorController.revealLine(line);
                    this.setStatus(`已跳转到 ${FileService.baseName(file)}:${line}`);
                  },
                  resumeDebug: () => this.resumeDebug(),
                  stepDebug: () => this.stepDebug(),
                  stepIntoDebug: () => this.stepIntoDebug(),
                  stepOutDebug: () => this.stepOutDebug(),
                  running: this.running,
                  replPrompt: '>>> ',
                  interpreterLabel: this.runtime.ready ? `Python ${this.runtime.version}` : 'Python 未就绪',
                  problemCount: this.problems,
                  runConfigName: '当前文件',
                  runAgain: () => this.runActiveFile(false),
                  selectTab: (tab: string) => {
                    this.consoleTab = tab;
                    // PyCharm：终端页签被激活时才启动 shell（惰性、真 PTY）
                    if (tab === 'terminal') {
                      const t: TerminalService = TerminalService.shared();
                      const ok: boolean = t.start((text: string) => {
                        this.appendEntry('stdout', text);
                      });
                      FileService.log(`terminal tab activated, native pty ready=${ok}`);
                      if (!ok) {
                        // PTY 不可用：打印诊断，并用 popen 兜底自检一次（真 shell）
                        FileService.log(`terminal diagnose ${t.diagnose()}`);
                        const probe: string = t.runOnce('echo native-shell-ok');
                        FileService.log(`terminal shell-fallback probe=${JSON.stringify(probe)}`);
                      }
                    }
                  },
                  clear: () => {
                    this.logEntries = [];
                    this.problems = 0;
                  },
                  // ConsoleView.PopupMenu: $Copy / CopyPaths —— 复制全部输出（真实写入剪贴板）
                  copyAll: () => {
                    let all: string = '';
                    for (const e of this.logEntries) {
                      all += e.text;
                    }
                    if (all.length === 0) {
                      this.showToast('控制台没有内容可复制');
                      return;
                    }
                    FileService.copyToClipboard(all);
                    this.setStatus(`已复制控制台输出（${all.length} 字符）`);
                  },
                  onContextMenu: (x: number, y: number) => {
                    this.consoleMenuX = Math.max(8, x - 20);
                    this.consoleMenuY = Math.max(8, Math.min(y, this.windowHeight - 320));
                    this.consoleMenuShown = true;
                  },
                  runCommand: (cmd: string) => {
                    if (this.consoleTab === 'repl') {
                      this.replSubmit(cmd);
                    } else {
                      this.terminalSubmit(cmd);
                    }
                  },
                  stop: () => this.stopRun(),
                  // 依据 PyCharm：Runner.RestoreLayout / ProblemsView.SortBy* / Terminal.Settings
                  restoreLayout: () => {
                    this.settings.bottomPanelHeight = 220;
                    SettingsService.save(this.settings);
                    this.setStatus('已恢复默认布局（底部工具窗高度 220）');
                  },
                  sortProblems: (by: string) => {
                    this.setStatus(by === 'severity' ? '问题排序：按严重性' : '问题排序：按名称');
                  },
                  openTerminalSettings: () => {
                    this.dialogTitle = '设置';
                    this.settingsCategory = 'tools.terminal';
                    this.dialog = 'settings';
                  },
                  // PyCharm 工具窗标题栏最右的 −
                  hidePanel: () => {
                    this.settings.showBottomToolWindow = false;
                    SettingsService.save(this.settings);
                    this.settings = this.settings;
                    this.setStatus('已隐藏底部工具窗（视图 → 工具窗口 可再次打开）');
                  }
                })
              }
              .height(this.bottomPanelHeight())
              .width('100%')
              // 底部工具窗自己也是圆角小岛（原来满宽满高、圆角被父层盖掉）
              .backgroundColor(this.theme.panelBg)
              .borderRadius(this.theme.islandArc)
              .clip(true)
              // 右缘要收在编辑器区域内：右侧面板打开时退到面板左侧 + 间隙
              // （实测原来右缘到 2605，压到了右侧面板/竖条下面 → 与编辑器岛不对齐）
              .margin({
                left: this.theme.islandGap,
                // 右缘要和编辑器岛一致：右边必须让出右竖条（+ 右侧面板）的位置，
                // 否则底部工具窗会伸到竖条下面（实测到 2605）
                right: this.rightStripW + this.theme.islandGap * 2
                  + (this.rightToolWindow.length > 0 ? this.rightPanelW : 0),
                bottom: 0
              })
            }
          }
          .layoutWeight(1)
          // 这里不能写 .height('100%')：它会覆盖父容器的 padding，
          // 导致编辑器岛底边比左列/Structure 多探出一份 islandGap（实测 1629 vs 1618）
          // 编辑器岛：整层（标签栏 + 面包屑 + 编辑器 + 底部工具窗）是同一个岛，
          // 圆角加在这一层，圆角就落在标签栏上沿（原来加在编辑内容层 → 圆角在编辑区上）
          .backgroundColor(this.theme.editorBg)
          .borderRadius(this.theme.islandArc)
          .clip(true)
          .margin({
            // 左侧不留边距：与左列之间的间隙同样由分隔条提供
            left: 0,
            top: this.theme.islandGap,
            // 右缘要在右竖条左侧留出间隙：否则岛顶到窗口右边缘（实测 2594），
            // 右边两个圆角外侧没有窗口底色 → 完全看不见圆角
            // 右侧面板打开时：与面板之间只留 islandGap（和 Project↔Structure 的间隙一致）
            // 面板关闭时：要给右竖条让出位置
            right: this.rightToolWindow.length > 0
              ? this.theme.islandGap
              : this.rightStripW + this.theme.islandGap * 2,
            // 底部间隙：与底部工具窗块之间留一份 islandGap（左列同值 → 两者底边对齐）
            bottom: this.theme.islandGap
          })

          // ── 右侧工具窗面板（PyCharm：右侧工具窗是内嵌面板小岛，可拖宽）──
          if (this.rightToolWindow.length > 0) {
            Column() {
              Column()
                .width(1)
                .height('100%')
                .backgroundColor(this.rightDividerHover ? this.theme.funcName : Color.Transparent)
            }
            .width(6)
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .onHover((isHover: boolean) => {
              this.rightDividerHover = isHover;
            })
            .gesture(
              PanGesture({ direction: PanDirection.Horizontal })
                .onActionStart(() => {
                  this.dragStartPanelW = this.rightPanelW;
                })
                .onActionUpdate((event: GestureEvent) => {
                  const w: number = this.dragStartPanelW - event.offsetX;
                  this.rightPanelW = Math.max(200, Math.min(560, w));
                })
            )

            Column() {
              // 标题栏（工具窗名 + ⋮ + −）
              Row() {
                Text(this.toolWindowLabel(this.rightToolWindow))
                  .fontSize(12)
                  .fontFamily(PyFont.ui)
                  .fontColor(this.theme.textPrimary)
                  .layoutWeight(1)
                Text('⋮')
                  .fontSize(14)
                  .fontColor(this.theme.textSecondary)
                  .width(22)
                  .height(22)
                  .textAlign(TextAlign.Center)
                  .onClick(() => {
                    this.twMenuShown = true;
                  })
                Text('−')
                  .fontSize(14)
                  .fontColor(this.theme.textSecondary)
                  .width(22)
                  .height(22)
                  .textAlign(TextAlign.Center)
                  .onClick(() => {
                    this.rightToolWindow = '';
                  })
              }
              .width('100%')
              .height(30)
              .padding({ left: 10, right: 6 })
              .alignItems(VerticalAlign.Center)

              // 内容（复用工具窗占位内容构建器）
              this.ToolWindowPanelContent()
            }
            .width(this.rightPanelW)
            .height('100%')
            .backgroundColor(this.theme.panelBg)
            // 右侧面板也是圆角小岛
            .borderRadius(this.theme.islandArc)
            .clip(true)
            .margin({
              top: this.theme.islandGap,
              right: this.theme.islandGap,
              bottom: this.theme.islandGap
            })
          }
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(VerticalAlign.Top)
        // 左竖条通高后不再属于本行，但它覆盖在窗口最左 → 行内左侧必须让出竖条宽度，
        // 否则整排岛（含左栏、编辑岛）会左移 50vp 压到竖条上。
        // 注意：这份 padding 在"行"上、不影响岛内标签位置 —— 标签贴左是 Scroll 居中问题，已在 EditorTabsBar 修掉。
        .padding({ left: this.showSideStrip ? this.leftStripW : 0 })
        // 这里不再留底部 padding：内容区底边 == 底部工具窗块顶边，左列 Structure 岛底边与之对齐
if (this.settings.showBottomToolWindow) {
            // 底部工具窗（PyCharm 的 Run/Terminal 岛）：四边都留 islandGap ——
            //   左：左竖条 + islandGap（左缘与 Project 岛左缘对齐）
            //   右：右竖条 + 2×islandGap（右缘与编辑器岛右缘对齐）
            //   下：状态栏上方留一份 islandGap
            //   上：内容区自身已留一份 islandGap → 岛顶边与编辑器岛底边恰好一份
            // 拖拽手柄改为叠加在岛上沿（不占布局高度），否则上边会多顶出一份间隙。
            Column() {
              Stack({ alignContent: Alignment.TopStart }) {
              Column() {
                ConsolePanelView({
                  theme: this.theme,
                  entries: this.logEntries,
                  activeTab: this.consoleTab,
                  debugLines: this.debugPanelLines(),
                  debugStack: this.debugStack,
                  evalText: this.evalText,
                  debugEvals: this.debugEvals,
                  onEvalText: (value: string) => {
                    this.evalText = value;
                  },
                  evalDebug: () => this.evalDebug(),
                  debugLocals: this.debugLocals,
                  problemRows: this.problemRows,
                  runInspect: () => {
                    this.runInspection(true, this.inspectOnlyFile);
                  },
                  inspectOnlyFile: this.inspectOnlyFile,
                  setInspectOnlyFile: (v: boolean) => {
                    this.inspectOnlyFile = v;
                  },
                  gotoProblem: (row: string) => {
                    const m: RegExpMatchArray | null = row.match(/([^\s:]+):(\d+)\s/);
                    if (m !== null) {
                      const rel: string = m[1];
                      const line: number = Number.parseInt(m[2], 10);
                      const target: string = `${this.projectRoot}/${rel}`;
                      if (FileService.exists(target) && target !== this.editorFilePath) {
                        this.openFile(target, rel.substring(rel.lastIndexOf('/') + 1));
                      }
                      this.editorController.revealLine(line);
                      this.setStatus(`已跳到 ${rel}:${line}`);
                    }
                  },
                  watches: this.watches,
                  watchValues: this.watchValues,
                  removeWatch: (name: string) => {
                    const i: number = this.watches.indexOf(name);
                    if (i >= 0) {
                      const w2: string[] = this.watches.slice();
                      const v2: string[] = this.watchValues.slice();
                      w2.splice(i, 1);
                      if (i < v2.length) {
                        v2.splice(i, 1);
                      }
                      this.watches = w2;
                      this.watchValues = v2;
                    }
                  },
                  evalVar: (name: string) => {
                    // 点变量行 = 加入监视（并立即求值一次）
                    if (this.watches.indexOf(name) < 0) {
                      const w3: string[] = this.watches.slice();
                      w3.push(name);
                      const v3: string[] = this.watchValues.slice();
                      v3.push('…');
                      this.watches = w3;
                      this.watchValues = v3;
                    }
                    this.evalText = name;
                    this.evalDebug();
                  },
                  gotoFrame: (file: string, line: number) => {
                    // PyCharm：点调用栈帧跳到对应源码位置
                    this.openFile(file, FileService.baseName(file));
                    this.editorController.revealLine(line);
                    this.setStatus(`已跳转到 ${FileService.baseName(file)}:${line}`);
                  },
                  resumeDebug: () => this.resumeDebug(),
                  stepDebug: () => this.stepDebug(),
                  stepIntoDebug: () => this.stepIntoDebug(),
                  stepOutDebug: () => this.stepOutDebug(),
                  running: this.running,
                  replPrompt: '>>> ',
                  interpreterLabel: this.runtime.ready ? `Python ${this.runtime.version}` : 'Python 未就绪',
                  problemCount: this.problems,
                  runConfigName: '当前文件',
                  runAgain: () => this.runActiveFile(false),
                  selectTab: (tab: string) => {
                    this.consoleTab = tab;
                    // PyCharm：终端页签被激活时才启动 shell（惰性、真 PTY）
                    if (tab === 'terminal') {
                      const t: TerminalService = TerminalService.shared();
                      const ok: boolean = t.start((text: string) => {
                        this.appendEntry('stdout', text);
                      });
                      FileService.log(`terminal tab activated, native pty ready=${ok}`);
                      if (!ok) {
                        // PTY 不可用：打印诊断，并用 popen 兜底自检一次（真 shell）
                        FileService.log(`terminal diagnose ${t.diagnose()}`);
                        const probe: string = t.runOnce('echo native-shell-ok');
                        FileService.log(`terminal shell-fallback probe=${JSON.stringify(probe)}`);
                      }
                    }
                  },
                  clear: () => {
                    this.logEntries = [];
                    this.problems = 0;
                  },
                  // ConsoleView.PopupMenu: $Copy / CopyPaths —— 复制全部输出（真实写入剪贴板）
                  copyAll: () => {
                    let all: string = '';
                    for (const e of this.logEntries) {
                      all += e.text;
                    }
                    if (all.length === 0) {
                      this.showToast('控制台没有内容可复制');
                      return;
                    }
                    FileService.copyToClipboard(all);
                    this.setStatus(`已复制控制台输出（${all.length} 字符）`);
                  },
                  onContextMenu: (x: number, y: number) => {
                    this.consoleMenuX = Math.max(8, x - 20);
                    this.consoleMenuY = Math.max(8, Math.min(y, this.windowHeight - 320));
                    this.consoleMenuShown = true;
                  },
                  runCommand: (cmd: string) => {
                    if (this.consoleTab === 'repl') {
                      this.replSubmit(cmd);
                    } else {
                      this.terminalSubmit(cmd);
                    }
                  },
                  stop: () => this.stopRun(),
                  // 依据 PyCharm：Runner.RestoreLayout / ProblemsView.SortBy* / Terminal.Settings
                  restoreLayout: () => {
                    this.settings.bottomPanelHeight = 220;
                    SettingsService.save(this.settings);
                    this.setStatus('已恢复默认布局（底部工具窗高度 220）');
                  },
                  sortProblems: (by: string) => {
                    this.setStatus(by === 'severity' ? '问题排序：按严重性' : '问题排序：按名称');
                  },
                  openTerminalSettings: () => {
                    this.dialogTitle = '设置';
                    this.settingsCategory = 'tools.terminal';
                    this.dialog = 'settings';
                  },
                  // PyCharm 工具窗标题栏最右的 −
                  hidePanel: () => {
                    this.settings.showBottomToolWindow = false;
                    SettingsService.save(this.settings);
                    this.settings = this.settings;
                    this.setStatus('已隐藏底部工具窗（视图 → 工具窗口 可再次打开）');
                  }
                })
              }
              .height(this.bottomPanelHeight())
              .width('100%')
              // 底部工具窗自己也是圆角小岛
              .backgroundColor(this.theme.panelBg)
              .borderRadius(this.theme.islandArc)
              .clip(true)

              // 拖拽手柄：叠加在岛上沿（不占布局高度），平时无线、hover 才亮
              Column() {
                Column()
                  .width('100%')
                  .height(1)
                  .backgroundColor(this.bottomDividerHover ? this.theme.funcName : Color.Transparent)
              }
              .height(this.theme.islandGap)
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .onHover((isHover: boolean) => {
                this.bottomDividerHover = isHover;
              })
              .gesture(
                PanGesture({ direction: PanDirection.Vertical })
                  .onActionStart(() => {
                    this.dragStartPanelW = this.settings.bottomPanelHeight;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const height: number = this.dragStartPanelW - event.offsetY;
                    this.settings.bottomPanelHeight = Math.max(100, Math.min(600, height));
                  })
                  .onActionEnd(() => {
                    SettingsService.save(this.settings);
                  })
              )
              }
              .width('100%')
              .height(this.bottomPanelHeight())
              }
              .width('100%')
              .padding({
                left: (this.showSideStrip ? this.leftStripW : 0) + this.theme.islandGap,
                right: this.rightStripW + this.theme.islandGap * 2
                  + (this.rightToolWindow.length > 0 ? this.rightPanelW : 0),
                bottom: this.theme.islandGap
              })
            }

        if (this.showStatusBar) {
          StatusBarView({
            theme: this.theme,
            interpreterLabel: this.runtime.ready
            ? `内嵌 [${this.runtime.version.split(' ')[0]}]`
            : 'Python 未就绪',
          cursorLine: this.cursorLine,
          cursorColumn: this.cursorColumn,
          tabSize: this.settings.tabSize,
          encoding: 'UTF-8',
          eol: 'LF',
          themeLabel: this.themeName === 'light' ? '浅色' : '深色',
          message: this.statusMessage,
          abi: this.runtime.abi,
          projectLabel: this.projectName.length > 0 ? this.projectName : '示例工程',
          fileLabel: (this.activeTab() !== undefined) ? (this.activeTab() as EditorTab).name : '',
          // 状态栏「类型:」= LanguageService 按扩展名识别出的语言名（原为硬编码 Built-in）
          fileType: (this.activeTab() !== undefined)
            ? languageLabel((this.activeTab() as EditorTab).name) : 'Text',
          vcsLabel: this.projectName.length > 0 ? this.projectName : '无版本控制',
          onStatusClick: (item: string) => {
            if (item === 'status.theme') {
              this.toggleTheme();
            } else if (item === 'status.gotoFile') {
              this.handleAction('view.recentFiles');
            } else if (item === 'status.interpreter' || item === 'status.abi') {
              // 解释器/ABI：打开运行时状态对话框（含错误全文与「重新初始化」）
              this.dialog = 'runtime';
            } else if (item === 'status.cursor') {
              this.openInputDialog('转到行', `${this.cursorLine}`, 'goto');
            } else if (item === 'status.indent') {
              this.dialog = 'settings';
            } else if (item === 'status.encoding') {
              this.showToast('UTF-8（本 IDE 统一以 UTF-8 读写文件）');
            } else if (item === 'status.eol') {
              this.showToast('LF（统一使用 Unix 换行）');
            } else {
              this.showToast(`状态项：${item}`);
            }
          }
        })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.windowBg)
      // chrome 的统一底色层：顶部带项目色，向下平滑过渡到 main-window-bg。
      // 顶部栏 / 顶栏下的间隙 / 左右竖条 / 状态栏 都透明，于是它们共用这一层 →
      // 视觉上是一个连续区域（不是几块各自上色）。
      .linearGradient({
        angle: 180,
        // 「显示项目渐变」(ColoredHeaderAction) 关闭时退化为纯窗口底色；
        // 颜色来自「更改项目颜色」子菜单（PyCharm 的 ProjectColorInfo）
        colors: [
          [this.projectTintOn ? this.projectTint : this.theme.windowBg, 0.0],
          [this.projectTintOn ? this.projectTintMid : this.theme.windowBg, 0.06],
          [this.theme.windowBg, 0.18]
        ]
      })
      .focusable(true)
      .defaultFocus(true)
      .onKeyEvent((event: KeyEvent) => {
        if (event.type !== KeyType.Down) {
          return;
        }
        if (event.keyCode === KeyCode.KEYCODE_F5) {
          this.runActiveFile(false);
        } else if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
          this.search.visible = false;
          this.search = this.search;
          // Esc 也用于关闭各类弹层（PyCharm 行为）
          this.menuOpenTitle = '';
          this.treeMenuPath = '';
          this.tabMenuShown = false;
        } else if (event.keyCode === KeyCode.KEYCODE_F2) {
          this.handleAction('nav.nextError');
        } else if (event.keyCode === KeyCode.KEYCODE_TAB) {
          this.handleAction('nav.nextTab');
        }
      })
      // Ctrl 组合键：ArkUI 的 KeyEvent 不暴露 ctrlKey 状态，统一走 keyboardShortcut
      .keyboardShortcut('1', [ModifierKey.CTRL], () => {
        this.goToTabN(1);
      })
      .keyboardShortcut('2', [ModifierKey.CTRL], () => {
        this.goToTabN(2);
      })
      .keyboardShortcut('3', [ModifierKey.CTRL], () => {
        this.goToTabN(3);
      })
      .keyboardShortcut('4', [ModifierKey.CTRL], () => {
        this.goToTabN(4);
      })
      .keyboardShortcut('5', [ModifierKey.CTRL], () => {
        this.goToTabN(5);
      })
      .keyboardShortcut('6', [ModifierKey.CTRL], () => {
        this.goToTabN(6);
      })
      .keyboardShortcut('7', [ModifierKey.CTRL], () => {
        this.goToTabN(7);
      })
      .keyboardShortcut('8', [ModifierKey.CTRL], () => {
        this.goToTabN(8);
      })
      .keyboardShortcut('9', [ModifierKey.CTRL], () => {
        this.goToTabN(9);
      })
      .keyboardShortcut('tab', [ModifierKey.CTRL], () => {
        // PyCharm：Ctrl+Tab = 切换器（SwitcherAndRecentFilesFallback）
        this.handleAction('nav.switcher');
      })
      .keyboardShortcut('s', [ModifierKey.CTRL], () => {
        this.saveActive();
      })
      .keyboardShortcut('f', [ModifierKey.CTRL], () => {
        this.handleAction('edit.find');
      })
      .keyboardShortcut('n', [ModifierKey.CTRL], () => {
        this.handleAction('file.new');
      })
      .keyboardShortcut('o', [ModifierKey.CTRL], () => {
        this.handleAction('file.open');
      })
      // ── 按 PyCharm 快捷键表补齐（真机/PC 上键盘可用）────────────────────
      .keyboardShortcut('z', [ModifierKey.CTRL], () => {
        this.handleAction('edit.undo');
      })
      .keyboardShortcut('z', [ModifierKey.CTRL, ModifierKey.SHIFT], () => {
        this.handleAction('edit.redo');
      })
      .keyboardShortcut('d', [ModifierKey.CTRL], () => {
        this.handleAction('edit.duplicate');
      })
      .keyboardShortcut('/', [ModifierKey.CTRL], () => {
        this.handleAction('edit.comment');
      })
      .keyboardShortcut('l', [ModifierKey.CTRL, ModifierKey.ALT], () => {
        this.handleAction('edit.format');
      })
      .keyboardShortcut('i', [ModifierKey.CTRL, ModifierKey.ALT], () => {
        this.handleAction('edit.optimizeImports');
      })
      .keyboardShortcut('w', [ModifierKey.CTRL], () => {
        this.handleAction('window.closeTab');
      })
      .keyboardShortcut('f', [ModifierKey.CTRL, ModifierKey.SHIFT], () => {
        this.handleAction('edit.findInFiles');
      })
      .keyboardShortcut('g', [ModifierKey.CTRL], () => {
        this.handleAction('nav.gotoLine');
      })
      .keyboardShortcut('e', [ModifierKey.CTRL], () => {
        this.handleAction('view.recentFiles');
      })
      .keyboardShortcut('a', [ModifierKey.CTRL, ModifierKey.SHIFT], () => {
        this.handleAction('help.findAction');
      })
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const width: number = Number(newValue.width);
        if (width !== this.windowWidth) {
          this.windowWidth = width;
        }
        const hgt: number = Number(newValue.height);
        if (hgt !== this.windowHeight) {
          this.windowHeight = hgt;
        }
        const size: string = this.layoutFromWidth(width);
        if (size !== this.layoutSize) {
          this.layoutSize = size;
        }
      })

      if (this.dialog.length > 0) {
        this.DialogLayer()
      }

      // 左侧竖条：PyCharm New UI 的第一条工具窗栏（Project / Learn / Structure / Commit / ⋯）
      // 绝对定位贴左边缘 → 通高（工具栏下方直到窗口底边），底色与窗口底色同为 #26282C，
      // 因此"竖条底部"和顶栏/间隙是同一个颜色，且它右侧不带任何分隔线。
      if (this.showSideStrip && this.windowWidth > 200) {
        Column() {
          this.SideToolButton('project', 'left')
          this.SideToolButton('learn', 'left')
          // PyCharm 竖条在上组之间有一条短分隔线（这是竖条内部的分组线，不是栏与栏之间的线）
          Divider()
            .vertical(false)
            .strokeWidth(1)
            .color(this.theme.separator)
            .width(this.leftStripW)
            .margin({ top: 6, bottom: 6 })
          this.SideToolButton('structure', 'left')
          // PyCharm 的 Commit 工具窗只在工程配置了版本控制时出现
          if (this.hasVcs) {
            this.SideToolButton('commit', 'left')
          }
          this.SideToolButton('more', 'left')

          Blank().layoutWeight(1)
        }
        // ui.lnf.xml 实测：左竖条 50vp（默认值；可拖拽改宽）
        .width(this.leftStripW)
        // 通高：主工具栏下方直到状态栏上沿（PyCharm 实机像素：竖条列到底仍是 #26282C，
        // 因为状态栏底色与它相同，看着就是一条通到底的统一底色）
        .height(this.windowHeight - RIGHT_STRIP_TOP - 24)
        .padding({ top: 8, bottom: 8 })
        .backgroundColor(Color.Transparent)
        .position({ x: 0, y: RIGHT_STRIP_TOP })
        // 竖条自身可拖拽调宽（PyCharm：拖竖条实时改宽）
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal })
            .onActionStart(() => {
              this.dragStartW = this.leftStripW;
              FileService.log(`strip drag start self=left w=${this.leftStripW}`);
            })
            .onActionUpdate((event: GestureEvent) => {
              const w: number = this.dragStartW + event.offsetX;
              this.leftStripW = w < 34 ? 34 : (w > 120 ? 120 : w);
            })
            .onActionEnd(() => {
              FileService.log(`strip drag end self=left w=${this.leftStripW}`);
            })
        )
      }

      // 右侧竖条：PyCharm New UI 的第二条工具窗栏（Python Packages/通知/AI 聊天/AtomCode/Junie/单词本）
      // 用绝对定位贴右边缘，避免改动主内容行的布局结构
      if (this.showSideStrip && this.windowWidth > 200) {
        Column() {
          // 右竖条：按 PyCharm 布局配置实测顺序 —— Notifications / AIAssistant / Database / Gradle / Maven / Plots / Python Packages
          this.SideToolButton('notifications', 'right')
          this.SideToolButton('aiChat', 'right')
          this.SideToolButton('database', 'right')
          this.SideToolButton('gradle', 'right')
          this.SideToolButton('maven', 'right')
          this.SideToolButton('plots', 'right')
          this.SideToolButton('packages', 'right')
          // PyCharm: <toolWindow id="Python Console" anchor="right"/> —— 归属右侧
          this.SideToolButton('pythonConsole', 'right')
        }
        .width(this.rightStripW)
        // 通高：主工具栏下方直到状态栏上沿（状态栏同为 #26282C，视觉上继续到底）
        .height(this.windowHeight - RIGHT_STRIP_TOP - 24)
        .padding({ top: 6, bottom: 6 })
        .backgroundColor(Color.Transparent)
        .position({ x: this.windowWidth - this.rightStripW, y: RIGHT_STRIP_TOP })
        // 可拖拽调宽（向左拖 = 变宽）
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal })
            .onActionStart(() => {
              this.dragStartW = this.rightStripW;
              FileService.log(`strip drag start self=right w=${this.rightStripW}`);
            })
            .onActionUpdate((event: GestureEvent) => {
              const w: number = this.dragStartW - event.offsetX;
              this.rightStripW = w < 34 ? 34 : (w > 120 ? 120 : w);
            })
            .onActionEnd(() => {
              FileService.log(`strip drag end self=right w=${this.rightStripW}`);
            })
        )

      // ── 竖条拖拽热区（6vp 宽，覆盖竖条内缘；PyCharm 拖竖条边缘即可实时改宽）──
      Column()
        .width(6)
        .height(this.windowHeight - RIGHT_STRIP_TOP - 24)
        // 近乎不可见但可命中（完全透明时 ArkUI 不参与命中测试，拖拽会失效）
        .backgroundColor('#05000000')
        // 用 Default（而非 Transparent）：Transparent 会让下层兄弟节点也参与命中，
        // 两个 PanGesture 互相竞争 → 谁都收不到 onActionStart
        .hitTestBehavior(HitTestMode.Default)
        .position({ x: this.leftStripW - 3, y: RIGHT_STRIP_TOP })
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal })
            .onActionStart(() => {
              this.dragStartW = this.leftStripW;
              FileService.log(`strip drag start hotzone=left w=${this.leftStripW}`);
            })
            .onActionUpdate((event: GestureEvent) => {
              const w: number = this.dragStartW + event.offsetX;
              this.leftStripW = w < 34 ? 34 : (w > 120 ? 120 : w);
            })
            .onActionEnd(() => {
              FileService.log(`strip drag end hotzone=left w=${this.leftStripW}`);
            })
        )
      Column()
        .width(6)
        .height(this.windowHeight - RIGHT_STRIP_TOP - 24)
        .backgroundColor('#05000000')
        .hitTestBehavior(HitTestMode.Default)
        .position({ x: this.windowWidth - this.rightStripW - 3, y: RIGHT_STRIP_TOP })
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal })
            .onActionStart(() => {
              this.dragStartW = this.rightStripW;
              FileService.log(`strip drag start hotzone=right w=${this.rightStripW}`);
            })
            .onActionUpdate((event: GestureEvent) => {
              const w: number = this.dragStartW - event.offsetX;
              this.rightStripW = w < 34 ? 34 : (w > 120 ? 120 : w);
            })
            .onActionEnd(() => {
              FileService.log(`strip drag end hotzone=right w=${this.rightStripW}`);
            })
        )
      }

      // 编辑器右上角动作（PyCharm 在标签行右端/编辑器右上：打开 + ⋮）
      // 放在页面级 Stack 里绝对定位：标签栏的横向 Scroll 会盖住同级图标，导致点不到
      if (this.windowWidth > 300 && this.tabs.length > 0) {
        Row() {
          // PyCharm 编辑器右上只有"标签页操作(⋮)"（→ EditorTabPopupMenu / TabList），没有"打开文件"文件夹入口
          IconMoreVertical({ iconSize: 16, color: this.theme.textSecondary })
            .onClick(() => {
              // PyCharm：编辑器右上 ⋮ = TabList（最近的文件/最近的位置/转到文件…）
              this.tabListShown = !this.tabListShown;
              FileService.log(`tab list click -> tabListShown=${this.tabListShown}`);
            })
        }
        .height(30)
        .padding({ left: 8, right: 8 })
        .position({ x: this.windowWidth - this.rightStripW - 78, y: 50 })
      }

      // 向右分屏：第二窗格（只读预览，页面级定位，不改动主编辑器布局）
      if (this.splitRight && this.tabs.length > 0 && this.windowWidth > 700 && this.windowHeight > 300) {
        Column() {
          Row() {
            Text(this.splitTab() !== undefined ? (this.splitTab() as EditorTab).name : '第二窗格')
              .fontSize(11)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textSecondary)
              .layoutWeight(1)
            Text('关闭分屏')
              .fontSize(11)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.funcName)
              .onClick(() => {
                this.splitRight = false;
                this.setStatus('已取消分屏');
              })
          }
          .width('100%')
          .height(28)
          .padding({ left: 10, right: 10 })
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.theme.panelBgAlt)

          // 真实可编辑的第二窗格（独立控制器 + 独立标签）
          CodeEditor({
            initialText: this.splitText(),
            filePath: this.splitPath(),
            theme: this.theme,
            fontSize: this.settings.fontSize,
            tabSize: this.settings.tabSize,
            showLineNumbers: this.settings.showLineNumbers,
            highlightCurrentLine: this.settings.highlightCurrentLine,
            showIndentGuides: this.showIndentGuides,
            breakpoints: [],
            debugLine: 0,
            controller: this.secondController,
            onEditorFocus: () => {
              if (this.activePane !== 'editor') {
                this.activePane = 'editor';
              }
            },
            onTextChange: (text: string) => {
              const tab: EditorTab | undefined = this.splitTab();
              if (tab !== undefined) {
                tab.updateText(text);
                if (tab.dirty) {
                  tab.preview = false;
                }
                this.tabs = this.tabs.slice();
                this.scheduleAutoSave();
              }
            },
            onCursorChange: (line: number, column: number) => {
            },
            onToggleBreakpoint: (line: number) => {
            },
            onClipboardAction: (action: string, length: number) => {
            }
          })
          .layoutWeight(1)
        }
        .width(this.windowWidth / 2 - this.rightStripW / 2)
        .height(this.windowHeight - 70)
        .backgroundColor(this.theme.editorBg)
        .border({ width: { left: 1 }, color: this.theme.border })
        .position({ x: this.windowWidth / 2, y: 46 })
      }

      // 编辑器右上 ⋮ 的 TabList 弹层
      if (this.tabListShown) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          // 只在**鼠标左键**点击时关闭：右键也会触发 onClick，会让菜单"刚打开就被关掉"（表现为右键点不开）
          .onMouse((event: MouseEvent) => {
            if (event.button === MouseButton.Left) {
              this.tabListShown = false;
            }
          })
        Column() {
          this.tabListMenu()
        }
        // 锚到 ⋮ 正下方：⋮ 在编辑器岛右上（岛右缘 ≈ 窗口宽 - 右侧竖条），弹层宽 250
        .position({ x: Math.max(8, this.windowWidth - this.rightStripW - 260), y: 62 })
        .clip(false)
        .zIndex(30)
      }

      // 标签栏 ⋮ 弹层（页面级：遮罩 + 菜单，机制同主菜单）
      if (this.tabMenuShown) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          // 只在**鼠标左键**点击时关闭：右键也会触发 onClick，会让菜单"刚打开就被关掉"（表现为右键点不开）
          .onMouse((event: MouseEvent) => {
            if (event.button === MouseButton.Left) {
              this.tabMenuShown = false;
            }
          })
        Column() {
          this.tabMenu()
        }
        .position({ x: Math.max(0, this.tabMenuX - 210), y: this.tabMenuY })
        .clip(false)
      }

      // 编辑器内右键菜单（EditorPopupMenu）
      if (this.editorMenuShown) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          // 只在**鼠标左键**点击时关闭：右键也会触发 onClick，会让菜单"刚打开就被关掉"（表现为右键点不开）
          .onMouse((event: MouseEvent) => {
            if (event.button === MouseButton.Left) {
              this.editorMenuShown = false;
            }
          })
        this.EditorContextMenu()
      }

      // 工具窗标题右键菜单（ToolWindowContextMenu）
      if (this.twMenuShown) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          // 只在**鼠标左键**点击时关闭：右键也会触发 onClick，会让菜单"刚打开就被关掉"（表现为右键点不开）
          .onMouse((event: MouseEvent) => {
            if (event.button === MouseButton.Left) {
              this.twMenuShown = false;
            }
          })
        this.ToolWindowContextMenuLayer()
      }

      // 最近文件弹层（Ctrl+E）
      if (this.recentShown) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.recentShown = false;
          })
        this.RecentFilesLayer()
      }

      // 顶栏右键/长按菜单（PyCharm MainToolbarPopupActions：工具栏(_T) + 自定义菜单与工具栏…）
      if (this.topMenuShown) {
        // 关键：菜单与子菜单必须放在**同一个已定尺寸容器**里。
        // 之前子菜单各自包在一个没有尺寸的 Column 中，而子菜单本身是 .position() 绝对定位，
        // 结果父容器塌成 0 尺寸 → 子菜单既画不出来也点不到（和 ⋮ 菜单"看得见点不动"同一类问题）。
        Stack({ alignContent: Alignment.TopStart }) {
          // 全屏遮罩：点击空白处关闭
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.topMenuShown = false;
              this.topSubmenu = '';
            })
          this.TopBarContextMenu()
          if (this.topSubmenu === 'quick') {
            this.TopQuickSubmenu()
          }
          if (this.topSubmenu === 'menu') {
            this.TopMenuModeSubmenu()
          }
          if (this.topSubmenu === 'color') {
            this.TopColorSubmenu()
          }
        }
        .width('100%')
        .height('100%')
        .zIndex(30)
      }

      // 工程树长按菜单（页面级：遮罩 + 菜单，机制同标签菜单）
      if (this.treeMenuPath.length > 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.treeMenuPath = '';
          })
        Column() {
          this.TreeContextMenu()
        }
        .clip(false)
      }

      // 控制台右键菜单（ConsoleView.PopupMenu）
      if (this.consoleMenuShown) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          // 只在**鼠标左键**点击时关闭：右键也会触发 onClick，会让菜单"刚打开就被关掉"（表现为右键点不开）
          .onMouse((event: MouseEvent) => {
            if (event.button === MouseButton.Left) {
              this.consoleMenuShown = false;
            }
          })
        Column() {
          this.ConsoleContextMenu()
        }
        .clip(false)
        .zIndex(30)
      }

      // 结构视图右键菜单（StructureViewPopupMenu）
      if (this.structMenuShown) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          // 只在**鼠标左键**点击时关闭：右键也会触发 onClick，会让菜单"刚打开就被关掉"（表现为右键点不开）
          .onMouse((event: MouseEvent) => {
            if (event.button === MouseButton.Left) {
              this.structMenuShown = false;
            }
          })
        Column() {
          this.StructureContextMenu()
        }
        .clip(false)
        .zIndex(30)
      }

      // 面包屑右键菜单（NavbarPopupMenu）
      if (this.navMenuShown) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          // 只在**鼠标左键**点击时关闭：右键也会触发 onClick，会让菜单"刚打开就被关掉"（表现为右键点不开）
          .onMouse((event: MouseEvent) => {
            if (event.button === MouseButton.Left) {
              this.navMenuShown = false;
            }
          })
        Column() {
          this.NavbarContextMenu()
        }
        .clip(false)
        .zIndex(30)
      }

      // 菜单弹层：挂在页面根 Stack 下（整页大小），否则超出菜单栏 30vp 后收不到点击
      if (this.menuOpenTitle.length > 0) {
        MenuPopupLayer({
          theme: this.theme,
          openTitle: this.menuOpenTitle,
          anchorX: this.menuPopupX,
          onAction: (action: string) => {
            this.menuOpenTitle = '';
            this.handleAction(action);
          },
          onClose: () => {
            this.menuOpenTitle = '';
          }
        })
      }

      if (this.toast.length > 0) {
        Column() {
          Text(this.toast)
            .fontSize(13)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        }
        .backgroundColor(this.theme.popupBg)
        .borderRadius(this.theme.popupArc)
        .clip(true)
        .border({ width: 1, color: this.theme.border })
        .shadow({ radius: 12, color: '#66000000', offsetY: 4 })
        .margin({ top: 64 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.windowBg)
  }

  private onSideToolClick(kind: string): void {
    this.sideKind = kind;
    if (kind === 'project') {
      this.settings.showLeftToolWindow = true;
      SettingsService.save(this.settings);
      return;
    }
    if (kind === 'learn') {
      this.handleAction('help.docs');
      return;
    }
    if (kind === 'structure') {
      this.openFileStructure();
      return;
    }
    if (kind === 'more') {
      this.handleAction('tools.settings');
      return;
    }
    if (kind === 'processOutput') {
      this.consoleTab = 'run';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    if (kind === 'pythonConsole') {
      this.consoleTab = 'repl';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    if (kind === 'terminal') {
      this.consoleTab = 'terminal';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    if (kind === 'problems') {
      this.consoleTab = 'problems';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    if (kind === 'packages') {
      this.handleAction('run.pip');
      return;
    }
    if (kind === 'services') {
      this.showInfo('服务', [
        '当前没有运行中的服务。',
        '本版本在鸿蒙沙箱内运行 Python，不启动外部守护进程。',
        '要执行后台任务，可在「终端」里运行，或在 Python 控制台里调用。'
      ]);
      return;
    }
    if (kind === 'vcs') {
      this.showInfo('版本控制', [
        `工程目录：${this.projectRoot}`,
        '沙箱内未捆绑 Git 可执行文件，因此没有提交/分支界面。',
        '可以用「终端」运行 Python 脚本来读写 .git 内容；',
        '或把工程目录放在设备可访问路径后用外部工具管理版本。'
      ]);
      return;
    }
    if (kind === 'database') {
      this.showInfo('数据库', [
        'PyCharm 的 Database 工具窗用于连接数据库、浏览表结构、执行 SQL。',
        '本 IDE 未捆绑 JDBC/数据库驱动，暂不可用。',
        '可以在「终端」里用 Python 的 sqlite3 模块操作本地数据库文件。'
      ]);
      return;
    }
    if (kind === 'gradle' || kind === 'maven') {
      this.showInfo(kind === 'gradle' ? 'Gradle' : 'Maven', [
        'PyCharm 的 Gradle/Maven 工具窗用于 JVM 项目的构建与依赖管理。',
        '本 IDE 面向 Python（CPython + pip），不使用这两个构建工具。',
        'Python 依赖请在「Python 软件包」面板里用 pip 安装。'
      ]);
      return;
    }
    if (kind === 'plots') {
      this.showInfo('图表', [
        'PyCharm 的 Plots 工具窗用于可视化科学计算图（matplotlib 等）。',
        '本 IDE 暂不支持内嵌图表渲染。'
      ]);
      return;
    }
    if (kind === 'notifications') {
      this.dialog = 'notifications';
      return;
    }
    if (kind === 'aiChat') {
      this.showInfo('AI 聊天', [
        '本版本未集成云端 AI 助手。',
        '编辑器内的代码补全、结构视图与调试都是本地能力，不依赖网络。',
        '后续版本可以在这里接入模型服务。'
      ]);
      return;
    }
    if (kind === 'atomcode') {
      this.showInfo('AtomCode', [
        'AtomCode 是 PyCharm 的插件面板。',
        '本 IDE 未实现插件系统，此面板仅作占位说明。'
      ]);
      return;
    }
    if (kind === 'junie') {
      this.showInfo('Junie', [
        'Junie 是 JetBrains 的 AI 编程代理，需要联网与账号。',
        '本版本不含该能力。'
      ]);
      return;
    }
    if (kind === 'wordbook') {
      this.showInfo('单词本', [
        '单词本用于收集代码里的标识符以便复习。',
        '当前文件里的标识符可从「视图 → 结构」查看。'
      ]);
      return;
    }
    this.dialog = this.dialog === 'settings' ? '' : 'settings';
  }

  private isSideSelected(kind: string): boolean {
    if (kind === 'project') {
      return this.settings.showLeftToolWindow && this.sideKind === 'project';
    }
    if (kind === 'terminal' || kind === 'processOutput' || kind === 'pythonConsole'
      || kind === 'problems') {
      return this.settings.showBottomToolWindow && this.consoleTab === this.consoleTabOf(kind);
    }
    return this.sideKind === kind;
  }

  /** 竖条项对应底部面板的标签 id */
  private consoleTabOf(kind: string): string {
    if (kind === 'pythonConsole') {
      return 'repl';
    }
    if (kind === 'terminal') {
      return 'terminal';
    }
    if (kind === 'problems') {
      return 'problems';
    }
    return 'run';
  }

  /** 竖条项的图标资源（PyCharm New UI 工具窗图标，优先用 20×20 高清变体） */
  private sideIcon(kind: string): string {
    if (kind === 'project') {
      return 'icons/twProject20.svg';
    }
    if (kind === 'learn') {
      return 'icons/twLearn20.svg';
    }
    if (kind === 'structure') {
      return 'icons/twStructure20.svg';
    }
    if (kind === 'more') {
      return 'icons/moreVertical.svg';
    }
    if (kind === 'processOutput') {
      return 'icons/console.svg';
    }
    if (kind === 'pythonConsole') {
      return 'icons/pyConsole.svg';
    }
    if (kind === 'services') {
      return 'icons/twServices20.svg';
    }
    if (kind === 'terminal') {
      return 'icons/twTerminal.svg';
    }
    if (kind === 'problems') {
      return 'icons/twProblems20.svg';
    }
    if (kind === 'vcs') {
      return 'icons/twVcs20.svg';
    }
    if (kind === 'packages') {
      // expui/toolwindows/dependencies@20x20.svg
      return 'icons/twDeps20.svg';
    }
    if (kind === 'notifications') {
      return 'icons/twNotifications20.svg';
    }
    if (kind === 'commit') {
      return 'icons/twCommit20.svg';
    }
    if (kind === 'database') {
      // expui: intellij.database.jar!icons/toolWindowDatabase.svg
      return 'icons/twDatabase20.svg';
    }
    if (kind === 'gradle' || kind === 'maven') {
      // 构建工具：expui/toolwindows/build@20x20.svg
      return 'icons/twBuild20.svg';
    }
    if (kind === 'plots') {
      return 'icons/twDataView20.svg';
    }
    if (kind === 'aiChat') {
      // expui/toolwindows/toolWindowAskAI@20x20.svg
      return 'icons/twAi20.svg';
    }
    if (kind === 'wordbook') {
      return 'icons/wordbook.svg';
    }
    return 'icons/twRun20.svg';
  }

  /** 左侧竖条的标签文字（PyCharm 是图标在上、文字在下） */
  private sideLabel(kind: string): string {
    if (kind === 'project') {
      return '项目';
    }
    if (kind === 'learn') {
      return '学习';
    }
    if (kind === 'structure') {
      return '结构';
    }
    if (kind === 'more') {
      return '⋯';
    }
    if (kind === 'processOutput') {
      return '进程输出';
    }
    if (kind === 'pythonConsole') {
      return '控制台';
    }
    if (kind === 'services') {
      return '服务';
    }
    if (kind === 'terminal') {
      return '终端';
    }
    if (kind === 'problems') {
      return '问题';
    }
    if (kind === 'vcs') {
      return '版本控制';
    }
    if (kind === 'packages') {
      return '软件包';
    }
    if (kind === 'notifications') {
      return '通知';
    }
    if (kind === 'commit') {
      return '提交';
    }
    if (kind === 'database') {
      return '数据库';
    }
    if (kind === 'gradle') {
      return 'Gradle';
    }
    if (kind === 'maven') {
      return 'Maven';
    }
    if (kind === 'plots') {
      // 语言包实测：Plots -> 绘图
      return '绘图';
    }
    if (kind === 'aiChat') {
      return 'AI\n聊天';
    }
    if (kind === 'atomcode') {
      return 'AtomCode';
    }
    if (kind === 'junie') {
      return 'Junie';
    }
    if (kind === 'wordbook') {
      return '单词本';
    }
    return '工具';
  }

  /** 竖条按钮：PyCharm 的图标在上、文字在下，选中为蓝色药丸 */
  @Builder
  SideToolButton(kind: string, side: string) {
    Column() {
      // 主题实测：竖条图标 20x20（expui 提供 @20x20 变体）
      IconAsset({
        iconSize: 20,
        file: this.sideIcon(kind)
      })
      Text(this.sideLabel(kind))
        // 小字号 = UI(12) − 1 = 11（主题 fontSizeOffset=-1）
        .fontSize(11)
        .fontFamily(PyFont.ui)
        .fontColor(this.isSideSelected(kind) ? '#FFFFFF' : this.theme.textSecondary)
        .textAlign(TextAlign.Center)
        // 项高 40 − 图标 20 − 间距 → 标签只有一行空间（主题 size 37,40 推得）
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Clip })
        // 主题实测：leftStripeTextOffset = 2、rightStripeTextOffset = -2（右侧贴更近）
        .margin({ top: side === 'left' ? 2 : 0 })
    }
    // 主题 StripeToolbar.Button.size = 37,40 → 项 37 宽 × 40 高
    // 内边距 left = 4,6,4,2；right = 4,2,4,6（主题 StripeToolbar.Button.*StripeIconWithName.padding）
    .width(44)
    .height(40)
    .padding({ top: 4, bottom: 4, left: side === 'left' ? 6 : 2, right: side === 'left' ? 2 : 6 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    // 选中 = 蓝药丸（工具窗有焦点）／灰药丸（焦点在别处）；hover = 灰（实测 PyCharm New UI）
    .backgroundColor(this.isSideSelected(kind)
      ? (this.activePane === 'tool' ? this.theme.toolSelectedBg : this.theme.toolHoverBg)
      : (this.sideHover === kind ? this.theme.toolHoverBg : Color.Transparent))
    .onHover((isHover: boolean) => {
      this.sideHover = isHover ? kind : '';
    })
    .onClick(() => {
      this.activePane = 'tool';
      this.onSideToolClick(kind);
    })
  }

  /** 通知中心内容（带时间戳 + 清空），对照 PyCharm 的 Notifications 工具窗 */
  @Builder
  NotificationsContent() {
    Column() {
      Row() {
        Text(`共 ${this.notifications.length} 条通知`)
          .fontSize(12)
          .fontFamily(PyFont.ui)
          .fontColor(this.theme.textSecondary)
          .layoutWeight(1)
        Text('清空')
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => {
            this.notifications = [];
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          if (this.notifications.length === 0) {
            Text('暂无通知。运行、保存、切换主题等事件会记录在这里。')
              .fontSize(12)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textDisabled)
              .padding({ top: 10 })
          } else {
            ForEach(this.notifications, (row: string) => {
              Text(row)
                .fontSize(12)
                .fontFamily(PyFont.ui)
                .fontColor(this.theme.textSecondary)
                .width('100%')
                .padding({ top: 5, bottom: 5 })
            }, (row: string, index: number) => `nt-${index}-${row}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .height(260)
      .width('100%')
      .margin({ top: 8 })
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 记一条通知（PyCharm 的 Notifications 工具窗） */
  private notify(text: string): void {
    const now: Date = new Date();
    const hh: string = now.getHours() < 10 ? `0${now.getHours()}` : `${now.getHours()}`;
    const mm: string = now.getMinutes() < 10 ? `0${now.getMinutes()}` : `${now.getMinutes()}`;
    const ss: string = now.getSeconds() < 10 ? `0${now.getSeconds()}` : `${now.getSeconds()}`;
    this.notifications.push(`[${hh}:${mm}:${ss}] ${text}`);
    if (this.notifications.length > 200) {
      this.notifications.shift();
    }
    this.notifications = this.notifications.slice();
  }

  /** 通用信息面板（没有专用界面的工具窗用它显示真实内容） */
  private showInfo(title: string, lines: string[]): void {
    this.infoTitle = title;
    this.infoLines = lines;
    this.dialog = 'info';
  }

  @Builder
  InfoDialogContent() {
    Column() {
      Text(this.infoTitle)
        .fontSize(14)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textPrimary)
        .width('100%')
        .margin({ bottom: 10 })
      ForEach(this.infoLines, (row: string) => {
        Text(row)
          .fontSize(12)
          .fontFamily(PyFont.ui)
          .fontColor(this.theme.textSecondary)
          .width('100%')
          .margin({ bottom: 6 })
      }, (row: string, index: number) => `info-${index}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  EditorTabsBar() {
    Row() {
      Scroll() {
        // ArkUI 的 Scroll 会把「比视口窄的子内容」居中 → 标签因此被推到编辑岛中部。
        // 给内层 Row 撑满宽度，标签就贴编辑岛左缘（PyCharm：首个标签与岛左缘齐平）。
        Row() {
          ForEach(this.tabs, (tab: EditorTab) => {
            Row() {
              IconAsset({ iconSize: 13, file: fileIconOf(tab.name) })
              Text(tab.name)
                .fontSize(12.5)
                .fontFamily(PyFont.ui)
                // PyCharm 的预览标签用斜体区分
                .fontStyle(tab.preview ? FontStyle.Italic : FontStyle.Normal)
                .fontColor(tab.id === this.activeTabId ? this.theme.tabActiveFg : this.theme.tabInactiveFg)
                .margin({ left: 6 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (tab.dirty) {
                Text('●')
                  .fontSize(9)
                  .fontColor(this.theme.accent)
                  .margin({ left: 6 })
              }
              IconClose({ iconSize: 11, color: this.theme.textSecondary })
                .margin({ left: 8 })
                .onClick(() => this.closeTab(tab.id))
            }
            .height(34)
            // PyCharm 的编辑器标签：图标 + 文件名 + 关闭按钮**靠左**，标签宽度随内容
            .justifyContent(FlexAlign.Start)
            // EditorTabs.unselectedAlpha = 0.75（主题实测）
            .opacity(tab.id === this.activeTabId ? 1 : 0.75)
            // EditorTabs.tabInsets = -6,8,-6,8（主题实测）
            .padding({ left: 8, right: 8 })
            .backgroundColor(tab.id === this.activeTabId ? this.theme.tabActiveBg : this.theme.tabInactiveBg)
            // PyCharm New UI 的标签上沿是圆角
            // 主题 ManyIslandsDark：Component.arc=8（标签上沿圆角）、EditorTabs.underlineArc=4（强调线圆角）
            .borderRadius({ topLeft: 8, topRight: 8, bottomLeft: 4, bottomRight: 4 })
            // 选中标签底部强调线：EditorTabs.underlineHeight = 4、underlineArc = 4
            .border({
              width: { bottom: tab.id === this.activeTabId ? 4 : 0 },
              color: this.theme.tabUnderline
            })
            .margin({ right: 1 })
            .onClick(() => this.activateTab(tab))
            // PyCharm：标签**右键**打开 EditorTabPopupMenu（此前 ⋮ 改成 TabList 后该菜单失去入口）
            .onMouse((event: MouseEvent) => {
              if (event.button === MouseButton.Right) {
                this.tabMenuX = Math.max(8, event.x);
                this.tabMenuY = Math.max(8, Math.min(event.y + 30, this.windowHeight - 560 - 8));
                this.tabMenuShown = true;
              }
            })
            .gesture(
              GestureGroup(GestureMode.Parallel,
                LongPressGesture({ repeat: false })
                  .onAction(() => {
                    this.tabMenuX = 320;
                    this.tabMenuY = Math.max(8, Math.min(300, this.windowHeight - 568));
                    this.tabMenuShown = true;
                  }),
                // PyCharm：把标签拖向编辑区边缘会弹出 SplitChooser（这里简化为"拖拽一定距离即弹出"）
                // 向下拖（把标签拖进编辑区）→ 弹 SplitChooser。
                // 注意：标签栏自身是横向 Scroll，横向拖会被它吃掉，必须用纵向手势
                PanGesture({ direction: PanDirection.Vertical, distance: 60 })
                  .onActionEnd((event: GestureEvent) => {
                    if (event.offsetY > 60) {
                      this.dialogTitle = '拆分编辑器';
                      this.dialog = 'splitChooser';
                    }
                  })
              )
            )
          }, (tab: EditorTab) => `${tab.id}_${tab.dirty}`)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
      .align(Alignment.TopStart)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      // 注意：PlatformActions.xml:1035 的 <group id="EditorTabsToolbarActions"/> 是**空组** ——
      // PyCharm 标签栏右端没有任何按钮，这里不再放"打开文件"文件夹图标。
    }
    .width('100%')
    .height(34)
    .backgroundColor(this.theme.tabInactiveBg)
    .border({ width: { bottom: 1 }, color: this.theme.border })
  }

  // ── 面包屑导航条（PyCharm 的 Editor Breadcrumbs）─────────────────────

  /** 当前文件拆成路径段：项目名 › 目录… › 文件名 */
  private breadcrumbSegments(): string[] {
    const tab: EditorTab | undefined = this.activeTab();
    if (tab === undefined) {
      return [];
    }
    const out: string[] = [this.projectName];
    let rest: string = tab.path;
    if (rest.startsWith(this.projectRoot)) {
      rest = rest.substring(this.projectRoot.length);
    }
    for (const part of rest.split('/')) {
      if (part.length > 0) {
        out.push(part);
      }
    }
    return out;
  }

  private onBreadcrumbClick(index: number): void {
    const segments: string[] = this.breadcrumbSegments();
    if (index >= segments.length - 1) {
      this.editorController.focus();
      return;
    }
    if (index === 0) {
      this.setStatus(`项目根：${this.projectRoot}`);
      return;
    }
    let path: string = this.projectRoot;
    for (let i = 1; i <= index; i++) {
      path += `/${segments[i]}`;
    }
    this.selectedPath = path;
    if (!this.settings.showLeftToolWindow) {
      this.settings.showLeftToolWindow = true;
    }
    this.setStatus(`已定位：${path}`);
  }

  @Builder
  BreadcrumbBar() {
    Row() {
      ForEach(this.breadcrumbSegments(), (segment: string, index: number) => {
        Row() {
          if (index > 0) {
            IconChevronRight({ iconSize: 12, color: this.theme.textDisabled })
          }
          Text(segment)
            .fontSize(12)
            .fontFamily(PyFont.ui)
            .fontColor(index === this.breadcrumbSegments().length - 1
              ? this.theme.textPrimary : this.theme.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 4, right: 4 })
        }
        .height(24)
        .borderRadius(4)
        .backgroundColor(this.breadcrumbHover === index ? this.theme.hoverBg : Color.Transparent)
        .onHover((isHover: boolean) => {
          this.breadcrumbHover = isHover ? index : -1;
        })
        .onClick(() => this.onBreadcrumbClick(index))
      }, (segment: string, index: number) => `${index}-${segment}`)
      Blank()
    }
    .width('100%')
    .height(26)
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.theme.editorBg)
    .border({ width: { bottom: 1 }, color: this.theme.editorBorder })
    // PyCharm：导航栏(Navbar)右键 → NavbarPopupMenu
    .onMouse((event: MouseEvent) => {
      if (event.button === MouseButton.Right) {
        this.navMenuX = Math.max(8, event.x - 40);
        const wantY: number = event.y + 26;
        this.navMenuY = Math.max(8, Math.min(wantY, this.windowHeight - 560 - 8));
        this.navMenuShown = true;
      }
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.navMenuX = 60;
          this.navMenuY = Math.max(8, Math.min(120, this.windowHeight - 560 - 8));
          this.navMenuShown = true;
        })
    )
  }

  @Builder
  DebugPanel() {
    Column() {
      Row() {
        Text('调试')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.debugAccent)
        Text(this.debugPaused
          ? `已暂停：${FileService.baseName(this.debugFile)}:${this.debugLine} · ${this.debugFunc}`
          : '运行中…（命中断点后会在此暂停）')
          .fontSize(12)
          .fontColor(this.theme.textSecondary)
          .margin({ left: 10 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('继续')
          .fontSize(12)
          .fontColor(this.debugPaused ? this.theme.textPrimary : this.theme.textDisabled)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => this.resumeDebug())
        Text('单步')
          .fontSize(12)
          .fontColor(this.debugPaused ? this.theme.textOnAccent : this.theme.textDisabled)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.debugPaused ? this.theme.buttonPrimaryBg : this.theme.buttonBg)
          .onClick(() => this.stepDebug())
        Text('步入')
          .fontSize(12)
          .fontColor(this.debugPaused ? this.theme.textPrimary : this.theme.textDisabled)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => this.stepIntoDebug())
        Text('步出')
          .fontSize(12)
          .fontColor(this.debugPaused ? this.theme.textPrimary : this.theme.textDisabled)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => this.stepOutDebug())
        Text('停止')
          .fontSize(12)
          .fontColor(this.theme.error)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => this.stopDebug())
      }
      .width('100%')
      .height(32)
      .padding({ left: 10, right: 8 })

      Divider().color(this.theme.border).strokeWidth(1)

      Scroll() {
        Column() {
          if (!this.debugPaused) {
            Text('程序正在运行；命中断点或点击「单步」后会在这里显示变量与调用栈。')
              .fontSize(12)
              .fontColor(this.theme.textSecondary)
              .padding(10)
          } else {
            Text(`局部变量（${this.debugLocals.length}）`)
              .fontSize(11)
              .fontColor(this.theme.textSecondary)
              .padding({ left: 10, top: 6, bottom: 4 })
            ForEach(this.debugLocals, (pair: string[]) => {
              Row() {
                Text(pair[0])
                  .fontSize(12)
                  .fontFamily(PyFont.mono)
                  .fontColor(this.theme.textPrimary)
                  .width(130)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(pair[1])
                  .fontSize(12)
                  .fontFamily(PyFont.mono)
                  .fontColor(this.theme.funcName)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 2, bottom: 2 })
            }, (pair: string[], index: number) => `v${index}_${pair[0]}_${pair[1]}`)

            Text(`调用栈（${this.debugStack.length}）`)
              .fontSize(11)
              .fontColor(this.theme.textSecondary)
              .padding({ left: 10, top: 8, bottom: 4 })
            ForEach(this.debugStack, (frame: string[]) => {
              Text(`${FileService.baseName(frame[0])}:${frame[1]}  ${frame[2]}`)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.textSecondary)
                .width('100%')
                .padding({ left: 10, right: 10, top: 2, bottom: 2 })
            }, (frame: string[], index: number) => `s${index}_${frame[0]}_${frame[1]}_${frame[2]}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height(190)
    .backgroundColor(this.theme.panelBgAlt)
    .border({ width: { top: 1 }, color: this.theme.border })
  }

  @Builder
  SearchBar() {
    Row() {
      TextInput({ text: this.search.query, placeholder: '查找' })
        .width(200)
        .height(28)
        .fontSize(12.5)
        .fontColor(this.theme.textPrimary)
        .placeholderColor(this.theme.textDisabled)
        .backgroundColor(this.theme.inputBg)
        .borderRadius(4)
        .border({ width: 1, color: this.theme.inputBorder })
        .onChange((value: string) => {
          this.search.query = value;
          this.search = this.search;
          this.runSearch();
        })

      TextInput({ text: this.search.replaceText, placeholder: '替换为' })
        .width(200)
        .height(28)
        .fontSize(12.5)
        .margin({ left: 8 })
        .fontColor(this.theme.textPrimary)
        .placeholderColor(this.theme.textDisabled)
        .backgroundColor(this.theme.inputBg)
        .borderRadius(4)
        .border({ width: 1, color: this.theme.inputBorder })
        .onChange((value: string) => {
          this.search.replaceText = value;
          this.search = this.search;
        })

      this.SmallButton('上一个', () => this.searchNext(false))
      this.SmallButton('下一个', () => this.searchNext(true))
      this.SmallButton('替换', () => this.replaceCurrent())
      this.SmallButton('全部替换', () => this.replaceAll())

      Text(`${this.search.matches.length} 处`)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .margin({ left: 10 })

      Blank()

      IconClose({ iconSize: 13, color: this.theme.textSecondary })
        .margin({ right: 10 })
        .onClick(() => {
          this.search.visible = false;
          this.search = this.search;
        })
    }
    .width('100%')
    .height(38)
    .padding({ left: 10, right: 4 })
    .backgroundColor(this.theme.panelBg)
    .border({ width: { bottom: 1 }, color: this.theme.border })
  }

  @Builder
  SmallButton(label: string, action: () => void) {
    Text(label)
      .fontSize(12)
      .fontColor(this.theme.textPrimary)
      .padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .margin({ left: 6 })
      .borderRadius(4)
      .backgroundColor(this.theme.buttonBg)
      .onClick(action)
  }

  @Builder
  DialogLayer() {
    Column() {
      Column() {
        Row() {
          Text(this.dialogTitle.length > 0 ? this.dialogTitle : this.dialogName())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.textPrimary)
          Blank()
          IconClose({ iconSize: 13, color: this.theme.textSecondary })
            .onClick(() => {
              this.dialog = '';
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 10 })

        Divider().color(this.theme.border).strokeWidth(1)

        Column() {
          if (this.dialog === 'about') {
            this.AboutContent()
          } else if (this.dialog === 'docs') {
            this.DocsContent()
          } else if (this.dialog === 'settings') {
            this.SettingsContent()
          } else if (this.dialog === 'customizeUI') {
            this.CustomizeUIContent()
          } else if (this.dialog === 'toolWindows') {
            this.ToolWindowsContent()
          } else if (this.dialog === 'newFileLang') {
            this.NewFileLangContent()
          } else if (this.dialog === 'todo') {
            this.TodoContent()
          } else if (this.dialog === 'twPanel') {
            this.ToolWindowPanelContent()
          } else if (this.dialog === 'projectList') {
            this.ProjectListContent()
          } else if (this.dialog === 'notifications') {
            this.NotificationsContent()
          } else if (this.dialog === 'info') {
            this.InfoDialogContent()
          } else if (this.dialog === 'openEditors') {
            this.OpenEditorsContent()
          } else if (this.dialog === 'runConfig') {
            this.RunConfigContent()
          } else if (this.dialog === 'shortcuts') {
            this.ShortcutsContent()
          } else if (this.dialog === 'licenses') {
            this.LicensesContent()
          } else if (this.dialog === 'goto') {
            this.GotoContent()
          } else if (this.dialog === 'fileStructure') {
            this.FileStructureContent()
          } else if (this.dialog === 'recentFiles') {
            this.RecentFilesContent()
          } else if (this.dialog === 'findInFiles') {
            this.FindInFilesContent()
          } else if (this.dialog === 'breakpoints') {
      this.BreakpointsContent()
    } else if (this.dialog === 'rename') {
      this.RenameContent()
    } else if (this.dialog === 'complete') {
      this.CompleteContent()
    } else if (this.dialog === 'inspect') {
      this.InspectContent()
    } else if (this.dialog === 'gotoclass') {
      this.GoToClassContent()
    } else if (this.dialog === 'usages') {
      this.UsagesContent()
    } else if (this.dialog === 'timeline') {
      this.TimelineContent()
    } else if (this.dialog === 'externals') {
      this.ExternalContent()
    } else if (this.dialog === 'scope') {
      this.ScopeContent()
    } else if (this.dialog === 'graph') {
      this.GraphContent()
    } else if (this.dialog === 'localHistory') {
      this.LocalHistoryContent()
    } else if (this.dialog === 'diffView') {
      this.DiffContent()
    } else if (this.dialog === 'splitChooser') {
      this.SplitChooserContent()
    } else if (this.dialog === 'gotoClass') {
      this.ClassesContent()
    } else if (this.dialog === 'gotoSymbol') {
      this.SymbolsContent()
    } else if (this.dialog === 'hierarchy') {
      this.HierarchyContent()
    } else if (this.dialog === 'switcher') {
      this.SwitcherContent()
    } else if (this.dialog === 'searchEverywhere') {
      this.SearchEverywhereContent()
    } else if (this.dialog === 'recentLocations') {
      this.RecentLocationsContent()
    } else if (this.dialog === 'bookmarks') {
      this.BookmarksContent()
    } else if (this.dialog === 'structure') {
            this.ProjectStructureContent()
          } else if (this.dialog === 'runtime') {
            this.RuntimeContent()
          } else if (this.dialog === 'delete') {
            Text(`确定删除 ${this.dialogTarget} 吗？此操作不可撤销。`)
              .fontSize(13)
              .fontColor(this.theme.textPrimary)
          } else {
            TextInput({ text: this.inputValue, placeholder: '请输入' })
              .width('100%')
              .height(32)
              .fontSize(13)
              .fontColor(this.theme.textPrimary)
              .placeholderColor(this.theme.textDisabled)
              .backgroundColor(this.theme.inputBg)
              .borderRadius(4)
              .border({ width: 1, color: this.theme.inputBorder })
              .onChange((value: string) => {
                this.inputValue = value;
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .alignItems(HorizontalAlign.Start)

        Row() {
          Blank()
          Text('取消')
            .fontSize(13)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonBg)
            .onClick(() => {
              this.dialog = '';
            })
          Text('确定')
            .fontSize(13)
            .fontColor(this.theme.textOnAccent)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .margin({ left: 10 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonPrimaryBg)
            .onClick(() => {
              if (this.dialog === 'delete') {
                this.confirmDelete();
              } else if (this.dialog === 'settings' || this.dialog === 'about'
                || this.dialog === 'docs' || this.dialog === 'projectList'
                || this.dialog === 'runtime' || this.dialog === 'structure'
                || this.dialog === 'findInFiles' || this.dialog === 'fileStructure'
                || this.dialog === 'recentFiles' || this.dialog === 'goto'
                || this.dialog === 'runConfig' || this.dialog === 'shortcuts'
                || this.dialog === 'licenses' || this.dialog === 'info'
                || this.dialog === 'notifications' || this.dialog === 'newFileLang') {
                this.dialog = '';
              } else {
                this.confirmInputDialog();
              }
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 14 })
      }
      .width(this.dialogWidth())
      .backgroundColor(this.theme.popupBg)
      .borderRadius(this.theme.popupArc)
        .clip(true)
      .border({ width: 1, color: this.theme.border })
      .shadow({ radius: 24, color: '#88000000', offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.dialog = '';
    })
  }

  private dialogName(): string {
    if (this.dialog === 'about') {
      return '关于';
    }
    if (this.dialog === 'docs') {
      return '使用文档';
    }
    if (this.dialog === 'settings') {
      return '设置';
    }
    if (this.dialog === 'projectList') {
      return '打开项目';
    }
    if (this.dialog === 'delete') {
      return '删除确认';
    }
    if (this.dialog === 'notifications') {
      return '通知';
    }
    if (this.dialog === 'info') {
      return this.infoTitle.length > 0 ? this.infoTitle : '信息';
    }
    if (this.dialog === 'runConfig') {
      return '编辑运行配置';
    }
    if (this.dialog === 'shortcuts') {
      return '键盘快捷方式';
    }
    if (this.dialog === 'licenses') {
      return '第三方组件与许可';
    }
    if (this.dialog === 'goto') {
      return this.gotoMode === 'file' ? '转到文件' : '转到符号';
    }
    if (this.dialog === 'fileStructure') {
      return '文件结构';
    }
    if (this.dialog === 'recentFiles') {
      return '最近文件';
    }
    if (this.dialog === 'findInFiles') {
      return '在文件中查找';
    }
    if (this.dialog === 'structure') {
      return '项目结构';
    }
    if (this.dialog === 'runtime') {
      return 'Python 运行时状态';
    }
    if (this.dialog === 'pip') {
      return '安装 Python 包';
    }
    return this.dialogTitle;
  }

  private dialogWidth(): number {
    // 设置对话框按 PyCharm 那样用大尺寸（左分类树 232 + 右侧内容）
    if (this.dialog === 'settings') {
      const max: number = this.windowWidth > 200 ? this.windowWidth - 80 : 900;
      return Math.min(max, 1000);
    }
    if (this.layoutSize === LayoutSize.COMPACT) {
      return 320;
    }
    return 460;
  }

/** 扫描工程里的 TODO/FIXME/XXX 注释（PyCharm 的 TODO 工具窗） */
  private scanTodo(): void {
    const out: string[] = [];
    try {
      this.collectTodo(this.projectRoot, out, 0);
    } catch (err) {
      FileService.log(`scanTodo 失败: ${JSON.stringify(err)}`);
    }
    this.todoItems = out.slice(0, 200);
    FileService.log(`scanTodo 命中 ${out.length} 条`);
    this.setStatus(`TODO：共 ${out.length} 条`);
  }

  private collectTodo(dir: string, out: string[], depth: number): void {
    if (depth > 6 || out.length > 200) {
      return;
    }
    const nodes: FileNode[] = FileService.listDir(dir, 1);
    for (let i = 0; i < nodes.length; i++) {
      const n: FileNode = nodes[i];
      if (n.name === '.git' || n.name === '__pycache__' || n.name === '.venv') {
        continue;
      }
      if (n.isDir) {
        this.collectTodo(n.path, out, depth + 1);
        continue;
      }
      if (!n.name.endsWith('.py') && !n.name.endsWith('.md') && !n.name.endsWith('.txt')) {
        continue;
      }
      try {
        const text: string = FileService.readText(n.path);
        const lines: string[] = text.split('\n');
        for (let k = 0; k < lines.length; k++) {
          const line: string = lines[k];
          const upper: string = line.toUpperCase();
          if (upper.indexOf('TODO') >= 0 || upper.indexOf('FIXME') >= 0 || upper.indexOf('XXX') >= 0) {
            out.push(`${n.name}:${k + 1}  ${line.trim()}`);
            if (out.length > 200) {
              return;
            }
          }
        }
      } catch (err) {
        continue;
      }
    }
  }

  /** 工具窗中文名（右侧面板标题用） */
  private toolWindowLabel(id: string): string {
    const all: ToolWindowInfo[] = toolWindows();
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === id) {
        return all[i].label;
      }
    }
    return id;
  }


  /** 自定义菜单与工具栏：PyCharm 的 CustomizeUI（自定义菜单与工具栏…）对应的可见性开关 */
  @Builder
  CustomizeUIContent() {
    Column() {
      Text('顶栏与工具窗的显示开关（对应 PyCharm 的「自定义菜单与工具栏…」）')
        .fontSize(11.5)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textSecondary)
        .margin({ bottom: 8 })
      this.CustomizeToggle('主工具栏', this.showMainToolbar, 'toolbar')
      this.CustomizeToggle('状态栏', this.showStatusBar, 'status')
      this.CustomizeToggle('左侧工具窗按钮条', this.showSideStrip, 'strip')
      this.CustomizeToggle('左侧工具窗', this.settings.showLeftToolWindow, 'left')
      this.CustomizeToggle('底部工具窗', this.settings.showBottomToolWindow, 'bottom')
      this.CustomizeToggle('右侧工具窗', this.rightToolWindow.length > 0, 'right')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 「自定义菜单与工具栏」里的一行开关 */
  @Builder
  CustomizeToggle(label: string, on: boolean, key: string) {
    Row() {
      Text(on ? '✓' : ' ')
        .fontSize(11)
        .width(16)
        .fontColor(this.theme.accent)
      Text(label)
        .fontSize(12.5)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .height(30)
    .padding({ left: 6, right: 6 })
    .borderRadius(4)
    .onClick(() => {
      this.toggleCustomize(key);
    })
  }

  /** 应用「自定义菜单与工具栏」里的一项 */
  private toggleCustomize(key: string): void {
    if (key === 'toolbar') {
      this.showMainToolbar = !this.showMainToolbar;
    } else if (key === 'status') {
      this.showStatusBar = !this.showStatusBar;
    } else if (key === 'strip') {
      this.showSideStrip = !this.showSideStrip;
    } else if (key === 'left') {
      this.settings.showLeftToolWindow = !this.settings.showLeftToolWindow;
      this.settings = this.settings;
    } else if (key === 'bottom') {
      this.settings.showBottomToolWindow = !this.settings.showBottomToolWindow;
      this.settings = this.settings;
    } else if (key === 'right') {
      this.rightToolWindow = this.rightToolWindow.length > 0 ? '' : 'ai';
    }
    FileService.log(`customizeUI toggle ${key}`);
  }

  /** 最近的位置 / 书签 共用的列表渲染 */
  @Builder
  LocationListContent(entries: string[], emptyText: string) {
    Column() {
      ForEach(entries, (entry: string) => {
        Row() {
          Text(entry.substring(0, entry.lastIndexOf('#')).substring(entry.substring(0, entry.lastIndexOf('#')).lastIndexOf('/') + 1))
            .fontSize(12.5)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`:${entry.substring(entry.lastIndexOf('#') + 1)}`)
            .fontSize(11)
            .fontColor(this.theme.textSecondary)
        }
        .width('100%')
        .height(26)
        .padding({ left: 8, right: 8 })
        .onClick(() => {
          this.dialog = '';
          this.openLocationEntry(entry);
        })
      }, (entry: string) => entry)
      if (entries.length === 0) {
        Text(emptyText)
          .fontSize(12)
          .fontColor(this.theme.textDisabled)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** TabList → 最近的位置（Recent Locations） */
  @Builder
  RecentLocationsContent() {
    this.LocationListContent(this.recentLocations, '暂无最近的位置（打开文件或转到行后会记录）')
  }

  /** TabList → 书签（Bookmarks） */
  @Builder
  BookmarksContent() {
    this.LocationListContent(this.bookmarks, '暂无书签（编辑器右键 → 切换书签，快捷键 F11）')
  }

  /** 打开的编辑器列表（MainToolbarCenter 的文件微件弹层，对应 FilenameToolbarWidgetAction 的 popup） */
  @Builder
  OpenEditorsContent() {
    Column() {
      ForEach(this.tabs, (tab: EditorTab) => {
        Row() {
          IconAsset({ iconSize: 14, file: fileIconOf(tab.name) })
          Text(tab.name)
            .fontSize(12.5)
            .fontFamily(PyFont.ui)
            .fontColor(tab.id === this.activeTabId ? this.theme.accent : this.theme.textPrimary)
            .margin({ left: 8 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (tab.dirty) {
            Text('●').fontSize(9).fontColor(this.theme.accent)
          }
        }
        .width('100%')
        .height(28)
        .padding({ left: 6, right: 6 })
        .onClick(() => {
          this.dialog = '';
          this.activateTab(tab);
        })
      }, (tab: EditorTab) => tab.id)
      if (this.tabs.length === 0) {
        Text('没有打开的编辑器').fontSize(12).fontColor(this.theme.textDisabled)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 工具窗列表（视图 → 工具窗口）：把 PyCharm 的工具窗全部列出来 */
  @Builder
  ToolWindowsContent() {
    Column() {
      Text('PyCharm 的全部工具窗（名称与锚点取自其注册文件；带 ● 的已实现真实内容）')
        .fontSize(11.5)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textSecondary)
        .margin({ bottom: 8 })
      Scroll() {
        Column() {
          ForEach(['left', 'right', 'bottom'], (anchor: string) => {
            Text(anchor === 'left' ? '左侧' : (anchor === 'right' ? '右侧' : '底部'))
              .fontSize(11)
              .fontColor(this.theme.textDisabled)
              .width('100%')
              .margin({ top: 6, bottom: 2 })
            ForEach(toolWindows().filter((w: ToolWindowInfo) => w.anchor === anchor), (w: ToolWindowInfo) => {
              Row() {
                Text(w.ready ? '●' : '○')
                  .fontSize(10)
                  .fontColor(w.ready ? this.theme.success : this.theme.textDisabled)
                Text(w.label)
                  .fontSize(12.5)
                  .fontFamily(PyFont.ui)
                  .fontColor(this.theme.textPrimary)
                  .margin({ left: 6 })
                Text(w.id)
                  .fontSize(11)
                  .fontFamily(PyFont.mono)
                  .fontColor(this.theme.textDisabled)
                  .margin({ left: 10 })
                  .layoutWeight(1)
                  .maxLines(1)
              }
              .width('100%')
              .height(26)
              .onClick(() => {
                this.openToolWindow(w);
              })
            }, (w: ToolWindowInfo) => w.id)
          }, (a: string) => a)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height(380)
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 新建文件（多语言）：语言列表取自 LanguageService.languages()
   * （顺序即 PyCharm「File ▸ New」里各语言文件类型的顺序）
   */
  @Builder
  NewFileLangContent() {
    Column() {
      Text('选择文件类型（扩展名决定语法高亮与模板）')
        .fontSize(11.5)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textSecondary)
        .margin({ bottom: 8 })
      Scroll() {
        Column() {
          ForEach(languages(), (lang: LangDef) => {
            Row() {
              Text(lang.name)
                .fontSize(12.5)
                .fontFamily(PyFont.ui)
                .fontColor(this.theme.textPrimary)
                .width(140)
              Text(lang.exts.length > 0 ? `.${lang.exts[0]}` : '（无扩展名）')
                .fontSize(11)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.textDisabled)
                .layoutWeight(1)
            }
            .width('100%')
            .height(26)
            .onClick(() => {
              this.chooseNewFileLang(lang);
            })
          }, (lang: LangDef) => lang.id)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height(380)
    .alignItems(HorizontalAlign.Start)
  }

  /** 打开工具窗：已实现的切到对应面板，未实现的给如实说明 */
  private openToolWindow(w: ToolWindowInfo): void {
    this.dialog = '';
    if (w.id === 'Project' || w.id === 'Learn') {
      this.sideKind = w.id === 'Project' ? 'project' : 'learn';
      this.settings.showLeftToolWindow = true;
      this.settings = this.settings;
      return;
    }
    if (w.id === 'Structure') {
      this.openFileStructure();
      return;
    }
    if (w.id === 'Commit' || w.id === 'Version Control') {
      this.handleAction('tools.vcs');
      return;
    }
    if (w.id === 'Notifications') {
      this.dialog = 'notifications';
      return;
    }
    if (w.id === 'Python Packages') {
      this.handleAction('tools.pip');
      return;
    }
    if (w.id === 'Python Console') {
      this.consoleTab = 'repl';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    if (w.id === 'Terminal') {
      this.consoleTab = 'terminal';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    if (w.id === 'Problems View') {
      this.consoleTab = 'problems';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    if (w.id === 'Services') {
      this.consoleTab = 'services';
      this.settings.showBottomToolWindow = true;
      this.settings = this.settings;
      return;
    }
    if (w.id === 'Run') {
      this.handleAction('run.showConsole');
      return;
    }
    if (w.id === 'TODO') {
      this.handleAction('tools.todo');
      return;
    }
    if (w.id === 'PythonProcessOutput') {
      this.handleAction('tools.processOutput');
      return;
    }
    // 右锚点工具窗 → 右侧内嵌面板（PyCharm 行为）；再点一次关闭
    if (w.anchor === 'right') {
      this.twPanelId = w.id;
      this.rightToolWindow = this.rightToolWindow === w.id ? '' : w.id;
      this.setStatus(`${w.label}：${this.rightToolWindow.length > 0 ? '已在右侧打开面板' : '已关闭'}`);
      return;
    }
    if (w.id === 'Bookmarks' || w.id === 'Coverage' || w.id === 'Endpoints'
      || w.id === 'SciView' || w.id === 'Jupyter Variables') {
      this.twPanelId = w.id;
      this.dialogTitle = w.label;
      this.dialog = 'twPanel';
      return;
    }
    if (w.id === 'Plots' || w.id === 'Database' || w.id === 'Gradle' || w.id === 'Maven') {
      this.showInfo(w.label, [
        `PyCharm 的「${w.label}」工具窗（id=${w.id}）用于${w.id === 'Plots' ? '展示科学计算图' :
          (w.id === 'Database' ? '连接数据库并执行 SQL' : 'JVM 项目的构建与依赖管理')}。`,
        '本 IDE 面向 Python（CPython + pip），该工具窗为界面占位，功能未实现。'
      ]);
      return;
    }
    this.showInfo(w.label, [
      `PyCharm 的工具窗「${w.label}」（id=${w.id}，锚点 ${w.anchor}）已在界面清单中列出。`,
      '本 IDE 暂未实现该工具窗的内容；分类与位置已与 PyCharm 对齐。'
    ]);
  }

  /** TODO 工具窗内容 */
  @Builder
  TodoContent() {
    Column() {
      Row() {
        Text(`共 ${this.todoItems.length} 条 TODO/FIXME`)
          .fontSize(12)
          .fontFamily(PyFont.ui)
          .fontColor(this.theme.textSecondary)
          .layoutWeight(1)
        Text('重新扫描')
          .fontSize(12)
          .fontColor(this.theme.link)
          .onClick(() => this.scanTodo())
      }
      .width('100%')
      .margin({ bottom: 6 })
      Scroll() {
        Column() {
          if (this.todoItems.length === 0) {
            Text('未发现 TODO/FIXME/XXX 注释')
              .fontSize(12)
              .fontColor(this.theme.textDisabled)
          } else {
            ForEach(this.todoItems, (line: string) => {
              Text(line)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.textPrimary)
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ bottom: 4 })
            }, (line: string) => line)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height(320)
    .alignItems(HorizontalAlign.Start)
  }

/** 编辑器内右键菜单（依据 PyCharm 的 EditorPopupMenu + FoldingGroup + Copy.Paste.Special） */
  @Builder
  EditorContextMenu() {
    Scroll() {
    Column() {
      this.tabMenuItem('ed.cut', '剪切(_T)', 'Ctrl+X')
      this.tabMenuItem('ed.copy', '复制(_C)', 'Ctrl+C')
      this.tabMenuItem('ed.paste', '粘贴(_P)', 'Ctrl+V')
      // EditorPopupMenu: <group id="Copy.Paste.Special" popup="true">
      //   EditorPasteSimple（简单粘贴） / PasteMultiple（从剪贴板粘贴多项）
      this.tabMenuItem('ed.pasteSimple', '　简单粘贴', 'Ctrl+Alt+Shift+V')
      this.tabMenuItem('ed.pasteMultiple', '　从剪贴板粘贴多项…', 'Ctrl+Shift+V')
      // EditorPopupMenu: EditorToggleColumnMode（切换列选择模式）
      this.tabMenuItem('ed.columnMode', '切换列选择模式', 'Alt+Shift+Insert')
      this.tabMenuItem('ed.copyPath', '复制路径(_O)', 'Ctrl+Shift+C')
      this.tabMenuItem('ed.copyRef', '复制引用(_Y)', 'Ctrl+Alt+Shift+C')
      this.tabMenuItem('ed.copyPlain', '复制为纯文本', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('ed.findInPath', '在文件中查找', '')
      this.tabMenuItem('ed.selectAll', '全选(_A)', 'Ctrl+A')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('ed.fold', '折叠代码块(_B)', 'Ctrl+-')
      this.tabMenuItem('ed.foldSelection', '折叠选区', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      // CodeMenu 项（PyCharm 的「代码(C)」菜单：HippieCompletion / EditorCompleteStatement）
      this.tabMenuItem('ed.hippieComplete', '循环补全', '')
      this.tabMenuItem('ed.completeStatement', '补全语句', '')
      this.tabMenuItem('ed.unfold', '展开(_X)', 'Ctrl+=')
      this.tabMenuItem('ed.foldDoc', '折叠文档注释(_O)', '')
      this.tabMenuItem('ed.unfoldAll', '全部展开(_E)', 'Ctrl+Shift+=')
      this.tabMenuItem('ed.foldAll', '全部收起(_A)', 'Ctrl+Shift+-')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('ed.intention', '显示上下文操作', 'Alt+Enter')
      this.tabMenuItem('ed.changeLang', '更改文件语言', '')
      this.tabMenuItem('ed.searchWeb', '使用 Google 搜索(_S)', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      // EditorPopupMenu: CompareClipboardWithSelection
      this.tabMenuItem('ed.compareClipboard', '将剪贴板与所选内容比较', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      // PyCharm 的 ToggleBookmark(F11) / ShowBookmarks(Shift+F11)
      this.tabMenuItem('ed.toggleBookmark', '切换书签', 'F11')
      this.tabMenuItem('ed.showBookmarks', '显示书签', 'Shift+F11')
    }
    .width('100%')
    }
    .width(240)
    .constraintSize({ maxHeight: 560 })
    .scrollBar(BarState.Auto)
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(this.theme.popupArc)
    .clip(true)
    .position({ x: this.editorMenuX, y: this.editorMenuY })
  }

  /** 工具窗标题右键菜单（依据 PyCharm 的 ToolWindowContextMenu） */
  @Builder
  ToolWindowContextMenuLayer() {
    Column() {
      this.tabMenuItem('tw.hide', '隐藏工具窗口', '')
      this.tabMenuItem('tw.moveEditor', '移至编辑器', '')
      this.tabMenuItem('tw.keepTab', '保留此文档', '')
      this.tabMenuItem('tw.rename', '重命名会话…', '')
      this.tabMenuItem('tw.maximize', '最大化工具窗口', '')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.tabMenuItem('tw.toolWindows', '工具窗口列表…', '')
    }
    .width(220)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(this.theme.popupArc)
        .clip(true)
    .position({ x: 96, y: 60 })
  }

  /** 编辑器右键菜单派发 */
  private onEditorMenuPick(id: string): void {
    this.editorMenuShown = false;
    // EditorPopupMenu 的三项（Copy.Paste.Special / EditorToggleColumnMode / CompareClipboardWithSelection）
    if (id === 'ed.pasteSimple') {
      this.editorController.pasteClipboard();
      return;
    }
    if (id === 'ed.pasteMultiple') {
      this.showToast('「从剪贴板粘贴多项」需要剪贴板历史，本 IDE 暂未实现');
      return;
    }
    if (id === 'ed.columnMode') {
      this.showToast('「切换列选择模式」本 IDE 暂未实现（编辑器为单列选择）');
      return;
    }
    if (id === 'ed.toggleBookmark') {
      this.toggleBookmark();
      return;
    }
    if (id === 'ed.showBookmarks') {
      this.dialogTitle = '书签';
      this.dialog = 'bookmarks';
      return;
    }
    if (id === 'ed.compareClipboard') {
      this.showToast('「将剪贴板与所选内容比较」需要差异视图，本 IDE 暂未实现');
      return;
    }
    if (id === 'ed.cut') {
      this.editorController.cutSelection();
      return;
    }
    if (id === 'ed.copy') {
      this.editorController.copySelection();
      return;
    }
    if (id === 'ed.paste') {
      this.editorController.pasteClipboard();
      return;
    }
    if (id === 'ed.copyPath') {
      const tab: EditorTab | undefined = this.activeTab();
      if (tab !== undefined) {
        FileService.copyToClipboard(tab.path);
        this.setStatus(`已复制路径：${tab.path}`);
      }
      return;
    }
    if (id === 'ed.copyRef') {
      this.handleAction('edit.copyReference');
      return;
    }
    if (id === 'ed.copyPlain') {
      this.handleAction('edit.copyPlain');
      return;
    }
    if (id === 'ed.findInPath') {
      this.handleAction('edit.findInFiles');
      return;
    }
    if (id === 'ed.selectAll') {
      this.setStatus('全选：Ctrl+A（在编辑器内选中全部文本）');
      return;
    }
    // ── 代码折叠（PyCharm FoldingGroup）：真实实现，只影响渲染，模型不动 ──
    if (id === 'ed.fold' || id === 'ed.foldDoc') {
      const s: number = this.foldStartAtCursor();
      if (s === 0) {
        this.showToast('光标所在行没有可折叠的块');
        return;
      }
      const key: string = `${this.activePathKey()}#${s}`;
      if (this.foldedStarts.indexOf(key) < 0) {
        const next: string[] = this.foldedStarts.slice();
        next.push(key);
        this.foldedStarts = next;
        this.persistFolds();
      }
      this.editorController.revealLine(s);
      this.setStatus(`已折叠第 ${s} 行起的代码块`);
      return;
    }
    if (id === 'ed.foldSelection') {
      this.collapseSelection();
      return;
    }
    if (id === 'ed.hippieComplete') {
      this.hippieComplete();
      return;
    }
    if (id === 'ed.completeStatement') {
      this.completeStatement();
      return;
    }
    if (id === 'ed.unfold') {
      const s: number = this.foldStartAtCursor();
      if (s === 0 || !this.isFoldedLine(s)) {
        this.showToast('光标所在块没有折叠');
        return;
      }
      const key: string = `${this.activePathKey()}#${s}`;
      this.foldedStarts = this.foldedStarts.filter((x: string) => x !== key);
      this.persistFolds();
      this.setStatus(`已展开第 ${s} 行起的代码块`);
      return;
    }
    if (id === 'ed.foldAll') {
      const path: string = this.activePathKey();
      const keep: string[] = this.foldedStarts.filter((x: string) => !x.startsWith(`${path}#`));
      const added: string[] = [];
      for (const s of this.foldableLines()) {
        added.push(`${path}#${s}`);
      }
      this.foldedStarts = keep.concat(added);
      this.persistFolds();
      this.setStatus(`已全部收起（${added.length} 个块）`);
      return;
    }
    if (id === 'ed.unfoldAll') {
      const path: string = this.activePathKey();
      this.foldedStarts = this.foldedStarts.filter((x: string) => !x.startsWith(`${path}#`));
      this.persistFolds();
      this.setStatus('已全部展开');
      return;
    }
    if (id === 'ed.foldDoc') {
      this.showInfo('代码折叠', [
        'PyCharm 的折叠组：展开(_X)/递归展开(_R)/全部展开(_E)/收起(_C)/递归收起(_A)/全部收起(_A)、',
        '展开·收起文档注释(_D/_O)、展开到级别 1–5、折叠选区、折叠代码块(_B)。',
        '本 IDE 的编辑器为自绘高亮层，尚未实现折叠（列为下一项功能）。'
      ]);
      return;
    }
    if (id === 'ed.intention') {
      this.showInfo('显示上下文操作', [
        'PyCharm 的 Alt+Enter 意图操作依赖语义分析（导入缺失模块、转换写法等）。',
        '本 IDE 已提供：补全、格式化、优化 import、注释切换。'
      ]);
      return;
    }
    if (id === 'ed.changeLang') {
      this.setStatus('更改文件语言：本 IDE 按扩展名判定（.py → Python，其余纯文本）');
      return;
    }
    if (id === 'ed.searchWeb') {
      this.showInfo('使用 Google 搜索', [
        'PyCharm 会把选中文本送到默认浏览器搜索。',
        'HarmonyOS 沙箱内没有浏览器跳转能力，暂不支持。'
      ]);
      return;
    }
  }

  /** 工具窗标题右键菜单派发 */
  private onToolWindowMenuPick(id: string): void {
    this.twMenuShown = false;
    if (id === 'tw.hide') {
      this.handleAction('window.hideSide');
      return;
    }
    if (id === 'tw.toolWindows') {
      this.dialogTitle = '工具窗口';
      this.dialog = 'toolWindows';
      return;
    }
    if (id === 'tw.maximize') {
      this.setStatus(`工具窗最大化：PyCharm 的 MaximizeToolWindow（本版本未实现）`);
      return;
    }
    if (id === 'tw.moveEditor') {
      this.showInfo('移至编辑器', [
        'PyCharm 可把工具窗内容移入编辑器区域的标签页（Terminal.MoveToEditor）。',
        '本 IDE 的底部工具窗固定在底部；可参考「运行」输出或在编辑器标签间切换。'
      ]);
      return;
    }
    if (id === 'tw.keepTab') {
      this.setStatus('保留此文档（Documentation.KeepTab）：本版本无文档标签页');
      return;
    }
    if (id === 'tw.rename') {
      this.setStatus('重命名会话：本版本终端/控制台为单会话');
      return;
    }
  }

/** 占位工具窗界面：标题 + 工具条（PyCharm 的按钮名）+ 空态 + 说明 */
  @Builder
  ToolWindowPanelContent() {
    Column() {
      ForEach(toolWindowPanels().filter((p: ToolWindowPanel) => p.id === this.twPanelId), (p: ToolWindowPanel) => {
        // 工具条：按 PyCharm 该工具窗的 action group 逐条显示
        Row() {
          ForEach(p.actions, (a: string) => {
            Text(a)
              .fontSize(11.5)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textPrimary)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .margin({ right: 6 })
              .borderRadius(4)
              .backgroundColor(this.theme.buttonBg)
              .onClick(() => {
                this.showInfo(p.title, [
                  `PyCharm 的「${p.title}」工具窗按钮：${p.actions.join(' / ')}`,
                  p.note,
                  '本 IDE 已把界面与按钮位置对齐，功能待实现。'
                ]);
              })
          }, (a: string) => p.id + a)
        }
        .width('100%')
        .margin({ bottom: 10 })

        Divider().strokeWidth(1).color(this.theme.separator).margin({ bottom: 12 })

        // 空态
        Text(p.empty)
          .fontSize(12.5)
          .fontFamily(PyFont.ui)
          .fontColor(this.theme.textDisabled)
          .margin({ bottom: 10 })

        Text(p.note)
          .fontSize(12)
          .fontFamily(PyFont.ui)
          .fontColor(this.theme.textSecondary)
      }, (p: ToolWindowPanel) => p.id)
    }
    .width('100%')
    .height(300)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  AboutContent() {
    Column() {
      Text('鸿蒙 Python IDE').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.theme.textPrimary)
      Text('面向鸿蒙平板与鸿蒙 PC（2in1）的 Python 集成开发环境').fontSize(12.5)
        .fontColor(this.theme.textSecondary).margin({ top: 6 })
      Text(`原生运行时：${this.runtime.ready ? `CPython ${this.runtime.version} (${this.runtime.abi})` : '未就绪'}`)
        .fontSize(12.5).fontColor(this.theme.textPrimary).margin({ top: 10 })
      Text('运行方式：ArkTS/ArkUI 界面 + NAPI 内嵌 CPython 静态库').fontSize(12.5)
        .fontColor(this.theme.textSecondary).margin({ top: 4 })
      Text('界面布局与配色对齐 PyCharm New UI（Darcula / Light 双主题）。').fontSize(12.5)
        .fontColor(this.theme.textSecondary).margin({ top: 4 })
      // 运行时设备形态（真机联调时用来确认跑在平板还是 PC）
      Text(`运行设备：${this.deviceLabel()}${this.windowMode.length > 0 ? `　窗口：${this.windowMode}` : ''}`)
        .fontSize(12.5).fontColor(this.theme.textPrimary).margin({ top: 10 })
      Text(this.deviceKind === '2in1'
        ? '当前为鸿蒙 PC（2in1）形态：支持自由窗口、鼠标与键盘快捷键。'
        : '当前为平板形态：支持全屏/分屏/悬浮窗口，触摸长按等同右键。')
        .fontSize(12.5).fontColor(this.theme.textSecondary).margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  /** 设备形态中文名（「关于」里显示） */
  private deviceLabel(): string {
    if (this.deviceKind === '2in1') {
      return '鸿蒙 PC（2in1）';
    }
    if (this.deviceKind === 'tablet') {
      return '鸿蒙平板（tablet）';
    }
    if (this.deviceKind === 'phone') {
      return '手机（phone）';
    }
    return this.deviceKind.length > 0 ? this.deviceKind : '未知';
  }

  @Builder
  RuntimeContent() {
    Column() {
      Text(this.runtime.ready
        ? `CPython ${this.runtime.version}（${this.runtime.abi}）已就绪`
        : 'Python 运行时未就绪')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.runtime.ready ? this.theme.success : this.theme.error)
      Scroll() {
        Text(this.runtime.message)
          .fontSize(12)
          .fontFamily(PyFont.mono)
          .fontColor(this.theme.textPrimary)
          .width('100%')
          .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
      }
      .height(170)
      .width('100%')
      .margin({ top: 8 })
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
      Text('「重新初始化」会重新从应用资源里释放标准库与 pip wheel，并重启解释器，不需要重装应用。')
        .fontSize(11)
        .fontColor(this.theme.textSecondary)
        .margin({ top: 8 })
      Text('重置界面布局')
        .fontSize(13)
        .fontColor(this.theme.textPrimary)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .margin({ top: 10, left: 10 })
        .borderRadius(4)
        .backgroundColor(this.theme.buttonBg)
        .onClick(() => this.handleAction('tools.resetLayout'))
      Text('重新初始化运行时')
        .fontSize(13)
        .fontColor(this.theme.textOnAccent)
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .margin({ top: 10 })
        .borderRadius(4)
        .backgroundColor(this.theme.buttonPrimaryBg)
        .onClick(() => this.reinitRuntime())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 断点列表内容 */
  @Builder
  BreakpointsContent() {
    Column() {
      if (this.bpRows.length === 0) {
        Text('暂无断点（在编辑器行号左侧点一下即可添加）')
          .fontSize(12)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.bpRows, (row: string, index: number) => {
              Row() {
                Text(row)
                  .fontSize(12)
                  .fontFamily(PyFont.mono)
                  .fontColor(this.theme.textPrimary)
                  .layoutWeight(1)
                  .maxLines(1)
                Text('删除')
                  .fontSize(12)
                  .fontColor(this.theme.funcName)
                  .padding({ left: 10, right: 6 })
                  .onClick(() => {
                    this.removeBreakpoint(this.bpKeys[index], this.bpLines[index]);
                  })
              }
              .width('100%')
              .height(26)
              .padding({ left: 8, right: 8 })
            }, (row: string, index: number) => `bp_${index}_${row}`)
            Row() {
              Text('全部清除')
                .fontSize(12)
                .fontColor(this.theme.funcName)
                .layoutWeight(1)
                .onClick(() => {
                  this.clearAllBreakpoints();
                })
            }
            .width('100%')
            .height(26)
            .padding({ left: 8, right: 8 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 380 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 重命名内容：选符号 → 选命名样式 → 报告 */
  @Builder
  RenameContent() {
    Column() {
      if (this.renameRows.length > 0) {
        Row() {
          Text('修改报告')
            .fontSize(11.5)
            .fontColor(this.theme.textDisabled)
            .layoutWeight(1)
            .padding({ left: 8, top: 2, bottom: 4 })
          Text('撤销这次重命名')
            .fontSize(11.5)
            .fontColor(this.theme.textOnAccent)
            .margin({ right: 8, top: 2, bottom: 4 })
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonPrimaryBg)
            .onClick(() => {
              this.renameRows = [];
              this.undoRename();
            })
        }
        .width('100%')
        Scroll() {
          Column() {
            ForEach(this.renameRows, (row: string, index: number) => {
              Text(row)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.textPrimary)
                .width('100%')
                .height(24)
                .padding({ left: 8, right: 8 })
            }, (row: string, index: number) => `rn_${index}_${row}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 300 })
        .scrollBar(BarState.Auto)
      } else if (this.renameTarget.length > 0) {
        Text(`已选符号：${this.renameTarget} —— 选择命名样式`)
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 8, top: 2, bottom: 6 })
        Row() {
          Text('加前缀 my_')
            .fontSize(12)
            .fontColor(this.theme.textOnAccent)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .margin({ right: 6 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonPrimaryBg)
            .onClick(() => {
              this.applyRename('prefix');
            })
          Text('加后缀 _v2')
            .fontSize(12)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .margin({ right: 6 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonBg)
            .onClick(() => {
              this.applyRename('suffix');
            })
              Text('去掉 my_ 前缀')
            .fontSize(12)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .margin({ right: 6 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonBg)
            .onClick(() => {
              this.applyRename('strip');
            })
          Text('转蛇形')
            .fontSize(12)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .margin({ right: 6 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonBg)
            .onClick(() => {
              this.applyRename('snake');
            })
          Text('转驼峰')
            .fontSize(12)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .margin({ right: 6 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonBg)
            .onClick(() => {
              this.applyRename('camel');
            })
          Text('转大写')
            .fontSize(12)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonBg)
            .onClick(() => {
              this.applyRename('upper');
            })
        }
        .width('100%')
        .padding({ left: 8 })
      } else {
        Text('点一个符号 → 选择命名样式执行跨文件重命名')
          .fontSize(11.5)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8, top: 2, bottom: 4 })
        Scroll() {
          Column() {
            ForEach(this.projectSymbols, (row: string, index: number) => {
              Text(row)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.textPrimary)
                .width('100%')
                .height(26)
                .padding({ left: 8, right: 8 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => {
                  const m: RegExpMatchArray | null = row.match(/^(?:类|函数)\s+(\S+)/);
                  if (m !== null) {
                    this.renameTarget = m[1];
                    this.renameRows = [];
                  }
                })
            }, (row: string, index: number) => `rs_${index}_${row}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 跨文件补全内容：模块 → 成员 → 插入「模块.成员」*/
  @Builder
  CompleteContent() {
    Column() {
      if (this.completeMembers.length > 0) {
        Text(`${this.completeModule} 的成员（点行插入 ${this.completeModule}.成员）`)
          .fontSize(11.5)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8, top: 2, bottom: 4 })
        Scroll() {
          Column() {
            ForEach(this.completeMembers, (row: string, index: number) => {
              Text(row)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.textPrimary)
                .width('100%')
                .height(26)
                .padding({ left: 8, right: 8 })
                .maxLines(1)
                .onClick(() => {
                  const m: RegExpMatchArray | null = row.match(/^(\S+)\s+/);
                  if (m !== null) {
                    const insert: string = `${this.completeModule}.${m[1]}`;
                    this.dialog = '';
                    this.editorController.insertText(insert);
                    this.setStatus(`已插入补全：${insert}`);
                  }
                })
            }, (row: string, index: number) => `cm_${index}_${row}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Auto)
      } else {
        Text('点一个已导入的模块，查看它有哪些成员')
          .fontSize(11.5)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8, top: 2, bottom: 4 })
        Scroll() {
          Column() {
            ForEach(this.completeModules, (mod: string, index: number) => {
              Text(mod)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.debugAccent)
                .width('100%')
                .height(26)
                .padding({ left: 8, right: 8 })
                .onClick(() => {
                  this.completeFromModule(mod);
                })
            }, (mod: string, index: number) => `cmd_${index}_${mod}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 检查结果内容：点行跳到该文件的问题处 */
  @Builder
  InspectContent() {
    Column() {
      if (this.inspectRows.length === 0) {
        Text('未发现问题')
          .fontSize(12)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.inspectRows, (row: string, index: number) => {
              Text(row)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.warning)
                .width('100%')
                .height(26)
                .padding({ left: 8, right: 8 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => {
                  const m: RegExpMatchArray | null = row.match(/([^\s:]+):(\d+)\s/);
                  if (m !== null) {
                    const rel: string = m[1];
                    const line: number = Number.parseInt(m[2], 10);
                    const target: string = `${this.projectRoot}/${rel}`;
                    this.dialog = '';
                    if (FileService.exists(target) && target !== this.editorFilePath) {
                      this.openFile(target, rel.substring(rel.lastIndexOf('/') + 1));
                    }
                    this.editorController.revealLine(line);
                    this.setStatus(`已跳到 ${rel}:${line}`);
                  }
                })
            }, (row: string, index: number) => `ins_${index}_${row}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 跨文件转到类内容：列全工程的类，点行打开该文件并定位 */
  @Builder
  GoToClassContent() {
    Column() {
      if (this.classRows.length === 0) {
        Text('正在扫描全工程的类…')
          .fontSize(11.5)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8, top: 2, bottom: 4 })
      } else {
        Text(`全工程共 ${this.classRows.length} 个类（点行打开定义处）`)
          .fontSize(11.5)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8, top: 2, bottom: 4 })
        Scroll() {
          Column() {
            ForEach(this.classRows, (row: string, index: number) => {
              Text(row)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.debugAccent)
                .width('100%')
                .height(26)
                .padding({ left: 8, right: 8 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => {
                  const m: RegExpMatchArray | null = row.match(/^类\s+(\S+)\s+([^\s:]+):(\d+)/);
                  if (m !== null) {
                    const rel: string = m[2];
                    const line: number = Number.parseInt(m[3], 10);
                    const target: string = `${this.projectRoot}/${rel}`;
                    this.dialog = '';
                    if (FileService.exists(target) && target !== this.editorFilePath) {
                      const nm: string = rel.substring(rel.lastIndexOf('/') + 1);
                      this.openFile(target, nm);
                    }
                    this.editorController.revealLine(line);
                    this.setStatus(`已跳到类 ${m[1]}（${rel}:${line}）`);
                  }
                })
            }, (row: string, index: number) => `gc_${index}_${row}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 查找用法内容：未选符号时列符号（来自 ast 结构），选中后列用法（点用法跳行）*/
  @Builder
  UsagesContent() {
    Column() {
      if (this.usagesRows.length === 0) {
        Text(this.projectSymbols.length > 0 ? '点一个符号 → 全工程查找它的定义与用法' : '点一个符号查看它的用法')
          .fontSize(11.5)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8, top: 2, bottom: 4 })
        Scroll() {
          Column() {
            ForEach(this.projectSymbols.length > 0 ? this.projectSymbols : this.liveStructure, (row: string, index: number) => {
              Text(row)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.textPrimary)
                .width('100%')
                .height(26)
                .padding({ left: 8, right: 8 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => {
                  const m: RegExpMatchArray | null = row.match(/(?:类|函数)\s+([A-Za-z_][A-Za-z0-9_]*)/);
                  const m2: RegExpMatchArray | null = row.match(/([A-Za-z_][A-Za-z0-9_]*)\s+L\d+/);
                  const name: string = m !== null ? m[1] : (m2 !== null ? m2[1] : '');
                  if (name.length > 0) {
                    this.findUsages(name);
                  }
                })
            }, (row: string, index: number) => `fu_${index}_${row}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Auto)
      } else {
        Text(`${this.usagesSymbol} 的用法（点行跳转）`)
          .fontSize(11.5)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8, top: 2, bottom: 4 })
        Scroll() {
          Column() {
            ForEach(this.usagesRows, (row: string, index: number) => {
              Text(row)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.textPrimary)
                .width('100%')
                .height(26)
                .padding({ left: 8, right: 8 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => {
                  // 行格式：`定义  文件:行   代码` 或 `用法  文件:行   代码` —— 支持跨文件跳转
                  const m: RegExpMatchArray | null = row.match(/^(?:定义|用法)\s+([^\s:]+):(\d+)/);
                  if (m !== null) {
                    const rel: string = m[1];
                    const line: number = Number.parseInt(m[2], 10);
                    const target: string = `${this.projectRoot}/${rel}`;
                    this.dialog = '';
                    if (FileService.exists(target) && target !== this.editorFilePath) {
                      const nm: string = rel.substring(rel.lastIndexOf('/') + 1);
                      this.openFile(target, nm);
                    }
                    this.editorController.revealLine(line);
                    this.setStatus(`已跳到 ${rel}:${line}`);
                  }
                })
            }, (row: string, index: number) => `us_${index}_${row}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 变更时间线内容：点行 → 与该文件当前内容 diff */
  @Builder
  TimelineContent() {
    Column() {
      if (this.timelineRows.length === 0) {
        Text('暂无历史版本（每次保存前会自动记录一次快照）')
          .fontSize(12)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8 })
      } else {
        Text('点任意版本 → 与该文件当前内容比较')
          .fontSize(11.5)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8, top: 2, bottom: 4 })
        Scroll() {
          Column() {
            ForEach(this.timelineRows, (row: string, index: number) => {
              Row() {
                Text(row)
                  .fontSize(12)
                  .fontFamily(PyFont.mono)
                  .fontColor(this.theme.textPrimary)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .height(26)
              .padding({ left: 8, right: 8 })
              .onClick(() => {
                const p: string = this.timelinePaths[index];
                this.dialog = '';
                this.compareSnapshotWithFile(p);
              })
            }, (row: string, index: number) => `tl_${index}_${row}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 430 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 外部系统内容：外部任务（终端执行）+ 依赖清单 */
  @Builder
  ExternalContent() {
    Column() {
      Text('外部任务（在真实终端中执行）')
        .fontSize(11.5)
        .fontColor(this.theme.textDisabled)
        .padding({ left: 8, top: 4, bottom: 2 })
      Row() {
        Text('Python 版本')
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => {
            this.runExternalTask('python -V');
          })
        Text('编译检查')
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => {
            this.runExternalTask(`python -m py_compile "${this.editorFilePath}"`);
          })
        Text('统计行数')
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => {
            this.runExternalTask(`find "${this.projectRoot}" -name "*.py" | xargs wc -l`);
          })
        Text('读取依赖清单')
          .fontSize(12)
          .fontColor(this.theme.textOnAccent)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonPrimaryBg)
          .onClick(() => {
            this.loadDependencies();
          })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 2, bottom: 6 })
      if (this.extRows.length > 0) {
        Text('依赖清单')
          .fontSize(11.5)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8, top: 2, bottom: 2 })
        Scroll() {
          Column() {
            ForEach(this.extRows, (row: string, index: number) => {
              Text(row)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.textPrimary)
                .width('100%')
                .padding({ left: 16, right: 8 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }, (row: string, index: number) => `dep_${index}_${row}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 380 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 作用域视图内容（ScopeView）：点行跳到定义行 */
  @Builder
  ScopeContent() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.scopeRows, (row: string, index: number) => {
            Row() {
              Text(row)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(row.indexOf('类') >= 0 ? this.theme.debugAccent : this.theme.textPrimary)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .height(24)
            .padding({ left: 8, right: 8 })
            .onClick(() => {
              const m: RegExpMatchArray | null = row.match(/L(\d+)/);
              if (m !== null) {
                const line: number = Number.parseInt(m[1], 10);
                this.editorController.revealLine(line);
                this.setStatus(`已跳到作用域所在行 ${line}`);
              }
            })
          }, (row: string, index: number) => `sc_${index}_${row}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: 460 })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 图表内容（Graph/Neighborhood）：工具栏 + Canvas 关系图 */
  @Builder
  GraphContent() {
    Column() {
      // 工具栏：控件较多（10 个），用可换行 Flex，避免超出对话框宽度导致点不到
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Text(`${this.graphNodes.length} 节点 / ${this.graphEdges.length} 边`)
          .fontSize(11.5)
          .fontColor(this.theme.textDisabled)
          .margin({ right: 10 })
        Text('树形布局')
          .fontSize(12)
          .fontColor(this.graphLayout === 'tree' ? this.theme.textOnAccent : this.theme.textPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.graphLayout === 'tree' ? this.theme.buttonPrimaryBg : this.theme.buttonBg)
          .onClick(() => {
            this.graphLayout = 'tree';
            this.drawGraph();
          })
        Text('正交布局')
          .fontSize(12)
          .fontColor(this.graphLayout === 'orthogonal' ? this.theme.textOnAccent : this.theme.textPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.graphLayout === 'orthogonal' ? this.theme.buttonPrimaryBg : this.theme.buttonBg)
          .onClick(() => {
            this.graphLayout = 'orthogonal';
            this.drawGraph();
          })
        Text(this.graphEdgeStyle === 'straight' ? '折线' : '直线')
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => {
            this.graphEdgeStyle = this.graphEdgeStyle === 'straight' ? 'polyline' : 'straight';
            this.drawGraph();
          })
        Text(this.graphDir === 'v' ? '左右' : '上下')
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => {
            this.graphDir = this.graphDir === 'v' ? 'h' : 'v';
            this.drawGraph();
          })
        Text('－')
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => {
            this.graphZoom = Math.max(0.6, this.graphZoom - 0.2);
            this.drawGraph();
          })
        Text('＋')
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => {
            this.graphZoom = Math.min(1.8, this.graphZoom + 0.2);
            this.drawGraph();
          })
        Text(this.graphShowLabels ? '隐藏标签' : '显示标签')
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => {
            this.graphShowLabels = !this.graphShowLabels;
            this.drawGraph();
          })
        Text('配色')
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => {
            this.graphPalette = (this.graphPalette + 1) % 3;
            this.drawGraph();
          })
        Text('导出 PNG')
          .fontSize(12)
          .fontColor(this.theme.textOnAccent)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ right: 6 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonPrimaryBg)
          .onClick(() => {
            this.exportGraph();
          })
        Text('适应')
          .fontSize(12)
          .fontColor(this.theme.textPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonBg)
          .onClick(() => {
            this.graphZoom = 1.0;
            this.drawGraph();
          })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 2, bottom: 6 })
      Canvas(this.graphCtx)
        .width('100%')
        .height(360)
        .onClick((event: ClickEvent) => {
          this.onGraphClick(event.x, event.y);
        })
        .backgroundColor(this.theme.editorBg)
        .onReady(() => {
          this.drawGraph();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 本地历史内容：点行 → 与当前编辑器内容比较；点「还原」→ 写回该快照 */
  @Builder
  LocalHistoryContent() {
    Column() {
      if (this.historyRows.length === 0) {
        Text('暂无快照（每次保存前会自动记录上一版本）')
          .fontSize(12)
          .fontColor(this.theme.textDisabled)
          .padding({ left: 8 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.historyRows, (row: string, index: number) => {
              Row() {
                Text(row)
                  .fontSize(12)
                  .fontFamily(PyFont.mono)
                  .fontColor(this.theme.textPrimary)
                  .layoutWeight(1)
                  .maxLines(1)
                  .onClick(() => {
                    const p: string = this.historyPaths[index];
                    this.dialog = '';
                    this.compareActiveWith(p);
                  })
                Text('还原')
                  .fontSize(12)
                  .fontColor(this.theme.funcName)
                  .padding({ left: 10, right: 6 })
                  .onClick(() => {
                    const p: string = this.historyPaths[index];
                    try {
                      const text: string = FileService.readText(p);
                      const tab: EditorTab | undefined = this.activeTab();
                      if (tab !== undefined) {
                        this.snapshotBeforeSave(tab.path);
                        FileService.writeText(tab.path, text);
                        tab.updateText(text);
                        tab.dirty = false;
                        this.tabs = this.tabs.slice();
                        this.dialog = '';
                        this.setStatus(`已还原到 ${row.trim()} 的版本`);
                      }
                    } catch (e) {
                      this.showToast('还原失败');
                    }
                  })
              }
              .width('100%')
              .height(26)
              .padding({ left: 8, right: 8 })
            }, (row: string, index: number) => `lh_${index}_${row}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 差异内容：一行一条，前缀 '  ' 相同 / '- ' 左侧独有 / '+ ' 右侧独有 */
  @Builder
  DiffContent() {
    Column() {
      Text(`+${this.diffAdded}  -${this.diffRemoved}   左：${this.diffLeftName}    右：${this.diffRightName}`)
        .fontSize(11.5)
        .fontColor(this.theme.textDisabled)
        .padding({ left: 8, right: 8, top: 2, bottom: 6 })
      Scroll() {
        Column() {
          ForEach(this.diffRows, (row: string, index: number) => {
            Row() {
              Text(row)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(row.charAt(0) === '-' ? '#E06C75' : (row.charAt(0) === '+' ? '#98C379' : this.theme.textPrimary))
                .backgroundColor(row.charAt(0) === '-' ? '#3A2A2C' : (row.charAt(0) === '+' ? '#2A3A2C' : Color.Transparent))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .height(19)
          }, (row: string, index: number) => `df_${index}_${row}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: 480 })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** SplitChooser.Actions（PyCharm 拖拽标签时弹出的拆分选择器） */
  @Builder
  SplitChooserContent() {
    Column() {
      ForEach(['向右拆分|h|false', '向下拆分|v|false', '向左拆分|h|true', '向上拆分|v|true',
        '居中拆分|h|center', '取消拆分|none|false', '全部取消拆分|all|false'], (spec: string) => {
        Row() {
          Text(spec.split('|')[0])
            .fontSize(12.5)
            .fontColor(this.theme.textPrimary)
            .layoutWeight(1)
        }
        .width('100%')
        .height(26)
        .padding({ left: 8, right: 8 })
        .onClick(() => {
          const parts: string[] = spec.split('|');
          const dir: string = parts[1];
          const flag: string = parts[2];
          this.dialog = '';
          if (flag === 'all') {
            this.unsplitEditor(true);
          } else if (flag === 'center') {
            this.splitEditor(dir, false, 0.5);
          } else if (flag === 'true') {
            this.splitEditor(dir, true);
          } else {
            this.splitEditor(dir);
          }
        })
      }, (spec: string) => `sc_${spec}`)
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      // PyCharm SplitChooser 里还有 Group Tabs / Move to Opposite Group / Next Window / Previous Window
      Text('标签分组 / 移到相反组 / 下一窗口 / 上一窗口：请用标签右键菜单（本选择器只做拆分）')
        .fontSize(11)
        .fontColor(this.theme.textDisabled)
        .padding({ left: 8, right: 8, bottom: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 转到类（PyCharm GoToClass）：当前文件的类与其基类，点击跳行 */
  @Builder
  ClassesContent() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.classHierarchy(), (row: string) => {
            Row() {
              Text(row)
                .fontSize(12.5)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.textPrimary)
                .layoutWeight(1)
                .maxLines(1)
            }
            .width('100%')
            .height(26)
            .padding({ left: 8, right: 8 })
            .onClick(() => {
              const name: string = row.split(' :')[0].trim();
              const line: number = this.lineOfSymbol(name);
              this.dialog = '';
              if (line > 0) {
                this.editorController.revealLine(line);
                this.setStatus(`已转到类 ${name}（第 ${line} 行）`);
              }
            })
          }, (row: string) => `cls_${row}`)
          if (this.classHierarchy().length === 0) {
            Text('当前文件没有 class 定义')
              .fontSize(12)
              .fontColor(this.theme.textDisabled)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: 260 })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 转到符号（PyCharm GoToSymbol）：当前文件的类与函数，带查询过滤，点击跳行 */
  @Builder
  SymbolsContent() {
    Column() {
      TextInput({ text: this.symbolQuery, placeholder: '搜索符号（类/函数）…' })
        .fontSize(12.5)
        .fontFamily(PyFont.ui)
        .backgroundColor(this.theme.inputBg)
        .fontColor(this.theme.textPrimary)
        .placeholderColor(this.theme.textDisabled)
        .height(30)
        .width('100%')
        .onChange((value: string) => {
          this.symbolQuery = value;
        })
      Scroll() {
        Column() {
          ForEach(this.liveStructure.filter((row: string) => this.symbolQuery.length === 0
            || row.toLowerCase().indexOf(this.symbolQuery.toLowerCase()) >= 0), (row: string) => {
            Row() {
              Text(row)
                .fontSize(12.5)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.textPrimary)
                .layoutWeight(1)
                .maxLines(1)
            }
            .width('100%')
            .height(26)
            .padding({ left: 8, right: 8 })
            .onClick(() => {
              const name: string = row.replace('ƒ  ', '').replace('C  ', '').trim();
              const line: number = this.lineOfSymbol(name);
              this.dialog = '';
              if (line > 0) {
                this.editorController.revealLine(line);
                // 结构行形如「ƒ  greet    L6」，提示里只显示符号名（去掉 L 后缀）
        this.setStatus(`已转到符号 ${name.replace(/\s+L\d+$/, '')}（第 ${line} 行）`);
              }
            })
          }, (row: string) => `sym_${row}`)
          if (this.liveStructure.length === 0) {
            Text('当前文件没有可识别的定义')
              .fontSize(12)
              .fontColor(this.theme.textDisabled)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: 240 })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 继承层级（PyCharm 的 Hierarchy 工具窗轻量版）：列出当前文件的类与基类 */
  @Builder
  HierarchyContent() {
    Column() {
      ForEach(this.classHierarchy(), (row: string) => {
        Row() {
          Text(row)
            .fontSize(12.5)
            .fontFamily(PyFont.mono)
            .fontColor(this.theme.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
        }
        .width('100%')
        .height(26)
        .padding({ left: 8, right: 8 })
        .onClick(() => {
          const name: string = row.split(' :')[0].trim();
          const line: number = this.lineOfSymbol(name);
          this.dialog = '';
          if (line > 0) {
            this.editorController.revealLine(line);
            this.setStatus(`已跳转到类 ${name}（第 ${line} 行）`);
          }
        })
      }, (row: string) => `hi_${row}`)
      if (this.classHierarchy().length === 0) {
        Text('当前文件没有 class 定义')
          .fontSize(12)
          .fontColor(this.theme.textDisabled)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 切换器（PyCharm SwitcherAndRecentFilesFallback，Ctrl+Tab）：打开的编辑器 + 最近的文件 */
  @Builder
  SwitcherContent() {
    Column() {
      ForEach(this.tabs, (tab: EditorTab) => {
        Row() {
          Text(tab.id === this.activeTabId ? '▸ ' : '  ')
            .fontSize(12)
            .fontColor(this.theme.accent)
          Text(tab.name)
            .fontSize(12.5)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
        }
        .width('100%')
        .height(28)
        .padding({ left: 8, right: 8 })
        .onClick(() => {
          this.dialog = '';
          this.activateTab(tab);
        })
      }, (tab: EditorTab) => `sw_${tab.id}`)
      if (this.recentFiles.length > 0) {
        Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
        ForEach(this.recentFiles, (p: string) => {
          Row() {
            Text(p.substring(p.lastIndexOf('/') + 1))
              .fontSize(12.5)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textSecondary)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .height(28)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.dialog = '';
            this.openFile(p, p.substring(p.lastIndexOf('/') + 1));
          })
        }, (p: string) => `swr_${p}`)
      }
      if (this.tabs.length === 0 && this.recentFiles.length === 0) {
        Text('没有可切换的编辑器')
          .fontSize(12)
          .fontColor(this.theme.textDisabled)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 随处搜索（PyCharm SearchEverywhere）：左=操作、右=文件，顶部查询过滤 */
  @Builder
  SearchEverywhereContent() {
    Column() {
      TextInput({ text: this.swQuery, placeholder: '搜索文件与操作…' })
        .id('sw-query')
        .fontSize(12.5)
        .fontFamily(PyFont.ui)
        .backgroundColor(this.theme.inputBg)
        .fontColor(this.theme.textPrimary)
        .placeholderColor(this.theme.textDisabled)
        .height(30)
        .width('100%')
        .onChange((value: string) => {
          this.swQuery = value;
        })
      Row() {
        Text('操作').fontSize(11).fontColor(this.theme.textDisabled).margin({ top: 6, bottom: 2 })
      }
      .width('100%')
      Scroll() {
        Column() {
        ForEach(SE_ACTIONS.filter((a: string) => this.swQuery.length === 0
          || a.split('|')[0].toLowerCase().indexOf(this.swQuery.toLowerCase()) >= 0), (item: string) => {
          Row() {
            Text(item.split('|')[0])
              .fontSize(12.5)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textPrimary)
              .layoutWeight(1)
              .maxLines(1)
          }
          .width('100%')
          .height(26)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.dialog = '';
            this.handleAction(item.split('|')[1]);
          })
        }, (item: string) => item)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: 150 })
      .scrollBar(BarState.Auto)
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 6, bottom: 6 })
      Row() {
        Text('文件').fontSize(11).fontColor(this.theme.textDisabled).margin({ bottom: 2 })
      }
      .width('100%')
      Scroll() {
        Column() {
          ForEach(this.flatNodes.filter((n: FileNode) => !n.isDir
            && (this.swQuery.length === 0 || n.name.toLowerCase().indexOf(this.swQuery.toLowerCase()) >= 0)),
            (n: FileNode) => {
              Row() {
                Text(n.name)
                  .fontSize(12.5)
                  .fontFamily(PyFont.ui)
                  .fontColor(this.theme.textPrimary)
                  .layoutWeight(1)
                  .maxLines(1)
              }
              .width('100%')
              .height(26)
              .padding({ left: 8, right: 8 })
              .onClick(() => {
                this.dialog = '';
                this.openFile(n.path, n.name);
              })
            }, (n: FileNode) => n.path)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: 220 })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 「在文件中查找」对话框（PyCharm 的 Ctrl+Shift+F 轻量版：真实的工程内搜索） */
  @Builder
  FindInFilesContent() {
    Column() {
      Row() {
        TextInput({ placeholder: '要查找的内容', text: this.inputValue })
          .layoutWeight(1)
          .height(28)
          .fontSize(12)
          .fontFamily(PyFont.mono)
          .fontColor(this.theme.textPrimary)
          .caretColor(this.theme.caret)
          .backgroundColor(this.theme.inputBg)
          .borderRadius(4)
          .onChange((value: string) => {
            this.inputValue = value;
          })
        Text('查找')
          .fontSize(12)
          .fontColor(this.theme.textOnAccent)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .margin({ left: 8 })
          .borderRadius(4)
          .backgroundColor(this.theme.buttonPrimaryBg)
          .onClick(() => this.runFindInFiles())
      }
      .width('100%')

      Scroll() {
        Column() {
          if (this.searchResults.length === 0) {
            Text('输入内容后点「查找」：会在工程内所有 .py 文件里搜索（最多 200 条），'
              + '结果按「文件:行: 内容」列出。')
              .fontSize(12)
              .fontColor(this.theme.textSecondary)
              .padding({ top: 10 })
          } else {
            ForEach(this.searchResults, (row: string) => {
              Text(row)
                .fontSize(12)
                .fontFamily(PyFont.mono)
                .fontColor(this.theme.textPrimary)
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ top: 4, bottom: 4 })
            }, (row: string, index: number) => `${index}-${row}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .height(220)
      .width('100%')
      .margin({ top: 8 })
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 文件结构（PyCharm 的 Structure 工具窗的对话框版） */
  @Builder
  FileStructureContent() {
    Scroll() {
      Column() {
        ForEach(this.structureSymbols, (row: string) => {
          Text(row)
            .fontSize(12)
            .fontFamily(PyFont.mono)
            .fontColor(this.theme.textPrimary)
            .width('100%')
            .padding({ top: 4, bottom: 4 })
        }, (row: string, index: number) => `${index}-${row}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .height(240)
    .width('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Auto)
  }

  /** 最近文件（PyCharm 的 Ctrl+E）：已打开标签，点一行切换过去 */
  @Builder
  RecentFilesContent() {
    Scroll() {
      Column() {
        ForEach(this.tabs, (tab: EditorTab) => {
          Text(`${tab.dirty ? '● ' : '   '}${tab.name}    ${tab.path}`)
            .fontSize(12)
            .fontFamily(PyFont.mono)
            .fontColor(tab.id === this.activeTabId ? this.theme.textPrimary : this.theme.textSecondary)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ top: 5, bottom: 5 })
            .onClick(() => {
              this.activateTab(tab);
              this.dialog = '';
            })
        }, (tab: EditorTab) => `${tab.id}-${tab.name}`)
        if (this.tabs.length === 0) {
          Text('当前没有打开的文件：用「文件 → 打开…」或工程树双击打开 .py')
            .fontSize(12)
            .fontColor(this.theme.textSecondary)
            .padding({ top: 8 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .height(240)
    .width('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Auto)
  }

  @Builder
  StructureRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor(this.theme.textPrimary)
        .width(112)
      Text(value)
        .fontSize(12)
        .fontFamily(PyFont.mono)
        .fontColor(this.theme.textSecondary)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .margin({ bottom: 9 })
    .alignItems(VerticalAlign.Top)
  }

  /** 项目结构（PyCharm 的 File → Project Structure 的轻量版：真实数据，不是占位） */
  @Builder
  ProjectStructureContent() {
    Column() {
      this.StructureRow('项目名', this.projectName.length > 0 ? this.projectName : '（未打开）')
      this.StructureRow('根目录', this.projectRoot)
      this.StructureRow('文件总数', `${this.countFiles(false)} 个`)
      this.StructureRow('Python 文件', `${this.countFiles(true)} 个`)
      this.StructureRow('打开标签', `${this.tabs.length} 个`)
      this.StructureRow('解释器', this.runtime.ready
        ? `CPython ${this.runtime.version}（${this.runtime.abi}）`
        : '未就绪')
      this.StructureRow('标准库', FileService.stdlibZipPath())
      this.StructureRow('第三方包目录', FileService.sitePackagesDir())
      this.StructureRow('沙箱根目录', FileService.projectRoot())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  DocsContent() {
    Column() {
      Text('快捷键').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
      Text('F5 运行 · Ctrl+S 保存 · Ctrl+F 查找 · Ctrl+N 新建 · Ctrl+O 打开')
        .fontSize(12.5).fontColor(this.theme.textSecondary).margin({ top: 6 })
      Text('内置终端').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
        .margin({ top: 12 })
      Text('python <文件> · python --version · pip install <包>').fontSize(12.5)
        .fontColor(this.theme.textSecondary).margin({ top: 6 })
      Text('构建原生运行时').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.theme.textPrimary)
        .margin({ top: 12 })
      Text('powershell -File scripts/build-cpython-ohos.ps1').fontSize(12.5)
        .fontFamily(PyFont.mono).fontColor(this.theme.textPrimary).margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  @State settingsCategory: string = 'appearance.appearance';
  /** 设置树里展开的分组 */
  @State settingsExpanded: string[] = ['appearance', 'editor', 'project'];
  /** 设置搜索关键字（PyCharm 设置左上角有搜索框） */
  @State settingsSearch: string = '';
  /** TODO 工具窗扫描结果（行文本 = "文件:行号  内容"） */
  @State todoItems: string[] = [];

  private settingsCategoryLabel(id: string): string {
    if (id === 'appearance') {
      return '外观与主题';
    }
    if (id === 'editor') {
      return '编辑器';
    }
    if (id === 'console') {
      return '控制台与运行';
    }
    if (id === 'shortcuts') {
      return '快捷键';
    }
    return '关于';
  }

  @Builder
  SettingsCategoryRow(id: string) {
    Text(this.settingsCategoryLabel(id))
      .fontSize(12.5)
      .fontFamily(PyFont.ui)
      .fontColor(this.settingsCategory === id ? this.theme.accent : this.theme.textPrimary)
      .maxLines(1)
      .width('100%')
      .height(30)
      .padding({ left: 10, right: 6 })
      .borderRadius(4)
      .backgroundColor(this.settingsCategory === id ? this.theme.hoverBg : Color.Transparent)
      .onClick(() => {
        this.settingsCategory = id;
      })
  }

/** 设置树过滤：有搜索词时平铺匹配页面，否则按展开状态显示 */
  private visibleSettingsNodes(): SettingsNode[] {
    const all: SettingsNode[] = settingsTree();
    const key: string = this.settingsSearch.trim().toLowerCase();
    if (key.length > 0) {
      const out: SettingsNode[] = [];
      for (let i = 0; i < all.length; i++) {
        const n: SettingsNode = all[i];
        if (!n.group && n.label.toLowerCase().indexOf(key) >= 0) {
          out.push(n);
        }
      }
      return out;
    }
    const out2: SettingsNode[] = [];
    for (let i = 0; i < all.length; i++) {
      const n: SettingsNode = all[i];
      if (n.group) {
        out2.push(n);
      } else if (this.settingsExpanded.indexOf(n.parent) >= 0) {
        out2.push(n);
      }
    }
    return out2;
  }

  /** 分组行：可展开/收起（PyCharm 设置树的父节点） */
  @Builder
  SettingsGroupRow(node: SettingsNode) {
    Row() {
      IconAsset({
        iconSize: 12,
        file: this.settingsExpanded.indexOf(node.id) >= 0 ? 'icons/chevronDown.svg' : 'icons/chevronRight.svg'
      })
      Text(node.label)
        .fontSize(12.5)
        .fontFamily(PyFont.ui)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.textPrimary)
        .margin({ left: 6 })
        .maxLines(1)
    }
    .width('100%')
    .height(28)
    .padding({ left: 6, right: 6 })
    .onClick(() => {
      const idx: number = this.settingsExpanded.indexOf(node.id);
      if (idx >= 0) {
        this.settingsExpanded = this.settingsExpanded.filter((x: string) => x !== node.id);
      } else {
        const next: string[] = this.settingsExpanded.slice();
        next.push(node.id);
        this.settingsExpanded = next;
      }
    })
  }

  /** 页面行：缩进 + 选中高亮（PyCharm 的叶子节点） */
  @Builder
  SettingsPageRow(node: SettingsNode) {
    Text(node.label)
      .fontSize(12.5)
      .fontFamily(PyFont.ui)
      .fontColor(this.settingsCategory === node.id ? this.theme.accent : this.theme.textPrimary)
      .maxLines(1)
      .width('100%')
      .height(26)
      .padding({ left: 26, right: 6 })
      .borderRadius(4)
      .backgroundColor(this.settingsCategory === node.id ? this.theme.hoverBg : Color.Transparent)
      .onClick(() => {
        this.settingsCategory = node.id;
      })
  }

  @Builder
  SettingsItemLabel(text: string) {
    Text(text).fontSize(13).fontColor(this.theme.textPrimary).width(120)
  }

  @Builder
  SettingsToggleRow(label: string, value: boolean, onChange: (on: boolean) => void) {
    Row() {
      this.SettingsItemLabel(label)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .onChange((isOn: boolean) => onChange(isOn))
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  /** PyCharm 设置是「左分类树 + 右内容」双栏；这里同样分区，不再是一长条 */
  @Builder
  SettingsContent() {
    Row() {
      Column() {
        // 搜索框（PyCharm 设置左上角）
        TextInput({ text: this.settingsSearch, placeholder: '搜索' })
          .fontSize(12)
          .height(28)
          .backgroundColor(this.theme.inputBg)
          .borderRadius(4)
          .margin({ bottom: 6 })
          .onChange((v: string) => {
            this.settingsSearch = v;
          })
        // 分类树（组可展开）
        Scroll() {
          Column() {
            ForEach(this.visibleSettingsNodes(), (n: SettingsNode) => {
              if (n.group) {
                this.SettingsGroupRow(n)
              } else {
                this.SettingsPageRow(n)
              }
            }, (n: SettingsNode) => n.id)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
      }
      .width(232)
      .height('100%')
      .padding({ left: 6, right: 6, top: 8 })
      .backgroundColor(this.theme.panelBgAlt)
      .border({ width: { right: 1 }, color: this.theme.border })

      Scroll() {
        Column() {
          if (this.settingsCategory === 'appearance.appearance') {
            Row() {
              this.SettingsItemLabel('主题')
              Text(this.themeName === 'light' ? '浅色（PyCharm Light）' : '深色（PyCharm Darcula）')
                .fontSize(12.5)
                .fontColor(this.theme.link)
                .onClick(() => this.toggleTheme())
            }.width('100%').margin({ bottom: 12 })
            Row() {
              this.SettingsItemLabel('字号')
              Text(`${this.settings.fontSize}`).fontSize(12.5).fontColor(this.theme.textPrimary)
              Text('－').fontSize(14).fontColor(this.theme.textSecondary).margin({ left: 16 })
                .onClick(() => this.handleAction('view.zoomOut'))
              Text('＋').fontSize(14).fontColor(this.theme.textSecondary).margin({ left: 16 })
                .onClick(() => this.handleAction('view.zoomIn'))
            }.width('100%').margin({ bottom: 12 })
            Row() {
              this.SettingsItemLabel('行号')
              Toggle({ type: ToggleType.Switch, isOn: this.settings.showLineNumbers })
                .onChange((isOn: boolean) => {
                  this.settings.showLineNumbers = isOn;
                  SettingsService.save(this.settings);
                })
            }.width('100%').margin({ bottom: 12 })
            Row() {
              this.SettingsItemLabel('当前行高亮')
              Toggle({ type: ToggleType.Switch, isOn: this.settings.highlightCurrentLine })
                .onChange((isOn: boolean) => {
                  this.settings.highlightCurrentLine = isOn;
                  SettingsService.save(this.settings);
                })
            }.width('100%').margin({ bottom: 12 })
          } else if (this.settingsCategory === 'editor.general') {
            Row() {
              this.SettingsItemLabel('缩进')
              Text(`${this.settings.tabSize} 空格`).fontSize(12.5).fontColor(this.theme.textSecondary)
              Text('－').fontSize(14).fontColor(this.theme.textSecondary).margin({ left: 16 })
                .onClick(() => {
                  this.settings.tabSize = Math.max(2, this.settings.tabSize - 2);
                  SettingsService.save(this.settings);
                })
              Text('＋').fontSize(14).fontColor(this.theme.textSecondary).margin({ left: 16 })
                .onClick(() => {
                  this.settings.tabSize = Math.min(8, this.settings.tabSize + 2);
                  SettingsService.save(this.settings);
                })
            }.width('100%').margin({ bottom: 12 })
            Row() {
              this.SettingsItemLabel('自动保存')
              Toggle({ type: ToggleType.Switch, isOn: this.settings.autoSave })
                .onChange((isOn: boolean) => {
                  this.settings.autoSave = isOn;
                  SettingsService.save(this.settings);
                })
            }.width('100%').margin({ bottom: 12 })
            Row() {
              this.SettingsItemLabel('自动保存延迟')
              Text(`${this.settings.autoSaveDelayMs} ms`).fontSize(12.5).fontColor(this.theme.textSecondary)
              Text('－').fontSize(14).fontColor(this.theme.textSecondary).margin({ left: 16 })
                .onClick(() => {
                  this.settings.autoSaveDelayMs = Math.max(300, this.settings.autoSaveDelayMs - 300);
                  SettingsService.save(this.settings);
                })
              Text('＋').fontSize(14).fontColor(this.theme.textSecondary).margin({ left: 16 })
                .onClick(() => {
                  this.settings.autoSaveDelayMs = Math.min(5000, this.settings.autoSaveDelayMs + 300);
                  SettingsService.save(this.settings);
                })
            }.width('100%').margin({ bottom: 12 })
          } else if (this.settingsCategory === 'project.interpreter') {
            Row() {
              this.SettingsItemLabel('解释器')
              Text(this.runtime.ready
                ? `CPython ${this.runtime.version}（${this.runtime.abi}）`
                : '未就绪').fontSize(12.5).fontColor(this.runtime.ready ? this.theme.success : this.theme.error)
            }.width('100%').margin({ bottom: 12 })
            Row() {
              this.SettingsItemLabel('底部面板高度')
              Text(`${this.settings.bottomPanelHeight}`).fontSize(12.5).fontColor(this.theme.textSecondary)
            }.width('100%').margin({ bottom: 12 })
            Row() {
              Text('重新初始化运行时（重新释放标准库与 pip wheel）')
                .fontSize(12.5).fontColor(this.theme.link)
                .onClick(() => this.handleAction('tools.reinit'))
            }.width('100%').margin({ bottom: 8 })
          } else if (this.settingsCategory === 'keymap') {
            ForEach([['运行当前文件', 'F5'], ['停止', 'Shift+F5'], ['保存', 'Ctrl+S'],
                     ['查找', 'Ctrl+F'], ['替换', 'Ctrl+R'], ['新建文件', 'Ctrl+N'],
                     ['打开文件', 'Ctrl+O'], ['设置', 'Ctrl+Alt+S'], ['切换主题', 'Ctrl+Alt+T'],
                     ['转到行', 'Ctrl+G']], (row: string[]) => {
              Row() {
                Text(row[0]).fontSize(12.5).fontColor(this.theme.textPrimary).width(140)
                Text(row[1]).fontSize(12.5).fontColor(this.theme.textSecondary)
              }.width('100%').margin({ bottom: 8 })
            }, (row: string[]) => row[0] + row[1])
          } else if (this.settingsCategory === 'editor.font') {
            Row() {
              this.SettingsItemLabel('字号')
              Text(`${this.settings.fontSize}`).fontSize(12.5).fontColor(this.theme.textPrimary)
              Text('－').fontSize(14).fontColor(this.theme.textSecondary).margin({ left: 16 })
                .onClick(() => this.handleAction('view.zoomOut'))
              Text('＋').fontSize(14).fontColor(this.theme.textSecondary).margin({ left: 16 })
                .onClick(() => this.handleAction('view.zoomIn'))
            }.width('100%').margin({ bottom: 12 })
            Row() {
              this.SettingsItemLabel('代码字体')
              Text('JetBrains Mono（随包注册）').fontSize(12.5).fontColor(this.theme.textSecondary)
            }.width('100%').margin({ bottom: 12 })
          } else if (this.settingsCategory === 'editor.colors') {
            Row() {
              this.SettingsItemLabel('方案')
              Text(this.themeName === 'light' ? 'Islands Light' : 'Islands Dark').fontSize(12.5)
                .fontColor(this.theme.link)
                .onClick(() => this.toggleTheme())
            }.width('100%').margin({ bottom: 12 })
            Text('配色取自 PyCharm 的 ManyIslandsDark.theme.json 与 IslandSchemeDark.xml；')
              .fontSize(12.5).fontColor(this.theme.textSecondary)
            Text('关键字 #CF8E6D · 字符串 #6AAB73 · 数字 #2AACB8 · 注释 #7A7E85 · 函数 #57AAF7')
              .fontSize(12.5).fontColor(this.theme.textSecondary).margin({ top: 4 })
          } else if (this.settingsCategory === 'editor.encoding') {
            Row() {
              this.SettingsItemLabel('项目编码')
              Text('UTF-8').fontSize(12.5).fontColor(this.theme.textPrimary)
            }.width('100%').margin({ bottom: 12 })
            Text('本 IDE 读写统一为 UTF-8；BOM 可在「文件」菜单里增删。')
              .fontSize(12.5).fontColor(this.theme.textSecondary)
          } else if (this.settingsCategory === 'project.packages') {
            Row() {
              this.SettingsItemLabel('索引地址')
              Text(this.settings.pipIndexUrl).fontSize(12).fontColor(this.theme.textSecondary).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.width('100%').margin({ bottom: 12 })
            Row() {
              this.SettingsItemLabel('允许联网')
              Toggle({ type: ToggleType.Switch, isOn: this.settings.pipOnline })
                .onChange((isOn: boolean) => {
                  this.settings.pipOnline = isOn;
                  SettingsService.save(this.settings);
                })
            }.width('100%').margin({ bottom: 12 })
            Text('Python 软件包面板可浏览已安装包；安装依赖于内嵌 pip（当前缺 _ssl，联网安装不可用）。')
              .fontSize(12.5).fontColor(this.theme.textSecondary)
          } else if (this.settingsCategory === 'plugins') {
            Text('已内置实现（替代插件提供的工具窗）：通知 / Python 软件包 / 数据库·Gradle·Maven·图表（说明页）')
              .fontSize(12.5).fontColor(this.theme.textSecondary).margin({ bottom: 8 })
            Text('本版本不含插件市场与插件加载机制。')
              .fontSize(12.5).fontColor(this.theme.textSecondary)
          } else if (this.settingsCategory === 'other.advanced') {
            Row() {
              this.SettingsItemLabel('省电模式')
              Text('始终开启（无后台索引）').fontSize(12.5).fontColor(this.theme.textSecondary)
            }.width('100%').margin({ bottom: 12 })
            Text('恢复默认设置（含主题、字号、面板宽度）')
              .fontSize(12.5).fontColor(this.theme.link)
              .onClick(() => this.handleAction('file.restoreDefaults'))
          } else if (this.settingsCategory === 'vcs.git') {
            Text('沙箱内未捆绑 Git 可执行文件，因此不提供 Git 集成。')
              .fontSize(12.5).fontColor(this.theme.textSecondary).margin({ bottom: 8 })
            Text('可用「终端」里的 Python 脚本读写 .git，或用外部工具管理版本。')
              .fontSize(12.5).fontColor(this.theme.textSecondary)
          } else if (this.settingsCategory === 'tools.terminal') {
            Row() {
              this.SettingsItemLabel('Shell')
              Text('内置 Python 终端（无系统 shell）').fontSize(12.5).fontColor(this.theme.textSecondary)
            }.width('100%').margin({ bottom: 12 })
          } else if (this.settingsCategory === 'language.python') {
            Row() {
              this.SettingsItemLabel('解释器')
              Text(this.runtime.ready ? `CPython ${this.runtime.version}` : '未就绪')
                .fontSize(12.5).fontColor(this.runtime.ready ? this.theme.success : this.theme.error)
            }.width('100%').margin({ bottom: 12 })
            Text('Python 支持：语法高亮、缩进/括号配对、补全、结构解析、运行与调试。')
              .fontSize(12.5).fontColor(this.theme.textSecondary)
          } else if (this.settingsCategory === 'about') {
            Text('鸿蒙 Python IDE 1.0.0').fontSize(13).fontColor(this.theme.textPrimary)
              .margin({ bottom: 8 })
            Text('面向鸿蒙平板与鸿蒙 PC 的 Python 集成开发环境')
              .fontSize(12.5).fontColor(this.theme.textSecondary).margin({ bottom: 8 })
            Text('内嵌 CPython 3.12.10 · 双 ABI · 随包标准库与 pip')
              .fontSize(12.5).fontColor(this.theme.textSecondary).margin({ bottom: 8 })
            Text('第三方组件许可见 docs/LICENSES.md')
              .fontSize(12).fontColor(this.theme.textSecondary)
          } else {
            Text(this.settingsCategoryLabel(this.settingsCategory))
              .fontSize(13).fontColor(this.theme.textPrimary).margin({ bottom: 8 })
            Text('该设置页与 PyCharm 的分类一一对应（名称取自其语言包），本版本尚未实现具体选项。')
              .fontSize(12.5).fontColor(this.theme.textSecondary).margin({ bottom: 8 })
            Text('已实现的设置页：外观 / 编辑器·常规·字体·颜色方案·文件编码 / ')
              .fontSize(12.5).fontColor(this.theme.textSecondary)
            Text('Python 解释器 / Python 软件包 / 运行配置 / 键位映射 / 插件 / 高级设置 / 版本控制·Git / 终端 / Python')
              .fontSize(12.5).fontColor(this.theme.textSecondary)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(14)
      }
      .layoutWeight(1)
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height(520)
  }

  @Builder
  ProjectListContent() {
    Column() {
      if (this.projectList.length === 0) {
        Text('沙箱内暂无项目，请先「新建项目」。').fontSize(12.5).fontColor(this.theme.textSecondary)
      } else {
        ForEach(this.projectList, (path: string) => {
          Row() {
            IconFolder({ iconSize: 14, color: this.theme.accent })
            Text(FileService.baseName(path))
              .fontSize(13)
              .fontColor(this.theme.textPrimary)
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            this.loadProject(path);
            this.dialog = '';
          })
        }, (path: string) => path)
      }
    }
    .alignItems(HorizontalAlign.Start)
  }
}
