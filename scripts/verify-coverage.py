#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CoverageService 宿主验证：把 .ets 里的覆盖率脚本抽出来，在“设备等价”的
导入环境（只有随包 python312.zip + 空 site-packages，不加载宿主标准库）里真跑 6 个场景。

为什么这样做
------------
设备端的嵌入式 CPython 3.12.10 用 zipimport 直接从
entry/src/main/resources/rawfile/python/python312.zip 加载标准库，没有宿主环境。
覆盖率脚本将来在设备上执行，所以这里在宿主机上模拟同一套 sys.path：

    sys.path = [ <临时空 site-packages>, <工程根>/.../python312.zip ]

宿主 Python 用 -I -S 隔离启动（不读 PYTHONPATH、不加载 site），再由 launcher.py
把 sys.path 整个替换掉。这样脚本能跑起来，就证明它只依赖随包 zip 里的纯 Python 标准库。

验证内容
--------
  场景 0  隔离环境：sys.path 只有空 site-packages + python312.zip；json/dis 等来自 zip
  场景 1  示例工程等价 fixture（main.py 调 utils.fib，含未走到的分支）：跨文件覆盖精确
  场景 2  目标抛异常：JSON 仍生成、ok=true、exit!=0、message 含异常类型与行号
  场景 3  目标 sys.exit(3)：exit=3、JSON 正常、不崩
  场景 4  目标大量执行标准库代码：报告里不出现标准库路径
  场景 5  目标不存在 / target='-'：ok=false、message 有说明、不抛未捕获异常
  场景 6  schema 校验：字段/类型/排序/percent 公式/文件排序符合契约（含 400 个截断）

用法
----
    python scripts/verify-coverage.py [--host-python <python.exe>]

宿主 Python 必须就是设备同版本的 3.12（默认用下面的全路径；PATH 上的 python.exe
是微软商店占位程序，不能用）。全部场景 PASS 时退出码 0，否则 1。
"""
from __future__ import annotations

import argparse
import dis
import json
import os
import re
import subprocess
import sys
import tempfile
import types
from pathlib import Path

DEFAULT_HOST_PYTHON = r"C:\Users\HUAWEI\AppData\Local\Programs\Python\Python312\python.exe"
REPO_ROOT = Path(__file__).resolve().parent.parent
ETS_FILE = REPO_ROOT / "entry" / "src" / "main" / "ets" / "service" / "CoverageService.ets"
STDLIB_ZIP = REPO_ROOT / "entry" / "src" / "main" / "resources" / "rawfile" / "python" / "python312.zip"

BEGIN_MARK = "#coverage-py-begin"
END_MARK = "#coverage-py-end"

# 在“设备等价”环境里 exec 覆盖率脚本的启动器：先替换 sys.path，再按 __main__ 跑脚本。
LAUNCHER_SOURCE = """# -*- coding: utf-8 -*-
# 宿主验证用启动器：模拟设备端 PyConfig 给出的 sys.path，然后以 __main__ 语义执行目标脚本。
import sys

site_dir, zip_path, script_path = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path[:] = [site_dir, zip_path]
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass
sys.argv = [script_path] + sys.argv[4:]
with open(script_path, "r", encoding="utf-8") as handle:
    source = handle.read()
code = compile(source, script_path, "exec")
exec(code, {"__name__": "__main__", "__file__": script_path})
"""

# 场景 0 用：证明隔离环境里覆盖率脚本要用的模块确实来自随包 zip（或解释器内建）。
PROBE_SOURCE = """# -*- coding: utf-8 -*-
import json
import sys

info = {"path": sys.path, "mods": {}}
for name in ("json", "dis", "traceback", "threading", "ast", "runpy"):
    module = __import__(name)
    spec = getattr(module, "__spec__", None)
    info["mods"][name] = [
        getattr(spec, "origin", "") or "",
        getattr(module, "__file__", "") or "",
    ]
sys.stdout.write("@@PROBE@@" + json.dumps(info) + "@@END@@")
"""

CHECK_TOTAL = 0
CHECK_FAILED = 0


def setup_stdout() -> None:
    """被管道捕获时统一用 UTF-8 输出，避免 Windows 代码页把中文打乱。"""
    for stream in (sys.stdout, sys.stderr):
        try:
            if not stream.isatty():
                stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass


def check(condition: bool, label: str, detail: str = "") -> bool:
    global CHECK_TOTAL, CHECK_FAILED
    CHECK_TOTAL += 1
    suffix = "  [" + detail + "]" if detail else ""
    if condition:
        print("  OK   " + label + suffix)
    else:
        CHECK_FAILED += 1
        print("  FAIL " + label + suffix)
    return condition


def section(title: str) -> None:
    print("\n== " + title + " ==")


def extract_coverage_script(ets_path: Path):
    """从 CoverageService.ets 的标记行之间抽出 Python 脚本数组（反转义 \' 与 \\）。"""
    text = ets_path.read_text(encoding="utf-8")
    element = re.compile(r"^\s*'((?:[^'\\]|\\.)*)'\s*,?\s*$")
    chunks = []
    ignored = []
    begin_seen = False
    end_seen = False
    in_block = False
    for line in text.splitlines():
        if BEGIN_MARK in line:
            begin_seen = True
            in_block = True
            continue
        if END_MARK in line:
            end_seen = True
            in_block = False
            continue
        if not in_block:
            continue
        match = element.match(line)
        if match:
            # ArkTS 单引号字符串 -> 原始字符：\' -> '，\\ -> \
            chunks.append(re.sub(r"\\(['\\])", r"\1", match.group(1)))
            continue
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("export const COVERAGE_PY_SCRIPT") or stripped.startswith("].join("):
            continue
        ignored.append(stripped)
    script = "\n".join(chunks) + "\n" if chunks else ""
    return script, begin_seen, end_seen, ignored


def executable_lines(path: Path) -> set:
    """独立实现一遍“可执行行”算法，用来核对脚本报告的行数。"""
    code = compile(path.read_bytes(), str(path), "exec")
    lines = set()
    stack = [code]
    seen = set()
    while stack:
        current = stack.pop()
        if id(current) in seen:
            continue
        seen.add(id(current))
        for _offset, lineno in dis.findlinestarts(current):
            if lineno and lineno > 0:
                lines.add(lineno)
        for const in current.co_consts:
            if isinstance(const, types.CodeType):
                stack.append(const)
    return lines


def line_index(text: str, needle: str, start: int = 1) -> int:
    for index, line in enumerate(text.splitlines(), 1):
        if index >= start and needle in line:
            return index
    raise AssertionError("fixture 里找不到标记：" + needle)


def write_file(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def run_coverage(work: Path, root: Path, target: str, out_name: str):
    """用隔离启动器跑一次覆盖率脚本，返回 (report dict 或 None, CompletedProcess)。"""
    out_path = work / out_name
    command = [
        HOST_PYTHON,
        "-I", "-S",
        str(work / "launcher.py"),
        str(work / "site"),
        str(STDLIB_ZIP),
        str(work / "coverage_run.py"),
        str(root),
        str(out_path),
        target,
    ]
    proc = subprocess.run(command, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=300)
    report = None
    error = ""
    if out_path.exists():
        try:
            report = json.loads(out_path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001 - 验证脚本要报告任何坏 JSON
            error = "JSON 解析失败: %s: %s" % (type(exc).__name__, exc)
    else:
        error = "报告文件不存在"
    return report, proc, error


def nonempty_lines(proc) -> list:
    return [line for line in proc.stdout.splitlines() if line.strip()]


def summary_is_last(proc) -> bool:
    lines = nonempty_lines(proc)
    return bool(lines) and lines[-1].startswith("覆盖率：")


def get_entry(report, rel: str):
    for entry in report.get("files", []):
        if entry.get("path") == rel:
            return entry
    return None


# ---------------------------------------------------------------------------
# fixture 内容
# ---------------------------------------------------------------------------

FIXTURE1_MAIN = [
    '"""示例工程等价 fixture：main.py 调用 utils.fib，并包含走不到的分支。"""',
    "# sample-v4",
    "import sys",
    "",
    "import utils",
    "",
    "",
    "def greet(name: str) -> str:",
    '    return f"你好, {name}!"',
    "",
    "",
    "def unused_branch(flag: bool) -> str:",
    "    if flag:",
    '        return "hit"',
    '    return "miss"  # COVERAGE_MARK_MISS_BRANCH',
    "",
    "",
    "def main() -> None:",
    '    print(greet("鸿蒙"))',
    '    print("Python :", sys.version.split()[0])',
    '    print("斐波那契:", utils.fib(8))',
    "    print(unused_branch(True))",
    "",
    "",
    'if __name__ == "__main__":',
    "    main()",
    "",
]

FIXTURE1_UTILS = [
    '"""常用工具函数，模拟示例工程的 utils.py。"""',
    "",
    "",
    "def fib(n: int) -> list:",
    '    """返回前 n 个斐波那契数（n<=1 的分支在示例里走不到）。"""',
    "    seq = [0, 1]",
    "    if n <= 1:",
    "        return seq[:n]  # COVERAGE_MARK_EARLY_RETURN",
    "    while len(seq) < n:",
    "        seq.append(seq[-1] + seq[-2])",
    "    return seq[:n]",
    "",
    "",
    "def never_called(n: int) -> int:",
    "    if n > 0:",
    "        return 1",
    "    return 0",
    "",
]

FIXTURE2 = [
    '"""目标故意抛异常：验证 JSON 仍生成、exit!=0、message 含异常类型与行号。"""',
    "",
    "",
    "def explode(n: int) -> int:",
    "    if n > 0:",
    '        raise ValueError("故意的覆盖率测试异常")  # COVERAGE_MARK_RAISE',
    "    return 0",
    "",
    "",
    "explode(1)",
    "",
]

FIXTURE3 = [
    '"""目标调用 sys.exit(3)：必须被捕获、报告正常写出。"""',
    "import sys",
    "",
    'print("hello")',
    "sys.exit(3)",
    "",
]

FIXTURE4 = [
    '"""目标大量执行标准库代码，用于验证标准库行不会进覆盖率报告。"""',
    "import ast",
    "import collections",
    "import dis",
    "import functools",
    "import json",
    "import os",
    "import pathlib",
    "import platform",
    "import sys",
    "import traceback",
    "import types",
    "",
    "",
    "def heavy() -> int:",
    '    data = json.loads(json.dumps({"a": [1, 2, 3], "b": "鸿蒙"}))',
    '    counter = collections.Counter("harmony python ide")',
    '    total = functools.reduce(lambda a, b: a + b, data["a"], 0)',
    '    tree = ast.parse("x = 1 + 2")',
    "    names = [node.__class__.__name__ for node in ast.walk(tree)]",
    "    path = pathlib.Path(os.getcwd())",
    "    machine = platform.machine()",
    '    table = dis.opmap.get("LOAD_CONST", -1)',
    "    exc_text = traceback.format_exc()",
    "    is_code = isinstance(heavy.__code__, types.CodeType)",
    '    print("stdlib:", total, len(counter), names[0], path.name, machine, table, len(exc_text), is_code)',
    "    return total + len(names)",
    "",
    "",
    'if __name__ == "__main__":',
    "    heavy()",
    "",
]


# ---------------------------------------------------------------------------
# 场景
# ---------------------------------------------------------------------------

def scenario0_isolation(work: Path) -> None:
    section("场景 0：隔离环境（sys.path 只有空 site-packages + 随包 python312.zip）")
    probe_path = work / "probe.py"
    write_file(probe_path, PROBE_SOURCE)
    command = [HOST_PYTHON, "-I", "-S", str(work / "launcher.py"),
               str(work / "site"), str(STDLIB_ZIP), str(probe_path)]
    proc = subprocess.run(command, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=120)
    output = proc.stdout
    probe_ok = "@@PROBE@@" in output and "@@END@@" in output
    if not check(probe_ok, "隔离探针正常输出",
                 "" if probe_ok else (output[-200:] if output else proc.stderr[-200:])):
        return
    info = json.loads(output.split("@@PROBE@@", 1)[1].split("@@END@@", 1)[0])
    paths = info.get("path", [])
    check(proc.returncode == 0, "隔离环境启动成功", "exit=%d" % proc.returncode)
    check(len(paths) == 2 and Path(paths[0]).exists() and paths[1] == str(STDLIB_ZIP),
          "sys.path == [空 site-packages, python312.zip]",
          " -> ".join(os.path.basename(p) for p in paths))
    host_lib = str(Path(HOST_PYTHON).resolve().parent / "Lib").lower()
    check(all(host_lib not in p.lower() for p in paths),
          "sys.path 里没有宿主标准库目录", host_lib)
    origin_detail = []
    all_zip_backed = True
    for name, (origin, module_file) in info.get("mods", {}).items():
        origin_detail.append("%s:%s" % (name, "zip" if "python312.zip" in origin else origin))
        if origin != "frozen" and "python312.zip" not in origin:
            all_zip_backed = False
    check(all_zip_backed, "脚本依赖的模块全部来自随包 zip（或解释器 frozen）",
          ", ".join(origin_detail))


def scenario1_cross_file(work: Path):
    section("场景 1：示例工程等价 fixture（跨文件覆盖精确、未走到的分支在 missing 里）")
    root = work / "fixture1"
    main_text = "\n".join(FIXTURE1_MAIN)
    utils_text = "\n".join(FIXTURE1_UTILS)
    write_file(root / "main.py", main_text)
    write_file(root / "utils.py", utils_text)
    report, proc, error = run_coverage(work, root, "main.py", "report1.json")
    if not check(report is not None and proc.returncode == 0,
                 "脚本正常退出并写出 JSON", error or ("exit=%d" % proc.returncode)):
        return None
    check(report.get("ok") is True, "ok=true", str(report.get("ok")))
    check(report.get("target") == "main.py", "target=main.py", str(report.get("target")))
    check(report.get("exit") == 0, "exit=0", str(report.get("exit")))
    stdout_lines = nonempty_lines(proc)
    check(summary_is_last(proc), "最后一行是覆盖率摘要（摘要前缀可区分）",
          stdout_lines[-1] if stdout_lines else "(空)")
    check("你好, 鸿蒙!" in proc.stdout, "目标 print 输出照常流到控制台（未被吞掉）")

    files = report.get("files", [])
    rels = [entry.get("path") for entry in files]
    check(rels == ["utils.py", "main.py"], "文件按 percent 升序：utils.py(66.7) -> main.py(93.8)",
          "files=" + str(rels))

    expected_main = executable_lines(root / "main.py")
    expected_utils = executable_lines(root / "utils.py")
    miss_line = line_index(main_text, "COVERAGE_MARK_MISS_BRANCH")
    early_line = line_index(utils_text, "COVERAGE_MARK_EARLY_RETURN")
    never_if = line_index(utils_text, "    if n > 0:")
    never_ret1 = line_index(utils_text, "        return 1")
    never_ret0 = line_index(utils_text, "    return 0")

    main_entry = get_entry(report, "main.py")
    utils_entry = get_entry(report, "utils.py")
    if not check(main_entry is not None and utils_entry is not None,
                 "main.py 与 utils.py 都被统计", "entries=" + str(rels)):
        return report

    for name, entry, expected in (
        ("main.py", main_entry, expected_main),
        ("utils.py", utils_entry, expected_utils),
    ):
        hit = set(entry.get("hit", []))
        missing = set(entry.get("missing", []))
        check(entry.get("total") == len(expected),
              "%s 可执行行数 total=%d（独立用 dis 复算）" % (name, len(expected)),
              "total=%d" % entry.get("total", -1))
        check(hit | missing == expected and not (hit & missing),
              "%s hit/missing 恰好划分可执行行" % name,
              "hit=%d missing=%d" % (len(hit), len(missing)))
        check(entry.get("covered") == len(hit),
              "%s covered == len(hit)" % name,
              "covered=%d" % entry.get("covered", -1))
        check(entry.get("percent") == round(entry.get("covered", 0) * 100.0 / entry.get("total", 1), 1),
              "%s percent == round(covered*100/total,1)" % name,
              "percent=%s" % entry.get("percent"))

    check(main_entry.get("missing") == [miss_line],
          "main.py 唯一未走到的分支在 missing 里（L%d return \"miss\"）" % miss_line,
          "missing=" + str(main_entry.get("missing")))
    expected_utils_missing = sorted([early_line, never_if, never_ret1, never_ret0])
    check(utils_entry.get("missing") == expected_utils_missing,
          "utils.fib 未走到的 early-return 与 never_called 整个函数都在 missing 里",
          "missing=" + str(utils_entry.get("missing")) + " expected=" + str(expected_utils_missing))
    append_line = line_index(utils_text, "seq.append(seq[-1] + seq[-2])")
    # 同一个 "return seq[:n]" 在 fib 里出现两次，取 early-return 之后的那次（真正执行的返回）
    fib_return = line_index(utils_text, "    return seq[:n]", early_line + 1)
    check(append_line in utils_entry.get("hit", []) and fib_return in utils_entry.get("hit", []),
          "跨文件：main.py 调 utils.fib(8) 后 utils 的循环/返回行被精确命中",
          "L%d/L%d in hit" % (append_line, fib_return))
    check(utils_entry.get("percent") == 66.7 and main_entry.get("percent") == 93.8,
          "关键数字符合 fixture 预期（utils 66.7%、main 93.8%）",
          "utils=%s main=%s" % (utils_entry.get("percent"), main_entry.get("percent")))
    return report


def scenario2_exception(work: Path) -> None:
    section("场景 2：目标抛异常（JSON 仍生成、ok=true、exit!=0、message 含类型与行号）")
    root = work / "fixture2"
    text = "\n".join(FIXTURE2)
    write_file(root / "main.py", text)
    raise_line = line_index(text, "COVERAGE_MARK_RAISE")
    report, proc, error = run_coverage(work, root, "main.py", "report2.json")
    if not check(report is not None and proc.returncode == 0,
                 "脚本不因目标异常而崩溃，JSON 已生成", error or ("exit=%d" % proc.returncode)):
        return
    check(report.get("ok") is True, "ok=true（报告已生成）", str(report.get("ok")))
    check(report.get("exit") != 0, "exit!=0", "exit=%s" % report.get("exit"))
    message = report.get("message", "")
    check("ValueError" in message, "message 含异常类型 ValueError", message)
    check("main.py:%d" % raise_line in message, "message 含异常行号 main.py:%d" % raise_line, message)
    entry = get_entry(report, "main.py")
    check(entry is not None and raise_line in entry.get("hit", []),
          "抛出异常的那一行仍算命中（trace 的 line 事件先于异常）",
          "L%d in hit" % raise_line)
    check(summary_is_last(proc), "stdout 以覆盖率摘要结尾",
          nonempty_lines(proc)[-1] if nonempty_lines(proc) else "(空)")
    check("Traceback" not in proc.stdout and "Traceback" not in proc.stderr,
          "异常栈没有漏到 stdout/stderr")


def scenario3_sys_exit(work: Path) -> None:
    section("场景 3：目标 sys.exit(3)（exit=3、JSON 正常、不崩）")
    root = work / "fixture3"
    write_file(root / "main.py", "\n".join(FIXTURE3))
    report, proc, error = run_coverage(work, root, "main.py", "report3.json")
    if not check(report is not None and proc.returncode == 0,
                 "脚本正常退出并写出 JSON", error or ("exit=%d" % proc.returncode)):
        return
    check(report.get("ok") is True, "ok=true", str(report.get("ok")))
    check(report.get("exit") == 3, "exit=3（SystemExit 被捕获，没有冒泡）",
          "exit=%s" % report.get("exit"))
    entry = get_entry(report, "main.py")
    check(entry is not None, "目标文件出现在报告里", "files=" + str([e.get("path") for e in report.get("files", [])]))
    check(entry is not None and entry.get("covered") == entry.get("total"),
          "sys.exit 之前的行全部命中", "covered=%s total=%s" % (
              entry.get("covered") if entry else "?", entry.get("total") if entry else "?"))
    check("hello" in proc.stdout, '目标 print("hello") 出现在运行输出里（输出未被吞掉）')
    check(summary_is_last(proc), "stdout 以覆盖率摘要结尾",
          nonempty_lines(proc)[-1] if nonempty_lines(proc) else "(空)")
    check(not report.get("message"), "message 为空（正常退出语义）", report.get("message", ""))


def scenario4_stdlib_not_counted(work: Path) -> None:
    section("场景 4：目标大量执行标准库代码（标准库行绝不能进报告）")
    root = work / "fixture4"
    write_file(root / "main.py", "\n".join(FIXTURE4))
    report, proc, error = run_coverage(work, root, "main.py", "report4.json")
    if not check(report is not None and proc.returncode == 0,
                 "标准库导入在隔离环境里全部成功，脚本正常退出",
                 error or ("exit=%d" % proc.returncode)):
        return
    check(report.get("ok") is True and report.get("exit") == 0,
          "目标正常结束", "ok=%s exit=%s" % (report.get("ok"), report.get("exit")))
    files = report.get("files", [])
    rels = [entry.get("path") for entry in files]
    check(rels == ["main.py"], "报告里只有工程内文件 main.py", "files=" + str(rels))
    bad = []
    for entry in files:
        rel = entry.get("path", "")
        lowered = rel.lower()
        if (os.path.isabs(rel) or ":" in rel or "python312.zip" in lowered
                or "/lib/" in lowered or "\\lib\\" in lowered or "site-packages" in lowered):
            bad.append(rel)
    check(not bad, "没有任何标准库/第三方库路径", "bad=" + str(bad))
    entry = files[0] if files else {}
    check(entry.get("covered") == entry.get("total") and entry.get("missing") == [],
          "main.py 全部可执行行命中（标准库调用不影响工程行统计）",
          "covered=%s/%s" % (entry.get("covered"), entry.get("total")))
    check("stdlib:" in proc.stdout, "目标 print 的输出照常出现在运行输出里")
    check(summary_is_last(proc), "stdout 以覆盖率摘要结尾",
          nonempty_lines(proc)[-1] if nonempty_lines(proc) else "(空)")


def scenario5_missing_target(work: Path) -> None:
    section("场景 5：目标不存在 / target='-'（ok=false + message 说明，不抛未捕获异常）")
    root_missing = work / "fixture5a"
    root_missing.mkdir(parents=True, exist_ok=True)
    report, proc, error = run_coverage(work, root_missing, "not_here.py", "report5a.json")
    if check(report is not None and proc.returncode == 0,
             "目标不存在：脚本正常退出且写出 JSON", error or ("exit=%d" % proc.returncode)):
        check(report.get("ok") is False, "ok=false", str(report.get("ok")))
        check(report.get("files") == [], "files=[]", str(report.get("files")))
        check(bool(report.get("message")) and "不存在" in report.get("message", ""),
              "message 说明目标不存在", report.get("message", ""))
        check("Traceback" not in proc.stderr, "没有未捕获异常栈")
        check(summary_is_last(proc), "失败场景仍打印一行覆盖率摘要（未生成）")
    root_dash = work / "fixture5b"
    root_dash.mkdir(parents=True, exist_ok=True)
    report2, proc2, error2 = run_coverage(work, root_dash, "-", "report5b.json")
    if check(report2 is not None and proc2.returncode == 0,
             "target='-'：脚本正常退出且写出 JSON", error2 or ("exit=%d" % proc2.returncode)):
        check(report2.get("ok") is False, "ok=false", str(report2.get("ok")))
        check(report2.get("target") == "", "target 为空串", repr(report2.get("target")))
        check(bool(report2.get("message")) and "未指定" in report2.get("message", ""),
              "message 说明没有目标", report2.get("message", ""))
        check("Traceback" not in proc2.stderr, "没有未捕获异常栈")
        check(summary_is_last(proc2), "失败场景仍打印一行覆盖率摘要（未生成）")


def scenario6_schema(work: Path, report) -> None:
    section("场景 6：报告 schema 校验（字段/类型/排序/percent 公式/文件排序/400 截断）")
    if not check(report is not None, "拿到场景 1 的报告用于校验"):
        return
    for key, expected in (("ok", bool), ("target", str), ("exit", int),
                          ("message", str), ("files", list)):
        value = report.get(key, "<<missing>>")
        check(isinstance(value, expected) and not (expected is int and isinstance(value, bool)),
              "顶层字段 %s 类型为 %s" % (key, expected.__name__),
              type(value).__name__)
    check(report.get("target") == "main.py", "target 为相对路径 main.py", str(report.get("target")))
    files = report.get("files", [])
    check(isinstance(files, list) and len(files) == 2, "files 为 2 项的数组", "len=%d" % len(files))
    keys = [("path", str), ("total", int), ("covered", int),
            ("percent", (int, float)), ("hit", list), ("missing", list)]
    schema_ok = True
    for entry in files:
        for key, expected in keys:
            value = entry.get(key, "<<missing>>")
            if not isinstance(value, expected) or (key in ("total", "covered") and isinstance(value, bool)):
                schema_ok = False
                print("        字段类型错误: %s=%r (%s)" % (key, value, type(value).__name__))
    check(schema_ok, "每个文件条目字段齐全且类型正确", "keys=" + str([k for k, _ in keys]))
    sorted_ok = True
    math_ok = True
    line_ok = True
    for entry in files:
        total = entry.get("total", 0)
        covered = entry.get("covered", 0)
        percent = entry.get("percent", 0)
        hit = entry.get("hit", [])
        missing = entry.get("missing", [])
        if not (isinstance(total, int) and isinstance(covered, int) and 0 <= covered <= total):
            sorted_ok = False
        if total > 0 and percent != round(covered * 100.0 / total, 1):
            math_ok = False
        if not isinstance(percent, (int, float)) or not (0 <= percent <= 100):
            math_ok = False
        if (not isinstance(hit, list) or not isinstance(missing, list)
                or not all(isinstance(v, int) and not isinstance(v, bool) and v > 0 for v in hit + missing)):
            line_ok = False
            continue
        if hit != sorted(set(hit)) or missing != sorted(set(missing)):
            line_ok = False
        if len(set(hit) | set(missing)) != total or set(hit) & set(missing):
            line_ok = False
    check(sorted_ok, "0 <= covered <= total")
    check(math_ok, "percent == round(covered*100/total,1) 且 0..100")
    check(line_ok, "hit/missing 升序去重、互斥且 len(hit)+len(missing)==total")
    order = [(entry.get("percent"), entry.get("path")) for entry in files]
    check(order == sorted(order), "files 按 (percent, path) 升序", str(order))
    check(len(files) <= 400, "文件数不超过 400", "len=%d" % len(files))

    # 400 个上限与截断说明
    root = work / "fixture_trunc"
    write_file(root / "main.py", "value = 1\n")
    for index in range(404):
        write_file(root / ("mod_%03d.py" % index), "value = %d\n" % index)
    report2, proc2, error2 = run_coverage(work, root, "main.py", "report_trunc.json")
    if not check(report2 is not None and proc2.returncode == 0,
                 "405 个文件时脚本正常退出", error2 or ("exit=%d" % proc2.returncode)):
        return
    files2 = report2.get("files", [])
    check(len(files2) == 400, "超过 400 个文件时报告截断为 400 个", "len=%d" % len(files2))
    check("截断" in report2.get("message", "") and "405" in report2.get("message", ""),
          "message 注明截断（405 -> 400）", report2.get("message", ""))
    order2 = [(entry.get("percent"), entry.get("path")) for entry in files2]
    check(order2 == sorted(order2), "截断后的 files 仍满足排序契约")


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def main() -> int:
    global HOST_PYTHON
    setup_stdout()
    parser = argparse.ArgumentParser(description="CoverageService 宿主验证")
    parser.add_argument("--host-python", default=DEFAULT_HOST_PYTHON,
                        help="宿主 Python 3.12 的完整路径（必须与设备同为 3.12）")
    args = parser.parse_args()
    HOST_PYTHON = os.path.abspath(args.host_python)

    print("CoverageService 宿主验证")
    print("工程根    : " + str(REPO_ROOT))
    print("ETS       : " + str(ETS_FILE))
    print("标准库 zip: " + str(STDLIB_ZIP))
    print("宿主 Python: " + HOST_PYTHON)

    if not check(Path(HOST_PYTHON).is_file(), "宿主 Python 存在"):
        print("\nRESULT: FAIL")
        return 2
    version = subprocess.run([HOST_PYTHON, "-c", "import sys; print(sys.version.split()[0])"],
                             capture_output=True, text=True, encoding="utf-8",
                             errors="replace").stdout.strip()
    if not check(version.startswith("3.12"), "宿主 Python 版本与设备一致（3.12.x）", version):
        print("\nRESULT: FAIL")
        return 2
    if not check(STDLIB_ZIP.is_file(), "随包标准库 zip 存在"):
        print("\nRESULT: FAIL")
        return 2
    if not check(ETS_FILE.is_file(), "CoverageService.ets 存在"):
        print("\nRESULT: FAIL")
        return 2

    script, begin_seen, end_seen, ignored = extract_coverage_script(ETS_FILE)
    section("脚本抽取（#coverage-py-begin..#coverage-py-end）")
    check(begin_seen and end_seen, "两个标记行都在")
    check(not ignored, "标记行之间没有无法识别的非字符串行", str(ignored[:3]))
    check(len(script) > 3000 and script.count("\n") > 100,
          "抽出的脚本非空", "%d 字符 / %d 行" % (len(script), script.count("\n")))
    try:
        compile(script, "coverage_run.py", "exec")
        check(True, "抽出的脚本能被 Python 编译（转义还原正确）")
    except SyntaxError as exc:
        check(False, "抽出的脚本能被 Python 编译", "%s: %s" % (type(exc).__name__, exc))
    check("sys.settrace(_trace)" in script and "dis.findlinestarts" in script,
          "脚本包含核心实现（settrace / findlinestarts）")

    work = Path(tempfile.mkdtemp(prefix="pyide-covverify-"))
    write_file(work / "launcher.py", LAUNCHER_SOURCE)
    write_file(work / "coverage_run.py", script)
    (work / "site").mkdir(parents=True, exist_ok=True)

    scenario0_isolation(work)
    report1 = scenario1_cross_file(work)
    scenario2_exception(work)
    scenario3_sys_exit(work)
    scenario4_stdlib_not_counted(work)
    scenario5_missing_target(work)
    scenario6_schema(work, report1)

    print("\n工作目录（fixture 与报告留在这里便于复查）: " + str(work))
    print("共 %d 项检查，失败 %d 项" % (CHECK_TOTAL, CHECK_FAILED))
    print("")
    if CHECK_FAILED == 0:
        print("RESULT: PASS")
        return 0
    print("RESULT: FAIL")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
