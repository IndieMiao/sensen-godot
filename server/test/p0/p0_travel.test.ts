/** SGODOT-278: cross-city travel (free first version), passes and stamps (note 0fc0bc5e §2–§4). */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Result } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { noteEntered, requirePass, tripOf } from '../../src/p0/travel.js';

const SF = 'gn-5391959', LA = 'gn-5368361', TOKYO = 'gn-1850147', NYC = 'gn-5128581', LDN = 'gn-2643743';
const HAYWARD_ETC = 3;   // San Francisco's nearest 3 (Hayward, Concord, Fairfield) are Trip 1
// The real frozen clusters (亚瑟's #213), so trips here are the ones players will see.
const c: P0Content = structuredClone(loadP0Content());
Object.defineProperty(c, 'clusters', { value: (loadP0Content() as P0Content & { clusters?: unknown }).clusters });
const TOKYO_POND = `${TOKYO}~pond0`;
c.fishing.places[TOKYO_POND] = { ...c.fishing.places.pond_san_francisco_03, city: 'tokyo' } as never;
const T = Date.parse('2026-10-10T18:00:00Z');   // 11:00 in San Francisco
const DAY = 86_400_000;

const fresh = () => freshState(c, 'travel-player', T, 7);
const run = (s: P0State, cmd: P0Command, at = T): P0Result => applyP0(c, s, cmd, at);
function step(s: P0State, cmd: P0Command, at = T) { const r = run(s, cmd, at); if (!r.ok) throw new Error(r.code); return r; }

describe('travel (SGODOT-278)', () => {
  it('fresh saves freeze the fallback list from the farm; trips follow table 11-4', () => {
    const s = fresh();
    expect(s.travel.fallback.near3).toHaveLength(HAYWARD_ETC);
    expect(s.travel.fallback.near10).toHaveLength(10);
    expect(tripOf(c, s, s.travel.fallback.near3[0]).trip).toBe(1);
    expect(tripOf(c, s, LA)).toMatchObject({ trip: 4, name: 'Long Haul' });
    expect(tripOf(c, s, TOKYO)).toMatchObject({ trip: 6, name: 'Intercontinental' });
    expect(tripOf(c, s, SF)).toEqual({ km: 0, trip: 1, name: 'Local' });
  });

  it('a first visit: Day Pass, stamp, +10 Energy, arrival event; free', () => {
    const s0 = fresh();
    s0.energy.value = 100;
    const r = step(s0, { type: 'travel', to: TOKYO });
    const s = r.state;
    expect(s.travel.here).toBe(TOKYO);
    expect(s.travel.passes[TOKYO]).toEqual({ kind: 'day', from: T, until: T + DAY });
    expect(s.travel.visits[TOKYO]).toMatchObject({ n: 1, first_at: T });
    expect(s.travel.stamps).toEqual([{ cluster: TOKYO, kind: 'climate', at: T, counted_on: '2026-10-10' }]);
    expect(s.energy.value).toBe(110);
    expect(s.coins).toBe(s0.coins);
    expect(r.events).toContainEqual(expect.objectContaining({ kind: 'arrival', cluster: TOKYO, first: true, energy: 10, pass_until: T + DAY }));
  });

  it('travel again while there is a no-op; a return visit gets no stamp or Energy; return_home keeps the pass', () => {
    let s = step(fresh(), { type: 'travel', to: TOKYO }).state;
    expect(step(s, { type: 'travel', to: TOKYO }, T + 1000).state.travel.visits[TOKYO].n).toBe(1);
    s = step(s, { type: 'return_home' }, T + 1000).state;
    expect(s.travel.here).toBe(SF);
    expect(s.travel.passes[TOKYO]).toBeDefined();
    const again = step(s, { type: 'travel', to: TOKYO }, T + 2 * DAY);
    expect(again.state.travel.visits[TOKYO].n).toBe(2);
    expect(again.state.travel.stamps).toHaveLength(1);
    expect(again.events).toContainEqual(expect.objectContaining({ kind: 'arrival', first: false, stamp: null, energy: 0 }));
  });

  it('two counted first visits a day: the third stamp counts tomorrow, with no Energy', () => {
    let s = fresh();
    s = step(s, { type: 'travel', to: TOKYO }).state;
    s = step(s, { type: 'travel', to: NYC }, T + 1).state;
    const before = s.energy.value;
    const r = step(s, { type: 'travel', to: LDN }, T + 2);
    expect(r.state.travel.stamps.map(x => x.counted_on)).toEqual(['2026-10-10', '2026-10-10', '2026-10-11']);
    expect(r.state.energy.value).toBe(before);
  });

  it('three counted stamps give Explorer Bronze once (+30)', () => {
    let s = fresh();
    s = step(s, { type: 'travel', to: TOKYO }).state;
    s = step(s, { type: 'travel', to: NYC }, T + 1).state;
    s = step(s, { type: 'travel', to: LDN }, T + 2).state;
    const r = step(s, { type: 'travel', to: LA }, T + DAY);
    expect(r.state.travel.explorer).toBe(3);
    expect(r.events).toContainEqual(expect.objectContaining({ kind: 'reward', id: 'explorer_3' }));
    expect(r.state.rewards.filter(x => x === 'explorer_3')).toHaveLength(1);
  });

  it('a medal for a stamp counted tomorrow comes with tomorrow\'s first command, not only the next trip', () => {
    let s = fresh();
    s = step(s, { type: 'travel', to: TOKYO }).state;
    s = step(s, { type: 'travel', to: NYC }, T + 1).state;
    s = step(s, { type: 'travel', to: LDN }, T + 2).state;   // third stamp counts 2026-10-11
    expect(s.travel.explorer).toBe(0);
    const r = step(s, { type: 'return_home' }, T + DAY);
    expect(r.state.travel.explorer).toBe(3);
    expect(r.events).toContainEqual(expect.objectContaining({ kind: 'reward', id: 'explorer_3' }));
  });

  it('home is always free; an unknown city is refused', () => {
    expect(step(fresh(), { type: 'travel', to: SF }).state.travel.here).toBe(SF);
    expect(run(fresh(), { type: 'travel', to: 'gn-1' })).toMatchObject({ ok: false, code: 'unknown_city' });
  });
});

describe('requirePass (SGODOT-278)', () => {
  it('a pond in a city never travelled to: pass_required with the confirm panel preview', () => {
    const r = run(fresh(), { type: 'cast', space: 'pond', place: TOKYO_POND });
    expect(r).toMatchObject({ ok: false, code: 'pass_required',
      detail: { message: 'Pass required', preview: { cluster: TOKYO, name: 'Tokyo', trip: 6, cost: { energy: 0, coins: 0, item: null }, first_visit: true } } });
  });

  it('with a Day Pass the pond fishes; once it runs out a new cast is trip_expired, the line already out still reels', () => {
    let s = step(fresh(), { type: 'travel', to: TOKYO }).state;
    s = step(s, { type: 'cast', space: 'pond', place: TOKYO_POND }, T + 1000).state;
    expect(s.cast?.place).toBe(TOKYO_POND);
    const late = T + DAY + 1;
    const reeled = run(s, { type: 'reel', outcome: 'cancel', space: 'pond', place: TOKYO_POND }, late);
    expect(reeled.ok).toBe(true);
    const again = run((reeled as { state: P0State }).state, { type: 'cast' }, late + 10);
    expect(again).toMatchObject({ ok: false, code: 'trip_expired', detail: { message: 'Trip expired' } });
  });

  it('an outpost already entered is not cut off when the pass ends; a new entry is', () => {
    let s = step(fresh(), { type: 'travel', to: TOKYO }).state;
    const outpost = `${TOKYO}~market0`;
    expect(requirePass(c, s, 'outpost', outpost, T + 1000)).toBeNull();
    noteEntered(s, 'outpost', outpost);   // what GET state ?space=outpost&place= does once the pass is checked
    expect(s.presence.entered).toBe(outpost);
    expect(requirePass(c, s, 'outpost', outpost, T + DAY + 5, 'sell')).toBeNull();
    expect(requirePass(c, s, 'outpost', outpost, T + DAY + 5)).toBeNull();   // the refresh read there too
    noteEntered(s, 'farm', null);   // left
    expect(requirePass(c, s, 'outpost', outpost, T + DAY + 5)?.code).toBe('trip_expired');
    expect(requirePass(c, s, 'outpost', `${TOKYO}~tea1`, T + DAY + 5, 'buy')?.code).toBe('trip_expired');
  });

  it('the 30 s refresh of the pond the player is in passes after the pass runs out; a new entry does not (亚瑟 on #206)', async () => {
    const app = Fastify();
    const store = new P0Store(c);
    let now = T;
    registerP0Routes(app, { content: c, store, now: () => now, dev: false });
    const headers = { 'x-p0-player': 'travel-route-2' };
    const at = `/v1/p0/state?space=pond&place=${encodeURIComponent(TOKYO_POND)}`;
    await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'travel', to: TOKYO } });
    expect((await app.inject({ method: 'GET', url: at, headers })).json().ok).toBe(true);
    now = T + 25 * 3_600_000;
    expect((await app.inject({ method: 'GET', url: at, headers })).json().ok).toBe(true);   // still in the pond
    await app.inject({ method: 'GET', url: '/v1/p0/state?space=farm', headers });             // went home
    expect((await app.inject({ method: 'GET', url: at, headers })).json()).toMatchObject({ ok: false, code: 'trip_expired' });
    await app.close();
  });

  it('home places never need a pass', () => {
    expect(requirePass(c, fresh(), 'pond', 'pond_san_francisco_03', T)).toBeNull();
    expect(requirePass(c, fresh(), 'outpost', c.outposts![0].id, T)).toBeNull();
  });

  it('GET state entering a foreign pond is refused and saves nothing', async () => {
    const app = Fastify();
    const store = new P0Store(c);
    registerP0Routes(app, { content: c, store, now: () => T, dev: false });
    const headers = { 'x-p0-player': 'travel-route-1' };
    const r = await app.inject({ method: 'GET', url: `/v1/p0/state?space=pond&place=${encodeURIComponent(TOKYO_POND)}`, headers });
    expect(r.json()).toMatchObject({ ok: false, code: 'pass_required', detail: { preview: { cluster: TOKYO } } });
    expect(r.json().state.travel.here).toBe(SF);
    expect(store.get('travel-route-1', T).presence.space).toBeNull();
    const city = await app.inject({ method: 'GET', url: `/v1/p0/city/${SF}`, headers });
    expect(city.json()).toMatchObject({ ok: true, city: { preview: { cluster: SF, trip: 1 } } });
    expect(city.json().city.ponds.length).toBeGreaterThan(0);
    expect((await app.inject({ method: 'GET', url: '/v1/p0/city/gn-9', headers })).statusCode).toBe(404);
    await app.close();
  });

  it('a Regular delivery counts once a day in the city the player is in', async () => {
    const { noteDelivery } = await import('../../src/p0/travel.js');
    const s = step(fresh(), { type: 'travel', to: TOKYO }).state;
    noteDelivery(c, s, T + 10); noteDelivery(c, s, T + 20);
    expect(s.travel.visits[TOKYO].deliveries).toBe(1);
    noteDelivery(c, s, T + DAY - 1000);   // next San Francisco day (04:00 rollover), pass still on
    expect(s.travel.visits[TOKYO].deliveries).toBe(2);
  });
});
