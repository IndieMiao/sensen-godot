import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import * as osm from '../src/osm.js';
import * as topo from '../src/topology.js';
import * as geos from '../src/geos.js';

const FIX = path.join(__dirname, 'fixtures', 'grid_overpass.json');
const ways = () => osm.parseWays(JSON.parse(readFileSync(FIX, 'utf8')));

describe('topology', () => {
  beforeAll(geos.initGeos);
  it('projection: center is origin, east is +x (~95 m per 0.001°)', () => {
    const t = topo.makeTransformer(31.2, 121.4);
    const [x, y] = t.forward([121.4, 31.2]);
    expect(Math.abs(x)).toBeLessThan(1e-6); expect(Math.abs(y)).toBeLessThan(1e-6);
    const [x2] = t.forward([121.401, 31.2]);
    expect(x2).toBeGreaterThan(90); expect(x2).toBeLessThan(100);
    const [lng, lat] = t.inverse([95, 0]);
    expect(lng).toBeCloseTo(121.401, 5); expect(lat).toBeCloseTo(31.2, 6);
  });
  it('projectWays filters footway', () => {
    expect(topo.projectWays(ways(), 31.2, 121.4)).toHaveLength(4);
  });
  it('hash grid + window gives nine faces', () => {
    const lines = topo.clipLines(topo.projectWays(ways(), 31.2, 121.4), 150);
    const polys = topo.polygonizeBlocks(lines, 150);
    expect(polys).toHaveLength(9);
    const biggest = Math.max(...polys.map(geos.area));
    expect(biggest).toBeGreaterThan(190 * 190); expect(biggest).toBeLessThan(210 * 210);
  });
});
