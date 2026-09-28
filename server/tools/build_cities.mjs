// Builds server/data/cities.tsv from GeoNames dumps (CC BY 4.0, https://www.geonames.org/).
// Usage: node tools/build_cities.mjs <cities15000.txt> <admin1CodesASCII.txt> <countryInfo.txt>
//
// A "city" here is the unit players share: the nearby list, city bubbles and farm clocks all group by it.
// Suburbs that sit inside a much larger city's radius are absorbed so a metro area stays one city.
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const [citiesFile, admin1File, countryFile] = process.argv.slice(2);
if (!countryFile) { console.error('usage: build_cities.mjs cities15000.txt admin1CodesASCII.txt countryInfo.txt'); process.exit(1); }

const admin1 = new Map(readFileSync(admin1File, 'utf8').split('\n').filter(Boolean).map(l => {
  const [code, name] = l.split('\t'); return [code, name];
}));
const countries = new Map(readFileSync(countryFile, 'utf8').split('\n').filter(l => l && !l.startsWith('#')).map(l => {
  const f = l.split('\t'); return [f[0], f[4]];
}));

// Sections of a populated place (city districts) are never a city of their own.
const SKIP = new Set(['PPLX', 'PPLH', 'PPLQ', 'PPLW', 'PPLCH']);
export const radiusKm = pop => pop >= 5e6 ? 45 : pop >= 1e6 ? 30 : pop >= 3e5 ? 20 : 12;
const R = 6371;
const dist = (a, b) => {
  const dLat = (b.lat - a.lat) * Math.PI / 180, dLng = (b.lng - a.lng) * Math.PI / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * Math.PI / 180) * Math.cos(b.lat * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
};
const clean = s => s.replace(/[\t\r\n]/g, ' ').trim();

const raw = readFileSync(citiesFile, 'utf8').split('\n').filter(Boolean).map(l => l.split('\t')).filter(f => !SKIP.has(f[7])).map(f => ({
  id: 'gn-' + f[0], name: clean(f[1]), lat: Number(f[4]), lng: Number(f[5]), cc: f[8],
  admin: clean(admin1.get(`${f[8]}.${f[10]}`) ?? ''), country: clean(countries.get(f[8]) ?? f[8]),
  pop: Number(f[14]) || 0, tz: f[17],
})).filter(c => Number.isFinite(c.lat) && Number.isFinite(c.lng) && c.tz && c.name);
raw.sort((a, b) => b.pop - a.pop || a.id.localeCompare(b.id));

// Grid index over kept cities so absorption stays O(n).
const CELL = 1; // degree
const grid = new Map();
const cellKey = (lat, lng) => `${Math.floor(lat / CELL)}:${Math.floor(lng / CELL)}`;
const kept = [];
for (const c of raw) {
  let absorbed = false;
  const cy = Math.floor(c.lat / CELL), cx = Math.floor(c.lng / CELL);
  for (let dy = -1; dy <= 1 && !absorbed; dy++) for (let dx = -1; dx <= 1 && !absorbed; dx++) {
    for (const k of grid.get(`${cy + dy}:${cx + dx}`) ?? []) {
      const d = dist(k, c), r = radiusKm(k.pop);
      if (k.pop > c.pop && d <= r && (k.pop >= c.pop * 3 || d <= r / 2)) { absorbed = true; break; }
    }
  }
  if (absorbed) continue;
  kept.push(c);
  const key = cellKey(c.lat, c.lng);
  if (!grid.has(key)) grid.set(key, []);
  grid.get(key).push(c);
}

const header = '# GeoNames cities15000 (CC BY 4.0, https://www.geonames.org/) compacted by tools/build_cities.mjs\n'
  + '# id\tname\tlat\tlng\tcountry_code\tadmin\tcountry\tpopulation\ttimezone\tradius_km\n';
const lines = kept.map(c => [c.id, c.name, c.lat.toFixed(5), c.lng.toFixed(5), c.cc, c.admin, c.country, c.pop, c.tz, radiusKm(c.pop)].join('\t'));
const out = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', 'data', 'cities.tsv');
writeFileSync(out, header + lines.join('\n') + '\n');
console.log(`raw=${raw.length} kept=${kept.length} -> ${out}`);
