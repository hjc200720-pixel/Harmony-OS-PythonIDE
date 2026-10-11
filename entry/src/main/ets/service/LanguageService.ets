/**
 * LanguageService —— 多语言定义与识别
 *
 * 依据说明：语言的关键字、注释符、字符串引号属于**语言规范本身**（Python/Java/C++/JS… 的语法定义），
 * 不是某家 IDE 的私有数据；扩展名列表与 PyCharm 注册的文件类型一致（见 _cache/pycharm 的抽取结果）。
 * 这样 IDE 不止能编辑 Python，也能识别并高亮其它常见语言。
 */

/** 一种语言的定义 */
export class LangDef {
  id: string;
  /** 显示名（英文，PyCharm 用英文名，如 Python / Java / JavaScript） */
  name: string;
  /** 中文名（界面提示用） */
  zh: string;
  /** 关联扩展名（小写，不含点） */
  exts: string[];
  /** 关键字 */
  keywords: string[];
  /** 内置类型 */
  types: string[];
  /** 行注释前缀 */
  lineComment: string;
  /** 是否有块注释 */
  blockComment: boolean;

  constructor(id: string, name: string, zh: string, exts: string[], keywords: string[],
              types: string[], lineComment: string, blockComment: boolean) {
    this.id = id;
    this.name = name;
    this.zh = zh;
    this.exts = exts;
    this.keywords = keywords;
    this.types = types;
    this.lineComment = lineComment;
    this.blockComment = blockComment;
  }
}

const PY_KW: string[] = ['def', 'class', 'if', 'elif', 'else', 'for', 'while', 'return', 'import',
  'from', 'as', 'try', 'except', 'finally', 'with', 'lambda', 'global', 'nonlocal', 'pass',
  'break', 'continue', 'raise', 'yield', 'assert', 'del', 'in', 'is', 'not', 'and', 'or',
  'async', 'await', 'match', 'case'];
const PY_TY: string[] = ['int', 'str', 'float', 'bool', 'list', 'dict', 'set', 'tuple', 'bytes',
  'None', 'True', 'False', 'object', 'type', 'self', 'range', 'len', 'print', 'super'];

const JAVA_KW: string[] = ['abstract', 'assert', 'break', 'case', 'catch', 'class', 'const',
  'continue', 'default', 'do', 'else', 'enum', 'extends', 'final', 'finally', 'for', 'goto',
  'if', 'implements', 'import', 'instanceof', 'interface', 'native', 'new', 'package', 'private',
  'protected', 'public', 'return', 'static', 'strictfp', 'super', 'switch', 'synchronized',
  'this', 'throw', 'throws', 'transient', 'try', 'volatile', 'while', 'var', 'record', 'sealed'];
const JAVA_TY: string[] = ['boolean', 'byte', 'char', 'double', 'float', 'int', 'long', 'short',
  'void', 'String', 'Object', 'Integer', 'Long', 'Double', 'Boolean', 'List', 'Map', 'Set'];

const C_KW: string[] = ['auto', 'break', 'case', 'const', 'continue', 'default', 'do', 'else',
  'enum', 'extern', 'for', 'goto', 'if', 'register', 'return', 'sizeof', 'static', 'struct',
  'switch', 'typedef', 'union', 'volatile', 'while', 'class', 'namespace', 'template', 'public',
  'private', 'protected', 'virtual', 'override', 'new', 'delete', 'try', 'catch', 'throw',
  'using', 'nullptr', 'constexpr', 'noexcept', 'concept', 'co_await'];
const C_TY: string[] = ['bool', 'char', 'double', 'float', 'int', 'long', 'short', 'signed',
  'unsigned', 'void', 'wchar_t', 'size_t', 'string', 'vector', 'auto'];

const JS_KW: string[] = ['async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
  'debugger', 'default', 'delete', 'do', 'else', 'export', 'extends', 'finally', 'for', 'function',
  'if', 'import', 'in', 'instanceof', 'let', 'new', 'of', 'return', 'static', 'super', 'switch',
  'this', 'throw', 'try', 'typeof', 'var', 'void', 'while', 'with', 'yield', 'interface', 'type',
  'enum', 'implements', 'declare', 'readonly', 'namespace', 'as'];
const JS_TY: string[] = ['number', 'string', 'boolean', 'any', 'unknown', 'never', 'object',
  'symbol', 'bigint', 'undefined', 'null', 'Array', 'Promise', 'Map', 'Set', 'Date', 'JSON'];

const GO_KW: string[] = ['break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else',
  'fallthrough', 'for', 'func', 'go', 'goto', 'if', 'import', 'interface', 'map', 'package',
  'range', 'return', 'select', 'struct', 'switch', 'type', 'var'];
const GO_TY: string[] = ['bool', 'byte', 'complex64', 'complex128', 'error', 'float32', 'float64',
  'int', 'int8', 'int16', 'int32', 'int64', 'rune', 'string', 'uint', 'uint8', 'uint16',
  'uint32', 'uint64', 'uintptr', 'nil', 'true', 'false'];

const RUST_KW: string[] = ['as', 'async', 'await', 'break', 'const', 'continue', 'crate', 'dyn',
  'else', 'enum', 'extern', 'false', 'fn', 'for', 'if', 'impl', 'in', 'let', 'loop', 'match',
  'mod', 'move', 'mut', 'pub', 'ref', 'return', 'self', 'Self', 'static', 'struct', 'super',
  'trait', 'true', 'type', 'unsafe', 'use', 'where', 'while'];
const RUST_TY: string[] = ['bool', 'char', 'f32', 'f64', 'i8', 'i16', 'i32', 'i64', 'i128',
  'isize', 'str', 'u8', 'u16', 'u32', 'u64', 'u128', 'usize', 'String', 'Vec', 'Option', 'Result'];

const KT_KW: string[] = ['as', 'break', 'class', 'continue', 'do', 'else', 'false', 'for', 'fun',
  'if', 'in', 'interface', 'is', 'null', 'object', 'package', 'return', 'super', 'this', 'throw',
  'true', 'try', 'typealias', 'typeof', 'val', 'var', 'when', 'while', 'by', 'catch', 'constructor',
  'delegate', 'dynamic', 'field', 'file', 'finally', 'get', 'import', 'init', 'param', 'property',
  'receiver', 'set', 'setparam', 'where', 'actual', 'abstract', 'annotation', 'companion',
  'const', 'crossinline', 'data', 'enum', 'expect', 'external', 'final', 'infix', 'inline',
  'inner', 'internal', 'lateinit', 'noinline', 'open', 'operator', 'out', 'override', 'private',
  'protected', 'public', 'reified', 'sealed', 'suspend', 'tailrec', 'vararg'];
const KT_TY: string[] = ['Boolean', 'Byte', 'Char', 'Double', 'Float', 'Int', 'Long', 'Short',
  'String', 'Unit', 'Any', 'Nothing', 'List', 'Map', 'Set'];

const SQL_KW: string[] = ['select', 'from', 'where', 'insert', 'into', 'values', 'update', 'set',
  'delete', 'create', 'table', 'alter', 'drop', 'index', 'view', 'join', 'inner', 'left', 'right',
  'full', 'outer', 'on', 'group', 'by', 'order', 'having', 'limit', 'offset', 'union', 'all',
  'distinct', 'as', 'and', 'or', 'not', 'null', 'is', 'in', 'between', 'like', 'exists', 'case',
  'when', 'then', 'else', 'end', 'primary', 'key', 'foreign', 'references', 'default', 'constraint'];
const SQL_TY: string[] = ['int', 'integer', 'bigint', 'smallint', 'decimal', 'numeric', 'real',
  'double', 'float', 'char', 'varchar', 'text', 'date', 'time', 'timestamp', 'boolean', 'blob'];

const SH_KW: string[] = ['if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do', 'done',
  'case', 'esac', 'function', 'in', 'return', 'break', 'continue', 'local', 'export', 'readonly',
  'shift', 'source', 'alias', 'unalias', 'set', 'unset', 'trap', 'exit'];
const SH_TY: string[] = ['echo', 'printf', 'read', 'cd', 'pwd', 'ls', 'cp', 'mv', 'rm', 'mkdir',
  'rmdir', 'touch', 'cat', 'grep', 'sed', 'awk', 'find', 'xargs', 'chmod', 'chown', 'sudo', 'test'];

/** 全部语言（顺序即"新建文件"菜单的顺序） */
export function languages(): LangDef[] {
  return [
    new LangDef('Python', 'Python', 'Python', ['py', 'pyw', 'pyi'], PY_KW, PY_TY, '#', true),
    new LangDef('Java', 'Java', 'Java', ['java'], JAVA_KW, JAVA_TY, '//', true),
    new LangDef('Kotlin', 'Kotlin', 'Kotlin', ['kt', 'kts'], KT_KW, KT_TY, '//', true),
    new LangDef('C/C++', 'C/C++', 'C/C++', ['c', 'h', 'cpp', 'cc', 'cxx', 'hpp', 'hh', 'hxx'],
      C_KW, C_TY, '//', true),
    new LangDef('JavaScript', 'JavaScript', 'JavaScript', ['js', 'mjs', 'cjs', 'jsx'],
      JS_KW, JS_TY, '//', true),
    new LangDef('TypeScript', 'TypeScript', 'TypeScript', ['ts', 'tsx'], JS_KW, JS_TY, '//', true),
    new LangDef('Go', 'Go', 'Go', ['go'], GO_KW, GO_TY, '//', true),
    new LangDef('Rust', 'Rust', 'Rust', ['rs'], RUST_KW, RUST_TY, '//', true),
    new LangDef('HTML', 'HTML', 'HTML', ['html', 'htm', 'xhtml'], [], [], '<!--', true),
    new LangDef('CSS', 'CSS', 'CSS', ['css', 'scss', 'sass', 'less'], [], [], '/*', true),
    new LangDef('JSON', 'JSON', 'JSON', ['json', 'json5'], [], ['true', 'false', 'null'], '//', false),
    new LangDef('YAML', 'YAML', 'YAML', ['yml', 'yaml'], [], [], '#', false),
    new LangDef('XML', 'XML', 'XML', ['xml', 'xsd', 'xsl', 'svg', 'plist'], [], [], '<!--', true),
    new LangDef('Markdown', 'Markdown', 'Markdown', ['md', 'markdown'], [], [], '', false),
    new LangDef('SQL', 'SQL', 'SQL', ['sql', 'ddl', 'dml'], SQL_KW, SQL_TY, '--', true),
    new LangDef('Shell Script', 'Shell Script', 'Shell 脚本', ['sh', 'bash', 'zsh', 'fish'],
      SH_KW, SH_TY, '#', false),
    new LangDef('Properties', 'Properties', '属性文件', ['properties', 'ini', 'cfg', 'conf'], [],
      [], '#', false),
    new LangDef('Diff', 'Diff', 'Diff', ['diff', 'patch'], [], [], '', false),
    new LangDef('Dockerfile', 'Dockerfile', 'Dockerfile', ['dockerfile'], SH_KW, SH_TY, '#', false),
    new LangDef('Plain Text', 'Text', '纯文本', ['txt', 'log', 'text'], [], [], '', false)
  ];
}

/** 按文件名/路径识别语言（找不到时返回纯文本） */
export function languageOf(fileName: string): LangDef {
  const all: LangDef[] = languages();
  const lower: string = fileName.toLowerCase();
  let ext: string = '';
  const dot: number = lower.lastIndexOf('.');
  if (dot >= 0) {
    ext = lower.substring(dot + 1);
  } else if (lower.indexOf('dockerfile') >= 0) {
    ext = 'dockerfile';
  }
  for (let i = 0; i < all.length; i++) {
    if (all[i].exts.indexOf(ext) >= 0) {
      return all[i];
    }
  }
  return all[all.length - 1];
}

/** 该语言里 word 是不是关键字 */
export function isKeyword(lang: LangDef, word: string): boolean {
  return lang.keywords.indexOf(word) >= 0;
}

/** 该语言里 word 是不是内置类型 */
export function isType(lang: LangDef, word: string): boolean {
  return lang.types.indexOf(word) >= 0;
}

/** 语言显示名（状态栏"类型:"用） */
export function languageLabel(fileName: string): string {
  return languageOf(fileName).name;
}
