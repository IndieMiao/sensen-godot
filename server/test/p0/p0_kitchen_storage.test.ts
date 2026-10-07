import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { dishesFit, haveIngredient, ingredientStock, routeDish, takeIngredient } from '../../src/p0/kitchen_storage.js';
import type { P0Event } from '../../src/p0/progress.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 2, 0, 0);
const fresh = () => {
  const s = freshState(c, 'player-kitchen-01', T0, 7);
  s.bag = [];
  return s;
};

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
function refused(s: P0State, cmd: P0Command): { code: string; detail?: unknown } {
  const r = applyP0(c, s, cmd, T0);
  if (r.ok) throw new Error(`${cmd.type} was accepted`);
  return { code: r.code, detail: r.detail };
}
/** A finished Grilled Crucian pot (Common, no heat rings), ready to collect at T0. */
function readyPot(s: P0State): P0State {
  s.stove = { dish: 'dish_grilled_crucian', rarity: 1, started_at: T0 - 10_000, ms: 5_000, heats: [], xp_pct: 100, mystery: false };
  s.firsts.push('cook:dish_grilled_crucian');
  return s;
}
const atLevel = (level: number) => { const s = fresh(); s.homestead.level = level; return s; };

describe('kitchen storage (SGODOT-226)', () => {
  it('counts and takes ingredients across bag stacks, smallest first', () => {
    const s = fresh();
    s.bag = [{ id: 'fish_crucian', qty: 10 }, { id: 'fish_crucian', qty: 2 }];
    expect(haveIngredient(c, s, 'fish_crucian')).toBe(12);
    expect(ingredientStock(c, s).get('fish_crucian')).toBe(12);
    const ev: P0Event[] = [];
    takeIngredient(c, s, 'fish_crucian', 3, ev);
    expect(s.bag).toEqual([{ id: 'fish_crucian', qty: 9 }]);
    expect(ev).toEqual([{ kind: 'item', id: 'fish_crucian', delta: -3 }]);
  });

  it('a Perfect pot needs room for both portions; two new ids need two slots', () => {
    const s = fresh();
    s.bag_cap = 1;
    const perfect: [string, number][] = [['dish_grilled_crucian@perfect', 1], ['dish_grilled_crucian', 1]];
    expect(dishesFit(c, s, perfect)).toBe(false);
    s.bag_cap = 2;
    expect(dishesFit(c, s, perfect)).toBe(true);
    // A plain portion stacks onto an existing plain stack (dish stack 5) without a new slot.
    s.bag_cap = 2;
    s.bag = [{ id: 'dish_grilled_crucian', qty: 4 }];
    expect(dishesFit(c, s, perfect)).toBe(true);
    s.bag = [{ id: 'dish_grilled_crucian', qty: 5 }];
    expect(dishesFit(c, s, perfect)).toBe(false);
    expect(s.bag).toEqual([{ id: 'dish_grilled_crucian', qty: 5 }]);   // the check never changes the bag
  });

  it('routes a dish into the bag with an item event', () => {
    const s = fresh();
    const ev: P0Event[] = [];
    routeDish(c, s, 'dish_grilled_crucian', 1, ev);
    expect(s.bag).toEqual([{ id: 'dish_grilled_crucian', qty: 1 }]);
    expect(ev).toEqual([{ kind: 'item', id: 'dish_grilled_crucian', delta: 1 }]);
  });

  it('Lv1 cooks only from the bag; from Lv2 the Spice Rack reaches stored seasonings, storage first (q(46))', () => {
    const lv1 = atLevel(1);
    lv1.storage = { rock_salt: 4 };
    lv1.bag = [{ id: 'rock_salt', qty: 1 }];
    expect(haveIngredient(c, lv1, 'rock_salt')).toBe(1);
    expect(viewOf(c, lv1, T0).cooking.rack).toEqual({ on: false, items: [] });
    const lv2 = atLevel(2);
    lv2.storage = { rock_salt: 4, wood: 9 };
    lv2.bag = [{ id: 'rock_salt', qty: 1 }];
    expect(haveIngredient(c, lv2, 'rock_salt')).toBe(5);
    expect(ingredientStock(c, lv2).get('wood')).toBeUndefined();   // only seasonings sit on the rack
    expect(viewOf(c, lv2, T0).cooking.rack).toEqual({ on: true, items: [{ id: 'rock_salt', name: 'Rock Salt', qty: 4 }] });
    const ev: P0Event[] = [];
    takeIngredient(c, lv2, 'rock_salt', 5, ev);
    expect(lv2.storage).toEqual({ wood: 9 });
    expect(lv2.bag).toEqual([]);
    expect(ev).toEqual([{ kind: 'item', id: 'rock_salt', delta: -1 }]);   // only the bag part is an item event
  });

  it('cooking at Lv2 uses the Rock Salt the Spice Rack put in storage; Lv1 does not reach storage', () => {
    const lv1 = atLevel(1);
    lv1.storage = { rock_salt: 2 };
    lv1.bag = [{ id: 'fish_crucian', qty: 1 }];
    expect(refused(lv1, { type: 'cook', items: ['fish_crucian', 'rock_salt'] })).toMatchObject({ code: 'not_enough', detail: { item: 'rock_salt' } });
    const lv2 = atLevel(2);
    lv2.storage = { rock_salt: 2 };
    lv2.bag = [{ id: 'fish_crucian', qty: 2 }];
    lv2.cookbook.push('dish_herb_grilled_fish');
    expect(viewOf(c, lv2, T0).cooking.cookbook.find(p => p.id === 'dish_herb_grilled_fish')?.can_cook).toBe(true);
    const r = step(lv2, { type: 'cook', recipe: 'dish_herb_grilled_fish' });
    expect(r.s.storage).toEqual({ rock_salt: 1 });
    expect(r.s.bag).toEqual([{ id: 'fish_crucian', qty: 1 }]);
    expect(r.ev.filter(e => e.kind === 'item')).toEqual([{ kind: 'item', id: 'fish_crucian', delta: -1 }]);
  });

  it('Lv3 keeps dishes in the Warming Cabinet, then the bag, then on the stove', () => {
    let s = readyPot(atLevel(3));
    s.cabinet = [{ id: 'dish_grilled_crucian', qty: 5 }];
    let r = step(s, { type: 'collect', taps: [] });
    expect(r.s.cabinet).toEqual([{ id: 'dish_grilled_crucian', qty: 6 }]);
    expect(r.ev).toContainEqual({ kind: 'cabinet', id: 'dish_grilled_crucian', delta: 1, to_bag: 0, have: 6, cap: 6 });
    expect(r.ev.some(e => e.kind === 'item')).toBe(false);
    // Full cabinet: the dish goes to the bag (Cabinet full · … sent to bag).
    s = readyPot(r.s);
    r = step(s, { type: 'collect', taps: [] });
    expect(r.s.bag).toEqual([{ id: 'dish_grilled_crucian', qty: 1 }]);
    expect(r.ev).toContainEqual({ kind: 'cabinet', id: 'dish_grilled_crucian', delta: 0, to_bag: 1, have: 6, cap: 6 });
    // Cabinet and bag full: the dish stays on the stove.
    s = readyPot(r.s);
    s.bag_cap = 1;
    s.bag = [{ id: 'fish_crucian', qty: 1 }];
    expect(refused(s, { type: 'collect', taps: [] })).toEqual({ code: 'bag_full', detail: { cabinet: true } });
    // …but COOK-4 Eat still works straight from the pot.
    s.energy = { value: 100, tick_ms: T0 };
    r = step(s, { type: 'collect', taps: [], eat: true });
    expect(r.s.stove).toBeNull();
    expect(r.s.cabinet).toEqual([{ id: 'dish_grilled_crucian', qty: 6 }]);
    expect(r.ev.find(e => e.kind === 'meal')).toMatchObject({ dish: 'dish_grilled_crucian' });
  });

  it('a Lv1–2 kitchen has no cabinet: dishes go to the bag and the view says null', () => {
    const r = step(readyPot(atLevel(2)), { type: 'collect', taps: [] });
    expect(r.s.cabinet).toEqual([]);
    expect(r.ev.some(e => e.kind === 'cabinet')).toBe(false);
    expect(viewOf(c, r.s, T0).cooking.cabinet).toBeNull();
    expect(refused(r.s, { type: 'cabinet_take', item: 'dish_grilled_crucian' }).code).toBe('locked');
  });

  it('cabinet dishes can be eaten or taken out one at a time (Eat / Take one / Bag full)', () => {
    const s = atLevel(3);
    s.cabinet = [{ id: 'dish_grilled_crucian', qty: 2 }];
    s.energy = { value: 100, tick_ms: T0 };
    expect(viewOf(c, s, T0).cooking.cabinet).toEqual({ cap: 6, have: 2,
      items: [{ id: 'dish_grilled_crucian', name: 'Grilled Crucian', qty: 2, energy: 20 }] });
    let r = step(s, { type: 'eat', item: 'dish_grilled_crucian', from: 'cabinet' });
    expect(r.s.cabinet).toEqual([{ id: 'dish_grilled_crucian', qty: 1 }]);
    expect(r.ev).toContainEqual({ kind: 'cabinet', id: 'dish_grilled_crucian', delta: -1, to_bag: 0, have: 1, cap: 6 });
    expect(r.ev.find(e => e.kind === 'meal')).toMatchObject({ dish: 'dish_grilled_crucian', nominal: 20 });
    r = step(r.s, { type: 'cabinet_take', item: 'dish_grilled_crucian' });
    expect(r.s.cabinet).toEqual([]);
    expect(r.s.bag).toEqual([{ id: 'dish_grilled_crucian', qty: 1 }]);
    const full = atLevel(3);
    full.cabinet = [{ id: 'dish_grilled_crucian', qty: 1 }];
    full.bag_cap = 1;
    full.bag = [{ id: 'fish_crucian', qty: 1 }];
    expect(refused(full, { type: 'cabinet_take', item: 'dish_grilled_crucian' }).code).toBe('bag_full');
  });
});
