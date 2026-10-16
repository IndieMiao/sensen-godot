/** MAP-8 Nearby cities (§11.8.1; the user on 10-13: this page only): the view names each near10 city's state or province. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { freshState } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { clusterAdmin } from '../../src/p0/world.js';
import { cityRegion, homeCities } from '../../src/p0/home_city.js';
import { clustersOf } from '../../src/p0/home.js';

const c = loadP0Content();
const now = Date.parse('2026-10-13T03:00:00Z');

describe('MAP-8: the near10 cities\' states in the view (不知火舞 on 301 / MAP-8)', () => {
  it('reads a cluster\'s state from its seed city', () => {
    expect(clusterAdmin('gn-5391295')).toBe('California');   // Salinas
    expect(clusterAdmin('gn-1850147')).toBe('Tokyo');
    expect(clusterAdmin('gn-nothing')).toBe('');
  });

  it('names every near10 city of a San Francisco home, and only those', () => {
    const s = freshState(c, 'nearby-player-01', now);
    const near10 = s.travel.fallback.near10;
    expect(near10.length).toBeGreaterThan(0);
    const admins = viewOf(c, s, now).travel.admins as Record<string, string>;
    expect(Object.keys(admins).sort()).toEqual(near10.filter(id => clusterAdmin(id) !== '').sort());
    for (const id of near10) if (admins[id]) expect(admins[id]).toBe(clusterAdmin(id));
    expect(Object.values(admins)).toContain('California');
  });

  // q(208) ①: every CityRow's second part — the home pick's and MAP-8's — is cityRegion
  it('writes a US city\'s state, elsewhere the country, none when it is the city\'s own name, a province for twins (q(208))', () => {
    expect(cityRegion(c, 'gn-5391295')).toBe('California');   // Salinas
    expect(cityRegion(c, 'gn-1850147')).toBe('Japan');        // Tokyo, not `Tokyo · Tokyo`
    expect(cityRegion(c, 'gn-2643743')).toBe('United Kingdom');
    expect(cityRegion(c, 'gn-1880252')).toBe('');             // Singapore
    expect(cityRegion(c, 'gn-1819729')).toBe('');             // Hong Kong
    expect(cityRegion(c, 'gn-2036579')).toBe('Jilin');        // Ji'an, one of two in China
    expect(cityRegion(c, 'gn-1806445')).toBe('Jiangxi');
    expect(cityRegion(c, 'gn-nothing')).toBe('');
    // twins outside the US: q(208) counts 83 pairs (two Ji'ans, two Suzhous …), each now told apart by its province
    const seen = new Map<string, string[]>();
    for (const cl of clustersOf(c)!.byId.values()) if (cl.country_code !== 'US') seen.set(`${cl.country_code}|${cl.name}`, [...(seen.get(`${cl.country_code}|${cl.name}`) ?? []), cl.id]);
    const twins = [...seen.values()].filter(ids => ids.length > 1);
    expect(twins).toHaveLength(83);
    // the home pick's rows and a San Francisco home's near10 read the same
    expect(Object.fromEntries(homeCities(c).open.map(r => [r.name, r.region]))).toMatchObject({ 'San Francisco': 'California',
      Tokyo: 'Japan', Shanghai: 'China', Singapore: '', 'Hong Kong': '', 'Mexico City': 'Mexico' });
    const s = freshState(c, 'nearby-player-02', now);
    const regions = viewOf(c, s, now).travel.regions as Record<string, string>;
    expect(Object.keys(regions).sort()).toEqual([...s.travel.fallback.near10].sort());   // every one, an empty one too
    for (const id of s.travel.fallback.near10) expect(regions[id]).toBe(cityRegion(c, id));
  });
});
