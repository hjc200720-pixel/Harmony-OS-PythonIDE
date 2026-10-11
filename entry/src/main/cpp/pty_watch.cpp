/**
 * pty_watch.cpp —— 终端 PTY（伪终端 + 真实 shell）与目录监听（inotify）。
 *
 * 为什么放 native：
 *  1) ArkTS 拿不到 pty 设备（/dev/ptmx、/dev/pts/N），也起不了真正的 shell；
 *     只有 native 能把 App 沙箱里的 shell 接到终端工具窗上。
 *  2) 目录监听用 inotify：一次注册，轮询只读内核队列，比 ArkTS 定时 refreshDir 便宜得多。
 *
 * 线程模型：所有函数都是**非阻塞**的（PTY master 设 O_NONBLOCK，inotify fd 设 O_NONBLOCK），
 * ArkTS 侧定时轮询即可，不会卡住 UI 线程。
 */
#include "pty_watch.h"

#include <hilog/log.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <string>
#include <vector>

#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#ifdef __linux__
#include <sys/inotify.h>
#define PYIDE_HAVE_INOTIFY 1
#endif

#define PTY_TAG "PyIDENative"
#define PTY_LOGI(fmt, ...) OH_LOG_INFO(LOG_APP, fmt, ##__VA_ARGS__)
#define PTY_LOGW(fmt, ...) OH_LOG_WARN(LOG_APP, fmt, ##__VA_ARGS__)

namespace {

struct PtySession {
  int master = -1;
  pid_t pid = -1;
  std::string shell;
};

struct WatchSession {
  int fd = -1;
  int wd = -1;
  std::string path;
  std::vector<std::string> pending;
};

std::mutex g_mutex;
std::map<int, PtySession> g_ptys;
std::map<int, WatchSession> g_watches;
int g_nextWatchId = 1;

// ── NAPI 小工具 ───────────────────────────────────────────────────────────

std::string Utf8Of(napi_env env, napi_value value) {
  size_t len = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &len) != napi_ok) {
    return std::string();
  }
  std::string out(len, '\0');
  size_t copied = 0;
  if (napi_get_value_string_utf8(env, value, &out[0], len + 1, &copied) != napi_ok) {
    return std::string();
  }
  out.resize(copied);
  return out;
}

int32_t IntOf(napi_env env, napi_value value, int32_t fallback) {
  int32_t out = fallback;
  if (napi_get_value_int32(env, value, &out) != napi_ok) {
    return fallback;
  }
  return out;
}

napi_value MakeInt(napi_env env, int32_t value) {
  napi_value out = nullptr;
  napi_create_int32(env, value, &out);
  return out;
}

napi_value MakeBool(napi_env env, bool value) {
  napi_value out = nullptr;
  napi_get_boolean(env, value, &out);
  return out;
}

napi_value MakeString(napi_env env, const std::string& value) {
  napi_value out = nullptr;
  napi_create_string_utf8(env, value.c_str(), value.size(), &out);
  return out;
}

std::string JsonEscape(const std::string& raw) {
  std::string out;
  out.reserve(raw.size() + 8);
  for (size_t i = 0; i < raw.size(); i++) {
    const char c = raw[i];
    if (c == '"' || c == '\\') {
      out.push_back('\\');
      out.push_back(c);
    } else if (c == '\n') {
      out += "\\n";
    } else if (c == '\r') {
      out += "\\r";
    } else if (c == '\t') {
      out += "\\t";
    } else if (static_cast<unsigned char>(c) < 0x20) {
      char buf[8] = {0};
      snprintf(buf, sizeof(buf), "\\u%04x", c);
      out += buf;
    } else {
      out.push_back(c);
    }
  }
  return out;
}

// ── PTY ──────────────────────────────────────────────────────────────────

bool SetNonBlocking(int fd) {
  const int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0) {
    return false;
  }
  return fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0;
}

bool SpawnShell(int master, const std::string& shell, std::string& slaveName, pid_t& childPid) {
  const char* slave = ptsname(master);
  if (slave == nullptr) {
    PTY_LOGW("%{public}s ptyOpen: ptsname failed errno=%{public}d (%{public}s)", PTY_TAG, errno,
             strerror(errno));
    return false;
  }
  slaveName = slave;
  const pid_t pid = fork();
  if (pid < 0) {
    PTY_LOGW("%{public}s ptyOpen: fork failed errno=%{public}d (%{public}s)", PTY_TAG, errno,
             strerror(errno));
    return false;
  }
  childPid = pid;
  if (pid == 0) {
    // 子进程：新会话 + 把 PTY 从设备接到 0/1/2，再 exec 真 shell
    setsid();
    const int sfd = open(slaveName.c_str(), O_RDWR);
    if (sfd < 0) {
      _exit(126);
    }
#ifdef TIOCSCTTY
    ioctl(sfd, TIOCSCTTY, 0);
#endif
    dup2(sfd, STDIN_FILENO);
    dup2(sfd, STDOUT_FILENO);
    dup2(sfd, STDERR_FILENO);
    if (sfd > STDERR_FILENO) {
      close(sfd);
    }
    close(master);
    // 沙箱里 /bin/sh 一定在；/system/bin/sh 作为兜底
    execl(shell.c_str(), "sh", "-i", nullptr);
    execl("/system/bin/sh", "sh", "-i", nullptr);
    _exit(127);
  }
  return true;
}

napi_value JsPtyOpen(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  std::string shell = argc >= 1 ? Utf8Of(env, argv[0]) : std::string();
  if (shell.empty()) {
    shell = "/bin/sh";
  }
  const int master = posix_openpt(O_RDWR | O_NOCTTY);
  if (master < 0) {
    // 鸿蒙应用沙箱里 /dev/ptmx 很可能是 Permission denied（SELinux 不给普通应用 pty 标签）
    PTY_LOGW("%{public}s ptyOpen: posix_openpt failed errno=%{public}d (%{public}s)", PTY_TAG, errno,
             strerror(errno));
    return MakeInt(env, -1);
  }
  if (grantpt(master) != 0) {
    PTY_LOGW("%{public}s ptyOpen: grantpt failed errno=%{public}d (%{public}s)", PTY_TAG, errno,
             strerror(errno));
    close(master);
    return MakeInt(env, -1);
  }
  if (unlockpt(master) != 0) {
    PTY_LOGW("%{public}s ptyOpen: unlockpt failed errno=%{public}d (%{public}s)", PTY_TAG, errno,
             strerror(errno));
    close(master);
    return MakeInt(env, -1);
  }
  SetNonBlocking(master);
  std::string slaveName;
  pid_t child = -1;
  if (!SpawnShell(master, shell, slaveName, child)) {
    close(master);
    return MakeInt(env, -1);
  }
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    PtySession session;
    session.master = master;
    session.pid = child;
    session.shell = shell;
    g_ptys[master] = session;
  }
  PTY_LOGI("%{public}s ptyOpen fd=%{public}d shell=%{public}s slave=%{public}s", PTY_TAG, master,
           shell.c_str(), slaveName.c_str());
  return MakeInt(env, master);
}

napi_value JsPtyWrite(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 2) {
    return MakeInt(env, -1);
  }
  const int32_t fd = IntOf(env, argv[0], -1);
  const std::string data = Utf8Of(env, argv[1]);
  const ssize_t written = write(fd, data.data(), data.size());
  return MakeInt(env, static_cast<int32_t>(written));
}

napi_value JsPtyRead(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  const int32_t fd = argc >= 1 ? IntOf(env, argv[0], -1) : -1;
  std::string out;
  char buf[4096];
  // 一次最多读 64KB，避免单帧过大；非阻塞，读空即返回
  for (int i = 0; i < 16; i++) {
    const ssize_t n = read(fd, buf, sizeof(buf));
    if (n > 0) {
      out.append(buf, static_cast<size_t>(n));
      continue;
    }
    break;
  }
  return MakeString(env, out);
}

napi_value JsPtyResize(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value argv[3] = {nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 3) {
    return MakeBool(env, false);
  }
  const int32_t fd = IntOf(env, argv[0], -1);
  struct winsize ws;
  memset(&ws, 0, sizeof(ws));
  ws.ws_col = static_cast<unsigned short>(IntOf(env, argv[1], 80));
  ws.ws_row = static_cast<unsigned short>(IntOf(env, argv[2], 24));
  return MakeBool(env, ioctl(fd, TIOCSWINSZ, &ws) == 0);
}

napi_value JsPtyClose(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  const int32_t fd = argc >= 1 ? IntOf(env, argv[0], -1) : -1;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_ptys.erase(fd);
  }
  if (fd >= 0) {
    close(fd);
  }
  return MakeBool(env, true);
}

napi_value JsPtyAlive(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  const int32_t fd = argc >= 1 ? IntOf(env, argv[0], -1) : -1;
  if (fd < 0) {
    return MakeBool(env, false);
  }
  char buf[1];
  const ssize_t n = read(fd, buf, 0);
  return MakeBool(env, !(n < 0 && errno == EBADF));
}

// ── 目录监听（inotify） ───────────────────────────────────────────────────

const char* MaskName(uint32_t mask) {
  if (mask & IN_CREATE) return "create";
  if (mask & IN_DELETE) return "delete";
  if (mask & IN_MOVED_FROM) return "movedFrom";
  if (mask & IN_MOVED_TO) return "movedTo";
  if (mask & IN_MODIFY) return "modify";
  if (mask & IN_ATTRIB) return "attrib";
  if (mask & IN_CLOSE_WRITE) return "closeWrite";
  if (mask & IN_DELETE_SELF) return "deleteSelf";
  if (mask & IN_MOVE_SELF) return "moveSelf";
  return "other";
}

napi_value JsWatchDir(napi_env env, napi_callback_info info) {
#ifdef PYIDE_HAVE_INOTIFY
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  const std::string path = argc >= 1 ? Utf8Of(env, argv[0]) : std::string();
  if (path.empty()) {
    return MakeInt(env, -1);
  }
  const int fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
  if (fd < 0) {
    PTY_LOGW("%{public}s watchDir: inotify_init1 failed errno=%{public}d", PTY_TAG, errno);
    return MakeInt(env, -1);
  }
  const uint32_t mask = IN_CREATE | IN_DELETE | IN_MODIFY | IN_MOVED_FROM | IN_MOVED_TO |
                        IN_ATTRIB | IN_CLOSE_WRITE | IN_DELETE_SELF | IN_MOVE_SELF;
  const int wd = inotify_add_watch(fd, path.c_str(), mask);
  if (wd < 0) {
    close(fd);
    PTY_LOGW("%{public}s watchDir: add_watch %{public}s failed errno=%{public}d", PTY_TAG,
             path.c_str(), errno);
    return MakeInt(env, -1);
  }
  int id = -1;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    id = g_nextWatchId++;
    WatchSession session;
    session.fd = fd;
    session.wd = wd;
    session.path = path;
    g_watches[id] = session;
  }
  PTY_LOGI("%{public}s watchDir id=%{public}d path=%{public}s", PTY_TAG, id, path.c_str());
  return MakeInt(env, id);
#else
  (void)info;
  return MakeInt(env, -1);
#endif
}

napi_value JsPollDirWatch(napi_env env, napi_callback_info info) {
#ifdef PYIDE_HAVE_INOTIFY
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  const int32_t id = argc >= 1 ? IntOf(env, argv[0], -1) : -1;
  int fd = -1;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    const auto it = g_watches.find(id);
    if (it == g_watches.end()) {
      return MakeString(env, "[]");
    }
    fd = it->second.fd;
  }
  std::string json = "[";
  bool first = true;
  char buf[4096] __attribute__((aligned(__alignof__(struct inotify_event))));
  for (;;) {
    const ssize_t len = read(fd, buf, sizeof(buf));
    if (len <= 0) {
      break;
    }
    for (char* p = buf; p < buf + len;) {
      const struct inotify_event* event = reinterpret_cast<const struct inotify_event*>(p);
      const char* name = event->len > 0 ? event->name : "";
      if (!first) {
        json += ",";
      }
      first = false;
      json += "{\"event\":\"";
      json += MaskName(event->mask);
      json += "\",\"name\":\"";
      json += JsonEscape(name);
      json += "\",\"dir\":";
      json += (event->mask & IN_ISDIR) ? "true" : "false";
      json += "}";
      p += sizeof(struct inotify_event) + event->len;
    }
  }
  json += "]";
  return MakeString(env, json);
#else
  (void)info;
  return MakeString(env, "[]");
#endif
}

napi_value JsUnwatchDir(napi_env env, napi_callback_info info) {
#ifdef PYIDE_HAVE_INOTIFY
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  const int32_t id = argc >= 1 ? IntOf(env, argv[0], -1) : -1;
  WatchSession session;
  bool found = false;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    const auto it = g_watches.find(id);
    if (it != g_watches.end()) {
      session = it->second;
      g_watches.erase(it);
      found = true;
    }
  }
  if (found) {
    if (session.wd >= 0) {
      inotify_rm_watch(session.fd, session.wd);
    }
    close(session.fd);
  }
  return MakeBool(env, found);
#else
  (void)info;
  return MakeBool(env, false);
#endif
}

// ── 无 PTY 时的「真 shell」兜底：popen(/bin/sh -c cmd) ──────────────────────
// 鸿蒙沙箱不给普通应用 /dev/ptmx 时，行式 shell 仍然可用：
// 命令在真 shell 里执行、stdout/stderr 合并返回，足够支撑终端工具窗。
napi_value JsShellRun(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  const std::string command = argc >= 1 ? Utf8Of(env, argv[0]) : std::string();
  if (command.empty()) {
    return MakeString(env, "");
  }
  std::string output;
  FILE* pipe = popen(command.c_str(), "r");
  if (pipe == nullptr) {
    PTY_LOGW("%{public}s shellRun: popen failed errno=%{public}d (%{public}s)", PTY_TAG, errno,
             strerror(errno));
    return MakeString(env, std::string("[shell] popen failed: ") + strerror(errno) + "\n");
  }
  char buf[1024];
  size_t n = 0;
  while ((n = fread(buf, 1, sizeof(buf), pipe)) > 0) {
    output.append(buf, n);
  }
  const int rc = pclose(pipe);
  PTY_LOGI("%{public}s shellRun cmd=%{public}s rc=%{public}d bytes=%{public}zu", PTY_TAG,
           command.c_str(), rc, output.size());
  return MakeString(env, output);
}

/** 诊断：报告 PTY 各步骤结果与 errno（ArkTS 侧可据此提示用户） */
napi_value JsPtyDiagnose(napi_env env, napi_callback_info /*info*/) {
  std::string json = "{\"ptmxAccess\":";
  const int acc = access("/dev/ptmx", R_OK | W_OK);
  json += (acc == 0) ? "true" : "false";
  json += ",\"ptmxErrno\":" + std::to_string(acc == 0 ? 0 : errno);
  json += ",\"ptmxErrnoText\":\"";
  json += JsonEscape(acc == 0 ? std::string("ok") : std::string(strerror(errno)));
  json += "\"";
  errno = 0;
  const int master = posix_openpt(O_RDWR | O_NOCTTY);
  const int openErrno = master < 0 ? errno : 0;
  if (master >= 0) {
    close(master);
  }
  json += ",\"posixOpenptOk\":";
  json += (master >= 0) ? "true" : "false";
  json += ",\"posixOpenptErrno\":" + std::to_string(openErrno);
  json += ",\"shellAvailable\":";
  json += (access("/bin/sh", X_OK) == 0) ? "true" : "false";
  json += "}";
  PTY_LOGI("%{public}s ptyDiagnose %{public}s", PTY_TAG, json.c_str());
  return MakeString(env, json);
}

}  // namespace

void RegisterPtyWatch(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"ptyOpen", nullptr, JsPtyOpen, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"ptyWrite", nullptr, JsPtyWrite, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"ptyRead", nullptr, JsPtyRead, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"ptyResize", nullptr, JsPtyResize, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"ptyClose", nullptr, JsPtyClose, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"ptyAlive", nullptr, JsPtyAlive, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"watchDir", nullptr, JsWatchDir, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"pollDirWatch", nullptr, JsPollDirWatch, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"unwatchDir", nullptr, JsUnwatchDir, nullptr, nullptr, nullptr, napi_default, nullptr},
      // 无 PTY 时的行式 shell 兜底 + 诊断
      {"shellRun", nullptr, JsShellRun, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"ptyDiagnose", nullptr, JsPtyDiagnose, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  PTY_LOGI("%{public}s RegisterPtyWatch: 9 个导出已注册（PTY + 目录监听）", PTY_TAG);
}
