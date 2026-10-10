import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';

// P1 (§4.6.1, SGODOT-240): Seed Saver at Farming Lv10 — a harvest of a general annual gives back 1 seed of its kind 5%
// of the time, from a hash of the harvest (never the save's rng); regional crops and perennials never.
const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 10, 18, 0, 0);
const H = 3_600_000;

function harvest(s: P0State, crop: string, readyAt: number): { s: P0State; ev: P0Event[] } {
  s.plots[0] = { id: 0, state: 'growing', crop, ready_at: readyAt, xp_pct: 100 };
  const r = applyP0(c, s, { type: 'harvest', plot: 0 } as P0Command, readyAt + H);
  if (!r.ok) throw new Error(r.code);
  return { s: r.state, ev: r.events };
}
function farmer(level: number): P0State {
  const s = freshState(c, 'player-seed-saver', T0, 7);
  s.skills.farming = c.skills.farming[level - 1];
  s.bag = [];
  return s;
}
const saved = (ev: P0Event[]) => ev.filter(e => e.kind === 'seed_saved');

describe('Seed Saver (Farming Lv10)', () => {
  it('is in this build at Lv10, 5%', () => {
    expect(c.farming?.conveniences?.seed_saver).toBe(10);
    expect(c.farming?.seed_saver_chance).toBe(0.05);
  });

  it('gives back a seed about 1 harvest in 20 at Lv10, and never below it', () => {
    let hits = 0;
    for (let i = 0; i < 400; i++) {
      const { s, ev } = harvest(farmer(10), 'crop_radish', T0 + i * H);
      if (saved(ev).length) {
        hits++;
        expect(ev).toContainEqual({ kind: 'item', id: 'seed_radish', delta: 1 });
        expect(saved(ev)).toEqual([{ kind: 'seed_saved', id: 'seed_radish', plot: 0 }]);
        expect(s.bag.find(b => b.id === 'seed_radish')?.qty).toBe(1);
      }
      expect(saved(harvest(farmer(9), 'crop_radish', T0 + i * H).ev)).toEqual([]);
    }
    expect(hits).toBeGreaterThan(8);    // 400 × 5% = 20
    expect(hits).toBeLessThan(36);
  });

  it('is the same roll for the same harvest, and none for regional crops', () => {
    const hit = Array.from({ length: 400 }, (_, i) => T0 + i * H).find(t => saved(harvest(farmer(10), 'crop_radish', t).ev).length)!;
    expect(saved(harvest(farmer(10), 'crop_radish', hit).ev)).toHaveLength(1);
    expect(saved(harvest(farmer(10), 'crop_pumpkin', hit).ev)).toEqual([]);
  });

  it('puts the seed in Farm Storage when the bag has no room for it', () => {
    const hit = Array.from({ length: 400 }, (_, i) => T0 + i * H).find(t => saved(harvest(farmer(10), 'crop_radish', t).ev).length)!;
    const s = farmer(10);
    // a full bag, but with room for the radish: the radish stack is already there and not full
    s.bag = [{ id: 'crop_radish', qty: 1 }, ...Array.from({ length: s.bag_cap - 1 }, (_, i) => ({ id: `fish_filler_${i}`, qty: 1 }))];
    const out = harvest(s, 'crop_radish', hit).s;
    expect(out.bag.find(b => b.id === 'seed_radish')).toBeUndefined();
    expect(out.storage.seed_radish).toBe(1);
  });
});
