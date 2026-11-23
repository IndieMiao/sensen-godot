import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { beforeAll, describe, expect, it } from 'vitest';
import { main, validateDataset } from '../src/cli.js';
import { resolveParams } from '../src/config.js';
import { buildDataset, writeDataset, type BuildResult } from '../src/dataset.js';
import { encodeTiles, resolveMapParams, type TileFeature } from '../src/mvt.js';
import { loadSnapshot } from '../src/snapshot.js';
import { sha256 } from '../src/sources.js';
import { checkTiles } from '../src/tilecheck.js';
import { checkParcelProperties, decodeFarm, RELAXED } from '../src/validate.js';

// Test range around 130 SAN RAFAEL WAY / 175 JUNIPERO SERRA BLVD (see README.md).
const SNAPSHOT = path.join(import.meta.dirname, 'fixtures', 'sf-test-snapshot');
const VERSION = 'sf-dynamic-farm-20261123-r5';
let result: BuildResult;
const text = (name: string) => result.files.get(name) as string;
const farm = (id: string) => JSON.parse(text(`farms/${id}.json`));

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
    const index = JSON.parse(text('index.geojson'));
    expect(index.features.length).toBe(88);
    for (const feature of index.features) {
      expect(checkParcelProperties(feature.properties, RELAXED)).toBeNull();
      const decoded = decodeFarm(farm(feature.properties.block_id), RELAXED);
      expect(decoded.ok, feature.properties.block_id).toBe(true);
    }
  });

  it('manifests pin every file', () => {
    const manifest = JSON.parse(text('manifest.json'));
    for (const [file, hash] of Object.entries(manifest.files)) expect(sha256(result.files.get(file)!)).toBe(hash);
    const client = JSON.parse(text('client-manifest.json'));
    expect(client.source_manifest_sha256).toBe(sha256(result.files.get('manifest.json')!));
    // r4 map-layer format (geo_map_config.gd): parcels from vector tiles, DataSF buildings as GeoJSON.
    expect(client.native_map).toMatchObject({
      type: 'vector', parcel_url_path: 'tilejson.json', parcel_source_layer: 'parcels', promote_id: 'block_id',
      source_minzoom: 15, source_maxzoom: 18, building_source: 'datasf', buildings_url_path: 'buildings.geojson',
    });
    expect(manifest.map_layer.tile_encoder).toBe('dynamic-farm-gen mvt-encoder-1');
  });

  it('is byte-for-byte reproducible', () => {
    const again = buildDataset(loadSnapshot(SNAPSHOT), { dataset_version: VERSION, params: resolveParams() });
    expect([...again.files.keys()]).toEqual([...result.files.keys()]);
    for (const [name, body] of again.files) expect(Buffer.from(body).equals(Buffer.from(result.files.get(name)!)), name).toBe(true);
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

describe('parcel tiles and building layer (test range)', () => {
  const written = () => {
    const dir = path.join(mkdtempSync(path.join(os.tmpdir(), 'farm-tiles-')), 'r5');
    writeDataset(dir, result);
    return dir;
  };
  const manifestOf = (dir: string) => JSON.parse(readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
  /** Rewrites one tile file and its manifest hash, as a broken generator would. */
  const replaceTile = (dir: string, name: string, bytes: Uint8Array | null) => {
    const manifest = manifestOf(dir);
    if (bytes) { writeFileSync(path.join(dir, name), bytes); manifest.files[name] = sha256(bytes); }
    else { delete manifest.files[name]; rmSync(path.join(dir, name)); }
    writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify(manifest));
  };
  const indexFeatures = (): TileFeature[] => JSON.parse(text('index.geojson')).features.map((f: any) => ({
    id: f.properties.block_id, properties: f.properties,
    polygons: f.geometry.type === 'Polygon' ? [f.geometry.coordinates] : f.geometry.coordinates,
  }));

  it('covers every parcel at every zoom 15–18 and matches the index', () => {
    const { report, properties } = checkTiles(written());
    expect(report.errors).toEqual([]);
    expect(report.ok).toBe(true);
    expect(Object.keys(report.zooms)).toEqual(['15', '16', '17', '18']);
    for (const z of Object.values(report.zooms)) {
      expect(z.unique_parcels).toBe(88);
      expect(z.missing_ids).toEqual([]);
    }
    expect(properties.size).toBe(88);
    const index = JSON.parse(text('index.geojson'));
    for (const f of index.features) expect(properties.get(f.properties.block_id)).toEqual(f.properties);
  });

  it('flags a tile whose parcel name differs from the dataset', () => {
    const dir = written();
    const features = indexFeatures().map(f => (f.id === 'p-3250003' ? { ...f, properties: { ...f.properties, name: '999 WRONG WAY' } } : f));
    const tiles = encodeTiles(features, resolveMapParams());
    const name = [...tiles.keys()].find(k => k.startsWith('tiles/18/') && Buffer.from(tiles.get(k)!).includes('999 WRONG WAY'))!;
    replaceTile(dir, name, tiles.get(name)!);
    const { report } = checkTiles(dir);
    expect(report.ok).toBe(false);
    expect(report.errors.join('\n')).toMatch(/p-3250003 name="999 WRONG WAY", index has "130 SAN RAFAEL WAY"/);
  });

  it('fails when a parcel is missing at the maximum zoom, and lists it per zoom', () => {
    const dir = written();
    const features = indexFeatures().filter(f => f.id !== 'p-3250003');
    const tiles = encodeTiles(features, resolveMapParams());
    for (const name of Object.keys(manifestOf(dir).files).filter(k => k.startsWith('tiles/18/'))) {
      replaceTile(dir, name, tiles.get(name) ?? null);
    }
    const { report } = checkTiles(dir);
    expect(report.ok).toBe(false);
    expect(report.zooms['18'].missing_ids).toEqual(['p-3250003']);
    expect(report.zooms['17'].missing_count).toBe(0);
    expect(report.errors.join('\n')).toMatch(/1 parcels missing at the maximum zoom/);
  });

  it('rejects tiles that are not pinned or were changed after the build', () => {
    const dir = written();
    const first = Object.keys(manifestOf(dir).files).find(k => k.startsWith('tiles/18/'))!;
    mkdirSync(path.join(dir, 'tiles/18/1'), { recursive: true });
    writeFileSync(path.join(dir, 'tiles/18/1/1.pbf'), readFileSync(path.join(dir, first)));
    writeFileSync(path.join(dir, first), Buffer.concat([readFileSync(path.join(dir, first)), Buffer.from([0])]));
    const errors = checkTiles(dir).report.errors.join('\n');
    expect(errors).toMatch(/tiles\/18\/1\/1\.pbf: not in manifest/);
    expect(errors).toMatch(/hash differs/);
    expect(validateDataset(dir, RELAXED, () => {})).toBeGreaterThan(0);
  });

  /** The written sample without its map layer, as a dataset from before r5's parcel tiles (C-49 r5, r4) looks. */
  const withoutMapLayer = (dropTiles: boolean) => {
    const dir = written();
    const manifest = manifestOf(dir);
    delete manifest.map_layer;
    if (dropTiles) {
      for (const name of Object.keys(manifest.files).filter(k => k.startsWith('tiles/') || k === 'tilejson.template.json')) delete manifest.files[name];
      rmSync(path.join(dir, 'tiles'), { recursive: true });
      rmSync(path.join(dir, 'tilejson.template.json'));
    }
    const text = JSON.stringify(manifest);
    writeFileSync(path.join(dir, 'manifest.json'), text);
    const client = JSON.parse(readFileSync(path.join(dir, 'client-manifest.json'), 'utf8'));
    writeFileSync(path.join(dir, 'client-manifest.json'), JSON.stringify({ ...client, source_manifest_sha256: sha256(text) }));
    return dir;
  };

  it('validates a dataset from before the map layer, skipping and reporting the tile check', () => {
    const lines: string[] = [];
    expect(validateDataset(withoutMapLayer(true), RELAXED, l => lines.push(l))).toBe(0);
    expect(lines).toContain('tiles skipped: manifest.json has no map_layer (dataset predates the parcel map layer)');
    expect(lines.at(-1)).toBe('88 farms checked, 0 failures');
  });

  it('fails without throwing when tiles are present but map_layer is missing, or client-manifest.json is absent', () => {
    const lines: string[] = [];
    expect(validateDataset(withoutMapLayer(false), RELAXED, l => lines.push(l))).toBe(1);
    expect(lines).toContain('TILE manifest.json has parcel tiles but no map_layer');
    const dir = withoutMapLayer(true);
    rmSync(path.join(dir, 'client-manifest.json'));
    lines.length = 0;
    expect(validateDataset(dir, RELAXED, l => lines.push(l))).toBe(1);
    expect(lines).toContain('MISSING client-manifest.json');
  });

  it('writes tilejson.json for a host base URL and checks it', async () => {
    const dir = written();
    expect(await main(['tilejson', '--dataset', dir, '--base', 'https://oss.example/sensen/r5-abc'])).toBe(0);
    const t = JSON.parse(readFileSync(path.join(dir, 'tilejson.json'), 'utf8'));
    expect(t.tiles).toEqual(['https://oss.example/sensen/r5-abc/tiles/{z}/{x}/{y}.pbf']);
    expect(t.vector_layers[0]).toMatchObject({ id: 'parcels', minzoom: 15, maxzoom: 18 });
    expect(checkTiles(dir).report).toMatchObject({ ok: true, tilejson: 'deployed: https://oss.example/sensen/r5-abc' });
    for (const base of ['http://oss.example/r5', 'https://oss.example/r5/', 'https://u:p@oss.example/r5', 'https://oss.example/r5?x=1']) {
      await expect(main(['tilejson', '--dataset', dir, '--base', base])).rejects.toThrow(/https URL/);
    }
    writeFileSync(path.join(dir, 'tilejson.json'), JSON.stringify({ ...t, maxzoom: 20 }));
    expect(checkTiles(dir).report.errors).toContain('tilejson.json: not the template with an https base URL');
  });

  it('keeps one light building feature per used footprint, traceable through the report', () => {
    const buildings = JSON.parse(text('buildings.geojson'));
    const report = JSON.parse(text('reports/generation-report.json'));
    const used = report.parcels.reduce((n: number, r: { building_area_ids: number[] }) => n + r.building_area_ids.length, 0);
    expect(buildings.features.length).toBe(used);
    for (const f of buildings.features) {
      expect(Object.keys(f.properties)).toEqual(['block_id']);
      const coords = (f.geometry.type === 'Polygon' ? [f.geometry.coordinates] : f.geometry.coordinates).flat(2);
      for (const [x, y] of coords) expect([Math.round(x * 1e6) / 1e6, Math.round(y * 1e6) / 1e6]).toEqual([x, y]);
    }
    for (const r of report.parcels) expect(r.building_area_ids.length).toBe(r.building_count);
    // C-49 wrote 77,147 bytes for the same 123 footprints.
    expect(text('buildings.geojson').length).toBeLessThan(77147 * 0.7);
  });
});

// C-55: + parcel tiles, tilejson template, map_layer, lighter buildings.geojson, building_area_ids in
// the report; farms and index.geojson unchanged from C-49's fe8d03428ebb60e9b5f39d129c3ef24b39fe174483556cae7f7ad3b024f8ff05.
const GOLDEN_MANIFEST_SHA256 = '654b2cfa15f7a80e6310aeb5151ddc9530bb42c2049056916d49846c3137d8ce';
