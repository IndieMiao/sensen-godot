/**
 * The DataSF building map layer (`buildings.geojson`). The client can read buildings only as one
 * GeoJSON file (geo_map_config.gd, building_source=datasf), so it is made lighter in place:
 * one `block_id` property per footprint, coordinates rounded to `building_decimals`, and vertices
 * within `building_simplify_m` of the outline dropped (Douglas–Peucker in local metres). Nothing
 * else changes: every used footprint stays a separate feature, so tapping a building still
 * highlights that building. A ring that would degenerate keeps its unsimplified rounded shape.
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
    const rings: number[][][] = [];
    poly.forEach((ring, ri) => {
      const slim = slimRing(ring, p, kx);
      if (slim) rings.push(slim);
      else if (ri === 0) rings.push(roundRing(ring, 7)); // never lose a footprint
    });
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

function area2(ring: number[][]): number {
  let sum = 0;
  for (let i = 0; i + 1 < ring.length; i++) sum += ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1];
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
