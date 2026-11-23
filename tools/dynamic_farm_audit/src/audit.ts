/**
 * Source-geometry audit: for every farm, the IoU between the union of its DataSF building
 * footprints (taken from the snapshot, not from the dataset) and its core cells is recomputed
 * exactly, together with source / core component and hole counts. The generator's own numbers
 * are only read to be compared, never used in a computation.
 */
import type { AuditParams } from './config.js';
import {
  gridTransform, intersectionArea, lonLatToUtm, mapPolygons, maskTopology, multiArea,
  runsIntersectionArea, topology, unionAll, type Pair, type Polygon,
} from './geometry.js';
import { buildingKey, type Dataset, type Farm, type SourceSnapshot } from './inputs.js';
import { reconcile, type Reconciliation } from './reconcile.js';

export const AUDIT_VERSION = 'dynamic-farm-audit-1';

export type Level = 'ok' | 'warn' | 'fail';

export interface FarmAudit {
  block_id: string;
  level: Level;
  issues: string[];
  building_source: string;
  building_area_ids: string[];
  cell_m: number;
  rotation_deg: number;
  /** Area of the union of the source footprints (m²). */
  source_area_m2: number;
  /** The farm's own source_area_m2. */
  reported_source_area_m2: number;
  source_components: number;
  source_holes: number;
  core_cells: number;
  core_components: number;
  core_holes: number;
  reported_core_components: number;
  /** Audited IoU, exact polygon areas. */
  iou: number;
  /** stats.core_iou in the farm file. */
  reported_iou: number;
  /** core_iou in reports/generation-report.json (null when the report has no row). */
  report_iou: number | null;
  /** iou - reported_iou. */
  iou_delta: number;
  /** Where each footprint lies relative to the snapshot's parcels. */
  buildings: BuildingAttribution[];
  too_small: boolean;
  flags: string[];
}

export interface BuildingAttribution {
  area_id: string;
  area_m2: number;
  /** Share of the footprint's area inside the farm's own parcel. */
  share_in_parcel: number;
  /** The other snapshot parcel holding the largest share of the footprint, if any. */
  best_other_parcel: string | null;
  best_other_share: number;
  /** Share inside no snapshot parcel (street, or a parcel outside a bbox snapshot). */
  share_outside_parcels: number;
}

/** Snapshot parcels in UTM with a 100 m bucket index, projected once. */
export class ParcelLookup {
  private utm = new Map<string, Polygon[]>();
  private buckets = new Map<string, string[]>();
  private bounds = new Map<string, [number, number, number, number]>();
  constructor(snapshot: SourceSnapshot, private size = 100) {
    for (const [id, parcel] of snapshot.parcels) {
      const polys = mapPolygons(parcel.polygons, ([lon, lat]) => lonLatToUtm(lon, lat));
      const b = bbox(polys);
      this.utm.set(id, polys);
      this.bounds.set(id, b);
      for (const k of this.keys(b)) {
        if (!this.buckets.has(k)) this.buckets.set(k, []);
        this.buckets.get(k)!.push(id);
      }
    }
  }
  private *keys([x0, y0, x1, y1]: [number, number, number, number]) {
    for (let x = Math.floor(x0 / this.size); x <= Math.floor(x1 / this.size); x++) {
      for (let y = Math.floor(y0 / this.size); y <= Math.floor(y1 / this.size); y++) yield `${x},${y}`;
    }
  }
  /** Shares of one footprint (lon/lat) in its own parcel and in every other overlapping parcel. */
  shares(footprintLonLat: Polygon[], ownId: string, areaId: string, toGrid: (p: Pair) => Pair, cellArea: number): BuildingAttribution {
    const utm = mapPolygons(footprintLonLat, ([lon, lat]) => lonLatToUtm(lon, lat));
    const b = bbox(utm);
    const candidates = new Set<string>();
    for (const k of this.keys(b)) for (const id of this.buckets.get(k) ?? []) {
      const pb = this.bounds.get(id)!;
      if (pb[0] <= b[2] && pb[2] >= b[0] && pb[1] <= b[3] && pb[3] >= b[1]) candidates.add(id);
    }
    // Work in the farm's grid frame: small coordinates keep the clipping precise.
    const shape = unionAll(mapPolygons(utm, toGrid));
    const area = multiArea(shape);
    let own = 0;
    let other: string | null = null;
    let otherShare = 0;
    let inside = 0;
    for (const id of [...candidates].sort()) {
      const share = area > 0 ? intersectionArea(shape, unionAll(mapPolygons(this.utm.get(id)!, toGrid))) / area : 0;
      inside += share;
      if (id === ownId) own = share;
      else if (share > otherShare) { other = id; otherShare = share; }
    }
    return {
      area_id: areaId, area_m2: r(area * cellArea, 2), share_in_parcel: r(own, 4), best_other_parcel: other,
      best_other_share: r(otherShare, 4), share_outside_parcels: r(Math.max(0, 1 - inside), 4),
    };
  }
}

function bbox(polys: Polygon[]): [number, number, number, number] {
  let x0 = Infinity;
  let y0 = Infinity;
  let x1 = -Infinity;
  let y1 = -Infinity;
  for (const poly of polys) for (const ring of poly) for (const [x, y] of ring) {
    x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
  }
  return [x0, y0, x1, y1];
}

const r = (v: number, d = 6) => Math.round(v * 10 ** d) / 10 ** d;

function sameCoordinates(a: Polygon[], b: Polygon[], tol: number): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i].length !== b[i].length) return false;
    for (let j = 0; j < a[i].length; j++) {
      const ra = a[i][j];
      const rb = b[i][j];
      if (ra.length !== rb.length) return false;
      for (let k = 0; k < ra.length; k++) {
        if (Math.abs(ra[k][0] - rb[k][0]) > tol || Math.abs(ra[k][1] - rb[k][1]) > tol) return false;
      }
    }
  }
  return true;
}

/** Core cells from the run list; also reports runs that overlap or leave the grid. */
export function coreMask(farm: Farm): { mask: Uint8Array; cells: number; bad_runs: number } {
  const { width: w, height: h } = farm.grid;
  const mask = new Uint8Array(w * h);
  let cells = 0;
  let bad = 0;
  for (const [y, x, n] of farm.zones.core.runs) {
    if (!(Number.isInteger(y) && Number.isInteger(x) && Number.isInteger(n)) || n <= 0 || y < 0 || y >= h || x < 0 || x + n > w) { bad++; continue; }
    for (let i = y * w + x; i < y * w + x + n; i++) {
      if (mask[i]) bad++;
      else { mask[i] = 1; cells++; }
    }
  }
  return { mask, cells, bad_runs: bad };
}

export function auditFarm(farm: Farm, snapshot: SourceSnapshot, dataset: Pick<Dataset, 'buildings'>,
  reportRow: { core_iou: number } | undefined, p: AuditParams, lookup?: ParcelLookup): FarmAudit {
  const issues: string[] = [];
  const fail = new Set<string>();
  const add = (code: string, isFail = false) => { if (!issues.includes(code)) issues.push(code); if (isFail) fail.add(code); };
  const source = farm.stats.building_source;
  const listed = dataset.buildings.get(farm.block_id) ?? [];
  if (listed.length === 0) add('no_buildings_listed', true);
  const hint = farm.geo_hints?.source_building_count;
  if (hint !== undefined && hint !== listed.length) add('building_count_differs');

  const footprints: Polygon[][] = [];
  const footprintIds: string[] = [];
  for (const b of listed) {
    const found = snapshot.buildings.get(buildingKey(source, b.area_id)) ?? [];
    if (found.length === 0) { add('building_missing_in_snapshot', true); continue; }
    if (found.length > 1) add('building_ambiguous_in_snapshot', true);
    if (!sameCoordinates(found[0].polygons, b.polygons, p.coordinate_tolerance_deg)) add('building_geometry_differs');
    footprints.push(found[0].polygons);
    footprintIds.push(b.area_id);
  }

  const cell = farm.source_cell_m;
  const toGrid = gridTransform(farm.source_transform.origin_m, farm.source_transform.rotation_deg, cell);
  const project = (polys: Polygon[]) => mapPolygons(polys, ([lon, lat]) => toGrid(lonLatToUtm(lon, lat)));
  const gridFootprints = footprints.map(project);
  const shape = unionAll(gridFootprints.flat());
  const cellArea = cell * cell;
  const sourceArea = multiArea(shape);
  const sourceTopo = topology(shape);

  const core = coreMask(farm);
  if (core.bad_runs > 0 || core.cells !== farm.counts.core_cell_count) add('core_runs_count_mismatch', true);
  const coreTopo = maskTopology(core.mask, farm.grid.width, farm.grid.height);
  const inter = runsIntersectionArea(shape, farm.zones.core.runs);
  const union = sourceArea + core.cells - inter;
  const iou = union > 0 ? inter / union : 0;

  const parcel = snapshot.parcels.get(farm.parcel_id);
  if (!parcel) add('parcel_missing_in_snapshot', true);
  else if (farm.parcel_aliases && [...farm.parcel_aliases].sort().join() !== parcel.lots.join()) add('parcel_aliases_differ');
  const parcels = lookup ?? new ParcelLookup(snapshot);
  const attribution = footprints.map((fp, i) => parcels.shares(fp, farm.parcel_id, footprintIds[i], toGrid, cellArea));
  for (const a of attribution) {
    if (a.share_in_parcel < p.attribution_min_fraction) add('building_mostly_outside_parcel');
    if (a.best_other_parcel !== null && a.best_other_share > a.share_in_parcel + 1e-3) add('building_larger_share_in_other_parcel');
  }

  if (iou < p.iou_exclude) add('iou_below_exclusion', true);
  else if (iou < p.iou_warn) add('iou_below_warning');
  if (Math.abs(iou - farm.stats.core_iou) > p.iou_delta_warn) add('iou_differs_from_generator');
  if (reportRow && reportRow.core_iou !== farm.stats.core_iou) add('generator_report_differs_from_farm');
  const sourceAreaM2 = sourceArea * cellArea;
  if (Math.abs(sourceAreaM2 - farm.source_area_m2) > p.area_rel_warn * Math.max(farm.source_area_m2, 1)) add('source_area_differs');
  if (sourceTopo.components !== coreTopo.components) add('component_count_differs');
  if (sourceTopo.holes !== coreTopo.holes) add('hole_count_differs');
  if (coreTopo.components !== farm.stats.core_components) add('reported_core_components_differs');

  return {
    block_id: farm.block_id,
    level: fail.size > 0 ? 'fail' : issues.length > 0 ? 'warn' : 'ok',
    issues,
    building_source: source,
    building_area_ids: listed.map(b => b.area_id),
    cell_m: cell,
    rotation_deg: farm.source_transform.rotation_deg,
    source_area_m2: r(sourceAreaM2, 2),
    reported_source_area_m2: farm.source_area_m2,
    source_components: sourceTopo.components,
    source_holes: sourceTopo.holes,
    core_cells: core.cells,
    core_components: coreTopo.components,
    core_holes: coreTopo.holes,
    reported_core_components: farm.stats.core_components,
    iou: r(iou),
    reported_iou: farm.stats.core_iou,
    report_iou: reportRow ? reportRow.core_iou : null,
    iou_delta: r(iou - farm.stats.core_iou),
    buildings: attribution,
    too_small: farm.stats.too_small,
    flags: [...farm.stats.recovery_flags],
  };
}

/** A farm file the audit could not evaluate (malformed JSON or missing fields). */
function unreadable(blockId: string, message: string): FarmAudit {
  return {
    block_id: blockId, level: 'fail', issues: [`farm_unreadable: ${message}`], building_source: '', building_area_ids: [],
    cell_m: 0, rotation_deg: 0, source_area_m2: 0, reported_source_area_m2: 0, source_components: 0, source_holes: 0,
    core_cells: 0, core_components: 0, core_holes: 0, reported_core_components: 0, iou: 0, reported_iou: 0,
    report_iou: null, iou_delta: 0, buildings: [], too_small: false, flags: [],
  };
}

export interface AuditReport {
  audit_version: string;
  status: 'pass' | 'warn' | 'fail';
  parameters: AuditParams;
  inputs: { snapshot_manifest_sha256: string; dataset_manifest_sha256: string };
  reconciliation: Reconciliation;
  summary: {
    farms_audited: number;
    levels: Record<Level, number>;
    issues: Record<string, number>;
    iou: { min: number; median: number; mean: number; max: number };
    iou_delta: { max_abs: number; mean_abs: number; mean: number; over_threshold: number };
    below_warning: { block_id: string; iou: number }[];
    below_exclusion: { block_id: string; iou: number }[];
    iou_differs_from_generator: { block_id: string; iou: number; reported_iou: number; delta: number }[];
    topology_differs: { block_id: string; source: [number, number]; core: [number, number] }[];
    attribution_findings: { block_id: string; area_id: string; share_in_parcel: number; best_other_parcel: string | null; best_other_share: number; share_outside_parcels: number }[];
    flags: Record<string, number>;
    too_small: number;
    cell_scaled_for_total_cap: number;
    /** C-48#13: farms carrying both cell_scaled_for_total_cap and too_small. */
    total_cap_and_too_small: { count: number; block_ids: string[] };
  };
  farms: FarmAudit[];
}

const median = (xs: number[]) => {
  if (xs.length === 0) return 0;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const mean = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0);

export function auditDataset(snapshot: SourceSnapshot, dataset: Dataset, datasetManifestSha: string, p: AuditParams,
  log: (s: string) => void = () => {}): AuditReport {
  const reconciliation = reconcile(snapshot, dataset);
  const lookup = new ParcelLookup(snapshot);
  const reportRows = new Map(dataset.report.parcels.map(row => [row.block_id, row]));
  const farms: FarmAudit[] = [];
  for (const blockId of [...dataset.farm_files].sort()) {
    let a: FarmAudit;
    try {
      a = auditFarm(dataset.readFarm(blockId), snapshot, dataset, reportRows.get(blockId), p, lookup);
    } catch (error) {
      a = unreadable(blockId, (error as Error).message);
    }
    farms.push(a);
    log(`${blockId}: iou ${a.iou.toFixed(4)} (generator ${a.reported_iou}) ${a.level}${a.issues.length ? ` ${a.issues.join(',')}` : ''}`);
  }
  const ious = farms.map(f => f.iou);
  const deltas = farms.map(f => f.iou_delta);
  const levels: Record<Level, number> = { ok: 0, warn: 0, fail: 0 };
  const issues: Record<string, number> = {};
  const flags: Record<string, number> = {};
  for (const f of farms) {
    levels[f.level]++;
    for (const i of f.issues) issues[i] = (issues[i] ?? 0) + 1;
    for (const fl of f.flags) flags[fl] = (flags[fl] ?? 0) + 1;
  }
  const sortKeys = (o: Record<string, number>) => Object.fromEntries(Object.entries(o).sort(([a], [b]) => (a < b ? -1 : 1)));
  const both = farms.filter(f => f.too_small && f.flags.includes('cell_scaled_for_total_cap')).map(f => f.block_id);
  const status = !reconciliation.consistent || levels.fail > 0 || farms.length === 0 ? 'fail' : levels.warn > 0 ? 'warn' : 'pass';
  return {
    audit_version: AUDIT_VERSION,
    status,
    parameters: p,
    inputs: { snapshot_manifest_sha256: snapshot.manifest_sha256, dataset_manifest_sha256: datasetManifestSha },
    reconciliation,
    summary: {
      farms_audited: farms.length,
      levels,
      issues: sortKeys(issues),
      iou: farms.length
        ? { min: r(Math.min(...ious)), median: r(median(ious)), mean: r(mean(ious)), max: r(Math.max(...ious)) }
        : { min: 0, median: 0, mean: 0, max: 0 },
      iou_delta: {
        max_abs: r(Math.max(0, ...deltas.map(Math.abs))), mean_abs: r(mean(deltas.map(Math.abs))), mean: r(mean(deltas)),
        over_threshold: farms.filter(f => f.issues.includes('iou_differs_from_generator')).length,
      },
      below_warning: farms.filter(f => f.issues.includes('iou_below_warning')).map(f => ({ block_id: f.block_id, iou: f.iou })),
      below_exclusion: farms.filter(f => f.issues.includes('iou_below_exclusion')).map(f => ({ block_id: f.block_id, iou: f.iou })),
      iou_differs_from_generator: farms.filter(f => f.issues.includes('iou_differs_from_generator'))
        .map(f => ({ block_id: f.block_id, iou: f.iou, reported_iou: f.reported_iou, delta: f.iou_delta })),
      topology_differs: farms.filter(f => f.source_components !== f.core_components || f.source_holes !== f.core_holes)
        .map(f => ({ block_id: f.block_id, source: [f.source_components, f.source_holes] as [number, number], core: [f.core_components, f.core_holes] as [number, number] })),
      attribution_findings: farms.flatMap(f => f.buildings
        .filter(b => b.share_in_parcel < p.attribution_min_fraction || (b.best_other_parcel !== null && b.best_other_share > b.share_in_parcel + 1e-3))
        .map(b => ({ block_id: f.block_id, area_id: b.area_id, share_in_parcel: b.share_in_parcel, best_other_parcel: b.best_other_parcel, best_other_share: b.best_other_share, share_outside_parcels: b.share_outside_parcels }))),
      flags: sortKeys(flags),
      too_small: farms.filter(f => f.too_small).length,
      cell_scaled_for_total_cap: farms.filter(f => f.flags.includes('cell_scaled_for_total_cap')).length,
      total_cap_and_too_small: { count: both.length, block_ids: both },
    },
    farms,
  };
}

