/**
 * 生成动态农场起步区配置（C-130）：assets/farm/data/dynamic_farm_starter_zone.json。
 * 按边界（真实街道中线围成的闭合多边形，[lng,lat]）从数据集 index.geojson 挑出地块中心在边界内的地块，
 * 连同边界、默认落点写进配置。扩大起步区 = 换更大的边界重跑；关掉 = 把 enabled 改成 false（或部署时设
 * PARCEL_STARTER_ZONE=0）。地块数据集本身不改。
 *
 *   pnpm --dir server exec tsx tools/starter_zone_build.ts --index <index.geojson> --dataset <dataset_version> \
 *     --id north-beach --name "North Beach" --community sf --boundary '[[lng,lat],...]' --center lng,lat --zoom 17 \
 *     [--enabled true|false] [--out ../assets/farm/data/dynamic_farm_starter_zone.json]
 */
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { parseStarterZones, pointInRing, STARTER_ZONE_FILE, type LngLat } from '../src/parcels/starter_zone.js';

interface IndexFeature { properties: { block_id?: unknown; center_lon?: unknown; center_lat?: unknown } }

/** 地块中心在边界内的地块：编号 → 中心，按编号排序（输出稳定）。 */
export function zoneParcels(features: IndexFeature[], boundary: LngLat[]): Record<string, LngLat> {
  const rows: [string, LngLat][] = [];
  for (const f of features) {
    const { block_id: id, center_lon: lng, center_lat: lat } = f.properties ?? {};
    if (typeof id !== 'string' || typeof lng !== 'number' || typeof lat !== 'number') continue;
    if (pointInRing([lng, lat], boundary)) rows.push([id, [lng, lat]]);
  }
  rows.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  return Object.fromEntries(rows);
}

function main(argv: string[]): void {
  const args = new Map<string, string>();
  for (let i = 0; i < argv.length; i += 2) {
    if (!argv[i].startsWith('--') || argv[i + 1] === undefined) throw new Error(`参数不对：${argv[i]}`);
    args.set(argv[i].slice(2), argv[i + 1]);
  }
  const need = (k: string) => { const v = args.get(k); if (!v) throw new Error(`缺少 --${k}`); return v; };
  const index = JSON.parse(readFileSync(need('index'), 'utf8')) as { features: IndexFeature[] };
  const boundary = JSON.parse(need('boundary')) as LngLat[];
  const center = need('center').split(',').map(Number) as LngLat;
  const zone = {
    id: need('id'), community_id: need('community'), name: need('name'), dataset_version: need('dataset'),
    boundary, center, zoom: Number(need('zoom')), parcels: zoneParcels(index.features, boundary),
  };
  const file = { version: 1, enabled: (args.get('enabled') ?? 'true') === 'true', zones: [zone] };
  parseStarterZones(file); // Same checks as the server's start-up.
  const out = args.get('out') ?? path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', '..', 'assets', 'farm', 'data', STARTER_ZONE_FILE);
  // One point per line: [lng, lat] pairs on a single line keep the file short and its diffs readable.
  const text = JSON.stringify(file, null, 1).replace(/\[\s+(-?[\d.e-]+),\s+(-?[\d.e-]+)\s+\]/g, '[$1, $2]');
  writeFileSync(out, `${text}\n`);
  console.log(`${out}: ${zone.id} ${Object.keys(zone.parcels).length} parcels`);
}

if (import.meta.url === `file://${process.argv[1]}`) main(process.argv.slice(2));
