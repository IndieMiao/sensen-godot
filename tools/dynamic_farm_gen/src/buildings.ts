/**
 * The DataSF building map layer (`buildings.geojson`). The client can read buildings only as one
 * GeoJSON file (geo_map_config.gd, building_source=datasf), so it is made lighter in place:
 * one `block_id` property per footprint, coordinates rounded to `building_decimals`, and vertices
 * within `building_simplify_m` of the outline dropped (Douglas–Peucker in local metres). Nothing
 * else changes: every used footprint stays a separate feature, so tapping a building still
 * highlights that building. A ring that would degenerate keeps its unsimplified rounded shape;
 * a part with no area left at 7 decimals is dropped, and a footprint with no part left has no feature.
 * Which source footprints each farm used stays traceable through the generation report.
 */
import { cos } from './detmath.js';
import { round, type Point, type Polygon, type Ring } from './geo.js';
import type { MapLayerParams } from './mvt.js';

const M_PER_DEG_LAT = 111_320;

export function slimPolygons(polys: Polygon[], p: MapLayerParams): number[][][][] {
  const lat0 = polys[0][0][0][1];
  const kx = M_PER_DEG_LAT * cos((lat0 * Math.PI) / 180);
  const out: number[][][][] = [];
  for (const poly of polys) {
    // Never lose a footprint to rounding: fall back to 7 decimals. An outer ring that has no area
    // even then (a sliver part of a MultiPolygon) is dropped with its holes: the native map rejects
    // the whole layer when one ring has fewer than 4 positions (C-43 V-167).
    const fine = roundRing(poly[0], 7);
    const outer = slimRing(poly[0], p, kx) ?? (valid(fine) ? fine : null);
    if (!outer) continue;
    const rings = [outer];
    for (const hole of poly.slice(1)) {
      const slim = slimRing(hole, p, kx);
      if (slim) rings.push(slim);
    }
    out.push(rings);
  }
  return out;
}

function roundRing(ring: Ring, digits: number): number[][] {
  const out: number[][] = [];
  for (const [x, y] of ring) {
    const pt = [round(x, digits), round(y, digits)];
    const prev = out[out.length - 1];
    if (!prev || prev[0] !== pt[0] || prev[1] !== pt[1]) out.push(pt);
  }
  if (out.length > 1 && (out[0][0] !== out[out.length - 1][0] || out[0][1] !== out[out.length - 1][1])) out.push(out[0]);
  return out;
}

const valid = (ring: number[][]) => ring.length >= 4 && area2(ring) !== 0;

/** Relative to the first point: products of raw lon/lat cancel out for a footprint a few cm across. */
function area2(ring: number[][]): number {
  const [ox, oy] = ring[0];
  let sum = 0;
  for (let i = 0; i + 1 < ring.length; i++) sum += (ring[i][0] - ox) * (ring[i + 1][1] - oy) - (ring[i + 1][0] - ox) * (ring[i][1] - oy);
  return sum;
}

/** Rounded and simplified ring, or the rounded ring if simplifying degenerates it, or null. */
function slimRing(ring: Ring, p: MapLayerParams, kx: number): number[][] | null {
  const rounded = roundRing(ring, p.building_decimals);
  if (!valid(rounded)) return null;
  if (p.building_simplify_m <= 0) return rounded;
  const [ox, oy] = rounded[0];
  const local: Point[] = rounded.map(([x, y]) => [(x - ox) * kx, (y - oy) * M_PER_DEG_LAT]);
  const keep = douglasPeucker(local, p.building_simplify_m);
  const simplified = rounded.filter((_, i) => keep[i]);
  return valid(simplified) ? simplified : rounded;
}

/** Keeps first/last points and every point farther than `tolerance` from the simplified chain. */
export function douglasPeucker(points: Point[], tolerance: number): boolean[] {
  const keep = points.map(() => false);
  keep[0] = true;
  keep[points.length - 1] = true;
  const stack: [number, number][] = [[0, points.length - 1]];
  const tol2 = tolerance * tolerance;
  while (stack.length > 0) {
    const [a, b] = stack.pop()!;
    let best = -1;
    let bestD = tol2;
    for (let i = a + 1; i < b; i++) {
      const d = segmentDistance2(points[i], points[a], points[b]);
      if (d > bestD) { bestD = d; best = i; }
    }
    if (best >= 0) {
      keep[best] = true;
      stack.push([a, best], [best, b]);
    }
  }
  return keep;
}

function segmentDistance2([px, py]: Point, [ax, ay]: Point, [bx, by]: Point): number {
  const dx = bx - ax;
  const dy = by - ay;
  const len2 = dx * dx + dy * dy;
  let t = len2 === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2;
  t = Math.max(0, Math.min(1, t));
  const ex = ax + dx * t - px;
  const ey = ay + dy * t - py;
  return ex * ex + ey * ey;
}
