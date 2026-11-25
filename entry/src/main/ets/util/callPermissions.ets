/**
 * 通话权限：麦克风（语音/视频都要）+ 摄像头（仅视频）。
 *
 * 为什么单独成模块：权限原先是在 CallPage.aboutToAppear 里顺手请求的，而那一刻
 * createCall 早就发出去了，tgcalls 已经去抢麦克风/摄像头。首次安装没有授权记录，
 * 系统既定的弹窗又来不及在设备被占用前落地，结果就是「首次通话要手动去设置里开权限」。
 * 现在统一成：发起/接听之前先把权限拿到，拿不到就不发起，入口一律走 ensureCallPermissions。
 *
 * 授权结果必须判：requestPermissionsFromUser 只 reject 异常，用户点「拒绝」是 resolve，
 * 原实现只挂了 catch，等于把拒绝当成功，通话照发、对端听不到本端。
 */
import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { logE, logI } from './log';

const MICROPHONE: Permissions = 'ohos.permission.MICROPHONE';
const CAMERA: Permissions = 'ohos.permission.CAMERA';

/** 本次通话真正需要的权限；语音只碰麦克风，视频两个都要。 */
function wantedPermissions(isVideo: boolean): Permissions[] {
  return isVideo ? [MICROPHONE, CAMERA] : [MICROPHONE];
}

/** 取本应用自己的 tokenId，checkAccessTokenSync 的入参。 */
function selfTokenId(): number {
  const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
  return info.appInfo.accessTokenId;
}

/** 单条权限是否已授予。查询本身失败一律按「未授予」处理，宁可多弹一次窗。 */
export function hasCallPermission(permission: Permissions): boolean {
  try {
    const status: abilityAccessCtrl.GrantStatus =
      abilityAccessCtrl.createAtManager().checkAccessTokenSync(selfTokenId(), permission);
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  } catch (e) {
    logE(`hasCallPermission(${permission}) failed: ${(e as BusinessError).message}`);
    return false;
  }
}

/** 只查不弹，用于入口处判断要不要打断用户。 */
export function hasCallPermissions(isVideo: boolean): boolean {
  const list: Permissions[] = wantedPermissions(isVideo);
  for (let i = 0; i < list.length; i++) {
    if (!hasCallPermission(list[i])) {
      return false;
    }
  }
  return true;
}

/**
 * 确保拿到本次通话所需的全部权限，返回是否可以继续发起/接听。
 *
 * 已授予的直接放行，只对缺的那几条发起请求 —— 二次通话不会再多弹一次窗。
 * 用户拒绝（含此前已「禁止」、系统不再弹窗的情况）返回 false，调用方负责提示。
 */
export async function ensureCallPermissions(context: common.UIAbilityContext, isVideo: boolean): Promise<boolean> {
  const wanted: Permissions[] = wantedPermissions(isVideo);
  const missing: Permissions[] = [];
  for (let i = 0; i < wanted.length; i++) {
    if (!hasCallPermission(wanted[i])) {
      missing.push(wanted[i]);
    }
  }
  if (missing.length === 0) {
    return true;
  }
  try {
    const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, missing);
    const authResults: number[] = result.authResults;
    for (let i = 0; i < authResults.length; i++) {
      // 0 = 已授权，-1 = 拒绝
      if (authResults[i] !== 0) {
        logE(`call permission denied: ${missing[i]}`);
        return false;
      }
    }
    logI(`call permissions granted: ${missing.join(',')}`);
    return true;
  } catch (e) {
    logE(`requestPermissionsFromUser failed: ${(e as BusinessError).message}`);
    return false;
  }
}
