import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { logE, logW } from './log';

// TDLib 的下载临时分片都落在 filesDir/tdlib_files/temp 下（文件名是纯数字）。
// 正常下载完成后会被 rename 出去，但下载被中断（进程被杀、网络断、切账号）时
// 这些分片会永久留在 temp 里：TDLib 自己不会回收，应用的"清空缓存"走的是 TDLib
// 登记过的文件，也清不到它们。实测一台真机上残留达 833 MB / 15 个分片。
//
// 冷启动时扫一遍 temp，两种阈值：
// 1) 常规：删超过 24 小时没被改写过的分片；
// 2) 超限：temp 总占用超过 200 MB 时收紧到 1 小时，避免中断残留长期占着几个 G。
// 正在进行的下载会持续刷新 mtime，不会被误删。
const TEMP_SUBDIR: string = 'tdlib_files/temp';
const STALE_AGE_MS: number = 24 * 60 * 60 * 1000;
const AGGRESSIVE_AGE_MS: number = 60 * 60 * 1000;
const TOTAL_LIMIT_BYTES: number = 200 * 1024 * 1024;

export async function cleanupStaleTdlibTemp(ctx: common.Context): Promise<void> {
  const dir: string = `${ctx.filesDir}/${TEMP_SUBDIR}`;
  try {
    if (!fs.accessSync(dir)) {
      return;
    }
    const names: string[] = fs.listFileSync(dir);
    if (names.length === 0) {
      return;
    }
    const now: number = Date.now();
    const stales: fs.Stat[] = [];
    const paths: string[] = [];
    let total: number = 0;
    for (const name of names) {
      const path: string = `${dir}/${name}`;
      const stat: fs.Stat = fs.statSync(path);
      if (!stat.isFile()) {
        continue;
      }
      total += stat.size;
      stales.push(stat);
      paths.push(path);
    }
    // Stat.mtime 单位是秒。
    const ageLimit: number = total > TOTAL_LIMIT_BYTES ? AGGRESSIVE_AGE_MS : STALE_AGE_MS;
    let removed: number = 0;
    let freed: number = 0;
    for (let i = 0; i < stales.length; i++) {
      const stat: fs.Stat = stales[i];
      if (now - stat.mtime * 1000 < ageLimit) {
        continue;
      }
      try {
        fs.unlinkSync(paths[i]);
        removed += 1;
        freed += stat.size;
      } catch (err) {
        logE(`tdlib temp unlink failed: ${paths[i]} ${(err as Error).message}`);
      }
    }
    if (removed > 0) {
      logW(`tdlib temp cleanup: removed ${removed} stale chunk(s), freed ${Math.round(freed / 1048576)} MB ` +
        `(total before ${Math.round(total / 1048576)} MB, ageLimit ${Math.round(ageLimit / 60000)} min)`);
    }
  } catch (e) {
    // 清理是加分项，任何失败都不该影响启动流程。
    logE(`tdlib temp cleanup failed: ${(e as Error).message}`);
  }
}
