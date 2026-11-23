import { spawnSync } from 'node:child_process';
import { readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { auditDataset, type AuditReport } from '../src/audit.js';
import { DEFAULT_AUDIT_PARAMS, resolveAuditParams } from '../src/config.js';
import { loadDataset, loadSnapshot, sha256 } from '../src/inputs.js';
import { rect, rotatedRect, squareSpec, writeFixture, type FixtureSpec } from './fixture.js';

function run(spec: FixtureSpec, params = DEFAULT_AUDIT_PARAMS): AuditReport {
  const { snapshot, dataset } = writeFixture(spec);
  return auditDataset(loadSnapshot(snapshot), loadDataset(dataset), sha256(readFileSync(path.join(dataset, 'manifest.json'))), params);
}

describe('IoU recomputed from source polygons and output cells', () => {
  it('is 1 when the core cells cover the footprint exactly', () => {
    const r = run(squareSpec());
    expect(r.status).toBe('pass');
    expect(r.farms[0].iou).toBeCloseTo(1, 6);
    expect(r.farms[0].source_area_m2).toBeCloseTo(25, 2);
    expect(r.farms[0]).toMatchObject({ source_components: 1, source_holes: 0, core_cells: 100, core_components: 1, core_holes: 0 });
  });

  it('matches the analytic value for a footprint shifted half a cell, ignoring the generator claim', () => {
    // Footprint [1.25, 6.25]², core [1, 6]²: intersection 4.75², union 50 - 4.75².
    const r = run(squareSpec({ core_iou: 0.99 }, [0.25, 0.25]));
    const expected = (4.75 * 4.75) / (50 - 4.75 * 4.75);
    expect(r.farms[0].iou).toBeCloseTo(expected, 5);
    expect(r.farms[0].reported_iou).toBe(0.99);
    expect(r.farms[0].iou_delta).toBeCloseTo(expected - 0.99, 5);
    expect(r.farms[0].issues).toEqual(expect.arrayContaining(['iou_below_exclusion', 'iou_differs_from_generator']));
    expect(r.farms[0].level).toBe('fail');
    expect(r.summary.below_exclusion.map(f => f.block_id)).toEqual(['p-1000001']);
    expect(r.status).toBe('fail');
  });

  it('uses the configured warning and exclusion lines', () => {
    const iou = (4.75 * 4.75) / (50 - 4.75 * 4.75); // ≈ 0.8223
    const r = run(squareSpec({ core_iou: 0.8223 }, [0.25, 0.25]), resolveAuditParams({ iou_warn: 0.85, iou_exclude: 0.8 }));
    expect(r.farms[0].iou).toBeCloseTo(iou, 5);
    expect(r.farms[0].issues).toEqual(['iou_below_warning']);
    expect(r.summary.below_warning.map(f => f.block_id)).toEqual(['p-1000001']);
    expect(r.status).toBe('warn');
  });

  it('follows the farm rotation', () => {
    // A 5 x 5 m building turned 30°; the grid is turned the same way with its origin at the
    // building corner minus one cell along both rotated axes.
    const t = (30 * Math.PI) / 180;
    const corner: [number, number] = [3, 1];
    const origin: [number, number] = [corner[0] - Math.cos(t) + Math.sin(t), corner[1] - Math.sin(t) - Math.cos(t)];
    const runs: number[][] = [];
    for (let y = 2; y < 12; y++) runs.push([y, 2, 10]);
    const r = run({
      parcels: [{ id: '1000001', rings: [rect(-5, -5, 15, 15)] }],
      buildings: [{ area_id: 11, rings: [rotatedRect(corner[0], corner[1], 5, 5, 30)] }],
      farms: [{ parcel: '1000001', buildings: [11], origin, rotation_deg: 30, cell_m: 0.5, width: 20, height: 20, runs, source_area_m2: 25 }],
    });
    expect(r.farms[0].iou).toBeCloseTo(1, 5);
  });

  it('unions several buildings and reports source vs core components and holes', () => {
    // Two 2 x 2 m buildings 1 m apart, but the core joins them into one block.
    const runs: number[][] = [];
    for (let y = 2; y < 6; y++) runs.push([y, 2, 10]);
    const r = run({
      parcels: [{ id: '1000001', rings: [rect(0, 0, 10, 10)] }],
      buildings: [{ area_id: 11, rings: [rect(1, 1, 3, 3)] }, { area_id: 12, rings: [rect(4, 1, 6, 3)] }],
      farms: [{ parcel: '1000001', buildings: [11, 12], origin: [0, 0], cell_m: 0.5, width: 20, height: 20, runs, source_area_m2: 8, core_iou: 0.8 }],
    });
    const f = r.farms[0];
    expect(f.source_area_m2).toBeCloseTo(8, 2);
    expect(f.iou).toBeCloseTo(8 / 10, 6);
    expect([f.source_components, f.core_components]).toEqual([2, 1]);
    expect(f.issues).toContain('component_count_differs');
    expect(r.summary.topology_differs).toEqual([{ block_id: 'p-1000001', source: [2, 0], core: [1, 0] }]);
  });

  it('lists a building that lies mostly in another parcel', () => {
    const runs: number[][] = [];
    for (let y = 2; y < 6; y++) runs.push([y, 14, 8]);
    const r = run({
      parcels: [{ id: '1000001', rings: [rect(0, 0, 10, 10)] }, { id: '1000002', rings: [rect(10, 0, 20, 10)] }],
      buildings: [{ area_id: 11, rings: [rect(7, 1, 11, 3)] }],
      farms: [{ parcel: '1000001', buildings: [11], origin: [0, 0], cell_m: 0.5, width: 40, height: 20, runs, source_area_m2: 8 }],
      excluded: [{ block_id: 'p-1000002', reason: 'no_building' }],
    });
    const b = r.farms[0].buildings[0];
    expect(b.share_in_parcel).toBeCloseTo(0.75, 4);
    expect(r.farms[0].issues).not.toContain('building_larger_share_in_other_parcel');
    const r2 = run({
      parcels: [{ id: '1000001', rings: [rect(0, 0, 10, 10)] }, { id: '1000002', rings: [rect(10, 0, 20, 10)] }],
      buildings: [{ area_id: 11, rings: [rect(9, 1, 13, 3)] }],
      farms: [{ parcel: '1000001', buildings: [11], origin: [0, 0], cell_m: 0.5, width: 40, height: 20, runs: [[2, 18, 8], [3, 18, 8], [4, 18, 8], [5, 18, 8]], source_area_m2: 8 }],
      excluded: [{ block_id: 'p-1000002', reason: 'no_building' }],
    });
    expect(r2.farms[0].buildings[0]).toMatchObject({ share_in_parcel: 0.25, best_other_parcel: '1000002', best_other_share: 0.75, share_outside_parcels: 0 });
    expect(r2.farms[0].issues).toEqual(expect.arrayContaining(['building_mostly_outside_parcel', 'building_larger_share_in_other_parcel']));
    expect(r2.summary.attribution_findings).toHaveLength(1);
  });

  it('fails a farm whose building is not in the snapshot', () => {
    const spec = squareSpec();
    const { snapshot, dataset } = writeFixture({
      ...spec,
      mutate: () => {},
    });
    // Point buildings.geojson at an area id the snapshot does not have.
    const bPath = path.join(dataset, 'buildings.geojson');
    const body = readFileSync(bPath, 'utf8').replace('"area_id":11', '"area_id":99');
    writeFileSync(bPath, body);
    const manifestPath = path.join(dataset, 'manifest.json');
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
    manifest.files['buildings.geojson'] = sha256(body);
    writeFileSync(manifestPath, JSON.stringify(manifest));
    const r = auditDataset(loadSnapshot(snapshot), loadDataset(dataset), 'x', DEFAULT_AUDIT_PARAMS);
    expect(r.farms[0].issues).toContain('building_missing_in_snapshot');
    expect(r.status).toBe('fail');
  });
});

describe('dataset formats', () => {
  it('reads building ids from the generation report and accepts the rounded map layer (C-55)', () => {
    const r = run({ ...squareSpec(), format: 'c55' });
    expect(r.status).toBe('pass');
    expect(r.farms[0]).toMatchObject({ building_ids_from: 'generation_report', building_area_ids: ['11'], issues: [] });
    expect(r.farms[0].iou).toBeCloseTo(1, 6);
    expect(r.farms[0].layer_iou!).toBeGreaterThan(0.95);
    expect(r.summary.building_layer.ids_from).toEqual({ generation_report: 1 });
  });

  it('takes the ids from buildings.geojson in the original layout and checks exact coordinates', () => {
    const r = run(squareSpec());
    expect(r.farms[0]).toMatchObject({ building_ids_from: 'buildings_layer', building_area_ids: ['11'] });
    expect(r.farms[0].layer_iou).toBeCloseTo(1, 6);
    const moved = run({ ...squareSpec(), layerRings: { 11: [rect(1, 1, 6, 6.05)] } });
    expect(moved.farms[0].issues).toEqual(['building_geometry_differs']);
  });

  it('computes IoU from the snapshot, not from the map layer', () => {
    // The layer shows the building 3 m away; the core still matches the snapshot footprint.
    const r = run({ ...squareSpec(), format: 'c55', layerRings: { 11: [rect(4, 1, 9, 6)] } });
    expect(r.farms[0].iou).toBeCloseTo(1, 6);
    expect(r.farms[0].layer_iou).toBeCloseTo(10 / 40, 2); // 6-decimal rounding moves it slightly
    expect(r.farms[0].issues).toEqual(['building_layer_differs']);
    expect(r.summary.building_layer.below_threshold.map(f => f.block_id)).toEqual(['p-1000001']);
  });

  it('lists report ids that disagree with the layer ids', () => {
    const r = run({ ...squareSpec(), mutate: ({ report }) => { report.parcels[0].building_area_ids = [12]; } });
    expect(r.farms[0].building_ids_from).toBe('generation_report');
    expect(r.farms[0].issues).toEqual(expect.arrayContaining(['building_ids_differ_report_vs_layer', 'building_missing_in_snapshot']));
    expect(r.status).toBe('fail');
  });

  it('does not treat the host-written tilejson.json as an unlisted file', () => {
    const { snapshot, dataset } = writeFixture({ ...squareSpec(), format: 'c55' });
    writeFileSync(path.join(dataset, 'tilejson.json'), '{}');
    const r = auditDataset(loadSnapshot(snapshot), loadDataset(dataset), 'x', DEFAULT_AUDIT_PARAMS);
    expect(r.reconciliation.consistent).toBe(true);
  });
});

describe('flags', () => {
  it('counts farms carrying both cell_scaled_for_total_cap and too_small separately', () => {
    const base = squareSpec();
    const farm = base.farms[0];
    const spec: FixtureSpec = {
      parcels: [...base.parcels, { id: '1000002', rings: [rect(20, 0, 30, 10)] }, { id: '1000003', rings: [rect(40, 0, 50, 10)] }],
      buildings: [...base.buildings, { area_id: 12, rings: [rect(21, 1, 26, 6)] }, { area_id: 13, rings: [rect(41, 1, 46, 6)] }],
      farms: [
        { ...farm, too_small: true, flags: ['cell_scaled_for_total_cap', 'too_small'] },
        { ...farm, parcel: '1000002', buildings: [12], origin: [20, 0], too_small: true, flags: ['too_small'] },
        { ...farm, parcel: '1000003', buildings: [13], origin: [40, 0], flags: ['cell_scaled_for_total_cap'] },
      ],
    };
    const r = run(spec);
    expect(r.summary.total_cap_and_too_small).toEqual({ count: 1, block_ids: ['p-1000001'] });
    expect(r.summary.too_small).toBe(2);
    expect(r.summary.cell_scaled_for_total_cap).toBe(2);
    expect(r.summary.flags).toEqual({ cell_scaled_for_total_cap: 2, too_small: 2 });
  });
});

describe('id reconciliation', () => {
  const twoParcels = (): FixtureSpec => ({
    ...squareSpec(),
    parcels: [...squareSpec().parcels, { id: '1000002', lots: ['1000002', '1000002A'], rings: [rect(20, 0, 30, 10)] }],
    excluded: [{ block_id: 'p-1000002', reason: 'no_building' }],
  });

  it('agrees for a consistent dataset and tallies exclusions and lots', () => {
    const r = run(twoParcels());
    expect(r.reconciliation.consistent).toBe(true);
    expect(r.reconciliation.counts).toMatchObject({
      input_valid: 2, generated: 1, excluded: 1, farm_files: 1, manifest_farm_files: 1, index_features: 1,
      input_lots: 3, generated_lots: 1, excluded_lots: 2,
    });
    expect(r.reconciliation.excluded_by_category).toEqual({ no_building: 1 });
  });

  it('reports a valid input parcel that is neither generated nor excluded', () => {
    const r = run({ ...twoParcels(), excluded: [], mutate: ({ report }) => { report.totals.excluded = 0; } });
    expect(r.reconciliation.discrepancies.map(d => d.check)).toContain('input_not_accounted (valid input parcel neither generated nor excluded)');
    expect(r.reconciliation.discrepancies[0].ids).toEqual(['p-1000002']);
    expect(r.status).toBe('fail');
  });

  it('reports a parcel listed as both generated and excluded, and categorises layout reasons', () => {
    const r = run({
      ...twoParcels(),
      excluded: [{ block_id: 'p-1000002', reason: 'layout: cannot connect walking areas' }, { block_id: 'p-1000001', reason: 'no_building' }],
      mutate: ({ report }) => { report.totals.excluded = 2; },
    });
    const checks = Object.fromEntries(r.reconciliation.discrepancies.map(d => [d.check, d.ids]));
    expect(checks.generated_and_excluded).toEqual(['p-1000001']);
    expect(checks.excluded_with_farm_file).toEqual(['p-1000001']);
    expect(r.reconciliation.excluded_by_category).toEqual({ layout: 1, no_building: 1 });
  });

  it('compares the reports with the farm files actually present and the manifest hashes', () => {
    const { snapshot, dataset } = writeFixture(twoParcels());
    writeFileSync(path.join(dataset, 'farms/p-9999999.json'), '{}');
    writeFileSync(path.join(dataset, 'index.geojson'), '{"type":"FeatureCollection","features":[]}');
    const r = auditDataset(loadSnapshot(snapshot), loadDataset(dataset), 'x', DEFAULT_AUDIT_PARAMS);
    const checks = Object.fromEntries(r.reconciliation.discrepancies.map(d => [d.check, d.ids]));
    expect(checks.farm_file_not_generated).toEqual(['p-9999999']);
    expect(checks.farm_file_not_in_manifest).toEqual(['p-9999999']);
    expect(checks.farm_file_not_in_index).toEqual(['p-1000001', 'p-9999999']);
    expect(checks.dataset_file_integrity).toEqual(['not in manifest: farms/p-9999999.json', 'sha256 mismatch: index.geojson']);
    expect(checks['count_mismatch totals.farms']).toEqual(['claimed 1, actual 2']);
    expect(r.farms.find(f => f.block_id === 'p-9999999')).toMatchObject({ level: 'fail' });
    expect(r.farms.find(f => f.block_id === 'p-9999999')!.issues[0]).toMatch(/^farm_unreadable: /);
  });

  it('reports a generated farm whose file is missing', () => {
    const { snapshot, dataset } = writeFixture(twoParcels());
    rmSync(path.join(dataset, 'farms/p-1000001.json'));
    const ds = loadDataset(dataset);
    const r = auditDataset(loadSnapshot(snapshot), ds, 'x', DEFAULT_AUDIT_PARAMS);
    const checks = Object.fromEntries(r.reconciliation.discrepancies.map(d => [d.check, d.ids]));
    expect(checks.generated_without_farm_file).toEqual(['p-1000001']);
    expect(checks.manifest_farm_without_file).toEqual(['p-1000001']);
    expect(checks.dataset_file_integrity).toEqual(['listed but missing: farms/p-1000001.json']);
  });

  it('detects a dataset built from a different snapshot', () => {
    const r = run({ ...squareSpec(), mutate: ({ manifest }) => { manifest.sources.snapshot_manifest_sha256 = 'f'.repeat(64); } });
    expect(r.reconciliation.discrepancies.map(d => d.check)).toContain('snapshot_manifest_sha256 (dataset was built from a different snapshot)');
  });

  it('counts an id once and keeps it valid when only some of its lots are inactive', () => {
    const { snapshot } = writeFixture({ ...squareSpec(), parcels: [...squareSpec().parcels, { id: '1000002', rings: [rect(20, 0, 30, 10)], active: 0, lots: ['1000002', '1000002A'] }] });
    const snap = loadSnapshot(snapshot);
    expect(snap.invalid_parcels).toEqual([{ id: '1000002', reason: 'inactive' }]);
    // Same parcel file with one active and one inactive lot under 1000001.
    const body = readFileSync(path.join(snapshot, 'parcels/p-0000.geojson'), 'utf8');
    const json = JSON.parse(body);
    json.features.push({ ...json.features[0], properties: { ...json.features[0].properties, blklot: '1000001B', active: 0 } });
    const text = JSON.stringify(json);
    writeFileSync(path.join(snapshot, 'parcels/p-0000.geojson'), text);
    const manifest = JSON.parse(readFileSync(path.join(snapshot, 'source-manifest.json'), 'utf8'));
    manifest.sources[0].files[0] = { ...manifest.sources[0].files[0], sha256: sha256(text), count: json.features.length };
    writeFileSync(path.join(snapshot, 'source-manifest.json'), JSON.stringify(manifest));
    const again = loadSnapshot(snapshot);
    expect(again.parcels.get('1000001')!.lots).toEqual(['1000001']);
    expect(again.invalid_parcels).toEqual([{ id: '1000002', reason: 'inactive' }]);
  });

  it('fails a farm file whose block_id differs from its file name', () => {
    const { snapshot, dataset } = writeFixture(squareSpec());
    const file = path.join(dataset, 'farms/p-1000001.json');
    writeFileSync(file, readFileSync(file, 'utf8').replace('"block_id":"p-1000001"', '"block_id":"p-1000009"'));
    const r = auditDataset(loadSnapshot(snapshot), loadDataset(dataset), 'x', DEFAULT_AUDIT_PARAMS);
    expect(r.farms[0]).toMatchObject({ block_id: 'p-1000001', level: 'fail', issues: ['farm_block_id_differs_from_file'] });
    expect(r.status).toBe('fail');
  });

  it('leaves inactive parcels out of the valid input set', () => {
    const r = run({ ...squareSpec(), parcels: [...squareSpec().parcels, { id: '1000002', rings: [rect(20, 0, 30, 10)], active: 0 }] });
    expect(r.reconciliation.consistent).toBe(true);
    expect(r.reconciliation.input_invalid_by_reason).toEqual({ inactive: 1 });
  });
});

describe('command line', () => {
  const tsx = path.join(import.meta.dirname, '..', 'node_modules', 'tsx', 'dist', 'cli.mjs');
  const cli = path.join(import.meta.dirname, '..', 'src', 'cli.ts');
  const exec = (args: string[]) => spawnSync(process.execPath, [tsx, cli, ...args], { encoding: 'utf8' }).status;

  it('exits 0 on pass, 1 on a failed audit and 2 when it cannot run', () => {
    const ok = writeFixture(squareSpec());
    const bad = writeFixture(squareSpec({ core_iou: 0.8 }, [0.25, 0.25]));
    const out = path.join(path.dirname(ok.dataset), 'out');
    expect(exec(['--snapshot', ok.snapshot, '--dataset', ok.dataset, '--out', out, '--quiet'])).toBe(0);
    expect(readFileSync(path.join(out, 'audit-summary.md'), 'utf8')).toMatch(/^# Dynamic farm audit: PASS/);
    expect(exec(['--snapshot', bad.snapshot, '--dataset', bad.dataset, '--out', out, '--quiet'])).toBe(1);
    const params = path.join(path.dirname(ok.dataset), 'p.json');
    writeFileSync(params, '{"iou_warn":2}');
    expect(exec(['--snapshot', ok.snapshot, '--dataset', ok.dataset, '--out', out, '--params', params, '--quiet'])).toBe(2);
    expect(exec(['--snapshot', ok.snapshot, '--dataset', path.join(out, 'missing'), '--out', out, '--quiet'])).toBe(2);
    expect(exec(['--snapshot', ok.snapshot])).toBe(2);
  });
});

describe('independence', () => {
  it('never imports generator code', () => {
    const dir = path.join(import.meta.dirname, '..', 'src');
    for (const file of readdirSync(dir)) {
      const text = readFileSync(path.join(dir, file), 'utf8');
      const imports = [...text.matchAll(/from\s+['"]([^'"]+)['"]/g)].map(m => m[1]);
      for (const spec of imports) {
        expect(spec, `${file} imports ${spec}`).not.toMatch(/dynamic_farm_gen|dynamic-farm-gen/);
        if (spec.startsWith('.')) expect(spec, `${file} imports ${spec}`).toMatch(/^\.\/[a-z]+\.js$/);
      }
    }
  });
});
