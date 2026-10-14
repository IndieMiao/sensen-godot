/**
 * Home (SGODOT-303, the server's first step): two cities the code used to call "home" alike, kept apart.
 *   - The written city: the content's profile city (San Francisco). Its ponds and outposts are the hand-written tables
 *     (fishing.places, outposts), never generated, and a bare content may lack its cluster.
 *   - The player's home: the save's travel.home, picked by choose_home (home_city.ts); a save that never picked one
 *     (every save before SGODOT-303) is the written city's, farming at content.profile.farm_at (q(163) ③).
 * A home's facts (name, climate, time zone, farm point) are content.profile's for the written city, as they always were,
 * and its cluster's for any other.
 */
import type { CityCluster, CityClusters } from './clusters.js';
import type { P0Content } from './content.js';

/** The written cities' old names (regions.json) → cluster ids, for names saves and places used before v5. */
export const HOME_ALIAS: Record<string, string> = { 'san francisco': 'gn-5391959', shanghai: 'gn-1796236', 'los angeles': 'gn-5368361' };

/** The frozen city clusters (亚瑟's CityClusters, assets/p0/city_clusters.json), attached by loadP0Content. */
export const clustersOf = (c: P0Content): CityClusters | undefined => (c as P0Content & { clusters?: CityClusters }).clusters;
export const clusterById = (c: P0Content, id: string): CityCluster | undefined => clustersOf(c)?.get(id);

/** The written city's cluster (the content's profile city, regions.json alias → gn- id). */
export const writtenCluster = (c: P0Content): string => HOME_ALIAS[c.profile.city.toLowerCase()] ?? `city:${c.profile.city.toLowerCase()}`;

/** A home's set (q(163) ①, §9.3.2 家一套): its first market, tea house, tackle shop and travel post, and its beginner pond. */
export interface HomeSet { market: string; tea: string; tackle: string; post: string; pond: string }

/** Anything carrying a save's travel block (a P0State); null or without one: the written city. */
export type Homed = { travel?: { home?: string; farm_at?: [number, number]; home_set?: HomeSet; day_hold?: DayHold } } | null | undefined;

/** q(173): the day a changed home carries over — its key, from the instant it began on the old clock until the first
 * 04:00 of the new home after the old one's end and on a later date. */
export interface DayHold { key: string; start: number; until: number }

/** The player's home city: the save's. */
export const homeOf = (c: P0Content, s: Homed): string => s?.travel?.home || writtenCluster(c);

export interface HomeFacts {
  cluster: string;
  name: string;                               // as the HUD writes it (`San Francisco`)
  climate: string;                            // `Temperate`, as content.profile.climate
  timezone: string | undefined;               // IANA; undefined: day.utc_offset_hours applies
  farm: { lat: number; lng: number } | null;  // the homestead's map point; null without a cluster table
}

/** The home's base point (q(184)): what Trip distances, tiers and the nearest 3 / 10 fallback are measured from, the
 * same for every player of a city — the written city's content point, another city's centre. The picked farm point
 * places only the home pin. */
export const homeBase = (c: P0Content, s: Homed): { lat: number; lng: number } | null =>
  homeFacts(c, { travel: { home: homeOf(c, s) } }).farm;

/** The player's home city's facts. The farm point is the picked spot (travel.farm_at), else the written one or the centre. */
export function homeFacts(c: P0Content, s: Homed): HomeFacts {
  const cluster = homeOf(c, s), cl = clusterById(c, cluster), picked = s?.travel?.farm_at;
  if (cluster === writtenCluster(c)) {
    const at = picked ?? c.profile.farm_at;
    return { cluster, name: c.profile.city, climate: c.profile.climate, timezone: c.profile.timezone,
      farm: at ? { lat: at[0], lng: at[1] } : cl ? { lat: cl.lat, lng: cl.lng } : null };
  }
  const z = cl?.climate;
  return { cluster, name: cl?.name ?? '', climate: z ? z[0].toUpperCase() + z.slice(1) : c.profile.climate, timezone: cl?.timezone,
    farm: picked ? { lat: picked[0], lng: picked[1] } : cl ? { lat: cl.lat, lng: cl.lng } : null };
}
