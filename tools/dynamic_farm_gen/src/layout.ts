/**
 * Turns a core mask into the schema-4 zones: core, a 2-cell walking ring, corridors that join
 * separate buildings, an entry path to the front side, and a noisy grass extension around it.
 * The client checks in modules/dynamic_farm/farm_data.gd are the contract this must satisfy.
 */
import type { GeneratorParams } from './config.js';

export const NONE = 0;
export const CORE = 1;
export const EXTENSION = 2;
export const SURFACE_SOIL = 0;
export const SURFACE_GRASS = 1;
export const SURFACE_PATH = 2;

/** Grid direction toward the street/front; +y is north (world -Z). */
export interface Dir { dx: number; dy: number }
export const DIRS: Record<'south' | 'west' | 'east' | 'north', Dir> = {
  south: { dx: 0, dy: -1 }, west: { dx: -1, dy: 0 }, east: { dx: 1, dy: 0 }, north: { dx: 0, dy: 1 },
};

export interface Layout {
  width: number;
  height: number;
  zone: Uint8Array;
  surface: Uint8Array;
  protect: Uint8Array;
  spawn: [number, number];
  entry: [number, number];
  /** Grid cell (0,0) corresponds to raster cell (offset[0], offset[1]). */
  offset: [number, number];
  counts: { core: number; extension: number; total: number };
  core_components: number;
  connectors: number;
  dropped_core_cells: number;
}

/** Offsets whose rounded-box distance is within 2 cells: the client's corridor rule. */
export const RING_OFFSETS: [number, number][] = [];
for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) {
  const ax = Math.max(Math.abs(dx) - 0.5, 0);
  const ay = Math.max(Math.abs(dy) - 0.5, 0);
  if (ax * ax + ay * ay <= 4) RING_OFFSETS.push([dx, dy]);
}

const N4: [number, number][] = [[1, 0], [-1, 0], [0, 1], [0, -1]];

class Canvas {
  constructor(readonly width: number, readonly height: number) {}
  in(x: number, y: number): boolean { return x >= 0 && y >= 0 && x < this.width && y < this.height; }
  at(x: number, y: number): number { return y * this.width + x; }
}

/** 4-connected components of `mask`; returns labels (0 = none) and sizes indexed by label. */
export function components(mask: Uint8Array, w: number, h: number): { labels: Int32Array; sizes: number[] } {
  const labels = new Int32Array(mask.length);
  const sizes = [0];
  const queue = new Int32Array(mask.length);
  for (let i = 0; i < mask.length; i++) {
    if (!mask[i] || labels[i]) continue;
    const label = sizes.length;
    let head = 0;
    let tail = 0;
    queue[tail++] = i;
    labels[i] = label;
    while (head < tail) {
      const c = queue[head++];
      const x = c % w;
      const y = (c - x) / w;
      for (const [dx, dy] of N4) {
        const nx = x + dx;
        const ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        const n = ny * w + nx;
        if (mask[n] && !labels[n]) { labels[n] = label; queue[tail++] = n; }
      }
    }
    sizes.push(tail);
  }
  return { labels, sizes };
}

/** Deterministic 32-bit integer hash. */
export function hash32(a: number, b: number, c: number): number {
  let h = Math.imul(a ^ 0x9e3779b9, 0x85ebca6b) ^ Math.imul(b ^ 0xc2b2ae35, 0x27d4eb2f) ^ Math.imul(c ^ 0x165667b1, 0x9e3779b1);
  h ^= h >>> 15;
  h = Math.imul(h, 0x2c1b3c6d);
  h ^= h >>> 12;
  h = Math.imul(h, 0x297a2d39);
  h ^= h >>> 15;
  return h >>> 0;
}

/** Smooth value noise in [-1, 1] with lattice spacing `period` cells. */
export function valueNoise(x: number, y: number, period: number, seed: number): number {
  const fx = x / period;
  const fy = y / period;
  const ix = Math.floor(fx);
  const iy = Math.floor(fy);
  const tx = fx - ix;
  const ty = fy - iy;
  const sx = tx * tx * (3 - 2 * tx);
  const sy = ty * ty * (3 - 2 * ty);
  const v = (i: number, j: number) => (hash32(i, j, seed) / 0xffffffff) * 2 - 1;
  const a = v(ix, iy) + (v(ix + 1, iy) - v(ix, iy)) * sx;
  const b = v(ix, iy + 1) + (v(ix + 1, iy + 1) - v(ix, iy + 1)) * sx;
  return a + (b - a) * sy;
}

export class LayoutError extends Error {}

/**
 * `core` is a raster mask (w × h). `front` points from the buildings toward the entry.
 * `seed` drives only the extension outline.
 */
export function buildLayout(core: Uint8Array, w: number, h: number, front: Dir, seed: number, p: GeneratorParams): Layout {
  const rMax = p.extension_cells + p.extension_jitter;
  const margin = rMax + 6;
  const cv = new Canvas(w + 2 * margin, h + 2 * margin);
  const size = cv.width * cv.height;
  const zone = new Uint8Array(size);
  const protect = new Uint8Array(size);
  const surface = new Uint8Array(size).fill(SURFACE_GRASS);

  // Core, minus raster noise islands.
  const raw = new Uint8Array(size);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (core[y * w + x]) raw[cv.at(x + margin, y + margin)] = 1;
  const cc = components(raw, cv.width, cv.height);
  let dropped = 0;
  let coreComponents = 0;
  for (let i = 0; i < size; i++) {
    if (!raw[i]) continue;
    if (cc.sizes[cc.labels[i]] < p.min_component_cells) { dropped++; continue; }
    zone[i] = CORE;
    surface[i] = SURFACE_SOIL;
  }
  let mainLabel = 0;
  for (let l = 1; l < cc.sizes.length; l++) {
    if (cc.sizes[l] < p.min_component_cells) continue;
    coreComponents++;
    if (!mainLabel || cc.sizes[l] > cc.sizes[mainLabel]) mainLabel = l;
  }
  if (coreComponents === 0) throw new LayoutError('no core cells');
  // The entry path and the spawn belong to the largest building, not a garage or shed.
  const inMain = (i: number) => zone[i] === CORE && cc.labels[i] === mainLabel;

  // Walking ring: every cell within the client's rounded 2-cell radius of the core.
  for (let i = 0; i < size; i++) {
    if (zone[i] !== CORE) continue;
    const x = i % cv.width;
    const y = (i - x) / cv.width;
    for (const [dx, dy] of RING_OFFSETS) protect[cv.at(x + dx, y + dy)] = 1;
  }

  // Join separate buildings' rings with 3-wide paths along shortest grid routes.
  let connectors = 0;
  for (;;) {
    const pc = components(protect, cv.width, cv.height);
    if (pc.sizes.length <= 2) break;
    let main = 1;
    for (let l = 2; l < pc.sizes.length; l++) if (pc.sizes[l] > pc.sizes[main]) main = l;
    const prev = new Int32Array(size).fill(-1);
    const queue = new Int32Array(size);
    let head = 0;
    let tail = 0;
    for (let i = 0; i < size; i++) if (pc.labels[i] === main) { queue[tail++] = i; prev[i] = i; }
    let hit = -1;
    while (head < tail && hit < 0) {
      const c = queue[head++];
      const x = c % cv.width;
      const y = (c - x) / cv.width;
      for (const [dx, dy] of N4) {
        const nx = x + dx;
        const ny = y + dy;
        if (!cv.in(nx, ny)) continue;
        const n = cv.at(nx, ny);
        if (prev[n] >= 0) continue;
        prev[n] = c;
        if (pc.labels[n] && pc.labels[n] !== main) { hit = n; break; }
        queue[tail++] = n;
      }
    }
    if (hit < 0) throw new LayoutError('cannot connect walking areas');
    for (let c = prev[hit]; pc.labels[c] !== main; c = prev[c]) {
      const x = c % cv.width;
      const y = (c - x) / cv.width;
      if (zone[c] !== CORE) surface[c] = SURFACE_PATH;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) protect[cv.at(x + dx, y + dy)] = 1;
    }
    connectors++;
  }

  // Grass extension: Euclidean distance to the protected area within a noisy radius.
  const radius = new Float64Array(size);
  for (let y = 0; y < cv.height; y++) for (let x = 0; x < cv.width; x++) {
    radius[cv.at(x, y)] = p.extension_cells + p.extension_jitter * valueNoise(x, y, p.extension_noise_period, seed);
  }
  const ext = new Uint8Array(size);
  for (let i = 0; i < size; i++) {
    if (!protect[i]) continue;
    const x = i % cv.width;
    const y = (i - x) / cv.width;
    for (let dy = -rMax; dy <= rMax; dy++) for (let dx = -rMax; dx <= rMax; dx++) {
      const d2 = dx * dx + dy * dy;
      if (d2 > rMax * rMax) continue;
      const nx = x + dx;
      const ny = y + dy;
      if (!cv.in(nx, ny)) continue;
      const n = cv.at(nx, ny);
      if (!protect[n] && d2 <= radius[n] * radius[n]) ext[n] = 1;
    }
  }

  // Entry lane: the main building's most protruding column toward the front, nearest its centre.
  const perp = { dx: Math.abs(front.dy), dy: Math.abs(front.dx) };
  const lanes = new Map<number, number>();
  for (let i = 0; i < size; i++) {
    if (!inMain(i)) continue;
    const x = i % cv.width;
    const y = (i - x) / cv.width;
    const l = x * perp.dx + y * perp.dy;
    const t = x * front.dx + y * front.dy;
    if (!lanes.has(l) || t > lanes.get(l)!) lanes.set(l, t);
  }
  const tMax = Math.max(...lanes.values());
  const top = [...lanes.entries()].filter(([, t]) => t === tMax).map(([l]) => l).sort((a, b) => a - b);
  const centre = (top[0] + top[top.length - 1]) / 2;
  const lane = top.reduce((best, l) => (Math.abs(l - centre) < Math.abs(best - centre) ? l : best), top[0]);
  const cell = (l: number, t: number) => ({ x: l * perp.dx + t * front.dx, y: l * perp.dy + t * front.dy });
  let tEntry = tMax;
  for (let t = tMax + 1; ; t++) {
    const c = cell(lane, t);
    if (!cv.in(c.x, c.y)) break;
    const i = cv.at(c.x, c.y);
    if (!protect[i] && !ext[i]) break;
    tEntry = t;
  }
  if (tEntry < tMax + 3) throw new LayoutError('entry path too short');
  for (let t = tMax + 1; t <= tEntry + 2; t++) for (let k = -2; k <= 2; k++) {
    const c = cell(lane + k, t);
    const i = cv.at(c.x, c.y);
    if (zone[i] === CORE) continue; // another building in the way stays core (and protected)
    if (t <= tEntry) {
      protect[i] = 1;
      ext[i] = 1;
      if (k === 0) surface[i] = SURFACE_PATH;
    } else if (!protect[i]) {
      ext[i] = 0; // keep the arrival clearance free of unprotected ground
    }
  }
  const entryCell = cell(lane, tEntry);

  for (let i = 0; i < size; i++) if (zone[i] !== CORE && (protect[i] || ext[i])) zone[i] = EXTENSION;
  // Keep only ground reachable from the core.
  const ground = new Uint8Array(size);
  for (let i = 0; i < size; i++) ground[i] = zone[i] ? 1 : 0;
  const gc = components(ground, cv.width, cv.height);
  let coreLabel = 0;
  for (let i = 0; i < size; i++) if (zone[i] === CORE) { coreLabel = gc.labels[i]; break; }
  for (let i = 0; i < size; i++) {
    if (zone[i] && gc.labels[i] !== coreLabel) { zone[i] = NONE; protect[i] = 0; }
    if (!zone[i]) { protect[i] = 0; surface[i] = SURFACE_GRASS; }
  }

  // Spawn: the main building's most interior cell (clearance capped at 3), then nearest the lane.
  const laneStart = cell(lane, tMax);
  let spawn = -1;
  let spawnScore = [-1, Infinity];
  for (let i = 0; i < size; i++) {
    if (!inMain(i)) continue;
    const x = i % cv.width;
    const y = (i - x) / cv.width;
    let clear = 0;
    while (clear < 3) {
      const r = clear + 1;
      let ok = true;
      for (let dy = -r; dy <= r && ok; dy++) for (let dx = -r; dx <= r && ok; dx++) if (zone[cv.at(x + dx, y + dy)] !== CORE) ok = false;
      if (!ok) break;
      clear = r;
    }
    const d2 = (x - laneStart.x) ** 2 + (y - laneStart.y) ** 2;
    if (clear > spawnScore[0] || (clear === spawnScore[0] && d2 < spawnScore[1])) { spawn = i; spawnScore = [clear, d2]; }
  }

  // Crop with a 2-cell empty border.
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (let i = 0; i < size; i++) {
    if (!zone[i]) continue;
    const x = i % cv.width;
    const y = (i - x) / cv.width;
    minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y);
  }
  const ox = minX - 2;
  const oy = minY - 2;
  const width = maxX - minX + 5;
  const height = maxY - minY + 5;
  const out = { zone: new Uint8Array(width * height), surface: new Uint8Array(width * height), protect: new Uint8Array(width * height) };
  const counts = { core: 0, extension: 0, total: 0 };
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const cx = x + ox;
    const cy = y + oy;
    if (!cv.in(cx, cy)) continue;
    const i = cv.at(cx, cy);
    const o = y * width + x;
    out.zone[o] = zone[i];
    out.surface[o] = zone[i] ? surface[i] : 0;
    out.protect[o] = protect[i];
    if (zone[i] === CORE) counts.core++;
    else if (zone[i] === EXTENSION) counts.extension++;
  }
  counts.total = counts.core + counts.extension;
  const sx = spawn % cv.width;
  const sy = (spawn - sx) / cv.width;
  return {
    width, height, ...out,
    spawn: [sx - ox, sy - oy],
    entry: [entryCell.x - ox, entryCell.y - oy],
    offset: [ox - margin, oy - margin],
    counts, core_components: coreComponents, connectors, dropped_core_cells: dropped,
  };
}
