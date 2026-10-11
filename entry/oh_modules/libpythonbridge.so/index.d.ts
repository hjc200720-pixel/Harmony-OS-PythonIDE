/**
 * 原生 CPython 运行时桥接（ArkTS 侧类型声明）。
 * 实现见同目录 ../napi_init.cpp，编译产物为 libpythonbridge.so。
 *
 * 线程模型：所有导出函数都在 native 侧的工作线程执行 Python，绝不阻塞 UI 线程；
 * 输出通过 setOutputCallback 注册的回调实时回流到 ArkTS。
 */

/** 初始化参数：全部是应用沙箱内的真实 POSIX 路径 */
export interface PyInitOptions {
  /** context.filesDir，例如 /data/storage/el2/base/haps/entry/files */
  filesDir: string;
  /** 标准库 zip（zipimport 直接加载，无需解压） */
  stdlibZip: string;
  /** 第三方包目录（pip --target 的落点） */
  sitePackages: string;
  /** PYTHONHOME 对应的目录 */
  home: string;
  /** 传给 sys.argv 的参数 */
  argv: string[];
  /** 额外加入 sys.path 的目录（通常是项目根目录） */
  extraPaths: string[];
}

/** 一次运行的汇总结果 */
export interface PyRunResult {
  /** 0 表示成功；异常时为非 0 */
  code: number;
  stdout: string;
  stderr: string;
  durationMs: number;
}

/** 运行时自描述信息 */
export interface PyRuntimeInfo {
  /** 本次构建是否链接了 CPython 静态库 */
  available: boolean;
  /** 例如 3.12.10；未链接时为空 */
  version: string;
  /** 目标 ABI，例如 arm64-v8a */
  abi: string;
  /** 编译该原生库的时间戳 */
  buildTime: string;
}

/** 流编号：0=stdout，1=stderr，**2=调试事件（暂停快照 JSON）** */
export type PyStream = number;

/** 调试暂停事件（stream=2 的 payload，JSON 序列化后通过 setOutputCallback 送达） */
export interface PyDebugPause {
  /** 绝对路径 */
  file: string;
  /** 1-based 行号 */
  line: number;
  /** 所在函数名，模块级为 <module> */
  func: string;
  /** 局部变量快照 [名称, repr] */
  locals: string[][];
  /** 调用栈 [文件, 行号, 函数] * 最内层在前 */
  stack: string[][];
}

/** 是否链接了 CPython 静态库（运行时未编译时全部功能返回友好错误） */
export const isRuntimeAvailable: () => boolean;

/** 获取运行时自描述信息 */
export const getRuntimeInfo: () => PyRuntimeInfo;

/**
 * 初始化解释器（幂等）。重复调用只返回当前版本号。
 * @returns sys.version 字符串
 */
export const initialize: (options: PyInitOptions) => Promise<string>;

/** 注册实时输出回调；重复注册会替换旧回调 */
export const setOutputCallback: (callback: (stream: PyStream, text: string) => void) => void;

/** 执行一个 .py 文件（等价于 python file.py args...） */
export const runFile: (path: string, args: string[]) => Promise<PyRunResult>;

/** 执行一段源码 */
export const runCode: (code: string, filename: string) => Promise<PyRunResult>;

/** 在同一个解释器会话里执行 REPL 输入，返回执行结果文本（含 traceback） */
export const runRepl: (line: string) => Promise<string>;

/** 中断当前正在运行的脚本（Ctrl+C 等价） */
export const interrupt: () => void;

/** 执行 pip 命令，例如 ['install', 'requests'] */
export const pipInstall: (args: string[]) => Promise<PyRunResult>;

/** 是否正在执行脚本 */
export const isRunning: () => boolean;

/**
 * 以调试模式运行 .py 文件：命中断点或单步时暂停，暂停快照以 stream=2 推送。
 * @param path 目标文件绝对路径
 * @param args 传给 sys.argv 的额外参数
 * @param breakpointsJson {"<绝对路径>": [行号, ...]}
 * @param rootsJson 工程根目录列表（只跟踪这些目录内的帧）
 */
export const debugRun: (
  path: string,
  args: string[],
  breakpointsJson: string,
  rootsJson: string
) => Promise<PyRunResult>;

/** 下发调试指令：'continue' | 'step' | 'stop'（仅在暂停时有意义） */
export const debugCommand: (command: string) => void;

/** 当前是否处于暂停态 */
export const isDebugPaused: () => boolean;

/** 结束解释器（释放内存；一般只在退出时调用） */
export const finalize: () => Promise<void>;

// ─────────────────────────────────────────────────────────────────────────────
// 终端 PTY（真实 shell + 伪终端）—— 实现见 ../pty_watch.cpp
// ─────────────────────────────────────────────────────────────────────────────

/**
 * 打开一个伪终端并启动真 shell（默认 /bin/sh -i）。
 * @param shell 可选的 shell 路径
 * @returns master fd（>=0），失败返回 -1
 */
export const ptyOpen: (shell?: string) => number;

/** 向 PTY 写入（通常是用户输入 + '\n'），返回写入字节数 */
export const ptyWrite: (fd: number, data: string) => number;

/** 非阻塞读取 PTY 当前可读输出（无输出时返回空串）；注意按 UTF-8 边界处理 */
export const ptyRead: (fd: number) => string;

/** 通知内核窗口尺寸（TIOCSWINSZ），供 shell 做换行/全屏程序使用 */
export const ptyResize: (fd: number, cols: number, rows: number) => boolean;

/** 关闭 PTY（同时结束子 shell） */
export const ptyClose: (fd: number) => boolean;

/** PTY master fd 是否仍然有效 */
export const ptyAlive: (fd: number) => boolean;

// ─────────────────────────────────────────────────────────────────────────────
// 目录监听（inotify）—— Project 树增量刷新用
// ─────────────────────────────────────────────────────────────────────────────

/** 监听一个目录，返回 watch id（>=0），失败返回 -1 */
export const watchDir: (path: string) => number;

/**
 * 取走该 watch 上累积的事件（非阻塞）。
 * @returns JSON 数组字符串，元素形如 {"event":"create","name":"a.py","dir":false}
 */
export const pollDirWatch: (id: number) => string;

/** 取消监听 */
export const unwatchDir: (id: number) => boolean;

// ─────────────────────────────────────────────────────────────────────────────
// 无 PTY 环境下的「真 shell」兜底（popen('/bin/sh -c cmd')）与 PTY 诊断
// ─────────────────────────────────────────────────────────────────────────────

/** 在真 shell 里执行一条命令，返回合并后的 stdout/stderr（无 PTY 时终端工具窗用它） */
export const shellRun: (command: string) => string;

/** PTY 可用性诊断：{"ptmxAccess":bool,"ptmxErrno":n,"posixOpenptOk":bool,...} */
export const ptyDiagnose: () => string;
