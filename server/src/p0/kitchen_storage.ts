/** Where the stove draws ingredients from and where finished dishes go (plan §7.2.6, §7.7; SGODOT-226).
 * cooking.ts reads and writes only through these functions, so the Spice Rack (Homestead Lv2) and the
 * Warming Cabinet (Lv3) live here without touching the recipe code.
 * Ingredients: the bag; from Lv2 the Spice Rack also reaches the seasonings (Rock Salt, Wild Herb) in farm
 * storage, storage first. The rack is no separate stock (Li Bai, q(46)): the Lv2 upgrade puts the bag's
 * seasonings into storage (Zhou Yu's storeMaterials, PR #17), and Experiment shows the stored count with a Rack badge.
 * Dishes: the Warming Cabinet first (6 portions from Lv3), then the bag; when neither has room the dish
 * stays on the stove (collect refuses bag_full). Residents' gift meals never come here (q(20)). */
import type { P0Content } from './content.js';
import { add, count, room, take } from './bag.js';
import { unlocked } from './homestead.js';
import type { P0Event } from './progress.js';
import type { Refusal } from './fishing.js';
import type { P0State } from './state.js';

/** A seasoning the Spice Rack holds: a material with a cooking family (Rock Salt, Wild Herb; q(40)). Same rule as
 * gathering.isSeasoning in PR #17; keep one copy once it lands. */
export function isSeasoning(c: P0Content, id: string): boolean {
  return !!c.materials[id]?.ingr;
}

export function rackOn(c: P0Content, s: P0State): boolean { return unlocked(c, s, 'spice_rack'); }

/** What the rack shows: stored seasonings, the real count (no 30 cap, q(46)). */
export function rackStock(c: P0Content, s: P0State): Map<string, number> {
  const out = new Map<string, number>();
  if (!rackOn(c, s)) return out;
  for (const [id, qty] of Object.entries(s.storage)) if (qty > 0 && isSeasoning(c, id)) out.set(id, qty);
  return out;
}

/** How many of id the stove can use right now. */
export function haveIngredient(c: P0Content, s: P0State, id: string): number {
  return count(s.bag, id) + (rackStock(c, s).get(id) ?? 0);
}

/** Every item the stove can draw from, with its count (Cookbook auto-pick and Experiment's grid). */
export function ingredientStock(c: P0Content, s: P0State): Map<string, number> {
  const left = new Map<string, number>();
  for (const b of s.bag) left.set(b.id, (left.get(b.id) ?? 0) + b.qty);
  for (const [id, qty] of rackStock(c, s)) left.set(id, (left.get(id) ?? 0) + qty);
  return left;
}

/** Take qty of id (the caller checked haveIngredient): the rack (farm storage) first, then the bag.
 * Only the bag part is an item event; the rack is read from the view. */
export function takeIngredient(c: P0Content, s: P0State, id: string, qty: number, events: P0Event[]): void {
  const fromRack = Math.min(qty, rackStock(c, s).get(id) ?? 0);
  if (fromRack > 0) {
    s.storage[id] -= fromRack;
    if (s.storage[id] === 0) delete s.storage[id];
  }
  const fromBag = qty - fromRack;
  if (fromBag > 0) {
    take(s.bag, id, fromBag);
    events.push({ kind: 'item', id, delta: -fromBag });
  }
}

/** Warming Cabinet portions once unlocked, else 0. */
export function cabinetCap(c: P0Content, s: P0State): number {
  return unlocked(c, s, 'warming_cabinet') ? c.homestead.warming_cabinet : 0;
}

export function cabinetCount(s: P0State, id?: string): number {
  return s.cabinet.filter(b => id === undefined || b.id === id).reduce((n, b) => n + b.qty, 0);
}

function cabinetFree(c: P0Content, s: P0State): number {
  return Math.max(0, cabinetCap(c, s) - cabinetCount(s));
}

/** Whether all these portions find a place (checked before the pot is emptied; a Perfect pot makes two ids). */
export function dishesFit(c: P0Content, s: P0State, dishes: [string, number][]): boolean {
  let free = cabinetFree(c, s);
  const probe = { bag: s.bag.map(b => ({ ...b })), bag_cap: s.bag_cap };
  for (const [id, n] of dishes) {
    const kept = Math.min(n, free);
    free -= kept;
    const rest = n - kept;
    if (rest === 0) continue;
    if (room(c, probe, id) < rest) return false;
    add(c, probe, id, rest);
  }
  return true;
}

/** Put qty of a finished dish away, cabinet first (dishesFit was checked). */
export function routeDish(c: P0Content, s: P0State, id: string, qty: number, events: P0Event[]): void {
  const cap = cabinetCap(c, s);
  const kept = Math.min(qty, cabinetFree(c, s));
  if (kept > 0) {
    const stack = s.cabinet.find(b => b.id === id);
    if (stack) stack.qty += kept;
    else s.cabinet.push({ id, qty: kept });
  }
  const rest = qty - kept;
  if (rest > 0) {
    add(c, s, id, rest);
    events.push({ kind: 'item', id, delta: rest });
  }
  if (cap > 0) events.push({ kind: 'cabinet', id, delta: kept, to_bag: rest, have: cabinetCount(s), cap });
}

export type DishSource = 'bag' | 'cabinet';

/** Portions of a dish the player can eat from that place (bag stacks include today's gift meal). */
export function haveDish(_c: P0Content, s: P0State, id: string, from: DishSource): number {
  return from === 'cabinet' ? cabinetCount(s, id) : count(s.bag, id);
}

/** Remove one eaten portion (the caller checked haveDish). */
export function eatFrom(c: P0Content, s: P0State, id: string, from: DishSource, events: P0Event[]): void {
  if (from === 'bag') {
    take(s.bag, id, 1);
    events.push({ kind: 'item', id, delta: -1 });
    return;
  }
  cabinetRemove(s, id, 1);
  events.push({ kind: 'cabinet', id, delta: -1, to_bag: 0, have: cabinetCount(s), cap: cabinetCap(c, s) });
}

/** Take one: a portion from the cabinet into the bag (Appendix B.7 `Take one` / `Bag full`). */
export function takeFromCabinet(c: P0Content, s: P0State, cmd: { item?: unknown }, events: P0Event[]): Refusal | null {
  const id = String(cmd.item ?? '');
  if (cabinetCap(c, s) === 0) return { code: 'locked', detail: { unlock: 'warming_cabinet' } };
  if (cabinetCount(s, id) < 1) return { code: 'not_enough', detail: { item: id, have: 0 } };
  if (room(c, s, id) < 1) return { code: 'bag_full' };
  cabinetRemove(s, id, 1);
  add(c, s, id, 1);
  events.push({ kind: 'item', id, delta: 1 });
  events.push({ kind: 'cabinet', id, delta: -1, to_bag: 1, have: cabinetCount(s), cap: cabinetCap(c, s) });
  return null;
}

function cabinetRemove(s: P0State, id: string, qty: number): void {
  const stack = s.cabinet.find(b => b.id === id);
  if (!stack) return;
  stack.qty -= qty;
  if (stack.qty <= 0) s.cabinet.splice(s.cabinet.indexOf(stack), 1);
}
