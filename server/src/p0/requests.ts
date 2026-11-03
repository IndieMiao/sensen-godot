/**
 * Shared by the request boards and residents (plan §9.6.2, §9.13.2): what counts as a match, which bag items are
 * handed in, and what it pays. Requests never pay XP; gift meals and bought goods are never handed in.
 */
import { cropById, dishBuyback, dishParts, fishById, itemKind, recipeById, type Need, type P0Content } from './content.js';
import { recipeRarity } from './cooking.js';
import type { P0State } from './state.js';
import { take } from './bag.js';
import { takeStorageFirst } from './storage.js';

/** Rarity of a bag id for a request: fish by species, crops by their ingredient rarity (§7.3.2), dishes by recipe (0 = Mystery Dish / unknown). */
export function rarityOf(c: P0Content, id: string): number {
  if (itemKind(id) === 'fish') return fishById(c, id)?.rarity ?? 0;
  if (itemKind(id) === 'crop') return cropById(c, id)?.ingr[1] ?? 0;
  if (itemKind(id) === 'dish') {
    const recipe = recipeById(c, dishParts(id).base);
    return recipe ? recipeRarity(c, recipe) : 0;
  }
  return 0;
}

/** Does one bag id satisfy a need? items narrows to fixed ids chosen when the request was drawn. */
export function matches(c: P0Content, need: Pick<Need, 'kind' | 'rarity' | 'style' | 'family'>, items: string[], id: string): boolean {
  if (c.fast_crops?.some(x => x.id === id)) return false;   // q(245): even an unrestricted crop need or explicit id
  if (need.kind === 'sow' || need.kind === 'harvest' || itemKind(id) !== need.kind) return false;
  if (items.length) return items.includes(id);
  if (need.kind === 'dish') {
    const r = rarityOf(c, id);
    const styles = need.style === undefined ? null : Array.isArray(need.style) ? need.style : [need.style];
    if (styles && !styles.includes(recipeById(c, dishParts(id).base)?.style ?? '')) return false;
    return r > 0 && (need.rarity === undefined || r === need.rarity);
  }
  if (need.kind === 'crop' && need.family !== undefined && cropById(c, id)?.ingr[0] !== need.family) return false;
  return need.rarity === undefined || rarityOf(c, id) === need.rarity;
}

/** §9.13.2 floor price: ⌊sell price × 0.8⌋ for crops and fish, the buyback for dishes, the material price. */
export function floorPrice(c: P0Content, id: string): number {
  const kind = itemKind(id);
  if (kind === 'crop') return Math.floor((cropById(c, id)?.price ?? 0) * c.requests.floor_rate + 1e-9);
  if (kind === 'fish') return Math.floor((fishById(c, id)?.price ?? 0) * c.requests.floor_rate + 1e-9);
  if (kind === 'dish') return dishBuyback(c, id) ?? 0;
  // A material with no buyback (price null) is paid at its shadow price (floor: Quartz 5, Hardwood 4; §8.4.1).
  return c.materials[id]?.floor ?? c.materials[id]?.price ?? 0;
}

/**
 * Units to hand in for one id list / need: plain bag stacks (materials also Farm Storage), cheapest first (dishes: lowest quality first).
 * Returns [id, qty][] or null when the bag can't cover it.
 */
export function pick(c: P0Content, s: P0State, need: Pick<Need, 'kind' | 'rarity' | 'style' | 'family'>, items: string[], qty: number): [string, number][] | null {
  const have = new Map<string, number>();
  for (const b of s.bag) if (!b.gift && matches(c, need, items, b.id)) have.set(b.id, (have.get(b.id) ?? 0) + b.qty);
  if (need.kind === 'material') for (const [id, n] of Object.entries(s.storage)) if (matches(c, need, items, id)) have.set(id, (have.get(id) ?? 0) + n);
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

export function haveFor(c: P0Content, s: P0State, need: Pick<Need, 'kind' | 'rarity' | 'style' | 'family'>, items: string[]): number {
  const bag = s.bag.filter(b => !b.gift && matches(c, need, items, b.id)).reduce((n, b) => n + b.qty, 0);
  if (need.kind !== 'material') return bag;
  return bag + Object.entries(s.storage).filter(([id]) => matches(c, need, items, id)).reduce((n, [, q]) => n + q, 0);
}

/**
 * Take a hand-in part: materials come from Farm Storage first, like upgrades (gathered Timber goes straight to storage,
 * SGODOT-231); everything else from plain bag stacks.
 */
export function handOver(c: P0Content, s: P0State, id: string, qty: number): void {
  if (itemKind(id) === 'material' && c.materials[id]) takeStorageFirst(s, id, qty);
  else take(s.bag, id, qty, 'skip');
}

/** The daily cap on completion bonuses (§9.13.2): by the Homestead level where the content gives one (q(272) ⑩), else cap. */
export function bonusCap(c: P0Content, s: Pick<P0State, 'homestead'>): number {
  const q = c.quotas.request_bonus;
  let cap = q.cap;
  for (const [from, n] of q.by_homestead ?? []) if (s.homestead.level >= from) cap = n;
  return cap;
}

/** Completion bonus actually paid today: request bonuses share a daily cap (§9.13.2, bonusCap). */
export function payBonus(c: P0Content, s: P0State, bonus: number): number {
  const paid = Math.max(0, Math.min(bonus, bonusCap(c, s) - s.day.bonus));
  s.day.bonus += paid;
  return paid;
}

/** Remember the last few completed ids so a repeated deliver says request_done rather than bad_request. */
export function noteDone(s: P0State, id: string): void {
  s.req_done = [...s.req_done.filter(x => x !== id), id].slice(-20);
}
