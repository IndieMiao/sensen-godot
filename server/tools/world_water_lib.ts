/**
 * Water under generated places (SGODOT-280, q(126)), offline only: ESA WorldCover 2021 v200 (10 m, CC BY 4.0) read
 * around a city, the places on water or too near it found, and each moved to the nearest land that keeps the §9.3.2 /
 * §6.3.3 placement rules. Used by tools/world_water_check.ts (a few cities, JSON) and tools/world_water_batch.ts (every
 * cluster, into server/data/world_water.json). The server never reads WorldCover: it only loads that table.
 *
 * q(126) ③ thresholds: an outpost ≥ 50 m from water (judged at MIN_DRY_M, a pixel of margin); a pond's pin off the
 * water (MIN_POND_M, by the shore is fine); never onto an islet under MIN_LAND_KM2; a pool under SMALL_WATER_KM2 (a
 * fountain between towers) is not water for the distance, but no place may stand on it.
 *
 * Reads go through curl: Node's own HTTPS to this bucket crawls here (1 MB in 90 s, resets) where curl takes 2 s.
 */
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { GeoTIFF, type GeoTIFFImage } from 'geotiff';
import type { CityCluster } from '../src/p0/clusters.js';
import { km, offset, type GenOutpost, type GenPond } from '../src/p0/world.js';

const run = promisify(execFile);
const BASE = 'https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/';
const DEG = 1 / 12000;                 // WorldCover pixel, degrees
export const MIN_DRY_M = 60;
export const MIN_POND_M = 20;
export const MIN_LAND_KM2 = 0.5;
export const SMALL_WATER_KM2 = 0.01;
const WATER = new Uint8Array(256);
for (const v of [0, 80, 90, 95]) WATER[v] = 1;   // no data (open sea), permanent water, wetland, mangrove

export const stats = { requests: 0, bytes: 0 };

async function curl(args: string[]): Promise<Buffer> {
  for (let attempt = 0; ; attempt++) {
    try {
      const { stdout } = await run('curl', ['-sS', '-f', '--retry', '3', '--retry-all-errors', '-m', '120', ...args],
        { encoding: 'buffer', maxBuffer: 256 * 1024 * 1024 });
      return stdout as Buffer;
    } catch (e) {
      const code = (e as { code?: number }).code;
      if (code === 22 || attempt >= 2) throw e;   // 22: HTTP error (no such tile); else a network blip, retry
    }
  }
}

/** A WorldCover tile as a geotiff image, or null where there is no tile (open sea). Cached per process. */
const tiles = new Map<string, Promise<GeoTIFFImage | null>>();
function tile(name: string) {
  let hit = tiles.get(name);
  if (!hit) {
    hit = (async () => {
      const url = `${BASE}ESA_WorldCover_10m_2021_v200_${name}_Map.tif`;
      let size: number;
      try {
        const head = (await curl(['-I', url])).toString();
        size = Number(/content-length:\s*(\d+)/i.exec(head)?.[1] ?? NaN);
      } catch (e) {
        if ((e as { code?: number }).code === 22) return null;   // no such tile: open sea
        throw e;   // never read a network failure as sea
      }
      if (!Number.isFinite(size)) throw new Error(`no size for ${name}`);
      const source = {
        fileSize: size,
        fetch: async (slices: { offset: number; length: number }[]) => Promise.all(slices.map(async ({ offset: at, length }) => {
          const end = Math.min(at + length, size) - 1;
          const buf = await curl(['-r', `${at}-${end}`, url]);
          stats.requests++; stats.bytes += buf.byteLength;
          return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer;
        })),
      };
      const tiff = await GeoTIFF.fromSource(source as never, { cache: true } as never);
      return tiff.getImage();
    })();
    hit.catch(() => tiles.delete(name));   // a failed read is tried again next time
    tiles.set(name, hit);
    if (tiles.size > 6) tiles.delete(tiles.keys().next().value!);
  }
  return hit;
}
const tileName = (s: number, w: number) => `${s < 0 ? 'S' : 'N'}${String(Math.abs(s)).padStart(2, '0')}${w < 0 ? 'W' : 'E'}${String(Math.abs(w)).padStart(3, '0')}`;

/** The WorldCover class at a point (10 tree … 50 built-up, 60 bare, 80 water …), 0 where there is no tile. */
export async function landClass(lat: number, lng: number): Promise<number> {
  const image = await tile(tileName(Math.floor(lat / 3) * 3, Math.floor(lng / 3) * 3));
  if (!image) return 0;
  const [ox, oy] = image.getOrigin();
  const x = Math.floor((lng - ox) / DEG), y = Math.floor((oy - lat) / DEG);
  const v = await image.readRasters({ window: [x, y, x + 1, y + 1], samples: [0], interleave: true }) as Uint8Array;
  return v[0];
}

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

/** 4-connected pieces of `want` pixels: per pixel, whether its piece is at least `minPx` or runs out of the box. */
function bigPieces(cls: Uint8Array, w: number, h: number, want: 0 | 1, minPx: number): Uint8Array {
  const label = new Int32Array(w * h).fill(-1), stack = new Int32Array(w * h), big: boolean[] = [];
  let n = 0;
  for (let i = 0; i < w * h; i++) {
    if (label[i] >= 0 || WATER[cls[i]] !== want) continue;
    let top = 0, count = 0, edge = false;
    stack[top++] = i; label[i] = n;
    while (top) {
      const j = stack[--top], x = j % w, y = (j - x) / w; count++;
      if (x === 0 || y === 0 || x === w - 1 || y === h - 1) edge = true;
      if (x > 0 && label[j - 1] < 0 && WATER[cls[j - 1]] === want) { label[j - 1] = n; stack[top++] = j - 1; }
      if (x < w - 1 && label[j + 1] < 0 && WATER[cls[j + 1]] === want) { label[j + 1] = n; stack[top++] = j + 1; }
      if (y > 0 && label[j - w] < 0 && WATER[cls[j - w]] === want) { label[j - w] = n; stack[top++] = j - w; }
      if (y < h - 1 && label[j + w] < 0 && WATER[cls[j + w]] === want) { label[j + w] = n; stack[top++] = j + w; }
    }
    big.push(edge || count >= minPx); n++;
  }
  const out = new Uint8Array(w * h);
  for (let i = 0; i < w * h; i++) if (label[i] >= 0 && big[label[i]]) out[i] = 1;
  return out;
}

export interface WaterMap { north: number; west: number; w: number; h: number; dist: Float32Array }
/**
 * Metres to the nearest water for each pixel of the box (south, west, north, east): 0 on any water (a small pool
 * included) and on an islet; WorldCover tiles are 3° and a box may straddle up to four; a missing tile is open sea.
 */
export async function waterMap(south: number, west: number, north: number, east: number): Promise<WaterMap> {
  const x0 = Math.floor(west / DEG), x1 = Math.ceil(east / DEG), y0 = Math.floor(-north / DEG), y1 = Math.ceil(-south / DEG);
  const w = x1 - x0, h = y1 - y0, cls = new Uint8Array(w * h);   // 0 (no data) until read
  for (let ts = Math.floor(south / 3) * 3; ts <= Math.floor(north / 3) * 3; ts += 3) {
    for (let tw = Math.floor(west / 3) * 3; tw <= Math.floor(east / 3) * 3; tw += 3) {
      const image = await tile(tileName(ts, tw));
      if (!image) continue;
      const [ox, oy] = image.getOrigin();   // the tile's north-west corner
      const tx0 = Math.round(ox / DEG), ty0 = Math.round(-oy / DEG);
      const ax = Math.max(x0, tx0), bx = Math.min(x1, tx0 + image.getWidth());
      const ay = Math.max(y0, ty0), by = Math.min(y1, ty0 + image.getHeight());
      if (ax >= bx || ay >= by) continue;
      const part = await image.readRasters({ window: [ax - tx0, ay - ty0, bx - tx0, by - ty0], samples: [0], interleave: true }) as Uint8Array;
      const pw = bx - ax;
      for (let y = ay; y < by; y++) cls.set(part.subarray((y - ay) * pw, (y - ay + 1) * pw), (y - y0) * w + (ax - x0));
    }
  }
  const lat = (south + north) / 2, dy = DEG * 111_320, dx = DEG * 111_320 * Math.cos((lat * Math.PI) / 180), pxKm2 = (dx * dy) / 1e6;
  const bigWater = bigPieces(cls, w, h, 1, SMALL_WATER_KM2 / pxKm2);
  const bigLand = bigPieces(cls, w, h, 0, MIN_LAND_KM2 / pxKm2);
  const g = new Float64Array(w * h);
  for (let i = 0; i < w * h; i++) g[i] = bigWater[i] ? 0 : Infinity;
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
    for (let x = 0; x < w; x++) { const i = y * w + x; dist[i] = WATER[cls[i]] || !bigLand[i] ? 0 : Math.sqrt(d[x]); }
  }
  return { north: -y0 * DEG, west: x0 * DEG, w, h, dist };
}

/** Metres from water at a point (0 on water or an islet), -1 outside the box. */
export const dryM = (m: WaterMap, p: { lat: number; lng: number }) => {
  const x = Math.floor((p.lng - m.west) / DEG), y = Math.floor((m.north - p.lat) / DEG);
  return x < 0 || y < 0 || x >= m.w || y >= m.h ? -1 : m.dist[y * m.w + x];
};

export type Place = (GenPond & { kind: 'pond'; fixed?: boolean }) | (GenOutpost & { kind: 'outpost'; fixed?: boolean });
export const need = (p: Place) => (p.kind === 'pond' ? MIN_POND_M : MIN_DRY_M);

/** The §9.3.2 / §6.3.3 rules (as p1_world_gen.test.ts checks them) for one place at `at`, against the others now. */
export function ruleOk(cl: CityCluster, places: Place[], me: Place, at: { lat: number; lng: number }): boolean {
  const ponds = places.filter(p => p.kind === 'pond') as (GenPond & { kind: 'pond' })[];
  const outs = places.filter(p => p.kind === 'outpost') as (GenOutpost & { kind: 'outpost' })[];
  const beginner = ponds.find(p => p.beginner)!;
  if (me.kind === 'pond') {
    const d = km(cl, at);
    if (me.beginner) return ponds.every(p => p === me || km(cl, p) >= d - 0.01);
    return d >= km(cl, beginner) - 0.01;
  }
  const o = me;
  for (const x of outs) if (x !== o && km(x, at) < (x.role === o.role ? 3 : 0.3) + 1e-6) return false;
  if (o.cabin) return true;
  if (o.role === 'tackle') {
    const pond = ponds.find(p => p.name === o.nearest?.name);
    if (!pond || km(pond, at) > 0.3) return false;
  }
  if (o.id.endsWith('~market0')) { const d = km(cl, at); if (d < 1 || d > 2 || km(beginner, at) > 0.8) return false; }
  if (o.id.endsWith('~post0') && km(cl, at) > 1) return false;
  return true;
}

/** Points by distance from `from`: rings every 25 m out to `maxM`, every 5°. */
export function* around(from: { lat: number; lng: number }, maxM: number) {
  yield { lat: from.lat, lng: from.lng, m: 0 };
  for (let r = 25; r <= maxM; r += 25) for (let a = 0; a < 360; a += 5) yield { ...offset(from.lat, from.lng, r / 1000, a), m: r };
}

export interface Move { id: string; name: string; from: [number, number]; to: [number, number]; moved_m: number; water_m: number; why: string }
export interface CityResult { cluster: string; places: number; wet: { id: string; water_m: number }[]; moved: Move[]; failed: string[]; still_bad: string[];
  no_data?: true }

/** The box around a city's places, `padKm` wider on each side. */
function boxOf(places: Place[], padKm: number, lat: number) {
  const pLat = padKm / 111.32, pLng = padKm / (111.32 * Math.max(0.05, Math.cos((lat * Math.PI) / 180)));
  const lats = places.map(p => p.lat), lngs = places.map(p => p.lng);
  return [Math.min(...lats) - pLat, Math.min(...lngs) - pLng, Math.max(...lats) + pLat, Math.max(...lngs) + pLng] as const;
}

/**
 * Check one city and move what stands on water. Places marked `fixed` (a hand fix in world.overrides) are never moved
 * but count for the rules. A first look reads a tight box; only a city with a wet place reads the wide one to search.
 */
export async function fixCity(cl: CityCluster, input: Place[], searchM = 3000): Promise<CityResult> {
  const places = input.map(p => ({ ...p }));
  // WorldCover has no tile for a few remote islands (Norfolk, Cocos): a missing tile round a city is no data, not sea —
  // such a city is left as generated. (Away from the city's own tile a missing tile is open sea.)
  if (!(await tile(tileName(Math.floor(cl.lat / 3) * 3, Math.floor(cl.lng / 3) * 3)))) {
    return { cluster: cl.id, places: places.length, wet: [], moved: [], failed: [], still_bad: [], no_data: true };
  }
  const tight = await waterMap(...boxOf(places, 1.2, cl.lat));
  const wetAt = (m: WaterMap, p: Place) => dryM(m, p) < need(p);
  const wet = places.filter(p => !p.fixed && wetAt(tight, p));
  const result: CityResult = { cluster: cl.id, places: places.length, wet: wet.map(p => ({ id: p.id, water_m: Math.round(Math.max(0, dryM(tight, p))) })),
    moved: [], failed: [], still_bad: [] };
  if (!wet.length) return result;
  const map = await waterMap(...boxOf(places, searchM / 1000 + 1.2, cl.lat));
  // Ponds first (beginner first), then tackle shops (≤ 300 m from their ponds), Market Square 1 (≤ 800 m from the
  // beginner pond and ≥ 300 m from its shop), Travel Post 1, then the rest.
  const rank = (p: Place) => p.kind === 'pond' ? 0 : p.role === 'tackle' ? 1 : p.id.endsWith('~market0') ? 2 : p.id.endsWith('~post0') ? 3 : 4;
  for (const p of [...places].sort((a, b) => rank(a) - rank(b))) {
    if (p.fixed) continue;
    const isWet = wetAt(map, p);
    if (!isWet && ruleOk(cl, places, p, p)) continue;
    let found: { lat: number; lng: number; m: number } | null = null;
    // A pond takes a spot that leaves room for what hangs on it: its tackle shop (≤ 300 m, off the water, spaced from the
    // rest) and, for the beginner pond, Market Square 1 — tried with the pond standing there, so the rules decide.
    const shop = p.kind === 'pond' ? places.find(o => o.kind === 'outpost' && o.role === 'tackle' && o.nearest?.name === p.name && !o.fixed) : undefined;
    const square = p.kind === 'pond' && p.beginner ? places.find(o => o.id === `${cl.id}~market0` && !o.fixed) : undefined;
    const roomFor = (o: Place | undefined, reach: number) => !o || (!wetAt(map, o) && ruleOk(cl, places, o, o))
      || [...around(p, reach)].some(s => dryM(map, s) >= need(o) && ruleOk(cl, places, o, s));
    for (const q of around(p, searchM)) {
      if (dryM(map, q) < need(p) || !ruleOk(cl, places, p, q)) continue;
      if (shop || square) {
        const [lat, lng] = [p.lat, p.lng];
        p.lat = q.lat; p.lng = q.lng;
        const fits = roomFor(shop, 300) && roomFor(square, 800);
        p.lat = lat; p.lng = lng;
        if (!fits) continue;
      }
      found = q; break;
    }
    if (!found) { result.failed.push(p.id); continue; }
    result.moved.push({ id: p.id, name: p.name, from: [p.lat, p.lng], to: [found.lat, found.lng], moved_m: found.m,
      water_m: Math.round(dryM(map, found)), why: isWet ? `${Math.round(Math.max(0, dryM(map, p)))} m from water` : 'a rule broke after a pond moved' });
    p.lat = found.lat; p.lng = found.lng;
  }
  result.still_bad = places.filter(p => wetAt(map, p) || !ruleOk(cl, places, p, p)).map(p => p.id);
  return result;
}
