/**
 * Python 词法着色器（纯函数，零依赖）。
 *
 * 只做「够用且快」的扫描：关键字/内置/字符串(含三引号与 f-string)/数字/注释/
 * 函数名/类名/装饰器/self/运算符。故意不做完整 AST 解析 —— 编辑器每次按键都要跑一遍，
 * 正确性优先级低于「绝不能卡」。
 */

import { LangDef } from './LanguageService';

export class Token {
  start: number = 0;
  end: number = 0;
  /** 与 PyTheme 字段同名的类型键 */
  type: string = 'op';

  constructor(start: number, end: number, type: string) {
    this.start = start;
    this.end = end;
    this.type = type;
  }
}

export class LineInfo {
  text: string = '';
  /** 该行在全文中的起始偏移 */
  offset: number = 0;
  indent: number = 0;
  blank: boolean = false;

  constructor(text: string, offset: number, indent: number, blank: boolean) {
    this.text = text;
    this.offset = offset;
    this.indent = indent;
    this.blank = blank;
  }
}

export class PyHighlighter {
  static readonly KEYWORDS: string[] = [
    'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue',
    'def', 'del', 'elif', 'else', 'except', 'finally', 'for', 'from', 'global', 'if', 'import', 'in',
    'is', 'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'try', 'while', 'with', 'yield',
    'match', 'case'
  ];

  static readonly BUILTINS: string[] = [
    'abs', 'all', 'any', 'ascii', 'bin', 'bool', 'bytearray', 'bytes', 'callable', 'chr', 'classmethod',
    'compile', 'complex', 'delattr', 'dict', 'dir', 'divmod', 'enumerate', 'eval', 'exec', 'filter',
    'float', 'format', 'frozenset', 'getattr', 'globals', 'hasattr', 'hash', 'help', 'hex', 'id',
    'input', 'int', 'isinstance', 'issubclass', 'iter', 'len', 'list', 'locals', 'map', 'max',
    'memoryview', 'min', 'next', 'object', 'oct', 'open', 'ord', 'pow', 'print', 'property', 'range',
    'repr', 'reversed', 'round', 'set', 'setattr', 'slice', 'sorted', 'staticmethod', 'str', 'sum',
    'super', 'tuple', 'type', 'vars', 'zip', '__import__', 'Exception', 'ValueError', 'TypeError',
    'KeyError', 'IndexError', 'RuntimeError', 'StopIteration', 'ZeroDivisionError', 'ImportError',
    'OSError', 'FileNotFoundError', 'AttributeError', 'NotImplementedError'
  ];

  private static readonly KEYWORD_SET: Set<string> = PyHighlighter.toSet(PyHighlighter.KEYWORDS);
  private static readonly BUILTIN_SET: Set<string> = PyHighlighter.toSet(PyHighlighter.BUILTINS);

  /** 当前文件语言的关键字/类型集合（由编辑器依据 LanguageService 切换） */
  private static activeKeywords: Set<string> = PyHighlighter.KEYWORD_SET;
  private static activeTypes: Set<string> = PyHighlighter.BUILTIN_SET;

  /**
   * 多语言接入点：切换当前语言后，tokenize 用该语言的关键字/类型着色。
   * 数据全部来自 LanguageService（语言规范本身，不是 IDE 私有数据）。
   */
  static setLanguage(lang: LangDef): void {
    PyHighlighter.activeKeywords = PyHighlighter.toSet(lang.keywords);
    PyHighlighter.activeTypes = lang.id === 'Python'
      ? PyHighlighter.BUILTIN_SET : PyHighlighter.toSet(lang.types);
  }

  private static toSet(items: string[]): Set<string> {
    const s: Set<string> = new Set<string>();
    for (const item of items) {
      s.add(item);
    }
    return s;
  }

  private static isIdentStart(c: string): boolean {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '_' || c.charCodeAt(0) > 127;
  }

  private static isIdentPart(c: string): boolean {
    return PyHighlighter.isIdentStart(c) || (c >= '0' && c <= '9');
  }

  private static isDigit(c: string): boolean {
    return c >= '0' && c <= '9';
  }

  /** 把源码切成 token 列表（按 offset 升序，互不重叠） */
  static tokenize(text: string): Token[] {
    const tokens: Token[] = [];
    const n: number = text.length;
    let i: number = 0;
    // 行首是否只有空白（用于识别文档字符串）
    let lineHasCode: boolean = false;
    // 上一个有意义的关键字（用于识别 def/class 后面的名字）
    let lastKeyword: string = '';
    // 上一行是否以冒号结尾（进入新代码块）
    let blockJustOpened: boolean = true;

    while (i < n) {
      const c: string = text.charAt(i);

      // 换行
      if (c === '\n') {
        if (lastKeyword !== '') {
          // 块内首行的文档字符串判定：冒号后换行仍然算「块刚打开」
          blockJustOpened = blockJustOpened || lastKeyword === ':';
        }
        lineHasCode = false;
        i++;
        continue;
      }
      // 空白
      if (c === ' ' || c === '\t' || c === '\r') {
        i++;
        continue;
      }
      // 注释
      if (c === '#') {
        const end: number = PyHighlighter.indexOfOrEnd(text, '\n', i);
        tokens.push(new Token(i, end, 'comment'));
        i = end;
        lineHasCode = true;
        continue;
      }
      // 字符串（含前缀 r/b/u/f 组合）
      const quoteCheck: number = PyHighlighter.stringPrefixLength(text, i);
      if (quoteCheck >= 0) {
        const quotePos: number = i + quoteCheck;
        const q: string = text.charAt(quotePos);
        if (q === '"' || q === '\'') {
          const triple: boolean = text.charAt(quotePos + 1) === q && text.charAt(quotePos + 2) === q;
          const isFString: boolean = quoteCheck > 0
            && (text.substring(i, quotePos).toLowerCase().indexOf('f') >= 0);
          const strEnd: number = PyHighlighter.scanString(text, quotePos, q, triple);
          let type: string = 'str';
          if (triple && !lineHasCode && blockJustOpened) {
            type = 'docstr';
          }
          if (isFString && type === 'str') {
            // f-string：整体为字符串，内部 {} 里的表达式用亮色标出
            tokens.push(new Token(i, quotePos + (triple ? 3 : 1), 'str'));
            PyHighlighter.tokenizeFString(text, quotePos + (triple ? 3 : 1), strEnd, tokens);
            tokens.push(new Token(strEnd, Math.min(n, strEnd + (triple ? 3 : 1)), 'str'));
          } else {
            tokens.push(new Token(i, strEnd, type));
          }
          i = strEnd;
          if (triple) {
            // 跳过结尾引号
            i = Math.min(n, strEnd + 3);
          } else {
            i = Math.min(n, strEnd + 1);
          }
          lineHasCode = true;
          blockJustOpened = false;
          continue;
        }
      }
      // 数字
      if (PyHighlighter.isDigit(c) || (c === '.' && PyHighlighter.isDigit(text.charAt(i + 1)))) {
        let j: number = i;
        while (j < n) {
          const d: string = text.charAt(j);
          const ok: boolean = PyHighlighter.isDigit(d) || d === '.' || d === '_' || d === 'x' || d === 'X'
            || d === 'o' || d === 'O' || d === 'b' || d === 'B' || d === 'e' || d === 'E'
            || (d >= 'a' && d <= 'f') || (d >= 'A' && d <= 'F') || d === 'j' || d === 'J';
          if (!ok) {
            break;
          }
          j++;
        }
        tokens.push(new Token(i, j, 'num'));
        i = j;
        lineHasCode = true;
        blockJustOpened = false;
        continue;
      }
      // 装饰器
      if (c === '@' && PyHighlighter.isIdentStart(text.charAt(i + 1))) {
        let j: number = i + 1;
        while (j < n && (PyHighlighter.isIdentPart(text.charAt(j)) || text.charAt(j) === '.')) {
          j++;
        }
        tokens.push(new Token(i, j, 'decorator'));
        i = j;
        lineHasCode = true;
        continue;
      }
      // 标识符
      if (PyHighlighter.isIdentStart(c)) {
        let j: number = i;
        while (j < n && PyHighlighter.isIdentPart(text.charAt(j))) {
          j++;
        }
        const word: string = text.substring(i, j);
        let type: string = '';
        if (word === 'self' || word === 'cls') {
          type = 'self';
        } else if (PyHighlighter.activeKeywords.has(word)) {
          type = 'kw';
          lastKeyword = word;
        } else if (lastKeyword === 'def') {
          type = 'func';
          lastKeyword = '';
        } else if (lastKeyword === 'class') {
          type = 'cls';
          lastKeyword = '';
        } else if (word === 'int' || word === 'str' || word === 'float' || word === 'bool'
          || word === 'list' || word === 'dict' || word === 'set' || word === 'tuple'
          || word === 'bytes' || word === 'object' || word === 'None' || word === 'True'
          || word === 'False' || word === 'type') {
          type = 'kwType';
        } else if (PyHighlighter.activeTypes.has(word)) {
          type = 'builtin';
        }
        if (type.length > 0) {
          tokens.push(new Token(i, j, type));
        }
        i = j;
        lineHasCode = true;
        blockJustOpened = false;
        continue;
      }
      // 冒号：标记代码块开始
      if (c === ':') {
        tokens.push(new Token(i, i + 1, 'op'));
        blockJustOpened = true;
        lineHasCode = true;
        i++;
        continue;
      }
      // 其它一律当运算符/括号
      tokens.push(new Token(i, i + 1, 'op'));
      lineHasCode = true;
      if (c !== ')' && c !== '(' && c !== ']' && c !== '[' && c !== '}' && c !== '{' && c !== ',') {
        blockJustOpened = false;
      }
      i++;
    }
    return tokens;
  }

  /** f-string 内部的 {expr} 片段单独着色 */
  private static tokenizeFString(text: string, from: number, end: number, tokens: Token[]): void {
    let i: number = from;
    const n: number = Math.min(end, text.length);
    while (i < n) {
      const c: string = text.charAt(i);
      if (c === '{' && text.charAt(i + 1) === '{') {
        i += 2;
        continue;
      }
      if (c === '}') {
        i++;
        continue;
      }
      if (c === '{') {
        let depth: number = 1;
        let j: number = i + 1;
        while (j < n && depth > 0) {
          const d: string = text.charAt(j);
          if (d === '{') {
            depth++;
          } else if (d === '}') {
            depth--;
            if (depth === 0) {
              break;
            }
          }
          j++;
        }
        tokens.push(new Token(i, Math.min(j + 1, n), 'fstr'));
        i = j + 1;
        continue;
      }
      i++;
    }
  }

  /** 返回字符串前缀长度（r/b/u/f 组合），不是字符串则返回 -1 */
  private static stringPrefixLength(text: string, i: number): number {
    const c: string = text.charAt(i);
    if (c === '"' || c === '\'') {
      return 0;
    }
    const lower: string = c.toLowerCase();
    if (lower !== 'r' && lower !== 'b' && lower !== 'u' && lower !== 'f') {
      return -1;
    }
    let j: number = i;
    let len: number = 0;
    while (j < text.length && len < 3) {
      const l: string = text.charAt(j).toLowerCase();
      if (l === 'r' || l === 'b' || l === 'u' || l === 'f') {
        j++;
        len++;
        continue;
      }
      break;
    }
    const q: string = text.charAt(j);
    if (q === '"' || q === '\'') {
      return len;
    }
    return -1;
  }

  /** 扫描字符串主体，返回结束引号/裸字符串的偏移（不含结尾引号） */
  private static scanString(text: string, quotePos: number, q: string, triple: boolean): number {
    const n: number = text.length;
    let i: number = quotePos + (triple ? 3 : 1);
    while (i < n) {
      const c: string = text.charAt(i);
      if (c === '\\') {
        i += 2;
        continue;
      }
      if (triple) {
        if (c === q && text.charAt(i + 1) === q && text.charAt(i + 2) === q) {
          return i;
        }
        i++;
        continue;
      }
      if (c === q) {
        return i;
      }
      if (c === '\n') {
        // 单引号字符串不允许换行：视为未闭合，收尾当前行
        return i;
      }
      i++;
    }
    return n;
  }

  private static indexOfOrEnd(text: string, target: string, from: number): number {
    const idx: number = text.indexOf(target, from);
    return idx < 0 ? text.length : idx;
  }

  /** 按行拆分并记录每行在全文中的偏移，供渲染与缩进使用 */
  static splitLines(text: string): LineInfo[] {
    const lines: LineInfo[] = [];
    let offset: number = 0;
    const raw: string[] = text.split('\n');
    for (const line of raw) {
      const trimmed: string = line.replace(/\r$/, '');
      let indent: number = 0;
      for (let k = 0; k < trimmed.length; k++) {
        const ch: string = trimmed.charAt(k);
        if (ch === ' ') {
          indent++;
        } else if (ch === '\t') {
          indent += 4;
        } else {
          break;
        }
      }
      lines.push(new LineInfo(trimmed, offset, indent, trimmed.trim().length === 0));
      offset += line.length + 1;
    }
    return lines;
  }

  /** 取上一行的缩进（自动缩进用），到 nonBlank 行为止 */
  static previousIndent(lines: LineInfo[], lineIndex: number): number {
    for (let k = lineIndex - 1; k >= 0; k--) {
      if (!lines[k].blank) {
        return lines[k].indent;
      }
    }
    return 0;
  }
}
