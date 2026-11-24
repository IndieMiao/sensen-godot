import { describe, expect, it } from 'vitest';
import { trace } from '../src/boundaries.js';
import { unrotate, type Polygon } from '../src/geo.js';
import { bestCore, exactCoverage, maskIou, rasterize, threshold } from '../src/raster.js';

const rect = (x: number, y: number, w: number, h: number): Polygon => [[[x, y], [x + w, y], [x + w, y + h], [x, y + h], [x, y]]];

describe('rasterize', () => {
  it('an aligned 10 m × 6 m footprint at 0.5 m is exactly 240 cells', () => {
    const core = threshold(rasterize([rect(100, 200, 10, 6)], 0, 0.5, 4), 0.5);
    expect(core.count).toBe(240);
    expect(core.iou).toBeCloseTo(1, 6);
  });
  it('cell count follows the real area: 0.25 m² per cell', () => {
    for (const [w, h] of [[8, 12], [15, 20], [31, 17]]) {
      const core = bestCore([rect(0, 0, w, h)], 0, 0.5, 0.5);
      expect(core.count).toBe((w * h) / 0.25);
    }
  });
  it('a rotated footprint snaps back when the grid uses its angle', () => {
    const poly: Polygon = [rect(0, 0, 12, 7)[0].map(p => unrotate(p as [number, number], 33))];
    const aligned = bestCore([poly], 33, 0.5, 0.5);
    const unaligned = bestCore([poly], 0, 0.5, 0.5);
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

describe('exactCoverage', () => {
  const sum = (a: Float64Array) => a.reduce((t, v) => t + v, 0);
  it('gives each cell its exact covered fraction', () => {
    // 1.3 m × 0.7 m at 0.5 m cells, from (0.1, 0.2): columns hold 0.8, 1, 0.8 of a cell width,
    // rows 0.6 and 0.8 of a cell height (the frame starts one margin cell lower-left).
    const c = exactCoverage([rect(0.1, 0.2, 1.3, 0.7)], 0, 0.5);
    const at = (x: number, y: number) => c.cov[(y + 1) * c.frame.width + x + 1];
    expect(at(0, 0)).toBeCloseTo(0.8 * 0.6, 12);
    expect(at(1, 0)).toBeCloseTo(0.6, 12);
    expect(at(2, 0)).toBeCloseTo(0.8 * 0.6, 12);
    expect(at(1, 1)).toBeCloseTo(0.8, 12);
    expect(sum(c.cov) * 0.25).toBeCloseTo(1.3 * 0.7, 12);
  });
  it('matches the footprint area for rotated shapes, holes in either winding and triangles', () => {
    const tri: Polygon = [[[0, 0], [7.3, 0.4], [2.2, 5.9], [0, 0]]];
    const courtyard: Polygon = [rect(0, 0, 12, 12)[0], rect(4, 4, 4, 4)[0]];
    const reversedHole: Polygon = [rect(0, 0, 12, 12)[0], [...rect(4, 4, 4, 4)[0]].reverse()];
    for (const [poly, area] of [[tri, (7.3 * 5.9 - 0.4 * 2.2) / 2], [courtyard, 128], [reversedHole, 128]] as const) {
      for (const rot of [0, 17, -38]) {
        const c = exactCoverage([poly as Polygon], rot, 0.5, [0.25, 0.75]);
        expect(sum(c.cov) * 0.25).toBeCloseTo(area as number, 9);
      }
    }
  });
  it('clamps overlapping footprints to a full cell', () => {
    const c = exactCoverage([rect(0, 0, 4, 4), rect(2, 0, 4, 4)], 0, 0.5);
    expect(Math.max(...c.cov)).toBe(1);
    expect(sum(c.cov) * 0.25).toBeCloseTo(24, 9);
  });
  it('the IoU of a mask is exact: half-covered cells count against it', () => {
    // 1 × 0.75 m at 0.5 m: two full cells and two half cells; all four core gives 0.75 / 1.
    const c = exactCoverage([rect(0, 0, 1, 0.75)], 0, 0.5);
    const core = threshold(c, 0.5);
    expect(core.count).toBe(4);
    expect(core.iou).toBeCloseTo(0.75, 12);
    expect(maskIou(c.cov, new Uint8Array(c.cov.length))).toBe(0);
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
