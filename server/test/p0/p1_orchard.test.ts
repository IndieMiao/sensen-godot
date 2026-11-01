import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { catalog } from '../../src/p0/shops.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

// P1 perennials on the farm (q(118) ①, §5.2.4, SGODOT-240): a tree takes one plot, planted from its sapling
// for 6 Energy, picked for 2 every 48 h; Orchard Feed halves a regrowth; 1 + Homestead level trees, 8 at most.
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
/** Farming Lv9 (all three saplings open), Homestead Lv2 (3 trees), a bag of saplings and Orchard Feed. */
function grower(): P0State {
  const s = freshState(c, 'player-orchard-01', T0, 7);
  s.skills.farming = c.skills.farming[8];
  s.homestead.level = 2;
  s.energy.value = 200;
  s.coins = 500;
  s.bag = [{ id: 'seed_apple', qty: 4 }, { id: 'seed_grape', qty: 1 }, { id: 'fert_orchard', qty: 3 }];
  return s;
}
const plant = (seed: string, plot: number) => ({ type: 'sow', plot, seed }) as P0Command;
const plot = (s: P0State, id: number) => s.plots.find(p => p.id === id)!;
const wildPlot = (s: P0State) => s.plots.find(p => p.state === 'wild')!.id;

describe('saplings at the Market (§5.2.4)', () => {
  it('sells Apple Sapling from Farming Lv7, Citrus and Grapevine from Lv9, and Orchard Feed 10 a day', () => {
    expect(catalog(c, 'market', grower())).toEqual(expect.arrayContaining(['seed_apple', 'seed_citrus', 'seed_grape', 'fert_orchard']));
    expect(c.stall.buy).not.toContain('seed_apple');
    const row = (s: P0State, id: string) => viewOf(c, s, T0).shops.market.buy.find(o => o.id === id)!;
    const lv7 = { ...grower(), skills: { ...grower().skills, farming: c.skills.farming[6] } };
    expect(row(lv7, 'seed_apple')).toMatchObject({ price: 40, gate: 7, unlocked: true });
    expect(row(lv7, 'seed_citrus')).toMatchObject({ price: 80, gate: 9, unlocked: false });
    expect(row(lv7, 'fert_orchard')).toMatchObject({ price: 6, gate: 7, unlocked: true, daily: 10, left: 10 });
    const s = step(grower(), { type: 'buy', shop: 'market', item: 'seed_apple', qty: 1 } as P0Command).s;
    expect(s.coins).toBe(460);
  });
});

describe('a tree on a plot (q(118) ①)', () => {
  it('plants on one empty plot, tilled or wild, for 6 Energy, and grows at once', () => {
    let s = grower();
    s.plots.find(p => p.id === 5)!.state = 'wild';   // only a save from before SGODOT-355 b1 has wild beds
    const wild = wildPlot(s);
    const { s: a, ev } = step(s, plant('seed_apple', wild));
    // §4.2.1: the planting's XP share is locked as paid — Lv9 planting a Lv7 tree is 2 levels over: 75%
    expect(plot(a, wild)).toMatchObject({ state: 'growing', crop: 'crop_apple', ready_at: T0 + 48 * H, picks: 0, xp_pct: 75 });
    expect(a.energy.value).toBe(194);
    expect(ev).toContainEqual({ kind: 'tree', action: 'planted', plot: wild, crop: 'crop_apple', used: 1, cap: 3 });
    s = step(a, plant('seed_grape', 0)).s;   // a tilled plot
    expect(plot(s, 0)).toMatchObject({ state: 'growing', crop: 'crop_grape', ready_at: T0 + 60 * H });
    expect(viewOf(c, s, T0).orchard).toEqual({ used: 2, cap: 3, homestead_next: 3 });
    expect(viewOf(c, s, T0).plots.find(p => p.id === 0)).toMatchObject({ tree: true, picks: 0, crop: 'crop_grape' });
  });

  it('plants one at a time, never on a sown plot or a facility, and only while the orchard has room', () => {
    let s = grower();
    s.gear.hoes.push(c.tools.row_hoe.id);
    s.gear.hoe = c.tools.row_hoe.id;
    expect(refused(s, { type: 'sow', plots: [0, 1], seed: 'seed_apple' } as P0Command)).toMatchObject({ code: 'bad_plot', detail: { most: 1 } });
    s.bag.push({ id: 'seed_radish', qty: 1 });
    s = step(s, { type: 'sow', plot: 2, seed: 'seed_radish' }).s;
    expect(refused(s, plant('seed_apple', 2))).toMatchObject({ code: 'wrong_state' });
    for (const id of [0, 1, 3]) s = step(s, plant('seed_apple', id)).s;
    expect(refused(s, plant('seed_apple', 4))).toMatchObject({ code: 'orchard_full', detail: { used: 3, cap: 3, homestead_next: 3 } });
    // Homestead Lv7 on: 8 and nothing next
    expect(viewOf(c, { ...s, homestead: { level: 7, plaque: [] } }, T0).orchard).toEqual({ used: 3, cap: 8, homestead_next: null });
  });

  it('picks for 2 Energy every 48 h; the first pick counts the planting: 6 + 2 + 15 XP', () => {
    const lv7 = grower();
    lv7.skills.farming = c.skills.farming[6];   // Farming Lv7: the apple's own level, full XP
    let s = step(lv7, plant('seed_apple', 0)).s;
    expect(refused(s, { type: 'harvest', plot: 0 }, T0 + 47 * H)).toMatchObject({ code: 'not_ready' });
    const xp0 = s.skills.farming;
    const first = step(s, { type: 'harvest', plot: 0 }, T0 + 48 * H);
    s = first.s;
    expect(s.bag.find(b => b.id === 'crop_apple')?.qty).toBe(2);
    expect(first.ev).toContainEqual(expect.objectContaining({ kind: 'energy', delta: -2, reason: 'pick' }));
    expect(s.skills.farming - xp0).toBe(6 + 2 + 15);
    expect(plot(s, 0)).toMatchObject({ state: 'growing', crop: 'crop_apple', picks: 1, ready_at: T0 + 96 * H });
    const xp1 = s.skills.farming;
    s = step(s, { type: 'harvest', plot: 0 }, T0 + 96 * H).s;
    expect(s.skills.farming - xp1).toBe(2);
    expect(plot(s, 0).picks).toBe(2);
  });

  it('takes Orchard Feed after a pick (this regrowth −50%), not while it ripens first, and no Compost', () => {
    let s = step(grower(), plant('seed_apple', 0)).s;
    expect(refused(s, { type: 'fertilize', plot: 0, item: 'fert_orchard' } as P0Command, T0 + H).code).toBe('first_ripening');
    s = step(s, { type: 'harvest', plot: 0 }, T0 + 48 * H).s;
    s = step(s, { type: 'fertilize', plot: 0, item: 'fert_orchard' } as P0Command, T0 + 49 * H).s;
    expect(plot(s, 0)).toMatchObject({ fert: true, ready_at: T0 + 72 * H });
    expect(refused(s, { type: 'fertilize', plot: 0, item: 'fert_orchard' } as P0Command, T0 + 50 * H).code).toBe('fertilized');
    s.bag.push({ id: 'fert_compost', qty: 1 });
    expect(refused(s, { type: 'fertilize', plot: 0, item: 'fert_compost' } as P0Command, T0 + 50 * H).code).toBe('trees_take_orchard_feed');
    s = step(s, { type: 'harvest', plot: 0 }, T0 + 72 * H).s;
    expect(plot(s, 0)).toMatchObject({ ready_at: T0 + 120 * H });
    expect(plot(s, 0).fert).toBeUndefined();
    // Orchard Feed on an annual: trees only
    s.bag.push({ id: 'seed_radish', qty: 1 });
    s = step(s, { type: 'sow', plot: 5, seed: 'seed_radish' }, T0 + 72 * H).s;
    expect(refused(s, { type: 'fertilize', plot: 5, item: 'fert_orchard' } as P0Command, T0 + 72 * H).code).toBe('trees_only');
  });

  it('keeps sprinklers and Seed Saver out of it, and is chopped back to tilled ground', () => {
    let s = step(grower(), plant('seed_apple', 7)).s;
    expect(refused(s, { type: 'till', plot: 7 }).code).not.toBe('ok');
    s = step(s, { type: 'chop', plot: 7, space: 'home' } as P0Command).s;
    expect(plot(s, 7)).toEqual({ id: 7, state: 'tilled' });
    expect(viewOf(c, s, T0).orchard.used).toBe(0);
    expect(refused(s, { type: 'chop', plot: 7 } as P0Command).code).toBe('not_a_tree');
  });
});
