/**
 * Farm spots for the home pick (SGODOT-303, q(160) ②), offline. For each open city (the written city and world.home.cities):
 *   run    3 base spots round its beginner pond keeping the run-time rules (home_city.ts: 0.5–3 km from the pond with room
 *          for the 100–200 m scatter, 300 m + scatter clear of every outpost and pond, 1 km + scatter apart, directions
 *          at least 90° apart so the card's compass words differ), on built-up land (WorldCover 50) at least 250 m from
 *          water (so every scattered spot keeps q(160)'s 50 m), with a district name (Mapbox reverse geocoding,
 *          neighbourhood, else locality). Merged into server/data/home_spots.json, stamped with the world seed and
 *          revision; <out>/review.tsv lists them.
 *   check  the acceptance items (q(160) ①, q(162) ⑤): the home set complete, its tackle shop by the beginner pond, the
 *          beginner pond giving Pond Crucian (Pond Catch), its outposts off the water, and for 40 sample players every
 *          scattered spot ≥ 50 m from water and inside the rules. <out>/check.tsv; exit 1 on any failure.
 *   maps   one Mapbox static map per city: P beginner pond, m / t / k / s its market, tea house, tackle shop and post,
 *          1–3 the spots. For 不知火舞's acceptance.
 *   npx tsx tools/home_spots.ts run|check|maps [--cities gn-1,gn-2] [--out output/home-spots]
 * The Mapbox token is read from mapbox_token.txt and never printed.
 */
import { execFile } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { loadP0Content } from '../src/p0/content.js';
import { pondFishIds } from '../src/p0/fishing_world.js';
import { clusterById, writtenCluster } from '../src/p0/home.js';
import { citySet, citySpots, cityOutposts, cityPonds, homeRules, homeSpots, type SpotTable } from '../src/p0/home_city.js';
import { hash32, km, offset, worldOf } from '../src/p0/world.js';
import { classAt, dryM, waterMap } from './world_water_lib.js';

const run = promisify(execFile);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const TABLE = path.join(ROOT, 'server/data/home_spots.json');
const BUILT_UP = 50, DRY_M = 250, SPOT_DRY_M = 50, MIN_TURN = 90, SAMPLE_PLAYERS = 40;

const args = process.argv.slice(2);
const cmd = args[0];
const opt = (name: string) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : undefined; };
const c = loadP0Content(), w = worldOf(c)!, rules = homeRules(c);
const cities = opt('cities')?.split(',') ?? [writtenCluster(c), ...rules.cities.filter(id => id !== writtenCluster(c))];
const out = path.resolve(ROOT, opt('out') ?? 'output/home-spots');
mkdirSync(out, { recursive: true });
const token = () => readFileSync(path.join(ROOT, 'mapbox_token.txt'), 'utf8').trim();
const nameOf = (id: string) => (id === writtenCluster(c) ? c.profile.city : clusterById(c, id)?.name ?? id);
const exKm = ((w.placement as { farm_exclusion_m?: number }).farm_exclusion_m ?? 300) / 1000;
const scKm = rules.spot.scatter_m[1] / 1000;

async function curl(url: string, file?: string): Promise<Buffer> {
  for (let i = 0; ; i++) {
    try {
      const { stdout } = await run('curl', ['-sS', '-f', '-m', '60', ...(file ? ['-o', file] : []), url], { encoding: 'buffer', maxBuffer: 64 << 20 });
      return stdout as Buffer;
    } catch (e) {
      if (i >= 3) throw new Error(`request failed (${(e as { code?: number }).code ?? '?'})`);   // the URL carries the token: never print it
    }
  }
}

/** A label as a card line takes it: a Tokyo chōme number (`Sendagaya 5`) and Mexico's `Colonia ` go. */
const clean = (n: string) => n.replace(/\s+\d+$/, '').replace(/^Colonia\s+/, '').trim();
const HOOD_MAX = 20;

/** The district name a point shows on the map: the nearest suburb / quarter / neighbourhood label (Mapbox Streets
 * place_label, English) within 1.5 km, else 3 km, not already used in the city, a short one (≤ 20) first; else
 * reverse geocoding's neighbourhood or locality. */
async function hoodOf(p: { lat: number; lng: number }, used: Set<string>): Promise<string> {
  for (const radius of [1500, 3000]) {
    const url = `https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/${p.lng},${p.lat}.json?radius=${radius}&limit=50&layers=place_label&access_token=${token()}`;
    const labels = (JSON.parse((await curl(url)).toString()) as { features?: { properties: Record<string, unknown> & { tilequery: { distance: number } } }[] }).features ?? [];
    const names = labels.filter(f => ['suburb', 'quarter', 'neighbourhood'].includes(String(f.properties.type)))
      .sort((a, b) => a.properties.tilequery.distance - b.properties.tilequery.distance)
      .map(f => clean(String(f.properties.name_en ?? f.properties.name ?? ''))).filter(n => n && LATIN.test(n) && !used.has(n));
    const near = names.find(n => n.length <= HOOD_MAX) ?? names[0];
    if (near) return near;
  }
  for (const type of ['neighborhood', 'locality']) {
    const url = `https://api.mapbox.com/search/geocode/v6/reverse?longitude=${p.lng}&latitude=${p.lat}&types=${type}&language=en&limit=1&access_token=${token()}`;
    const body = JSON.parse((await curl(url)).toString()) as { features?: { properties?: { name?: string } }[] };
    const name = clean(body.features?.[0]?.properties?.name ?? '');
    if (name && LATIN.test(name) && !used.has(name)) return name;
  }
  return '';
}

/** App text is English (the user, 2026-09-04): a district name in another script is passed over. */
const LATIN = /^[\p{Script=Latin}\p{N}\s'’.&()-]+$/u;

/** No water pixel at all (a fountain included) and no islet within `rKm` of a point, on a 10 m grid: every spot a
 * player's scatter can give stands on dry land. */
function discDry(map: Awaited<ReturnType<typeof waterMap>>, at: { lat: number; lng: number }, rKm: number): boolean {
  const steps = Math.ceil((rKm * 1000) / 10);
  for (let i = -steps; i <= steps; i++) {
    for (let j = -steps; j <= steps; j++) {
      if (i * i + j * j > steps * steps) continue;
      const p = { lat: at.lat + (i * 0.01) / 111.32, lng: at.lng + (j * 0.01) / (111.32 * Math.cos((at.lat * Math.PI) / 180)) };
      if (dryM(map, p) <= 0) return false;
    }
  }
  return true;
}

/** The water map round a city's home: the beginner pond's 3 km and every home outpost and spot, with a margin. */
function homeBox(points: { lat: number; lng: number }[], marginKm: number) {
  const lat = points.map(p => p.lat), lng = points.map(p => p.lng), mid = (Math.min(...lat) + Math.max(...lat)) / 2;
  const dLat = marginKm / 111.32, dLng = marginKm / (111.32 * Math.cos((mid * Math.PI) / 180));
  return waterMap(Math.min(...lat) - dLat, Math.min(...lng) - dLng, Math.max(...lat) + dLat, Math.max(...lng) + dLng);
}

const turnGap = (a: number, b: number) => { const d = Math.abs(((a - b) % 360 + 360) % 360); return Math.min(d, 360 - d); };

async function pick(cluster: string): Promise<{ lat: number; lng: number; hood: string; deg: number; d: number; dry: number }[] | string> {
  const set = citySet(c, cluster);
  if (!set) return 'no home set';
  const pond = cityPonds(c, cluster).find(p => p.id === set.pond)?.at;
  if (!pond) return 'no beginner pond point';
  const blocks = [...cityOutposts(c, cluster), ...cityPonds(c, cluster)].flatMap(p => (p.at ? [p.at] : []));
  const map = await homeBox([pond], rules.spot.pond_km[1] + 0.5);
  const found: { at: { lat: number; lng: number }; deg: number; d: number; dry: number }[] = [];
  for (let deg = 0; deg < 360; deg += 5) {
    for (let d = rules.spot.pond_km[0] + scKm; d <= rules.spot.pond_km[1] - scKm + 1e-9; d += 0.1) {
      const at = offset(pond.lat, pond.lng, d, deg), dry = dryM(map, at);
      if (dry >= DRY_M && classAt(map, at) === BUILT_UP && blocks.every(b => km(at, b) >= exKm + scKm) && discDry(map, at, scKm)) found.push({ at, deg, d, dry });
    }
  }
  // Toward 3 directions 120° apart from the city's own bearing; the best-scoring fit that has a district name of its own.
  const base = hash32(w.seed, cluster, 'home:spots') % 360, rows: { lat: number; lng: number; hood: string; deg: number; d: number; dry: number }[] = [];
  const used = new Set<string>([nameOf(cluster)]);
  for (let k = 0; k < 3; k++) {
    const want = base + 120 * k;
    const fits = found.filter(f => rows.every(o => km(f.at, o) >= rules.spot.apart_km + 2 * scKm && turnGap(f.deg, o.deg) >= MIN_TURN));
    if (!fits.length) return `no room for spot ${k + 1} (${found.length} dry built-up candidates)`;
    const score = (f: typeof found[number]) => turnGap(f.deg, want) / 20 + Math.abs(f.d - 1.4) / 0.4 - Math.min(f.dry, 600) / 1000;
    let row: typeof rows[number] | null = null;
    for (const f of fits.sort((a, b) => score(a) - score(b)).slice(0, 12)) {
      const hood = await hoodOf(f.at, used);
      if (hood) { row = { lat: f.at.lat, lng: f.at.lng, hood, deg: f.deg, d: Math.round(f.d * 100) / 100, dry: Math.round(f.dry) }; break; }
    }
    if (!row) return `no named district for spot ${k + 1}`;
    used.add(row.hood);
    rows.push(row);
  }
  return rows;
}

async function main() {
  if (cmd === 'run') {
    const table: SpotTable = existsSync(TABLE) ? JSON.parse(readFileSync(TABLE, 'utf8')) : { seed: w.seed, revision: w.revision, cities: {} };
    // Another world's spots, or a full run (no --cities): start again, so the table holds the open list and nothing else.
    if (table.seed !== w.seed || table.revision !== w.revision || !opt('cities')) table.cities = {};
    table.seed = w.seed; table.revision = w.revision;
    const tsv = ['cluster\tcity\tspot\tlat\tlng\thood\tdeg\tkm_to_pond\twater_m\tnote'];
    for (const id of cities) {
      const got = await pick(id);
      if (typeof got === 'string') { tsv.push(`${id}\t${nameOf(id)}\t\t\t\t\t\t\t\t${got}`); console.log(nameOf(id), '—', got); continue; }
      table.cities[id] = got.map(({ lat, lng, hood }) => ({ lat, lng, hood }));
      got.forEach((g, k) => tsv.push(`${id}\t${nameOf(id)}\t${k + 1}\t${g.lat}\t${g.lng}\t${g.hood}\t${g.deg}\t${g.d}\t${g.dry}\t`));
      console.log(nameOf(id), '·', got.map(g => `${g.hood || '?'} (${g.d} km, ${g.dry} m dry)`).join(' · '));
    }
    const sorted = Object.fromEntries(Object.entries(table.cities).sort(([a], [b]) => a.localeCompare(b)));
    writeFileSync(TABLE, JSON.stringify({ _note: 'Farm spots for the home pick (SGODOT-303, q(160) ②): per open city, 3 base spots on built-up land ≥ 250 m from water, with district names (Mapbox). Made by server/tools/home_spots.ts run; read by server/src/p0/home_city.ts.',
      seed: table.seed, revision: table.revision, cities: sorted }, null, 1) + '\n');
    writeFileSync(path.join(out, 'review.tsv'), tsv.join('\n') + '\n');
    return;
  }
  if (cmd === 'check') {
    const tsv = ['cluster\tcity\tcheck\tok\tdetail'];
    let bad = 0;
    const note = (id: string, check: string, ok: boolean, detail = '') => { tsv.push(`${id}\t${nameOf(id)}\t${check}\t${ok ? 'ok' : 'FAIL'}\t${detail}`); if (!ok) bad++; };
    for (const id of cities) {
      const set = citySet(c, id);
      note(id, 'home set', !!set, set ? Object.values(set).join(' ') : 'a role or the beginner pond is missing');
      if (!set) continue;
      const pond = cityPonds(c, id).find(p => p.id === set.pond)!, outposts = cityOutposts(c, id);
      const tackle = outposts.find(o => o.id === set.tackle);
      note(id, 'tackle by the beginner pond', !!(tackle?.at && pond.at && km(tackle.at, pond.at) <= 0.3), tackle?.at && pond.at ? `${Math.round(km(tackle.at, pond.at) * 1000)} m` : '');
      note(id, 'Pond Catch fish', pondFishIds(c, set.pond).has('fish_crucian'), pond.name);
      const rows = citySpots(c, id);
      note(id, 'spots in the table', !!rows && rows.every(r => r.hood), rows?.map(r => r.hood ?? '?').join(' · ') ?? 'none');
      if (!pond.at) continue;
      const home = [set.market, set.tea, set.tackle, set.post].flatMap(oid => outposts.find(o => o.id === oid)?.at ?? []);
      const map = await homeBox([pond.at, ...home, ...(rows ?? []).map(r => r.at)], rules.spot.pond_km[1] + 0.5);
      const wet = [set.market, set.tea, set.tackle, set.post].map(oid => outposts.find(o => o.id === oid)!).filter(o => o.at && dryM(map, o.at) < 50);
      note(id, 'home outposts off the water', wet.length === 0, wet.map(o => `${o.id} ${Math.round(dryM(map, o.at!))} m`).join(' '));
      const blocks = [...outposts, ...cityPonds(c, id)].flatMap(p => (p.at ? [p.at] : []));
      let worst = Infinity, broke = '';
      for (let i = 0; i < SAMPLE_PLAYERS; i++) {
        const spots = homeSpots(c, id, `player-check-${String(i).padStart(4, '0')}`) ?? [];
        if (spots.length !== 3) { broke = 'not 3 spots'; break; }
        for (const s of spots) {
          worst = Math.min(worst, dryM(map, s));
          if (s.km < rules.spot.pond_km[0] || s.km > rules.spot.pond_km[1]) broke = `#${s.spot} ${s.km} km from the pond`;
          if (blocks.some(b => km(s, b) < exKm)) broke = `#${s.spot} within ${exKm * 1000} m of a place`;
        }
        if (km(spots[0], spots[1]) < 1 || km(spots[1], spots[2]) < 1 || km(spots[0], spots[2]) < 1) broke = 'spots under 1 km apart';
        if (new Set(spots.map(s => s.toward)).size < 3) broke = 'two spots in one direction';
      }
      note(id, `${SAMPLE_PLAYERS} players' spots`, !broke && worst >= SPOT_DRY_M, broke || `nearest water ${Math.round(worst)} m`);
    }
    writeFileSync(path.join(out, 'check.tsv'), tsv.join('\n') + '\n');
    console.log(`${cities.length} cities, ${bad} failures → ${path.relative(ROOT, path.join(out, 'check.tsv'))}`);
    if (bad) process.exit(1);
    return;
  }
  if (cmd === 'maps') {
    for (const id of cities) {
      const set = citySet(c, id), rows = citySpots(c, id);
      if (!set || !rows) { console.log(nameOf(id), '— nothing to draw'); continue; }
      const outposts = cityOutposts(c, id), pond = cityPonds(c, id).find(p => p.id === set.pond)!;
      const pin = (label: string, colour: string, p: { lat: number; lng: number }) => `pin-s-${label}+${colour}(${p.lng.toFixed(6)},${p.lat.toFixed(6)})`;
      const pins = [pond.at && pin('p', '1e88e5', pond.at),
        ...(['market', 'tea', 'tackle', 'post'] as const).map((role, i) => { const o = outposts.find(x => x.id === set[role]); return o?.at && pin('mtks'[i], 'f9a825', o.at); }),
        ...rows.map((r, k) => pin(String(k + 1), '2e7d32', r.at))].filter(Boolean);
      const file = path.join(out, `SGODOT-303-spots-${nameOf(id).replace(/[^A-Za-z0-9]/g, '')}.png`);
      await curl(`https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/${pins.join(',')}/auto/800x800@2x?padding=90&access_token=${token()}`, file);
      console.log(nameOf(id), '→', path.relative(ROOT, file));
    }
    return;
  }
  console.log('usage: npx tsx tools/home_spots.ts run|check|maps [--cities gn-1,gn-2] [--out output/home-spots]');
  process.exit(2);
}
main().catch(e => { console.error(String(e)); process.exit(1); });
