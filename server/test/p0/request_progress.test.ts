/**
 * q(134): every taken request says its progress when what it takes comes into the bag — one event per grown count, the
 * one that fills it `done` — counted before and after each command on the server, whatever brought the items.
 */
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Result } from '../../src/p0/reducer.js';
import type { P0Event } from '../../src/p0/progress.js';
import { noteProgress, takenCounts } from '../../src/p0/request_progress.js';
import { freshState, type P0State } from '../../src/p0/state.js';

const c: P0Content = loadP0Content();
const T = Date.parse('2026-10-10T18:00:00Z');
const POND = 'pond_san_francisco_03';
const step = (s: P0State, cmd: P0Command, at = T): Extract<P0Result, { ok: true }> => {
  const r = applyP0(c, s, cmd, at);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return r;
};
const progress = (events: P0Event[]) => events.filter(e => e.kind === 'request_progress');
/** One fish landed at the beginner pond (the first three bites are Pond Crucian, §14.2.2). */
function land(s: P0State, at: number): Extract<P0Result, { ok: true }> {
  s = step(s, { type: 'cast', space: 'pond', place: POND }, at).state;
  s.cast!.breaks = null;
  return step(s, { type: 'reel', outcome: 'landed', space: 'pond', place: POND }, s.cast!.at + s.cast!.bite_ms + 1);
}

describe('request progress (q(134))', () => {
  it('a taken request says each fish it counts, and the one that fills it says done', () => {
    let s = freshState(c, 'progress-player', T, 7);
    const id = c.requests.tutorial.id, qty = s.boards.stall[0].req!.qty;
    expect(qty).toBe(2);
    s = step(s, { type: 'accept', request: id }).state;
    const one = land(s, T + 1000);
    expect(progress(one.events)).toEqual([{ kind: 'request_progress', id, have: 1, qty: 2 }]);
    const two = land(one.state, T + 120_000);
    expect(progress(two.events)).toEqual([{ kind: 'request_progress', id, have: 2, qty: 2, done: true }]);
    const three = land(two.state, T + 240_000);   // already full: nothing more
    expect(progress(three.events)).toEqual([]);
  });

  it('a request not taken says nothing; nor does taking it, handing it in or a count that falls', () => {
    let s = freshState(c, 'progress-open', T, 7);
    const id = c.requests.tutorial.id;
    const open = land(s, T + 1000);
    expect(progress(open.events)).toEqual([]);
    s = open.state;
    const taken = step(s, { type: 'accept', request: id }, T + 2000);   // it already holds one: taking it is no progress
    expect(progress(taken.events)).toEqual([]);
    s = taken.state;
    s.bag.push({ id: 'fish_crucian', qty: 1 });
    const sold = step(s, { type: 'sell', shop: 'homestead', item: 'fish_crucian', qty: 1 } as P0Command, T + 3000);
    expect(progress(sold.events)).toEqual([]);
    const both = land(sold.state, T + 120_000);
    expect(progress(both.events)).toEqual([{ kind: 'request_progress', id, have: 2, qty: 2, done: true }]);
    const handed = step(both.state, { type: 'deliver', request: id }, T + 130_000);
    expect(progress(handed.events)).toEqual([]);
  });

  it('a basket says the item that grew, each on its own, and done once every item is in', () => {
    const s = freshState(c, 'progress-basket', T, 7);
    s.boards.market = [{ req: { id: 'basket', template: 'req_sys_crop_mixed', items: ['crop_radish', 'crop_carrot'], kind: 'crop',
      qty: 3, bonus: 20, drawn_at: T, status: 'accepted' }, refill_at: 0 }];
    let before = takenCounts(c, s);
    s.bag.push({ id: 'crop_carrot', qty: 2 });
    let ev: P0Event[] = [];
    noteProgress(c, s, before, ev);
    expect(ev).toEqual([{ kind: 'request_progress', id: 'basket', item: 'crop_carrot', have: 2, qty: 3 }]);
    before = takenCounts(c, s);
    s.bag.push({ id: 'crop_radish', qty: 3 }, { id: 'crop_carrot', qty: 5 });   // both grow: a line each
    ev = [];
    noteProgress(c, s, before, ev);
    expect(ev).toEqual([{ kind: 'request_progress', id: 'basket', have: 3, qty: 3, done: true }]);
    // two baskets' worth of one item but none of the other: that item's count stops at qty
    const half = freshState(c, 'progress-basket-2', T, 7);
    half.boards.market = structuredClone(s.boards.market);
    const was = takenCounts(c, half);
    half.bag.push({ id: 'crop_radish', qty: 9 });
    ev = [];
    noteProgress(c, half, was, ev);
    expect(ev).toEqual([{ kind: 'request_progress', id: 'basket', item: 'crop_radish', have: 3, qty: 3 }]);
  });

  it('a resident\'s taken request counts the same way: a sow request by the plots it has had sown', () => {
    const [rid, def] = Object.entries(c.residents).find(([, d]) => d.requests.some(q => q.need.kind === 'sow'))!;
    const q = def.requests.find(x => x.need.kind === 'sow')!;
    const s = freshState(c, 'progress-resident', T, 7);
    s.residents[rid] = { affinity: 0, chat_day: '', gift_day: '', next: 0, req: { id: q.id, at: T, progress: 0 }, done_day: '' } as never;
    const before = takenCounts(c, s);
    expect(before.get(q.id)).toEqual({ qty: q.qty, have: 0 });
    s.residents[rid].req!.progress = 2;
    const ev: P0Event[] = [];
    noteProgress(c, s, before, ev);
    expect(ev).toEqual([{ kind: 'request_progress', id: q.id, have: Math.min(2, q.qty), qty: q.qty, ...(2 >= q.qty ? { done: true } : {}) }]);
  });

  it('check-ins are not counted (their toast says them)', () => {
    const s = freshState(c, 'progress-visit', T, 7);
    s.boards.market = [{ req: { id: 'stamp', template: 'req_sys_explore_outpost', items: [], kind: 'visit', qty: 1, bonus: 40,
      drawn_at: T, status: 'accepted', visit: { place: 'x', done: false } }, refill_at: 0 }];
    expect(takenCounts(c, s).has('stamp')).toBe(false);
  });
});
