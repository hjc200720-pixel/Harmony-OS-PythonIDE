#!/usr/bin/env node
/**
 * verify-datapreview.mjs —— DataPreviewService.ets 的宿主验证脚本
 *
 * 做法：把 entry/src/main/ets/service/DataPreviewService.ets 原样复制成临时 .ts，
 * 用 Node 24 的 --experimental-strip-types 直接 import（临时目录里写一个
 * package.json {"type":"module"} 保证按 ESM 加载），逐用例断言后清理临时目录。
 *
 * 跑法（工程根目录）：
 *   C:\Program Files\nodejs\node.exe --experimental-strip-types scripts/verify-datapreview.mjs
 *
 * 输出：每条断言一行 [n] OK / FAIL（附关键细节），最后一行 RESULT: PASS/FAIL；
 * 有失败时进程退出码为 1。
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(here, '..');
const servicePath = path.join(projectRoot, 'entry', 'src', 'main', 'ets', 'service', 'DataPreviewService.ets');

let checks = 0;
let failures = 0;
let caseNo = 0;

function caseStart(title) {
  caseNo++;
  console.log('');
  console.log('== 用例 ' + caseNo + '：' + title + ' ==');
}

function check(desc, cond, detail) {
  checks++;
  const line = '[' + checks + '] ' + (cond ? 'OK   ' : 'FAIL ') + desc + (detail ? ' | ' + detail : '');
  if (cond) {
    console.log(line);
  } else {
    failures++;
    console.log(line);
  }
}

function eq(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function describeTable(t) {
  return 'ok=' + t.ok + ', kind=' + JSON.stringify(t.kind) + ', source=' + JSON.stringify(t.source) +
    ', headers=' + JSON.stringify(t.headers) + ', rows=' + t.rows.length + ', totalRows=' + t.totalRows +
    ', columns=' + t.columns + ', truncated=' + t.truncated + ', message=' + JSON.stringify(t.message);
}

function makeWideCsv(cols, dataRows) {
  const head = [];
  for (let c = 1; c <= cols; c++) {
    head.push('C' + c);
  }
  const lines = [head.join(',')];
  for (let r = 1; r <= dataRows; r++) {
    const cells = [];
    for (let c = 1; c <= cols; c++) {
      cells.push('r' + r + 'v' + c);
    }
    lines.push(cells.join(','));
  }
  return lines.join('\n');
}

function makeWideJson(cols) {
  const pairs = [];
  for (let c = 1; c <= cols; c++) {
    pairs.push('"K' + c + '":' + c);
  }
  return '[{' + pairs.join(',') + '}]';
}

function runTests(api) {
  // ---------------------------------------------------------------- 用例 1
  caseStart('基础 CSV（中文表头 + 3 行）');
  const t1 = api.parseDataTable('姓名,年龄,城市\n张三,28,北京\n李四,31,上海\n王五,25,深圳\n', 'people.csv', 120);
  check('ok/kind/source 正确', t1.ok === true && t1.kind === 'CSV' && t1.source === 'people.csv', describeTable(t1));
  check('表头与列数正确', eq(t1.headers, ['姓名', '年龄', '城市']) && t1.columns === 3, JSON.stringify(t1.headers));
  check('3 行全部解析，首尾行内容正确',
    t1.rows.length === 3 && t1.totalRows === 3 && eq(t1.rows[0], ['张三', '28', '北京']) && eq(t1.rows[2], ['王五', '25', '深圳']),
    JSON.stringify(t1.rows));

  // ---------------------------------------------------------------- 用例 2
  caseStart('RFC4180 引号语义（字段内逗号 / 转义双引号 / 字段内换行）');
  const csv2 = '名称,描述,备注\n' +
    'A,"含,逗号",普通\n' +
    'B,"他说""你好""",引号\n' +
    'C,"第一行\n第二行",多行\n';
  const t2 = api.parseDataTable(csv2, 'rfc.csv', 120);
  check('3 行都被正确切分', t2.ok === true && t2.rows.length === 3 && t2.totalRows === 3, describeTable(t2));
  check('引号字段内的逗号不分列', t2.rows[0][1] === '含,逗号', JSON.stringify(t2.rows[0]));
  check('两个连续双引号表示一个双引号', t2.rows[1][1] === '他说"你好"', JSON.stringify(t2.rows[1]));
  check('引号字段内的换行保留在单元格里', t2.rows[2][1] === '第一行\n第二行', JSON.stringify(t2.rows[2][1]));
  const t2b = api.parseCsvTable('h1, h2 ,h3\na , "b" ,c\n', ',', 120);
  check('未加引号字段去首尾空格、引号后的空格被忽略',
    eq(t2b.headers, ['h1', 'h2', 'h3']) && eq(t2b.rows[0], ['a', 'b', 'c']),
    'headers=' + JSON.stringify(t2b.headers) + ', rows=' + JSON.stringify(t2b.rows));

  // ---------------------------------------------------------------- 用例 3
  caseStart('CRLF + UTF-8 BOM');
  const csv3 = '\uFEFF名称,值\r\n甲,1\r\n乙,2\r\n丙,"x\r\ny"\r\n';
  const t3 = api.parseDataTable(csv3, 'bom.csv', 120);
  check('BOM 被忽略、CRLF 正常分 3 行',
    t3.ok === true && eq(t3.headers, ['名称', '值']) && t3.rows.length === 3,
    describeTable(t3));
  check('CRLF 行内容正确、引号内 CRLF 归一为 \n',
    eq(t3.rows[0], ['甲', '1']) && eq(t3.rows[1], ['乙', '2']) && t3.rows[2][1] === 'x\ny',
    JSON.stringify(t3.rows));

  // ---------------------------------------------------------------- 用例 4
  caseStart('分隔符探测（引号内分隔符不计数、平手取逗号）');
  check('逗号文件 → ","', api.detectDelimiter('a,b,c\n1,2,3') === ',', JSON.stringify(api.detectDelimiter('a,b,c\n1,2,3')));
  check('分号文件 → ";"', api.detectDelimiter('a;b;c\n1;2;3') === ';', JSON.stringify(api.detectDelimiter('a;b;c\n1;2;3')));
  check('制表符文件 → "\\t"', api.detectDelimiter('a\tb\tc\n1\t2\t3') === '\t', JSON.stringify(api.detectDelimiter('a\tb\tc')));
  check('竖线文件 → "|"', api.detectDelimiter('a|b|c\n1|2|3') === '|', JSON.stringify(api.detectDelimiter('a|b|c')));
  check('引号内的逗号不计数（表头 "a,b";c;d → ";"）',
    api.detectDelimiter('"a,b";c;d\n1;2;3') === ';', JSON.stringify(api.detectDelimiter('"a,b";c;d')));
  check('平手（逗号 1 : 制表符 1）取逗号', api.detectDelimiter('a,b\tc') === ',', JSON.stringify(api.detectDelimiter('a,b\tc')));
  check('无分隔符时默认逗号', api.detectDelimiter('abc') === ',', JSON.stringify(api.detectDelimiter('abc')));
  check('首个非空行才是表头行（前面空行跳过）',
    api.detectDelimiter('\n\n"a,b";c;d\n1;2;3') === ';', JSON.stringify(api.detectDelimiter('\n\n"a,b";c;d')));

  // ---------------------------------------------------------------- 用例 5
  caseStart('TSV 走 parseDataTable（kind=TSV，扩展名大小写不敏感）');
  const t5 = api.parseDataTable('名称\t数量\n苹果\t3\n香蕉\t5\n', 'stock.TSV', 120);
  check('kind=TSV、source 保留原文件名', t5.ok === true && t5.kind === 'TSV' && t5.source === 'stock.TSV', describeTable(t5));
  check('表头与 2 行内容正确', eq(t5.headers, ['名称', '数量']) && t5.rows.length === 2 && eq(t5.rows[1], ['香蕉', '5']), JSON.stringify(t5.rows));

  // ---------------------------------------------------------------- 用例 6
  caseStart('JSON 对象数组（键并集 / 缺键补空 / 值格式化）');
  const json6 = '[{"name":"张三","age":28,"vip":true},{"name":"李四","age":null,"city":"上海"}]';
  const t6 = api.parseDataTable(json6, 'users.json', 120);
  check('ok/kind=JSON/source 正确', t6.ok === true && t6.kind === 'JSON' && t6.source === 'users.json', describeTable(t6));
  check('表头 = 按首次出现顺序的键并集', eq(t6.headers, ['name', 'age', 'vip', 'city']), JSON.stringify(t6.headers));
  check('缺键补空 + 数字/布尔/null 格式化',
    eq(t6.rows[0], ['张三', '28', 'true', '']) && eq(t6.rows[1], ['李四', '', '', '上海']),
    JSON.stringify(t6.rows));
  check('totalRows=2、columns=4', t6.totalRows === 2 && t6.columns === 4, 'totalRows=' + t6.totalRows + ', columns=' + t6.columns);
  const t6b = api.parseJsonTable('\uFEFF[1,2]', 120);
  check('JSON 文本带 BOM 也能解析', t6b.ok === true && eq(t6b.rows, [['1'], ['2']]), describeTable(t6b));

  // ---------------------------------------------------------------- 用例 7
  caseStart('JSON 数组的数组（列1..列N，N=最长数组长度）');
  const t7 = api.parseDataTable('[[1,2,3],["a","b"],[]]', 'matrix.json', 120);
  check('表头为 列1..列3', eq(t7.headers, ['列1', '列2', '列3']) && t7.columns === 3, JSON.stringify(t7.headers));
  check('短数组补空、空数组也占一行',
    t7.rows.length === 3 && t7.totalRows === 3 &&
    eq(t7.rows[0], ['1', '2', '3']) && eq(t7.rows[1], ['a', 'b', '']) && eq(t7.rows[2], ['', '', '']),
    JSON.stringify(t7.rows));

  // ---------------------------------------------------------------- 用例 8
  caseStart('JSON 标量数组（单列「值」）');
  const t8 = api.parseDataTable('[1,"二",true,null]', 'scalars.json', 120);
  check('单列表头 = 值', eq(t8.headers, ['值']) && t8.columns === 1, JSON.stringify(t8.headers));
  check('数字/字符串/布尔/null 格式化正确',
    t8.rows.length === 4 && t8.totalRows === 4 && eq(t8.rows[0], ['1']) && eq(t8.rows[1], ['二']) &&
    eq(t8.rows[2], ['true']) && eq(t8.rows[3], ['']),
    JSON.stringify(t8.rows));

  // ---------------------------------------------------------------- 用例 9
  caseStart('JSON 顶层对象（键 / 值两列，嵌套值用 JSON 文本）');
  const t9 = api.parseDataTable('{"名称":"示例","版本":2,"嵌套":{"a":1},"列表":[1,2]}', 'meta.json', 120);
  check('两列表头 = 键/值', eq(t9.headers, ['键', '值']) && t9.columns === 2, JSON.stringify(t9.headers));
  check('4 个键按顺序展开、嵌套对象/数组为 JSON 文本',
    t9.totalRows === 4 && eq(t9.rows[0], ['名称', '示例']) && eq(t9.rows[1], ['版本', '2']) &&
    eq(t9.rows[2], ['嵌套', '{"a":1}']) && eq(t9.rows[3], ['列表', '[1,2]']),
    JSON.stringify(t9.rows));
  const longNested = '{"big":{"k":"' + 'x'.repeat(200) + '"}}';
  const t9b = api.parseJsonTable(longNested, 120);
  const nestedCell = t9b.rows[0][1];
  check('嵌套值 JSON 文本截断到 120 字符 + 省略号',
    nestedCell.length === 121 && nestedCell.endsWith('…'),
    'length=' + nestedCell.length + ', tail=' + JSON.stringify(nestedCell.substring(117)));

  // ---------------------------------------------------------------- 用例 10
  caseStart('非法 JSON → ok=false 且 message 非空（绝不抛异常）');
  const bad1 = api.parseDataTable('{"a":1,}', 'bad.json', 120);
  check('尾逗号被识别为解析失败', bad1.ok === false && bad1.message.indexOf('JSON 解析失败：') === 0, describeTable(bad1));
  const bad2 = api.parseJsonTable('not json at all', 120);
  check('非 JSON 文本被识别为解析失败', bad2.ok === false && bad2.message.length > 0, describeTable(bad2));
  const bad3 = api.parseJsonTable('{"a": }', 120);
  check('缺值被识别为解析失败（未抛出）', bad3.ok === false && bad3.message.length > 0, describeTable(bad3));
  const bad4 = api.parseJsonTable('{"a":1} trailing', 120);
  check('尾部多余内容被识别为解析失败', bad4.ok === false && bad4.message.indexOf('JSON 解析失败：') === 0, describeTable(bad4));
  const bad5 = api.parseJsonTable('123', 120);
  check('顶层标量 → ok=false（不是表格）', bad5.ok === false && bad5.message.length > 0, describeTable(bad5));
  const deepBad = api.parseJsonTable('['.repeat(300) + ']'.repeat(300), 120);
  check('超深嵌套被安全拒绝（不栈溢出、不抛出）',
    deepBad.ok === false && deepBad.message.indexOf('嵌套层级过深') >= 0, describeTable(deepBad));
  const deepOk = api.parseJsonTable('['.repeat(50) + ']'.repeat(50), 120);
  check('正常 50 层嵌套仍可解析', deepOk.ok === true, describeTable(deepOk));

  // ---------------------------------------------------------------- 用例 11
  caseStart('空文本 / 只有表头 / 不支持扩展名');
  const e1 = api.parseDataTable('', 'empty.csv', 120);
  check('空文本 → ok=false + 「文件为空」', e1.ok === false && e1.message === '文件为空', describeTable(e1));
  const e2 = api.parseJsonTable('   \n\t\n', 120);
  check('纯空白 JSON → ok=false + 「文件为空」', e2.ok === false && e2.message === '文件为空', describeTable(e2));
  const e3 = api.parseDataTable('a,b\n', 'header_only.csv', 120);
  check('只有表头 → ok=false + 「没有数据行」且 headers 保留',
    e3.ok === false && e3.message === '没有数据行' && eq(e3.headers, ['a', 'b']) && e3.totalRows === 0,
    describeTable(e3));
  const e4 = api.parseJsonTable('[]', 120);
  check('空 JSON 数组 → ok=false + message', e4.ok === false && e4.message === 'JSON 数组为空', describeTable(e4));
  const e5 = api.parseDataTable('hello', 'notes.txt', 120);
  check('不支持扩展名 → ok=false + 说明 + source',
    e5.ok === false && e5.source === 'notes.txt' && e5.message.indexOf('不支持的文件类型') === 0,
    describeTable(e5));

  // ---------------------------------------------------------------- 用例 12
  caseStart('截断（20 行 + maxRows=5）与 maxRows clamp');
  let many = '序号,值\n';
  for (let i = 1; i <= 20; i++) {
    many += i + ',行' + i + '\n';
  }
  const tr1 = api.parseDataTable(many, 'many.csv', 5);
  check('rows=5、totalRows=20、truncated=true',
    tr1.ok === true && tr1.rows.length === 5 && tr1.totalRows === 20 && tr1.truncated === true,
    describeTable(tr1));
  check('message 含「已截断：显示前 5 行，共 20 行」',
    tr1.message.indexOf('已截断：显示前 5 行，共 20 行') >= 0, JSON.stringify(tr1.message));
  check('保留的是前 5 行（第 5 行序号=5）', tr1.rows[4][0] === '5', JSON.stringify(tr1.rows[4]));
  const tr2 = api.parseDataTable('[1,2,3,4,5,6,7,8,9,10]', 'ten.json', 3);
  check('JSON 同样截断：rows=3、totalRows=10、message 说明',
    tr2.ok === true && tr2.rows.length === 3 && tr2.totalRows === 10 && tr2.truncated === true &&
    tr2.message.indexOf('已截断：显示前 3 行，共 10 行') >= 0,
    describeTable(tr2));
  const tr3 = api.parseCsvTable(many, ',', 0);
  check('maxRows=0 被 clamp 到 1（只显示 1 行，totalRows 仍 20）',
    tr3.rows.length === 1 && tr3.totalRows === 20 && tr3.truncated === true,
    describeTable(tr3));
  const tr4 = api.parseCsvTable(many, ',', 5000);
  check('maxRows=5000 被 clamp 到 1000（20 行全显示、不截断）',
    tr4.rows.length === 20 && tr4.truncated === false, describeTable(tr4));
  check('导出的常量符合契约（200 / 40）',
    api.DATA_PREVIEW_MAX_ROWS === 200 && api.DATA_PREVIEW_MAX_COLUMNS === 40,
    'DATA_PREVIEW_MAX_ROWS=' + api.DATA_PREVIEW_MAX_ROWS + ', DATA_PREVIEW_MAX_COLUMNS=' + api.DATA_PREVIEW_MAX_COLUMNS);

  // ---------------------------------------------------------------- 用例 13
  caseStart('参差 CSV（少列补空 / 多列丢弃）+ 空行跳过');
  const ragged = '\n\na,b,c\n\n1,2\n3,4,5,6\n,\n"",""\n5,6,7\n\n';
  const t13 = api.parseDataTable(ragged, 'ragged.csv', 120);
  check('3 个有效数据行（空行、逗号空行、引号空行都跳过）',
    t13.ok === true && t13.rows.length === 3 && t13.totalRows === 3, describeTable(t13));
  check('少列补空串、多列丢弃、行长度 = 表头长度',
    eq(t13.rows[0], ['1', '2', '']) && eq(t13.rows[1], ['3', '4', '5']) && eq(t13.rows[2], ['5', '6', '7']) &&
    t13.rows[0].length === 3 && t13.rows[1].length === 3,
    JSON.stringify(t13.rows));
  check('表头前空行被跳过（表头 = a,b,c）', eq(t13.headers, ['a', 'b', 'c']), JSON.stringify(t13.headers));
  const emptyHeaderCells = api.parseCsvTable('x,,z\n1,2,3\n', ',', 120);
  check('空表头单元格命名为「列N」（第 2 列 → 列2）',
    eq(emptyHeaderCells.headers, ['x', '列2', 'z']), JSON.stringify(emptyHeaderCells.headers));

  // ---------------------------------------------------------------- 用例 14
  caseStart('isDataFileName 正反例');
  const positives = ['data.csv', 'DATA.CSV', 'x.tsv', 'y.tab', 'z.json', 'dir/sub/a.csv', 'C:\\tmp\\b.TSV'];
  const negatives = ['a.txt', 'a.py', 'a.jsonl', 'a.csv.bak', '', '.md', 'data'];
  let posOk = true;
  for (let i = 0; i < positives.length; i++) {
    if (api.isDataFileName(positives[i]) !== true) {
      posOk = false;
    }
  }
  let negOk = true;
  for (let i = 0; i < negatives.length; i++) {
    if (api.isDataFileName(negatives[i]) !== false) {
      negOk = false;
    }
  }
  check('正例全部为 true', posOk, JSON.stringify(positives));
  check('反例全部为 false', negOk, JSON.stringify(negatives));

  // ---------------------------------------------------------------- 用例 15
  caseStart('列数 >40 截断（构造 45 列）');
  const wideCsv = makeWideCsv(45, 2);
  const t15 = api.parseDataTable(wideCsv, 'wide.csv', 120);
  check('columns=40、headers.length=40、rows 每行 40 个单元格',
    t15.ok === true && t15.columns === 40 && t15.headers.length === 40 &&
    t15.rows.length === 2 && t15.rows[0].length === 40 && t15.rows[1].length === 40,
    describeTable(t15));
  check('保留前 40 列（第 40 列 = C40 / r1v40），第 41 列被丢弃', t15.headers[39] === 'C40' && t15.rows[0][39] === 'r1v40' && t15.headers.indexOf('C41') < 0,
    'headers[39]=' + JSON.stringify(t15.headers[39]) + ', rows[0][39]=' + JSON.stringify(t15.rows[0][39]));
  check('message 注明「列数超过上限：仅显示前 40 列（共 45 列）」',
    t15.message.indexOf('列数超过上限：仅显示前 40 列（共 45 列）') >= 0, JSON.stringify(t15.message));
  const wideJson = makeWideJson(45);
  const t15b = api.parseDataTable(wideJson, 'wide.json', 120);
  check('JSON 键并集 >40 也只保留前 40 列并提示',
    t15b.ok === true && t15b.headers.length === 40 && t15b.headers[39] === 'K40' && t15b.rows[0][39] === '40' &&
    t15b.message.indexOf('列数超过上限：仅显示前 40 列（共 45 列）') >= 0,
    describeTable(t15b));
}

// -------------------------------------------------------------------- 主流程
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-datapreview-'));
const tmpTs = path.join(tmpDir, 'DataPreviewService.ts');
let api = null;

try {
  if (!fs.existsSync(servicePath)) {
    console.log('找不到服务文件：' + servicePath);
  } else {
    fs.copyFileSync(servicePath, tmpTs);
    fs.writeFileSync(path.join(tmpDir, 'package.json'), '{"type":"module"}\n', 'utf8');
    api = await import(pathToFileURL(tmpTs).href);
    console.log('已加载 DataPreviewService：' + Object.keys(api).sort().join(', '));
  }
} catch (err) {
  console.log('加载 DataPreviewService 失败：' + (err && err.message ? err.message : String(err)));
}

if (api !== null) {
  try {
    runTests(api);
  } catch (err) {
    failures++;
    console.log('[!] FAIL 用例执行中抛出异常：' + (err && err.stack ? err.stack : String(err)));
  }
}

try {
  fs.rmSync(tmpDir, { recursive: true, force: true });
} catch (err) {
  console.log('清理临时目录失败（可忽略）：' + String(err));
}

console.log('');
if (api === null) {
  console.log('RESULT: FAIL (模块加载失败)');
  process.exitCode = 1;
} else if (failures === 0) {
  console.log('RESULT: PASS (' + checks + ' 项断言 / ' + caseNo + ' 个用例)');
} else {
  console.log('RESULT: FAIL (' + failures + ' / ' + checks + ' 项断言失败 / ' + caseNo + ' 个用例)');
  process.exitCode = 1;
}
