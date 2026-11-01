/**
 * v4q(3) wild-site catalogue (SGODOT-355), offline: Natural Earth 10m land and lakes (GeoJSON) → server/data/wild_sites.json,
 * plus review files in output/wild-sites (counts, the guarantees that could not be met, the open home cities' near sites).
 *
 *   npx tsx tools/wild_sites_build.ts --land <ne_10m_land.geojson> --lakes <ne_10m_lakes.geojson> --countries <ne_10m_admin_0_countries.geojson>
 *
 * The world's seed and revision stamp the table (src/p0/wild.ts refuses another world's). Rules and numbers: world_gen.json
 * `wild` (see its _note) and tools/wild_sites_lib.ts.
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadP0Content } from '../src/p0/content.js';
import { clustersOf } from '../src/p0/home.js';
import { worldOf } from '../src/p0/world.js';
import { ClusterIndex, countryRaster, guarantee, nameSites, placeSites, polygonsOf, Raster, SiteIndex, TYPES, drawTypes, fullName,
  type Site, type WildConfig } from './wild_sites_lib.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const arg = (name: string) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : undefined; };
const t0 = Date.now(), lap = (what: string) => console.log(`${((Date.now() - t0) / 1000).toFixed(1)}s ${what}`);

const c = loadP0Content();
const world = worldOf(c)!;
const cfg = (world as unknown as { wild: WildConfig }).wild;
// trials for the rule review: --city-min-km N tries another distance from the cities, written to output/ only
const trial = arg('city-min-km');
if (trial) cfg.city_min_km = Number(trial);
// the game's clusters: a closed country's are not in them (content.ts, q(189)), and its land gets no site either
const clusters = [...clustersOf(c)!.byId.values()];
cfg.exclude_countries = c.travel?.closed_countries ?? [];
if (!cfg.words) console.log('WARNING: world_gen.json wild.words is not there yet — the ponds\' words stand in (review ⑤: 李白\'s own pool replaces them)');
const land = new Raster(cfg.raster_deg).fill(polygonsOf(JSON.parse(readFileSync(arg('land')!, 'utf8'))));
lap('land rastered');
const lakes = new Raster(cfg.raster_deg).fill(polygonsOf(JSON.parse(readFileSync(arg('lakes')!, 'utf8'))));
lap('lakes rastered');
const countries = countryRaster(cfg.raster_deg, JSON.parse(readFileSync(arg('countries')!, 'utf8')));
lap('countries rastered');
const sites = placeSites(cfg, world.seed, land, lakes, new ClusterIndex(clusters), countries.at);
lap(`${sites.length} sites placed`);
drawTypes(cfg, world.seed, sites);
const short = guarantee(cfg, world.seed, sites, clusters);
lap(`guarantees (${short.length} short)`);
nameSites(cfg, world.seed, sites, cfg.words ?? world.ponds.words);
lap('named');

const fields = ['row', 'col', 'lat', 'lng', 'type', 'main', 'side', 'floors', 'coastal', 'near', 'word', 'country'];
const table = {
  _note: 'v4q(3) wild sites, made by server/tools/wild_sites_build.ts from Natural Earth 10m land and lakes (public domain) with world_gen.json `wild`. id = wd-<row>-<col>; type indexes `types`. Not frozen yet: frozen at batch 1\'s release, after 李白\'s simulator check and the user\'s review.',
  seed: world.seed, revision: world.revision, grid_deg: cfg.grid_deg, types: TYPES, fields,
  rows: sites.map(s => [s.row, s.col, s.lat, s.lng, TYPES.indexOf(s.type), s.main, s.side, s.floors, s.coastal ? 1 : 0, s.near, s.word, s.country]),
};
const out = trial ? path.join(ROOT, `server/output/wild-sites/trial-${trial}km.json`) : path.join(ROOT, 'server/data/wild_sites.json');
mkdirSync(path.dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(table) + '\n');
lap(`wrote ${out} (${(JSON.stringify(table).length / 1e6).toFixed(2)} MB)`);

// ---- review files ---------------------------------------------------------------------------------------------
const dir = path.join(ROOT, 'server/output/wild-sites', trial ? `trial-${trial}km` : '');
mkdirSync(dir, { recursive: true });
const count = (key: (s: Site) => string) => {
  const m = new Map<string, number>();
  for (const s of sites) m.set(key(s), (m.get(key(s)) ?? 0) + 1);
  return [...m.entries()].sort(([a], [b]) => (a < b ? -1 : 1));
};
const lines = [`sites ${sites.length}`, '', 'by type:', ...count(s => s.type).map(([k, n]) => `  ${k} ${n}`),
  '', 'by continent × type:', ...count(s => `${s.continent} ${s.type}`).map(([k, n]) => `  ${k} ${n}`),
  '', 'veins by main:', ...count(s => (s.type === 'vein' ? `${s.main}` : '-')).filter(([k]) => k !== '-').map(([k, n]) => `  ${k} ${n}`),
  '', 'quarries by side:', ...count(s => (s.type === 'quarry' ? `${s.side}` : '-')).filter(([k]) => k !== '-').map(([k, n]) => `  ${k} ${n}`),
  '', 'by country (first 15):', ...count(s => s.country || '(none)').sort((a, b) => b[1] - a[1]).slice(0, 15).map(([k, n]) => `  ${k} ${n}`),
  '', `short (${short.length}):`,
  ...['quarry', 'vein', 'geode'].map(k => `  ${k}: ${short.filter(x => x.need === k).length}`)];
writeFileSync(path.join(dir, 'summary.txt'), lines.join('\n') + '\n');
writeFileSync(path.join(dir, 'short.tsv'), ['cluster\tname\tneed\thave\twant', ...short.map(x => `${x.cluster}\t${x.name}\t${x.need}\t${x.have}\t${x.want}`)].join('\n') + '\n');

// the open home cities (SF and world.home.cities): the nearest sites, what is within Trip 2, the nearest geode
const homes = ['gn-5391959', ...((world as unknown as { home: { cities: string[] } }).home.cities)];
const index = new SiteIndex(sites, cfg.grid_deg);
const rows = ['city\tnearest 3 (km type main/side)\tquarries ≤100 km (side)\tveins ≤100 km\tnearest geode km'];
for (const id of homes) {
  const cl = clusters.find(x => x.id === id)!;
  const near = index.around(cl.lat, cl.lng, 600);
  const fmt = (x: { s: Site; km: number }) => `${x.km.toFixed(0)} ${x.s.type}${x.s.main ? ` ${x.s.main}` : x.s.side !== null ? ` side${x.s.side}` : ''} "${fullName(cfg, x.s)}"`;
  const q = near.filter(x => x.km <= cfg.near.trip2_km && x.s.type === 'quarry');
  const v = near.filter(x => x.km <= cfg.near.trip2_km && x.s.type === 'vein');
  const g = near.find(x => x.s.type === 'geode');
  rows.push(`${cl.name}\t${near.slice(0, 3).map(fmt).join(' | ')}\t${q.map(x => `${x.km.toFixed(0)} side${x.s.side}`).join(', ')}\t${v.map(x => `${x.km.toFixed(0)} ${x.s.main}`).join(', ')}\t${g ? g.km.toFixed(0) : '-'}`);
}
writeFileSync(path.join(dir, 'home-cities.tsv'), rows.join('\n') + '\n');
console.log(lines.join('\n'));
console.log(rows.join('\n'));
