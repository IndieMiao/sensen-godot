// City clusters for P0 travel (SGODOT-275, plan v2 §11.1; 亚瑟's cross-city plan §1 on the 275 card).
//
// The ~21k cities of data/cities.tsv (population ≥ 15,000) are merged greedily, most populous first, with every
// not-yet-clustered city within 30 km: one cluster per metro area (San Francisco + Oakland, Tokyo + Yokohama).
// A cluster's key is its seed city's GeoNames id and is FROZEN: stamps, passes and visits in saves are keyed by it,
// so a rebuild keeps every existing assignment and only places cities that are new to the directory (joining the
// nearest existing seed within 30 km, else seeding a cluster of their own). Delete the outputs to start over.
//
// SPLIT_OUT lists cities the greedy merge put in another country's cluster that are big enough to be cities of their
// own: each becomes its own seed (its id is its key), the rest of the build unchanged. A city new to the directory
// near one may then join it.
//
//   node server/tools/build_clusters.mjs
//   → assets/p0/city_clusters.json        (client + server: one row per cluster; JSON so it ships in the APK)
//   → server/data/city_cluster_members.tsv (server only: city id → cluster id)
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const CITIES = path.join(root, 'server/data/cities.tsv');
const OUT = path.join(root, 'assets/p0/city_clusters.json');
const MEMBERS = path.join(root, 'server/data/city_cluster_members.tsv');
export const CLUSTER_KM = 30;

const rows = readFileSync(CITIES, 'utf8').split('\n').filter(l => l && !l.startsWith('#')).map(l => {
  const f = l.split('\t');
  return { id: f[0], name: f[1], lat: +f[2], lng: +f[3], cc: f[4], country: f[6], pop: +f[7], tz: f[8] };
});
const byId = new Map(rows.map(r => [r.id, r]));

const rad = Math.PI / 180;
const km = (a, b) => {
  const dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.min(1, Math.sqrt(h)));
};

// Climate band by the cluster centre's latitude (plan §11.1, the whole book): <23.5 tropical, 23.5–35 subtropical,
// 35–55 temperate, ≥55 cool.
export const climate = lat => { const a = Math.abs(lat); return a < 23.5 ? 'tropical' : a < 35 ? 'subtropical' : a < 55 ? 'temperate' : 'cool'; };

// Continent (passport page, §11.9.3) by country code: each country's most common timezone region, with the plan's
// rules on top (Russia and Turkey are Europe; the Americas split into North, with Central America and the Caribbean,
// and South).
const SOUTH_AMERICA = new Set(['AR', 'BO', 'BR', 'CL', 'CO', 'EC', 'FK', 'GF', 'GY', 'PE', 'PY', 'SR', 'UY', 'VE', 'GS']);
const FORCE = { RU: 'europe', TR: 'europe', US: 'north_america', CA: 'north_america', MX: 'north_america',
  PT: 'europe', ES: 'europe', IS: 'europe', FO: 'europe', CV: 'africa', MV: 'asia', IO: 'asia', CY: 'asia' };
const REGION = { Asia: 'asia', Europe: 'europe', Africa: 'africa', Australia: 'oceania', Pacific: 'oceania', Indian: 'africa', Atlantic: 'europe', Antarctica: 'oceania' };
const tzByCountry = new Map();
for (const r of rows) {
  const head = r.tz.split('/')[0];
  const m = tzByCountry.get(r.cc) ?? new Map();
  m.set(head, (m.get(head) ?? 0) + 1);
  tzByCountry.set(r.cc, m);
}
export const continent = cc => {
  if (FORCE[cc]) return FORCE[cc];
  if (SOUTH_AMERICA.has(cc)) return 'south_america';
  const m = tzByCountry.get(cc);
  const head = m ? [...m].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1))[0][0] : 'Europe';
  return head === 'America' ? 'north_america' : REGION[head] ?? 'europe';
};

// Neighbour lookup on a 0.5° grid (30 km < 0.5° of latitude; longitude cells widen toward the poles, so the search
// spans enough cells east and west for the latitude).
const CELL = 0.5;
const cellKey = (i, j) => `${i}:${j}`;
const seeds = new Map();   // cell → seed cities in it
const addSeed = r => { const k = cellKey(Math.floor(r.lat / CELL), Math.floor(r.lng / CELL)); (seeds.get(k) ?? seeds.set(k, []).get(k)).push(r); };
const nearestSeed = r => {
  const i = Math.floor(r.lat / CELL), j = Math.floor(r.lng / CELL);
  const span = Math.min(180, Math.ceil(CLUSTER_KM / (111 * CELL * Math.max(0.05, Math.cos(r.lat * rad)))));
  let best = null, bestKm = Infinity;
  for (let di = -1; di <= 1; di++) for (let dj = -span; dj <= span; dj++) for (const s of seeds.get(cellKey(i + di, j + dj)) ?? []) {
    const d = km(r, s);
    if (d <= CLUSTER_KM && (d < bestKm || (d === bestKm && s.id < best.id))) { best = s; bestKm = d; }
  }
  return best;
};

// Cities taken out of the cluster the merge put them in, each its own cluster from then on (SGODOT-280).
const SPLIT_OUT = [
  { id: 'gn-5391811', why: 'San Diego (US, 1.4 M) had joined Tijuana (MX) 28 km away; players went to "San Diego" and stood in Tijuana' },
];

// Frozen assignments from the last build.
const of = new Map();
if (existsSync(MEMBERS)) {
  for (const l of readFileSync(MEMBERS, 'utf8').split('\n')) {
    if (!l || l.startsWith('#')) continue;
    const [city, cluster] = l.split('\t');
    if (byId.has(city) && byId.has(cluster)) of.set(city, cluster);
  }
}
for (const { id } of SPLIT_OUT) if (byId.has(id)) of.set(id, id);
for (const id of new Set(of.values())) addSeed(byId.get(id));
const fresh = of.size === 0;

// Most populous first (ties by id): deterministic. On a fresh build a city within 30 km of an earlier seed joins it
// (the greedy merge); on a rebuild only cities new to the directory are placed, the same way.
const order = [...rows].sort((a, b) => b.pop - a.pop || (a.id < b.id ? -1 : 1));
let added = 0;
for (const r of order) {
  if (of.has(r.id)) continue;
  const s = nearestSeed(r);
  if (s) of.set(r.id, s.id);
  else { of.set(r.id, r.id); addSeed(r); }
  added++;
}

const members = new Map();
for (const [city, cluster] of of) members.set(cluster, (members.get(cluster) ?? 0) + 1);
const clusters = [...members.keys()].map(id => byId.get(id)).sort((a, b) => b.pop - a.pop || (a.id < b.id ? -1 : 1));

const FIELDS = ['id', 'name', 'lat', 'lng', 'country_code', 'country', 'population', 'members', 'climate', 'continent', 'timezone'];
writeFileSync(OUT, '{"_note": "P0 city clusters (SGODOT-275, plan v2 §11.1): cities15000 (GeoNames, CC BY 4.0) merged within 30 km, '
  + 'most populous first. Keys are frozen (saves hold them): rebuild with server/tools/build_clusters.mjs, which keeps existing '
  + 'assignments.",\n "fields": ' + JSON.stringify(FIELDS) + ',\n "rows": [\n'
  + clusters.map(c => JSON.stringify([c.id, c.name, +c.lat.toFixed(5), +c.lng.toFixed(5), c.cc, c.country, c.pop, members.get(c.id),
    climate(c.lat), continent(c.cc), c.tz])).join(',\n') + '\n]}\n');
writeFileSync(MEMBERS, '# city id → P0 city cluster id (assets/p0/city_clusters.json); frozen, see server/tools/build_clusters.mjs\n'
  + [...of].sort((a, b) => (a[0] < b[0] ? -1 : 1)).map(([c, k]) => `${c}\t${k}`).join('\n') + '\n');
console.log(`${fresh ? 'built' : 'rebuilt'}: ${rows.length} cities → ${clusters.length} clusters (${added} placed this run)`);
