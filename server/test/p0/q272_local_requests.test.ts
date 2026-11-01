/** q(272) (SGODOT-378, cross-city plan H step 2): local requests — away from home each city's keepers give the player
 * per_day a player day, drawn as that city's Market Board would; taken and handed in at the keeper's outpost, dropped
 * anywhere; the coins only, under the daily bonus cap and outside today's 6; a city left 30 days starts over. */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, type BoardRequest, type P0State } from '../../src/p0/state.js';
import { settleBoards, tracked } from '../../src/p0/boards.js';
import { givers, pruneCities, settleLocals } from '../../src/p0/locals.js';
import { mapMarkers } from '../../src/p0/markers.js';
import { bonusCap, payBonus } from '../../src/p0/requests.js';
import { skillLevel } from '../../src/p0/rules.js';
import { protectedQty } from '../../src/p0/shops.js';
import { viewOf } from '../../src/p0/view.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';
import { noteProgress, takenCounts } from '../../src/p0/request_progress.js';
import type { P0Event } from '../../src/p0/progress.js';

const c = loadP0Content();
const SF = 'gn-5391959', HAYWARD = 'gn-5355933', LOUDI = 'gn-1802238', SHANGHAI = 'gn-1796236', TOKYO = 'gn-1850147', NYC = 'gn-5128581';   // Loudi: an S-tier town, one Trading Post cabin
const T = Date.parse('2026-10-10T18:00:00Z');   // 11:00 in San Francisco
const H = 3_600_000, DAY = 24 * H;

/** A Homestead Lv3 player with every skill up, standing in `at` since an hour ago on a Day Pass. */
function player(at = HAYWARD, name = 'q272-player'): P0State {
  const s = freshState(c, name, T - 10 * DAY, 7);
  s.homestead.level = 3;
  s.skills = { farming: 5000, fishing: 5000, cooking: 5000 };
  s.coins = 5000;
  s.boards.stall = [{ req: null, refill_at: T - 9 * DAY }];
  if (at !== SF) {
    s.travel.here = at;
    s.travel.visits[at] = { n: 1, first_at: T - H, last_at: T - H, deliveries: 0, delivered_day: '' };
    s.travel.passes[at] = { kind: 'day', from: T - H, until: T + 23 * H } as never;
  }
  return s;
}
const run = (s: P0State, cmd: object, at = T) => applyP0(c, s, cmd as P0Command, at);
const step = (s: P0State, cmd: object, at = T) => {
  const r = run(s, cmd, at);
  if (!r.ok) throw new Error(`${(cmd as P0Command).type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return r.state;
};
const locals = (s: P0State, city = HAYWARD) => s.locals?.[city]?.slots ?? [];
const at = (place: string) => ({ space: 'outpost', place });
function fill(s: P0State, r: BoardRequest): void {
  if (r.items.length) for (const id of r.items) s.bag.push({ id, qty: r.qty });
  else if (r.kind === 'fish') s.bag.push({ id: r.rarity && r.rarity > 1 ? 'fish_golden_koi' : 'fish_crucian', qty: r.qty });
}
/** A drawn local request that names its one item (so the bag can be filled for it), with its keeper's outpost. */
const itemised = (s: P0State, city = HAYWARD) => locals(s, city).find(sl => sl.req.items.length === 1)!;
/** A player in Hayward whose day there drew such a request (the draw follows the player id). */
function itemisedPlayer(): P0State {
  for (let n = 0; n < 50; n++) {
    const s = player(HAYWARD, `q272-player-${n}`);
    settleLocals(c, s, T);
    if (itemised(s)) return s;
  }
  throw new Error('no itemised local request in 50 players');
}

describe('q(272) local requests', () => {
  it('the content: each role\'s templates exist, are on, and are neither explore nor home_only nor out of zone (q(272) ④)', () => {
    const roles = c.requests.local!.roles;
    expect(Object.keys(roles).sort()).toEqual(['market', 'post', 'tackle', 'tea']);
    const all = Object.values(roles).flat();
    expect(all).toHaveLength(20);
    // 奕星's numeric review: never the 0-Energy materials, whose hand-in skips the daily material buyback
    for (const id of ['req_sys_material_wood', 'req_sys_material_fiber', 'req_sys_material_clay']) expect(all).not.toContain(id);
    for (const id of all) {
      const t = c.requests.templates[id];
      expect(t, id).toBeDefined();
      expect(t.enabled, id).not.toBe(false);
      expect(t.home_only, id).toBeFalsy();
      expect(t.need.kind, id).not.toBe('visit');
      expect(t.need.regional, id).not.toBe('other_zone');
    }
  });

  it('away: per_day a day on different keepers, each of its role\'s kind, ids req_loc_; the view and the next command see the same', () => {
    const s = player();
    const v = viewOf(c, s, T);
    expect(v.locals).toHaveLength(c.requests.local!.per_day);
    const places = v.locals.map((r: { place: string }) => r.place);
    expect(new Set(places).size).toBe(places.length);
    const kinds: Record<string, string> = { tackle: 'fish', tea: 'dish', market: 'crop', post: 'material' };
    const roleOf = new Map(givers(c, HAYWARD).map(g => [g.place, g.role]));
    for (const r of v.locals as { id: string; kind: string; place: string; giver: string; city: string; here: boolean; template: string }[]) {
      expect(r.id.startsWith(`req_loc_${HAYWARD}-`)).toBe(true);
      expect(r.kind).toBe(kinds[roleOf.get(r.place)!]);
      expect(r.giver).not.toBe('');
      expect(r).toMatchObject({ city: 'Hayward', here: true, cluster: HAYWARD });
      expect(c.requests.templates[r.template].home_only).toBeFalsy();
    }
    const first = v.locals[0] as { id: string; place: string };
    const s2 = step(s, { type: 'accept', request: first.id, ...at(first.place) }, T + 2 * H);
    expect(locals(s2).find(sl => sl.req.id === first.id)?.req.status).toBe('accepted');
  });

  it('none at home, none in the home city\'s view', () => {
    const s = player(SF);
    settleLocals(c, s, T);
    expect(s.locals).toBeUndefined();
    expect(viewOf(c, s, T).locals).toEqual([]);
  });

  it('an S-tier town: all of them from its Trading Post cabin, any of the four kinds', () => {
    const s = player(LOUDI);
    settleLocals(c, s, T);
    expect(locals(s, LOUDI).length).toBeGreaterThan(0);
    expect(locals(s, LOUDI).every(sl => sl.place === `${LOUDI}~cabin0`)).toBe(true);
    expect(givers(c, LOUDI)[0].templates.length).toBe(new Set(Object.values(c.requests.local!.roles).flat()).size);
  });

  it('taken and handed in at the keeper\'s outpost only (wrong_place elsewhere); dropped anywhere, not drawn again that day', () => {
    let s = player();
    settleLocals(c, s, T);
    const { req, place } = locals(s)[0];
    const other = givers(c, HAYWARD).find(g => g.place !== place)!.place;
    expect(run(s, { type: 'accept', request: req.id, ...at(other) })).toMatchObject({ ok: false, code: 'wrong_place', detail: { place, city: HAYWARD } });
    expect(run(s, { type: 'accept', request: req.id, space: 'home' })).toMatchObject({ ok: false, code: 'wrong_place' });
    s = step(s, { type: 'accept', request: req.id, ...at(place) });
    expect(tracked(c, s)).toBe(1);
    s.travel.here = SF;
    s = step(s, { type: 'drop', request: req.id, space: 'home' });
    expect(locals(s).some(sl => sl.req.id === req.id)).toBe(false);
    s.travel.here = HAYWARD;
    settleLocals(c, s, T + H);
    expect(locals(s).some(sl => sl.req.id === req.id)).toBe(false);
    expect(locals(s)).toHaveLength(c.requests.local!.per_day - 1);
  });

  it('hands in for the floor price and the template\'s bonus under the daily cap, not one of today\'s 6 (even with the 6 done)', () => {
    let s = itemisedPlayer();
    const { req, place } = itemised(s);
    s = step(s, { type: 'accept', request: req.id, ...at(place) });
    fill(s, locals(s).find(sl => sl.req.id === req.id)!.req);
    s.day.sys_done = c.quotas.sys_requests.cap;
    s.day.bonus = 95;
    const coins = s.coins;
    const r = run(s, { type: 'deliver', request: req.id, ...at(place) });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.day.sys_done).toBe(c.quotas.sys_requests.cap);
    expect(r.state.day.bonus).toBe(100);
    const done = r.events.find(e => e.kind === 'request' && e.status === 'done') as { coins: number; bonus: number };
    expect(done.bonus).toBe(5);
    expect(r.state.coins - coins).toBe(done.coins);
    expect(locals(r.state).some(sl => sl.req.id === req.id)).toBe(false);
    expect(r.state.req_done).toContain(req.id);
    expect(run(r.state, { type: 'deliver', request: req.id, ...at(place) })).toMatchObject({ ok: false, code: 'request_done' });
  });

  it('a new day: the tracked one stays (outside the new per_day), the untracked are drawn anew', () => {
    let s = player();
    settleLocals(c, s, T);
    const { req, place } = locals(s)[0];
    s = step(s, { type: 'accept', request: req.id, ...at(place) });
    const old = locals(s).filter(sl => sl.req.id !== req.id).map(sl => sl.req.id);
    s.travel.passes[HAYWARD] = { kind: 'day', from: T + DAY - H, until: T + 2 * DAY } as never;
    settleLocals(c, s, T + DAY);
    const ids = locals(s).map(sl => sl.req.id);
    expect(ids).toContain(req.id);
    expect(ids.filter(id => old.includes(id))).toEqual([]);
    expect(ids).toHaveLength(1 + c.requests.local!.per_day);
  });

  it('track ≤ 3 counts them with the boards and the residents', () => {
    let s = player();
    settleBoards(c, s, T);
    settleLocals(c, s, T);
    for (const { req, place } of locals(s)) s = step(s, { type: 'accept', request: req.id, ...at(place) });
    expect(tracked(c, s)).toBe(3);
    const board = s.markets[HAYWARD].find(sl => sl.req)!.req!;
    expect(run(s, { type: 'accept', request: board.id, ...at(`${HAYWARD}~market0`) })).toMatchObject({ ok: false, code: 'track_limit' });
  });

  it('the map: a ! on the keeper for one offered while in the city, none from home; a ✓ for one ready wherever, today\'s 6 or not', () => {
    let s = itemisedPlayer();
    const { req, place } = itemised(s);
    expect(mapMarkers(c, s, T).find(m => m.place === place)).toMatchObject({ kind: 'request', why: { request: req.id } });
    s = step(s, { type: 'accept', request: req.id, ...at(place) });
    s.travel.here = SF;
    expect(mapMarkers(c, s, T).find(m => m.place === place)).toBeUndefined();
    fill(s, locals(s).find(sl => sl.req.id === req.id)!.req);
    s.day.sys_done = c.quotas.sys_requests.cap;
    expect(mapMarkers(c, s, T).find(m => m.place === place)).toMatchObject({ kind: 'deliver', why: { request: req.id, tracked: true } });
    const v = viewOf(c, s, T);
    expect(v.locals).toEqual([expect.objectContaining({ id: req.id, here: false, city: 'Hayward', ready: true, status: 'accepted' })]);
  });

  it('progress floats count a tracked local request as a board\'s', () => {
    let s = itemisedPlayer();
    const { req, place } = itemised(s);
    s = step(s, { type: 'accept', request: req.id, ...at(place) });
    const before = takenCounts(c, s);
    expect(before.get(req.id)).toMatchObject({ qty: req.qty, have: 0 });
    s.bag.push({ id: req.items[0], qty: 1 });
    const events: P0Event[] = [];
    noteProgress(c, s, before, events);
    expect(events).toContainEqual(expect.objectContaining({ kind: 'request_progress', id: req.id, have: 1, qty: req.qty }));
  });

  it('the daily bonus cap reads the content by Homestead level (q(272) ⑩); all 100 today', () => {
    const s = player(SF);
    expect(bonusCap(c, s)).toBe(100);
    const tiered = { ...c, quotas: { ...c.quotas, request_bonus: { ...c.quotas.request_bonus, by_homestead: [[1, 100], [3, 150]] } } } as P0Content;
    expect(bonusCap(tiered, s)).toBe(150);
    s.homestead.level = 2;
    expect(bonusCap(tiered, s)).toBe(100);
    s.homestead.level = 3;
    s.day.bonus = 140;
    expect(payBonus(tiered, s, 20)).toBe(10);
    expect(viewOf(tiered, s, T).quotas.request_bonus.cap).toBe(150);
  });

  it('a city left 30 days with nothing tracked loses its Market Board and its local requests; one tracked keeps them', () => {
    let s = player();
    settleBoards(c, s, T);
    settleLocals(c, s, T);
    s.travel.here = SF;
    const later = T + 31 * DAY;
    const a = structuredClone(s);
    pruneCities(c, a, later);
    expect(a.markets[HAYWARD]).toBeUndefined();
    expect(a.locals?.[HAYWARD]).toBeUndefined();
    expect(a.markets[SF]).toBe(a.boards.market);
    pruneCities(c, s, T + 29 * DAY);
    expect(s.markets[HAYWARD]).toBeDefined();
    s.travel.here = HAYWARD;
    const { req, place } = locals(s)[0];
    s = step(s, { type: 'accept', request: req.id, ...at(place) });
    s.travel.here = SF;
    pruneCities(c, s, later);
    expect(s.locals?.[HAYWARD]).toBeDefined();
    expect(s.markets[HAYWARD]).toBeDefined();
  });

  it('30 days from the later of the last arrival and the pass\'s end; never with a pass running nor while inside one of its outposts; visits and stamps stay', () => {
    const s = player();
    settleBoards(c, s, T);
    settleLocals(c, s, T);
    s.travel.here = SF;
    s.travel.stamps = [...(s.travel.stamps ?? []), HAYWARD] as never;
    const keep = (at: number, edit: (x: P0State) => void = () => {}) => {
      const x = structuredClone(s);
      edit(x);
      pruneCities(c, x, at);
      return x.markets[HAYWARD] !== undefined;
    };
    expect(keep(T + 31 * DAY)).toBe(false);
    // a pass that ended 2 days after the arrival counts from its end
    expect(keep(T + 31 * DAY, x => { x.travel.passes[HAYWARD] = { kind: 'day', from: T - H, until: T + 2 * DAY } as never; })).toBe(true);
    expect(keep(T + 33 * DAY, x => { x.travel.passes[HAYWARD] = { kind: 'day', from: T - H, until: T + 2 * DAY } as never; })).toBe(false);
    // still inside its market square (a lapsed pass does not send the player home from there)
    expect(keep(T + 31 * DAY, x => { x.presence.entered = `${HAYWARD}~market0`; })).toBe(true);
    const gone = structuredClone(s);
    pruneCities(c, gone, T + 31 * DAY);
    expect(gone.travel.visits[HAYWARD]).toEqual(s.travel.visits[HAYWARD]);
    expect(gone.travel.stamps).toEqual(s.travel.stamps);
  });

  it('a fish one only for a fish the player can land there: none above the Fishing level (Local Waters too), River Run only where the city\'s waters hold trout', () => {
    const drawn = (cc: P0Content, city: string, fishing: number) => {
      const out: BoardRequest[] = [];
      for (let n = 0; n < 40; n++) {
        const s = player(city, `q272-fish-${n}`);
        s.skills.fishing = fishing;
        settleLocals(cc, s, T);
        out.push(...(s.locals?.[city]?.slots ?? []).map(sl => sl.req));
      }
      return out;
    };
    const levelOf = (id: string) => c.fish.find(f => f.id === id)!.level;
    const mid = player(SHANGHAI);
    mid.skills.fishing = 300;   // Fishing Lv3: Local Waters open, Shanghai's regional fish not all landable
    const lv = skillLevel(c, mid, 'fishing');
    const shanghai = drawn(c, SHANGHAI, 300);
    expect(shanghai.some(r => r.kind === 'fish')).toBe(true);
    for (const r of shanghai) for (const i of r.items) if (i.startsWith('fish_')) expect(levelOf(i), i).toBeLessThanOrEqual(lv);
    expect(drawn(c, HAYWARD, 5000).some(r => r.template === 'req_sys_fish_river')).toBe(true);
    // the same city with no trout in its waters (a content where trout lives nowhere) never gives River Run
    const dry = Object.create(Object.getPrototypeOf(c), Object.getOwnPropertyDescriptors(c)) as P0Content;
    dry.fish = c.fish.map(f => (f.id === 'fish_trout' ? { ...f, where: [] } : f));
    expect(drawn(dry, HAYWARD, 5000).some(r => r.template === 'req_sys_fish_river')).toBe(false);
  });

  it('a home change: a local request tracked in the new home is dropped, free (the event lists it)', () => {
    const opened = Object.create(Object.getPrototypeOf(c), Object.getOwnPropertyDescriptors(c)) as P0Content & { world: { home?: object } };
    opened.world = { ...opened.world, home: { ...opened.world.home, cities: [TOKYO, NYC] } };
    const first = applyP0(opened, freshState(opened, 'q272-home-change', T, 7, { pending: true }), { type: 'choose_home', city: TOKYO, spot: 0 } as unknown as P0Command, T);
    if (!first.ok) throw new Error(first.code);
    let s = first.state;
    s.travel.here = NYC;
    s.travel.visits[NYC] = { n: 1, first_at: T, last_at: T, deliveries: 0, delivered_day: '' };
    s.travel.passes[NYC] = { kind: 'day', from: T, until: T + 23 * H } as never;
    settleLocals(opened, s, T);
    const { req, place } = s.locals![NYC].slots[0];
    const acc = applyP0(opened, s, { type: 'accept', request: req.id, space: 'outpost', place } as unknown as P0Command, T);
    if (!acc.ok) throw new Error(acc.code);
    s = acc.state;
    const ch = applyP0(opened, s, { type: 'change_home', city: NYC, spot: 0, space: 'home' } as unknown as P0Command, T + H);
    expect(ch.ok).toBe(true);
    if (!ch.ok) return;
    expect(ch.state.locals?.[NYC]).toBeUndefined();
    expect(ch.events).toContainEqual(expect.objectContaining({ kind: 'home', action: 'changed', city: NYC, dropped: [req.id] }));
    expect(tracked(opened, ch.state)).toBe(0);
  });

  it('Sell All keeps back what a tracked local request names', () => {
    let s = itemisedPlayer();
    const { req, place } = itemised(s);
    s = step(s, { type: 'accept', request: req.id, ...at(place) });
    expect(protectedQty(s, req.items[0])).toBe(req.kind === 'crop' || req.kind === 'material' ? req.qty : 0);
  });

  it('the routes mark a keeper\'s local request only for a client that shows them (x-p0-features: locals)', async () => {
    const s = player(HAYWARD, 'q272-route-player');
    settleLocals(c, s, T);
    const store = new P0Store(c);
    store.put(s);
    const app = Fastify();
    registerP0Routes(app, { content: c, store, now: () => T, dev: false });
    const marks = async (f: string) => ((await app.inject({ method: 'GET', url: '/v1/p0/state',
      headers: { 'x-p0-player': s.player, 'x-p0-features': f } })).json().state.map_markers as { place: string; why: { request?: string } }[])
      .filter(m => m.why.request?.startsWith('req_loc_'));
    expect(await marks('choose_home,guide_v3')).toEqual([]);
    // one mark a place (the market square's own board ! may stand for its keeper's too, as ` · +N more`)
    expect((await marks('choose_home,guide_v3,locals')).length).toBeGreaterThan(0);
    await app.close();
  });
});
