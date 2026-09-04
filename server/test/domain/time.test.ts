import { describe, expect, it } from 'vitest';
import { DateTime } from 'luxon';
import { dayStartMs, daysBetween, nextDayStartMs, playerDayId } from '../../src/domain/time.js';

const SH = 'Asia/Shanghai';
const LA = 'America/Los_Angeles';
/** 用带 offset 的绝对时间构造，避免测试自己踩进夏令时歧义。 */
const at = (iso: string) => DateTime.fromISO(iso, { setZone: true }).toMillis();

describe('playerDayId', () => {
  it('当地 04:00 换日，之前算前一天', () => {
    expect(playerDayId(at('2026-09-04T03:59:59+08:00'), SH)).toBe('2026-09-03');
    expect(playerDayId(at('2026-09-04T04:00:00+08:00'), SH)).toBe('2026-09-04');
    expect(playerDayId(at('2026-09-04T23:59:59+08:00'), SH)).toBe('2026-09-04');
  });

  it('同一时刻在两个城市可能属于不同玩家日', () => {
    const t = at('2026-09-04T12:00:00+08:00'); // 上海中午 = 洛杉矶前一天 21:00
    expect(playerDayId(t, SH)).toBe('2026-09-04');
    expect(playerDayId(t, LA)).toBe('2026-09-03');
  });

  /**
   * 2026-11-01 洛杉矶夏令时结束：当地 01:00 回拨到 01:00，01:30 出现两次，
   * 一次 UTC-07:00 一次 UTC-08:00。两次都在 04:00 之前，都算前一天。
   */
  it('秋季回拨：重复出现的当地 01:30 两次都归前一天', () => {
    const first = at('2026-11-01T01:30:00-07:00');
    const second = at('2026-11-01T01:30:00-08:00');
    expect(second - first).toBe(3600_000); // 确实是两个不同时刻
    expect(playerDayId(first, LA)).toBe('2026-10-31');
    expect(playerDayId(second, LA)).toBe('2026-10-31');
    expect(playerDayId(at('2026-11-01T04:00:00-08:00'), LA)).toBe('2026-11-01');
  });

  /** 2026-03-08 洛杉矶春季跳时：当地 02:00-03:00 不存在，但 04:00 边界不受影响。 */
  it('春季跳时：04:00 边界仍然只出现一次', () => {
    expect(playerDayId(at('2026-03-08T01:59:00-08:00'), LA)).toBe('2026-03-07');
    expect(playerDayId(at('2026-03-08T04:00:00-07:00'), LA)).toBe('2026-03-08');
  });

  it('未知时区抛错而不是静默用 UTC', () => {
    expect(() => playerDayId(Date.now(), 'Mars/Olympus')).toThrowError(/未知时区/);
  });
});

describe('dayStartMs / nextDayStartMs', () => {
  it('玩家日开始就是当地 04:00', () => {
    expect(dayStartMs('2026-09-04', SH)).toBe(at('2026-09-04T04:00:00+08:00'));
  });

  it('跨夏令时结束那天的一天是 25 小时，跨春季跳时是 23 小时', () => {
    const autumn = dayStartMs('2026-11-01', LA) - dayStartMs('2026-10-31', LA);
    const spring = dayStartMs('2026-03-08', LA) - dayStartMs('2026-03-07', LA);
    expect(autumn).toBe(25 * 3600_000);
    expect(spring).toBe(23 * 3600_000);
  });

  it('nextDayStartMs 连续推进跨过 DST 也不重复不跳过', () => {
    let t = at('2026-10-31T12:00:00-07:00');
    const days: string[] = [];
    for (let i = 0; i < 4; i++) {
      t = nextDayStartMs(t, LA);
      days.push(playerDayId(t, LA));
    }
    expect(days).toEqual(['2026-11-01', '2026-11-02', '2026-11-03', '2026-11-04']);
  });
});

describe('daysBetween', () => {
  it('跨 DST 仍按日历天算，不受 25 小时那天影响', () => {
    expect(daysBetween('2026-10-31', '2026-11-02')).toBe(2);
    expect(daysBetween('2026-09-04', '2026-09-04')).toBe(0);
  });
});
