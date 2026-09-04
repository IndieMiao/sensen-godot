/**
 * 玩家日与时区。PRD §9.1 L666：`player_day_id` 按**所选城市时区**与**当地 04:00** 生成。
 *
 * 为什么不用 UTC 日：上海与洛杉矶的玩家应各自在自己的凌晨 4 点换日，而洛杉矶有夏令时。
 * 全部换算交给 luxon 的 IANA 数据，本模块不自己算偏移。
 */
import { DateTime } from 'luxon';

/** PRD §9.1：当地 04:00 之前算前一天。 */
export const DAY_ROLLOVER_HOUR = 4;

export function playerDayId(nowMs: number, timezone: string): string {
  const local = DateTime.fromMillis(nowMs, { zone: timezone });
  if (!local.isValid) throw new Error(`未知时区 ${timezone}: ${local.invalidReason}`);
  const shifted = local.hour < DAY_ROLLOVER_HOUR ? local.minus({ days: 1 }) : local;
  return shifted.toFormat('yyyy-MM-dd');
}

/**
 * 某个玩家日开始的绝对时刻（当地 04:00）。
 *
 * 夏令时的两个边界都由 luxon 处理：春季跳时那天当地 02:00-03:00 不存在，秋季回拨那天
 * 01:00-02:00 出现两次——但 04:00 在两种情况下都只出现一次，所以玩家日边界本身没有歧义。
 */
export function dayStartMs(dayId: string, timezone: string): number {
  const dt = DateTime.fromISO(dayId, { zone: timezone }).set({
    hour: DAY_ROLLOVER_HOUR, minute: 0, second: 0, millisecond: 0,
  });
  if (!dt.isValid) throw new Error(`非法玩家日 ${dayId} / ${timezone}: ${dt.invalidReason}`);
  return dt.toMillis();
}

/** 下一个玩家日开始的绝对时刻；QA 的 skip_days 按它逐日推进。 */
export function nextDayStartMs(nowMs: number, timezone: string): number {
  const today = playerDayId(nowMs, timezone);
  const next = DateTime.fromISO(today, { zone: timezone }).plus({ days: 1 }).toFormat('yyyy-MM-dd');
  return dayStartMs(next, timezone);
}

/** 两个玩家日之间相差几天（b - a）；用来推进 weather_day_index。 */
export function daysBetween(a: string, b: string): number {
  const da = DateTime.fromISO(a, { zone: 'utc' });
  const db = DateTime.fromISO(b, { zone: 'utc' });
  return Math.round(db.diff(da, 'days').days);
}
