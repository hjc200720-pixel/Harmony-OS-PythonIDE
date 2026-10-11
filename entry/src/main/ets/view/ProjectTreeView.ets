/**
 * ProjectTreeView —— PyCharm New UI 风格左侧「项目」工具窗
 *
 * 数据流：父组件已经把树按展开状态扁平化成 nodes 数组（按显示顺序），
 * 本组件只做「顺序渲染 + 事件回抛」，绝不自己递归、绝不自己改树。
 * 注意 rows 的行内右键菜单挂在 ProjectTreeRow（每个节点一个实例）上，
 * 这样「当前是哪个节点」是行内 @State，不存在共享状态读到旧值的问题。
 *
 * 右键菜单实现说明（本文件唯一有取舍的地方）：
 *  ArkUI 的 bindContextMenu(content: CustomBuilder, responseType: ResponseType)
 *  在 items 上绑定时，CustomBuilder 无法接收「当前是哪一个节点」，只能读组件状态；
 *  而右击触发与状态刷新在同一帧，读状态有拿到旧值的风险。
 *  因此这里改成「长按 → 设置 menuShown → 弹出由 isShow 驱动的 bindMenu」：
 *  - bindMenu(isShow, content, options) 出处：component/common.d.ts:21480
 *  - bindContextMenu(content, responseType, options) 出处：component/common.d.ts:21495
 *  - ResponseType.RightClick 出处：component/enums.d.ts:2989
 *  - LongPressGesture(...).onAction 出处：component/gesture.d.ts:1453 / :1464（const: :2040）
 *
 * API 出处（HarmonyOS 26.0.0 / API 26 SDK）：
 *  - List(options?: ListOptions) + scroller : component/list.d.ts:805 / :695
 *  - List.divider(ListDividerOptions | null) : component/list.d.ts:1135，ListDividerOptions :823
 *  - List.scrollBar(BarState)                : component/list.d.ts:1014
 *  - ListItem(value?: ListItemOptions)       : component/list_item.d.ts:473，ListItemOptions :427
 *  - Text.fontSize / fontColor / fontFamily / maxLines / textOverflow / textAlign
 *      : component/text.d.ts:146 / :132 / :528 / :545 / :511 / :354
 *  - TextOverflowOptions 接口                : component/text.d.ts:35
 *  - TextInput(value?: TextInputOptions) + onChange / onFocus / onBlur
 *      : component/text_input.d.ts:832 / :1107 / common.d.ts:18777 / :18788
 *  - Divider.vertical / color / strokeWidth  : component/divider.d.ts:69 / :84 / :103
 *  - CommonMethod.onHover / onClick          : component/common.d.ts:18556 / :18506
 *  - CommonMethod.position(Position)         : component/common.d.ts:20390
 *  - MenuOptions 接口（bindMenu 的 options）  : component/common.d.ts:15637（extends ContextMenuOptions :14963）
 *  - Placement.BottomLeft                    : component/enums.d.ts:3126
 *  - CommonMethod.padding / margin / borderWidth / borderColor / borderStyle
 *      : component/common.d.ts:17517 / :17573 / :18218 / :18232 / :18203
 *  - EdgeWidths / Padding / Margin 都是 declare type（不是 class）
 *      : component/units.d.ts:699 / :414 / :651
 *  - BorderStyle.Solid                       : component/enums.d.ts:443
 *  - ForEach(arr, itemGenerator, keyGenerator?) : component/for_each.d.ts:85
 *
 * ArkTS 严格模式：union 型属性参数（padding/margin/borderWidth/position）以及
 * bindMenu 的 options 一律先声明显式类型再传入，避免 arkts-no-untyped-obj-literals。
 */

import { PyTheme, PyFont } from '../common/Theme';
import { FileNode, isExcludedDirName } from '../model/Models';
import {
  FileTypeIcon, IconChevronDown, IconChevronRight, IconPlus, IconRefresh,
  IconSearch, IconClose, IconEdit, IconTrash, IconFolder, IconFileText,
  IconCollapseAll, IconChevronsUp, IconChevronsDown, IconMoreVertical, IconExpandAll, IconLocate
} from './IdeIcons';

/** 工具窗标题栏高度 */
const TITLE_BAR_HEIGHT: number = 28;
/** 树行高（PyCharm 紧凑行高 24vp） */
const ROW_HEIGHT: number = 24;
/** 树的基准缩进 */
const ROW_BASE_INDENT: number = 12;
/** 每一层深度的额外缩进 */
const ROW_DEPTH_STEP: number = 14;
/** 小图标尺寸 */
const SMALL_ICON: number = 14;
/** 上下文菜单项行高 */
const CTX_ITEM_HEIGHT: number = 26;
/** 上下文菜单宽 */
const CTX_WIDTH: number = 170;

/** 上下文菜单动作 id（与回调一一对应） */
const CTX_NEW_FILE: string = 'ctx.newFile';
const CTX_NEW_FOLDER: string = 'ctx.newFolder';
const CTX_RENAME: string = 'ctx.rename';
const CTX_DELETE: string = 'ctx.delete';
const CTX_REFRESH: string = 'ctx.refresh';
// 依据 PyCharm ProjectViewPopupMenu：编辑源 / 剪贴板 / 重构 / 运行 / 重新加载
const CTX_EDIT_SOURCE: string = 'ctx.editSource';
const CTX_COPY_PATH: string = 'ctx.copyPath';
const CTX_CUT: string = 'ctx.cut';
const CTX_COPY: string = 'ctx.copy';
const CTX_PASTE: string = 'ctx.paste';
const CTX_REFACTOR: string = 'ctx.refactor';
const CTX_RUN: string = 'ctx.run';

// ── 显式类型的布局常量 ──────────────────────────────────────
const ELLIPSIS: TextOverflowOptions = { overflow: TextOverflow.Ellipsis };
const TITLE_BAR_PAD: Padding = { left: 10, right: 4 };
const TITLE_BAR_EDGE: EdgeWidths = { top: 0, right: 0, bottom: 1, left: 0 };
const FILTER_ROW_PAD: Padding = { left: 8, right: 8, top: 4, bottom: 4 };
const FILTER_INPUT_PAD: Padding = { left: 6, right: 6 };
const ROW_PAD: Padding = { right: 6 };
const NAME_MARGIN: Margin = { left: 6 };
const CTX_ITEM_PAD: Padding = { left: 10, right: 10 };
const CTX_MENU_PAD: Padding = { top: 4, bottom: 4 };
const CTX_DIVIDER_MARGIN: Margin = { top: 4, bottom: 4 };
const CTX_LABEL_MARGIN: Margin = { left: 8 };
const EMPTY_HINT_PAD: Padding = { left: 12, right: 12 };

/**
 * 单行节点。独立成组件是为了让「右键菜单是否展开」变成行内 @State，
 * 避免用全局共享状态 + bindContextMenu 时读到旧值。
 */
@Component
struct ProjectTreeRow {
  @Prop theme: PyTheme = new PyTheme();
  @Prop node: FileNode = new FileNode('', '', false, 0);
  @Prop selected: boolean = false;
  @State hovered: boolean = false;
  /** 该行的上下文菜单是否展开 */
  @State menuShown: boolean = false;
  /** 行为开关（来自 Index，见 ProjectTreeView 里的说明） */
  @Prop projectIconFile: string = '';
  @Prop singleClickOpen: boolean = true;
  @Prop openDirsSingle: boolean = true;

  openFile: (path: string, name: string, preview: boolean) => void = () => {};
  toggleDir: (node: FileNode) => void = () => {};
  /** 只选中不打开（一键打开文件/目录 关闭时的第一次点击） */
  onSelect: (path: string) => void = () => {};
  refreshDir: (path: string) => void = () => {};
  newFile: (dirPath: string) => void = () => {};
  newFolder: (dirPath: string) => void = () => {};
  renamePath: (path: string) => void = () => {};
  deletePath: (path: string) => void = () => {};
  /** 复制路径 / 运行 / 未实现项的说明（PyCharm ProjectViewPopupMenu 里的项） */
  copyPath: (path: string) => void = () => {};
  runPath: (path: string) => void = () => {};
  onTreeInfo: (kind: string) => void = () => {};
  /** 长按/右键：把菜单交给页面在页面级渲染（bindMenu 在部分版本不弹） */
  onRowMenu: (path: string, x: number, y: number) => void = () => {};

  /** 新建/删除/重命名的作用目录：目录用自身路径，文件用父目录 */
  private targetDir(): string {
    if (this.node.isDir) {
      return this.node.path;
    }
    const idx: number = this.node.path.lastIndexOf('/');
    return idx > 0 ? this.node.path.substring(0, idx) : this.node.path;
  }

  /** 缩进引导线的层数（等于节点深度） */
  private indentGuides(): number[] {
    const out: number[] = [];
    for (let i = 0; i < this.node.depth; i++) {
      out.push(i);
    }
    return out;
  }

  private rowBg(): ResourceColor {
    if (this.selected) {
      return this.theme.selectedBg;
    }
    return this.hovered ? this.theme.hoverBg : Color.Transparent;
  }

  private rowFg(): string {
    if (this.selected) {
      return this.theme.textPrimary;
    }
    if (this.node.isDir) {
      return this.theme.textPrimary;
    }
    return this.node.name.toLowerCase().endsWith('.py')
      ? this.theme.textPrimary
      : this.theme.textSecondary;
  }

  /**
   * 行点击，按 PyCharm 的两个开关分流：
   *   ProjectView.AutoscrollToSource（一键打开文件）关 → 单击只选中，再次点击/双击才打开
   *   ProjectView.OpenDirectoriesWithSingleClick（一键打开目录）关 → 目录同样先选中再展开
   */
  private onRowClick(): void {
    if (this.node.isDir) {
      if (!this.openDirsSingle && !this.selected) {
        this.onSelect(this.node.path);
        return;
      }
      this.toggleDir(this.node);
      return;
    }
    if (!this.singleClickOpen && !this.selected) {
      this.onSelect(this.node.path);
      return;
    }
    // 第一次点击 → 预览标签；再点同一行 → 钉住
    this.openFile(this.node.path, this.node.name, !this.selected);
  }

  /** bindMenu 的 options；显式类型避免 arkts-no-untyped-obj-literals */
  private ctxMenuOptions(): MenuOptions {
    const opt: MenuOptions = {
      placement: Placement.BottomLeft,
      enableArrow: false,
      onDisappear: () => {
        this.menuShown = false;
      }
    };
    return opt;
  }

  /** 上下文菜单项：iconKind 用字符串区分图标，避免 @Builder 传函数 */
  @Builder
  ctxItem(action: string, label: string, iconKind: string) {
    Row() {
      if (iconKind === 'file') {
        IconFileText({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
      } else if (iconKind === 'folder') {
        IconFolder({ iconSize: SMALL_ICON, color: this.theme.funcName })
      } else if (iconKind === 'edit') {
        IconEdit({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
      } else {
        IconTrash({ iconSize: SMALL_ICON, color: this.theme.error })
      }
      Text(label)
        .fontSize(12)
        .fontFamily(PyFont.ui)
        .fontColor(iconKind === 'trash' ? this.theme.error : this.theme.textPrimary)
        .margin(CTX_LABEL_MARGIN)
        .maxLines(1)
    }
    .width('100%')
    .height(CTX_ITEM_HEIGHT)
    .padding(CTX_ITEM_PAD)
    .onClick(() => {
      this.menuShown = false;
      if (action === CTX_NEW_FILE) {
        this.newFile(this.targetDir());
      } else if (action === CTX_NEW_FOLDER) {
        this.newFolder(this.targetDir());
      } else if (action === CTX_EDIT_SOURCE) {
        // 菜单里显式打开 = 直接钉住，不走预览
        this.openFile(this.node.path, this.node.name, false);
      } else if (action === CTX_COPY_PATH) {
        this.copyPath(this.node.path);
      } else if (action === CTX_RUN) {
        this.runPath(this.node.path);
      } else if (action === CTX_RENAME) {
        this.renamePath(this.node.path);
      } else if (action === CTX_DELETE) {
        this.deletePath(this.node.path);
      } else if (action === CTX_CUT || action === CTX_COPY || action === CTX_PASTE
        || action === CTX_REFACTOR) {
        this.onTreeInfo(action);
      } else {
        this.refreshDir(this.node.isDir ? this.node.path : this.targetDir());
      }
    })
  }

  /** 上下文菜单内容 */
  @Builder
  ctxMenu() {
    Column() {
      this.ctxItem(CTX_NEW_FILE, '新建文件', 'file')
      this.ctxItem(CTX_NEW_FOLDER, '新建文件夹', 'folder')
      Divider()
        .vertical(false)                   // divider.d.ts:69
        .strokeWidth(1)                    // divider.d.ts:103
        .color(this.theme.separator)       // divider.d.ts:84
        .margin(CTX_DIVIDER_MARGIN)
      // 依据 ProjectViewPopupMenu：编辑源 / 剪切(_T) 复制(_C) 复制路径(_O) 粘贴(_P)
      this.ctxItem(CTX_EDIT_SOURCE, '编辑源', 'edit')
      this.ctxItem(CTX_CUT, '剪切(_T)', 'edit')
      this.ctxItem(CTX_COPY, '复制(_C)', 'edit')
      this.ctxItem(CTX_COPY_PATH, '复制路径(_O)', 'edit')
      this.ctxItem(CTX_PASTE, '粘贴(_P)', 'edit')
      Divider()
        .vertical(false)
        .strokeWidth(1)
        .color(this.theme.separator)
        .margin(CTX_DIVIDER_MARGIN)
      // 依据 ProjectViewPopupMenuRefactoringGroup：重构… / 重命名(_R)…
      this.ctxItem(CTX_REFACTOR, '重构…', 'edit')
      this.ctxItem(CTX_RENAME, '重命名(_R)…', 'edit')
      Divider()
        .vertical(false)
        .strokeWidth(1)
        .color(this.theme.separator)
        .margin(CTX_DIVIDER_MARGIN)
      // 依据 ProjectViewPopupMenuRunGroup / CacheRecovery / ExternalToolsGroup
      this.ctxItem(CTX_RUN, '运行', 'file')
      this.ctxItem(CTX_REFRESH, '从磁盘重新加载', 'folder')
      Divider()
        .vertical(false)
        .strokeWidth(1)
        .color(this.theme.separator)
        .margin(CTX_DIVIDER_MARGIN)
      this.ctxItem(CTX_DELETE, '删除(_D)', 'trash')
    }
    .width(CTX_WIDTH)
    .padding(CTX_MENU_PAD)
    .backgroundColor(this.theme.popupBg)
  }

  build() {
    Row() {
      // 缩进：PyCharm 用竖线做缩进引导（每层一条 1vp 竖线 + 13vp 间距）
      Row() {
        Row()
          .width(ROW_BASE_INDENT)
          .height(ROW_HEIGHT)
        ForEach(this.indentGuides(), (level: number) => {
          Row()
            .width(1)
            .height(ROW_HEIGHT)
            .backgroundColor(this.theme.indentGuide)
            .margin({ right: ROW_DEPTH_STEP - 1 })
        }, (level: number) => `guide${level}`)
      }
      .height(ROW_HEIGHT)

      // 展开 / 折叠箭头（目录才有，文件用等宽占位保证对齐）
      if (this.node.isDir) {
        if (this.node.expanded) {
          IconChevronDown({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
        } else {
          IconChevronRight({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
        }
      } else {
        Row().width(SMALL_ICON).height(ROW_HEIGHT)
      }

      Row().width(4)

      // 类型图标 + 文件名
      FileTypeIcon({
        name: this.node.name,
        theme: this.theme,
        isDir: this.node.isDir,
        // 工程根行 = expui/nodes/ideaProject.svg；排除目录 = expui/nodes/excludeRoot.svg（橙色）
        isProjectRoot: this.node.depth === 0,
        excluded: this.node.isDir && isExcludedDirName(this.node.name),
        // 根行可用「设置自定义项目图标…」导入的图；合成节点用节点自带图标
        iconPath: (this.node.depth === 0 && this.projectIconFile.length > 0)
          ? this.projectIconFile : '',
        iconFileOverride: this.node.iconFile,
        iconSize: SMALL_ICON
      })

      if (this.node.depth === 0 && !this.node.synthetic) {
        // PyCharm 的工程根行是「工程名 + 灰色路径」同一行
        // （合成节点「外部库/临时文件和控制台」也是 depth 0，但它们不显示路径）
        Text(this.node.name)
          .fontSize(12)
          .fontFamily(PyFont.ui)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.rowFg())
          .maxLines(1)
          .textOverflow(ELLIPSIS)
        Text(this.node.path)
          .fontSize(11)
          .fontFamily(PyFont.ui)
          .fontColor(this.theme.textDisabled)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow(ELLIPSIS)
          .margin({ left: 8 })
      } else {
        Text(this.node.name)
          .fontSize(12)
          .fontFamily(PyFont.ui)
          .fontColor(this.rowFg())
          .margin(NAME_MARGIN)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow(ELLIPSIS)
      }
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding(ROW_PAD)
    .backgroundColor(this.rowBg())
    .alignItems(VerticalAlign.Center)
    .onHover((isHover: boolean) => {          // common.d.ts:18556
      this.hovered = isHover;
    })
    .onClick(() => {                          // common.d.ts:18506
      this.onRowClick();
    })
    // PC：鼠标右键等同长按（左面板原点约 66,80）
    .onMouse((event: MouseEvent) => {
      if (event.button === MouseButton.Right) {
        this.onRowMenu(this.node.path, 66 + event.x, 80 + event.y);
      }
    })
    // 长按 = 右键等效入口；出处 gesture.d.ts:1453 / :1464
    // 在 List 里普通 gesture 会被滚动容器抢占，用 parallelGesture 才能收到长按
    .parallelGesture(
      LongPressGesture({ repeat: false, duration: 450 })
        .onAction((event: GestureEvent) => {
          // 页面级菜单：把长按位置一起上报（PyCharm 的 ProjectViewPopupMenu）
          let gx: number = 0;
          let gy: number = 0;
          if (event.fingerList.length > 0) {
            gx = event.fingerList[0].globalX;
            gy = event.fingerList[0].globalY;
          }
          this.menuShown = true;
          this.onRowMenu(this.node.path, gx, gy);
        })
    )
    // isShow 驱动的菜单；出处 common.d.ts:21480
    .bindMenu(this.menuShown, () => {
      this.ctxMenu();
    }, this.ctxMenuOptions())
  }
}

@Component
export struct ProjectTreeView {
  @Prop theme: PyTheme = new PyTheme();
  @Prop projectName: string = '';
  @Prop projectRoot: string = '';
  /** 父组件按展开状态扁平化好的可见节点（按显示顺序） */
  @Prop nodes: FileNode[] = [];
  @Prop selectedPath: string = '';
  @Prop filterText: string = '';
  /** 过滤框默认收起：PyCharm 的工具窗标题只有「项目 ⌄」，点搜索图标才出现输入框 */
  @State showFilter: boolean = false;
  /** ⋮ 菜单开关（ProjectView.ToolWindow.*Reactions） */
  @State gearShown: boolean = false;
  /** 排序方式：name / type / timeDesc / timeAsc / manual（ProjectView.Sort.Actions） */
  @State sortBy: string = 'name';
  /** 文件夹总在最前（ProjectView.FoldersAlwaysOnTop） */
  @State foldersFirst: boolean = true;
  @State gearHover: string = '';
  /** 文件详细信息 = 显示路径（ViewInplaceComments） */
  @State showDetails: boolean = false;
  /** 压缩目录（ProjectView.CompactDirectories） */
  @State compactDirs: boolean = false;
  /**
   * ProjectView.ToolWindow.Behavior.Actions（LangActions.xml:701-712）四项的行为开关，
   * 真源在 Index（因为它们影响打开文件/树选择），这里只读。
   *   previewTab      = ProjectView.OpenInPreviewTab           启用预览标签页
   *   singleClickOpen = ProjectView.AutoscrollToSource         一键打开文件
   *   openDirsSingle  = ProjectView.OpenDirectoriesWithSingleClick 一键打开目录
   *   autoscrollFromSource = ProjectView.AutoscrollFromSource  始终选择打开的文件
   */
  @Prop previewTab: boolean = true;
  @Prop singleClickOpen: boolean = true;
  @Prop openDirsSingle: boolean = true;
  @Prop autoscrollFromSource: boolean = false;
  /** ProjectView.ShowExcludedFiles / ShowScratchesAndConsoles（外观组） */
  @Prop showExcluded: boolean = false;
  @Prop showScratches: boolean = true;
  /** 自定义项目图标（WelcomeScreen.ChangeProjectIcon）；空 = 默认 ideaProject 图标 */
  @Prop projectIconFile: string = '';

  /** 过滤输入框是否获得焦点（仅用于边框高亮） */
  @State filterFocused: boolean = false;
  /** 标题栏 hover 中的按钮 key */
  @State hoverIcon: string = '';

  openFile: (path: string, name: string, preview: boolean) => void = () => {};
  toggleDir: (node: FileNode) => void = () => {};
  onSelect: (path: string) => void = () => {};
  refreshDir: (path: string) => void = () => {};
  newFile: (dirPath: string) => void = () => {};
  newFolder: (dirPath: string) => void = () => {};
  renamePath: (path: string) => void = () => {};
  deletePath: (path: string) => void = () => {};
  copyPath: (path: string) => void = () => {};
  runPath: (path: string) => void = () => {};
  onTreeInfo: (kind: string) => void = () => {};
  onRowMenu: (path: string, x: number, y: number) => void = () => {};
  onFilterChange: (text: string) => void = () => {};
  /** 工具窗标题右键（PyCharm 的 ToolWindowContextMenu） */
  onToolWindowMenu: () => void = () => {};
  /** 排序方式变化（Index 负责真正重排树） */
  onSortChange: (by: string) => void = () => {};
  /** 标题栏动作（由 Index 实现，因为树的完整结构在父组件里） */
  collapseAll: () => void = () => {};
  expandAll: () => void = () => {};
  hideWindow: () => void = () => {};
  /** 当前打开文件路径（SelectInProjectView 用） */
  @Prop activeFilePath: string = '';
  /** Index 定位完成后 +1，触发树滚动到该行 */
  @Prop @Watch('onLocateTick') locateTick: number = 0;
  /** 标题栏「定位」按钮：Index 负责展开祖先目录并选中 */
  onLocate: () => void = () => {};
  /** 齿轮菜单里会真正影响树的选项（压缩目录 / 文件夹总在前）→ 通知 Index 重建视图树 */
  onViewOption: (key: string, value: boolean) => void = () => {};
  private listScroller: Scroller = new Scroller();

  private onLocateTick(): void {
    if (this.activeFilePath.length === 0) {
      return;
    }
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].path === this.activeFilePath) {
        this.listScroller.scrollToIndex(i);
        return;
      }
    }
  }

  private iconBg(key: string): ResourceColor {
    return this.hoverIcon === key ? this.theme.hoverBg : Color.Transparent;
  }

  /** 标题栏显示的工程名：优先 projectName，没有就取 projectRoot 的最后一段 */
  private projectLabel(): string {
    if (this.projectName.length > 0) {
      return this.projectName;
    }
    const idx: number = this.projectRoot.lastIndexOf('/');
    if (idx >= 0 && idx < this.projectRoot.length - 1) {
      return this.projectRoot.substring(idx + 1);
    }
    return '';
  }

  /** List 的分隔线：本项目不需要，用与面板同色的 0 宽线关掉 */
  private listDivider(): ListDividerOptions {
    const opt: ListDividerOptions = { strokeWidth: 0, color: this.theme.panelBg };
    return opt;
  }

/** ⋮ 菜单动作：能真做的做，其余如实提示 */
  private onGearAction(key: string): void {
    this.gearShown = false;
    if (key === 'sortName' || key === 'sortType' || key === 'sortTimeDesc' || key === 'sortTimeAsc'
      || key === 'sortManual') {
      this.sortBy = key === 'sortName' ? 'name' : (key === 'sortType' ? 'type'
        : (key === 'sortTimeDesc' ? 'timeDesc' : (key === 'sortTimeAsc' ? 'timeAsc' : 'manual')));
      this.onSortChange(this.sortBy);
      return;
    }
    if (key === 'foldersFirst') {
      this.foldersFirst = !this.foldersFirst;
      // 真正生效：Index 用它决定视图树里目录是否排在文件前
      this.onViewOption('foldersFirst', this.foldersFirst);
      return;
    }
    if (key === 'details') {
      this.showDetails = !this.showDetails;
      return;
    }
    if (key === 'compact') {
      this.compactDirs = !this.compactDirs;
      // 真正生效：Index 用它压缩"只有一个子目录"的链（PyCharm Compact Middle Packages）
      this.onViewOption('compact', this.compactDirs);
      return;
    }
    // Behavior/Appearance 组：真源在 Index，这里只上报新值
    if (key === 'preview') {
      this.onViewOption('preview', !this.previewTab);
      return;
    }
    if (key === 'singleClick') {
      this.onViewOption('singleClick', !this.singleClickOpen);
      return;
    }
    if (key === 'singleDir') {
      this.onViewOption('singleDir', !this.openDirsSingle);
      return;
    }
    if (key === 'autoscroll') {
      this.onViewOption('autoscroll', !this.autoscrollFromSource);
      return;
    }
    if (key === 'excluded') {
      this.onViewOption('excluded', !this.showExcluded);
      return;
    }
    if (key === 'scratches') {
      this.onViewOption('scratches', !this.showScratches);
      return;
    }
    if (key === '过滤文件名…') {
      this.showFilter = true;
      return;
    }
    // 其余为 PyCharm 里需要语义模型/索引的项
    this.onGearUnsupported(key);
  }

  /** 未实现的 ⋮ 菜单项：如实提示（不假装实现） */
  private onGearUnsupported(key: string): void {
    // 这些项在 PyCharm 里依赖语义模型/索引，本 IDE 暂不实现（仅记录，不假装实现）
    console.info(`[PyIDE] project gear action not implemented: ${key}`);
  }

  /** 标题栏小图标按钮 */
  @Builder
  titleIcon(key: string) {
    Stack() {
      if (key === 'add') {
        IconPlus({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
      } else if (key === 'locate') {
        IconLocate({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
      } else if (key === 'expandAll') {
        IconExpandAll({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
      } else if (key === 'collapseAll') {
        IconCollapseAll({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
      } else if (key === 'chevronsUp') {
        IconChevronsUp({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
      } else if (key === 'chevronsDown') {
        IconChevronsDown({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
      } else if (key === 'more') {
        IconMoreVertical({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
      } else if (key === 'filter') {
        // 过滤文件名（PyCharm 工具窗标题的搜索图标）
        IconSearch({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
      } else if (key === 'hide') {
        // 隐藏工具窗：PyCharm 标题栏最右侧的短横
        Row()
          .width(11)
          .height(1.6)
          .borderRadius(1)
          .backgroundColor(this.theme.textSecondary)
      } else {
        IconClose({ iconSize: SMALL_ICON, color: this.theme.textSecondary })
      }
    }
    .width(20)
    .height(20)
    .margin({ left: 2, right: 2 })
    .borderRadius(4)
    .backgroundColor(this.iconBg(key))
    .onHover((isHover: boolean) => {
      this.hoverIcon = isHover ? key : '';
    })
    .onClick(() => {
      if (key === 'add') {
        this.newFile(this.projectRoot);
      } else if (key === 'locate') {
        // SelectInProjectView：定位/滚动到当前打开的文件
        this.onLocate();
      } else if (key === 'expandAll') {
        this.expandAll();
      } else if (key === 'collapseAll') {
        this.collapseAll();
      } else if (key === 'more') {
        // PyCharm：标题栏 ⋮ = 工具窗选项菜单
        this.gearShown = !this.gearShown;
      } else if (key === 'filter') {
        // 过滤框开关（PyCharm 的搜索图标）
        this.showFilter = !this.showFilter;
        if (!this.showFilter) {
          this.onFilterChange('');
        }
      } else if (key === 'hide') {
        this.hideWindow();
      } else {
        this.onFilterChange('');
      }
    })
  }

/** 标题栏 ⋮ 菜单（条目与分组取自 PyCharm 的 ProjectView.ToolWindow.Behavior/Appearance/Sort.Actions） */
  @Builder
  gearMenu() {
    Column() {
      this.gearItem('行为', true)
      // 依据 ProjectView.ToolWindow.Behavior.Actions 的顺序与文案
      this.gearToggle('启用预览标签页', 'preview', this.previewTab)
      this.gearToggle('一键打开文件', 'singleClick', this.singleClickOpen)
      this.gearToggle('一键打开目录', 'singleDir', this.openDirsSingle)
      this.gearToggle('始终选择打开的文件', 'autoscroll', this.autoscrollFromSource)
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.gearItem('外观', true)
      this.gearToggle('显示模块', 'modules', false)
      this.gearToggle('显示成员', 'members', false)
      this.gearToggle('显示排除的文件', 'excluded', this.showExcluded)
      this.gearToggle('显示可见性图标', 'visibility', false)
      this.gearToggle('显示库内容', 'library', false)
      this.gearToggle('显示临时文件和控制台', 'scratches', this.showScratches)
      this.gearToggle('文件详细信息', 'details', this.showDetails)
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.gearToggle('平展模块', 'flatModules', false)
      this.gearToggle('平展软件包', 'flatPackages', false)
      this.gearToggle('缩写限定名称', 'abbrev', false)
      this.gearToggle('隐藏空的中间软件包', 'hideEmpty', false)
      this.gearToggle('压缩目录', 'compact', this.compactDirs)
      this.gearItem('文件嵌套…', false)
      this.gearItem('自定义树视图…', false)
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.gearItem('排序方式', true)
      this.gearToggle('手动排序', 'sortManual', this.sortBy === 'manual')
      this.gearToggle('按名称排序', 'sortName', this.sortBy === 'name')
      this.gearToggle('按类型排序', 'sortType', this.sortBy === 'type')
      this.gearToggle('按修改时间排序(从新到旧)', 'sortTimeDesc', this.sortBy === 'timeDesc')
      this.gearToggle('按修改时间排序(从旧到新)', 'sortTimeAsc', this.sortBy === 'timeAsc')
      Divider().strokeWidth(1).color(this.theme.separator).margin({ top: 4, bottom: 4 })
      this.gearToggle('文件夹总在最前', 'foldersFirst', this.foldersFirst)
      this.gearItem('过滤文件名…', false)
    }
    .width(268)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.theme.popupBg)
    .border({ width: 1, color: this.theme.separator })
    .borderRadius(8)
    .position({ x: 8, y: TITLE_BAR_HEIGHT })
  }

  /** ⋮ 菜单的分组标题 */
  @Builder
  gearItem(label: string, isHeader: boolean) {
    Text(label)
      .fontSize(isHeader ? 11 : 12)
      .fontFamily(PyFont.ui)
      .fontColor(isHeader ? this.theme.textDisabled : this.theme.textPrimary)
      .width('100%')
      .padding({ left: 10, right: 10, top: isHeader ? 4 : 5, bottom: isHeader ? 2 : 5 })
      .onClick(() => {
        if (!isHeader) {
          this.gearShown = false;
          this.onGearAction(label);
        }
      })
  }

  /** ⋮ 菜单的勾选项 */
  @Builder
  gearToggle(label: string, key: string, on: boolean) {
    Row() {
      Text(on ? '✓' : ' ')
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
    .backgroundColor(this.gearHover === key ? this.theme.toolHoverBg : Color.Transparent)
    .onHover((isHover: boolean) => {
      this.gearHover = isHover ? key : '';
    })
    .onClick(() => {
      this.onGearAction(key);
    })
  }

  /** 标题栏里两个图标之间的竖分隔线（PyCharm 的 `+` 后面就有一条） */
  @Builder
  titleSeparator() {
    Row()
      .width(1)
      .height(16)
      .margin({ left: 4, right: 4 })
      .backgroundColor(this.theme.separator)
  }

  build() {
    Column() {
      // ── 工具窗标题栏 ────────────────────────────────
      Row() {
        // PyCharm 工具窗标题：亮色标题 + 折叠箭头（工程名在树的第一行，不重复出现在标题）
        Text('项目')
          // ToolWindow.Header.font.size.offset = 0 → 标题字号 = UI 12
          .fontSize(12)
          .fontFamily(PyFont.ui)
          .fontColor(this.theme.textPrimary)
          .maxLines(1)
        IconChevronDown({ iconSize: 12, color: this.theme.textSecondary })
          .margin({ left: 4 })

        Blank()

        // PyCharm 标题栏动作组：＋ │ 折叠全部 展开全部 更多 −
        // ── 按 PyCharm 文件 PlatformActions.xml 的 <group id="ProjectViewToolbar"> 还原 ──
        //   NewElement(+，cfg1.xml anchor=first) | SelectInProjectView(locate)
        //   ExpandRecursively / ExpandAll(同一图标) / CollapseAll
        this.titleIcon('add')
        this.titleSeparator()
        this.titleIcon('locate')
        this.titleIcon('expandAll')
        this.titleIcon('collapseAll')
        this.titleIcon('more')
        this.titleIcon('filter')
        this.titleIcon('hide')
      }
      .width('100%')
      .height(TITLE_BAR_HEIGHT)
      .padding(TITLE_BAR_PAD)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.theme.panelBg)
      // PC：标题栏右键 → ToolWindowContextMenu（PyCharm 同名菜单）
      .onMouse((event: MouseEvent) => {
        if (event.button === MouseButton.Right) {
          this.onToolWindowMenu();
        }
      })

      // ── 过滤输入框 ──────────────────────────────────
      Row() {
        TextInput({ placeholder: '过滤文件名', text: this.filterText })
          .layoutWeight(1)
          .height(24)
          .padding(FILTER_INPUT_PAD)
          .fontSize(12)
          .fontFamily(PyFont.ui)
          .fontColor(this.theme.textPrimary)
          .caretColor(this.theme.caret)
          .placeholderColor(this.theme.textDisabled)
          .backgroundColor(this.theme.inputBg)
          .borderWidth(1)
          .borderColor(this.filterFocused ? this.theme.inputBorderFocused : this.theme.inputBorder)
          .borderStyle(BorderStyle.Solid)
          .borderRadius(4)
          .onFocus(() => {
            this.filterFocused = true;
          })
          .onBlur(() => {
            this.filterFocused = false;
          })
          .onChange((value: string) => {       // text_input.d.ts:1107
            this.onFilterChange(value);
          })
      }
      .width('100%')
      .padding(FILTER_ROW_PAD)
      .backgroundColor(this.theme.panelBg)
      // 收起时不占高度（Visibility.None 不参与布局）
      .visibility(this.showFilter ? Visibility.Visible : Visibility.None)

      // ── 主体树 ──────────────────────────────────────
      if (this.nodes.length === 0) {
        Column() {
          Text('项目为空，右键新建文件')
            .fontSize(12)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textDisabled)
            .textAlign(TextAlign.Center)
            .padding(EMPTY_HINT_PAD)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.theme.panelBg)
      } else {
        List({ scroller: this.listScroller }) {
          ForEach(this.nodes, (node: FileNode, index: number) => {
            ListItem() {
              ProjectTreeRow({
                theme: this.theme,
                node: node,
                selected: node.path === this.selectedPath,
                projectIconFile: this.projectIconFile,
                singleClickOpen: this.singleClickOpen,
                openDirsSingle: this.openDirsSingle,
                openFile: this.openFile,
                toggleDir: this.toggleDir,
                onSelect: this.onSelect,
                refreshDir: this.refreshDir,
                newFile: this.newFile,
                newFolder: this.newFolder,
                renamePath: this.renamePath,
                deletePath: this.deletePath,
                copyPath: this.copyPath,
                runPath: this.runPath,
                onTreeInfo: this.onTreeInfo,
                onRowMenu: this.onRowMenu
              })
            }
          }, (node: FileNode, index: number) =>
            // 展开态必须进 key，否则点开文件夹后箭头图标不刷新
            `${index}-${node.path}-${node.isDir ? 1 : 0}-${node.expanded ? 1 : 0}`)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(this.theme.panelBg)
        .scrollBar(BarState.Auto)              // list.d.ts:1014
        .divider(this.listDivider())           // list.d.ts:1135
      }

      // ⋮ 菜单弹层（工具窗选项）
      // 必须挂在"面板根节点"上：它用 .position() 绝对定位、会伸出标题栏，
      // 而 ArkUI 只把触摸事件派发给父容器边界内的孩子 —— 挂在标题栏里会"看得见点不动"。
      if (this.gearShown) {
        this.gearMenu()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.panelBg)
  }
}
