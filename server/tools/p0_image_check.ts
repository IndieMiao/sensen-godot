/**
 * Start-up data check for a P0 server image (0.2.0, 李元芳): run inside the image before it ships.
 *   docker run --rm --entrypoint ./node_modules/.bin/tsx p0-server:<sha> tools/p0_image_check.ts
 * Every file the server reads at start must be there and the content must load with its city clusters: a missing member
 * table (server/data/city_cluster_members.tsv) ends the process at start, and a missing cities.tsv quietly mis-tiers cities,
 * so both have to fail here instead of on Hong Kong.
 */
import { existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadP0Content } from '../src/p0/content.js';
import { clusterPopulation, waterTable } from '../src/p0/world.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
// cities.tsv: global generation sums a cluster's population from it (clusterPopulation) and falls back quietly without
// it, so a city like Miami would silently drop to a lower tier (后裔 on #254).
const files = ['assets/p0/p0_content.json', 'assets/p0/p0_outposts.json', 'assets/p0/p0_ponds.json', 'assets/p0/city_clusters.json',
  'server/data/city_cluster_members.tsv', 'server/data/cities.tsv', 'server/data/world_water.json', 'assets/ponds/catalog.json',
  'assets/farm/data/regions.json'];
const missing = files.filter(f => !existsSync(path.join(root, f)) || statSync(path.join(root, f)).size === 0);
const fragments = existsSync(path.join(root, 'assets/p0/content')) ? readdirSync(path.join(root, 'assets/p0/content')).filter(f => f.endsWith('.json')) : [];
if (!fragments.length) missing.push('assets/p0/content/*.json');
if (missing.length) { console.log(JSON.stringify({ ok: false, missing })); process.exit(1); }
const c = loadP0Content() as ReturnType<typeof loadP0Content> & { clusters?: { byId: Map<string, unknown> }; cityPlaces?: (id: string) => unknown };
const clusters = c.clusters?.byId.size ?? 0;
const tokyo = c.cityPlaces?.('gn-1850147') as { ponds?: string[] } | null | undefined;
// Miami (gn-4164138): its cluster's summed population, which only comes out right with both tables read.
const miamiCluster = (c.clusters as unknown as { get(id: string): Parameters<typeof clusterPopulation>[0] | undefined } | undefined)?.get('gn-4164138');
const miami = miamiCluster ? clusterPopulation(miamiCluster) : 0;
// world_water.json (q(126)): without it generated places stand in rivers and the sea again; made for this world's seed
// and revision, or cityPlaces throws (Tokyo above would have).
const water = waterTable(), world = (c as unknown as { world?: { seed: string; revision: number } }).world;
const waterFixes = water && world && water.seed === world.seed && water.revision === world.revision ? Object.keys(water.fixes).length : 0;
const ok = clusters > 10_000 && !!tokyo?.ponds?.length && miami === 780_231 && waterFixes > 1000;
console.log(JSON.stringify({ ok, content: c.version, fragments: fragments.length, clusters, tokyo_ponds: tokyo?.ponds?.length ?? 0, miami_population: miami, water_fixes: waterFixes }));
process.exit(ok ? 0 : 1);
