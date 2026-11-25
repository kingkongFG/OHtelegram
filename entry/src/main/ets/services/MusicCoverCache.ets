import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { logE } from '../util/log';
import { TrimContext, registerCacheTrimHook, trimMusicCoverEntriesFor } from '../util/globalCacheTrim';

// 专辑封面（messageAudio 的 album_cover_thumbnail）的取数与缓存。
//
// 【为什么单独一层】封面缩略图是**按文件 id**取的，而同一张专辑会在播放页、
// 播放列表、合集详情、搜索结果里同时出现好几次。不缓存的话每处各发一次
// downloadFile，滚动时尤其浪费；缓存在这里，谁先要谁触发，其余直接命中。
//
// 【失败也缓存】没有内嵌封面、或者缩略图取不回来的曲目，每次进来都会再问一次，
// 而答案不会变。存一条空串当"问过了，没有"，界面据此退回渐变色块。

const cache: Map<number, string> = new Map<number, string>();
const inFlight: Map<number, Promise<string>> = new Map<number, Promise<string>>();

// 缓存的是"文件的绝对路径"，不是位图本身，但它是**无界的**：听过的每张专辑
// 都会留下一条（含取不到的 '' 占位），长跑一个音乐会话能攒到上千条。
// 400 条 ≈ 一次音乐会话的专辑量级，路径字符串总共也就几十 KB，给个上限
// 只为不让"听过一次就算一条"无限堆积。
const COVER_CACHE_MAX: number = 400;

// 写入并维持 LRU 顺序：命中/写入都挪到队尾，超上限淘汰队头。
function rememberCover(fileId: number, path: string): void {
  cache.delete(fileId);
  cache.set(fileId, path);
  while (cache.size > COVER_CACHE_MAX) {
    const oldest: number | undefined = cache.keys().next().value as number | undefined;
    if (oldest === undefined) {
      break;
    }
    cache.delete(oldest);
  }
}

// 缩略图，优先级压到最低：它只是好看，不该和正在播的那首抢带宽。
const COVER_PRIORITY: number = 1;

// 已经拿到的路径；'' 表示没有或还没取。界面用它同步渲染，不必等 Promise。
export function cachedMusicCover(fileId: number): string {
  const hit: string | undefined = cache.get(fileId);
  if (hit === undefined) {
    return '';
  }
  // 命中挪到队尾，别让正在播放的那张先被淘汰。
  cache.delete(fileId);
  cache.set(fileId, hit);
  return hit;
}

export function ensureMusicCover(fileId: number): Promise<string> {
  if (fileId <= 0) {
    return Promise.resolve('');
  }
  const hit: string | undefined = cache.get(fileId);
  if (hit !== undefined) {
    return Promise.resolve(hit);
  }
  const running: Promise<string> | undefined = inFlight.get(fileId);
  if (running !== undefined) {
    return running;
  }
  const req: TdRequest = { '@type': 'downloadFile' };
  req['file_id'] = fileId;
  req['priority'] = COVER_PRIORITY;
  req['synchronous'] = true;
  const started: Promise<string> = getTdClient().send(req).then((file: TdObject): string => {
    const local = file['local'] as TdObject | undefined;
    const path: string = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
    rememberCover(fileId, path);
    return path;
  }).catch((e: TdError): string => {
    // 失败也记一笔，别让同一个取不到的封面每次滚过都再发一遍请求。
    rememberCover(fileId, '');
    logE(`MusicCoverCache.downloadFile(${fileId}) failed: ${e.message}`);
    return '';
  }).finally((): void => {
    inFlight.delete(fileId);
  });
  inFlight.set(fileId, started);
  return started;
}

// 换账号时清掉：文件 id 是按账号发的。
export function resetMusicCoverCache(): void {
  cache.clear();
  inFlight.clear();
}

// 给 Image() 用的来源串。TDLib 给的是绝对路径，要加 file:// 前缀。
export function musicCoverSource(path: string): string {
  return path.startsWith('/') ? `file://${path}` : path;
}

// 内存压力下的显式回收（0 = 全清）。清掉的只是"路径已取到"的记忆，
// 下次进入播放页会重新走一次 downloadFile（TDLib 侧命中本地文件，不会重新下载）。
export function trimMusicCoverCache(targetEntries: number): number {
  const target: number = Math.max(0, Math.floor(targetEntries));
  let removed: number = 0;
  while (cache.size > target) {
    const oldest: number | undefined = cache.keys().next().value as number | undefined;
    if (oldest === undefined) {
      break;
    }
    cache.delete(oldest);
    removed++;
  }
  return removed;
}

export function musicCoverCacheSize(): number {
  return cache.size;
}

// 封面只是"好看"，优先级最低，轻微档就让步。
registerCacheTrimHook('musicCoverCache', (ctx: TrimContext): void => {
  if (ctx.restore) {
    return;
  }
  trimMusicCoverCache(trimMusicCoverEntriesFor(ctx.level));
});
