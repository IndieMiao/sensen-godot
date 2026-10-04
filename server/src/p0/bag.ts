/** Bag (25 slots, stacking by kind, §10.3.3). One BagStack per occupied slot. */
import { itemKind, type P0Content } from './content.js';
import type { BagStack } from './state.js';

export function count(bag: BagStack[], id: string): number { return bag.filter(b => b.id === id).reduce((n, b) => n + b.qty, 0); }
function stackLimit(c: P0Content, id: string): number { return c.bag.stack[itemKind(id)] ?? 99; }
export function freeSlots(c: P0Content, bag: BagStack[]): number { return Math.max(0, c.bag.capacity - bag.length); }
export function room(c: P0Content, bag: BagStack[], id: string): number {
  const limit = stackLimit(c, id);
  const partial = bag.filter(b => b.id === id).reduce((n, b) => n + (limit - b.qty), 0);
  return partial + freeSlots(c, bag) * limit;
}
export function add(c: P0Content, bag: BagStack[], id: string, qty: number): void {
  const limit = stackLimit(c, id);
  for (const b of bag) if (b.id === id && qty > 0) { const put = Math.min(qty, limit - b.qty); b.qty += put; qty -= put; }
  while (qty > 0 && bag.length < c.bag.capacity) { const put = Math.min(qty, limit); bag.push({ id, qty: put }); qty -= put; }
}
export function take(bag: BagStack[], id: string, qty: number): void {
  // Take from the smallest stack first (§10.3.3 "从最少的堆扣起").
  const stacks = bag.filter(b => b.id === id).sort((a, b) => a.qty - b.qty);
  for (const b of stacks) { const put = Math.min(qty, b.qty); b.qty -= put; qty -= put; if (qty === 0) break; }
  for (let i = bag.length - 1; i >= 0; i--) if (bag[i].qty <= 0) bag.splice(i, 1);
}
