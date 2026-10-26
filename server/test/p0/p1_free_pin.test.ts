/** q(216) (SGODOT-342, 338·L2; user 10-26, method D): a home's farm stands where the player drops a free pin — inside
 * the city's circle (range_km of its base), clear of its outposts, huts and ponds (clear_m); no land or water test.
 * choose_home / change_home carry `at: [lat, lng]`; an older client still sends `spot` and gets one of the three. */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { homeBase, homeFacts } from '../../src/p0/home.js';
import { citySet, homeRules, homeSpots, pinArea, pinBlocks, pinRefusal } from '../../src/p0/home_city.js';
import type { P0Event } from '../../src/p0/progress.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { viewOf } from '../../src/p0/view.js';
import { km, offset, type WorldContent } from '../../src/p0/world.js';

const c: P0Content = loadP0Content();
const w = (c as P0Content & { world: WorldContent }).world;
const T0 = Date.parse('2026-10-26T15:00:00Z');
const SF = 'gn-5391959', TOKYO = 'gn-1850147', NYC = 'gn-5128581';
const opened: P0Content = (() => {
  const o = Object.create(Object.getPrototypeOf(c), Object.getOwnPropertyDescriptors(c)) as P0Content & { world: WorldContent };
  o.world = { ...w, home: { ...(w as { home?: object }).home, cities: [TOKYO, NYC] } } as WorldContent;
  return o;
})();
const withPin = (pin: { range_km: number; clear_m: number }): P0Content => {
  const o = Object.create(Object.getPrototypeOf(opened), Object.getOwnPropertyDescriptors(opened)) as P0Content & { world: WorldContent };
  const ow = (opened as P0Content & { world: WorldContent }).world as WorldContent & { home: object };
  o.world = { ...ow, home: { ...ow.home, pin } } as WorldContent;
  return o;
};
const pending = (id = 'player-pin-0001'): P0State => freshState(opened, id, T0, 7, { pending: true });
const run = (cc: P0Content, s: P0State, cmd: Record<string, unknown>, at = T0) => applyP0(cc, s, cmd as unknown as P0Command, at);
const base = (city: string) => homeBase(opened, { travel: { home: city } })!;
/** A point km from the city's base that keeps clear of its places: the first such on a ring, bearing by bearing. */
const freePoint = (city: string, d: number) => {
  for (let deg = 0; deg < 360; deg += 5) {
    const p = offset(base(city).lat, base(city).lng, d, deg);
    if (!pinRefusal(opened, city, p)) return p;
  }
  throw new Error(`no free point ${d} km from ${city}`);
};

describe('the rules (q(216))', () => {
  it('ship as method D: 10 km round the base, 300 m clear of the places', () => {
    expect(homeRules(c).pin).toEqual({ range_km: 10, clear_m: 300 });
  });

  it('the base is the written city\'s profile point, another city\'s centre (q(184) homeBase)', () => {
    expect(base(SF)).toEqual({ lat: c.profile.farm_at![0], lng: c.profile.farm_at![1] });
    expect(base(TOKYO)).toEqual(homeFacts(opened, { travel: { home: TOKYO } }).farm);
  });

  it('a point inside the circle and clear of every place may stand, wherever it falls — no land test', () => {
    for (const d of [0.8, 4, 9.9]) expect(pinRefusal(opened, TOKYO, freePoint(TOKYO, d))).toBeNull();
  });

  it('beyond the circle: home_out_of_range, with how far it is', () => {
    const p = offset(base(TOKYO).lat, base(TOKYO).lng, 10.5, 90);
    expect(pinRefusal(opened, TOKYO, p)).toEqual({ code: 'home_out_of_range', detail: { km: expect.closeTo(10.5, 1), range_km: 10 } });
  });

  it('within 300 m of an outpost, a hut or a pond: home_too_close, naming the nearest', () => {
    const blocks = pinBlocks(opened, TOKYO);
    expect(blocks.length).toBeGreaterThan(5);
    const set = citySet(opened, TOKYO)!;
    for (const id of [set.market, set.pond]) {
      const b = blocks.find(x => x.id === id)!;
      const p = offset(b.lat, b.lng, 0.12, 30);
      const no = pinRefusal(opened, TOKYO, p);
      expect(no?.code).toBe('home_too_close');
      expect(no?.detail).toMatchObject({ clear_m: 300 });
      const named = blocks.find(x => x.id === no!.detail!.place)!;
      expect(Math.round(km(p, named) * 1000)).toBe(no!.detail!.m);
      expect(blocks.every(x => km(p, x) * 1000 >= (no!.detail!.m as number) - 1)).toBe(true);
    }
  });

  it('clear_m 0 lets a pin stand by a place (q(216) ⑤ not taken)', () => {
    const b = pinBlocks(opened, TOKYO).find(x => x.id === citySet(opened, TOKYO)!.market)!;
    expect(pinRefusal(withPin({ range_km: 10, clear_m: 0 }), TOKYO, offset(b.lat, b.lng, 0.1, 30))).toBeNull();
  });

  it('every open city\'s pin starts on a point it may stand on, for any player', () => {
    for (const city of [SF, ...homeRules(c).cities]) {
      for (let i = 0; i < 6; i++) {
        const a = pinArea(c, city, `player-start-${i}`)!;
        expect(a, city).not.toBeNull();
        expect(a.start).toEqual({ lat: homeSpots(c, city, `player-start-${i}`)![0].lat, lng: homeSpots(c, city, `player-start-${i}`)![0].lng });
        expect(pinRefusal(c, city, a.start), `${city} player ${i}`).toBeNull();
      }
    }
  });
});

describe('choose_home and change_home with a free pin', () => {
  it('the farm stands at the pin; the home set is the city\'s; the event says spot -1', () => {
    const p = freePoint(TOKYO, 6);
    const r = run(opened, pending(), { type: 'choose_home', city: TOKYO, at: [p.lat, p.lng] });
    if (!r.ok) throw new Error(r.code);
    expect(r.state.travel.farm_at).toEqual([p.lat, p.lng]);
    expect(r.state.travel.home).toBe(TOKYO);
    expect(r.state.travel.home_set).toEqual(citySet(opened, TOKYO));
    expect(r.state.travel.pending).toBeUndefined();
    expect((r.events as P0Event[]).find(e => e.kind === 'home')).toMatchObject({ kind: 'home', action: 'chosen', city: TOKYO, spot: -1 });
    const v = viewOf(opened, r.state, T0) as unknown as { home: { farm: { lat: number; lng: number } } };
    expect(v.home.farm).toEqual(p);
  });

  it('a refused pin leaves the save pending, nothing written', () => {
    const s = pending();
    const far = offset(base(TOKYO).lat, base(TOKYO).lng, 12, 200);
    const r = run(opened, s, { type: 'choose_home', city: TOKYO, at: [far.lat, far.lng] });
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe('home_out_of_range');
    expect(s.travel.pending).toBe(true);
    expect(s.travel.farm_at).toBeUndefined();
  });

  it('a pin that is not a point: bad_pin', () => {
    for (const at of [[35.6], [35.6, 'x'], [95, 139], [35.6, 200], 'here', null, [Number.NaN, 139]]) {
      const r = run(opened, pending(), { type: 'choose_home', city: TOKYO, at });
      expect(r.ok ? 'ok' : r.code, JSON.stringify(at)).toBe('bad_pin');
    }
  });

  it('a city not open refuses the pin as it refuses a spot', () => {
    const r = run(opened, pending(), { type: 'choose_home', city: 'gn-1796236', at: [31.23, 121.47] });
    expect(r.ok ? 'ok' : r.code).toBe('home_not_open');
  });

  it('`at` wins over `spot`: a client sending both gets its pin', () => {
    const p = freePoint(NYC, 3);
    const r = run(opened, pending(), { type: 'choose_home', city: NYC, spot: 2, at: [p.lat, p.lng] });
    if (!r.ok) throw new Error(r.code);
    expect(r.state.travel.farm_at).toEqual([p.lat, p.lng]);
  });

  it('an older client\'s spot still picks one of the three', () => {
    const r = run(opened, pending(), { type: 'choose_home', city: TOKYO, spot: 1 });
    if (!r.ok) throw new Error(r.code);
    const s1 = homeSpots(opened, TOKYO, 'player-pin-0001')![1];
    expect(r.state.travel.farm_at).toEqual([s1.lat, s1.lng]);
    expect((r.events as P0Event[]).find(e => e.kind === 'home')).toMatchObject({ spot: 1 });
  });

  it('the free change takes a pin too, in the new city\'s circle', () => {
    const first = run(opened, pending(), { type: 'choose_home', city: TOKYO, spot: 0 });
    if (!first.ok) throw new Error(first.code);
    const p = freePoint(NYC, 2);
    const r = run(opened, first.state, { type: 'change_home', city: NYC, at: [p.lat, p.lng] }, T0 + 3_600_000);
    if (!r.ok) throw new Error(r.code);
    expect(r.state.travel.home).toBe(NYC);
    expect(r.state.travel.farm_at).toEqual([p.lat, p.lng]);
    expect(r.state.travel.home_changes).toBe(1);
    const tokyoPin = freePoint(TOKYO, 2);
    const again = run(opened, first.state, { type: 'change_home', city: NYC, at: [tokyoPin.lat, tokyoPin.lng] }, T0 + 3_600_000);
    expect(again.ok ? 'ok' : again.code).toBe('home_out_of_range');
  });
});

describe('the pick page\'s read (GET /v1/p0/home/spots/:cluster)', () => {
  const app = Fastify();
  registerP0Routes(app, { content: opened, store: new P0Store(opened), now: () => T0, dev: true });
  const headers = { 'x-p0-player': 'player-pin-route' };

  it('carries the pin\'s circle, its start and the places it keeps clear of, beside the three spots', async () => {
    const r = (await app.inject({ method: 'GET', url: `/v1/p0/home/spots/${TOKYO}`, headers })).json();
    expect(r.ok).toBe(true);
    expect(r.spots).toHaveLength(3);
    expect(r.pin).toEqual({ base: base(TOKYO), range_km: 10, clear_m: 300, start: { lat: r.spots[0].lat, lng: r.spots[0].lng },
      blocks: pinBlocks(opened, TOKYO) });
  });
});
