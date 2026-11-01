import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { coverOf, plotCount } from '../../src/p0/garden.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

// P1 step 1 (q(59) §1.4, SGODOT-239): sprinklers on the garden grid. SGODOT-355 b1 (不知火舞 approved 哪吒's grid, 11-02):
// the grid is 9 × 7 = 63 beds, their ids in the order they open; the level's Plots, plus a bed for each tree and sprinkler.
const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 10, 2, 0, 0);
const H = 3_600_000;
const LV6 = c.skills.farming[5];   // 750 XP: Farming Lv6, the sprinkler's gate
const MATS = { wood: 20, stone: 20, copper_ore: 7 };

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
const fresh = () => ({ ...freshState(c, 'player-garden-01', T0, 7), created_at: T0 - 8 * 24 * H });
/** The bed at [col, row] on the garden grid. */
const at = (col: number, row: number) => c.garden.plots.findIndex(([x, y]) => x === col && y === row);
/** The beds round [col, row] (the 8 neighbours on the grid) of the first `open` ids, sorted. */
const ring = (col: number, row: number, open: number) => {
  const out: number[] = [];
  for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
    const id = at(col + dx, row + dy);
    if ((dx || dy) && id >= 0 && id < open) out.push(id);
  }
  return out.sort((x, y) => x - y);
};
const S = at(3, 3);   // a bed in the starting block whose 8 neighbours are all open from Lv10
/** F6 (§7 test table): Farming Lv6, Homestead Lv10 with its 26 Plots, materials for three sprinklers in storage. */
function f6(level = 10): P0State {
  const s = fresh();
  s.skills.farming = LV6;
  s.homestead.level = level;
  s.storage = { ...MATS };
  s.energy.value = 300;
  return upgradeState(c, s, T0);   // the fill opens the level's beds
}
const plot = (s: P0State, id: number) => s.plots.find(p => p.id === id)!;
const sow = (s: P0State, id: number, seed = 'seed_radish') => {
  if (plot(s, id).state === 'wild') s = step(s, { type: 'till', plot: id }).s;
  s.bag.push({ id: seed, qty: 1 });
  return step(s, { type: 'sow', plot: id, seed }).s;
};

describe('the garden grid and its Plots (SGODOT-355 b1)', () => {
  it('63 beds on the 2-cell lattice, cols −1…7 × rows −2…4, ids in the order they open', () => {
    const g = c.garden.plots;
    expect(g).toHaveLength(63);
    expect(new Set(g.map(([x, y]) => `${x},${y}`)).size).toBe(63);
    for (const [x, y] of g) { expect(x).toBeGreaterThanOrEqual(-1); expect(x).toBeLessThanOrEqual(7); expect(y).toBeGreaterThanOrEqual(-2); expect(y).toBeLessThanOrEqual(4); }
    // the starting 2 × 4 in front of the farmhouse door, then the back row outward toward the stall's side first
    expect(g.slice(0, 8)).toEqual([[2, 4], [3, 4], [4, 4], [5, 4], [2, 3], [3, 3], [4, 3], [5, 3]]);
    expect(g.slice(8, 13)).toEqual([[6, 4], [1, 4], [7, 4], [0, 4], [-1, 4]]);
  });

  it('a new homestead has the 8 starting Plots, all tilled; an upgrade opens the next ones tilled, says so, and moves nothing', () => {
    const s = fresh();
    expect(s.plots).toEqual(Array.from({ length: 8 }, (_, id) => ({ id, state: 'tilled' })));
    expect(plotCount(c, s)).toBe(8);
    s.skills = { farming: 2000, fishing: 2000, cooking: 2000 };
    s.storage = { wood: 50, stone: 50, fiber: 50, clay: 50, copper_ore: 50, rock_salt: 50 };
    s.coins = 5000;
    s.plots[3] = { id: 3, state: 'growing', crop: 'crop_radish', ready_at: T0 + H, xp_pct: 100 };
    const { s: after, ev } = step(s, { type: 'homestead_upgrade' });
    expect(after.plots.slice(8)).toEqual([{ id: 8, state: 'tilled' }, { id: 9, state: 'tilled' }]);
    expect(after.plots[3]).toEqual(s.plots[3]);
    expect(ev).toContainEqual({ kind: 'plots_added', plots: [8, 9], reason: 'homestead' });
    expect(viewOf(c, after, T0).garden).toEqual({ plots: 10, fields: { used: 1, cap: 10 } });
  });

  it('the Plots go by level (homestead.plots): 8, +2 a level to 36 at Lv15, 39, 41; never past the grid', () => {
    for (const [level, n] of [[1, 8], [2, 10], [10, 26], [15, 36], [16, 39], [17, 41]])
      expect(plotCount(c, { ...fresh(), plots: [], homestead: { level, plaque: [] } })).toBe(n);
    const big = { ...c, homestead: { ...c.homestead, plots: [[1, 99]] as [number, number][] } };
    expect(plotCount(big, fresh())).toBe(63);
  });

  it('a tree or a sprinkler takes a bed and opens the next one, so the Plots stay what the level gives', () => {
    let s = f6(1);   // 8 beds, Farming Lv6
    s.storage = { wood: 80, stone: 80, copper_ore: 80 };
    const placed = step(s, { type: 'place', recipe: 'craft_sprinkler', plot: S });
    expect(placed.ev).toContainEqual({ kind: 'plots_added', plots: [8], reason: 'facility' });
    expect(plotCount(c, placed.s)).toBe(9);
    expect(viewOf(c, placed.s, T0).garden).toEqual({ plots: 9, fields: { used: 0, cap: 8 } });
    s = placed.s;
    s.skills.farming = c.skills.farming[6];   // Farming Lv7: the apple sapling's level
    s.bag.push({ id: 'seed_apple', qty: 1 });
    const tree = step(s, { type: 'sow', plot: 0, seed: 'seed_apple' });
    expect(tree.ev).toContainEqual({ kind: 'plots_added', plots: [9], reason: 'facility' });
    expect(plotCount(c, tree.s)).toBe(10);
    expect(viewOf(c, tree.s, T0).garden.fields).toEqual({ used: 0, cap: 8 });   // a tree is not an annual
  });

  it('annuals stand on at most the Plots: one more is plots_full (a bed a moved sprinkler left open stays open)', () => {
    let s = fresh();
    s.plots.push({ id: 8, state: 'tilled' });   // opened by a sprinkler that has since moved off the field
    s.energy.value = 200;
    for (let id = 0; id < 8; id++) s = sow(s, id);
    s.bag.push({ id: 'seed_radish', qty: 1 });
    expect(refused(s, { type: 'sow', plot: 8, seed: 'seed_radish' })).toMatchObject({ code: 'plots_full', detail: { used: 8, cap: 8 } });
  });

  it('the new beds work like the old: sow, water, harvest (no Till: a bed opens tilled)', () => {
    let s = f6();
    const last = plotCount(c, s) - 1;
    expect(plot(s, last).state).toBe('tilled');
    s = sow(s, last);
    s = step(s, { type: 'water', plot: last }).s;
    s = step(s, { type: 'harvest', plot: last }, T0 + 5 * H).s;
    expect(plot(s, last).state).toBe('tilled');
  });
});

describe('sprinklers (q(59) §1.4)', () => {
  it('cover the 8 beds around them on the grid, fewer at an edge or where beds are not open yet', () => {
    expect(coverOf(c, 'sprinkler', S, 26)).toEqual(ring(3, 3, 26));
    expect(ring(3, 3, 26)).toHaveLength(8);
    expect(coverOf(c, 'sprinkler', at(2, 4), 26)).toEqual(ring(2, 4, 26));   // the back row: nothing behind it
    expect(ring(2, 4, 26)).toHaveLength(5);
    expect(coverOf(c, 'sprinkler', S, 8)).toEqual([0, 1, 2, 4, 6]);   // a new homestead: only the starting block is open
  });

  it('are built in one step: place takes the materials from storage and stands on the bed (T9)', () => {
    const [a1, a2] = ring(3, 3, 26);
    let s = sow(sow(f6(), a1), a2);   // two sown beds, not yet watered, in S's ring
    const { s: after, ev } = step(s, { type: 'place', recipe: 'craft_sprinkler', plot: S, space: 'home' });
    expect(after.storage).toEqual({ wood: 12, stone: 14, copper_ore: 4 });
    expect(after.facilities).toEqual([{ id: 1, kind: 'sprinkler', plot: S, under: 'tilled' }]);
    expect(ev).toContainEqual({ kind: 'facility', action: 'placed', facility: 1, facility_kind: 'sprinkler', plot: S, covered: 8, started: [a1, a2] });
    for (const id of [a1, a2]) {   // the two sown beds started growing at once, 15% sooner
      expect(plot(after, id).state).toBe('growing');
      expect(plot(after, id).ready_at).toBe(T0 + Math.round(4 * H * 0.85));
    }
    s = after;
    const v = viewOf(c, s, T0);
    expect(v.plots.find(p => p.id === a1)).toMatchObject({ covered: true, facility: null });
    expect(v.plots.find(p => p.id === S)).toMatchObject({ covered: false, facility: 1 });
    expect(v.facilities).toEqual([{ id: 1, kind: 'sprinkler', plot: S, covers: ring(3, 3, 27) }]);
  });

  it('water a covered bed as it is sown: growing at once, −15%, −35% with Compost; Water is refused', () => {
    const near = ring(3, 3, 26)[0], far = at(7, 3);
    let s = step(f6(), { type: 'place', recipe: 'craft_sprinkler', plot: S }).s;
    s = sow(s, near);
    expect(plot(s, near)).toMatchObject({ state: 'growing', ready_at: T0 + Math.round(4 * H * 0.85) });
    expect(refused(s, { type: 'water', plot: near }).code).toBe('already_growing');
    // composted before it was watered (sown outside, then the sprinkler moved over it): both cuts, capped at 35%
    let t = sow(f6(), near);
    t.bag.push({ id: 'fert_compost', qty: 1 });
    t = step(t, { type: 'fertilize', plot: near }).s;
    t = step(t, { type: 'place', recipe: 'craft_sprinkler', plot: S }).s;
    expect(plot(t, near).ready_at).toBe(T0 + Math.round(4 * H * 0.65));
    // a bed outside the ring still waits for water, and water there is the P0 time
    t = sow(t, far);
    expect(plot(t, far).state).toBe('sown');
    t = step(t, { type: 'water', plot: far }).s;
    expect(plot(t, far).ready_at).toBe(T0 + 4 * H);
  });

  it('take a bed out of the field: nothing is tilled, sown, fed or harvested on it', () => {
    const id = at(6, 4);
    let s = step(f6(), { type: 'place', recipe: 'craft_sprinkler', plot: id }).s;
    for (const cmd of [{ type: 'till', plot: id }, { type: 'harvest', plot: id }, { type: 'fertilize', plot: id }] as P0Command[])
      expect(refused(s, cmd).code).toBe('plot_occupied');
    s.bag.push({ id: 'seed_radish', qty: 3 });
    expect(refused(s, { type: 'sow', plot: id, seed: 'seed_radish' }).code).toBe('plot_occupied');
  });

  it('refuse a bed with a crop or a facility, and one that is not a bed (T8)', () => {
    let s = sow(f6(), 4);
    expect(refused(s, { type: 'place', recipe: 'craft_sprinkler', plot: 4 })).toMatchObject({ code: 'plot_occupied' });
    expect(refused(s, { type: 'place', recipe: 'craft_sprinkler', plot: 99 }).code).toBe('bad_plot');
    s = step(s, { type: 'place', recipe: 'craft_sprinkler', plot: S }).s;
    expect(refused(s, { type: 'place', recipe: 'craft_sprinkler', plot: S })).toMatchObject({ code: 'plot_occupied', detail: { facility: 'sprinkler' } });
    expect(s.storage).toEqual({ wood: 12, stone: 14, copper_ore: 4 });   // a refusal takes nothing
  });

  it('need Farming Lv6, the materials and room under the cap: 3 + Homestead level (T12)', () => {
    const low = f6();
    low.skills.farming = LV6 - 10;
    expect(refused(low, { type: 'place', recipe: 'craft_sprinkler', plot: S })).toMatchObject({
      code: 'skill_level_required', detail: { skill: 'farming', level: 6, xp_to_go: 10 } });
    const poor = f6();
    poor.storage = { wood: 8, stone: 6, copper_ore: 1 };
    expect(refused(poor, { type: 'place', recipe: 'craft_sprinkler', plot: S })).toMatchObject({
      code: 'missing_materials', detail: { item: 'copper_ore', need: 3, have: 1 } });
    let s = f6(3);   // Homestead Lv3: 12 Plots, room for 6
    s.storage = { wood: 80, stone: 80, copper_ore: 80 };
    for (const id of [0, 1, 2, 3, 4, 5]) s = step(s, { type: 'place', recipe: 'craft_sprinkler', plot: id }).s;
    expect(refused(s, { type: 'place', recipe: 'craft_sprinkler', plot: 6 })).toMatchObject({
      code: 'facility_cap', detail: { cap: 6, used: 6, homestead_next: 4 } });
    expect(plotCount(c, s)).toBe(18);   // the 12 Plots and a bed for each of the six
    const card = viewOf(c, s, T0).workbench.recipes.find(r => r.id === 'craft_sprinkler')!;
    expect(card).toMatchObject({ tab: 'facilities', cap: 6, used: 6, can_craft: false, block: { code: 'facility_cap' } });
    // Lv2: 5
    const two = { ...f6(), homestead: { level: 2, plaque: [] } };
    expect(viewOf(c, two, T0).workbench.recipes.find(r => r.id === 'craft_sprinkler')).toMatchObject({ cap: 5, used: 0, homestead_next: 3 });
  });

  it('stop growing with the Homestead at 10 (homestead.sprinkler_max): Lv6 9 → Lv7, Lv7 and on 10 with nothing next', () => {
    const at = (level: number) => ({ ...f6(), homestead: { level, plaque: [] } });
    const card = (level: number) => viewOf(c, at(level), T0).workbench.recipes.find(r => r.id === 'craft_sprinkler')!;
    expect(card(6)).toMatchObject({ cap: 9, homestead_next: 7 });
    expect(card(7)).toMatchObject({ cap: 10, homestead_next: null });
    expect(card(10)).toMatchObject({ cap: 10, homestead_next: null });
  });

  it('are never crafted into the bag: craft says place_only', () => {
    expect(refused(f6(), { type: 'craft', recipe: 'craft_sprinkler' }).code).toBe('place_only');
  });

  it('move for free to an empty bed; the old bed is tilled again; growing crops keep their time (T11)', () => {
    const near = ring(3, 3, 26)[0], to = at(7, 3), there = ring(7, 3, 27).find(id => !ring(3, 3, 27).includes(id))!;
    let s = sow(f6(), near);
    s = step(s, { type: 'place', recipe: 'craft_sprinkler', plot: S }).s;
    const growing = plot(s, near).ready_at;
    s = sow(s, there);   // outside S's ring: waits for water
    const storage = { ...s.storage };
    const { s: after, ev } = step(s, { type: 'move_facility', facility: 1, plot: to });
    expect(after.storage).toEqual(storage);
    expect(after.facilities).toEqual([{ id: 1, kind: 'sprinkler', plot: to, under: 'tilled' }]);
    expect(plot(after, S).state).toBe('tilled');
    expect(plot(after, near).ready_at).toBe(growing);
    expect(plot(after, there)).toMatchObject({ state: 'growing', ready_at: T0 + Math.round(4 * H * 0.85) });
    expect(ev).toContainEqual(expect.objectContaining({ kind: 'facility', action: 'moved', facility: 1, plot: to, from: S, started: [there] }));
    expect(refused(after, { type: 'move_facility', facility: 1, plot: near }).code).toBe('plot_occupied');
    expect(refused(after, { type: 'move_facility', facility: 9, plot: 10 }).code).toBe('bad_facility');
    expect(refused(after, { type: 'move_facility', facility: 1, plot: to }).code).toBe('same_plot');
  });

  it('leave wild ground wild when they move off it (亚瑟 on #207; only a save from before 355 b1 has wild beds)', () => {
    const wild = at(6, 4), other = at(1, 4);
    let s = f6();
    for (const id of [wild, other]) s.plots.find(p => p.id === id)!.state = 'wild';
    s = step(s, { type: 'place', recipe: 'craft_sprinkler', plot: wild }).s;
    expect(plot(s, wild).state).toBe('wild');
    s = step(s, { type: 'move_facility', facility: 1, plot: other }).s;
    expect(plot(s, wild).state).toBe('wild');
    expect(s.facilities?.[0]).toMatchObject({ plot: other, under: 'wild' });
    s = step(s, { type: 'move_facility', facility: 1, plot: S }).s;   // onto tilled ground, then away again
    expect(plot(s, other).state).toBe('wild');
    s = step(s, { type: 'move_facility', facility: 1, plot: 3 }).s;
    expect(plot(s, S).state).toBe('tilled');
  });

  it('are built and moved only at home', () => {
    expect(refused(f6(), { type: 'place', recipe: 'craft_sprinkler', plot: S, space: 'pond' }).code).toBe('not_home');
  });
});
