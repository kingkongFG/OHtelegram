// 【Beta7 · 聊天气泡外观】形状 / 配色 / 渐变的预设表，以及沉浸光感的覆盖区域判定。
//
// 这里**只放定义与读**：写入统一由设置页（pages/main/BubbleStylePage）调
// store/AppSettings 的 setter。util 层不反向 import store，否则 AppSettings →
// surfaceGlass/appearance → ... 这条链很容易绕回来打死结。
//
// 三套预设共用一条约束：**每一项都必须真实生效**。形状写 KEY_BUBBLE_RADIUS
// （外加两个角的上限），配色写四个 hex 键（recomputeAppearance 重算资源绑定），
// 渐变由 util/chatBubbleGradient 现读现用。没有"存了但没人读"的档位。

// **不 import store/AppSettings**：气泡组件 → chatBubbleGradient → 本文件，
// 而 AppSettings 又拽着 appearance/surfaceGlass 一大串，把 store 拉进来容易
// 绕成初始化环（常量读到 undefined）。圆角键名与 store 保持一致，写死在这儿。
export const KEY_BUBBLE_RADIUS_ALIAS: string = 'bubbleRadius';

// ---------- 键 ----------

// 形状预设 id，见 BUBBLE_SHAPES。
export const KEY_BUBBLE_SHAPE: string = 'bubbleShape';
// 配色预设 id，见 BUBBLE_PALETTES。
export const KEY_BUBBLE_PALETTE: string = 'bubblePalette';
// 渐变预设 id，见 BUBBLE_GRADIENTS。
export const KEY_BUBBLE_GRADIENT: string = 'bubbleGradientPreset';

// ---------- 形状 ----------

export interface BubbleShape {
  id: string;
  // app.string.* 的键名，页面自己去 $r 化。
  labelKey: string;
  // 主圆角，写进 KEY_BUBBLE_RADIUS。
  radius: number;
  // 连体角（同一人连续气泡贴在一起那条边）的上限。
  runCap: number;
  // 靠头像那一侧尾角的上限。
  tailCap: number;
}

export const SHAPE_CLASSIC: string = 'classic';
export const SHAPE_ROUND: string = 'round';
export const SHAPE_SQUARE: string = 'square';
export const SHAPE_SHARP: string = 'sharp';
export const SHAPE_CAPSULE: string = 'capsule';

// 五套形状。classic 的 (17, 7, 2) 与改这个功能之前写死的数值逐字一致——
// 老用户升级上来看到的还是同一只气泡，选别的档才算改过。
export const BUBBLE_SHAPES: BubbleShape[] = [
  { id: SHAPE_CLASSIC, labelKey: 'appearance_shape_classic', radius: 17, runCap: 7, tailCap: 2 },
  { id: SHAPE_ROUND, labelKey: 'appearance_shape_round', radius: 20, runCap: 10, tailCap: 4 },
  { id: SHAPE_SQUARE, labelKey: 'appearance_shape_square', radius: 10, runCap: 4, tailCap: 1 },
  { id: SHAPE_SHARP, labelKey: 'appearance_shape_sharp', radius: 3, runCap: 1, tailCap: 0 },
  { id: SHAPE_CAPSULE, labelKey: 'appearance_shape_capsule', radius: 24, runCap: 12, tailCap: 12 }
];

export function bubbleShapeOf(id: string): BubbleShape {
  for (const shape of BUBBLE_SHAPES) {
    if (shape.id === id) {
      return shape;
    }
  }
  return BUBBLE_SHAPES[0];
}

export function bubbleShapeId(): string {
  const stored: string = AppStorage.get<string>(KEY_BUBBLE_SHAPE) ?? '';
  return stored !== '' ? stored : SHAPE_CLASSIC;
}

export function bubbleShape(): BubbleShape {
  return bubbleShapeOf(bubbleShapeId());
}

// 连体角 / 尾角的上限。两个气泡组件原来写死 Math.min(radius, 7) 与
// Math.min(radius, 2)，现在跟着形状档走——但**永远不超过主圆角**，
// 否则方形档会出现内角比外角还圆的自相矛盾。
export function bubbleRunRadiusCap(): number {
  const shape: BubbleShape = bubbleShape();
  return Math.min(shape.runCap, shape.radius);
}

export function bubbleTailRadiusCap(): number {
  const shape: BubbleShape = bubbleShape();
  return Math.min(shape.tailCap, shape.radius);
}

// 当前形状对应的主圆角。圆形档位之外，用户还可以用「聊天设置」里的圆角
// 滑杆自己微调——滑杆写的是同一个键，所以滑杆一动形状档就变成"自定义"，
// 这里不去纠正它（纠正等于抢用户的滑杆）。
export function bubbleRadiusOfShape(): number {
  return bubbleShape().radius;
}

// ---------- 配色 ----------

export interface BubblePalette {
  id: string;
  labelKey: string;
  // 自己（右）气泡
  out: string;
  outDark: string;
  // 对方（左）气泡
  in: string;
  inDark: string;
}

// 跟随主题 = 不覆盖 hex 键（等于清空四个键回到出厂色）。它必须排第一：
// 用户调乱了要有一条明确的路回去。
export const PALETTE_THEME: string = 'theme';

export const BUBBLE_PALETTES: BubblePalette[] = [
  { id: PALETTE_THEME, labelKey: 'appearance_palette_theme',
    out: '#E1FFC7', outDark: '#2B5278', in: '#FFFFFF', inDark: '#182533' },
  { id: 'ocean', labelKey: 'appearance_palette_ocean',
    out: '#CFE6FF', outDark: '#26547C', in: '#FFFFFF', inDark: '#122032' },
  { id: 'violet', labelKey: 'appearance_palette_violet',
    out: '#E3D9FB', outDark: '#4B3A85', in: '#FFFFFF', inDark: '#1E1B2E' },
  { id: 'forest', labelKey: 'appearance_palette_forest',
    out: '#D6F2DF', outDark: '#28553B', in: '#FFFFFF', inDark: '#16281E' },
  { id: 'rose', labelKey: 'appearance_palette_rose',
    out: '#FFDDE8', outDark: '#6B2F45', in: '#FFFFFF', inDark: '#2A1720' },
  { id: 'graphite', labelKey: 'appearance_palette_graphite',
    out: '#E3E7ED', outDark: '#3A424E', in: '#FFFFFF', inDark: '#1B1F26' }
];

export function bubblePaletteOf(id: string): BubblePalette {
  for (const palette of BUBBLE_PALETTES) {
    if (palette.id === id) {
      return palette;
    }
  }
  return BUBBLE_PALETTES[0];
}

export function bubblePaletteId(): string {
  const stored: string = AppStorage.get<string>(KEY_BUBBLE_PALETTE) ?? '';
  return stored !== '' ? stored : PALETTE_THEME;
}

export function bubblePalette(): BubblePalette {
  return bubblePaletteOf(bubblePaletteId());
}

// ---------- 渐变 ----------

export interface BubbleGradient {
  id: string;
  labelKey: string;
  // 自己：深色 / 浅色，各两端的色相
  outDark: string[];
  outLight: string[];
  // 对方：与自己反序，拼缝处才不会被看见第二种色相
  inDark: string[];
  inLight: string[];
}

export const GRADIENT_NONE: string = 'none';
// 出厂档。写在这儿而不是让各处自己写 'violetBlue'，是为了万一要换默认值时
// 只改一处（AppSettings 播种和 bubbleGradientId 的兜底共用这一个常量）。
export const GRADIENT_DEFAULT: string = 'violetBlue';

// 六套渐变 + 自定义。'violetBlue' 是 Beta7 里已经上过真机的那一对紫蓝，排第二
// （第一是"无"），这样"要不要渐变"是显式的第一选择。
//
// **Beta8（2026-11-05）：每套从 2 枚色标扩到 4 枚，成为一条环形色带。**
// 气泡不再各拿一对固定的"两端色"，而是按行号在色带上取一小段（见
// util/chatBubbleGradient.bubbleGradientColorsAt）。扩到 4 枚之后，16 行一圈的
// 色相推进才看得出血色、蓝、青之间的流动；2 枚色标只能做出"紫↔蓝"来回摆，
// 纵向位置变化会退化成两种颜色交替。
// outLight 是同一色相的浅色版（浅色主题里气泡要托得住黑字，不能直接用暗色）。
// inDark/inLight 保留给旧的取色调用（顶栏预览等处），方向仍是反序。
export const GRADIENT_CUSTOM: string = 'custom';

export const BUBBLE_GRADIENTS: BubbleGradient[] = [
  { id: GRADIENT_NONE, labelKey: 'appearance_gradient_none',
    outDark: [], outLight: [], inDark: [], inLight: [] },
  { id: 'violetBlue', labelKey: 'appearance_gradient_violet_blue',
    outDark: ['#FF8B5CF6', '#FF5B6EEA', '#FF2F6FE0', '#FF6E7BF2'],
    outLight: ['#FFE2D5FB', '#FFD8DCFA', '#FFD3E3FD', '#FFDBD8FB'],
    inDark: ['#FF2F6FE0', '#FF5B6EEA', '#FF8B5CF6', '#FF6E7BF2'],
    inLight: ['#FFD3E3FD', '#FFD8DCFA', '#FFE2D5FB', '#FFDBD8FB'] },
  { id: 'sunset', labelKey: 'appearance_gradient_sunset',
    outDark: ['#FFFF7A5C', '#FFE8467C', '#FFD93FA0', '#FFF0638A'],
    outLight: ['#FFFFD9CE', '#FFFACCDA', '#FFF6CBE8', '#FFF7CFD6'],
    inDark: ['#FFD93FA0', '#FFE8467C', '#FFFF7A5C', '#FFF0638A'],
    inLight: ['#FFF6CBE8', '#FFFACCDA', '#FFFFD9CE', '#FFF7CFD6'] },
  { id: 'aurora', labelKey: 'appearance_gradient_aurora',
    outDark: ['#FF35D6C6', '#FF3FBEDB', '#FF6C5CE7', '#FF5A9BE0'],
    outLight: ['#FFCFF5F0', '#FFD2EDF8', '#FFDDD7FB', '#FFD5E8FA'],
    inDark: ['#FF6C5CE7', '#FF3FBEDB', '#FF35D6C6', '#FF5A9BE0'],
    inLight: ['#FFDDD7FB', '#FFD2EDF8', '#FFCFF5F0', '#FFD5E8FA'] },
  { id: 'galaxy', labelKey: 'appearance_gradient_galaxy',
    outDark: ['#FF4A3AFF', '#FF2E7BFF', '#FF00C2FF', '#FF6E5CFF'],
    outLight: ['#FFDAD6FF', '#FFD2E4FF', '#FFC7EEFF', '#FFDCD9FF'],
    inDark: ['#FF00C2FF', '#FF2E7BFF', '#FF4A3AFF', '#FF6E5CFF'],
    inLight: ['#FFC7EEFF', '#FFD2E4FF', '#FFDAD6FF', '#FFDCD9FF'] },
  { id: 'mint', labelKey: 'appearance_gradient_mint',
    outDark: ['#FF34D399', '#FF2EC8C0', '#FF2AA7DE', '#FF4FC0A8'],
    outLight: ['#FFD3F5E5', '#FFCFEFEF', '#FFC9E9F8', '#FFD5F2EA'],
    inDark: ['#FF2AA7DE', '#FF2EC8C0', '#FF34D399', '#FF4FC0A8'],
    inLight: ['#FFC9E9F8', '#FFCFEFEF', '#FFD3F5E5', '#FFD5F2EA'] },
  { id: 'graphite', labelKey: 'appearance_gradient_graphite',
    outDark: ['#FF5B6470', '#FF454E5A', '#FF2A313A', '#FF3E4753'],
    outLight: ['#FFEDF0F4', '#FFE5E9EF', '#FFDCE2EA', '#FFE2E7EE'],
    inDark: ['#FF2A313A', '#FF454E5A', '#FF5B6470', '#FF3E4753'],
    inLight: ['#FFDCE2EA', '#FFE5E9EF', '#FFEDF0F4', '#FFE2E7EE'] },
  // 自定义：色标由用户在气泡外观页编辑，存在下面两个键里（暗色一条，
  // 浅色一条）。空数组 = 还没配过，按出厂 violetBlue 的色带兜底。
  { id: GRADIENT_CUSTOM, labelKey: 'appearance_gradient_custom',
    outDark: [], outLight: [], inDark: [], inLight: [] }
];

// 自定义色板：逗号分隔的 '#FFRRGGBB'，暗色与浅色各一条。
export const KEY_BUBBLE_GRADIENT_CUSTOM: string = 'bubbleGradientCustom';
export const KEY_BUBBLE_GRADIENT_CUSTOM_LIGHT: string = 'bubbleGradientCustomLight';
// 色带一圈跨多少行（越小颜色变化越急）。设置页暂时不暴露，读写留好接口。
export const KEY_BUBBLE_GRADIENT_CYCLE: string = 'bubbleGradientCycle';

// 出厂自定义色板（用户没改过时给一套能用的）
const CUSTOM_FALLBACK_DARK: string[] = ['#FF8B5CF6', '#FF5B6EEA', '#FF2F6FE0', '#FF6E7BF2'];
const CUSTOM_FALLBACK_LIGHT: string[] = ['#FFE2D5FB', '#FFD8DCFA', '#FFD3E3FD', '#FFDBD8FB'];

function parseCustomBand(raw: string): string[] {
  const out: string[] = [];
  for (const part of raw.split(',')) {
    const token: string = part.trim();
    if (token.length >= 7 && token.startsWith('#')) {
      out.push(token);
    }
    if (out.length >= 8) {
      break;
    }
  }
  return out;
}

export function bubbleGradientCustomBand(dark: boolean): string[] {
  const key: string = dark ? KEY_BUBBLE_GRADIENT_CUSTOM : KEY_BUBBLE_GRADIENT_CUSTOM_LIGHT;
  const stored: string = AppStorage.get<string>(key) ?? '';
  const parsed: string[] = parseCustomBand(stored);
  if (parsed.length >= 2) {
    return parsed;
  }
  return dark ? CUSTOM_FALLBACK_DARK : CUSTOM_FALLBACK_LIGHT;
}

export function bubbleGradientCustomBandRaw(dark: boolean): string {
  const key: string = dark ? KEY_BUBBLE_GRADIENT_CUSTOM : KEY_BUBBLE_GRADIENT_CUSTOM_LIGHT;
  const stored: string = AppStorage.get<string>(key) ?? '';
  return parseCustomBand(stored).length >= 2 ? stored : bubbleGradientCustomBand(dark).join(',');
}

export function bubbleGradientCycle(): number {
  const stored: number = AppStorage.get<number>(KEY_BUBBLE_GRADIENT_CYCLE) ?? 0;
  return stored > 0 ? stored : 16;
}

// 当前渐变的主色带（自己那一侧）。对方气泡在 chatBubbleGradient 里按同色位
// 压暗一档，让左右在同一行里仍能区分，同时不断开整条色带。
export function bubbleGradientBand(dark: boolean): string[] {
  const preset: BubbleGradient = bubbleGradient();
  if (preset.id === GRADIENT_CUSTOM) {
    return bubbleGradientCustomBand(dark);
  }
  const band: string[] = dark ? preset.outDark : preset.outLight;
  return band.length >= 2 ? band : (dark ? CUSTOM_FALLBACK_DARK : CUSTOM_FALLBACK_LIGHT);
}

export function bubbleGradientOf(id: string): BubbleGradient {
  for (const gradient of BUBBLE_GRADIENTS) {
    if (gradient.id === id) {
      return gradient;
    }
  }
  return BUBBLE_GRADIENTS[1];
}

export function bubbleGradientId(): string {
  const stored: string = AppStorage.get<string>(KEY_BUBBLE_GRADIENT) ?? '';
  return stored !== '' ? stored : 'violetBlue';
}

export function bubbleGradient(): BubbleGradient {
  return bubbleGradientOf(bubbleGradientId());
}

// 选了「无」就是纯色档：气泡退回 backgroundColor，玻璃材质档重新可用。
export function bubbleGradientOff(): boolean {
  return bubbleGradientId() === GRADIENT_NONE;
}

// 单侧单模式的两种色相。调用方拿到空数组时按"不画渐变"处理。
export function bubbleGradientColorsFor(outgoing: boolean, dark: boolean): string[] {
  const preset: BubbleGradient = bubbleGradient();
  if (dark) {
    return outgoing ? preset.outDark : preset.inDark;
  }
  return outgoing ? preset.outLight : preset.inLight;
}

// ---------- 沉浸光感的覆盖区域 ----------

// 三个区域，各自映射到**已经存在且真的有人读**的开关。新增一条假的
// "覆盖区域"比不加更糟：勾上去什么都没变，用户会以为坏了。
export const GLASS_SCOPE_BUBBLE: string = 'bubble';   // 气泡本体的玻璃
export const GLASS_SCOPE_FRAME: string = 'frame';     // 界面框架（标题栏/底栏/卡片）
export const GLASS_SCOPE_LIGHT: string = 'light';     // 光感（触摸流光 / 按压形变）

export interface GlassScope {
  id: string;
  labelKey: string;
  subKey: string;
  // 该区域真正的开关键。页面用它做勾选，不另建一套"影子开关"——勾上去必须
  // 真的能关掉那一片玻璃，否则就是个假控件。
  storageKey: string;
}

// 气泡 / 框架两片的开关键是 util/surfaceGlass 里已有的那两个（字符串值与那边
// 逐字一致；不 import 是为了让本文件保持零依赖）。
export const GLASS_STORAGE_BUBBLE: string = 'bubbleGlassOn';
export const GLASS_STORAGE_FRAME: string = 'surfaceGlassOn';
// 光感（点光源 + 按压形变）原来没有总闸，只有四档强弱。这里补一个，默认开，
// 让「覆盖区域」三片语义对齐：勾掉哪片，哪片就没有沉浸效果。
export const KEY_GLASS_SCOPE_LIGHT_ON: string = 'glassScopeLightOn';
export const GLASS_STORAGE_LIGHT: string = KEY_GLASS_SCOPE_LIGHT_ON;

export const GLASS_SCOPES: GlassScope[] = [
  { id: GLASS_SCOPE_BUBBLE, labelKey: 'appearance_scope_bubble', subKey: 'appearance_scope_bubble_sub',
    storageKey: GLASS_STORAGE_BUBBLE },
  { id: GLASS_SCOPE_FRAME, labelKey: 'appearance_scope_frame', subKey: 'appearance_scope_frame_sub',
    storageKey: GLASS_STORAGE_FRAME },
  { id: GLASS_SCOPE_LIGHT, labelKey: 'appearance_scope_light', subKey: 'appearance_scope_light_sub',
    storageKey: GLASS_STORAGE_LIGHT }
];

// 光感总闸。默认开——老用户升级上来不该发现点光不动了。
export function glassScopeLightOn(): boolean {
  return AppStorage.get<boolean>(KEY_GLASS_SCOPE_LIGHT_ON) ?? true;
}

// 气泡圆角随形状档走，页面上的滑杆读同一个键，所以这里给一个统一的读。
export function currentBubbleRadius(): number {
  return AppStorage.get<number>(KEY_BUBBLE_RADIUS_ALIAS) ?? 17;
}
