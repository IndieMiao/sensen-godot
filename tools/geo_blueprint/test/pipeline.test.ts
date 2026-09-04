import { describe, it, expect, beforeAll } from 'vitest';
import { existsSync, mkdtempSync, readFileSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import type { LineString } from 'geojson';
import * as osm from '../src/osm.js';
import * as topo from '../src/topology.js';
import * as pipeline from '../src/pipeline.js';
import * as writer from '../src/writer.js';
import * as geos from '../src/geos.js';
import * as anchors from '../src/anchors.js';

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
  it('buildAndWrite validates even when bp.report is missing, and writes nothing on failure (regression #1)', () => {
    const { bp, overlay } = pipeline.syntheticSafe();
    delete bp.report; // simulate a caller-assembled Blueprint that never went through buildFromLines's validation
    const g = bp.grid[0];
    let nonWalkable: [number, number] | null = null;
    for (let j = 0; j < g && !nonWalkable; j++) {
      for (let i = 0; i < g && !nonWalkable; i++) if (bp.masks.walkable[j][i] === '0') nonWalkable = [i, j];
    }
    expect(nonWalkable).not.toBeNull(); // sanity: the synthetic grid must have at least one non-walkable cell
    bp.anchors.beds[0].cells[0] = nonWalkable!; // now genuinely invalid: this bed cell is unreachable
    const outRoot = mkdtempSync(path.join(os.tmpdir(), 'out-invalid-'));
    expect(() => pipeline.buildAndWrite(bp, overlay, outRoot)).toThrow(anchors.ValidationError);
    expect(existsSync(path.join(outRoot, bp.layout_patch_id))).toBe(false); // nothing was written
  });
  it('overlay path features stay 1:1 with bp.paths even when a short stub line is filtered out (regression #3)', () => {
    const ways = osm.parseWays(JSON.parse(readFileSync(FIX, 'utf8')));
    const projected = topo.projectWays(ways, 31.2, 121.4);
    const lines = topo.clipLines(projected, 150);
    const meta = { layout_patch_id: 'fix-stub', revision: 1, region_id: 'shanghai', name: 'Fixture Stub', source: {} };
    const t = topo.makeTransformer(31.2, 121.4);
    const base = pipeline.buildFromLines(lines, 150, meta, t);

    // 5m physical stub; half=150 -> play scale = PLAY_AREA_M/(2*150) = 64/300 -> ~1.07m in play space, below the 2.0m keep threshold.
    const stub: LineString = { type: 'LineString', coordinates: [[0, 0], [5, 0]] };
    const withStub = pipeline.buildFromLines([...lines, stub], 150, meta, t);

    expect(withStub.bp.paths.length).toBe(base.bp.paths.length); // stub did not survive into bp.paths
    const pathFeatures = (fc: typeof withStub.overlay) => fc.features.filter(f => f.properties?.kind === 'path').length;
    expect(pathFeatures(withStub.overlay)).toBe(pathFeatures(base.overlay)); // and it did not sneak into the overlay either
    expect(withStub.overlay.features).toHaveLength(withStub.bp.paths.length + withStub.bp.blocks.length); // invariant holds by construction
  });
});
