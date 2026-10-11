import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { FileNode } from '../model/Models';

/**
 * 沙箱文件服务。
 *
 * 设计取舍：v1 的项目根目录固定落在应用沙箱 `context.filesDir/PyProjects`，
 * 这是鸿蒙上唯一**无需任何权限、且能被原生 CPython 用普通 POSIX 接口直接读写**的位置，
 * 因此 IDE 的文件树、编辑器、Python 运行时三者的路径完全一致，不存在映射层。
 * 需要把结果交付给用户时，用系统文件选择器导出（exportFile / importFiles）。
 */
export class FileService {
  static readonly PROJECT_DIR_NAME: string = 'PyProjects';

  private static ctx: common.UIAbilityContext | undefined = undefined;

  /**
   * 统一诊断日志：`hdc shell hilog | grep PyIDE` 可见。
   * 文件系统是这套 IDE 的命门（项目树/编辑器/解释器共用同一批路径），
   * 出问题时必须能从设备日志上直接看到是哪一步失败，而不是靠猜。
   */
  static log(message: string): void {
    hilog.info(0x1234, 'PyIDE', '%{public}s', message);
  }

  /** 复制文本到系统剪贴板（失败不影响其它功能）：编辑菜单的「复制路径」用它 */
  /**
   * 异步读取系统剪贴板文本（Diff: Compare with Clipboard 用）。
   * 注意：HarmonyOS 上 getDataSync() 会因隐私限制返回空；必须用异步 getData()，
   * 系统会弹出"允许粘贴"授权，用户同意后才拿到内容。
   */
  static readClipboardAsync(onDone: (text: string) => void): void {
    try {
      pasteboard.getSystemPasteboard().getData((err: BusinessError, data: pasteboard.PasteData) => {
        if (err) {
          FileService.log(`readClipboard err=${err.code}`);
          onDone('');
          return;
        }
        if (data === undefined) {
          onDone('');
          return;
        }
        try {
          onDone(data.getPrimaryText());
        } catch (e2) {
          onDone('');
        }
      });
    } catch (e) {
      FileService.log('readClipboard threw');
      onDone('');
    }
  }

  static copyToClipboard(text: string): boolean {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setDataSync(data);
      return true;
    } catch (err) {
      FileService.log(`clipboard FAILED err=${JSON.stringify(err)}`);
      return false;
    }
  }

  /** 写入二进制（导出画布 PNG 用）*/
  static writeBinary(path: string, data: Uint8Array): void {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, data.buffer as ArrayBuffer);
      fs.closeSync(file);
    } catch (err) {
      FileService.log(`writeBinary FAILED ${path}`);
    }
  }

  static attach(context: common.UIAbilityContext): void {
    FileService.ctx = context;
    FileService.log(`attach filesDir=${context.filesDir} cacheDir=${context.cacheDir}`);
  }

  static context(): common.UIAbilityContext {
    if (FileService.ctx === undefined) {
      throw new Error('FileService.attach(context) 尚未调用');
    }
    return FileService.ctx;
  }

  /** 项目根目录：<filesDir>/PyProjects */
  static projectRoot(): string {
    return `${FileService.context().filesDir}/${FileService.PROJECT_DIR_NAME}`;
  }

  /** 运行时资源目录：<filesDir>/python */
  static runtimeDir(): string {
    return `${FileService.context().filesDir}/python`;
  }

  /** 第三方包目录：<filesDir>/site-packages */
  static sitePackagesDir(): string {
    return `${FileService.context().filesDir}/site-packages`;
  }

  static stdlibZipPath(): string {
    return `${FileService.context().filesDir}/python312.zip`;
  }

  /** 随包 wheel 目录：<filesDir>/python/wheels（解释器启动时会解压进 site-packages） */
  static wheelsDir(): string {
    return `${FileService.runtimeDir()}/wheels`;
  }

  /**
   * 路径是否存在。
   *
   * ⚠️ 真机教训（这是本工程最严重的一个 bug）：**不能用 `fs.accessSync` 判断存在性**。
   * 在鸿蒙模拟器/真机上实测 `accessSync` 对**不存在**的路径也不抛错，于是 exists() 恒为 true：
   *   → `ensureDir()` 认为目录已存在，从不 mkdir；
   *   → 项目目录树从未被创建（listFileSync 报 13900002 = ENOENT）；
   *   → 文件树空白、文件读不出来（编辑区只剩欢迎页）、pip 的 wheels 目录也没建出来。
   * `statSync` 对不存在的路径会正常抛错（13900002），所以以它为准。
   */
  static exists(path: string): boolean {
    try {
      fs.statSync(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  static isDir(path: string): boolean {
    try {
      return fs.statSync(path).isDirectory();
    } catch (e) {
      FileService.log(`isDir FAILED ${path} err=${JSON.stringify(e)}`);
      return false;
    }
  }

  /**
   * 判断条目是不是目录。
   * 真机教训：某些设备/沙盒路径上 `statSync().isDirectory()` 会失败或谎报（实测
   * 示例工程目录被判成"不是目录"，但 main.py 明明在里面），所以这里加一条兜底：
   * stat 说不是目录时，再试一次列目录——列得出来就一定是目录。
   */
  static isDirRobust(path: string): boolean {
    try {
      if (fs.statSync(path).isDirectory()) {
        return true;
      }
    } catch (e) {
      FileService.log(`stat ${path} err=${JSON.stringify(e)}`);
    }
    try {
      fs.listFileSync(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  static ensureDir(path: string): void {
    try {
      if (!FileService.exists(path)) {
        fs.mkdirSync(path, true);
        FileService.log(`mkdir ${path}`);
      }
    } catch (err) {
      FileService.log(`mkdir FAILED ${path} err=${JSON.stringify(err)}`);
      throw new Error(`mkdir failed: ${path}`);
    }
  }

  static sizeOf(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (e) {
      return 0;
    }
  }

  static readText(path: string): string {
    try {
      const text: string = fs.readTextSync(path);
      FileService.log(`read ${path} chars=${text.length}`);
      return text;
    } catch (err) {
      FileService.log(`readTextSync FAILED ${path} err=${JSON.stringify(err)}; trying fd read`);
    }
    // 兜底：手动 open + read 再解码。
    // 真机上遇到过 readTextSync 失败（与 statSync 同类问题）但 fd 读正常的情况。
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const size: number = fs.statSync(path).size;
      const buffer: ArrayBuffer = new ArrayBuffer(size > 0 ? size : 1);
      const read: number = fs.readSync(file.fd, buffer);
      const decoder = util.TextDecoder.create('utf-8');
      const text: string = decoder.decodeToString(new Uint8Array(buffer.slice(0, read)));
      FileService.log(`read(fd) ${path} bytes=${read} chars=${text.length}`);
      return text;
    } finally {
      fs.closeSync(file);
    }
  }

  static writeText(path: string, content: string): void {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const written: number = fs.writeSync(file.fd, content);
        FileService.log(`write ${path} bytes=${written}/${content.length}`);
      } finally {
        fs.closeSync(file);
      }
    } catch (err) {
      FileService.log(`write FAILED ${path} err=${JSON.stringify(err)}`);
      throw new Error(`write failed: ${path}`);
    }
  }

  static createFile(path: string, content: string): void {
    FileService.writeText(path, content);
  }

  static createDir(path: string): void {
    FileService.ensureDir(path);
  }

  static rename(oldPath: string, newPath: string): void {
    fs.renameSync(oldPath, newPath);
  }

  static remove(path: string): void {
    if (FileService.isDir(path)) {
      fs.rmdirSync(path);
    } else {
      fs.unlinkSync(path);
    }
  }

  static parentOf(path: string): string {
    const idx = path.lastIndexOf('/');
    return idx > 0 ? path.substring(0, idx) : path;
  }

  static baseName(path: string): string {
    const idx = path.lastIndexOf('/');
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

  /** 读取一层目录（不递归），目录在前、同类按名称不区分大小写排序 */
  static listDir(dir: string, depth: number): FileNode[] {
    const result: FileNode[] = [];
    // 不做 isDir() 预判：直接尝试列目录。列不出来就返回空表。
    let names: string[] = [];
    try {
      names = fs.listFileSync(dir);
    } catch (e) {
      FileService.log(`listDir FAILED ${dir} err=${JSON.stringify(e)}`);
      return result;
    }
    FileService.log(`listDir ${dir} -> ${names.length} entries`);
    const dirs: FileNode[] = [];
    const files: FileNode[] = [];
    for (const name of names) {
      // 跳过隐藏文件与构建产物，避免文件树噪音
      if (name.startsWith('.')) {
        continue;
      }
      const full: string = `${dir}/${name}`;
      const isDirectory: boolean = FileService.isDirRobust(full);
      const node = new FileNode(name, full, isDirectory, depth);
      if (isDirectory) {
        dirs.push(node);
      } else {
        files.push(node);
      }
    }
    dirs.sort((a: FileNode, b: FileNode) => a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1);
    files.sort((a: FileNode, b: FileNode) => a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1);
    for (const d of dirs) {
      result.push(d);
    }
    for (const f of files) {
      result.push(f);
    }
    return result;
  }

  /** 递归加载整棵子树（供展开目录时使用） */
  static loadChildren(node: FileNode): void {
    node.children = FileService.listDir(node.path, node.depth + 1);
    for (const child of node.children) {
      child.depth = node.depth + 1;
    }
    node.loaded = true;
  }

  /** 按展开状态把树扁平化为「可见行」，供 List 直接顺序渲染（避免 UI 层递归） */
  static flatten(nodes: FileNode[], out: FileNode[]): void {
    for (const node of nodes) {
      out.push(node);
      if (node.isDir && node.expanded && node.children.length > 0) {
        FileService.flatten(node.children, out);
      }
    }
  }

  /** 不区分大小写的名称过滤（作用于扁平化结果时保留命中目录的祖先链由调用方处理） */
  static matchesFilter(node: FileNode, filter: string): boolean {
    if (filter.length === 0) {
      return true;
    }
    return node.name.toLowerCase().includes(filter.toLowerCase());
  }

  /** 生成不与现有文件冲突的新文件路径 */
  static uniquePath(dir: string, baseName: string, suffix: string = ''): string {
    let candidate: string = `${dir}/${baseName}${suffix}`;
    let index: number = 1;
    while (FileService.exists(candidate)) {
      candidate = `${dir}/${baseName}${index}${suffix}`;
      index++;
    }
    return candidate;
  }

  /** 导入外部文件到项目目录（系统文件选择器，无需任何权限） */
  static async importFiles(context: common.UIAbilityContext, targetDir: string): Promise<string[]> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 50;
    options.fileSuffixFilters = ['.py', '.txt', '.md', '.json', '.csv', '.ini', '.cfg', '.toml', '.yaml', '.yml', '.whl'];
    const viewPicker = new picker.DocumentViewPicker(context);
    const uris: string[] = await viewPicker.select(options);
    const created: string[] = [];
    for (const uri of uris) {
      // picker 返回的是 file://docs/... 形式的 URI，取最后一段即文件名；
      // 当前 SDK 的 fileUri 只提供 getUriFromPath()，没有 getUriInfo()，故不依赖它。
      const name: string = FileService.baseName(uri);
      const dest: string = FileService.uniquePath(targetDir, name);
      fs.copyFileSync(uri, dest);
      created.push(dest);
    }
    return created;
  }

  /**
   * 导入项目图标（PyCharm 的 WelcomeScreen.ChangeProjectIcon / 设置自定义项目图标…）。
   * 只允许 SVG / PNG；按 IntelliJ 约定落到 <项目>/.idea/icon.svg（或 icon.png）。
   * 返回落点绝对路径；用户取消返回空串。
   */
  static async importIcon(context: common.UIAbilityContext, projectRoot: string): Promise<string> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.svg', '.png'];
    const viewPicker = new picker.DocumentViewPicker(context);
    const uris: string[] = await viewPicker.select(options);
    if (uris.length === 0) {
      return '';
    }
    const uri: string = uris[0];
    const rawName: string = FileService.baseName(uri);
    const lower: string = rawName.toLowerCase();
    if (!(lower.endsWith('.svg') || lower.endsWith('.png'))) {
      return '';
    }
    const dir: string = `${projectRoot}/.idea`;
    FileService.ensureDir(dir);
    const dest: string = `${dir}/${lower.endsWith('.svg') ? 'icon.svg' : 'icon.png'}`;
    fs.copyFileSync(uri, dest);
    FileService.log(`importIcon ${uri} -> ${dest}`);
    return dest;
  }

  /** 把沙箱内的文件导出到用户可见位置（系统保存对话框） */
  static async exportFile(context: common.UIAbilityContext, srcPath: string): Promise<string> {
    const options = new picker.DocumentSaveOptions();
    const name: string = FileService.baseName(srcPath);
    options.newFileNames = [name];
    const dot: number = name.lastIndexOf('.');
    options.fileSuffixChoices = dot > 0 ? [name.substring(dot)] : ['.txt'];
    const viewPicker = new picker.DocumentViewPicker(context);
    const uris: string[] = await viewPicker.save(options);
    if (uris.length === 0) {
      return '';
    }
    fs.copyFileSync(srcPath, uris[0]);
    return uris[0];
  }

  /** 在沙箱项目目录里新建一个可直接运行的示例工程 */
  static createSampleProject(root: string): void {
    FileService.ensureDir(root);
    const mainPy: string = `${root}/main.py`;
    // 示例工程升级：早期版本的 main.py 没有 import utils（缺少跨文件引用样本），发现即重写
    if (FileService.exists(mainPy) && FileService.readText(mainPy).indexOf('import utils') < 0) {
      FileService.writeText(mainPy, '');
    }
    if (!FileService.exists(mainPy) || FileService.readText(mainPy).length === 0) {
      FileService.writeText(mainPy, [
        '"""鸿蒙 Python IDE 示例工程。"""',
        'import sys',
        'import platform',
        '',
        'import utils',
        '',
        '',
        'def greet(name: str) -> str:',
        '    return f"你好, {name}!"',
        '',
        '',
        'def main() -> None:',
        '    print(greet("鸿蒙"))',
        '    print("Python :", sys.version.split()[0])',
        '    print("平台   :", sys.platform, platform.machine())',
        '    print("演示计算:", sum(i * i for i in range(1, 11)))',
        '    print("斐波那契:", utils.fib(8))',
        '',
        '',
        'if __name__ == "__main__":',
        '    main()',
        ''
      ].join('\n'));
    }
    const modelsPy: string = `${root}/demo_pkg/models.py`;
    if (!FileService.exists(modelsPy)) {
      FileService.writeText(modelsPy, [
        '"""示例类层次：便于演示继承层级 / 查找用法 / 结构视图。"""',
        '',
        '',
        'class Animal:',
        '    """所有动物的基类。"""',
        '',
        '    def __init__(self, name: str) -> None:',
        '        self.name = name',
        '',
        '    def speak(self) -> str:',
        '        return "..."',
        '',
        '',
        'class Dog(Animal):',
        '    """狗：重写 speak，并新增 fetch。"""',
        '',
        '    def speak(self) -> str:',
        '        return f"{self.name}: 汪汪"',
        '',
        '    def fetch(self) -> str:',
        '        return f"{self.name} 把球叼回来了"',
        '',
        '',
        'class Cat(Animal):',
        '    def speak(self) -> str:',
        '        return f"{self.name}: 喵"',
        ''
      ].join('\n'));
    }
    const utilsPy: string = `${root}/utils.py`;
    if (!FileService.exists(utilsPy)) {
      FileService.writeText(utilsPy, [
        '"""常用工具函数，方便在 main.py 里 import utils 复用。"""',
        '',
        '',
        'def fib(n: int) -> list:',
        '    """返回前 n 个斐波那契数。"""',
        '    seq = [0, 1]',
        '    while len(seq) < n:',
        '        seq.append(seq[-1] + seq[-2])',
        '    return seq[:n]',
        ''
      ].join('\n'));
    }
    const readme: string = `${root}/README.md`;
    if (!FileService.exists(readme)) {
      FileService.writeText(readme, [
        '# 示例工程',
        '',
        '在左侧工程树双击 `main.py`，点击工具栏 ▶ 运行。',
        '',
        '- `main.py`  入口示例',
        '- `utils.py` 可 import 的模块',
        '',
        '> 该目录位于应用沙箱内，Python 运行时可原生读写，重启不丢失。',
        ''
      ].join('\n'));
    }
    // 一个真实的包目录 demo_pkg/core：既能 import，也用来体现 PyCharm 的
    // 「压缩中间目录」（Compact Middle Packages，默认开启）—— 该链会显示成一行 demo_pkg/core
    // writeText 不会自动建父目录，先 ensureDir（否则 err=13900002 无此文件）
    FileService.ensureDir(`${root}/demo_pkg`);
    FileService.ensureDir(`${root}/demo_pkg/core`);
    const pkgInit: string = `${root}/demo_pkg/__init__.py`;
    if (!FileService.exists(pkgInit)) {
      FileService.writeText(pkgInit, [
        '"""示例包：demo_pkg。"""',
        '',
        'from .core import engine',
        ''
      ].join('\n'));
    }
    const coreInit: string = `${root}/demo_pkg/core/__init__.py`;
    if (!FileService.exists(coreInit)) {
      FileService.writeText(coreInit, [
        '"""demo_pkg.core 子包。"""',
        ''
      ].join('\n'));
    }
    const enginePy: string = `${root}/demo_pkg/core/engine.py`;
    if (!FileService.exists(enginePy)) {
      FileService.writeText(enginePy, [
        '"""极简"引擎"示例：演示包内模块。"""',
        '',
        '',
        'def start(name: str = "engine") -> str:',
        '    return f"{name} 已启动"',
        ''
      ].join('\n'));
    }
  }
}
