import { logE, logI } from './log';
import {
  NativePixelBudget, fullNativePixelBudget, pressuredNativePixelBudget
} from './NativePixelBudget';

// 进程内所有"可以丢的内存缓存"的统一回收中枢。
//
// 【为什么要有这一层】缓存散在 util/ 与 services/ 十几处，每处只管自己的上限；
// 系统通过 onMemoryLevel 告诉应用"该让一让"时，原来只有 EntryAbility.onBackground
// 调了一次 trimPixelCache()——贴纸、公式图、段落、封面、TGS 文本、光栅化背景一个都
// 不动。低内存设备上"缓存总量"照样可能顶到进程被系统强杀。
//
// 【为什么用注册表而不是逐个 import】这些模块分布在 util/ 与 services/，其中
// services/AlphaStickerStore 会拉起 nativeWebm 的 .so。这里若静态 import 它们，
// 一条链就会把本该懒加载的原生模块拖进冷启动。改成"模块自己注册"：没被加载过的
// 模块本来也没有缓存要清；注册表本身不 import 任何缓存模块，因此不会成环。
//
// 【红线】draftCache（草稿）、收藏贴纸、CacheRegistry、已下载媒体、TDLib 数据库
// 属于用户数据，任何档位都不参与清理。

export const TRIM_LEVEL_LIGHT: number = 0;
export const TRIM_LEVEL_MODERATE: number = 1;
export const TRIM_LEVEL_CRITICAL: number = 2;

// 一档要清多少、留多少，全部由这里下发，被清模块不再各自维护一套数字。
export interface TrimContext {
  // 归一化档位：0 轻微 / 1 中等 / 2 紧急。
  level: number;
  // 图片（PixelMap）缓存此刻允许的天花板字节数。
  imageBytes: number;
  // 透明贴纸缓存此刻允许的天花板字节数。
  alphaBytes: number;
  // true 表示这是一次"压力解除、预算回到满额"的恢复通知，不是回收。
  restore: boolean;
}

export type CacheTrimHook = (ctx: TrimContext) => void;

interface RegisteredHook {
  name: string;
  hook: CacheTrimHook;
}

const hooks: RegisteredHook[] = [];

// 同一个名字重复注册时覆盖（热重载 / 模块被重复求值都不会堆出多份）。
export function registerCacheTrimHook(name: string, hook: CacheTrimHook): void {
  for (let i = 0; i < hooks.length; i++) {
    if (hooks[i].name === name) {
      hooks[i].hook = hook;
      return;
    }
  }
  hooks.push({ name: name, hook: hook });
}

// 只有一个体积巨大、重建极慢的条目才需要限流；像素缓存那边一次只放一批引用。
const PIXEL_TRIM_BATCH: number = 8;

// 轻微档：只有"重建几毫秒"的纯文本 / 排版 / 小图形缓存让步。
// 位图预算这一档不动——中等档才收，避免一次轻微提示就把正在看的图清掉。
const LIGHT_PARAGRAPH_ENTRIES: number = 128;
const LIGHT_MATH_ENTRIES: number = 48;
const LIGHT_TGS_ENTRIES: number = 64;
const LIGHT_AVATAR_ENTRIES: number = 40;
const LIGHT_MUSIC_COVER_ENTRIES: number = 300;
const LIGHT_RASTER_ENTRIES: number = 32;

// 中等档：位图按 NativePixelBudget 的既有映射收紧（图片 12MiB / 贴纸 8MiB），
// 文本类缓存继续减半。
const MODERATE_PARAGRAPH_ENTRIES: number = 48;
const MODERATE_MATH_ENTRIES: number = 16;
const MODERATE_TGS_ENTRIES: number = 16;
const MODERATE_AVATAR_ENTRIES: number = 16;
const MODERATE_MUSIC_COVER_ENTRIES: number = 100;
const MODERATE_RASTER_ENTRIES: number = 8;

export interface TrimSummary {
  level: number;
  imageBytes: number;
  alphaBytes: number;
  hooksRun: number;
  // true 表示这次是恢复通知而不是回收。
  restore: boolean;
}

// 档位 → 预算。轻微档维持满额，中等/紧急档直接复用 NativePixelBudget 已有的
// 纯函数（12/8MiB，以及 level>=2 时归零），两处数字不会打架。
// 切到后台同样归零：那时没有任何一帧在画，位图留着只是占内存。
function budgetFor(level: number, appForeground: boolean): NativePixelBudget {
  if (!appForeground || level >= TRIM_LEVEL_CRITICAL) {
    return { imageBytes: 0, alphaBytes: 0 };
  }
  if (level >= TRIM_LEVEL_MODERATE) {
    return pressuredNativePixelBudget(TRIM_LEVEL_MODERATE, true);
  }
  return fullNativePixelBudget();
}

function runHooks(ctx: TrimContext): number {
  let ran: number = 0;
  for (let i = 0; i < hooks.length; i++) {
    const entry: RegisteredHook = hooks[i];
    try {
      entry.hook(ctx);
      ran++;
    } catch (e) {
      // 回收失败绝不影响前台运行：某一个模块炸了，其余模块照旧清。
      logE(`globalCacheTrim hook ${entry.name} failed: ${(e as Error).message}`);
    }
  }
  return ran;
}

let lastLevel: number = -1;
let lastAt: number = 0;
let lastSummary: TrimSummary = {
  level: -1, imageBytes: 0, alphaBytes: 0, hooksRun: 0, restore: false
};
// onMemoryLevel 在真实压力下会连续下发，同一档位短时间内重入没有意义
// （缓存已经是空的），只白跑一遍预算下发。
const REPEAT_INTERVAL_MS: number = 2000;

// 唯一的对门外入口：level 就是 AbilityConstant.MemoryLevel 的数值语义
// （0 适中 / 1 低 / 2 极低，>=3 的 UI_HIDDEN 与后台档一律按紧急处理）。
export function trimMemoryCaches(level: number, appForeground: boolean = true): TrimSummary {
  const safeLevel: number = level <= TRIM_LEVEL_LIGHT ? TRIM_LEVEL_LIGHT
    : (level >= TRIM_LEVEL_CRITICAL ? TRIM_LEVEL_CRITICAL : level);
  const now: number = Date.now();
  if (safeLevel === lastLevel && now - lastAt < REPEAT_INTERVAL_MS) {
    return lastSummary;
  }
  const budget: NativePixelBudget = budgetFor(safeLevel, appForeground);
  const ctx: TrimContext = {
    level: safeLevel,
    imageBytes: budget.imageBytes,
    alphaBytes: budget.alphaBytes,
    restore: false
  };
  const ran: number = runHooks(ctx);
  const summary: TrimSummary = {
    level: safeLevel,
    imageBytes: budget.imageBytes,
    alphaBytes: budget.alphaBytes,
    hooksRun: ran,
    restore: false
  };
  lastLevel = safeLevel;
  lastAt = now;
  lastSummary = summary;
  logI(`[mem] trim level=${safeLevel} fg=${appForeground} ` +
    `image=${budget.imageBytes} alpha=${budget.alphaBytes} hooks=${ran}`);
  return summary;
}

// 压力解除 / 回到前台：只把预算放回满额，不清任何缓存。
// 清空是单向操作，恢复时再清一遍等于把刚重建的又扔掉。
export function restoreMemoryBudgets(): void {
  const full: NativePixelBudget = fullNativePixelBudget();
  const ctx: TrimContext = {
    level: TRIM_LEVEL_LIGHT,
    imageBytes: full.imageBytes,
    alphaBytes: full.alphaBytes,
    restore: true
  };
  const ran: number = runHooks(ctx);
  lastLevel = -1;
  lastAt = 0;
  lastSummary = {
    level: TRIM_LEVEL_LIGHT,
    imageBytes: full.imageBytes,
    alphaBytes: full.alphaBytes,
    hooksRun: ran,
    restore: true
  };
  logI(`[mem] restore image=${full.imageBytes} alpha=${full.alphaBytes} hooks=${ran}`);
}

// 各档位要清到多少条，供注册进来的模块读取，避免数字散落。
export function trimEntriesFor(level: number): number {
  if (level >= TRIM_LEVEL_CRITICAL) {
    return 0;
  }
  if (level >= TRIM_LEVEL_MODERATE) {
    return MODERATE_PARAGRAPH_ENTRIES;
  }
  return LIGHT_PARAGRAPH_ENTRIES;
}

export function trimMathEntriesFor(level: number): number {
  if (level >= TRIM_LEVEL_CRITICAL) {
    return 0;
  }
  return level >= TRIM_LEVEL_MODERATE ? MODERATE_MATH_ENTRIES : LIGHT_MATH_ENTRIES;
}

export function trimTgsEntriesFor(level: number): number {
  if (level >= TRIM_LEVEL_CRITICAL) {
    return 0;
  }
  return level >= TRIM_LEVEL_MODERATE ? MODERATE_TGS_ENTRIES : LIGHT_TGS_ENTRIES;
}

export function trimAvatarEntriesFor(level: number): number {
  if (level >= TRIM_LEVEL_CRITICAL) {
    return 0;
  }
  return level >= TRIM_LEVEL_MODERATE ? MODERATE_AVATAR_ENTRIES : LIGHT_AVATAR_ENTRIES;
}

export function trimMusicCoverEntriesFor(level: number): number {
  if (level >= TRIM_LEVEL_CRITICAL) {
    return 0;
  }
  return level >= TRIM_LEVEL_MODERATE ? MODERATE_MUSIC_COVER_ENTRIES : LIGHT_MUSIC_COVER_ENTRIES;
}

export function trimRasterEntriesFor(level: number): number {
  if (level >= TRIM_LEVEL_CRITICAL) {
    return 0;
  }
  return level >= TRIM_LEVEL_MODERATE ? MODERATE_RASTER_ENTRIES : LIGHT_RASTER_ENTRIES;
}

export function pixelTrimBatch(): number {
  return PIXEL_TRIM_BATCH;
}

export function cacheTrimHookCount(): number {
  return hooks.length;
}
