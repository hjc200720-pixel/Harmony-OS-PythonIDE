# 路线图

按"对 IDE 体验的提升幅度 ÷ 实现成本"排序。

## 已完成（本轮补完）

0. ~~**构建器的 ABI 隔离**~~ ✅ **已修复并验证**
   `ohos_cpython_build.py` 现在把对象文件放在 `<work>/<abi>/obj/…`（源码树只读），
   并在 `phase_compile` 里校验 `<src>/Include/pyconfig.h` 的 triplet 是否匹配当前 `--abi`
   （不匹配就重新探测），归档前还有"期望对象全集核算"与 `llvm-readelf` 架构闸门兜底。
   实测：`-Abi both` 顺序构建通过，arm64-v8a 与 x86_64 各 230/230 编译成功、
   架构自检分别为 `AArch64` / `X86-64`，两者都成功内嵌进 HAP。
   另修掉：`statvfs`/`fstatvfs` 宏必须成对（x86_64 上曾因此编译失败）。
   顺带发现并修复了一个真实缺陷：两个 `.ps1` 缺 UTF-8 BOM，Windows PowerShell 会按 GBK 读，
   导致 `build-cpython-ohos.ps1` 直接语法报错——现已补 BOM 并通过语法自检。

0.1 ~~**内置 pip**~~ ✅ **已完成并做宿主侧验证**
   标准库 zip 之外的 `rawfile/python/wheels/` 随包官方 `pip-25.0.1-py3-none-any.whl`，
   解释器首次启动时由 `napi_init.cpp` 的内置脚本解压进 `site-packages`，
   因此 `pip install --no-index --find-links <目录> <包>` 真正可用。
   验证方式：用与 C++ 脚本**完全相同**的解压逻辑在宿主 Python 3.12.10 上跑通，
   `import pip` → 25.0.1、`python -m pip --version` 正常。
   （注意：`_ssl` 缺失，联网访问 PyPI 仍需先交叉编译 OpenSSL。）

## P0 —— 补齐"IDE 之所以是 IDE"的核心能力

0.2 **首次上机验收**（当前最大的未知量）
   本机没有签名材料，所有结论止于"编译 / 链接 / 符号 / 导入契约"。
   上机后请按 DEVICE-ADAPTATION.md 第 7 节的清单跑一遍，重点验证：
   `sys.builtin_module_names`、`import zlib/_socket/select/math/decimal/pyexpat/unicodedata`、
   `hashlib.sha256`、`socket.socket(AF_INET)`、`threading`、`os.getrandom`、
   以及本 IDE 的"运行 + 实时输出 + traceback + REPL + pip 离线安装"闭环。
   `scripts/verify-hap.py` 与 `scripts/verify-runtime-contract.py` 可在上机前先把
   打包与导入契约这一层卡住。

1. ~~**断点调试引擎**~~ ✅ **已完成（行级）**
   已实现：行断点暂停、继续/单步/停止、局部变量 repr 快照、调用栈、编辑器暂停行高亮与自动定位；
   调试钩子语义由 `scripts/verify-debug-hook.py` 在宿主上 6/6 验证。
   仍缺：条件断点、步入/步出、watch 表达式、暂停中展开/修改对象、多帧变量浏览。

1.1 **调试器增强**
   - 用 `sys.settrace` / `sys.monitoring`（3.12+）实现行级 trace，C 侧通过 `_pyide_bridge` 上报
     `(file, line, locals, globals)`，ArkTS 侧做变量树、调用栈、单步/继续/跳出。
   - 编辑器已有断点槽与持久化，只需接上执行控制（暂停/单步/继续）。
   - 注意：tracing 会显著拖慢执行，需要"开启调试才安装 trace"。

2. **代码补全与跳转**
   - 轻量方案：内置 `jedi`（纯 Python，可打进 `python312.zip`）提供补全/定义跳转/签名提示。
   - 编辑器需要能渲染补全弹层（`bindPopup` + `List`），并在 `TextArea` 上跟随光标定位。

3. **撤销/重做独立栈**
   - 当前依赖系统输入框；应自建操作栈（按行 diff 存快照），并提供 `Ctrl+Z/Y`。

## P1 —— 规模与性能

4. **编辑器虚拟化**：把高亮层换 `LazyForEach` + `IDataSource`，只渲染可见行 ± 缓冲；
   输入层仍需整篇文本，但可用"分页 TextArea"或按段落拆分降低单次布局成本。
5. **大文件降级策略**：> 5000 行自动关闭高亮并提示，保证可编辑。
6. **行号槽与代码横向滚动解耦**：行号槽固定列 + 代码区独立横向滚动（两个 Scroller 同步偏移）。

## P2 —— 工程与生态

7. **完整终端**：`fork/exec` 受 HarmonyOS 沙箱限制，建议改为"内置命令 + 可扩展的 Python 子进程"
   或 `childProcessManager`（API 12+ 提供 `@ohos.app.ability.childProcessManager`）。
8. **pip 完整体验**：为真机 ABI 预置常用纯 Python wheel（离线仓库）；若要做联网 PyPI，
   需要把 OpenSSL 交叉编译进 sysroot 并启用 `_ssl`。
9. **多项目与最近记录**：项目列表、切换、删除、克隆模板工程。
10. **项目管理文件**：`.pyide/run.json` 保存运行配置/工作目录/环境变量，并支持多份 Run Configuration。
11. **代码格式化**：内置 `black`（纯 Python）+ `isort`，替换当前的"去尾空白 + 展开 Tab"。
12. **Git 集成**：只做调用系统 `git`（若有）或纯 Python 的 dulwich 子集。

## P3 —— 分发与工程化

13. **签名与上架**：配置 signingConfigs，产出正式签名 HAP，走 AppGallery 上架流程。
14. **单元测试**：`ohosTest`（hypium）覆盖 `PyHighlighter`、`FileService`、路径与缩进逻辑；
    原生侧加一个"用 `PyRun_SimpleString` 跑断言"的自测入口。
15. **CI**：命令行 `ohpm install + hvigorw assembleHap` 已可用，可直接进流水线；
    交叉编译 CPython 需要缓存 `_cache` 目录以缩短时长。
16. **多语言**：文案抽到 `resources/base/element/string.json` + `en_US`，目前中文硬编码在组件里。

## 已知技术债

- `Index.ets` 偏大（状态中心 + 全部动作分发）。可拆成 `IdeViewModel`（`@Observed`）+ 更薄的页面。
- 编辑器与父组件之间用 `@Prop initialText` 单向下发 + 回调上传，语义上略绕；
  更干净的做法是 `@Link` + 显式 `editorRevision` 版本号。
- `IdeIcons.ets` 里用 `Shape + Path` 组合的两个图标依赖 `viewPort` 缩放语义，需在真机上目视确认。
- 未做无障碍（无障碍焦点顺序、TalkBack 文案）与字体缩放适配。
