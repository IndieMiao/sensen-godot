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
/** Farming Lv8, Homestead Lv15 (36 Plots: rows 1–4 open end to end, SGODOT-355 b1), materials and coins in storage. */
function grower(level = 8, homestead = 15): P0State {
  const s = freshState(c, 'player-greenhouse-01', T0, 7);
  s.skills.farming = c.skills.farming[level - 1];
  s.homestead.level = homestead;
  s.storage = { wood: 60, stone: 40, copper_ore: 30 };
  s.coins = 1000;
  s.energy.value = 300;
  return upgradeState(c, s, T0);
}
const build = (plot: number) => ({ type: 'place', recipe: 'craft_greenhouse', plot, space: 'home' }) as P0Command;
const bed = (s: P0State, id: number) => s.plots.find(p => p.id === id)!;
const sow = (s: P0State, id: number, seed = 'seed_radish') => {
  if (bed(s, id).state === 'wild') s = step(s, { type: 'till', plot: id }).s;
  s.bag.push({ id: seed, qty: 1 });
  return step(s, { type: 'sow', plot: id, seed }).s;
};
/** The bed at [col, row] on the garden grid; the 16 beds of the 4×4 block whose lowest col and row that is. */
const at = (col: number, row: number) => c.garden.plots.findIndex(([x, y]) => x === col && y === row);
const block = (col: number, row: number) => {
  const ids: number[] = [];
  for (let y = row; y < row + 4; y++) for (let x = col; x < col + 4; x++) ids.push(at(x, y));
  return ids.sort((p, q) => p - q);
};
const A = at(1, 1), BLOCK = block(1, 1);   // cols 1–4, rows 1–4: open from Homestead Lv15
const inside = (k: number) => BLOCK.filter(id => id !== A)[k];

describe('a greenhouse over 4×4 plots (q(118) ②)', () => {
  it("roofs the 16 plots from its anchor, the block's lowest col and row", () => {
    expect(coverOf(c, 'greenhouse', A).sort((a, b) => a - b)).toEqual(BLOCK);
    expect(coverOf(c, 'greenhouse', at(3, 1))).toHaveLength(16);
    expect(coverOf(c, 'greenhouse', A, 26)).toHaveLength(12);   // Homestead Lv10: row 1 is not open yet
  });

  it('is built at the workbench for 20 Timber, 12 Stone, 8 Copper Ore and 300 coins; wild plots under it are tilled', () => {
    let s = grower();
    const w = inside(5);
    bed(s, w).state = 'wild';   // only a save from before SGODOT-355 b1 has wild beds
    const { s: a, ev } = step(s, build(A));
    expect(a.storage).toEqual({ wood: 40, stone: 28, copper_ore: 22 });
    expect(a.coins).toBe(700);
    expect(ev).toContainEqual({ kind: 'coins', delta: -300 });
    expect(bed(a, w).state).toBe('tilled');
    const v = viewOf(c, a, T0);
    expect(v.facilities).toEqual([{ id: 1, kind: 'greenhouse', plot: A, covers: expect.arrayContaining(BLOCK) }]);
    expect(v.plots.filter(p => p.greenhouse).map(p => p.id).sort((x, y) => x - y)).toEqual(BLOCK);
    expect(v.plots.find(p => p.id === A)).toMatchObject({ facility: null, greenhouse: true });   // still a field
    expect(v.garden.plots).toBe(36);   // a greenhouse opens no bed: its plots stay fields
    s = a;
  });

  it('needs Farming Lv8, a clear 4×4 block, and room under the cap: 1 at Lv8, 2 from Lv10', () => {
    const low = grower(7);
    expect(refused(low, build(A))).toMatchObject({ code: 'skill_level_required', detail: { level: 8 } });
    const busy = inside(3);
    let s = sow(grower(), busy);
    expect(refused(s, build(A))).toMatchObject({ code: 'needs_clear_block', detail: { plots: [busy], size: [4, 4] } });
    expect(refused(grower(), build(at(5, 3)))).toMatchObject({ code: 'needs_clear_block' });   // no col 8, no row 5
    // Homestead Lv12: row 1 has only cols 2–4 open, so a block from [2, 1] is not all open yet (`More plots open as your
    // Homestead grows`, 不知火舞); an anchor on a bed still to open is no bed at all
    expect(refused(grower(8, 12), build(at(2, 1)))).toMatchObject({ code: 'needs_clear_block', detail: { plots: [] } });
    expect(refused(grower(8, 12), build(at(1, -2)))).toMatchObject({ code: 'bad_plot' });
    s = step(grower(), build(at(-1, 1))).s;
    expect(refused(s, build(at(3, 1)))).toMatchObject({ code: 'facility_cap', detail: { cap: 1, used: 1, farming_next: 10 } });
    let ten = grower(10);
    ten = step(ten, build(at(-1, 1))).s;
    expect(refused(ten, build(A))).toMatchObject({ code: 'needs_clear_block' });   // overlaps the first
    ten = step(ten, build(at(3, 1))).s;
    expect(refused(ten, build(at(0, 1)))).toMatchObject({ code: 'facility_cap', detail: { cap: 2, used: 2, farming_next: null } });
    const poor = grower();
    poor.coins = 200;
    expect(refused(poor, build(A))).toMatchObject({ code: 'no_coins', detail: { need: 140 } });
  });

  it('waters as sown, −25%, ≤ −45% with Compost, and grows a regional crop at its home time', () => {
    const one = inside(0), two = inside(1);
    let s = step(grower(), build(A)).s;
    s = sow(s, one);
    expect(bed(s, one)).toMatchObject({ state: 'growing', ready_at: T0 + Math.round(4 * H * 0.75) });
    expect(refused(s, { type: 'water', plot: one }).code).toBe('already_growing');
    s.bag.push({ id: 'fert_compost', qty: 1 });
    s = step(s, { type: 'fertilize', plot: one }).s;
    expect(bed(s, one).ready_at).toBe(T0 + Math.round(4 * H * 0.55));
    s = sow(s, two, 'seed_pineapple');   // Tropical: 36 h in San Francisco's open field, 24 h under glass
    expect(bed(s, two).ready_at).toBe(T0 + Math.round(24 * H * 0.75));
  });

  it('keeps trees and sprinklers out', () => {
    let s = step(grower(), build(A)).s;
    s.bag.push({ id: 'seed_apple', qty: 1 });
    expect(refused(s, { type: 'sow', plot: inside(0), seed: 'seed_apple' } as P0Command).code).toBe('greenhouse_no_trees');
    s.storage = { ...s.storage, wood: 40, stone: 40, copper_ore: 40 };
    s.skills.farming = c.skills.farming[7];
    expect(refused(s, { type: 'place', recipe: 'craft_sprinkler', plot: inside(4) } as P0Command)).toMatchObject({ code: 'plot_occupied', detail: { facility: 'greenhouse' } });
  });

  it('moves for free while nothing grows under it, and not while something does', () => {
    const to = at(3, 1), under = block(3, 1).find(id => !BLOCK.includes(id))!;
    let s = step(grower(), build(A)).s;
    s = step(s, { type: 'move_facility', facility: 1, plot: to }).s;
    expect(viewOf(c, s, T0).plots.filter(p => p.greenhouse).map(p => p.id)).toContain(under);
    s = sow(s, under);
    expect(refused(s, { type: 'move_facility', facility: 1, plot: A })).toMatchObject({ code: 'greenhouse_not_empty', detail: { plots: [under] } });
  });
});
