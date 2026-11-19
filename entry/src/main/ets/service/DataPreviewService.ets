/**
 * DataPreviewService —— 「数据视图（SciView）」工具窗的服务层
 *
 * 纯函数、零副作用：不做文件 IO、不依赖 ArkUI / Ability / Context，
 * 输入「文件文本 + 文件名」，输出可直接渲染成表格的 DataTable。
 *
 * 支持类型：.csv / .tsv / .tab / .json（扩展名大小写不敏感）
 * - CSV/TSV：RFC4180 引号语义（引号字段内可含分隔符、换行，"" 表示一个双引号），
 *   表头取第一个非空行，空表头单元格命名「列N」（N 从 1 起），整行全空的数据行跳过；
 * - JSON：顶层数组（对象数组 / 数组的数组 / 标量数组）或顶层对象（键 / 值两列）。
 *
 * 安全边界：
 * - 单次最多保留 DATA_PREVIEW_MAX_COLUMNS 列，超出丢弃并在 message 注明；
 * - maxRows 由调用方给，内部 clamp 到 1..1000，超出部分截断并在 message 注明；
 * - JSON 解析用本文件内的只读解析器实现（不依赖平台 JSON 解析接口的宽松返回类型，
 *   避免 ArkTS 严格模式下的类型问题）；任何解析失败只返回 ok=false，绝不抛异常。
 */

/** 单次预览的数据行数参考上限（调用方仍可传更小的 maxRows） */
export const DATA_PREVIEW_MAX_ROWS: number = 200;
/** 单次预览最多保留的列数 */
export const DATA_PREVIEW_MAX_COLUMNS: number = 40;

/** maxRows 的内部硬上限（防止调用方传入过大值拖垮渲染） */
const MAX_ROWS_LIMIT: number = 1000;
/** JSON 对象 / 数组值转成单元格文本时的最大字符数（含省略号前的部分） */
const JSON_CELL_MAX_CHARS: number = 120;
/** JSON 解析允许的最大嵌套层级（防病态输入导致递归栈溢出） */
const JSON_MAX_DEPTH: number = 200;

/** 分隔符探测候选，顺序决定了平手时的优先级（平手取逗号） */
const DELIMITER_CANDIDATES: string[] = [',', '\t', ';', '|'];

/** 一张可直接渲染成表格的预览结果 */
export class DataTable {
  /** 是否成功解析出可显示的数据 */
  ok: boolean = false;
  /** 文件名（不含目录） */
  source: string = '';
  /** CSV / TSV / JSON */
  kind: string = '';
  /** 表头（空表头单元格已命名为「列N」） */
  headers: string[] = [];
  /** 数据行；每行长度一定等于 headers.length（不足补空串，多余丢弃） */
  rows: string[][] = [];
  /** 截断前的完整数据行数 */
  totalRows: number = 0;
  /** 列数，恒等于 headers.length */
  columns: number = 0;
  /** 是否因 maxRows 被截断 */
  truncated: boolean = false;
  /** ok=false 的原因，或截断 / 列数超限等提示 */
  message: string = '';
}

/** 去掉 UTF-8 BOM（如果存在） */
function stripBom(text: string): string {
  if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) {
    return text.substring(1);
  }
  return text;
}

/** 把反斜杠统一成正斜杠（Windows 路径文件名兼容） */
function normalizeSlashes(fileName: string): string {
  let out: string = '';
  for (let i: number = 0; i < fileName.length; i++) {
    const ch: string = fileName.charAt(i);
    out += ch === '\\' ? '/' : ch;
  }
  return out;
}

/** 是否为数据视图支持的文件名（.csv / .tsv / .tab / .json，大小写不敏感） */
export function isDataFileName(fileName: string): boolean {
  const name: string = normalizeSlashes(fileName);
  const dot: number = name.lastIndexOf('.');
  if (dot < 0) {
    return false;
  }
  const ext: string = name.substring(dot).toLowerCase();
  return ext === '.csv' || ext === '.tsv' || ext === '.tab' || ext === '.json';
}

/** 取文件名（不含目录） */
function fileNameOf(fileName: string): string {
  const name: string = normalizeSlashes(fileName);
  const slash: number = name.lastIndexOf('/');
  return slash >= 0 ? name.substring(slash + 1) : name;
}

/** 取小写扩展名（含点号，如 ".csv"；没有扩展名时返回空串） */
function extensionOf(fileName: string): string {
  const name: string = fileNameOf(fileName).toLowerCase();
  const dot: number = name.lastIndexOf('.');
  return dot >= 0 ? name.substring(dot) : '';
}

/** 把调用方给的 maxRows clamp 到 1..1000（NaN / 0 / 负数都按 1 处理） */
function clampMaxRows(maxRows: number): number {
  let n: number = Math.floor(maxRows);
  if (!(n >= 1)) {
    return 1;
  }
  if (n > MAX_ROWS_LIMIT) {
    return MAX_ROWS_LIMIT;
  }
  return n;
}

/** 空表头 / 数组的数组的列名：列1、列2 ... */
function columnName(index: number): string {
  return '列' + (index + 1).toString();
}

/** 整行是否全空（所有单元格都是空串） */
function isBlankRow(cells: string[]): boolean {
  for (let i: number = 0; i < cells.length; i++) {
    if (cells[i].length > 0) {
      return false;
    }
  }
  return true;
}

/** 列数超限提示 */
function columnCapNote(totalColumns: number): string {
  return '列数超过上限：仅显示前 ' + DATA_PREVIEW_MAX_COLUMNS + ' 列（共 ' + totalColumns + ' 列）';
}

/** 文本截断：超出 maxChars 时保留前 maxChars 个字符并追加省略号 */
function truncateText(text: string, maxChars: number): string {
  if (text.length <= maxChars) {
    return text;
  }
  return text.substring(0, maxChars) + '…';
}

/**
 * 统一收尾：写 totalRows / truncated / message / ok。
 * rows 由调用方按 limit 预先裁剪；notes 是列数超限等附加提示（会被拼进 message）。
 */
function finishTable(table: DataTable, total: number, limit: number, notes: string[]): DataTable {
  table.totalRows = total;
  table.truncated = total > limit;
  if (total === 0) {
    table.ok = false;
    table.message = '没有数据行';
    return table;
  }
  table.ok = true;
  if (table.truncated) {
    notes.push('已截断：显示前 ' + limit + ' 行，共 ' + total + ' 行');
  }
  table.message = notes.join('；');
  return table;
}

/**
 * 取「表头行」：第一个非空逻辑行（引号内的换行不算行尾）。
 * 只用于分隔符探测，不做字段切分。
 */
function firstHeaderLine(text: string): string {
  const s: string = stripBom(text);
  let start: number = 0;
  let inQuotes: boolean = false;
  let i: number = 0;
  while (i <= s.length) {
    const atEnd: boolean = i >= s.length;
    const ch: string = atEnd ? '\n' : s.charAt(i);
    if (!atEnd && ch === '"') {
      if (inQuotes && i + 1 < s.length && s.charAt(i + 1) === '"') {
        i += 2;
        continue;
      }
      inQuotes = !inQuotes;
      i++;
      continue;
    }
    if (!atEnd && inQuotes) {
      i++;
      continue;
    }
    if (atEnd || ch === '\n' || ch === '\r') {
      const line: string = s.substring(start, i);
      if (line.trim().length > 0) {
        return line;
      }
      if (!atEnd && ch === '\r' && i + 1 < s.length && s.charAt(i + 1) === '\n') {
        i += 2;
      } else {
        i++;
      }
      start = i;
      continue;
    }
    i++;
  }
  return '';
}

/**
 * 探测 CSV 分隔符：对表头行统计引号外的 , \t ; | 出现次数，多者胜，平手取逗号。
 */
export function detectDelimiter(text: string): string {
  const header: string = firstHeaderLine(text);
  const counts: number[] = [0, 0, 0, 0];
  let inQuotes: boolean = false;
  for (let i: number = 0; i < header.length; i++) {
    const ch: string = header.charAt(i);
    if (ch === '"') {
      if (inQuotes && i + 1 < header.length && header.charAt(i + 1) === '"') {
        i++;
        continue;
      }
      inQuotes = !inQuotes;
      continue;
    }
    if (inQuotes) {
      continue;
    }
    for (let c: number = 0; c < DELIMITER_CANDIDATES.length; c++) {
      if (ch === DELIMITER_CANDIDATES[c]) {
        counts[c] = counts[c] + 1;
      }
    }
  }
  let best: number = 0;
  for (let c: number = 1; c < counts.length; c++) {
    if (counts[c] > counts[best]) {
      best = c;
    }
  }
  return DELIMITER_CANDIDATES[best];
}

/**
 * CSV 记录读取器（RFC4180 的宽松实现）：
 * - 双引号字段内可含分隔符 / 换行 / "" 转义；
 * - 未加引号的字段去掉首尾空格，加引号的字段原样保留；
 * - CRLF / LF / 单独 CR 都算行尾；引号内的 CRLF 归一成 LF；
 * - 行尾 / 文件尾都会收口最后一个字段。
 */
class CsvReader {
  text: string = '';
  delimiter: string = ',';
  pos: number = 0;
  cell: string = '';
  cellQuoted: boolean = false;
  cellStarted: boolean = false;
  inQuotes: boolean = false;
  afterClose: boolean = false;
  record: string[] = [];
  records: string[][] = [];
  error: string = '';

  /** 解析整段文本，结果写入 records / error */
  run(text: string, delimiter: string): void {
    this.text = stripBom(text);
    this.delimiter = delimiter.length > 0 ? delimiter.charAt(0) : ',';
    this.pos = 0;
    this.cell = '';
    this.cellQuoted = false;
    this.cellStarted = false;
    this.inQuotes = false;
    this.afterClose = false;
    this.record = [];
    this.records = [];
    this.error = '';
    while (this.pos < this.text.length) {
      const ch: string = this.text.charAt(this.pos);
      if (this.inQuotes) {
        this.consumeQuotedChar(ch);
        continue;
      }
      // 引号闭合后、分隔符前的空白不属于字段内容
      if (this.afterClose && (ch === ' ' || ch === '\t')) {
        this.pos++;
        continue;
      }
      if (ch === this.delimiter) {
        this.pushCell();
        this.pos++;
        continue;
      }
      if (ch === '\n' || ch === '\r') {
        this.pushCell();
        this.pushRecord();
        if (ch === '\r' && this.pos + 1 < this.text.length && this.text.charAt(this.pos + 1) === '\n') {
          this.pos += 2;
        } else {
          this.pos++;
        }
        continue;
      }
      if (ch === '"') {
        // 字段开头（允许前面只有空格）的引号开启引号字段；此时丢弃前置空格
        const onlySpaces: boolean = !this.cellQuoted && this.cell.trim().length === 0;
        if (!this.cellStarted || onlySpaces) {
          this.cell = '';
          this.inQuotes = true;
          this.cellQuoted = true;
          this.cellStarted = true;
        } else {
          // 非字段开头的引号按普通字符处理（宽松策略）
          this.cell += '"';
        }
        this.pos++;
        continue;
      }
      this.cell += ch;
      this.cellStarted = true;
      this.afterClose = false;
      this.pos++;
    }
    if (this.inQuotes) {
      this.error = 'CSV 解析失败：引号未闭合';
      return;
    }
    if (this.record.length > 0 || this.cellStarted) {
      this.pushCell();
      this.pushRecord();
    }
  }

  /** 引号字段内部字符消费 */
  consumeQuotedChar(ch: string): void {
    if (ch === '"') {
      if (this.pos + 1 < this.text.length && this.text.charAt(this.pos + 1) === '"') {
        this.cell += '"';
        this.pos += 2;
        return;
      }
      this.inQuotes = false;
      this.afterClose = true;
      this.pos++;
      return;
    }
    if (ch === '\r') {
      this.cell += '\n';
      if (this.pos + 1 < this.text.length && this.text.charAt(this.pos + 1) === '\n') {
        this.pos += 2;
      } else {
        this.pos++;
      }
      return;
    }
    this.cell += ch;
    this.pos++;
  }

  /** 收口当前字段（未加引号则 trim） */
  pushCell(): void {
    let value: string = this.cell;
    if (!this.cellQuoted) {
      value = value.trim();
    }
    this.record.push(value);
    this.cell = '';
    this.cellQuoted = false;
    this.cellStarted = false;
    this.afterClose = false;
  }

  /** 收口当前行 */
  pushRecord(): void {
    this.records.push(this.record);
    this.record = [];
  }
}

/**
 * 解析 CSV / TSV 文本为 DataTable。
 * 表头 = 第一个非空行；数据行跳过整行全空的行；列数、行数按上限裁剪。
 */
export function parseCsvTable(text: string, delimiter: string, maxRows: number): DataTable {
  const table: DataTable = new DataTable();
  const limit: number = clampMaxRows(maxRows);
  const sep: string = delimiter.length > 0 ? delimiter.charAt(0) : ',';
  table.kind = sep === '\t' ? 'TSV' : 'CSV';

  const reader: CsvReader = new CsvReader();
  reader.run(text, sep);
  if (reader.error.length > 0) {
    table.message = reader.error;
    return table;
  }

  const records: string[][] = reader.records;
  let headerIndex: number = -1;
  for (let i: number = 0; i < records.length; i++) {
    if (!isBlankRow(records[i])) {
      headerIndex = i;
      break;
    }
  }
  if (headerIndex < 0) {
    table.message = stripBom(text).trim().length === 0 ? '文件为空' : '没有表头行';
    return table;
  }

  const headerCells: string[] = records[headerIndex];
  const headerCount: number = headerCells.length;
  const colCount: number = headerCount > DATA_PREVIEW_MAX_COLUMNS ? DATA_PREVIEW_MAX_COLUMNS : headerCount;
  const headers: string[] = [];
  for (let c: number = 0; c < colCount; c++) {
    const cell: string = headerCells[c];
    headers.push(cell.length === 0 ? columnName(c) : cell);
  }
  table.headers = headers;
  table.columns = colCount;

  let total: number = 0;
  const rows: string[][] = [];
  for (let i: number = headerIndex + 1; i < records.length; i++) {
    const record: string[] = records[i];
    if (isBlankRow(record)) {
      continue;
    }
    total++;
    if (rows.length < limit) {
      const cells: string[] = [];
      for (let c: number = 0; c < colCount; c++) {
        cells.push(c < record.length ? record[c] : '');
      }
      rows.push(cells);
    }
  }
  table.rows = rows;

  const notes: string[] = [];
  if (headerCount > DATA_PREVIEW_MAX_COLUMNS) {
    notes.push(columnCapNote(headerCount));
  }
  return finishTable(table, total, limit, notes);
}

/** JSON 值的中间表示（只读解析器的输出，避免宽松 / 动态类型） */
class JsonValue {
  /** null / boolean / number / string / array / object / invalid */
  kind: string = 'null';
  /** kind=string 时的解码后文本；kind=number 时的原始词法 */
  text: string = '';
  /** kind=number 时的数值 */
  num: number = 0;
  /** kind=boolean 时的值 */
  bool: boolean = false;
  /** kind=array 时的元素 */
  items: JsonValue[] = [];
  /** kind=object 时的键（保持首次出现顺序） */
  keys: string[] = [];
  /** kind=object 时与 keys 一一对应的值 */
  values: JsonValue[] = [];
}

/**
 * 只读 JSON 解析器：递归下降，失败只记录 error，不抛异常。
 * 覆盖 RFC8259 的完整语法（对象 / 数组 / 字符串含转义 / 数字 / true/false/null）。
 */
class JsonParser {
  text: string = '';
  pos: number = 0;
  depth: number = 0;
  error: string = '';

  /** 解析整段文本；调用后检查 error */
  parse(text: string): JsonValue {
    this.text = text;
    this.pos = 0;
    this.depth = 0;
    this.error = '';
    this.skipWs();
    const value: JsonValue = this.readValue();
    if (this.error.length === 0) {
      this.skipWs();
      if (this.pos < this.text.length) {
        this.error = '多余的内容（位置 ' + this.pos + '）';
      }
    }
    return value;
  }

  /** 跳过空白 */
  skipWs(): void {
    while (this.pos < this.text.length) {
      const ch: string = this.text.charAt(this.pos);
      if (ch === ' ' || ch === '\t' || ch === '\r' || ch === '\n') {
        this.pos++;
      } else {
        break;
      }
    }
  }

  /** 读取一个值（带嵌套深度保护，避免病态输入导致递归栈溢出） */
  readValue(): JsonValue {
    this.skipWs();
    if (this.error.length > 0) {
      return new JsonValue();
    }
    if (this.depth >= JSON_MAX_DEPTH) {
      this.error = '嵌套层级过深（上限 ' + JSON_MAX_DEPTH + ' 层）';
      return new JsonValue();
    }
    this.depth++;
    const value: JsonValue = this.readValueInner();
    this.depth--;
    return value;
  }

  /** 读取一个值（内部实现，不含深度计数） */
  readValueInner(): JsonValue {
    this.skipWs();
    if (this.error.length > 0) {
      return new JsonValue();
    }
    if (this.pos >= this.text.length) {
      this.error = '内容意外结束';
      return new JsonValue();
    }
    const ch: string = this.text.charAt(this.pos);
    if (ch === '{') {
      return this.readObject();
    }
    if (ch === '[') {
      return this.readArray();
    }
    if (ch === '"') {
      return this.readString();
    }
    if (ch === 't') {
      return this.readLiteral('true', 'boolean', true);
    }
    if (ch === 'f') {
      return this.readLiteral('false', 'boolean', false);
    }
    if (ch === 'n') {
      return this.readLiteral('null', 'null', false);
    }
    const code: number = ch.charCodeAt(0);
    if (ch === '-' || (code >= 48 && code <= 57)) {
      return this.readNumber();
    }
    this.error = '意外的字符 "' + ch + '"（位置 ' + this.pos + '）';
    return new JsonValue();
  }

  /** 读取 true / false / null 字面量 */
  readLiteral(literal: string, kind: string, boolValue: boolean): JsonValue {
    const value: JsonValue = new JsonValue();
    if (this.text.substring(this.pos, this.pos + literal.length) !== literal) {
      this.error = '非法的字面量（位置 ' + this.pos + '）';
      return value;
    }
    this.pos += literal.length;
    value.kind = kind;
    value.bool = boolValue;
    return value;
  }

  /** 读取字符串（含转义） */
  readString(): JsonValue {
    const value: JsonValue = new JsonValue();
    value.kind = 'string';
    this.pos++;
    let out: string = '';
    while (this.pos < this.text.length) {
      const ch: string = this.text.charAt(this.pos);
      if (ch === '"') {
        this.pos++;
        value.text = out;
        return value;
      }
      if (ch === '\\') {
        this.pos++;
        if (this.pos >= this.text.length) {
          this.error = '字符串转义不完整';
          return value;
        }
        const esc: string = this.text.charAt(this.pos);
        if (esc === '"') {
          out += '"';
        } else if (esc === '\\') {
          out += '\\';
        } else if (esc === '/') {
          out += '/';
        } else if (esc === 'b') {
          out += '\b';
        } else if (esc === 'f') {
          out += '\f';
        } else if (esc === 'n') {
          out += '\n';
        } else if (esc === 'r') {
          out += '\r';
        } else if (esc === 't') {
          out += '\t';
        } else if (esc === 'u') {
          if (this.pos + 4 >= this.text.length) {
            this.error = '\\u 转义不完整';
            return value;
          }
          const hex: string = this.text.substring(this.pos + 1, this.pos + 5);
          if (!/^[0-9a-fA-F]{4}$/.test(hex)) {
            this.error = '非法的 \\u 转义 "\\u' + hex + '"';
            return value;
          }
          out += String.fromCharCode(Number.parseInt(hex, 16));
          this.pos += 4;
        } else {
          this.error = '未知的转义字符 \\' + esc;
          return value;
        }
        this.pos++;
        continue;
      }
      if (ch.charCodeAt(0) < 0x20) {
        this.error = '字符串中出现未转义的控制字符（位置 ' + this.pos + '）';
        return value;
      }
      out += ch;
      this.pos++;
    }
    this.error = '字符串未闭合';
    return value;
  }

  /** 读取数字 */
  readNumber(): JsonValue {
    const value: JsonValue = new JsonValue();
    value.kind = 'number';
    const start: number = this.pos;
    while (this.pos < this.text.length) {
      const ch: string = this.text.charAt(this.pos);
      const code: number = ch.charCodeAt(0);
      const isDigit: boolean = code >= 48 && code <= 57;
      if (isDigit || ch === '-' || ch === '+' || ch === '.' || ch === 'e' || ch === 'E') {
        this.pos++;
      } else {
        break;
      }
    }
    const token: string = this.text.substring(start, this.pos);
    if (!/^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/.test(token)) {
      this.error = '非法的数字 "' + token + '"（位置 ' + start + '）';
      return value;
    }
    const parsed: number = Number.parseFloat(token);
    if (!Number.isFinite(parsed)) {
      this.error = '数字超出可表示范围 "' + token + '"';
      return value;
    }
    value.num = parsed;
    value.text = token;
    return value;
  }

  /** 读取对象 */
  readObject(): JsonValue {
    const value: JsonValue = new JsonValue();
    value.kind = 'object';
    this.pos++;
    this.skipWs();
    if (this.pos < this.text.length && this.text.charAt(this.pos) === '}') {
      this.pos++;
      return value;
    }
    while (true) {
      this.skipWs();
      if (this.error.length > 0) {
        return value;
      }
      if (this.pos >= this.text.length) {
        this.error = '对象未闭合';
        return value;
      }
      if (this.text.charAt(this.pos) !== '"') {
        this.error = '对象的键必须是字符串（位置 ' + this.pos + '）';
        return value;
      }
      const key: JsonValue = this.readString();
      if (this.error.length > 0) {
        return value;
      }
      this.skipWs();
      if (this.pos >= this.text.length || this.text.charAt(this.pos) !== ':') {
        this.error = '对象缺少冒号（位置 ' + this.pos + '）';
        return value;
      }
      this.pos++;
      const item: JsonValue = this.readValue();
      if (this.error.length > 0) {
        return value;
      }
      value.keys.push(key.text);
      value.values.push(item);
      this.skipWs();
      if (this.pos >= this.text.length) {
        this.error = '对象未闭合';
        return value;
      }
      const ch: string = this.text.charAt(this.pos);
      if (ch === ',') {
        this.pos++;
        continue;
      }
      if (ch === '}') {
        this.pos++;
        return value;
      }
      this.error = '对象缺少逗号或右花括号（位置 ' + this.pos + '）';
      return value;
    }
  }

  /** 读取数组 */
  readArray(): JsonValue {
    const value: JsonValue = new JsonValue();
    value.kind = 'array';
    this.pos++;
    this.skipWs();
    if (this.pos < this.text.length && this.text.charAt(this.pos) === ']') {
      this.pos++;
      return value;
    }
    while (true) {
      const item: JsonValue = this.readValue();
      if (this.error.length > 0) {
        return value;
      }
      value.items.push(item);
      this.skipWs();
      if (this.pos >= this.text.length) {
        this.error = '数组未闭合';
        return value;
      }
      const ch: string = this.text.charAt(this.pos);
      if (ch === ',') {
        this.pos++;
        continue;
      }
      if (ch === ']') {
        this.pos++;
        return value;
      }
      this.error = '数组缺少逗号或右方括号（位置 ' + this.pos + '）';
      return value;
    }
  }
}

/** 把字符串编码成 JSON 字符串字面量（用于嵌套对象 / 数组的展示） */
function quoteJsonString(text: string): string {
  let out: string = '"';
  for (let i: number = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    if (ch === '"') {
      out += '\\"';
    } else if (ch === '\\') {
      out += '\\\\';
    } else if (ch === '\n') {
      out += '\\n';
    } else if (ch === '\r') {
      out += '\\r';
    } else if (ch === '\t') {
      out += '\\t';
    } else if (ch === '\b') {
      out += '\\b';
    } else if (ch === '\f') {
      out += '\\f';
    } else {
      const code: number = text.charCodeAt(i);
      if (code < 0x20) {
        const hex: string = code.toString(16).toUpperCase();
        out += '\\u' + '0000'.substring(hex.length) + hex;
      } else {
        out += ch;
      }
    }
  }
  return out + '"';
}

/** 把 JSON 值序列化成紧凑 JSON 文本（用于嵌套值的单元格展示） */
function jsonValueToJson(value: JsonValue): string {
  if (value.kind === 'null') {
    return 'null';
  }
  if (value.kind === 'boolean') {
    return value.bool ? 'true' : 'false';
  }
  if (value.kind === 'number') {
    return value.num.toString();
  }
  if (value.kind === 'string') {
    return quoteJsonString(value.text);
  }
  if (value.kind === 'array') {
    let out: string = '[';
    for (let i: number = 0; i < value.items.length; i++) {
      if (i > 0) {
        out += ',';
      }
      out += jsonValueToJson(value.items[i]);
    }
    return out + ']';
  }
  if (value.kind === 'object') {
    let out: string = '{';
    for (let i: number = 0; i < value.keys.length; i++) {
      if (i > 0) {
        out += ',';
      }
      out += quoteJsonString(value.keys[i]) + ':' + jsonValueToJson(value.values[i]);
    }
    return out + '}';
  }
  return '';
}

/**
 * 把一个 JSON 值格式化成单元格文本：
 * 字符串原样；数字 / 布尔转文本；null → 空串；对象 / 数组 → JSON 文本并截断到 120 字符。
 */
function jsonValueToCell(value: JsonValue): string {
  if (value.kind === 'string') {
    return value.text;
  }
  if (value.kind === 'number') {
    return value.num.toString();
  }
  if (value.kind === 'boolean') {
    return value.bool ? 'true' : 'false';
  }
  if (value.kind === 'null') {
    return '';
  }
  if (value.kind === 'object' || value.kind === 'array') {
    return truncateText(jsonValueToJson(value), JSON_CELL_MAX_CHARS);
  }
  return '';
}

/** 顶层数组、元素全是对象：键并集（首次出现顺序）作为表头 */
function buildObjectArrayTable(table: DataTable, items: JsonValue[], limit: number): DataTable {
  const union: string[] = [];
  for (let i: number = 0; i < items.length; i++) {
    const item: JsonValue = items[i];
    for (let k: number = 0; k < item.keys.length; k++) {
      const key: string = item.keys[k];
      if (union.indexOf(key) < 0) {
        union.push(key);
      }
    }
  }
  if (union.length === 0) {
    table.ok = false;
    table.message = '没有可显示的字段';
    return table;
  }
  const notes: string[] = [];
  let shownKeys: string[] = union;
  if (union.length > DATA_PREVIEW_MAX_COLUMNS) {
    shownKeys = union.slice(0, DATA_PREVIEW_MAX_COLUMNS);
    notes.push(columnCapNote(union.length));
  }
  table.headers = shownKeys;
  table.columns = shownKeys.length;

  const total: number = items.length;
  const rowCount: number = total > limit ? limit : total;
  const rows: string[][] = [];
  for (let r: number = 0; r < rowCount; r++) {
    const item: JsonValue = items[r];
    const cells: string[] = [];
    for (let c: number = 0; c < shownKeys.length; c++) {
      const idx: number = item.keys.indexOf(shownKeys[c]);
      cells.push(idx < 0 ? '' : jsonValueToCell(item.values[idx]));
    }
    rows.push(cells);
  }
  table.rows = rows;
  return finishTable(table, total, limit, notes);
}

/** 顶层数组、元素全是数组：列1..列N（N = 最长数组长度，≤40） */
function buildArrayArrayTable(table: DataTable, items: JsonValue[], limit: number): DataTable {
  let maxLen: number = 0;
  for (let i: number = 0; i < items.length; i++) {
    const len: number = items[i].items.length;
    if (len > maxLen) {
      maxLen = len;
    }
  }
  if (maxLen === 0) {
    table.ok = false;
    table.message = '没有可显示的字段';
    return table;
  }
  const colCount: number = maxLen > DATA_PREVIEW_MAX_COLUMNS ? DATA_PREVIEW_MAX_COLUMNS : maxLen;
  const headers: string[] = [];
  for (let c: number = 0; c < colCount; c++) {
    headers.push(columnName(c));
  }
  table.headers = headers;
  table.columns = colCount;

  const total: number = items.length;
  const rowCount: number = total > limit ? limit : total;
  const rows: string[][] = [];
  for (let r: number = 0; r < rowCount; r++) {
    const inner: JsonValue[] = items[r].items;
    const cells: string[] = [];
    for (let c: number = 0; c < colCount; c++) {
      cells.push(c < inner.length ? jsonValueToCell(inner[c]) : '');
    }
    rows.push(cells);
  }
  table.rows = rows;
  const notes: string[] = [];
  if (maxLen > DATA_PREVIEW_MAX_COLUMNS) {
    notes.push(columnCapNote(maxLen));
  }
  return finishTable(table, total, limit, notes);
}

/** 顶层数组、元素是标量（或混合类型）：单列「值」 */
function buildScalarArrayTable(table: DataTable, items: JsonValue[], limit: number): DataTable {
  table.headers = ['值'];
  table.columns = 1;
  const total: number = items.length;
  const rowCount: number = total > limit ? limit : total;
  const rows: string[][] = [];
  for (let r: number = 0; r < rowCount; r++) {
    rows.push([jsonValueToCell(items[r])]);
  }
  table.rows = rows;
  return finishTable(table, total, limit, []);
}

/** 顶层为数组：按元素类型分派到对象数组 / 数组的数组 / 标量数组 */
function buildArrayTable(table: DataTable, root: JsonValue, limit: number): DataTable {
  const items: JsonValue[] = root.items;
  if (items.length === 0) {
    table.ok = false;
    table.message = 'JSON 数组为空';
    return table;
  }
  let allObjects: boolean = true;
  let allArrays: boolean = true;
  for (let i: number = 0; i < items.length; i++) {
    if (items[i].kind !== 'object') {
      allObjects = false;
    }
    if (items[i].kind !== 'array') {
      allArrays = false;
    }
  }
  if (allObjects) {
    return buildObjectArrayTable(table, items, limit);
  }
  if (allArrays) {
    return buildArrayArrayTable(table, items, limit);
  }
  return buildScalarArrayTable(table, items, limit);
}

/** 顶层为对象：渲染成「键 / 值」两列 */
function buildObjectTable(table: DataTable, root: JsonValue, limit: number): DataTable {
  if (root.keys.length === 0) {
    table.ok = false;
    table.message = 'JSON 对象为空';
    return table;
  }
  table.headers = ['键', '值'];
  table.columns = 2;
  const total: number = root.keys.length;
  const rowCount: number = total > limit ? limit : total;
  const rows: string[][] = [];
  for (let r: number = 0; r < rowCount; r++) {
    rows.push([root.keys[r], jsonValueToCell(root.values[r])]);
  }
  table.rows = rows;
  return finishTable(table, total, limit, []);
}

/** 解析 JSON 文本为 DataTable（失败只返回 ok=false，绝不抛异常） */
export function parseJsonTable(text: string, maxRows: number): DataTable {
  const table: DataTable = new DataTable();
  table.kind = 'JSON';
  const limit: number = clampMaxRows(maxRows);
  const body: string = stripBom(text);
  if (body.trim().length === 0) {
    table.message = '文件为空';
    return table;
  }
  const parser: JsonParser = new JsonParser();
  const root: JsonValue = parser.parse(body);
  if (parser.error.length > 0) {
    table.message = 'JSON 解析失败：' + parser.error;
    return table;
  }
  if (root.kind === 'array') {
    return buildArrayTable(table, root, limit);
  }
  if (root.kind === 'object') {
    return buildObjectTable(table, root, limit);
  }
  table.ok = false;
  table.message = 'JSON 顶层不是对象或数组，无法显示为表格';
  return table;
}

/**
 * 按文件名扩展名分派解析：
 * .json → JSON；.tsv / .tab → 制表符；.csv → 自动探测分隔符；其他 → ok=false。
 * source 填文件名（不含目录），kind 填 CSV / TSV / JSON。
 */
export function parseDataTable(text: string, fileName: string, maxRows: number): DataTable {
  const source: string = fileNameOf(fileName);
  const ext: string = extensionOf(source);
  let table: DataTable = new DataTable();
  if (ext === '.json') {
    table = parseJsonTable(text, maxRows);
  } else if (ext === '.tsv' || ext === '.tab') {
    table = parseCsvTable(text, '\t', maxRows);
  } else if (ext === '.csv') {
    table = parseCsvTable(text, detectDelimiter(text), maxRows);
  } else {
    table = new DataTable();
    table.source = source;
    table.message = '不支持的文件类型：' + source + '（仅支持 .csv / .tsv / .tab / .json）';
    return table;
  }
  table.source = source;
  if (table.kind.length === 0) {
    table.kind = ext === '.json' ? 'JSON' : (ext === '.csv' ? 'CSV' : 'TSV');
  }
  return table;
}
