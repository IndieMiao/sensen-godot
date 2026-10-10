/** SGODOT-280: global generation — a city cluster's ponds and outposts from the world seed and the cluster id (plan v2
 * §9.3.2 outposts, §6.3.3 ponds), the same every time; the home city keeps its hand-written tables. */
import { describe, expect, it } from 'vitest';
import type { CityCluster } from '../../src/p0/clusters.js';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState } from '../../src/p0/state.js';
import { clusterOf } from '../../src/p0/travel.js';
import { cityPlaces, generateCity, km, placeOf, pondCount, tierOf, type WorldContent } from '../../src/p0/world.js';

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

  it('tiers by population (§9.3.2 thresholds), raised by the area list (Los Angeles and Tokyo reach L3)', () => {
    expect([400_000, 1_000_000, 2_000_000, 5_000_000, 10_000_000, 20_000_000].map(p => tierOf(w, fake(p))))
      .toEqual(['S', 'M1', 'M2', 'L1', 'L2', 'L3']);
    expect(tierOf(w, clusters.get(LA)!)).toBe('L3');      // 3.8 M people: L1 by population
    expect(tierOf(w, clusters.get(TOKYO)!)).toBe('L3');
    expect(tierOf(w, clusters.get(SHANGHAI)!)).toBe('L3');
    expect(tierOf(w, clusters.get(NYC)!)).toBe('L2');
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
      expect(c.fishing.sites[first.site].fish).toContain('fish_crucian');
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

  it('names keepers from the climate pool, never a resident name, and tea houses from the climate words', () => {
    const tokyo = cityPlaces(c, TOKYO)!;
    const temperate = w.keeper_names.Temperate;
    expect(tokyo.detail.outposts.filter(o => temperate.includes(o.keeper.name)).length).toBe(temperate.length);   // own pool first
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
