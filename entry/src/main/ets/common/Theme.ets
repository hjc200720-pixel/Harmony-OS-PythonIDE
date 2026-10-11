/**
 * PyCharm 风格设计令牌（Design Tokens）
 *
 * 两套配色严格参考 PyCharm 官方主题：
 *  - DARCULA      : PyCharm Dark（New UI，2024+）
 *  - INTELLIJ_LIGHT: PyCharm Light（New UI）
 *
 * 全应用只允许从这里取色，禁止在组件里写死色值，否则深浅色主题切换会破功。
 */

// 字号来源：PyCharm 配置 other.xml fontSize=12.0（UI 字号）；
// 主题行 "fontSizeOffset": -1 → 小字号 = 11（竖条/状态栏/路径等）
export const UI_FONT_SIZE: number = 12;
export const SMALL_FONT_SIZE: number = 11;

// 圆角/间隙来源：主题 Islands Dark 的 Island 段（你的配置没有紧凑模式 → 用普通档）
//   Island.arc = 20、Island.borderWidth = 6、Island.borderColor = tool-window-bg(#191A1C)
//   弹层/对话框弧：主题里另一段 arc = 12
export const ISLAND_ARC: number = 20;
export const ISLAND_GAP: number = 6;
export const POPUP_ARC: number = 12;
export const ISLAND_BORDER: string = '#191A1C';

export class PyTheme {
  // ── 语法着色 ─────────────────────────────────────────────
  kw: string = '#CF8E6D';            // 关键字 def/class/if/for
  kwType: string = '#CF8E6D';        // 内置类型 int/str/list
  str: string = '#6AAB73';           // 字符串
  num: string = '#2AACB8';           // 数字
  comment: string = '#7A7E85';       // 注释
  docstr: string = '#6AAB73';        // 文档字符串（Python 里即字符串）
  funcName: string = '#57AAF7';      // 函数名/调用（DEFAULT_INSTANCE_METHOD）
  className: string = '#BCBEC4';     // 类名（DEFAULT_CLASS_REFERENCE）
  decorator: string = '#B3AE60';     // @decorator
  selfParam: string = '#94558D';     // self / cls
  builtin: string = '#8888C6';       // 内置函数 print/len
  op: string = '#BCBEC4';            // 运算符（方案实测 DEFAULT_OPERATION_SIGN=bcbec4）
  fstrBrace: string = '#C77DBB';     // f-string 里的 {expr}
  invalid: string = '#FF5B5B';       // 非法/错误标记

  // ── 编辑器 ───────────────────────────────────────────────
  /** 小岛圆角（主题 Island.arc = 20） */
  islandArc: number = 20;
  /** 小岛之间的间隙（主题 Island.borderWidth = 6） */
  islandGap: number = 6;
  /** 弹层/对话框圆角（主题 arc = 12） */
  popupArc: number = 12;
  editorBg: string = '#191A1C';
  // 方案实测：TEXT foreground=bcbec4（编辑器正文），≠ UI 的 text-default
  editorFg: string = '#BCBEC4';
  caret: string = '#D1D3D9';
  selectionBg: string = '#233558';
  /** 编辑器选区叠加色（半透明：输入层在文字层之上，不透明会盖住高亮文字） */
  selectionOverlay: string = '#55233558';
  currentLineBg: string = '#1F2024';
  gutterBg: string = '#191A1C';
  gutterFg: string = '#4B5059';
  gutterActiveFg: string = '#D1D3D9';
  indentGuide: string = '#33353B';
  editorBorder: string = '#26282C';   // editor-border = layer-0-border（与窗口底色同色）
  matchBraceBg: string = '#32593D';
  searchHitBg: string = '#32593D';
  breakpointDot: string = '#F75464';
  /** Python 双色徽标（与 PyCharm 工程树里 .py 的图标同色，采样自 PyCharm 截图） */
  pythonBlue: string = '#548AF7';
  pythonYellow: string = '#F2C55C';
  /** 工具窗竖条：选中 = 蓝色药丸（实测 PyCharm New UI 选中态 #3871E1），hover = 灰色 */
  toolSelectedBg: string = '#3871E1';
  /** 竖条 hover：主题 toolbar-bg-hovered = core-bg-transparent-hovered (#FFFFFF17 → ARGB #17FFFFFF) */
  toolHoverBg: string = '#17FFFFFF';
  /** 调试暂停行的整行底色（与断点红点区分开） */
  debugLineBg: string = '#2C3B5A';
  /** 调试相关强调色（暂停图标、变量面板标题） */
  debugAccent: string = '#5C9CF5';
  errorStripe: string = '#E55B5B';
  warningStripe: string = '#D9A343';

  // ── 窗口 / 面板 ──────────────────────────────────────────
  /** 窗口底色 = 主题 main-window-bg = layer-1-bg = #26282C。
   *  必须与岛（#191A1C）不同，否则岛的圆角没有对比度 → 看不见（这正是之前圆角"没有"的原因） */
  windowBg: string = '#26282C';
  panelBg: string = '#191A1C';
  /** 工具窗背景 alt：主题 tool-window-bg-alt = gray-20 = #212326 */
  panelBgAlt: string = '#212326';
  toolbarBg: string = '#26282C';
  /** 工具窗竖条底色 = 窗口底色 main-window-bg #26282C。
   *  依据：PyCharm New UI 实机截图逐像素扫描（pc-geom/pc-max3/pc-now 三张一致）——
   *  竖条列 x0..128 在 y=600 / H-20 / H-5 全是 #26282C，与"竖条与岛之间的间隙"同色，
   *  即顶栏 / 间隙 / 左右竖条（含其底部）用的是同一个底色，竖条不是更亮的色块。 */
  stripeBg: string = '#26282C';
  menuBarBg: string = '#26282C';
  /** 菜单/hover：主题 toolbar-bg-hovered = #FFFFFF17 → #17FFFFFF */
  menuHoverBg: string = '#17FFFFFF';
  popupBg: string = '#26282C';
  /** 边界色 = 主题 layer-0-border = gray-30 = #26282C。
   *  它与窗口底色 main-window-bg 相同 → 岛之间**没有实线**，分隔完全由背景色渲染（这是 PyCharm 的实际做法） */
  border: string = '#26282C';
  separator: string = '#33353B';
  /** 通用 hover：主题 core-bg-transparent-hovered #FFFFFF17 → #17FFFFFF */
  hoverBg: string = '#17FFFFFF';
  /** 按下：主题 core-bg-transparent-pressed #FFFFFF29 → #29FFFFFF */
  pressedBg: string = '#29FFFFFF';
  selectedBg: string = '#2A4371';
  selectedInactiveBg: string = '#2B2D30';

  // ── Tab ──────────────────────────────────────────────────
  // EditorTabs：background=editor-bg(#191A1C)、选中底=blue-40(#233558)、下划线=blue-60(#2E4D89)
  tabActiveBg: string = '#233558';
  tabInactiveBg: string = '#191A1C';
  tabActiveFg: string = '#DFE1E5';
  tabInactiveFg: string = '#9DA0A8';
  tabUnderline: string = '#2E4D89';
  /** 标签 hover：主题 EditorTabs.hoverBackground = tab-bg-hovered #FFFFFF17 → #17FFFFFF */
  tabHoverBg: string = '#17FFFFFF';

  // ── 文本 ─────────────────────────────────────────────────
  // text-default = gray-130、text-muted = gray-100、text-disabled = gray-60（主题实测）
  textPrimary: string = '#D1D3D9';
  textSecondary: string = '#9FA2A8';
  textDisabled: string = '#4C4F56';
  textOnAccent: string = '#FFFFFF';
  accent: string = '#3871E1';
  accentHover: string = '#4A80F5';
  link: string = '#548AF7';
  success: string = '#57965C';
  warning: string = '#F2C55C';
  error: string = '#FA6675';

  // ── 状态栏 ───────────────────────────────────────────────
  // 实测（PyCharm 2026.2.2 浮动窗口截图）：状态栏与编辑器同色，不是更亮的工具栏色
  // StatusBar.background = main-window-bg = layer-1-bg = gray-30（主题实测）
  statusBarBg: string = '#26282C';
  statusBarFg: string = '#9DA0A8';
  /** 状态栏组件 hover：主题 StatusBar.Widget.hoverBackground = toolbar-bg-hovered → #17FFFFFF */
  statusBarHoverBg: string = '#17FFFFFF';
  statusBarBorder: string = '#393B40';
  /**
   * 标题栏 / 主工具栏底色 = 窗口底色 main-window-bg #26282C。
   * 说明：PyCharm 新 UI 在有「项目颜色」时会给标题栏叠一层该颜色的渐变色（实测中间偏绿
   * #324A36、边缘 #272A2D ≈ 窗口底色）。本项目按需求关闭该着色 —— 顶部栏与间隙/竖条/
   * 底部用完全相同的底色，即"统一配色"。
   */
  headerBg: string = '#26282C';
  /**
   * 窗口底色（= 顶部栏 / 顶栏下的间隙 / 左右竖条 / 状态栏 共用的那层）的竖向渐变。
   * 主题文件里这些区域都是 main-window-bg；实机上那层项目绿来自运行期 ProjectColorInfo 着色。
   * 做法：整块窗口底做一条「顶部有色 → 向下过渡到 main-window-bg」的竖向渐变，
   * chrome 全部透明 → 这几个区域天然连成一个区域，不会出现某块有色、另一块没色的断层。
   */
  chromeTop: string = '#334B35';
  chromeTopMid: string = '#2C3B33';

  // ── 运行控制台 ───────────────────────────────────────────
  consoleBg: string = '#191A1C';
  consoleFg: string = '#BCBEC4';
  consoleErr: string = '#F75464';
  consoleWarn: string = '#D9A343';
  consoleInfo: string = '#BCBEC4';   // CONSOLE_SYSTEM_OUTPUT（方案实测）
  consolePrompt: string = '#57965C';
  consoleLink: string = '#548AF7';

  // ── 控件 ─────────────────────────────────────────────────
  inputBg: string = '#1E1F22';
  inputBorder: string = '#4E5157';
  inputBorderFocused: string = '#3574F0';
  buttonBg: string = '#393B40';
  buttonHoverBg: string = '#17FFFFFF';
  buttonPrimaryBg: string = '#3574F0';
  scrollbarThumb: string = '#4E5157';

  // ── 语义 ─────────────────────────────────────────────────
  isDark: boolean = true;
}

/** PyCharm Dark（New UI） */
export const DARCULA: PyTheme = new PyTheme();

class LightTheme extends PyTheme {
  kw: string = '#0033B3';
  kwType: string = '#0033B3';
  str: string = '#067D17';
  num: string = '#1750EB';
  comment: string = '#8C8C8C';
  docstr: string = '#8C8C8C';
  funcName: string = '#00627A';
  className: string = '#000000';
  decorator: string = '#9E880D';
  selfParam: string = '#94558D';
  builtin: string = '#0033B3';
  op: string = '#080808';
  fstrBrace: string = '#C77DBB';
  invalid: string = '#DB3B4B';

  editorBg: string = '#FFFFFF';
  editorFg: string = '#080808';
  caret: string = '#000000';
  selectionBg: string = '#A6C8FF';
  selectionOverlay: string = '#66A6C8FF';
  currentLineBg: string = '#F2F6FC';
  gutterBg: string = '#F2F3F5';
  gutterFg: string = '#ADADAD';
  gutterActiveFg: string = '#000000';
  indentGuide: string = '#E4E6E8';
  editorBorder: string = '#D3D5DB';
  matchBraceBg: string = '#C3E5C3';
  searchHitBg: string = '#C3E5C3';
  breakpointDot: string = '#DB3B4B';
  pythonBlue: string = '#2B62D9';
  pythonYellow: string = '#D9A343';
  toolSelectedBg: string = '#3B82F6';
  debugLineBg: string = '#DCE9FF';
  debugAccent: string = '#2B62D9';
  errorStripe: string = '#DB3B4B';
  warningStripe: string = '#C7861E';

  windowBg: string = '#F7F8FA';
  panelBg: string = '#F7F8FA';
  panelBgAlt: string = '#FFFFFF';
  toolbarBg: string = '#F7F8FA';
  menuBarBg: string = '#F7F8FA';
  menuHoverBg: string = '#E9EBEE';
  popupBg: string = '#FFFFFF';
  border: string = '#D3D5DB';
  separator: string = '#D3D5DB';
  hoverBg: string = '#EDEFF2';
  pressedBg: string = '#E2E5E9';
  selectedBg: string = '#D4E2FF';
  selectedInactiveBg: string = '#EDEFF2';

  tabActiveBg: string = '#FFFFFF';
  tabInactiveBg: string = '#F7F8FA';
  tabActiveFg: string = '#1F2329';
  tabInactiveFg: string = '#6C707E';
  tabUnderline: string = '#3574F0';
  tabHoverBg: string = '#E9EBEE';

  textPrimary: string = '#1F2329';
  textSecondary: string = '#6C707E';
  textDisabled: string = '#A8ADB7';
  textOnAccent: string = '#FFFFFF';
  accent: string = '#3574F0';
  accentHover: string = '#2B62D9';
  link: string = '#2B62D9';
  success: string = '#208A3C';
  warning: string = '#C7861E';
  error: string = '#DB3B4B';

  statusBarBg: string = '#F7F8FA';
  /** 浅色主题：标题栏底色（未着色时 = 窗口底色） */
  headerBg: string = '#F7F8FA';
  chromeTop: string = '#D7E9DE';
  chromeTopMid: string = '#EAF2ED';
  statusBarFg: string = '#6C707E';
  statusBarHoverBg: string = '#E9EBEE';
  statusBarBorder: string = '#D3D5DB';

  consoleBg: string = '#FFFFFF';
  consoleFg: string = '#080808';
  consoleErr: string = '#DB3B4B';
  consoleWarn: string = '#C7861E';
  consoleInfo: string = '#8C8C8C';
  consolePrompt: string = '#208A3C';
  consoleLink: string = '#2B62D9';

  inputBg: string = '#FFFFFF';
  inputBorder: string = '#C9CCD3';
  inputBorderFocused: string = '#3574F0';
  buttonBg: string = '#EBECF0';
  buttonHoverBg: string = '#DFE1E6';
  buttonPrimaryBg: string = '#3574F0';
  scrollbarThumb: string = '#C9CCD3';

  isDark: boolean = false;
}

/** PyCharm Light（New UI） */
export const INTELLIJ_LIGHT: PyTheme = new LightTheme();

export type ThemeName = 'darcula' | 'light';

export function themeByName(name: ThemeName): PyTheme {
  return name === 'light' ? INTELLIJ_LIGHT : DARCULA;
}

/** 编辑器统一排版令牌（行号槽与代码必须使用完全相同的字体与行高，否则光标/对齐会错位） */
export class PyFont {
  /**
   * 代码字体族。
   * ⚠️ 必须与随包字体一致：之前写的 'JetBrains Mono' 在鸿蒙设备上并不存在，
   * ArkUI 会静默回退到比例字体，代码看起来就"不像 IDE"。
   * 现在随包 Fira Code（SIL OFL 1.1），在 Index.aboutToAppear 里注册。
   */
  static readonly mono: string = 'JetBrains Mono';
  static readonly monoBold: string = 'JetBrains Mono Bold';
  static readonly monoFallback: string = 'HarmonyOS Sans';
  static readonly ui: string = 'HarmonyOS Sans';
  static readonly defaultCodeSize: number = 14;
  /** 行高 = fontSize * lineHeightRatio，编辑器与行号槽共用（1.45 更接近 PyCharm 的紧凑观感） */
  static readonly lineHeightRatio: number = 1.45;
}
