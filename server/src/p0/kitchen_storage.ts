/** Where the stove draws ingredients from and where finished dishes go (plan §7.2.6, §7.7; SGODOT-226).
 * cooking.ts reads and writes only through these functions, so the Spice Rack (Homestead Lv2, seasonings
 * off the bag, 30 each) and the Warming Cabinet (Lv3, 6 portions) plug in here without touching the recipes.
 * Today: the bag only, exactly as before (no rack, no cabinet yet). Next: rack → farm storage → bag for
 * ingredients; cabinet → bag for dishes. */
import type { P0Content } from './content.js';
import { add, count, room, take } from './bag.js';
import type { P0Event } from './progress.js';
import type { P0State } from './state.js';

/** How many of id the stove can use right now. */
export function haveIngredient(_c: P0Content, s: P0State, id: string): number {
  return count(s.bag, id);
}

/** Every item the stove can draw from, with its count (Cookbook auto-pick and Experiment's grid). */
export function ingredientStock(_c: P0Content, s: P0State): Map<string, number> {
  const left = new Map<string, number>();
  for (const b of s.bag) left.set(b.id, (left.get(b.id) ?? 0) + b.qty);
  return left;
}

/** Take qty of id (the caller checked haveIngredient) and report where it came from. */
export function takeIngredient(_c: P0Content, s: P0State, id: string, qty: number, events: P0Event[]): void {
  take(s.bag, id, qty);
  events.push({ kind: 'item', id, delta: -qty });
}

/** Whether all these portions find a place (checked before the pot is emptied; a Perfect pot makes two ids). */
export function dishesFit(c: P0Content, s: P0State, dishes: [string, number][]): boolean {
  const need = new Map<string, number>();
  for (const [id, n] of dishes) need.set(id, (need.get(id) ?? 0) + n);
  // Separate ids each need a free slot of their own unless they stack onto an existing one: try them in turn.
  const probe = { bag: s.bag.map(b => ({ ...b })), bag_cap: s.bag_cap };
  for (const [id, n] of need) {
    if (room(c, probe, id) < n) return false;
    add(c, probe, id, n);
  }
  return true;
}

/** Put qty of a finished dish away and say where (dishesFit was checked). */
export function routeDish(c: P0Content, s: P0State, id: string, qty: number, events: P0Event[]): void {
  add(c, s, id, qty);
  events.push({ kind: 'item', id, delta: qty });
}
