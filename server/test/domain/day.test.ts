import { describe, expect, it } from 'vitest';
import { BEDS, SH, at, advance, content, freshFarm, run, runAll } from './helpers.js';
import { makeCtx } from '../../src/domain/reducer.js';
import { materializeDay } from '../../src/domain/handlers/day.js';

const D = (n: number) => at(`2026-09-0${4 + n}T10:00:00+08:00`);
const done = (s = freshFarm()) => { s.chapters[s.clock.chapter_index].status = 'done'; return s; };

describe('章节 Grant 的物化顺序', () => {
  /**
   * 这是 Codex 二审 N-C1：库存只按作物聚合存绑定种子，分不清「上一章剩的」和「本章刚发的」。
   * 若写成「发 Grant → 清 bound」，D6 那份 C/H/L 各 1 会被同一步清掉，玩家要多花 24 金币
   * 补买，钱包 305 变 281、账户价值 545 变 521，PRD §7.5 的账本全错。
   */
  it('开新章时先清旧 bound 再发本章 Grant，新 Grant 不会被清掉', () => {
    const s = done(); // 第 0 章已发 6R+3L 并标记完成
    expect(s.inventory.seeds.R.bound).toBe(6);
    expect(s.inventory.seeds.L.bound).toBe(3);
    const next = advance(s, D(1)); // 开第 1 章，Grant = 3L
    expect(next.clock.chapter_index).toBe(1);
    expect(next.inventory.seeds.R.bound).toBe(0); // D0 没种完的 6R 作废
    expect(next.inventory.seeds.L.bound).toBe(3); // D1 新发的 3L 完好无损
  });

  it('D6 的 C/H/L 各 1 在清零之后发出，三种都在', () => {
    const s = freshFarm();
    s.clock.chapter_index = 5;
    s.clock.weather_day_index = 5;
    for (let i = 0; i <= 5; i++) { s.chapters[i].status = 'done'; s.chapters[i].grants_issued = true; }
    s.inventory.seeds.C.bound = 7; // 上一章剩下的，应当作废
    const next = advance(s, D(1));
    expect(next.clock.chapter_index).toBe(6);
    expect(next.inventory.seeds.C.bound).toBe(1);
    expect(next.inventory.seeds.H.bound).toBe(1);
    expect(next.inventory.seeds.L.bound).toBe(1);
  });

  it('grants_issued 幂等：同一章重复物化不会重复发放', () => {
    const s = done();
    const once = advance(s, D(1));
    const twice = advance(once, D(1));
    expect(twice.inventory.seeds.L.bound).toBe(3);
  });

  it('不开新章时不动 bound——漏一天不该惩罚玩家（PRD L665）', () => {
    const s = freshFarm(); // 第 0 章仍 active，未完成
    expect(s.inventory.seeds.R.bound).toBe(6);
    const next = advance(s, D(3)); // 隔三天回来
    expect(next.clock.chapter_index).toBe(0);
    expect(next.inventory.seeds.R.bound).toBe(6); // 种子还在
    expect(next.clock.weather_day_index).toBe(3); // 但天气照常推进
  });

  it('已播种的种子在格子里，不受清零影响', () => {
    const s = runAll(freshFarm(), [
        [{ type: 'till_cells', cell_ids: BEDS.slice(0, 3) }],
      [{ type: 'sow_cells', cell_ids: BEDS.slice(0, 3), crop: 'R', lot: 'bound' }],
    ]);
    s.chapters[0].status = 'done';
    const next = advance(s, D(1));
    expect(next.inventory.seeds.R.bound).toBe(0); // 仓里剩的 3R 作废
    expect(next.cells[BEDS[0]!]!.crop).toBe('R');     // 已下地的没事
    expect(next.cells[BEDS[0]!]!.state).toBe('sown');
  });
});

describe('换日重置', () => {
  it('摊位预算、回购次数、当日收获计数都按玩家日重置', () => {
    const s = freshFarm();
    s.stall = { day: '2026-09-04', settled: 100 };
    s.buyback = { day: '2026-09-04', sold: 1, week_total: 1 };
    s.xp.harvest_counted = { day: '2026-09-04', plants: 9 };
    const next = advance(s, D(1));
    expect(next.stall).toEqual({ day: '2026-09-05', settled: 0 });
    // week_total 跨日累计，不随换日清零——回购是周上限而不是日上限
    expect(next.buyback).toEqual({ day: '2026-09-05', sold: 0, week_total: 1 });
    expect(next.xp.harvest_counted).toEqual({ day: '2026-09-05', plants: 0 });
  });

  it('同一玩家日内多次物化是空操作', () => {
    const s = freshFarm();
    s.stall.settled = 42;
    const next = advance(s, at('2026-09-04T23:00:00+08:00'));
    expect(next.stall.settled).toBe(42);
  });
});

describe('时钟单调守卫', () => {
  it('时间倒退时拒绝执行命令', () => {
    const s = freshFarm();
    s.clock.last_effective_now = D(1);
    const r = run(s, { type: 'till_cells', cell_ids: [BEDS[0]!] });
    expect(r.ok === false && r.code).toBe('CLOCK_REGRESSION');
  });
});
