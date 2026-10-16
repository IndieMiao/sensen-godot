/** MAP-8 Nearby cities (§11.8.1; the user on 10-13: this page only): the view names each near10 city's state or province. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { freshState } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { preview } from '../../src/p0/travel.js';
import { clusterAdmin } from '../../src/p0/world.js';
import { cityRegion, homeCities, namesCountry } from '../../src/p0/home_city.js';
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
    // typed with a plain apostrophe, the search finds both (the directory writes Ji’an)
    expect(homeCities(c, "ji'an").matches.map(r => `${r.name} · ${r.region}`)).toEqual(expect.arrayContaining(['Ji’an · Jilin', 'Ji’an · Jiangxi']));
    expect(cityRegion(c, 'gn-nothing')).toBe('');
    // q(209) ②: a name holding its own country's name as a whole word reads alone — eight in the directory; part of a
    // word (Iranshahr) or another country's name (Benin City, Armenia) does not count
    const all = [...clustersOf(c)!.byId.values()];
    expect(all.filter(cl => cl.name !== cl.country && namesCountry(cl.name, cl.country)).map(cl => cl.name).sort()).toEqual(
      ['Andorra la Vella', 'Belize City', 'Guatemala City', 'Kuwait City', 'Mexico City', 'Panama City', 'Port Sudan', 'Santiago de Cuba']);
    for (const [name, region] of [['Iranshahr', 'Iran'], ['Benin City', 'Nigeria'], ['Armenia', 'Colombia']]) {
      const cl = all.find(x => x.name === name)!;
      expect(cityRegion(c, cl.id), name).toBe(region);
    }
    // q(209) ①: two same-named cities in one province both read the province, no third part (two Changzhis in Shanxi)
    const changzhi = all.filter(cl => cl.name === 'Changzhi' && cl.country_code === 'CN');
    expect(changzhi.length).toBeGreaterThanOrEqual(2);
    for (const cl of changzhi) expect(cityRegion(c, cl.id)).toBe('Shanxi');
    // a search lists them most populous first (the page puts the ones that can be picked before the rest, keeping this order)
    const pops = homeCities(c, 'changzhi').matches.map(r => all.find(cl => cl.id === r.id)!.population);
    expect(pops).toEqual([...pops].sort((a, b) => b - a));
    // twins outside the US: q(208) counts 83 pairs (two Ji'ans, two Suzhous …), each now told apart by its province
    const seen = new Map<string, string[]>();
    for (const cl of clustersOf(c)!.byId.values()) if (cl.country_code !== 'US') seen.set(`${cl.country_code}|${cl.name}`, [...(seen.get(`${cl.country_code}|${cl.name}`) ?? []), cl.id]);
    const twins = [...seen.values()].filter(ids => ids.length > 1);
    expect(twins).toHaveLength(83);
    // the home pick's rows and a San Francisco home's near10 read the same
    expect(Object.fromEntries(homeCities(c).open.map(r => [r.name, r.region]))).toMatchObject({ 'San Francisco': 'California',
      Tokyo: 'Japan', Shanghai: 'China', Singapore: '', 'Hong Kong': '', 'Mexico City': '' });
    const s = freshState(c, 'nearby-player-02', now);
    const regions = viewOf(c, s, now).travel.regions as Record<string, string>;
    expect(Object.keys(regions).sort()).toEqual([...s.travel.fallback.near10].sort());   // every one, an empty one too
    for (const id of s.travel.fallback.near10) expect(regions[id]).toBe(cityRegion(c, id));
  });

  // q(210): the country is Unicode CLDR's English name; Hong Kong, Macao, Taiwan, the Palestinian Territories, Kosovo and
  // Western Sahara read the city's name alone (q(210) ② ③)
  it('writes the country as CLDR names it, and only the city in the six places that read it alone (q(210))', () => {
    const all = [...clustersOf(c)!.byId.values()];
    const by = (name: string, code: string) => all.find(cl => cl.name === name && cl.country_code === code)!;
    for (const [name, code, region] of [['Istanbul', 'TR', 'Türkiye'], ['Abidjan', 'CI', 'Côte d’Ivoire'], ['Amsterdam', 'NL', 'Netherlands'],
      ['Kinshasa', 'CD', 'Congo (DRC)'], ['Pointe-Noire', 'CG', 'Congo (Republic)'], ['Yangon', 'MM', 'Myanmar'], ['Praia', 'CV', 'Cabo Verde'],
      ['Prague', 'CZ', 'Czechia'], ['Gros Islet', 'LC', 'St. Lucia'], ['Taipei', 'TW', ''], ['Gaza', 'PS', ''], ['Pristina', 'XK', ''],
      ['Laayoune', 'EH', ''], ['Hong Kong', 'HK', ''], ['Smara', 'MA', 'Morocco']]) {
      const cl = by(name, code);
      expect(cl, name).toBeDefined();
      expect(cityRegion(c, cl.id), name).toBe(region);
    }
    // every country the directory has is in the table (no city falls back to GeoNames' own spelling)
    for (const code of new Set(all.map(cl => cl.country_code))) expect(c.travel?.country_names?.[code], code).toBeTruthy();
    // the home pick's row carries the same country (q(210) ⑤: one function for every exit)
    expect(homeCities(c, 'istanbul').matches.find(r => r.name === 'Istanbul')?.country).toBe('Türkiye');
    expect(homeCities(c).open.find(r => r.name === 'Hong Kong')?.country).toBe('');
    // the silhouette card's preview writes the same country
    const s = freshState(c, 'nearby-player-03', now);
    expect(preview(c, s, by('Istanbul', 'TR').id, now).country).toBe('Türkiye');
    expect(preview(c, s, by('Taipei', 'TW').id, now).country).toBe('');
  });
});
