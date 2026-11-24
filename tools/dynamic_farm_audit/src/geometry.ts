/**
 * Exact planar geometry for the audit. Projection uses proj4 and polygon operations use
 * polygon-clipping, both independent of the generator's own projection and rasterizer.
 */
import polygonClipping, { type MultiPolygon, type Polygon, type Ring } from 'polygon-clipping';
import proj4 from 'proj4';

export type { MultiPolygon, Polygon, Ring };
export type Pair = [number, number];

const UTM10N = '+proj=utm +zone=10 +datum=WGS84 +units=m +no_defs';
const toUtm = proj4('EPSG:4326', UTM10N);

/** WGS84 lon/lat to UTM zone 10N (EPSG:32610) metres. */
export function lonLatToUtm(lon: number, lat: number): Pair {
  const [x, y] = toUtm.forward([lon, lat]);
  return [x, y];
}

/** GeoJSON Polygon / MultiPolygon coordinates to a list of polygons; other types give []. */
export function geoJsonPolygons(geometry: { type: string; coordinates: unknown } | null | undefined): Polygon[] {
  if (!geometry) return [];
  const list = geometry.type === 'Polygon' ? [geometry.coordinates as number[][][]]
    : geometry.type === 'MultiPolygon' ? (geometry.coordinates as number[][][][]) : [];
  const out: Polygon[] = [];
  for (const poly of list) {
    if (!Array.isArray(poly)) continue;
    const rings = poly
      .filter(Array.isArray)
      .map(ring => ring.filter(p => Array.isArray(p) && Number.isFinite(p[0]) && Number.isFinite(p[1])).map(p => [p[0], p[1]] as Pair))
      .filter(ring => ring.length >= 4);
    if (rings.length > 0) out.push(rings);
  }
  return out;
}

export const mapPolygons = (polys: Polygon[], f: (p: Pair) => Pair): Polygon[] =>
  polys.map(poly => poly.map(ring => ring.map(p => f(p as Pair))));

/**
 * Metric UTM point into the farm grid frame: rotated by the farm's rotation_deg the same way the
 * schema documents it (source points are rotated by -rotation_deg), translated so grid point (0,0)
 * is the origin and scaled so one cell is one unit.
 */
export function gridTransform(originM: Pair, rotationDeg: number, cellM: number): (p: Pair) => Pair {
  const t = (rotationDeg * Math.PI) / 180;
  const c = Math.cos(t);
  const s = Math.sin(t);
  return ([x, y]) => {
    const dx = x - originM[0];
    const dy = y - originM[1];
    return [(dx * c + dy * s) / cellM, (-dx * s + dy * c) / cellM];
  };
}

function ringArea(ring: Ring): number {
  if (ring.length < 3) return 0;
  const [ox, oy] = ring[0];
  let sum = 0;
  for (let i = 0; i < ring.length; i++) {
    const a = ring[i];
    const b = ring[(i + 1) % ring.length];
    sum += (a[0] - ox) * (b[1] - oy) - (b[0] - ox) * (a[1] - oy);
  }
  return Math.abs(sum / 2);
}

/** Area of a valid (non-overlapping) multipolygon such as polygon-clipping output. */
export function multiArea(mp: MultiPolygon): number {
  let a = 0;
  for (const poly of mp) {
    if (poly.length === 0) continue;
    a += ringArea(poly[0]);
    for (const hole of poly.slice(1)) a -= ringArea(hole);
  }
  return a;
}

/** Sum of the input polygons' own areas (overlaps counted twice), as a raw source would report it. */
export function rawArea(polys: Polygon[]): number {
  let a = 0;
  for (const poly of polys) {
    if (poly.length === 0) continue;
    let pa = ringArea(poly[0]);
    for (const hole of poly.slice(1)) pa -= ringArea(hole);
    a += Math.max(pa, 0);
  }
  return a;
}

/** Union of all polygons; each one is unioned on its own so a self-touching footprint is normalised. */
export function unionAll(polys: Polygon[]): MultiPolygon {
  if (polys.length === 0) return [];
  const [first, ...rest] = polys;
  return polygonClipping.union(first, ...rest);
}

export interface Topology { components: number; holes: number }

export const topology = (mp: MultiPolygon): Topology => ({
  components: mp.length,
  holes: mp.reduce((n, poly) => n + Math.max(poly.length - 1, 0), 0),
});

export function intersectionArea(a: MultiPolygon | Polygon, b: MultiPolygon | Polygon): number {
  return multiArea(polygonClipping.intersection(a, b));
}

const box = (x0: number, y0: number, x1: number, y1: number): Polygon => [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]];

/**
 * Exact area of `shape` (grid units) inside the cells listed as runs [y, x, length, ...].
 * Runs must be disjoint; the shape is first cut to each row strip so each run clip stays small.
 */
export function runsIntersectionArea(shape: MultiPolygon, runs: number[][]): number {
  if (shape.length === 0) return 0;
  const rows = new Map<number, number[][]>();
  for (const r of runs) {
    if (!rows.has(r[0])) rows.set(r[0], []);
    rows.get(r[0])!.push(r);
  }
  let minX = Infinity;
  let maxX = -Infinity;
  for (const poly of shape) for (const [x] of poly[0]) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); }
  let total = 0;
  for (const [y, list] of rows) {
    const strip = polygonClipping.intersection(shape, box(Math.floor(minX) - 1, y, Math.ceil(maxX) + 1, y + 1));
    if (strip.length === 0) continue;
    for (const [, x, n] of list) total += multiArea(polygonClipping.intersection(strip, box(x, y, x + n, y + 1)));
  }
  return total;
}

/**
 * Cell-mask topology: foreground components with 4-connectivity (as farm cells connect) and holes
 * as background components with 8-connectivity that do not reach the grid border.
 */
export function maskTopology(mask: Uint8Array, w: number, h: number): Topology {
  // Pad by one cell so the outside background is a single border-touching component.
  const W = w + 2;
  const H = h + 2;
  const m = new Uint8Array(W * H);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) m[(y + 1) * W + x + 1] = mask[y * w + x];
  const seen = new Uint8Array(W * H);
  const stack: number[] = [];
  const flood = (start: number, value: number, eight: boolean) => {
    seen[start] = 1;
    stack.push(start);
    while (stack.length) {
      const c = stack.pop()!;
      const cx = c % W;
      const cy = (c - cx) / W;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        if ((dx === 0 && dy === 0) || (!eight && dx !== 0 && dy !== 0)) continue;
        const nx = cx + dx;
        const ny = cy + dy;
        if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
        const n = ny * W + nx;
        if (seen[n] || m[n] !== value) continue;
        seen[n] = 1;
        stack.push(n);
      }
    }
  };
  let components = 0;
  let background = 0;
  for (let i = 0; i < m.length; i++) {
    if (seen[i]) continue;
    if (m[i]) { components++; flood(i, 1, false); } else { background++; flood(i, 0, true); }
  }
  return { components, holes: background - 1 };
}
