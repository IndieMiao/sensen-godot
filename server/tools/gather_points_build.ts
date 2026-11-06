/**
 * v4q(4) city gathering points (SGODOT-355, v4 §4.1), offline: San Francisco, the open home cities and each one's nearest
 * 10 get the kinds of world_gen.json `gather_points` placed round their base point, off water (ESA WorldCover, through
 * tools/world_water_lib.ts) and clear of the city's ponds and outposts → server/data/gather_points.json, which only the
 * server reads (src/p0/gather_points.ts). Review rows in output/gather-points/.
 *
 *   npx tsx tools/gather_points_build.ts                 (places and names every point; reads WorldCover)
 *   npx tsx tools/gather_points_build.ts --names-only    (keeps the table's points, names them again from wild.words)
 *
 * Deterministic: every draw is hash32(seed, point id, topic); the WorldCover reads are the only network.
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { distanceKm, type CityCluster } from '../src/p0/clusters.js';
import { loadP0Content, type P0Content } from '../src/p0/content.js';
import { clusterById, homeBase } from '../src/p0/home.js';
import { fallbackOf, writtenCluster } from '../src/p0/travel.js';
import { cityPlaces, hash32, offset, worldOf } from '../src/p0/world.js';
import { dryM, stats, waterMap, type WaterMap } from './world_water_lib.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

export interface KindRule { tier: string; word: string; yield: [string, number][]; home: number; other: number; near_water_m?: number }
export interface GatherRules {
  ring_km: [number, number]; apart_m: number; from_places_m: number; dry_m: number; tries: number;
  energy: number; cooldown_h: number; t2_with_near3: number; kinds: Record<string, KindRule>;
}
interface Point { cluster: string; kind: string; n: number; lat: number; lng: number; word: string; water_m: number | null }

const c: P0Content = loadP0Content();
const world = worldOf(c)!;
const rules = (world as unknown as { gather_points: GatherRules }).gather_points;
const words = (world as unknown as { wild?: { words?: Record<string, string[]> } }).wild?.words ?? (world.ponds.words as Record<string, string[]>);
const homes = [writtenCluster(c), ...((world as unknown as { home: { cities: string[] } }).home.cities)];
const near3 = new Map(homes.map(h => [h, fallbackOf(c, h).near3]));
const cities = [...new Set([...homes, ...homes.flatMap(h => fallbackOf(c, h).near10)])].sort();

// how many of each kind a city gets: home / other, then the T2 top-up for each home and its nearest 3
const count = new Map<string, Record<string, number>>();
for (const id of cities) {
  const home = homes.includes(id);
  count.set(id, Object.fromEntries(Object.entries(rules.kinds).map(([k, r]) => [k, home ? r.home : r.other])));
}
for (const h of homes) {
  for (const [kind, r] of Object.entries(rules.kinds)) {
    if (r.tier !== 'T2') continue;
    const group = [h, ...near3.get(h)!];
    let have = group.reduce((a, id) => a + (count.get(id)?.[kind] ?? 0), 0);
    // the missing ones go round the nearest 3, nearest first
    for (let i = 0; have < rules.t2_with_near3 && group.length > 1; i++) { count.get(group[1 + (i % (group.length - 1))])![kind] += 1; have++; }
  }
}

/** The city's own places to keep clear of: the written city's hand-written tables, else the generator's. */
function placesOf(id: string): { lat: number; lng: number }[] {
  if (id === writtenCluster(c)) {
    const x = c as unknown as { outposts: { cluster?: string; lat: number; lng: number }[]; fishing: { places: Record<string, { cluster?: string; at: [number, number] }> } };
    return [...x.outposts.filter(o => o.cluster === id).map(o => ({ lat: o.lat, lng: o.lng })),
      ...Object.values(x.fishing.places).filter(p => p.cluster === id).map(p => ({ lat: p.at[0], lng: p.at[1] }))];
  }
  const city = cityPlaces(c, id)!;
  return [...city.detail.ponds, ...city.detail.outposts, ...city.detail.huts].map(p => ({ lat: p.lat, lng: p.lng }));
}

/** A city's points named: a word of its climate band's pool, never twice in the city (in placing order). */
function nameCity(id: string, points: Point[]): void {
  const cl = clusterById(c, id) as CityCluster | undefined;
  const band = (cl?.climate ?? String((c as unknown as { profile: { climate: string } }).profile.climate).toLowerCase());
  const pool = words[band.charAt(0).toUpperCase() + band.slice(1)] ?? [];
  if (!pool.length) throw new Error(`no wild words for ${id} (${band})`);
  const used = new Set<string>();
  for (const p of points) {
    const start = hash32(world.seed, `${p.cluster}~${p.kind}${p.n}`, 'word') % pool.length;
    p.word = pool[start];
    for (let i = 0; i < pool.length; i++) { const w = pool[(start + i) % pool.length]; if (!used.has(w)) { p.word = w; break; } }
    used.add(p.word);
  }
}

async function placeCity(id: string): Promise<{ points: Point[]; failed: string[] }> {
  const base = homeBase(c, { travel: { home: id } })!;
  const r1 = rules.ring_km[1] + 0.5, dLat = r1 / 111.2, dLng = r1 / (111.2 * Math.cos(base.lat * Math.PI / 180));
  let water: WaterMap | null = null;
  try { water = await waterMap(base.lat - dLat, base.lng - dLng, base.lat + dLat, base.lng + dLng); } catch { water = null; }
  const keepClear = placesOf(id), points: Point[] = [], failed: string[] = [];
  for (const [kind, r] of Object.entries(rules.kinds)) {
    for (let n = 0; n < count.get(id)![kind]; n++) {
      const pid = `${id}~${kind}${n}`;
      let best: Point | null = null;
      for (let t = 0; t < rules.tries && !best; t++) {
        const u = hash32(world.seed, pid, `a${t}`) / 2 ** 32, v = hash32(world.seed, pid, `r${t}`) / 2 ** 32;
        const km = rules.ring_km[0] + (rules.ring_km[1] - rules.ring_km[0]) * Math.sqrt(v);
        const at = offset(base.lat, base.lng, km, u * 360);
        const wet = water ? dryM(water, at) : null;
        if (wet !== null && wet < rules.dry_m) continue;
        // a reed bank looks for the water's edge first; past half its tries any dry point does
        if (r.near_water_m && wet !== null && wet > r.near_water_m && t < rules.tries / 2) continue;
        if (keepClear.some(p => distanceKm(p, at) * 1000 < rules.from_places_m)) continue;
        if (points.some(p => distanceKm(p, at) * 1000 < rules.apart_m)) continue;
        best = { cluster: id, kind, n, lat: +at.lat.toFixed(6), lng: +at.lng.toFixed(6), word: '', water_m: wet === null ? null : Math.round(Math.min(wet, 99_999)) };   // no water in the window reads as far
      }
      if (!best) { failed.push(pid); continue; }
      points.push(best);
    }
  }
  nameCity(id, points);
  return { points, failed };
}

const all: Point[] = [], failed: string[] = [];
const out = path.join(ROOT, 'server/data/gather_points.json');
if (process.argv.includes('--names-only')) {   // (the review file's water column reads '-' then: see the full run's)
  // the table's points as they are (no WorldCover), named again: a new word pool needs no new places
  const old = JSON.parse(readFileSync(out, 'utf8')) as { fields: string[]; rows: unknown[][] };
  const at = (f: string) => old.fields.indexOf(f);
  for (const r of old.rows) all.push({ cluster: r[at('cluster')] as string, kind: r[at('kind')] as string, n: r[at('n')] as number,
    lat: r[at('lat')] as number, lng: r[at('lng')] as number, word: '', water_m: null });
  for (const id of new Set(all.map(p => p.cluster))) nameCity(id, all.filter(p => p.cluster === id));
} else {
  for (const [i, id] of cities.entries()) {
    const got = await placeCity(id);
    all.push(...got.points); failed.push(...got.failed);
    if (i % 10 === 0) console.log(`${i + 1}/${cities.length} ${id} (${stats.requests} reads, ${(stats.bytes / 1e6).toFixed(0)} MB)`);
  }
}
const table = {
  _note: 'v4q(4) city gathering points, made by server/tools/gather_points_build.ts with world_gen.json `gather_points` (WorldCover for water). id = <cluster>~<kind><n>. Frozen with the wild sites at batch 1\'s release.',
  seed: world.seed, revision: world.revision, fields: ['cluster', 'kind', 'n', 'lat', 'lng', 'word'],
  rows: all.map(p => [p.cluster, p.kind, p.n, p.lat, p.lng, p.word]),
};
writeFileSync(out, JSON.stringify(table) + '\n');
const dir = path.join(ROOT, 'server/output/gather-points');
mkdirSync(dir, { recursive: true });
writeFileSync(path.join(dir, 'points.tsv'), ['id\tkind\tlat\tlng\tname\twater_m\thome', ...all.map(p =>
  `${p.cluster}~${p.kind}${p.n}\t${p.kind}\t${p.lat}\t${p.lng}\t${p.word} ${rules.kinds[p.kind].word}\t${p.water_m ?? '-'}\t${homes.includes(p.cluster) ? 1 : 0}`)].join('\n') + '\n');
writeFileSync(path.join(dir, 'failed.txt'), failed.join('\n') + '\n');
const namesOnly = process.argv.includes('--names-only');
console.log(JSON.stringify(namesOnly ? { names_only: true, cities: new Set(all.map(p => p.cluster)).size, points: all.length }
  : { cities: cities.length, points: all.length, failed: failed.length, no_water_data: all.filter(p => p.water_m === null).length }));
