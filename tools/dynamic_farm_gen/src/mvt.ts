/**
 * Parcel vector tiles (Mapbox Vector Tile 2.1) in the r4 map-layer format the client reads:
 * one layer `parcels`, polygons of the real parcel outlines, every index property on each feature
 * (the client promotes `block_id` to the feature id), XYZ tiles z15–18.
 *
 * A small encoder of our own instead of tippecanoe: it needs no native tool on the build machine
 * and, like the rest of the build, uses only IEEE-exact arithmetic plus src/detmath.ts, so the tile
 * bytes are identical on every platform. Geometry is clipped to the tile plus a buffer and
 * quantized to the tile extent; nothing is simplified or dropped on purpose (a parcel can only
 * vanish from a low-zoom tile when it collapses below one tile unit, which the tile check reports).
 */
import { log, sin } from './detmath.js';
import type { Point, Polygon, Ring } from './geo.js';

export const MVT_ENCODER = 'dynamic-farm-gen mvt-encoder-1';

export interface MapLayerParams {
  /** Parcel tile zoom range (r4: 15–18). The client's parcel layer is visible from native_map.minzoom. */
  tile_minzoom: number;
  tile_maxzoom: number;
  /** Tile units per tile edge (MVT default 4096). */
  tile_extent: number;
  /** Clip buffer around each tile, in tile units (r4 tippecanoe --buffer=5 = 80 units). */
  tile_buffer: number;
  /** Building map layer: decimal places kept in lon/lat (6 ≈ 0.1 m). */
  building_decimals: number;
  /** Building map layer: vertices within this distance of the simplified outline are dropped (m). */
  building_simplify_m: number;
}

export const DEFAULT_MAP_PARAMS: MapLayerParams = {
  tile_minzoom: 15,
  tile_maxzoom: 18,
  tile_extent: 4096,
  tile_buffer: 80,
  building_decimals: 6,
  building_simplify_m: 0.1,
};

export function resolveMapParams(overrides: Partial<MapLayerParams> = {}): MapLayerParams {
  const p: MapLayerParams = { ...DEFAULT_MAP_PARAMS };
  for (const [key, value] of Object.entries(overrides)) {
    if (!(key in DEFAULT_MAP_PARAMS)) throw new Error(`unknown map parameter ${key}`);
    if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`map parameter ${key} must be a number`);
    (p as unknown as Record<string, number>)[key] = value;
  }
  const ints: (keyof MapLayerParams)[] = ['tile_minzoom', 'tile_maxzoom', 'tile_extent', 'tile_buffer', 'building_decimals'];
  for (const key of ints) if (!Number.isInteger(p[key]) || p[key] < 0) throw new Error(`map parameter ${key} must be a non-negative integer`);
  // The client accepts source zooms 0–22 (geo_map_config.gd, ParcelPayload.kt).
  if (p.tile_minzoom > p.tile_maxzoom || p.tile_maxzoom > 22) throw new Error('tile zooms must satisfy tile_minzoom ≤ tile_maxzoom ≤ 22');
  if (p.tile_extent < 256 || p.tile_extent > 16384) throw new Error('tile_extent must be within 256–16384');
  if (p.tile_buffer > p.tile_extent / 2) throw new Error('tile_buffer must be at most half the extent');
  if (p.building_decimals < 5 || p.building_decimals > 7) throw new Error('building_decimals must be within 5–7');
  if (!(p.building_simplify_m >= 0 && p.building_simplify_m <= 1)) throw new Error('building_simplify_m must be within 0–1 m');
  return p;
}

export type TileValue = string | number | boolean;

export interface TileFeature {
  /** Sort key and promoted id (block_id). */
  id: string;
  properties: Record<string, TileValue>;
  /** lon/lat polygons, outer ring first. */
  polygons: Polygon[];
}

/** Web Mercator in [0, 1)²: x east, y south. */
export function mercator([lon, lat]: Point): Point {
  const s = sin((lat * Math.PI) / 180);
  return [(lon + 180) / 360, 0.5 - log((1 + s) / (1 - s)) / (4 * Math.PI)];
}

export const tilePath = (z: number, x: number, y: number) => `tiles/${z}/${x}/${y}.pbf`;

/** Encodes every feature into the tiles it touches; returns tilePath → MVT bytes (uncompressed). */
export function encodeTiles(features: TileFeature[], p: MapLayerParams): Map<string, Uint8Array> {
  const sorted = [...features].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const world = sorted.map(f => f.polygons.map(poly => poly.map(ring => ring.map(mercator))));
  const tiles = new Map<string, Uint8Array>();
  for (let z = p.tile_minzoom; z <= p.tile_maxzoom; z++) {
    const scale = (1 << z) * p.tile_extent; // integer, so scaling is exact (no `**`: see detmath.ts)
    const perTile = new Map<string, { x: number; y: number; features: { feature: TileFeature; geometry: number[] }[] }>();
    sorted.forEach((feature, fi) => {
      const polys = world[fi].map(poly => poly.map(ring => ring.map(([x, y]) => [x * scale, y * scale] as Point)));
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      for (const poly of polys) for (const [x, y] of poly[0]) {
        minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y);
      }
      const last = (1 << z) - 1;
      const t0x = Math.max(0, Math.floor((minX - p.tile_buffer) / p.tile_extent));
      const t1x = Math.min(last, Math.floor((maxX + p.tile_buffer) / p.tile_extent));
      const t0y = Math.max(0, Math.floor((minY - p.tile_buffer) / p.tile_extent));
      const t1y = Math.min(last, Math.floor((maxY + p.tile_buffer) / p.tile_extent));
      for (let tx = t0x; tx <= t1x; tx++) for (let ty = t0y; ty <= t1y; ty++) {
        const geometry = tileGeometry(polys, tx * p.tile_extent, ty * p.tile_extent, p.tile_extent, p.tile_buffer);
        if (geometry.length === 0) continue;
        const key = tilePath(z, tx, ty);
        if (!perTile.has(key)) perTile.set(key, { x: tx, y: ty, features: [] });
        perTile.get(key)!.features.push({ feature, geometry });
      }
    });
    const keys = [...perTile.keys()].sort((a, b) => {
      const ta = perTile.get(a)!;
      const tb = perTile.get(b)!;
      return ta.x - tb.x || ta.y - tb.y;
    });
    for (const key of keys) tiles.set(key, encodeLayer('parcels', p.tile_extent, perTile.get(key)!.features));
  }
  return tiles;
}

/**
 * Clips each ring to the buffered tile, quantizes it to tile units and encodes MVT polygon
 * commands. Outer rings get positive area in tile coordinates (y down), holes negative; a hole
 * whose outer ring vanished is dropped with it.
 */
function tileGeometry(polys: Polygon[], ox: number, oy: number, extent: number, buffer: number): number[] {
  const commands: number[] = [];
  let cx = 0;
  let cy = 0;
  for (const poly of polys) {
    let outerKept = false;
    poly.forEach((ring, ri) => {
      if (ri > 0 && !outerKept) return;
      const clipped = clipRing(ring, ox - buffer, oy - buffer, ox + extent + buffer, oy + extent + buffer);
      const q: Point[] = [];
      for (const [x, y] of clipped) {
        const pt: Point = [Math.round(x - ox), Math.round(y - oy)];
        const prev = q[q.length - 1];
        if (!prev || prev[0] !== pt[0] || prev[1] !== pt[1]) q.push(pt);
      }
      while (q.length > 1 && q[0][0] === q[q.length - 1][0] && q[0][1] === q[q.length - 1][1]) q.pop();
      if (q.length < 3) return;
      const area = ringArea2(q);
      if (area === 0) return;
      if ((ri === 0) !== (area > 0)) q.reverse();
      if (ri === 0) outerKept = true;
      commands.push(command(1, 1), zigzag(q[0][0] - cx), zigzag(q[0][1] - cy));
      cx = q[0][0]; cy = q[0][1];
      commands.push(command(2, q.length - 1));
      for (let i = 1; i < q.length; i++) {
        commands.push(zigzag(q[i][0] - cx), zigzag(q[i][1] - cy));
        cx = q[i][0]; cy = q[i][1];
      }
      commands.push(command(7, 1));
    });
  }
  return commands;
}

/** Twice the signed area (positive = clockwise on screen, the MVT outer-ring orientation). */
export function ringArea2(ring: Point[]): number {
  let sum = 0;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) sum += ring[j][0] * ring[i][1] - ring[i][0] * ring[j][1];
  return sum;
}

/** Sutherland–Hodgman against an axis-aligned box; the result is open (no repeated first point). */
export function clipRing(ring: Ring, x0: number, y0: number, x1: number, y1: number): Point[] {
  let pts: Point[] = ring.length > 1 && ring[0][0] === ring[ring.length - 1][0] && ring[0][1] === ring[ring.length - 1][1]
    ? ring.slice(0, -1) : ring.slice();
  const edges: [number, number, boolean][] = [[0, x0, true], [0, x1, false], [1, y0, true], [1, y1, false]];
  for (const [axis, bound, lower] of edges) {
    if (pts.length === 0) break;
    const inside = (pt: Point) => (lower ? pt[axis] >= bound : pt[axis] <= bound);
    const out: Point[] = [];
    for (let i = 0; i < pts.length; i++) {
      const a = pts[(i + pts.length - 1) % pts.length];
      const b = pts[i];
      const ain = inside(a);
      const bin = inside(b);
      if (ain !== bin) {
        const t = (bound - a[axis]) / (b[axis] - a[axis]);
        const other = 1 - axis;
        const cross: Point = [0, 0];
        cross[axis] = bound;
        cross[other] = a[other] + (b[other] - a[other]) * t;
        out.push(cross);
      }
      if (bin) out.push(b);
    }
    pts = out;
  }
  return pts;
}

const command = (id: number, count: number) => (id & 7) | (count << 3);
const zigzag = (n: number) => (n << 1) ^ (n >> 31);

/** Minimal protobuf writer for the vector_tile.proto messages. */
class Writer {
  private buf = new Uint8Array(1024);
  length = 0;
  private ensure(n: number) {
    if (this.length + n <= this.buf.length) return;
    let size = this.buf.length * 2;
    while (size < this.length + n) size *= 2;
    const next = new Uint8Array(size);
    next.set(this.buf.subarray(0, this.length));
    this.buf = next;
  }
  varint(v: number) {
    if (!Number.isSafeInteger(v) || v < 0) throw new Error(`varint out of range: ${v}`);
    this.ensure(10);
    while (v >= 0x80) { this.buf[this.length++] = (v % 0x80) | 0x80; v = Math.floor(v / 0x80); }
    this.buf[this.length++] = v;
  }
  tag(field: number, wire: number) { this.varint(field * 8 + wire); }
  bytes(field: number, data: Uint8Array) { this.tag(field, 2); this.varint(data.length); this.ensure(data.length); this.buf.set(data, this.length); this.length += data.length; }
  string(field: number, s: string) { this.bytes(field, new TextEncoder().encode(s)); }
  packed(field: number, values: number[]) { const w = new Writer(); for (const v of values) w.varint(v); this.bytes(field, w.finish()); }
  double(field: number, v: number) {
    this.tag(field, 1);
    this.ensure(8);
    new DataView(this.buf.buffer, this.buf.byteOffset + this.length, 8).setFloat64(0, v, true);
    this.length += 8;
  }
  finish() { return this.buf.slice(0, this.length); }
}

function encodeValue(v: TileValue): Uint8Array {
  const w = new Writer();
  if (typeof v === 'string') w.string(1, v);
  else if (typeof v === 'boolean') { w.tag(7, 0); w.varint(v ? 1 : 0); }
  else if (Number.isSafeInteger(v) && v >= 0) { w.tag(5, 0); w.varint(v); }
  else if (Number.isSafeInteger(v)) { w.tag(6, 0); w.varint(-2 * v - 1); }
  else if (Number.isFinite(v)) w.double(3, v);
  else throw new Error(`cannot encode tile value ${v}`);
  return w.finish();
}

function encodeLayer(name: string, extent: number, features: { feature: TileFeature; geometry: number[] }[]): Uint8Array {
  const keys: string[] = [];
  const keyIndex = new Map<string, number>();
  const values: Uint8Array[] = [];
  const valueIndex = new Map<string, number>();
  const layer = new Writer();
  layer.tag(15, 0); layer.varint(2);
  layer.string(1, name);
  for (const { feature, geometry } of features) {
    const tags: number[] = [];
    for (const [key, value] of Object.entries(feature.properties)) {
      if (!keyIndex.has(key)) { keyIndex.set(key, keys.length); keys.push(key); }
      const vk = `${typeof value}:${String(value)}`;
      if (!valueIndex.has(vk)) { valueIndex.set(vk, values.length); values.push(encodeValue(value)); }
      tags.push(keyIndex.get(key)!, valueIndex.get(vk)!);
    }
    const f = new Writer();
    f.packed(2, tags);
    f.tag(3, 0); f.varint(3); // POLYGON
    f.packed(4, geometry);
    layer.bytes(2, f.finish());
  }
  for (const key of keys) layer.string(3, key);
  for (const value of values) layer.bytes(4, value);
  layer.tag(5, 0); layer.varint(extent);
  const tile = new Writer();
  tile.bytes(3, layer.finish());
  return tile.finish();
}
