import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { coverOf } from '../../src/p0/garden.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

// P1 (q(118) ②, §5.7, SGODOT-240): a greenhouse is a glass roof over 4×4 plots — watered as sown, −25% (≤ −45% with
// Compost), regional crops at their home time, no trees or sprinklers inside, moved only while nothing grows there.
const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 10, 18, 0, 0);
const H = 3_600_000;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
function refused(s: P0State, cmd: P0Command, now = T0) {
  const r = applyP0(c, s, cmd, now);
  if (r.ok) throw new Error(`${cmd.type} was accepted`);
  return r;
}
/** Farming Lv8, Homestead Lv3 (40 plots), materials and coins for a greenhouse in storage. */
function grower(level = 8): P0State {
  const s = freshState(c, 'player-greenhouse-01', T0, 7);
  s.skills.farming = c.skills.farming[level - 1];
  s.homestead.level = 3;
  s.storage = { wood: 60, stone: 40, copper_ore: 30 };
  s.coins = 1000;
  s.energy.value = 300;
  return upgradeState(c, s, T0);
}
const build = (plot: number) => ({ type: 'place', recipe: 'craft_greenhouse', plot, space: 'home' }) as P0Command;
const sow = (s: P0State, id: number, seed = 'seed_radish') => {
  if (s.plots[id].state === 'wild') s = step(s, { type: 'till', plot: id }).s;
  s.bag.push({ id: seed, qty: 1 });
  return step(s, { type: 'sow', plot: id, seed }).s;
};
// plot 7 is grid [1,1]: its block is cols 1–4, rows 1–4
const BLOCK7 = [7, 8, 9, 10, 13, 14, 15, 16, 19, 20, 21, 22, 25, 26, 27, 28];

describe('a greenhouse over 4×4 plots (q(118) ②)', () => {
  it("roofs the 16 plots from its anchor, the block's lowest col and row", () => {
    expect(coverOf(c, 'greenhouse', 7).sort((a, b) => a - b)).toEqual(BLOCK7);
    expect(coverOf(c, 'greenhouse', 4)).toHaveLength(16);   // cols 4–7 (30–39 are cols 6–7), rows 0–3
    expect(coverOf(c, 'greenhouse', 4, 30)).toHaveLength(8);   // before Homestead Lv3: cols 4–5 only
  });

  it('is built at the workbench for 20 Timber, 12 Stone, 8 Copper Ore and 300 coins; wild plots under it are tilled', () => {
    let s = grower();
    s.plots[28] = { id: 28, state: 'wild' };
    const { s: a, ev } = step(s, build(7));
    expect(a.storage).toEqual({ wood: 40, stone: 28, copper_ore: 22 });
    expect(a.coins).toBe(700);
    expect(ev).toContainEqual({ kind: 'coins', delta: -300 });
    expect(a.plots[28].state).toBe('tilled');
    const v = viewOf(c, a, T0);
    expect(v.facilities).toEqual([{ id: 1, kind: 'greenhouse', plot: 7, covers: expect.arrayContaining(BLOCK7) }]);
    expect(v.plots.filter(p => p.greenhouse).map(p => p.id).sort((x, y) => x - y)).toEqual(BLOCK7);
    expect(v.plots.find(p => p.id === 7)).toMatchObject({ facility: null, greenhouse: true });   // still a field
    s = a;
  });

  it('needs Farming Lv8, a clear 4×4 block, and room under the cap: 1 at Lv8, 2 from Lv10', () => {
    const low = grower(7);
    expect(refused(low, build(7))).toMatchObject({ code: 'skill_level_required', detail: { level: 8 } });
    let s = sow(grower(), 14);
    expect(refused(s, build(7))).toMatchObject({ code: 'needs_clear_block', detail: { plots: [14], size: [4, 4] } });
    expect(refused(grower(), build(23))).toMatchObject({ code: 'needs_clear_block' });   // grid [5,3]: no col 8, no row 5
    s = step(grower(), build(0)).s;
    expect(refused(s, build(4))).toMatchObject({ code: 'facility_cap', detail: { cap: 1, used: 1, farming_next: 10 } });
    let ten = grower(10);
    ten = step(ten, build(0)).s;
    expect(refused(ten, build(2))).toMatchObject({ code: 'needs_clear_block' });   // overlaps the first
    ten = step(ten, build(4)).s;
    expect(refused(ten, build(24))).toMatchObject({ code: 'facility_cap', detail: { cap: 2, used: 2, farming_next: null } });
    const poor = grower();
    poor.coins = 200;
    expect(refused(poor, build(7))).toMatchObject({ code: 'no_coins', detail: { need: 140 } });
  });

  it('waters as sown, −25%, ≤ −45% with Compost, and grows a regional crop at its home time', () => {
    let s = step(grower(), build(7)).s;
    s = sow(s, 8);
    expect(s.plots[8]).toMatchObject({ state: 'growing', ready_at: T0 + Math.round(4 * H * 0.75) });
    expect(refused(s, { type: 'water', plot: 8 }).code).toBe('already_growing');
    s.bag.push({ id: 'fert_compost', qty: 1 });
    s = step(s, { type: 'fertilize', plot: 8 }).s;
    expect(s.plots[8].ready_at).toBe(T0 + Math.round(4 * H * 0.55));
    s = sow(s, 9, 'seed_pineapple');   // Tropical: 36 h in San Francisco's open field, 24 h under glass
    expect(s.plots[9].ready_at).toBe(T0 + Math.round(24 * H * 0.75));
  });

  it('keeps trees and sprinklers out', () => {
    let s = step(grower(), build(7)).s;
    s.bag.push({ id: 'seed_apple', qty: 1 });
    expect(refused(s, { type: 'sow', plot: 8, seed: 'seed_apple' } as P0Command).code).toBe('greenhouse_no_trees');
    s.storage = { ...s.storage, wood: 40, stone: 40, copper_ore: 40 };
    s.homestead.level = 3;
    s.skills.farming = c.skills.farming[7];
    expect(refused(s, { type: 'place', recipe: 'craft_sprinkler', plot: 14 } as P0Command)).toMatchObject({ code: 'plot_occupied', detail: { facility: 'greenhouse' } });
  });

  it('moves for free while nothing grows under it, and not while something does', () => {
    let s = step(grower(), build(7)).s;
    s = step(s, { type: 'move_facility', facility: 1, plot: 0 }).s;
    expect(viewOf(c, s, T0).plots.filter(p => p.greenhouse).map(p => p.id)).toContain(0);
    s = sow(s, 1);
    expect(refused(s, { type: 'move_facility', facility: 1, plot: 7 })).toMatchObject({ code: 'greenhouse_not_empty', detail: { plots: [1] } });
  });
});
