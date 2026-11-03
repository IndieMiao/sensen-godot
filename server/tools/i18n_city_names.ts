/**
 * SGODOT-385 (#649 第二批 ④): the cities the 中文版 names in Chinese — the open home cities (home_city.homeCities) and
 * each one's frozen fallback ten (travel.fallbackOf, §11.2.3), as the game reaches them. Prints JSON for
 * tools/p0/i18n/extract.py: [{id, name, country, homes: [the home cities it is one of the ten of, or itself]}].
 *
 *   node --import tsx tools/i18n_city_names.ts
 */
import { loadP0Content } from '../src/p0/content.js';
import { clusterById, countryPart } from '../src/p0/home.js';
import { homeCities } from '../src/p0/home_city.js';
import { fallbackOf } from '../src/p0/travel.js';

const c = loadP0Content();
const out = new Map<string, { id: string; name: string; country: string; homes: string[] }>();
const add = (id: string, name: string, home: string) => {
  const cl = clusterById(c, id);
  const e = out.get(id) ?? { id, name, country: cl ? countryPart(c, cl) : '', homes: [] };
  if (!e.homes.includes(home)) e.homes.push(home);
  out.set(id, e);
};
for (const home of homeCities(c).open) {
  add(home.id, home.name, home.name);
  for (const id of fallbackOf(c, home.id).near10) add(id, clusterById(c, id)?.name ?? id, home.name);
}
console.log(JSON.stringify([...out.values()]));
