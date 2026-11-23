/**
 * Reads the two audit inputs straight from disk: the DataSF source snapshot (raw responses listed
 * in source-manifest.json) and a generated dataset directory. Nothing here comes from generator code.
 */
import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { geoJsonPolygons, type Polygon } from './geometry.js';

export const sha256 = (data: string | Buffer) => createHash('sha256').update(data).digest('hex');

type Feature = { properties?: Record<string, unknown> | null; geometry?: { type: string; coordinates: unknown } | null };

interface ManifestSource { label: string; role: string; files: { file: string; sha256: string; count: number }[] }

export interface SourceParcel {
  /** mapblklot, or blklot when mapblklot is empty. */
  id: string;
  /** All lot numbers grouped under the id. */
  lots: string[];
  /** Every member lot's polygons (lon/lat). */
  polygons: Polygon[];
}

export interface SourceBuilding { source: string; area_id: string; polygons: Polygon[] }

export interface SourceSnapshot {
  manifest_sha256: string;
  file_problems: string[];
  parcel_source: string;
  /** Parcels with a usable id and geometry: the valid input set. */
  parcels: Map<string, SourceParcel>;
  /** Parcel ids left out of the valid input set, once per id and reason (ids with a usable lot are not listed). */
  invalid_parcels: { id: string; reason: 'inactive' | 'invalid_id' | 'no_geometry' }[];
  /** `${source}|${area_id}` -> records (more than one means the id is ambiguous in that source). */
  buildings: Map<string, SourceBuilding[]>;
  building_sources: string[];
}

const text = (v: unknown) => (v === null || v === undefined ? '' : String(v).trim());
/** DataSF `active` is 1/true for active parcels; a missing field means the source holds active parcels only. */
const isActive = (v: unknown) => v === undefined || v === null || v === true || v === 1 || v === '1' || v === 'true';
const VALID_ID = /^[A-Za-z0-9]{1,40}$/;

export const buildingKey = (source: string, areaId: string | number) => `${source}|${text(areaId)}`;

export function loadSnapshot(dir: string): SourceSnapshot {
  const raw = readFileSync(path.join(dir, 'source-manifest.json'));
  const manifest = JSON.parse(raw.toString('utf8')) as { sources: ManifestSource[] };
  const fileProblems: string[] = [];
  const features = (src: ManifestSource): Feature[] => src.files.flatMap(f => {
    const file = path.join(dir, f.file);
    if (!existsSync(file)) { fileProblems.push(`missing ${f.file}`); return []; }
    const body = readFileSync(file);
    if (sha256(body) !== f.sha256) fileProblems.push(`sha256 mismatch ${f.file}`);
    const list = (JSON.parse(body.toString('utf8')).features ?? []) as Feature[];
    if (list.length !== f.count) fileProblems.push(`${f.file}: ${list.length} features, manifest says ${f.count}`);
    return list;
  });

  const parcelSources = manifest.sources.filter(s => s.role === 'parcels');
  if (parcelSources.length !== 1) throw new Error(`snapshot has ${parcelSources.length} parcel sources, expected 1`);
  const parcels = new Map<string, SourceParcel>();
  const invalid: SourceSnapshot['invalid_parcels'] = [];
  const pending = new Map<string, { lots: Set<string>; polygons: Polygon[] }>();
  for (const f of features(parcelSources[0])) {
    const p = f.properties ?? {};
    const lot = text(p.blklot);
    const id = text(p.mapblklot) || lot;
    if (!isActive(p.active)) { invalid.push({ id, reason: 'inactive' }); continue; }
    if (!VALID_ID.test(id) || !VALID_ID.test(lot)) { invalid.push({ id, reason: 'invalid_id' }); continue; }
    if (!pending.has(id)) pending.set(id, { lots: new Set(), polygons: [] });
    const entry = pending.get(id)!;
    entry.lots.add(lot);
    entry.polygons.push(...geoJsonPolygons(f.geometry));
  }
  for (const [id, entry] of pending) {
    if (entry.polygons.length === 0) { invalid.push({ id, reason: 'no_geometry' }); continue; }
    parcels.set(id, { id, lots: [...entry.lots].sort(), polygons: entry.polygons });
  }

  const buildings = new Map<string, SourceBuilding[]>();
  const buildingSources = manifest.sources.filter(s => s.role === 'buildings');
  for (const src of buildingSources) {
    for (const f of features(src)) {
      const areaId = text(f.properties?.area_id);
      if (!areaId) continue;
      const key = buildingKey(src.label, areaId);
      if (!buildings.has(key)) buildings.set(key, []);
      buildings.get(key)!.push({ source: src.label, area_id: areaId, polygons: geoJsonPolygons(f.geometry) });
    }
  }
  // Counted per parcel id: an id with at least one usable lot is valid, and each left-out id is
  // listed once per reason even when several of its lot features were skipped.
  const seenInvalid = new Set<string>();
  const invalidIds = invalid.filter(x => {
    const key = `${x.reason}|${x.id}`;
    if (parcels.has(x.id) || seenInvalid.has(key)) return false;
    seenInvalid.add(key);
    return true;
  });
  return {
    manifest_sha256: sha256(raw), file_problems: fileProblems, parcel_source: parcelSources[0].label,
    parcels, invalid_parcels: invalidIds, buildings, building_sources: buildingSources.map(s => s.label),
  };
}

export interface Farm {
  block_id: string;
  parcel_id: string;
  parcel_aliases?: string[];
  source_cell_m: number;
  source_area_m2: number;
  source_transform: { crs: string; rotation_deg: number; origin_m: [number, number] };
  grid: { width: number; height: number };
  zones: { core: { runs: number[][] } };
  counts: { core_cell_count: number; extension_cell_count: number; total_cell_count: number };
  geo_hints?: { source_building_count?: number };
  stats: { core_iou: number; core_components: number; building_source: string; too_small: boolean; recovery_flags: string[] };
}

export interface GenerationReportParcel {
  block_id: string;
  core_iou: number;
  too_small: boolean;
  flags: string[];
  building_count: number;
  /** Source area_ids of the farm's footprints (datasets from C-55 on; older ones have them in buildings.geojson). */
  building_area_ids?: (number | string)[];
}

/** Files that are written next to a dataset by the host and are not listed in manifest.json. */
export const UNLISTED_FILES = new Set(['manifest.json', 'client-manifest.json', 'tilejson.json']);

export interface Dataset {
  dir: string;
  manifest: { files: Record<string, string>; parcel_count?: number; sources?: { snapshot_manifest_sha256?: string } };
  /** Block ids of the files actually present in farms/. */
  farm_files: string[];
  /** Files in the dataset whose bytes differ from manifest.json, or that are missing / unlisted. */
  file_problems: string[];
  index_ids: string[];
  /**
   * block_id -> the map layer's footprints in buildings.geojson. Older datasets carry each
   * footprint's area_id at full precision; from C-55 on there is no area_id (null) and the
   * geometry is rounded and simplified for the map.
   */
  buildings: Map<string, { area_id: string | null; polygons: Polygon[] }[]>;
  report: {
    totals: Record<string, number>;
    parcels: GenerationReportParcel[];
    excluded: { block_id: string; reason: string }[];
    rejected_records: { source: string; reason: string; id: string }[];
  };
  readFarm(blockId: string): Farm;
}

function listFiles(dir: string, base = ''): string[] {
  return readdirSync(path.join(dir, base), { withFileTypes: true }).flatMap(e => {
    const rel = base ? `${base}/${e.name}` : e.name;
    return e.isDirectory() ? listFiles(dir, rel) : [rel];
  });
}

export function loadDataset(dir: string): Dataset {
  const manifest = JSON.parse(readFileSync(path.join(dir, 'manifest.json'), 'utf8')) as Dataset['manifest'];
  const problems: string[] = [];
  const present = listFiles(dir).filter(f => !UNLISTED_FILES.has(f)).sort();
  for (const f of present) {
    const want = manifest.files[f];
    if (want === undefined) problems.push(`not in manifest: ${f}`);
    else if (sha256(readFileSync(path.join(dir, f))) !== want) problems.push(`sha256 mismatch: ${f}`);
  }
  const presentSet = new Set(present);
  for (const f of Object.keys(manifest.files)) if (!presentSet.has(f)) problems.push(`listed but missing: ${f}`);
  const farmFiles = present
    .filter(f => /^farms\/[^/]+\.json$/.test(f))
    .map(f => f.slice('farms/'.length, -'.json'.length));
  const index = JSON.parse(readFileSync(path.join(dir, 'index.geojson'), 'utf8')) as { features: { id?: string; properties?: { block_id?: string } }[] };
  const buildingsJson = JSON.parse(readFileSync(path.join(dir, 'buildings.geojson'), 'utf8')) as { features: Feature[] };
  const buildings = new Map<string, { area_id: string | null; polygons: Polygon[] }[]>();
  for (const f of buildingsJson.features) {
    const blockId = text(f.properties?.block_id);
    if (!buildings.has(blockId)) buildings.set(blockId, []);
    buildings.get(blockId)!.push({ area_id: text(f.properties?.area_id) || null, polygons: geoJsonPolygons(f.geometry) });
  }
  const report = JSON.parse(readFileSync(path.join(dir, 'reports/generation-report.json'), 'utf8')) as Dataset['report'];
  return {
    dir, manifest, farm_files: farmFiles, file_problems: problems,
    index_ids: index.features.map(f => text(f.properties?.block_id ?? f.id)),
    buildings, report,
    readFarm: (blockId: string) => JSON.parse(readFileSync(path.join(dir, 'farms', `${blockId}.json`), 'utf8')) as Farm,
  };
}
