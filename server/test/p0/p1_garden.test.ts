import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { coverOf, plotCount } from '../../src/p0/garden.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

// P1 step 1 (q(59) §1.1 / §1.4, SGODOT-239): 40 plots from Homestead Lv3, sprinklers on the garden grid.
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
/** F6 (§7 test table): Farming Lv6, Homestead Lv3 with its 40 plots, materials for three sprinklers in storage. */
function f6(): P0State {
  const s = fresh();
  s.skills.farming = LV6;
  s.homestead.level = 3;
  s.storage = { ...MATS };
  s.energy.value = 300;
  return upgradeState(c, s, T0);   // the fill adds plots 30–39
}
const plot = (s: P0State, id: number) => s.plots.find(p => p.id === id)!;
const sow = (s: P0State, id: number, seed = 'seed_radish') => {
  if (plot(s, id).state === 'wild') s = step(s, { type: 'till', plot: id }).s;
  s.bag.push({ id: seed, qty: 1 });
  return step(s, { type: 'sow', plot: id, seed }).s;
};

describe('the garden grid and 40 plots (q(59) §1.1)', () => {
  it('0–29 keep P0\'s 6 × 5 places; 30–39 are two new columns on the right, row by row', () => {
    expect(c.garden.plots.slice(0, 30)).toEqual(Array.from({ length: 30 }, (_, i) => [i % 6, Math.floor(i / 6)]));
    expect(c.garden.plots.slice(30, 40)).toEqual([[6, 0], [7, 0], [6, 1], [7, 1], [6, 2], [7, 2], [6, 3], [7, 3], [6, 4], [7, 4]]);
    // Homestead Lv7 (q(172) A): 40–47 a whole row in front of the field, row −1, left to right
    expect(c.garden.plots.slice(40)).toEqual([[0, -1], [1, -1], [2, -1], [3, -1], [4, -1], [5, -1], [6, -1], [7, -1]]);
  });

  it('Homestead Lv1–2 has 30 plots; the Lv3 upgrade adds 30–39 as wild, says so, and moves nothing', () => {
    const s = fresh();
    expect(s.plots.map(p => p.id)).toEqual(Array.from({ length: 30 }, (_, i) => i));
    expect(plotCount(c, s)).toBe(30);
    s.homestead.level = 2;
    s.skills = { farming: 150, fishing: 70, cooking: 0 };
    s.storage = { wood: 16, stone: 12, fiber: 10, clay: 4, rock_salt: 4 };
    s.coins = 440;
    s.plots[3] = { id: 3, state: 'growing', crop: 'crop_radish', ready_at: T0 + H, xp_pct: 100 };
    const { s: after, ev } = step(s, { type: 'homestead_upgrade' });
    expect(after.plots).toHaveLength(40);
    expect(after.plots.slice(30).every(p => p.state === 'wild')).toBe(true);
    expect(after.plots[3]).toEqual(s.plots[3]);
    expect(ev).toContainEqual({ kind: 'plots_added', plots: [30, 31, 32, 33, 34, 35, 36, 37, 38, 39], reason: 'homestead' });
    expect(viewOf(c, after, T0).garden).toEqual({ plots: 40 });
  });

  it('the plot count is the Homestead table\'s (homestead.plots), never past the garden grid', () => {
    expect(c.homestead.plots).toEqual([[1, 30], [3, 40], [7, 48]]);
    for (const [level, n] of [[1, 30], [2, 30], [3, 40], [6, 40], [7, 48], [10, 48]]) expect(plotCount(c, { ...fresh(), homestead: { level, plaque: [] } })).toBe(n);
    const big = { ...c, homestead: { ...c.homestead, plots: [[1, 30], [3, 60]] as [number, number][] } };
    expect(plotCount(big, { ...fresh(), homestead: { level: 3, plaque: [] } })).toBe(48);
  });

  it('a save already at Lv3 gets its 10 plots when it loads (T14), once', () => {
    const old = { ...fresh(), homestead: { level: 3, plaque: [] } } as P0State;
    delete (old as Partial<P0State>).facilities;
    const once = upgradeState(c, structuredClone(old), T0);
    expect(once.plots.map(p => p.id)).toEqual(Array.from({ length: 40 }, (_, i) => i));
    expect(upgradeState(c, structuredClone(once), T0).plots).toEqual(once.plots);
    expect(once.facilities).toEqual([]);
    expect(upgradeState(c, fresh(), T0).plots).toHaveLength(30);   // Lv1 stays at 30
  });

  it('the new plots work like the old: till for 0 Energy, sow, water, harvest (T15)', () => {
    let s = f6();
    const before = s.energy.value;
    s = step(s, { type: 'till', plot: 37 }).s;
    expect(s.energy.value).toBe(before);
    s = sow(s, 37);
    s = step(s, { type: 'water', plot: 37 }).s;
    s = step(s, { type: 'harvest', plot: 37 }, T0 + 5 * H).s;
    expect(plot(s, 37).state).toBe('tilled');
  });
});

describe('sprinklers (q(59) §1.4)', () => {
  it('cover the 8 plots around them on the grid, fewer at an edge, across old and new plots', () => {
    expect(coverOf(c, 'sprinkler', 7).sort((a, b) => a - b)).toEqual([0, 1, 2, 6, 8, 12, 13, 14]);
    expect(coverOf(c, 'sprinkler', 0, 40).sort((a, b) => a - b)).toEqual([1, 6, 7]);
    // from Homestead Lv7 the corner sprinkler reaches the new front row too (q(172))
    expect(coverOf(c, 'sprinkler', 0, 48).sort((a, b) => a - b)).toEqual([1, 6, 7, 40, 41]);
    expect(coverOf(c, 'sprinkler', 5, 40).sort((a, b) => a - b)).toEqual([4, 10, 11, 30, 32]);
    expect(coverOf(c, 'sprinkler', 5, 48).sort((a, b) => a - b)).toEqual([4, 10, 11, 30, 32, 44, 45, 46]);
    expect(coverOf(c, 'sprinkler', 30, 40).sort((a, b) => a - b)).toEqual([5, 11, 31, 32, 33]);
    expect(coverOf(c, 'sprinkler', 30, 48).sort((a, b) => a - b)).toEqual([5, 11, 31, 32, 33, 45, 46, 47]);
  });

  it('cover only the plots the homestead has: an edge sprinkler at Lv2 waters none of 30–39', () => {
    const s = { ...f6(), homestead: { level: 2, plaque: [] } } as P0State;
    s.plots = s.plots.filter(p => p.id < 30);
    const { s: after, ev } = step(s, { type: 'place', recipe: 'craft_sprinkler', plot: 5 });
    expect(ev).toContainEqual(expect.objectContaining({ kind: 'facility', covered: 3 }));
    expect(viewOf(c, after, T0).facilities[0].covers).toEqual([4, 10, 11]);
  });

  it('are built in one step: place takes the materials from storage and stands on the plot (T9)', () => {
    let s = sow(sow(f6(), 1), 13);   // two sown plots, not yet watered, in plot 7's ring
    const { s: after, ev } = step(s, { type: 'place', recipe: 'craft_sprinkler', plot: 7, space: 'home' });
    expect(after.storage).toEqual({ wood: 12, stone: 14, copper_ore: 4 });
    expect(after.facilities).toEqual([{ id: 1, kind: 'sprinkler', plot: 7, under: 'tilled' }]);
    expect(ev).toContainEqual({ kind: 'facility', action: 'placed', facility: 1, facility_kind: 'sprinkler', plot: 7, covered: 8, started: [1, 13] });
    // the two sown plots started growing at once, 15% sooner
    for (const id of [1, 13]) {
      expect(plot(after, id).state).toBe('growing');
      expect(plot(after, id).ready_at).toBe(T0 + Math.round(4 * H * 0.85));
    }
    s = after;
    const v = viewOf(c, s, T0);
    expect(v.plots.find(p => p.id === 0)).toMatchObject({ covered: true, facility: null });
    expect(v.plots.find(p => p.id === 7)).toMatchObject({ covered: false, facility: 1 });
    expect(v.facilities).toEqual([{ id: 1, kind: 'sprinkler', plot: 7, covers: [0, 1, 2, 6, 8, 12, 13, 14] }]);
  });

  it('water a covered plot as it is sown: growing at once, −15%, −35% with Compost; Water is refused', () => {
    let s = step(f6(), { type: 'place', recipe: 'craft_sprinkler', plot: 7 }).s;
    s = sow(s, 0);
    expect(plot(s, 0)).toMatchObject({ state: 'growing', ready_at: T0 + Math.round(4 * H * 0.85) });
    expect(refused(s, { type: 'water', plot: 0 }).code).toBe('already_growing');
    // composted before it was watered (sown outside, then the sprinkler moved over it): both cuts, capped at 35%
    let t = sow(f6(), 0);
    t.bag.push({ id: 'fert_compost', qty: 1 });
    t = step(t, { type: 'fertilize', plot: 0 }).s;
    t = step(t, { type: 'place', recipe: 'craft_sprinkler', plot: 7 }).s;
    expect(plot(t, 0).ready_at).toBe(T0 + Math.round(4 * H * 0.65));
    // a plot outside the ring still waits for water, and water there is the P0 time
    t = sow(t, 20);
    expect(plot(t, 20).state).toBe('sown');
    t = step(t, { type: 'water', plot: 20 }).s;
    expect(plot(t, 20).ready_at).toBe(T0 + 4 * H);
  });

  it('take a plot out of the field: nothing is tilled, sown, fed or harvested on it', () => {
    let s = step(f6(), { type: 'place', recipe: 'craft_sprinkler', plot: 31 }).s;   // a wild plot
    for (const cmd of [{ type: 'till', plot: 31 }, { type: 'harvest', plot: 31 }, { type: 'fertilize', plot: 31 }] as P0Command[])
      expect(refused(s, cmd).code).toBe('plot_occupied');
    s.bag.push({ id: 'seed_radish', qty: 3 });
    expect(refused(s, { type: 'sow', plot: 31, seed: 'seed_radish' }).code).toBe('plot_occupied');
  });

  it('refuse a plot with a crop or a facility, and one that is not a plot (T8)', () => {
    let s = sow(f6(), 4);
    expect(refused(s, { type: 'place', recipe: 'craft_sprinkler', plot: 4 })).toMatchObject({ code: 'plot_occupied' });
    expect(refused(s, { type: 'place', recipe: 'craft_sprinkler', plot: 99 }).code).toBe('bad_plot');
    s = step(s, { type: 'place', recipe: 'craft_sprinkler', plot: 7 }).s;
    expect(refused(s, { type: 'place', recipe: 'craft_sprinkler', plot: 7 })).toMatchObject({ code: 'plot_occupied', detail: { facility: 'sprinkler' } });
    expect(s.storage).toEqual({ wood: 12, stone: 14, copper_ore: 4 });   // a refusal takes nothing
  });

  it('need Farming Lv6, the materials and room under the cap: 3 + Homestead level (T12)', () => {
    const low = f6();
    low.skills.farming = LV6 - 10;
    expect(refused(low, { type: 'place', recipe: 'craft_sprinkler', plot: 7 })).toMatchObject({
      code: 'skill_level_required', detail: { skill: 'farming', level: 6, xp_to_go: 10 } });
    const poor = f6();
    poor.storage = { wood: 8, stone: 6, copper_ore: 1 };
    expect(refused(poor, { type: 'place', recipe: 'craft_sprinkler', plot: 7 })).toMatchObject({
      code: 'missing_materials', detail: { item: 'copper_ore', need: 3, have: 1 } });
    let s = f6();
    s.storage = { wood: 80, stone: 80, copper_ore: 80 };
    for (const id of [0, 3, 18, 21, 30, 38]) s = step(s, { type: 'place', recipe: 'craft_sprinkler', plot: id }).s;
    expect(refused(s, { type: 'place', recipe: 'craft_sprinkler', plot: 10 })).toMatchObject({
      code: 'facility_cap', detail: { cap: 6, used: 6, homestead_next: 4 } });   // Homestead goes to Lv10 since #209 (SGODOT-282)
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

  it('move for free to an empty plot; the old plot is tilled again; growing crops keep their time (T11)', () => {
    let s = sow(f6(), 0);
    s = step(s, { type: 'place', recipe: 'craft_sprinkler', plot: 7 }).s;
    const growing = plot(s, 0).ready_at;
    s = sow(s, 22);   // outside the ring: waits for water
    const storage = { ...s.storage };
    const { s: after, ev } = step(s, { type: 'move_facility', facility: 1, plot: 28 });
    expect(after.storage).toEqual(storage);
    expect(after.facilities).toEqual([{ id: 1, kind: 'sprinkler', plot: 28, under: 'wild' }]);   // 28 is one of P0's wild ten
    expect(plot(after, 7).state).toBe('tilled');
    expect(plot(after, 0).ready_at).toBe(growing);
    expect(plot(after, 22)).toMatchObject({ state: 'growing', ready_at: T0 + Math.round(4 * H * 0.85) });
    expect(ev).toContainEqual({ kind: 'facility', action: 'moved', facility: 1, facility_kind: 'sprinkler', plot: 28, from: 7, covered: 5, started: [22] });
    expect(refused(after, { type: 'move_facility', facility: 1, plot: 0 }).code).toBe('plot_occupied');
    expect(refused(after, { type: 'move_facility', facility: 9, plot: 10 }).code).toBe('bad_facility');
    expect(refused(after, { type: 'move_facility', facility: 1, plot: 28 }).code).toBe('same_plot');
  });

  it('leave wild ground wild when they move off it (亚瑟 on #207)', () => {
    let s = step(f6(), { type: 'place', recipe: 'craft_sprinkler', plot: 31 }).s;   // 31 is wild
    expect(plot(s, 31).state).toBe('wild');
    s = step(s, { type: 'move_facility', facility: 1, plot: 33 }).s;
    expect(plot(s, 31).state).toBe('wild');
    expect(s.facilities?.[0]).toMatchObject({ plot: 33, under: 'wild' });
    s = step(s, { type: 'move_facility', facility: 1, plot: 7 }).s;   // onto tilled ground, then away again
    expect(plot(s, 33).state).toBe('wild');
    s = step(s, { type: 'move_facility', facility: 1, plot: 3 }).s;
    expect(plot(s, 7).state).toBe('tilled');
  });

  it('are built and moved only at home', () => {
    expect(refused(f6(), { type: 'place', recipe: 'craft_sprinkler', plot: 7, space: 'pond' }).code).toBe('not_home');
  });
});
