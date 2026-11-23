import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { beforeAll, describe, expect, it } from 'vitest';
import { validateDataset } from '../src/cli.js';
import { resolveParams } from '../src/config.js';
import { buildDataset, writeDataset, type BuildResult } from '../src/dataset.js';
import { loadSnapshot } from '../src/snapshot.js';
import { sha256 } from '../src/sources.js';
import { checkParcelProperties, decodeFarm, RELAXED } from '../src/validate.js';

// Test range around 130 SAN RAFAEL WAY / 175 JUNIPERO SERRA BLVD (see README.md).
const SNAPSHOT = path.join(import.meta.dirname, 'fixtures', 'sf-test-snapshot');
const VERSION = 'sf-dynamic-farm-20261123-r5';
let result: BuildResult;
const farm = (id: string) => JSON.parse(result.files.get(`farms/${id}.json`)!);

beforeAll(() => {
  result = buildDataset(loadSnapshot(SNAPSHOT), { dataset_version: VERSION, params: resolveParams() });
});

describe('sample build (test range)', () => {
  it('generates every parcel that has a footprint', () => {
    expect(result.reports.length).toBe(88);
    expect(result.excluded.every(e => e.reason === 'no_building')).toBe(true);
  });

  it('130 SAN RAFAEL WAY follows its L-shaped house and garage', () => {
    const f = farm('p-3250003');
    expect(f.name).toBe('130 SAN RAFAEL WAY');
    expect(f.counts.core_cell_count).toBe(717);
    expect(f.source_cell_m).toBe(0.5);
    expect(f.stats.core_iou).toBeGreaterThan(0.95);
    expect(f.stats.core_components).toBe(2);
    // Main house: an L, not its bounding rectangle.
    const house = f.boundaries.core.map((p: { outer: number[][] }) => p.outer).sort((a: number[][], b: number[][]) => b.length - a.length)[0];
    expect(house.length).toBeGreaterThan(5);
  });

  it('175 JUNIPERO SERRA BLVD keeps its courtyards and is capped', () => {
    const f = farm('p-3250006');
    expect(f.counts.core_cell_count).toBeLessThanOrEqual(4096);
    expect(f.counts.total_cell_count).toBeLessThanOrEqual(8192);
    expect(f.source_cell_m).toBeGreaterThan(0.5);
    expect(f.stats.recovery_flags).toContain('cell_scaled_for_core_cap');
    expect(f.source_cell_m).toBe(0.6901);
    expect(f.source_area_m2).toBe(1874.7);
    expect(f.boundaries.core[0].holes.length).toBeGreaterThanOrEqual(2);
    expect(f.stats.core_iou).toBeGreaterThan(0.95);
  });

  it('larger footprints get more cells at the fixed cell size', () => {
    const fixed = result.reports.filter(r => r.cell_m === 0.5).sort((a, b) => a.building_area_m2 - b.building_area_m2);
    for (const r of fixed) expect(r.core_cell_count / (r.building_area_m2 / 0.25)).toBeGreaterThan(0.9);
    for (const r of fixed) expect(r.core_cell_count / (r.building_area_m2 / 0.25)).toBeLessThan(1.1);
    expect(fixed[0].core_cell_count).toBeLessThan(fixed[fixed.length - 1].core_cell_count);
  });

  it('every farm and index feature passes the client checks (with the C-43 count rule)', () => {
    const index = JSON.parse(result.files.get('index.geojson')!);
    expect(index.features.length).toBe(88);
    for (const feature of index.features) {
      expect(checkParcelProperties(feature.properties, RELAXED)).toBeNull();
      const decoded = decodeFarm(farm(feature.properties.block_id), RELAXED);
      expect(decoded.ok, feature.properties.block_id).toBe(true);
    }
  });

  it('manifests pin every file', () => {
    const manifest = JSON.parse(result.files.get('manifest.json')!);
    for (const [file, hash] of Object.entries(manifest.files)) expect(sha256(result.files.get(file)!)).toBe(hash);
    const client = JSON.parse(result.files.get('client-manifest.json')!);
    expect(client.source_manifest_sha256).toBe(sha256(result.files.get('manifest.json')!));
    expect(client.native_map).toMatchObject({ type: 'geojson', promote_id: 'block_id', building_source: 'datasf', buildings_url_path: 'buildings.geojson' });
  });

  it('is byte-for-byte reproducible', () => {
    const again = buildDataset(loadSnapshot(SNAPSHOT), { dataset_version: VERSION, params: resolveParams() });
    expect([...again.files.keys()]).toEqual([...result.files.keys()]);
    for (const [name, body] of again.files) expect(body === result.files.get(name), name).toBe(true);
    // Golden: any change to the generator's output for this snapshot must update this pin on purpose.
    expect(sha256(result.files.get('manifest.json')!)).toBe(GOLDEN_MANIFEST_SHA256);
  });

  it('never calls the engine\'s libm on the build path (its last bit differs between platforms)', () => {
    const names = ['sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'atan2', 'exp', 'expm1', 'log', 'log1p', 'log2', 'log10',
      'sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh', 'hypot', 'pow', 'cbrt'] as const;
    const saved = names.map(n => Math[n]);
    try {
      for (const n of names) (Math as unknown as Record<string, unknown>)[n] = () => { throw new Error(`Math.${n} called`); };
      const again = buildDataset(loadSnapshot(SNAPSHOT), { dataset_version: VERSION, params: resolveParams() });
      expect(again.files.get('manifest.json')).toBe(result.files.get('manifest.json'));
    } finally {
      names.forEach((n, i) => { (Math as unknown as Record<string, unknown>)[n] = saved[i]; });
    }
  });

  it('writes to disk and validates from disk; refuses to replace unrelated folders', () => {
    const tmp = mkdtempSync(path.join(os.tmpdir(), 'farm-gen-'));
    const out = path.join(tmp, 'r5');
    writeDataset(out, result);
    expect(validateDataset(out, RELAXED, () => {})).toBe(0);
    writeDataset(out, result); // an earlier dataset may be replaced
    const other = path.join(tmp, 'other');
    mkdirSync(other);
    writeFileSync(path.join(other, 'keep.txt'), 'x');
    expect(() => writeDataset(other, result)).toThrow(/refusing/);
    expect(readFileSync(path.join(other, 'keep.txt'), 'utf8')).toBe('x');
  });

  it('detects a changed snapshot file', () => {
    const tmp = mkdtempSync(path.join(os.tmpdir(), 'farm-snap-'));
    const copy = path.join(tmp, 'snap');
    mkdirSync(path.join(copy, 'parcels'), { recursive: true });
    mkdirSync(path.join(copy, 'buildings'), { recursive: true });
    for (const f of ['source-manifest.json', 'parcels/sfgis-parcels-0000.geojson', 'buildings/sfgis-buildings-0000.geojson', 'buildings/sfenv-buildings-0000.geojson']) {
      writeFileSync(path.join(copy, f), readFileSync(path.join(SNAPSHOT, f)));
    }
    writeFileSync(path.join(copy, 'buildings/sfgis-buildings-0000.geojson'), '{"features":[]}');
    expect(() => loadSnapshot(copy)).toThrow(/changed/);
  });
});

const GOLDEN_MANIFEST_SHA256 = 'fe8d03428ebb60e9b5f39d129c3ef24b39fe174483556cae7f7ad3b024f8ff05';
