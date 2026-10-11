/**
 * libpythonbridge.so —— 鸿蒙 Python IDE 的内嵌 CPython 运行时桥接。
 *
 * 设计要点
 * ─────────
 * 1. CPython 以**静态库**形式链接进本 .so（-Wl,--whole-archive），因此运行在应用进程内，
 *    与应用沙箱是同一个文件系统命名空间，Python 的 open() 与 ArkTS 的 @ohos.file.fs
 *    看到的是完全相同的路径。
 * 2. 线程模型：解释器在「初始化线程」上建立后立刻 `PyEval_SaveThread()` 交出 GIL；
 *    之后所有 Python 执行都跑在 NAPI 异步工作线程上，用 `PyGILState_Ensure/Release` 取放 GIL，
 *    并额外用一把互斥锁保证同一时刻只有一段脚本在跑（解释器状态是全局的）。
 *    UI 线程永远不会被 Python 阻塞。
 * 3. 输出回传：Python 侧 sys.stdout/sys.stderr 被替换成调用内建扩展模块 `_pyide_bridge`
 *    的 writer；该模块的 emit() 把文本推入线程安全函数（napi_threadsafe_function），
 *    在 JS 线程上回调 ArkTS —— 因此 print 是**实时**出现在控制台里的。
 * 4. 未链接 libpython 时（尚未执行 scripts/build-cpython-ohos.ps1）本模块依然可以正常加载，
 *    所有接口返回明确的“运行时未就绪”错误，保证工程随时可编译、可安装、可提示用户。
 */

#include <napi/native_api.h>
#include <hilog/log.h>

// 终端 PTY + 目录监听（inotify）：见 pty_watch.cpp
#include "pty_watch.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

#ifdef PY_RUNTIME_AVAILABLE
#include <Python.h>
#else
// 未链接 libpython 时也要让源码保持可编译：这两个常量取自 CPython 的 compile.h，
// 仅用于填参数，ExecuteSource 会直接返回“运行时未就绪”而不会真的执行。
#define Py_single_input 256
#define Py_file_input 257
#endif

#define PYIDE_LOG_DOMAIN 0x3200
#define PYIDE_LOG_TAG "PyBridge"

#define PYIDE_LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, PYIDE_LOG_DOMAIN, PYIDE_LOG_TAG, __VA_ARGS__)
#define PYIDE_LOGW(...) OH_LOG_Print(LOG_APP, LOG_WARN, PYIDE_LOG_DOMAIN, PYIDE_LOG_TAG, __VA_ARGS__)
#define PYIDE_LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, PYIDE_LOG_DOMAIN, PYIDE_LOG_TAG, __VA_ARGS__)

// ─────────────────────────────────────────────────────────────────────────────
// 全局状态
// ─────────────────────────────────────────────────────────────────────────────

static std::mutex g_tsfnMutex;
static napi_threadsafe_function g_tsfn = nullptr;

static std::mutex g_pyMutex;                 // 串行化 Python 执行
static std::atomic<bool> g_initialized{false};
static std::atomic<bool> g_finalized{false};
static std::atomic<bool> g_running{false};

static std::string g_version;                // sys.version 首行
static std::string g_runStdout;              // 当前这次运行的累积输出
static std::string g_runStderr;
static std::atomic<int> g_lastExitCode{0};   // 最近一次运行的退出码（SystemExit 会被解析）

static const char* kAbi =
#if defined(__aarch64__)
    "arm64-v8a";
#elif defined(__x86_64__)
    "x86_64";
#elif defined(__arm__)
    "armeabi-v7a";
#else
    "unknown";
#endif

static const std::string kBuildTime = std::string(__DATE__) + " " + std::string(__TIME__);

// ─────────────────────────────────────────────────────────────────────────────
// 输出回流：Worker 线程 → JS 线程
// ─────────────────────────────────────────────────────────────────────────────

struct StreamMessage {
  int stream;      // 0 = stdout, 1 = stderr
  std::string text;
};

static void CallJsOutput(napi_env env, napi_value jsCallback, void* /*context*/, void* data)
{
  StreamMessage* msg = static_cast<StreamMessage*>(data);
  if (msg == nullptr) {
    return;
  }
  if (env != nullptr && jsCallback != nullptr) {
    napi_value argv[2] = {nullptr, nullptr};
    napi_create_int32(env, msg->stream, &argv[0]);
    napi_create_string_utf8(env, msg->text.c_str(), msg->text.size(), &argv[1]);
    napi_value global = nullptr;
    napi_get_global(env, &global);
    napi_value result = nullptr;
    napi_status status = napi_call_function(env, global, jsCallback, 2, argv, &result);
    if (status != napi_ok) {
      PYIDE_LOGW("call output callback failed: %{public}d", status);
    }
  }
  delete msg;
}

/** 任意线程调用：把 Python 的输出片段投递给 ArkTS 回调 */
static void EmitStream(int stream, const std::string& text)
{
  if (text.empty()) {
    return;
  }
  if (g_running.load()) {
    // 只累积真正的程序输出；stream 2 是调试事件，不能混进 stdout/stderr
    if (stream == 0) {
      g_runStdout += text;
    } else if (stream == 1) {
      g_runStderr += text;
    }
  }
  napi_threadsafe_function tsfn = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_tsfnMutex);
    tsfn = g_tsfn;
  }
  if (tsfn == nullptr) {
    return;
  }
  StreamMessage* msg = new StreamMessage();
  msg->stream = stream;
  msg->text = text;
  napi_status status = napi_call_threadsafe_function(tsfn, msg, napi_tsfn_nonblocking);
  if (status != napi_ok) {
    // 队列不可用时必须自行回收，否则泄漏
    delete msg;
  }
}

#ifdef PY_RUNTIME_AVAILABLE
// ─────────────────────────────────────────────────────────────────────────────
// 内建扩展模块 _pyide_bridge（Python 侧输出通道）
// ─────────────────────────────────────────────────────────────────────────────

static PyObject* BridgeEmit(PyObject* /*self*/, PyObject* args)
{
  int stream = 0;
  const char* text = nullptr;
  if (!PyArg_ParseTuple(args, "is", &stream, &text)) {
    return nullptr;
  }
  EmitStream(stream, std::string(text == nullptr ? "" : text));
  Py_RETURN_NONE;
}

// ─────────────────────────────────────────────────────────────────────────────
// 调试支持：行级断点 + 单步 + 变量/调用栈快照
//
// 机制：把下面这段 Python 钩子注入 __main__，用 sys.settrace 在行事件上判断是否命中
// 断点；命中就调用内建模块的 pause()，由 C++ 侧把快照（stream=2）推给 ArkTS，
// 然后在条件变量上**阻塞**，直到 UI 下发 debugCommand（continue/step/stop）。
//
// 为什么用 sys.settrace 而不是 sys.monitoring：settrace 在 3.12 上语义稳定、写起来短，
// 而调试场景本来就不追求性能；只在用户工程目录内的帧上返回局部 trace 函数，标准库不跟。
// ─────────────────────────────────────────────────────────────────────────────

static std::mutex g_debugMutex;
static std::condition_variable g_debugCv;
static std::string g_debugCommand;
static std::atomic<bool> g_debugPaused{false};
static std::atomic<bool> g_debugAbort{false};

static const char* kDebugHookScript = R"PYDEBUG(
import json as _pyide_json
import sys as _pyide_sys

_pyide_bridge = __import__('_pyide_bridge')
_pyide_breakpoints = {}
_pyide_roots = []
_pyide_step = 'continue'
_pyide_enabled = False
_pyide_pauses = 0
_pyide_seen = 0
_pyide_step_depth = -1
_pyide_verbose = False


def _pyide_configure(breakpoints_json, roots_json):
    """breakpoints_json: {"<绝对路径>": [行号, ...]}；roots_json: [工程根目录, ...]"""
    global _pyide_breakpoints, _pyide_roots
    try:
        raw = _pyide_json.loads(breakpoints_json) if breakpoints_json else {}
    except Exception:
        raw = {}
    table = {}
    for path, lines in (raw or {}).items():
        try:
            table[str(path)] = set(int(x) for x in lines)
        except Exception:
            continue
    _pyide_breakpoints = table
    try:
        parsed = _pyide_json.loads(roots_json) if roots_json else []
        _pyide_roots = [str(r) for r in parsed]
    except Exception:
        _pyide_roots = []
    if _pyide_verbose:
        print('[dbg] configure breakpoints=%r roots=%r' % (_pyide_breakpoints, _pyide_roots))


def _pyide_in_scope(filename):
    """只在用户工程目录内跟踪：既避免在标准库内部单步，也大幅降低开销。

    注意必须按"目录 + /"比较：早期用裸 startswith 时，<filesDir>/python 会把
    <filesDir>/python312.zip/platform.py 也判成在作用域内（字符串前缀相同）。
    """
    for root in _pyide_roots:
        if root and (filename == root or filename.startswith(root + '/')):
            return True
    return filename in _pyide_breakpoints


def _pyide_snapshot(frame):
    locals_out = []
    try:
        items = list(frame.f_locals.items())
    except Exception:
        items = []
    for name, value in items[:200]:
        try:
            text = repr(value)
        except Exception:
            text = '<repr failed>'
        locals_out.append([name, text[:400]])
    stack = []
    walker = frame
    while walker is not None and len(stack) < 32:
        code = walker.f_code
        stack.append([code.co_filename, walker.f_lineno, code.co_name])
        walker = walker.f_back
    return locals_out, stack


def _pyide_trace(frame, event, arg):
    global _pyide_step, _pyide_enabled, _pyide_pauses, _pyide_seen, _pyide_step_depth
    if not _pyide_enabled:
        return None
    if event == 'call':
        return _pyide_trace if _pyide_in_scope(frame.f_code.co_filename) else None
    if event != 'line':
        return _pyide_trace
    filename = frame.f_code.co_filename
    lineno = frame.f_lineno

    # 帧深度（0 = 最外层），用于实现「单步跳过」：只在本帧或更外层停
    depth = 0
    probe = frame
    while probe.f_back is not None:
        depth += 1
        probe = probe.f_back

    lines = _pyide_breakpoints.get(filename)
    on_breakpoint = bool(lines) and lineno in lines
    stepping = _pyide_step == 'step'
    if stepping and _pyide_step_depth >= 0 and depth > _pyide_step_depth and not on_breakpoint:
        return _pyide_trace
    if not stepping and not on_breakpoint:
        return _pyide_trace

    if _pyide_verbose and _pyide_seen < 25:
        _pyide_seen += 1
        print('[dbg] hit %s:%d depth=%d stepping=%s bp=%s at %r'
              % (filename, lineno, depth, stepping, on_breakpoint, arg))

    try:
        locals_out, stack = _pyide_snapshot(frame)
        payload = _pyide_json.dumps({
            'file': filename,
            'line': lineno,
            'func': frame.f_code.co_name,
            'locals': locals_out,
            'stack': stack,
        })
        _pyide_pauses += 1
        command = _pyide_bridge.pause('step' if stepping else 'breakpoint', payload)
    except Exception:
        # 钩子自身出错绝不能拖垮用户程序：直接卸载 trace
        _pyide_enabled = False
        _pyide_sys.settrace(None)
        return None
    # PyCharm Evaluate：UI 发 eval:<表达式> 时，在**当前暂停帧**里求值，把结果并入新的暂停事件，然后继续阻塞
    while command.startswith('eval:'):
        _pyide_expr = command[5:]
        try:
            _pyide_value = repr(eval(_pyide_expr, frame.f_globals, frame.f_locals))
        except Exception as _pyide_eval_err:
            _pyide_value = '<错误: %s>' % _pyide_eval_err
        _pyide_eval_payload = _pyide_json.dumps({
            'file': filename,
            'line': lineno,
            'func': frame.f_code.co_name,
            'locals': locals_out,
            'stack': stack,
            'evalExpr': _pyide_expr,
            'evalResult': _pyide_value,
        })
        command = _pyide_bridge.pause('eval', _pyide_eval_payload)
    if command == 'stop':
        _pyide_enabled = False
        _pyide_sys.settrace(None)
        raise SystemExit(130)
    if command in ('step', 'stepinto', 'stepout'):
        _pyide_step = 'step'
        if command == 'step':
            # 单步跳过：本帧或更外层才停
            _pyide_step_depth = len(stack) - 1
        elif command == 'stepout':
            # 步出：只在返回上一层（更外层）时停
            _pyide_step_depth = len(stack) - 2
        else:
            # 步入：不限深度
            _pyide_step_depth = -1
    else:
        _pyide_step = 'continue'
        _pyide_step_depth = -1
    return _pyide_trace


def _pyide_install():
    global _pyide_enabled, _pyide_step
    _pyide_enabled = True
    _pyide_step = 'continue'
    _pyide_sys.settrace(_pyide_trace)
    if _pyide_verbose:
        print('[dbg] install enabled=%s trace=%r' % (_pyide_enabled, _pyide_sys.gettrace()))


def _pyide_uninstall():
    global _pyide_enabled
    _pyide_enabled = False
    _pyide_sys.settrace(None)
)PYDEBUG";

/** Python 字符串字面量（用于把 JSON 安全地注入脚本） */
static std::string PyStrLiteral(const std::string& value)
{
  std::string out = "'";
  for (char c : value) {
    switch (c) {
      case '\\':
        out += "\\\\";
        break;
      case '\'':
        out += "\\'";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\r':
        out += "\\r";
        break;
      default:
        out += c;
        break;
    }
  }
  out += "'";
  return out;
}

/**
 * 内建扩展模块 _pyide_bridge.pause(kind, payload_json) -> 'continue'|'step'|'stop'
 *
 * 把调试快照以 stream=2 推给 ArkTS，然后阻塞等待 UI 指令。
 * 超时（10 分钟）按 stop 处理：宁可结束会话，也不要让解释器永久挂住。
 */
static PyObject* BridgePause(PyObject* /*self*/, PyObject* args)
{
  const char* kind = nullptr;
  const char* payload = nullptr;
  if (!PyArg_ParseTuple(args, "ss", &kind, &payload)) {
    return nullptr;
  }
  EmitStream(2, std::string(payload == nullptr ? "" : payload));

  std::string command;
  {
    std::unique_lock<std::mutex> lock(g_debugMutex);
    g_debugCommand.clear();
    g_debugAbort.store(false);
    g_debugPaused.store(true);
    g_debugCv.wait_for(lock, std::chrono::minutes(10), [] {
      return !g_debugCommand.empty() || g_debugAbort.load();
    });
    g_debugPaused.store(false);
    command = g_debugAbort.load() ? std::string("stop") : g_debugCommand;
    if (command.empty()) {
      command = "stop";
    }
  }
  PYIDE_LOGI("debug pause released with command=%{public}s", command.c_str());
  return PyUnicode_FromString(command.c_str());
}

static PyMethodDef BridgeMethods[] = {
    {"emit", BridgeEmit, METH_VARARGS, "emit(stream, text) -> None"},
    {"pause", BridgePause, METH_VARARGS, "pause(kind, payload_json) -> command"},
    {nullptr, nullptr, 0, nullptr},
};

static struct PyModuleDef BridgeModuleDef = {
    PyModuleDef_HEAD_INIT,
    "_pyide_bridge",
    "鸿蒙 Python IDE 输出桥（内建扩展）",
    -1,
    BridgeMethods,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
};

static PyObject* PyInit__pyide_bridge(void)
{
  return PyModule_Create(&BridgeModuleDef);
}

/**
 * 首次启动时把随包的 wheel（pip）解压进 site-packages。
 *
 * 为什么不直接在标准库 zip 里用 ensurepip：ensurepip 需要读自己 `_bundled/` 下的
 * **真实文件**，zipimport 下 `__file__` 不是可用路径，必然失败。所以把 wheel 解压成
 * 真实文件，pip 才真正可用；顺带也支持用户把任意 wheel 丢进 <home>/wheels 离线安装。
 * %WHEELS% / %SITE% 由 C++ 侧替换为运行时真实路径，脚本里没有其它 % 占位符。
 */
static const char* kInstallBundledWheelsScriptTemplate = R"PY(
import os
import sys
import zipfile


def _install_wheels(wheel_dir, site_dir):
    if not (os.path.isdir(wheel_dir) and os.path.isdir(site_dir)):
        return
    installed = []
    for name in sorted(os.listdir(wheel_dir)):
        if not name.endswith('.whl'):
            continue
        marker = os.path.join(site_dir, '.' + name + '.installed')
        if os.path.exists(marker):
            continue
        try:
            with zipfile.ZipFile(os.path.join(wheel_dir, name)) as zf:
                zf.extractall(site_dir)
            with open(marker, 'w') as fp:
                fp.write('ok')
            installed.append(name)
        except Exception as exc:
            sys.stderr.write('解压 wheel 失败 %s: %s\n' % (name, exc))
    if installed:
        sys.stdout.write('已安装随包 wheel: %s\n' % ', '.join(installed))


_install_wheels(r"%WHEELS%", r"%SITE%")
)PY";

/** 安装 stdout/stderr 重定向 + 关闭交互式提示符。
 * 必须在解释器初始化完成后执行一次。
 */
static const char* kInstallWriterScript = R"PY(
import sys

class _PyIdeWriter:
    """把写入内容实时推给宿主 IDE 的 stdout/stderr 替身。"""
    __slots__ = ('_stream',)

    def __init__(self, stream):
        self._stream = stream

    def write(self, text):
        if text:
            import _pyide_bridge
            _pyide_bridge.emit(self._stream, text if isinstance(text, str) else str(text))
        return len(text) if text else 0

    def writelines(self, lines):
        for line in lines:
            self.write(line)

    def flush(self):
        pass

    def isatty(self):
        return False

    def fileno(self):
        raise OSError('IDE 输出通道没有真实文件描述符')

    @property
    def encoding(self):
        return 'utf-8'

    @property
    def errors(self):
        return 'replace'


sys.stdout = _PyIdeWriter(0)
sys.stderr = _PyIdeWriter(1)
sys.stdin = None
del _PyIdeWriter
)PY";

/** 把当前线程的 Python 异常转成文本；同时解析 SystemExit 的退出码 */
static void ReportException(std::string& errOut, int& exitCode)
{
  PyObject* type = nullptr;
  PyObject* value = nullptr;
  PyObject* tb = nullptr;
  PyErr_Fetch(&type, &value, &tb);
  if (type == nullptr) {
    return;
  }
  PyErr_NormalizeException(&type, &value, &tb);

  if (PyErr_GivenExceptionMatches(type, PyExc_SystemExit)) {
    long code = 0;
    PyObject* codeObj = (value != nullptr) ? PyObject_GetAttrString(value, "code") : nullptr;
    if (codeObj != nullptr) {
      if (codeObj == Py_None) {
        code = 0;
      } else if (PyLong_Check(codeObj)) {
        code = PyLong_AsLong(codeObj);
      } else {
        PyObject* text = PyObject_Str(codeObj);
        if (text != nullptr) {
          const char* s = PyUnicode_AsUTF8(text);
          if (s != nullptr) {
            errOut += s;
            errOut += "\n";
          }
          Py_DECREF(text);
        }
        code = 1;
      }
      Py_DECREF(codeObj);
    }
    exitCode = static_cast<int>(code);
    Py_XDECREF(type);
    Py_XDECREF(value);
    Py_XDECREF(tb);
    return;
  }

  exitCode = 1;
  PyObject* tbModule = PyImport_ImportModule("traceback");
  if (tbModule != nullptr) {
    PyObject* formatFn = PyObject_GetAttrString(tbModule, "format_exception");
    if (formatFn != nullptr) {
      PyObject* list = PyObject_CallFunctionObjArgs(formatFn, type, value,
                                                    (tb != nullptr ? tb : Py_None), nullptr);
      if (list != nullptr) {
        PyObject* empty = PyUnicode_FromString("");
        PyObject* joined = (empty != nullptr) ? PyUnicode_Join(empty, list) : nullptr;
        if (joined != nullptr) {
          const char* s = PyUnicode_AsUTF8(joined);
          if (s != nullptr) {
            errOut += s;
          }
          Py_DECREF(joined);
        }
        Py_XDECREF(empty);
        Py_DECREF(list);
      }
      Py_DECREF(formatFn);
    }
    Py_DECREF(tbModule);
  } else {
    PyErr_Clear();
    errOut += "发生异常，但无法导入 traceback 模块格式化堆栈。\n";
  }
  Py_XDECREF(type);
  Py_XDECREF(value);
  Py_XDECREF(tb);
}
#endif  // PY_RUNTIME_AVAILABLE

// ─────────────────────────────────────────────────────────────────────────────
// 解释器生命周期
// ─────────────────────────────────────────────────────────────────────────────

struct InitOptions {
  std::string filesDir;
  std::string stdlibZip;
  std::string sitePackages;
  std::string home;
  std::vector<std::string> argv;
  std::vector<std::string> extraPaths;
};

static bool EnsureInterpreter(const InitOptions& options, std::string& error)
{
#ifndef PY_RUNTIME_AVAILABLE
  (void)options;
  error = "本次构建未链接 CPython 静态库（libpython3.12.a）。"
          "请先执行 scripts/build-cpython-ohos.ps1 交叉编译原生运行时，再重新构建应用。";
  return false;
#else
  if (g_initialized.load()) {
    return true;
  }
  if (g_finalized.load()) {
    error = "解释器已经 finalize，无法再次初始化。请重启应用。";
    return false;
  }

  PyImport_AppendInittab("_pyide_bridge", PyInit__pyide_bridge);

  PyConfig config;
  PyConfig_InitPythonConfig(&config);
  config.parse_argv = 0;
  config.install_signal_handlers = 0;  // 初始化可能发生在工作线程上，不接管进程信号
  config.use_environment = 0;          // 不读取宿主环境变量，路径完全由 IDE 决定
  config.write_bytecode = 0;           // 沙箱内不生成 __pycache__，保持项目目录干净
  config.user_site_directory = 0;
  config.site_import = 1;              // 保留 site 以支持 .pth 与 site-packages

  PyStatus status = PyConfig_SetBytesString(&config, &config.home, options.home.c_str());
  if (PyStatus_Exception(status)) {
    PyConfig_Clear(&config);
    error = "配置 PYTHONHOME 失败";
    return false;
  }
  std::string programName = options.home + "/python";
  status = PyConfig_SetBytesString(&config, &config.program_name, programName.c_str());
  if (PyStatus_Exception(status)) {
    PyConfig_Clear(&config);
    error = "配置 program_name 失败";
    return false;
  }

  // 搜索路径顺序：用户 site-packages → 标准库 zip → 额外路径（项目根）
  config.module_search_paths_set = 1;
  auto appendPath = [&config](const std::string& path) -> bool {
    wchar_t* wide = Py_DecodeLocale(path.c_str(), nullptr);
    if (wide == nullptr) {
      return false;
    }
    PyStatus st = PyWideStringList_Append(&config.module_search_paths, wide);
    PyMem_RawFree(wide);
    return !PyStatus_Exception(st);
  };
  if (!options.sitePackages.empty()) {
    appendPath(options.sitePackages);
  }
  if (!options.stdlibZip.empty()) {
    appendPath(options.stdlibZip);
  }
  for (const std::string& extra : options.extraPaths) {
    appendPath(extra);
  }

  // sys.argv
  if (!options.argv.empty()) {
    config.argv.length = 0;
    for (const std::string& arg : options.argv) {
      wchar_t* wide = Py_DecodeLocale(arg.c_str(), nullptr);
      if (wide != nullptr) {
        PyWideStringList_Append(&config.argv, wide);
        PyMem_RawFree(wide);
      }
    }
  }

  status = Py_InitializeFromConfig(&config);
  PyConfig_Clear(&config);
  if (PyStatus_Exception(status)) {
    std::string detail = (status.err_msg != nullptr) ? status.err_msg : "unknown";
    error = "Py_InitializeFromConfig 失败: " + detail;
    return false;
  }

  // 记录版本
  const char* version = Py_GetVersion();
  g_version = std::string(version == nullptr ? "unknown" : version);
  const size_t newline = g_version.find('\n');
  if (newline != std::string::npos) {
    g_version = g_version.substr(0, newline);
  }

  // 装好输出通道
  PyObject* mainModule = PyImport_AddModule("__main__");
  PyObject* globals = (mainModule != nullptr) ? PyModule_GetDict(mainModule) : nullptr;
  if (globals != nullptr) {
    PyObject* result = PyRun_StringFlags(kInstallWriterScript, Py_file_input, globals, globals, nullptr);
  Py_XDECREF(result);

  // sys.platform 由构建时的 host triplet 决定；我们绕过了 configure，实测它是 'unknown'。
  // 改为 'ohos'：既符合事实，也让 platform / urllib 之类的分支判断走在正确路径上。
  const char* kPlatformFixScript =
      "import sys\n"
      "if getattr(sys, 'platform', 'unknown') in ('', 'unknown'):\n"
      "    sys.platform = 'ohos'\n";
  PyObject* platformFix = PyRun_StringFlags(kPlatformFixScript, Py_file_input, globals, globals, nullptr);
  Py_XDECREF(platformFix);
    if (result == nullptr) {
      std::string ignored;
      int code = 0;
      ReportException(ignored, code);
      PYIDE_LOGW("install writer failed: %{public}s", ignored.c_str());
      EmitStream(1, ignored);
    } else {
      Py_DECREF(result);
    }
  }

  // 装好随包 wheel（pip）——必须在交出 GIL 之前、且在同一个 __main__ 命名空间里跑
  if (globals != nullptr) {
    auto replaceAll = [](std::string& text, const std::string& from, const std::string& to) {
      if (from.empty()) {
        return;
      }
      size_t pos = 0;
      while ((pos = text.find(from, pos)) != std::string::npos) {
        text.replace(pos, from.size(), to);
        pos += to.size();
      }
    };
    std::string wheelScript = kInstallBundledWheelsScriptTemplate;
    replaceAll(wheelScript, "%WHEELS%", options.home + "/wheels");
    replaceAll(wheelScript, "%SITE%", options.sitePackages);
    PyObject* wheelResult = PyRun_StringFlags(wheelScript.c_str(), Py_file_input,
                                              globals, globals, nullptr);
    if (wheelResult == nullptr) {
      std::string ignored;
      int code = 0;
      ReportException(ignored, code);
      PYIDE_LOGW("install bundled wheels failed: %{public}s", ignored.c_str());
      EmitStream(1, ignored);
    } else {
      Py_DECREF(wheelResult);
    }
  }

  // 初始化完成后立即交出 GIL：后续所有执行都在工作线程上取 GIL 进行
  PyEval_SaveThread();
  g_initialized.store(true);
  PYIDE_LOGI("CPython initialized: %{public}s (abi=%{public}s)", g_version.c_str(), kAbi);
  return true;
#endif
}

/**
 * 在**已持有 GIL** 的前提下执行一段 Python 源码。
 *
 * 为什么需要这个"锁定版"：sys.settrace 是**按线程状态**生效的，而 PyGILState_Ensure/Release
 * 在非 Python 线程上会创建并在 Release 时销毁线程状态。调试会话必须让"装钩子"和"跑用户脚本"
 * 共享同一个线程状态，否则钩子会随线程状态一起被销毁——断点永远不命中（实测踩过）。
 */
static void ExecuteSourceLocked(const std::string& source,
                                const std::string& filename,
                                int startMode,
                                std::string& errOut,
                                int& exitCode)
{
#ifdef PY_RUNTIME_AVAILABLE
  PyObject* mainModule = PyImport_AddModule("__main__");
  PyObject* globals = (mainModule != nullptr) ? PyModule_GetDict(mainModule) : nullptr;
  if (globals == nullptr) {
    errOut += "无法获取 __main__ 命名空间\n";
    exitCode = 1;
    // GIL 由调用方负责释放（本函数假设调用时已持有）
    return;
  }
  if (!filename.empty()) {
    PyObject* fileObj = PyUnicode_FromString(filename.c_str());
    if (fileObj != nullptr) {
      PyDict_SetItemString(globals, "__file__", fileObj);
      Py_DECREF(fileObj);
    }
  }
  // ⚠️ 必须用带文件名的编译接口。PyRun_StringFlags 的第 5 个参数是 PyCompilerFlags*，
  // 它根本没有文件名参数——直接用它会让 co_filename 变成 "<string>"，后果有两个（都实测踩过）：
  //   1) traceback 显示 File "<string>"，对一个 Python IDE 来说不可接受；
  //   2) 调试钩子按真实路径做作用域过滤和断点匹配 → 所有行事件被挡掉 → 断点永远不命中。
  const char* scriptName = filename.empty() ? "<pyide>" : filename.c_str();
  PyCompilerFlags flags;
  std::memset(&flags, 0, sizeof(flags));
  PyObject* code = Py_CompileStringExFlags(source.c_str(), scriptName, startMode, &flags, -1);
  if (code == nullptr) {
    ReportException(errOut, exitCode);
  } else {
    PyObject* result = PyEval_EvalCode(code, globals, globals);
    Py_DECREF(code);
    if (result == nullptr) {
      ReportException(errOut, exitCode);
    } else {
      Py_DECREF(result);
      exitCode = 0;
    }
  }
  g_lastExitCode.store(exitCode);
#else
  (void)source;
  (void)filename;
  (void)startMode;
  errOut += "运行时未就绪：本次构建未链接 libpython3.12.a\n";
  exitCode = 127;
#endif
  g_lastExitCode.store(exitCode);
}

/** 单次执行（自带 GIL 获取/释放），用于普通运行、REPL、pip 等场景 */
static void ExecuteSource(const std::string& source,
                          const std::string& filename,
                          int startMode,
                          std::string& errOut,
                          int& exitCode)
{
  PyGILState_STATE gil = PyGILState_Ensure();
  ExecuteSourceLocked(source, filename, startMode, errOut, exitCode);
  PyGILState_Release(gil);
}

// ─────────────────────────────────────────────────────────────────────────────
// NAPI 异步封装
// ─────────────────────────────────────────────────────────────────────────────

struct AsyncTask {
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  std::function<void()> execute;
  std::function<napi_value(napi_env)> complete;
};

static void ExecuteCallback(napi_env /*env*/, void* data)
{
  AsyncTask* task = static_cast<AsyncTask*>(data);
  if (task != nullptr && task->execute) {
    task->execute();
  }
}

static void CompleteCallback(napi_env env, napi_status /*status*/, void* data)
{
  AsyncTask* task = static_cast<AsyncTask*>(data);
  if (task == nullptr) {
    return;
  }
  napi_value value = nullptr;
  if (task->complete) {
    value = task->complete(env);
  }
  if (value == nullptr) {
    napi_get_undefined(env, &value);
  }
  napi_resolve_deferred(env, task->deferred, value);
  napi_delete_async_work(env, task->work);
  delete task;
}

static napi_value RunAsync(napi_env env,
                           const char* resourceName,
                           std::function<void()> execute,
                           std::function<napi_value(napi_env)> complete)
{
  napi_deferred deferred = nullptr;
  napi_value promise = nullptr;
  napi_create_promise(env, &deferred, &promise);

  AsyncTask* task = new AsyncTask();
  task->deferred = deferred;
  task->execute = std::move(execute);
  task->complete = std::move(complete);

  napi_value name = nullptr;
  napi_create_string_utf8(env, resourceName, NAPI_AUTO_LENGTH, &name);
  napi_create_async_work(env, nullptr, name, ExecuteCallback, CompleteCallback, task, &task->work);
  napi_queue_async_work(env, task->work);
  return promise;
}

// ─────────────────────────────────────────────────────────────────────────────
// JS 值辅助函数
// ─────────────────────────────────────────────────────────────────────────────

static std::string GetString(napi_env env, napi_value value)
{
  napi_valuetype type = napi_undefined;
  napi_typeof(env, value, &type);
  if (type != napi_string) {
    return std::string();
  }
  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
    return std::string();
  }
  std::string buffer(length + 1, '\0');
  size_t copied = 0;
  napi_get_value_string_utf8(env, value, &buffer[0], length + 1, &copied);
  buffer.resize(copied);
  return buffer;
}

static std::string GetStringProperty(napi_env env, napi_value object, const char* name)
{
  bool has = false;
  napi_has_named_property(env, object, name, &has);
  if (!has) {
    return std::string();
  }
  napi_value value = nullptr;
  if (napi_get_named_property(env, object, name, &value) != napi_ok) {
    return std::string();
  }
  return GetString(env, value);
}

static std::vector<std::string> GetStringArrayValue(napi_env env, napi_value value)
{
  std::vector<std::string> result;
  bool isArray = false;
  napi_is_array(env, value, &isArray);
  if (!isArray) {
    return result;
  }
  uint32_t length = 0;
  napi_get_array_length(env, value, &length);
  for (uint32_t i = 0; i < length; i++) {
    napi_value item = nullptr;
    if (napi_get_element(env, value, i, &item) == napi_ok) {
      result.push_back(GetString(env, item));
    }
  }
  return result;
}

static std::vector<std::string> GetStringArrayProperty(napi_env env, napi_value object, const char* name)
{
  bool has = false;
  napi_has_named_property(env, object, name, &has);
  if (!has) {
    return std::vector<std::string>();
  }
  napi_value array = nullptr;
  if (napi_get_named_property(env, object, name, &array) != napi_ok) {
    return std::vector<std::string>();
  }
  return GetStringArrayValue(env, array);
}

static void SetProperty(napi_env env, napi_value object, const char* name, napi_value value)
{
  napi_set_named_property(env, object, name, value);
}

static void SetStringProperty(napi_env env, napi_value object, const char* name, const std::string& value)
{
  napi_value str = nullptr;
  napi_create_string_utf8(env, value.c_str(), value.size(), &str);
  SetProperty(env, object, name, str);
}

static void SetIntProperty(napi_env env, napi_value object, const char* name, int32_t value)
{
  napi_value num = nullptr;
  napi_create_int32(env, value, &num);
  SetProperty(env, object, name, num);
}

static void SetDoubleProperty(napi_env env, napi_value object, const char* name, double value)
{
  napi_value num = nullptr;
  napi_create_double(env, value, &num);
  SetProperty(env, object, name, num);
}

static void SetBoolProperty(napi_env env, napi_value object, const char* name, bool value)
{
  napi_value flag = nullptr;
  napi_get_boolean(env, value, &flag);
  SetProperty(env, object, name, flag);
}

static napi_value MakeRunResult(napi_env env, int32_t code, const std::string& out,
                                const std::string& err, double durationMs)
{
  napi_value object = nullptr;
  napi_create_object(env, &object);
  SetIntProperty(env, object, "code", code);
  SetStringProperty(env, object, "stdout", out);
  SetStringProperty(env, object, "stderr", err);
  SetDoubleProperty(env, object, "durationMs", durationMs);
  return object;
}

// ─────────────────────────────────────────────────────────────────────────────
// 导出接口
// ─────────────────────────────────────────────────────────────────────────────

static napi_value JsIsRuntimeAvailable(napi_env env, napi_callback_info /*info*/)
{
  napi_value result = nullptr;
#ifdef PY_RUNTIME_AVAILABLE
  napi_get_boolean(env, true, &result);
#else
  napi_get_boolean(env, false, &result);
#endif
  return result;
}

static napi_value JsIsRunning(napi_env env, napi_callback_info /*info*/)
{
  napi_value result = nullptr;
  napi_get_boolean(env, g_running.load(), &result);
  return result;
}

static napi_value JsGetRuntimeInfo(napi_env env, napi_callback_info /*info*/)
{
  napi_value object = nullptr;
  napi_create_object(env, &object);
#ifdef PY_RUNTIME_AVAILABLE
  SetBoolProperty(env, object, "available", true);
#else
  SetBoolProperty(env, object, "available", false);
#endif
  SetStringProperty(env, object, "version", g_version);
  SetStringProperty(env, object, "abi", std::string(kAbi));
  SetStringProperty(env, object, "buildTime", kBuildTime);
  return object;
}

static napi_value JsSetOutputCallback(napi_env env, napi_callback_info info)
{
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  napi_valuetype type = napi_undefined;
  if (argc > 0) {
    napi_typeof(env, args[0], &type);
  }

  std::lock_guard<std::mutex> lock(g_tsfnMutex);
  if (g_tsfn != nullptr) {
    napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
    g_tsfn = nullptr;
  }
  if (argc > 0 && type == napi_function) {
    napi_value name = nullptr;
    napi_create_string_utf8(env, "PyBridgeOutput", NAPI_AUTO_LENGTH, &name);
    napi_status status = napi_create_threadsafe_function(
        env, args[0], nullptr, name, 0, 1, nullptr, nullptr, nullptr, CallJsOutput, &g_tsfn);
    if (status != napi_ok) {
      g_tsfn = nullptr;
      PYIDE_LOGE("create threadsafe function failed: %{public}d", status);
    }
  }
  napi_value undefined = nullptr;
  napi_get_undefined(env, &undefined);
  return undefined;
}

static napi_value JsInitialize(napi_env env, napi_callback_info info)
{
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  InitOptions options;
  if (argc > 0) {
    options.filesDir = GetStringProperty(env, args[0], "filesDir");
    options.stdlibZip = GetStringProperty(env, args[0], "stdlibZip");
    options.sitePackages = GetStringProperty(env, args[0], "sitePackages");
    options.home = GetStringProperty(env, args[0], "home");
    options.argv = GetStringArrayProperty(env, args[0], "argv");
    options.extraPaths = GetStringArrayProperty(env, args[0], "extraPaths");
  }
  if (options.home.empty() && !options.filesDir.empty()) {
    options.home = options.filesDir + "/python";
  }

  return RunAsync(env, "PyIdeInitialize",
      [options]() {
        std::lock_guard<std::mutex> lock(g_pyMutex);
        std::string error;
        if (!EnsureInterpreter(options, error)) {
          EmitStream(1, error + "\n");
        }
      },
      [](napi_env env2) -> napi_value {
        napi_value value = nullptr;
        if (!g_initialized.load()) {
          napi_create_string_utf8(env2, "", 0, &value);
          return value;
        }
        napi_create_string_utf8(env2, g_version.c_str(), g_version.size(), &value);
        return value;
      });
}

static napi_value JsRunFile(napi_env env, napi_callback_info info)
{
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  const std::string path = (argc > 0) ? GetString(env, args[0]) : std::string();
  std::vector<std::string> scriptArgs;
  if (argc > 1) {
    scriptArgs = GetStringArrayValue(env, args[1]);
  }

  return RunAsync(env, "PyIdeRunFile",
      [path, scriptArgs]() {
        if (g_running.exchange(true)) {
          EmitStream(1, "已有脚本正在运行，请先停止。\n");
          return;
        }
        {
          std::lock_guard<std::mutex> lock(g_pyMutex);
          g_runStdout.clear();
          g_runStderr.clear();

          std::string source;
          FILE* file = fopen(path.c_str(), "rb");
          if (file == nullptr) {
            EmitStream(1, "无法打开文件: " + path + "\n");
          } else {
            char buffer[8192];
            size_t read = 0;
            while ((read = fread(buffer, 1, sizeof(buffer), file)) > 0) {
              source.append(buffer, read);
            }
            fclose(file);
          }

          if (!source.empty()) {
#ifdef PY_RUNTIME_AVAILABLE
            // 设置 sys.argv，让被运行的脚本拿到命令行参数
            {
              PyGILState_STATE gil = PyGILState_Ensure();
              PyObject* sysModule = PyImport_ImportModule("sys");
              if (sysModule != nullptr) {
                PyObject* list = PyList_New(0);
                if (list != nullptr) {
                  PyObject* scriptName = PyUnicode_FromString(path.c_str());
                  PyList_Append(list, scriptName);
                  Py_XDECREF(scriptName);
                  for (const std::string& arg : scriptArgs) {
                    PyObject* item = PyUnicode_FromString(arg.c_str());
                    PyList_Append(list, item);
                    Py_XDECREF(item);
                  }
                  PyObject_SetAttrString(sysModule, "argv", list);
                  Py_DECREF(list);
                }
                Py_DECREF(sysModule);
              } else {
                PyErr_Clear();
              }
              PyGILState_Release(gil);
            }
#endif
            std::string error;
            int exitCode = 0;
            ExecuteSource(source, path, Py_file_input, error, exitCode);
            if (!error.empty()) {
              EmitStream(1, error);
            }
          }
          g_running.store(false);
        }
      },
      [](napi_env env2) -> napi_value {
        std::string out;
        std::string err;
        {
          std::lock_guard<std::mutex> lock(g_pyMutex);
          out = g_runStdout;
          err = g_runStderr;
        }
        return MakeRunResult(env2, g_lastExitCode.load(), out, err, 0.0);
      });
}

static napi_value JsRunCode(napi_env env, napi_callback_info info)
{
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  const std::string code = (argc > 0) ? GetString(env, args[0]) : std::string();
  const std::string filename = (argc > 1) ? GetString(env, args[1]) : std::string("<ide>");

  return RunAsync(env, "PyIdeRunCode",
      [code, filename]() {
        if (g_running.exchange(true)) {
          EmitStream(1, "已有脚本正在运行，请先停止。\n");
          return;
        }
        {
          std::lock_guard<std::mutex> lock(g_pyMutex);
          g_runStdout.clear();
          g_runStderr.clear();
          std::string error;
          int exitCode = 0;
          ExecuteSource(code, filename, Py_file_input, error, exitCode);
          if (!error.empty()) {
            EmitStream(1, error);
          }
          g_running.store(false);
        }
      },
      [](napi_env env2) -> napi_value {
        std::string out;
        std::string err;
        {
          std::lock_guard<std::mutex> lock(g_pyMutex);
          out = g_runStdout;
          err = g_runStderr;
        }
        return MakeRunResult(env2, g_lastExitCode.load(), out, err, 0.0);
      });
}

static napi_value JsRunRepl(napi_env env, napi_callback_info info)
{
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  const std::string line = (argc > 0) ? GetString(env, args[0]) : std::string();

  return RunAsync(env, "PyIdeRunRepl",
      [line]() {
        std::lock_guard<std::mutex> lock(g_pyMutex);
        g_runStdout.clear();
        g_runStderr.clear();
        std::string error;
        int exitCode = 0;
        // Py_single_input 等价于交互式解释器：表达式会自动打印 repr
        ExecuteSource(line, "<console>", Py_single_input, error, exitCode);
        if (!error.empty()) {
          EmitStream(1, error);
        }
      },
      [](napi_env env2) -> napi_value {
        std::string out;
        std::string err;
        {
          std::lock_guard<std::mutex> lock(g_pyMutex);
          out = g_runStdout;
          err = g_runStderr;
        }
        napi_value value = nullptr;
        napi_create_string_utf8(env2, (out + err).c_str(), out.size() + err.size(), &value);
        return value;
      });
}

static napi_value JsPipInstall(napi_env env, napi_callback_info info)
{
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  std::vector<std::string> pipArgs = (argc > 0) ? GetStringArrayValue(env, args[0]) : std::vector<std::string>();

  return RunAsync(env, "PyIdePip",
      [pipArgs]() {
        if (g_running.exchange(true)) {
          EmitStream(1, "已有脚本正在运行，请先停止。\n");
          return;
        }
        {
          std::lock_guard<std::mutex> lock(g_pyMutex);
          g_runStdout.clear();
          g_runStderr.clear();
          std::string command = "import sys, runpy\nsys.argv = ['pip'";
          for (const std::string& arg : pipArgs) {
            command += ", '";
            for (char ch : arg) {
              if (ch == '\'') {
                command += "\\'";
              } else {
                command += ch;
              }
            }
            command += "'";
          }
          command += "]\ntry:\n    runpy.run_module('pip', run_name='__main__', alter_sys=True)\n"
                     "except SystemExit:\n    pass\n";
          std::string error;
          int exitCode = 0;
          ExecuteSource(command, "<pip>", Py_file_input, error, exitCode);
          if (!error.empty()) {
            EmitStream(1, error);
          }
          g_running.store(false);
        }
      },
      [](napi_env env2) -> napi_value {
        std::string out;
        std::string err;
        {
          std::lock_guard<std::mutex> lock(g_pyMutex);
          out = g_runStdout;
          err = g_runStderr;
        }
        return MakeRunResult(env2, g_lastExitCode.load(), out, err, 0.0);
      });
}

static napi_value JsInterrupt(napi_env env, napi_callback_info /*info*/)
{
#ifdef PY_RUNTIME_AVAILABLE
  if (g_initialized.load()) {
    PyErr_SetInterrupt();
  }
#endif
  napi_value undefined = nullptr;
  napi_get_undefined(env, &undefined);
  return undefined;
}

static napi_value JsFinalize(napi_env env, napi_callback_info /*info*/)
{
  return RunAsync(env, "PyIdeFinalize",
      []() {
        std::lock_guard<std::mutex> lock(g_pyMutex);
#ifdef PY_RUNTIME_AVAILABLE
        if (g_initialized.load() && !g_finalized.load()) {
          PyGILState_STATE gil = PyGILState_Ensure();
          Py_FinalizeEx();
          (void)gil;
          g_finalized.store(true);
          g_initialized.store(false);
        }
#endif
      },
      [](napi_env env2) -> napi_value {
        napi_value value = nullptr;
        napi_get_boolean(env2, true, &value);
        return value;
      });
}

/** ArkTS 下发调试指令：'continue' | 'step' | 'stop'（仅在暂停时有效） */
static napi_value JsDebugCommand(napi_env env, napi_callback_info info)
{
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  std::string command = (argc > 0) ? GetString(env, args[0]) : std::string("continue");
  if (command.empty()) {
    command = "continue";
  }
  {
    std::lock_guard<std::mutex> lock(g_debugMutex);
    g_debugCommand = command;
  }
  g_debugCv.notify_all();
  PYIDE_LOGI("debug command: %{public}s", command.c_str());
  napi_value undefined = nullptr;
  napi_get_undefined(env, &undefined);
  return undefined;
}

static napi_value JsIsDebugPaused(napi_env env, napi_callback_info /*info*/)
{
  napi_value result = nullptr;
  napi_get_boolean(env, g_debugPaused.load(), &result);
  return result;
}

/**
 * 以调试模式运行 .py 文件：
 *   debugRun(path, args, breakpointsJson, rootsJson) -> Promise<PyRunResult>
 * breakpointsJson: {"<绝对路径>": [行号, ...]}；rootsJson: [工程根目录, ...]
 * 暂停事件以 stream=2 的形式推送（见 setOutputCallback）。
 */
static napi_value JsDebugRun(napi_env env, napi_callback_info info)
{
  size_t argc = 4;
  napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  const std::string path = (argc > 0) ? GetString(env, args[0]) : std::string();
  std::vector<std::string> scriptArgs;
  if (argc > 1) {
    scriptArgs = GetStringArrayValue(env, args[1]);
  }
  const std::string breakpointsJson = (argc > 2) ? GetString(env, args[2]) : std::string("{}");
  const std::string rootsJson = (argc > 3) ? GetString(env, args[3]) : std::string("[]");

  return RunAsync(env, "PyIdeDebugRun",
      [path, scriptArgs, breakpointsJson, rootsJson]() {
        if (g_running.exchange(true)) {
          EmitStream(1, "已有脚本正在运行，请先停止。\n");
          return;
        }
        {
          std::lock_guard<std::mutex> lock(g_pyMutex);
          g_runStdout.clear();
          g_runStderr.clear();
          g_debugAbort.store(false);
          g_lastExitCode.store(0);

          std::string source;
          FILE* file = fopen(path.c_str(), "rb");
          if (file == nullptr) {
            EmitStream(1, "无法打开文件: " + path + "\n");
            g_running.store(false);
            return;
          }
          char buffer[8192];
          size_t read = 0;
          while ((read = fread(buffer, 1, sizeof(buffer), file)) > 0) {
            source.append(buffer, read);
          }
          fclose(file);

          std::string error;
          int exitCode = 0;
#ifdef PY_RUNTIME_AVAILABLE
          // ⚠️ 钩子安装与用户脚本执行必须在**同一个 GIL 段**内完成。
          // sys.settrace 按线程状态生效，而 PyGILState_Ensure/Release 在非 Python 线程上会
          // 创建并在 Release 时销毁线程状态；若分成多次 ExecuteSource，钩子会随线程状态
          // 一起被销毁 → 行事件再也不触发 → 断点永不命中（这正是之前调试器不工作的原因）。
          {
            PyGILState_STATE gil = PyGILState_Ensure();
            PyObject* sysModule = PyImport_ImportModule("sys");
            if (sysModule != nullptr) {
              PyObject* list = PyList_New(0);
              if (list != nullptr) {
                PyObject* scriptName = PyUnicode_FromString(path.c_str());
                PyList_Append(list, scriptName);
                Py_XDECREF(scriptName);
                for (const std::string& arg : scriptArgs) {
                  PyObject* item = PyUnicode_FromString(arg.c_str());
                  PyList_Append(list, item);
                  Py_XDECREF(item);
                }
                PyObject_SetAttrString(sysModule, "argv", list);
                Py_DECREF(list);
              }
              Py_DECREF(sysModule);
            } else {
              PyErr_Clear();
            }

            // 1) 注入钩子  2) 配置断点与工程根  3) 执行用户脚本  4) 卸载钩子（同一线程状态）
            ExecuteSourceLocked(kDebugHookScript, "<pyide-debug-hook>",
                                Py_file_input, error, exitCode);
            if (!error.empty()) {
              EmitStream(1, error);
            }
            std::string installCall = "_pyide_configure(" + PyStrLiteral(breakpointsJson) + ", "
                                      + PyStrLiteral(rootsJson) + ")\n_pyide_install()\n";
            error.clear();
            ExecuteSourceLocked(installCall, "<pyide-debug-install>",
                                Py_file_input, error, exitCode);
            if (!error.empty()) {
              EmitStream(1, error);
            }
            error.clear();
            ExecuteSourceLocked(source, path, Py_file_input, error, exitCode);
            if (!error.empty()) {
              EmitStream(1, error);
            }
            std::string cleanupError;
            int cleanupCode = 0;
            ExecuteSourceLocked("_pyide_uninstall()\n", "<pyide-debug-uninstall>",
                                Py_file_input, cleanupError, cleanupCode);
            PyGILState_Release(gil);
          }
#else
          EmitStream(1, "运行时未就绪：本次构建未链接 libpython3.12.a\n");
          g_lastExitCode.store(127);
#endif
          g_running.store(false);
        }
      },
      [](napi_env env2) -> napi_value {
        std::string out;
        std::string err;
        {
          std::lock_guard<std::mutex> lock(g_pyMutex);
          out = g_runStdout;
          err = g_runStderr;
        }
        return MakeRunResult(env2, g_lastExitCode.load(), out, err, 0.0);
      });
}

// ─────────────────────────────────────────────────────────────────────────────
// 模块注册
// ─────────────────────────────────────────────────────────────────────────────

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
  napi_property_descriptor desc[] = {
      {"isRuntimeAvailable", nullptr, JsIsRuntimeAvailable, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"getRuntimeInfo", nullptr, JsGetRuntimeInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"setOutputCallback", nullptr, JsSetOutputCallback, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"initialize", nullptr, JsInitialize, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"runFile", nullptr, JsRunFile, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"runCode", nullptr, JsRunCode, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"runRepl", nullptr, JsRunRepl, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"pipInstall", nullptr, JsPipInstall, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"interrupt", nullptr, JsInterrupt, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"isRunning", nullptr, JsIsRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"debugRun", nullptr, JsDebugRun, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"debugCommand", nullptr, JsDebugCommand, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"isDebugPaused", nullptr, JsIsDebugPaused, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"finalize", nullptr, JsFinalize, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  // 终端 PTY / 目录监听：注册到同一个 pythonbridge 模块上
  RegisterPtyWatch(env, exports);
  return exports;
}
EXTERN_C_END

static napi_module pythonBridgeModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "pythonbridge",
    .nm_priv = ((void*)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterPythonBridgeModule(void)
{
  napi_module_register(&pythonBridgeModule);
}
