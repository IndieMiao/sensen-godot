/**
 * Cross-city travel state (P1, SGODOT-275; gameplay plan v2 §11, P2 first version: travel is free). Save v5 adds it.
 * Field names are provisional until 亚瑟's cross-city technical note (city cluster key, pass protocol) lands.
 */
import type { P0Content } from './content.js';

export interface TravelVisit { first_at: number; visits: number }
export interface TravelState {
  home: string;                              // home city cluster (always explored, always covered by a pass)
  at: string;                                // the cluster the player is in now
  visited: Record<string, TravelVisit>;      // clusters reached by travel, home not included
  stamps: string[];                          // city stamps, one per cluster, in first-visit order (§11.9.3)
  pass: { city: string; until: number } | null;   // the Day Pass for `at` when it is not home (§11.5.1)
}

/** The home cluster id of this content's profile. Provisional: the region key until the cluster key is fixed. */
export const homeCluster = (c: P0Content): string => (c.profile as { region?: string }).region ?? c.profile.city.toLowerCase();

export const freshTravel = (c: P0Content): TravelState => {
  const home = homeCluster(c);
  return { home, at: home, visited: {}, stamps: [], pass: null };
};
