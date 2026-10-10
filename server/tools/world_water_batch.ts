/**
 * The water table for every generated city (SGODOT-280, q(126)): checks each cluster's places against ESA WorldCover
 * and writes the moves into server/data/world_water.json, which world.ts lays over the generator before world.overrides.
 *
 *   npx tsx tools/world_water_batch.ts run --shard 0/4 [--out output/world-water] [--only gn-…,gn-…]
 *       one shard of the clusters (a run of them in WorldCover tile order); resumable: a cluster already in the shard's
 *       file is skipped, a failed one is tried again. Run the shards side by side (network-bound: 20 or more).
 *   npx tsx tools/world_water_batch.ts run --retry wide --search 8000 --only gn-…,gn-…
 *       those cities again with a wider search (where no land kept the rules within 3 km), read by merge after the shards
 *   npx tsx tools/world_water_batch.ts merge [--out output/world-water]
 *       every shard into server/data/world_water.json (stamped with world.seed and revision) and review.tsv: moves
 *       over 1 km, cities with ≥ 30 % of their places moved, places with no land in reach (q(126) ②: look at these).
 *
 * Places with a hand fix in world.overrides stay where the hand put them (they still count for the rules).
 * Data: ESA WorldCover 2021 v200, © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021)
 * processed by ESA WorldCover consortium (CC BY 4.0; credited in the app per q(129)).
 */
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { CityCluster } from '../src/p0/clusters.js';
import { loadP0Content, type P0Content } from '../src/p0/content.js';
import { homeCluster } from '../src/p0/travel.js';
import { generateCity, type WaterTable, type WorldContent } from '../src/p0/world.js';
import { fixCity, ruleOk, stats, type Move, type Place } from './world_water_lib.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const args = process.argv.slice(2);
const opt = (name: string, dflt = '') => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : dflt; };
const out = path.resolve(ROOT, opt('out', 'output/world-water'));
mkdirSync(out, { recursive: true });

const c = loadP0Content();
const w = (c as P0Content & { world: WorldContent }).world;
const clusters = (c as P0Content & { clusters: { byId: Map<string, CityCluster> } }).clusters;

interface Line { cluster: string; name?: string; tier?: string; places?: number; wet?: { id: string; water_m: number }[]; moved?: Move[];
  failed?: string[]; still_bad?: string[]; no_data?: true; error?: string; s?: number; mb?: number }

const readLines = (file: string): Line[] => existsSync(file)
  ? readFileSync(file, 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l) as Line) : [];

if (args[0] === 'run') {
  const [shard, of] = opt('shard', '0/1').split('/').map(Number);
  const only = opt('only') ? new Set(opt('only').split(',')) : null;
  // --retry <tag> --search <m>: cities again with a wider search (places with no land in 3 km), into retry-<tag>.jsonl,
  // which merge reads after the shards
  const retry = opt('retry');
  const searchM = Number(opt('search', '3000'));
  const file = path.join(out, retry ? `retry-${retry}.jsonl` : `shard-${shard}-of-${of}.jsonl`);
  const done = new Set(readLines(file).filter(l => !l.error).map(l => l.cluster));
  const home = homeCluster(c);   // hand-written, never generated
  // In WorldCover tile order, cut into n runs: neighbours share a tile already opened (each new tile costs a few slow
  // round trips), so a shard is a stretch of the map rather than every n-th city.
  const tileKey = (cl: CityCluster) => `${String(Math.floor(cl.lat / 3) * 3 + 90).padStart(3, '0')}:${String(Math.floor(cl.lng / 3) * 3 + 180).padStart(3, '0')}:${cl.id}`;
  const all = [...clusters.byId.values()].filter(cl => cl.id !== home).sort((a, b) => tileKey(a).localeCompare(tileKey(b))).map(cl => cl.id);
  const from = Math.floor((all.length * shard) / of), to = Math.floor((all.length * (shard + 1)) / of);
  const ids = only ? all.filter(id => only.has(id)) : all.slice(from, to);
  const fixed = new Set(Object.keys(w.overrides ?? {}).filter(k => !k.startsWith('_')));
  let n = 0;
  for (const id of ids) {
    if (done.has(id)) continue;
    const cl = clusters.byId.get(id)!;
    const t0 = Date.now(), b0 = stats.bytes;
    let line: Line;
    try {
      const city = generateCity(c, cl, { water: false });
      const places: Place[] = [...city.detail.ponds.map(p => ({ ...p, kind: 'pond' as const, fixed: fixed.has(p.id) })),
        ...city.detail.outposts.map(o => ({ ...o, kind: 'outpost' as const, fixed: fixed.has(o.id) }))];
      const r = await fixCity(cl, places, searchM);
      line = { ...r, name: cl.name, tier: city.tier };
    } catch (e) {
      line = { cluster: id, name: cl.name, error: String((e as Error).message ?? e).slice(0, 300) };
    }
    line.s = Math.round((Date.now() - t0) / 100) / 10;
    line.mb = Math.round((stats.bytes - b0) / 1e5) / 10;
    appendFileSync(file, JSON.stringify(line) + '\n');
    if (++n % 25 === 0) console.log(`${new Date().toISOString()} shard ${shard}/${of}: ${n} done, ${(stats.bytes / 1e9).toFixed(2)} GB`);
  }
  console.log(`shard ${shard}/${of} finished: ${n} cities this run`);
} else if (args[0] === 'merge') {
  const last = new Map<string, Line>();
  const order = (f: string) => (f.startsWith('retry-') ? 1 : 0);
  for (const f of readdirSync(out).filter(f => (f.startsWith('shard-') || f.startsWith('retry-')) && f.endsWith('.jsonl'))
    .sort((a, b) => order(a) - order(b) || a.localeCompare(b))) {
    // per city the run that left the fewest places on water; on a tie the later run (a retry after the shards)
    for (const l of readLines(path.join(out, f))) {
      const prior = last.get(l.cluster);
      if (l.error && prior) continue;
      if (!prior || prior.error || (l.failed?.length ?? 0) <= (prior.failed?.length ?? 0)) last.set(l.cluster, l);
    }
  }
  const expected = [...clusters.byId.keys()].filter(id => id !== homeCluster(c));
  const missing = expected.filter(id => !last.has(id) || last.get(id)!.error);
  const fixes: WaterTable['fixes'] = {};
  // a place given a hand fix since the run is the hand's (as a rerun would skip it)
  const handFixed = new Set(Object.keys(w.overrides ?? {}).filter(k => !k.startsWith('_')));
  const review: string[] = ['kind\tcluster\tcity\tid\tname\tmoved_m\tfrom\tto\twater_m'];
  let places = 0, moved = 0;
  for (const id of [...last.keys()].sort()) {
    const l = last.get(id)!;
    if (l.error) continue;
    if (l.failed?.length) {
      const kept = keepRules(id, l.moved ?? []);
      for (const m of (l.moved ?? []).filter(m => !kept.includes(m))) review.push(['kept_on_water', id, l.name, m.id, m.name, '', m.from.join(','), '', ''].join('\t'));
      l.moved = kept;
    }
    places += l.places ?? 0; moved += l.moved?.length ?? 0;
    const share = (l.moved?.length ?? 0) / Math.max(1, l.places ?? 1);
    for (const m of l.moved ?? []) {
      if (handFixed.has(m.id)) continue;
      fixes[m.id] = [r6(m.to[0]), r6(m.to[1]), m.from[0], m.from[1], m.water_m];
      if (m.moved_m > 1000 || share >= 0.3) {
        review.push([m.moved_m > 1000 ? 'over_1km' : 'city_30pct', id, l.name, m.id, m.name, m.moved_m, m.from.join(','), m.to.map(r6).join(','), m.water_m].join('\t'));
      }
    }
    for (const f of [...(l.failed ?? []), ...(l.still_bad ?? []).filter(x => !(l.failed ?? []).includes(x))]) {
      review.push(['no_land', id, l.name, f, '', '', '', '', ''].join('\t'));
    }
  }
  for (const id of missing) review.push(['not_checked', id, clusters.byId.get(id)!.name, '', '', '', '', '', ''].join('\t'));
  for (const [id, l] of last) if (l.no_data) review.push(['no_data', id, l.name, '', '', '', '', '', ''].join('\t'));
  const table: WaterTable & { _note: string; source: string } = {
    _note: 'Generated places moved off water (SGODOT-280, q(126)) by tools/world_water_batch.ts: id → [lat, lng, generated lat, generated lng, metres from water]. Only for the seed and revision below; world.overrides (hand fixes) wins over it. Do not edit by hand: change world.overrides, or rerun the batch.',
    source: 'ESA WorldCover 2021 v200 (10 m), © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium, CC BY 4.0',
    seed: w.seed, revision: w.revision, fixes };
  writeFileSync(path.join(ROOT, 'server/data/world_water.json'), JSON.stringify(table) + '\n');
  writeFileSync(path.join(out, 'review.tsv'), review.join('\n') + '\n');
  console.log(JSON.stringify({ cities: last.size, expected: expected.length, not_checked: missing.length, places, moved,
    review: review.length - 1, table_kb: Math.round(JSON.stringify(table).length / 1024) }));
} else {
  console.log('usage: world_water_batch.ts run --shard i/n [--out dir] [--only ids] | merge [--out dir]');
  process.exit(2);
}

function r6(v: number) { return Math.round(v * 1e6) / 1e6; }

/**
 * A city where some place found no land: a move that leaves another place breaking the rules (a tackle shop left on the
 * water 1.5 km from its moved pond, Market Square 1 from its moved beginner pond) is undone, the anchor with it, until
 * every rule holds. Those places stay as generated (on the water), listed in review.tsv for a hand fix.
 */
function keepRules(cluster: string, moves: Move[]): Move[] {
  const cl = clusters.byId.get(cluster)!;
  const fixed = new Set(Object.keys(w.overrides ?? {}).filter(k => !k.startsWith('_')));
  const city = generateCity(c, cl, { water: false });
  const base: Place[] = [...city.detail.ponds.map(p => ({ ...p, kind: 'pond' as const, fixed: fixed.has(p.id) })),
    ...city.detail.outposts.map(o => ({ ...o, kind: 'outpost' as const, fixed: fixed.has(o.id) }))];
  let kept = [...moves];
  for (let round = 0; round < 20; round++) {
    const places = base.map(p => { const m = kept.find(x => x.id === p.id); return m ? { ...p, lat: m.to[0], lng: m.to[1] } : { ...p }; });
    const broken = places.filter(p => !ruleOk(cl, places, p, p));
    if (!broken.length) return kept;
    const undo = new Set<string>();
    for (const p of broken) {
      undo.add(p.id);
      if (p.kind === 'outpost' && p.role === 'tackle') { const pond = places.find(q => q.kind === 'pond' && q.name === p.nearest?.name); if (pond) undo.add(pond.id); }
      if (p.id.endsWith('~market0')) { const b = places.find(q => q.kind === 'pond' && q.beginner); if (b) undo.add(b.id); }
    }
    const before = kept.length;
    kept = kept.filter(m => !undo.has(m.id));
    if (kept.length === before) break;
  }
  console.log(`${cluster}: rules still broken after undoing moves`);
  return kept;
}
