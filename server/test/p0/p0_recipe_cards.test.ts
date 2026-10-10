/** SGODOT-282: recipe cards (§7.16.1) — the Homestead Stall's two a day, Market's climate cards; a card makes a page Tasted. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 10, 18);   // 11:00 in San Francisco (after the 04:00 rollover)
const DAY = 24 * 3_600_000;
const fresh = (): P0State => ({ ...freshState(c, 'cards-player', T0, 7), created_at: T0 - 8 * DAY, coins: 2_000 });
function step(s: P0State, cmd: P0Command, at = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, at);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const buy = (item: string, shop = 'homestead'): P0Command => ({ type: 'buy', item, qty: 1, shop });
const shelf = (s: P0State, at = T0) => viewOf(c, s, at).shops.homestead.cards;

describe('Recipe cards (§7.16.1)', () => {
  it('the Stall shows two cards a day from pages not in the Cookbook, the same two all day', () => {
    const s = fresh();
    const cards = shelf(s);
    expect(cards).toHaveLength(2);
    for (const card of cards) {
      expect(card.id).toBe(`recipe_card_${card.page}`);
      expect(s.cookbook).not.toContain(card.page);
      expect(card.price).toBe(card.rarity === 1 ? 30 : 80);
      expect(card.owned).toBe(false);
    }
    expect(shelf(s, T0 + 3_600_000)).toEqual(cards);
    const next = shelf(s, T0 + DAY).map(x => x.id);
    expect(next).toHaveLength(2);   // a new day draws again
  });

  it('only Temperate homes see page 14 and only tropical ones page 13; Market sells its climate card', () => {
    const temperate = viewOf(c, { ...fresh(), cookbook: c.cooking.recipes.map(r => r.id).filter(id => !['dish_tilapia_wraps', 'dish_crispy_smelt'].includes(id)) }, T0);
    expect(temperate.shops.homestead.cards.map(x => x.page)).toEqual(['dish_crispy_smelt']);
    expect(c.cooking.recipes.find(r => r.n === 14)).toMatchObject({ card_price: 80, card_zones: ['Temperate', 'Cool'] });
    expect(c.cooking.recipes.find(r => r.n === 47)).toMatchObject({ card_price: 500, card_zone: 'Temperate' });
    const s = fresh();
    s.cookbook = c.cooking.recipes.map(r => r.id);   // every cookable page known: nothing left to shelve
    expect(shelf(s)).toEqual([]);   // the silhouettes (13, 14, …) join once they are recipes (SGODOT-281)
    expect(viewOf(c, fresh(), T0).shops.market.cards).toEqual([   // San Francisco is Temperate: page 47
      { id: 'recipe_card_dish_pumpkin_chowder', page: 'dish_pumpkin_chowder', name: 'Pumpkin Chowder', rarity: 4, price: 500, need: 540, owned: false }]);
  });

  it('buying one puts the page in the Cookbook as Tasted, charges the price and leaves it off the shelf', () => {
    let s = fresh();
    const [card, other] = shelf(s);
    const r = step(s, buy(card.id));
    s = r.s;
    expect(s.cookbook).toContain(card.page);
    expect(s.coins).toBe(2_000 - card.price);
    expect(r.ev).toContainEqual({ kind: 'recipe', page: card.page, from: 'card' });
    expect(viewOf(c, s, T0).cooking.cookbook.find(p => p.id === card.page)).toMatchObject({ state: 'tasted' });
    expect(shelf(s)).toEqual([{ ...card, owned: true }, other]);   // today's shelf stays as drawn
    expect(applyP0(c, s, buy(card.id), T0)).toMatchObject({ ok: false, code: 'owned' });
  });

  it('refuses a card not on today\'s shelf, more than one at a time, and short coins (40 floor)', () => {
    const s = fresh();
    const today = shelf(s).map(x => x.id);
    const off = c.cooking.recipes.filter(r => r.card_price && !r.card_zone && !r.card_zones && r.n! <= 7 && !s.cookbook.includes(r.id))
      .map(r => `recipe_card_${r.id}`).find(id => !today.includes(id))!;
    expect(applyP0(c, s, buy(off), T0)).toMatchObject({ ok: false, code: 'bad_item' });
    expect(applyP0(c, s, { type: 'buy', item: today[0], qty: 2, shop: 'homestead' }, T0)).toMatchObject({ ok: false, code: 'bad_qty' });
    const poor = { ...fresh(), coins: 60 };
    const card = shelf(poor)[0];
    if (card.price + 40 > 60) expect(applyP0(c, poor, buy(card.id), T0)).toMatchObject({ ok: false, code: 'no_coins' });
  });
});
