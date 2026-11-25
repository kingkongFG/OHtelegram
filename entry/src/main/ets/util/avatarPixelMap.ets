import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { logE } from './log';
import { TrimContext, registerCacheTrimHook, trimAvatarEntriesFor } from './globalCacheTrim';

// 已下载的头像文件 → PixelMap。系统通知的 largeIcon 与来电界面的 userProfile
// 都要 PixelMap，解码逻辑在此共用。
// 解码结果按路径缓存：通知可能连续发布多条，重复解码同一头像很浪费。
const cache: Map<string, image.PixelMap> = new Map();
const SIZE: number = 96;
// 96×96 RGBA 一张约 36KB，64 张 ≈ 2.3MB，和 pixelCache 里 48 张钉住头像的
// 先例同一量级（见 pixelCache 的 BOUNDED_PIN_MAX）。
const AVATAR_CACHE_MAX: number = 64;

export function avatarPixelMap(avatarPath: string): image.PixelMap | undefined {
  if (avatarPath === '') {
    return undefined;
  }
  const cached = cache.get(avatarPath);
  if (cached !== undefined) {
    // 命中即挪到队尾：不这么做，"一张常驻头像 + 一堆一次性头像"里先被淘汰的
    // 反而是那张天天用的，LRU 就退化成 FIFO 了。
    cache.delete(avatarPath);
    cache.set(avatarPath, cached);
    return cached;
  }
  let file: fileIo.File | null = null;
  try {
    file = fileIo.openSync(avatarPath, fileIo.OpenMode.READ_ONLY);
    const source: image.ImageSource = image.createImageSource(file.fd);
    const pixelMap: image.PixelMap = source.createPixelMapSync({
      desiredSize: { width: SIZE, height: SIZE }
    });
    source.release();
    // 头像文件路径随内容变化，缓存不会读到过期图；上限防止长期运行膨胀。
    // 原来是"超 64 就 cache.clear()"——一次清空 64 张，接下来通知列表里
    // 每一张都要重新解码。改成逐条淘汰最久未用的，代价从 64 次降到 1 次。
    while (cache.size >= AVATAR_CACHE_MAX) {
      const oldest: string | undefined = cache.keys().next().value as string | undefined;
      if (oldest === undefined) {
        break;
      }
      // 只摘引用，不 release：外面可能正拿着上一张在画。
      cache.delete(oldest);
    }
    cache.set(avatarPath, pixelMap);
    return pixelMap;
  } catch (e) {
    logE(`avatarPixelMap(${avatarPath}) failed: ${(e as Error).message}`);
    return undefined;
  } finally {
    if (file !== null) {
      try {
        fileIo.closeSync(file);
      } catch (e) {
        // 关闭失败不影响已解码的位图
      }
    }
  }
}

// 来电界面的 userProfile 是必填项，没有头像时给一张占位图。
export function avatarPixelMapOrPlaceholder(avatarPath: string): image.PixelMap {
  const decoded = avatarPixelMap(avatarPath);
  if (decoded !== undefined) {
    return decoded;
  }
  return image.createPixelMapSync(
    new ArrayBuffer(SIZE * SIZE * 4), { size: { width: SIZE, height: SIZE } });
}

// 内存压力下的显式回收（0 = 全清）。同样只摘引用、不 release。
export function trimAvatarPixelMaps(targetEntries: number): number {
  const target: number = Math.max(0, Math.floor(targetEntries));
  let removed: number = 0;
  while (cache.size > target) {
    const oldest: string | undefined = cache.keys().next().value as string | undefined;
    if (oldest === undefined) {
      break;
    }
    cache.delete(oldest);
    removed++;
  }
  return removed;
}

export function avatarPixelMapCacheSize(): number {
  return cache.size;
}

// 通知栏 / 来电界面用的头像位图，属于"小尺寸缩略图"那一类，轻微档就让步。
registerCacheTrimHook('avatarPixelMap', (ctx: TrimContext): void => {
  if (ctx.restore) {
    return;
  }
  trimAvatarPixelMaps(trimAvatarEntriesFor(ctx.level));
});
