/** Overpass 一次性抓取 + 本地缓存。缓存文件入库，之后构建不联网。 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { EnvHttpProxyAgent, setGlobalDispatcher } from 'undici';

export const OVERPASS_URL = 'https://overpass-api.de/api/interpreter';
export const HIGHWAY_RE =
  'primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|residential|unclassified|living_street|pedestrian';
const M_PER_DEG_LAT = 111319.4908;

export interface OverpassElement {
  type: string; id: number; lat?: number; lon?: number; nodes?: number[]; tags?: Record<string, string>;
}
export interface OverpassJson { elements: OverpassElement[] }
export interface Way { id: number; highway: string; coords: [number, number][] } // [lat, lng]

export function bbox(lat: number, lng: number, radiusM: number): [number, number, number, number] {
  const dlat = radiusM / M_PER_DEG_LAT;
  const dlng = radiusM / (M_PER_DEG_LAT * Math.cos((lat * Math.PI) / 180));
  return [lat - dlat, lng - dlng, lat + dlat, lng + dlng];
}

export function buildQuery(lat: number, lng: number, radiusM: number): string {
  const [s, w, n, e] = bbox(lat, lng, radiusM);
  return `[out:json][timeout:60];way["highway"~"^(${HIGHWAY_RE})$"]` +
    `(${s.toFixed(6)},${w.toFixed(6)},${n.toFixed(6)},${e.toFixed(6)});(._;>;);out body;`;
}

let proxyInstalled = false;
function installEnvProxy(): void {
  if (proxyInstalled) return;
  proxyInstalled = true;
  if (process.env.https_proxy || process.env.HTTPS_PROXY) setGlobalDispatcher(new EnvHttpProxyAgent());
}

export async function fetchOverpass(lat: number, lng: number, radiusM: number, cachePath: string): Promise<OverpassJson> {
  if (existsSync(cachePath)) return JSON.parse(readFileSync(cachePath, 'utf8')) as OverpassJson;
  installEnvProxy();
  // Overpass 的 Apache 前端在走本机代理时会对 undici 默认请求头返回 406；显式带上
  // User-Agent/Accept（等价于 curl 的默认行为）即可通过，与业务逻辑无关，纯粹是客户端兼容性修复。
  const res = await fetch(OVERPASS_URL, {
    method: 'POST',
    headers: { 'User-Agent': 'geo_blueprint/0.1 (sensen-godot)', Accept: '*/*' },
    body: new URLSearchParams({ data: buildQuery(lat, lng, radiusM) }),
  });
  if (!res.ok) throw new Error(`overpass HTTP ${res.status}`);
  const data = (await res.json()) as OverpassJson;
  mkdirSync(path.dirname(cachePath), { recursive: true });
  writeFileSync(cachePath, JSON.stringify(data, null, 1));
  return data;
}

export function parseWays(data: OverpassJson): Way[] {
  const nodes = new Map<number, [number, number]>();
  for (const el of data.elements) if (el.type === 'node' && el.lat !== undefined && el.lon !== undefined) nodes.set(el.id, [el.lat, el.lon]);
  const ways: Way[] = [];
  for (const el of data.elements) {
    if (el.type !== 'way') continue;
    const coords = (el.nodes ?? []).map(n => nodes.get(n)).filter((c): c is [number, number] => !!c);
    if (coords.length >= 2) ways.push({ id: el.id, highway: el.tags?.highway ?? '', coords });
  }
  return ways;
}
