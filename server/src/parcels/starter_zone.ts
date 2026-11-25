/**
 * 动态农场起步区（C-130）：新玩家只能在起步区里认领地块；已经认领的地块（区内区外）不受影响。
 * 来源是 assets/farm/data/dynamic_farm_starter_zone.json，由 server/tools/starter_zone_build.ts 按边界从数据集
 * index.geojson 生成：边界（真实街道中线围成的多边形）、地图默认落点，以及地块中心在边界内的地块编号和中心点。
 * 判定只看地块编号是否在清单里（客户端报的中心点改不了结果），区内认领存清单里的中心点。
 * 一个社区最多一个起步区；没有起步区的社区不限制。整体开关：文件里的 enabled，可被环境变量
 * PARCEL_STARTER_ZONE=0/1 覆盖。文件不合法时抛错，进程不启动，免得悄悄放开或全拒。
 * 它不在 content_version 的指纹里，改它不影响存档。
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';

export const STARTER_ZONE_FILE = 'dynamic_farm_starter_zone.json';
/** 与 routes.ts 的 PARCEL_ID_RE 一致（这里单独写一份，避免两个模块互相引用）。 */
const PARCEL_ID_RE = /^p-[A-Za-z0-9_*-]{1,98}$/;
const ID_RE = /^[a-z0-9_-]{1,64}$/;
/** 一个起步区的地块上限：起步区本来就是一小片，再多说明边界画错了。 */
export const MAX_ZONE_PARCELS = 5000;
const MAX_BOUNDARY_POINTS = 512;

export type LngLat = [number, number];
export interface StarterZone {
  id: string;
  community_id: string;
  name: string;
  /** 生成清单所用的数据集；只是记录，判定按社区，不按数据集。 */
  dataset_version: string;
  /** 闭合环，GeoJSON 顺序 [lng, lat]，首尾相同。 */
  boundary: LngLat[];
  /** 没有家园的玩家进地图时的落点和缩放。 */
  center: LngLat;
  zoom: number;
  /** 地块编号 → 地块中心 [lng, lat]。 */
  parcels: Map<string, LngLat>;
}
export interface StarterZones {
  enabled: boolean;
  zones: StarterZone[];
}

const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const isPoint = (v: unknown): v is LngLat =>
  Array.isArray(v) && v.length === 2 && isNum(v[0]) && isNum(v[1]) && Math.abs(v[0]) <= 180 && Math.abs(v[1]) <= 85;

/** 不合法就抛错（启动时发现）。 */
export function parseStarterZones(raw: unknown): StarterZones {
  const fail = (what: string): never => { throw new Error(`${STARTER_ZONE_FILE}: ${what}`); };
  const r = raw as { version?: unknown; enabled?: unknown; zones?: unknown } | null;
  if (!r || typeof r !== 'object' || r.version !== 1) fail('version 必须为 1');
  if (typeof r!.enabled !== 'boolean') fail('enabled 必须是 true 或 false');
  if (!Array.isArray(r!.zones)) fail('zones 必须是数组');
  const zones: StarterZone[] = [];
  const communities = new Set<string>();
  for (const z of r!.zones as Record<string, unknown>[]) {
    if (!z || typeof z !== 'object') fail('起步区格式不对');
    const id = z.id, community = z.community_id;
    if (typeof id !== 'string' || !ID_RE.test(id)) fail('起步区 id 不对');
    if (typeof community !== 'string' || !ID_RE.test(community)) fail(`${id}: community_id 不对`);
    if (communities.has(community as string)) fail(`社区 ${community} 有多个起步区`);
    communities.add(community as string);
    if (typeof z.name !== 'string' || !z.name.trim() || z.name.length > 80) fail(`${id}: name 不对`);
    if (typeof z.dataset_version !== 'string' || !ID_RE.test(z.dataset_version)) fail(`${id}: dataset_version 不对`);
    const ring = z.boundary;
    if (!Array.isArray(ring) || ring.length < 4 || ring.length > MAX_BOUNDARY_POINTS || !ring.every(isPoint)) fail(`${id}: boundary 不对`);
    const first = (ring as LngLat[])[0], last = (ring as LngLat[])[(ring as LngLat[]).length - 1];
    if (first[0] !== last[0] || first[1] !== last[1]) fail(`${id}: boundary 必须首尾相同`);
    if (!isPoint(z.center)) fail(`${id}: center 不对`);
    if (!isNum(z.zoom) || z.zoom < 13 || z.zoom > 21) fail(`${id}: zoom 必须在 13–21`);
    if (!z.parcels || typeof z.parcels !== 'object' || Array.isArray(z.parcels)) fail(`${id}: parcels 必须是对象`);
    const entries = Object.entries(z.parcels as Record<string, unknown>);
    if (!entries.length || entries.length > MAX_ZONE_PARCELS) fail(`${id}: parcels 数量不对`);
    const parcels = new Map<string, LngLat>();
    for (const [parcel, center] of entries) {
      if (!PARCEL_ID_RE.test(parcel) || !isPoint(center)) fail(`${id}: 地块 ${parcel} 不对`);
      parcels.set(parcel, [(center as LngLat)[0], (center as LngLat)[1]]);
    }
    zones.push({ id: id as string, community_id: community as string, name: (z.name as string).trim(), dataset_version: z.dataset_version as string,
      boundary: (ring as LngLat[]).map(p => [p[0], p[1]] as LngLat), center: [(z.center as LngLat)[0], (z.center as LngLat)[1]], zoom: z.zoom as number, parcels });
  }
  return { enabled: r!.enabled as boolean, zones };
}

/** PARCEL_STARTER_ZONE：不设或空按文件；0 关、1 开；其它值返回 null，进程拒绝启动，免得拼错后悄悄放开。 */
export function starterZoneSwitchFromEnv(env: Record<string, string | undefined>): boolean | 'file' | null {
  const raw = env.PARCEL_STARTER_ZONE ?? '';
  return raw === '' ? 'file' : raw === '1' ? true : raw === '0' ? false : null;
}

export function loadStarterZones(contentDir: string, override: boolean | 'file' = 'file'): StarterZones {
  const zones = parseStarterZones(JSON.parse(readFileSync(path.join(contentDir, STARTER_ZONE_FILE), 'utf8')));
  return override === 'file' ? zones : { ...zones, enabled: override };
}

/** 社区当前生效的起步区；整体关闭或该社区没有起步区时返回 null（不限制）。 */
export function activeZone(zones: StarterZones | undefined, communityId: string): StarterZone | null {
  if (!zones?.enabled) return null;
  return zones.zones.find(z => z.community_id === communityId) ?? null;
}

/** 给地图的公开描述：边界、落点和区内地块编号（地块编号本来就在公开数据集里）。 */
export const zoneView = (z: StarterZone) => ({
  id: z.id, community_id: z.community_id, name: z.name, dataset_version: z.dataset_version,
  boundary: z.boundary, center: z.center, zoom: z.zoom, parcel_ids: [...z.parcels.keys()].sort(),
});

/** 射线法：点是否在多边形内（边界上的点归属不保证；生成工具只用地块中心，不会恰好落在街道中线上）。 */
export function pointInRing(point: LngLat, ring: LngLat[]): boolean {
  const [x, y] = point;
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i], [xj, yj] = ring[j];
    if ((yi > y) !== (yj > y) && x < xi + (y - yi) * (xj - xi) / (yj - yi)) inside = !inside;
  }
  return inside;
}
