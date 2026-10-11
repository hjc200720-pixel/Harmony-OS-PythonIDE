import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  isRuntimeAvailable,
  getRuntimeInfo,
  setOutputCallback,
  initialize,
  runFile,
  runCode,
  runRepl,
  pipInstall,
  interrupt,
  isRunning,
  finalize,
  debugRun,
  debugCommand,
  isDebugPaused
} from 'libpythonbridge.so';
import { DebugPause, RunResult, RuntimeStatus } from '../model/Models';
import { FileService } from './FileService';

/**
 * 注意：这里刻意不再重复声明 PyInitOptions / PyRuntimeInfo 等接口。
 * ArkTS 禁止结构化类型（arkts-no-structural-typing），本地重新声明的接口即使字段完全一致，
 * 也不能与 libpythonbridge.so 里声明的同名接口互相赋值。
 * 因此约定：入参一律「把对象字面量直接传给原生函数」由参数类型做上下文推断，
 * 出参一律「只读取字段」不整体赋值。
 */
export type OutputListener = (stream: number, text: string) => void;

/** 调试暂停事件监听器 */
export type DebugListener = (pause: DebugPause) => void;

/**
 * Python 运行时服务：负责
 *  1. 首次启动把随包的标准库 zip 从 rawfile 释放到沙箱（之后 zipimport 直接加载，无需解压）
 *  2. 驱动原生桥接完成解释器初始化
 *  3. 对外提供 运行文件 / 运行代码 / 交互式控制台 / pip 安装 / 中断 能力
 *  4. 把 Python 的实时输出分发给 UI
 */
export class PyRuntimeService {
  private static readonly STDLIB_RAWFILE: string = 'python/python312.zip';
  /** 随包 wheel 目录（pip 等）：解压进 site-packages 后 pip 才真正可用 */
  private static readonly WHEELS_RAWFILE_DIR: string = 'python/wheels';
  private static readonly READY_STAMP: string = 'runtime.ready';

  private static listeners: OutputListener[] = [];
  private static debugListeners: DebugListener[] = [];
  private static status: RuntimeStatus = new RuntimeStatus(false, '', '', false, '尚未初始化');
  private static bootstrapped: boolean = false;

  static getStatus(): RuntimeStatus {
    return PyRuntimeService.status;
  }

  static isReady(): boolean {
    return PyRuntimeService.status.ready;
  }

  static addOutputListener(listener: OutputListener): void {
    if (PyRuntimeService.listeners.indexOf(listener) < 0) {
      PyRuntimeService.listeners.push(listener);
    }
  }

  static removeOutputListener(listener: OutputListener): void {
    const index: number = PyRuntimeService.listeners.indexOf(listener);
    if (index >= 0) {
      PyRuntimeService.listeners.splice(index, 1);
    }
  }

  static addDebugListener(listener: DebugListener): void {
    if (PyRuntimeService.debugListeners.indexOf(listener) < 0) {
      PyRuntimeService.debugListeners.push(listener);
    }
  }

  static removeDebugListener(listener: DebugListener): void {
    const index: number = PyRuntimeService.debugListeners.indexOf(listener);
    if (index >= 0) {
      PyRuntimeService.debugListeners.splice(index, 1);
    }
  }

  /**
   * 事件分发：stream 2 是调试暂停快照（不进控制台），0/1 才是程序输出。
   */
  private static dispatch(stream: number, text: string): void {
    if (stream === 2) {
      PyRuntimeService.handleDebugEvent(text);
      return;
    }
    for (const listener of PyRuntimeService.listeners) {
      listener(stream, text);
    }
  }

  private static handleDebugEvent(payload: string): void {
    let pause: DebugPause;
    try {
      pause = JSON.parse(payload) as DebugPause;
    } catch (err) {
      PyRuntimeService.dispatch(1, `调试事件解析失败：${JSON.stringify(err)}\n`);
      return;
    }
    if (pause === undefined || pause === null) {
      return;
    }
    for (const listener of PyRuntimeService.debugListeners) {
      listener(pause);
    }
  }

  // ── 调试会话 ───────────────────────────────────────────────────────────

  /**
   * 以调试模式运行文件。命中断点/单步时原生侧会阻塞在 pause()，由 debugCommand 放行，
   * 因此这里返回的 Promise 要等整个脚本结束（或停止）才 resolve。
   */
  static async runDebug(path: string, args: string[], breakpointsJson: string,
                        rootsJson: string): Promise<RunResult> {
    if (!PyRuntimeService.status.ready) {
      return new RunResult(-1, '', PyRuntimeService.status.message, 0);
    }
    const started: number = Date.now();
    const result = await debugRun(path, args, breakpointsJson, rootsJson);
    return new RunResult(result.code, result.stdout, result.stderr, Date.now() - started);
  }

  /** 下发调试指令：continue / step / stop */
  static sendDebugCommand(command: string): void {
    try {
      debugCommand(command);
    } catch (err) {
      PyRuntimeService.dispatch(1, `下发调试指令失败：${JSON.stringify(err)}\n`);
    }
  }

  static isPaused(): boolean {
    try {
      return isDebugPaused();
    } catch (err) {
      return false;
    }
  }

  /**
   * 初始化运行时。幂等：重复调用直接返回上次结果。
   * 任何失败都会落到 status.message 上，界面据此给用户可执行的指引。
   */
  static async bootstrap(context: common.UIAbilityContext): Promise<RuntimeStatus> {
    if (PyRuntimeService.bootstrapped) {
      return PyRuntimeService.status;
    }

    let nativeAvailable: boolean = false;
    let abi: string = '';
    let nativeVersion: string = '';
    try {
      nativeAvailable = isRuntimeAvailable();
      const raw = getRuntimeInfo();
      abi = raw.abi;
      nativeVersion = raw.version;
    } catch (err) {
      nativeAvailable = false;
      PyRuntimeService.status = new RuntimeStatus(
        false, '', '', false,
        `原生模块 libpythonbridge.so 加载失败：${JSON.stringify(err)}`);
      PyRuntimeService.bootstrapped = true;
      return PyRuntimeService.status;
    }

    // 沙箱目录准备（无论运行时是否就绪都要做，文件管理功能不依赖 Python）
    FileService.ensureDir(FileService.runtimeDir());
    FileService.ensureDir(FileService.sitePackagesDir());
    FileService.ensureDir(FileService.wheelsDir());
    FileService.ensureDir(FileService.projectRoot());

    if (!nativeAvailable) {
      PyRuntimeService.status = new RuntimeStatus(
        false, '', abi, false,
        '本次构建未链接 CPython 运行时（libpython3.12.a）。\n' +
        '请在开发机上执行：\n' +
        '    pnpm 无关，直接运行 → powershell -File scripts/build-cpython-ohos.ps1\n' +
        '编译完成后重新构建 HAP，IDE 即可执行 Python。\n' +
        '文件管理、编辑器、语法高亮等功能现在已可正常使用。');
      PyRuntimeService.bootstrapped = true;
      return PyRuntimeService.status;
    }

    // 标准库：rawfile → 沙箱（一次性）
    let stdlibReady: boolean = false;
    const zipPath: string = FileService.stdlibZipPath();
    try {
      PyRuntimeService.releaseStdlibFromRawfile(context, zipPath);
      stdlibReady = FileService.exists(zipPath) && FileService.sizeOf(zipPath) > 0;
    } catch (err) {
      stdlibReady = false;
      PyRuntimeService.status = new RuntimeStatus(
        false, nativeVersion, abi, false,
        `释放标准库失败：${JSON.stringify(err)}`);
      PyRuntimeService.bootstrapped = true;
      return PyRuntimeService.status;
    }

    if (!stdlibReady) {
      PyRuntimeService.status = new RuntimeStatus(
        false, nativeVersion, abi, false,
        '未找到随包的标准库资源 entry/src/main/resources/rawfile/python/python312.zip。\n' +
        '请先执行 scripts/build-cpython-ohos.ps1，它会交叉编译出 libpython3.12.a 并生成该 zip。');
      PyRuntimeService.bootstrapped = true;
      return PyRuntimeService.status;
    }

    // 释放随包 wheel（pip）。解释器启动时会把它们解压进 site-packages，
    // 之后「pip install --no-index --find-links <本地目录> <包名>」才真正可用。
    PyRuntimeService.releaseWheelsFromRawfile(context);

    // 先挂输出回调，保证初始化期间的信息也能出现在控制台
    setOutputCallback((stream: number, text: string) => {
      PyRuntimeService.dispatch(stream, text);
    });

    const projectRoot: string = FileService.projectRoot();

    try {
      // 内联字面量，由原生 d.ts 的参数类型做上下文推断（避免结构化类型限制）
      const version: string = await initialize({
        filesDir: context.filesDir,
        stdlibZip: zipPath,
        sitePackages: FileService.sitePackagesDir(),
        home: FileService.runtimeDir(),
        argv: ['python'],
        extraPaths: [projectRoot]
      });
      PyRuntimeService.status = new RuntimeStatus(true, version, abi, true, '运行时已就绪');
    } catch (err) {
      PyRuntimeService.status = new RuntimeStatus(
        false, nativeVersion, abi, true, `解释器初始化失败：${JSON.stringify(err)}`);
    }
    PyRuntimeService.bootstrapped = true;
    return PyRuntimeService.status;
  }

  /** 列出 rawfile 内容，用于把"到底缺了什么"写进错误信息 */
  private static rawfileListing(context: common.UIAbilityContext): string {
    let py: string = '?';
    let wheels: string = '?';
    try {
      py = context.resourceManager.getRawFileListSync('python').join(', ');
    } catch (err) {
      py = `列出失败(${JSON.stringify(err)})`;
    }
    try {
      wheels = context.resourceManager.getRawFileListSync('python/wheels').join(', ');
    } catch (err) {
      wheels = `列出失败(${JSON.stringify(err)})`;
    }
    return `rawfile/python=[${py}] rawfile/python/wheels=[${wheels}]`;
  }

  /** 整块写入，返回实际写入字节数 */
  private static writeWholeBuffer(destPath: string, buffer: ArrayBuffer): number {
    const file = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      return fs.writeSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  /** 校验沙箱里的 zip 是不是真 zip（前两字节 "PK"）——半截/错位写入会被这一步拦住 */
  private static looksLikeZip(path: string): boolean {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const head: ArrayBuffer = new ArrayBuffer(2);
        const got: number = fs.readSync(file.fd, head);
        if (got < 2) {
          return false;
        }
        const view = new Uint8Array(head);
        return view[0] === 0x50 && view[1] === 0x4B;
      } finally {
        fs.closeSync(file);
      }
    } catch (err) {
      return false;
    }
  }

  /** 走 raw fd 读一次再写；useOffset 决定是否加 descriptor 的 offset（不同版本语义不同，两种都试） */
  private static readRawByFd(context: common.UIAbilityContext, destPath: string,
                            useOffset: boolean): number {
    const rawFd = context.resourceManager.getRawFdSync(PyRuntimeService.STDLIB_RAWFILE);
    const buffer: ArrayBuffer = new ArrayBuffer(rawFd.length);
    const got: number = useOffset
      ? fs.readSync(rawFd.fd, buffer, { offset: rawFd.offset, length: rawFd.length })
      : fs.readSync(rawFd.fd, buffer, { length: rawFd.length });
    try {
      context.resourceManager.closeRawFdSync(PyRuntimeService.STDLIB_RAWFILE);
    } catch (closeErr) {
      // 关不掉不影响结果
    }
    if (got <= 0) {
      return 0;
    }
    return PyRuntimeService.writeWholeBuffer(destPath, buffer);
  }

  /**
   * 把随包标准库释放到沙箱。
   *
   * 真机踩坑记录：python312.zip 有 2.5 MB。早期实现用 getRawFileContentSync 一次性读进
   * ArrayBuffer 再整块写，设备上会失败——UI 上看到的就是"释放标准库失败"。
   * 现在按下面的顺序来，并且**每一步都要校验**：
   *   1) 已存在且长度与 rawfile 一致 → 直接用（幂等）
   *   2) getRawFileContentSync 整块读写
   *   3) 失败或结果不完整 → getRawFdSync + readSync（先带 offset 试，再不带 offset 试）
   * 最后强制校验"长度一致 + 前两字节是 PK"。任何一步不满足都抛错，并把 rawfile 内容、
   * 目标路径、各步原始错误一起带出去——绝不留下半截 zip（zipimport 撞上坏 zip 会直接崩）。
   */
  private static releaseStdlibFromRawfile(context: common.UIAbilityContext, zipPath: string): void {
    const rm = context.resourceManager;
    let expected: number = 0;
    try {
      expected = rm.getRawFdSync(PyRuntimeService.STDLIB_RAWFILE).length;
      try {
        rm.closeRawFdSync(PyRuntimeService.STDLIB_RAWFILE);
      } catch (closeErr) {
      }
      if (expected > 0 && FileService.exists(zipPath) && FileService.sizeOf(zipPath) === expected
        && PyRuntimeService.looksLikeZip(zipPath)) {
        return; // 已正确释放
      }
    } catch (err) {
      expected = 0;
    }
    if (FileService.exists(zipPath)) {
      try {
        FileService.remove(zipPath);
      } catch (err) {
        // 删不掉也没关系，后面会 TRUNC 覆盖
      }
    }

    let wholeError: string = '';
    let written: number = 0;
    try {
      const data: Uint8Array = rm.getRawFileContentSync(PyRuntimeService.STDLIB_RAWFILE);
      const buffer: ArrayBuffer =
        data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) as ArrayBuffer;
      written = PyRuntimeService.writeWholeBuffer(zipPath, buffer);
      if (expected <= 0) {
        expected = data.byteLength;
      }
    } catch (err) {
      wholeError = JSON.stringify(err);
      written = 0;
    }

    if (written <= 0 || !PyRuntimeService.looksLikeZip(zipPath)) {
      let fdError: string = '';
      written = 0;
      // 先按 descriptor 的 offset 读（多数实现是"绝对偏移"），不行再按纯顺序读
      for (const useOffset of [true, false]) {
        try {
          written = PyRuntimeService.readRawByFd(context, zipPath, useOffset);
          if (written > 0 && PyRuntimeService.looksLikeZip(zipPath)) {
            expected = written;
            break;
          }
        } catch (err) {
          fdError = `offset=${useOffset}:${JSON.stringify(err)}`;
          written = 0;
        }
      }
      if (written <= 0 || !PyRuntimeService.looksLikeZip(zipPath)) {
        throw new Error(`释放标准库失败。整块读写=${wholeError.length > 0 ? wholeError : '未成功'}；`
          + `fd 读取=${fdError.length > 0 ? fdError : '未成功'}；目标=${zipPath}；`
          + `已写入=${FileService.sizeOf(zipPath)} 字节；${PyRuntimeService.rawfileListing(context)}`);
      }
    }

    const actual: number = FileService.sizeOf(zipPath);
    if (expected > 0 && actual !== expected) {
      throw new Error(`标准库写入不完整：期望 ${expected} 字节，实际 ${actual} 字节；`
        + `整块读写错误=${wholeError.length > 0 ? wholeError : '无'}；`
        + `${PyRuntimeService.rawfileListing(context)}`);
    }
    FileService.writeText(`${FileService.runtimeDir()}/${PyRuntimeService.READY_STAMP}`,
      `released=${actual}\n`);
  }

  /**
   * 手动重置运行时（"重新初始化"入口用它）：可顺带删掉已释放的标准库与 wheel，
   * 强制下次 bootstrap 重新从 rawfile 释放一遍。真机上"释放失败"后不必重装应用。
   */
  static resetBootstrap(deleteReleasedAssets: boolean): void {
    if (deleteReleasedAssets) {
      try {
        const zipPath: string = FileService.stdlibZipPath();
        if (FileService.exists(zipPath)) {
          FileService.remove(zipPath);
        }
      } catch (err) {
      }
      try {
        const wheels: string = FileService.wheelsDir();
        if (FileService.isDir(wheels)) {
          for (const name of fs.listFileSync(wheels)) {
            FileService.remove(`${wheels}/${name}`);
          }
        }
      } catch (err) {
      }
    }
    PyRuntimeService.bootstrapped = false;
    PyRuntimeService.status = new RuntimeStatus(false, '', '', false, '正在重新初始化运行时…');
  }

  /**
   * 把随包的 wheel 从 rawfile 释放到沙箱（例如 pip）。
   * 没有 wheels 目录时静默跳过：这不是错误，只是没有随包 wheel。
   */
  private static releaseWheelsFromRawfile(context: common.UIAbilityContext): void {
    const target: string = FileService.wheelsDir();
    FileService.ensureDir(target);
    let names: string[] = [];
    try {
      names = context.resourceManager.getRawFileListSync(PyRuntimeService.WHEELS_RAWFILE_DIR);
    } catch (err) {
      return;
    }
    for (const name of names) {
      if (!name.endsWith('.whl')) {
        continue;
      }
      const dest: string = `${target}/${name}`;
      if (FileService.exists(dest) && FileService.sizeOf(dest) > 1024) {
        continue;
      }
      try {
        const data: Uint8Array = context.resourceManager
          .getRawFileContentSync(`${PyRuntimeService.WHEELS_RAWFILE_DIR}/${name}`);
        const buffer: ArrayBuffer =
          data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) as ArrayBuffer;
        const file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        try {
          fs.writeSync(file.fd, buffer);
        } finally {
          fs.closeSync(file);
        }
      } catch (err) {
        PyRuntimeService.dispatch(1, `释放 wheel ${name} 失败：${JSON.stringify(err)}\n`);
      }
    }
  }

  /** 运行沙箱内的 .py 文件 */
  static async run(path: string, args: string[] = []): Promise<RunResult> {
    if (!PyRuntimeService.status.ready) {
      return new RunResult(-1, '', PyRuntimeService.status.message, 0);
    }
    const started: number = Date.now();
    const result = await runFile(path, args);
    return new RunResult(result.code, result.stdout, result.stderr, Date.now() - started);
  }

  /** 运行一段源码（用于“运行选中代码”“示例片段”等） */
  static async runSource(code: string, filename: string = '<ide>'): Promise<RunResult> {
    if (!PyRuntimeService.status.ready) {
      return new RunResult(-1, '', PyRuntimeService.status.message, 0);
    }
    const started: number = Date.now();
    const result = await runCode(code, filename);
    return new RunResult(result.code, result.stdout, result.stderr, Date.now() - started);
  }

  /** 交互式控制台：单行输入，变量在同一会话内保持 */
  static async repl(line: string): Promise<string> {
    if (!PyRuntimeService.status.ready) {
      return PyRuntimeService.status.message;
    }
    return await runRepl(line);
  }

  /** 执行 pip 命令，例如 ['install', 'requests'] */
  static async pip(args: string[]): Promise<RunResult> {
    if (!PyRuntimeService.status.ready) {
      return new RunResult(-1, '', PyRuntimeService.status.message, 0);
    }
    const started: number = Date.now();
    const result = await pipInstall(args);
    return new RunResult(result.code, result.stdout, result.stderr, Date.now() - started);
  }

  static isBusy(): boolean {
    try {
      return isRunning();
    } catch (err) {
      return false;
    }
  }

  static stop(): void {
    try {
      interrupt();
    } catch (err) {
      // 忽略：未初始化时中断无意义
    }
  }

  static async shutdown(): Promise<void> {
    try {
      await finalize();
    } catch (err) {
      // 进程即将退出，忽略
    }
  }
}
