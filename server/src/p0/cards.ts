/** Recipe cards (plan §7.16.1, SGODOT-282). A card is bought once and turns its page Tasted (into the Cookbook);
 * the first cook still makes it Discovered and pays first-cook XP. The pool is on the recipes (Li Bai's 48 pages):
 * card_price, card_zone (Market, that climate) or card_zones (Stall, only those home climates). The Homestead Stall
 * shelves `stall_daily` cards a day, drawn from pages not yet in the Cookbook and fixed for the day. */
import { recipeById, type P0Content, type Recipe } from './content.js';
import { coinsNeeded } from './homestead.js';
import { climateAt, homeClimate } from './travel.js';
import type { P0Event } from './progress.js';
import { cookable } from './cooking.js';
import type { P0State } from './state.js';
import type { Refusal } from './fishing.js';

export const CARD = 'recipe_card_';
export const isCard = (id: string) => id.startsWith(CARD);
export const cardPage = (id: string) => id.slice(CARD.length);

/** A card's price (Stall 30 / 80, Market 200 / 500), or null for a page with no card. */
export function cardPrice(c: P0Content, id: string): number | null {
  return recipeById(c, cardPage(id))?.card_price ?? null;
}

/** Pages that can carry a card now: priced, and cookable in this build (a card for a page with no ingredients yet
 * would teach a dish nobody can make). */
const carded = (c: P0Content) => c.cooking.recipes.filter((r): r is Recipe & { card_price: number } => r.card_price !== undefined && cookable(c, r));

const mix = (h: number, text: string) => {
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
  return h >>> 0;
};

/** Today's Stall shelf: drawn on the first look of the day from the pool, without the pages already in the Cookbook,
 * then kept for the day (a card bought stays off; no new one replaces it). Deterministic per player and day. */
export function stallCards(c: P0Content, s: P0State): string[] {
  const cards = c.cooking.cards;
  if (!cards) return [];
  if (s.day.cards) return s.day.cards;
  const open = carded(c).filter(r => r.card_zone === undefined && (!r.card_zones || r.card_zones.includes(homeClimate(c, s))))
    .map(r => r.id).filter(page => !s.cookbook.includes(page));
  const seed = mix(2166136261, `${s.player}:${s.day.key}`);
  return open.map(page => ({ page, k: mix(seed, page) })).sort((a, b) => a.k - b.k)
    .slice(0, cards.stall_daily).map(x => CARD + x.page);
}

/** Fix today's shelf the first time a command looks at it, so buying never redraws. */
export function settleCards(c: P0Content, s: P0State): void {
  if (c.cooking.cards && !s.day.cards && s.day.key) s.day.cards = stallCards(c, s);
}

/** Market cards for this climate (Rare / Legendary regional pages). */
export function marketCards(c: P0Content, climate: string): string[] {
  return c.cooking.cards ? carded(c).filter(r => r.card_zone === climate).map(r => CARD + r.id) : [];
}

/** Buy a card at the counter that shelves it: the page goes into the Cookbook (Tasted). A Market shelves its own city's
 * climate cards (q(182), as its buy-back): the place's city, else the one the player is in. */
export function buyCard(c: P0Content, s: P0State, id: string, shop: string, events: P0Event[], place?: unknown): Refusal | null {
  const page = cardPage(id), price = cardPrice(c, id);
  const shelved = shop === 'homestead' ? stallCards(c, s) : shop === 'market' ? marketCards(c, climateAt(c, s, place)) : [];
  if (price === null || !shelved.includes(id)) return { code: 'bad_item' };
  if (s.cookbook.includes(page)) return { code: 'owned' };
  if (s.coins < coinsNeeded(c, price)) return { code: 'no_coins', detail: { need: coinsNeeded(c, price) - s.coins } };
  s.coins -= price;
  events.push({ kind: 'coins', delta: -price });
  s.cookbook.push(page);
  events.push({ kind: 'recipe', page, from: 'card' });
  return null;
}
