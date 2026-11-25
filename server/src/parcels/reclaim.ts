/**
 * 闲置地块回收（C-100，C-95#2 定的默认规则）：游客（没有账号的装上即建号玩家）超过 N 天没有登录或使用，
 * 他的地块收回，之后谁都可以重新认领。N 默认 30，用 PARCEL_IDLE_RECLAIM_DAYS 调，0 为不收回。
 * 有账号（邀请账号等）的玩家的地块不收：他们换设备、重装都能登录回来，地块不会成为没人用的空占。
 * 判定口径：最后活动时间 = 最后一次登录（players.last_seen_at）和最后一次用 token（tokens.last_used_at）中较晚的；
 * token 被撤销或过期时，它的最后使用时间先记到 players.last_seen_at 上（C-120），所以撤销全部 token 不会让地块提前收回。
 * 严格早于 now − N 天才收，正好满 N 天不收。
 */
import type { ParcelStore } from './store.js';

export const DEFAULT_IDLE_RECLAIM_DAYS = 30;
export const DAY_MS = 86_400_000;
/** 定时回收的间隔与每批条数。到期到真正收回最多差一个间隔。 */
export const RECLAIM_INTERVAL_MS = 10 * 60_000;
export const RECLAIM_BATCH = 200;

/** 不设或空为 30；0 关闭；1–3650 的整数天。其它值返回 null，进程拒绝启动。 */
export function parcelIdleDaysFromEnv(env: Record<string, string | undefined>): number | null {
  const raw = env.PARCEL_IDLE_RECLAIM_DAYS ?? '';
  if (raw === '') return DEFAULT_IDLE_RECLAIM_DAYS;
  if (!/^\d{1,4}$/.test(raw)) return null;
  const days = Number(raw);
  return days <= 3650 ? days : null;
}

/** 收回所有已到期的游客地块，返回收回的块数。days ≤ 0 时什么也不做。 */
export async function reclaimIdleParcels(store: ParcelStore, days: number, now: number, batch = RECLAIM_BATCH): Promise<number> {
  if (days <= 0) return 0;
  const cutoff = now - days * DAY_MS;
  let total = 0;
  for (;;) {
    const gone = await store.reclaimIdle(cutoff, now, batch);
    total += gone.length;
    if (gone.length < batch) return total;
  }
}

/**
 * 启动时先收一次，之后每 RECLAIM_INTERVAL_MS 收一次。多个进程同时跑也安全（挑选时 SKIP LOCKED，删到的行只有一个进程拿得到）。
 * 返回停止函数。
 */
export function scheduleIdleReclaim(store: ParcelStore, days: number, now: () => number,
  log: (line: string) => void, intervalMs = RECLAIM_INTERVAL_MS): () => void {
  if (days <= 0) return () => undefined;
  let running = false;
  const tick = async () => {
    if (running) return;
    running = true;
    try {
      const n = await reclaimIdleParcels(store, days, now());
      if (n > 0) log(`idle parcel reclaim: ${n} parcel(s) idle over ${days} days returned`);
    } catch (error) {
      log(`idle parcel reclaim failed: ${(error as Error).message}`);
    } finally { running = false; }
  };
  void tick();
  const timer = setInterval(() => { void tick(); }, intervalMs);
  timer.unref();
  return () => clearInterval(timer);
}
