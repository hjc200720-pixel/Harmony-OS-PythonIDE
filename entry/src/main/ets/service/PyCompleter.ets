/**
 * PyCompleter —— 代码补全引擎（纯 ArkTS，无原生往返，输入即出候选）
 *
 * 为什么不走解释器：补全要在每次按键后立刻出结果，跨 NAPI + 抢 GIL 的往返太慢，
 * 而且解释器只能看到"已经运行过"的对象。这里采用 PyCharm 式的**静态**思路：
 *   1. 关键字、内置函数
 *   2. 当前文档里定义的符号（def / class / 赋值 / 参数）
 *   3. 已 import 的模块名（含 as 别名、from ... import ... 的名字）
 *   4. 常用模块/类型的成员表（sys./os./json./str./list. …）
 * 覆盖日常写代码时最常用的那一批，延迟为零。
 */

/** 一条补全候选 */
export class CompletionItem {
  /** 插入的文本 */
  text: string = '';
  /** 类别：keyword / builtin / symbol / class / module / attr / param */
  kind: string = 'text';
  /** 右侧说明（模块名或所属对象） */
  detail: string = '';

  constructor(text: string, kind: string, detail: string = '') {
    this.text = text;
    this.kind = kind;
    this.detail = detail;
  }
}

const KEYWORDS: string[] = [
  'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await', 'break', 'class',
  'continue', 'def', 'del', 'elif', 'else', 'except', 'finally', 'for', 'from', 'global',
  'if', 'import', 'in', 'is', 'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise',
  'return', 'try', 'while', 'with', 'yield'
];

const BUILTINS: string[] = [
  'abs', 'all', 'any', 'ascii', 'bin', 'bool', 'bytearray', 'bytes', 'callable', 'chr',
  'classmethod', 'compile', 'complex', 'delattr', 'dict', 'dir', 'divmod', 'enumerate',
  'eval', 'exec', 'filter', 'float', 'format', 'frozenset', 'getattr', 'globals',
  'hasattr', 'hash', 'help', 'hex', 'id', 'input', 'int', 'isinstance', 'issubclass',
  'iter', 'len', 'list', 'locals', 'map', 'max', 'min', 'next', 'object', 'oct', 'open',
  'ord', 'pow', 'print', 'property', 'range', 'repr', 'reversed', 'round', 'set',
  'setattr', 'slice', 'sorted', 'staticmethod', 'str', 'sum', 'super', 'tuple', 'type',
  'vars', 'zip'
];

/** 常用模块 / 内置类型的成员（静态表，取日常最常用的那一批） */
const MEMBERS: Record<string, string[]> = {
  'sys': ['argv', 'exit', 'path', 'platform', 'stdin', 'stdout', 'stderr', 'version',
    'version_info', 'maxsize', 'modules', 'executable', 'getrecursionlimit', 'setrecursionlimit'],
  'os': ['getcwd', 'listdir', 'mkdir', 'makedirs', 'remove', 'rename', 'rmdir', 'path',
    'environ', 'sep', 'linesep', 'system', 'walk', 'stat', 'getenv', 'chdir', 'name'],
  'os.path': ['abspath', 'basename', 'dirname', 'exists', 'isdir', 'isfile', 'join',
    'splitext', 'split', 'relpath', 'expanduser', 'getsize'],
  'math': ['sqrt', 'pow', 'floor', 'ceil', 'fabs', 'pi', 'e', 'sin', 'cos', 'tan', 'log',
    'log10', 'exp', 'factorial', 'gcd', 'hypot', 'inf', 'nan'],
  'json': ['dumps', 'loads', 'dump', 'load', 'JSONDecodeError'],
  'random': ['random', 'randint', 'randrange', 'choice', 'shuffle', 'sample', 'seed',
    'uniform', 'gauss'],
  'time': ['time', 'sleep', 'localtime', 'strftime', 'strptime', 'perf_counter', 'ctime'],
  're': ['compile', 'match', 'search', 'findall', 'finditer', 'sub', 'split', 'escape',
    'IGNORECASE', 'MULTILINE', 'DOTALL', 'Pattern', 'Match'],
  'platform': ['system', 'machine', 'node', 'platform', 'python_version', 'release', 'processor'],
  'pathlib': ['Path', 'PurePath', 'PosixPath'],
  'datetime': ['datetime', 'date', 'time', 'timedelta', 'timezone', 'now', 'today'],
  'collections': ['Counter', 'defaultdict', 'OrderedDict', 'deque', 'namedtuple', 'ChainMap'],
  'itertools': ['count', 'cycle', 'repeat', 'chain', 'combinations', 'permutations',
    'product', 'groupby', 'islice', 'accumulate'],
  'functools': ['reduce', 'partial', 'lru_cache', 'wraps', 'cmp_to_key', 'total_ordering'],
  'typing': ['Any', 'Dict', 'List', 'Optional', 'Tuple', 'Union', 'Callable', 'Iterable',
    'Sequence', 'TypeVar', 'cast'],
  'threading': ['Thread', 'Lock', 'RLock', 'Event', 'Condition', 'Semaphore', 'current_thread'],
  'subprocess': ['run', 'Popen', 'check_output', 'PIPE', 'CalledProcessError'],
  'asyncio': ['run', 'sleep', 'gather', 'create_task', 'get_event_loop', 'Queue', 'wait_for'],
  'zipfile': ['ZipFile', 'ZipInfo', 'is_zipfile', 'ZIP_DEFLATED'],
  'hashlib': ['sha256', 'md5', 'sha1', 'blake2b', 'new'],
  'sqlite3': ['connect', 'Connection', 'Cursor', 'Row'],
  'str': ['capitalize', 'casefold', 'center', 'count', 'encode', 'endswith', 'find',
    'format', 'index', 'isalnum', 'isalpha', 'isdigit', 'islower', 'isspace', 'isupper',
    'join', 'lower', 'lstrip', 'replace', 'rfind', 'rindex', 'rstrip', 'split',
    'splitlines', 'startswith', 'strip', 'swapcase', 'title', 'upper', 'zfill'],
  'list': ['append', 'clear', 'copy', 'count', 'extend', 'index', 'insert', 'pop',
    'remove', 'reverse', 'sort'],
  'dict': ['clear', 'copy', 'fromkeys', 'get', 'items', 'keys', 'pop', 'popitem',
    'setdefault', 'update', 'values'],
  'set': ['add', 'clear', 'copy', 'difference', 'discard', 'intersection', 'issubset',
    'issuperset', 'pop', 'remove', 'union', 'update'],
  'tuple': ['count', 'index'],
  'self': []
};

/** 光标前那个"点号表达式"片段（只含标识符字符与点） */
function prefixAt(text: string, offset: number): string {
  let i: number = offset;
  while (i > 0) {
    const ch: string = text.charAt(i - 1);
    const isWord: boolean = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
      || (ch >= '0' && ch <= '9') || ch === '_';
    if (isWord || ch === '.') {
      i--;
    } else {
      break;
    }
  }
  return text.substring(i, offset);
}

/** 扫描文档里定义的符号 */
function documentSymbols(text: string): Map<string, string> {
  const out: Map<string, string> = new Map<string, string>();
  const lines: string[] = text.split('\n');
  for (const raw of lines) {
    const line: string = raw.trim();
    if (line.startsWith('def ') || line.startsWith('async def ')) {
      const start: number = line.startsWith('async def ') ? 10 : 4;
      out.set(identifierAt(line, start), 'symbol');
    } else if (line.startsWith('class ')) {
      out.set(identifierAt(line, 6), 'class');
    } else {
      // 赋值：name = / name: type = （排除 == 比较）
      const ident: string = identifierAt(line, 0);
      if (ident.length > 0) {
        const rest: string = line.substring(ident.length).trim();
        if (rest.startsWith('=') && !rest.startsWith('==')) {
          if (!out.has(ident)) {
            out.set(ident, 'symbol');
          }
        } else if (rest.startsWith(':') && rest.includes('=')) {
          if (!out.has(ident)) {
            out.set(ident, 'symbol');
          }
        }
      }
    }
  }
  return out;
}

/** 取从 start 开始的标识符 */
function identifierAt(line: string, start: number): string {
  let result: string = '';
  for (let i: number = start; i < line.length; i++) {
    const ch: string = line.charAt(i);
    const ok: boolean = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
      || (ch >= '0' && ch <= '9') || ch === '_';
    if (ok) {
      result += ch;
    } else {
      break;
    }
  }
  return result;
}

/** 扫描 import，返回 名字 -> 模块（含 from ... import） */
function importedNames(text: string): Map<string, string> {
  const out: Map<string, string> = new Map<string, string>();
  const lines: string[] = text.split('\n');
  for (const raw of lines) {
    const line: string = raw.trim();
    if (line.startsWith('import ')) {
      for (const partRaw of line.substring(7).split(',')) {
        const part: string = partRaw.trim();
        if (part.length === 0) {
          continue;
        }
        const asIndex: number = part.indexOf(' as ');
        if (asIndex > 0) {
          out.set(part.substring(asIndex + 4).trim(), part.substring(0, asIndex).trim());
        } else {
          const top: string = part.split('.')[0];
          out.set(top, part);
        }
      }
    } else if (line.startsWith('from ')) {
      const idx: number = line.indexOf(' import ');
      if (idx > 7) {
        const module: string = line.substring(5, idx).trim();
        for (const nameRaw of line.substring(idx + 8).split(',')) {
          const name: string = nameRaw.trim();
          if (name.length > 0 && name !== '*') {
            const asIndex: number = name.indexOf(' as ');
            if (asIndex > 0) {
              out.set(name.substring(asIndex + 4).trim(), module);
            } else {
              out.set(name, module);
            }
          }
        }
      }
    }
  }
  return out;
}

export class PyCompleter {
  /** 候选上限，避免弹层过长 */
  static readonly LIMIT: number = 12;

  /**
   * 计算补全候选。offset 为光标在 text 中的绝对偏移。
   * 返回按"前缀匹配 + 类别优先级"排序后的列表（可能为空）。
   */
  static complete(text: string, offset: number): CompletionItem[] {
    if (offset <= 0 || offset > text.length) {
      return [];
    }
    const prefix: string = prefixAt(text, offset);
    const parts: string[] = prefix.split('.');
    const head: string = parts[0];
    const tail: string = parts[parts.length - 1];
    const result: CompletionItem[] = [];

    if (parts.length === 1) {
      // ① 顶层：关键字 / 内置 / 文档符号 / 已导入名字
      for (const kw of KEYWORDS) {
        if (kw.toLowerCase().startsWith(tail.toLowerCase()) && tail.length > 0) {
          result.push(new CompletionItem(kw, 'keyword', 'keyword'));
        }
      }
      for (const bi of BUILTINS) {
        if (bi.toLowerCase().startsWith(tail.toLowerCase()) && tail.length > 0) {
          result.push(new CompletionItem(bi, 'builtin', 'builtin'));
        }
      }
      const symbols: Map<string, string> = documentSymbols(text);
      symbols.forEach((kind: string, name: string) => {
        if (name.toLowerCase().startsWith(tail.toLowerCase()) && name.length > 0) {
          result.push(new CompletionItem(name, kind, '当前文件'));
        }
      });
      const imports: Map<string, string> = importedNames(text);
      imports.forEach((module: string, name: string) => {
        if (name.toLowerCase().startsWith(tail.toLowerCase()) && name.length > 0) {
          result.push(new CompletionItem(name, 'module', module));
        }
      });
    } else {
      // ② 属性：obj.attr —— obj 可能是模块、也可能是 self/类实例
      const base: string = parts[0];
      const members: string[] | undefined = MEMBERS[base];
      if (members !== undefined) {
        for (const m of members) {
          if (m.toLowerCase().startsWith(tail.toLowerCase())) {
            result.push(new CompletionItem(m, 'attr', base));
          }
        }
      } else {
        // 未登记的模块名 -> 用它自己的成员表（若在表里以点号前缀存在）
        const imports: Map<string, string> = importedNames(text);
        const module: string | undefined = imports.get(base);
        if (module !== undefined) {
          const fromModule: string[] | undefined = MEMBERS[module];
          if (fromModule !== undefined) {
            for (const m of fromModule) {
              if (m.toLowerCase().startsWith(tail.toLowerCase())) {
                result.push(new CompletionItem(m, 'attr', module));
              }
            }
          }
        }
        if (base === 'self') {
          const symbols: Map<string, string> = documentSymbols(text);
          symbols.forEach((kind: string, name: string) => {
            if (kind === 'symbol' && name.toLowerCase().startsWith(tail.toLowerCase())) {
              result.push(new CompletionItem(name, 'attr', 'self'));
            }
          });
        }
      }
    }

    // 去重 + 截断
    const seen: Set<string> = new Set<string>();
    const deduped: CompletionItem[] = [];
    for (const item of result) {
      if (item.text.length === 0 || seen.has(item.text)) {
        continue;
      }
      seen.add(item.text);
      deduped.push(item);
      if (deduped.length >= PyCompleter.LIMIT) {
        break;
      }
    }
    return deduped;
  }

  /** 光标前的表达式片段长度（接受候选时要替换掉它） */
  static prefixLength(text: string, offset: number): number {
    return prefixAt(text, offset).length;
  }

  /** 候选左侧的小标记（单字符，避免引入更多图标资源） */
  static markOf(kind: string): string {
    if (kind === 'keyword') {
      return 'K';
    }
    if (kind === 'builtin') {
      return 'B';
    }
    if (kind === 'class') {
      return 'C';
    }
    if (kind === 'module') {
      return 'M';
    }
    if (kind === 'attr') {
      return 'a';
    }
    return 'f';
  }
}
