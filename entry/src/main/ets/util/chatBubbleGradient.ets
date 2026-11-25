import { gradientStops } from './backgroundPresentation';
import { bubbleGradientBand, bubbleGradientColorsFor, bubbleGradientCycle, bubbleGradientOff } from './bubbleStyle';

// Beta2：1 对 1 对话页的夜间深蓝底 + 普通文本气泡的渐变填充。
//
// 只服务「1 对 1 的普通文本气泡」这一种情形：通话记录气泡、系统胶囊、媒体 /
// 文件 / 语音条、引用块、链接预览、贴纸与表情大图一律不走这里，保持原有纯色
// 与材质逻辑（见 MessageBubble / LightweightPlainTextBubble 的调用点判据）。
//
// 【Beta3 第 2 批】按参考图（微信图片_20261105002155_59_21.jpg）重定取值：
//   · 对方（左）气泡 = 深灰**纯色** #2D3142，不再走渐变；
//   · 自己（右）气泡 = 紫蓝渐变 #7E4CC1 → #6A5ACD（原来是蓝 → 亮蓝）；
//   · 通话记录 / 系统服务气泡 = 深蓝 #1A2B4A；
//   · 浅色主题各给一套同色相的浅色版，保证深色下白字、浅色下黑字都可读。
// 所有色值只在这里定义，组件侧一律通过下面三个函数取值，禁止再写散落字面量。

// 【Beta7 2026-11-05】统一成「紫 ↔ 蓝」两极，双方都走渐变，方向相反：
//   · 自己（右）：顶部紫 → 底部蓝；
//   · 对方（左）：顶部蓝 → 底部紫。
// 两极取同一个紫、同一个蓝，只交换顺序——这样左右气泡在视觉上是一对镜像，
// 不会出现「自己偏紫、对方偏另一个色系」的不协调。
const GRADIENT_PURPLE: string = '#FF8B5CF6';
const GRADIENT_BLUE: string = '#FF2F6FE0';
// 浅色主题的同色相版本：白底上要留得住黑字，所以彩度压到只够辨认色相。
const GRADIENT_PURPLE_LIGHT: string = '#FFE2D5FB';
const GRADIENT_BLUE_LIGHT: string = '#FFD3E3FD';

// 深色（夜间）——自己：紫 → 蓝
export const BUBBLE_GRADIENT_OUT_DARK: string[] = [GRADIENT_PURPLE, GRADIENT_BLUE];
// 浅色——自己：浅紫 → 浅蓝
export const BUBBLE_GRADIENT_OUT_LIGHT: string[] = [GRADIENT_PURPLE_LIGHT, GRADIENT_BLUE_LIGHT];

// 对方气泡的单色兜底（渐变不可用时才会被看到，例如贴纸/表情大图路径）
export const BUBBLE_IN_SOLID_DARK: string = '#FF2D3142';
export const BUBBLE_IN_SOLID_LIGHT: string = '#FFEFF1F5';

// 通话记录 / 系统服务气泡的单色兜底
export const BUBBLE_CALL_SOLID_DARK: string = '#FF1A2B4A';
export const BUBBLE_CALL_SOLID_LIGHT: string = '#FFE3EAF6';

// 对方：与自己反序（蓝 → 紫）
const BUBBLE_GRADIENT_IN_DARK: string[] = [GRADIENT_BLUE, GRADIENT_PURPLE];
const BUBBLE_GRADIENT_IN_LIGHT: string[] = [GRADIENT_BLUE_LIGHT, GRADIENT_PURPLE_LIGHT];

// 渐变角度：90° = 自上而下。需求是「顶部紫到底部蓝」，不做斜向过渡。
export const BUBBLE_GRADIENT_ANGLE: number = 180;

// 跟随系统（既没有自定义色彩也没有壁纸）时的兜底底色，深/浅各一套。
// 深色用 Telegram 夜间同系深蓝（#0E1621 → #17212B），浅色是同色相的浅蓝。
export const CHAT_BG_FALLBACK_DARK: string[] = ['#FF0E1621', '#FF17212B'];
export const CHAT_BG_FALLBACK_LIGHT: string[] = ['#FFEDF2F9', '#FFE2EAF4'];
export const CHAT_BG_FALLBACK_ANGLE: number = 160;

// 渐变开关关闭时用的全透明双 stop：ArkUI 的 linearGradient 单 stop 画不出东西，
// 而属性链上又不能按条件挂载，所以关闭态一律喂这一对透明色——视觉上等于没有
// 渐变，填充继续由 backgroundColor 负责（玻璃档、其他消息类型都走这条）。
export const BUBBLE_GRADIENT_OFF: Array<[string, number]> = [['#00000000', 0], ['#00000000', 1]];
const GRADIENT_OFF: Array<[string, number]> = BUBBLE_GRADIENT_OFF;

// 【Beta7 · 多套渐变】色相不再写死在这里，改由外观设置里的「渐变」预设给
// （见 util/bubbleStyle 的 BUBBLE_GRADIENTS）。上面那几对常量仍是出厂档
// 「紫 ↔ 蓝」，保留下来只做两件事：预设表的数据来源、以及"选了无渐变但
// 被别处误调"时有个确定的返回值（尾巴取末色那条路径要它）。
export function bubbleGradientColors(outgoing: boolean, dark: boolean): string[] {
  const preset: string[] = bubbleGradientColorsFor(outgoing, dark);
  if (preset.length >= 2) {
    return preset;
  }
  if (outgoing) {
    return dark ? BUBBLE_GRADIENT_OUT_DARK : BUBBLE_GRADIENT_OUT_LIGHT;
  }
  return dark ? BUBBLE_GRADIENT_IN_DARK : BUBBLE_GRADIENT_IN_LIGHT;
}

// 渐变是否被用户关掉（"无渐变"档）。气泡组件的 gradientBubbleOn() 读它：
// 关掉之后这些气泡整体退回纯色 + 玻璃材质，与加渐变之前逐字一致。
export function bubbleGradientDisabled(): boolean {
  return bubbleGradientOff();
}

export function bubbleGradientStops(outgoing: boolean, dark: boolean, enabled: boolean): Array<[string, number]> {
  if (!enabled) {
    return GRADIENT_OFF;
  }
  return gradientStops(bubbleGradientColors(outgoing, dark));
}

// 渐变档下尾巴的填充色：取靠尾巴那一端的颜色，拼缝处才不会出现第二种色相。
// 两端尾巴都在气泡底部（对方左下、自己右下），而 Beta7 的渐变是自上而下的
// 90°，所以双方一律取末色。渐变从斜向改垂直之后这里必须跟着改，否则对方
// 尾巴会取到顶部那端的蓝，拼缝处冒出第二种色相。
export function bubbleGradientTailColor(outgoing: boolean, dark: boolean): string {
  const colors: string[] = bubbleGradientColors(outgoing, dark);
  return colors[colors.length - 1];
}

// 通话记录气泡的渐变：与普通气泡同一对色相，但整体压暗一档——通话记录里
// 有未接红的告警字，底色太亮会把红字压到看不清。
export function callRecordGradientColors(outgoing: boolean, dark: boolean): string[] {
  if (dark) {
    return outgoing ? ['#FF7A46C8', '#FF2A5CBF'] : ['#FF2A5CBF', '#FF7A46C8'];
  }
  return outgoing ? ['#FFDCCBF8', '#FFC9DDFB'] : ['#FFC9DDFB', '#FFDCCBF8'];
}

export function callRecordGradientStops(outgoing: boolean, dark: boolean): Array<[string, number]> {
  return gradientStops(callRecordGradientColors(outgoing, dark));
}

// 通话记录气泡的**纵向色带**版本（Beta8 补：通话记录不再是独立系统底色）。
// 与普通气泡吃同一条色带、同一个行号相位，所以整段会话的色带不会被通话记录
// 打断；区别只有压暗一档（未接红的告警字要压得住）。
export function callRecordGradientColorsAt(outgoing: boolean, dark: boolean,
  rowIndex: number): string[] {
  const core: string[] = bubbleGradientColorsAtCore(dark, rowIndex);
  if (core.length < 2) {
    return callRecordGradientColors(outgoing, dark);
  }
  const toward: string = dark ? '#FF000000' : '#FFFFFFFF';
  const mute: number = dark ? 0.18 : 0.30;
  return [mixBubbleColors(core[0], toward, mute), mixBubbleColors(core[1], toward, mute)];
}

export function callRecordGradientStopsAt(outgoing: boolean, dark: boolean, enabled: boolean,
  rowIndex: number): Array<[string, number]> {
  if (!enabled) {
    return GRADIENT_OFF;
  }
  const colors: string[] = callRecordGradientColorsAt(outgoing, dark, rowIndex);
  if (colors.length < 2) {
    return GRADIENT_OFF;
  }
  return [[colors[0], 0], [colors[1], 1]];
}

export function chatBackgroundFallbackColors(dark: boolean): string[] {
  return dark ? CHAT_BG_FALLBACK_DARK : CHAT_BG_FALLBACK_LIGHT;
}

// 对方（左）气泡纯色底。
export function bubbleInSolidColor(dark: boolean): string {
  return dark ? BUBBLE_IN_SOLID_DARK : BUBBLE_IN_SOLID_LIGHT;
}

// 通话记录 / 系统服务气泡底。
export function callRecordSolidColor(dark: boolean): string {
  return dark ? BUBBLE_CALL_SOLID_DARK : BUBBLE_CALL_SOLID_LIGHT;
}

// 参考图是「深蓝黑底 + 浅色卡通图案」。底色继续用上面的 CHAT_BG_FALLBACK_*
// （本身就是深蓝黑），这里只补图案的线色：深色主题取淡蓝白、浅色主题取深蓝灰，
// 都由下面的函数给出，避免组件里再写 rgba 字面量。
export const CHAT_DOODLE_STROKE_DARK: string = 'rgba(214,222,240,0.13)';
export const CHAT_DOODLE_STROKE_LIGHT: string = 'rgba(38,50,74,0.10)';

export function chatDoodleStrokeColor(dark: boolean): string {
  return dark ? CHAT_DOODLE_STROKE_DARK : CHAT_DOODLE_STROKE_LIGHT;
}

export function chatBackgroundFallbackStops(dark: boolean): Array<[string, number]> {
  return gradientStops(chatBackgroundFallbackColors(dark));
}

// ════════════════════════ Beta8：随纵向位置变化的渐变带 ════════════════════════
//
// 需求（2026-11-05）：气泡颜色不再由「自己/对方 × 深/浅」四个固定组合决定，
// 而是随气泡在会话纵轴上的位置连续变化——整屏气泡拼成一条色带，色带颜色组
// 可以有多套、每套支持多枚色标（见 util/bubbleStyle.BUBBLE_GRADIENTS 与自定义
// 色板）。参照官方 Telegram 的做法：每条气泡取色带上的一段，相邻气泡首尾
// 相接，而不是每个气泡各拿一对固定色。
//
// 为什么相位用「行号」而不是像素坐标：
//   · List 滚动是整体平移，行内组件拿不到随滚动变化的全局坐标（onAreaChange
//     的 position 相对父容器，滚动时不重算）；
//   · 若把 scrollOffset 灌进全局状态、逐帧驱动，所有可见行每帧都要重绘——本
//     工程复用桶 + 8.31ms 帧预算是硬约束，花不起；
//   · 行号是 RepeatItem 现成的，零订阅零开销，只随内容本身变化。
// 于是色带锚定在「对话内容」上：滚动时颜色跟着消息一起走，视觉上是一条贯穿
// 整段会话的渐变；每 BUBBLE_GRADIENT_ROW_CYCLE 行走完一圈，跨周期首尾相接，
// 看不出接缝。剩余产能若要「滚动流光」，只需换相位来源，取色这层不用动。
//
// 左右镜像改为「同相位 + 对方压暗」：同一行左右气泡吃同一个色位，整条色带才
// 连得起来；左右靠明度区分（对方混黑/混白），不再靠色相反序。
export const BUBBLE_GRADIENT_ROW_CYCLE: number = 16;

// 相位：行号落在色带上的位置，0..1。只依赖行号，不依赖总行数——后续追加
// 新消息时，历史行的颜色不会整体漂移。
// 一圈跨多少行：用户可在气泡外观页调（KEY_BUBBLE_GRADIENT_CYCLE），
// 没配过就用出厂值。phase 与 span 必须同一个分母，取色才不会对不上。
function bubbleGradientRows(): number {
  const configured: number = bubbleGradientCycle();
  return configured > 0 ? configured : BUBBLE_GRADIENT_ROW_CYCLE;
}

export function bubbleGradientPhase(rowIndex: number): number {
  const rows: number = bubbleGradientRows();
  const idx: number = ((Math.floor(rowIndex) % rows) + rows) % rows;
  return idx / rows;
}

// '#AARRGGBB' / '#RRGGBB' → [a, r, g, b]，解不动的一律当白色（宁可错色不炸）。
function parseArgbColor(hex: string): number[] {
  let s: string = hex.trim();
  if (s.startsWith('#')) {
    s = s.substring(1);
  }
  if (s.length === 8) {
    return [
      parseInt(s.substring(0, 2), 16), parseInt(s.substring(2, 4), 16),
      parseInt(s.substring(4, 6), 16), parseInt(s.substring(6, 8), 16)
    ];
  }
  if (s.length === 6) {
    return [255, parseInt(s.substring(0, 2), 16), parseInt(s.substring(2, 4), 16),
      parseInt(s.substring(4, 6), 16)];
  }
  return [255, 255, 255, 255];
}

function toHexByte(value: number): string {
  const v: number = Math.max(0, Math.min(255, Math.round(value)));
  return v < 16 ? '0' + v.toString(16) : v.toString(16);
}

function toArgbHex(a: number, r: number, g: number, b: number): string {
  return '#' + toHexByte(a) + toHexByte(r) + toHexByte(g) + toHexByte(b);
}

// 两色线性插值（t=0 取 from，t=1 取 to）。alpha 一起插，色标带透明度时也对。
export function mixBubbleColors(from: string, to: string, t: number): string {
  const c1: number[] = parseArgbColor(from);
  const c2: number[] = parseArgbColor(to);
  const k: number = Math.max(0, Math.min(1, t));
  return toArgbHex(c1[0] + (c2[0] - c1[0]) * k, c1[1] + (c2[1] - c1[1]) * k,
    c1[2] + (c2[2] - c1[2]) * k, c1[3] + (c2[3] - c1[3]) * k);
}

// 在环形色带上按 t（0..1）采样：色标首尾相接，跨周期不会有跳变。
export function sampleGradientBand(colors: string[], t: number): string {
  if (colors.length === 0) {
    return '#00000000';
  }
  if (colors.length === 1) {
    return colors[0];
  }
  const n: number = colors.length;
  const wrapped: number = t - Math.floor(t);
  const pos: number = wrapped * n;
  const i: number = Math.floor(pos) % n;
  const frac: number = pos - Math.floor(pos);
  return mixBubbleColors(colors[i], colors[(i + 1) % n], frac);
}

// 该行左右气泡共用的色带（自己那组是主色带，对方在下面压暗）。
function bubbleGradientColorsAtCore(dark: boolean, rowIndex: number): string[] {
  const band: string[] = bubbleGradientBand(dark);
  if (band.length < 2) {
    return band;
  }
  const t0: number = bubbleGradientPhase(rowIndex);
  // 单个气泡在色带上占一整行的跨度：相邻气泡（行号差 1）取到的两端正好接上，
  // 气泡自身也保留一段可见过渡（不是死板单色）。
  const span: number = 1 / bubbleGradientRows();
  return [sampleGradientBand(band, t0), sampleGradientBand(band, t0 + span)];
}

// 某一行的渐变两端色：[顶部, 底部]。
//  · 自己：直接用色带；
//  · 对方：同色位混黑（夜间）/ 混白（白天）压一档，保证左右可区分又不断带。
export function bubbleGradientColorsAt(outgoing: boolean, dark: boolean, rowIndex: number): string[] {
  const core: string[] = bubbleGradientColorsAtCore(dark, rowIndex);
  if (outgoing || core.length < 2) {
    return core;
  }
  const toward: string = dark ? '#FF000000' : '#FFFFFFFF';
  const mute: number = dark ? 0.24 : 0.38;
  return [mixBubbleColors(core[0], toward, mute), mixBubbleColors(core[1], toward, mute)];
}

export function bubbleGradientStopsAt(outgoing: boolean, dark: boolean, enabled: boolean,
  rowIndex: number): Array<[string, number]> {
  if (!enabled) {
    return GRADIENT_OFF;
  }
  const colors: string[] = bubbleGradientColorsAt(outgoing, dark, rowIndex);
  if (colors.length < 2) {
    return GRADIENT_OFF;
  }
  return [[colors[0], 0], [colors[1], 1]];
}

// 尾巴取靠尾巴那一端（两端尾巴都在气泡底部）= 色带底部色。
export function bubbleGradientTailColorAt(outgoing: boolean, dark: boolean, rowIndex: number): string {
  const colors: string[] = bubbleGradientColorsAt(outgoing, dark, rowIndex);
  if (colors.length < 2) {
    return bubbleGradientTailColor(outgoing, dark);
  }
  return colors[colors.length - 1];
}
