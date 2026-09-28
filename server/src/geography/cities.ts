/**
 * 全球城市目录（SGODOT-136 B0）。
 *
 * 城市是玩家共享的单位：Nearby、城市气泡、农场时钟都按它分组。数据来自 GeoNames
 * cities15000（CC BY 4.0），由 tools/build_cities.mjs 压成 data/cities.tsv——构建时已把
 * 落在大城半径内的卫星城并掉，所以运行时只需要"找最近"。
 *
 * 上海、洛杉矶是精品城市：沿用 regions.json 的 id、placement_bounds 与人工内容，它们在
 * GeoNames 里的条目作为别名指回精品 id，老农场的 region_id 不用迁移。
 *
 * 城市归属由服务端从坐标解析，客户端传来的城市名一律不信。
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import type { FarmLocation, PlacementBounds } from '../http/farm_location.js';

export interface City {
  id: string;
  name: string;
  country_code: string;
  country: string;
  admin: string;
  center: [lat: number, lng: number];
  timezone: string;
  radius_km: number;
  population: number;
  curated: boolean;
  placement_bounds?: PlacementBounds;
}

export interface CuratedRegion {
  id: string; name?: string; timezone: string; center?: [number, number];
  placement_bounds?: PlacementBounds; geonames_id?: string; country_code?: string;
}

/** 距离 / 城市半径超过这个倍数就不算任何城市（海上、极地、荒原）。 */
export const MAX_RADIUS_RATIO = 4;
/** 选中城市后在其半径 × 该系数内选址都算这座城，免得边界附近被吸到邻城。 */
export const PLACEMENT_TOLERANCE = 1.25;

export const DEFAULT_CITIES_FILE = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', '..', 'data', 'cities.tsv');
const CELL = 1;
const EARTH_KM = 6371;

export function distanceKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const dLat = (b.lat - a.lat) * Math.PI / 180, dLng = (b.lng - a.lng) * Math.PI / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * Math.PI / 180) * Math.cos(b.lat * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

const inBounds = (b: PlacementBounds, p: FarmLocation) => p.lat >= b[0] && p.lng >= b[1] && p.lat <= b[2] && p.lng <= b[3];
const point = (c: City) => ({ lat: c.center[0], lng: c.center[1] });

export class CityCatalog {
  private byId = new Map<string, City>();
  private aliases = new Map<string, string>();
  private grid = new Map<string, City[]>();
  private curated: City[] = [];

  constructor(cities: City[], curated: CuratedRegion[] = []) {
    for (const c of cities) {
      this.byId.set(c.id, c);
      const key = this.cell(c.center[0], c.center[1]);
      if (!this.grid.has(key)) this.grid.set(key, []);
      this.grid.get(key)!.push(c);
    }
    for (const r of curated) {
      const base = r.geonames_id ? this.byId.get(r.geonames_id) : undefined;
      const city: City = {
        id: r.id, name: r.name ?? base?.name ?? r.id, country_code: r.country_code ?? base?.country_code ?? '',
        country: base?.country ?? '', admin: base?.admin ?? '',
        center: r.center ?? base?.center ?? [0, 0], timezone: r.timezone, radius_km: base?.radius_km ?? 45,
        population: base?.population ?? 0, curated: true, ...(r.placement_bounds ? { placement_bounds: r.placement_bounds } : {}),
      };
      this.byId.set(city.id, city);
      this.curated.push(city);
      if (r.geonames_id) this.aliases.set(r.geonames_id, r.id);
    }
  }

  static load(file = DEFAULT_CITIES_FILE, curated: CuratedRegion[] = []): CityCatalog {
    return new CityCatalog(parseCities(readFileSync(file, 'utf8')), curated);
  }

  static fromRegionsFile(regionsFile: string, citiesFile = DEFAULT_CITIES_FILE): CityCatalog {
    const regions = JSON.parse(readFileSync(regionsFile, 'utf8')) as { regions: CuratedRegion[] };
    return CityCatalog.load(citiesFile, regions.regions);
  }

  get size(): number { return this.byId.size; }

  get(id: string): City | null {
    const city = this.byId.get(this.aliases.get(id) ?? id);
    return city ?? null;
  }

  timezone(id: string): string { return this.get(id)?.timezone ?? 'UTC'; }

  curatedCities(): City[] { return [...this.curated]; }

  /** 坐标所在城市：精品城市边界优先，否则取"距离 / 半径"最小的城市。 */
  resolve(location: FarmLocation): City | null {
    for (const c of this.curated) if (c.placement_bounds && inBounds(c.placement_bounds, location)) return c;
    const latSpan = 2, lngSpan = Math.min(180, Math.ceil(2 / Math.max(0.1, Math.cos(location.lat * Math.PI / 180))));
    const cy = Math.floor(location.lat / CELL), cx = Math.floor(location.lng / CELL);
    let best: City | null = null, bestRatio = Infinity;
    for (let dy = -latSpan; dy <= latSpan; dy++) for (let dx = -lngSpan; dx <= lngSpan; dx++) {
      const x = ((cx + dx + 180) % 360 + 360) % 360 - 180;
      for (const c of this.grid.get(`${cy + dy}:${x}`) ?? []) {
        const ratio = distanceKm(location, point(c)) / c.radius_km;
        if (ratio < bestRatio || (ratio === bestRatio && best && c.population > best.population)) { best = c; bestRatio = ratio; }
      }
    }
    if (!best || bestRatio > MAX_RADIUS_RATIO) return null;
    return this.get(best.id);
  }

  /**
   * 选址归属。玩家已经选了某座城时，在它半径的容差内都算这座城（边界附近不会被吸到邻城）；
   * 超出容差就按坐标重新解析。精品城市严格按 placement_bounds。
   */
  forPlacement(location: FarmLocation, requestedId?: string): City | null {
    const requested = requestedId ? this.get(requestedId) : null;
    if (requested) {
      if (requested.placement_bounds) { if (inBounds(requested.placement_bounds, location)) return requested; }
      else if (distanceKm(location, point(requested)) <= requested.radius_km * PLACEMENT_TOLERANCE) return requested;
    }
    return this.resolve(location);
  }

  /** 按名字前缀搜（离线兜底；正式搜索走客户端 Mapbox 再回 resolve）。 */
  search(query: string, limit = 10): City[] {
    const q = query.trim().toLowerCase();
    if (q.length < 2) return [];
    const out: City[] = [];
    for (const c of this.byId.values()) {
      if (this.aliases.has(c.id)) continue;
      if (c.name.toLowerCase().startsWith(q)) out.push(c);
    }
    return out.sort((a, b) => Number(b.curated) - Number(a.curated) || b.population - a.population).slice(0, limit);
  }

  private cell(lat: number, lng: number) { return `${Math.floor(lat / CELL)}:${Math.floor(lng / CELL)}`; }
}

export function parseCities(text: string): City[] {
  const out: City[] = [];
  for (const line of text.split('\n')) {
    if (!line || line.startsWith('#')) continue;
    const f = line.split('\t');
    if (f.length < 10) continue;
    out.push({ id: f[0], name: f[1], center: [Number(f[2]), Number(f[3])], country_code: f[4], admin: f[5], country: f[6],
      population: Number(f[7]), timezone: f[8], radius_km: Number(f[9]), curated: false });
  }
  return out;
}

/** 客户端看到的城市。bounds 给地图框定范围：精品城市用人工边界，其余用半径外接框。 */
export function cityView(c: City, farmCount?: number) {
  const dLat = c.radius_km / 111.32, dLng = dLat / Math.max(0.1, Math.cos(c.center[0] * Math.PI / 180));
  const bounds: PlacementBounds = c.placement_bounds
    ?? [c.center[0] - dLat, c.center[1] - dLng, c.center[0] + dLat, c.center[1] + dLng];
  return {
    id: c.id, name: c.name, country_code: c.country_code, country: c.country, admin: c.admin,
    center: c.center, timezone: c.timezone, radius_km: c.radius_km, curated: c.curated, placement_bounds: bounds,
    ...(farmCount !== undefined ? { farm_count: farmCount } : {}),
  };
}
