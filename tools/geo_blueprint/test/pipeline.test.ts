import { describe, it, expect, beforeAll } from 'vitest';
import { existsSync, mkdtempSync, readFileSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import * as osm from '../src/osm.js';
import * as topo from '../src/topology.js';
import * as pipeline from '../src/pipeline.js';
import * as writer from '../src/writer.js';
import * as geos from '../src/geos.js';

const FIX = path.join(__dirname, 'fixtures', 'grid_overpass.json');

describe('pipeline', () => {
  beforeAll(geos.initGeos);
  it('builds a valid, deterministic blueprint from the fixture', () => {
    const ways = osm.parseWays(JSON.parse(readFileSync(FIX, 'utf8')));
    const lines = topo.clipLines(topo.projectWays(ways, 31.2, 121.4), 150);
    const meta = { layout_patch_id: 'fix', revision: 1, region_id: 'shanghai', name: 'Fixture', source: {} };
    const t = topo.makeTransformer(31.2, 121.4);
    const { bp, overlay } = pipeline.buildFromLines(lines, 150, meta, t);
    const { bp: bp2 } = pipeline.buildFromLines(lines, 150, meta, t);
    expect(bp.report!.errors).toEqual([]);
    expect(writer.checksum(bp)).toBe(writer.checksum(bp2));
    expect(bp.blocks.length).toBeGreaterThanOrEqual(3); expect(bp.blocks.length).toBeLessThanOrEqual(7);
    expect(bp.grid).toEqual([64, 64]);
    expect(overlay.features).toHaveLength(bp.paths.length + bp.blocks.length);
    expect(bp.overlay_wgs84.center[0]).toBeCloseTo(31.2, 8);
    expect(bp.overlay_wgs84.center[1]).toBeCloseTo(121.4, 8);
  });
  it('synthetic safe blueprint is valid', () => {
    const { bp, overlay } = pipeline.syntheticSafe();
    expect(bp.layout_patch_id).toBe('safe_grid');
    expect(bp.report!.errors).toEqual([]);
    expect(overlay.features).toEqual([]);
  });
  it('buildAndWrite writes report', () => {
    const { bp, overlay } = pipeline.syntheticSafe();
    const out = pipeline.buildAndWrite(bp, overlay, mkdtempSync(path.join(os.tmpdir(), 'out-')));
    expect(existsSync(path.join(out, 'farm_blueprint.json'))).toBe(true);
    expect(existsSync(path.join(out, 'report.json'))).toBe(true);
  });
});
