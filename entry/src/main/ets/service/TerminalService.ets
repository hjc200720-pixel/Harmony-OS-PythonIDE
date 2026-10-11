/**
 * TerminalService —— 终端工具窗的 native 后端（PTY + 目录监听）。
 *
 * 实现在 entry/src/main/cpp/pty_watch.cpp：
 *  - ptyOpen/ptyWrite/ptyRead/ptyResize/ptyClose：真 shell（/bin/sh -i）跑在伪终端里，
 *    输入输出都是非阻塞的，UI 线程只做 150ms 轮询。
 *  - watchDir/pollDirWatch/unwatchDir：inotify 目录监听，工程树增量刷新用。
 *
 * 依据：PyCharm 的 Terminal 工具窗就是「真正的外部 shell + 伪终端」，
 * 不是模拟命令回显；Project 树的自动刷新同样来自文件系统事件。
 */
import {
  ptyOpen,
  ptyWrite,
  ptyRead,
  ptyResize,
  ptyClose,
  watchDir,
  pollDirWatch,
  unwatchDir,
  shellRun,
  ptyDiagnose
} from 'libpythonbridge.so';
import { FileService } from './FileService';

/** 终端 PTY（进程内单例：一个工具窗一个 shell） */
export class TerminalService {
  private static instance: TerminalService | undefined = undefined;
  private fd: number = -1;
  private timer: number = -1;
  private sink: (text: string) => void = (text: string) => {
  };

  static shared(): TerminalService {
    if (TerminalService.instance === undefined) {
      TerminalService.instance = new TerminalService();
    }
    return TerminalService.instance;
  }

  /** 打开 PTY（幂等）。onText 在 UI 线程被调用，参数是本次读到的输出 */
  start(onText: (text: string) => void): boolean {
    this.sink = onText;
    if (this.fd >= 0) {
      return true;
    }
    try {
      this.fd = ptyOpen('/bin/sh');
    } catch (err) {
      this.fd = -1;
      FileService.log(`terminal ptyOpen FAILED err=${JSON.stringify(err)}`);
    }
    FileService.log(`terminal ptyOpen fd=${this.fd}`);
    if (this.fd < 0) {
      return false;
    }
    if (this.timer < 0) {
      this.timer = setInterval(() => {
        this.drain();
      }, 150);
    }
    return true;
  }

  /** 当前是否有活着的 PTY shell */
  active(): boolean {
    return this.fd >= 0;
  }

  /**
   * 无 PTY 时的行式 shell（popen('/bin/sh -c cmd')）：
   * 鸿蒙应用沙箱不给 /dev/ptmx 时，命令依然在真 shell 里执行。
   */
  runOnce(command: string): string {
    try {
      return shellRun(command);
    } catch (err) {
      FileService.log(`terminal shellRun FAILED err=${JSON.stringify(err)}`);
      return '';
    }
  }

  /** PTY 可用性诊断（ptmx 权限 / errno），供状态栏或日志提示 */
  diagnose(): string {
    try {
      return ptyDiagnose();
    } catch (err) {
      return `{"error":"${JSON.stringify(err)}"}`;
    }
  }

  /** 发送一条命令（自动补换行），成功返回 true */
  send(command: string): boolean {
    if (this.fd < 0) {
      return false;
    }
    try {
      ptyWrite(this.fd, `${command}\n`);
      return true;
    } catch (err) {
      FileService.log(`terminal ptyWrite FAILED err=${JSON.stringify(err)}`);
      return false;
    }
  }

  /** 通知内核终端尺寸（shell/全屏程序换行用） */
  resize(cols: number, rows: number): void {
    if (this.fd < 0) {
      return;
    }
    try {
      ptyResize(this.fd, cols, rows);
    } catch (err) {
      FileService.log(`terminal ptyResize FAILED err=${JSON.stringify(err)}`);
    }
  }

  /** 关闭 shell（面板隐藏/退出时调用） */
  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    if (this.fd >= 0) {
      try {
        ptyClose(this.fd);
      } catch (err) {
        FileService.log(`terminal ptyClose FAILED err=${JSON.stringify(err)}`);
      }
      this.fd = -1;
    }
  }

  private drain(): void {
    if (this.fd < 0) {
      return;
    }
    try {
      const text: string = ptyRead(this.fd);
      if (text.length > 0) {
        this.sink(text);
      }
    } catch (err) {
      FileService.log(`terminal ptyRead FAILED err=${JSON.stringify(err)}`);
    }
  }
}

/** 目录监听（inotify）：替代「定时全量扫描」，事件驱动刷新工程树 */
export class DirWatcher {
  private watchId: number = -1;
  private timer: number = -1;
  private dir: string = '';

  /** 开始监听目录；onEvents 收到的是 native 侧给出的 JSON 事件数组 */
  start(dir: string, onEvents: (json: string) => void): boolean {
    this.stop();
    this.dir = dir;
    if (dir.length === 0) {
      return false;
    }
    try {
      this.watchId = watchDir(dir);
    } catch (err) {
      this.watchId = -1;
      FileService.log(`dirwatch watchDir FAILED err=${JSON.stringify(err)}`);
    }
    if (this.watchId < 0) {
      return false;
    }
    this.timer = setInterval(() => {
      try {
        const json: string = pollDirWatch(this.watchId);
        if (json.length > 2) {
          onEvents(json);
        }
      } catch (err) {
        FileService.log(`dirwatch poll FAILED err=${JSON.stringify(err)}`);
      }
    }, 400);
    return true;
  }

  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    if (this.watchId >= 0) {
      try {
        unwatchDir(this.watchId);
      } catch (err) {
        FileService.log(`dirwatch unwatch FAILED err=${JSON.stringify(err)}`);
      }
      this.watchId = -1;
    }
  }

  watchedDir(): string {
    return this.dir;
  }
}
