/**
 * AccountService —— 华为账号登录（HarmonyOS Account Kit）
 *
 * 依据本地 SDK：D:/DevEco Studio/sdk/default/hms/ets/kits/@kit.AccountKit.d.ts
 *   - authentication.HuaweiIDProvider.createLoginWithHuaweiIDRequest()
 *   - authentication.AuthenticationController.executeRequest(request)
 *   - credential: authorizationCode / idToken / unionID / openID
 *
 * 说明（重要）：本服务只负责「调用系统账号能力」。要让登录真正成功，必须先在
 * AppGallery Connect 创建应用、开通「华为账号」服务、并登记本应用的签名证书指纹；
 * 否则 executeRequest 会返回 1001502002（应用未授权）等错误码，本服务会把码原样报出，
 * 不做任何假成功。
 */
import { authentication } from '@kit.AccountKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FileService } from './FileService';

/** 登录后保存的账号信息（unionID/openID 是华为账号的稳定标识） */
export class AccountProfile {
  unionID: string = '';
  openID: string = '';
  nickName: string = '';
  avatarUri: string = '';
  loginTime: number = 0;
  hasIdToken: boolean = false;
  hasAuthCode: boolean = false;
}

/** 一次登录尝试的结果（成功或带错误码的失败） */
export class AccountResult {
  ok: boolean = false;
  code: number = 0;
  message: string = '';
  profile: AccountProfile = new AccountProfile();
}

/** 错误码 → 人话（取自 AuthenticationErrorCode 的官方注释） */
function explain(code: number): string {
  if (code === 1001502001) {
    return '设备上未登录华为账号：请先在系统「设置 → 华为账号」登录，或允许弹出登录页。';
  }
  if (code === 1001502002) {
    return '应用未授权：需要在 AppGallery Connect 里开通「华为账号」服务，并登记本应用的签名证书指纹。';
  }
  if (code === 1001502003) {
    return '参数不合法（state/scopes 等）。';
  }
  if (code === 1001502012) {
    return '用户取消了登录。';
  }
  return `账号服务返回错误码 ${code}。`;
}

export class AccountService {
  private static storePath(): string {
    return `${FileService.context().filesDir}/account.json`;
  }

  static load(): AccountProfile {
    const p: string = AccountService.storePath();
    if (!FileService.exists(p)) {
      return new AccountProfile();
    }
    try {
      return JSON.parse(FileService.readText(p)) as AccountProfile;
    } catch (err) {
      return new AccountProfile();
    }
  }

  static isLoggedIn(): boolean {
    return AccountService.load().unionID.length > 0;
  }

  static logout(): void {
    try {
      FileService.writeText(AccountService.storePath(), JSON.stringify(new AccountProfile()));
    } catch (err) {
      FileService.log('account.json 清空失败');
    }
  }

  /** 发起华为账号登录（forceLogin=true 时若无登录态会拉起登录页） */
  static login(context: common.UIAbilityContext): Promise<AccountResult> {
    return new Promise<AccountResult>((resolve: (r: AccountResult) => void) => {
      const result: AccountResult = new AccountResult();
      try {
        const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
        const request: authentication.LoginWithHuaweiIDRequest = provider.createLoginWithHuaweiIDRequest();
        request.forceLogin = true;
        request.state = `harmonyide-${Date.now()}`;
        const controller: authentication.AuthenticationController =
          new authentication.AuthenticationController(context);
        controller.executeRequest(request)
          .then((resp: authentication.LoginWithHuaweiIDResponse) => {
            const cred: authentication.LoginWithHuaweiIDCredential | undefined = resp.data;
            if (cred === undefined) {
              result.message = '账号服务未返回凭证。';
              resolve(result);
              return;
            }
            const prof: AccountProfile = new AccountProfile();
            prof.unionID = cred.unionID === undefined ? '' : cred.unionID;
            prof.openID = cred.openID === undefined ? '' : cred.openID;
            prof.hasIdToken = cred.idToken !== undefined && cred.idToken.length > 0;
            prof.hasAuthCode = cred.authorizationCode !== undefined && cred.authorizationCode.length > 0;
            prof.loginTime = Date.now();
            result.ok = true;
            result.profile = prof;
            result.message = '登录成功。';
            try {
              FileService.writeText(AccountService.storePath(), JSON.stringify(prof));
            } catch (err) {
              FileService.log('account.json 写入失败');
            }
            FileService.log(`account login ok unionID=${prof.unionID.slice(0, 6)}… idToken=${prof.hasIdToken}`);
            resolve(result);
          })
          .catch((err: BusinessError) => {
            result.ok = false;
            result.code = err.code;
            result.message = explain(err.code);
            FileService.log(`account login fail code=${err.code}`);
            resolve(result);
          });
      } catch (err) {
        const be: BusinessError = err as BusinessError;
        result.ok = false;
        result.code = be.code === undefined ? -1 : be.code;
        result.message = `调用账号服务异常：${be.message === undefined ? '未知' : be.message}`;
        FileService.log(`account login throw code=${result.code}`);
        resolve(result);
      }
    });
  }
}
