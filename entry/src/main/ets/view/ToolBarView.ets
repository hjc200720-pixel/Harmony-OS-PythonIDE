/**
 * ToolBarView —— PyCharm New UI 风格主工具栏（单行紧凑，行高 36vp）
 *
 * 布局：运行配置下拉 | 运行 / 调试 / 停止 | 分隔线 | 新建 / 打开 / 保存 / 撤销 / 重做
 *       | 撑开 | 搜索框 | 设置
 *
 * 运行配置下拉采用自绘弹层（而非 Select），原因：
 *  - Select 需要 Array<SelectOption> 对象数组，且默认内边距/圆角偏「表单风」，
 *    与 PyCharm 工具栏的 26vp 紧凑下拉不一致；
 *  - 自绘可以直接复用 IconChevronDown 并精确控制行高。
 * 如需改用系统组件，签名出处：
 *  - Select(options: Array<SelectOption>) : component/select.d.ts:73 / SelectOption :28
 *  - Select.onSelect((index, value) => void) : component/select.d.ts:582
 *
 * API 出处（HarmonyOS 26.0.0 / API 26 SDK）：
 *  - TextInput(value?: TextInputOptions)          : component/text_input.d.ts:832
 *  - TextInputOptions.placeholder / text / controller : component/text_input.d.ts:742 / :760 / :769
 *  - TextInput.placeholderColor / caretColor      : component/text_input.d.ts:984 / :1049
 *  - TextInput.enterKeyType(EnterKeyType)         : component/text_input.d.ts:1038
 *  - EnterKeyType.Search = 3                      : component/text_input.d.ts:517
 *  - TextInput.onChange(EditableTextOnChangeCallback) : component/text_input.d.ts:1107
 *  - EditableTextOnChangeCallback = (value, previewText?, options?) => void : text_common.d.ts:481
 *  - TextInput.onSubmit(OnSubmitCallback)         : component/text_input.d.ts:1091
 *  - OnSubmitCallback = (enterKey, event: SubmitEvent) => void : component/text_input.d.ts:880
 *  - SubmitEvent.text                             : component/text_input.d.ts:651
 *  - TextInput.fontSize / fontColor / fontFamily  : component/text_input.d.ts:1171 / :1159 / :1217
 *  - TextInputController                          : component/text_input.d.ts:653 起
 *  - Divider.vertical / color / strokeWidth       : component/divider.d.ts:69 / :84 / :103
 *  - CommonMethod.onHover((isHover, event) => void) : component/common.d.ts:18556 — 工具按钮 hover 高亮
 *  - Blank() 组件                                  : component/blank.d.ts:103
 *  - CommonMethod.layoutWeight(number | string)   : component/common.d.ts:17475
 *  - CommonMethod.borderWidth(Length | EdgeWidths | LocalizedEdgeWidths) : component/common.d.ts:18218
 *  - CommonMethod.borderColor / borderStyle / borderRadius : component/common.d.ts:18232 / :18203 / :18250
 *  - CommonMethod.backgroundColor(ResourceColor)  : component/common.d.ts:17653
 *  - CommonMethod.constraintSize(ConstraintSizeOptions) : component/common.d.ts:17399
 *  - EdgeWidths / Padding / Margin / Position 都是 declare type（不是 class）
 *      : component/units.d.ts:699 / :414 / :651 / :2159
 *  - ShadowOptions 接口                           : component/common.d.ts:7484
 *  - BorderStyle.Solid 枚举                       : component/enums.d.ts:443
 *  - TextOverflowOptions 接口                     : component/text.d.ts:35
 *  - ForEach(arr, itemGenerator, keyGenerator?)   : component/for_each.d.ts:85
 *
 * ArkTS 严格模式：union 型属性参数统一先声明显式类型常量，避免 arkts-no-untyped-obj-literals。
 * 另外所有 prop 名避开 CommonMethod 的通用属性名（size/width/height/... 均不可用）。
 */

import { PyTheme, PyFont } from '../common/Theme';
import {
  IconRun, IconDebug, IconStop, IconPlus, IconFolder, IconSave,
  IconUndo, IconRedo, IconSearch, IconSettings, IconChevronDown, IconAsset, IconMoreVertical
} from './IdeIcons';

/** 工具栏高度（PyCharm New UI 主工具栏约 36vp） */
const TOOLBAR_HEIGHT: number = 38;
/** 工具按钮点击热区边长 */
const TOOL_BTN_SIZE: number = 26;
/** 搜索框宽度 */
const SEARCH_BOX_WIDTH: number = 220;

/** 工具栏按钮种类（@Builder 参数用字符串区分，避免传函数类型） */
const BTN_RUN: string = 'run';
const BTN_DEBUG: string = 'debug';
const BTN_STOP: string = 'stop';
const BTN_PLUS: string = 'plus';
const BTN_FOLDER: string = 'folder';
const BTN_SAVE: string = 'save';
const BTN_UNDO: string = 'undo';
const BTN_REDO: string = 'redo';
const BTN_SETTINGS: string = 'settings';
const BTN_AI: string = 'ai';            // MainToolbarRight: AIAssistantHubPopupAction
const BTN_SEARCH: string = 'searchEverywhere';  // MainToolbarRight: SearchEverywhere
const BTN_MORE: string = 'moreRun';             // RunToolbarMainActionGroup: MoreRunToolbarActions

// ── 显式类型的布局常量 ──────────────────────────────────────
const ELLIPSIS: TextOverflowOptions = { overflow: TextOverflow.Ellipsis };
const TOOLBAR_PAD: Padding = { left: 8, right: 8 };
const TOOLBAR_EDGE: EdgeWidths = { top: 0, right: 0, bottom: 1, left: 0 };
const CONFIG_BTN_PAD: Padding = { left: 8, right: 6 };
// MainToolbar.Dropdown.maxWidth = 350（主题实测键）
const CONFIG_BTN_MIN: ConstraintSizeOptions = { minWidth: 120, maxWidth: 350 };
const CONFIG_POPUP_SIZE: ConstraintSizeOptions = { minWidth: 180, maxHeight: 300 };
const CONFIG_ITEM_PAD: Padding = { left: 10, right: 10 };
const CONFIG_POPUP_POS: Position = { x: 8, y: TOOLBAR_HEIGHT };
const SEARCH_BOX_PAD: Padding = { left: 6, right: 6 };
const SEARCH_INPUT_PAD: Padding = { left: 4, right: 4 };
const SEP_MARGIN: Margin = { left: 4, right: 4 };
const TITLE_ICON_MARGIN: Margin = { left: 4 };
const CONFIG_POPUP_PAD: Padding = { top: 4, bottom: 4 };

@Component
export struct ToolBarView {
  @Prop theme: PyTheme = new PyTheme();
  @Prop runConfigs: string[] = [];
  @Prop currentRunConfig: string = '';
  @Prop running: boolean = false;
  @Prop canUndo: boolean = false;
  @Prop canRedo: boolean = false;
  @Prop searchText: string = '';
  /** 是否已经运行过（决定运行按钮显示三角还是圈圈箭头） */
  @Prop hasRun: boolean = false;
  /** MainToolbarCenter: main.toolbar.Filename —— 工具栏中部的"当前文件"微件 */
  @Prop activeFileName: string = '';
  @Prop activeFilePath: string = '';
  /** 点中间文件微件 → Index 弹出打开的编辑器列表（FilenameToolbarWidgetAction 的 popup） */
  onActiveFileClick: () => void = () => {};
  /** 运行配置选择器的 hover 态（RunWidget.hoverBackground） */
  @State configHover: boolean = false;
  /** ⋮（MoreRunToolbarActions）弹层 */
  @State moreOpen: boolean = false;
  /** 选择器 / ⋮ 的实际横向位置（由 onAreaChange 记录），弹层据此展开 */
  @State selX: number = 0;
  @State moreX: number = 0;
  /** 工具栏自身宽度（onAreaChange 记录），弹层按右缘对齐 */
  @State barW: number = 1120;

  /** 运行配置下拉是否展开 */
  @State configOpen: boolean = false;
  /** hover 中的运行配置名 */
  @State hoverConfig: string = '';
  /** hover 中的工具按钮 key */
  @State hoverBtn: string = '';

  onToolbarAction: (action: string) => void = () => {};
  onRunConfigChange: (name: string) => void = () => {};
  onSearchChange: (text: string) => void = () => {};
  onSearchSubmit: (text: string) => void = () => {};

  /** 受控输入框控制器；普通成员，不参与状态观察 */
  private searchController: TextInputController = new TextInputController();

  private iconColorOf(key: string): string {
    // 运行：常态绿描边（图标自带 green-90），运行中白描边配绿底；
    // 停止：常态灰描边（RunWidget.iconColor=icon-default-stroke），运行中白描边配红底；
    // 调试：彩色图标（绿虫子），不置白
    if (key === BTN_STOP) {
      return this.running ? '#FFFFFF' : this.theme.textSecondary;
    }
    if (key === BTN_RUN) {
      return this.running ? '#FFFFFF' : this.theme.textPrimary;
    }
    if (key === BTN_UNDO && !this.canUndo) {
      return this.theme.textDisabled;
    }
    if (key === BTN_REDO && !this.canRedo) {
      return this.theme.textDisabled;
    }
    if (key === BTN_STOP) {
      return this.running ? this.theme.error : this.theme.textDisabled;
    }
    if (key === BTN_RUN) {
      return this.running ? this.theme.textDisabled : this.theme.success;
    }
    // PyCharm 同款语义：调试是绿色、停止是红色（运行中才亮）
    if (key === BTN_DEBUG) {
      return this.running ? this.theme.textDisabled : this.theme.success;
    }
    if (key === BTN_STOP) {
      return this.running ? this.theme.error : this.theme.textDisabled;
    }
    return this.theme.textSecondary;
  }

  private isEnabled(key: string): boolean {
    if (key === BTN_UNDO) {
      return this.canUndo;
    }
    if (key === BTN_REDO) {
      return this.canRedo;
    }
    if (key === BTN_STOP) {
      return this.running;
    }
    if (key === BTN_RUN) {
      return !this.running;
    }
    return true;
  }

  private btnBg(key: string, enabled: boolean): ResourceColor {
    // ManyIslandsDark 的 RunWidget：常态**无底色**（运行图标是 green-90 描边）；
    // 只有"运行中"才出现底色：runningBackground=accent-success-bg、stopBackground=accent-error-bg
    // （主题里 accent-error-bg=red-80，darcula 主题给的同义值是 #c94f4f）
    if (key === BTN_RUN) {
      // 运行按钮 = **填充的绿色圆角方块**（用户要求：填充圆角方块），里面是白描边箭头。
      // RunWidget.runningBackground = accent-success-bg；色值取实机截图测得 #3E9B57
      return this.running ? '#3E9B57' : '#3E9B57';
    }
    if (key === BTN_STOP) {
      // PyCharm 的停止按钮始终是红底圆角块（RunWidget.stopBackground = toolbar-stop-bg = accent-error-bg = red-80）
      return this.running ? '#C94F4F' : '#7E3A3A';
    }
    if (!enabled) {
      return Color.Transparent;
    }
    return this.hoverBtn === key ? this.theme.hoverBg : Color.Transparent;
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

  /** 工具按钮的无障碍名称（同时让工具栏图标出现在 dumpLayout 里，便于自动化定位） */
  private btnLabel(key: string): string {
    if (key === BTN_RUN) {
      return '运行';
    }
    if (key === BTN_DEBUG) {
      return '调试';
    }
    if (key === BTN_STOP) {
      return '停止';
    }
    if (key === BTN_MORE) {
      return '更多运行操作';
    }
    if (key === BTN_AI) {
      return 'AI 助手';
    }
    if (key === BTN_SEARCH) {
      return '随处搜索';
    }
    return '设置';
  }

  /** 通用工具按钮：图标 + 点击热区 + hover 高亮 */
  @Builder
  toolButton(key: string, action: string) {
    Stack() {
      if (key === BTN_RUN) {
        // 三个按钮图标统一 16vp 基准，避免"虫子比例不一致"
        IconRun({ iconSize: 16, color: this.iconColorOf(key), idleGreen: !this.running, rerun: this.hasRun })
      } else if (key === BTN_DEBUG) {
        IconDebug({ iconSize: 16, color: '#4E9D6C' })
      } else if (key === BTN_STOP) {
        IconStop({ iconSize: 16, color: this.iconColorOf(key) })
      } else if (key === BTN_PLUS) {
        IconPlus({ iconSize: 16, color: this.iconColorOf(key) })
      } else if (key === BTN_FOLDER) {
        IconFolder({ iconSize: 16, color: this.iconColorOf(key) })
      } else if (key === BTN_SAVE) {
        IconSave({ iconSize: 16, color: this.iconColorOf(key) })
      } else if (key === BTN_UNDO) {
        IconUndo({ iconSize: 16, color: this.iconColorOf(key) })
      } else if (key === BTN_REDO) {
        IconRedo({ iconSize: 16, color: this.iconColorOf(key) })
      } else if (key === BTN_AI) {
        IconAsset({ iconSize: 16, file: 'icons/twAi20.svg' })
      } else if (key === BTN_MORE) {
        IconMoreVertical({ iconSize: 16, color: this.iconColorOf(key) })
      } else if (key === BTN_SEARCH) {
        IconSearch({ iconSize: 16, color: this.iconColorOf(key) })
      } else {
        IconSettings({ iconSize: 16, color: this.iconColorOf(key) })
      }
    }
    .width(TOOL_BTN_SIZE)
    .height(TOOL_BTN_SIZE)
    .accessibilityText(this.btnLabel(key))
    // 组件 id：dumpLayout 会导出 id 字段 → 自动化可用 id 精确定位工具栏按钮（图标节点不带 text）
    .id(`tb-${key}`)
    .backgroundColor(this.btnBg(key, this.isEnabled(key)))
    // 主题实测：MainToolbar.Button.arc.compact = 8；Icon.insets = 6,5,4,5（26 = 16 图标 + 5×2）
    .padding({ top: 6, left: 5, bottom: 4, right: 5 })
    .borderRadius(8)
    .onHover((isHover: boolean) => {
      this.hoverBtn = isHover ? key : '';
    })
    .onClick(() => {
      if (this.isEnabled(key)) {
        this.onToolbarAction(action);
      }
    })
  }

  /** 竖线分隔 */
  @Builder
  sep() {
    Divider()
      .vertical(true)                     // divider.d.ts:69
      .strokeWidth(1)                     // divider.d.ts:103
      .color(this.theme.separator)        // divider.d.ts:84
      .height(18)
      .margin(SEP_MARGIN)
  }

  /** 运行配置下拉弹层（用 Column，避免 Scroll 在绝对定位子节点里的限制） */
  @Builder
  configPopup() {
    Column() {
      // 1) 现有运行配置（当前项打勾）
      ForEach(this.runConfigs, (name: string, index: number) => {
        Row() {
          Text(this.currentRunConfig === name ? '✓' : ' ')
            .fontSize(11)
            .width(14)
            .fontColor(this.theme.accent)
          Text(name)
            .fontSize(12.5)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow(ELLIPSIS)
        }
        .width('100%')
        .height(26)
        .padding(CONFIG_ITEM_PAD)
        .backgroundColor(this.hoverConfig === name ? this.theme.menuHoverBg : Color.Transparent)
        .onHover((isHover: boolean) => {
          this.hoverConfig = isHover ? name : '';
        })
        .onClick(() => {
          this.configOpen = false;
          this.hoverConfig = '';
          this.onRunConfigChange(name);
        })
      }, (name: string, index: number) => `${index}-${name}`)
      // 2) ExecutionBundle: run.configurations.popup.existing.configurations.separator.text = Run Configurations
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      Text('运行配置')
        .fontSize(11)
        .fontColor(this.theme.textDisabled)
        .width('100%')
        .padding({ left: 10, bottom: 2 })
      // 3) ExecutionBundle: run.configurations.popup.edit.run.config.and.run.current.file = Run with Parameters…
      this.moreRunItem('使用形参运行…', 'run.more.args', '')
      this.moreRunItem('编辑配置…', 'run.more', '')
    }
    .width(240)
    // 绝对定位的 Column 在 ArkUI 里会按首个子节点测高 → 必须显式给高，背景才包得住所有行
    .height(160)
    // 定位写在弹层自己身上：外层再无尺寸包壳 → 背景能完整包住所有行
    .position({ x: Math.max(8, this.barW - 311), y: TOOLBAR_HEIGHT })
    .zIndex(20)
    .constraintSize(CONFIG_POPUP_SIZE)
    .padding(CONFIG_POPUP_PAD)
    .backgroundColor(this.theme.popupBg)
    .borderWidth(1)
    .borderColor(this.theme.border)
    .borderStyle(BorderStyle.Solid)
    .borderRadius(4)
    .shadow(this.popupShadow())
  }

  /** ⋮ 弹层里的一行 */
  @Builder
  moreRunItem(label: string, action: string, shortcut: string) {
    Row() {
      Text(label)
        .fontSize(12.5)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
        .maxLines(1)
      if (shortcut.length > 0) {
        Text(shortcut).fontSize(11).fontColor(this.theme.textSecondary)
      }
    }
    .width('100%')
    .height(26)
    .padding({ left: 10, right: 10 })
    .onClick(() => {
      this.moreOpen = false;
      this.onToolbarAction(action);
    })
  }

  /** 弹层横向定位用：拿不到窗口宽度时退回一个稳定值 */
  private windowWidthOf(): number {
    return 1120;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ── 第一层：工具栏本体 ────────────────────────────
      Row() {
        // 依据 PyCharm 的 MainToolbarNewUI 三段布局（PlatformActions.xml:1072-1087）：
        //   MainToolbarLeft   = main.toolbar.Project（项目微件，在 MenuBarView 里）
        //   MainToolbarCenter = main.toolbar.Filename（当前文件微件，页面中部）
        //   MainToolbarRight  = NewUiRunWidget(anchor=first) + SearchEverywhere + SettingsEntryPoint
        Blank().layoutWeight(1)

        // ── MainToolbarCenter: main.toolbar.Filename ──
        // 依据 MacToolbarFrameHeader.isCompactHeader（判据 mainToolbarHasNoActions）：
        // 该"当前文件"微件**只在主工具栏没有任何动作的紧凑头部**才显示；
        // 主工具栏有动作时（我们的情况）不显示文件名 —— 之前显示 main.py 是错的。
        Blank().layoutWeight(1)

        // ── 运行微件（NewUiRunWidget）：配置下拉 + 运行/调试/停止 ──
        // ── 运行配置下拉 ────────────────────────────────
        // 选择器与它自己的弹层放在同一个 Stack 里 → 弹层贴着选择器下方展开，
        // 不再用固定坐标（之前 CONFIG_POPUP_POS 写死 x=8，弹层跑到工具栏最左边）
        Stack({ alignContent: Alignment.TopStart }) {
        Row() {
          Text(this.currentRunConfig.length > 0 ? this.currentRunConfig : '未选择配置')
            .fontSize(12)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textPrimary)
            .maxLines(1)
            .textOverflow(ELLIPSIS)
          IconChevronDown({ iconSize: 14, color: this.theme.textSecondary })
            .margin(TITLE_ICON_MARGIN)
        }
        .constraintSize(CONFIG_BTN_MIN)
        .height(24)
        .padding(CONFIG_BTN_PAD)
        // PyCharm 主题 ManyIslandsDarcula.theme.json 的 RunWidget：默认无底色，
        // 仅 hoverBackground=#00000019 / pressedBackground=#00000028（即"无框，选中才有浅色框"）
        .backgroundColor(this.configOpen ? '#00000028'
          : (this.configHover ? '#00000019' : Color.Transparent))
        .borderRadius(4)
        .onHover((isHover: boolean) => {
          this.configHover = isHover;
        })
        .onClick(() => {
          this.configOpen = !this.configOpen;
          this.moreOpen = false;
        })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.selX = 0;   // 兜底，下方按 barW 右对齐计算
        })
        }
        .zIndex(15)

        this.toolButton(BTN_RUN, 'run.run')
        this.toolButton(BTN_DEBUG, 'run.debug')
        this.toolButton(BTN_STOP, 'run.stop')
        // RunToolbarMainActionGroup 里的 MoreRunToolbarActions（⋮）
        Stack() {
          this.toolButton(BTN_MORE, 'run.more')
        }
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.moreX = Number(newValue.position.x) - 180;
        })
        .onClick(() => {
          this.moreOpen = !this.moreOpen;
          this.configOpen = false;
        })

        Blank().width(8)

        // ── 按 MainToolbarRight 的 add-to-group 锚点排序 ──
        //   NewUiRunWidget  anchor=first      → 运行微件在最左
        //   AIAssistantHub  anchor=before SearchEverywhere
        //   SettingsEntryPoint 在 SearchEverywhere 之后、试用状态之前
        this.toolButton(BTN_AI, 'view.recentFiles')
        // MainToolbarRight: SearchEverywhere（随处搜索）
        this.toolButton(BTN_SEARCH, 'edit.searchEverywhere')
        this.toolButton(BTN_SETTINGS, 'tools.settings')
      }
      .width('100%')
      .height(TOOLBAR_HEIGHT)
      .padding(TOOLBAR_PAD)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.barW = Number(newValue.width);
      })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(Color.Transparent)
      // EdgeWidths 是 declare type（component/units.d.ts:699），不是 class
      .borderWidth(TOOLBAR_EDGE)
      // 同上：MainToolbar.borderColor = transparent
      .borderColor(Color.Transparent)
      .borderStyle(BorderStyle.Solid)

      // ── 第二层：点击外部关闭的遮罩（与工具栏本体位置重合） ──
      if (this.configOpen || this.moreOpen) {
        Column()
          .width('100%')
          .height(TOOLBAR_HEIGHT)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.configOpen = false;
            this.moreOpen = false;
          })
      }

      // ── 第三层：运行配置弹层（挂在工具栏根 Stack 下，位置按选择器实际 x） ──
      if (this.configOpen) {
        Column() {
          this.configPopup()
        }
        // 右对齐：选择器右缘 ≈ 工具栏右缘 - 运行/调试/停止/⋮/AI/搜索/设置(≈250)，
        // 弹层宽 240 → x = barW - 250 - 240
        // 实测校正：弹层左缘要落在选择器左缘（选择器文本 x=2025px/810vp，弹层曾落在 619vp）
        // 二次实测：弹层左缘还需右移 40vp（1925→2025px 对齐选择器）→ 351-40=311
        .position({ x: Math.max(8, this.barW - 311), y: TOOLBAR_HEIGHT })
        .zIndex(20)
      }

      // ── 第四层：⋮ = MoreRunToolbarActions（PyCharm ExecutionBundle 的
      //    run.configurations.popup.*：使用形参运行… / 运行配置 分组） ──
      if (this.moreOpen) {
        Column() {
          this.moreRunItem('运行', 'run.run', '')
          this.moreRunItem('使用形参运行…', 'run.more.args', '')
          this.moreRunItem('调试', 'run.debug', '')
          Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
          Text('运行配置')
            .fontSize(11)
            .fontColor(this.theme.textDisabled)
            .width('100%')
            .padding({ left: 10, bottom: 2 })
          this.moreRunItem('编辑配置…', 'run.more', '')
          this.moreRunItem('停止', 'run.stop', '')
        }
        .width(200)
        .height(206)
        .padding({ top: 4, bottom: 4 })
        .backgroundColor(this.theme.popupBg)
        .border({ width: 1, color: this.theme.separator })
        .borderRadius(6)
        .shadow(this.popupShadow())
        // ⋮ 按钮实测在 ~1014vp，弹层宽 200 → 左缘取 924vp
        // ⋮ 实测在 ~1007vp，弹层宽 200 → 左缘目标 ~907vp → 偏移 200+51=251
        .position({ x: Math.max(8, this.barW - 251), y: TOOLBAR_HEIGHT + 2 })
        .zIndex(20)
      }
    }
    .width('100%')
    .height(TOOLBAR_HEIGHT)
    .backgroundColor(Color.Transparent)
  }
}
