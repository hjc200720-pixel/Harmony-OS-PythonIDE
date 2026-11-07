/**
 * CoverageService —— 覆盖率（Coverage）服务层
 *
 * 组成：
 *   1. COVERAGE_PY_SCRIPT：设备端执行的覆盖率统计脚本（纯标准库，嵌入式 CPython 3.12 可跑）；
 *   2. CoverageFileEntry / CoverageReport：报告数据模型；
 *   3. parseCoverageReport：把脚本写出的 JSON 转成强类型模型，做容错校验。
 *
 * 脚本调用约定（与 Index.ets 接线一致）：
 *   脚本写到 <filesDir>/.harmonyide/coverage_run.py，然后
 *   PyRuntimeService.run(scriptPath, [projectRoot, outJson, targetRel])
 *   其中 sys.argv[1] = 工程根绝对路径，sys.argv[2] = 报告 JSON 路径，
 *   sys.argv[3] = 目标文件（相对工程根，'-' 表示没有目标）。
 *
 * 说明：
 *   * Python 源码沿用 Index.ets 里 PROJECT_AST_SCRIPT 的写法 —— 单引号字符串数组
 *     + join('\n')，因为 ArkTS 没有 heredoc / 多行字符串字面量。
 *   * 两个 #coverage-py-... 标记行供 scripts/verify-coverage.py 原样抽取脚本，
 *     改动 Python 源码时不要删掉它们。
 *   * 本文件不做文件 IO、不 import FileService：写脚本、读报告由接线方完成，
 *     这样服务层保持纯逻辑，宿主验证脚本也能直接抽取 Python 源码跑。
 */

// #coverage-py-begin
export const COVERAGE_PY_SCRIPT: string = [
  '# -*- coding: utf-8 -*-',
  '"""覆盖率统计脚本（设备端 CPython 3.12，纯标准库实现）。',
  '',
  '调用约定（由 CoverageService.ets 写盘后经 PyRuntimeService.run 执行）：',
  '    sys.argv[1] = 工程根绝对路径',
  '    sys.argv[2] = 覆盖率报告 JSON 的绝对路径',
  '    sys.argv[3] = 目标文件（相对工程根；\'-\' 表示没有目标）',
  '',
  '行为约定：',
  '    * 以 __main__ 语义执行目标（runpy.run_path(..., run_name=\'__main__\')），',
  '      sys.path 顶部插入工程根，__file__ / __name__ 与直接运行一致。',
  '    * 用 sys.settrace + threading.settrace 逐行统计命中行；finally 里恢复。',
  '    * 只统计工程根下的 .py：跳过以 . 开头的目录、__pycache__、site-packages、venv。',
  '    * 可执行行 = compile 后递归 co_consts，用 dis.findlinestarts 收集的行号集合。',
  '    * 无论目标抛异常 / sys.exit / 语法错误 / 目标不存在 / 内部错误，都必须写出 JSON。',
  '    * 目标程序的 stdout/stderr 原样透传（IDE 运行控制台照常显示）；脚本最后再打印一行「覆盖率：…」摘要。',
  '"""',
  '',
  'import dis',
  'import io',
  'import json',
  'import os',
  'import runpy',
  'import sys',
  'import threading',
  'import types',
  '',
  '# 报告最多列出的文件数（超出时截断，并在 message 里说明）',
  'MAX_FILES = 400',
  '',
  '# 绝对路径口径统一（Windows 上 normcase 会转小写；设备上是 POSIX 语义）',
  'SKIP_DIR_NAMES = (\'__pycache__\', \'site-packages\', \'venv\', \'.venv\')',
  '',
  'if len(sys.argv) < 3:',
  '    sys.stderr.write(\'usage: coverage_run.py <project_root> <out_json> [target_rel]\\n\')',
  '    raise SystemExit(2)',
  '',
  'ROOT = os.path.abspath(sys.argv[1])',
  'OUT = os.path.abspath(sys.argv[2])',
  'TARGET_ARG = sys.argv[3] if len(sys.argv) > 3 else \'-\'',
  '',
  '_root_norm = os.path.normcase(ROOT) if hasattr(os.path, \'normcase\') else ROOT',
  '_sep = os.sep',
  '',
  '# 文件名 -> 是否属于工程内 .py（tracing 每行都会问，必须缓存）',
  '_file_ok_cache = {}',
  '# 规范化文件名 -> 命中行号集合',
  'executed = {}',
  '',
  '',
  'def _norm(path):',
  '    """绝对路径 + normcase，用于比较（不用于展示）。"""',
  '    try:',
  '        return os.path.normcase(os.path.abspath(path))',
  '    except Exception:',
  '        return path',
  '',
  '',
  'def _is_project_file(filename):',
  '    """判断 trace 到的文件是否属于工程（且不是被排除的目录）。"""',
  '    cached = _file_ok_cache.get(filename)',
  '    if cached is not None:',
  '        return cached',
  '    result = False',
  '    try:',
  '        name = _norm(filename)',
  '        if name.lower().endswith(\'.py\'):',
  '            if name == _root_norm or name.startswith(_root_norm + _sep):',
  '                rel = os.path.relpath(name, _root_norm)',
  '                parts = rel.split(_sep)',
  '                blocked = False',
  '                for part in parts[:-1]:',
  '                    low = part.lower()',
  '                    if part.startswith(\'.\') or low in SKIP_DIR_NAMES:',
  '                        blocked = True',
  '                        break',
  '                result = not blocked',
  '    except Exception:',
  '        result = False',
  '    _file_ok_cache[filename] = result',
  '    return result',
  '',
  '',
  'def _record(frame):',
  '    """记录一次行命中。"""',
  '    filename = _norm(frame.f_code.co_filename)',
  '    lines = executed.get(filename)',
  '    if lines is None:',
  '        lines = set()',
  '        executed[filename] = lines',
  '    lines.add(frame.f_lineno)',
  '',
  '',
  'def _trace(frame, event, arg):',
  '    """sys.settrace / threading.settrace 的全局跟踪函数。"""',
  '    if not _is_project_file(frame.f_code.co_filename):',
  '        return None',
  '    if event == \'line\':',
  '        _record(frame)',
  '    return _trace',
  '',
  '',
  'def _executable_lines(code):',
  '    """递归收集 code object 里所有可执行行号（含嵌套函数/推导式）。"""',
  '    lines = set()',
  '    stack = [code]',
  '    seen = set()',
  '    while stack:',
  '        current = stack.pop()',
  '        if id(current) in seen:',
  '            continue',
  '        seen.add(id(current))',
  '        try:',
  '            for _offset, lineno in dis.findlinestarts(current):',
  '                if lineno and lineno > 0:',
  '                    lines.add(lineno)',
  '        except Exception:',
  '            pass',
  '        for const in current.co_consts:',
  '            if isinstance(const, types.CodeType):',
  '                stack.append(const)',
  '    return lines',
  '',
  '',
  'def _rel(path):',
  '    """转成报告里展示的相对路径（统一用 /）。"""',
  '    try:',
  '        return os.path.relpath(path, ROOT).replace(\'\\\\\', \'/\')',
  '    except Exception:',
  '        return path',
  '',
  '',
  'def _exception_message(exc):',
  '    """目标异常 -> 人类可读摘要（含异常类型、位置行号，截断 400 字符）。"""',
  '    name = type(exc).__name__',
  '    detail = str(exc)',
  '    lineno = getattr(exc, \'lineno\', 0) or 0',
  '    where = getattr(exc, \'filename\', \'\') or \'\'',
  '    tb = exc.__traceback__',
  '    while tb is not None:',
  '        filename = tb.tb_frame.f_code.co_filename',
  '        if _is_project_file(filename):',
  '            where = filename',
  '            lineno = tb.tb_lineno',
  '        tb = tb.tb_next',
  '    if where:',
  '        text = \'%s: %s（%s:%s）\' % (name, detail, _rel(where), lineno)',
  '    else:',
  '        text = \'%s: %s\' % (name, detail)',
  '    return text[:400]',
  '',
  '',
  'def _scan_project_files():',
  '    """遍历工程根下的 .py，返回 [(绝对路径, 可执行行集合)]。"""',
  '    entries = []',
  '    for dirpath, dirnames, filenames in os.walk(ROOT):',
  '        keep = []',
  '        for name in dirnames:',
  '            low = name.lower()',
  '            if name.startswith(\'.\') or low in SKIP_DIR_NAMES:',
  '                continue',
  '            keep.append(name)',
  '        keep.sort()',
  '        dirnames[:] = keep',
  '        for filename in sorted(filenames):',
  '            if not filename.lower().endswith(\'.py\'):',
  '                continue',
  '            path = os.path.join(dirpath, filename)',
  '            try:',
  '                with io.open(path, \'rb\') as handle:',
  '                    data = handle.read()',
  '                # 用 bytes 编译：让 Python 自己处理编码声明与 BOM',
  '                code = compile(data, path, \'exec\')',
  '            except Exception:',
  '                continue',
  '            lines = _executable_lines(code)',
  '            if not lines:',
  '                continue',
  '            entries.append((path, lines))',
  '    return entries',
  '',
  '',
  'def _run_target():',
  '    """执行目标并记录命中行，返回 (ok, exit_code, message)。"""',
  '    if not TARGET_ARG or TARGET_ARG == \'-\':',
  '        return (False, 0,',
  '                \'未指定目标文件（target=\\\'-\\\'）：请先在编辑器里打开一个 Python 文件再统计覆盖率。\')',
  '    if os.path.isabs(TARGET_ARG):',
  '        target_path = TARGET_ARG',
  '    else:',
  '        target_path = os.path.join(ROOT, TARGET_ARG)',
  '    target_path = os.path.abspath(target_path)',
  '    if not os.path.isfile(target_path):',
  '        return (False, 0, \'目标文件不存在：%s（工程根：%s）\' % (_rel(target_path), ROOT))',
  '',
  '    # 保证 import 工程内模块时能找到它们；工程根放在 sys.path 最前面',
  '    try:',
  '        while ROOT in sys.path:',
  '            sys.path.remove(ROOT)',
  '    except ValueError:',
  '        pass',
  '    sys.path.insert(0, ROOT)',
  '',
  '    exit_code = 0',
  '    message = \'\'',
  '    sys.settrace(_trace)',
  '    threading.settrace(_trace)',
  '    try:',
  '        # 目标输出不拦截、不重定向：IDE 运行控制台要照常看到程序输出',
  '        runpy.run_path(target_path, run_name=\'__main__\')',
  '    except SystemExit as exc:',
  '        code = exc.code',
  '        if code is None:',
  '            exit_code = 0',
  '        elif isinstance(code, int):',
  '            exit_code = code',
  '        else:',
  '            exit_code = 1',
  '            message = \'目标以 SystemExit(%r) 退出\' % (code,)',
  '    except BaseException as exc:',
  '        exit_code = 1',
  '        message = _exception_message(exc)',
  '    finally:',
  '        sys.settrace(None)',
  '        threading.settrace(None)',
  '    return (True, exit_code, message)',
  '',
  '',
  'def _build_report(ok, exit_code, message):',
  '    """静态扫描 + 执行命中，组装报告。"""',
  '    files = []',
  '    for path, lines in _scan_project_files():',
  '        hit_lines = executed.get(_norm(path), set())',
  '        total = len(lines)',
  '        if total == 0:',
  '            continue',
  '        covered = len(lines & hit_lines)',
  '        percent = round(covered * 100.0 / total, 1)',
  '        files.append({',
  '            \'path\': _rel(path),',
  '            \'total\': total,',
  '            \'covered\': covered,',
  '            \'percent\': percent,',
  '            \'hit\': sorted(lines & hit_lines),',
  '            \'missing\': sorted(lines - hit_lines),',
  '        })',
  '    files.sort(key=lambda item: (item[\'percent\'], item[\'path\']))',
  '    note = \'\'',
  '    if len(files) > MAX_FILES:',
  '        note = \'工程内共 %d 个 Python 文件，报告已截断为前 %d 个\' % (len(files), MAX_FILES)',
  '        files = files[:MAX_FILES]',
  '    if note:',
  '        message = (message + \'；\' + note) if message else note',
  '    target = TARGET_ARG if TARGET_ARG and TARGET_ARG != \'-\' else \'\'',
  '    return {\'ok\': ok, \'target\': target, \'exit\': exit_code, \'message\': message, \'files\': files}',
  '',
  '',
  'def _summary(report):',
  '    """stdout 唯一一行摘要。"""',
  '    files = report[\'files\']',
  '    total = 0',
  '    covered = 0',
  '    covered_files = 0',
  '    for item in files:',
  '        total += item[\'total\']',
  '        covered += item[\'covered\']',
  '        if item[\'covered\'] > 0:',
  '            covered_files += 1',
  '    percent = round(covered * 100.0 / total, 1) if total else 0.0',
  '    return \'覆盖率：%d/%d 个文件，总行覆盖率 %.1f%%\' % (covered_files, len(files), percent)',
  '',
  '',
  'def main():',
  '    report = None',
  '    try:',
  '        ok, exit_code, message = _run_target()',
  '        report = _build_report(ok, exit_code, message)',
  '    except BaseException as exc:',
  '        report = {',
  '            \'ok\': False,',
  '            \'target\': TARGET_ARG if TARGET_ARG and TARGET_ARG != \'-\' else \'\',',
  '            \'exit\': 1,',
  '            \'message\': \'内部错误：%s: %s\' % (type(exc).__name__, str(exc))[:400],',
  '            \'files\': [],',
  '        }',
  '    try:',
  '        parent = os.path.dirname(OUT)',
  '        if parent and not os.path.isdir(parent):',
  '            os.makedirs(parent)',
  '        with io.open(OUT, \'w\', encoding=\'utf-8\') as handle:',
  '            handle.write(json.dumps(report, ensure_ascii=False))',
  '    except Exception as exc:',
  '        sys.stderr.write(\'write coverage report failed: %s: %s\\n\' % (type(exc).__name__, exc))',
  '    if report[\'ok\']:',
  '        sys.stdout.write(_summary(report) + \'\\n\')',
  '    else:',
  '        sys.stdout.write(\'覆盖率：未生成（%s）\\n\' % report[\'message\'][:200])',
  '    return 0',
  '',
  '',
  'raise SystemExit(main())',
].join('\n');
// #coverage-py-end

/** 单个文件的覆盖率 */
export class CoverageFileEntry {
  /** 相对工程根的路径（统一用 /；展示与匹配都用它） */
  rel: string = '';
  /** 可执行行数（compile + dis.findlinestarts 递归收集） */
  total: number = 0;
  /** 命中行数 */
  covered: number = 0;
  /** 行覆盖率，0..100，保留 1 位小数 */
  percent: number = 0;
  /** 命中的行号（升序） */
  hit: number[] = [];
  /** 未命中的行号（升序） */
  missing: number[] = [];
}

/** 一次覆盖率统计的结果 */
export class CoverageReport {
  /** true 表示脚本成功生成了报告；目标异常/非零退出时仍为 true（看 exitCode / message） */
  ok: boolean = false;
  /** 本次统计的目标文件（相对工程根；没有目标时为空串） */
  targetRel: string = '';
  /** 目标进程退出码：正常 0，sys.exit(n) 为 n，异常为 1 */
  exitCode: number = 0;
  /** 人类可读摘要；目标异常时含异常类型与行号，失败时说明原因 */
  message: string = '';
  /** 工程内文件（按覆盖率升序，最多 400 个） */
  files: CoverageFileEntry[] = [];
}

/**
 * JSON 的原始形状。
 *
 * 只用于承接 JSON.parse 的结果，所有字段都是可选的：真实报告可能被截断、
 * 字段缺失甚至类型不对，parseCoverageReport 会逐字段校验后再填进强类型模型。
 * 注意：不会把 JSON 断言成 CoverageFileEntry / CoverageReport 直接当实例用。
 */
interface RawCoverageFile {
  path?: string;
  total?: number;
  covered?: number;
  percent?: number;
  hit?: number[];
  missing?: number[];
}

interface RawCoverageReport {
  ok?: boolean;
  target?: string;
  exit?: number;
  message?: string;
  files?: RawCoverageFile[];
}

/** 逐项校验行号数组：只保留正整数，其他（字符串、负数、小数）丢掉 */
function toLineArray(values: number[] | undefined): number[] {
  const out: number[] = [];
  if (!Array.isArray(values)) {
    return out;
  }
  for (let i = 0; i < values.length; i++) {
    const value: number = values[i];
    if (typeof value === 'number' && Number.isInteger(value) && value > 0) {
      out.push(value);
    }
  }
  return out;
}

/**
 * 解析覆盖率脚本写出的 JSON。
 *
 * 容错规则（与脚本契约对齐）：
 *   * 空文本 / 非法 JSON / 不是对象 / 缺少 ok 字段 -> 返回 new CoverageReport()，
 *     ok=false 且 message 说明原因；
 *   * files 不是数组 -> ok=false 并说明；
 *   * 单条文件缺 path 则跳过；数字/行号字段类型不对则用默认值。
 * 绝不抛异常，调用方可以无条件使用返回值。
 */
export function parseCoverageReport(jsonText: string): CoverageReport {
  const report: CoverageReport = new CoverageReport();
  if (jsonText === undefined || jsonText === null || jsonText.length === 0) {
    report.message = '覆盖率报告为空：脚本没有写出 JSON。';
    return report;
  }
  let raw: RawCoverageReport;
  try {
    raw = JSON.parse(jsonText) as RawCoverageReport;
  } catch (err) {
    report.message = '覆盖率报告不是合法 JSON（无法解析脚本输出）。';
    return report;
  }
  if (raw === null || raw === undefined) {
    report.message = '覆盖率报告不是 JSON 对象（解析结果为 null）。';
    return report;
  }
  if (typeof raw.ok !== 'boolean') {
    report.message = '覆盖率报告缺少 ok 字段（或类型不是布尔），报告无效。';
    return report;
  }
  report.ok = raw.ok;
  report.targetRel = typeof raw.target === 'string' ? raw.target : '';
  report.exitCode = typeof raw.exit === 'number' ? raw.exit : 0;
  report.message = typeof raw.message === 'string' ? raw.message : '';
  const rawFiles: RawCoverageFile[] | undefined = raw.files;
  if (!Array.isArray(rawFiles)) {
    report.ok = false;
    if (report.message.length === 0) {
      report.message = '覆盖率报告缺少 files 数组。';
    }
    return report;
  }
  const files: CoverageFileEntry[] = [];
  for (let i = 0; i < rawFiles.length; i++) {
    const item: RawCoverageFile = rawFiles[i];
    if (item === null || item === undefined) {
      continue;
    }
    const rel: string = typeof item.path === 'string' ? item.path : '';
    if (rel.length === 0) {
      continue;
    }
    const entry: CoverageFileEntry = new CoverageFileEntry();
    entry.rel = rel;
    entry.total = typeof item.total === 'number' ? item.total : 0;
    entry.covered = typeof item.covered === 'number' ? item.covered : 0;
    entry.percent = typeof item.percent === 'number' ? item.percent : 0;
    entry.hit = toLineArray(item.hit);
    entry.missing = toLineArray(item.missing);
    files.push(entry);
  }
  report.files = files;
  return report;
}

/** 报告的紧凑摘要（界面标题/状态栏可用；服务层不依赖 UI） */
export function coverageSummaryLine(report: CoverageReport): string {
  if (!report.ok) {
    return `覆盖率：未生成（${report.message}）`;
  }
  let total: number = 0;
  let covered: number = 0;
  for (let i = 0; i < report.files.length; i++) {
    total += report.files[i].total;
    covered += report.files[i].covered;
  }
  if (total === 0) {
    return '覆盖率：工程内没有可统计的 Python 文件。';
  }
  const percent: number = Math.round(covered * 1000 / total) / 10;
  return `覆盖率：${report.files.length} 个文件，总行覆盖率 ${percent.toFixed(1)}%`;
}
