/**
 * Water check for generated cities (SGODOT-280, q(114) ⑤), offline: reads ESA WorldCover 2021 v200 (10 m, CC BY 4.0)
 * around a city's generated places (world.overrides already applied), reports the ones on water or too near it (an
 * outpost under MIN_DRY_M, a pond's pin under MIN_POND_M), and proposes the nearest point on land that keeps the
 * §9.3.2 / §6.3.3 placement rules, never on an islet. The proposals go into world.overrides by hand, map checked.
 *   npx tsx tools/world_water_check.ts gn-5128581 [gn-…]   → JSON on stdout (wet, moved, failed, still_bad)
 */
import { fromUrl } from 'geotiff';
import type { CityCluster } from '../src/p0/clusters.js';
import { loadP0Content, type P0Content } from '../src/p0/content.js';
import { generateCity, km, offset, type GenOutpost, type GenPond } from '../src/p0/world.js';

const BASE = 'https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/';
const DEG = 1 / 12000;               // WorldCover pixel, degrees
const MIN_DRY_M = 60;                 // an outpost (q(114)): ≥ 50 m from water, plus a pixel of margin
const MIN_POND_M = 20;                // a pond's pin: on land, by the water is fine (a fishing spot)
const MIN_LAND_KM2 = 0.5;             // never onto an islet (Liberty Island 0.06 km²); land running out of the box counts as big
const WATER = new Set([0, 80, 90, 95]);   // no data, permanent water, wetland, mangrove

const tileOf = (lat: number, lng: number) => {
  const s = Math.floor(lat / 3) * 3, w = Math.floor(lng / 3) * 3;
  return { name: `${s < 0 ? 'S' : 'N'}${String(Math.abs(s)).padStart(2, '0')}${w < 0 ? 'W' : 'E'}${String(Math.abs(w)).padStart(3, '0')}`, s, w };
};

/** 1-D squared distance transform (Felzenszwalb–Huttenlocher) with sample spacing `h`. */
function edt1(f: Float64Array, n: number, h: number, d: Float64Array, v: Int32Array, z: Float64Array) {
  let k = 0; v[0] = 0; z[0] = -Infinity; z[1] = Infinity;
  for (let q = 1; q < n; q++) {
    if (f[q] === Infinity) continue;
    if (f[v[0]] === Infinity) { v[0] = q; continue; }
    let s: number;
    for (;;) {
      const p = v[k];
      s = ((f[q] + (q * h) ** 2) - (f[p] + (p * h) ** 2)) / (2 * h * (q - p));
      if (s <= z[k] && k > 0) k--; else break;
    }
    if (s <= z[k]) { v[k] = q; z[k + 1] = Infinity; continue; }
    k++; v[k] = q; z[k] = s; z[k + 1] = Infinity;
  }
  if (f[v[0]] === Infinity) { d.fill(Infinity, 0, n); return; }
  k = 0;
  for (let q = 0; q < n; q++) {
    while (z[k + 1] < q * h) k++;
    d[q] = (q - v[k]) ** 2 * h * h + f[v[k]];
  }
}

interface WaterMap { north: number; west: number; w: number; h: number; dist: Float32Array; bigLand: Uint8Array }
/** Metres from each pixel of the box to the nearest water pixel (0 on water). */
async function waterMap(south: number, west: number, north: number, east: number): Promise<WaterMap> {
  const t = tileOf((south + north) / 2, (west + east) / 2);
  if (tileOf(south, west).name !== t.name || tileOf(north, east).name !== t.name) throw new Error(`box spans tiles near ${t.name}`);
  const tiff = await fromUrl(`${BASE}ESA_WorldCover_10m_2021_v200_${t.name}_Map.tif`);
  const image = await tiff.getImage();
  const [ox, oy] = image.getOrigin();
  const x0 = Math.max(0, Math.floor((west - ox) / DEG)), x1 = Math.min(image.getWidth(), Math.ceil((east - ox) / DEG));
  const y0 = Math.max(0, Math.floor((oy - north) / DEG)), y1 = Math.min(image.getHeight(), Math.ceil((oy - south) / DEG));
  const values = await image.readRasters({ window: [x0, y0, x1, y1], samples: [0], interleave: true }) as Uint8Array;
  const w = x1 - x0, h = y1 - y0, lat = (south + north) / 2;
  const dy = DEG * 111_320, dx = DEG * 111_320 * Math.cos((lat * Math.PI) / 180);
  const g = new Float64Array(w * h);
  for (let i = 0; i < w * h; i++) g[i] = WATER.has(values[i]) ? 0 : Infinity;
  const n = Math.max(w, h), f = new Float64Array(n), d = new Float64Array(n), v = new Int32Array(n), z = new Float64Array(n + 1);
  for (let x = 0; x < w; x++) {
    for (let y = 0; y < h; y++) f[y] = g[y * w + x];
    edt1(f, h, dy, d, v, z);
    for (let y = 0; y < h; y++) g[y * w + x] = d[y];
  }
  const dist = new Float32Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) f[x] = g[y * w + x];
    edt1(f, w, dx, d, v, z);
    for (let x = 0; x < w; x++) dist[y * w + x] = Math.sqrt(d[x]);
  }
  // Land pieces (4-connected): 1 where the piece is at least MIN_LAND_KM2 or runs out of the box.
  const bigLand = new Uint8Array(w * h), seen = new Uint8Array(w * h), stack = new Int32Array(w * h), pxKm2 = (dx * dy) / 1e6;
  for (let i = 0; i < w * h; i++) {
    if (seen[i] || WATER.has(values[i])) continue;
    let top = 0, n = 0, edge = false; const members: number[] = [];
    stack[top++] = i; seen[i] = 1;
    while (top) {
      const j = stack[--top], x = j % w, y = (j - x) / w; members.push(j); n++;
      if (x === 0 || y === 0 || x === w - 1 || y === h - 1) edge = true;
      for (const k of [x > 0 ? j - 1 : -1, x < w - 1 ? j + 1 : -1, y > 0 ? j - w : -1, y < h - 1 ? j + w : -1]) {
        if (k >= 0 && !seen[k] && !WATER.has(values[k])) { seen[k] = 1; stack[top++] = k; }
      }
    }
    if (edge || n * pxKm2 >= MIN_LAND_KM2) for (const j of members) bigLand[j] = 1;
  }
  return { north: oy - y0 * DEG, west: ox + x0 * DEG, w, h, dist, bigLand };
}
/** Metres from water at a point; 0 on an islet (as if it were water), -1 outside the box. */
const dryM = (m: WaterMap, p: { lat: number; lng: number }) => {
  const x = Math.floor((p.lng - m.west) / DEG), y = Math.floor((m.north - p.lat) / DEG);
  if (x < 0 || y < 0 || x >= m.w || y >= m.h) return -1;
  return m.bigLand[y * m.w + x] ? m.dist[y * m.w + x] : 0;
};

type Place = (GenPond & { kind: 'pond' }) | (GenOutpost & { kind: 'outpost' });

/** The rules the generator promises (and p1_world_gen.test.ts checks) for one place at `at`, against the others now. */
function ruleOk(cl: CityCluster, places: Place[], me: Place, at: { lat: number; lng: number }): boolean {
  const ponds = places.filter(p => p.kind === 'pond') as (GenPond & { kind: 'pond' })[];
  const outs = places.filter(p => p.kind === 'outpost') as (GenOutpost & { kind: 'outpost' })[];
  const beginner = ponds.find(p => p.beginner)!;
  if (me.kind === 'pond') {
    const d = km(cl, at);
    if (me.beginner) return ponds.every(p => p === me || km(cl, p) >= d - 0.01);
    return d >= km(cl, beginner) - 0.01;
  }
  const o = me;
  for (const x of outs) {
    if (x === o) continue;
    if (km(x, at) < (x.role === o.role ? 3 : 0.3) + 1e-6) return false;
  }
  if (o.cabin) return true;
  if (o.role === 'tackle') {
    const pond = ponds.find(p => p.name === o.nearest?.name);
    if (!pond || km(pond, at) > 0.3) return false;
  }
  if (o.id.endsWith('~market0')) {
    const d = km(cl, at);
    if (d < 1 || d > 2 || km(beginner, at) > 0.8) return false;
  }
  if (o.id.endsWith('~post0') && km(cl, at) > 1) return false;
  return true;
}

/** Points by distance from `from`: rings every 25 m out to `maxM`, every 5°. */
function* around(from: { lat: number; lng: number }, maxM: number) {
  yield { lat: from.lat, lng: from.lng, m: 0 };
  for (let r = 25; r <= maxM; r += 25) for (let a = 0; a < 360; a += 5) yield { ...offset(from.lat, from.lng, r / 1000, a), m: r };
}

async function checkCity(c: P0Content, cl: CityCluster) {
  const city = generateCity(c, cl);
  const places: Place[] = [...city.detail.ponds.map(p => ({ ...p, kind: 'pond' as const })), ...city.detail.outposts.map(o => ({ ...o, kind: 'outpost' as const }))];
  const lats = places.map(p => p.lat), lngs = places.map(p => p.lng), pad = 0.04;
  const map = await waterMap(Math.min(...lats) - pad, Math.min(...lngs) - pad / Math.cos((cl.lat * Math.PI) / 180),
    Math.max(...lats) + pad, Math.max(...lngs) + pad / Math.cos((cl.lat * Math.PI) / 180));
  const need = (p: Place) => (p.kind === 'pond' ? MIN_POND_M : MIN_DRY_M);
  const before = places.map(p => ({ id: p.id, name: p.name, lat: p.lat, lng: p.lng, water_m: Math.round(dryM(map, p)), need: need(p) }));
  const moved: { id: string; name: string; from: [number, number]; to: [number, number]; moved_m: number; water_m: number; why: string }[] = [];
  const failed: string[] = [];
  // Ponds first (beginner first), then tackle shops (≤ 300 m from their ponds), Market Square 1 (≤ 800 m from the
  // beginner pond and ≥ 300 m from its shop), Travel Post 1, then the rest.
  const rank = (p: Place) => p.kind === 'pond' ? 0 : p.role === 'tackle' ? 1 : p.id.endsWith('~market0') ? 2 : p.id.endsWith('~post0') ? 3 : 4;
  const order = [...places].sort((a, b) => rank(a) - rank(b));
  for (const p of order) {
    const wet = dryM(map, p) < need(p);
    if (!wet && ruleOk(cl, places, p, p)) continue;
    const reason = wet ? `${Math.round(dryM(map, p))} m from water` : 'a rule broke after a pond moved';
    let found: { lat: number; lng: number; m: number } | null = null;
    for (const q of around(p, 3000)) {
      if (dryM(map, q) < need(p) || !ruleOk(cl, places, p, q)) continue;
      // A beginner pond has to leave room for its tackle shop and Market Square 1.
      if (p.kind === 'pond' && p.beginner) {
        const shop = [...around(q, 300)].some(s => dryM(map, s) >= MIN_DRY_M);
        const square = [...around(q, 800)].some(s => { const d = km(cl, s); return d >= 1 && d <= 2 && dryM(map, s) >= MIN_DRY_M; });
        if (!shop || !square) continue;
      }
      found = q; break;
    }
    if (!found) { failed.push(p.id); continue; }
    moved.push({ id: p.id, name: p.name, from: [p.lat, p.lng], to: [found.lat, found.lng], moved_m: found.m,
      water_m: Math.round(dryM(map, found)), why: reason });
    p.lat = found.lat; p.lng = found.lng;
  }
  const after = places.filter(p => dryM(map, p) < need(p) || !ruleOk(cl, places, p, p)).map(p => p.id);
  return { cluster: cl.id, name: cl.name, tier: city.tier, places: before.length,
    wet: before.filter(b => b.water_m < b.need), moved, failed, still_bad: after };
}

const c = loadP0Content();
const clusters = (c as P0Content & { clusters: { get(id: string): CityCluster | undefined } }).clusters;
const out = [];
for (const id of process.argv.slice(2)) {
  const cl = clusters.get(id);
  if (!cl) { out.push({ cluster: id, error: 'no such cluster' }); continue; }
  try { out.push(await checkCity(c, cl)); } catch (e) { out.push({ cluster: id, error: String(e) }); }
}
console.log(JSON.stringify(out, null, 1));
