/**
 * fetch    --out <snapshot> --sources <label,...> [--bbox minLon,minLat,maxLon,maxLat]
 * build    --snapshot <snapshot> --out <dataset> --dataset-version <v> [--params <json>] [--only p-1,p-2]
 * validate --dataset <dataset> [--core-range current|relaxed]
 * compare  --dataset <dataset> --out <dir> --ids p-1,p-2 [--before <dir with older farms/*.json>]
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { compareSvg } from './compare.js';
import { resolveParams } from './config.js';
import { buildDataset, writeDataset } from './dataset.js';
import type { Polygon } from './geo.js';
import { loadSnapshot } from './snapshot.js';
import { fetchSnapshot, sha256 } from './sources.js';
import { checkParcelProperties, CURRENT_CLIENT, decodeFarm, RELAXED } from './validate.js';

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

/** Validates every farm and index feature of a written dataset; returns the number of failures. */
export function validateDataset(dir: string, range = RELAXED, log = console.log): number {
  const manifest = JSON.parse(readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
  let failures = 0;
  for (const [file, hash] of Object.entries(manifest.files as Record<string, string>)) {
    const body = readFileSync(path.join(dir, file), 'utf8');
    if (sha256(body) !== hash) { log(`HASH ${file}`); failures++; }
  }
  const client = JSON.parse(readFileSync(path.join(dir, 'client-manifest.json'), 'utf8'));
  if (client.source_manifest_sha256 !== sha256(readFileSync(path.join(dir, 'manifest.json'), 'utf8'))) { log('HASH manifest.json'); failures++; }
  const index = JSON.parse(readFileSync(path.join(dir, 'index.geojson'), 'utf8'));
  for (const feature of index.features) {
    const error = checkParcelProperties(feature.properties, range);
    if (error) { log(`INDEX ${feature.properties.block_id}: ${error}`); failures++; }
    const farm = JSON.parse(readFileSync(path.join(dir, feature.properties.farm_path), 'utf8'));
    const result = decodeFarm(farm, range);
    if (!result.ok) { log(`FARM ${feature.properties.block_id}: ${result.error}`); failures++; }
  }
  log(`${index.features.length} farms checked, ${failures} failures`);
  return failures;
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
    const result = buildDataset(snap, { dataset_version: need(a, 'dataset-version'), params, only }, console.log);
    writeDataset(need(a, 'out'), result);
    console.log(`${result.reports.length} farms, ${result.excluded.length} excluded -> ${a.out}`);
    return 0;
  }
  if (command === 'validate') {
    const range = a['core-range'] === 'current' ? CURRENT_CLIENT : RELAXED;
    return validateDataset(need(a, 'dataset'), range) === 0 ? 0 : 1;
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
  console.log(readFileSync(new URL(import.meta.url), 'utf8').split('\n').slice(1, 5).join('\n'));
  return command ? 1 : 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  main(process.argv.slice(2)).then(code => process.exit(code), error => {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
}
