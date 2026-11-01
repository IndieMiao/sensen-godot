/** q(270) (SGODOT-378, cross-city plan H step 1): one Market Board per city cluster — made when the player is in that
 * city, drawn from that city, taken and handed in there, dropped from anywhere; the old single board is the home
 * city's; other cities' tracked requests show where they go (boards.elsewhere, a ✓ on that city's market). */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type BoardRequest, type P0State } from '../../src/p0/state.js';
import { boardsOf, eligible, handIn, settleBoards, tracked } from '../../src/p0/boards.js';
import { mapMarkers } from '../../src/p0/markers.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const SF = 'gn-5391959', HAYWARD = 'gn-5355933', HAYWARD_MARKET = `${HAYWARD}~market0`;
const T = Date.parse('2026-10-10T18:00:00Z');   // 11:00 in San Francisco
const H = 3_600_000;

/** A Homestead Lv3 player with every skill up, so most templates are open; `at` the city they stand in. */
function player(at = SF): P0State {
  const s = freshState(c, 'q270-player', T - 10 * 24 * H, 7);
  s.homestead.level = 3;
  s.skills = { farming: 5000, fishing: 5000, cooking: 5000 };
  s.coins = 5000;
  s.boards.stall = [{ req: null, refill_at: T - 9 * 24 * H }];   // Pond Catch done: past the first session's tracked-only map
  if (at !== SF) {
    s.travel.here = at;
    s.travel.visits[at] = { n: 1, first_at: T - H, last_at: T - H, deliveries: 0, delivered_day: '' };
    s.travel.passes[at] = { kind: 'day', from: T - H, until: T + 23 * H } as never;
  }
  return s;
}
const step = (s: P0State, cmd: P0Command, at = T) => {
  const r = applyP0(c, s, cmd, at);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return r.state;
};
const atMarket = (place: string) => ({ space: 'outpost', place });
const hayward = (s: P0State) => s.markets[HAYWARD] ?? [];
/** Fill the bag for a drawn request so it can be handed in. */
function fill(s: P0State, r: BoardRequest): void {
  for (const id of r.items.length ? r.items : []) s.bag.push({ id, qty: r.qty });
}

describe('q(270) Market Board per city', () => {
  it('a v5 save: its one board becomes the home city\'s, the same array under `market`, requests and times kept', () => {
    const s = player() as P0State & { v: number };
    settleBoards(c, s, T);
    const held = structuredClone(s.boards.market);
    const v5 = JSON.parse(JSON.stringify(s)) as Omit<P0State, 'v'> & { v: number };
    v5.v = 5;
    delete (v5 as { markets?: unknown }).markets;
    const up = upgradeState(c, v5 as unknown as P0State, T);
    expect(up.v).toBe(6);
    expect(Object.keys(up.markets)).toEqual([SF]);
    expect(up.markets[SF]).toBe(up.boards.market);
    expect(up.boards.market).toEqual(held);
  });

  it('a rollback to v5: every value of `boards` is still a board (v5\'s upgradeState walks them); back on v6, the board v5 played is home\'s and the other cities\' kept', () => {
    const s = player(HAYWARD);
    settleBoards(c, s, T);
    expect(Object.values(s.boards).every(Array.isArray)).toBe(true);
    const away = structuredClone(hayward(s));
    // a v5 server reads it, keeps the fields it does not know, plays its one board and writes v: 5
    const v5 = JSON.parse(JSON.stringify(s)) as P0State;
    (v5 as { v: number }).v = 5;
    v5.boards.market = [{ req: null, refill_at: T + 3 * H }];
    const up = upgradeState(c, v5, T + H);
    expect(up.boards.market).toEqual([{ req: null, refill_at: T + 3 * H }]);
    expect(up.markets[SF]).toBe(up.boards.market);
    expect(up.markets[HAYWARD]).toEqual(away);
  });

  it('a rollback with a home change meanwhile: the old home\'s copy loses the requests the board took along', () => {
    const s = player();
    settleBoards(c, s, T);
    const taken = s.boards.market.find(sl => sl.req)!.req!;
    const v5 = JSON.parse(JSON.stringify(s)) as P0State;
    (v5 as { v: number }).v = 5;
    // the v5 server moved home to Hayward; its one board went along
    Object.assign(v5.travel, { home: HAYWARD, here: HAYWARD, home_set: { pond: `${HAYWARD}~pond0` }, home_chosen_at: T });
    const up = upgradeState(c, v5, T + H);
    expect(up.markets[HAYWARD]).toBe(up.boards.market);
    expect(up.boards.market.some(sl => sl.req?.id === taken.id)).toBe(true);
    expect(up.markets[SF].some(sl => sl.req?.id === taken.id)).toBe(false);
    expect(up.markets[SF].find(sl => sl.req === null)).toEqual({ req: null, refill_at: T + H });
  });

  it('is made the first time the player is in the city, dated from the arrival: the view and the next command see the same requests', () => {
    const s = player(HAYWARD);
    expect(s.markets[HAYWARD]).toBeUndefined();
    const v = viewOf(c, s, T);
    expect(v.boards.market).toMatchObject({ cluster: HAYWARD, city: 'Hayward', home: false });
    const shown = (v.boards.market.slots as { id?: string }[]).map(x => x.id);
    expect(shown.every(id => id?.includes(`-${HAYWARD}-`))).toBe(true);
    const later = viewOf(c, s, T + 2 * H).boards.market.slots as { id?: string }[];
    expect(later.map(x => x.id)).toEqual(shown);   // the same draw, whenever it is read
    const s2 = step(s, { type: 'accept', request: shown[0]!, ...atMarket(HAYWARD_MARKET) } as P0Command);
    expect(hayward(s2)[0].req).toMatchObject({ id: shown[0], status: 'accepted' });
    expect(s2.boards.market).not.toBe(hayward(s2));   // home's board is its own
  });

  it('draws from its own city and never a home_only template; the home board still can', () => {
    const s = player(HAYWARD);
    const away = eligible(c, s, 'market', HAYWARD);
    const homeOnly = Object.entries(c.requests.templates).filter(([, t]) => t.home_only).map(([id]) => id);
    expect(homeOnly.length).toBe(6);
    expect(away.filter(id => homeOnly.includes(id))).toEqual([]);
    expect(eligible(c, s, 'market', SF).some(id => homeOnly.includes(id))).toBe(true);
  });

  it('is taken and handed in in its city only (the outpost the command comes from); dropped from anywhere, its board waiting 8 h', () => {
    let s = player(HAYWARD);
    settleBoards(c, s, T);
    const id = hayward(s)[0].req!.id;
    expect(applyP0(c, s, { type: 'accept', request: id, ...atMarket('sh_market_1') } as P0Command, T))
      .toMatchObject({ ok: false, code: 'wrong_city', detail: { city: HAYWARD } });
    s = step(s, { type: 'accept', request: id, ...atMarket(HAYWARD_MARKET) } as P0Command);
    fill(s, hayward(s)[0].req!);
    s.travel.here = SF;   // home again
    expect(applyP0(c, s, { type: 'deliver', request: id, space: 'home' } as P0Command, T)).toMatchObject({ ok: false, code: 'wrong_city' });
    expect(applyP0(c, s, { type: 'deliver', request: id } as P0Command, T)).toMatchObject({ ok: false, code: 'wrong_city' });
    const dropped = step(s, { type: 'drop', request: id, space: 'home' } as P0Command);
    expect(hayward(dropped)[0]).toEqual({ req: null, refill_at: T + 8 * H });
  });

  it('hands in at its city\'s market and refills there at once (q(268) B), counting today\'s 6 for the account', () => {
    let s = player(HAYWARD);
    settleBoards(c, s, T);
    const r = hayward(s).map(sl => sl.req!).find(x => x.kind !== 'visit' && x.items.length)!;
    s = step(s, { type: 'accept', request: r.id, ...atMarket(HAYWARD_MARKET) } as P0Command);
    fill(s, r);
    expect(handIn(c, s, hayward(s).find(sl => sl.req?.id === r.id)!.req!)).not.toBeNull();
    s = step(s, { type: 'deliver', request: r.id, ...atMarket(HAYWARD_MARKET) } as P0Command);
    expect(s.day.sys_done).toBe(1);
    expect(hayward(s).some(sl => sl.req?.id === r.id)).toBe(false);
    expect((viewOf(c, s, T).boards.market.slots as { empty?: boolean }[]).every(x => !x.empty)).toBe(true);   // refilled at once
  });

  it('home again: the board shown is home\'s; a request tracked in Hayward is in `elsewhere`, a ✓ on Hayward\'s market once it is ready — not after today\'s 6', () => {
    let s = player(HAYWARD);
    settleBoards(c, s, T);
    const r = hayward(s).map(sl => sl.req!).find(x => x.kind !== 'visit' && x.items.length)!;
    s = step(s, { type: 'accept', request: r.id, ...atMarket(HAYWARD_MARKET) } as P0Command);
    s.travel.here = SF;
    const v = viewOf(c, s, T);
    expect(v.boards.market).toMatchObject({ cluster: SF, home: true });
    expect(v.boards.elsewhere).toEqual([expect.objectContaining({ id: r.id, cluster: HAYWARD, city: 'Hayward', home: false, deliver_place: HAYWARD_MARKET })]);
    expect(mapMarkers(c, s, T).find(m => m.place === HAYWARD_MARKET)).toBeUndefined();   // not ready yet
    fill(s, r);
    expect(mapMarkers(c, s, T).find(m => m.place === HAYWARD_MARKET)).toMatchObject({ kind: 'deliver', why: { request: r.id, tracked: true } });
    s.day.sys_done = c.quotas.sys_requests.cap;
    expect(mapMarkers(c, s, T).find(m => m.place === HAYWARD_MARKET)).toBeUndefined();
  });

  it('another city\'s untaken requests show no ! while the player is elsewhere; the city they stand in shows them', () => {
    const s = player(HAYWARD);
    settleBoards(c, s, T);
    expect(mapMarkers(c, s, T).find(m => m.place === HAYWARD_MARKET)).toMatchObject({ kind: 'request' });
    s.travel.here = SF;
    expect(mapMarkers(c, s, T).find(m => m.place === HAYWARD_MARKET)).toBeUndefined();
  });

  it('Track ≤ 3 counts every city\'s boards together', () => {
    let s = player(HAYWARD);
    settleBoards(c, s, T);
    for (const sl of hayward(s)) s = step(s, { type: 'accept', request: sl.req!.id, ...atMarket(HAYWARD_MARKET) } as P0Command);
    s.travel.here = SF;
    settleBoards(c, s, T);
    const home = boardsOf(c, s).find(b => b.board === 'market' && b.city === SF)!.slots.map(sl => sl.req).filter(Boolean)[0]!;
    s = step(s, { type: 'accept', request: home.id, ...atMarket('sh_market_1') } as P0Command);
    expect(tracked(c, s)).toBe(3);
    const next = boardsOf(c, s).find(b => b.board === 'market' && b.city === SF)!.slots.map(sl => sl.req).find(x => x && x.status === 'open')!;
    expect(applyP0(c, s, { type: 'accept', request: next.id, ...atMarket('sh_market_1') } as P0Command, T)).toMatchObject({ ok: false, code: 'track_limit' });
  });
});
