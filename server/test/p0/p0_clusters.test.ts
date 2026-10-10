/** SGODOT-275: P0 city clusters (plan v2 §11.1–11.2) built from the city directory and frozen. */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { CityClusters, DEFAULT_CLUSTERS, distanceKm, tripByKm } from '../../src/p0/clusters.js';
import { loadP0Content } from '../../src/p0/content.js';

const cl = CityClusters.load();
const SF = 'gn-5391959', TOKYO = 'gn-1850147', LA = 'gn-5368361', SHANGHAI = 'gn-1796236';

describe('P0 city clusters (SGODOT-275)', () => {
  it('merges each metro area within 30 km into its most populous city, as the plan examples', () => {
    expect(cl.byId.size).toBe(12490);
    expect(cl.ofCity('gn-5378538')).toBe(SF);        // Oakland → San Francisco
    expect(cl.ofCity('gn-1848354')).toBe(TOKYO);     // Yokohama → Tokyo
    expect(cl.ofCity('gn-3085128')).toBe('gn-3096472');   // Sosnowiec → Katowice
    expect(cl.ofCity('gn-5367929')).toBe('gn-5367929');   // Long Beach (32 km from LA) is its own
    expect(cl.get(SF)).toMatchObject({ name: 'San Francisco', climate: 'temperate', continent: 'north_america' });
    expect(cl.get(TOKYO)).toMatchObject({ climate: 'temperate', continent: 'asia' });
    expect(cl.get('gn-524901')?.continent).toBe('europe');   // Moscow: Russia is Europe (§11.9.3)
  });

  it('every directory city is in exactly one cluster, and every cluster seed is its own member', () => {
    const cities = readFileSync(DEFAULT_CLUSTERS.replace('assets/p0/city_clusters.json', 'server/data/cities.tsv'), 'utf8')
      .split('\n').filter(l => l && !l.startsWith('#')).map(l => l.split('\t')[0]);
    expect(cities.every(id => cl.byId.has(cl.ofCity(id) ?? ''))).toBe(true);
    for (const id of cl.byId.keys()) expect(cl.ofCity(id)).toBe(id);
  });

  it('places the P0 home cluster where the content says (profile.region san_francisco = gn-5391959)', () => {
    const c = loadP0Content();
    const [lat, lng] = c.profile.farm_at ?? [0, 0];
    expect(distanceKm({ lat, lng }, cl.get(SF)!)).toBeLessThan(30);
  });

  it('trip tiers follow the distance bounds and the fallback lists (§11.2.1, §11.2.3)', () => {
    expect([29, 30, 31, 100, 101, 500, 1600, 1601, 4000, 10000, 10001].map(tripByKm)).toEqual([1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7]);
    const farm = { lat: 37.7558, lng: -122.4345 };   // the San Francisco homestead
    const fb = cl.fallback(SF, farm);
    expect(fb.near3).toHaveLength(3);
    expect(fb.near10).toHaveLength(10);
    expect(fb.near10.slice(0, 3)).toEqual(fb.near3);
    expect(fb.near10).not.toContain(SF);
    expect(cl.trip(SF, SF, farm, fb)).toEqual({ km: 0, trip: 1, name: 'Local' });
    expect(cl.trip(fb.near3[0], SF, farm, fb).trip).toBe(1);
    expect(cl.trip(LA, SF, farm, fb)).toMatchObject({ trip: 4, name: 'Long Haul' });       // §11.2.4: 559 km
    expect(cl.trip(TOKYO, SF, farm, fb)).toMatchObject({ trip: 6, name: 'Intercontinental' });
    expect(cl.trip(SHANGHAI, SF, farm, fb)).toMatchObject({ trip: 6 });                    // §11.2.4 SF row: Trip 6
  });
});
