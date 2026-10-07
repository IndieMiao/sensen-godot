/** Farm storage (§10.4.8): no slot limit; upgrades, facilities and seasoning take from it first, then from the bag. */
import { count, take } from './bag.js';
import type { P0State } from './state.js';

export function stored(s: P0State, id: string): number { return s.storage[id] ?? 0; }

/** What the player holds for a cost: storage plus plain bag stacks. */
export function haveTotal(s: P0State, id: string): number { return stored(s, id) + count(s.bag, id, 'skip'); }

export function putInStorage(s: P0State, id: string, qty: number): void {
  if (qty > 0) s.storage[id] = stored(s, id) + qty;
}

/** Take qty (caller checked haveTotal) from storage first, the rest from the bag. */
export function takeStorageFirst(s: P0State, id: string, qty: number): { storage: number; bag: number } {
  const fromStorage = Math.min(qty, stored(s, id));
  if (fromStorage > 0) {
    s.storage[id] = stored(s, id) - fromStorage;
    if (s.storage[id] === 0) delete s.storage[id];
  }
  const fromBag = qty - fromStorage;
  if (fromBag > 0) take(s.bag, id, fromBag, 'skip');
  return { storage: fromStorage, bag: fromBag };
}

/** First missing item of a cost list, or null when everything is there. */
export function missing(s: P0State, cost: [string, number][]): { item: string; need: number; have: number } | null {
  for (const [item, need] of cost) {
    const have = haveTotal(s, item);
    if (have < need) return { item, need, have };
  }
  return null;
}
