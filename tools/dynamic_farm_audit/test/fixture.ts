/**
 * Builds small synthetic snapshot + dataset directories on disk. Geometry is defined in UTM metres
 * and converted to lon/lat with proj4, so the audit's projection round-trips to the same metres.
 */
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import proj4 from 'proj4';

const fromUtm = proj4('+proj=utm +zone=10 +datum=WGS84 +units=m +no_defs', 'EPSG:4326');
const sha = (s: string) => createHash('sha256').update(s).digest('hex');
export type Pt = [number, number];

/** UTM origin of the fixture neighbourhood (inside zone 10N, San Francisco). */
export const BASE: Pt = [546500, 4176200];

export const rect = (x0: number, y0: number, x1: number, y1: number): Pt[] => [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]];
/** Rectangle rotated by `deg` (counter-clockwise) about its own corner (x0, y0). */
export function rotatedRect(x0: number, y0: number, w: number, h: number, deg: number): Pt[] {
  const t = (deg * Math.PI) / 180;
  const c = Math.cos(t);
  const s = Math.sin(t);
  return rect(0, 0, w, h).map(([x, y]) => [x0 + x * c - y * s, y0 + x * s + y * c]);
}

const lonLat = (rings: Pt[][]) => rings.map(ring => ring.map(([x, y]) => fromUtm.forward([BASE[0] + x, BASE[1] + y])));

export interface ParcelSpec { id: string; lots?: string[]; rings: Pt[][]; active?: number }
export interface BuildingSpec { area_id: number; rings: Pt[][] }
export interface FarmSpec {
  parcel: string;
  buildings: number[];
  /** Grid origin relative to BASE (m), rotation (deg), cell edge (m). */
  origin: Pt;
  rotation_deg?: number;
  cell_m: number;
  width: number;
  height: number;
  /** Core runs [y, x, length]. */
  runs: number[][];
  core_iou?: number;
  core_components?: number;
  source_area_m2?: number;
  too_small?: boolean;
  flags?: string[];
}

export interface FixtureSpec {
  parcels: ParcelSpec[];
  buildings: BuildingSpec[];
  farms: FarmSpec[];
  excluded?: { block_id: string; reason: string }[];
  /** Mutations applied after the dataset is written: extra files, dropped files, report edits. */
  mutate?: (ctx: { dataset: string; report: Record<string, any>; manifest: Record<string, any>; index: any[] }) => void;
}

export function writeFixture(spec: FixtureSpec): { snapshot: string; dataset: string } {
  const root = mkdtempSync(path.join(os.tmpdir(), 'dfa-'));
  const snapshot = path.join(root, 'snap');
  const dataset = path.join(root, 'ds');
  mkdirSync(path.join(snapshot, 'parcels'), { recursive: true });
  mkdirSync(path.join(snapshot, 'buildings'), { recursive: true });
  const parcelFeatures = spec.parcels.flatMap(p => (p.lots ?? [p.id]).map(lot => ({
    type: 'Feature',
    properties: { mapblklot: p.id, blklot: lot, active: p.active ?? 1 },
    geometry: { type: 'Polygon', coordinates: lonLat(p.rings) },
  })));
  const buildingFeatures = spec.buildings.map(b => ({
    type: 'Feature', properties: { area_id: b.area_id, mblr: null },
    geometry: { type: 'Polygon', coordinates: lonLat(b.rings) },
  }));
  const pBody = JSON.stringify({ type: 'FeatureCollection', features: parcelFeatures });
  const bBody = JSON.stringify({ type: 'FeatureCollection', features: buildingFeatures });
  writeFileSync(path.join(snapshot, 'parcels/p-0000.geojson'), pBody);
  writeFileSync(path.join(snapshot, 'buildings/b-0000.geojson'), bBody);
  const snapManifest = `${JSON.stringify({
    snapshot_schema: 1, fetched_at: 'fixture', bbox: null,
    sources: [
      { label: 'p', role: 'parcels', files: [{ file: 'parcels/p-0000.geojson', sha256: sha(pBody), count: parcelFeatures.length }] },
      { label: 'b', role: 'buildings', files: [{ file: 'buildings/b-0000.geojson', sha256: sha(bBody), count: buildingFeatures.length }] },
    ],
  }, null, 2)}\n`;
  writeFileSync(path.join(snapshot, 'source-manifest.json'), snapManifest);

  const files = new Map<string, string>();
  const reportRows: unknown[] = [];
  const index: any[] = [];
  const bFeatures: unknown[] = [];
  for (const f of spec.farms) {
    const blockId = `p-${f.parcel}`;
    const parcel = spec.parcels.find(p => p.id === f.parcel);
    const cells = f.runs.reduce((n, r) => n + r[2], 0);
    const flags = f.flags ?? [];
    const farm = {
      schema: 4, block_id: blockId, parcel_id: f.parcel, parcel_aliases: parcel?.lots ?? [f.parcel],
      source_cell_m: f.cell_m, source_area_m2: f.source_area_m2 ?? 0,
      source_transform: { crs: 'EPSG:32610', rotation_deg: f.rotation_deg ?? 0, origin_m: [BASE[0] + f.origin[0], BASE[1] + f.origin[1]] },
      grid: { width: f.width, height: f.height, origin_cell: [0, 0] },
      zones: { core: { runs: f.runs.map(r => [r[0], r[1], r[2], 0]) }, extension: { runs: [] } },
      counts: { core_cell_count: cells, extension_cell_count: 0, total_cell_count: cells },
      geo_hints: { source_building_count: f.buildings.length },
      stats: {
        core_iou: f.core_iou ?? 1, core_components: f.core_components ?? 1, building_source: 'b',
        too_small: f.too_small ?? false, recovery_flags: flags,
      },
    };
    files.set(`farms/${blockId}.json`, JSON.stringify(farm));
    reportRows.push({ block_id: blockId, core_iou: farm.stats.core_iou, too_small: farm.stats.too_small, flags, building_count: f.buildings.length });
    index.push({ type: 'Feature', id: blockId, properties: { block_id: blockId }, geometry: null });
    for (const id of f.buildings) {
      const b = spec.buildings.find(x => x.area_id === id)!;
      bFeatures.push({ type: 'Feature', properties: { block_id: blockId, area_id: id }, geometry: { type: 'Polygon', coordinates: lonLat(b.rings) } });
    }
  }
  const report: Record<string, any> = {
    totals: { parcels_in_snapshot: spec.parcels.filter(p => (p.active ?? 1) === 1).length, farms: spec.farms.length, excluded: (spec.excluded ?? []).length },
    parcels: reportRows, excluded: spec.excluded ?? [], rejected_records: [],
  };
  const manifest: Record<string, any> = { parcel_count: spec.farms.length, sources: { snapshot_manifest_sha256: sha(snapManifest) }, files: {} };
  const ctx = { dataset, report, manifest, index };
  const write = () => {
    files.set('index.geojson', JSON.stringify({ type: 'FeatureCollection', features: index }));
    files.set('buildings.geojson', JSON.stringify({ type: 'FeatureCollection', features: bFeatures }));
    files.set('reports/generation-report.json', JSON.stringify(report));
    manifest.files = {};
    for (const [name, body] of [...files].sort()) {
      manifest.files[name] = sha(body);
      mkdirSync(path.dirname(path.join(dataset, name)), { recursive: true });
      writeFileSync(path.join(dataset, name), body);
    }
    writeFileSync(path.join(dataset, 'manifest.json'), JSON.stringify(manifest));
  };
  write();
  if (spec.mutate) {
    spec.mutate(ctx);
    writeFileSync(path.join(dataset, 'reports/generation-report.json'), JSON.stringify(report));
    writeFileSync(path.join(dataset, 'index.geojson'), JSON.stringify({ type: 'FeatureCollection', features: index }));
    manifest.files['reports/generation-report.json'] = sha(JSON.stringify(report));
    manifest.files['index.geojson'] = sha(JSON.stringify({ type: 'FeatureCollection', features: index }));
    writeFileSync(path.join(dataset, 'manifest.json'), JSON.stringify(manifest));
  }
  return { snapshot, dataset };
}

/** One 5 x 5 m building at (1, 1)–(6, 6) m in a 10 x 10 m parcel; grid of 0.5 m cells at the parcel corner. */
export function squareSpec(over: Partial<FarmSpec> = {}, buildingOffset: Pt = [0, 0]): FixtureSpec {
  const [dx, dy] = buildingOffset;
  const runs: number[][] = [];
  for (let y = 2; y < 12; y++) runs.push([y, 2, 10]);
  return {
    parcels: [{ id: '1000001', rings: [rect(0, 0, 10, 10)] }],
    buildings: [{ area_id: 11, rings: [rect(1 + dx, 1 + dy, 6 + dx, 6 + dy)] }],
    farms: [{ parcel: '1000001', buildings: [11], origin: [0, 0], cell_m: 0.5, width: 20, height: 20, runs, source_area_m2: 25, ...over }],
  };
}
