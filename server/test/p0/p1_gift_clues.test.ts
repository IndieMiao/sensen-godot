/**
 * Gift Clues (§4.6.2 Fishing Lv7; q(167), 不知火舞 on 284): from Fishing Lv7 the view says which met residents love or
 * like each dish in the bag (the bag's ♥, `Liked by …`) and, per resident, what giving each dish adds (the gift
 * drawer's `♥ +3`, the Mystery Dish's −2). Dishes only: residents take no fish as gifts.
 */
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { recipeRarity } from '../../src/p0/cooking.js';
import { GIFT_CLUES_LEVEL, giftPoints, residentState } from '../../src/p0/residents.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { dayKey } from '../../src/p0/rules.js';
import { viewOf } from '../../src/p0/view.js';

const c: P0Content = loadP0Content();
const T0 = Date.UTC(2026, 9, 13, 18);
const xpFor = (level: number) => c.skills.fishing[level - 1];
const grilled = (rarity: number) => c.cooking.recipes.find(r => r.style === 'Grilled' && recipeRarity(c, r) === rarity)!.id;
const COMMON_GRILLED = grilled(1), FINE_GRILLED = grilled(2);
function player(level: number): P0State {
  const s = freshState(c, 'gift-clues', T0, 7);
  s.skills.fishing = xpFor(level);
  s.bag = [{ id: COMMON_GRILLED, qty: 1 }, { id: FINE_GRILLED, qty: 2 }, { id: 'fish_crucian', qty: 3 }, { id: c.cooking.mystery.id, qty: 1 }];
  return s;
}
const met = (s: P0State, id: string) => { residentState(s, id).chat_day = dayKey(c, s, T0); };   // talked once

describe('Gift Clues (q(167))', () => {
  it('nothing below Fishing Lv7', () => {
    const s = player(GIFT_CLUES_LEVEL - 1);
    met(s, 'res_old_kai');
    const v = viewOf(c, s, T0);
    expect(v.gift_clues).toBeNull();
    expect(v.residents.res_old_kai.gift_points).toBeNull();
  });

  it('the met residents who love or like each dish in the bag; fish, a dish anyone takes and the Mystery Dish are not clues', () => {
    const s = player(GIFT_CLUES_LEVEL);
    met(s, 'res_old_kai');   // likes Grilled
    met(s, 'res_pip');       // likes Dessert: takes a grilled dish, no clue
    const clues = viewOf(c, s, T0).gift_clues!;
    expect(clues[FINE_GRILLED]).toEqual([{ resident: 'res_old_kai', verdict: 'loved' }]);
    expect(clues[COMMON_GRILLED]).toEqual([{ resident: 'res_old_kai', verdict: 'liked' }]);
    expect(Object.keys(clues)).not.toContain('fish_crucian');
    expect(Object.keys(clues)).not.toContain(c.cooking.mystery.id);
    // a resident never talked to is no clue (no spoiler), whatever they like
    const fresh = player(GIFT_CLUES_LEVEL);
    expect(viewOf(c, fresh, T0).gift_clues).toEqual({});
  });

  it('each resident\'s gift points: what giving each dish adds, the Mystery Dish −2', () => {
    const s = player(GIFT_CLUES_LEVEL);
    met(s, 'res_old_kai');
    residentState(s, 'res_old_kai').gift_day = '2026-01-01';   // given before: q(220)'s first-gift +10 is spent (p1_first_gift)
    const pts = viewOf(c, s, T0).residents.res_old_kai.gift_points!;
    const kai = c.residents.res_old_kai;
    expect(pts[FINE_GRILLED]).toBe(giftPoints(c, s, kai, FINE_GRILLED).delta);
    expect(pts[FINE_GRILLED]).toBe(c.affinity.gift.loved_fine);
    expect(pts[COMMON_GRILLED]).toBe(c.affinity.gift.liked);
    expect(pts[c.cooking.mystery.id]).toBe(c.affinity.gift.mystery);
    expect(Object.keys(pts)).not.toContain('fish_crucian');
    // a Perfect pot of it adds Perfect's +1, within the cap
    s.bag.push({ id: `${FINE_GRILLED}@perfect`, qty: 1 });
    expect(viewOf(c, s, T0).residents.res_old_kai.gift_points![`${FINE_GRILLED}@perfect`])
      .toBe(Math.min(c.affinity.gift.loved_fine + c.affinity.gift.perfect, c.affinity.gift.cap));
  });
});
