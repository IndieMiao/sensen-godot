/** v4q(1) (SGODOT-355 b1): the batch-1 table, each skill's gate, the travel gate and content-driven Energy back. */
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0 } from '../../src/p0/reducer.js';
import { foodCap, levelEnergy, maxEnergy } from '../../src/p0/rules.js';
import { freshState, upgradeState, SAVE_VERSION } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content(), T = Date.UTC(2026, 9, 28, 2);
const VISIT = { n: 1, first_at: T, last_at: T, deliveries: 0, delivered_day: '' };
/** A save one level short of `level` with everything that level asks for: Lv10 skills, the coins and materials, and from
 * Lv16 the stamps and two other climate bands (Guangzhou, Moscow). */
function ready(level: number, energy: number, cc = c) {
  const s = freshState(cc, 'pacing-old-account', T, 4);
  s.created_at = T - 30 * 86400000;
  s.homestead.level = level - 1;
  const next = cc.homestead.levels.find(x => x.level === level)!;
  s.skills = { farming: cc.skills.farming[9], fishing: cc.skills.fishing[9], cooking: cc.skills.cooking[9] };
  s.coins = next.coins + 40; s.storage = Object.fromEntries(next.materials);
  s.energy = { value: energy, tick_ms: T };
  if (next.travel) {
    s.travel.stamps = Array.from({ length: next.travel.stamps }, (_, k) => ({ cluster: `gn-${k}`, kind: 'climate' as const, at: T, counted_on: '2026-10-28' }));
    s.travel.visits = { 'gn-1809858': VISIT, 'gn-524901': VISIT };
  }
  return s;
}
function upgrade(level: number, energy: number, cc = c) {
  const before = ready(level, energy, cc);
  const r = applyP0(cc, before, { type: 'homestead_upgrade', space: 'home' }, T);
  if (!r.ok) throw new Error(r.code);
  return { before, ...r };
}

describe('v4q(1): the batch-1 table to Lv17 and 50 Energy back to Lv15, for every account', () => {
  it('matches v4q(1) ②③④⑥: coins (2,125 in all), each skill\'s gate, the travel gate from Lv16, 50 back to Lv15', () => {
    const L = c.homestead.levels;
    expect(c.homestead.max_level).toBe(17);
    expect(L.map(l => l.level)).toEqual([2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]);
    expect(L.map(l => l.coins)).toEqual([40, 60, 70, 80, 80, 80, 80, 85, 90, 115, 120, 150, 175, 220, 280, 400]);
    expect(L.reduce((n, l) => n + l.coins, 0)).toBe(2125);
    expect(L.map(l => [l.skills.farming, l.skills.fishing, l.skills.cooking ?? null])).toEqual([
      [1, 1, null], [1, 1, null], [2, 2, null], [3, 2, null], [3, 3, 2], [4, 3, 3], [4, 4, 4], [4, 5, 4], [4, 5, 5], [4, 6, 5],
      [4, 6, 6], [5, 6, 6], [5, 6, 7], [6, 7, 7], [6, 7, 8], [7, 8, 8]]);
    expect(L.map(l => l.energy)).toEqual([50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 0, 0]);
    expect(L.map(l => l.travel ?? null)).toEqual([...Array(14).fill(null), { stamps: 6, climates: 1 }, { stamps: 8, climates: 2 }]);
    expect(L[0].materials).toEqual([['wood', 6], ['stone', 4], ['fiber', 3]]);
    expect(L[14].materials).toEqual([['hardwood', 13], ['flax', 9], ['iron_ore', 4], ['quartz', 2]]);   // Lv16: the bridge row, T2 only
  });

  it.each([2, 3, 4, 8, 11, 15])('Lv%d gives back only what fits: 50, the room left, nothing at or above the new pool', level => {
    const cap = 200 + levelEnergy(c, level);
    for (const [before, gain] of [[0, 50], [cap - 1, 1], [cap, 0], [cap + 15, 0]]) {
      const r = upgrade(level, before);
      expect(r.state.energy.value).toBe(before + gain);
      expect(r.events.find(e => e.kind === 'homestead')).toMatchObject({ level, energy: gain });
      expect(r.events.filter(e => e.kind === 'energy')).toEqual(gain ? [{ kind: 'energy', delta: gain, reason: 'homestead' }] : []);
      expect(r.state.v).toBe(r.before.v);
    }
  });

  it('the pool and the meal cap share one ladder: +10 a level to Lv10, then +5 (Lv10 290, Lv17 325)', () => {
    expect([1, 2, 10, 11, 15, 17].map(l => 200 + levelEnergy(c, l))).toEqual([200, 210, 290, 295, 315, 325]);
    const s = ready(17, 10);
    s.homestead.level = 17;
    expect(maxEnergy(c, s)).toBe(325);
    expect(foodCap(c, s, T)).toBe(c.cooking.food_cap + 125);
  });

  it('reads the reward from content, not a level check: Lv16–17 give nothing back', () => {
    const cc: P0Content = structuredClone(c);
    cc.homestead.levels[0].energy = 7;
    expect(upgrade(2, 100, cc).state.energy.value).toBe(107);
    for (const level of [16, 17]) {
      const r = upgrade(level, 1);
      expect(r.state.energy.value).toBe(1);
      expect(r.events.find(e => e.kind === 'homestead')).toMatchObject({ level, energy: 0 });
    }
  });

  it('can perform two affordable upgrades on an old Lv1 account, with separate payments/rewards and no automatic upgrade', () => {
    let s = ready(2, 0); s.coins = 140; s.storage = { wood: 8, stone: 8, fiber: 3, clay: 2 };   // Lv2 6 / 4 / reeds 3, Lv3 stone 4 wood 2 clay 2 (庚2)
    s.skills = { farming: c.skills.farming[1], fishing: c.skills.fishing[1], cooking: 0 };
    expect(viewOf(c, s, T).homestead.next!.can_upgrade).toBe(true);
    expect(s.homestead.level).toBe(1);
    for (const level of [2, 3]) {
      const r = applyP0(c, s, { type: 'homestead_upgrade', space: 'home' }, T);
      if (!r.ok) throw new Error(r.code);
      s = r.state;
      expect(s.homestead.level).toBe(level);
      expect(r.events.find(e => e.kind === 'homestead')).toMatchObject({ energy: 50 });
    }
    expect(s.energy.value).toBe(100); expect(s.coins).toBe(40); expect(s.storage).toEqual({});
    expect(s.homestead.plaque.map(p => p.level)).toEqual([2, 3]); expect(s.plots).toHaveLength(c.homestead.plots!.find(([lv]) => lv === 3)![1]);   // Lv3's beds (355 grid: 12)
  });

  it('loading existing reached levels neither downgrades nor refunds historical payments or rewards', () => {
    for (const level of [2, 3, 4, 5, 10, 17]) {
      const s = ready(level, 123); s.homestead.level = level; s.coins = 71;
      s.homestead.plaque = [{ level, at: T - 10 * 86400000 }];
      const before = { level, coins: s.coins, energy: s.energy.value, plaque: structuredClone(s.homestead.plaque) };
      const r = upgradeState(c, JSON.parse(JSON.stringify(s)), T);
      expect({ level: r.homestead.level, coins: r.coins, energy: r.energy.value, plaque: r.homestead.plaque }).toEqual(before);
      expect(r.v).toBe(SAVE_VERSION);
    }
  });
});
