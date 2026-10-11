/**
 * IdeIcons —— 无状态矢量图标库（16×16 视口，用 ArkUI Path 绘制）
 *
 * 统一设计语言（对齐 PyCharm New UI 的图标观感，但为原创手绘路径，未复制 JetBrains 资源）：
 *  - 固定 16×16 网格，外轮廓留 1.8~2.4 的安全边距，保证缩到 11~18vp 都不糊。
 *  - 线形图标统一 stroke=1.4、round cap / round join、fill=Transparent；
 *    仅"实心语义"的图标（运行三角、停止方块、暂停双杠、Python 双色）用填充。
 *  - 颜色一律由外部传入（父组件从 PyTheme 取色），组件内只留与主题无关的中性兜底值，
 *    避免深浅主题切换时出现写死颜色。
 *  - prop 名必须是 iconSize：CustomComponent/CommonMethod 基类自带 size(value: SizeOptions)
 *    （component/common.d.ts:17358），重名会被 ArkTS 拒绝。
 *
 * API 出处（HarmonyOS 26.0.0 / API 26 SDK）：
 *  - Path 组件声明 / commands : component/path.d.ts:169 / :148
 *  - fill / stroke / strokeWidth / strokeLineCap / antiAlias : component/common.d.ts
 *  - LineCapStyle / LineJoinStyle : component/enums.d.ts
 */

import { fileIconOf } from '../common/FileIcons';
import { PyTheme } from '../common/Theme';

/** 16×16 视口基准边长，路径坐标全部按这个网格设计 */
const ICON_VIEW: number = 16;
/** 线形图标统一线宽 */
const ICON_STROKE: number = 1.4;
/** 中性兜底色（父组件一定会传 color，这里只是防御） */
const ICON_FALLBACK: string = '#DFE1E5';

// ─────────────────────────────────────────────────────────────
// 运行 / 调试类（实心语义，PyCharm 同款观感）
// ─────────────────────────────────────────────────────────────

/** 运行：实心圆角三角 ▶ */
@Component
export struct IconRun {
  @Prop iconSize: number = ICON_VIEW;
  /** 常态用 green-90 描边（RunWidget.runIconColor=icon-green-stroke）；运行中用白描边配绿底 */
  @Prop idleGreen: boolean = true;
  /** 运行配置执行过一次后，PyCharm 的运行按钮变成"重新运行"的圈圈箭头（expui/run/rerun_stroke.svg） */
  @Prop rerun: boolean = false;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    // AllIcons.Actions.Execute 的描边版：常态绿描边（green-90 #4E9D6C）/ 运行中白描边
    // （DefaultRunExecutor 引用 AllIcons.Actions.Execute；主题 RunWidget.runIconColor=icon-green-stroke）
    // 绿色圆角块上的**白描边**箭头（配彩色底才可见的资源）：
    //   未跑过 = actions/execute_stroke.svg（三角）；跑过一次 = expui/run/rerun_stroke.svg（圈圈箭头）
    Image($rawfile(this.rerun ? 'icons/rerun_stroke.svg' : 'icons/execute_stroke.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 调试：甲虫轮廓（身体 + 中缝 + 头 + 触角 + 三对足） */
@Component
export struct IconDebug {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    // 调试按钮 = **线条**虫子 + 绿色描边、无底色（expui/run/debug_stroke.svg 描边版）
    Image($rawfile('icons/debug_stroke_green.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 停止：实心圆角方块 ■ */
@Component
export struct IconStop {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    // AllIcons.Actions.Suspend 的白色描边版：actions/suspend_stroke.svg（底色由工具栏画红）
    Image($rawfile('icons/suspend_stroke.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 暂停：双竖杠（单条路径两个子路径，nonzero 填充） */
@Component
export struct IconPause {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/pause.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

// ─────────────────────────────────────────────────────────────
// 文件 / 目录类
// ─────────────────────────────────────────────────────────────

/** 目录：带前折页的文件夹轮廓 */
@Component
export struct IconFolder {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/folder.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 展开的目录：前盖向外翻 */
@Component
export struct IconFolderOpen {
  @Prop iconSize: number = ICON_VIEW;
  @Prop color: string = '';
  build() {
    // PyCharm 的目录图标（展开态由箭头表示，图标本身同 expui/nodes/folder.svg）
    IconAsset({ iconSize: this.iconSize, file: 'icons/nodeFolder.svg' })
  }
}

/** Python 源文件：折角页 + 双蛇点 */
@Component
export struct IconFilePy {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/python.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** Python 标记：单色双蛇 S 形 + 双眼（用于 .json / 配置类文件的类型标识） */
@Component
export struct IconPyMark {
  @Prop iconSize: number = ICON_VIEW;
  @Prop color: string = '';
  build() {
    // 依据 PyCharm Python 插件里的 Python 图标（expui/fileTypes/python.svg）
    IconAsset({ iconSize: this.iconSize, file: 'icons/python.svg' })
  }
}

/** 普通文本文件：折角页 + 文本行 */
@Component
export struct IconFileText {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/fileText.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

// ─────────────────────────────────────────────────────────────
// 操作类
// ─────────────────────────────────────────────────────────────

/** 搜索：放大镜 */
@Component
export struct IconSearch {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/search.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 关闭：两条交叉线 */
@Component
export struct IconClose {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/close.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 新建：加号 */
@Component
export struct IconPlus {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/add.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 保存：软盘 */
@Component
export struct IconSave {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/save.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 撤销：左弯箭头 */
@Component
export struct IconUndo {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/undo.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 重做：右弯箭头 */
@Component
export struct IconRedo {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/redo.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 刷新：带箭头的圆环 */
@Component
export struct IconRefresh {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/refresh.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 终端：窗口 + 提示符 */
@Component
export struct IconTerminal {
  @Prop iconSize: number = ICON_VIEW;
  @Prop color: string = '';
  build() {
    // 依据 PyCharm terminal.jar!icons/expui/toolwindow/terminal.svg
    IconAsset({ iconSize: this.iconSize, file: 'icons/twTerminal20.svg' })
  }
}

/** 右向折角 */
@Component
export struct IconChevronRight {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/chevronRight.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 下向折角 */
@Component
export struct IconChevronDown {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/chevronDown.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 删除：垃圾桶 */
@Component
export struct IconTrash {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/delete.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 重命名：铅笔 */
@Component
export struct IconEdit {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/edit.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 复制：两张叠放的圆角纸 */
@Component
export struct IconCopyOutline {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/copy.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 设置：齿轮（内圆 + 8 根辐条，16px 下比实心齿轮更清晰） */
@Component
export struct IconSettings {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/settings.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

// ─────────────────────────────────────────────────────────────
// 品牌类（双色）
// ─────────────────────────────────────────────────────────────

/** Python：双蛇互扣标记（color = 上/左蛇，colorAlt = 下/右蛇） */
@Component
export struct IconPython {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/python.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 折叠全部：圆圈内向的四个刻度（PyCharm 工具窗标题栏同款） */
@Component
/** 通用资源图标：按 rawfile 路径渲染（工具窗竖条等需要动态图标的地方用） */
@Component
export struct IconAsset {
  @Prop iconSize: number = ICON_VIEW;
  @Prop file: string = 'icons/twProject.svg';

  build() {
    Image($rawfile(this.file))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

@Component
export struct IconCollapseAll {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/collapseAll.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 双上箭头：全部折叠 */
@Component
export struct IconChevronsUp {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/collapseAll.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 展开全部（expui/general/expandAll.svg，ProjectViewToolbar 的 ExpandAll / ExpandRecursively 都用它） */
@Component
export struct IconExpandAll {
  @Prop iconSize: number = ICON_VIEW;
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    Image($rawfile('icons/expandAll.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 在项目树中定位（expui/general/locate.svg；对应动作 SelectInProjectView） */
@Component
export struct IconLocate {
  @Prop iconSize: number = ICON_VIEW;
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    Image($rawfile('icons/locate.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 从沙箱绝对路径渲染图标（自定义项目图标就是导入进来的 SVG/PNG 文件） */
@Component
export struct IconFromPath {
  @Prop iconSize: number = ICON_VIEW;
  @Prop path: string = '';
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    Image(`file://${this.path}`)
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 双下箭头：全部展开 */
@Component
export struct IconChevronsDown {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/expandAll.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 更多操作：竖排三点 */
@Component
export struct IconMoreVertical {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/moreVertical.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/** 灯泡：行号槽里的「意图操作」提示（PyCharm 在当前行显示） */
@Component
export struct IconLightbulb {
  @Prop iconSize: number = ICON_VIEW;
  /** 保留属性以兼容调用点；PyCharm 图标自带配色，不再着色 */
  @Prop color: string = ICON_FALLBACK;
  @Prop colorAlt: string = ICON_FALLBACK;

  build() {
    // PyCharm New UI（expui）图标资源：Apache-2.0，JetBrains s.r.o.，署名见 docs/LICENSES.md
    Image($rawfile('icons/intentionBulb.svg'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .draggable(false)
  }
}

/**
 * 按文件名选图标（工程树 / 编辑器标签共用）。
 * 目录 → 文件夹；.py → Python 文件；配置类 → Python 标记；其余 → 文本文件。
 */
@Component
export struct FileTypeIcon {
  @Prop name: string = '';
  @Prop theme: PyTheme = new PyTheme();
  @Prop isDir: boolean = false;
  /** 工程根行：PyCharm 用 expui/nodes/ideaProject.svg（文件夹 + 蓝色工程角标） */
  @Prop isProjectRoot: boolean = false;
  /** 排除目录（.venv/__pycache__/.idea 等）：PyCharm 用 expui/nodes/excludeRoot.svg（橙色文件夹） */
  @Prop excluded: boolean = false;
  /** 行级图标覆盖（合成节点用，如外部库/临时文件和控制台）；非空时优先 */
  @Prop iconFileOverride: string = '';
  /** 导入进来的图标文件绝对路径（自定义项目图标）；非空时最优先 */
  @Prop iconPath: string = '';
  @Prop iconSize: number = ICON_VIEW;

  private isConfig(): boolean {
    const lower: string = this.name.toLowerCase();
    return lower.endsWith('.json') || lower.endsWith('.json5') || lower.endsWith('.yaml')
      || lower.endsWith('.yml') || lower.endsWith('.toml') || lower.endsWith('.ini')
      || lower.endsWith('.cfg') || lower.endsWith('.txt');
  }

  build() {
    // 图标全部取 PyCharm 自带资源：目录 = expui/nodes/folder.svg；文件 = expui/fileTypes/*.svg
    if (this.iconPath.length > 0) {
      // 自定义项目图标：用户在「设置自定义项目图标…」里导入的 SVG/PNG
      IconFromPath({ iconSize: this.iconSize, path: this.iconPath })
    } else if (this.iconFileOverride.length > 0) {
      IconAsset({ iconSize: this.iconSize, file: this.iconFileOverride })
    } else if (this.isProjectRoot) {
      IconAsset({ iconSize: this.iconSize, file: 'icons/projectRoot.svg' })
    } else if (this.excluded) {
      IconAsset({ iconSize: this.iconSize, file: 'icons/excludedFolder.svg' })
    } else if (this.isDir) {
      IconAsset({ iconSize: this.iconSize, file: 'icons/nodeFolder.svg' })
    } else {
      IconAsset({ iconSize: this.iconSize, file: fileIconOf(this.name) })
    }
  }
}
