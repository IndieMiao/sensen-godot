/**
 * P0 city clusters (SGODOT-275, plan v2 §11.1; 亚瑟's cross-city plan §1 on the 275 card): the unit stamps, passes
 * and visits are keyed by. assets/p0/city_clusters.json (one row per cluster, shared with the client) and
 * server/data/city_cluster_members.tsv (city id → cluster id) are built by server/tools/build_clusters.mjs and frozen.
 * Pure lookups: trip tiers (§11.2.1), the fallback lists (§11.2.3) and coordinate → cluster for generation.
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export type Climate = 'tropical' | 'subtropical' | 'temperate' | 'cool';
export type Continent = 'asia' | 'europe' | 'africa' | 'north_america' | 'south_america' | 'oceania';
export interface CityCluster {
  id: string; name: string; lat: number; lng: number; country_code: string; country: string;
  population: number; members: number; climate: Climate; continent: Continent; timezone: string;
}
export interface Point { lat: number; lng: number }

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
export const DEFAULT_CLUSTERS = path.join(ROOT, 'assets/p0/city_clusters.json');
export const DEFAULT_MEMBERS = path.join(ROOT, 'server/data/city_cluster_members.tsv');

/** Trip 1–7 distance bounds in km (§11.2.1): Trip n is ≤ BOUNDS[n-1]; beyond the last is Trip 7. */
export const TRIP_KM = [30, 100, 500, 1600, 4000, 10000] as const;
export const TRIP_NAMES = ['Local', 'Nearby', 'Regional', 'Long Haul', 'Continental', 'Intercontinental', 'Antipodal'] as const;
/** §11.2.3: the fallback lists count clusters of at least this population outside the home cluster. */
export const FALLBACK_MIN_POP = 100_000;

export function distanceKm(a: Point, b: Point): number {
  const rad = Math.PI / 180, dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Trip tier by distance alone, 1–7 (§11.2.1). */
export function tripByKm(km: number): number {
  const i = TRIP_KM.findIndex(b => km <= b);
  return i < 0 ? 7 : i + 1;
}

const tsv = (file: string) => readFileSync(file, 'utf8').split('\n').filter(l => l && !l.startsWith('#')).map(l => l.split('\t'));

export class CityClusters {
  readonly byId = new Map<string, CityCluster>();
  private member = new Map<string, string>();

  constructor(clusters: CityCluster[], members: [string, string][]) {
    for (const c of clusters) this.byId.set(c.id, c);
    for (const [city, cluster] of members) this.member.set(city, cluster);
  }

  static load(clusters = DEFAULT_CLUSTERS, members = DEFAULT_MEMBERS): CityClusters {
    const table = JSON.parse(readFileSync(clusters, 'utf8')) as { fields: string[]; rows: unknown[][] };
    const at = (name: string) => table.fields.indexOf(name);
    const [id, name, lat, lng, cc, country, pop, n, climate, continent, tz] =
      ['id', 'name', 'lat', 'lng', 'country_code', 'country', 'population', 'members', 'climate', 'continent', 'timezone'].map(at);
    return new CityClusters(table.rows.map(r => ({
      id: r[id] as string, name: r[name] as string, lat: r[lat] as number, lng: r[lng] as number, country_code: r[cc] as string,
      country: r[country] as string, population: r[pop] as number, members: r[n] as number, climate: r[climate] as Climate,
      continent: r[continent] as Continent, timezone: r[tz] as string,
    })), tsv(members).map(f => [f[0], f[1]] as [string, string]));
  }

  get(id: string): CityCluster | undefined { return this.byId.get(id); }
  /** The cluster a directory city (GeoNames id, e.g. a curated region's geonames_id) belongs to. */
  ofCity(cityId: string): string | undefined { return this.member.get(cityId); }

  /**
   * §11.2.3 fallback lists from the home farm's point: the nearest 3 and 10 clusters of ≥ 100,000 people outside the
   * home cluster, nearest first (ties by id). Computed when the save is made and frozen there.
   */
  fallback(home: string, farm: Point): { near3: string[]; near10: string[] } {
    const near = [...this.byId.values()]
      .filter(c => c.id !== home && c.population >= FALLBACK_MIN_POP)
      .map(c => ({ id: c.id, km: distanceKm(farm, c) }))
      .sort((a, b) => a.km - b.km || (a.id < b.id ? -1 : 1))
      .slice(0, 10).map(c => c.id);
    return { near3: near.slice(0, 3), near10: near };
  }

  /**
   * Every cluster of ≥ minPop people outside home with its distance from the farm and its trip tier as trip() gives it
   * (fallback included), nearest first (ties by id): the pool the cross-city requests draw their city from (SGODOT-284,
   * 亚瑟: the same TRIP_KM bounds as tripOf and the travel preview). The caller caches it per home.
   */
  ranked(home: string, farm: Point, fallback: { near3: string[]; near10: string[] }, minPop = FALLBACK_MIN_POP): { id: string; km: number; trip: number }[] {
    return [...this.byId.values()]
      .filter(c => c.id !== home && c.population >= minPop)
      .map(c => {
        const km = distanceKm(farm, c);
        let trip = tripByKm(km);
        if (fallback.near3.includes(c.id)) trip = 1;
        else if (fallback.near10.includes(c.id)) trip = Math.min(trip, 2);
        return { id: c.id, km, trip };
      })
      .sort((a, b) => a.km - b.km || (a.id < b.id ? -1 : 1));
  }

  /**
   * The trip tier to a cluster from the home farm (§11.2.1 + §11.2.3): by distance, then the lower of that and the
   * fallback tier (nearest 3 → Trip 1, nearest 10 → at most Trip 2). The home cluster is Trip 1.
   */
  trip(to: string, home: string, farm: Point, fallback: { near3: string[]; near10: string[] }): { km: number; trip: number; name: string } {
    const c = this.byId.get(to);
    if (!c) throw new Error(`unknown city cluster ${to}`);
    const km = to === home ? 0 : distanceKm(farm, c);
    let trip = to === home ? 1 : tripByKm(km);
    if (fallback.near3.includes(to)) trip = 1;
    else if (fallback.near10.includes(to)) trip = Math.min(trip, 2);
    return { km: Math.round(km), trip, name: TRIP_NAMES[trip - 1] };
  }
}
