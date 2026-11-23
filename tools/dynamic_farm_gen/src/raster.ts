/** Supersampled scanline rasterization of building footprints onto a rotated metric grid. */
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
  const b = bounds(rings.flat());
  const u0 = (Math.floor(b.minX / cell_m) - margin - phase[0]) * cell_m;
  const v0 = (Math.floor(b.minY / cell_m) - margin - phase[1]) * cell_m;
  const width = Math.ceil((b.maxX - u0) / cell_m) + margin;
  const height = Math.ceil((b.maxY - v0) / cell_m) + margin;
  const frame: Frame = { rotation_deg, cell_m, u0, v0, width, height };
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
  /** 1 where the cell is core. */
  mask: Uint8Array;
  count: number;
  /** Raster/footprint intersection-over-union, from the same supersampling. */
  iou: number;
}

export function threshold(c: Coverage, minCoverage: number): CoreRaster {
  const mask = new Uint8Array(c.cov.length);
  let count = 0;
  let inter = 0;
  let area = 0;
  for (let i = 0; i < c.cov.length; i++) {
    area += c.cov[i];
    if (c.cov[i] >= minCoverage) { mask[i] = 1; count++; inter += c.cov[i]; }
  }
  const union = count + area - inter;
  return { frame: c.frame, mask, count, iou: union > 0 ? inter / union : 0 };
}

const PHASES: [number, number][] = [];
for (const px of [0, 0.25, 0.5, 0.75]) for (const py of [0, 0.25, 0.5, 0.75]) PHASES.push([px, py]);

/** Best of 16 sub-cell grid offsets by IoU; ties keep the earlier phase so the choice is stable. */
export function bestCore(polys: Polygon[], rotation_deg: number, cell_m: number, samples: number, minCoverage: number): CoreRaster {
  let best: CoreRaster | null = null;
  for (const phase of PHASES) {
    const r = threshold(rasterize(polys, rotation_deg, cell_m, samples, phase), minCoverage);
    if (!best || r.iou > best.iou + 1e-12) best = r;
  }
  return best!;
}
