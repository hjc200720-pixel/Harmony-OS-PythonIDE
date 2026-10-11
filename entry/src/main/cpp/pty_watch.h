/**
 * pty_watch.h —— 终端 PTY 与目录监听的 NAPI 绑定（libpythonbridge 的一部分）
 */
#ifndef HARMONY_PY_IDE_PTY_WATCH_H
#define HARMONY_PY_IDE_PTY_WATCH_H

#include <napi/native_api.h>

/**
 * 注册以下导出：
 *   终端 PTY：ptyOpen / ptyWrite / ptyRead / ptyResize / ptyClose / ptyAlive
 *   目录监听：watchDir / pollDirWatch / unwatchDir
 * 全部为非阻塞（O_NONBLOCK / inotify），UI 线程可安全轮询。
 */
void RegisterPtyWatch(napi_env env, napi_value exports);

#endif // HARMONY_PY_IDE_PTY_WATCH_H
