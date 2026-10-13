/** SGODOT-303, the server's second step (q(160)–q(163)): a new player picks a home city and one of 3 farm spots; the save
 * keeps the home, the spot and the home set; one free change follows. Saves that never picked play San Francisco as
 * before (q(163) ③). */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { visitPlaces } from '../../src/p0/boards.js';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { clustersOf, homeFacts } from '../../src/p0/home.js';
import { citySet, citySpots, cityOutposts, cityPonds, homeCities, homeRules, homeSpots, homeStatus, livesIn, spotTable } from '../../src/p0/home_city.js';
import { pondFor } from '../../src/p0/markers.js';
import { pondFishIds } from '../../src/p0/fishing_world.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { dayKey } from '../../src/p0/rules.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { clusterById, fallbackOf } from '../../src/p0/travel.js';
import { viewOf } from '../../src/p0/view.js';
import { km, tierOf, type WorldContent } from '../../src/p0/world.js';

const c: P0Content = loadP0Content();
const w = (c as P0Content & { world: WorldContent }).world;
const T0 = Date.parse('2026-10-13T15:00:00Z');
const DAY = 86_400_000;
const SF = 'gn-5391959', TOKYO = 'gn-1850147', NYC = 'gn-5128581', LONDON = 'gn-2643743', OSAKA = 'gn-1853909';
/** The content with only Tokyo, New York and London on the open list (the shipped list is checked on its own below). */
const opened: P0Content = (() => {
  const o = Object.create(Object.getPrototypeOf(c), Object.getOwnPropertyDescriptors(c)) as P0Content & { world: WorldContent };
  o.world = { ...w, home: { ...(w as { home?: object }).home, cities: [TOKYO, NYC, LONDON] } } as WorldContent;
  return o;
})();
const pending = (): P0State => freshState(opened, 'player-pick-01', T0, 7, { pending: true });
const run = (cc: P0Content, s: P0State, cmd: Record<string, unknown>, at = T0) => applyP0(cc, s, cmd as unknown as P0Command, at);
const picked = (city = TOKYO, spot = 1): P0State => {
  const r = run(opened, pending(), { type: 'choose_home', city, spot });
  if (!r.ok) throw new Error(r.code);
  return r.state;
};

describe('saves that never picked a home (q(163) ③)', () => {
  it('stay San Francisco\'s, farming at the written point, with nothing to pick', () => {
    const s = freshState(c, 'player-old-0001', T0, 3);
    expect(s.travel.pending).toBeUndefined();
    const up = upgradeState(c, structuredClone(s), T0);
    expect(up.travel).toEqual(s.travel);
    const v = viewOf(c, up, T0) as unknown as { home: Record<string, unknown> };
    expect(v.home).toMatchObject({ city: SF, name: 'San Francisco', pending: false,
      farm: { lat: c.profile.farm_at![0], lng: c.profile.farm_at![1] },
      set: { market: 'sh_market_1', tea: 'sh_tea_1', tackle: 'sh_tackle_1', post: 'sh_post_1', pond: 'pond_san_francisco_03' } });
  });

  it('a home that was never picked still goes back to the written city on load; a picked one stays', () => {
    const s = freshState(c, 'player-old-0002', T0, 3);
    s.travel = { ...s.travel, home: TOKYO, here: TOKYO };
    expect(upgradeState(c, structuredClone(s), T0).travel.home).toBe(SF);
    const p = picked();
    expect(upgradeState(opened, structuredClone(p), T0).travel).toEqual(p.travel);
  });

  it('a new save asks to pick only when its client can offer the pick', () => {
    const store = new P0Store(c);
    expect(store.get('player-new-0001', T0).travel.pending).toBeUndefined();
    expect(store.get('player-new-0002', T0, { pending: true }).travel.pending).toBe(true);
    expect(store.get('player-new-0001', T0, { pending: true }).travel.pending).toBeUndefined();   // only when the save is made
  });
});

describe('home sets and which cities can be picked (q(160) ①, q(162))', () => {
  it('San Francisco\'s set is the hand-written one; a generated city\'s is its first of each role and its beginner pond', () => {
    expect(citySet(c, SF)).toEqual({ market: 'sh_market_1', tea: 'sh_tea_1', tackle: 'sh_tackle_1', post: 'sh_post_1', pond: 'pond_san_francisco_03' });
    const tokyo = citySet(c, TOKYO)!;
    expect(tokyo).toMatchObject({ market: `${TOKYO}~market0`, tea: `${TOKYO}~tea0`, post: `${TOKYO}~post0` });
    const pond = cityPonds(c, TOKYO).find(p => p.id === tokyo.pond)!;
    expect(pond.beginner).toBe(true);
    const tackle = cityOutposts(c, TOKYO).find(o => o.id === tokyo.tackle)!;
    expect(km(tackle.at!, pond.at!)).toBeLessThanOrEqual(0.3);   // its own tackle shop, by the pond
  });

  it('San Francisco is always open; others need the list (M1 and up); S-tier towns are travel only', () => {
    expect(homeStatus(c, SF)).toBe('open');
    expect(homeStatus(c, OSAKA)).toBe('not_open');
    expect(homeStatus(opened, TOKYO)).toBe('open');
    expect(homeStatus(opened, 'gn-1796236')).toBe('not_open');   // Shanghai: on the shipped list, not on this one
    const town = [...clustersOf(c)!.byId.values()].find(cl => tierOf(w, cl) === 'S')!;
    expect(homeStatus(opened, town.id)).toBe('small');
    expect(homeStatus(c, 'gn-0')).toBeNull();
  });

  it('the pick page lists the open cities and finds others by name, greyed with the reason', () => {
    expect(homeCities(c).open.map(r => r.id)).toEqual([SF, ...homeRules(c).cities]);
    const { open, matches } = homeCities(opened, 'tok');
    expect(open.map(r => r.id)).toEqual([SF, TOKYO, NYC, LONDON]);
    expect(matches[0]).toMatchObject({ id: TOKYO, name: clusterById(c, TOKYO)!.name, status: 'open' });
    expect(homeCities(c, 'osa').matches.find(r => r.id === OSAKA)?.status).toBe('not_open');
    expect(homeCities(c, 't').matches).toEqual([]);   // two letters at least
  });
});

describe('farm spots (q(160) ②)', () => {
  // Every 60th city of M1 and up, plus the named ones: the rules hold everywhere a home can be.
  const cities = [SF, TOKYO, NYC, ...[...clustersOf(c)!.byId.values()].filter(cl => tierOf(w, cl) !== 'S').filter((_, i) => i % 60 === 0).map(cl => cl.id)];

  /** q(160) ②'s rules for one player's 3 spots in a city that can be a home. */
  const keepsRules = (city: string, player: string) => {
    const spots = homeSpots(c, city, player);
    expect(spots, `${city} ${player}`).toHaveLength(3);
    const set = citySet(c, city)!, pond = cityPonds(c, city).find(p => p.id === set.pond)!.at!;
    const blocks = [...cityOutposts(c, city), ...cityPonds(c, city)].flatMap(p => (p.at ? [p.at] : []));
    for (const s of spots!) {
      expect(s.km).toBeGreaterThanOrEqual(0.5);
      expect(s.km).toBeLessThanOrEqual(3);
      expect(Math.abs(km(s, pond) - s.km)).toBeLessThan(0.001);
      for (const b of blocks) expect(km(s, b), `${city} ${player} #${s.spot}`).toBeGreaterThanOrEqual(0.3);
      expect(s.pond.id).toBe(set.pond);
    }
    for (let i = 0; i < 3; i++) for (let j = i + 1; j < 3; j++) expect(km(spots![i], spots![j]), `${city} ${player}`).toBeGreaterThanOrEqual(1);
    expect(new Set(spots!.map(s => s.toward)).size, `${city} ${player}`).toBe(3);
  };

  it('3 spots, 0.5–3 km from the beginner pond, 300 m clear of every outpost and pond, 1 km apart, in different directions', () => {
    let checked = 0;
    for (const city of cities) {
      if (!citySet(c, city)) { expect(homeSpots(c, city, 'player-spot-01')).toBeNull(); continue; }
      keepsRules(city, 'player-spot-01');
      checked++;
    }
    expect(checked).toBeGreaterThan(20);
  });

  it('every city of the offline table keeps the rules for any player (周瑜 on #371: 4 players a city)', () => {
    const table = spotTable()!;
    for (const city of Object.keys(table.cities)) {
      for (const player of ['player-rule-0001', 'player-rule-0002', 'player-rule-0003', 'player-rule-0004']) keepsRules(city, player);
    }
  });

  it('the same player gets the same spots; each player is 100–200 m off the city\'s point', () => {
    expect(homeSpots(c, TOKYO, 'player-spot-01')).toEqual(homeSpots(c, TOKYO, 'player-spot-01'));
    const base = citySpots(c, TOKYO)!;
    for (const player of ['player-spot-01', 'player-spot-02', 'player-spot-03']) {
      homeSpots(c, TOKYO, player)!.forEach((s, k) => {
        const off = km(s, base[k].at) * 1000;
        expect(off).toBeGreaterThanOrEqual(99);
        expect(off).toBeLessThanOrEqual(201);
      });
    }
    expect(homeSpots(c, TOKYO, 'player-spot-02')).not.toEqual(homeSpots(c, TOKYO, 'player-spot-01'));
    const geometry = citySpots(c, OSAKA)!;   // a city off the table: the rules alone
    homeSpots(c, OSAKA, 'player-spot-01')!.forEach((s, k) => expect(km(s, geometry[k].at) * 1000).toBeLessThanOrEqual(201));
  });

  it('the shipped open list (q(160) ①): every city has its 3 checked spots with district names, for this world', () => {
    const table = spotTable()!;
    expect(table).toMatchObject({ seed: w.seed, revision: w.revision });
    const open = [SF, ...homeRules(c).cities];
    expect(Object.keys(table.cities).sort()).toEqual([...open].sort());
    const zones = new Map<string, number>();
    for (const city of open) {
      expect(homeStatus(c, city), city).toBe('open');
      const rows = table.cities[city];
      expect(rows, city).toHaveLength(3);
      const hoods = rows.map(r => r.hood);
      expect(new Set(hoods).size, city).toBe(3);
      for (const h of hoods) expect(h, city).toMatch(/^[\p{Script=Latin}\p{N}\s'’.&()-]{2,22}$/u);   // English card text, 22 at most (不知火舞)
      for (const h of hoods) expect(h, city).not.toMatch(/\b(park|hill|market|center|centre)\b|parken$/i);   // districts, not parks or landmarks
      expect(homeSpots(c, city, 'player-spot-01')!.map(s => s.hood)).toEqual(hoods);
      const zone = clusterById(c, city)?.climate ?? 'temperate';
      zones.set(zone, (zones.get(zone) ?? 0) + 1);
    }
    for (const zone of ['tropical', 'subtropical', 'temperate', 'cool']) expect(zones.get(zone) ?? 0, zone).toBeGreaterThanOrEqual(2);
  });

  it('the card line: district, distance and the pond\'s direction (`Mission District · 1.2 km to Fern Pond · northeast`)', () => {
    const s = homeSpots(c, SF, 'player-spot-01')![0];
    expect(s.pond.name).toBe('Fern Pond');
    expect(['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest']).toContain(s.toward);
    expect(s.hood).toBe('Mission District');
    expect(homeSpots(c, OSAKA, 'player-spot-01')![0].hood).toBeNull();   // off the table: no district name
  });
});

describe('choose_home (q(160), q(163))', () => {
  it('sets home, the spot, the frozen home set and the home\'s clock; the pick is asked no more', () => {
    const before = pending();
    expect(before.travel.home).toBe(SF);   // meanwhile it plays from the written city
    const r = run(opened, before, { type: 'choose_home', city: TOKYO, spot: 1 });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const t = r.state.travel, spot = homeSpots(opened, TOKYO, 'player-pick-01')![1];
    expect(t).toMatchObject({ home: TOKYO, here: TOKYO, farm_at: [spot.lat, spot.lng], home_set: citySet(c, TOKYO), home_chosen_at: T0 });
    expect(t.pending).toBeUndefined();
    expect(t.home_changes).toBeUndefined();   // the first pick is not the free change
    expect(t.fallback).toEqual(fallbackOf(c, TOKYO, t.farm_at));
    expect(homeFacts(c, r.state).farm).toEqual({ lat: spot.lat, lng: spot.lng });
    expect(dayKey(c, r.state, Date.UTC(2026, 9, 13, 18, 59))).toBe('2026-10-13');   // 03:59 in Tokyo
    expect(dayKey(c, r.state, Date.UTC(2026, 9, 13, 19, 0))).toBe('2026-10-14');    // 04:00 in Tokyo
    expect(r.events).toContainEqual({ kind: 'home', action: 'chosen', city: TOKYO, from: SF, spot: 1, dropped: [] });
    expect(run(opened, r.state, { type: 'choose_home', city: NYC, spot: 0 })).toMatchObject({ ok: false, code: 'home_chosen' });
  });

  it('refuses a city that is not open, and a spot that is not 0–2', () => {
    expect(run(c, freshState(c, 'player-pick-02', T0, 7, { pending: true }), { type: 'choose_home', city: OSAKA, spot: 0 }))
      .toMatchObject({ ok: false, code: 'home_not_open', detail: { status: 'not_open' } });
    expect(run(opened, pending(), { type: 'choose_home', city: TOKYO, spot: 3 })).toMatchObject({ ok: false, code: 'bad_spot' });
    expect(run(opened, freshState(opened, 'player-old-0003', T0, 3), { type: 'choose_home', city: TOKYO, spot: 0 }))
      .toMatchObject({ ok: false, code: 'home_chosen' });   // a save that never asked (San Francisco's) has chosen
  });

  it('a home on the list reads its set: Stamp Run places, the fish pin, the view', () => {
    const s = picked(), set = citySet(c, TOKYO)!;
    expect(visitPlaces(opened, 'market', s)).toEqual([set.tackle, set.tea, set.post]);
    const fish = [...pondFishIds(c, set.pond)];
    expect(fish.length).toBeGreaterThan(0);
    expect(pondFor(opened, s, fish.slice(0, 1))).toBe(set.pond);
    expect((viewOf(opened, s, T0) as unknown as { home: unknown }).home).toMatchObject({ city: TOKYO, pending: false, set });
  });
});

describe('change_home: once, within 7 days or before Homestead Lv2 (q(161))', () => {
  it('moves the farm and counts the change; a second is refused', () => {
    const r = run(opened, picked(TOKYO, 1), { type: 'change_home', city: NYC, spot: 2 }, T0 + DAY);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.travel).toMatchObject({ home: NYC, here: NYC, home_set: citySet(c, NYC), home_changes: 1, home_chosen_at: T0 + DAY });
    expect(r.state.travel.visits[TOKYO]).toMatchObject({ n: 1, first_at: T0 });   // the old home is a city visited (④)
    const v = viewOf(opened, r.state, T0 + DAY) as unknown as { home: { change: { open: boolean; used: number } } };
    expect(v.home.change).toMatchObject({ open: false, used: 1 });
    expect(run(opened, r.state, { type: 'change_home', city: TOKYO, spot: 0 }, T0 + DAY)).toMatchObject({ ok: false, code: 'home_set_for_good' });
  });

  it('closes after 7 days, at Homestead Lv2, and is not offered before the first pick', () => {
    const s = picked();
    expect(run(opened, structuredClone(s), { type: 'change_home', city: NYC, spot: 0 }, T0 + 7 * DAY))
      .toMatchObject({ ok: false, code: 'home_set_for_good', detail: { until: T0 + 7 * DAY } });
    const lv2 = structuredClone(s);
    lv2.homestead.level = 2;
    expect(run(opened, lv2, { type: 'change_home', city: NYC, spot: 0 }, T0 + DAY)).toMatchObject({ ok: false, code: 'home_set_for_good' });
    expect(run(opened, pending(), { type: 'change_home', city: NYC, spot: 0 })).toMatchObject({ ok: false, code: 'home_set_for_good' });
    const open = viewOf(opened, s, T0 + DAY) as unknown as { home: { change: Record<string, unknown> } };
    expect(open.home.change).toEqual({ open: true, until: T0 + 7 * DAY, before_level: 2, used: 0 });
  });

  it('drops, free, an accepted resident request whose resident does not live in the new home; Pip\'s stays', () => {
    const away = Object.keys(c.residents).find(id => id !== 'res_pip' && livesIn(c, SF, id) && !livesIn(c, LONDON, id))!;
    expect(away).toBeTruthy();
    const s = freshState(opened, 'player-pick-03', T0, 7);   // San Francisco's, never asked
    s.residents[away] = { affinity: 0, chat_day: '', gift_day: '', next: 0, req: { id: 'req_away', at: T0, progress: 0 }, done_day: '' };
    s.residents.res_pip = { affinity: 0, chat_day: '', gift_day: '', next: 0, req: { id: 'req_pip', at: T0, progress: 0 }, done_day: '' };
    const coins = s.coins;
    const r = run(opened, s, { type: 'change_home', city: LONDON, spot: 0 }, T0 + DAY);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.residents[away].req).toBeNull();
    expect(r.state.residents.res_pip.req?.id).toBe('req_pip');
    expect(r.state.coins).toBe(coins);
    expect(r.events).toContainEqual(expect.objectContaining({ kind: 'home', action: 'changed', from: SF, city: LONDON, dropped: ['req_away'] }));
  });

  it('a Day Pass for the new home goes (home needs none); a line out at an old pond comes in', () => {
    const s = freshState(opened, 'player-pick-04', T0, 7);
    s.travel.passes[NYC] = { kind: 'day', from: T0, until: T0 + DAY };
    s.cast = { place: 'pond_san_francisco_03', site: 'pond' } as unknown as P0State['cast'];
    const r = run(opened, s, { type: 'change_home', city: NYC, spot: 0 }, T0 + 3_600_000);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.travel.passes[NYC]).toBeUndefined();
    expect(r.state.cast).toBeNull();
  });
});

describe('routes (SGODOT-303)', () => {
  const app = Fastify();
  registerP0Routes(app, { content: opened, store: new P0Store(opened), now: () => T0, dev: true });
  const headers = { 'x-p0-player': 'player-route-01' };

  it('a client that can pick sends x-p0-features: choose_home and its new save asks', async () => {
    const asks = (await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { ...headers, 'x-p0-features': 'choose_home' } })).json();
    expect(asks.state.home.pending).toBe(true);
    const old = (await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { 'x-p0-player': 'player-route-02' } })).json();
    expect(old.state.home.pending).toBe(false);
  });

  it('lists cities, offers spots, takes the pick', async () => {
    const list = (await app.inject({ method: 'GET', url: '/v1/p0/home/cities?q=new', headers })).json();
    expect(list.open.map((r: { id: string }) => r.id)).toEqual([SF, TOKYO, NYC, LONDON]);
    expect(list.matches.some((r: { id: string; status: string }) => r.id === NYC && r.status === 'open')).toBe(true);
    const spots = (await app.inject({ method: 'GET', url: `/v1/p0/home/spots/${NYC}`, headers })).json();
    expect(spots).toEqual({ ok: true, city: NYC, spots: homeSpots(opened, NYC, 'player-route-01') });
    const shut = (await app.inject({ method: 'GET', url: '/v1/p0/home/spots/gn-1796236', headers })).json();
    expect(shut).toMatchObject({ ok: false, code: 'home_not_open', detail: { status: 'not_open' } });
    expect((await app.inject({ method: 'GET', url: '/v1/p0/home/spots/gn-0', headers })).statusCode).toBe(404);
    const done = (await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'choose_home', city: NYC, spot: 2 } })).json();
    expect(done.ok).toBe(true);
    expect(done.state.home).toMatchObject({ city: NYC, pending: false });
  });
});
