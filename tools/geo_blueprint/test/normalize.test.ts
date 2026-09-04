import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import type { Polygon, Point } from 'geojson';
import * as osm from '../src/osm.js';
import * as topo from '../src/topology.js';
import * as norm from '../src/normalize.js';
import * as geos from '../src/geos.js';

const FIX = path.join(__dirname, 'fixtures', 'grid_overpass.json');
function polys(): Polygon[] {
  const ways = osm.parseWays(JSON.parse(readFileSync(FIX, 'utf8')));
  return topo.polygonizeBlocks(topo.clipLines(topo.projectWays(ways, 31.2, 121.4), 150), 150);
}
const box = (x0: number, y0: number, x1: number, y1: number): Polygon =>
  ({ type: 'Polygon', coordinates: [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]] });

describe('normalize', () => {
  beforeAll(geos.initGeos);
  it('selectBlocks caps at seven, sorted desc', () => {
    const kept = norm.selectBlocks(polys(), 150);
    expect(kept.length).toBeGreaterThanOrEqual(3); expect(kept.length).toBeLessThanOrEqual(7);
    const areas = kept.map(geos.area);
    expect(areas).toEqual([...areas].sort((a, b) => b - a));
  });
  it('selectBlocks drops slivers', () => {
    const kept = norm.selectBlocks([...polys(), box(0, 0, 2, 2)], 150);
    expect(kept.every(p => geos.area(p) > 0.02 * 300 * 300)).toBe(true);
  });
  it('toPlay maps window corners to [0,64]²', () => {
    const p: Point = { type: 'Point', coordinates: [-150, -150] };
    expect(norm.toPlay(p, 150, 64).coordinates).toEqual([0, 0]);
    const q: Point = { type: 'Point', coordinates: [150, 0] };
    expect(norm.toPlay(q, 150, 64).coordinates).toEqual([64, 32]);
  });
  it('adjacency: center block touches at least four neighbours', () => {
    const play = norm.selectBlocks(polys(), 150).map(p => norm.toPlay(p, 150, 64));
    const { ids, neighbors } = norm.adjacency(play, 3.0);
    expect(ids[0]).toBe('b0');
    expect(neighbors['b0'].length).toBeGreaterThanOrEqual(4);
  });
});
