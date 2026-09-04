import { describe, expect, it } from 'vitest';
import { BEDS, content, freshFarm, run, T0 } from './helpers.js';
import type { FarmState } from '../../src/domain/state.js';

const stocked = (over: Partial<FarmState> = {}): FarmState => {
  const s = freshFarm();
  s.inventory.produce = { R: 10, L: 10, C: 10, H: 10 };
  return { ...s, ...over };
};

describe('摊位（PRD §6.4 L431）', () => {
  it('按 items 顺序成交到 100 为止，装不下的原样留库存且不降价', () => {
    const s = stocked();
    const r = run(s, { type: 'sell_at_stall', items: [
      { kind: 'produce', id: 'C', qty: 6 }, // 96
      { kind: 'produce', id: 'H', qty: 2 }, // 19 一份，只剩 4 的额度 → 一份都卖不掉
    ] });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.stall.settled).toBe(96);
    expect(r.state.inventory.produce.H).toBe(10); // 原样留着
    expect(r.state.wallet).toBe(180 + 96);
  });

  it('部分成交：只卖装得下的那几件', () => {
    const s = stocked();
    const r = run(s, { type: 'sell_at_stall', items: [{ kind: 'produce', id: 'C', qty: 10 }] });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.stall.settled).toBe(96); // 6 份 ×16
    expect(r.state.inventory.produce.C).toBe(4);
  });

  it('额度已满且一件都卖不掉时才报 STALL_BUDGET', () => {
    const s = stocked();
    s.stall = { day: s.clock.player_day_id, settled: 100 };
    const r = run(s, { type: 'sell_at_stall', items: [{ kind: 'produce', id: 'R', qty: 1 }] });
    expect(r.ok === false && r.code).toBe('STALL_BUDGET');
  });

  it('工程篮预留物不进入出售候选（L574）', () => {
    const s = stocked();
    s.engineering.reserved = { C: 10 };
    const r = run(s, { type: 'sell_at_stall', items: [{ kind: 'produce', id: 'C', qty: 1 }] });
    expect(r.ok === false && r.code).toBe('INSUFFICIENT_ITEMS');
  });

  it('出售累加 sales_facts，供 resolve_life_choice(sold) 校验——不再隐式写生活槽', () => {
    const s = stocked();
    s.clock.chapter_index = 1;
    const r = run(s, { type: 'sell_at_stall', items: [{ kind: 'produce', id: 'R', qty: 2 }] });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.sales_facts[1]).toEqual({ R: 2 });
    expect(r.state.life_choices[1]).toBeUndefined(); // 槽没被隐式占掉
  });
});

describe('门口回购箱（PRD L534 / 决策⑦）', () => {
  const withTea = () => {
    const s = freshFarm();
    s.inventory.dishes.tea = 3;
    return s;
  };

  it('不占摊位预算——PRD 把它算在「居民请求」栏', () => {
    const s = withTea();
    s.stall = { day: s.clock.player_day_id, settled: 100 };
    const r = run(s, { type: 'sell_to_buyback_box', qty: 1 });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.wallet).toBe(180 + 24);
    expect(r.state.stall.settled).toBe(100); // 没动
  });

  it('首周上限 1 次——不限次数时高频账户价值上界会到 1026', () => {
    const first = run(withTea(), { type: 'sell_to_buyback_box', qty: 1 });
    expect(first.ok).toBe(true);
    if (!first.ok) return;
    const second = run(first.state, { type: 'sell_to_buyback_box', qty: 1 });
    expect(second.ok === false && second.code).toBe('BUYBACK_LIMIT');
  });
});

describe('料理', () => {
  it('厨房需第 3 章开放', () => {
    const s = freshFarm();
    s.inventory.produce = { R: 0, L: 1, C: 1, H: 1 };
    expect((run(s, { type: 'cook_dish', recipe: 'salad' }) as { code: string }).code).toBe('CHAPTER_LOCKED');
    s.clock.chapter_index = 3;
    const r = run(s, { type: 'cook_dish', recipe: 'salad' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.inventory.dishes.salad).toBe(1);
    expect(r.state.inventory.produce.C).toBe(0);
    expect(r.state.xp.total).toBe(10); // 首次配方 +10
  });
});

describe('安全线种苗包（PRD §7.6 L587）', () => {
  const broke = () => {
    const s = freshFarm();
    s.wallet = 0;
    s.inventory.seeds = { R: { bought: 0, bound: 0 }, L: { bought: 0, bound: 0 },
      C: { bought: 0, bound: 0 }, H: { bought: 0, bound: 0 } };
    return s;
  };

  it('身无分文且一无所有时可领 3 枚绑定小萝卜', () => {
    const r = run(broke(), { type: 'claim_seedling_pack' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.inventory.seeds.R.bound).toBe(3);
  });

  it('还有任何可回收资产就不发——否则高频玩家能把它当收入来源', () => {
    for (const mutate of [
      (s: FarmState) => { s.inventory.produce.R = 1; },
      (s: FarmState) => { s.inventory.dishes.tea = 1; },
      (s: FarmState) => { s.inventory.seeds.R.bought = 1; },
      (s: FarmState) => { s.engineering.reserved = { C: 1 }; },
      (s: FarmState) => { s.cells[BEDS[0]].state = 'growing'; },
    ]) {
      const s = broke();
      mutate(s);
      const r = run(s, { type: 'claim_seedling_pack' });
      expect(r.ok === false && r.code).toBe('NOT_AVAILABLE');
    }
  });

  it('钱够买最便宜的种子就不发', () => {
    const s = broke();
    s.wallet = content.crops.crops.R.seed_price;
    expect((run(s, { type: 'claim_seedling_pack' }) as { code: string }).code).toBe('NOT_AVAILABLE');
  });

  it('每玩家日一次、首周至多 2 次', () => {
    let s = broke();
    const a = run(s, { type: 'claim_seedling_pack' });
    expect(a.ok).toBe(true);
    if (!a.ok) return;
    // 同日再领
    expect((run(a.state, { type: 'claim_seedling_pack' }) as { code: string }).code).toBe('PACK_LIMIT');
    // 换日 + 清空后可领第二次，第三次撞周上限
    const s2 = broke(); s2.seedling_packs.days = ['2026-09-01', '2026-09-02'];
    expect((run(s2, { type: 'claim_seedling_pack' }) as { code: string }).code).toBe('PACK_LIMIT');
  });
});

describe('补贴', () => {
  it('竣工补贴要苗圃真的竣工，不能只靠到了第 6 章', () => {
    const s = freshFarm();
    s.clock.chapter_index = 6;
    expect((run(s, { type: 'claim_subsidy', subsidy_id: 'nursery_built' }) as { code: string }).code)
      .toBe('NOT_AVAILABLE');
    s.nursery.stage = 'built';
    const r = run(s, { type: 'claim_subsidy', subsidy_id: 'nursery_built' });
    expect(r.ok && r.state.wallet).toBe(180 + 60);
  });

  it('同一补贴只能领一次', () => {
    const s = freshFarm();
    s.clock.chapter_index = 1;
    const first = run(s, { type: 'claim_subsidy', subsidy_id: 'weather_story' });
    expect(first.ok).toBe(true);
    if (!first.ok) return;
    expect((run(first.state, { type: 'claim_subsidy', subsidy_id: 'weather_story' }) as { code: string }).code)
      .toBe('ALREADY_CLAIMED');
  });
});
