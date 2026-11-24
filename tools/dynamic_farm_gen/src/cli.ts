/**
 * fetch    --out <snapshot> --sources <label,...> [--bbox minLon,minLat,maxLon,maxLat]
 * build    --snapshot <snapshot> --out <dataset> --dataset-version <v> [--params <json>] [--map-params <json>] [--only p-1,p-2]
 * validate --dataset <dataset> [--core-range current|relaxed]
 * check-tiles --dataset <dataset> [--report <json>] [--properties <json>]
 * tilejson --dataset <dataset> --base <https URL the dataset is served from>
 * compare  --dataset <dataset> --out <dir> --ids p-1,p-2 [--before <dir with older farms/*.json>]
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { compareSvg } from './compare.js';
import { resolveParams } from './config.js';
import { buildDataset, TILEJSON_TEMPLATE, writeDataset } from './dataset.js';
import type { Polygon } from './geo.js';
import { resolveMapParams } from './mvt.js';
import { loadSnapshot } from './snapshot.js';
import { fetchSnapshot, sha256 } from './sources.js';
import { checkTiles, deployTileJson, type TileReport } from './tilecheck.js';
import { checkMapGeometry, checkParcelProperties, CURRENT_CLIENT, decodeFarm, RELAXED } from './validate.js';

function args(argv: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith('--')) throw new Error(`unexpected argument ${argv[i]}`);
    out[argv[i].slice(2)] = argv[i + 1] ?? '';
    i++;
  }
  return out;
}

function need(a: Record<string, string>, key: string): string {
  if (!a[key]) throw new Error(`--${key} is required`);
  return a[key];
}

/**
 * Validates every file hash, farm, index feature, map-layer geometry and parcel tile of a written dataset; returns the number of failures.
 * A dataset without manifest.map_layer and without tiles predates the map layer: its tile check is skipped and logged.
 */
export function validateDataset(dir: string, range = RELAXED, log = console.log): number {
  const manifest = JSON.parse(readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
  let failures = 0;
  for (const [file, hash] of Object.entries(manifest.files as Record<string, string>)) {
    const body = readFileSync(path.join(dir, file));
    if (sha256(body) !== hash) { log(`HASH ${file}`); failures++; }
  }
  const clientFile = path.join(dir, 'client-manifest.json');
  if (!existsSync(clientFile)) { log('MISSING client-manifest.json'); failures++; } else {
    const client = JSON.parse(readFileSync(clientFile, 'utf8'));
    if (client.source_manifest_sha256 !== sha256(readFileSync(path.join(dir, 'manifest.json'), 'utf8'))) { log('HASH manifest.json'); failures++; }
  }
  const index = JSON.parse(readFileSync(path.join(dir, 'index.geojson'), 'utf8'));
  for (const feature of index.features) {
    const error = checkParcelProperties(feature.properties, range);
    if (error) { log(`INDEX ${feature.properties.block_id}: ${error}`); failures++; }
    const farm = JSON.parse(readFileSync(path.join(dir, feature.properties.farm_path), 'utf8'));
    const result = decodeFarm(farm, range);
    if (!result.ok) { log(`FARM ${feature.properties.block_id}: ${result.error}`); failures++; }
  }
  for (const file of ['index.geojson', 'buildings.geojson']) {
    if (!existsSync(path.join(dir, file))) continue;
    const features = file === 'index.geojson' ? index.features : JSON.parse(readFileSync(path.join(dir, file), 'utf8')).features;
    for (const [i, feature] of features.entries()) {
      const error = checkMapGeometry(feature.geometry);
      if (error) { log(`MAP ${file} feature ${i} (${feature.properties?.block_id}): ${error}`); failures++; }
    }
  }
  if (manifest.map_layer?.parameters) {
    const tiles = checkTiles(dir).report;
    logTileReport(tiles, log);
    failures += tiles.error_count;
  } else if (Object.keys(manifest.files).some(name => name.startsWith('tiles/')) || existsSync(path.join(dir, 'tiles'))) {
    log('TILE manifest.json has parcel tiles but no map_layer'); failures++;
  } else {
    // Datasets from before the r5 map layer (r4, C-49's GeoJSON-only r5) have no tiles to check.
    log('tiles skipped: manifest.json has no map_layer (dataset predates the parcel map layer)');
  }
  log(`${index.features.length} farms checked, ${failures} failures`);
  return failures;
}

export function logTileReport(r: TileReport, log = console.log): void {
  for (const [z, c] of Object.entries(r.zooms)) {
    log(`z${z}: ${c.tiles} tiles, ${c.unique_parcels}/${r.index_parcels} parcels, ${c.missing_count} missing${c.missing_count ? ` (${c.missing_ids.slice(0, 10).join(', ')}${c.missing_count > 10 ? ', …' : ''})` : ''}, ${c.bytes} bytes, largest ${c.max_tile_bytes}`);
  }
  for (const e of r.errors) log(`TILE ${e}`);
  if (r.error_count > r.errors.length) log(`TILE … ${r.error_count - r.errors.length} more`);
  log(`tiles ${r.ok ? 'ok' : 'FAILED'}: ${r.tile_count} tiles, ${r.error_count} errors; ${r.tilejson}`);
}

export async function main(argv: string[]): Promise<number> {
  const [command, ...rest] = argv;
  const a = args(rest);
  if (command === 'fetch') {
    const bbox = a.bbox ? a.bbox.split(',').map(Number) : null;
    if (bbox && (bbox.length !== 4 || bbox.some(v => !Number.isFinite(v)))) throw new Error('--bbox needs four numbers');
    await fetchSnapshot(need(a, 'out'), need(a, 'sources').split(','), bbox);
    return 0;
  }
  if (command === 'build') {
    const params = resolveParams(a.params ? JSON.parse(readFileSync(a.params, 'utf8')) : {});
    const snap = loadSnapshot(need(a, 'snapshot'));
    const only = a.only ? new Set(a.only.split(',')) : undefined;
    const map = resolveMapParams(a['map-params'] ? JSON.parse(readFileSync(a['map-params'], 'utf8')) : {});
    const result = buildDataset(snap, { dataset_version: need(a, 'dataset-version'), params, map, only }, console.log);
    writeDataset(need(a, 'out'), result);
    console.log(`${result.reports.length} farms, ${result.excluded.length} excluded -> ${a.out}`);
    return 0;
  }
  if (command === 'validate') {
    const range = a['core-range'] === 'current' ? CURRENT_CLIENT : RELAXED;
    return validateDataset(need(a, 'dataset'), range) === 0 ? 0 : 1;
  }
  if (command === 'check-tiles') {
    const { report, properties } = checkTiles(need(a, 'dataset'));
    logTileReport(report);
    if (a.report) writeFileSync(a.report, `${JSON.stringify(report, null, 2)}\n`);
    if (a.properties) writeFileSync(a.properties, `${JSON.stringify([...properties.values()], null, 2)}\n`);
    return report.ok ? 0 : 1;
  }
  if (command === 'tilejson') {
    const dir = need(a, 'dataset');
    const manifest = JSON.parse(readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
    const text = readFileSync(path.join(dir, TILEJSON_TEMPLATE), 'utf8');
    if (sha256(text) !== manifest.files[TILEJSON_TEMPLATE]) throw new Error(`${TILEJSON_TEMPLATE} differs from manifest.json`);
    const out = path.join(dir, 'tilejson.json');
    writeFileSync(out, `${JSON.stringify(deployTileJson(JSON.parse(text), need(a, 'base')), null, 2)}\n`);
    console.log(`${out} (not in manifest.json; pin it separately when deploying)`);
    return 0;
  }
  if (command === 'compare') {
    const dir = need(a, 'dataset');
    const out = need(a, 'out');
    mkdirSync(out, { recursive: true });
    const buildings = JSON.parse(readFileSync(path.join(dir, 'buildings.geojson'), 'utf8'));
    for (const id of need(a, 'ids').split(',')) {
      const after = JSON.parse(readFileSync(path.join(dir, 'farms', `${id}.json`), 'utf8'));
      const beforeFile = a.before ? path.join(a.before, `${id}.json`) : '';
      const before = beforeFile && existsSync(beforeFile) ? JSON.parse(readFileSync(beforeFile, 'utf8')) : null;
      const footprints: Polygon[] = buildings.features
        .filter((f: any) => f.properties.block_id === id)
        .flatMap((f: any) => (f.geometry.type === 'Polygon' ? [f.geometry.coordinates] : f.geometry.coordinates));
      writeFileSync(path.join(out, `${id}.svg`), compareSvg(after, before, footprints));
      console.log(`${id}: ${path.join(out, `${id}.svg`)}`);
    }
    return 0;
  }
  console.log(readFileSync(new URL(import.meta.url), 'utf8').split('\n').slice(1, 7).join('\n'));
  return command ? 1 : 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  main(process.argv.slice(2)).then(code => process.exit(code), error => {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
}
