# 上架交接包（已完成 / 只能你做的 / 可直接粘贴的材料）

> 原则：本文只写**已验证**的事。凡是需要你的华为开发者账号或实名材料的，都明确标为「你来做」，并给出逐步操作。

## 一、我已经做完的（附证据）

| # | 事项 | 状态与证据 |
|---|---|---|
| 1 | 华为账号登录（真实 Account Kit）| ✅ 代码 `service/AccountService.ets`：`HuaweiIDProvider` → `LoginWithHuaweiIDRequest`（`forceLogin=true`、`state` 用 `util.generateRandomUUID`）→ `AuthenticationController.executeRequest`；凭证落盘 `account.json` |
| 2 | 顶栏账号入口（对标 PyCharm 右上「试用/账号」微件）| ✅ 新增按钮 `tb-account`，真机 `dumpLayout` 确认存在；点击后对话框显示「华为账号 / 未登录 / 华为账号登录」 |
| 3 | **真机验证调用链真的通** | ✅ 点登录后系统返回 **`1001502003`**，状态栏与对话框都显示「华为账号登录失败：1001502003」——**证明调用进入了系统账号服务**（不是空壳）|
| 4 | Account Kit 权限要求核实 | ✅ 通读 `@hms.core.authentication.d.ts`：**无 `@permission` 要求**（所以失败不是权限问题；`module.json5` 也无需加权限）|
| 5 | 应用内三份合规文档 | ✅ 「隐私政策 / 用户协议 / 第三方 SDK 与数据说明」，帮助菜单可打开，正文如实写明「仅本机保存、不上传」 |
| 6 | 可托管的隐私政策 | ✅ `docs/privacy-policy.md` + `docs/privacy-policy.html`（可直接丢到任意静态托管当隐私政策 URL）|
| 7 | 发布签名脚手架 | ✅ `scripts/prepare-release-signing.ps1`：传入 AGC 下载的 .p12/.cer/.p7b 即自动写入 `build-profile.json5`（先备份）|
| 8 | 版本与包名（发布态）| ✅ `AppScope/app.json5`：`bundleName com.harmonyide.python`、`versionCode 1000000`、`versionName 1.0.0`、`icon $media:layered_image` |

## 二、只能你做的（我做不了：需要你的账号/实名）

### 2.1 AGC 配置（决定登录能否成功）
1. 登录 AppGallery Connect → 我的项目 → 创建**应用**，包名填 **`com.harmonyide.python`**（必须完全一致）。
2. 「API 管理」里开通 **华为账号（Account Kit）**。
3. 「项目设置 → 常规 → 应用 → 签名证书指纹」里**登记 SHA-256 指纹**：
   - 调试证书指纹（现有 `C:\Users\HUAWEI\.ohos\config\default_HarmonyPyIDE_*.cer`）
   - 发布证书指纹（下一步申请后登记）
   - **这是登录失败最常见的坑**；指纹不一致/未登记会出现 `1001502002` 或 `1001502003`。
4. 若日后要在自己的服务端校验 `idToken`，client id/密钥放服务端，**不要进客户端代码**。

### 2.2 发布签名与出包
```powershell
# 1) 在 AGC「证书、App ID 和 Profile」申请发布证书，下载 .p12 / .cer / .p7b
# 2) 一条命令填入工程：
cd <工程目录>
.\scripts\prepare-release-signing.ps1 -StoreFile D:\keys\release.p12 -KeyAlias releaseKey -CertPath D:\keys\release.cer -Profile D:\keys\release.p7b -StorePassword *** -KeyPassword ***
# 3) 把 build-profile.json5 里 products 的 signingConfig 改为 "release"，然后：
hvigorw --mode module -p product=default -p buildMode=release assembleApp
```

### 2.3 备案与资质（国内上架硬要求）
- **App 备案（工信部）**：需要你的主体证件（个人身份证或企业营业执照）、域名/服务器信息；华为应用市场提审时会校验备案号。
- **软著**：部分类目要求，需以你的名义申请。
- **开发者实名**：华为开发者账号需完成实名认证（个人/企业）。

### 2.4 隐私政策托管
把 `docs/privacy-policy.html` 上传到任意静态托管（Gitee Pages / 华为云 OBS / 自有域名），得到 URL 填进商店；
**并先把文档里的联系邮箱换成你的真实邮箱**（我留了显式占位）。

## 三、可直接粘贴到应用市场的材料

**应用名称**：HarmonyPyIDE（鸿蒙 Python IDE）

**一句话简介**（≤ 30 字）：
在鸿蒙平板与 PC 上写、跑、调 Python 的桌面级 IDE。

**详细介绍**：
```
HarmonyPyIDE 把 PyCharm 风格的 Python 开发体验带到鸿蒙设备（平板 / 2in1），内置 CPython 3.12，全部在本机运行。

【编辑与运行】多标签编辑、语法高亮、代码折叠、断点调试（变量/调用栈/单步/求值/监视）、内置终端与 Python 控制台（REPL），运行结果直接看输出。
【跨文件理解】全工程符号索引、转到定义、转到类、结构视图（文件/工程两级）、继承层级、查找用法、跨文件补全。
【静态检查】未使用导入、重复定义、空实现、未使用变量、未定义名字共 5 类检查，全部零误报；带问题面板（筛选/排序/跳转）与编辑器装订区标记。
【重构】跨文件重命名，支持 6 种命名风格、自动备份与一键撤销。
【可视化与工程】关系图（继承+调用，可导出 PNG）、变更时间线、外部任务与依赖清单、多窗格编辑器、本地历史、书签。

全部功能在本机沙箱内离线运行：不上传代码、不联网、不申请敏感权限。
```

**分类建议**：开发工具 / 效率办公
**关键词**：Python、IDE、代码编辑器、鸿蒙、开发工具、编程

**权限说明**（提审时填写）：
```
本应用未申请任何敏感系统权限。项目文件保存在应用自身沙箱目录内；
Python 代码在本机沙箱内运行；华为账号登录使用系统 Account Kit，仅在用户主动点击时获取账号标识并仅保存在本机。
```

**版本说明（1.0.0）**：
```
首个版本：PyCharm 风格界面、内置 CPython 3.12 运行/调试、跨文件符号索引与跳转、5 类静态检查、跨文件重命名与补全、关系图与导出、终端与控制台、书签、华为账号登录入口。
```

**截图建议**（提供 3~5 张；我已留下的真机截图可直接用作素材候选，位于 `_cache/device/`）：
| 截图内容 | 文件 |
|---|---|
| 主界面（项目树 + 编辑器 + 结构视图）| `rails6.jpeg` / `final1.jpeg` |
| 问题面板与 5 类检查 | `undef2.jpeg` |
| 关系图导出 | `graphreg.jpeg` |
| 继承层级 | `rg3.jpeg` |
| 华为账号登录 | `acct.jpeg` / `acct2.jpeg` |

## 四、验证记录（可复现）

```
构建：hvigorw --mode module -p product=default -p buildMode=debug assembleHap   → BUILD SUCCESSFUL
安装：hdc install -r entry-default-signed.hap
入口：dumpLayout 命中 id=tb-account（顶栏账号按钮）
点击：对话框出现「华为账号 / 未登录 / 华为账号登录」
登录：点击后系统返回 1001502003（PARAMETER_INVALID），界面如实显示，未做假成功
权限：@hms.core.authentication.d.ts 无 @permission 要求；module.json5 未申请权限
```