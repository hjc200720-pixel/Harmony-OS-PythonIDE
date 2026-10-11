# 第三方许可与来源说明

本工程随包分发了若干第三方组件。按各自许可证要求在此列明来源与授权。

## 1. JetBrains Mono（代码字体）

| | |
|---|---|
| 文件 | `entry/src/main/resources/rawfile/fonts/JetBrainsMono-Regular.ttf`、`JetBrainsMono-Bold.ttf` |
| 来源 | PyCharm 安装目录 `jbr/lib/fonts/`（即 PyCharm 编辑器默认字体本身） |
| 版权 | Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono) |
| 许可 | **SIL Open Font License 1.1**（允许嵌入与再分发；不得单独售卖） |
| 许可证全文 | `entry/src/main/resources/rawfile/fonts/OFL-JetBrainsMono.txt`（随包分发，满足 OFL 第 2 条） |

> 换成 JetBrains Mono 的原因：它就是 PyCharm 编辑器的默认字体，随包后代码区与 PyCharm 观感一致。
> 早期版本用过 Fira Code（同样是 OFL），现已移除以减小包体。
>
> 未使用 Consolas（Windows 系统字体，闭源，不可再分发）。


## 2. CPython 3.12.10（原生运行时）

| | |
|---|---|
| 产物 | `entry/src/main/cpp/thirdparty/<abi>/libpython3.12.a`、`entry/src/main/resources/rawfile/python/python312.zip` |
| 来源 | https://www.python.org/downloads/release/python-31210/ （官方源码 tarball，由 `scripts/build-cpython-ohos.ps1` 交叉编译） |
| 许可 | **PSF License Version 2**（见 CPython 源码树 `LICENSE`） |
| 修改 | 未修改任何 C 源码；OHOS 适配通过生成 `pyconfig.h` 与模块启用/禁用表完成，详见 `docs/CPYTHON-PORT-NOTES.md` |

## 3. pip 25.0.1（随包 wheel）

| | |
|---|---|
| 文件 | `entry/src/main/resources/rawfile/python/wheels/pip-25.0.1-py3-none-any.whl` |
| 来源 | CPython 源码树 `Lib/ensurepip/_bundled/`（官方随 Python 分发的 pip wheel） |
| 许可 | **MIT**（见 wheel 内 `pip-25.0.1.dist-info/LICENSE.txt`） |

## 4. 工程自有代码

- ArkTS/ArkUI 界面、NAPI 桥接、调试钩子、构建脚本与文档为本工程原创（`entry/src/main/ets/**`、
  `entry/src/main/cpp/napi_init.cpp`、`scripts/**`、`docs/**`）。
- 图标为 `scripts/make-icons.py` 用 Pillow 生成的原创几何图形，不含第三方素材。
- 矢量图标（`view/IdeIcons.ets`）为手写 SVG 路径，未引用 Material/Feather 等图标库资源。


## JetBrains PyCharm New UI 图标（expui）

`entry/src/main/resources/rawfile/icons/` 下的 SVG 图标取自 JetBrains PyCharm 2026.2.2
（`lib/intellij.platform.ide.jar` 的 `expui/**` 与 Python 插件的 `icons/pythonFile.svg`）。
每个 SVG 源文件头部均声明：

    Copyright 2000-2023 JetBrains s.r.o. and contributors.
    Use of this source code is governed by the Apache 2.0 license.

因此这些图标按 **Apache License 2.0** 使用，署名：JetBrains s.r.o.。
本项目未修改图标内容，仅按原样随包分发用于界面展示。
