import { describe, expect, it } from 'vitest';
import { trace } from '../src/boundaries.js';
import { unrotate, type Polygon } from '../src/geo.js';
import { bestCore, rasterize, threshold } from '../src/raster.js';

const rect = (x: number, y: number, w: number, h: number): Polygon => [[[x, y], [x + w, y], [x + w, y + h], [x, y + h], [x, y]]];

describe('rasterize', () => {
  it('an aligned 10 m × 6 m footprint at 0.5 m is exactly 240 cells', () => {
    const core = threshold(rasterize([rect(100, 200, 10, 6)], 0, 0.5, 4), 0.5);
    expect(core.count).toBe(240);
    expect(core.iou).toBeCloseTo(1, 6);
  });
  it('cell count follows the real area: 0.25 m² per cell', () => {
    for (const [w, h] of [[8, 12], [15, 20], [31, 17]]) {
      const core = bestCore([rect(0, 0, w, h)], 0, 0.5, 4, 0.5);
      expect(core.count).toBe((w * h) / 0.25);
    }
  });
  it('a rotated footprint snaps back when the grid uses its angle', () => {
    const poly: Polygon = [rect(0, 0, 12, 7)[0].map(p => unrotate(p as [number, number], 33))];
    const aligned = bestCore([poly], 33, 0.5, 4, 0.5);
    const unaligned = bestCore([poly], 0, 0.5, 4, 0.5);
    expect(aligned.count).toBe(336);
    expect(aligned.iou).toBeGreaterThan(0.999);
    expect(unaligned.iou).toBeLessThan(aligned.iou);
  });
  it('keeps an L shape and a courtyard', () => {
    const l: Polygon = [[[0, 0], [10, 0], [10, 4], [4, 4], [4, 10], [0, 10], [0, 0]]];
    const core = threshold(rasterize([l], 0, 0.5, 4, [0, 0], 0), 0.5);
    expect(core.count).toBe(64 / 0.25);
    const courtyard: Polygon = [...rect(0, 0, 12, 12), rect(4, 4, 4, 4)[0]];
    expect(threshold(rasterize([courtyard], 0, 0.5, 4), 0.5).count).toBe(128 / 0.25);
  });
  it('unions separate and overlapping footprints', () => {
    const a = threshold(rasterize([rect(0, 0, 4, 4), rect(10, 0, 4, 4)], 0, 0.5, 4), 0.5);
    expect(a.count).toBe(128);
    const b = threshold(rasterize([rect(0, 0, 4, 4), rect(2, 0, 4, 4)], 0, 0.5, 4), 0.5);
    expect(b.count).toBe(96);
  });
});

describe('trace', () => {
  const mask = (rows: string[]) => {
    const h = rows.length;
    const w = rows[0].length;
    const m = new Uint8Array(w * h);
    // rows[0] is the top (highest y)
    rows.forEach((row, r) => [...row].forEach((c, x) => { if (c === '#') m[(h - 1 - r) * w + x] = 1; }));
    return { m, w, h };
  };
  it('a square is one clockwise ring starting at its lowest-left corner', () => {
    const { m, w, h } = mask(['....', '.##.', '.##.', '....']);
    expect(trace(m, w, h)).toEqual([{ outer: [[1, 1], [1, 3], [3, 3], [3, 1], [1, 1]], holes: [] }]);
  });
  it('a frame has one hole', () => {
    const { m, w, h } = mask(['###', '#.#', '###']);
    const polys = trace(m, w, h);
    expect(polys).toHaveLength(1);
    expect(polys[0].holes).toEqual([[[1, 1], [2, 1], [2, 2], [1, 2], [1, 1]]]);
  });
  it('corner-touching cells stay separate rings', () => {
    const { m, w, h } = mask(['.#', '#.']);
    const polys = trace(m, w, h);
    expect(polys).toHaveLength(2);
    expect(polys.every(p => p.outer.length === 5 && p.holes.length === 0)).toBe(true);
  });
});
