import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { dishesFit, haveIngredient, ingredientStock, routeDish, takeIngredient } from '../../src/p0/kitchen_storage.js';
import type { P0Event } from '../../src/p0/progress.js';
import { freshState } from '../../src/p0/state.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 2, 0, 0);
const fresh = () => {
  const s = freshState(c, 'player-kitchen-01', T0, 7);
  s.bag = [];
  return s;
};

describe('kitchen storage (SGODOT-226; bag only until the rack and cabinet land)', () => {
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
});
