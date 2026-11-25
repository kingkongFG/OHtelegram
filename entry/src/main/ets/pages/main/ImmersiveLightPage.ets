// 沉浸光感（外观设置 → 沉浸光感）
//
// 这一页是「外观设置」目录下光感那一片的汇总面板。此前这三块散在聊天设置页的
// 三张卡片里（浮层材质厚度 / 表面玻璃 / 光感等级），覆盖区域又藏在气泡样式页，
// 用户要调一个"光感"得翻三个地方。这里把它们收拢到一处，并补上系统材质的
// 能力探测——那个信息以前只能在日志里看。
//
// **写入的键与各消费方完全一致**，不新增任何设置语义：
//   · 厚度   KEY_MATERIAL_THICKNESS / _DARK   → util/overlayMaterial（面厚度与降级模糊半径）
//   · 光感   KEY_MATERIAL_LIGHT / _DARK       → util/hdsPointLight、util/hdsMaterialLevel
//   · 覆盖   KEY_GLASS_SCOPE_LIGHT_ON、GLASS_STORAGE_BUBBLE/FRAME → util/bubbleStyle 的 glassScope
// 所以这里改完立刻全局生效，不需要重启，也不需要各页各写一遍。
//
// 另：module.json5 里的 ohos.arkui.UIMaterial.state = enable 是应用级总闸，
// 决定 Dialog/Toast/Menu/Slider/Toggle/Select/SegmentButton 这批组件是否默认
// 挂系统材质。它在构建期生效，运行时改不了，所以这一页只做"显示"，不做开关
// （见 probeCard 的注释）。

import { router, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { appIsDark, KEY_MATERIAL_LIGHT_DARK, KEY_MATERIAL_THICKNESS_DARK } from '../../util/appearance';
import {
  KEY_MATERIAL_LIGHT, KEY_MATERIAL_THICKNESS, setBoolean, setNumber, setString
} from '../../store/AppSettings';
import { bumpSurfaceGlassEpoch } from '../../util/surfaceGlass';
import { bumpMaterialEpoch } from '../../util/materialEpoch';
import {
  LIGHT_ADAPTIVE, LIGHT_DEFAULT, LIGHT_EXQUISITE, LIGHT_GENTLE, LIGHT_SMOOTH,
  THICKNESS_DEFAULT, THICKNESS_OFF, THICKNESS_REGULAR, THICKNESS_THICK,
  THICKNESS_THIN, THICKNESS_ULTRA_THICK, THICKNESS_ULTRA_THIN
} from '../../util/materialTuning';
import {
  GLASS_STORAGE_BUBBLE, GLASS_STORAGE_FRAME, KEY_GLASS_SCOPE_LIGHT_ON
} from '../../util/bubbleStyle';
import { str } from '../../util/strings';
import { contentSideGutter } from '../../util/contentWidth';
import { HdsSubDestination } from '../common/HdsSubDestination';

const CARD_RADIUS: number = 14;
// ImmersiveMaterial 的引入版本。低于它，材质对象不存在，凡是"系统材质"的
// 描述都不该出现——这一页就退化成纯自绘玻璃的档位页。
const IMMERSIVE_MATERIAL_API: number = 26;

interface LevelOption {
  label: string;
  value: number;
}

interface LightOption {
  label: string;
  value: string;
}

// 从薄到厚，与 ImmersiveStyle 枚举次序一致；存的是相对偏移，"标准"是 0。
// label 复用聊天设置页那套字符串键，两处显示的档位名必须一致。
const THICKNESS_OPTIONS: LevelOption[] = [
  { label: str('material_thickness_off'), value: THICKNESS_OFF },
  { label: str('material_thickness_ultra_thin'), value: THICKNESS_ULTRA_THIN },
  { label: str('material_thickness_thin'), value: THICKNESS_THIN },
  { label: str('material_thickness_regular'), value: THICKNESS_REGULAR },
  { label: str('material_thickness_thick'), value: THICKNESS_THICK },
  { label: str('material_thickness_ultra_thick'), value: THICKNESS_ULTRA_THICK }
];

const LIGHT_OPTIONS: LightOption[] = [
  { label: str('material_light_smooth'), value: LIGHT_SMOOTH },
  { label: str('material_light_gentle'), value: LIGHT_GENTLE },
  { label: str('material_light_adaptive'), value: LIGHT_ADAPTIVE },
  { label: str('material_light_exquisite'), value: LIGHT_EXQUISITE }
];

@Entry
@Component
struct ImmersiveLightPage {
  private hdsScroller: Scroller = new Scroller();
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  // 深浅色切换要重画预览与同步下拉的当前值（厚度/光感按模式各存一份）。
  @StorageProp('appearanceEpoch') appearanceEpoch: number = 0;

  @StorageLink(KEY_MATERIAL_THICKNESS) thickness: number = THICKNESS_DEFAULT;
  @StorageLink(KEY_MATERIAL_THICKNESS_DARK) thicknessDark: number = THICKNESS_DEFAULT;
  @StorageLink(KEY_MATERIAL_LIGHT) light: string = LIGHT_DEFAULT;
  @StorageLink(KEY_MATERIAL_LIGHT_DARK) lightDark: string = LIGHT_DEFAULT;

  // 覆盖区域三片。默认值与出厂一致：光感开，气泡/框架玻璃关。
  @State scopeLight: boolean = true;
  @State scopeBubble: boolean = false;
  @State scopeFrame: boolean = false;

  // 系统材质能力探测结果。低版本设备上这几项取不到，保持 fallback 文案。
  @State probeDone: boolean = false;
  @State materialState: string = '';
  @State materialSupported: boolean = false;
  @State deviceLevel: string = '';
  private sdkApi: number = 0;

  aboutToAppear(): void {
    this.scopeLight = AppStorage.get<boolean>(KEY_GLASS_SCOPE_LIGHT_ON) ?? true;
    this.scopeBubble = AppStorage.get<boolean>(GLASS_STORAGE_BUBBLE) ?? false;
    this.scopeFrame = AppStorage.get<boolean>(GLASS_STORAGE_FRAME) ?? false;
    this.sdkApi = deviceInfo.sdkApiVersion;
    this.probe();
  }

  // 探测系统材质能力。三件事都在 API 26 起才有，且**成员解引用本身**在低版本
  // 运行时会抛（util/hdsTabsFloating 文件头记过同一类坑），所以先问版本，再包
  // try：宁可这一张卡显示"不支持"，也不能让整页白屏。
  private probe(): void {
    if (this.sdkApi < IMMERSIVE_MATERIAL_API) {
      this.probeDone = true;
      this.materialState = 'unsupported_os';
      this.materialSupported = false;
      this.deviceLevel = '';
      return;
    }
    try {
      const info: uiMaterial.MaterialInfo = uiMaterial.getMaterialInfo();
      this.materialState = info.state === uiMaterial.MaterialState.ENABLE ? 'enable'
        : (info.state === uiMaterial.MaterialState.DISABLE ? 'disable' : 'default');
      this.materialSupported = uiMaterial.isImmersiveMaterialSupported();
      const lv: uiMaterial.MaterialLevel = uiMaterial.getGlobalMaterialLevel();
      this.deviceLevel = lv === uiMaterial.MaterialLevel.EXQUISITE ? 'exquisite'
        : (lv === uiMaterial.MaterialLevel.GENTLE ? 'gentle' : 'smooth');
    } catch (e) {
      this.materialState = 'unknown';
      this.materialSupported = false;
      this.deviceLevel = '';
    }
    this.probeDone = true;
  }

  // ---------- 写 ----------

  private thicknessOf(forDark: boolean): number {
    return forDark ? this.thicknessDark : this.thickness;
  }

  private lightOf(forDark: boolean): string {
    return forDark ? this.lightDark : this.light;
  }

  private thicknessIndex(forDark: boolean): number {
    const idx = THICKNESS_OPTIONS.findIndex((o: LevelOption): boolean => o.value === this.thicknessOf(forDark));
    return idx < 0 ? 3 : idx;
  }

  private lightIndex(forDark: boolean): number {
    const idx = LIGHT_OPTIONS.findIndex((o: LightOption): boolean => o.value === this.lightOf(forDark));
    return idx < 0 ? 2 : idx;
  }

  // 存相对偏移，"标准"是 0——绝对档位会把各面调到同一厚度（弹窗跟着顶栏变薄
  // 就漏底了），理由见 util/materialTuning 文件头。
  private pickThickness(forDark: boolean, index: number): void {
    const v = THICKNESS_OPTIONS[index].value;
    if (forDark) {
      this.thicknessDark = v;
    } else {
      this.thickness = v;
    }
    setNumber(forDark ? KEY_MATERIAL_THICKNESS_DARK : KEY_MATERIAL_THICKNESS, v);
    // 厚度同时决定降级路径上的高斯模糊半径，两个纪元都要跳：材质纪元管
    // systemMaterial 的重挂，玻璃纪元管自绘玻璃的重算。
    bumpMaterialEpoch();
    bumpSurfaceGlassEpoch();
  }

  private pickLight(forDark: boolean, index: number): void {
    const v = LIGHT_OPTIONS[index].value;
    if (forDark) {
      this.lightDark = v;
    } else {
      this.light = v;
    }
    setString(forDark ? KEY_MATERIAL_LIGHT_DARK : KEY_MATERIAL_LIGHT, v);
    bumpMaterialEpoch();
  }

  private toggleScope(which: string): void {
    if (which === 'bubble') {
      this.scopeBubble = !this.scopeBubble;
      setBoolean(GLASS_STORAGE_BUBBLE, this.scopeBubble);
      bumpSurfaceGlassEpoch();
      return;
    }
    if (which === 'frame') {
      this.scopeFrame = !this.scopeFrame;
      setBoolean(GLASS_STORAGE_FRAME, this.scopeFrame);
      bumpSurfaceGlassEpoch();
      return;
    }
    this.scopeLight = !this.scopeLight;
    setBoolean(KEY_GLASS_SCOPE_LIGHT_ON, this.scopeLight);
    bumpMaterialEpoch();
  }

  // ---------- 小件 ----------

  @Builder
  cardTitle(title: ResourceStr, sub: ResourceStr) {
    Column({ space: 2 }) {
      Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
      Text(sub).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .alignItems(HorizontalAlign.Start).width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 4 });
  }

  @Builder
  probeRow(label: string, value: string, ok: boolean) {
    Row() {
      Text(label).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Text(value).fontSize(15)
        .fontColor(ok ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
    }
    .width('100%').padding({ left: 16, right: 16, top: 11, bottom: 11 });
  }

  @Builder
  pageNote(text: ResourceStr) {
    Text(text).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
      .width('100%').padding({ left: 4, right: 4 });
  }

  // ---------- 卡片 ----------

  // 能力探测。全部只读：module.json5 的应用级开关是构建期配置，运行时改不了，
  // 做成 Toggle 只会误导用户（见 CSDN 那篇踩坑记录：静态模块元数据不是业务开关）。
  @Builder
  probeCard() {
    Column() {
      this.cardTitle($r('app.string.il_probe_title'), $r('app.string.il_probe_sub'));
      this.probeRow(str('il_probe_state'), this.stateText(), this.stateOk());
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
      this.probeRow(str('il_probe_support'), this.materialSupported ? str('il_probe_yes') : str('il_probe_no'),
        this.materialSupported);
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
      this.probeRow(str('il_probe_level'), this.levelText(), this.deviceLevel.length > 0);
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
      this.probeRow(str('il_probe_sdk'), `${this.sdkApi}`, this.sdkApi >= IMMERSIVE_MATERIAL_API);
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .padding({ top: 4, bottom: 4 });
  }

  private stateText(): string {
    if (!this.probeDone) {
      return str('il_probe_probing');
    }
    switch (this.materialState) {
      case 'enable': return str('il_state_enable');
      case 'disable': return str('il_state_disable');
      case 'default': return str('il_state_default');
      case 'unsupported_os': return str('il_state_no_os');
      default: return str('il_probe_unknown');
    }
  }

  private stateOk(): boolean {
    return this.materialState === 'enable' || this.materialState === 'default';
  }

  private levelText(): string {
    switch (this.deviceLevel) {
      case 'exquisite': return str('il_level_exquisite');
      case 'gentle': return str('il_level_gentle');
      case 'smooth': return str('il_level_smooth');
      default: return str('il_probe_unknown');
    }
  }

  // 光感等级：决定流光/按压反馈给多广（见 util/materialTuning 的 lightEffectOn）。
  // 浅色深色各一行——它和壁纸一样是"按模式"的，深色下给太强的光会脏。
  @Builder
  lightCard() {
    Column() {
      this.cardTitle($r('app.string.il_light_title'), $r('app.string.il_light_sub'));
      this.lightRow(false);
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
      this.lightRow(true);
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .padding({ top: 4, bottom: 12 });
  }

  @Builder
  lightRow(forDark: boolean) {
    Row({ space: 12 }) {
      Text(forDark ? str('il_mode_dark') : str('il_mode_light'))
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Select(LIGHT_OPTIONS.map((o: LightOption): SelectOption => ({ value: o.label } as SelectOption)))
        .selected(this.lightIndex(forDark))
        .value(LIGHT_OPTIONS[this.lightIndex(forDark)].label)
        .font({ size: 14 })
        .onSelect((index: number): void => { this.pickLight(forDark, index); });
    }
    .width('100%').padding({ left: 16, right: 12, top: 8, bottom: 8 });
  }

  // 浮层材质厚度：顶栏胶囊、输入框、菜单、弹窗各自有一档基准厚度，这里的偏移
  // 是整体平移，保住它们之间的相对次序。
  @Builder
  thicknessCard() {
    Column() {
      this.cardTitle($r('app.string.il_thickness_title'), $r('app.string.il_thickness_sub'));
      this.thicknessRow(false);
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
      this.thicknessRow(true);
      this.pageNote($r('app.string.il_thickness_note'));
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .padding({ top: 4, bottom: 12 });
  }

  @Builder
  thicknessRow(forDark: boolean) {
    Row({ space: 12 }) {
      Text(forDark ? str('il_mode_dark') : str('il_mode_light'))
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Select(THICKNESS_OPTIONS.map((o: LevelOption): SelectOption => ({ value: o.label } as SelectOption)))
        .selected(this.thicknessIndex(forDark))
        .value(THICKNESS_OPTIONS[this.thicknessIndex(forDark)].label)
        .font({ size: 14 })
        .onSelect((index: number): void => { this.pickThickness(forDark, index); });
    }
    .width('100%').padding({ left: 16, right: 12, top: 8, bottom: 8 });
  }

  // 覆盖区域：光感到底铺到哪些面。这是"全域光感"的实际开关，和气泡样式页
  // 里那三片是同一组键——两处修改互相同步（都走 @StorageLink / AppStorage）。
  @Builder
  scopeCard() {
    Column() {
      this.cardTitle($r('app.string.il_scope_title'), $r('app.string.il_scope_sub'));
      this.scopeRow($r('app.string.il_scope_light'), $r('app.string.il_scope_light_sub'), this.scopeLight, 'light');
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
      this.scopeRow($r('app.string.il_scope_bubble'), $r('app.string.il_scope_bubble_sub'), this.scopeBubble, 'bubble');
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
      this.scopeRow($r('app.string.il_scope_frame'), $r('app.string.il_scope_frame_sub'), this.scopeFrame, 'frame');
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .padding({ top: 4, bottom: 4 });
  }

  @Builder
  scopeRow(title: ResourceStr, sub: ResourceStr, on: boolean, which: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
        Text(sub).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor(COLOR_PRIMARY)
        .onChange((): void => { this.toggleScope(which); });
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 });
  }

  // 预览：一条自绘的气泡带 + 一个浮层面板，铺在同一张渐变底上。它照的是
  // 当前光感开关的效果近似（预览永远不能等于真机材质），作用只是让用户点完
  // 下拉立刻看到"厚一点/薄一点"的差别，不用退回聊天页找感觉。
  @Builder
  previewCard() {
    Column() {
      this.cardTitle($r('app.string.il_preview_title'), $r('app.string.il_preview_sub'));
      Stack() {
        Column()
          .width('100%').height('100%')
          .linearGradient({
            angle: 135,
            colors: appIsDark()
              ? [['#FF1B2733', 0.0], ['#FF2B5278', 0.55], ['#FF57A8F2', 1.0]]
              : [['#FFE1FFC7', 0.0], ['#FF3390EC', 0.55], ['#FFAF52DE', 1.0]]
          });
        Column({ space: 8 }) {
          Row() {
            Text(str('il_preview_bubble')).fontSize(13)
              .fontColor(COLOR_TEXT_PRIMARY)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(this.scopeBubble ? $r('app.color.bubble_in') : COLOR_SURFACE)
              .borderRadius(14);
          }
          .width('100%').justifyContent(FlexAlign.Start);
          Row() {
            Text(str('il_preview_panel')).fontSize(13)
              .fontColor(COLOR_TEXT_PRIMARY)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(COLOR_SURFACE)
              .borderRadius(12)
              .opacity(this.scopeLight ? 0.82 : 1.0);
          }
          .width('100%').justifyContent(FlexAlign.End);
        }
        .width('100%').padding(14);
      }
      .width('100%').height(132).borderRadius(CARD_RADIUS).clip(true);
      this.pageNote($r('app.string.il_note'));
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .padding({ top: 4, bottom: 12 });
  }

  build() {
    Column() {
      HdsSubDestination({
        title: $r('app.string.il_page_title'),
        scroller: this.hdsScroller,
        onBack: (): void => { router.back(); }
      }) {
        Scroll(this.hdsScroller) {
          Column({ space: 14 }) {
            this.previewCard();
            this.lightCard();
            this.thicknessCard();
            this.scopeCard();
            this.probeCard();
          }
          .width('100%').padding({
            left: 12 + contentSideGutter(this.screenW),
            right: 12 + contentSideGutter(this.screenW),
            top: 8, bottom: this.bottomSafe + 24
          });
        }
        .align(Alignment.Top)
        .layoutWeight(1).width('100%').scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring).clip(false);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}

// 路由表（router_map.json）的 buildFunction 指向这里。
@Builder
export function ImmersiveLightPageBuilder(): void {
  ImmersiveLightPage();
}
