/** v4q(4) (SGODOT-355): the city gathering points' table — this world's only, a point's id, name and yield from the content,
 * and the city read sending a city's points, the written city's too (contract-c §9). */
import Fastify from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { gatherCatalogueOf, gatherPointById, gatherPointsOf, useGatherCatalogue } from '../../src/p0/gather_points.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';
import { worldOf } from '../../src/p0/world.js';

const SF = 'gn-5391959', TOKYO = 'gn-1850147', T = Date.parse('2026-11-02T18:00:00Z');
const FIELDS = ['cluster', 'kind', 'n', 'lat', 'lng', 'word'];

let content: P0Content | null = null;
afterEach(() => { if (content) useGatherCatalogue(content, null); content = null; });
const table = (c: P0Content, rows: unknown[][], seed?: string) => ({ seed: seed ?? worldOf(c)!.seed, revision: worldOf(c)!.revision, fields: FIELDS, rows });

describe('city gathering points (src/p0/gather_points.ts)', () => {
  it('refuses a table made for another world', () => {
    const c = loadP0Content();
    expect(() => gatherCatalogueOf(c, table(c, [[SF, 'wood', 0, 37.76, -122.43, 'Badger']], 'another-seed'))).toThrow(/rerun tools\/gather_points_build/);
  });

  it('a point is <cluster>~<kind><n>, named by its word and the kind, giving what the content says', () => {
    const c = loadP0Content(); content = c;
    useGatherCatalogue(c, gatherCatalogueOf(c, table(c, [[SF, 'reed', 1, 37.77, -122.41, 'Heron'], [SF, 'hardwood', 0, 37.74, -122.45, 'Fox'],
      [TOKYO, 'wood', 0, 35.7, 139.7, 'Plum'], [SF, 'no_such_kind', 0, 37.7, -122.4, 'Owl']])));
    expect(gatherPointById(c, `${SF}~reed1`)).toMatchObject({ kind: 'reed', tier: 'T1', name: 'Heron Reed Bank', short: 'Heron',
      yield: [['fiber', 4], ['bait_worm', 2]], energy: 3, cooldown_h: 4 });
    expect(gatherPointById(c, `${SF}~hardwood0`)).toMatchObject({ tier: 'T2', name: 'Fox Woods', yield: [['hardwood', 3]] });
    expect(gatherPointsOf(c, SF).map(p => p.id)).toEqual([`${SF}~reed1`, `${SF}~hardwood0`]);   // a kind the content lost is left out
    expect(gatherPointsOf(c, 'gn-1')).toEqual([]);
  });

  it('GET /v1/p0/city/:cluster sends the city\'s points, the written city\'s too', async () => {
    const c = loadP0Content(); content = c;
    useGatherCatalogue(c, gatherCatalogueOf(c, table(c, [[SF, 'wood', 0, 37.76, -122.43, 'Badger'], [TOKYO, 'stone', 0, 35.7, 139.7, 'Plum']])));
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => T, dev: false });
    const headers = { 'x-p0-player': 'gather-route-1' };
    const sf = (await app.inject({ method: 'GET', url: `/v1/p0/city/${SF}`, headers })).json();
    expect(sf.city.gather).toEqual([expect.objectContaining({ id: `${SF}~wood0`, name: 'Badger Grove' })]);
    const tokyo = (await app.inject({ method: 'GET', url: `/v1/p0/city/${TOKYO}`, headers })).json();
    expect(tokyo.city.gather.map((p: { name: string }) => p.name)).toEqual(['Plum Rocks']);
    await app.close();
  });

  it('U2: a client that says pond_guide gets no town points, and gathering one is bad_spot; an older one keeps them (奕星, a)', async () => {
    const c = loadP0Content(); content = c;
    useGatherCatalogue(c, gatherCatalogueOf(c, table(c, [[SF, 'wood', 0, 37.76, -122.43, 'Badger']])));
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => T, dev: false });
    const old = { 'x-p0-player': 'gather-route-u2' }, ponds = { ...old, 'x-p0-features': 'guide_v3,wing8,pond_guide' };
    expect((await app.inject({ method: 'GET', url: `/v1/p0/city/${SF}`, headers: ponds })).json().city.gather).toEqual([]);
    expect((await app.inject({ method: 'GET', url: `/v1/p0/city/${SF}`, headers: old })).json().city.gather).toHaveLength(1);
    const gather = (headers: Record<string, string>) => app.inject({ method: 'POST', url: '/v1/p0/commands', headers,
      payload: { type: 'gather', spot: `${SF}~wood0`, space: 'home' } }).then(r => r.json());
    expect(await gather(ponds)).toMatchObject({ ok: false, code: 'bad_spot' });
    expect(await gather(old)).toMatchObject({ ok: true });
    await app.close();
  });
});
