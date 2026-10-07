/**
 * Shared by the request boards and residents (plan §9.6.2, §9.13.2): what counts as a match, which bag items are
 * handed in, and what it pays. Requests never pay XP; gift meals and bought goods are never handed in.
 */
import { cropById, dishBuyback, dishParts, fishById, itemKind, recipeById, type Need, type P0Content } from './content.js';
import { recipeRarity } from './cooking.js';
import type { P0State } from './state.js';

/** Rarity of a bag id for a request: fish by species, dishes by recipe (0 = Mystery Dish / unknown). */
export function rarityOf(c: P0Content, id: string): number {
  if (itemKind(id) === 'fish') return fishById(c, id)?.rarity ?? 0;
  if (itemKind(id) === 'dish') {
    const recipe = recipeById(c, dishParts(id).base);
    return recipe ? recipeRarity(c, recipe) : 0;
  }
  return 0;
}

/** Does one bag id satisfy a need? items narrows to fixed ids chosen when the request was drawn. */
export function matches(c: P0Content, need: Pick<Need, 'kind' | 'rarity'>, items: string[], id: string): boolean {
  if (need.kind === 'sow' || itemKind(id) !== need.kind) return false;
  if (items.length) return items.includes(id);
  if (need.kind === 'dish') {
    const r = rarityOf(c, id);
    return r > 0 && (need.rarity === undefined || r === need.rarity);
  }
  return need.rarity === undefined || rarityOf(c, id) === need.rarity;
}

/** §9.13.2 floor price: ⌊sell price × 0.8⌋ for crops and fish, the buyback for dishes, the material price. */
export function floorPrice(c: P0Content, id: string): number {
  const kind = itemKind(id);
  if (kind === 'crop') return Math.floor((cropById(c, id)?.price ?? 0) * c.requests.floor_rate + 1e-9);
  if (kind === 'fish') return Math.floor((fishById(c, id)?.price ?? 0) * c.requests.floor_rate + 1e-9);
  if (kind === 'dish') return dishBuyback(c, id) ?? 0;
  return c.materials[id]?.price ?? 0;
}

/**
 * Bag units to hand in for one id list / need: plain stacks only, cheapest first (dishes: lowest quality first).
 * Returns [id, qty][] or null when the bag can't cover it.
 */
export function pick(c: P0Content, s: P0State, need: Pick<Need, 'kind' | 'rarity'>, items: string[], qty: number): [string, number][] | null {
  const have = new Map<string, number>();
  for (const b of s.bag) if (!b.gift && matches(c, need, items, b.id)) have.set(b.id, (have.get(b.id) ?? 0) + b.qty);
  const order = [...have.keys()].sort((a, b) => dishParts(a).quality - dishParts(b).quality || floorPrice(c, a) - floorPrice(c, b) || a.localeCompare(b));
  const out: [string, number][] = [];
  let left = qty;
  for (const id of order) {
    if (left === 0) break;
    const n = Math.min(left, have.get(id)!);
    out.push([id, n]);
    left -= n;
  }
  return left === 0 ? out : null;
}

export function haveFor(c: P0Content, s: P0State, need: Pick<Need, 'kind' | 'rarity'>, items: string[]): number {
  return s.bag.filter(b => !b.gift && matches(c, need, items, b.id)).reduce((n, b) => n + b.qty, 0);
}

/** Completion bonus actually paid today: request bonuses share a 100-coin daily cap (§9.13.2). */
export function payBonus(c: P0Content, s: P0State, bonus: number): number {
  const paid = Math.max(0, Math.min(bonus, c.quotas.request_bonus.cap - s.day.bonus));
  s.day.bonus += paid;
  return paid;
}

/** Remember the last few completed ids so a repeated deliver says request_done rather than bad_request. */
export function noteDone(s: P0State, id: string): void {
  s.req_done = [...s.req_done.filter(x => x !== id), id].slice(-20);
}
