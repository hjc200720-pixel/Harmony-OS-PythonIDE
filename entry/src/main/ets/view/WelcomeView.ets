/**
 * WelcomeView —— 欢迎页（PyCharm New UI 结构）
 *
 * 布局对照 PyCharm 的欢迎屏：
 *   左侧固定宽度导航（项目 / 自定义 / 插件 / 学习） + 右侧内容区
 *   内容区：大标题 → 操作入口 → 「最近项目」列表（图标 + 工程名 + 灰色路径）
 * 我们的导航项对应真实功能：项目（最近工程）/ 自定义（主题与设置）/ 文档 / 关于。
 */
import { PyTheme, PyFont } from '../common/Theme';
import { RuntimeStatus } from '../model/Models';
import { IconFolder, IconFileText, IconSettings, IconPython, IconPlus } from './IdeIcons';

const NAV_WIDTH: number = 196;
const RECENT_ROW_HEIGHT: number = 46;
const RECENT_MAX_HEIGHT: number = 280;
const ACTION_CHIP_PAD: Padding = { left: 14, right: 14, top: 7, bottom: 7 };
const ACTION_CHIP_MARGIN: Margin = { right: 10 };
const NAV_ITEM_PAD: Padding = { left: 12, right: 8 };
const CONTENT_PAD: Padding = { left: 36, right: 36, top: 28, bottom: 20 };

@Component
export struct WelcomeView {
  @Prop theme: PyTheme = new PyTheme();
  @Prop recentProjects: string[] = [];
  @Prop runtime: RuntimeStatus = new RuntimeStatus(false, '', '', false, '');
  @Prop isLoading: boolean = false;
  /** 左侧导航当前分区 */
  @State section: string = 'projects';

  newProject: () => void = () => {
  };
  openProject: () => void = () => {
  };
  openRecent: (path: string) => void = () => {
  };
  openSettings: () => void = () => {
  };

  /** 导航项（PyCharm 欢迎屏左侧那一列） */
  @Builder
  navItem(id: string, label: string) {
    Row() {
      if (id === 'projects') {
        IconFolder({ iconSize: 16, color: this.navFg(id) })
      } else if (id === 'customize') {
        IconSettings({ iconSize: 16, color: this.navFg(id) })
      } else if (id === 'docs') {
        IconFileText({ iconSize: 16, color: this.navFg(id) })
      } else {
        IconPython({ iconSize: 16, color: this.navFg(id), colorAlt: this.theme.pythonYellow })
      }
      Text(label)
        .fontSize(13)
        .fontFamily(PyFont.ui)
        .fontColor(this.navFg(id))
        .margin({ left: 10 })
        .maxLines(1)
    }
    .width('100%')
    .height(34)
    .padding(NAV_ITEM_PAD)
    .borderRadius(4)
    .backgroundColor(this.section === id ? this.theme.hoverBg : Color.Transparent)
    .onClick(() => {
      this.section = id;
    })
  }

  private navFg(id: string): string {
    return this.section === id ? this.theme.textPrimary : this.theme.textSecondary;
  }

  /** 操作入口（PyCharm 大标题下面的那一排） */
  @Builder
  actionChip(label: string, kind: string) {
    Row() {
      if (kind === 'new') {
        IconPlus({ iconSize: 14, color: this.theme.textPrimary })
      } else if (kind === 'open') {
        IconFolder({ iconSize: 14, color: this.theme.textPrimary })
      } else {
        IconFileText({ iconSize: 14, color: this.theme.textPrimary })
      }
      Text(label)
        .fontSize(13)
        .fontFamily(PyFont.ui)
        .fontColor(this.theme.textPrimary)
        .margin({ left: 6 })
    }
    .height(32)
    .padding(ACTION_CHIP_PAD)
    .margin(ACTION_CHIP_MARGIN)
    .borderRadius(6)
    .backgroundColor(this.theme.buttonBg)
    .onHover((isHover: boolean) => {
      this.hoverChip = isHover ? kind : '';
    })
    .onClick(() => {
      if (kind === 'new') {
        this.newProject();
      } else if (kind === 'open') {
        this.openProject();
      } else {
        this.openSettings();
      }
    })
  }

  @State hoverChip: string = '';

  /** 最近项目的一行：图标 + 工程名 + 灰色路径 */
  @Builder
  recentRow(path: string) {
    Row() {
      IconFolder({ iconSize: 18, color: this.theme.textSecondary })
      Column() {
        Text(this.baseName(path))
          .fontSize(13)
          .fontFamily(PyFont.ui)
          .fontColor(this.theme.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(path)
          .fontSize(11)
          .fontFamily(PyFont.ui)
          .fontColor(this.theme.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })
    }
    .width('100%')
    .height(RECENT_ROW_HEIGHT)
    .padding({ left: 8, right: 8 })
    .borderRadius(6)
    .backgroundColor(this.hoverRecent === path ? this.theme.hoverBg : Color.Transparent)
    .onHover((isHover: boolean) => {
      this.hoverRecent = isHover ? path : '';
    })
    .onClick(() => {
      this.openRecent(path);
    })
  }

  @State hoverRecent: string = '';

  private baseName(path: string): string {
    const idx: number = path.lastIndexOf('/');
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

  build() {
    Row() {
      // ── 左侧导航（PyCharm 欢迎屏左侧那一列）──
      Column() {
        this.navItem('projects', '项目')
        this.navItem('customize', '自定义')
        this.navItem('docs', '文档')
        this.navItem('about', '关于')
      }
      .width(NAV_WIDTH)
      .height('100%')
      .padding({ left: 8, right: 8, top: 12 })
      .backgroundColor(this.theme.panelBgAlt)
      .border({ width: { right: 1 }, color: this.theme.border })

      // ── 右侧内容 ──
      Scroll() {
        Column() {
          Text(this.sectionTitle())
            .fontSize(30)
            .fontFamily(PyFont.ui)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.textPrimary)
            .width('100%')

          Text(this.sectionSubtitle())
            .fontSize(14)
            .fontFamily(PyFont.ui)
            .fontColor(this.theme.textSecondary)
            .width('100%')
            .margin({ top: 8 })

          if (this.isLoading) {
            Row() {
              LoadingProgress().width(18).height(18).color(this.theme.accent)
              Text('正在加载…')
                .fontSize(13)
                .fontFamily(PyFont.ui)
                .fontColor(this.theme.textSecondary)
                .margin({ left: 8 })
            }
            .width('100%')
            .margin({ top: 14 })
            .alignItems(VerticalAlign.Center)
          }

          if (this.section === 'projects') {
            Row() {
              this.actionChip('新建项目', 'new')
              this.actionChip('打开项目', 'open')
              this.actionChip('设置', 'settings')
            }
            .width('100%')
            .margin({ top: 22 })

            Text('最近项目')
              .fontSize(13)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textSecondary)
              .width('100%')
              .margin({ top: 26, bottom: 6 })

            if (this.recentProjects.length === 0) {
              Text('暂无最近项目')
                .fontSize(13)
                .fontFamily(PyFont.ui)
                .fontColor(this.theme.textDisabled)
                .width('100%')
                .padding({ left: 8, top: 6 })
            } else {
              Column() {
                ForEach(this.recentProjects, (path: string, index: number) => {
                  this.recentRow(path)
                }, (path: string, index: number) => `${index}-${path}`)
              }
              .width('100%')
              .constraintSize({ maxHeight: RECENT_MAX_HEIGHT })
            }
          } else if (this.section === 'customize') {
            Text('外观与行为都在设置里：主题（深色 Darcula / 浅色 Light）、字号、行号、'
              + '当前行高亮、缩进、自动保存、快捷键。')
              .fontSize(13)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textSecondary)
              .width('100%')
              .margin({ top: 22 })
            Row() {
              this.actionChip('打开设置', 'settings')
            }
            .width('100%')
            .margin({ top: 14 })
          } else if (this.section === 'docs') {
            Text('F5 运行当前文件 · Shift+F5 停止 · 行号槽点击设断点 · 工具栏「调试」进入调试会话 · '
              + 'Ctrl+Alt+S 打开设置 · Ctrl+Alt+T 切换主题 · Ctrl+G 转到行。')
              .fontSize(13)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textSecondary)
              .width('100%')
              .margin({ top: 22 })
          } else {
            Text('鸿蒙 Python IDE 1.0.0')
              .fontSize(13)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textPrimary)
              .width('100%')
              .margin({ top: 22 })
            Text('内嵌 CPython 3.12.10（arm64-v8a / x86_64 双 ABI）· 随包标准库与 pip · '
              + '编辑器/调试器/控制台/终端/工程管理')
              .fontSize(13)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textSecondary)
              .width('100%')
              .margin({ top: 8 })
            Text('第三方组件与许可：docs/LICENSES.md')
              .fontSize(12)
              .fontFamily(PyFont.ui)
              .fontColor(this.theme.textSecondary)
              .width('100%')
              .margin({ top: 8 })
          }

          // ── 底部：运行时状态（PyCharm 没有这一行，但对我们有用，做成小字）──
          Row() {
            Circle({ width: 7, height: 7 })
              .fill(this.runtime.ready ? this.theme.success : this.theme.error)
            Text(this.runtime.ready
              ? `CPython ${this.runtime.version}（${this.runtime.abi}）已就绪`
              : 'Python 运行时未就绪')
              .fontSize(12)
              .fontFamily(PyFont.ui)
              .fontColor(this.runtime.ready ? this.theme.textSecondary : this.theme.error)
              .margin({ left: 8 })
          }
          .width('100%')
          .margin({ top: 28 })
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(CONTENT_PAD)
      }
      .layoutWeight(1)
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.windowBg)
  }

  private sectionTitle(): string {
    if (this.section === 'projects') {
      return '欢迎使用 鸿蒙 Python IDE';
    }
    if (this.section === 'customize') {
      return '自定义';
    }
    if (this.section === 'docs') {
      return '快速上手';
    }
    return '关于';
  }

  private sectionSubtitle(): string {
    if (this.section === 'projects') {
      return '面向鸿蒙平板与鸿蒙 PC 的 Python 集成开发环境';
    }
    if (this.section === 'customize') {
      return '主题、编辑器与运行行为';
    }
    if (this.section === 'docs') {
      return '常用操作与快捷键';
    }
    return '版本与致谢';
  }
}
