import { notificationManager } from '@kit.NotificationKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { str } from '../util/strings';
import { logE, logI } from '../util/log';

// 通话进行中的常驻通知（带「挂断」按钮）。
//
// 来由：通话页可以缩成应用内小窗、也可以退到后台，这两种情况下用户没有
// 直观的"挂断"入口，只能一层层找回来。这里在接通时发一条 ongoing 通知
// 停在通知栏，挂断按钮直接结束当前通话。
//
// 按钮为什么走公共事件而不是 want 参数：通知按钮的 WantAgent 只能拉起
// ability 或发公共事件，两者都在独立进程里执行；挂断要作用到本进程里的
// CallSession，所以用 SEND_COMMON_EVENT，由本进程订阅后调用 hangup()
// （与 BackgroundCacheNotifier 的「全部暂停」按钮同一范式）。
// EntryAbility 侧另外解析一层 want 参数（CALL_ACTION_WANT_KEY），是给
// 「点击通知体」这条 START_ABILITY 路径留的钩子。

const ACTIVE_NOTIFICATION_ID: number = 999002;
const HANGUP_REQUEST_CODE: number = 8321;
const OPEN_REQUEST_CODE: number = 8322;
const EVENT_SUFFIX: string = '.call.action';
const OP_HANGUP: string = 'hangup';
// want 参数键：EntryAbility / Index 解析后据此挂断。
export const CALL_ACTION_WANT_KEY: string = 'callAction';

class CallNotification {
  private bundleName: string = '';
  private onHangup: () => void = (): void => {};
  private subscribing: boolean = false;
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;
  private hangupAgent: Promise<WantAgent> | null = null;
  private openAgent: Promise<WantAgent> | null = null;
  private shown: boolean = false;
  // 已发布内容的指纹。CallSession 每次 publish（静音/音量/视频开关都会触发）
  // 都会调一次 show()，不比对内容就会把通知反复重发，通知栏会闪。
  private shownKey: string = '';

  // 只绑定一次：Globals 装配通话会话时调用。onHangup 由调用方接到
  // CallSession.hangup，本类不认识通话会话（避免循环依赖）。
  bind(bundleName: string, onHangup: () => void): void {
    this.bundleName = bundleName;
    this.onHangup = onHangup;
    this.ensureSubscriber();
  }

  // 接通后发布常驻通知。重复调用复用同一 id（系统按 id 覆盖）。
  show(peerName: string, isVideo: boolean): void {
    if (this.bundleName === '') {
      return;
    }
    const key: string = `${peerName}|${isVideo}`;
    if (this.shown && this.shownKey === key) {
      return; // 内容没变，不重发
    }
    this.shown = true;
    this.shownKey = key;
    this.showAsync(peerName, isVideo).catch((e: Object): void => {
      logE(`CallNotification.show failed: ${JSON.stringify(e)}`);
    });
  }

  // 通话结束/取消时撤销。非本类发布的通知不会碰（shown 为 false 时短路）。
  cancel(): void {
    if (!this.shown) {
      return;
    }
    this.shown = false;
    this.shownKey = '';
    notificationManager.cancel(ACTIVE_NOTIFICATION_ID).catch((e: Error): void => {
      logE(`CallNotification.cancel failed: ${e.message}`);
    });
  }

  private async showAsync(peerName: string, isVideo: boolean): Promise<void> {
    const open: WantAgent = await this.openAgentOf();
    const hangup: WantAgent = await this.hangupAgentOf();
    const button: notificationManager.NotificationActionButton = {
      title: str('call_hang_up'), wantAgent: hangup
    };
    const title: string = peerName !== '' ? peerName : str('pp_call');
    const request: notificationManager.NotificationRequest = {
      id: ACTIVE_NOTIFICATION_ID,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: isVideo ? str('call_notify_video') : str('call_notify_voice')
        }
      },
      wantAgent: open,
      actionButtons: [button],
      isOngoing: true,
      tapDismissed: false
    };
    await notificationManager.publish(request);
    logI(`CallNotification shown id=${ACTIVE_NOTIFICATION_ID} video=${isVideo}`);
  }

  // 点击通知体：拉起应用（通话页在页面栈里就回到通话页，否则落在首页，
  // 首页的悬浮小窗仍能一键恢复）。
  private openAgentOf(): Promise<WantAgent> {
    if (this.openAgent === null) {
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: this.bundleName, abilityName: 'EntryAbility' }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: OPEN_REQUEST_CODE,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const pending: Promise<WantAgent> = wantAgent.getWantAgent(info);
      this.openAgent = pending;
      pending.catch((_e: Object): void => { this.openAgent = null; });
    }
    return this.openAgent;
  }

  // 挂断按钮：发公共事件到本进程。
  private hangupAgentOf(): Promise<WantAgent> {
    if (this.hangupAgent === null) {
      const params: Record<string, Object> = {};
      params[CALL_ACTION_WANT_KEY] = OP_HANGUP;
      const info: wantAgent.WantAgentInfo = {
        wants: [{ action: this.eventName(), parameters: params }],
        actionType: wantAgent.OperationType.SEND_COMMON_EVENT,
        requestCode: HANGUP_REQUEST_CODE,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const pending: Promise<WantAgent> = wantAgent.getWantAgent(info);
      this.hangupAgent = pending;
      pending.catch((_e: Object): void => { this.hangupAgent = null; });
    }
    return this.hangupAgent;
  }

  private eventName(): string {
    return `${this.bundleName}${EVENT_SUFFIX}`;
  }

  private ensureSubscriber(): void {
    if (this.subscribing || this.bundleName === '') {
      return;
    }
    this.subscribing = true;
    const info: commonEventManager.CommonEventSubscribeInfo = { events: [this.eventName()] };
    commonEventManager.createSubscriber(info)
      .then((subscriber: commonEventManager.CommonEventSubscriber): void => {
        this.subscriber = subscriber;
        commonEventManager.subscribe(subscriber,
          (error: BusinessError, data: commonEventManager.CommonEventData): void => {
            if (error !== undefined && error !== null && error.code !== 0) {
              logE(`CallNotification event failed: ${error.message}`);
              return;
            }
            const params = data.parameters as Record<string, Object> | undefined;
            const action: string = params !== undefined
              ? ((params[CALL_ACTION_WANT_KEY] as string | undefined) ?? '') : '';
            if (action === OP_HANGUP) {
              logI('CallNotification hangup action from notification');
              this.onHangup();
            }
          });
      })
      .catch((e: Object): void => {
        this.subscribing = false;
        this.subscriber = null;
        logE(`CallNotification subscribe failed: ${JSON.stringify(e)}`);
      });
  }
}

export const callNotification: CallNotification = new CallNotification();
