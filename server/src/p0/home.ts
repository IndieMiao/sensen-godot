/**
 * Home (SGODOT-303, the server's first step): two cities the code used to call "home" alike, kept apart.
 *   - The written city: the content's profile city (San Francisco). Its ponds and outposts are the hand-written tables
 *     (fishing.places, outposts), never generated, and a bare content may lack its cluster.
 *   - The player's home: the save's travel.home. Until players choose a home every save's is the written city
 *     (upgradeState still moves any other back), so nothing plays differently yet.
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

/** Anything carrying a save's travel block (a P0State); null or without one: the written city. */
export type Homed = { travel?: { home?: string } } | null | undefined;

/** The player's home city: the save's. */
export const homeOf = (c: P0Content, s: Homed): string => s?.travel?.home || writtenCluster(c);

export interface HomeFacts {
  cluster: string;
  name: string;                               // as the HUD writes it (`San Francisco`)
  climate: string;                            // `Temperate`, as content.profile.climate
  timezone: string | undefined;               // IANA; undefined: day.utc_offset_hours applies
  farm: { lat: number; lng: number } | null;  // the homestead's map point; null without a cluster table
}

/** The player's home city's facts. */
export function homeFacts(c: P0Content, s: Homed): HomeFacts {
  const cluster = homeOf(c, s), cl = clusterById(c, cluster);
  if (cluster === writtenCluster(c)) {
    const at = c.profile.farm_at;
    return { cluster, name: c.profile.city, climate: c.profile.climate, timezone: c.profile.timezone,
      farm: at ? { lat: at[0], lng: at[1] } : cl ? { lat: cl.lat, lng: cl.lng } : null };
  }
  const z = cl?.climate;
  return { cluster, name: cl?.name ?? '', climate: z ? z[0].toUpperCase() + z.slice(1) : c.profile.climate, timezone: cl?.timezone,
    farm: cl ? { lat: cl.lat, lng: cl.lng } : null };
}
