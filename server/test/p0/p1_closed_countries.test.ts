/** q(189), SGODOT-305: North Korean cities do not open. The city table the game reads skips them (content.ts), so no
 * map, search, Nearby or fallback list has them and they cannot be travelled to or picked; their generated places
 * stay as they are (world.revision unchanged). A save that ever referred to one is handled on load. */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { CityClusters } from '../../src/p0/clusters.js';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { clusterById, clustersOf } from '../../src/p0/home.js';
import { homeCities, homeStatus } from '../../src/p0/home_city.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState, upgradeState } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { fallbackOf, rankedCities, settleExplorer } from '../../src/p0/travel.js';
import { cityPlaces, generateCity } from '../../src/p0/world.js';
import { viewOf } from '../../src/p0/view.js';

const c: P0Content = loadP0Content();
const full = CityClusters.load();
const T = Date.UTC(2026, 9, 14, 1);
const PYONGYANG = 'gn-1871859', KAESONG = 'gn-1876373', SEOUL = 'gn-1835848', GANGHWA = 'gn-1843163', JIAN = 'gn-2036579', DANDONG = 'gn-2037886';
const kp = [...full.byId.values()].filter(cl => cl.country_code === 'KP');

describe('closed countries (q(189))', () => {
  it('the content closes KP; the game\'s table has none of its 41 clusters, the full table keeps them', () => {
    expect(c.travel?.closed_countries).toEqual(['KP']);
    expect(kp).toHaveLength(41);
    for (const cl of kp) expect(clusterById(c, cl.id), cl.name).toBeUndefined();
    expect(clustersOf(c)!.byId.size).toBe(full.byId.size - 41);
    // the two foreign towns once inside North Korean clusters stay open (q(191))
    for (const id of [GANGHWA, JIAN, SEOUL, DANDONG]) expect(clusterById(c, id), id).toBeDefined();
  });

  it('no world is served for them, though their places are what they were (no revision change)', () => {
    expect(cityPlaces(c, PYONGYANG)).toBeNull();
    expect(generateCity(c, full.get(PYONGYANG)!).detail.ponds.length).toBeGreaterThan(0);
  });

  it('not a home, not in a search, not in a ranking or a fallback list', () => {
    expect(homeStatus(c, PYONGYANG)).toBeNull();
    expect(homeCities(c, 'pyong').matches).toEqual([]);   // no grey row either (q(189) ①)
    const s = freshState(c, 'player-kp-0001', T, 1);
    s.travel = { ...s.travel, home: SEOUL, here: SEOUL, home_chosen_at: T, fallback: fallbackOf(c, SEOUL) };
    const ids = new Set(kp.map(cl => cl.id));
    expect(rankedCities(c, s).some(r => ids.has(r.id))).toBe(false);
    expect([...s.travel.fallback.near3, ...s.travel.fallback.near10].some(id => ids.has(id))).toBe(false);
    expect(s.travel.fallback.near3).not.toContain(KAESONG);
  });

  it('travel there is refused and its city read is a 404', async () => {
    const s = freshState(c, 'player-kp-0002', T, 1);
    expect(applyP0(c, s, { type: 'travel', to: PYONGYANG } as unknown as P0Command, T)).toMatchObject({ ok: false });
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => T, dev: false });
    const r = await app.inject({ method: 'GET', url: `/v1/p0/city/${PYONGYANG}`, headers: { 'x-p0-player': 'player-kp-0003' } });
    expect(r.statusCode).toBe(404);
  });

  it('a save that once went there: home again, the pass gone, a check-in request there dropped; visits and stamps kept, never shown or counted', () => {
    const s = freshState(c, 'player-kp-0004', T - 86_400_000, 1);
    s.travel.here = PYONGYANG;
    s.travel.passes[PYONGYANG] = { kind: 'day', from: T - 3_600_000, until: T + 3_600_000 };
    s.travel.visits[PYONGYANG] = { n: 1, first_at: T - 3_600_000, last_at: T - 3_600_000, deliveries: 0, delivered_day: '' };
    s.travel.stamps.push({ cluster: PYONGYANG, kind: 'climate', at: T - 3_600_000, counted_on: '2026-10-12' });
    s.presence.place = `${PYONGYANG}~pond0`;
    s.boards.market = [{ req: { id: 'req_x', status: 'accepted', visit: { place: `${PYONGYANG}~tea0`, done: false } } as never, refill_at: 0 }];
    const up = upgradeState(c, structuredClone(s), T);
    expect(up.travel.here).toBe(up.travel.home);
    expect(up.travel.passes[PYONGYANG]).toBeUndefined();
    expect(up.presence.place).toBeNull();
    expect(up.boards.market[0].req).toBeNull();
    expect(up.travel.visits[PYONGYANG]).toBeDefined();   // kept in the save
    expect(up.travel.stamps.some(x => x.cluster === PYONGYANG)).toBe(true);
    const shown = (viewOf(c, up, T) as unknown as { travel: { visits: Record<string, unknown>; stamps: { cluster: string }[] } }).travel;
    expect(shown.visits[PYONGYANG]).toBeUndefined();
    expect(shown.stamps.some(x => x.cluster === PYONGYANG)).toBe(false);
    // three stamps would earn Explorer 3: with one of them in a closed city it is not earned
    up.travel.stamps.push({ cluster: SEOUL, kind: 'climate', at: T, counted_on: '2026-10-12' }, { cluster: DANDONG, kind: 'climate', at: T, counted_on: '2026-10-12' });
    settleExplorer(c, up, T, []);
    expect(up.travel.explorer).toBe(0);
  });
});
