import { describe, expect, it } from 'vitest';
import { DateTime } from 'luxon';
import { DEFAULT_CONTENT_DIR, loadContent } from '../../src/domain/content.js';
import { conditionFor, derive } from '../../src/domain/derive.js';
import { createInitialState } from '../../src/domain/state.js';
import type { FarmState } from '../../src/domain/state.js';

const c = loadContent(DEFAULT_CONTENT_DIR);
const SH = 'Asia/Shanghai';
const at = (iso: string) => DateTime.fromISO(iso, { setZone: true }).toMillis();
const T0 = at('2026-09-04T10:00:00+08:00');

const state = (): FarmState => createInitialState({
  player_day_id: '2026-09-04', field_condition: 'sunny', now: T0, wallet: 180,
});

describe('成熟是派生的，不是存下来的状态', () => {
  it('ready_at 为 null 的格子永远不成熟——播种但未照料时安全暂停', () => {
    const s = state();
    s.cells['1,1'] = { state: 'sown', crop: 'R', watered_at: null, ready_at: null };
    expect(derive(s, T0 + 10 * 86400_000, SH, c).ripe_cells).toEqual([]);
  });

  it('ready_at <= now 即成熟，无需任何 tick', () => {
    const s = state();
    s.cells['1,1'] = { state: 'growing', crop: 'R', watered_at: T0, ready_at: T0 + 1000 };
    expect(derive(s, T0 + 999, SH, c).ripe_cells).toEqual([]);
    expect(derive(s, T0 + 1000, SH, c).ripe_cells).toEqual(['1,1']);
  });

  it('成熟后永久停留，不因换日清除（PRD §6.2 L393）', () => {
    const s = state();
    s.cells['1,1'] = { state: 'growing', crop: 'R', watered_at: T0, ready_at: T0 };
    expect(derive(s, T0 + 30 * 86400_000, SH, c).ripe_cells).toEqual(['1,1']);
  });
});

describe('玩家日与田况', () => {
  it('同一玩家日内 field_condition 不变，跨日才按脚本推进', () => {
    const s = state();
    expect(derive(s, T0 + 3600_000, SH, c).days_elapsed).toBe(0);
    expect(derive(s, T0 + 3600_000, SH, c).field_condition).toBe('sunny');
    const next = derive(s, at('2026-09-05T10:00:00+08:00'), SH, c);
    expect(next.days_elapsed).toBe(1);
    expect(next.weather_day_index).toBe(1);
    expect(next.field_condition).toBe('rain'); // 脚本第 2 项
  });

  it('漏两天时 weather_day_index 跳两格，不是补两次', () => {
    const s = state();
    const d = derive(s, at('2026-09-06T10:00:00+08:00'), SH, c);
    expect(d.days_elapsed).toBe(2);
    expect(d.weather_day_index).toBe(2);
    expect(d.field_condition).toBe('sunny'); // 脚本第 3 项
  });
});

describe('章节推进', () => {
  it('上一章未完成时漏日也不开新章（PRD L665 不跳章不作废）', () => {
    const s = state(); // 第 0 章 active
    const d = derive(s, at('2026-09-06T10:00:00+08:00'), SH, c);
    expect(d.opens_new_chapter).toBe(false);
    expect(d.chapter_index).toBe(0);
  });

  it('上一章完成且跨日才开新章；同一天内不开第二章（L667）', () => {
    const s = state();
    s.chapters[0].status = 'done';
    expect(derive(s, T0 + 3600_000, SH, c).opens_new_chapter).toBe(false);
    const d = derive(s, at('2026-09-05T10:00:00+08:00'), SH, c);
    expect(d.opens_new_chapter).toBe(true);
    expect(d.chapter_index).toBe(1);
  });

  it('D6 之后章节冻结在 6，但天气索引继续走——r1 的 mod 会永远卡在槽 6', () => {
    const s = state();
    s.clock.chapter_index = 6;
    s.clock.weather_day_index = 6;
    s.chapters.forEach(ch => { ch.status = 'done'; });
    const d = derive(s, at('2026-09-05T10:00:00+08:00'), SH, c);
    expect(d.opens_new_chapter).toBe(false);
    expect(d.chapter_index).toBe(6);
    expect(d.weather_day_index).toBe(7);
    expect(d.field_condition).toBe('sunny'); // 回到脚本第 1 项，而不是卡在 wind
  });
});

describe('conditionFor', () => {
  it('按 mod 循环且负数安全', () => {
    expect(conditionFor(0, c.weather.script)).toBe('sunny');
    expect(conditionFor(5, c.weather.script)).toBe('wind');
    expect(conditionFor(7, c.weather.script)).toBe('sunny');
    expect(conditionFor(12, c.weather.script)).toBe('wind');
    expect(conditionFor(-1, c.weather.script)).toBe('sunny');
  });
});
