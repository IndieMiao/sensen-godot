/** SGODOT-278 / 280: GET /v1/p0/city/:cluster passes a generated city's places through (detail included); home stays hand-written. */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';
import type { CityInfo } from '../../src/p0/travel.js';

const TOKYO = 'gn-1850147', SF = 'gn-5391959';
const T = Date.parse('2026-10-10T18:00:00Z');

describe('GET /v1/p0/city/:cluster with a generator (SGODOT-280)', () => {
  it('a foreign city comes from cityPlaces, detail and all; the home city from the hand-written tables', async () => {
    const c: P0Content = loadP0Content();
    const asked: string[] = [];
    const gen = (id: string): CityInfo => { asked.push(id); return { ponds: [`${id}~pond0`], outposts: [`${id}~cabin0`], residents: 2,
      fish: [{ fish: 'fish_crucian', level: 1 }], detail: { ponds: [{ id: `${id}~pond0`, name: 'Sumida Pond' }], outposts: [] } }; };
    Object.defineProperty(c, 'cityPlaces', { value: gen, enumerable: false });
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => T, dev: false });
    const headers = { 'x-p0-player': 'city-route-1' };
    const tokyo = (await app.inject({ method: 'GET', url: `/v1/p0/city/${TOKYO}`, headers })).json();
    expect(tokyo).toMatchObject({ ok: true, city: { ponds: [`${TOKYO}~pond0`], residents: 2,
      detail: { ponds: [{ name: 'Sumida Pond' }] }, preview: { cluster: TOKYO, counts: { ponds: 1, outposts: 1, residents: 2 } } } });
    const home = (await app.inject({ method: 'GET', url: `/v1/p0/city/${SF}`, headers })).json();
    expect(home.city.ponds.length).toBeGreaterThan(0);
    expect(asked).not.toContain(SF);
    await app.close();
  });
});
