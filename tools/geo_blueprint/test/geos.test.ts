import { describe, it, expect, beforeAll } from 'vitest';
import type { LineString } from 'geojson';
import * as geos from '../src/geos.js';

const line = (c: number[][]): LineString => ({ type: 'LineString', coordinates: c });

describe('geos wrapper', () => {
  beforeAll(geos.initGeos);
  it('unaryUnion + polygonize cuts a hash grid inside a window into 9 faces', () => {
    const H = 150;
    const noded = geos.unaryUnion([
      line([[-160, 100], [160, 100]]), line([[-160, -100], [160, -100]]),
      line([[-105, 160], [-105, -160]]), line([[105, 160], [105, -160]]),
      line([[-H, -H], [H, -H], [H, H], [-H, H], [-H, -H]]),
    ]);
    const polys = geos.polygonize(noded);
    expect(polys).toHaveLength(9);
    expect(Math.round(Math.max(...polys.map(geos.area)))).toBe(42000);
  });
  it('buffer + preparedContains', () => {
    const corridor = geos.buffer(line([[0, 32.5], [64, 32.5]]), 1.5);
    const pc = geos.preparedContains(corridor);
    expect(pc.contains([20.5, 32.5])).toBe(true);
    expect(pc.contains([20.5, 34.5])).toBe(false);
    pc.dispose();
  });
  it('intersection of disjoint shapes is empty; simplify keeps polygon', () => {
    const box = { type: 'Polygon' as const, coordinates: [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]] };
    expect(geos.isEmpty(geos.intersection(line([[0, 32.5], [64, 32.5]]), box))).toBe(true);
    const s = geos.simplify(geos.buffer(box, -1), 1.5);
    expect(s.type).toBe('Polygon');
    expect(Math.round(geos.area(s))).toBe(64);
  });
});
