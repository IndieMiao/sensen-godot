/**
 * Building footprints on a rotated metric grid: exact per-cell coverage for the farm core, and a
 * supersampled scanline rasterization (centre samples) for assigning buildings to parcels.
 */
import { bounds, closeRing, rotate, type Polygon, type Ring } from './geo.js';

export interface Frame {
  /** Grid rotation: source points are rotated by -rotation_deg before sampling. */
  rotation_deg: number;
  /** Real edge length of one cell (m). */
  cell_m: number;
  /** Rotated-frame metric coordinate of grid point (0, 0). */
  u0: number;
  v0: number;
  width: number;
  height: number;
}

export interface Coverage {
  frame: Frame;
  /** Fraction of each cell covered by the union of the footprints, row-major (y * width + x). */
  cov: Float64Array;
}

/**
 * Rasterizes the union of `polys` (metric, unrotated) with `samples`² points per cell.
 * `phase` ([0,1)²) shifts the grid by a fraction of a cell, `margin` adds empty cells around.
 */
export function rasterize(polys: Polygon[], rotation_deg: number, cell_m: number, samples: number,
  phase: [number, number] = [0, 0], margin = 1): Coverage {
  const rings: Ring[][] = polys.map(poly => poly.map(ring => closeRing(ring).map(p => rotate(p, rotation_deg))));
  const frame = frameFor(rings, rotation_deg, cell_m, phase, margin);
  const { width, height, u0, v0 } = frame;
  const hits = new Uint16Array(width * height);
  const row = new Uint8Array(width * samples);
  const step = cell_m / samples;
  for (let sy = 0; sy < height * samples; sy++) {
    const y = v0 + (sy + 0.5) * step;
    row.fill(0);
    let any = false;
    for (const poly of rings) {
      const xs: number[] = [];
      for (const ring of poly) {
        for (let i = 0; i + 1 < ring.length; i++) {
          const [x1, y1] = ring[i];
          const [x2, y2] = ring[i + 1];
          if (y1 > y !== y2 > y) xs.push(x1 + ((y - y1) * (x2 - x1)) / (y2 - y1));
        }
      }
      xs.sort((a, c) => a - c);
      for (let k = 0; k + 1 < xs.length; k += 2) {
        // Sample sx is inside when its centre lies in [xs[k], xs[k+1]).
        const from = Math.max(0, Math.ceil((xs[k] - u0) / step - 0.5));
        const to = Math.min(width * samples - 1, Math.ceil((xs[k + 1] - u0) / step - 0.5) - 1);
        for (let sx = from; sx <= to; sx++) row[sx] = 1;
        if (to >= from) any = true;
      }
    }
    if (!any) continue;
    const cy = Math.floor(sy / samples);
    for (let sx = 0; sx < row.length; sx++) if (row[sx]) hits[cy * width + Math.floor(sx / samples)]++;
  }
  const cov = new Float64Array(width * height);
  const total = samples * samples;
  for (let i = 0; i < cov.length; i++) cov[i] = hits[i] / total;
  return { frame, cov };
}

export interface CoreRaster {
  frame: Frame;
  /** Exact fraction of each cell inside the footprints (clamped to 1 where footprints overlap). */
  cov: Float64Array;
  /** 1 where the cell is core. */
  mask: Uint8Array;
  count: number;
  /** Raster/footprint intersection-over-union from the exact coverage. */
  iou: number;
}

export function threshold(c: Coverage, minCoverage: number): CoreRaster {
  const mask = new Uint8Array(c.cov.length);
  let count = 0;
  for (let i = 0; i < c.cov.length; i++) if (c.cov[i] >= minCoverage) { mask[i] = 1; count++; }
  return { frame: c.frame, cov: c.cov, mask, count, iou: maskIou(c.cov, mask) };
}

/**
 * IoU of a cell mask against the footprints, both in cell units: the union is the mask's cells plus
 * the footprint area outside them. Every cell of the frame must hold its coverage, so the frame has
 * to contain the whole footprint (the rasterizers add a margin).
 */
export function maskIou(cov: Float64Array, mask: Uint8Array): number {
  let count = 0;
  let inter = 0;
  let area = 0;
  for (let i = 0; i < cov.length; i++) {
    area += cov[i];
    if (mask[i]) { count++; inter += cov[i]; }
  }
  const union = count + area - inter;
  return union > 0 ? inter / union : 0;
}

/** Grid frame shared by both rasterizers: rings rotated, origin snapped to the cell grid minus `phase`. */
function frameFor(rings: Ring[][], rotation_deg: number, cell_m: number, phase: [number, number], margin: number): Frame {
  const b = bounds(rings.flat());
  const u0 = (Math.floor(b.minX / cell_m) - margin - phase[0]) * cell_m;
  const v0 = (Math.floor(b.minY / cell_m) - margin - phase[1]) * cell_m;
  const width = Math.ceil((b.maxX - u0) / cell_m) + margin;
  const height = Math.ceil((b.maxY - v0) / cell_m) + margin;
  return { rotation_deg, cell_m, u0, v0, width, height };
}

/** Sutherland–Hodgman against one axis-aligned half-plane: keeps `sign * (p[axis] - at) >= 0`. */
function clipHalf(pts: number[], axis: 0 | 1, at: number, sign: 1 | -1): number[] {
  const out: number[] = [];
  const n = pts.length / 2;
  if (n === 0) return out;
  const o = 1 - axis;
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    const ai = pts[2 * i + axis];
    const aj = pts[2 * j + axis];
    const inI = sign * (ai - at) >= 0;
    const inJ = sign * (aj - at) >= 0;
    if (inI) out.push(pts[2 * i], pts[2 * i + 1]);
    if (inI !== inJ) {
      const t = (at - ai) / (aj - ai);
      const v = pts[2 * i + o] + (pts[2 * j + o] - pts[2 * i + o]) * t;
      if (axis === 0) out.push(at, v); else out.push(v, at);
    }
  }
  return out;
}

/** Signed shoelace area of a flat [x0, y0, x1, y1, …] ring, relative to its first vertex. */
function flatArea(pts: number[]): number {
  const n = pts.length / 2;
  if (n < 3) return 0;
  const ox = pts[0];
  const oy = pts[1];
  let sum = 0;
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    sum += (pts[2 * i] - ox) * (pts[2 * j + 1] - oy) - (pts[2 * j] - ox) * (pts[2 * i + 1] - oy);
  }
  return sum / 2;
}

/**
 * Exact coverage: the area of each cell inside the footprints, by clipping every ring to each grid
 * row and then to each column line (only + − × ÷, so bit-identical on every platform). A polygon's
 * holes subtract from its outer ring; separate polygons add up and a cell is clamped to 1, which is
 * exact unless two footprints overlap inside that cell. Same frame as `rasterize`.
 */
export function exactCoverage(polys: Polygon[], rotation_deg: number, cell_m: number,
  phase: [number, number] = [0, 0], margin = 1): Coverage {
  const rings: Ring[][] = polys.map(poly => poly.map(ring => closeRing(ring).map(p => rotate(p, rotation_deg))));
  const frame = frameFor(rings, rotation_deg, cell_m, phase, margin);
  const { width, height, u0, v0 } = frame;
  const cov = new Float64Array(width * height);
  for (const poly of rings) {
    poly.forEach((ring, ri) => {
      // Ring in cell units relative to the frame, closing vertex dropped.
      const pts: number[] = [];
      let minY = Infinity;
      let maxY = -Infinity;
      for (let i = 0; i + 1 < ring.length; i++) {
        const x = (ring[i][0] - u0) / cell_m;
        const y = (ring[i][1] - v0) / cell_m;
        pts.push(x, y);
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      const whole = flatArea(pts);
      if (whole === 0) return;
      // Outer rings add, holes subtract, whatever the ring's own winding.
      const sign = (ri === 0 ? 1 : -1) * (whole > 0 ? 1 : -1);
      for (let y = Math.max(0, Math.floor(minY)); y < Math.min(height, Math.ceil(maxY)); y++) {
        const strip = clipHalf(clipHalf(pts, 1, y, 1), 1, y + 1, -1);
        if (strip.length < 6) continue;
        let minX = Infinity;
        let maxX = -Infinity;
        for (let i = 0; i < strip.length; i += 2) { if (strip[i] < minX) minX = strip[i]; if (strip[i] > maxX) maxX = strip[i]; }
        const x0 = Math.max(0, Math.floor(minX));
        const x1 = Math.min(width, Math.ceil(maxX));
        // left(X) = area of the strip left of the column line X; a cell holds left(x + 1) - left(x).
        let left = 0;
        for (let x = x0; x < x1; x++) {
          const next = x + 1 >= maxX ? flatArea(strip) : flatArea(clipHalf(strip, 0, x + 1, -1));
          cov[y * width + x] += sign * (next - left);
          left = next;
        }
      }
    });
  }
  for (let i = 0; i < cov.length; i++) cov[i] = cov[i] < 0 ? 0 : cov[i] > 1 ? 1 : cov[i];
  return { frame, cov };
}

const PHASES: [number, number][] = [];
for (const px of [0, 0.25, 0.5, 0.75]) for (const py of [0, 0.25, 0.5, 0.75]) PHASES.push([px, py]);

/** Best of 16 sub-cell grid offsets by exact IoU; ties keep the earlier phase so the choice is stable. */
export function bestCore(polys: Polygon[], rotation_deg: number, cell_m: number, minCoverage: number): CoreRaster {
  let best: CoreRaster | null = null;
  for (const phase of PHASES) {
    const r = threshold(exactCoverage(polys, rotation_deg, cell_m, phase), minCoverage);
    if (!best || r.iou > best.iou + 1e-12) best = r;
  }
  return best!;
}
