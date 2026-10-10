import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';

// P1 (q(118) ④, SGODOT-240): Harvest All at Farming Lv9 takes every ripe annual of one garden row at once, 0 Energy,
// with a nearly full bag as many as fit, from the plot in front outward (q(123)); below Lv9, or across rows, refused.
const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 10, 18, 0, 0);
const H = 3_600_000;

function run(s: P0State, cmd: P0Command, now = T0 + 5 * H) { return applyP0(c, s, cmd, now); }
function farmer(level: number, ripe: number[]): P0State {
  const s = freshState(c, 'player-harvest-all', T0, 7);
  s.skills.farming = c.skills.farming[level - 1];
  s.bag = [];
  for (const id of ripe) s.plots[id] = { id, state: 'growing', crop: 'crop_radish', ready_at: T0 + 4 * H, xp_pct: 100 };
  return s;
}
const all = (plots: number[]) => ({ type: 'harvest', plot: plots[0], plots }) as P0Command;

describe('Harvest All (Farming Lv9)', () => {
  it("takes a row's ripe annuals at once, for no Energy", () => {
    const s = farmer(9, [6, 7, 9, 11]);   // row 1 of the garden grid: plots 6–11
    const before = s.energy.value;
    const r = run(s, all([6, 7, 9, 11]));
    if (!r.ok) throw new Error(r.code);
    expect(r.state.bag.find(b => b.id === 'crop_radish')?.qty).toBe(4);
    expect([6, 7, 9, 11].map(id => r.state.plots[id].state)).toEqual(['tilled', 'tilled', 'tilled', 'tilled']);
    expect(r.state.energy.value).toBeGreaterThanOrEqual(before);
    expect(r.events.filter((e: P0Event) => e.kind === 'xp')).toHaveLength(4 + 1);   // each plant, and the first harvest once
  });

  it('is refused below Farming Lv9, across rows, on an unripe plot, and when the bag cannot take even the first', () => {
    expect(run(farmer(8, [6, 7]), all([6, 7]))).toMatchObject({ ok: false, code: 'harvest_all_locked', detail: { level: 9 } });
    expect(run(farmer(9, [5, 6]), all([5, 6]))).toMatchObject({ ok: false, code: 'bad_plot' });   // 5 is row 0, 6 row 1
    const s = farmer(9, [6, 7]);
    s.plots[8] = { id: 8, state: 'growing', crop: 'crop_radish', ready_at: T0 + 9 * H, xp_pct: 100 };
    expect(run(s, all([6, 7, 8]))).toMatchObject({ ok: false, code: 'not_ready', detail: { plot: 8 } });
    const full = farmer(9, [6, 7]);
    full.bag = Array.from({ length: full.bag_cap }, (_, i) => ({ id: `fish_filler_${i}`, qty: 1 }));
    const r = run(full, all([6, 7]));
    expect(r).toMatchObject({ ok: false, code: 'bag_full', detail: { plot: 6 } });   // as a single plot
    expect(full.plots[6].state).toBe('growing');   // nothing was taken
  });

  it('takes what fits with a nearly full bag, from the plot in front outward, and says where it stopped (q(123))', () => {
    // row 1, the player at its right end: 11 is in front, then 10, 9 (radish) and 8, 7 (carrot); room for 3 radishes only
    const s = farmer(9, [11, 10, 9]);
    for (const id of [8, 7]) s.plots[id] = { id, state: 'growing', crop: 'crop_carrot', ready_at: T0 + 4 * H, xp_pct: 100 };
    const limit = c.bag.stack.crop;
    s.bag = [{ id: 'crop_radish', qty: limit - 3 },
      ...Array.from({ length: s.bag_cap - 1 }, (_, i) => ({ id: `fish_filler_${i}`, qty: 1 }))];
    const r = run(s, all([11, 10, 9, 8, 7]));
    if (!r.ok) throw new Error(r.code);
    expect(r.state.bag[0]).toEqual({ id: 'crop_radish', qty: limit });
    expect([11, 10, 9, 8, 7].map(id => r.state.plots[id].state)).toEqual(['tilled', 'tilled', 'tilled', 'growing', 'growing']);
    expect(r.events).toContainEqual({ kind: 'harvest_short', got: 3, of: 5, plot: 8 });
    expect(r.events.filter((e: P0Event) => e.kind === 'item')).toHaveLength(3);
    // the order is the client's: the same row sent the other way round fills from 7 and stops at the first radish
    const back = run(structuredClone(s), all([7, 8, 9, 10, 11]));
    expect(back).toMatchObject({ ok: false, code: 'bag_full', detail: { plot: 7 } });   // a carrot first: no room
    // a row that fits in full says nothing more
    const roomy = run(farmer(9, [6, 7]), all([6, 7]));
    expect(roomy.ok && roomy.events.some((e: P0Event) => e.kind === 'harvest_short')).toBe(false);
  });

  it('counts a seed Seed Saver put in for the plots after it: a crop is never cleared from its plot and lost (哪吒 on #269)', () => {
    const lucky = { ...c, farming: { ...c.farming!, seed_saver_chance: 1 } };   // every harvest gives a seed back
    const s = farmer(10, [6]);
    s.plots[7] = { id: 7, state: 'growing', crop: 'crop_carrot', ready_at: T0 + 4 * H, xp_pct: 100 };
    s.bag = Array.from({ length: s.bag_cap - 2 }, (_, i) => ({ id: `fish_filler_${i}`, qty: 1 }));   // two slots free
    const r = applyP0(lucky, s, all([6, 7]), T0 + 5 * H);
    if (!r.ok) throw new Error(r.code);
    // the radish and its seed take the two slots: the carrot stays ripe on its plot, and the reply says so
    expect(r.state.bag.filter(b => !b.id.startsWith('fish_filler_'))).toEqual([{ id: 'crop_radish', qty: 1 }, { id: 'seed_radish', qty: 1 }]);
    expect(r.state.plots[7]).toMatchObject({ state: 'growing', crop: 'crop_carrot' });
    expect(r.events).toContainEqual({ kind: 'harvest_short', got: 1, of: 2, plot: 7 });
    expect(r.events.some((e: P0Event) => e.kind === 'item' && e.id === 'crop_carrot')).toBe(false);
  });

  it('leaves trees out: a row with a ripe tree in it is refused, the tree is picked alone', () => {
    const s = farmer(9, [6, 7]);
    s.plots[8] = { id: 8, state: 'growing', crop: 'crop_apple', ready_at: T0 + 4 * H, xp_pct: 100, picks: 1 };
    expect(run(s, all([6, 7, 8]))).toMatchObject({ ok: false, code: 'not_ready', detail: { plot: 8, tree: true } });
    const pick = run(s, { type: 'harvest', plot: 8 } as P0Command);
    expect(pick.ok && pick.state.plots[8]).toMatchObject({ state: 'growing', crop: 'crop_apple', picks: 2 });
  });

  it('still harvests a single plot the old way at any level', () => {
    const r = run(farmer(1, [3]), { type: 'harvest', plot: 3 } as P0Command);
    expect(r.ok).toBe(true);
  });
});
