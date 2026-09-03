import { describe, it, expect } from 'vitest';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import * as osm from '../src/osm.js';

const FIX = path.join(__dirname, 'fixtures', 'grid_overpass.json');

describe('osm', () => {
  it('bbox is symmetric in lat and wider in lng', () => {
    const [s, w, n, e] = osm.bbox(31.2, 121.4, 200);
    expect(Math.abs((n - 31.2) - (31.2 - s))).toBeLessThan(1e-9);
    expect(e - w).toBeGreaterThan(n - s);
  });
  it('query mentions highway regex and out body', () => {
    const q = osm.buildQuery(31.2, 121.4, 200);
    expect(q).toContain('way["highway"~');
    expect(q).toContain('residential');
    expect(q).toContain('out body');
  });
  it('parses five ways from fixture', () => {
    const ways = osm.parseWays(JSON.parse(readFileSync(FIX, 'utf8')));
    expect(ways).toHaveLength(5);
    const w = ways.find(x => x.id === 101)!;
    expect(w.highway).toBe('residential');
    expect(w.coords[0]).toEqual([31.2009, 121.3982]);
  });
  it('fetchOverpass returns cache without network', async () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'osm-'));
    const cache = path.join(dir, 'c.json');
    writeFileSync(cache, readFileSync(FIX));
    const data = await osm.fetchOverpass(31.2, 121.4, 150, cache);
    expect(data.elements).toHaveLength(13);
  });
});
