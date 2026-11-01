/**
 * q(134): every taken request says its progress when what it takes comes into the bag — the Stall Board's and the
 * Market Board's tracked requests and the residents' taken ones (check-ins excepted: their toast says them). Each reply
 * compares what each one counted before the command with what it counts after, whatever brought it (a harvest, a
 * catch, a trap, a pot, a gather, the mine, a purchase, a parcel): a count that grew sends one event; a count that fell
 * (sold, eaten) sends none. A basket (Market Basket) counts each of its items and says the one that grew; the one that
 * fills the request (every item of a basket) says `done` instead, for the client's Success toast.
 */
import type { P0Content } from './content.js';
import { boardsOf, haveForRequest } from './boards.js';
import type { P0Event } from './progress.js';
import { haveFor } from './requests.js';
import { progressOf, residentDef, residentRequest } from './residents.js';
import type { P0State } from './state.js';

/** One taken request's count: `have` (the least of a basket's items), each item's for a basket, all capped at qty. */
export interface TakenCount { qty: number; have: number; items?: Record<string, number> }

/** What each taken request counts now, by request id. */
export function takenCounts(c: P0Content, s: P0State): Map<string, TakenCount> {
  const out = new Map<string, TakenCount>();
  for (const { slots } of boardsOf(c, s)) for (const sl of slots) {
    const r = sl.req;
    if (r?.status !== 'accepted' || r.kind === 'visit') continue;
    if (r.items.length > 1) {   // Market Basket: N of each
      const items: Record<string, number> = {};
      for (const item of r.items) items[item] = Math.min(r.qty, haveFor(c, s, { kind: r.kind }, [item]));
      out.set(r.id, { qty: r.qty, have: Math.min(...Object.values(items)), items });
    } else out.set(r.id, { qty: r.qty, have: Math.min(r.qty, haveForRequest(c, s, r)) });
  }
  for (const [id, rs] of Object.entries(s.residents ?? {})) {
    const q = rs.req ? residentRequest(residentDef(c, id), rs.req.id) : undefined;
    if (q) out.set(q.id, { qty: q.qty, have: Math.min(q.qty, progressOf(c, s, id, q)) });
  }
  return out;
}

/**
 * The reply's progress events against the counts before the command: a request already full before, taken or handed in
 * by this command, says nothing.
 */
export function noteProgress(c: P0Content, s: P0State, before: Map<string, TakenCount>, events: P0Event[]): void {
  for (const [id, now] of takenCounts(c, s)) {
    const was = before.get(id);
    if (!was || was.have >= now.qty) continue;
    if (now.have >= now.qty) { events.push({ kind: 'request_progress', id, have: now.qty, qty: now.qty, done: true }); continue; }
    if (now.items) {
      for (const [item, n] of Object.entries(now.items)) {
        if (n > (was.items?.[item] ?? 0)) events.push({ kind: 'request_progress', id, item, have: n, qty: now.qty });
      }
    } else if (now.have > was.have) events.push({ kind: 'request_progress', id, have: now.have, qty: now.qty });
  }
}
