/**
 * EndpointService —— 「端点（Endpoints）」工具窗的服务层
 *
 * 设备端运行时是嵌入式 CPython 3.12.10（标准库从 rawfile/python/python312.zip 以 zipimport 加载），
 * 没有 flask/fastapi/django 这些第三方包，所以端点清单只能由**纯静态 ast 扫描**得到：
 * 下面的脚本在设备上执行，只 import ast/io/os/sys，绝不 import 任何 Web 框架。
 *
 * 调用约定（与扫描脚本的文件头注释一致）：
 *   argv[1] = 工程根，argv[2] = 输出文本路径；输出每行 5 列 TAB 分隔，
 *   parseEndpointRows 负责把它还原成 EndpointEntry（文件 + 行号）。
 */

// #endpoints-py-begin
export const ENDPOINTS_PY_SCRIPT: string = [
  '# 端点扫描（EndpointService）—— 纯静态 ast 解析，不 import 任何第三方 Web 框架',
  '# 输入：sys.argv[1] 为工程根，sys.argv[2] 为输出文本路径',
  '# 输出：每行一个端点，5 列以 TAB 分隔：METHOD / route / rel-file:LINE / framework / handler',
  '# 排序：file, line, method；最多输出 400 行（超出截断）',
  '# 已知边界：不解析 include() 与蓝图/路由前缀拼接（url_prefix、APIRouter(prefix=...)），',
  '#           不解析变量 route（只认字符串常量 route），ast.parse 失败的文件整体跳过。',
  'import ast, io, os, sys',
  '',
  'MAX_ROWS = 400',
  'SKIP_DIRS = ("__pycache__", ".harmonyide", "site-packages", "venv", ".venv")',
  'HTTP_METHODS = ("get", "post", "put", "delete", "patch", "head", "options")',
  'DJANGO_CALLS = ("path", "re_path", "url")',
  'FRAMEWORK_KEYS = ("flask", "quart", "fastapi", "starlette")',
  '',
  '',
  'def rel_posix(path, root):',
  '    return os.path.relpath(path, root).replace(os.sep, "/")',
  '',
  '',
  'def collect_py_files(root):',
  '    files = []',
  '    for dirpath, dirnames, filenames in os.walk(root):',
  '        dirnames[:] = sorted([d for d in dirnames if not d.startswith(".") and d not in SKIP_DIRS])',
  '        for name in sorted(filenames):',
  '            if name.endswith(".py"):',
  '                files.append(os.path.join(dirpath, name))',
  '    files.sort()',
  '    return files',
  '',
  '',
  'def import_flags(tree):',
  '    flags = {"flask": False, "quart": False, "fastapi": False, "starlette": False, "django": False}',
  '    for node in ast.walk(tree):',
  '        if isinstance(node, ast.Import):',
  '            for alias in node.names:',
  '                head = alias.name.split(".")[0]',
  '                if head in FRAMEWORK_KEYS:',
  '                    flags[head] = True',
  '        elif isinstance(node, ast.ImportFrom):',
  '            mod = node.module or ""',
  '            head = mod.split(".")[0]',
  '            if head in FRAMEWORK_KEYS:',
  '                flags[head] = True',
  '            if mod in ("django.urls", "django.conf.urls"):',
  '                flags["django"] = True',
  '        elif isinstance(node, ast.Assign):',
  '            for target in node.targets:',
  '                if isinstance(target, ast.Name) and target.id == "urlpatterns":',
  '                    flags["django"] = True',
  '    return flags',
  '',
  '',
  'def str_const(node):',
  '    if isinstance(node, ast.Constant) and isinstance(node.value, str):',
  '        return node.value',
  '    return None',
  '',
  '',
  'def dotted_name(node):',
  '    if isinstance(node, ast.Name):',
  '        return node.id',
  '    if isinstance(node, ast.Attribute):',
  '        parts = []',
  '        cur = node',
  '        while isinstance(cur, ast.Attribute):',
  '            parts.append(cur.attr)',
  '            cur = cur.value',
  '        if isinstance(cur, ast.Name):',
  '            parts.append(cur.id)',
  '            return ".".join(reversed(parts))',
  '    return ""',
  '',
  '',
  'def flask_route_methods(dec):',
  '    has_methods = False',
  '    methods = []',
  '    for kw in dec.keywords:',
  '        if kw.arg != "methods":',
  '            continue',
  '        has_methods = True',
  '        if not isinstance(kw.value, (ast.List, ast.Tuple)):',
  '            return []',
  '        for elt in kw.value.elts:',
  '            val = str_const(elt)',
  '            if val:',
  '                methods.append(val.upper())',
  '    if not has_methods:',
  '        return ["GET"]',
  '    return methods',
  '',
  '',
  'def scan_decorators(node, rel, flask_fw, fastapi_fw, rows):',
  '    for dec in node.decorator_list:',
  '        if not isinstance(dec, ast.Call) or not isinstance(dec.func, ast.Attribute):',
  '            continue',
  '        attr = dec.func.attr',
  '        route = str_const(dec.args[0]) if dec.args else None',
  '        if route is None:',
  '            continue',
  '        if attr == "route":',
  '            methods = flask_route_methods(dec)',
  '            if not methods:',
  '                continue',
  '            for method in methods:',
  '                rows.append((rel, dec.lineno, method, route, flask_fw, node.name))',
  '        elif attr in HTTP_METHODS:',
  '            rows.append((rel, dec.lineno, attr.upper(), route, fastapi_fw, node.name))',
  '',
  '',
  'def scan_django_calls(node, rel, rows):',
  '    if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Name):',
  '        return',
  '    if node.func.id not in DJANGO_CALLS or len(node.args) < 2:',
  '        return',
  '    route = str_const(node.args[0])',
  '    handler = dotted_name(node.args[1])',
  '    if route is None or not handler:',
  '        return',
  '    rows.append((rel, node.lineno, "ANY", route, "Django", handler))',
  '',
  '',
  'def scan_file(path, root, rows):',
  '    try:',
  '        text = io.open(path, encoding="utf-8").read()',
  '        tree = ast.parse(text)',
  '    except Exception:',
  '        return',
  '    flags = import_flags(tree)',
  '    rel = rel_posix(path, root)',
  '    flask_fw = "Flask" if flags["flask"] else ("Quart" if flags["quart"] else "Web")',
  '    fastapi_fw = "FastAPI" if flags["fastapi"] else ("Starlette" if flags["starlette"] else "Web")',
  '    for node in ast.walk(tree):',
  '        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):',
  '            scan_decorators(node, rel, flask_fw, fastapi_fw, rows)',
  '        if flags["django"]:',
  '            scan_django_calls(node, rel, rows)',
  '',
  '',
  'def main():',
  '    if len(sys.argv) < 3:',
  '        sys.stderr.write("usage: endpoints_scan.py <projectRoot> <out.txt>" + chr(10))',
  '        return 2',
  '    root = os.path.abspath(sys.argv[1])',
  '    out = sys.argv[2]',
  '    if not os.path.isdir(root):',
  '        sys.stderr.write("project root not found: " + root + chr(10))',
  '        return 2',
  '    rows = []',
  '    for path in collect_py_files(root):',
  '        scan_file(path, root, rows)',
  '    rows.sort(key=lambda row: (row[0], row[1], row[2]))',
  '    rows = rows[:MAX_ROWS]',
  '    lines = []',
  '    for row in rows:',
  '        lines.append(chr(9).join([row[2], row[3], row[0] + ":" + str(row[1]), row[4], row[5]]))',
  '    parent = os.path.dirname(out)',
  '    if parent and not os.path.isdir(parent):',
  '        os.makedirs(parent)',
  '    io.open(out, "w", encoding="utf-8", newline=chr(10)).write(chr(10).join(lines))',
  '    return 0',
  '',
  '',
  'def run():',
  '    try:',
  '        return main()',
  '    except Exception:',
  '        import traceback',
  '        traceback.print_exc(file=sys.stderr)',
  '        return 1',
  '',
  '',
  'sys.exit(run())',
].join('\n');
// #endpoints-py-end

/** 一个端点条目（method/route/file/line/framework/handler） */
export class EndpointEntry {
  /** GET / POST / ... 或 ANY（Django 的 path/url 调用无法静态确定方法） */
  method: string = '';
  /** 路由原样保留，不做前缀拼接 */
  route: string = '';
  /** 相对工程根的文件路径（统一 / 分隔） */
  file: string = '';
  /** 端点定义行号（装饰器行或 Django 调用行，从 1 起） */
  line: number = 0;
  /** Flask / FastAPI / Starlette / Django / Quart / Web */
  framework: string = '';
  /** 处理函数名（Django 为 views.xxx 这种点号形式） */
  handler: string = '';
}

/**
 * 把扫描脚本的输出文本解析成端点数组。
 * 每行 5 列 TAB 分隔：METHOD / route / rel-file:LINE / framework / handler；
 * 空行、列数不对、缺少 :行号、行号非正整数的行一律忽略。
 */
export function parseEndpointRows(txt: string): EndpointEntry[] {
  const rows: EndpointEntry[] = [];
  if (txt.length === 0) {
    return rows;
  }
  const lines: string[] = txt.split('\n');
  for (let i: number = 0; i < lines.length; i++) {
    let raw: string = lines[i];
    if (raw.endsWith('\r')) {
      raw = raw.substring(0, raw.length - 1);
    }
    if (raw.trim().length === 0) {
      continue;
    }
    const cols: string[] = raw.split('\t');
    if (cols.length !== 5) {
      continue;
    }
    const loc: string = cols[2];
    const sep: number = loc.lastIndexOf(':');
    if (sep <= 0) {
      continue;
    }
    const lineText: string = loc.substring(sep + 1);
    if (!/^[0-9]+$/.test(lineText)) {
      continue;
    }
    const lineNo: number = Number.parseInt(lineText, 10);
    if (lineNo <= 0) {
      continue;
    }
    const entry: EndpointEntry = new EndpointEntry();
    entry.method = cols[0];
    entry.route = cols[1];
    entry.file = loc.substring(0, sep);
    entry.line = lineNo;
    entry.framework = cols[3];
    entry.handler = cols[4];
    rows.push(entry);
  }
  return rows;
}
