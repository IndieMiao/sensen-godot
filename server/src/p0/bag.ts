/** Bag (25 slots, 30 after Bag Upgrade I; stacking by kind, §10.3.3 / §10.4.3). One BagStack per occupied slot. */
import { itemKind, type P0Content } from './content.js';
import type { BagStack } from './state.js';

/** Anything with a bag and its current capacity (the player state). */
export interface BagHolder { bag: BagStack[]; bag_cap: number }

/** Which stacks an operation may use: a resident's gift meal can be eaten and given to a resident, never sold or handed in. */
export type GiftUse = 'any' | 'skip';

const usable = (b: BagStack, gifts: GiftUse) => gifts === 'any' || !b.gift;

export function count(bag: BagStack[], id: string, gifts: GiftUse = 'any'): number {
  return bag.filter(b => b.id === id && usable(b, gifts)).reduce((n, b) => n + b.qty, 0);
}
function stackLimit(c: P0Content, id: string): number { return c.bag.stack[itemKind(id)] ?? 99; }
export function freeSlots(s: BagHolder): number { return Math.max(0, s.bag_cap - s.bag.length); }

/** How many more of id fit: partial plain stacks plus empty slots (gift stacks never take more). */
export function room(c: P0Content, s: BagHolder, id: string): number {
  const limit = stackLimit(c, id);
  const partial = s.bag.filter(b => b.id === id && !b.gift).reduce((n, b) => n + (limit - b.qty), 0);
  return partial + freeSlots(s) * limit;
}

export function add(c: P0Content, s: BagHolder, id: string, qty: number, gift?: BagStack['gift']): void {
  const limit = stackLimit(c, id);
  const same = (b: BagStack) => b.id === id && (gift ? b.gift?.from === gift.from && b.gift.day === gift.day : !b.gift);
  for (const b of s.bag) if (same(b) && qty > 0) { const put = Math.min(qty, limit - b.qty); b.qty += put; qty -= put; }
  while (qty > 0 && s.bag.length < s.bag_cap) {
    const put = Math.min(qty, limit);
    s.bag.push(gift ? { id, qty: put, gift: { ...gift } } : { id, qty: put });
    qty -= put;
  }
}

/** Take from the smallest stack first (§10.3.3 "从最少的堆扣起"); when gifts may be used, the expiring gift meal goes first. */
export function take(bag: BagStack[], id: string, qty: number, gifts: GiftUse = 'any'): void {
  const stacks = bag.filter(b => b.id === id && usable(b, gifts))
    .sort((a, b) => Number(!a.gift) - Number(!b.gift) || a.qty - b.qty);
  for (const b of stacks) { const put = Math.min(qty, b.qty); b.qty -= put; qty -= put; if (qty === 0) break; }
  for (let i = bag.length - 1; i >= 0; i--) if (bag[i].qty <= 0) bag.splice(i, 1);
}
