import { describe, expect, it } from 'vitest';
import { dominantAngle, insideRings, polygonArea, rotate, toUtm, unrotate, type Polygon } from '../src/geo.js';

describe('toUtm (EPSG:32610)', () => {
  // Reference values from proj4 2.22 "+proj=utm +zone=10 +datum=WGS84".
  const cases: [number, number, number, number][] = [
    [-122.4194, 37.7749, 551130.7685, 4180998.8815],
    [-122.470873757, 37.732717506, 546624.1411, 4176291.9],
    [-123, 37.5, 500000, 4150341.3418],
    [-121.5, 38.2, 631341.0882, 4229069.1501],
  ];
  it.each(cases)('%f, %f', (lon, lat, e, n) => {
    const [x, y] = toUtm(lon, lat);
    expect(x).toBeCloseTo(e, 3);
    expect(y).toBeCloseTo(n, 3);
  });
});

describe('planar helpers', () => {
  const square: Polygon = [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]], [[2, 2], [4, 2], [4, 4], [2, 4], [2, 2]]];
  it('subtracts holes from the area and the inside test', () => {
    expect(polygonArea(square)).toBe(96);
    expect(insideRings(square, 1, 1)).toBe(true);
    expect(insideRings(square, 3, 3)).toBe(false);
    expect(insideRings(square, 11, 1)).toBe(false);
  });
  it('rotate and unrotate are inverses', () => {
    const [x, y] = unrotate(rotate([3, -7], 27.5), 27.5);
    expect(x).toBeCloseTo(3, 12);
    expect(y).toBeCloseTo(-7, 12);
  });
  it('finds the wall direction folded into (-45, 45]', () => {
    const at = (deg: number): Polygon => [[[0, 0], [20, 0], [20, 8], [8, 8], [8, 14], [0, 14], [0, 0]].map(p => unrotate(p as [number, number], deg))];
    expect(dominantAngle([at(0)])).toBeCloseTo(0, 1);
    expect(dominantAngle([at(30)])).toBeCloseTo(30, 1);
    expect(dominantAngle([at(-12.4)])).toBeCloseTo(-12.4, 1);
    expect(dominantAngle([at(70)])).toBeCloseTo(-20, 1);
  });
});
