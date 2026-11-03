/** v4q(3) (SGODOT-355): wild sites — the offline catalogue's raster and guarantees, the server's catalogue, the nearest 3
 * free with a quarry and a vein, and the map's viewport read (contract-c §2–§4). */
import Fastify from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { homeBase } from '../../src/p0/home.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { preview } from '../../src/p0/travel.js';
import { freshState } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { catalogueOf, parseBbox, useCatalogue, viewport, VIEWPORT_CAP, wildById, wildNearOf } from '../../src/p0/wild.js';
import { worldOf } from '../../src/p0/world.js';
import { guarantee, nameSites, Raster, type Site, type WildConfig } from '../../tools/wild_sites_lib.js';

const SF = 'gn-5391959', T = Date.parse('2026-11-02T18:00:00Z'), G = 0.5;
const TYPES = ['quarry', 'vein', 'geode', 'abyss', 'ruin', 'woodland', 'waterside', 'bloom'];
const FIELDS = ['row', 'col', 'lat', 'lng', 'type', 'main', 'side', 'floors', 'coastal', 'near', 'word', 'country'];
const cellOf = (lat: number, lng: number) => [Math.floor((lat + 90) / G), Math.floor((lng + 180) / G)];

/** A table of sites at (dLat, dLng) from a point, of the given types, stamped for this world (or another). */
function table(c: P0Content, from: { lat: number; lng: number }, sites: [number, number, string, string?][], seed?: string) {
  const w = worldOf(c)!;
  return { seed: seed ?? w.seed, revision: w.revision, grid_deg: G, types: TYPES, fields: FIELDS,
    rows: sites.map(([dLat, dLng, type, main], i) => {
      const lat = from.lat + dLat, lng = from.lng + dLng, [row, col] = cellOf(lat, lng);
      const mine = type === 'quarry' || type === 'vein' || type === 'geode';
      return [row, col, lat, lng, TYPES.indexOf(type), type === 'vein' ? main ?? null : null, mine ? i % 8 : null, mine ? 30 : null, 0, SF, `W${i}`, 'US'];
    }) };
}

let content: P0Content | null = null;
afterEach(() => { if (content) useCatalogue(content, null); content = null; });
const setup = (rows: [number, number, string, string?][]) => {
  const c = loadP0Content(); content = c;
  const base = homeBase(c, { travel: { home: SF } })!;
  useCatalogue(c, catalogueOf(c, table(c, base, rows)));
  return { c, base };
};

describe('the offline catalogue (tools/wild_sites_lib.ts)', () => {
  it('rasters a polygon even–odd, its hole left out', () => {
    const square = [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]], [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]]];
    const r = new Raster(0.5).fill([square]);
    expect(r.get(2, 2)).toBe(1);
    expect(r.get(5, 5)).toBe(0);     // the hole
    expect(r.get(12, 2)).toBe(0);
    expect(r.clear(2, 2, 1)).toBe(true);
    expect(r.clear(0.1, 2, 1)).toBe(false);   // a cell from the edge
    expect(r.within(12, 5, 300, 1)).toBe(true);
  });

  it('turns the nearest loose sites into veins of different main and quarries of different side near a cluster, and locks them', () => {
    const cfg = { grid_deg: G, near: { trip2_km: 100, quarry: 2, vein: 2, geode_km: 500 }, abyss: [1, 1], ruin: 1, sides: 4,
      mines: { quarry: { floors: [20, 30], mains: ['stone', 'copper_ore'], main_from: 1 }, vein: { floors: [40, 60], mains: ['iron_ore', 'quartz'], one_main: true, main_from: 10, open_to: 40 },
        geode: { floors: [50, 80], mains: ['gem'], main_from: 10 }, abyss: { floors: [100, 150], mains: ['core'], main_from: 20 }, ruin: { floors: [30, 30], mains: ['relic'], main_from: 10 } },
    } as unknown as WildConfig;
    const sites: Site[] = [];
    for (let i = 0; i < 9; i++) {
      const lat = 10.25 + Math.floor(i / 3) * G, lng = 20.25 + (i % 3) * G, [row, col] = cellOf(lat, lng);
      sites.push({ id: `wd-${row}-${col}`, row, col, lat, lng, type: i === 0 ? 'quarry' : 'woodland', main: null, side: i === 0 ? 1 : null, floors: null,
        coastal: false, wet: false, near: 'x', climate: 'temperate', continent: 'asia', country: 'CN', word: '', locked: false });
    }
    const cl = { id: 'gn-1', name: 'Here', lat: 10.75, lng: 20.75, population: 1e6, climate: 'temperate', continent: 'asia' } as never;
    const short = guarantee(cfg, 'seed', sites, [cl]);
    expect(short.filter(x => x.need !== 'geode')).toEqual([]);
    const quarries = sites.filter(s => s.type === 'quarry');
    expect(quarries).toHaveLength(2);
    expect(new Set(quarries.map(s => s.side)).size).toBe(2);           // told apart by the side yield
    expect(quarries.every(s => s.main === null)).toBe(true);            // a quarry yields every main (review B3)
    expect(sites.filter(s => s.type === 'vein').map(s => s.main).sort()).toEqual(['iron_ore', 'quartz']);
    expect(sites.filter(s => s.type === 'quarry' || s.type === 'vein').every(s => s.locked)).toBe(true);
    expect(sites.filter(s => s.type === 'ruin')).toHaveLength(1);
  });

  it('names the sites nearest a cluster with words its gathering points have not taken, and never twice (v4q(4) f77fd19b)', () => {
    const sites: Site[] = Array.from({ length: 4 }, (_, i) => ({ id: `wd-200-${i}`, row: 200, col: i, lat: 10, lng: 20 + i * 0.5,
      type: 'quarry', main: null, side: 0, floors: 25, coastal: false, wet: false, near: 'gn-1', climate: 'temperate', continent: 'asia',
      country: 'CN', word: '', locked: false }) as Site);
    const cfg = { type_words: {} } as unknown as WildConfig;
    nameSites(cfg, 'seed', sites, { Temperate: ['Fox', 'Wolf', 'Boar', 'Stag', 'Owl', 'Hare'] }, new Map([['gn-1', new Set(['Fox', 'Wolf'])]]));
    const used = sites.map(s => s.word);
    expect(new Set(used).size).toBe(4);
    expect(used.some(w => w === 'Fox' || w === 'Wolf')).toBe(false);
  });
});

describe('the server catalogue (src/p0/wild.ts)', () => {
  it('refuses a table made for another world', () => {
    const c = loadP0Content();
    expect(() => catalogueOf(c, table(c, { lat: 0, lng: 0 }, [[0, 0, 'quarry', 'stone']], 'another-seed'))).toThrow(/rerun tools\/wild_sites_build/);
  });

  it('names a site by its word and type, and opens quarries and veins only', () => {
    const { c, base } = setup([[0.6, 0, 'vein', 'quartz'], [0, 0.8, 'woodland']]);
    const [row, col] = cellOf(base.lat + 0.6, base.lng);
    expect(wildById(c, `wd-${row}-${col}`)).toMatchObject({ name: 'W0 Vein', short: 'W0', open: true, country: 'US',
      mine: { main: 'quartz', yields: ['quartz'], main_from: 10, open_to: 40 } });
    const [r2, c2] = cellOf(base.lat, base.lng + 0.8);
    expect(wildById(c, `wd-${r2}-${c2}`)).toMatchObject({ type: 'woodland', open: false });
    expect(wildById(c, 'gn-5391959')).toBeUndefined();
  });

  it('the free 3 are the nearest quarry, iron vein and quartz vein, however far (the user, 11-02 庚3, v4q(3) ③)', () => {
    const { c, base } = setup([[0.5, 0, 'quarry', 'stone'], [0, 0.8, 'quarry', 'coal'], [-1, 0, 'quarry', 'clay'],
      [0, -0.6, 'woodland'], [2, 2, 'vein', 'iron_ore'], [1.5, 1.5, 'vein', 'iron_ore'], [-6, -6, 'vein', 'quartz']]);
    const near = wildNearOf(c, SF).map(id => wildById(c, id)!);
    expect(near.map(s => [s.type, s.mine?.main ?? null])).toEqual([['quarry', null], ['vein', 'iron_ore'], ['vein', 'quartz']]);   // nearest first (a quarry has no main)
    const [r2, c2] = cellOf(base.lat + 1.5, base.lng + 1.5);
    expect(near[1].id).toBe(`wd-${r2}-${c2}`);   // the nearer iron vein
    expect(near.some(s => s.type === 'woodland')).toBe(false);   // not open: never one of the free 3
    // no quartz vein anywhere: the two that there are
    const { c: c2nd } = setup([[0.5, 0, 'quarry', 'stone'], [2, 2, 'vein', 'iron_ore']]);
    expect(wildNearOf(c2nd, SF).map(id => wildById(c2nd, id)!.type)).toEqual(['quarry', 'vein']);
  });

  it('reads a viewport: open sites and grey pins, nearest home first, at most the cap, none below the pins\' zoom', () => {
    const rows: [number, number, string, string?][] = [];
    for (let i = 0; i < 60; i++) rows.push([-3 + Math.floor(i / 10) * G, -3 + (i % 10) * G, i % 2 ? 'vein' : 'quarry', i % 2 ? 'quartz' : 'stone']);
    rows.push([0.25, 0.25, 'bloom'], [0.3, -0.3, 'geode']);
    const { c, base } = setup(rows);
    const s = freshState(c, 'wild-1', T);
    const box = { south: base.lat - 4, west: base.lng - 4, north: base.lat + 4, east: base.lng + 4 };
    const got = viewport(c, s, box, 9, T);
    expect(got.total).toBe(61);                                       // 60 mines and the grey geode; no bloom
    expect(got.sites).toHaveLength(VIEWPORT_CAP);
    expect(got.capped).toBe(true);
    expect(got.sites.some(x => x.type === 'bloom')).toBe(false);
    expect(got.sites.find(x => x.type === 'geode')).toMatchObject({ open: false, free: false });
    const kms = got.sites.map(x => x.km);
    expect(kms).toEqual([...kms].sort((a, b) => a - b));               // nearest the home's base first
    expect(viewport(c, s, box, 8, T).sites).toEqual([]);               // below map_min_zoom (9)
  });

  it('reads a box over the 180° line and refuses one that is not a box', () => {
    expect(parseBbox('10,170,20,-170')).toEqual({ south: 10, west: 170, north: 20, east: -170 });
    expect(parseBbox('20,0,10,5')).toBeNull();
    expect(parseBbox('a,b,c,d')).toBeNull();
    expect(parseBbox('0,-180,10,180')).toBeNull();     // the whole way round: wider than BBOX_MAX_DEG (周瑜 on #616)
    expect(parseBbox('-30,0,30,5')).toBeNull();
    expect(parseBbox('10,-10,30,10')).toEqual({ south: 10, west: -10, north: 30, east: 10 });   // 20° each way is the most
    const c = loadP0Content(); content = c;
    const w = worldOf(c)!;
    const rows = [[Math.floor((15 + 90) / G), Math.floor((179.6 + 180) / G), 15.2, 179.6, 0, null, 0, 25, 0, SF, 'East', 'FJ'],
      [Math.floor((15 + 90) / G), Math.floor((-179.6 + 180) / G), 15.2, -179.6, 1, 'quartz', 0, 45, 0, SF, 'West', 'FJ']];
    useCatalogue(c, catalogueOf(c, { seed: w.seed, revision: w.revision, grid_deg: G, types: TYPES, fields: FIELDS, rows }));
    const got = viewport(c, freshState(c, 'wild-2', T), parseBbox('10,170,20,-170')!, 9, T);
    expect(got.sites.map(x => x.short).sort()).toEqual(['East', 'West']);
  });

  it('GET /v1/p0/wild sends the viewport with the catalogue revision, 400 without a box', async () => {
    const { c, base } = setup([[0.5, 0, 'quarry', 'stone'], [0, 0.8, 'vein', 'iron_ore']]);
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => T, dev: false });
    const headers = { 'x-p0-player': 'wild-route-1' };
    const bbox = `${base.lat - 2},${base.lng - 2},${base.lat + 2},${base.lng + 2}`;
    const res = await app.inject({ method: 'GET', url: `/v1/p0/wild?bbox=${bbox}&zoom=9`, headers });
    expect(res.headers['x-wild-revision']).toBe(String(worldOf(c)!.revision));
    const body = res.json();
    expect(body).toMatchObject({ ok: true, capped: false, total: 2 });
    expect(body.sites.map((x: { type: string }) => x.type).sort()).toEqual(['quarry', 'vein']);
    expect(body.sites[0]).toMatchObject({ free: true, visited: false, pass_until: null, trip: expect.any(Number) });
    expect((await app.inject({ method: 'GET', url: '/v1/p0/wild?zoom=9', headers })).statusCode).toBe(400);
    // below the pins' zoom: an empty list, even for a box too wide to read (周瑜 on #616)
    expect((await app.inject({ method: 'GET', url: '/v1/p0/wild?bbox=-60,-180,60,180&zoom=5', headers })).json()).toEqual({ ok: true, sites: [], capped: false, total: 0 });
    await app.close();
  });

  it("each site carries its fare as the travel card has it (cost: free ones 0, the others the card's; 亚瑟, C part 2)", async () => {
    const { c, base } = setup([[0.5, 0, 'quarry', 'stone'], [0, 0.8, 'vein', 'iron_ore'], [0, -0.8, 'vein', 'quartz'],
      [1.0, 0, 'quarry', 'stone'], [1.5, 0, 'quarry', 'stone'], [-1.5, 0.5, 'quarry', 'stone']]);
    const store = new P0Store(c), app = Fastify();
    registerP0Routes(app, { content: c, store, now: () => T, dev: false });
    const headers = { 'x-p0-player': 'wild-route-cost' };
    const bbox = `${base.lat - 2},${base.lng - 2},${base.lat + 2},${base.lng + 2}`;
    const body = (await app.inject({ method: 'GET', url: `/v1/p0/wild?bbox=${bbox}&zoom=9`, headers })).json();
    const s = store.get('wild-route-cost', T);
    type Row = { id: string; free: boolean; cost: { energy: number; coins: number } };
    for (const x of body.sites as Row[]) {
      const card = preview(c, s, x.id, T + s.clock_ms).cost;
      expect(x.cost).toEqual({ energy: card.energy, coins: card.coins });
      if (x.free) expect(x.cost).toEqual({ energy: 0, coins: 0 });
    }
    expect((body.sites as Row[]).some(x => !x.free && x.cost.energy + x.cost.coins > 0)).toBe(true);   // a priced one is in
    await app.close();
  });
});
