/**
 * 生成动态农场起步区配置（C-130）：assets/farm/data/dynamic_farm_starter_zone.json。
 * 按边界（真实街道中线围成的闭合多边形，[lng,lat]）从数据集 index.geojson 挑出地块中心在边界内的地块，
 * 连同边界、默认落点写进配置。扩大起步区 = 换更大的边界重跑；关掉 = 把 enabled 改成 false（或部署时设
 * PARCEL_STARTER_ZONE=0）。地块数据集本身不改。
 * 其中核心格（core_cell_count）少于 min_core_cells 的地块记进 too_small，服务端不让认领（C-143）；下限默认取客户端
 * modules/dynamic_farm/map/config.json 的 min_core_cells，与客户端同一口径。
 *
 *   pnpm --dir server exec tsx tools/starter_zone_build.ts --index <index.geojson> --dataset <dataset_version> \
 *     --id sf-starter --name "San Francisco starter area" --community sf --boundary '[[lng,lat],...]' --center lng,lat --zoom 17 \
 *     [--min-core-cells 400] [--enabled true|false] [--out ../assets/farm/data/dynamic_farm_starter_zone.json]
 */
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { parseStarterZones, pointInRing, STARTER_ZONE_FILE, type LngLat } from '../src/parcels/starter_zone.js';

interface IndexFeature { properties: { block_id?: unknown; center_lon?: unknown; center_lat?: unknown; core_cell_count?: unknown } }

const REPO = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', '..');
/** 客户端地图配置：它的 min_core_cells 决定哪块地太小、不给认领键。 */
export const CLIENT_MAP_CONFIG = path.join(REPO, 'modules', 'dynamic_farm', 'map', 'config.json');

/** 地块中心在边界内的地块：编号 → 中心；其中核心格少于 minCoreCells 的编号进 too_small。都按编号排序（输出稳定）。
 * 区内地块缺核心格数时抛错：判定不了就不生成。 */
export function zoneParcels(features: IndexFeature[], boundary: LngLat[], minCoreCells: number): { parcels: Record<string, LngLat>; too_small: string[] } {
  const rows: [string, LngLat][] = [];
  const tooSmall: string[] = [];
  for (const f of features) {
    const { block_id: id, center_lon: lng, center_lat: lat, core_cell_count: core } = f.properties ?? {};
    if (typeof id !== 'string' || typeof lng !== 'number' || typeof lat !== 'number') continue;
    if (!pointInRing([lng, lat], boundary)) continue;
    if (typeof core !== 'number' || !Number.isFinite(core)) throw new Error(`地块 ${id} 没有核心格数（core_cell_count）`);
    rows.push([id, [lng, lat]]);
    if (core < minCoreCells) tooSmall.push(id);
  }
  const byId = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
  rows.sort((a, b) => byId(a[0], b[0]));
  return { parcels: Object.fromEntries(rows), too_small: tooSmall.sort(byId) };
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
  const minCoreCells = Number(args.get('min-core-cells') ?? (JSON.parse(readFileSync(CLIENT_MAP_CONFIG, 'utf8')) as { min_core_cells?: unknown }).min_core_cells);
  const { parcels, too_small } = zoneParcels(index.features, boundary, minCoreCells);
  const zone = {
    id: need('id'), community_id: need('community'), name: need('name'), dataset_version: need('dataset'),
    boundary, center, zoom: Number(need('zoom')), min_core_cells: minCoreCells, parcels, too_small,
  };
  const file = { version: 1, enabled: (args.get('enabled') ?? 'true') === 'true', zones: [zone] };
  parseStarterZones(file); // Same checks as the server's start-up.
  const out = args.get('out') ?? path.join(REPO, 'assets', 'farm', 'data', STARTER_ZONE_FILE);
  // One point per line: [lng, lat] pairs on a single line keep the file short and its diffs readable.
  const text = JSON.stringify(file, null, 1).replace(/\[\s+(-?[\d.e-]+),\s+(-?[\d.e-]+)\s+\]/g, '[$1, $2]');
  writeFileSync(out, `${text}\n`);
  console.log(`${out}: ${zone.id} ${Object.keys(parcels).length} parcels, ${too_small.length} too small (core < ${minCoreCells})`);
}

if (import.meta.url === `file://${process.argv[1]}`) main(process.argv.slice(2));
