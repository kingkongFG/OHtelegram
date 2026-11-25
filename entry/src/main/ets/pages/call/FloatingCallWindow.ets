import { router } from '@kit.ArkUI';
import { getCallSession } from '../../tdkit/Globals';
import { CallSession, CallSnapshot, CALL_MINIMIZED_KEY } from '../../services/CallSession';
import { AvatarView } from '../chatlist/AvatarView';
import { callDurationLabel } from '../../util/callPresentation';
import {
  FloatingDragAnchor, FloatingDragBounds, clampFloatingTranslation, dragFloatingTranslation
} from '../../util/floatingDrag';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logI } from '../../util/log';

// 应用内悬浮通话小窗。
//
// 通话页点「缩为悬浮窗」后退出全屏页、把 minimized 置 true，宿主（pages/Index）
// 在页面栈之上叠这一块小窗。显隐完全由 CallSession 的 minimized 决定
// （经 AppStorage 的 CALL_MINIMIZED_KEY 同步过来），不在本组件里另存一份状态
// ——两处状态各写各的就会出现"小窗还在、通话已经结束"这种鬼影。
//
// 形态按通话类型分两套（与 IM 惯例一致，也和通话页左上角那颗按钮的图标语义对齐）：
//   - 语音通话：横向通话条（头像 + 名字 + 计时 + 静音 + 挂断）。
//   - 视频通话：竖版小窗（132×196），优先铺远端画面；远端没画面时用头像 +
//     视频图标占位，绝不留一块纯黑。控件收敛为静音/挂断两颗最小按钮。
// 两套都点主体回全屏页，都可拖动（仍旧落在 util/floatingDrag 的同一套夹紧数学里）。
//
// 远端画面为什么能接进小窗：远端流绑定的就是 surfaceId（CallSession
// .setRemoteSurface → NativeCallMedia.callSetRemoteVideoSurface），全屏页退栈时
// 会解绑自己的 surface，小窗 onLoad 再绑上自己的，原生侧照旧往新 surface 送帧。
// 两侧 onDestroy 都走 clearRemoteSurfaceIf(自己的 id)，只在"当前绑定的仍是自己"
// 时才解绑，避免交接时序把对方刚接上的画面打黑。

const BG_COLOR: string = '#F217212B';
const DANGER: string = '#FFE5484D';
const CONTROL_BG: string = '#33FFFFFF';
const SUBTEXT: string = '#B8C4CF';
const SCRIM: string = '#99000000';
const BADGE_BG: string = '#59000000';

// 语音通话条：沿用原来的 196 宽横条与 30 的控制圆钮。
const BAR_WIDTH: number = 196;
const BAR_BUTTON: number = 30;
// 视频通话小窗：竖版 132×196（9:16 附近），圆角 16。
const VIDEO_WIDTH: number = 132;
const VIDEO_HEIGHT: number = 196;
const VIDEO_RADIUS: number = 16;
const MINI_BUTTON: number = 26;
const DRAG_MARGIN: number = 8;

@Component
export struct FloatingCallWindow {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  // 拖动夹紧用的屏幕尺寸：EntryAbility 启动时按窗口实测写进来（vp）。
  @StorageProp('screenWidthVp') screenWidthVp: number = 0;
  @StorageProp('screenHeightVp') screenHeightVp: number = 0;
  @State snap: CallSnapshot | null = null;
  @State nowMs: number = 0;
  @State dragX: number = 0;
  @State dragY: number = 0;
  private unsub: (() => void) | null = null;
  private tickTimer: number = -1;
  // 远端画面：与全屏通话页一样是 TEXTURE 型 XComponent，换页时重新绑定 surface。
  private remoteController: XComponentController = new XComponentController();
  private boundRemoteSurface: string = '0';
  private dragAnchor: FloatingDragAnchor | null = null;
  private panStartX: number = 0;
  private panStartY: number = 0;

  aboutToAppear(): void {
    const session: CallSession = getCallSession();
    this.unsub = session.subscribe((s: CallSnapshot): void => {
      this.snap = s;
    });
    this.tickTimer = setInterval((): void => {
      this.nowMs = Date.now();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
    if (this.tickTimer !== -1) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    // 小窗退场：只有"当前绑定的仍是本小窗这一路"时才解绑，否则会打黑刚恢复的
    // 全屏通话页（pushUrl 触发的 CallPage onLoad 可能早于本组件的 onDestroy）。
    const surfaceId: string = this.boundRemoteSurface;
    this.boundRemoteSurface = '0';
    getCallSession().clearRemoteSurfaceIf(surfaceId);
  }

  private isVideoForm(): boolean {
    return this.snap !== null && this.snap.isVideo;
  }

  // 远端真的在送画面才挂 XComponent：呼出中/连接中/对端关摄像头一律走占位，
  // 免得先糊一块黑底在小窗里。
  private remoteVideoReady(): boolean {
    const s = this.snap;
    return s !== null && s.isVideo && s.phase === 'active' && s.remoteVideoActive;
  }

  private peerName(): string {
    const s = this.snap;
    return s !== null && s.peerName !== '' ? s.peerName : str('pp_call');
  }

  private timeLine(): string {
    const s = this.snap;
    if (s === null) {
      return '';
    }
    return callDurationLabel(s.startedAtMs, this.nowMs === 0 ? Date.now() : this.nowMs);
  }

  // 恢复全屏：先清最小化标记（小窗随之消失），再推通话页。pushUrl 失败
  // 时把标记放回去，否则通话会变成既没全屏页也没小窗的孤儿。
  private restore(): void {
    const session: CallSession = getCallSession();
    session.setMinimized(false);
    router.pushUrl({ url: 'pages/call/CallPage' }).catch((): void => {
      session.setMinimized(true);
    });
  }

  // 拖动夹紧范围取整屏（vp，EntryAbility 实测写入 AppStorage）；小窗在 Index 里
  // 由容器摆到右下角，这里的 anchor 只用于把位移限制在屏幕内，不改布局位置。
  private currentDragBounds(): FloatingDragBounds | null {
    if (this.screenWidthVp <= 0 || this.screenHeightVp <= 0) {
      return null;
    }
    return { width: this.screenWidthVp, height: this.screenHeightVp, margin: DRAG_MARGIN };
  }

  // onAreaChange 报的是布局位置（不受 translate 影响），正好是夹紧数学要的锚点。
  private onWindowArea(area: Area): void {
    this.dragAnchor = {
      x: Number(area.globalPosition.x ?? 0),
      y: Number(area.globalPosition.y ?? 0),
      width: Number(area.width),
      height: Number(area.height)
    };
    this.reclampDrag();
  }

  private reclampDrag(): void {
    const bounds: FloatingDragBounds | null = this.currentDragBounds();
    if (this.dragAnchor === null || bounds === null) {
      return;
    }
    const held = clampFloatingTranslation(this.dragX, this.dragY, this.dragAnchor, bounds);
    this.dragX = held.x;
    this.dragY = held.y;
  }

  private onPanUpdate(event: GestureEvent): void {
    const bounds: FloatingDragBounds | null = this.currentDragBounds();
    if (this.dragAnchor === null || bounds === null) {
      return;
    }
    const next = dragFloatingTranslation(
      this.panStartX, this.panStartY, event.offsetX, event.offsetY,
      this.dragAnchor, bounds
    );
    this.dragX = next.x;
    this.dragY = next.y;
  }

  @Builder
  muteButton(size: number, iconSize: number) {
    Column() {
      SymbolGlyph($r(this.snap !== null && this.snap.muted
        ? 'sys.symbol.mic_slash_fill' : 'sys.symbol.mic'))
        .fontSize(iconSize)
        .fontColor([this.snap !== null && this.snap.muted ? Color.Black : Color.White]);
    }
    .width(size).height(size).borderRadius(size / 2)
    .backgroundColor(this.snap !== null && this.snap.muted ? '#E6FFFFFF' : CONTROL_BG)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => { getCallSession().toggleMute(); });
  }

  @Builder
  hangupButton(size: number, iconSize: number) {
    Column() {
      // phone_down_fill 已在本机 SDK 的 sysResource 符号表里核实存在。
      SymbolGlyph($r('sys.symbol.phone_down_fill')).fontSize(iconSize).fontColor([Color.White]);
    }
    .width(size).height(size).borderRadius(size / 2)
    .backgroundColor(DANGER)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => { getCallSession().hangup(); });
  }

  // 语音通话：横向通话条（形态与改动前一致，只把两处颜色/尺寸常量提到文件头）。
  @Builder
  voiceBar() {
    Row({ space: 8 }) {
      AvatarView({
        avatarPath: '',
        initials: this.peerName().substring(0, 1).toUpperCase(),
        colorSeed: this.snap !== null ? this.snap.peerUserId : 0,
        avatarSize: 34
      });
      Column({ space: 2 }) {
        Text(this.peerName())
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.timeLine())
          .fontSize(11).fontColor(SUBTEXT).maxLines(1);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      this.muteButton(BAR_BUTTON, 17);
      this.hangupButton(BAR_BUTTON, 17);
    }
    .width(BAR_WIDTH)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(18)
    .backgroundColor(BG_COLOR)
    .shadow({ radius: 16, color: '#66000000', offsetY: 4 });
  }

  // 视频通话：竖版小窗。远端画面铺满，底部压一条半透明信息/控制条。
  @Builder
  videoWindow() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.remoteVideoReady()) {
        XComponent({
          id: 'call_float_remote_video',
          type: XComponentType.TEXTURE,
          controller: this.remoteController
        })
          .onLoad((): void => {
            const surfaceId: string = this.remoteController.getXComponentSurfaceId();
            this.boundRemoteSurface = surfaceId;
            logI(`FloatingCallWindow remote surface bind ${surfaceId}`);
            getCallSession().setRemoteSurface(surfaceId);
          })
          .onDestroy((): void => {
            const surfaceId: string = this.remoteController.getXComponentSurfaceId();
            this.boundRemoteSurface = '0';
            logI(`FloatingCallWindow remote surface clear ${surfaceId}`);
            getCallSession().clearRemoteSurfaceIf(surfaceId);
          })
          .width('100%').height('100%');
      } else {
        // 占位：远端没有画面（连接中 / 对端关摄像头 / 仅音频轨）时不铺黑底，
        // 用头像 + 视频图标，形态上仍与语音横条一眼可分。
        Column({ space: 8 }) {
          AvatarView({
            avatarPath: '',
            initials: this.peerName().substring(0, 1).toUpperCase(),
            colorSeed: this.snap !== null ? this.snap.peerUserId : 0,
            avatarSize: 46
          });
          SymbolGlyph($r('sys.symbol.video'))
            .fontSize(18)
            .fontColor(['#B3FFFFFF']);
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      }

      // 左上角视频标识，和语音横条区分开。
      Row() {
        SymbolGlyph($r('sys.symbol.video_fill')).fontSize(11).fontColor([Color.White]);
      }
      .width(20).height(20).borderRadius(10)
      .backgroundColor(BADGE_BG)
      .justifyContent(FlexAlign.Center)
      .margin({ left: 6, top: 6 });

      // 底部信息 + 控件条（压满宽度，整块半透明黑）。
      Column({ space: 4 }) {
        Text(this.peerName())
          .fontSize(11).fontWeight(FontWeight.Medium).fontColor(Color.White)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
        Text(this.timeLine())
          .fontSize(10).fontColor(SUBTEXT).maxLines(1)
          .width('100%');
        Row({ space: 10 }) {
          this.muteButton(MINI_BUTTON, 15);
          this.hangupButton(MINI_BUTTON, 15);
        }
        .width('100%')
        .justifyContent(FlexAlign.Center);
      }
      .width('100%')
      .height('100%')
      .padding({ left: 6, right: 6, top: 8, bottom: 6 })
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.Start);
    }
    .width(VIDEO_WIDTH)
    .height(VIDEO_HEIGHT)
    .borderRadius(VIDEO_RADIUS)
    .clip(true)
    .backgroundColor(BG_COLOR)
    .shadow({ radius: 16, color: '#66000000', offsetY: 4 });
  }

  build() {
    Stack() {
      if (this.isVideoForm()) {
        this.videoWindow();
      } else {
        this.voiceBar();
      }
    }
    // translate 写在最后：拖动跟手，不经过任何尺寸动画。
    .translate({ x: this.dragX, y: this.dragY })
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.All, distance: 5 })
        .onActionStart((): void => {
          this.panStartX = this.dragX;
          this.panStartY = this.dragY;
        })
        .onActionUpdate((event: GestureEvent): void => this.onPanUpdate(event))
    )
    .onAreaChange((_old: Area, area: Area): void => this.onWindowArea(area))
    .onClick((): void => { this.restore(); });
  }
}
