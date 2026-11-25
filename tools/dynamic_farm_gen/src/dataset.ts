/**
 * Builds a dataset directory from a snapshot: farms/<block_id>.json, the parcel index, the parcel
 * vector tiles and their TileJSON template, the building layer, client-manifest.json and a
 * manifest with every file's SHA-256.
 * Output depends only on (snapshot, parameters, dataset_version): no clock, no randomness.
 */
import { existsSync, mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { slimPolygons } from './buildings.js';
import { GENERATOR_VERSION, SCHEMA, type GeneratorParams } from './config.js';
import { generateFarm, LowIouError, OSM_ATTRIBUTION } from './farm.js';
import { bounds, insideRings, polygonArea, rotate, round, toUtm, type Point, type Polygon } from './geo.js';
import { DIRS, LayoutError, type Dir } from './layout.js';
import { encodeTiles, MVT_ENCODER, resolveMapParams, type MapLayerParams, type TileFeature, type TileValue } from './mvt.js';
import { rasterize } from './raster.js';
import { sha256 } from './sources.js';
import type { BuildingRecord, ParcelRecord, Snapshot } from './snapshot.js';

export interface BuildOptions {
  dataset_version: string;
  params: GeneratorParams;
  /** Map layer (tiles, building layer); defaults from src/mvt.ts. */
  map?: MapLayerParams;
  /** Restrict the farms written (block ids); the index then lists only these. */
  only?: Set<string>;
}

export interface ParcelReport {
  block_id: string;
  name: string;
  building_count: number;
  building_source: string;
  /** area_id of each source footprint the farm was built from (in building_source). */
  building_area_ids: number[];
  building_area_m2: number;
  parcel_area_m2: number;
  cell_m: number;
  cell_area_m2: number;
  rotation_deg: number;
  core_cell_count: number;
  extension_cell_count: number;
  total_cell_count: number;
  core_iou: number;
  too_small: boolean;
  flags: string[];
}

export interface BuildResult {
  /** Relative path → contents; tiles/*.pbf are binary, everything else is UTF-8 text. */
  files: Map<string, string | Uint8Array>;
  reports: ParcelReport[];
  /** `low_iou` rows also carry the core IoU and cell size that failed `min_core_iou`. */
  excluded: { block_id: string; reason: string; core_iou?: number; cell_m?: number }[];
}

interface Projected { record: ParcelRecord; utm: Polygon[]; bounds: ReturnType<typeof bounds> }

const project = (polys: Polygon[]): Polygon[] => polys.map(poly => poly.map(ring => ring.map(([lon, lat]) => toUtm(lon, lat))));
const q7 = (v: number) => round(v, 7);

/** Uniform grid over parcel bounds for point lookups. */
class ParcelIndex {
  private cells = new Map<string, number[]>();
  constructor(readonly parcels: Projected[], private size = 100) {
    parcels.forEach((p, i) => {
      for (let x = Math.floor(p.bounds.minX / size); x <= Math.floor(p.bounds.maxX / size); x++) {
        for (let y = Math.floor(p.bounds.minY / size); y <= Math.floor(p.bounds.maxY / size); y++) {
          const k = `${x},${y}`;
          if (!this.cells.has(k)) this.cells.set(k, []);
          this.cells.get(k)!.push(i);
        }
      }
    });
  }
  at(x: number, y: number): number[] {
    const hits: number[] = [];
    for (const i of this.cells.get(`${Math.floor(x / this.size)},${Math.floor(y / this.size)}`) ?? []) {
      const p = this.parcels[i];
      if (x < p.bounds.minX || x > p.bounds.maxX || y < p.bounds.minY || y > p.bounds.maxY) continue;
      if (p.utm.some(poly => insideRings(poly, x, y))) hits.push(i);
    }
    return hits;
  }
}

/**
 * Each building goes to the parcel holding most of its 1 m sample points; the footprint's own
 * map-block-lot (centroid join from a draft basemap) only breaks ties or covers misses.
 */
function assign(buildings: BuildingRecord[], utm: Polygon[][], index: ParcelIndex, byId: Map<string, number>): number[] {
  return buildings.map((b, bi) => {
    const votes = new Map<number, number>();
    const cov = rasterize(utm[bi], 0, 1, 1, [0, 0], 0);
    const f = cov.frame;
    let samples = 0;
    for (let y = 0; y < f.height; y++) for (let x = 0; x < f.width; x++) {
      if (cov.cov[y * f.width + x] < 1) continue;
      samples++;
      for (const i of index.at(f.u0 + (x + 0.5), f.v0 + (y + 0.5))) votes.set(i, (votes.get(i) ?? 0) + 1);
    }
    if (samples === 0) {
      const ring = utm[bi][0][0];
      const c = ring.reduce((s, p) => [s[0] + p[0] / ring.length, s[1] + p[1] / ring.length], [0, 0]);
      for (const i of index.at(c[0], c[1])) votes.set(i, 1);
    }
    const mblr = b.mblr !== null ? byId.get(b.mblr) : undefined;
    let best = -1;
    let bestVotes = 0;
    for (const [i, v] of [...votes.entries()].sort((a, c) => a[0] - c[0])) {
      if (v > bestVotes || (v === bestVotes && i === mblr)) { best = i; bestVotes = v; }
    }
    return best >= 0 ? best : mblr ?? -1;
  });
}

/**
 * Which side faces the street: probes 3 m outside the parcel edge on each side and prefers the
 * side whose probes land in no parcel (right-of-way); then the smaller setback; then S, W, E, N.
 */
function frontFinder(parcel: Projected, buildings: Polygon[], index: ParcelIndex, self: number) {
  return (rotation: number): Dir => {
    const pr = parcel.utm.flatMap(poly => poly.map(ring => ring.map(p => rotate(p, rotation))));
    const br = buildings.flatMap(poly => poly.map(ring => ring.map(p => rotate(p, rotation))));
    const pb = bounds(pr);
    const bb = bounds(br);
    let best: Dir = DIRS.south;
    let bestScore = [-1, Infinity];
    for (const d of [DIRS.south, DIRS.west, DIRS.east, DIRS.north]) {
      const along = d.dx === 0;
      const lo = along ? pb.minX : pb.minY;
      const hi = along ? pb.maxX : pb.maxY;
      let street = 0;
      let probes = 0;
      for (let k = 1; k <= 5; k++) {
        const l = lo + ((hi - lo) * k) / 6;
        let edge = -Infinity;
        for (const ring of pr) for (let i = 0; i + 1 < ring.length; i++) {
          const a = ring[i];
          const b = ring[i + 1];
          const [la, lb] = along ? [a[0], b[0]] : [a[1], b[1]];
          if ((la > l) === (lb > l)) continue;
          const t = (l - la) / (lb - la);
          const x = a[0] + (b[0] - a[0]) * t;
          const y = a[1] + (b[1] - a[1]) * t;
          edge = Math.max(edge, x * d.dx + y * d.dy);
        }
        if (edge === -Infinity) continue;
        const out = edge + 3;
        const probe: Point = along ? [l, out * d.dy] : [out * d.dx, l];
        const [ux, uy] = rotate(probe, -rotation);
        probes++;
        if (index.at(ux, uy).every(i => i === self)) street++;
      }
      const setback = d.dx === 0
        ? (d.dy < 0 ? bb.minY - pb.minY : pb.maxY - bb.maxY)
        : (d.dx < 0 ? bb.minX - pb.minX : pb.maxX - bb.maxX);
      const score = [probes ? street / probes : 0, setback];
      if (score[0] > bestScore[0] + 1e-9 || (Math.abs(score[0] - bestScore[0]) <= 1e-9 && score[1] < bestScore[1] - 1e-6)) {
        best = d;
        bestScore = score;
      }
    }
    return best;
  };
}

function geometryHash(parcel: ParcelRecord, buildings: BuildingRecord[]): string {
  const rings = (polys: Polygon[]) => polys.map(poly => poly.map(ring => ring.map(([x, y]) => [q7(x), q7(y)])));
  return sha256(JSON.stringify({ parcel: rings(parcel.polygons), buildings: buildings.map(b => ({ source: b.source, area_id: b.area_id, rings: rings(b.polygons) })) }));
}

const lonLatBounds = (polys: Polygon[]) => bounds(polys.flat());
/** Area centroid of the outer rings, relative to the first vertex to keep precision. */
function lonLatCentroid(polys: Polygon[]): Point {
  const [ox, oy] = polys[0][0][0];
  let a = 0;
  let cx = 0;
  let cy = 0;
  for (const poly of polys) {
    const ring = poly[0].map(([x, y]) => [x - ox, y - oy]);
    for (let i = 0; i + 1 < ring.length; i++) {
      const cross = ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1];
      a += cross;
      cx += (ring[i][0] + ring[i + 1][0]) * cross;
      cy += (ring[i][1] + ring[i + 1][1]) * cross;
    }
  }
  return a === 0 ? [ox, oy] : [ox + cx / (3 * a), oy + cy / (3 * a)];
}

export function buildDataset(snap: Snapshot, opts: BuildOptions, log: (s: string) => void = () => {}): BuildResult {
  const p = opts.params;
  const mapParams = opts.map ?? resolveMapParams();
  const projected: Projected[] = snap.parcels.map(record => {
    const utm = project(record.polygons);
    return { record, utm, bounds: bounds(utm.flat()) };
  });
  const byId = new Map(projected.map((pp, i) => [pp.record.parcel_id, i]));
  const index = new ParcelIndex(projected);
  const buildingUtm = snap.buildings.map(b => project(b.polygons));
  const owner = assign(snap.buildings, buildingUtm, index, byId);

  const perParcel = new Map<number, Map<string, number[]>>();
  owner.forEach((pi, bi) => {
    if (pi < 0) return;
    if (!perParcel.has(pi)) perParcel.set(pi, new Map());
    const bySource = perParcel.get(pi)!;
    const src = snap.buildings[bi].source;
    if (!bySource.has(src)) bySource.set(src, []);
    bySource.get(src)!.push(bi);
  });

  const buildingDefs = snap.manifest.sources.filter(s => s.role === 'buildings');
  const fallbackSources = new Set(buildingDefs.filter(s => s.fallback).map(s => s.label));
  const osmSources = new Set(buildingDefs.filter(s => s.kind === 'osm-pbf').map(s => s.label));

  const files = new Map<string, string | Uint8Array>();
  const reports: ParcelReport[] = [];
  const excluded: BuildResult['excluded'] = [];
  const indexFeatures: unknown[] = [];
  const buildingFeatures: unknown[] = [];
  const tileFeatures: TileFeature[] = [];
  const lonLatBounds_ = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity };
  for (let pi = 0; pi < projected.length; pi++) {
    const parcel = projected[pi];
    const blockId = `p-${parcel.record.parcel_id}`;
    if (opts.only && !opts.only.has(blockId)) continue;
    const bySource = perParcel.get(pi);
    if (!bySource) { excluded.push({ block_id: blockId, reason: 'no_building' }); continue; }
    // One source per parcel, never a mix of copies whose coordinates disagree: the copy with the
    // most footprint area (the more complete one), earlier sources winning ties. A fallback source
    // (OpenStreetMap, C-113) only counts when no other source has a footprint here.
    let chosen = '';
    for (const fallback of [false, true]) {
      let chosenArea = 0;
      for (const src of snap.building_sources) {
        if (fallbackSources.has(src) !== fallback) continue;
        const a = (bySource.get(src) ?? []).reduce((sum, i) => sum + buildingUtm[i].reduce((t, poly) => t + polygonArea(poly), 0), 0);
        if (a > chosenArea + 1e-6) { chosen = src; chosenArea = a; }
      }
      if (chosen) break;
    }
    if (!chosen) { excluded.push({ block_id: blockId, reason: 'no_building' }); continue; }
    const ids = bySource.get(chosen)!;
    const records = ids.map(i => snap.buildings[i]);
    const hash = geometryHash(parcel.record, records);
    let result;
    try {
      result = generateFarm({
        dataset_version: opts.dataset_version,
        parcel_id: parcel.record.parcel_id,
        aliases: parcel.record.aliases,
        name: parcel.record.name,
        address: parcel.record.address,
        buildings: ids.flatMap(i => buildingUtm[i]),
        building_source: chosen,
        attribution: osmSources.has(chosen) ? OSM_ATTRIBUTION : undefined,
        parcel_area_m2: parcel.utm.reduce((s, poly) => s + polygonArea(poly), 0),
        front: frontFinder(parcel, ids.flatMap(i => buildingUtm[i]), index, pi),
        source_geometry_hash: hash,
      }, p);
    } catch (error) {
      if (!(error instanceof LayoutError)) throw error;
      excluded.push(error instanceof LowIouError
        ? { block_id: blockId, reason: 'low_iou', core_iou: round(error.iou, 4), cell_m: error.cell_m }
        : { block_id: blockId, reason: `layout: ${error.message}` });
      continue;
    }
    const farmPath = `farms/${blockId}.json`;
    files.set(farmPath, JSON.stringify(result.farm));
    const counts = result.farm.counts as Record<string, number>;
    const lb = lonLatBounds(parcel.record.polygons);
    const center = lonLatCentroid(parcel.record.polygons).map(q7);
    const bbox = [lb.minX, lb.minY, lb.maxX, lb.maxY].map(q7);
    lonLatBounds_.minX = Math.min(lonLatBounds_.minX, lb.minX);
    lonLatBounds_.minY = Math.min(lonLatBounds_.minY, lb.minY);
    lonLatBounds_.maxX = Math.max(lonLatBounds_.maxX, lb.maxX);
    lonLatBounds_.maxY = Math.max(lonLatBounds_.maxY, lb.maxY);
    const properties: Record<string, TileValue> = {
      block_id: blockId, parcel_id: parcel.record.parcel_id, selection_unit: 'parcel',
      name: parcel.record.name, address: parcel.record.address ?? '',
      center: JSON.stringify(center), bbox: JSON.stringify(bbox), center_lon: center[0], center_lat: center[1],
      farm_path: farmPath, cell_count: counts.core_cell_count,
      core_cell_count: counts.core_cell_count, extension_cell_count: counts.extension_cell_count, total_cell_count: counts.total_cell_count,
      source_area_m2: round(result.area_m2, 2), building_count: records.length, too_small: result.too_small,
    };
    const geometry = geometryJson(parcel.record.polygons);
    indexFeatures.push({ type: 'Feature', id: blockId, properties, geometry });
    // The tiles carry the same outline and the same properties as the index feature.
    const outline = (geometry.type === 'Polygon' ? [geometry.coordinates] : geometry.coordinates) as Polygon[];
    tileFeatures.push({ id: blockId, properties, polygons: outline });
    for (const b of records) {
      const slim = slimPolygons(b.polygons, mapParams);
      if (slim.length > 0) buildingFeatures.push({ type: 'Feature', properties: { block_id: blockId }, geometry: shape(slim) });
    }
    reports.push({
      block_id: blockId, name: parcel.record.name, building_count: records.length, building_source: chosen,
      building_area_ids: records.map(b => b.area_id),
      building_area_m2: round(result.area_m2, 2),
      parcel_area_m2: round(parcel.utm.reduce((s, poly) => s + polygonArea(poly), 0), 2),
      cell_m: result.cell_m, cell_area_m2: round(result.cell_m * result.cell_m, 4), rotation_deg: result.rotation_deg,
      core_cell_count: counts.core_cell_count, extension_cell_count: counts.extension_cell_count, total_cell_count: counts.total_cell_count,
      core_iou: round(result.iou, 4), too_small: result.too_small, flags: result.flags,
    });
    log(`${blockId} ${parcel.record.name}: ${counts.core_cell_count} core / ${counts.total_cell_count} total, cell ${result.cell_m} m, iou ${round(result.iou, 3)}`);
  }
  if (reports.length === 0) throw new Error('no farm could be generated');

  const bboxAll = [lonLatBounds_.minX, lonLatBounds_.minY, lonLatBounds_.maxX, lonLatBounds_.maxY].map(q7);
  files.set('index.geojson', JSON.stringify({ type: 'FeatureCollection', features: indexFeatures }));
  files.set('buildings.geojson', JSON.stringify({ type: 'FeatureCollection', features: buildingFeatures }));
  const tiles = encodeTiles(tileFeatures, mapParams);
  for (const [name, body] of tiles) files.set(name, body);
  const tileStats: Record<string, { tiles: number; bytes: number; max_tile_bytes: number }> = {};
  for (const [name, body] of tiles) {
    const z = name.split('/')[1];
    const s = (tileStats[z] ??= { tiles: 0, bytes: 0, max_tile_bytes: 0 });
    s.tiles++; s.bytes += body.length; s.max_tile_bytes = Math.max(s.max_tile_bytes, body.length);
  }
  const center = [q7((bboxAll[0] + bboxAll[2]) / 2), q7((bboxAll[1] + bboxAll[3]) / 2)];
  files.set(TILEJSON_TEMPLATE, `${JSON.stringify(tileJsonTemplate(tileFeatures, mapParams, bboxAll, center), null, 2)}\n`);
  const report = {
    dataset_version: opts.dataset_version,
    generator_version: GENERATOR_VERSION,
    parameters: p,
    totals: {
      parcels_in_snapshot: snap.parcels.length,
      farms: reports.length,
      too_small: reports.filter(r => r.too_small).length,
      excluded: excluded.length,
      buildings_in_snapshot: snap.buildings.length,
      buildings_unassigned: owner.filter(o => o < 0).length,
    },
    parcels: reports,
    excluded,
    rejected_records: snap.rejected,
  };
  files.set('reports/generation-report.json', `${JSON.stringify(report, null, 2)}\n`);

  const fileHashes: Record<string, string> = {};
  for (const name of [...files.keys()].sort()) fileHashes[name] = sha256(files.get(name)!);
  // r4 map-layer keys (geo_map_config.gd): parcels from vector tiles through tilejson.json, which
  // the host writes from tilejson.template.json once the public base URL is known (`cli tilejson`).
  const native = {
    type: 'vector', parcel_url_path: 'tilejson.json', parcel_source_layer: 'parcels', promote_id: 'block_id',
    source_minzoom: mapParams.tile_minzoom, source_maxzoom: mapParams.tile_maxzoom,
    minzoom: 16, address_minzoom: 18, bounds: bboxAll, center,
    initial_zoom: 17.5, building_source: 'datasf', buildings_url_path: 'buildings.geojson',
  };
  const manifest = {
    schema: SCHEMA,
    dataset_version: opts.dataset_version,
    selection_unit: 'parcel',
    map_format: 'mvt',
    generator_version: GENERATOR_VERSION,
    parcel_count: reports.length,
    block_count: reports.length,
    counts: report.totals,
    generator: { version: GENERATOR_VERSION, parameters: p },
    map_layer: {
      tile_encoder: MVT_ENCODER,
      tippecanoe: 'not used; tiles come from the built-in encoder (src/mvt.ts)',
      source_layer: 'parcels',
      tile_format: 'MVT 2.1, uncompressed, XYZ tiles/{z}/{x}/{y}.pbf',
      tilejson_template: TILEJSON_TEMPLATE,
      parameters: mapParams,
      tiles: tileStats,
      buildings: 'buildings.geojson: one feature per used footprint, block_id only, lon/lat rounded and simplified (parameters)',
    },
    sources: {
      snapshot_manifest_sha256: snap.manifest_sha256,
      bbox: snap.manifest.bbox,
      fetched_at: snap.manifest.fetched_at,
      datasets: snap.manifest.sources.map(s => ({
        label: s.label, role: s.role, title: s.title, datasf_dataset: s.datasf_dataset, license: s.license,
        url: s.url, arcgis_item: s.arcgis_item ?? null, metadata: s.metadata, note: s.note ?? null, files: s.files,
      })),
    },
    native_map: native,
    scope: { mode: snap.manifest.bbox ? 'bbox' : 'full_city', bounds: bboxAll },
    ...(osmSources.size > 0 ? { licence: osmLicence(reports, osmSources) } : {}),
    files: fileHashes,
  };
  const manifestText = `${JSON.stringify(manifest, null, 2)}\n`;
  files.set('manifest.json', manifestText);
  const client = {
    schema: SCHEMA,
    dataset_version: opts.dataset_version,
    selection_unit: 'parcel',
    parcel_count: reports.length,
    block_count: reports.length,
    generator_version: GENERATOR_VERSION,
    native_map: native,
    scope: manifest.scope,
    source_manifest_sha256: sha256(manifestText),
  };
  files.set('client-manifest.json', `${JSON.stringify(client, null, 2)}\n`);
  return { files, reports, excluded };
}

/**
 * ODbL 1.0 (C-113): a dataset with OpenStreetMap buildings is a derivative database. It names the
 * OSM credit and stays under the ODbL; the DataSF parcels and footprints remain PDDL. Datasets
 * without an OSM source carry no `licence` block, so their manifests are unchanged.
 */
function osmLicence(reports: ParcelReport[], osm: Set<string>) {
  const farms: Record<string, number> = {};
  for (const r of reports) farms[r.building_source] = (farms[r.building_source] ?? 0) + 1;
  return {
    dataset: 'Open Data Commons Open Database License (ODbL) 1.0',
    attribution: '© OpenStreetMap contributors; DataSF (PDDL 1.0)',
    notice: 'Contains information from OpenStreetMap (https://www.openstreetmap.org/copyright), made available here under the '
      + 'Open Database License (ODbL) 1.0. Parcels and DataSF footprints: Public Domain Dedication and License (PDDL) 1.0.',
    farms_by_building_source: farms,
    osm_farms: reports.filter(r => osm.has(r.building_source)).length,
  };
}

function geometryJson(polys: Polygon[]) {
  return shape(polys.map(poly => poly.map(ring => ring.map(([x, y]) => [q7(x), q7(y)]))));
}

function shape(coords: number[][][][]) {
  return coords.length === 1 ? { type: 'Polygon', coordinates: coords[0] } : { type: 'MultiPolygon', coordinates: coords };
}

export const TILEJSON_TEMPLATE = 'tilejson.template.json';
export const PUBLIC_BASE = '{PUBLIC_BASE}';

function tileJsonTemplate(features: TileFeature[], p: MapLayerParams, bbox: number[], center: number[]) {
  const fields: Record<string, string> = {};
  for (const f of features) {
    for (const [key, value] of Object.entries(f.properties)) fields[key] ??= typeof value === 'string' ? 'String' : typeof value === 'number' ? 'Number' : 'Boolean';
  }
  return {
    tilejson: '2.2.0',
    name: 'Dynamic Farm SF parcels',
    scheme: 'xyz',
    tiles: [`${PUBLIC_BASE}/tiles/{z}/{x}/{y}.pbf`],
    minzoom: p.tile_minzoom,
    maxzoom: p.tile_maxzoom,
    bounds: bbox,
    center: [...center, 17.5],
    attribution: 'DataSF (PDDL 1.0)',
    vector_layers: [{ id: 'parcels', minzoom: p.tile_minzoom, maxzoom: p.tile_maxzoom, fields }],
  };
}

/** Replaces `dir` only if it is empty or holds an earlier dataset (client-manifest.json). */
export function writeDataset(dir: string, result: BuildResult): void {
  if (existsSync(dir) && readdirSync(dir).length > 0 && !existsSync(path.join(dir, 'client-manifest.json'))) {
    throw new Error(`${dir} is not empty and does not hold a dataset; refusing to replace it`);
  }
  rmSync(dir, { recursive: true, force: true });
  for (const [name, body] of result.files) {
    const file = path.join(dir, name);
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, body);
  }
}
