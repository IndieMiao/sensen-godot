/** SGODOT-280: global generation — a city cluster's ponds and outposts from the world seed and the cluster id (plan v2
 * §9.3.2 outposts, §6.3.3 ponds), the same every time; the home city keeps its hand-written tables. */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { everFish } from '../../src/p0/fishing_world.js';
import type { CityCluster } from '../../src/p0/clusters.js';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState } from '../../src/p0/state.js';
import { clusterOf } from '../../src/p0/travel.js';
import { applyOverrides, applyWater, cityPlaces, clusterPopulation, generateCity, km, placeOf, pondCount, tierOf, waterTable,
  type CityPlaces, type PlaceFix, type WorldContent } from '../../src/p0/world.js';

const c: P0Content = loadP0Content();
const w = (c as P0Content & { world: WorldContent }).world;
const clusters = (c as P0Content & { clusters: { get(id: string): CityCluster | undefined; byId: Map<string, CityCluster> } }).clusters;
const SF = 'gn-5391959', LA = 'gn-5368361', SHANGHAI = 'gn-1796236', BEIJING = 'gn-1816670', NYC = 'gn-5128581', TOKYO = 'gn-1850147';
const T = Date.parse('2026-10-10T18:00:00Z');

/** A made-up cluster of `population` at (lat, lng), for the tier and count rules. */
const fake = (population: number, lat = 40, climate: CityCluster['climate'] = 'temperate'): CityCluster => ({
  id: `gn-test${population}`, name: 'Testville', lat, lng: 10, country_code: 'XX', country: 'Test', population,
  members: 1, climate, continent: 'europe', timezone: 'UTC' });

describe('global generation (SGODOT-280)', () => {
  it('is deterministic: the same cluster gives the same places on every call and after a reload', () => {
    const again = loadP0Content();
    for (const id of [TOKYO, SHANGHAI, 'gn-463835']) {
      expect(generateCity(again, clusters.get(id)!)).toEqual(generateCity(c, clusters.get(id)!));
      expect(cityPlaces(c, id)).toBe(cityPlaces(c, id));   // cached
    }
  });

  it('never generates the home city: San Francisco keeps p0_ponds.json / p0_outposts.json, each with its cluster', () => {
    expect(cityPlaces(c, SF)).toBeNull();
    expect(cityPlaces(c, 'gn-nope')).toBeNull();
    for (const id of Object.keys(c.fishing.places)) expect(c.fishing.places[id].cluster).toBe(SF);
    for (const o of c.outposts ?? []) expect(o.cluster).toBe(SF);
    expect(clusterOf(c, 'pond_san_francisco_03')).toBe(SF);
    expect(clusterOf(c, 'sh_tea_1')).toBe(SF);
  });

  it('tiers by the members\' summed population (q(114) ①), raised by the area list (q(114) ②)', () => {
    expect([400_000, 1_000_000, 2_000_000, 5_000_000, 10_000_000, 20_000_000].map(p => tierOf(w, fake(p))))
      .toEqual(['S', 'M1', 'M2', 'L1', 'L2', 'L3']);
    expect(tierOf(w, clusters.get(LA)!)).toBe('L3');      // 3.8 M people: L1 by population
    expect(tierOf(w, clusters.get(TOKYO)!)).toBe('L3');
    expect(tierOf(w, clusters.get(SHANGHAI)!)).toBe('L3');
    expect(tierOf(w, clusters.get(NYC)!)).toBe('L3');     // q(114) ② area list
    // Miami: 487,014 alone, 780,231 with its members — an M1 metro by people, L3 by the area list, never an S-tier town
    expect(clusterPopulation(clusters.get('gn-4164138')!)).toBe(780_231);
    expect(tierOf(w, clusters.get('gn-4164138')!)).toBe('L3');
    expect(clusterPopulation(clusters.get(SF)!)).toBeGreaterThan(clusters.get(SF)!.population);   // Oakland, Hayward
  });

  it('gives 3 ponds, one more per 500,000 people, at most 6; the first is the beginner Pond nearest the centre', () => {
    expect([100_000, 999_999, 1_000_000, 1_600_000, 9_000_000].map(p => pondCount(w, fake(p)))).toEqual([3, 3, 4, 5, 6]);
    for (const id of [LA, SHANGHAI, BEIJING, NYC, TOKYO, 'gn-463835']) {
      const city = cityPlaces(c, id)!, cl = clusters.get(id)!;
      const [first, ...rest] = city.detail.ponds;
      expect(first).toMatchObject({ id: `${id}~pond0`, site: 'pond', beginner: true });
      expect(rest.every(p => !p.beginner)).toBe(true);
      expect(Math.min(...rest.map(p => km(cl, p)))).toBeGreaterThanOrEqual(km(cl, first) - 0.01);
      expect(city.detail.ponds[1].site).toBe('river');
      expect(new Set(city.detail.ponds.map(p => p.name)).size).toBe(city.detail.ponds.length);
      for (const p of city.detail.ponds) expect(['crescent', 'gourd', 'meander']).toContain(p.template_id);
      // the crucian is always in the beginner pond
      expect(everFish(c, c.fishing.sites[first.site], id).map(f => f.id)).toContain('fish_crucian');   // pools by habitat (SGODOT-283)
    }
  });

  it('lays out outposts by the §9.3.2 counts and rules, for every cluster', () => {
    let checked = 0;
    for (const cl of clusters.byId.values()) {
      const city = cityPlaces(c, cl.id);
      if (!city) continue;
      checked++;
      const o = city.detail.outposts, beginner = city.detail.ponds[0];
      if (city.tier === 'S') {
        expect(o).toHaveLength(1);
        expect(o[0]).toMatchObject({ id: `${cl.id}~cabin0`, cabin: true });
        continue;
      }
      const row = w.tiers.find(t => t.tier === city.tier)!;
      const count = (r: string) => o.filter(x => x.role === r).length;
      expect(count('tea')).toBe(row.tea);
      expect(count('market')).toBe(row.market);
      expect(count('post')).toBe(row.travel);
      expect(count('tackle')).toBeGreaterThanOrEqual(1);
      expect(count('tackle')).toBeLessThanOrEqual(Math.min(row.tackle_max!, city.ponds.length));
      for (const a of o) for (const b of o) {
        if (a === b) continue;
        expect(km(a, b)).toBeGreaterThanOrEqual(a.role === b.role ? 3 - 1e-6 : 0.3 - 1e-6);
      }
      // q(144): a pond is a place of another kind — every outpost ≥ 300 m from every pond, a tackle shop 100–300 m from
      // its own (Market Square 2 used to stand on pond 5 in 262 big cities)
      for (const a of o) for (const p of city.detail.ponds) {
        const own = a.role === 'tackle' && a.nearest?.name === p.name, d = km(a, p);
        if (own) expect(d * 1000, `${a.id} by its pond`).toBeGreaterThanOrEqual(100 - 1e-3);
        else expect(d, `${a.id}–${p.id}`).toBeGreaterThanOrEqual(0.3 - 1e-6);
      }
      const post0 = o.find(x => x.id === `${cl.id}~post0`)!, market0 = o.find(x => x.id === `${cl.id}~market0`)!;
      expect(km(cl, post0)).toBeLessThanOrEqual(1);
      expect(km(cl, market0)).toBeGreaterThanOrEqual(1 - 1e-6);
      expect(km(cl, market0)).toBeLessThanOrEqual(2 + 1e-6);
      expect(km(market0, beginner) * 1000).toBeLessThanOrEqual(800);
      const tackle0 = o.find(x => x.id === `${cl.id}~tackle0`)!;
      expect(tackle0.nearest?.name).toBe(beginner.name);   // the beginner pond's shop first
      expect(km(tackle0, beginner) * 1000).toBeLessThanOrEqual(300);
      expect(new Set(o.map(x => x.keeper.name)).size).toBe(o.length);   // a name plate never twice in a city
      for (const x of o) {
        expect(x.name.length).toBeLessThanOrEqual(24);
        expect(x.name).not.toMatch(/[0-9]/);
        expect(x.id).toMatch(new RegExp(`^${cl.id}~(tea|tackle|market|post)[0-9]+$`));
      }
    }
    expect(checked).toBe(clusters.byId.size - 1);   // every cluster but the home city
  });

  it('keeps Market Square 2 off pond 5 (q(144)): Taipei\'s Tea Hill Market Square and Hong Kong\'s Lagoon Market Square stand apart', () => {
    for (const id of ['gn-1668341', 'gn-1819729']) {
      const d = generateCity(c, clusters.get(id)!, { water: false }).detail;
      const square = d.outposts.find(o => o.id === `${id}~market1`)!, pond = d.ponds.find(p => p.id === `${id}~pond4`)!;
      expect(km(square, pond)).toBeGreaterThanOrEqual(0.3);   // was 0 m: the same point
      expect(km(clusters.get(id)!, square)).toBeGreaterThanOrEqual(5 - 0.01);   // still on its ring
    }
  });

  it('never names an outpost after its own city (q(32)): Tokyo has no "Tokyo Market Square"', () => {
    const tokyo = cityPlaces(c, TOKYO)!.detail.outposts;
    expect(tokyo.find(o => o.id === `${TOKYO}~market0`)!.name).not.toMatch(/^Tokyo /);
    expect(tokyo.find(o => o.id === `${TOKYO}~post0`)!.name).not.toMatch(/^Tokyo /);
    for (const cl of clusters.byId.values()) {
      const city = cityPlaces(c, cl.id);
      if (!city) continue;
      for (const o of city.detail.outposts) expect(o.name.startsWith(`${cl.name} `)).toBe(false);
      const names = city.detail.outposts.map(o => o.name);
      expect(new Set(names).size).toBe(names.length);   // the same kind never shares a name in a city
    }
  });

  it('names ponds from their climate\'s forty-word pool (q(125)): cities of one band differ, no word in two pools', () => {
    const pools = w.ponds.words as Record<string, string[]>;
    const bands = ['Tropical', 'Subtropical', 'Temperate', 'Cool'];
    const all = bands.flatMap(b => pools[b]);
    for (const b of bands) expect(pools[b]).toHaveLength(40);
    expect(new Set(all).size).toBe(all.length);
    const tea = Object.values(w.tea_words).flat(), keepers = Object.values(w.keeper_names).flat();
    const fishWords = c.fish.flatMap(f => String((f as { name?: string }).name ?? '').split(' '));
    // never a city's name (Plum and Aurora are towns): a pond word reads as a place, not as another city
    const cityNames = new Set(readFileSync(new URL('../../data/cities.tsv', import.meta.url), 'utf8').split('\n')
      .filter(l => l && !l.startsWith('#')).map(l => l.split('\t')[1]?.toLowerCase()));
    for (const word of all) {
      for (const taken of [tea, keepers, fishWords]) expect(taken).not.toContain(word);   // no Willow Tea House by Willow Pond
      expect(cityNames.has(word.toLowerCase()), `${word} is a city`).toBe(false);
      expect(`${word} Creek`.length).toBeLessThanOrEqual(18);
      expect(`${word} Tackle Shop`.length).toBeLessThanOrEqual(24);
    }
    const band = (id: string) => pools[{ tropical: 'Tropical', subtropical: 'Subtropical', temperate: 'Temperate', cool: 'Cool' }[cityPlaces(c, id)!.climate]];
    for (const id of [TOKYO, NYC, BEIJING, SHANGHAI, LA, 'gn-463835']) {
      for (const p of cityPlaces(c, id)!.detail.ponds) expect(band(id)).toContain(p.name.split(' ')[0]);
    }
    // Tokyo, New York and Beijing (all temperate, six ponds each) no longer share one set of names
    const set = (id: string) => cityPlaces(c, id)!.detail.ponds.map(p => p.name.split(' ')[0]).sort().join();
    expect(new Set([TOKYO, NYC, BEIJING].map(set)).size).toBe(3);
  });

  it('names keepers from the climate pool, never a resident name, and tea houses from the climate words', () => {
    const tokyo = cityPlaces(c, TOKYO)!;
    const temperate = w.keeper_names.Temperate;
    expect(temperate.length).toBeGreaterThanOrEqual(18);   // q(114) ④: 18 a band, enough for an L3 city's 17 counters
    expect(tokyo.detail.outposts.every(o => temperate.includes(o.keeper.name))).toBe(true);   // no borrowing needed
    for (const o of tokyo.detail.outposts) {
      expect(['Pip', 'Kai', 'Wu', 'Mira', 'Rafa', 'Ivo', 'Hana', 'Sam', 'Lena', 'Tomo', 'Theo', 'Nadia']).not.toContain(o.keeper.name);
      expect(o.keeper.look).toMatch(/^(tea|tackle|market|post)_temperate_[0-2]$/);
    }
    for (const t of tokyo.detail.outposts.filter(o => o.role === 'tea')) {
      expect(w.tea_words.Temperate).toContain(t.name.replace(/ Tea House$/, ''));
    }
    expect(cityPlaces(c, SHANGHAI)!.detail.outposts.find(o => o.role === 'tea')!.name).toMatch(
      new RegExp(`^(${w.tea_words.Subtropical.join('|')}) Tea House$`));
  });

  it('gives each city two regional fish, the first from its climate\'s low group; curated cities keep theirs', () => {
    expect(cityPlaces(c, SHANGHAI)!.fish.map(f => f.fish)).toEqual(['fish_grass_carp', 'fish_snakehead']);
    expect(cityPlaces(c, LA)!.fish.map(f => f.fish)).toEqual(['fish_tilapia', 'fish_grass_carp']);
    const tokyo = cityPlaces(c, TOKYO)!.fish;
    expect(tokyo).toHaveLength(2);
    const low = (c.fishing as unknown as { regional: { groups: Record<string, { low: string[] }> } }).regional.groups.Temperate.low;
    expect(low).toContain(tokyo[0].fish);
    expect(tokyo[0].fish).not.toBe(tokyo[1].fish);
    expect(tokyo[0].level).toBe(c.fish.find(f => f.id === tokyo[0].fish)!.level);
  });

  it('answers placeOf for a generated pond like a hand-written one, and cityInfo shows the generated city', () => {
    expect(placeOf(c, `${TOKYO}~pond0`)).toMatchObject({ site: 'pond', cluster: TOKYO, beginner: true });
    expect(placeOf(c, `${TOKYO}~pond9`)).toBeUndefined();
    expect(placeOf(c, `${TOKYO}~tea0`)).toBeUndefined();   // an outpost is not a pond
    expect(placeOf(c, 'pond_san_francisco_03')).toBe(c.fishing.places.pond_san_francisco_03);
    const info = (c as P0Content & { cityPlaces: (id: string) => { ponds: string[]; outposts: string[] } }).cityPlaces(TOKYO);
    expect(info.ponds[0]).toBe(`${TOKYO}~pond0`);
    expect(info.outposts.length).toBeGreaterThan(0);
    expect(Object.keys(c)).not.toContain('cityPlaces');   // not enumerable: structuredClone(content) still works
    expect(() => structuredClone(c)).not.toThrow();
  });

  it('places residents by §9.4.3: Pip in every travel post, Sam and Nadia fixed, the rest by rank and city traits', () => {
    const where = (id: string) => Object.fromEntries(cityPlaces(c, id)!.detail.outposts
      .filter(o => o.residents.length).map(o => [o.id.split('~')[1], o.residents]));
    // Shanghai (L3, coast + river): the plan's example allocation, Lena at a tea house until the Lighthouse Room exists
    expect(where(SHANGHAI)).toEqual({ post0: ['res_pip', 'res_sam'], post1: ['res_pip'], market0: ['res_nadia', 'res_theo'],
      market1: ['res_tomo'], tackle0: ['res_old_kai'], tackle1: ['res_rafa'], tea0: ['res_hana'], tea1: ['res_lena'] });
    // Beijing (L3, no coast or river in the trait list): no Old Kai, Rafa or Lena
    const bj = Object.values(where(BEIJING)).flat();
    for (const r of ['res_old_kai', 'res_rafa', 'res_lena', 'res_ivo']) expect(bj).not.toContain(r);
    // Old Kai keeps the beginner pond's tackle shop
    const sh = cityPlaces(c, SHANGHAI)!;
    expect(sh.detail.outposts.find(o => o.residents.includes('res_old_kai'))!.nearest?.name).toBe(sh.detail.ponds[0].name);
    // S tier: the trading post holds Pip and Granny Wu under 100,000 people, else the next eligible (Theo)
    expect(where('gn-498687')).toEqual({ cabin0: ['res_pip', 'res_granny_wu'] });   // Sarapul, 98,830
    expect(where('gn-463835')).toEqual({ cabin0: ['res_pip', 'res_theo'] });         // Zelenodolsk, 157,600 with its members
    for (const cl of clusters.byId.values()) {
      const city = cityPlaces(c, cl.id);
      if (!city) continue;
      const fixed = city.detail.outposts.flatMap(o => o.residents);
      expect(city.detail.outposts.every(o => o.residents.length <= 2)).toBe(true);
      expect(new Set(fixed.filter(r => r !== 'res_pip')).size).toBe(fixed.filter(r => r !== 'res_pip').length);   // one place each
      if (city.tier !== 'S') expect(new Set(fixed).size).toBeLessThanOrEqual(city.detail.outposts.length);   // the trading post holds 2 by rule
      expect(fixed).not.toContain('res_ivo');   // no Mine Hut yet
      for (const r of fixed) expect(Object.keys((c as P0Content & { residents: object }).residents)).toContain(r);
    }
  });

  it('gives every keeper one of the 48 placeholder looks of their role and climate, made of public parts', () => {
    const looks = w.keeper_looks!;
    const npcOnly = ['mask16_npc_kai', 'hairhat71_npc_kai', 'hairhat12_npc_mei', 'cloth11_npc_mei', 'hairhat80_npc_ama',
      'hairhat36_npc_sigrid', 'cloth36_npc_sigrid', 'cloth12_npc_finn', 'hairhat36_npc_pip'];
    const keys = Object.keys(looks).filter(k => !k.startsWith('_'));
    expect(keys).toHaveLength(48);
    for (const k of keys) for (const part of Object.values(looks[k])) expect(npcOnly).not.toContain(part);
    for (const id of [TOKYO, SHANGHAI, 'gn-463835']) {
      for (const o of cityPlaces(c, id)!.detail.outposts) expect(looks[o.keeper.look]).toBeDefined();
    }
  });

  it('lays world.overrides over the generated city and moves nothing else (q(114) ⑤): LA\'s Clover Tackle Shop off Hollenbeck Lake', () => {
    const fixes = Object.entries(w.overrides ?? {}).filter(([k]) => !k.startsWith('_')) as [string, PlaceFix][];
    expect(fixes.length).toBeGreaterThan(0);
    const fixed = new Set(fixes.map(([id]) => id));
    const all = (x: CityPlaces) => [...x.detail.ponds, ...x.detail.outposts];
    const saved = w.overrides;
    for (const [id, fix] of fixes) {
      const cluster = id.slice(0, id.indexOf('~'));
      let bare: CityPlaces;
      w.overrides = undefined;
      try { bare = generateCity(c, clusters.get(cluster)!); } finally { w.overrides = saved; }
      const city = cityPlaces(c, cluster)!;
      const was = all(bare).find(p => p.id === id), now = all(city).find(p => p.id === id);
      expect(was, `${id} is a place the generator makes`).toBeDefined();
      if (fix.lat !== undefined) expect(now).toMatchObject({ lat: fix.lat, lng: fix.lng });
      // to the nearest land that keeps the rules, a stuck group (pond, shop, square) up to 8 km as the batch's wide search;
      // never across the country (a swapped lat / lng)
      expect(km(was!, now!)).toBeLessThanOrEqual(8);
      const tackle = city.detail.outposts.find(o => o.id === id && o.role === 'tackle');
      if (tackle) expect(km(tackle, city.detail.ponds.find(p => p.name === tackle.nearest!.name)!) * 1000).toBeLessThanOrEqual(300);
      expect(all(city).filter(p => !fixed.has(p.id))).toEqual(all(bare).filter(p => !fixed.has(p.id)));
    }
    // the tackle shop found on Hollenbeck Lake (Clover Tackle Shop then; named after its Cove since q(125))
    const la = cityPlaces(c, LA)!.detail;
    expect(la.outposts.find(o => o.id === `${LA}~tackle2`))
      .toMatchObject({ lat: 34.040844, lng: -118.219243, nearest: { name: la.ponds[2].name } });
    // New York's beginner pond, its shop and Market Square 1 came off the Hudson together (司空震, 286 16ffaf67), then off
    // Pier 40 into the West Village for the first home cities (SGODOT-303, 303 582765b3)
    const nyc = (w.overrides as Record<string, PlaceFix>)[`${NYC}~pond0`];
    expect(placeOf(c, `${NYC}~pond0`)).toMatchObject({ beginner: true, at: [nyc.lat, nyc.lng] });
    expect(km({ lat: nyc.lat!, lng: nyc.lng! }, { lat: 40.734, lng: -74.0078 })).toBeLessThan(0.1);
    // A renamed pond (before the freeze) keeps its tackle shop pointing at it; a point without both lat and lng is ignored.
    const tokyo = structuredClone(generateCity(c, clusters.get(TOKYO)!).detail);
    const [pond, shop] = [tokyo.ponds[0], tokyo.outposts.find(o => o.id === `${TOKYO}~tackle0`)!];
    const at = { lat: pond.lat, lng: pond.lng };
    applyOverrides({ ...w, overrides: { [pond.id]: { name: 'Koi Pond', lat: 1 } } }, tokyo.ponds, tokyo.outposts);
    expect(pond).toMatchObject({ name: 'Koi Pond', ...at });
    expect(shop.nearest?.name).toBe('Koi Pond');
  });

  it('lays the water table (q(126)) under the hand fixes: every entry is this world\'s, a short move, never a hand-fixed place', () => {
    const table = waterTable();
    expect(table, 'server/data/world_water.json (tools/world_water_batch.ts)').not.toBeNull();
    expect([table!.seed, table!.revision]).toEqual([w.seed, w.revision]);
    const hand = new Set(Object.keys(w.overrides ?? {}).filter(k => !k.startsWith('_')));
    const byCity = new Map<string, string[]>();
    for (const id of Object.keys(table!.fixes)) byCity.set(id.slice(0, id.indexOf('~')), [...(byCity.get(id.slice(0, id.indexOf('~'))) ?? []), id]);
    expect(Object.keys(table!.fixes).length).toBeGreaterThan(1000);
    for (const [cluster, ids] of byCity) {
      const bare = generateCity(c, clusters.get(cluster)!, { water: false }), city = cityPlaces(c, cluster)!;
      const all = (x: CityPlaces) => [...x.detail.ponds, ...x.detail.outposts];
      for (const id of ids) {
        const [lat, lng, fromLat, fromLng] = table!.fixes[id];
        expect(hand.has(id), `${id} has a hand fix`).toBe(false);
        const was = all(bare).find(p => p.id === id);
        expect(was && [was.lat, was.lng], `${id}: rerun tools/world_water_batch.ts`).toEqual([fromLat, fromLng]);
        expect(all(city).find(p => p.id === id)).toMatchObject({ lat, lng });
        // 3 km, or 8 km where nothing within 3 km kept the rules (the batch's --retry wide --search 8000)
        expect(km({ lat, lng }, { lat: fromLat, lng: fromLng })).toBeLessThanOrEqual(8);
      }
    }
    // a table made for another world is an error, never quietly used
    expect(() => applyWater({ ...w, revision: w.revision + 1 }, [], [], table)).toThrow(/rerun tools\/world_water_batch/);
  });

  it('a player with a pass to Tokyo casts in its generated beginner pond', () => {
    let s = freshState(c, 'world-player', T, 7);
    const run = (cmd: P0Command) => { const r = applyP0(c, s, cmd, T); if (!r.ok) throw new Error(r.code); s = r.state; return r; };
    run({ type: 'travel', to: TOKYO });
    const pond = `${TOKYO}~pond0`;
    const r = run({ type: 'cast', space: 'pond', place: pond } as P0Command);
    expect(s.presence.place).toBe(pond);
    expect(s.cast?.place).toBe(pond);
    expect(s.cast?.site).toBe('pond');
    expect(r.events.some(e => e.kind === 'cast')).toBe(true);
  });
});
