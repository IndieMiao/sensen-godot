/**
 * Tile check: decodes every parcel tile of a written dataset with an independent decoder
 * (@mapbox/vector-tile + pbf, not our encoder) and compares each feature with the dataset's
 * parcel index: block_id, parcel_id, name, address, farm_path and every other property must equal
 * the index feature, geometry must be a polygon inside that parcel's bounds. Lists coverage and
 * missing parcels per zoom; any parcel missing at the maximum zoom fails the check.
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { classifyRings, VectorTile } from '@mapbox/vector-tile';
import { PbfReader } from 'pbf';
import { PUBLIC_BASE, TILEJSON_TEMPLATE } from './dataset.js';
import { sha256 } from './sources.js';

export interface ZoomCoverage {
  tiles: number;
  feature_instances: number;
  unique_parcels: number;
  missing_count: number;
  missing_ids: string[];
  bytes: number;
  max_tile_bytes: number;
}

export interface TileReport {
  ok: boolean;
  dataset_version: string;
  manifest_sha256: string;
  decoder: Record<string, string>;
  index_parcels: number;
  tile_count: number;
  minzoom: number;
  maxzoom: number;
  zooms: Record<string, ZoomCoverage>;
  error_count: number;
  errors: string[];
  tilejson: string;
}

/** Properties the map hands to the client for one parcel, as decoded from the maximum zoom. */
export type DecodedProperties = Record<string, string | number | boolean>;

const MAX_LISTED_ERRORS = 200;

/** Version of a dependency installed for this package (pnpm links it under ../node_modules). */
function packageVersion(name: string): string {
  const file = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'node_modules', name, 'package.json');
  return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')).version : 'unknown';
}

const listTiles = (dir: string): string[] => {
  const root = path.join(dir, 'tiles');
  if (!existsSync(root)) return [];
  return readdirSync(root, { recursive: true, withFileTypes: true })
    .filter(e => e.isFile())
    .map(e => path.relative(dir, path.join(e.parentPath, e.name)).split(path.sep).join('/'));
};

export function checkTiles(dir: string): { report: TileReport; properties: Map<string, DecodedProperties> } {
  const errors: string[] = [];
  let errorCount = 0;
  const fail = (message: string) => { errorCount++; if (errors.length < MAX_LISTED_ERRORS) errors.push(message); };
  const manifestText = readFileSync(path.join(dir, 'manifest.json'), 'utf8');
  const manifest = JSON.parse(manifestText);
  const params = manifest.map_layer?.parameters;
  if (!params) throw new Error('manifest.json has no map_layer; not a tiled dataset');
  const extent: number = params.tile_extent;
  const minzoom: number = params.tile_minzoom;
  const maxzoom: number = params.tile_maxzoom;
  const index = JSON.parse(readFileSync(path.join(dir, 'index.geojson'), 'utf8'));
  const expected = new Map<string, { properties: DecodedProperties; bbox: number[] }>();
  for (const f of index.features) {
    expected.set(f.properties.block_id, { properties: f.properties, bbox: JSON.parse(f.properties.bbox) });
  }

  const listed = Object.keys(manifest.files as Record<string, string>).filter(name => name.startsWith('tiles/'));
  const onDisk = listTiles(dir);
  for (const name of onDisk) if (!(name in manifest.files)) fail(`${name}: not in manifest.json`);

  const zooms: Record<string, ZoomCoverage> = {};
  const seen = new Map<number, Set<string>>();
  for (let z = minzoom; z <= maxzoom; z++) {
    zooms[z] = { tiles: 0, feature_instances: 0, unique_parcels: 0, missing_count: 0, missing_ids: [], bytes: 0, max_tile_bytes: 0 };
    seen.set(z, new Set());
  }
  const properties = new Map<string, DecodedProperties>();
  for (const name of listed.sort()) {
    const m = /^tiles\/(\d+)\/(\d+)\/(\d+)\.pbf$/.exec(name);
    if (!m) { fail(`${name}: not a tiles/z/x/y.pbf path`); continue; }
    const [z, x, y] = m.slice(1).map(Number);
    if (z < minzoom || z > maxzoom || x >= 2 ** z || y >= 2 ** z) { fail(`${name}: outside z${minzoom}–${maxzoom}`); continue; }
    const file = path.join(dir, name);
    if (!existsSync(file)) { fail(`${name}: missing`); continue; }
    const bytes = readFileSync(file);
    if (sha256(bytes) !== manifest.files[name]) fail(`${name}: hash differs from manifest.json`);
    const zc = zooms[z];
    zc.tiles++; zc.bytes += bytes.length; zc.max_tile_bytes = Math.max(zc.max_tile_bytes, bytes.length);
    let tile: VectorTile;
    try { tile = new VectorTile(new PbfReader(bytes)); } catch (error) { fail(`${name}: does not decode (${error})`); continue; }
    const layers = Object.keys(tile.layers);
    if (layers.length !== 1 || layers[0] !== 'parcels') { fail(`${name}: layers ${JSON.stringify(layers)}, expected only "parcels"`); continue; }
    const layer = tile.layers.parcels;
    if (layer.version !== 2 || layer.extent !== extent) fail(`${name}: layer version ${layer.version} extent ${layer.extent}`);
    // Tolerance: quantization to one tile unit, in degrees of longitude (≥ the latitude unit).
    const unit = 360 / 2 ** z / extent;
    const inTile = new Set<string>();
    for (let i = 0; i < layer.length; i++) {
      const feature = layer.feature(i);
      const props = feature.properties;
      const id = props.block_id;
      if (typeof id !== 'string' || !expected.has(id)) { fail(`${name}: unknown block_id ${JSON.stringify(id)}`); continue; }
      if (inTile.has(id)) fail(`${name}: ${id} appears twice`);
      inTile.add(id);
      zc.feature_instances++;
      seen.get(z)!.add(id);
      const want = expected.get(id)!;
      const keys = new Set([...Object.keys(want.properties), ...Object.keys(props)]);
      for (const key of keys) {
        if (props[key] !== want.properties[key]) fail(`${name}: ${id} ${key}=${JSON.stringify(props[key])}, index has ${JSON.stringify(want.properties[key])}`);
      }
      if (props.farm_path !== `farms/${id}.json` || !(props.farm_path in manifest.files)) fail(`${name}: ${id} farm_path ${props.farm_path} is not a dataset farm`);
      if (feature.type !== 3) { fail(`${name}: ${id} is not a polygon`); continue; }
      const rings = feature.loadGeometry();
      if (rings.length === 0 || classifyRings(rings).length === 0) { fail(`${name}: ${id} has no polygon ring`); continue; }
      const geo = feature.toGeoJSON(x, y, z).geometry;
      const coords = (geo.type === 'Polygon' ? [geo.coordinates] : geo.type === 'MultiPolygon' ? geo.coordinates : []).flat(2);
      const [w, s, e, n] = want.bbox;
      if (coords.some(([lon, lat]) => lon < w - 1.5 * unit || lon > e + 1.5 * unit || lat < s - 1.5 * unit || lat > n + 1.5 * unit)) {
        fail(`${name}: ${id} geometry lies outside its parcel bounds`);
      }
      if (z === maxzoom && !properties.has(id)) properties.set(id, { ...props });
    }
  }
  for (let z = minzoom; z <= maxzoom; z++) {
    const ids = seen.get(z)!;
    const missing = [...expected.keys()].filter(id => !ids.has(id)).sort();
    Object.assign(zooms[z], { unique_parcels: ids.size, missing_count: missing.length, missing_ids: missing });
  }
  if (zooms[maxzoom].missing_count > 0) fail(`z${maxzoom}: ${zooms[maxzoom].missing_count} parcels missing at the maximum zoom`);

  const tilejson = checkTileJson(dir, manifest, Object.keys(expected.values().next().value?.properties ?? {}), fail);
  return {
    report: {
      ok: errorCount === 0,
      dataset_version: manifest.dataset_version,
      manifest_sha256: sha256(manifestText),
      decoder: { '@mapbox/vector-tile': packageVersion('@mapbox/vector-tile'), pbf: packageVersion('pbf'), node: process.version },
      index_parcels: expected.size,
      tile_count: listed.length,
      minzoom,
      maxzoom,
      zooms,
      error_count: errorCount,
      errors,
      tilejson,
    },
    properties,
  };
}

/** The template must describe the tiles; a host-written tilejson.json must be that template with an https base. */
function checkTileJson(dir: string, manifest: any, keys: string[], fail: (m: string) => void): string {
  const file = path.join(dir, TILEJSON_TEMPLATE);
  if (!existsSync(file)) { fail(`${TILEJSON_TEMPLATE}: missing`); return 'missing'; }
  const text = readFileSync(file, 'utf8');
  if (sha256(text) !== manifest.files[TILEJSON_TEMPLATE]) fail(`${TILEJSON_TEMPLATE}: hash differs from manifest.json`);
  const t = JSON.parse(text);
  const p = manifest.map_layer.parameters;
  if (t.scheme !== 'xyz' || t.minzoom !== p.tile_minzoom || t.maxzoom !== p.tile_maxzoom) fail(`${TILEJSON_TEMPLATE}: scheme/zooms differ from the tiles`);
  if (JSON.stringify(t.tiles) !== JSON.stringify([`${PUBLIC_BASE}/tiles/{z}/{x}/{y}.pbf`])) fail(`${TILEJSON_TEMPLATE}: unexpected tiles template`);
  const layer = t.vector_layers?.[0];
  if (t.vector_layers?.length !== 1 || layer.id !== 'parcels' || keys.some(k => !(k in layer.fields))) fail(`${TILEJSON_TEMPLATE}: vector_layers must list "parcels" and its fields`);
  const native = manifest.native_map;
  if (native.type !== 'vector' || native.parcel_source_layer !== 'parcels' || native.parcel_url_path !== 'tilejson.json'
    || native.source_minzoom !== p.tile_minzoom || native.source_maxzoom !== p.tile_maxzoom || native.promote_id !== 'block_id') {
    fail('manifest.json: native_map does not point at the parcel tiles');
  }
  const deployed = path.join(dir, 'tilejson.json');
  if (!existsSync(deployed)) return 'template only (tilejson.json is written by the host: cli tilejson)';
  const d = JSON.parse(readFileSync(deployed, 'utf8'));
  const base = typeof d.tiles?.[0] === 'string' ? d.tiles[0].replace(/\/tiles\/\{z\}\/\{x\}\/\{y\}\.pbf$/, '') : '';
  if (!isPublicBase(base) || JSON.stringify(d) !== JSON.stringify(deployTileJson(t, base))) fail('tilejson.json: not the template with an https base URL');
  return `deployed: ${base}`;
}

export function isPublicBase(base: string): boolean {
  try {
    const u = new URL(base);
    return u.protocol === 'https:' && !u.username && !u.password && !u.search && !u.hash && !base.endsWith('/') && !base.includes('{');
  } catch {
    return false;
  }
}

/** tilejson.json for a host: the template with {PUBLIC_BASE} replaced (no trailing slash). */
export function deployTileJson(template: { tiles: string[] }, base: string) {
  if (!isPublicBase(base)) throw new Error('base must be an https URL without credentials, query, fragment or trailing slash');
  return { ...template, tiles: template.tiles.map(t => t.replace(PUBLIC_BASE, base)) };
}
