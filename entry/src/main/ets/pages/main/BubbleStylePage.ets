// 聊天气泡外观（外观设置 → 聊天气泡）
//
// 这一页把原来散在「聊天设置」里那一根圆角滑杆，扩成三组预设 + 一片沉浸光感
// 的覆盖区域：
//   · 形状 5 档 —— 写 KEY_BUBBLE_RADIUS（外加连体角/尾角两个上限，见 bubbleStyle）
//   · 配色 6 档 —— 写 KEY_BUBBLE_PALETTE，appearance.bubbleCustomised 认它
//   · 渐变 7 档 —— 写 KEY_BUBBLE_GRADIENT，util/chatBubbleGradient 现读现用
//   · 覆盖区域 3 片 —— 各自写**已经存在且真的有人读**的那三个开关（见 GLASS_SCOPES）
//
// 每一档都必须真生效：选完立刻写键 + recomputeAppearance()（它会 bump
// appearanceEpoch，V2 气泡子树读的就是那个值，所以要这一下才重绘）。

import { router } from '@kit.ArkUI';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY,
  COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { appIsDark, recomputeAppearance } from '../../util/appearance';
import { setBoolean, setNumber, setString, KEY_BUBBLE_RADIUS } from '../../store/AppSettings';
import { bumpSurfaceGlassEpoch } from '../../util/surfaceGlass';
import { bumpMaterialEpoch } from '../../util/materialEpoch';
import {
  BUBBLE_SHAPES, BUBBLE_PALETTES, BUBBLE_GRADIENTS, GLASS_SCOPES,
  BubbleShape, BubblePalette, BubbleGradient, GlassScope,
  KEY_BUBBLE_SHAPE, KEY_BUBBLE_PALETTE, KEY_BUBBLE_GRADIENT,
  KEY_BUBBLE_GRADIENT_CUSTOM, KEY_BUBBLE_GRADIENT_CUSTOM_LIGHT,
  KEY_GLASS_SCOPE_LIGHT_ON,
  SHAPE_CLASSIC, PALETTE_THEME, GRADIENT_DEFAULT,
  GRADIENT_NONE, GRADIENT_CUSTOM,
  GLASS_SCOPE_BUBBLE, GLASS_SCOPE_FRAME,
  GLASS_STORAGE_BUBBLE, GLASS_STORAGE_FRAME,
  bubbleShapeOf, bubblePaletteOf, bubbleGradientOf, bubbleGradientCustomBand
} from '../../util/bubbleStyle';
import { bubbleGradientColorsAt } from '../../util/chatBubbleGradient';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { contentSideGutter } from '../../util/contentWidth';
import { HdsSubDestination } from '../common/HdsSubDestination';

const CARD_RADIUS: number = 14;
// 预览气泡的最大宽度。定死而不是按屏宽算：这是个示意图，跟着变宽只会在平板上
// 变成两条长条，反而看不出形状。
const PREVIEW_W: number = 196;

// 「自定义」渐变档的取色盘：24 枚，冷到暖各来一遍，够拼出官方 Telegram 那类
// 多段色带。点色板 = 替换当前选中的那枚色标（见 applySwatch）。
const CUSTOM_SWATCHES: string[] = [
  '#FF8B5CF6', '#FF7C3AED', '#FF6366F1', '#FF4F46E5', '#FF3B82F6', '#FF2F6FE0',
  '#FF0EA5E9', '#FF06B6D4', '#FF14B8A6', '#FF22C55E', '#FF84CC16', '#FFEAB308',
  '#FFF59E0B', '#FFF97316', '#FFEF4444', '#FFE11D48', '#FFEC4899', '#FFD946EF',
  '#FFA855F7', '#FF64748B', '#FF94A3B8', '#FF334155', '#FFF1F5F9', '#FFFFFFFF'
];

@Entry
@Component
struct BubbleStylePage {
  // 标题栏由 HdsSubDestination 画（和外观设置页同一套），它自己吃安全区、
  // 自己给内容限宽，所以这一页不再自己算 topSafe。
  private hdsScroller: Scroller = new Scroller();
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  // 深浅色切换要让预览重画（预览用的是 hex，不跟资源色走）。
  @StorageProp('appearanceEpoch') appearanceEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;

  // 三组预设的当前值。@State 副本而不是直接读 AppStorage：这一页要在点选的
  // 瞬间换选中态，读 AppStorage 得等下一轮刷新才动。
  @State shapeId: string = SHAPE_CLASSIC;
  @State paletteId: string = PALETTE_THEME;
  @State gradientId: string = GRADIENT_DEFAULT;
  // 「自定义」档的色带：编辑的是**当前主题**那一条（深色写 KEY_..._CUSTOM，
  // 浅色写 _LIGHT），和 util/bubbleStyle 读写的是同一对键。customPick 是正在
  // 改的色标下标，只影响这一页的选中描边。
  @State customBand: string[] = [];
  @State customPick: number = 0;

  // 覆盖区域三片。默认值与三个开关键出厂值一致（气泡/框架默认关、光感默认开）。
  @State scopeBubble: boolean = false;
  @State scopeFrame: boolean = false;
  @State scopeLight: boolean = true;

  aboutToAppear(): void {
    this.shapeId = AppStorage.get<string>(KEY_BUBBLE_SHAPE) ?? SHAPE_CLASSIC;
    this.paletteId = AppStorage.get<string>(KEY_BUBBLE_PALETTE) ?? PALETTE_THEME;
    this.gradientId = AppStorage.get<string>(KEY_BUBBLE_GRADIENT) ?? GRADIENT_DEFAULT;
    this.scopeBubble = AppStorage.get<boolean>(GLASS_STORAGE_BUBBLE) ?? false;
    this.scopeFrame = AppStorage.get<boolean>(GLASS_STORAGE_FRAME) ?? false;
    this.scopeLight = AppStorage.get<boolean>(KEY_GLASS_SCOPE_LIGHT_ON) ?? true;
    this.customBand = bubbleGradientCustomBand(appIsDark());
  }

  // ---------- 写 ----------

  private pickShape(id: string): void {
    this.shapeId = id;
    setString(KEY_BUBBLE_SHAPE, id);
    // 形状的主圆角落在原来那根滑杆的同一个键上：不这么做，"形状"和"圆角"
    // 会变成两套互相打架的数值。
    setNumber(KEY_BUBBLE_RADIUS, bubbleShapeOf(id).radius);
    recomputeAppearance();
  }

  private pickPalette(id: string): void {
    this.paletteId = id;
    setString(KEY_BUBBLE_PALETTE, id);
    // 配色要靠 recomputeAppearance 把 hex 重新绑到 theme 上（见 appearance）。
    recomputeAppearance();
  }

  private pickGradient(id: string): void {
    this.gradientId = id;
    setString(KEY_BUBBLE_GRADIENT, id);
    // 渐变没有自己的纪元，借 appearanceEpoch 让气泡子树重画一次。
    recomputeAppearance();
  }

  private toggleScope(scope: GlassScope): void {
    if (scope.id === GLASS_SCOPE_BUBBLE) {
      this.scopeBubble = !this.scopeBubble;
      setBoolean(GLASS_STORAGE_BUBBLE, this.scopeBubble);
      bumpSurfaceGlassEpoch();
      return;
    }
    if (scope.id === GLASS_SCOPE_FRAME) {
      this.scopeFrame = !this.scopeFrame;
      setBoolean(GLASS_STORAGE_FRAME, this.scopeFrame);
      bumpSurfaceGlassEpoch();
      return;
    }
    this.scopeLight = !this.scopeLight;
    setBoolean(KEY_GLASS_SCOPE_LIGHT_ON, this.scopeLight);
    // 光感走 hdsEffect 那条路，缓存按材质纪元分代（见 util/hdsPointLight）。
    bumpMaterialEpoch();
  }

  // ---------- 自定义色带（「自定义」渐变档） ----------
  //
  // 色标 2~6 枚，按顺序首尾相接（最后再接回第一枚，见 util/bubbleStyle.parseCustomBand
  // 与 chatBubbleGradient.sampleGradientBand 的 wrap 取色）。写入的就是气泡真正读的
  // 那两个键，写完 recomputeAppearance() 让 appearanceEpoch 跳一下，气泡子树重绘。
  private customBandKey(): string {
    return appIsDark() ? KEY_BUBBLE_GRADIENT_CUSTOM : KEY_BUBBLE_GRADIENT_CUSTOM_LIGHT;
  }
  private writeCustomBand(next: string[]): void {
    this.customBand = next;
    setString(this.customBandKey(), next.join(','));
    recomputeAppearance();
  }
  private pickBandStop(index: number): void {
    this.customPick = index;
  }
  // 点色板：把当前选中的那枚色标换掉。
  private applySwatch(color: string): void {
    if (this.customBand.length === 0) {
      return;
    }
    const next: string[] = this.customBand.slice();
    const at: number = Math.min(this.customPick, next.length - 1);
    next[at] = color;
    this.writeCustomBand(next);
  }
  // 加一枚：复制当前选中色，插在它后面，用户再点色板就是"从这枚开始变出去的第三色"。
  private addBandStop(): void {
    if (this.customBand.length >= 6) {
      return;
    }
    const next: string[] = this.customBand.slice();
    const at: number = Math.min(this.customPick, next.length - 1);
    next.splice(at + 1, 0, next[at]);
    this.customPick = at + 1;
    this.writeCustomBand(next);
  }
  private removeBandStop(): void {
    if (this.customBand.length <= 2) {
      return;
    }
    const next: string[] = this.customBand.slice();
    next.splice(Math.min(this.customPick, next.length - 1), 1);
    this.customPick = 0;
    this.writeCustomBand(next);
  }

  private scopeOn(scope: GlassScope): boolean {
    if (scope.id === GLASS_SCOPE_BUBBLE) { return this.scopeBubble; }
    if (scope.id === GLASS_SCOPE_FRAME) { return this.scopeFrame; }
    return this.scopeLight;
  }

  // ---------- 预览配色 ----------

  // 两端色。选了「无」或者拿到空数组，就用配色的那一支实色平铺（首尾同色）。
  private endColor(outgoing: boolean, tail: boolean): string {
    const gradient: BubbleGradient = bubbleGradientOf(this.gradientId);
    const dark: boolean = appIsDark();
    const colors: string[] = gradient.id === GRADIENT_NONE ? []
      : (dark ? (outgoing ? gradient.outDark : gradient.inDark)
              : (outgoing ? gradient.outLight : gradient.inLight));
    if (colors.length >= 2) {
      return tail ? colors[1] : colors[0];
    }
    const palette: BubblePalette = bubblePaletteOf(this.paletteId);
    if (dark) {
      return outgoing ? palette.outDark : palette.inDark;
    }
    return outgoing ? palette.out : palette.in;
  }

  private hasGradient(): boolean {
    return this.gradientId !== GRADIENT_NONE;
  }

  // 预览气泡的圆角：形状档的主圆角按预览高度缩一点，免得 24 的胶囊档在 34 高的
  // 示意块上直接变成半个圆看不出形状差。
  private previewRadius(): number {
    return Math.min(bubbleShapeOf(this.shapeId).radius, 15);
  }

  private previewRadius2(): number {
    return Math.min(bubbleShapeOf(this.shapeId).radius, 12);
  }

  // ---------- UI ----------

  @Builder
  previewBubble(outgoing: boolean, rowIndex: number) {
    Row() {
      Text(outgoing ? str('appearance_bubble_style_preview_out') : str('appearance_bubble_style_preview_in'))
        .fontSize(14).fontColor(outgoing ? Color.White : COLOR_TEXT_PRIMARY)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .constraintSize({ maxWidth: PREVIEW_W })
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    // 靠头像那一侧小一点，和真气泡的尾角上限同一个方向（tailCap 通常 2~12）。
    .borderRadius({
      topLeft: this.previewRadius(), topRight: this.previewRadius2(),
      bottomLeft: this.previewRadius(), bottomRight: this.previewRadius2()
    })
    // 【Beta8】预览和真气泡同一套取色：按行号在色带上取一段（见
    // util/chatBubbleGradient.bubbleGradientColorsAt）。原来这里取的是"首色→末色"，
    // 每个气泡都一样，看不出"随纵向位置变化"这回事，预览也就不再真。
    .linearGradient({
      angle: 180,
      colors: this.previewStops(outgoing, rowIndex)
    })
    // 气泡那片勾上了就描一道高光，表示"它会有一层玻璃"。
    .border(this.scopeBubble ? { width: 1, color: '#59FFFFFF' } : { width: 0, color: Color.Transparent })
    .clip(true);
  }

  private previewStops(outgoing: boolean, rowIndex: number): Array<[string, number]> {
    if (this.gradientId === GRADIENT_NONE) {
      return [[this.endColor(outgoing, false), 0.0], [this.endColor(outgoing, true), 1.0]];
    }
    const colors: string[] = bubbleGradientColorsAt(outgoing, appIsDark(), rowIndex);
    if (colors.length < 2) {
      return [[this.endColor(outgoing, false), 0.0], [this.endColor(outgoing, true), 1.0]];
    }
    return [[colors[0], 0.0], [colors[colors.length - 1], 1.0]];
  }

  // 预览画四行：行号 0 / 4 / 8 / 12，正好走完一圈色带的四分之三，
  // 左右交替——用户一眼能看到"同一套色带在纵轴上怎么流"。
  @Builder
  previewCard() {
    Column({ space: 8 }) {
      Row() {
        Blank();
        this.previewBubble(true, 0);
      }.width('100%').justifyContent(FlexAlign.End);
      Row() {
        this.previewBubble(false, 4);
        Blank();
      }.width('100%').justifyContent(FlexAlign.Start);
      Row() {
        Blank();
        this.previewBubble(true, 8);
      }.width('100%').justifyContent(FlexAlign.End);
      Row() {
        this.previewBubble(false, 12);
        Blank();
      }.width('100%').justifyContent(FlexAlign.Start);
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 14, bottom: 14 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  sectionTitle(key: string) {
    Text(str(key))
      .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').padding({ left: 4, bottom: 6 });
  }

  @Builder
  shapeTile(shape: BubbleShape) {
    Column({ space: 6 }) {
      Row() {}
      .width(46).height(24)
      .backgroundColor(this.shapeId === shape.id ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
      .opacity(this.shapeId === shape.id ? 1 : 0.45)
      .borderRadius(Math.min(shape.radius, 12));
      Text(str(shape.labelKey)).fontSize(12)
        .fontColor(this.shapeId === shape.id ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%').padding({ top: 10, bottom: 10 })
    .backgroundColor(this.shapeId === shape.id ? $r('app.color.divider') : Color.Transparent)
    .borderRadius(10)
    .onClick((): void => { this.pickShape(shape.id); });
  }

  @Builder
  paletteTile(palette: BubblePalette) {
    Column({ space: 6 }) {
      Row({ space: 3 }) {
        Row() {}
        .width(22).height(18)
        .backgroundColor(appIsDark() ? palette.outDark : palette.out)
        .borderRadius({ topLeft: 6, topRight: 6, bottomLeft: 6, bottomRight: 2 });
        Row() {}
        .width(22).height(18)
        .backgroundColor(appIsDark() ? palette.inDark : palette.in)
        .borderRadius({ topLeft: 6, topRight: 2, bottomLeft: 6, bottomRight: 6 })
        .border({ width: 0.7, color: $r('app.color.divider') });
      };
      Text(str(palette.labelKey)).fontSize(12)
        .fontColor(this.paletteId === palette.id ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%').padding({ top: 10, bottom: 10 })
    .backgroundColor(this.paletteId === palette.id ? $r('app.color.divider') : Color.Transparent)
    .borderRadius(10)
    .onClick((): void => { this.pickPalette(palette.id); });
  }

  // 色块画整条色带（每一枚色标都落在对应位置），不再只画首末两色——多段色带
  // 在卡片上也能看出中间那段。
  private tileStops(gradient: BubbleGradient): Array<[string, number]> {
    const colors: string[] = gradient.id === GRADIENT_CUSTOM
      ? this.customBand
      : (appIsDark() ? gradient.outDark : gradient.outLight);
    if (colors.length < 2) {
      return [['#B8BEC7', 0.0], ['#8F97A3', 1.0]];
    }
    const stops: Array<[string, number]> = [];
    for (let i = 0; i < colors.length; i++) {
      stops.push([colors[i], i / (colors.length - 1)]);
    }
    return stops;
  }

  @Builder
  gradientTile(gradient: BubbleGradient) {
    Column({ space: 6 }) {
      Row() {}
      .width(46).height(14).borderRadius(7)
      .linearGradient({
        angle: 0,
        colors: this.tileStops(gradient)
      });
      Text(str(gradient.labelKey)).fontSize(12)
        .fontColor(this.gradientId === gradient.id ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%').padding({ top: 10, bottom: 10 })
    .backgroundColor(this.gradientId === gradient.id ? $r('app.color.divider') : Color.Transparent)
    .borderRadius(10)
    .onClick((): void => { this.pickGradient(gradient.id); });
  }

  @Builder
  shapeCard() {
    Column({ space: 4 }) {
      this.sectionTitle('appearance_bubble_shape_title');
      Column() {
        GridRow({ columns: 5, gutter: 6 }) {
          ForEach(BUBBLE_SHAPES, (shape: BubbleShape): void => {
            GridCol({ span: 1 }) {
              this.shapeTile(shape);
            };
          }, (shape: BubbleShape): string => shape.id);
        }
        .width('100%');
      }
      .width('100%')
      .padding(6)
      .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
    }
    .width('100%');
  }

  @Builder
  paletteCard() {
    Column({ space: 4 }) {
      this.sectionTitle('appearance_bubble_palette_title');
      Column() {
        GridRow({ columns: 3, gutter: 8 }) {
          ForEach(BUBBLE_PALETTES, (palette: BubblePalette): void => {
            GridCol({ span: 1 }) {
              this.paletteTile(palette);
            };
          }, (palette: BubblePalette): string => palette.id);
        }
        .width('100%');
      }
      .width('100%')
      .padding(6)
      .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
    }
    .width('100%');
  }

  // 「自定义」渐变档的色带编辑器：只在选中该档时出现，不选就不占位置。
  // 写键 → recomputeAppearance()，与形状/配色/其它渐变档同一条生效链路。
  @Builder
  bandCard() {
    if (this.gradientId === GRADIENT_CUSTOM && this.customBand.length >= 2) {
      Column({ space: 4 }) {
        this.sectionTitle('appearance_gradient_custom_title');
        Column({ space: 12 }) {
          // 色带本体：一枚色标一格，点它选中，之后点色板替换的就是它
          Row({ space: 6 }) {
            ForEach(this.customBand, (color: string, index: number): void => {
              Stack() {}
              .width(30).height(26)
              .backgroundColor(color)
              .borderRadius(7)
              .border({
                width: this.customPick === index ? 2 : 0.7,
                color: this.customPick === index ? COLOR_PRIMARY : $r('app.color.divider')
              })
              .onClick((): void => { this.pickBandStop(index); });
            }, (color: string, index: number): string => `${index}_${color}`);
            Blank();
            Text(str('appearance_gradient_custom_add'))
              .fontSize(12).fontColor(COLOR_PRIMARY)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor($r('app.color.divider')).borderRadius(8)
              .onClick((): void => { this.addBandStop(); });
            Text(str('appearance_gradient_custom_remove'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor($r('app.color.divider')).borderRadius(8)
              .onClick((): void => { this.removeBandStop(); });
          }
          .width('100%');
          // 取色盘
          GridRow({ columns: 8, gutter: 6 }) {
            ForEach(CUSTOM_SWATCHES, (color: string): void => {
              GridCol({ span: 1 }) {
                Stack() {}
                .width('100%').height(28)
                .backgroundColor(color)
                .borderRadius(8)
                .border({ width: 0.7, color: $r('app.color.divider') })
                .onClick((): void => { this.applySwatch(color); });
              };
            }, (color: string): string => color);
          }
          .width('100%');
          Text(str('appearance_gradient_custom_hint'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(17)
            .width('100%');
        }
        .width('100%')
        .padding(12)
        .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
      }
      .width('100%');
    }
  }

  @Builder
  gradientCard() {
    Column({ space: 4 }) {
      this.sectionTitle('appearance_bubble_gradient_title');
      Column() {
        GridRow({ columns: 4, gutter: 8 }) {
          ForEach(BUBBLE_GRADIENTS, (gradient: BubbleGradient): void => {
            GridCol({ span: 1 }) {
              this.gradientTile(gradient);
            };
          }, (gradient: BubbleGradient): string => gradient.id);
        }
        .width('100%');
      }
      .width('100%')
      .padding(6)
      .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
    }
    .width('100%');
  }

  @Builder
  scopeRow(scope: GlassScope, last: boolean) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(str(scope.labelKey)).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
        Text(str(scope.subKey)).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      // 勾选框自绘：Toggle 在这一列里比文字还高，视觉上对不齐。
      Stack() {
        if (this.scopeOn(scope)) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([Color.White]);
        }
      }
      .width(22).height(22).borderRadius(11)
      .backgroundColor(this.scopeOn(scope) ? COLOR_PRIMARY : Color.Transparent)
      .border({
        width: this.scopeOn(scope) ? 0 : 1.5,
        color: this.scopeOn(scope) ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY
      });
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => { this.toggleScope(scope); });

    if (!last) {
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 14 });
    }
  }

  @Builder
  glassCard() {
    Column({ space: 4 }) {
      this.sectionTitle('appearance_bubble_glass_title');
      Column() {
        ForEach(GLASS_SCOPES, (scope: GlassScope, index: number): void => {
          this.scopeRow(scope, index === GLASS_SCOPES.length - 1);
        }, (scope: GlassScope): string => scope.id);
        Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 14 });
        Text(str('appearance_bubble_glass_sub'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
          .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 12 });
      }
      .width('100%')
      .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
    }
    .width('100%');
  }

  // 预设不是「跟随主题」时，上一页那四行自定义取色器会被整档接管（见
  // appearance.ets 的 paletteOverride）。写在这里而不是丢给用户自己猜。
  @Builder
  customCard() {
    if (this.paletteId !== PALETTE_THEME) {
      Text(str('appearance_bubble_preset_hint'))
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(17)
        .width('100%').padding({ left: 4, right: 4 });
    }
  }

  build() {
    Column() {
      HdsSubDestination({
        title: str('settings_bubble_style'),
        scroller: this.hdsScroller,
        // 这是 router 页，不是 NavDestination：默认的 popSelf() 出的是 Navigation
        // 栈，在这一页上什么都不会发生，必须显式退回 router 栈。
        onBack: (): void => { router.back(); }
      }) {
        Scroll(this.hdsScroller) {
          Column({ space: 14 }) {
            this.previewCard();
            this.shapeCard();
            this.paletteCard();
            this.gradientCard();
            this.bandCard();
            this.customCard();
            this.glassCard();
            Text(str('appearance_bubble_style_note'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
              .width('100%').padding({ left: 4, right: 4 });
          }
          .width('100%')
          .padding({
            left: 12 + contentSideGutter(this.screenW),
            right: 12 + contentSideGutter(this.screenW),
            top: 8, bottom: this.bottomSafe + 24
          });
        }
        .align(Alignment.Top)
        .layoutWeight(1).width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .clip(false);
      }
    }
    .width('100%').height('100%')
    .backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
