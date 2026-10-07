/**
 * Inbox parcels (§10.4.8, q(45)): passive rewards that do not fit the bag wait here, 8 at most, each kept 24 h.
 * With 8 waiting, new rewards queue instead of being dropped, pushing a parcel out or turning into coins; a queued
 * reward enters in order when a place frees up, and its 24 h starts then. Expired sellable items pay ⌊floor × 0.8⌋,
 * others are gone, and gifts go back to their sender.
 */
import { add, freeSlots, room, stackLimit } from './bag.js';
import { itemKind, sellPriceOf, type P0Content } from './content.js';
import type { P0Event } from './progress.js';
import { untilRollover } from './rules.js';
import type { BagStack, P0State, Parcel, ParcelUpdate } from './state.js';

export const PARCEL_LIMIT = 8;
export const PARCEL_LIFETIME_MS = 24 * 3_600_000;
const UPDATES_KEPT = 100;

/** Coins for an expired parcel: the Homestead Stall's floor price for the whole parcel × 0.8, rounded down. Gifts pay nothing. */
export function expiryCoins(c: P0Content, p: BagStack): number {
  if (p.gift) return 0;
  const base = sellPriceOf(c, p.id), rule = c.shops.homestead.buys[itemKind(p.id)];
  if (base === null || base <= 0 || !rule) return 0;
  const unit = Math.max(1, Math.floor(base * rule.rate + 1e-9));
  return Math.floor(unit * p.qty * 0.8);
}

function record(s: P0State, p: Parcel | Omit<Parcel, 'expires_at'>, at: number, status: ParcelUpdate['status'], coins = 0): void {
  s.inbox.updates.push({ key: p.key, id: p.id, qty: p.qty, ...(p.gift ? { gift: p.gift } : {}), source: p.source, at, status, coins,
    read: status === 'claimed' });
  s.inbox.updates = s.inbox.updates.slice(-UPDATES_KEPT);
}

/** A resident's gift meal is gone at the player-day rollover (§3.4.5), even as a parcel. */
function lifetimeEnd(c: P0Content, p: Omit<Parcel, 'expires_at'>, now: number): number {
  return p.gift ? Math.min(now + PARCEL_LIFETIME_MS, now + untilRollover(c, now)) : now + PARCEL_LIFETIME_MS;
}

/**
 * Pay out expired parcels and admit queued ones. Runs before every read and command (store, view, reducer), so a
 * refused command still persists what expired. Returns whether anything changed.
 */
export function settleParcels(c: P0Content, s: P0State, now: number): boolean {
  let changed = false;
  s.inbox.parcels = s.inbox.parcels.filter(p => {
    if (now < p.expires_at) return true;
    const coins = expiryCoins(c, p);
    s.coins += coins;
    record(s, p, p.expires_at, p.gift ? 'returned' : 'expired', coins);   // an unclaimed gift goes back to its sender
    changed = true;
    return false;
  });
  while (s.inbox.parcels.length < PARCEL_LIMIT && s.inbox.waiting.length > 0) {
    const p = s.inbox.waiting.shift()!;
    changed = true;
    if (p.gift && untilRollover(c, p.created_at) <= now - p.created_at) { record(s, p, now, 'returned'); continue; }
    s.inbox.parcels.push({ ...p, expires_at: lifetimeEnd(c, p, now) });
  }
  return changed;
}

/**
 * Give a passive reward once per source key (a skill level, an achievement, a request reward): what fits goes into the
 * bag, the rest becomes parcels of at most one stack each, each with a `parcel` event. Recipe cards (`recipe:<page>`)
 * open the Cookbook page. Returns how many of each item went into the bag (callers say that their own way), or null
 * when the key was granted before.
 */
export function grantItems(c: P0Content, s: P0State, now: number, key: string, source: string,
  items: [string, number][], events: P0Event[], gift?: BagStack['gift']): Record<string, number> | null {
  if (s.inbox.granted.includes(key)) return null;
  const bagged: Record<string, number> = {};
  settleParcels(c, s, now);
  s.inbox.granted.push(key);
  let index = 0;
  for (const [id, qty] of items) {
    if (id.startsWith('recipe:')) {
      const page = id.slice(7);
      if (!s.cookbook.includes(page)) s.cookbook.push(page);
      continue;
    }
    // A gift stack never merges with others, so it needs an empty slot of its own.
    const put = Math.min(qty, gift ? (freeSlots(s) > 0 ? stackLimit(c, id) : 0) : room(c, s, id));
    if (put > 0) { add(c, s, id, put, gift); bagged[id] = (bagged[id] ?? 0) + put; }
    for (let left = qty - put; left > 0;) {
      const amount = Math.min(left, stackLimit(c, id));
      const p = { key: `${key}:${index++}`, id, qty: amount, ...(gift ? { gift: { ...gift } } : {}), source, created_at: now };
      const waiting = s.inbox.parcels.length >= PARCEL_LIMIT;
      const end = lifetimeEnd(c, p, now);
      if (waiting) s.inbox.waiting.push(p);
      else s.inbox.parcels.push({ ...p, expires_at: end });
      // expires_in: a gift meal's parcel is gone at 04:00, so its float must not promise 24 h.
      events.push({ kind: 'parcel', id, qty: amount, key: p.key, waiting, ...(waiting ? {} : { expires_in: end - now }), ...(gift ? { gift: true } : {}) });
      left -= amount;
    }
  }
  return bagged;
}

/** Claim one parcel into one empty bag slot, even when a partial stack of the same item exists (§10.4.8). */
export function claimParcel(c: P0Content, s: P0State, now: number, key: string, events: P0Event[]): { code: string; detail?: Record<string, unknown> } | null {
  const p = s.inbox.parcels.find(item => item.key === key);
  if (!p) {
    const prior = s.inbox.updates.find(u => u.key === key);
    return prior?.status === 'claimed' ? null : { code: prior ? 'parcel_expired' : 'bad_parcel' };
  }
  if (freeSlots(s) === 0) return { code: 'bag_full', detail: { slots: 1 } };
  s.bag.push(p.gift ? { id: p.id, qty: p.qty, gift: { ...p.gift } } : { id: p.id, qty: p.qty });
  s.inbox.parcels = s.inbox.parcels.filter(item => item.key !== key);
  record(s, p, now, 'claimed');
  events.push({ kind: 'item', id: p.id, delta: p.qty });
  settleParcels(c, s, now);
  return null;
}

export function inboxView(s: P0State, now: number) {
  const free = freeSlots(s);
  return {
    limit: PARCEL_LIMIT,
    // Queued rewards show only as a count on the Parcels rule line, never on the bell (q(45) detail, PARCEL-4).
    badge: s.inbox.parcels.length + s.inbox.updates.filter(u => !u.read).length,
    waiting: s.inbox.waiting.length,
    claim_slots: Math.min(free, s.inbox.parcels.length),
    parcels: [...s.inbox.parcels].sort((a, b) => a.expires_at - b.expires_at)
      .map(p => ({ ...p, left: Math.max(0, p.expires_at - now), can_claim: free > 0 })),
    updates: [...s.inbox.updates].reverse(),
  };
}
