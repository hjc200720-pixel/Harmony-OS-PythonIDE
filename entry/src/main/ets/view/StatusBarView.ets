/**
 * StatusBarView —— PyCharm New UI 风格底部状态栏（高 26vp，上边框 1vp）
 *
 * 左侧：当前提示 message（灰字）
 * 右侧依次：解释器 / ABI（灰字不可点）/ 光标行列 / 缩进 / 编码 / 换行符 / 主题
 *
 * API 出处（HarmonyOS 26.0.0 / API 26 SDK）：
 *  - Text(content?, TextOptions?)               : component/text.d.ts:75
 *  - Text.fontSize / fontColor / fontFamily / maxLines / textOverflow : component/text.d.ts:146 / :132 / :528 / :545 / :511
 *  - Text.layoutWeight(number | string)         : component/common.d.ts:17475
 *  - CommonMethod.height / width                : component/common.d.ts（Length，number 视为 vp）
 *  - CommonMethod.padding(Padding | Length)     : component/common.d.ts:17517（Padding 是 declare type units.d.ts:414）
 *  - CommonMethod.backgroundColor(ResourceColor) : component/common.d.ts:17653
 *  - CommonMethod.borderWidth(Length | EdgeWidths) / borderColor / borderStyle : component/common.d.ts:18218 / :18232 / :18203
 *  - EdgeWidths 是 declare type                 : component/units.d.ts:699
 *  - BorderStyle.Solid                          : component/enums.d.ts:443
 *  - CommonMethod.onHover / onClick             : component/common.d.ts:18556 / :18506
 *  - ForEach(arr, itemGenerator, keyGenerator?) : component/for_each.d.ts:85
 */

import { PyTheme, PyFont } from '../common/Theme';

/** 状态栏高度（PyCharm New UI 为 24vp） */
const STATUS_BAR_HEIGHT: number = 24;
/** 单项水平内边距 */
const ITEM_PADDING_H: number = 8;
/** 状态栏文字字号 */
// 状态栏用 PyCharm 的小字号：UI(12) − 1 = 11
const STATUS_FONT_SIZE: number = 11;

/** 状态栏可点击项：key 回调父组件，label 显示文字，clickable 决定是否可点 */
class StatusItem {
  key: string = '';
  label: string = '';
  clickable: boolean = true;

  constructor(key: string, label: string, clickable: boolean) {
    this.key = key;
    this.label = label;
    this.clickable = clickable;
  }
}

@Component
export struct StatusBarView {
  @Prop theme: PyTheme = new PyTheme();
  @Prop interpreterLabel: string = '';
  @Prop cursorLine: number = 1;
  @Prop cursorColumn: number = 1;
  @Prop tabSize: number = 4;
  @Prop encoding: string = 'UTF-8';
  @Prop eol: string = 'LF';
  @Prop themeLabel: string = 'Darcula';
  @Prop message: string = '';
  @Prop abi: string = '';
  /** 左下角的导航栏（PyCharm New UI 把面包屑放在状态栏左侧） */
  @Prop projectLabel: string = '';
  @Prop fileLabel: string = '';
  /** 文件类型段（PyCharm 显示「类型: Built-in」，此处如实反映内嵌解释器类型） */
  @Prop fileType: string = 'Built-in';
  /** VCS/工程段（沙箱内无 Git，显示工程名） */
  @Prop vcsLabel: string = '';

  /** hover 中的项 key */
  @State hoverKey: string = '';

  onStatusClick: (item: string) => void = () => {};

  private itemBg(key: string): ResourceColor {
    return this.hoverKey === key ? this.theme.statusBarHoverBg : Color.Transparent;
  }

  /**
   * 右侧项列表，顺序对齐 PyCharm New UI 实测：
   * 行列 │ VCS/工程 │ 换行符 │ 编码 │ 缩进 │ 类型 │ 解释器
   */
  private makeItems(): StatusItem[] {
    const items: StatusItem[] = [];
    items.push(new StatusItem('status.cursor', `${this.cursorLine}:${this.cursorColumn}`, true));
    items.push(new StatusItem('status.vcs', this.vcsLabel, true));
    items.push(new StatusItem('status.eol', this.eol, true));
    items.push(new StatusItem('status.encoding', this.encoding, true));
    items.push(new StatusItem('status.indent', `${this.tabSize} 个空格`, true));
    items.push(new StatusItem('status.fileType', `类型: ${this.fileType}`, false));
    items.push(new StatusItem('status.interpreter', this.interpreterLabel, true));
    return items;
  }

  /** 单个状态项 */
  @Builder
  statusItem(item: StatusItem) {
    Text(item.label)
      .fontSize(STATUS_FONT_SIZE)
      .fontFamily(PyFont.ui)
      .fontColor(item.clickable ? this.theme.textPrimary : this.theme.textDisabled)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .height(STATUS_BAR_HEIGHT)
      .padding({ left: ITEM_PADDING_H, right: ITEM_PADDING_H })
      // PyCharm 的状态项 hover 是一个小圆角底，而不是整条变色
      .borderRadius(4)
      .backgroundColor(item.clickable ? this.itemBg(item.key) : Color.Transparent)
      .onHover((isHover: boolean) => {
        if (!item.clickable) {
          return;
        }
        this.hoverKey = isHover ? item.key : '';
      })
      .onClick(() => {
        if (item.clickable) {
          this.onStatusClick(item.key);
        }
      })
  }

  build() {
    Row() {
      // ── 左侧：导航栏（面包屑）+ 临时提示 ──────────────
      Row() {
        Text(this.projectLabel.length > 0 ? this.projectLabel : '未打开工程')
          .fontSize(STATUS_FONT_SIZE)
          .fontFamily(PyFont.ui)
          .fontColor(this.theme.textSecondary)
          .maxLines(1)
        if (this.fileLabel.length > 0) {
          Text(' › ')
            .fontSize(STATUS_FONT_SIZE)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textDisabled)
          Text(this.fileLabel)
            .fontSize(STATUS_FONT_SIZE)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textPrimary)
            .maxLines(1)
        }
        if (this.message.length > 0) {
          Text(`   ${this.message}`)
            .fontSize(STATUS_FONT_SIZE)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textDisabled)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .height(STATUS_BAR_HEIGHT)
      .padding({ left: ITEM_PADDING_H, right: ITEM_PADDING_H })
      .borderRadius(4)
      .alignItems(VerticalAlign.Center)
      .layoutWeight(1)
      .onClick(() => {
        this.onStatusClick('status.gotoFile');
      })

      // ── 右侧各项（顺序对齐 PyCharm New UI）────────────
      ForEach(this.makeItems(), (item: StatusItem, index: number) => {
        this.statusItem(item)
      }, (item: StatusItem, index: number) => `${index}-${item.key}-${item.label}`)
    }
    .width('100%')
    .height(STATUS_BAR_HEIGHT)
    .alignItems(VerticalAlign.Center)
    // 透明：颜色取自根层那条 chrome 渐变，保证与顶栏/间隙是同一层
    .backgroundColor(Color.Transparent)
  }
}
