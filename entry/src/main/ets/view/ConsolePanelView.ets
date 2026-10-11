/**
 * ConsolePanelView —— PyCharm New UI 风格底部工具窗（运行 / Python 控制台 / 终端 / 问题）
 *
 * 标签栏在左侧、动作图标在右侧；内容区用 Scroll + Column 逐行渲染日志，
 * 并在 entries 变化时自动贴底。
 *
 * API 出处（HarmonyOS 26.0.0 / API 26 SDK）：
 *  - Scroll(scroller?: Scroller) : component/scroll.d.ts:861
 *  - Scroller 类                 : component/scroll.d.ts:351
 *  - Scroller.scrollEdge(value: Edge, options?: ScrollEdgeOptions) : component/scroll.d.ts:395
 *  - Scroller.scrollTo(options: ScrollOptions) : component/scroll.d.ts:379
 *  - Scroll.scrollBar(BarState)  : component/scroll.d.ts:1186
 *  - Edge 枚举                   : component/enums.d.ts:1252
 *  - Text.copyOption(CopyOptions) : component/text.d.ts:677，CopyOptions.LocalDevice : component/enums.d.ts:3262
 *  - Text.textSelectable(mode: TextSelectableMode) : component/text.d.ts:1133
 *    （注意：textSelectable 收的是枚举不是 boolean，TextSelectableMode.SELECTABLE_UNFOCUSABLE: enums.d.ts:4652）
 *  - Text.fontFamily / fontSize / fontColor / maxLines / textAlign / textOverflow
 *      : component/text.d.ts:528 / :146 / :132 / :545 / :354 / :511
 *  - TextOverflowOptions 接口                     : component/text.d.ts:35
 *  - TextInput(value?: TextInputOptions) : component/text_input.d.ts:832
 *  - TextInput.onSubmit(OnSubmitCallback) : component/text_input.d.ts:1091
 *    OnSubmitCallback = (enterKey: EnterKeyType, event: SubmitEvent) => void : text_input.d.ts:880
 *  - TextInput.onChange / enterKeyType / caretColor / placeholderColor
 *      : component/text_input.d.ts:1107 / :1038 / :1049 / :984
 *  - EnterKeyType.Send = 4                        : component/text_input.d.ts:526
 *  - Divider.vertical / color / strokeWidth       : component/divider.d.ts:69 / :84 / :103
 *  - CommonMethod.onHover / onClick               : component/common.d.ts:18556 / :18506
 *  - ScrollableCommonMethod.align(Alignment)      : component/common.d.ts:25187 / :20310
 *  - Alignment.TopStart                           : component/enums.d.ts:1548
 *  - HorizontalAlign.Start                        : component/enums.d.ts:1946
 *  - FlexAlign.Center / VerticalAlign.Center      : component/enums.d.ts:1990 / :2327
 *  - Blank() 组件                                  : component/blank.d.ts:103
 *  - CommonMethod.constraintSize(ConstraintSizeOptions) : component/common.d.ts:17399
 *  - EdgeWidths / Padding / Margin 都是 declare type（不是 class）
 *      : component/units.d.ts:699 / :414 / :651
 *  - BorderStyle.Solid                            : component/enums.d.ts:443
 *  - ForEach(arr, itemGenerator, keyGenerator?)   : component/for_each.d.ts:85
 *  - @Watch('entries') 用于内容变化时贴底（ArkUI 状态管理 v1，见 state_management.d.ts）
 *
 * ArkTS 严格模式：union 型属性参数（padding/margin/borderWidth）统一用显式类型常量传入，
 * 避免 arkts-no-untyped-obj-literals；build() 内不写局部 const，保证只有一个根容器。
 */

import { PyTheme, PyFont } from '../common/Theme';
import { LogEntry } from '../model/Models';
import { IconClose, IconCopyOutline, IconStop, IconRun, IconRefresh, IconTrash,
  IconChevronDown } from './IdeIcons';

/** 标签栏高度 */
/** Run 工具窗工具条高度（PyCharm 的 Run 工具窗顶部有一条工具条） */
// 与 TAB_BAR_HEIGHT 同理：高度必须容纳 22vp 的按钮，
// 否则子元素溢出父容器 → 整行的点击命中失效
const TOOLBAR_HEIGHT: number = 36;

// 高度必须容纳 22vp 的标题栏按钮：较小高度会让子元素溢出父容器，
// 导致整条工具条的点击命中失效（ArkUI 命中测试受父边界约束）
const TAB_BAR_HEIGHT: number = 36;
/** 标签高亮下划线厚度（PyCharm 是 2vp） */
const TAB_UNDERLINE: number = 2;
/** 内容区字号（比编辑器小一号） */
const CONSOLE_FONT_SIZE: number = PyFont.defaultCodeSize - 1;
/** 日志区左右内边距 */
const CONSOLE_PADDING: number = 8;
/** 问题徽标尺寸 */
const BADGE_SIZE: number = 16;

/** 标签 id 常量（与父组件约定一致） */
const TAB_RUN: string = 'run';
const TAB_REPL: string = 'repl';
const TAB_TERMINAL: string = 'terminal';
const TAB_PROBLEMS: string = 'problems';
/** PyCharm 布局配置里的底部工具窗：Version Control / Services 也需要有 */
const TAB_DEBUG: string = 'debug';
const TAB_VCS: string = 'vcs';
const TAB_SERVICES: string = 'services';

// ── 显式类型的布局常量 ──────────────────────────────────────
const ELLIPSIS: TextOverflowOptions = { overflow: TextOverflow.Ellipsis };
const TAB_BAR_PAD: Padding = { top: 6, bottom: 6, left: 6, right: 4 };
const TAB_BAR_EDGE: EdgeWidths = { top: 0, right: 0, bottom: 1, left: 0 };
const TAB_ITEM_PAD: Padding = { left: 12, right: 12 };
/** 主题实测：ToolWindow.Header.tabContentMinWidth = 24 */
const TAB_MIN_WIDTH: ConstraintSizeOptions = { minWidth: 24 };
const TAB_UNDERLINE_EDGE: EdgeWidths = { top: 0, right: 0, bottom: TAB_UNDERLINE, left: 0 };
const TAB_EDGE_NONE: EdgeWidths = { top: 0, right: 0, bottom: 0, left: 0 };
const BADGE_PAD: Padding = { left: 4, right: 4 };
const BADGE_MARGIN: Margin = { left: 4 };
const BADGE_MIN: ConstraintSizeOptions = { minWidth: BADGE_SIZE };
const INPUT_ROW_PAD: Padding = { left: CONSOLE_PADDING, right: CONSOLE_PADDING };
const INPUT_ROW_EDGE: EdgeWidths = { top: 1, right: 0, bottom: 0, left: 0 };
const INPUT_PAD: Padding = { left: 4, right: 4 };
const TERM_TEXT_PAD: Padding = { top: 6 };

/** 标签描述：id + 中文名 */
class ConsoleTab {
  id: string = '';
  label: string = '';

  constructor(id: string, label: string) {
    this.id = id;
    this.label = label;
  }
}

function buildTabs(): ConsoleTab[] {
  return [
    new ConsoleTab(TAB_RUN, '运行'),
    new ConsoleTab(TAB_DEBUG, '调试'),
    new ConsoleTab(TAB_VCS, '版本控制'),
    new ConsoleTab(TAB_PROBLEMS, '问题'),
    new ConsoleTab(TAB_TERMINAL, '终端'),
    new ConsoleTab(TAB_SERVICES, '服务'),
    new ConsoleTab(TAB_REPL, 'Python 控制台')
  ];
}

@Component
export struct ConsolePanelView {
  @Prop theme: PyTheme = new PyTheme();
  /** entries 变化时触发贴底 */
  @Prop @Watch('onEntriesChanged') entries: LogEntry[] = [];
  @Prop activeTab: string = TAB_RUN;
  /** 调试页内容（XDebugger 变量/调用栈）：由 Index 侧的调试事件生成 */
  @Prop debugLines: string[] = [];
  /** 调用栈帧 [file, line, func]，可点击跳转到源码位置（PyCharm Frames 行为）*/
  @Prop debugStack: string[][] = [];
  gotoFrame: (file: string, line: number) => void = () => {};
  /** Evaluate（PyCharm）：表达式输入 + 求值历史 */
  @Prop evalText: string = '';
  @Prop debugEvals: string[] = [];
  onEvalText: (value: string) => void = () => {};
  /** 变量 [[名, 值]]，点击某行即对该变量求值（无需输入）*/
  @Prop debugLocals: string[][] = [];
  evalVar: (name: string) => void = () => {};
  evalDebug: () => void = () => {};
  @Prop running: boolean = false;
  @Prop replPrompt: string = '>>> ';
  @Prop interpreterLabel: string = '';
  @Prop problemCount: number = 0;
  /** Run 工具窗工具条左侧显示的运行配置名 */
  @Prop runConfigName: string = '当前文件';
  /** 工具条「重新运行」 */
  runAgain: () => void = () => {};

  /** 底部输入行（repl / terminal 共用） */
  @State inputText: string = '';
  /** 标签 hover 项 */
  @State hoverTab: string = '';
  /** 右侧图标 hover 项 */
  @State hoverIcon: string = '';

  selectTab: (tab: string) => void = () => {};
  /** 调试动作（XDebugger：Resume / Step Over / Step Into / Step Out）*/
  resumeDebug: () => void = () => {};
  stepDebug: () => void = () => {};
  stepIntoDebug: () => void = () => {};
  stepOutDebug: () => void = () => {};
  clear: () => void = () => {};
  copyAll: () => void = () => {};
  /** PyCharm ConsoleView.PopupMenu：控制台右键菜单（交给 Index 弹出） */
  onContextMenu: (x: number, y: number) => void = () => {};
  runCommand: (cmd: string) => void = () => {};
  stop: () => void = () => {};
  /** 运行工具窗：恢复默认布局（PyCharm 的 Runner.RestoreLayout） */
  restoreLayout: () => void = () => {};
  /** 问题工具窗：排序方式（ProblemsView.SortBySeverity / SortByName） */
  sortProblems: (by: string) => void = () => {};
  /** 隐藏工具窗（PyCharm 标题栏最右的 −） */
  hidePanel: () => void = () => {};
  /** 终端：打开设置（Terminal.Settings） */
  openTerminalSettings: () => void = () => {};

  private scroller: Scroller = new Scroller();
  /** 标题栏 ⋮ 菜单开关（RunnerLayoutActions） */
  @State moreShown: boolean = false;
  /** 是否显示标签页文字（Runner.ToggleTabLabels） */
  @State showTabLabels: boolean = true;
  @State hoverRow: string = '';

  private tabs: ConsoleTab[] = buildTabs();

  /** @Watch 回调：内容追加后把滚动条贴到底 */
  private onEntriesChanged(): void {
    this.scroller.scrollEdge(Edge.Bottom);       // scroll.d.ts:395
  }

  private tabBg(id: string): ResourceColor {
    if (this.activeTab === id) {
      return this.theme.panelBgAlt;
    }
    return this.hoverTab === id ? this.theme.tabHoverBg : Color.Transparent;
  }

  private tabFg(id: string): string {
    return this.activeTab === id ? this.theme.tabActiveFg : this.theme.tabInactiveFg;
  }

  private iconBg(key: string): ResourceColor {
    return this.hoverIcon === key ? this.theme.hoverBg : Color.Transparent;
  }

  /** 按 stream 给日志着色：stdout | stderr | info/system | success | command */
  private streamColor(stream: string): string {
    if (stream === 'stderr') {
      return this.theme.consoleErr;
    }
    if (stream === 'info' || stream === 'system') {
      return this.theme.consoleInfo;
    }
    if (stream === 'success') {
      return this.theme.consolePrompt;
    }
    if (stream === 'command') {
      return this.theme.consoleLink;
    }
    return this.theme.consoleFg;
  }

  private submitInput(): void {
    const cmd: string = this.inputText;
    if (cmd.length === 0) {
      return;
    }
    this.inputText = '';
    this.runCommand(cmd);
  }

  /** 左上角标签页 */
  @Builder
  tabItem(tab: ConsoleTab) {
    Column() {
      Text(tab.label)
        .fontSize(12)
        .fontFamily(PyFont.ui)
        .fontColor(this.tabFg(tab.id))
        .maxLines(1)
        .textOverflow(ELLIPSIS)
    }
    .height(TAB_BAR_HEIGHT)
    .padding(TAB_ITEM_PAD)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.tabBg(tab.id))
    .borderWidth(this.activeTab === tab.id ? TAB_UNDERLINE_EDGE : TAB_EDGE_NONE)
    .borderColor(this.theme.tabUnderline)
    .borderStyle(BorderStyle.Solid)
    .onHover((isHover: boolean) => {
      this.hoverTab = isHover ? tab.id : '';
    })
    .onClick(() => {
      this.selectTab(tab.id);
    })
  }

  /** 文字按钮（PyCharm 工具窗标题栏里也有文字按钮，如「按严重性」「设置」） */
  @Builder
  textAction(label: string, action: () => void) {
    Text(label)
      .fontSize(11.5)
      .fontFamily(PyFont.ui)
      .fontColor(this.theme.textPrimary)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .margin({ right: 6 })
      .borderRadius(4)
      .backgroundColor(this.iconBg(label))
      .onHover((isHover: boolean) => {
        this.hoverIcon = isHover ? label : '';
      })
      .onClick(action)
  }

/** 标题栏 ⋮ 菜单（依据 RunnerLayoutActions） */
  @Builder
  moreMenu() {
    Column() {
      this.menuItem('显示标签页标签', this.showTabLabels, () => {
        this.showTabLabels = !this.showTabLabels;
        this.moreShown = false;
      })
      this.menuItem('恢复默认布局', false, () => {
        this.moreShown = false;
        this.restoreLayout();
      })
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.menuItem('关闭', false, () => {
        this.moreShown = false;
        this.clear();
      })
      this.menuItem('关闭其他', false, () => {
        this.moreShown = false;
      })
      this.menuItem('关闭所有', false, () => {
        this.moreShown = false;
        this.clear();
      })
      this.menuItem('关闭所有未固定的', false, () => {
        this.moreShown = false;
      })
    }
    .width(200)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(8)
    .position({ x: this.panelWidth() - 200, y: 34 })
  }

  /** ⋮ 菜单项 */
  @Builder
  menuItem(label: string, checked: boolean, action: () => void) {
    Row() {
      Text(checked ? '✓' : ' ')
        .fontSize(11)
        .width(14)
        .fontColor(this.theme.accent)
      Text(label)
        .fontSize(12)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 8, right: 10, top: 5, bottom: 5 })
    .backgroundColor(this.hoverRow === label ? this.theme.toolHoverBg : Color.Transparent)
    .onHover((isHover: boolean) => {
      this.hoverRow = isHover ? label : '';
    })
    .onClick(action)
  }

  /** 面板宽度（⋮ 菜单位置用） */
  private panelWidth(): number {
    return 360;
  }

  /** 右上角动作图标 */
  @Builder
  actionIcon(key: string) {
    Stack() {
      if (key === 'clear') {
        IconClose({ iconSize: 14, color: this.theme.textSecondary })
      } else if (key === 'copy') {
        IconCopyOutline({ iconSize: 14, color: this.theme.textSecondary })
      } else if (key === 'rerun') {
        IconRefresh({ iconSize: 14, color: this.theme.textSecondary })
      } else if (key === 'clearAll') {
        IconTrash({ iconSize: 14, color: this.theme.textSecondary })
      } else {
        IconStop({ iconSize: 12, color: this.theme.error })
      }
    }
    .width(22)
    .height(22)
    // 主题实测：tabContentActionsRightInsets = 0,4,0,2；按钮圆角取 MainToolbar.Button.arc.compact = 8
    .margin({ left: 2, right: 4 })
    .borderRadius(8)
    .backgroundColor(this.iconBg(key))
    .onHover((isHover: boolean) => {
      this.hoverIcon = isHover ? key : '';
    })
    .onClick(() => {
      if (key === 'clear') {
        this.clear();
      } else if (key === 'copy') {
        this.copyAll();
      } else if (key === 'rerun') {
        this.runAgain();
      } else if (key === 'clearAll') {
        this.clear();
      } else {
        this.stop();
      }
    })
  }

  /** 底部输入行：Python 控制台 / 终端共用 */
  @Builder
  inputLine(prompt: string) {
    Row() {
      Text(prompt)
        .fontSize(CONSOLE_FONT_SIZE)
        .fontFamily(PyFont.mono)
        .fontColor(this.theme.consolePrompt)
        .maxLines(1)
      TextInput({ placeholder: '', text: this.inputText })
        .layoutWeight(1)
        .height(26)
        .padding(INPUT_PAD)
        .fontSize(CONSOLE_FONT_SIZE)
        .fontFamily(PyFont.mono)
        .fontColor(this.theme.consoleFg)
        .caretColor(this.theme.caret)
        .placeholderColor(this.theme.textDisabled)
        .backgroundColor(Color.Transparent)
        .borderWidth(0)
        .enterKeyType(EnterKeyType.Send)      // text_input.d.ts:1038 / :526
        .onChange((value: string) => {        // text_input.d.ts:1107
          this.inputText = value;
        })
        .onSubmit((enterKey: EnterKeyType, event: SubmitEvent) => {   // :1091 / :880
          this.submitInput();
        })
    }
    .width('100%')
    .height(30)
    .padding(INPUT_ROW_PAD)
    .backgroundColor(this.theme.consoleBg)
    .borderWidth(INPUT_ROW_EDGE)
    .borderColor(this.theme.border)
    .borderStyle(BorderStyle.Solid)
    .alignItems(VerticalAlign.Center)
  }

  /** 日志逐行渲染 */
  @Builder
  logLines() {
    Column() {
      ForEach(this.entries, (entry: LogEntry, index: number) => {
        Text(entry.text)
          .fontSize(CONSOLE_FONT_SIZE)
          .fontFamily(PyFont.mono)
          .fontColor(this.streamColor(entry.stream))
          .width('100%')
          .textAlign(TextAlign.Start)
          .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)   // text.d.ts:1133 / enums.d.ts:4652
          .copyOption(CopyOptions.LocalDevice)                        // text.d.ts:677 / enums.d.ts:3262
      }, (entry: LogEntry, index: number) => entry.id.toString())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    // 用 Stack 承载：菜单作为最后一层，保证在最上层且不被裁切
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
      // ── 工具条（对照 PyCharm 的 Run 工具窗）：左侧绿色 ▶ + 配置名，右侧 ⟲ ⏹ 🗑 ──
      Row() {
        Row() {
          IconRun({ iconSize: 14, color: this.theme.success })
          Text(this.runConfigName)
            .fontSize(12)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textPrimary)
            .margin({ left: 6 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          IconChevronDown({ iconSize: 11, color: this.theme.textSecondary })
            .margin({ left: 4 })
        }
        .height(22)
        .padding({ left: 8, right: 8 })
        .borderRadius(4)
        .backgroundColor(this.theme.buttonBg)
        .onClick(() => {
          this.runAgain();
        })

        Blank().layoutWeight(1)

        // 依据 PyCharm 各工具窗的 action group，按当前标签显示对应按钮
        if (this.activeTab === TAB_RUN) {
          this.textAction('布局', () => this.restoreLayout())
          this.actionIcon('rerun')
          if (this.running) {
            this.actionIcon('stop')
          }
          this.actionIcon('clearAll')
        } else if (this.activeTab === TAB_PROBLEMS) {
          this.textAction('按严重性', () => this.sortProblems('severity'))
          this.textAction('按名称', () => this.sortProblems('name'))
        } else if (this.activeTab === TAB_TERMINAL) {
          this.textAction('设置', () => this.openTerminalSettings())
        } else {
          this.actionIcon('clearAll')
        }

        // PyCharm：工具窗的 ⋮（选项）与 −（隐藏）在标签行的右端
        Blank().layoutWeight(1)
        Text('⋮')
          .fontSize(14)
          .fontColor(this.theme.textSecondary)
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .borderRadius(4)
          .backgroundColor(this.moreShown ? this.theme.pressedBg : Color.Transparent)
          .onClick(() => {
            this.moreShown = !this.moreShown;
            console.info(`[PyIDE] bottom more toggled -> ${this.moreShown}`);
          })
        Text('−')
          .fontSize(14)
          .fontColor(this.theme.textSecondary)
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .borderRadius(4)
          .onClick(() => {
            this.hidePanel();
          })
      }
      .width('100%')
      .height(TOOLBAR_HEIGHT)
      .padding(TAB_BAR_PAD)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.theme.panelBg)

      // ── 工具窗标签栏（横向可滚动：底部工具窗有 6 个标签，窄窗口下要能滚到）──
      Row() {
        Scroll() {
          Row() {
            ForEach(this.tabs, (tab: ConsoleTab, index: number) => {
              Row() {
                this.tabItem(tab)
                // 问题数徽标
                if (tab.id === TAB_PROBLEMS && this.problemCount > 0) {
                  Text(this.problemCount > 99 ? '99+' : this.problemCount.toString())
                    .fontSize(10)
                    .fontFamily(PyFont.ui)
                    .fontColor(this.theme.textOnAccent)
                    .textAlign(TextAlign.Center)
                    .constraintSize(BADGE_MIN)
                    .height(BADGE_SIZE)
                    .padding(BADGE_PAD)
                    .backgroundColor(this.theme.error)
                    .borderRadius(BADGE_SIZE / 2)
                    .margin(BADGE_MARGIN)
                }
              }
              .alignItems(VerticalAlign.Center)
            }, (tab: ConsoleTab, index: number) => `${index}-${tab.id}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)

        if (this.running) {
          this.actionIcon('stop')
        }
        this.actionIcon('copy')
        this.actionIcon('clear')
      }
      .width('100%')
      .height(TAB_BAR_HEIGHT)
      .padding(TAB_BAR_PAD)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.theme.panelBg)
      .borderWidth(TAB_BAR_EDGE)
      .borderColor(this.theme.border)
      .borderStyle(BorderStyle.Solid)

      // ── 内容区 ──────────────────────────────────────
      if (this.activeTab === TAB_DEBUG) {
      Column() {
        Row() {
          Text('继续')
            .fontSize(12)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ right: 6 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonBg)
            .onClick(() => this.resumeDebug())
          Text('单步')
            .fontSize(12)
            .fontColor(this.theme.textOnAccent)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ right: 6 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonPrimaryBg)
            .onClick(() => this.stepDebug())
          Text('步入')
            .fontSize(12)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ right: 6 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonBg)
            .onClick(() => this.stepIntoDebug())
          Text('步出')
            .fontSize(12)
            .fontColor(this.theme.textPrimary)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ right: 6 })
            .borderRadius(4)
            .backgroundColor(this.theme.buttonBg)
            .onClick(() => this.stepOutDebug())
        }
        .width('100%')
        .padding({ left: 8, top: 4, bottom: 4 })
        if (this.debugLocals.length > 0) {
          Column() {
            ForEach(this.debugLocals, (pair: string[], index: number) => {
              Row() {
                Text(`${pair.length >= 2 ? pair[0] : '?'} = ${pair.length >= 2 ? pair[1] : ''}`)
                  .fontSize(12)
                  .fontFamily(PyFont.mono)
                  .fontColor(this.theme.textPrimary)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ left: 16, right: 8, top: 2, bottom: 2 })
              .onClick(() => {
                if (pair.length >= 1) {
                  this.evalVar(pair[0]);
                }
              })
            }, (pair: string[], index: number) => `lv_${index}_${pair.join('|')}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        if (this.debugStack.length > 0) {
          Row() {
            TextInput({ text: this.evalText, placeholder: '求值表达式（如 name）…' })
              .fontSize(12)
              .fontFamily(PyFont.mono)
              .height(28)
              .layoutWeight(1)
              .backgroundColor(this.theme.inputBg)
              .fontColor(this.theme.textPrimary)
              .placeholderColor(this.theme.textDisabled)
              .onChange((value: string) => {
                this.onEvalText(value);
              })
            Text('求值')
              .fontSize(12)
              .fontColor(this.theme.textOnAccent)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .margin({ left: 6 })
              .borderRadius(4)
              .backgroundColor(this.theme.buttonPrimaryBg)
              .onClick(() => this.evalDebug())
          }
          .width('100%')
          .padding({ left: 16, right: 8, top: 4, bottom: 4 })
          ForEach(this.debugEvals, (row: string, index: number) => {
            Text(row)
              .fontSize(12)
              .fontFamily(PyFont.mono)
              .fontColor(this.theme.funcName)
              .width('100%')
              .padding({ left: 16, right: 8 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }, (row: string, index: number) => `ev_${index}_${row}`)
          Column() {
            ForEach(this.debugStack, (frame: string[], index: number) => {
              Row() {
                Text(`${frame.length >= 3 ? frame[2] : '?'}   ${frame.length >= 1 ? frame[0].substring(frame[0].lastIndexOf('/') + 1) : ''}:${frame.length >= 2 ? frame[1] : ''}`)
                  .fontSize(12)
                  .fontFamily(PyFont.mono)
                  .fontColor(this.theme.textPrimary)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ left: 16, right: 8, top: 2, bottom: 2 })
              .onClick(() => {
                if (frame.length >= 2) {
                  this.gotoFrame(frame[0], Number.parseInt(frame[1], 10));
                }
              })
            }, (frame: string[], index: number) => `fr_${index}_${frame.join('|')}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        if (this.debugLines.length === 0) {
          Text('未在调试中（在行号左侧点一下加断点，再点工具栏的调试按钮）')
            .fontSize(12)
            .fontColor(this.theme.textDisabled)
            .padding({ left: 8, top: 6 })
        } else {
          Scroll() {
            Column() {
              ForEach(this.debugLines, (line: string, index: number) => {
                Text(line)
                  .fontSize(12)
                  .fontFamily(PyFont.mono)
                  .fontColor(line.startsWith('·') ? this.theme.debugAccent : this.theme.textPrimary)
                  .width('100%')
                  .padding({ left: 8, right: 8 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }, (line: string, index: number) => `dbg2_${index}_${line}`)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (this.activeTab === TAB_REPL) {
        Scroll(this.scroller) {
          this.logLines()
        }
        .width('100%')
        .layoutWeight(1)
        .padding(CONSOLE_PADDING)
        .align(Alignment.TopStart)
        .scrollBar(BarState.Auto)
        .backgroundColor(this.theme.consoleBg)

        this.inputLine(this.replPrompt)
      } else if (this.activeTab === TAB_TERMINAL) {
        Column() {
          Text('内置终端：可直接执行 python 命令')
            .fontSize(CONSOLE_FONT_SIZE)
            .fontFamily(PyFont.mono)
            .fontColor(this.theme.consoleInfo)
            .width('100%')
            .textAlign(TextAlign.Start)

          Scroll(this.scroller) {
            this.logLines()
          }
          .width('100%')
          .layoutWeight(1)
          .padding(TERM_TEXT_PAD)
          .align(Alignment.TopStart)
          .scrollBar(BarState.Auto)
        }
        .width('100%')
        .layoutWeight(1)
        .padding(CONSOLE_PADDING)
        .alignItems(HorizontalAlign.Start)
        .backgroundColor(this.theme.consoleBg)

        this.inputLine('$ ')
      } else if (this.activeTab === TAB_VCS) {
        Column() {
          Text('版本控制')
            .fontSize(CONSOLE_FONT_SIZE)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textPrimary)
            .width('100%')
          Text('沙箱内未捆绑 Git 可执行文件，因此没有变更列表与提交操作。')
            .fontSize(CONSOLE_FONT_SIZE)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textSecondary)
            .width('100%')
            .margin({ top: 6 })
          Text('编辑器保存会直接写入磁盘；版本管理可用「终端」+ Python 脚本或外部工具完成。')
            .fontSize(CONSOLE_FONT_SIZE)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textSecondary)
            .width('100%')
            .margin({ top: 6 })
        }
        .width('100%')
        .layoutWeight(1)
        .padding(CONSOLE_PADDING)
        .alignItems(HorizontalAlign.Start)
        .backgroundColor(this.theme.consoleBg)
      } else if (this.activeTab === TAB_SERVICES) {
        Column() {
          Text('没有运行中的服务')
            .fontSize(CONSOLE_FONT_SIZE)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textDisabled)
            .width('100%')
            .margin({ top: 6 })
          Text('本版本在鸿蒙沙箱内运行 Python，不启动外部守护进程；后台任务请在「终端」里运行。')
            .fontSize(CONSOLE_FONT_SIZE)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textSecondary)
            .width('100%')
            .margin({ top: 6 })
        }
        .width('100%')
        .layoutWeight(1)
        .padding(CONSOLE_PADDING)
        .alignItems(HorizontalAlign.Start)
        .backgroundColor(this.theme.consoleBg)
      } else if (this.activeTab === TAB_PROBLEMS) {
        if (this.problemCount === 0) {
          Column() {
            Text('未发现问题')
              .fontSize(CONSOLE_FONT_SIZE)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textDisabled)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.theme.consoleBg)
        } else {
          Scroll(this.scroller) {
            this.logLines()
          }
          .width('100%')
          .layoutWeight(1)
          .padding(CONSOLE_PADDING)
          .align(Alignment.TopStart)
          .scrollBar(BarState.Auto)
          .backgroundColor(this.theme.consoleBg)
        }
      } else {
        Scroll(this.scroller) {
          this.logLines()
        }
        .width('100%')
        .layoutWeight(1)
        .padding(CONSOLE_PADDING)
        .align(Alignment.TopStart)
        .scrollBar(BarState.Auto)
        .backgroundColor(this.theme.consoleBg)
      }

      // 关闭 Column（根容器）
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.consoleBg)

      // ⋮ 菜单（RunnerLayoutActions）
      if (this.moreShown) {
        this.moreMenu()
      }
    }
    .width('100%')
    .height('100%')
    // PyCharm：控制台内容右键 → ConsoleView.PopupMenu（10 项）
    .onMouse((event: MouseEvent) => {
      if (event.button === MouseButton.Right) {
        this.onContextMenu(event.x, event.y);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.onContextMenu(60, 180);
        })
    )
    // PyCharm New UI：底部工具窗也是圆角小岛（主题 Island.arc = 20）
    .borderRadius(this.theme.islandArc)
      .clip(true)
  }
}
