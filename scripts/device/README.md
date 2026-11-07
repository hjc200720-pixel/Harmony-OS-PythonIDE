# 真机 / 模拟器验证脚本（scripts/device）

本目录提供 HarmonyPyIDE 在鸿蒙设备上的可复用验证链路：启动模拟器、安装 HAP、启动应用、
dumpLayout（界面树）、截图、点击、文本输入、按关键字汇总界面树。

> 说明：所有 `.ps1` 文件必须是**纯 ASCII**。Windows PowerShell 读取无 BOM 的 `.ps1` 时会按
> 系统 ANSI 代码页（中文系统为 GBK）解码，非 ASCII 字节会导致语法错误。中文说明统一放本文件。

## 环境（本机实测）

| 项 | 值 |
| --- | --- |
| 工程根 | `D:\HuaweiMoveData\...\default-workspace\HarmonyPyIDE` |
| hdc | `D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe` |
| 模拟器可执行 | `D:\DevEco Studio\tools\emulator\Emulator.exe` |
| 模拟器实例 | `MateBook Pro`（2in1，3120x2080，density 304，HarmonyOS 7.0.0 / API 26 / x86） |
| 模拟器镜像部署目录 | `D:/DevEcoStudioData/Emulator/deployed` |
| HAP | `entry\build\default\outputs\default\entry-default-signed.hap` |
| 应用包名 / Ability | `com.harmonyide.python` / `EntryAbility` |
| 设备端 hdc 目标 | 模拟器：`127.0.0.1:5555`（TCP）；物理平板：`USB 序列号`（如 `5VXUN25A11G01767`） |

## start-emulator.ps1

幂等启动 2in1 模拟器（已在线则直接返回），等待 hdc 目标出现；失败时打印
`Emulator.log` 尾部与 hdc 输出。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-emulator.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-emulator.ps1 -TimeoutSec 480
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-emulator.ps1 -ForceRestart
```

实现要点：

- 用 **WMI `Win32_Process.Create`** 启动 `Emulator.exe`，而不是 `Start-Process`。
  实测 `Start-Process` 启动的模拟器会在调用方 PowerShell 退出时被一并终止
  （退出码 `-1073741510` = `STATUS_CONTROL_C_EXIT`，启动 2 秒即死）；WMI 方式不受影响。
- 启动参数（与 DevEco 日志一致）：
  `-hvd "MateBook Pro" -path <deployed> -t trace_<随机端口>_commandPipe -imageRoot D:/DevEcoStudioData`
- 成功判定：`hdc list targets -v` 中出现 `TCP Connected` 目标且 `hdc -t <serial> shell echo PING_OK` 返回。
- 退出码：0 成功 / 1 超时或进程退出 / 2 配置缺失 / 3 启动失败。

首次启动到 hdc 可用的实测耗时：**约 3 分钟**（低内存时更久；日志里 `system.img` 校验就要 1~2 分钟）。

## device.ps1

hdc 封装，所有子命令都带超时与明确的 `[OK]/[FAIL]` 输出。默认目标选择顺序：
**TCP 目标（模拟器）→ USB 目标（真机）**；可用 `-Serial` 指定。

```powershell
# 目标
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 targets
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 info
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 -Serial 5VXUN25A11G01767 info

# 安装 / 启动 / 停止
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 install
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 install -Hap <x.hap> -TimeoutSec 300
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 start
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 stop

# 证据：界面树 / 截图（默认写到 HarmonyPyIDE\_cache\device2\）
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 dump
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 dump -Out _cache\device2\a.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 shot
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 shot -Out _cache\device2\a.jpeg

# 交互
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 click -X 1163 -Y 135 -SettleMs 600
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 text -X 900 -Y 900 -Text hello
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 key -KeyCode 3

# 解析界面树（按 text/id/type 正则过滤，输出 bounds 便于点按）
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 summary -In _cache\device2\a.json -Filter '覆盖率|端点|GET' -MaxNodes 40

# 透传 / 取文件
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 shell uname -a
powershell -NoProfile -ExecutionPolicy Bypass -File .\device.ps1 recv /data/local/tmp/x.txt <本地路径>
```

子命令一览：`targets wait info install start stop dump shot click text key shell recv summary help`。

## 最小验证序列（本轮实测）

```powershell
$D = "<工程根>\scripts\device\device.ps1"
$T = "5VXUN25A11G01767"        # 真机平板；模拟器用 127.0.0.1:5555
powershell -NoProfile -ExecutionPolicy Bypass -File $D -Serial $T install
powershell -NoProfile -ExecutionPolicy Bypass -File $D -Serial $T start
powershell -NoProfile -ExecutionPolicy Bypass -File $D -Serial $T dump  -Out "<工程根>\_cache\device2\final_00.json"
powershell -NoProfile -ExecutionPolicy Bypass -File $D -Serial $T shot  -Out "<工程根>\_cache\device2\final_00.jpeg"
powershell -NoProfile -ExecutionPolicy Bypass -File $D -Serial $T click -X 150 -Y 132      # 展开顶栏菜单
powershell -NoProfile -ExecutionPolicy Bypass -File $D -Serial $T click -X 1163 -Y 135     # 运行(U)
powershell -NoProfile -ExecutionPolicy Bypass -File $D -Serial $T click -X 1655 -Y 291     # 运行当前文件并统计覆盖率(_C)
powershell -NoProfile -ExecutionPolicy Bypass -File $D -Serial $T click -X 63 -Y 685       # 左侧竖条底部「⋯」= 更多工具窗…
```

界面树解析出的关键坐标（2800x1840 平板、当前布局，供参考；换设备/分辨率需重新 dump）：

| 元素 | 坐标/范围 |
| --- | --- |
| 顶栏菜单（点左上 ☰ 展开） | 文件(F)[170,88] 编辑(E) 视图(V) 导航 代码 重构 运行(U)[1086,88] 工具(T)[1241,88] 版本控制 窗口 帮助[H] |
| 运行菜单 → 覆盖率项 | 文本中心约 (1655, 291) |
| 左侧竖条「更多工具窗…」 | (63, 685) |
| 右侧工具窗面板标题栏 ⋮/− | (2660,210)-(2770,265) |

2in1 模拟器（3120x2080，应用为桌面浮窗，实测坐标）：左上 ☰ (596,386)；顶栏「运行(U)」(1387,387)；「运行当前文件并统计覆盖率(_C)」(1773,505)；工程树 demo_pkg 展开箭头约 (683,558)（需按 dump 里的 ListItem/Row 定位；窗口位置不同坐标会变）。

## 本轮验证结论与已知问题

1. **物理平板可用**：MatePad 11.5 S（SLG-W50，2800x1840，API 26，HarmonyOS 7.0.0.111）上
   安装/启动/dump/截图/点击全部正常，覆盖率、端点、gutter 均验证通过（见
   `_cache/device2/final_*`）。
2. **2in1 模拟器链路可用，首次安装崩溃已修复并回归通过**：模拟器可启动（约 100~180s 到 hdc 在线）、
   HAP 可安装。曾出现过应用一启动即 JS 崩溃：
   `write failed: .../PyProjects/示例工程/demo_pkg/models.py`；根因是
   `FileService.createSampleProject()` 先写 `demo_pkg/models.py` 后才 `ensureDir(demo_pkg)`，
   空沙箱（首次安装）没有该目录。应用侧已在 2026-11-08 00:13 的 HAP 修复：
   函数开头先建 `demo_pkg` 与 `demo_pkg/core`，且 `writeText()` 统一兜底建父目录。
   回归步骤：`hdc uninstall` 清数据（确认沙箱目录消失）→ install → start；
   结果无新 jscrash，工程树可见 demo_pkg 下 models.py/web_routes.py 等 8 个文件（见
   `_cache/device2/fresh_*`），模拟器 x86 运行时上覆盖率也能出数（21.3%，main.py 14/14）。
3. 应用侧已修复的缺陷（验证通过）：右侧工具窗内容串味（覆盖率↔端点切换后标题与内容不一致）。
4. 内存：模拟器占 ~4GB，低内存（可用 <1GB）时启动会非常慢，验证前建议先关掉不必要的进程。

## 证据目录

`HarmonyPyIDE\_cache\device2\`
- `fresh_*`：2in1 模拟器首次安装回归证据（00:13 HAP，含 demo_pkg 建目录成功、覆盖率）
- `final_*`：最新 HAP（00:03 构建）的最终验证证据
- `cov2_* / ep2_* / sw_*`：上一版 HAP（23:51/23:59 构建）的切换/端点验证
- `cov_* / ep_* / tablet_*`：修复前基线证据（含「端点面板显示覆盖率内容」缺陷现场）

界面树 `.json` 用 `uitest dumpLayout` 生成，可用 `device.ps1 summary -In <json> -Filter <正则>`
查看；截图 `.jpeg` 为设备原分辨率（2800x1840），gutter 细节可裁剪查看。
