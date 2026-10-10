/**
 * Cross-city requests (q(128), 李白; SGODOT-284): Tea Trail / Postcard Trip / New Climate send the player to an outpost
 * in another city — checked in on entering, handed in at the home Market Board, the check-in counting that city's
 * Deliveries — and Far Pond takes fish the home city's ponds don't have, as the bag holds them.
 */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Result } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { settleBoards, crossCities, farFish, farTries, handIn } from '../../src/p0/boards.js';
import { floorPrice } from '../../src/p0/requests.js';
import { clusterById, clusterOf, rankedCities, tripOf } from '../../src/p0/travel.js';
import { cityPlaces } from '../../src/p0/world.js';
import { viewOf } from '../../src/p0/view.js';

const SF = 'gn-5391959', TOKYO = 'gn-1850147';
const base = loadP0Content() as P0Content & { clusters?: unknown };
/** The content with only this template on the Market Board (the real frozen clusters, as p0_travel). */
function only(template: string): P0Content {
  const c: P0Content = structuredClone(base);
  Object.defineProperty(c, 'clusters', { value: base.clusters });
  c.requests.boards.market.templates = [template];
  return c;
}
const T = Date.parse('2026-10-10T18:00:00Z');   // 11:00 in San Francisco
const fresh = (c: P0Content, homestead = 2) => {
  const s = freshState(c, 'cross-city-player', T, 7);
  s.homestead.level = homestead;
  settleBoards(c, s, T);
  return s;
};
const run = (c: P0Content, s: P0State, cmd: P0Command, at = T): P0Result => applyP0(c, s, cmd, at);
function step(c: P0Content, s: P0State, cmd: P0Command, at = T) { const r = run(c, s, cmd, at); if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`); return r; }
const req = (s: P0State) => s.boards.market[0].req!;

describe('cross-city targets (q(128))', () => {
  it('Postcard Trip: Market Square 1 (or a small city\'s Trading Post) of a Trip 2–3 city', () => {
    const c = only('req_sys_explore_city');
    const s = fresh(c);
    const r = req(s);
    expect(r.template).toBe('req_sys_explore_city');
    const city = clusterOf(c, r.visit!.place)!;
    expect(city).not.toBe(SF);
    expect([2, 3]).toContain(tripOf(c, s, city).trip);
    expect(r.visit!.place).toMatch(/~(market0|cabin0)$/);
    // the card names it without the client's city cache (亚瑟): name, city and point come with the request
    const v = viewOf(c, s, T).boards.market.slots[0] as { visit: Record<string, unknown> };
    expect(v.visit).toMatchObject({ place: r.visit!.place, done: false, cluster: city, city: clusterById(c, city)!.name });
    expect(String(v.visit.name)).not.toBe('');
    expect(typeof v.visit.lat).toBe('number');
  });

  it('Tea Trail: the first Tea House of a Trip 1–2 city; New Climate: the nearest city in another climate zone', () => {
    const tea = only('req_sys_explore_tea');
    const s = fresh(tea);
    const place = req(s).visit!.place;
    expect([1, 2]).toContain(tripOf(tea, s, clusterOf(tea, place)!).trip);
    expect(place).toMatch(/~(tea0|cabin0)$/);
    const zone = only('req_sys_explore_zone');
    const z = fresh(zone, 3);
    const home = clusterById(zone, SF)!.climate;
    const nearest = rankedCities(zone, z).find(x => clusterById(zone, x.id)!.climate !== home && cityPlaces(zone, x.id))!;
    expect(clusterOf(zone, req(z).visit!.place)).toBe(nearest.id);
    expect(clusterById(zone, nearest.id)!.climate).not.toBe(home);
    expect(crossCities(zone, z, { where: 'other_zone', role: 'market' })[0]).toBe(nearest.id);
  });

  it('gated at the Homestead level: never on the first session\'s Market Board', () => {
    for (const [t, lv] of [['req_sys_explore_tea', 2], ['req_sys_explore_city', 2], ['req_sys_explore_zone', 3], ['req_sys_explore_pond', 2]] as const) {
      const c = only(t);
      expect(fresh(c, lv - 1).boards.market[0].req, t).toBeNull();
      expect(fresh(c, lv).boards.market[0].req?.template, t).toBe(t);
    }
  });
});

describe('the check-in and the hand-in', () => {
  it('entering the outpost there checks it in and counts that city\'s Deliveries; home pays the bonus, counting none', async () => {
    const c = only('req_sys_explore_city');
    const app = Fastify();
    const store = new P0Store(c);
    registerP0Routes(app, { content: c, store, now: () => T, dev: false });
    const player = 'cross-city-route';
    let s = store.get(player, T);
    s.homestead.level = 2;
    settleBoards(c, s, T);
    const r = req(s), city = clusterOf(c, r.visit!.place)!;
    s = step(c, s, { type: 'accept', request: r.id }).state;
    expect(run(c, s, { type: 'deliver', request: r.id })).toMatchObject({ ok: false, code: 'not_visited' });
    s = step(c, s, { type: 'travel', to: city }).state;
    store.put(s);
    const entered = await app.inject({ method: 'GET', url: `/v1/p0/state?space=outpost&place=${encodeURIComponent(r.visit!.place)}`,
      headers: { 'x-p0-player': player } });
    expect(entered.json().ok).toBe(true);
    s = store.get(player, T);
    expect(req(s).visit!.done).toBe(true);
    expect(s.travel.visits[city].deliveries).toBe(1);
    s = step(c, s, { type: 'travel', to: SF }, T + 60_000).state;
    const coins = s.coins;
    const done = step(c, s, { type: 'deliver', request: r.id }, T + 120_000);
    expect(done.state.coins).toBe(coins + 60);
    expect(done.state.travel.visits[city].deliveries).toBe(1);   // the hand-in at home adds none (q(128) ④)
    await app.close();
  });
  // 周瑜 on #285: the entry read checks in before it settles `here`; a pass bought earlier, home again, then straight into
  // that outpost still counts that city, not wherever `here` pointed
  it('a check-in counts its own city\'s Deliveries, whatever city the player was in before', async () => {
    const c = only('req_sys_explore_city');
    const app = Fastify();
    const store = new P0Store(c);
    registerP0Routes(app, { content: c, store, now: () => T, dev: false });
    const player = 'cross-city-order';
    let s = store.get(player, T);
    s.homestead.level = 2;
    settleBoards(c, s, T);
    const r = req(s), city = clusterOf(c, r.visit!.place)!;
    s = step(c, s, { type: 'accept', request: r.id }).state;
    s = step(c, s, { type: 'travel', to: city }).state;   // the pass
    s = step(c, s, { type: 'travel', to: SF }).state;     // home again, the pass kept
    store.put(s);
    const entered = await app.inject({ method: 'GET', url: `/v1/p0/state?space=outpost&place=${encodeURIComponent(r.visit!.place)}`,
      headers: { 'x-p0-player': player } });
    expect(entered.json().ok).toBe(true);
    s = store.get(player, T);
    expect(req(s).visit!.done).toBe(true);
    expect(s.travel.visits[city].deliveries).toBe(1);
    await app.close();
  });
});

describe('Far Pond (q(128) 甲)', () => {
  const slot = (c: P0Content, s: P0State) => viewOf(c, s, T).boards.market.slots[0] as { have: number; coins: number; tries?: string[]; where: string };

  it('takes the fish the home city\'s ponds don\'t have — what is in the bag, wherever it was caught', () => {
    const c = only('req_sys_explore_pond');
    let s = fresh(c);
    const r = req(s), qty = r.qty;
    expect(r).toMatchObject({ kind: 'fish', where: 'not_home', items: [] });
    expect(r).not.toHaveProperty('abroad');
    // San Francisco: other cities' regional fish; not its own 2 (Arctic Char, Salmon), nor what its 6 ponds give — Clover
    // Pond is a Coast pond, so Grey Mullet and Mackerel are home fish
    const far = farFish(c);
    expect(far).toEqual(expect.arrayContaining(['fish_tilapia', 'fish_smelt']));
    for (const id of ['fish_crucian', 'fish_mullet', 'fish_mackerel', 'fish_seabass', 'fish_arctic_char', 'fish_salmon']) expect(far).not.toContain(id);
    // the card estimates at the cheapest of them (Tilapia / Smelt, floor 3): 3 × 3 + 20 = 29 for three
    const cheapest = Math.min(...far.map(id => floorPrice(c, id)));
    expect(cheapest).toBe(3);
    expect(slot(c, s).coins).toBe(qty * cheapest + 20);
    s.bag.push({ id: 'fish_crucian', qty: 9 }, { id: 'fish_mullet', qty: 4 });
    expect(slot(c, s).have).toBe(0);
    expect(handIn(c, s, r)).toBeNull();
    s = step(c, s, { type: 'accept', request: r.id }).state;
    // caught anywhere, collected from a trap, or before it was taken: the bag is what counts
    s.bag.push({ id: 'fish_smelt', qty: qty - 1 });
    expect(slot(c, s).have).toBe(qty - 1);
    expect(run(c, s, { type: 'deliver', request: r.id })).toMatchObject({ ok: false, code: 'not_enough', detail: { need: qty, have: qty - 1 } });
    s.bag.push({ id: 'fish_tilapia', qty: 2 });
    expect(slot(c, s).have).toBe(qty);
    // sold or eaten, the count goes down with it
    const less = structuredClone(s);
    less.bag = less.bag.filter(b => b.id !== 'fish_tilapia');
    expect(slot(c, less).have).toBe(qty - 1);
    // the hand-in takes those kinds only, cheapest first, at floor + 20; no city's Deliveries count it
    const visits = structuredClone(s.travel.visits);
    const parts = handIn(c, s, req(s))!;
    expect(parts.every(([id]) => far.includes(id))).toBe(true);
    const done = step(c, s, { type: 'deliver', request: r.id });
    const floor = parts.reduce((n, [id, k]) => n + floorPrice(c, id) * k, 0);
    expect(done.events).toContainEqual(expect.objectContaining({ kind: 'request', id: r.id, status: 'done', coins: floor + 20 }));
    expect(done.state.bag.filter(b => b.id === 'fish_crucian' || b.id === 'fish_mullet').reduce((n, b) => n + b.qty, 0)).toBe(13);
    expect(done.state.travel.visits).toEqual(visits);
  });

  it('is drawn only when one is landable within Trip 3 at the player\'s Fishing level; that list is its example line', () => {
    const c = only('req_sys_explore_pond');
    const s = fresh(c);
    const tries = farTries(c, s), far = farFish(c);
    expect(tries.length).toBeGreaterThanOrEqual(1);
    expect(tries.length).toBeLessThanOrEqual(3);
    for (const id of tries) {
      expect(far).toContain(id);
      expect(c.fish.find(f => f.id === id)!.level).toBeLessThanOrEqual(1);
    }
    expect(slot(c, s).tries).toEqual(tries);   // the view sends it with the card, at the level now
    // a higher level opens more (Grass Carp, Fishing Lv3): the list follows the level, each one cached
    const higher = structuredClone(s);
    higher.skills.fishing = 100_000;
    expect(farTries(c, higher).some(id => c.fish.find(f => f.id === id)!.level > 1)).toBe(true);
    expect(farTries(c, s)).toBe(tries);
    // nothing landable at this level within Trip 3: no Far Pond on the board
    const none = only('req_sys_explore_pond');
    for (const f of none.fish) if (farFish(none).includes(f.id)) f.level = 11;
    const blank = fresh(none);
    expect(farTries(none, blank)).toEqual([]);
    expect(blank.boards.market[0].req).toBeNull();
  });

  it('no pin on a pond for it (a pond in another city, the player\'s choice)', () => {
    const c = only('req_sys_explore_pond');
    const s = fresh(c);
    req(s).status = 'accepted';
    const markers = (viewOf(c, s, T) as { map_markers: { place: string; why?: { request?: string } }[] }).map_markers;
    expect(markers.filter(m => m.why?.request === req(s).id && m.place.startsWith('pond_'))).toEqual([]);
  });
});
