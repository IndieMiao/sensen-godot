import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { spotBlock } from '../../src/p0/decor.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

// P1 (q(118) ③, q(121), SGODOT-240 / 241): the Compost Bin stands on a yard cell (the decor yard's rules, never a
// plot), one from Farming Lv7 for 6 Timber and 4 Stone; any crop in the bag becomes Compost 1:1, 5 a player day.
const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 10, 2, 0, 0);
const H = 3_600_000;
const LV7 = c.skills.farming[6];

function step(s: P0State, cmd: P0Command, now = T0): P0State {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return r.state;
}
function refused(s: P0State, cmd: P0Command, now = T0) {
  const r = applyP0(c, s, cmd, now);
  if (r.ok) throw new Error(`${cmd.type} was accepted`);
  return r;
}
function f7(): P0State {
  const s = { ...freshState(c, 'player-compost-bin', T0, 7), created_at: T0 - 8 * 24 * H };
  s.skills.farming = LV7;
  s.storage = { wood: 20, stone: 20 };
  return upgradeState(c, s, T0);
}
const build = (s: P0State, x = 4, y = 15) => step(s, { type: 'place', recipe: 'craft_compost_bin', x, y, space: 'home' });
const crops = (s: P0State, id: string, qty: number) => { s.bag.push({ id, qty }); return s; };

describe('the Compost Bin on the yard (q(118) ③)', () => {
  it('is built at Farming Lv7 on a yard cell for 6 Timber and 4 Stone, and stands there', () => {
    const s = build(f7());
    expect(s.storage).toEqual({ wood: 14, stone: 16 });
    expect(s.facilities).toEqual([{ id: 1, kind: 'compost_bin', plot: -1, cell: [4, 15] }]);
    expect(viewOf(c, s, T0).facilities).toEqual([{ id: 1, kind: 'compost_bin', plot: -1, covers: [], cell: [4, 15] }]);
    const low = f7();
    low.skills.farming = LV7 - 1;
    expect(refused(low, { type: 'place', recipe: 'craft_compost_bin', x: 4, y: 15 })).toMatchObject({ code: 'skill_level_required', detail: { level: 7 } });
  });

  it('keeps to the yard: not on the field, a path or a yard object; one only', () => {
    const s = f7();
    expect(refused(s, { type: 'place', recipe: 'craft_compost_bin', x: 5, y: 5 }).code).toBe('decor_outside');   // the field
    expect(refused(s, { type: 'place', recipe: 'craft_compost_bin', x: 13, y: 14 }).code).toBe('decor_path');   // the stall's path
    // yard2 (v4q(12)): paths2 too, for that client alone
    expect(applyP0(c, s, { type: 'place', recipe: 'craft_compost_bin', x: 12, y: 15, space: 'home' }, T0, { yard2: true })).toMatchObject({ ok: false, code: 'decor_path' });
    expect(applyP0(c, s, { type: 'place', recipe: 'craft_compost_bin', x: 12, y: 15, space: 'home' }, T0).ok).toBe(true);
    expect(refused(s, { type: 'place', recipe: 'craft_compost_bin', x: 8, y: 15 }).code).toBe('decor_overlap');
    expect(refused(s, { type: 'place', recipe: 'craft_compost_bin', plot: 3 } as P0Command).code).toBe('bad_spot');
    const one = build(s);
    expect(refused(one, { type: 'place', recipe: 'craft_compost_bin', x: 6, y: 14 })).toMatchObject({ code: 'facility_cap', detail: { cap: 1, used: 1 } });
  });

  it('and decor keep out of each other\'s cells; it moves for free to another free cell', () => {
    let s = build(f7());
    expect(spotBlock(c, s, 'deco_planter', 4, 15, 0)?.code).toBe('decor_overlap');   // a piece can't go on the bin
    s.decor = { placed: [{ uid: 1, id: 'deco_planter', x: 6, y: 14, rot: 0 }], count: 1 };
    expect(refused(s, { type: 'move_facility', facility: 1, x: 6, y: 14 }).code).toBe('decor_overlap');   // nor the bin on a piece
    expect(refused(s, { type: 'move_facility', facility: 1, x: 4, y: 15 }).code).toBe('same_plot');
    s = step(s, { type: 'move_facility', facility: 1, x: 5, y: 15, space: 'home' });
    expect(s.facilities?.[0].cell).toEqual([5, 15]);
    expect(s.storage).toEqual({ wood: 14, stone: 16 });   // moving is free
  });
});

describe('composting (q(118) ③, q(121))', () => {
  it('turns any crop in the bag into Compost 1:1 at once — regional and fruit too', () => {
    let s = crops(crops(crops(build(f7()), 'crop_radish', 3), 'crop_apple', 1), 'crop_beet', 1);
    const r = applyP0(c, s, { type: 'compost', item: 'crop_radish', qty: 2, space: 'home' } as P0Command, T0);
    if (!r.ok) throw new Error(r.code);
    expect(r.events).toEqual(expect.arrayContaining([{ kind: 'item', id: 'crop_radish', delta: -2 }, { kind: 'item', id: 'fert_compost', delta: 2 },
      { kind: 'compost', item: 'crop_radish', qty: 2, used: 2, cap: 5 }]));
    s = r.state;
    s = step(s, { type: 'compost', item: 'crop_apple', qty: 1 });
    s = step(s, { type: 'compost', item: 'crop_beet', qty: 1 });
    expect(s.bag.find(b => b.id === 'fert_compost')?.qty).toBe(4);
    expect(s.bag.find(b => b.id === 'crop_radish')?.qty).toBe(1);
    expect(viewOf(c, s, T0).compost).toEqual({ cap: 5, used: 4, left: 1, resets_in: expect.any(Number) });
  });

  it('takes 5 a player day: the sixth is refused with the time to the reset; the next day starts again', () => {
    let s = crops(build(f7()), 'crop_radish', 8);
    s = step(s, { type: 'compost', item: 'crop_radish', qty: 5 });
    const r = refused(s, { type: 'compost', item: 'crop_radish', qty: 1 });
    expect(r).toMatchObject({ code: 'limit_reached', detail: { used: 5, cap: 5 } });
    expect((r.detail as { resets_in: number }).resets_in).toBeGreaterThan(0);
    expect(refused(crops(build(f7()), 'crop_radish', 8), { type: 'compost', item: 'crop_radish', qty: 6 }).code).toBe('limit_reached');
    s = step(s, { type: 'compost', item: 'crop_radish', qty: 3 }, T0 + 24 * H);
    expect(viewOf(c, s, T0 + 24 * H).compost).toMatchObject({ used: 3, left: 2 });
  });

  it('refuses what is not a crop, more than the bag holds, without a bin, and away from home', () => {
    const s = crops(crops(build(f7()), 'crop_radish', 2), 'seed_radish', 4);
    expect(refused(s, { type: 'compost', item: 'seed_radish', qty: 1 }).code).toBe('not_a_crop');
    expect(refused(s, { type: 'compost', item: 'crop_radish', qty: 3 })).toMatchObject({ code: 'not_enough', detail: { have: 2, need: 3 } });
    expect(refused(crops(f7(), 'crop_radish', 2), { type: 'compost', item: 'crop_radish', qty: 1 }).code).toBe('no_compost_bin');
    expect(viewOf(c, f7(), T0).compost).toBeNull();
    expect(refused(s, { type: 'compost', item: 'crop_radish', qty: 1, space: 'pond' } as P0Command).code).toBe('not_home');
  });

  it('makes its own room when a whole stack goes, and is refused when the Compost has nowhere to go', () => {
    const s = build(f7());
    s.bag = [{ id: 'crop_radish', qty: 2 }, ...Array.from({ length: s.bag_cap - 1 }, (_, i) => ({ id: `fish_filler_${i}`, qty: 1 }))];
    const whole = step(structuredClone(s), { type: 'compost', item: 'crop_radish', qty: 2 });   // the stack's slot takes the Compost
    expect(whole.bag[whole.bag.length - 1]).toEqual({ id: 'fert_compost', qty: 2 });
    expect(refused(s, { type: 'compost', item: 'crop_radish', qty: 1 }).code).toBe('bag_full');   // one of two leaves no slot
  });
});
