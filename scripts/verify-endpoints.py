#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""EndpointService.ets 宿主验证：在「设备式」导入环境里真跑「端点」扫描脚本。

为什么这样验证
--------------
「端点」工具窗靠 EndpointService.ets 里的 ENDPOINTS_PY_SCRIPT 做纯静态 ast 扫描
（设备端是嵌入式 CPython 3.12.10，标准库从 rawfile/python/python312.zip 以 zipimport
加载，没有 flask/fastapi/django 这些包）。本脚本做四件事：

  1. 从 .ets 的 // #endpoints-py-begin / // #endpoints-py-end 标记区间**反转义**抽出
     真正的 Python 源码（逐行 TS 字符串字面量，按 TypeScript 语义还原转义，再用 \n 连接）；
  2. 用宿主 Python 3.12 全路径、以与设备一致的搜索路径
     sys.path = [<临时 site-packages>, <工程内 python312.zip>] 运行这段脚本；
     runner 会断言 ast 确实由 zipimport 从 zip 里加载，防止悄悄用了宿主标准库。
     另把宿主扩展目录（DLLs）追加在最后：设备端 C 扩展是静态链接进 libpython 的，
     宿主上必须从 DLLs 加载（与 verify-runtime-contract.py 同一做法）；只补 C 后端，
     绝不追加宿主纯 Python 标准库，所以 ast/os/io 等纯 Python 部分仍来自 zip；
  3. 临时生成 fixture 工程，逐场景断言**精确行号 / method / route / framework /
     handler / 排序**，并覆盖 Flask / FastAPI / Django / Quart / Web、负例、
     零误报、中文、隐藏目录排除、解析失败文件跳过、400 行截断；
  4. 另做一次独立校验：用 Python 复刻 parseEndpointRows 的文本切分规则，
     断言 5 列输出能还原 file/line，且非法行被忽略。

用法
----
    python scripts/verify-endpoints.py
    python scripts/verify-endpoints.py --project . --host-python <python.exe> --keep

约束（与任务契约一致）：只认字符串常量 route；不解析 include() 与蓝图/路由前缀；
解析失败的文件整体跳过；输出最多 400 行。
"""
from __future__ import annotations

import argparse
import io
import os
import shutil
import subprocess
import sys
import tempfile

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

HOST_PYTHON_DEFAULT = r"C:\Users\HUAWEI\AppData\Local\Programs\Python\Python312\python.exe"
ETS_REL = os.path.join("entry", "src", "main", "ets", "service", "EndpointService.ets")
ZIP_REL = os.path.join("entry", "src", "main", "resources", "rawfile", "python", "python312.zip")
BEGIN_MARK = "#endpoints-py-begin"
END_MARK = "#endpoints-py-end"

# 设备式 runner：sys.path = [临时 site-packages, python312.zip] + 宿主扩展目录
# （DLLs 只是设备端静态链接 C 扩展的替身；纯 Python 标准库必须来自 zip）。
# 断言 ast 来自 zip，否则说明验证悄悄借用了宿主标准库，结论无效。
RUNNER = '''import sys

site_dir, zip_path, dynload, script_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
sys.path[:] = [site_dir, zip_path]

# 注意：os 在替换 sys.path 之后才导入，因此连 os 都来自 zip；
# 若提前 import os，扫描脚本的 os 会复用宿主版本，模拟就不严格了。
import os
for _extra in dynload.split(os.pathsep):
    if _extra and os.path.isdir(_extra):
        sys.path.append(_extra)
sys.argv = [script_path] + sys.argv[5:]

import ast
origin = getattr(ast, "__file__", "") or ""
if "python312.zip" not in origin:
    sys.stderr.write("device-emulation FAILED: ast was not loaded from python312.zip: " + origin + chr(10))
    sys.exit(3)

src = open(script_path, "rb").read()
exec(compile(src, script_path, "exec"), {"__name__": "__main__", "__file__": script_path})
'''


# ---------------------------------------------------------------------------
# 1) 从 .ets 标记区间抽取脚本（模拟 TypeScript 字符串字面量的语义）
# ---------------------------------------------------------------------------

def parse_ts_string(text, start):
    """从 text[start] 的引号开始解析一个 TS 字符串字面量，返回 (值, 结束后的下标)。"""
    quote = text[start]
    if quote not in ("'", '"'):
        raise ValueError("start is not a string literal")
    out = []
    i = start + 1
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "\\":
            if i + 1 >= n:
                raise ValueError("dangling backslash in string literal")
            esc = text[i + 1]
            if esc == "n":
                out.append("\n")
            elif esc == "t":
                out.append("\t")
            elif esc == "r":
                out.append("\r")
            elif esc == "b":
                out.append("\b")
            elif esc == "f":
                out.append("\f")
            elif esc == "\\":
                out.append("\\")
            elif esc == "'":
                out.append("'")
            elif esc == '"':
                out.append('"')
            elif esc == "/":
                out.append("/")
            elif esc == "u":
                hex4 = text[i + 2:i + 6]
                if len(hex4) != 4:
                    raise ValueError("bad \\u escape")
                out.append(chr(int(hex4, 16)))
                i += 4
            else:
                out.append(esc)
            i += 2
            continue
        if ch == quote:
            return "".join(out), i + 1
        out.append(ch)
        i += 1
    raise ValueError("unterminated string literal")


def extract_script(ets_path):
    """抽取 ENDPOINTS_PY_SCRIPT：标记区间内每行一个 TS 字符串字面量，按 \\n 连接。"""
    text = io.open(ets_path, encoding="utf-8").read()
    begin = text.find(BEGIN_MARK)
    end = text.find(END_MARK, begin + 1) if begin >= 0 else -1
    if begin < 0 or end < 0:
        raise ValueError("缺少 // %s / // %s 标记" % (BEGIN_MARK, END_MARK))
    region_start = text.find("\n", begin) + 1
    region = text[region_start:end]
    parts = []
    for lineno, raw in enumerate(region.split("\n"), 1):
        s = raw.strip()
        if not s or s.startswith("//"):
            continue
        if s[0] not in ("'", '"'):
            continue
        value, after = parse_ts_string(s, 0)
        rest = s[after:].strip()
        if rest not in ("", ","):
            raise ValueError("标记区间第 %d 行字符串字面量后有多余内容：%r" % (lineno, rest))
        parts.append(value)
    if not parts:
        raise ValueError("标记区间没有抽取到任何脚本行")
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# 2) 设备式运行
# ---------------------------------------------------------------------------

def run_device(env, script_text, script_args):
    """把抽取到的脚本写进临时目录，用设备式搜索路径 + 宿主 Python 3.12 执行。

    script_args 是原样交给设备脚本的 argv[1:]（正常场景为 [工程根, 输出路径]）。
    """
    work = tempfile.mkdtemp(prefix="ep-run-")
    try:
        script_path = os.path.join(work, "endpoints_scan.py")
        io.open(script_path, "w", encoding="utf-8", newline="\n").write(script_text)
        site_dir = os.path.join(work, "site-packages")
        os.makedirs(site_dir)
        runner_path = os.path.join(work, "runner.py")
        io.open(runner_path, "w", encoding="utf-8", newline="\n").write(RUNNER)
        cmd = [env["host_python"], "-I", "-S", runner_path, site_dir,
               env["zip_path"], env.get("dynload", ""), script_path] + list(script_args)
        return subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    finally:
        shutil.rmtree(work, ignore_errors=True)


def host_extension_dirs(host_python):
    """宿主解释器的 C 扩展目录（设备端这些模块静态链接在 libpython 里）。

    只返回平台扩展目录（DLLs / lib-dynload）；绝不返回宿主 Lib，否则纯 Python
    标准库会被宿主版本悄悄顶替，验证就失去意义了。
    """
    code = "\n".join([
        "import os, sys, sysconfig",
        "p = sysconfig.get_paths()",
        "c = [os.path.join(p.get('platstdlib', ''), 'DLLs'),",
        "     os.path.join(p.get('stdlib', ''), 'lib-dynload'),",
        "     os.path.join(sys.prefix, 'DLLs')]",
        "print(os.pathsep.join([d for d in c if d and os.path.isdir(d)]))",
    ])
    try:
        proc = subprocess.run([host_python, "-c", code], capture_output=True, text=True)
        return (proc.stdout or "").strip()
    except Exception:
        return ""


# ---------------------------------------------------------------------------
# 3) 输出解析 + parseEndpointRows 的 Python 复刻（文本契约独立校验）
# ---------------------------------------------------------------------------

def rows_from_output(text):
    """严格解析脚本输出：每行必须 5 列 TAB 分隔，第 3 列 rel-file:LINE。"""
    rows = []
    for lineno, line in enumerate(text.split("\n"), 1):
        if line == "":
            continue
        cols = line.split("\t")
        if len(cols) != 5:
            raise ValueError("第 %d 行不是 5 列（实际 %d 列）：%r" % (lineno, len(cols), line))
        loc = cols[2]
        sep = loc.rfind(":")
        if sep < 0:
            raise ValueError("第 %d 行缺少 :行号：%r" % (lineno, loc))
        line_text = loc[sep + 1:]
        try:
            line_no = int(line_text, 10)
        except ValueError:
            raise ValueError("第 %d 行行号不是整数：%r" % (lineno, loc))
        rows.append((cols[0], cols[1], loc[:sep], line_no, cols[3], cols[4]))
    return rows


def parse_rows_mirror(txt):
    """独立复刻 EndpointService.parseEndpointRows 的切分规则（不 import 被测代码）。

    规则：按 \n 拆行；去掉行尾 \r；跳过空白行；TAB 拆列且必须正好 5 列；
    第 3 列用最后一个 ':' 拆 file/line；file 为空、行号非 ASCII 数字、行号 <= 0 的行跳过。
    """
    entries = []
    if not txt:
        return entries
    for raw in txt.split("\n"):
        if raw.endswith("\r"):
            raw = raw[:-1]
        if not raw.strip():
            continue
        cols = raw.split("\t")
        if len(cols) != 5:
            continue
        loc = cols[2]
        sep = loc.rfind(":")
        if sep <= 0:
            continue
        line_text = loc[sep + 1:]
        if not line_text or not all(c in "0123456789" for c in line_text):
            continue
        line_no = int(line_text, 10)
        if line_no <= 0:
            continue
        entries.append({
            "method": cols[0],
            "route": cols[1],
            "file": loc[:sep],
            "line": line_no,
            "framework": cols[3],
            "handler": cols[4],
        })
    return entries


def fmt_row(row):
    return "%s %s %s:%d %s %s" % (row[0], row[1], row[2], row[3], row[4], row[5])


def compare_rows(expected, actual):
    problems = []
    exp = list(expected)
    act = list(actual)
    missing = [r for r in exp if r not in act]
    extra = [r for r in act if r not in exp]
    for row in missing:
        problems.append("缺少: " + fmt_row(row))
    for row in extra:
        problems.append("多出: " + fmt_row(row))
    if not missing and not extra:
        for idx, (want, got) in enumerate(zip(exp, act)):
            if want != got:
                problems.append("排序不符：第 %d 行期望 %s，实际 %s" % (idx + 1, fmt_row(want), fmt_row(got)))
                break
    return problems


# ---------------------------------------------------------------------------
# 4) fixture 工程
# ---------------------------------------------------------------------------

def line_of(lines, needle):
    for idx, line in enumerate(lines):
        if needle in line:
            return idx + 1
    raise AssertionError("fixture 中找不到标记行：%r" % needle)


MAIN_FILES = {
    "app_flask.py": [
        "# Flask 示例：中文注释与中文路由都不能导致乱码",
        "import flask",
        "app = flask.Flask(__name__)",
        "",
        '@app.route("/hello")',
        "def hello():",
        '    return "你好"',
        "",
        '@app.route("/submit", methods=["GET", "POST"])',
        "def submit():",
        '    return "ok"',
        "",
        '@app.route("/only-get")',
        "def only_get():",
        '    return "g"',
        "",
        "def helper():",
        '    # @app.route("/fake-in-comment")',
        "    return 1",
    ],
    "routers/items.py": [
        "from fastapi import APIRouter",
        "",
        'router = APIRouter(prefix="/api")',
        "",
        '@router.get("/items")',
        "def list_items():",
        "    return []",
        "",
        '@router.post("/items")',
        "def create_item():",
        "    return {}",
    ],
    "app_fastapi.py": [
        "from fastapi import FastAPI",
        "",
        "app = FastAPI()",
        "",
        '@app.delete("/items/{id}")',
        "def delete_item(item_id: str):",
        '    return {"ok": True}',
    ],
    "app_quart.py": [
        "from quart import Quart",
        "app = Quart(__name__)",
        "",
        '@app.route("/q/hello")',
        "async def q_hello():",
        '    return "q"',
        "",
        '@app.route("/q/lower", methods=["get"])',
        "def q_lower():",
        '    return "l"',
    ],
    "app_starlette.py": [
        "from starlette.applications import Starlette",
        "app = Starlette()",
        "",
        '@app.get("/star")',
        "def star_route():",
        "    return 1",
    ],
    "web_generic.py": [
        "# 没有 import 任何 Web 框架：framework 记为 Web",
        '@app.route("/web-only")',
        "def web_only():",
        "    return 1",
    ],
    "urls.py": [
        "from django.urls import path, re_path, include",
        "from django.conf.urls import url",
        "from . import views",
        "",
        "urlpatterns = [",
        '    path("home/", views.home, name="home"),',
        '    re_path(r"^x/(?P<id>\\d+)$", views.x),',
        '    url(r"^y/", views.y),',
        '    path("api/", include("app.urls")),',
        '    path("about/", about),',
        "]",
    ],
    "cn_routes.py": [
        "# -*- coding: utf-8 -*-",
        "# 中文注释：端点扫描不应崩溃，也不应乱码",
        "from fastapi import FastAPI",
        "app = FastAPI()",
        "",
        '@app.get("/中文/路径")',
        "def 中文处理():",
        '    return "中文返回值"',
    ],
    "negatives.py": [
        "from flask import Flask",
        "app = Flask(__name__)",
        'PREFIX = "/api"',
        "",
        "def plain_function():",
        "    return 1",
        "",
        '@app.route(PREFIX + "/x")',
        "def concat_route():",
        "    return 1",
        "",
        'route = "/var"',
        "",
        "@app.route(route)",
        "def var_route():",
        "    return 1",
        "",
        '@app.route("/multi", methods=[METHOD])',
        "def var_method():",
        "    return 1",
        "",
        "@app.route()",
        "def no_route():",
        "    return 1",
    ],
}

EXCLUDED_FILES = {
    ".hidden/hidden_routes.py": [
        "from flask import Flask",
        "app = Flask(__name__)",
        "",
        '@app.route("/hidden")',
        "def hidden():",
        "    return 1",
    ],
    "venv/lib/venv_routes.py": [
        "from flask import Flask",
        "app = Flask(__name__)",
        "",
        '@app.route("/venv")',
        "def venv_route():",
        "    return 1",
    ],
    "site-packages/pkg/sp_routes.py": [
        "from flask import Flask",
        "app = Flask(__name__)",
        "",
        '@app.route("/site-packages")',
        "def sp_route():",
        "    return 1",
    ],
    "__pycache__/pycache_routes.py": [
        "from flask import Flask",
        "app = Flask(__name__)",
        "",
        '@app.route("/pycache")',
        "def pycache_route():",
        "    return 1",
    ],
    ".harmonyide/gen_routes.py": [
        "from flask import Flask",
        "app = Flask(__name__)",
        "",
        '@app.route("/harmonyide-gen")',
        "def gen_route():",
        "    return 1",
    ],
}

PLAIN_FILES = {
    "main.py": [
        "# 纯 Python 工程：没有任何 Web 框架",
        "",
        "def add(a, b):",
        "    return a + b",
        "",
        "class Greeter:",
        "    def hello(self):",
        '        return "hi"',
    ],
    "pkg/util.py": [
        "# 工具函数",
        "",
        "def clamp(v, lo, hi):",
        "    return max(lo, min(hi, v))",
    ],
}

# (method, route, file, line, framework, handler, fixture 里用于自检行号的标记文本)
EXPECTED_MAIN = [
    ("GET", "/hello", "app_flask.py", 5, "Flask", "hello", '@app.route("/hello")'),
    ("GET", "/submit", "app_flask.py", 9, "Flask", "submit", '@app.route("/submit"'),
    ("POST", "/submit", "app_flask.py", 9, "Flask", "submit", '@app.route("/submit"'),
    ("GET", "/only-get", "app_flask.py", 13, "Flask", "only_get", '@app.route("/only-get")'),
    ("GET", "/items", "routers/items.py", 5, "FastAPI", "list_items", '@router.get("/items")'),
    ("POST", "/items", "routers/items.py", 9, "FastAPI", "create_item", '@router.post("/items")'),
    ("DELETE", "/items/{id}", "app_fastapi.py", 5, "FastAPI", "delete_item", '@app.delete("/items/{id}")'),
    ("GET", "/q/hello", "app_quart.py", 4, "Quart", "q_hello", '@app.route("/q/hello")'),
    ("GET", "/q/lower", "app_quart.py", 8, "Quart", "q_lower", '@app.route("/q/lower", methods=["get"])'),
    ("GET", "/star", "app_starlette.py", 4, "Starlette", "star_route", '@app.get("/star")'),
    ("GET", "/web-only", "web_generic.py", 2, "Web", "web_only", '@app.route("/web-only")'),
    ("ANY", "home/", "urls.py", 6, "Django", "views.home", 'path("home/", views.home'),
    ("ANY", "^x/(?P<id>\\d+)$", "urls.py", 7, "Django", "views.x", 're_path(r"^x/(?P<id>\\d+)$"'),
    ("ANY", "^y/", "urls.py", 8, "Django", "views.y", 'url(r"^y/", views.y)'),
    ("ANY", "about/", "urls.py", 10, "Django", "about", 'path("about/", about)'),
    ("GET", "/中文/路径", "cn_routes.py", 6, "FastAPI", "中文处理", '@app.get("/中文/路径")'),
]

BANNED_ROUTES = ["/x", "/var", "/multi", "/fake-in-comment", "/hidden",
                 "/venv", "/site-packages", "/pycache", "/harmonyide-gen"]


def write_tree(root, files):
    for rel, lines in files.items():
        path = os.path.join(root, *rel.split("/"))
        parent = os.path.dirname(path)
        if parent and not os.path.isdir(parent):
            os.makedirs(parent)
        io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


def expected_rows(specs):
    rows = [(method, route, rel, line, framework, handler)
            for method, route, rel, line, framework, handler, _marker in specs]
    return sorted(rows, key=lambda row: (row[2], row[3], row[0]))


def verify_fixture_lines(files, specs):
    for _method, _route, rel, line, _framework, _handler, marker in specs:
        if rel not in files:
            raise AssertionError("fixture 缺少文件：" + rel)
        actual = line_of(files[rel], marker)
        if actual != line:
            raise AssertionError("fixture 行号漂移：%s 的 %r 在第 %d 行（期望 %d）"
                                 % (rel, marker, actual, line))


def run_case(env, script_text, project_root, out_path):
    info = {"problems": [], "text": "", "rows": [], "proc": None}
    try:
        proc = run_device(env, script_text, [project_root, out_path])
    except Exception as exc:
        info["problems"].append("无法启动设备式 Python：%r" % (exc,))
        return info
    info["proc"] = proc
    if proc.returncode != 0:
        info["problems"].append("退出码 %d（期望 0）" % proc.returncode)
        err_tail = "\n".join((proc.stderr or "").strip().splitlines()[-6:])
        if err_tail:
            info["problems"].append("stderr 尾部：" + err_tail.replace("\n", " | "))
        return info
    if proc.stderr.strip():
        info["problems"].append("stderr 非空：%r" % proc.stderr.strip()[:200])
    if not os.path.exists(out_path):
        info["problems"].append("输出文件不存在：%s" % out_path)
        return info
    try:
        info["text"] = io.open(out_path, encoding="utf-8").read()
    except Exception as exc:
        info["problems"].append("输出不是合法 UTF-8：%r" % (exc,))
        return info
    if info["text"].startswith("\ufeff"):
        info["problems"].append("输出带 UTF-8 BOM")
        info["text"] = info["text"][1:]
    try:
        info["rows"] = rows_from_output(info["text"])
    except Exception as exc:
        info["problems"].append("输出格式非法：%s" % exc)
    return info


# ---------------------------------------------------------------------------
# 5) 场景
# ---------------------------------------------------------------------------

class Report:
    def __init__(self):
        self.items = []

    def add(self, name, problems):
        problems = list(problems)
        self.items.append((name, problems))
        print("[%d] %s  %s" % (len(self.items), name, "OK" if not problems else "FAIL"))
        for problem in problems[:24]:
            print("      " + problem.replace("\n", "\n      "))
        if len(problems) > 24:
            print("      ...（另有 %d 条问题）" % (len(problems) - 24))


def resolve_project(explicit):
    if explicit:
        return os.path.abspath(explicit)
    start = os.path.dirname(os.path.abspath(__file__))
    cur = start
    for _ in range(10):
        if os.path.exists(os.path.join(cur, ETS_REL)):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return os.path.abspath(os.path.join(start, ".."))


def pick_host_python(requested):
    if requested and os.path.exists(requested):
        return requested
    if requested:
        print("WARN: 宿主 Python 不存在（%s），改用当前解释器：%s" % (requested, sys.executable))
        return sys.executable
    return sys.executable


def main():
    parser = argparse.ArgumentParser(
        description="EndpointService.ets 宿主验证（设备式 CPython 环境 + fixture 断言）")
    parser.add_argument("--project", default="", help="工程根（默认从脚本位置向上找）")
    parser.add_argument("--host-python", default=HOST_PYTHON_DEFAULT,
                        help="宿主 Python 3.12 全路径（设备端同版本）")
    parser.add_argument("--zip", dest="zip_path", default="",
                        help="设备端标准库 zip（默认 entry/src/main/resources/rawfile/python/python312.zip）")
    parser.add_argument("--keep", action="store_true", help="保留临时 fixture 目录")
    args = parser.parse_args()

    project = resolve_project(args.project)
    ets_path = os.path.join(project, ETS_REL)
    zip_path = os.path.abspath(args.zip_path) if args.zip_path else os.path.join(project, ZIP_REL)
    host_python = pick_host_python(args.host_python)

    print("== EndpointService（端点工具窗）宿主验证 ==")
    print("工程根      : %s" % project)
    print(".ets 文件   : %s" % ets_path)
    print("标准库 zip  : %s" % zip_path)
    print("主机 Python : %s" % host_python)

    if not os.path.exists(ets_path):
        print("FAIL: 找不到 .ets 文件")
        print("RESULT: FAIL")
        return 2
    if not os.path.exists(zip_path):
        print("FAIL: 找不到设备端标准库 zip")
        print("RESULT: FAIL")
        return 2
    try:
        version = subprocess.run([host_python, "--version"], capture_output=True, text=True)
        version_text = (version.stdout or version.stderr or "").strip()
    except Exception as exc:
        version_text = "无法执行：%r" % (exc,)
    print("Python 版本 : %s" % version_text)

    try:
        script = extract_script(ets_path)
        compile(script, "<ENDPOINTS_PY_SCRIPT>", "exec")
    except Exception as exc:
        print("FAIL: 从 .ets 抽取/编译脚本失败：%s" % exc)
        print("RESULT: FAIL")
        return 2
    print("抽取脚本    : %d 行 / %d 字节（标记区间反转义，compile 通过）"
          % (script.count("\n") + 1, len(script.encode("utf-8"))))
    dynload = host_extension_dirs(host_python)
    print("搜索路径    : [<临时 site-packages>, <python312.zip>, <宿主扩展目录替身>]（runner 断言 ast 来自 zip）")
    print("扩展替身    : %s" % (dynload if dynload else "(未找到；设备端 C 扩展静态链接进 libpython)"))
    print("")

    env = {"host_python": host_python, "zip_path": os.path.abspath(zip_path),
           "dynload": dynload}
    report = Report()
    temp_root = tempfile.mkdtemp(prefix="ep-verify-")
    try:
        out_dir = os.path.join(temp_root, "out")
        main_proj = os.path.join(temp_root, "proj_main")
        verify_fixture_lines(MAIN_FILES, EXPECTED_MAIN)
        write_tree(main_proj, MAIN_FILES)
        write_tree(main_proj, EXCLUDED_FILES)
        write_tree(main_proj, {"broken.py": ["def broken(:", "    return 1"]})

        expected_main = expected_rows(EXPECTED_MAIN)
        main_case = run_case(env, script, main_proj, os.path.join(out_dir, "main.txt"))
        base_problems = list(main_case["problems"])
        rows_main = main_case["rows"]

        def scenario_flask():
            problems = list(base_problems)
            want = [row for row in expected_main if row[2] == "app_flask.py"]
            got = [row for row in rows_main if row[2] == "app_flask.py"]
            problems.extend(compare_rows(want, got))
            return problems

        def scenario_fastapi():
            problems = list(base_problems)
            want = [row for row in expected_main
                    if row[2] in ("routers/items.py", "app_fastapi.py", "app_starlette.py")]
            got = [row for row in rows_main
                   if row[2] in ("routers/items.py", "app_fastapi.py", "app_starlette.py")]
            problems.extend(compare_rows(want, got))
            return problems

        def scenario_django():
            problems = list(base_problems)
            want = [row for row in expected_main if row[2] == "urls.py"]
            got = [row for row in rows_main if row[2] == "urls.py"]
            problems.extend(compare_rows(want, got))
            for row in rows_main:
                if row[2] == "urls.py" and ("app.urls" in row[1] or "include" in row[5]):
                    problems.append("include() 被误报: " + fmt_row(row))
            return problems

        def scenario_negatives():
            problems = list(base_problems)
            bad_files = ("negatives.py", "broken.py", ".hidden/hidden_routes.py",
                         "venv/lib/venv_routes.py", "site-packages/pkg/sp_routes.py",
                         "__pycache__/pycache_routes.py", ".harmonyide/gen_routes.py")
            for row in rows_main:
                if row[2] in bad_files:
                    problems.append("误报（本应被排除或跳过）: " + fmt_row(row))
            if len(rows_main) != len(expected_main):
                problems.append("端点总数期望 %d，实际 %d（可能混入负例/排除目录）"
                                % (len(expected_main), len(rows_main)))
            for row in rows_main:
                if row[1] in BANNED_ROUTES:
                    problems.append("负例 route 被命中: " + fmt_row(row))
            return problems

        plain_proj = os.path.join(temp_root, "proj_plain")
        write_tree(plain_proj, PLAIN_FILES)
        plain_case = run_case(env, script, plain_proj, os.path.join(out_dir, "plain.txt"))

        def scenario_zero():
            problems = list(plain_case["problems"])
            if plain_case["text"] != "":
                problems.append("零端点时应写空文件，实际 %d 字节：%r"
                                % (len(plain_case["text"]), plain_case["text"][:120]))
            if plain_case["rows"]:
                problems.append("纯 Python 工程不应有任何端点，实际 %d 行" % len(plain_case["rows"]))
            return problems

        def scenario_chinese():
            problems = list(base_problems)
            want = [row for row in expected_main if row[2] == "cn_routes.py"]
            got = [row for row in rows_main if row[2] == "cn_routes.py"]
            problems.extend(compare_rows(want, got))
            text = main_case["text"]
            if "\ufffd" in text:
                problems.append("输出含替换字符 U+FFFD，疑似编码损坏")
            if "/中文/路径" not in text:
                problems.append("输出缺少中文路由 /中文/路径")
            if "中文处理" not in text:
                problems.append("输出缺少中文 handler 中文处理")
            return problems

        many_proj = os.path.join(temp_root, "proj_many")
        many_lines = ["from flask import Flask", "app = Flask(__name__)", ""]
        for idx in range(420):
            many_lines.append('@app.route("/r%d")' % idx)
            many_lines.append("def h%d():" % idx)
            many_lines.append("    return %d" % idx)
            many_lines.append("")
        write_tree(many_proj, {"many.py": many_lines})
        many_case = run_case(env, script, many_proj, os.path.join(out_dir, "many.txt"))

        def scenario_truncate():
            problems = list(many_case["problems"])
            rows = many_case["rows"]
            if len(rows) != 400:
                problems.append("期望截断到 400 行，实际 %d 行" % len(rows))
            for idx, row in enumerate(rows[:400]):
                if row[1] != "/r%d" % idx:
                    problems.append("第 %d 行期望 /r%d，实际 %s" % (idx + 1, idx, row[1]))
                    break
                if row[3] != 4 + 4 * idx:
                    problems.append("第 %d 行号期望 %d，实际 %d" % (idx + 1, 4 + 4 * idx, row[3]))
                    break
            if rows and row[2] != "many.py":
                problems.append("截断场景文件路径异常：%s" % row[2])
            if list(rows) != sorted(rows, key=lambda row: (row[2], row[3], row[0])):
                problems.append("输出未按 file/line/method 升序排序")
            return problems

        def scenario_errors():
            problems = []
            try:
                short = run_device(env, script, [temp_root])
            except Exception as exc:
                return ["无法启动设备式 Python：%r" % (exc,)]
            if short.returncode == 0:
                problems.append("参数不足（只给 1 个参数）时应退出非 0，实际 0")
            if not (short.stderr or "").strip():
                problems.append("参数不足时 stderr 为空（契约要求 stderr 带信息）")
            missing_out = os.path.join(out_dir, "missing.txt")
            try:
                missing = run_device(env, script, [os.path.join(temp_root, "no-such-root"), missing_out])
            except Exception as exc:
                return problems + ["无法启动设备式 Python：%r" % (exc,)]
            if missing.returncode == 0:
                problems.append("工程根不存在时应退出非 0，实际 0")
            if not (missing.stderr or "").strip():
                problems.append("工程根不存在时 stderr 为空（契约要求 stderr 带信息）")
            if os.path.exists(missing_out):
                problems.append("工程根不存在时不应写输出文件")
            return problems

        def scenario_contract():
            problems = list(base_problems)
            text = main_case["text"]
            for idx, line in enumerate(text.split("\n"), 1):
                if line and len(line.split("\t")) != 5:
                    problems.append("扫描输出第 %d 行不是 5 列：%r" % (idx, line))
            mirror = parse_rows_mirror(text)
            mirror_rows = [(entry["method"], entry["route"], entry["file"], entry["line"],
                            entry["framework"], entry["handler"]) for entry in mirror]
            problems.extend(compare_rows(expected_main, mirror_rows))
            for entry in mirror:
                if not entry["file"] or entry["line"] <= 0:
                    problems.append("复刻解析还原出非法 file/line：%r" % (entry,))
                    break

            synthetic = "\n".join([
                "GET\t/ok\tpkg/a.py:3\tFlask\th",
                "",
                "   ",
                "GET\t/bad\tpkg/a.py\tFlask\th",
                "GET\t/bad\tpkg/a.py:x\tFlask\th",
                "GET\t/bad\tpkg/a.py:0\tFlask\th",
                "GET\t/bad\t:7\tFlask\th",
                "GET\t/bad\tpkg/a.py:5\tFlask",
                "GET\t/bad\tpkg/a.py:5\tFlask\th\textra",
                "GET\t/windows\tC:/work/app.py:12\tWeb\twin",
                "POST\t/crlf\twin/app.py:9\tFlask\tcrlf\r",
            ])
            want = [
                {"method": "GET", "route": "/ok", "file": "pkg/a.py", "line": 3,
                 "framework": "Flask", "handler": "h"},
                {"method": "GET", "route": "/windows", "file": "C:/work/app.py", "line": 12,
                 "framework": "Web", "handler": "win"},
                {"method": "POST", "route": "/crlf", "file": "win/app.py", "line": 9,
                 "framework": "Flask", "handler": "crlf"},
            ]
            got = parse_rows_mirror(synthetic)
            if got != want:
                problems.append("复刻解析对非法行/盘符冒号/CRLF 的处理不符：期望 %r，实际 %r"
                                % (want, got))
            return problems

        report.add("1. Flask 规则（route 常量 / methods 多方法展开 / 默认 GET / 注释装饰器不命中）",
                   scenario_flask())
        report.add("2. FastAPI 风格装饰器（@router.get / @app.post / @app.delete，method 大写，Starlette）",
                   scenario_fastapi())
        report.add("3. Django 规则（path/re_path/url、ANY、handler 点号、include() 不误报）",
                   scenario_django())
        report.add("4. 负例与排除（普通函数/拼接 route/变量 route/解析失败/隐藏与依赖目录）",
                   scenario_negatives())
        report.add("5. 零误报（纯 Python 工程 → 空输出且退出码 0）", scenario_zero())
        report.add("6. 中文（中文注释与中文路由不乱码、不崩溃）", scenario_chinese())
        report.add("7. 排序与截断（420 个端点 → 400 行，file/line/method 升序）", scenario_truncate())
        report.add("8. 文本契约（5 列可还原 file/line；非法行/盘符冒号/CRLF）", scenario_contract())
        report.add("9. 错误路径（缺参 / 工程根不存在 → 退出码非 0 且 stderr 有信息）", scenario_errors())
    except Exception as exc:
        print("")
        print("FAIL: 验证自身出错（fixture/环境）：%r" % (exc,))
        print("RESULT: FAIL")
        return 2
    finally:
        if args.keep:
            print("")
            print("临时 fixture 保留在：%s" % temp_root)
        else:
            shutil.rmtree(temp_root, ignore_errors=True)

    failed = [name for name, problems in report.items if problems]
    print("")
    if failed:
        print("RESULT: FAIL（%d/%d 个场景失败）" % (len(failed), len(report.items)))
        return 1
    print("RESULT: PASS（%d 个场景全部通过）" % len(report.items))
    return 0


if __name__ == "__main__":
    sys.exit(main())
