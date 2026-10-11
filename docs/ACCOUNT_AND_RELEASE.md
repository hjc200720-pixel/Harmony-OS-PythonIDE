# 华为账号登录 + 上架准备（实施记录与待办）

> 本文只写**已验证的事实**与**必须由应用所有者完成的事项**，不做假实现、不声称未验证的结果。

## 一、华为账号登录：本地能力核实（有据）

本地 SDK 里 Account Kit **是完整可用的**（不是猜测）：

| 文件 | 内容 |
|---|---|
| `D:/DevEco Studio/sdk/default/hms/ets/kits/@kit.AccountKit.d.ts` | `export { authentication, LoginPanel, LoginWithHuaweiIDButton, loginComponentManager, realName, shippingAddress, minorsProtection, … }` |
| `…/hms/ets/api/@hms.core.authentication.d.ts` | `declare namespace authentication { … } export default authentication;`，含 `HuaweiIDProvider.createLoginWithHuaweiIDRequest()`、`AuthenticationController.executeRequest(request)`、`LoginWithHuaweiIDRequest.forceLogin/state`、`LoginWithHuaweiIDCredential.{authorizationCode,idToken,unionID,openID}`、`AuthenticationErrorCode`（1001502001 未登录 / 1001502002 应用未授权 / 1001502003 参数非法 / 1001502012 用户取消 …）|
| `…/hms/ets/api/@hms.core.account.LoginComponent.d.ets` | 官方一键登录按钮组件（元服务场景必需；普通应用可用自绘按钮 + 上述 API）|

## 二、已经在应用里实现的部分

| 文件 | 内容 |
|---|---|
| `entry/src/main/ets/service/AccountService.ets` | **真实**调用 Account Kit：`HuaweiIDProvider` → `LoginWithHuaweiIDRequest`（`forceLogin=true`、`state` 防 CSRF）→ `AuthenticationController.executeRequest`；成功则把 `unionID/openID/idToken/authorizationCode` 落盘到 `${filesDir}/account.json`；失败把**错误码原样**返回并译成人话 |
| `Index.ets` → `AccountContent()` | 华为账号对话框：未登录/已登录状态、`华为账号登录`/`重新登录`/`退出登录` 按钮、失败原因（含错误码）如实显示、并写明「未配置 AGC 会返回 1001502002」|
| `Index.ets` → `openAccount()` / `doAccountLogin()` / `doAccountLogout()` | 入口与状态管理；登录/退出都写 hilog（`account login ok/fail code=…`）便于验证 |
| `MenuBarView.ets` | 帮助菜单新增 `华为账号登录…`（`help.account`）|

**构建状态**：`assembleHap` 通过（用真实 Account Kit API 编译，无 ArkTS 报错）。

**诚实说明（重要）**：菜单下拉是**系统弹层**，`uitest dumpLayout` 抓不到，本轮**没能在真机上稳定点开该入口**，因此
「点入口 → 拉登录 → 拿到错误码」这条链路**尚未取得真机证据**。要完成这条验证，需要先完成下面第三节的 AGC 配置
（否则拉起的登录必然失败，只能验证「失败路径」）。

## 三、必须由你完成的事（我做不了：需要你的华为开发者账号）

### 3.1 AppGallery Connect（登录能不能成功的关键）
1. 在 AGC 创建**项目**与**应用**：包名必须与工程一致 —— **`com.harmonyide.python`**（见 `AppScope/app.json5`）。
2. 在「API 管理 / 服务」里**开通「华为账号」(Account Kit)**。
3. **登记签名证书指纹**（SHA-256）：这是登录失败最常见的坑 —— 指纹不匹配会直接返回 **1001502002（应用未授权）**。
   - 调试期：登记调试证书指纹（`C:\Users\HUAWEI\.ohos\config\default_HarmonyPyIDE_*.cer` 对应的指纹）。
   - 发布期：登记**发布证书**指纹，并保证两者都在 AGC 里（可各登记一条）。
4. 如需在**你自己的服务端**校验 `idToken`（推荐：客户端拿凭证 → 服务端验签换取用户体系），需要在 AGC 配置并妥善保管 client id / 密钥（**不要写进客户端代码**）。

### 3.2 发布签名（当前是调试签名，不能用于上架）

`build-profile.json5` 现在的 `signingConfigs[0]` 是：
```
keyAlias: debugKey
certpath/profile/storeFile: C:\Users\HUAWEI\.ohos\config\default_HarmonyPyIDE_*.cer/.p7b/.p12
```
上架必须替换为 **AGC 生成的发布证书**（.cer）+ **发布 profile**（.p7b）+ 对应 .p12，并把 `type` 保持 `HarmonyOS`。
（我可以帮你改配置，但证书必须在 AGC 申请后下载到你本机。）

## 四、上架检查清单（HarmonyOS 应用市场）

| # | 事项 | 现状 |
|---|---|---|
| 1 | 发布签名（.cer/.p7b/.p12）| ❌ 当前是 debugKey |
| 2 | AGC 应用创建 + 包名一致 | ❌ 待办（包名已知：com.harmonyide.python）|
| 3 | 登录相关服务开通 + 证书指纹登记 | ❌ 待办 |
| 4 | 应用名称/图标/描述/截图/分类 | 🟡 图标与名称已有（AppScope/app.json5、resources）|
| 5 | 隐私政策 + 用户协议（URL）| ❌ 待办（需你提供托管地址）|
| 6 | 权限声明核对 | 🟡 `module.json5` 目前**没有申请任何敏感权限**（文件读写走应用沙箱，无需权限）——上架前需再逐项复核 |
| 7 | 第三方 SDK / 数据收集说明 | ❌ 待办（用到系统 Account Kit，需在隐私政策里说明收集的信息与用途）|
| 8 | 中国大陆额外要求：**App 备案**（工信部）| ❌ 待办（没有备案无法在国内应用市场发布）|
| 9 | 软著（部分类目要求）| ❌ 待办 |
| 10 | 内测 → 审核 → 上架 | ❌ 待办 |

## 五、建议的推进顺序

1. **先配 AGC + 登记证书指纹**（3.1）→ 然后我这边就能在真机上验证「点登录 → 拉起华为账号 → 拿到 unionID/idToken」这条成功链路。
2. **再换发布签名**（3.2）→ 出 release 包。
3. **补隐私政策 / 备案 / 截图**（第四节）→ 提交审核。
4. 登录成功后可继续做「云端能力」：账号绑定、设置同步、云端项目（需要你自己的服务端）。
## 六、真机验证记录（2026-10-11 补充）

| 项 | 结果 |
|---|---|
| 顶栏账号按钮 | 新增 `tb-account`（`ToolBarView.ets`，`.id('tb-'+key)`），真机 `dumpLayout` 命中 ✓ |
| 账号对话框 | 点击后显示「华为账号 / 未登录 / 华为账号登录」✓ |
| **真实调用链** | 点登录后系统返回 **`1001502003`**，状态栏显示「华为账号登录失败：1001502003」✓ —— 证明已进入系统账号服务 |
| 参数修正尝试 | `state` 原为自定义字符串 → 改为 `util.generateRandomUUID(true)` 的 UUID 后**仍为 1001502003** ⇒ 参数不是唯一原因 |
| 权限核实 | `@hms.core.authentication.d.ts` 中**无 `@permission`**；`module.json5` 未申请权限 ⇒ 不是权限问题 |
| 结论 | 剩余的 `1001502003/1001502002` 与本应用**尚未在 AGC 创建/开通华为账号服务（含签名指纹登记）**一致；完成第三节 3.1 后即可复测成功路径 |

截图：`_cache/device/acct.jpeg`、`_cache/device/acct2.jpeg`