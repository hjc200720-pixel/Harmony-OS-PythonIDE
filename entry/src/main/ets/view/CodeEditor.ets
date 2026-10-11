import { PyTheme, PyFont } from '../common/Theme';
import { PyHighlighter, LineInfo, Token } from '../service/PyHighlighter';
import { languageOf, LangDef } from '../service/LanguageService';
import { FileService } from '../service/FileService';
import { IconLightbulb } from './IdeIcons';
import { KeyCode } from '@kit.InputKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { inputMethod } from '@kit.IMEKit';
import { PyCompleter, CompletionItem } from '../service/PyCompleter';

/**
 * 菜单「复制/剪切/粘贴」用的应用内剪贴板缓冲。
 * 系统剪贴板读写可能受权限限制，所以以应用内缓冲为主、系统剪贴板为增强：
 * 复制/剪切时两边都写，粘贴时优先用应用内缓冲、空了再读系统剪贴板。
 */
let appClipboard: string = '';

/** 一行高亮片段 */
export class SpanModel {
  text: string = '';
  color: string = '';
  italic: boolean = false;
  bold: boolean = false;

  constructor(text: string, color: string, italic: boolean = false, bold: boolean = false) {
    this.text = text;
    this.color = color;
    this.italic = italic;
    this.bold = bold;
  }
}

/** 预计算好的一行渲染数据（避免渲染期做词法分析） */
export class LineRender {
  text: string = '';
  spans: SpanModel[] = [];
  blank: boolean = false;
  indent: number = 0;

  constructor(text: string, spans: SpanModel[], blank: boolean, indent: number) {
    this.text = text;
    this.spans = spans;
    this.blank = blank;
    this.indent = indent;
  }
}

/** 父组件通过它反向调用编辑器内部能力（查找跳转、聚焦、插入文本等） */
export class CodeEditorController {
  revealOffset: (offset: number) => void = () => {
  };
  /** 滚动到指定行并聚焦（调试暂停时用） */
  revealLine: (line: number) => void = () => {
  };
  focus: () => void = () => {
  };
  insertText: (text: string) => void = () => {
  };
  selectAll: () => void = () => {
  };
  undo: () => void = () => {
  };
  redo: () => void = () => {
  };
  /** 复制选区（无选区则复制整行） */
  copySelection: () => void = () => {
  };
  /** 剪切选区（无选区则剪切整行） */
  cutSelection: () => void = () => {
  };
  /** 粘贴（有选区则替换选区） */
  pasteClipboard: () => void = () => {
  };
  /** 格式化代码（去行尾空白 / Tab 转空格 / 结尾单换行） */
  formatDocument: () => void = () => {
  };
  /** 优化导入（排序 + 去重） */
  optimizeImports: () => void = () => {
  };
  /** 扩展选区：单词 → 整行 → 全文 */
  expandSelection: () => void = () => {
  };
  /** 在当前文件里跳到下一个/上一个匹配 */
  findNext: (needle: string, forward: boolean) => void = () => {
  };
  /** 触发代码补全弹层（代码菜单 → 代码补全） */
  triggerCompletion: () => void = () => {
  };
  /** 将光标移到匹配的括号（导航菜单 → 将文本光标移至匹配的大括号） */
  moveToMatchingBrace: () => void = () => {
  };
  /** 编辑器获得焦点/被点击（页面据此把竖条选中态由蓝变灰，与 PyCharm 一致） */
  onEditorFocus: () => void = () => {
  };
  /** 注释/取消注释（Ctrl+/） */
  toggleComment: () => void = () => {
  };
  /** 复制当前行（Ctrl+D） */
  duplicateLine: () => void = () => {
  };
}

/**
 * 代码编辑器。
 *
 * 实现方式（关键设计）
 * ────────────────────
 * ArkUI 的 RichEditor 做语法高亮需要按 token 调用 updateSpanStyle，每次按键都会触发大量
 * 布局，长文件必然掉帧。这里采用更稳的「分层叠加」方案：
 *
 *   ┌ Scroll(V) ─────────────────────────────────────────────┐
 *   │ ┌ Scroll(H) ─────────────────────────────────────────┐ │
 *   │ │ Row                                                │ │
 *   │ │  ├ 行号/断点槽 Column（逐行 Row，高度 = 行高）      │ │
 *   │ │  └ Stack                                            │ │
 *   │ │      ├ 高亮层 Column（逐行 Row → Text+Span）        │ │
 *   │ │      └ TextArea（字体颜色全透明，只负责光标/选区/IME）│ │
 *   │ └────────────────────────────────────────────────────┘ │
 *   └────────────────────────────────────────────────────────┘
 *
 * 行高由我们自己固定（fontSize * 1.5），两层的每一行都强制同高，因此光标与高亮**必然对齐**；
 * 每次按键只重算一次词法（约 O(n)）并重建 Column，代价可控且无 API 抖动。
 * 代价：不虚拟化，超大文件（>约 2000 行）会有压力，已在 docs 中标注。
 */
@Component
export struct CodeEditor {
  @Prop @Watch('onInitialTextChanged') initialText: string = '';
  @Prop @Watch('onFilePathChanged') filePath: string = '';
  @Prop theme: PyTheme = new PyTheme();
  @Prop fontSize: number = PyFont.defaultCodeSize;
  @Prop tabSize: number = 4;
  @Prop showLineNumbers: boolean = true;
  /** 只读镜像（多窗格第 2 窗格用）：禁用输入层，避免两个编辑器实例各自改文本导致分叉 */
  @Prop readOnly: boolean = false;
  @Prop highlightCurrentLine: boolean = true;
  /** 显示缩进参考线（视图菜单 → 外观 → 显示缩进参考线） */
  @Prop showIndentGuides: boolean = false;
  /**
   * 代码折叠：这些**行号**在渲染时隐藏（height=0 + Visibility.None）。
   * 关键安全属性：模型 `this.lines` 完全不动 → 保存写回的永远是原文，不会因折叠损坏文件。
   */
  @Prop hiddenLines: number[] = [];
  /** 可折叠块的首行（gutter 显示折角标记，点击切换折叠） */
  @Prop foldableLines: number[] = [];
  /** 点击 gutter 折角标记 → 展开/折叠（ExpandCollapseToggleAction） */
  onToggleFold: (line: number) => void = () => {};
  /** 最近一次鼠标按键（onClick 对右键也会触发，需要区分，否则右键会把 IME 拉起来） */
  private lastMouseButton: number = 0;

  /** 选区变化（供 FoldingGroup 的 CollapseSelection 用） */
  onSelectionChange: (start: number, end: number) => void = () => {};
  /** 断点行号（1-based） */
  @Prop @Watch('onBreakpointsChanged') breakpoints: number[] = [];
  /** 检查问题所在行（gutter 上显示警示标）*/
  @Prop warnLines: number[] = [];
  /** 调试暂停所在行（1-based，0 表示没有暂停） */
  @Prop @Watch('onDebugLineChanged') debugLine: number = 0;
  /** 剪贴板动作回报（供父组件提示）：'copy' | 'cut' | 'paste' | 'paste-empty' */
  onClipboardAction: (action: string, length: number) => void = () => {
  };
  /** 外部注入的控制器 */
  controller: CodeEditorController = new CodeEditorController();
  onTextChange: (text: string) => void = () => {
  };
  onCursorChange: (line: number, column: number) => void = () => {
  };
  onToggleBreakpoint: (line: number) => void = () => {
  };
  /** 将光标移到匹配的括号（PyCharm：将文本光标移至匹配的大括号） */
  moveToMatchingBrace: () => void = () => {
  };
  /** 编辑器被点击/获得焦点（页面据此把竖条选中态由蓝变灰，与 PyCharm 一致） */
  onEditorFocus: () => void = () => {
  };
  /** 编辑器内右键（PyCharm 的 EditorPopupMenu）：上报位置给页面弹菜单 */
  /**
   * 收起系统输入法（含长按文本弹出的"选择/自动填充/拍摄输入"工具条）。
   * 编辑器是自绘层 + 透明 TextArea 输入层，右键/长按会顺带把 IME 拉起来，和我们的菜单叠在一起。
   */
  private dismissSystemInput(): void {
    try {
      inputMethod.getController().stopInputSession();
    } catch (e) {
      // IME 不可用时忽略
    }
  }

  onEditorMenu: (x: number, y: number) => void = () => {
  };

  @State private text: string = '';
  @State private lines: LineRender[] = [];
  @State private cursorLine: number = 1;
  @State private cursorColumn: number = 1;
  @State private contentWidth: number = 600;
  @State private gutterWidth: number = 56;
  @State private lineCount: number = 1;

  private areaController: TextAreaController = new TextAreaController();
  /** 输入层回报的选区（绝对偏移），供复制/剪切/粘贴使用 */
  private selStart: number = 0;
  private selEnd: number = 0;
  /** 补全候选（PyCharm 式弹层） */
  @State completions: CompletionItem[] = [];
  @State completionIndex: number = 0;
  /** 刚接受过一个候选：抑制紧随其后的一次弹出 */
  private completionSuppress: boolean = false;
  /** 自建撤销栈：ArkUI 的 TextArea 没有开放撤销栈，所以自己记录文本快照 */
  private history: string[] = [];
  private historyIndex: number = -1;
  private vScroller: Scroller = new Scroller();
  private highlightTimer: number = -1;
  private suppressChange: boolean = false;
  /** 最近一次已知的字符偏移，用于把 onChange 的结果映射回行列 */
  private lastKnownLine: number = 1;

  // ── 生命周期 ───────────────────────────────────────────────────────────

  aboutToAppear(): void {
    this.text = this.initialText;
    // 多语言高亮：按文件扩展名（LanguageService）切换关键字/类型集合
    const lang: LangDef = languageOf(this.filePath);
    PyHighlighter.setLanguage(lang);
    FileService.log(`highlight lang=${lang.name} ext=(${lang.exts.join('/')}) file=${this.filePath}`);
    this.rebuild(true);
    this.bindController();
  }

  aboutToDisappear(): void {
    if (this.highlightTimer >= 0) {
      clearTimeout(this.highlightTimer);
      this.highlightTimer = -1;
    }
  }

  private bindController(): void {
    this.controller.revealOffset = (offset: number) => {
      const line: number = this.lineOfOffset(offset);
      this.areaController.setTextSelection(offset, offset);
      this.scrollToLine(line);
    };
    this.controller.revealLine = (line: number) => {
      this.scrollToLine(line);
      this.cursorLine = line;
      this.onCursorChange(line, 1);
    };
    this.controller.focus = () => {
      this.areaController.caretPosition(this.offsetOfCursor());
    };
    this.controller.insertText = (insert: string) => {
      this.applyEdit(insert, 0);
    };
    this.controller.selectAll = () => {
      this.areaController.setTextSelection(0, this.text.length);
    };
    this.controller.undo = () => {
      this.applyHistory(this.historyIndex - 1);
    };
    this.controller.redo = () => {
      this.applyHistory(this.historyIndex + 1);
    };
    this.controller.copySelection = () => {
      this.copyToClipboard(false);
    };
    this.controller.cutSelection = () => {
      this.copyToClipboard(true);
    };
    this.controller.pasteClipboard = () => {
      this.pasteFromClipboard();
    };
    this.controller.formatDocument = () => {
      this.formatDocument();
    };
    this.controller.optimizeImports = () => {
      this.optimizeImports();
    };
    this.controller.expandSelection = () => {
      this.expandSelection();
    };
    this.controller.findNext = (needle: string, forward: boolean) => {
      this.findNextOccurrence(needle, forward);
    };
    this.controller.triggerCompletion = () => {
      this.refreshCompletions();
    };
    this.controller.moveToMatchingBrace = () => {
      this.jumpToMatchingBrace();
    };
    this.controller.toggleComment = () => {
      this.toggleComment();
    };
    this.controller.duplicateLine = () => {
      this.duplicateLine();
    };
  }

  private onInitialTextChanged(): void {
    if (this.text === this.initialText) {
      return;
    }
    this.suppressChange = true;
    this.text = this.initialText;
    this.cursorLine = 1;
    this.cursorColumn = 1;
    this.suppressChange = false;
    // 载入新内容时重置撤销栈
    this.history = [this.text];
    this.historyIndex = 0;
    this.rebuild(true);
    this.vScroller.scrollEdge(Edge.Top);
    this.areaController.setTextSelection(0, 0);
  }

  private onFilePathChanged(): void {
    // 文件切换时清掉待执行的高亮任务，避免把上一个文件的 token 画到新文件上
    if (this.highlightTimer >= 0) {
      clearTimeout(this.highlightTimer);
      this.highlightTimer = -1;
    }
    // 多语言高亮：新文件的扩展名决定关键字/类型集合
    const lang: LangDef = languageOf(this.filePath);
    PyHighlighter.setLanguage(lang);
    FileService.log(`highlight switch lang=${lang.name} file=${this.filePath}`);
    this.rebuild(true);
  }

  private onBreakpointsChanged(): void {
    // 断点是 @Prop 传入的数组，变化时只需触发一次重渲染（读取时按行查询）
  }

  private onDebugLineChanged(): void {
    if (this.debugLine > 0) {
      this.scrollToLine(this.debugLine);
    }
  }

  // ── 词法与几何计算 ─────────────────────────────────────────────────────

  private lineHeight(): number {
    return Math.round(this.fontSize * PyFont.lineHeightRatio);
  }

  /** 等宽字体的字符宽度估算（JetBrains Mono 的 advance 约为 0.6em） */
  private charWidth(): number {
    return this.fontSize * 0.601;
  }

  private rebuild(resetCursor: boolean): void {
    const info: LineInfo[] = PyHighlighter.splitLines(this.text);
    const tokens: Token[] = PyHighlighter.tokenize(this.text);
    const result: LineRender[] = [];
    let maxLength: number = 1;
    let tokenIndex: number = 0;

    for (let i = 0; i < info.length; i++) {
      const line: LineInfo = info[i];
      const lineStart: number = line.offset;
      const lineEnd: number = lineStart + line.text.length;
      const spans: SpanModel[] = [];
      let cursor: number = lineStart;

      // 跳过与该行无关的 token
      while (tokenIndex < tokens.length && tokens[tokenIndex].end <= lineStart) {
        tokenIndex++;
      }
      let probe: number = tokenIndex;
      while (probe < tokens.length && tokens[probe].start < lineEnd) {
        const token: Token = tokens[probe];
        const start: number = Math.max(token.start, lineStart);
        const end: number = Math.min(token.end, lineEnd);
        if (start > cursor) {
          spans.push(new SpanModel(this.text.substring(cursor, start), this.theme.editorFg));
        }
        if (end > start) {
          const style: SpanModel = this.styleOf(token.type);
          spans.push(new SpanModel(this.text.substring(start, end), style.color, style.italic, style.bold));
        }
        cursor = Math.max(cursor, end);
        probe++;
      }
      if (cursor < lineEnd) {
        spans.push(new SpanModel(this.text.substring(cursor, lineEnd), this.theme.editorFg));
      }
      if (spans.length === 0) {
        spans.push(new SpanModel(' ', this.theme.editorFg));
      }
      if (line.text.length > maxLength) {
        maxLength = line.text.length;
      }
      result.push(new LineRender(line.text, spans, line.blank, line.indent));
    }

    if (result.length === 0) {
      result.push(new LineRender('', [new SpanModel(' ', this.theme.editorFg)], true, 0));
    }

    this.lines = result;
    this.lineCount = result.length;
    this.contentWidth = Math.max(320, maxLength * this.charWidth() + 80);
    const digits: number = `${result.length}`.length;
    this.gutterWidth = this.showLineNumbers ? 16 + digits * this.charWidth() + 12 : 4;
    if (resetCursor) {
      this.cursorLine = 1;
      this.cursorColumn = 1;
    }
  }

  private styleOf(type: string): SpanModel {
    const t: PyTheme = this.theme;
    if (type === 'kw') {
      return new SpanModel('', t.kw);
    }
    if (type === 'kwType') {
      return new SpanModel('', t.kwType);
    }
    if (type === 'str') {
      return new SpanModel('', t.str);
    }
    if (type === 'docstr') {
      return new SpanModel('', t.docstr, true);
    }
    if (type === 'num') {
      return new SpanModel('', t.num);
    }
    if (type === 'comment') {
      return new SpanModel('', t.comment, true);
    }
    if (type === 'func') {
      return new SpanModel('', t.funcName);
    }
    if (type === 'cls') {
      return new SpanModel('', t.className, false, true);
    }
    if (type === 'decorator') {
      return new SpanModel('', t.decorator);
    }
    if (type === 'self') {
      return new SpanModel('', t.selfParam, true);
    }
    if (type === 'builtin') {
      return new SpanModel('', t.builtin);
    }
    if (type === 'fstr') {
      return new SpanModel('', t.fstrBrace);
    }
    return new SpanModel('', t.op);
  }

  private offsetOfCursor(): number {
    let offset: number = 0;
    for (let i = 0; i < this.cursorLine - 1 && i < this.lines.length; i++) {
      offset += this.lines[i].text.length + 1;
    }
    return offset + Math.max(0, this.cursorColumn - 1);
  }

  private lineOfOffset(offset: number): number {
    let acc: number = 0;
    for (let i = 0; i < this.lines.length; i++) {
      const len: number = this.lines[i].text.length + 1;
      if (offset < acc + len) {
        return i + 1;
      }
      acc += len;
    }
    return this.lines.length;
  }

  /** 将光标移到匹配的括号（PyCharm：将文本光标移至匹配的大括号） */
  private jumpToMatchingBrace(): void {
    const pairs: string = '()[]{}';
    const text: string = this.text;
    const caret: number = this.offsetOfCursor();
    let idx: number = -1;
    if (caret < text.length && pairs.indexOf(text.charAt(caret)) >= 0) {
      idx = caret;
    } else if (caret > 0 && pairs.indexOf(text.charAt(caret - 1)) >= 0) {
      idx = caret - 1;
    }
    if (idx < 0) {
      this.onEditorFocus();
      return;
    }
    const ch: string = text.charAt(idx);
    const openIdx: number = pairs.indexOf(ch);
    const isOpen: boolean = openIdx % 2 === 0;
    const matchCh: string = pairs.charAt(isOpen ? openIdx + 1 : openIdx - 1);
    let depth: number = 0;
    let found: number = -1;
    if (isOpen) {
      for (let i = idx; i < text.length; i++) {
        const c: string = text.charAt(i);
        if (c === ch) {
          depth++;
        } else if (c === matchCh) {
          depth--;
          if (depth === 0) {
            found = i;
            break;
          }
        }
      }
    } else {
      for (let i = idx; i >= 0; i--) {
        const c: string = text.charAt(i);
        if (c === ch) {
          depth++;
        } else if (c === matchCh) {
          depth--;
          if (depth === 0) {
            found = i;
            break;
          }
        }
      }
    }
    if (found >= 0) {
      const line: number = this.lineOfOffset(found);
      let lineStart: number = 0;
      for (let i = 0; i < line - 1 && i < this.lines.length; i++) {
        lineStart += this.lines[i].text.length + 1;
      }
      this.cursorLine = line;
      this.cursorColumn = found - lineStart + 1;
      this.areaController.caretPosition(found);
      this.scrollToLine(line);
      this.onCursorChange(this.cursorLine, this.cursorColumn);
    }
    this.onEditorFocus();
  }

  private scrollToLine(line: number): void {
    const target: number = Math.max(0, (line - 3) * this.lineHeight());
    this.vScroller.scrollTo({ xOffset: 0, yOffset: target, animation: { duration: 120 } });
  }

  // ── 编辑行为 ───────────────────────────────────────────────────────────

  private scheduleHighlight(): void {
    if (this.highlightTimer >= 0) {
      clearTimeout(this.highlightTimer);
    }
    this.highlightTimer = setTimeout(() => {
      this.highlightTimer = -1;
      this.rebuild(false);
    }, 60);
  }

  /** 在光标处插入文本，并把光标移到插入之后 */
  private applyEdit(insert: string, deleteBefore: number): void {
    const offset: number = this.offsetOfCursor();
    const from: number = Math.max(0, offset - deleteBefore);
    const next: string = this.text.substring(0, from) + insert + this.text.substring(offset);
    this.suppressChange = true;
    this.text = next;
    this.suppressChange = false;
    const caret: number = from + insert.length;
    this.rebuild(false);
    this.areaController.setTextSelection(caret, caret);
    this.updateCursorFromOffset(caret);
    this.onTextChange(this.text);
  }

  /** 缩进参考线的层级下标：缩进 n 级就画 n 条（第 0 条贴左边，逐级右移一个缩进宽） */
  private guideLevels(indent: number): number[] {
    const out: number[] = [];
    for (let i = 0; i < indent; i++) {
      out.push(i);
    }
    return out;
  }

  // ── 编辑操作（格式化 / 优化导入 / 扩展选区 / 查找下一个）─────────────

  /** 整篇替换文本（走同一套重建 + 通知链路） */
  private replaceWholeText(next: string): void {
    this.suppressChange = true;
    this.text = next;
    this.suppressChange = false;
    this.rebuild(true);
    this.pushHistory(next);
    this.onTextChange(this.text);
  }

  /** 格式化：Tab 转空格、去行尾空白、文件末尾只保留一个换行 */
  private formatDocument(): void {
    const rawLines: string[] = this.text.split('\n');
    const out: string[] = [];
    for (const raw of rawLines) {
      let line: string = '';
      for (let i = 0; i < raw.length; i++) {
        const ch: string = raw.charAt(i);
        line += ch === '\t' ? ' '.repeat(this.tabSize) : ch;
      }
      while (line.length > 0 && line.charAt(line.length - 1) === ' ') {
        line = line.substring(0, line.length - 1);
      }
      out.push(line);
    }
    while (out.length > 1 && out[out.length - 1].length === 0) {
      out.pop();
    }
    this.replaceWholeText(out.join('\n') + '\n');
  }

  /** 优化导入：把顶部 import 块排序并去重（保留块内注释与空行） */
  private optimizeImports(): void {
    const lines: string[] = this.text.split('\n');
    const imports: string[] = [];
    let firstIndex: number = -1;
    for (let i = 0; i < lines.length; i++) {
      const trimmed: string = lines[i].trim();
      if (trimmed.startsWith('import ') || trimmed.startsWith('from ')) {
        imports.push(trimmed);
        if (firstIndex < 0) {
          firstIndex = i;
        }
      } else if (firstIndex >= 0 && trimmed.length > 0 && !trimmed.startsWith('#')) {
        break;
      }
    }
    if (firstIndex < 0 || imports.length < 2) {
      return;
    }
    const unique: string[] = [];
    for (const item of imports) {
      if (unique.indexOf(item) < 0) {
        unique.push(item);
      }
    }
    unique.sort((a: string, b: string) => a.toLowerCase() < b.toLowerCase() ? -1 : 1);
    const out: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const trimmed: string = lines[i].trim();
      if (i === firstIndex) {
        for (const item of unique) {
          out.push(item);
        }
      }
      if (trimmed.startsWith('import ') || trimmed.startsWith('from ')) {
        continue;
      }
      out.push(lines[i]);
    }
    this.replaceWholeText(out.join('\n'));
  }

  /** 选区：空 → 光标处单词；单词 → 整行；整行 → 全文 */
  private expandSelection(): void {
    let start: number = this.selStart;
    let end: number = this.selEnd;
    if (end < start) {
      const swap: number = start;
      start = end;
      end = swap;
    }
    if (start === end) {
      let s: number = start;
      while (s > 0 && this.isWordChar(this.text.charAt(s - 1))) {
        s--;
      }
      let e: number = start;
      while (e < this.text.length && this.isWordChar(this.text.charAt(e))) {
        e++;
      }
      if (e > s) {
        start = s;
        end = e;
      }
    } else {
      const lineStart: number = this.lineStartOf(start);
      const lineEnd: number = this.lineEndOf(end);
      if (start === lineStart && end === lineEnd && this.text.length > 0
        && !(start === 0 && end === this.text.length)) {
        start = 0;
        end = this.text.length;
      } else {
        start = lineStart;
        end = lineEnd;
      }
    }
    this.areaController.setTextSelection(start, end);
    this.selStart = start;
    this.selEnd = end;
  }

  private isWordChar(ch: string): boolean {
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
      || (ch >= '0' && ch <= '9') || ch === '_';
  }

  private lineStartOf(offset: number): number {
    let i: number = Math.max(0, Math.min(offset, this.text.length));
    while (i > 0 && this.text.charAt(i - 1) !== '\n') {
      i--;
    }
    return i;
  }

  private lineEndOf(offset: number): number {
    let i: number = Math.max(0, Math.min(offset, this.text.length));
    while (i < this.text.length && this.text.charAt(i) !== '\n') {
      i++;
    }
    return i;
  }

  /** 在当前文件中查找下一个/上一个匹配（PyCharm 的 F3 / Shift+F3） */
  private findNextOccurrence(needle: string, forward: boolean): void {
    if (needle.length === 0) {
      return;
    }
    const from: number = forward
      ? Math.max(this.selEnd, this.offsetOfCursor()) + 1
      : Math.max(0, Math.min(this.selStart, this.offsetOfCursor()) - 1);
    let index: number = -1;
    if (forward) {
      index = this.text.indexOf(needle, from);
      if (index < 0) {
        index = this.text.indexOf(needle, 0);
      }
    } else {
      const head: string = this.text.substring(0, from + needle.length);
      index = head.lastIndexOf(needle);
      if (index < 0) {
        index = this.text.lastIndexOf(needle);
      }
    }
    if (index < 0) {
      return;
    }
    this.areaController.setTextSelection(index, index + needle.length);
    this.selStart = index;
    this.selEnd = index + needle.length;
    this.updateCursorFromOffset(index);
    this.scrollToLine(this.cursorLine);
    this.areaController.caretPosition(index);
  }

  /** 注释/取消注释（选区覆盖的行或当前行） */
  private toggleComment(): void {
    const lines: string[] = this.text.split('\n');
    let startLine: number = this.cursorLine - 1;
    let endLine: number = this.cursorLine - 1;
    if (this.selEnd > this.selStart) {
      startLine = this.lineOfOffset(this.selStart) - 1;
      endLine = this.lineOfOffset(this.selEnd) - 1;
    }
    if (startLine < 0) {
      startLine = 0;
    }
    if (endLine >= lines.length) {
      endLine = lines.length - 1;
    }
    let allCommented: boolean = true;
    for (let i = startLine; i <= endLine; i++) {
      const trimmed: string = lines[i].trim();
      if (trimmed.length > 0 && !trimmed.startsWith('#')) {
        allCommented = false;
      }
    }
    for (let i = startLine; i <= endLine; i++) {
      const line: string = lines[i];
      if (line.trim().length === 0) {
        continue;
      }
      if (allCommented) {
        const idx: number = line.indexOf('#');
        if (idx >= 0) {
          // 去掉 '# ' 或 '#'
          const after: string = line.substring(idx + 1);
          lines[i] = line.substring(0, idx)
            + (after.startsWith(' ') ? after.substring(1) : after);
        }
      } else {
        let indent: number = 0;
        while (indent < line.length && (line.charAt(indent) === ' ' || line.charAt(indent) === '\t')) {
          indent++;
        }
        lines[i] = line.substring(0, indent) + '# ' + line.substring(indent);
      }
    }
    this.replaceWholeText(lines.join('\n'));
  }

  /** 复制当前行（紧跟在下方插入一份） */
  private duplicateLine(): void {
    const lines: string[] = this.text.split('\n');
    if (lines.length === 0) {
      return;
    }
    const index: number = Math.max(0, Math.min(this.cursorLine - 1, lines.length - 1));
    lines.splice(index + 1, 0, lines[index]);
    this.replaceWholeText(lines.join('\n'));
  }

  // ── 撤销 / 重做（自建快照栈）────────────────────────────────────────────

  /** 记录一次文本快照（连续的重复内容不入栈） */
  private pushHistory(value: string): void {
    if (this.historyIndex >= 0 && this.history[this.historyIndex] === value) {
      return;
    }
    if (this.historyIndex < this.history.length - 1) {
      this.history = this.history.slice(0, this.historyIndex + 1);
    }
    this.history.push(value);
    if (this.history.length > 200) {
      this.history.shift();
    }
    this.historyIndex = this.history.length - 1;
  }

  /** 跳到栈中某个快照 */
  private applyHistory(index: number): void {
    if (index < 0 || index >= this.history.length || index === this.historyIndex) {
      return;
    }
    this.historyIndex = index;
    const value: string = this.history[index];
    this.suppressChange = true;
    this.text = value;
    this.suppressChange = false;
    this.rebuild(true);
    this.onTextChange(this.text);
  }

  // ── 代码补全 ───────────────────────────────────────────────────────────

  /** 每次输入后刷新候选；前缀为空则收起弹层 */
  private refreshCompletions(): void {
    if (this.completionSuppress) {
      this.completionSuppress = false;
      if (this.completions.length > 0) {
        this.completions = [];
      }
      return;
    }
    // ⚠️ 不能用 offsetOfCursor()：它依赖 cursorLine/cursorColumn，而正常打字时这两个值
    // 只有在 applyEdit 等路径才会更新，会算出陈旧偏移。优先向控制器要真实光标偏移
    // （TextContentControllerBase#getCaretOffset），拿不到再退到选区/行列。
    let offset: number = -1;
    try {
      const caret: CaretOffset = this.areaController.getCaretOffset();
      offset = caret.index;
    } catch (err) {
      offset = -1;
    }
    if (offset < 0 || offset > this.text.length) {
      if (this.selStart === this.selEnd && this.selEnd >= 0 && this.selEnd <= this.text.length) {
        offset = this.selEnd;
      } else {
        offset = this.offsetOfCursor();
      }
    }
    this.updateCursorFromOffset(offset);
    if (PyCompleter.prefixLength(this.text, offset) === 0) {
      if (this.completions.length > 0) {
        this.completions = [];
      }
      return;
    }
    const items: CompletionItem[] = PyCompleter.complete(this.text, offset);
    if (items.length === 0) {
      if (this.completions.length > 0) {
        this.completions = [];
      }
      return;
    }
    this.completions = items;
    this.completionIndex = 0;
  }

  /** 接受候选：用候选文本替换掉已输入的前缀 */
  private acceptCompletion(item: CompletionItem): void {
    let offset: number = -1;
    try {
      const caret: CaretOffset = this.areaController.getCaretOffset();
      offset = caret.index;
    } catch (err) {
      offset = -1;
    }
    if (offset < 0 || offset > this.text.length) {
      if (this.selStart === this.selEnd && this.selEnd > 0 && this.selEnd <= this.text.length) {
        offset = this.selEnd;
      } else {
        offset = this.offsetOfCursor();
      }
    }
    const length: number = PyCompleter.prefixLength(this.text, offset);
    this.completionSuppress = true;
    if (this.completions.length > 0) {
      this.completions = [];
    }
    this.replaceRange(offset - length, offset, item.text);
  }

  /** 弹层纵向位置：光标所在行的下一行 */
  private completionTop(): number {
    return Math.max(0, (this.cursorLine - 1) * this.lineHeight() + this.lineHeight());
  }

  /** 弹层横向位置：对着光标列，贴右边界时回退 */
  private completionLeft(): number {
    const charWidth: number = this.fontSize * 0.601;
    const left: number = (this.cursorColumn - 1) * charWidth;
    const maxLeft: number = Math.max(0, this.contentWidth - 262);
    return Math.min(left, maxLeft);
  }

  /** 当前选区 [start, end]；没有选区时退化为光标处的空区间 */
  private selectedRange(): number[] {
    const caret: number = this.offsetOfCursor();
    let start: number = this.selStart;
    let end: number = this.selEnd;
    if (end < start) {
      const swap: number = start;
      start = end;
      end = swap;
    }
    if (end <= start || end > this.text.length) {
      return [caret, caret];
    }
    return [start, end];
  }

  /** 用 insert 替换 [from, to)，光标落到替换内容之后（applyEdit 的区间版本） */
  private replaceRange(from: number, to: number, insert: string): void {
    const start: number = Math.max(0, Math.min(from, this.text.length));
    const stop: number = Math.max(start, Math.min(to, this.text.length));
    const next: string = this.text.substring(0, start) + insert + this.text.substring(stop);
    this.suppressChange = true;
    this.text = next;
    this.suppressChange = false;
    const caret: number = start + insert.length;
    this.rebuild(false);
    this.areaController.setTextSelection(caret, caret);
    this.updateCursorFromOffset(caret);
    this.selStart = caret;
    this.selEnd = caret;
    this.onTextChange(this.text);
  }

  /** 复制（cut=true 时剪切）。无选区则整行——与 PyCharm 的 Ctrl+C/Ctrl+X 一致。 */
  private copyToClipboard(cut: boolean): void {
    const range: number[] = this.selectedRange();
    let start: number = range[0];
    let stop: number = range[1];
    if (stop <= start) {
      const lineIndex: number = this.cursorLine - 1;
      if (lineIndex < 0 || lineIndex >= this.lines.length) {
        return;
      }
      start = 0;
      for (let i = 0; i < lineIndex; i++) {
        start += this.lines[i].text.length + 1;
      }
      stop = start + this.lines[lineIndex].text.length + 1;
      if (stop > this.text.length) {
        stop = this.text.length;
      }
    }
    const payload: string = this.text.substring(start, stop);
    appClipboard = payload;
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, payload);
      pasteboard.getSystemPasteboard().setDataSync(data);
    } catch (err) {
      // 系统剪贴板不可用（权限/环境限制）时不影响应用内剪贴板
    }
    if (cut) {
      this.replaceRange(start, stop, '');
    }
    this.onClipboardAction(cut ? 'cut' : 'copy', payload.length);
  }

  /** 粘贴：优先应用内缓冲，为空时尝试系统剪贴板 */
  private pasteFromClipboard(): void {
    let payload: string = appClipboard;
    if (payload.length === 0) {
      try {
        const data = pasteboard.getSystemPasteboard().getDataSync();
        payload = data.getPrimaryText();
        appClipboard = payload;
      } catch (err) {
        payload = '';
      }
    }
    if (payload.length === 0) {
      this.onClipboardAction('paste-empty', 0);
      return;
    }
    const range: number[] = this.selectedRange();
    this.replaceRange(range[0], range[1], payload);
    this.onClipboardAction('paste', payload.length);
  }

  private updateCursorFromOffset(offset: number): void {
    let acc: number = 0;
    for (let i = 0; i < this.lines.length; i++) {
      const lineLength: number = this.lines[i].text.length;
      if (offset <= acc + lineLength) {
        this.cursorLine = i + 1;
        this.cursorColumn = offset - acc + 1;
        this.onCursorChange(this.cursorLine, this.cursorColumn);
        return;
      }
      acc += lineLength + 1;
    }
  }

  /**
   * 处理换行：复制上一行缩进，若上一行以「:」结尾（且不是字典/切片）再补一级缩进。
   */
  private handleEnter(previousText: string, caretOffset: number): boolean {
    let acc: number = 0;
    for (let i = 0; i < this.lines.length; i++) {
      const lineLength: number = this.lines[i].text.length;
      if (caretOffset <= acc + lineLength + 1 && caretOffset > acc) {
        const lineText: string = this.lines[i].text;
        const col: number = caretOffset - acc;
        const before: string = lineText.substring(0, col);
        const indentText: string = before.substring(0, before.length - before.trimStart().length);
        let indent: string = indentText;
        const trimmed: string = before.trimEnd();
        if (trimmed.endsWith(':')) {
          indent += ' '.repeat(this.tabSize);
        }
        this.applyEdit('\n' + indent, 0);
        return true;
      }
      acc += lineLength + 1;
    }
    return false;
  }

  /** 括号/引号自动配对；若已有右半部分则只移动光标 */
  private handleAutoPair(symbol: string): boolean {
    const pairs: string[] = ['()', '[]', '{}', '""', '\'\''];
    let closing: string = '';
    for (const pair of pairs) {
      if (pair.charAt(0) === symbol) {
        closing = pair.charAt(1);
        break;
      }
    }
    if (closing.length === 0) {
      return false;
    }
    const offset: number = this.offsetOfCursor();
    const nextChar: string = offset < this.text.length ? this.text.charAt(offset) : '';
    if (nextChar === closing && (symbol === '"' || symbol === '\'')) {
      // 输入引号且后面就是同一个引号 → 只跳过，不重复插入
      this.areaController.setTextSelection(offset + 1, offset + 1);
      this.updateCursorFromOffset(offset + 1);
      return true;
    }
    if (symbol === '"' || symbol === '\'') {
      const lineStart: number = offset - (this.cursorColumn - 1);
      const before: string = this.text.substring(lineStart, offset);
      const count: number = before.split(symbol).length - 1;
      if (count % 2 === 1) {
        // 已有一个未闭合的同类引号：只插入一个，视为闭合
        this.applyEdit(symbol, 0);
        return true;
      }
    }
    this.applyEdit(symbol + closing, 0);
    const caret: number = this.offsetOfCursor() - 1;
    this.areaController.setTextSelection(caret, caret);
    this.updateCursorFromOffset(caret);
    return true;
  }

  // ── UI ────────────────────────────────────────────────────────────────

  build() {
    Scroll(this.vScroller) {
      Scroll() {
        Row() {
          // ── 行号 / 断点槽 ──
          Column() {
            ForEach(this.lines, (line: LineRender, index: number) => {
              Row() {
                if (this.showLineNumbers) {
                  Text(`${index + 1}`)
                    .fontSize(this.fontSize - 1)
                    .fontFamily(PyFont.mono)
                    .fontColor(this.cursorLine === index + 1 ? this.theme.gutterActiveFg : this.theme.gutterFg)
                    .textAlign(TextAlign.End)
                    .width(this.gutterWidth - 20)
                }
                // 断点标记（点击切换）；没有断点的当前行显示「意图操作」灯泡（PyCharm 同款）
                Stack() {
                  if (this.foldableLines.indexOf(index + 1) >= 0) {
                    // 折叠折角：可折叠块的首行显示 ▾/▸，点击切换（PyCharm ExpandCollapseToggleAction）
                    Text(this.hiddenLines.indexOf(index + 2) >= 0 ? '▸' : '▾')
                      .fontSize(9)
                      .fontColor(this.theme.gutterActiveFg)
                      .onClick(() => {
                        this.onToggleFold(index + 1);
                      })
                  } else if (this.breakpoints.indexOf(index + 1) >= 0) {
                    Circle({ width: 9, height: 9 }).fill(this.theme.breakpointDot)
                  } else if (this.warnLines.indexOf(index + 1) >= 0) {
                    // 检查问题标记（PyCharm 的警告小标：琥珀色）
                    Circle({ width: 8, height: 8 }).fill(this.theme.warning)
                  } else if (this.cursorLine === index + 1) {
                    IconLightbulb({ iconSize: 13, color: this.theme.pythonYellow })
                  }
                }
                .width(16)
                .height(this.lineHeight())
              }
              .width(this.gutterWidth)
              .height(this.hiddenLines.indexOf(index + 1) >= 0 ? 0 : this.lineHeight())
              .visibility(this.hiddenLines.indexOf(index + 1) >= 0 ? Visibility.None : Visibility.Visible)
              .backgroundColor(this.debugLine === index + 1
                ? this.theme.debugLineBg
                : (this.highlightCurrentLine && this.cursorLine === index + 1
                  ? this.theme.currentLineBg : Color.Transparent))
              .onClick(() => {
                this.onToggleBreakpoint(index + 1);
              })
            }, (line: LineRender, index: number) =>
              // 断点红点 / 当前行 / 调试暂停行 / 主题 / 字号 / 行号开关 都必须进 key，
              // 否则 ForEach 会复用旧节点，红点和高亮不刷新（ArkUI 经典陷阱）
              `g${index}_${this.showLineNumbers ? 1 : 0}_${this.fontSize}`
              + `_${this.theme.isDark ? 'd' : 'l'}`
              + `_${this.breakpoints.indexOf(index + 1) >= 0 ? 1 : 0}`
              + `_${this.warnLines.indexOf(index + 1) >= 0 ? 1 : 0}`
              + `_${this.cursorLine === index + 1 ? 1 : 0}`
              + `_${this.debugLine === index + 1 ? 1 : 0}`)
          }
          .width(this.gutterWidth)
          .alignItems(HorizontalAlign.End)
          .backgroundColor(this.theme.gutterBg)
          .border({ width: { right: 1 }, color: this.theme.editorBorder })

          // ── 高亮层 + 输入层 ──
          Stack({ alignContent: Alignment.TopStart }) {
            // 缩进参考线层（视图 → 外观 → 显示缩进参考线）：按每行缩进层级画 1vp 竖线
            if (this.showIndentGuides) {
              Column() {
                ForEach(this.lines, (line: LineRender, index: number) => {
                  Row() {
                    ForEach(this.guideLevels(line.indent), (level: number) => {
                      Column()
                        .width(1)
                        .height(this.lineHeight())
                        .backgroundColor(this.theme.indentGuide)
                        .margin({ left: level === 0 ? 0 : this.tabSize * this.charWidth() - 1 })
                    }, (level: number) => `guide${index}_${level}`)
                  }
                  .width(this.contentWidth)
                  .height(this.hiddenLines.indexOf(index + 1) >= 0 ? 0 : this.lineHeight())
                  .visibility(this.hiddenLines.indexOf(index + 1) >= 0 ? Visibility.None : Visibility.Visible)
                  .alignItems(VerticalAlign.Top)
                }, (line: LineRender, index: number) => `gl${index}_${line.indent}`)
              }
              .width(this.contentWidth)
              .alignItems(HorizontalAlign.Start)
            }

            Column() {
              ForEach(this.lines, (line: LineRender, index: number) => {
                Text() {
                  ForEach(line.spans, (span: SpanModel) => {
                    Span(span.text)
                      .fontColor(span.color)
                      .fontFamily(span.bold ? PyFont.monoBold : PyFont.mono)
                      .fontSize(this.fontSize)
                      .fontStyle(span.italic ? FontStyle.Italic : FontStyle.Normal)
                      .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
                  }, (span: SpanModel, spanIndex: number) => `s${index}_${spanIndex}`)
                }
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Clip })
                .width(this.contentWidth)
                .height(this.hiddenLines.indexOf(index + 1) >= 0 ? 0 : this.lineHeight())
                .visibility(this.hiddenLines.indexOf(index + 1) >= 0 ? Visibility.None : Visibility.Visible)
                .lineHeight(this.lineHeight())
                .backgroundColor(this.debugLine === index + 1
                  ? this.theme.debugLineBg
                  : (this.highlightCurrentLine && this.cursorLine === index + 1
                    ? this.theme.currentLineBg : Color.Transparent))
              }, (line: LineRender, index: number) =>
                // 行文本 + 高亮相关状态全部进 key：改了哪一行就只重建哪一行
                `c${index}_${this.fontSize}_${this.theme.isDark ? 'd' : 'l'}`
                + `_${this.debugLine === index + 1 ? 1 : 0}`
                + `_${this.highlightCurrentLine && this.cursorLine === index + 1 ? 1 : 0}`
                + `_${line.text}`)
            }
            .width(this.contentWidth)
            .alignItems(HorizontalAlign.Start)

            TextArea({ text: this.text, controller: this.areaController })
              // 只读镜像：禁用输入层（文本由下方高亮层渲染，禁用不影响观感），并隐藏光标
              .enabled(!this.readOnly)
              .caretColor(this.readOnly ? Color.Transparent : this.theme.caret)
              .width(this.contentWidth)
              .height(Math.max(this.lineHeight(), this.lineCount * this.lineHeight()))
              .fontSize(this.fontSize)
              .fontFamily(PyFont.mono)
              .fontColor(Color.Transparent)
              .caretColor(this.theme.caret)
              // 输入层的选区背景是半透明的，否则会整块盖住下面高亮层的彩色文字
              .selectedBackgroundColor(this.theme.selectionOverlay)
              .backgroundColor(Color.Transparent)
              .padding(0)
              .margin(0)
              .borderRadius(0)
              .lineHeight(this.lineHeight())
              .textAlign(TextAlign.Start)
              .barState(BarState.Off)
              // 右键/长按弹菜单时不再自动拉起系统键盘（并在弹菜单前主动收起 IME）
              .enableKeyboardOnFocus(false)
              // 关键：隐藏系统「文本选择」工具条（选/自动填充/拍摄输入）——
              // 右键或长按会让输入层选中文本，系统随即弹出该工具条，与我们自己的菜单叠在一起
              .selectionMenuHidden(true)
              // 选区偏移上报（PyCharm FoldingGroup > CollapseSelection）
              .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
                this.onSelectionChange(selectionStart, selectionEnd);
              })
              // 输入层是最上层：右键很可能被它吃掉、传不到外层 Scroll —— 这里也接一次
              .onMouse((event: MouseEvent) => {
                this.lastMouseButton = event.button;
                FileService.log(`editor TextArea mouse button=${event.button} action=${event.action} x=${event.x} y=${event.y}`);
                if (event.button === MouseButton.Right) {
                  this.dismissSystemInput();
                  this.onEditorMenu(event.x + this.gutterWidth, event.y);
                }
              })
              // 输入层获得焦点 = 编辑器获得焦点（竖条选中态随之由蓝变灰）
              .onFocus(() => {
                this.onEditorFocus();
              })
              .onChange((value: string) => {
                if (this.suppressChange) {
                  return;
                }
                const previous: string = this.text;
                this.text = value;
                this.scheduleHighlight();
                this.onTextChange(value);
                this.pushHistory(value);
                this.refreshCompletions();
                // 回车自动缩进：仅当本次新增内容里恰好出现一个换行
                const added: number = value.length - previous.length;
                if (added === 1 && value.length > 0) {
                  const caret: number = this.offsetOfCursor();
                  if (caret > 0 && value.charAt(caret - 1) === '\n') {
                    this.updateCursorFromOffset(caret);
                    this.handleEnter(previous, caret);
                  }
                }
              })
              .onKeyEvent((event: KeyEvent) => {
                if (event.type !== KeyType.Down) {
                  return;
                }
                // 补全弹层打开时优先接管上下键 / 回车 / Tab / Esc（PyCharm 行为）
                if (this.completions.length > 0) {
                  if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
                    this.completionIndex = (this.completionIndex + 1) % this.completions.length;
                    return;
                  }
                  if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
                    this.completionIndex =
                      (this.completionIndex - 1 + this.completions.length) % this.completions.length;
                    return;
                  }
                  if (event.keyCode === KeyCode.KEYCODE_ENTER
                    || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER
                    || event.keyCode === KeyCode.KEYCODE_TAB) {
                    this.acceptCompletion(this.completions[this.completionIndex]);
                    return;
                  }
                  if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
                    this.completions = [];
                    return;
                  }
                }
                if (event.keyCode === KeyCode.KEYCODE_TAB) {
                  this.applyEdit(' '.repeat(this.tabSize), 0);
                }
              })
              // 记录选区：菜单里的复制/剪切/粘贴要靠它（TextAreaController 没有选区 getter）
              .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
                this.selStart = selectionStart;
                this.selEnd = selectionEnd;
              })

            // ── 补全弹层（挂在同一个 Stack 里，随文本一起滚动）──
            if (this.completions.length > 0) {
              Column() {
                ForEach(this.completions, (item: CompletionItem, index: number) => {
                  Row() {
                    Text(PyCompleter.markOf(item.kind))
                      .fontSize(11)
                      .fontFamily(PyFont.mono)
                      .fontColor(item.kind === 'keyword' ? this.theme.kw : this.theme.funcName)
                      .width(16)
                    Text(item.text)
                      .fontSize(12)
                      .fontFamily(PyFont.mono)
                      .fontColor(this.theme.textPrimary)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(item.detail)
                      .fontSize(10)
                      .fontColor(this.theme.textSecondary)
                      .maxLines(1)
                  }
                  .width(258)
                  .height(22)
                  .padding({ left: 6, right: 6 })
                  .backgroundColor(index === this.completionIndex
                    ? this.theme.selectionBg : this.theme.popupBg)
                  .onClick(() => this.acceptCompletion(item))
                }, (item: CompletionItem, index: number) => `${index}-${item.kind}-${item.text}`)
              }
              .width(258)
              .backgroundColor(this.theme.popupBg)
              .border({ width: 1, color: this.theme.border })
              .borderRadius(4)
              .shadow({ radius: 10, color: '#66000000', offsetX: 0, offsetY: 3 })
              .offset({ x: this.completionLeft(), y: this.completionTop() })
            }
          }
          .width(this.contentWidth)
        }
        .alignItems(VerticalAlign.Top)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .align(Alignment.TopStart)
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .align(Alignment.TopStart)
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.editorBg)
    .edgeEffect(EdgeEffect.None)
    .onClick((event: ClickEvent) => {
      // 右键（含右键长按）不移动插入符：否则 caretPosition 会让 TextArea 抢焦点 → 系统键盘/选择条弹出
      if (this.lastMouseButton === MouseButton.Right) {
        this.dismissSystemInput();
        return;
      }
      this.lastMouseButton = MouseButton.Left;
      this.onEditorFocus();
      // PyCharm：点击编辑器应把插入符落到**点击处**（原先用 cursorLine 反算偏移 = 点了也不动，
      // 这会导致折叠选区/在光标处折叠等依赖 cursorLine 的功能拿不到正确位置）
      const lh: number = this.lineHeight();
      const line: number = Math.max(1, Math.min(this.lines.length, Math.floor(event.y / lh) + 1));
      const colF: number = Math.floor((event.x - this.gutterWidth) / this.charWidth());
      const col: number = Math.max(0, Math.min(this.lines[line - 1].text.length, colF));
      let off: number = 0;
      for (let i = 0; i < line - 1 && i < this.lines.length; i++) {
        off += this.lines[i].text.length + 1;
      }
      off += col;
      this.cursorLine = line;
      this.areaController.caretPosition(off);
    })
    // PC：编辑器内右键 → 上下文菜单（PyCharm 的 EditorPopupMenu）
    .onMouse((event: MouseEvent) => {
      this.lastMouseButton = event.button;
      FileService.log(`editor Scroll mouse button=${event.button} action=${event.action} x=${event.x} y=${event.y}`);
      if (event.button === MouseButton.Right) {
        this.dismissSystemInput();
        this.onEditorMenu(event.x, event.y);
      }
    })
    // 平板/触摸：长按等同右键（EditorPopupMenu）
    .parallelGesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction((event: GestureEvent) => {
          if (event.fingerList.length > 0) {
            this.dismissSystemInput();
            this.onEditorMenu(event.fingerList[0].globalX, event.fingerList[0].globalY);
          } else {
            this.onEditorMenu(80, 160);
          }
        })
    )
  }
}
