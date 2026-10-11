/**
 * 全局领域模型。
 *
 * ArkTS 约束：所有对象字面量都必须有明确的类型；不使用 any/unknown；
 * 需要触发 UI 刷新的嵌套对象统一用 @Observed 装饰，并通过重新赋值数组触发刷新。
 */

/**
 * PyCharm 会把虚拟环境/缓存类目录视为"排除目录"（橙色文件夹，expui/nodes/excludeRoot.svg）。
 * 对应动作 ProjectView.ShowExcludedFiles（LangActions.xml:725）。
 */
export function isExcludedDirName(name: string): boolean {
  const n: string = name.toLowerCase();
  return n === '.venv' || n === 'venv' || n === '.idea' || n === '__pycache__'
    || n === 'node_modules' || n === '.git' || n === '.mypy_cache' || n === '.pytest_cache';
}

/** 项目树节点 */
@Observed
export class FileNode {
  name: string = '';
  path: string = '';
  isDir: boolean = false;
  expanded: boolean = false;
  loaded: boolean = false;
  depth: number = 0;
  children: FileNode[] = [];
  /** 合成节点（PyCharm 的「外部库」「临时文件和控制台」）：path 不是真实文件系统路径 */
  synthetic: boolean = false;
  /** 该行专用图标（rawfile 路径）；空串表示按文件名推断类型 */
  iconFile: string = '';
  /** 合成叶子点击时显示的说明文字（不当作真实文件打开） */
  infoText: string = '';

  constructor(name: string, path: string, isDir: boolean, depth: number) {
    this.name = name;
    this.path = path;
    this.isDir = isDir;
    this.depth = depth;
  }
}

/** 编辑器标签页 */
@Observed
export class EditorTab {
  id: string = '';
  path: string = '';
  name: string = '';
  /** 文件正文（唯一真源，编辑器组件只负责渲染与回调） */
  text: string = '';
  /** 磁盘上的正文，用于判断 dirty */
  savedText: string = '';
  dirty: boolean = false;
  cursorLine: number = 1;
  cursorColumn: number = 1;
  /** 断点行号集合（1-based） */
  breakpoints: number[] = [];
  /** 是否预览态（PyCharm 单击打开为斜体标签） */
  preview: boolean = false;

  constructor(path: string, name: string, text: string) {
    this.id = path;
    this.path = path;
    this.name = name;
    this.text = text;
    this.savedText = text;
  }

  markSaved(text: string): void {
    this.text = text;
    this.savedText = text;
    this.dirty = false;
  }

  updateText(text: string): void {
    this.text = text;
    this.dirty = text !== this.savedText;
  }
}

/** 运行控制台一条输出 */
export class LogEntry {
  id: number = 0;
  /** stdout | stderr | info | success | command | system */
  stream: string = 'stdout';
  text: string = '';
  timeMs: number = 0;

  constructor(id: number, stream: string, text: string, timeMs: number) {
    this.id = id;
    this.stream = stream;
    this.text = text;
    this.timeMs = timeMs;
  }
}

/** 运行结果 */
export class RunResult {
  code: number = 0;
  stdout: string = '';
  stderr: string = '';
  durationMs: number = 0;

  constructor(code: number, stdout: string, stderr: string, durationMs: number) {
    this.code = code;
    this.stdout = stdout;
    this.stderr = stderr;
    this.durationMs = durationMs;
  }
}

/** 运行时状态 */
export class RuntimeStatus {
  ready: boolean = false;
  version: string = '';
  abi: string = '';
  stdlibReady: boolean = false;
  /** 未就绪时的原因，直接展示给用户 */
  message: string = '';

  constructor(ready: boolean, version: string, abi: string, stdlibReady: boolean, message: string) {
    this.ready = ready;
    this.version = version;
    this.abi = abi;
    this.stdlibReady = stdlibReady;
    this.message = message;
  }
}

/** 运行配置（PyCharm 的 Run Configuration） */
@Observed
export class RunConfiguration {
  name: string = '当前文件';
  targetPath: string = '';
  args: string = '';
  workingDir: string = '';
  /** 运行时环境变量，形如 KEY=VALUE 的数组 */
  env: string[] = [];

  constructor(name: string, targetPath: string, args: string, workingDir: string) {
    this.name = name;
    this.targetPath = targetPath;
    this.args = args;
    this.workingDir = workingDir;
  }
}

/** 布局断点：平板竖屏 / 平板横屏 / PC 窗口 */
export enum LayoutSize {
  /** 窄：手机竖屏、平板分屏、PC 窄窗口 */
  COMPACT = 'compact',
  /** 中：平板竖屏、PC 中等窗口 */
  MEDIUM = 'medium',
  /** 宽：平板横屏、PC 全屏 */
  EXPANDED = 'expanded'
}

/** 应用设置 */
@Observed
export class AppSettings {
  themeName: string = 'darcula';
  fontSize: number = 14;
  tabSize: number = 4;
  showLineNumbers: boolean = true;
  wordWrap: boolean = false;
  autoSave: boolean = false;
  /** 自动保存延迟（毫秒） */
  autoSaveDelayMs: number = 1500;
  showIndentGuides: boolean = true;
  highlightCurrentLine: boolean = true;
  showLeftToolWindow: boolean = true;
  /** 代码折叠状态（`path#line`，逗号分隔持久化；与 recentFiles 同样用字符串存） */
  foldedFolds: string = '';
  /** 多窗格：拆分方向 none|h|v、第 2 窗格标签 id（逗号分隔）、分隔比例 */
  paneSplit: string = 'none';
  pane2Tabs: string = '';
  paneRatio: number = 0.5;
  paneBefore: boolean = false;
  showBottomToolWindow: boolean = true;
  leftPanelWidth: number = 280;
  bottomPanelHeight: number = 220;
  /** 最后一次打开的项目根目录 */
  lastProjectRoot: string = '';
  /** pip 索引地址（离线时可置空走本地 wheel 目录） */
  pipIndexUrl: string = 'https://repo.huaweicloud.com/repository/pypi/simple';
  /** 是否允许 pip 联网 */
  pipOnline: boolean = false;
  /** 最近打开的文件（逗号分隔，最新在前）——PyCharm 的 最近的文件(_N) */
  recentFiles: string = '';

  constructor() {
  }
}

/**
 * 一次调试暂停的快照。
 * 字段与 entry/src/main/cpp/types/libpythonbridge/index.d.ts 的 PyDebugPause 一一对应，
 * 由调试钩子（napi_init.cpp 里的 kDebugHookScript）以 stream=2 的 JSON 推送。
 */
export interface DebugPause {
  /** 绝对路径 */
  file: string;
  /** 1-based 行号 */
  line: number;
  /** 所在函数名，模块级为 <module> */
  func: string;
  /** 局部变量快照：[名称, repr] */
  locals: string[][];
  /** 调用栈：[文件, 行号, 函数]，最内层在前 */
  stack: string[][];
  /** Evaluate：被求值的表达式（仅 'eval' 类暂停有值）*/
  evalExpr?: string;
  /** Evaluate：求值结果（仅 'eval' 类暂停有值）*/
  evalResult?: string;
}

/** 查找/替换状态 */
export class SearchState {
  visible: boolean = false;
  query: string = '';
  replaceText: string = '';
  caseSensitive: boolean = false;
  wholeWord: boolean = false;
  regex: boolean = false;
  /** 命中位置（字符偏移） */
  matches: number[] = [];
  currentIndex: number = -1;

  reset(): void {
    this.matches = [];
    this.currentIndex = -1;
  }
}
