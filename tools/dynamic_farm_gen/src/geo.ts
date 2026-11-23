/** Planar geometry helpers. Lon/lat in WGS84 degrees; metres in UTM zone 10N (EPSG:32610). */

export type Point = [number, number];
export type Ring = Point[];
/** First ring is the outer boundary, the rest are holes. Rings may be open or closed. */
export type Polygon = Ring[];

export const UTM_CRS = 'EPSG:32610';
const A = 6378137;
const F = 1 / 298.257223563;
const K0 = 0.9996;
const LON0 = -123; // zone 10 central meridian
const FALSE_EASTING = 500000;

// Krüger series (Karney 2011), sixth order in n: sub-millimetre inside a UTM zone.
const N = F / (2 - F);
const A_HAT = (A / (1 + N)) * (1 + N ** 2 / 4 + N ** 4 / 64 + N ** 6 / 256);
const ALPHA = [
  N / 2 - (2 * N ** 2) / 3 + (5 * N ** 3) / 16 + (41 * N ** 4) / 180 - (127 * N ** 5) / 288 + (7891 * N ** 6) / 37800,
  (13 * N ** 2) / 48 - (3 * N ** 3) / 5 + (557 * N ** 4) / 1440 + (281 * N ** 5) / 630 - (1983433 * N ** 6) / 1935360,
  (61 * N ** 3) / 240 - (103 * N ** 4) / 140 + (15061 * N ** 5) / 26880 + (167603 * N ** 6) / 181440,
  (49561 * N ** 4) / 161280 - (179 * N ** 5) / 168 + (6601661 * N ** 6) / 7257600,
  (34729 * N ** 5) / 80640 - (3418889 * N ** 6) / 1995840,
  (212378941 * N ** 6) / 319334400,
];
const E = Math.sqrt(F * (2 - F));

/** WGS84 lon/lat (degrees) to UTM zone 10N easting/northing (metres). */
export function toUtm(lon: number, lat: number): Point {
  const phi = (lat * Math.PI) / 180;
  const lambda = ((lon - LON0) * Math.PI) / 180;
  const tau = Math.tan(phi);
  const sigma = Math.sinh(E * Math.atanh((E * tau) / Math.sqrt(1 + tau * tau)));
  const tauP = tau * Math.sqrt(1 + sigma * sigma) - sigma * Math.sqrt(1 + tau * tau);
  const xiP = Math.atan2(tauP, Math.cos(lambda));
  const etaP = Math.asinh(Math.sin(lambda) / Math.sqrt(tauP * tauP + Math.cos(lambda) ** 2));
  let xi = xiP;
  let eta = etaP;
  for (let j = 1; j <= 6; j++) {
    xi += ALPHA[j - 1] * Math.sin(2 * j * xiP) * Math.cosh(2 * j * etaP);
    eta += ALPHA[j - 1] * Math.cos(2 * j * xiP) * Math.sinh(2 * j * etaP);
  }
  return [FALSE_EASTING + K0 * A_HAT * eta, K0 * A_HAT * xi];
}

export function closeRing(ring: Ring): Ring {
  if (ring.length === 0) return ring;
  const [a, b] = [ring[0], ring[ring.length - 1]];
  return a[0] === b[0] && a[1] === b[1] ? ring : [...ring, a];
}

/** Signed shoelace area; positive for counter-clockwise rings in a y-up frame. */
export function signedArea(ring: Ring): number {
  const r = closeRing(ring);
  let sum = 0;
  for (let i = 0; i + 1 < r.length; i++) sum += r[i][0] * r[i + 1][1] - r[i + 1][0] * r[i][1];
  return sum / 2;
}

export function polygonArea(poly: Polygon): number {
  if (poly.length === 0) return 0;
  let area = Math.abs(signedArea(poly[0]));
  for (const hole of poly.slice(1)) area -= Math.abs(signedArea(hole));
  return Math.max(area, 0);
}

/** Even-odd test over every ring, so holes and multipart input both work. */
export function insideRings(rings: Ring[], x: number, y: number): boolean {
  let inside = false;
  for (const ring of rings) {
    const r = closeRing(ring);
    for (let i = 0, j = r.length - 2; i < r.length - 1; j = i++) {
      const [xi, yi] = r[i];
      const [xj, yj] = r[j];
      if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
    }
  }
  return inside;
}

export interface Bounds { minX: number; minY: number; maxX: number; maxY: number }

export function bounds(rings: Ring[]): Bounds {
  const b = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity };
  for (const ring of rings) for (const [x, y] of ring) {
    if (x < b.minX) b.minX = x;
    if (y < b.minY) b.minY = y;
    if (x > b.maxX) b.maxX = x;
    if (y > b.maxY) b.maxY = y;
  }
  return b;
}

/** Rotates by -deg, i.e. a source edge at bearing `deg` from +x becomes axis-aligned. */
export function rotate(p: Point, deg: number): Point {
  const t = (deg * Math.PI) / 180;
  const c = Math.cos(t);
  const s = Math.sin(t);
  return [p[0] * c + p[1] * s, -p[0] * s + p[1] * c];
}

/** Inverse of rotate(). */
export function unrotate(p: Point, deg: number): Point {
  return rotate(p, -deg);
}

/**
 * Dominant edge direction modulo 90°, folded into (-45, 45]. Length-weighted 1° bins with a
 * ±1° window, so a footprint drawn slightly off-square still snaps to its own walls.
 */
export function dominantAngle(polys: Polygon[]): number {
  const edges: [number, number][] = [];
  const bins = new Array<number>(90).fill(0);
  for (const poly of polys) for (const ring of poly) {
    const r = closeRing(ring);
    for (let i = 0; i + 1 < r.length; i++) {
      const dx = r[i + 1][0] - r[i][0];
      const dy = r[i + 1][1] - r[i][1];
      const len = Math.hypot(dx, dy);
      if (len === 0) continue;
      const deg = ((((Math.atan2(dy, dx) * 180) / Math.PI) % 90) + 90) % 90;
      edges.push([deg, len]);
      bins[Math.round(deg) % 90] += len;
    }
  }
  let best = 0;
  let bestScore = -1;
  for (let b = 0; b < 90; b++) {
    const score = bins[(b + 89) % 90] + bins[b] + bins[(b + 1) % 90];
    if (score > bestScore + 1e-9) { best = b; bestScore = score; }
  }
  // Refine to the length-weighted mean of the edges inside the winning window.
  const offset = (deg: number) => ((((deg - best) % 90) + 135) % 90) - 45;
  let sum = 0;
  let weight = 0;
  for (const [deg, len] of edges) {
    const d = offset(deg);
    if (Math.abs(d) <= 1.5) { sum += d * len; weight += len; }
  }
  let angle = best + (weight > 0 ? sum / weight : 0);
  if (angle > 45) angle -= 90;
  if (angle <= -45) angle += 90;
  return round(angle, 3);
}

export function round(value: number, digits: number): number {
  const m = 10 ** digits;
  const r = Math.round(value * m) / m;
  return Object.is(r, -0) ? 0 : r;
}
