/** q(217) (SGODOT-343): Quick Radish Seeds, the first session's teaching seed — 45 s after it starts growing it is a Radish. */
import { describe, expect, it } from 'vitest';
import { cropById, itemName, loadP0Content, plotCrop, type P0Content } from '../../src/p0/content.js';
import { coverOf, seedSaver } from '../../src/p0/garden.js';
import type { GuideContent } from '../../src/p0/guide.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const T0 = Date.UTC(2026, 9, 26, 2);
const S = 1000;
const QUICK = 'seed_quick_radish';

/** The guide only starts with a table (339's steps): one step is enough for a guided save. */
const STEPS: GuideContent = { steps: [{ id: 't_sow_quick', phase: 'B', done_on: { key: 'sow:crop_quick_radish', count: 2 } }], recover: [], tips: {} };
function content(): P0Content {
  const c = loadP0Content();
  c.guide = structuredClone(STEPS);
  return c;
}
const c = content();

function run(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, { space: 'home', ...cmd } as P0Command, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return { s: r.state, ev: r.events };
}
function refused(s: P0State, cmd: P0Command, now = T0) {
  const r = applyP0(c, s, { space: 'home', ...cmd } as P0Command, now);
  if (r.ok) throw new Error(`${cmd.type} went through`);
  return r;
}
const guided = () => freshState(c, 'quick-radish-01', T0, 42, { guide: true });
const qty = (s: P0State, id: string) => s.bag.filter(b => b.id === id).reduce((n, b) => n + b.qty, 0);

describe('the start bag (q(217) ②)', () => {
  it('gives a guided save Quick Radish Seeds ×2 first, then the usual two stacks (3/25)', () => {
    const s = guided();
    expect(s.guide?.step).toBe('t_sow_quick');
    expect(s.bag).toEqual([{ id: QUICK, qty: 2 }, { id: 'seed_radish', qty: 20 }, { id: 'seed_lettuce', qty: 10 }]);
  });

  it('gives a save outside the guide the two stacks as before', () => {
    expect(freshState(c, 'quick-radish-02', T0, 42).bag).toEqual([{ id: 'seed_radish', qty: 20 }, { id: 'seed_lettuce', qty: 10 }]);
    // no steps in the table (the shipped one until 339's land): no guide, no quick seeds
    const plain = loadP0Content();
    plain.guide = { steps: [], recover: [], tips: {} };
    expect(freshState(plain, 'quick-radish-03', T0, 42, { guide: true }).bag.map(b => b.id)).toEqual(['seed_radish', 'seed_lettuce']);
  });
});

describe('sow, water and harvest (q(217) ①)', () => {
  it('sows for 2 Energy as a Quick Radish and ripens 45 s after watering', () => {
    let s = guided();
    const e0 = s.energy.value;
    s = run(s, { type: 'sow', plot: 0, seed: QUICK }).s;
    expect(s.energy.value).toBe(e0 - 2);
    expect(qty(s, QUICK)).toBe(1);
    expect(s.plots[0]).toMatchObject({ state: 'sown', crop: 'crop_quick_radish', xp_pct: 100 });
    s = run(s, { type: 'water', plot: 0 }, T0 + 10 * S).s;
    expect(s.plots[0]).toMatchObject({ state: 'growing', ready_at: T0 + 55 * S });
    expect(refused(s, { type: 'harvest', plot: 0 }, T0 + 54 * S).code).toBe('not_ready');
  });

  it('is harvested as a Radish: 1 crop_radish, 2 XP and the Radish first-harvest +10, no Quick Radish item', () => {
    let s = guided();
    s = run(s, { type: 'sow', plot: 0, seed: QUICK }).s;
    s = run(s, { type: 'water', plot: 0 }).s;
    const xp0 = s.skills.farming;
    const { s: out, ev } = run(s, { type: 'harvest', plot: 0 }, T0 + 45 * S);
    expect(qty(out, 'crop_radish')).toBe(1);
    expect(out.bag.some(b => b.id === 'crop_quick_radish')).toBe(false);
    expect(ev).toContainEqual({ kind: 'item', id: 'crop_radish', delta: 1 });
    expect(out.skills.farming - xp0).toBe(cropById(c, 'crop_radish')!.xp + cropById(c, 'crop_radish')!.first_xp);
    expect(out.firsts).toContain('harvest:crop_radish');
    expect(out.plots[0]).toEqual({ id: 0, state: 'tilled' });
    // the first-harvest bonus is the Radish's: a normal radish after it gets none
    let t = run(out, { type: 'sow', plot: 1, seed: 'seed_radish' }, T0 + 50 * S).s;
    t = run(t, { type: 'water', plot: 1 }, T0 + 50 * S).s;
    const xp1 = t.skills.farming;
    t = run(t, { type: 'harvest', plot: 1 }, T0 + 50 * S + 4 * 3_600_000).s;
    expect(t.skills.farming - xp1).toBe(cropById(c, 'crop_radish')!.xp);
  });

  // SGODOT-355 b1: on the new grid bed 6 [4, 3] is beside bed 7 [5, 3], both in a new homestead's 8
  it('keeps 45 s under a sprinkler and a greenhouse: growing as sown, no cut', () => {
    let s = guided();
    s.facilities = [{ id: 1, kind: 'sprinkler', plot: 7 }];
    s = run(s, { type: 'sow', plot: 6, seed: QUICK }).s;
    expect(s.plots[6]).toMatchObject({ state: 'growing', crop: 'crop_quick_radish', ready_at: T0 + 45 * S });
    let g = guided();
    g.facilities = [{ id: 1, kind: 'greenhouse', plot: 4 }];
    const under = coverOf(c, 'greenhouse', 4, g.plots.length).find(id => g.plots[id].state === 'tilled')!;
    g = run(g, { type: 'sow', plot: under, seed: QUICK }).s;
    expect(g.plots[under]).toMatchObject({ state: 'growing', ready_at: T0 + 45 * S });
  });

  it('a sprinkler built beside a sown Quick Radish starts it at 45 s too', () => {
    let s = guided();
    s.skills.farming = c.skills.farming[5];   // Farming Lv6, the sprinkler's gate
    s.storage = { wood: 20, stone: 20, copper_ore: 7 };
    s = run(s, { type: 'sow', plot: 6, seed: QUICK }).s;
    s = run(s, { type: 'place', recipe: 'craft_sprinkler', plot: 7 }, T0 + 5 * S).s;
    expect(s.plots[6]).toMatchObject({ state: 'growing', ready_at: T0 + 50 * S });
  });

  it('takes no Compost: the plot goes by its state, nothing is spent', () => {
    let s = guided();
    s.bag.push({ id: 'fert_compost', qty: 3 });
    s = run(s, { type: 'sow', plot: 0, seed: QUICK }).s;
    expect(refused(s, { type: 'fertilize', plot: 0, item: 'fert_compost' }).code).toBe('wrong_state');
    s = run(s, { type: 'water', plot: 0 }).s;
    expect(refused(s, { type: 'fertilize', plot: 0, item: 'fert_compost' }).code).toBe('wrong_state');
    expect(qty(s, 'fert_compost')).toBe(3);
  });

  it('never gives a seed back through Seed Saver', () => {
    const cc = loadP0Content();
    cc.farming!.seed_saver_chance = 1;
    const s = freshState(cc, 'quick-radish-04', T0, 42);
    s.skills.farming = cc.skills.farming[9];
    const plot = { id: 0, state: 'growing' as const, crop: 'crop_quick_radish', ready_at: T0, xp_pct: 100 };
    const ev: P0Event[] = [];
    seedSaver(cc, s, plotCrop(cc, 'crop_quick_radish')!, plot, ev);
    seedSaver(cc, s, cropById(cc, 'crop_radish')!, plot, ev);
    expect(ev.filter(e => e.kind === 'seed_saved')).toEqual([{ kind: 'seed_saved', id: 'seed_radish', plot: 0 }]);
  });

  it('counts sow: and water: on the plot crop for the guide', () => {
    let s = guided();
    s = run(s, { type: 'sow', plot: 0, seed: QUICK }).s;
    s = run(s, { type: 'sow', plot: 1, seed: QUICK }).s;
    expect(s.guide?.n['sow:crop_quick_radish']).toBe(2);
  });
});

describe('not a crop of the tables (q(217) ①, implementation note)', () => {
  it('is named, never sold, bought or listed as a crop', () => {
    expect(itemName(c, QUICK)).toBe('Quick Radish Seeds');
    expect(itemName(c, 'crop_quick_radish')).toBe('Quick Radish');
    expect(c.crops.some(x => x.id === 'crop_quick_radish' || x.seed === QUICK)).toBe(false);
    const s = guided();
    expect(refused(s, { type: 'sell', item: QUICK, qty: 1, shop: 'stall' }).ok).toBe(false);
    expect(refused(s, { type: 'buy', item: QUICK, qty: 1, shop: 'stall' }).ok).toBe(false);
    const v = viewOf(c, s, T0);
    expect(v.names[QUICK]).toBe('Quick Radish Seeds');
    expect(v.names['crop_quick_radish']).toBe('Quick Radish');
    expect(v.crops.some(x => x.id === 'crop_quick_radish')).toBe(false);
    expect(v.quick_seeds).toEqual([{ id: 'crop_quick_radish', seed: QUICK, energy: 2, grow_s: 45, harvest: 'crop_radish' }]);
    expect(v.items[QUICK]).toMatchObject({ name: 'Quick Radish Seeds', kind: 'seed', sell: null });
  });

  it('shows the plot as a Quick Radish with its seconds to go', () => {
    let s = guided();
    s = run(s, { type: 'sow', plot: 0, seed: QUICK }).s;
    s = run(s, { type: 'water', plot: 0 }).s;
    expect(viewOf(c, s, T0 + 15 * S).plots[0]).toMatchObject({ state: 'growing', crop: 'crop_quick_radish', ready_in: 30 * S, fert: false });
    expect(viewOf(c, s, T0 + 45 * S).plots[0]).toMatchObject({ state: 'ready', crop: 'crop_quick_radish' });
  });
});
