/**
 * Cross-city travel (P1, SGODOT-275 / 278; gameplay plan v2 §11, the P2 first version: travel is free and instant).
 * Save v5 adds the travel block; the shape and the error codes follow 亚瑟's technical note (275, comment 0fc0bc5e):
 * every key is a city cluster id (`gn-<GeoNames id>` of the cluster's seed city, San Francisco gn-5391959).
 */
import type { CityClusters, CityCluster } from './clusters.js';
import type { P0Content } from './content.js';
import { gainEnergy, grantOnce, type P0Event } from './progress.js';
import { dayKey, maxEnergy } from './rules.js';
import type { P0State } from './state.js';

export interface TravelPass { kind: 'day'; from: number; until: number }
export interface TravelVisit { n: number; first_at: number; last_at: number; deliveries: number; delivered_day: string }
export interface TravelStamp { cluster: string; kind: 'landmark' | 'climate'; at: number; counted_on: string }
export interface TravelState {
  home: string;                                  // home cluster; the first version: San Francisco for everyone
  here: string;                                  // the cluster the player is in; travel sets it, return_home resets it
  passes: Record<string, TravelPass>;            // Day Passes; home is covered without one
  visits: Record<string, TravelVisit>;           // per cluster reached by travel (home not included)
  stamps: TravelStamp[];                         // first-visit order
  fallback: { near3: string[]; near10: string[] };   // frozen when the block is made (§11.2.3); empty until clusters load
  explorer: number;                              // the highest Explorer medal granted: 0 / 3 / 10 / 30 / 100
}

export const HOME_ALIAS: Record<string, string> = { 'san francisco': 'gn-5391959', shanghai: 'gn-1796236', 'los angeles': 'gn-5368361' };
const DAY_PASS_MS = 24 * 3_600_000;
const FIRST_VISIT_ENERGY = 10;
const FIRST_VISITS_PER_DAY = 2;
const EXPLORER: [number, number][] = [[3, 30], [10, 50], [30, 70], [100, 100]];

type WithClusters = P0Content & { clusters?: CityClusters; landmarks?: Record<string, string> };

/** The frozen city clusters (亚瑟's CityClusters, assets/p0/city_clusters.json), attached by loadP0Content. */
const clusters = (c: P0Content) => (c as WithClusters).clusters;
export const clusterById = (c: P0Content, id: string): CityCluster | undefined => clusters(c)?.get(id);

/** The home cluster of this content's profile (regions.json alias → gn- id). */
export const homeCluster = (c: P0Content): string => HOME_ALIAS[c.profile.city.toLowerCase()] ?? `city:${c.profile.city.toLowerCase()}`;

/** A city name a save or a place used before v5 (`san francisco`) → its cluster. */
export const clusterOfCityName = (c: P0Content, city: string): string | null => {
  const k = city.toLowerCase();
  if (HOME_ALIAS[k]) return HOME_ALIAS[k];
  for (const cl of clusters(c)?.byId.values() ?? []) if (cl.name.toLowerCase() === k) return cl.id;
  return null;
};

/** Which cluster a place is in (§4 of the note): generated ids carry it (`gn-1850147~pond0`), the hand-written San
 * Francisco places have a `cluster` field, or (until that lands) their old city name. Null: not a place we know. */
export function clusterOf(c: P0Content, place: string): string | null {
  const cut = place.indexOf('~');
  if (cut > 0) return place.slice(0, cut);
  const pond = c.fishing.places[place] as { cluster?: string; city?: string } | undefined;
  const outpost = c.outposts?.find(o => o.id === place) as { cluster?: string } | undefined;
  const known = pond ?? outpost;
  if (!known) return null;
  if (known.cluster) return known.cluster;
  if (pond?.city) return clusterOfCityName(c, pond.city);
  return homeCluster(c);   // a hand-written outpost without its cluster field yet: the home city's
}

function farmPoint(c: P0Content): { lat: number; lng: number } | null {
  if (c.profile.farm_at) return { lat: c.profile.farm_at[0], lng: c.profile.farm_at[1] };
  const h = clusterById(c, homeCluster(c));
  return h ? { lat: h.lat, lng: h.lng } : null;
}

/** §11.2.3: frozen into the save when the block is made (CityClusters.fallback); empty without the table. */
export function fallbackOf(c: P0Content): { near3: string[]; near10: string[] } {
  const at = farmPoint(c), cl = clusters(c);
  return at && cl ? cl.fallback(homeCluster(c), at) : { near3: [], near10: [] };
}

export const freshTravel = (c: P0Content): TravelState => {
  const home = homeCluster(c);
  return { home, here: home, passes: {}, visits: {}, stamps: [], fallback: fallbackOf(c), explorer: 0 };
};

/** Distance from the home farm and the Trip band, by CityClusters.trip (the same rule as the client's P0Clusters). */
export function tripOf(c: P0Content, s: P0State, cluster: string): { km: number; trip: number; name: string } {
  const at = farmPoint(c), cl = clusters(c);
  if (!at || !cl?.get(cluster)) return { km: 0, trip: 1, name: 'Local' };
  return cl.trip(cluster, s.travel.home, at, s.travel.fallback);
}

/** Home is always covered; elsewhere a Day Pass still running (second home and guest passes come later). */
export const covers = (s: P0State, cluster: string, now: number): boolean =>
  cluster === s.travel.home || (s.travel.passes[cluster]?.until ?? 0) > now;

/** What the confirm panel needs (§11.8.2). Costs stay 0 in the first version; the fields are there for the paid one. */
export function preview(c: P0Content, s: P0State, cluster: string) {
  const cl = clusterById(c, cluster);
  const { km: d, trip, name: tripName } = tripOf(c, s, cluster);
  const info = cityInfo(c, cluster);
  return { cluster, name: cl?.name ?? '', country: cl?.country ?? '', km: d, trip, trip_name: tripName,
    cost: { energy: 0, coins: 0, item: null }, first_visit: !s.travel.visits[cluster],
    fishing: info.fish, counts: { ponds: info.ponds.length, outposts: info.outposts.length, residents: info.residents } };
}

/** A city's places for GET /v1/p0/city/:cluster and the silhouette card. Shell: home returns the hand-written tables;
 * generated cities come from 后裔's cityPlaces(cluster) (SGODOT-280) once it lands. */
export function cityInfo(c: P0Content, cluster: string): { ponds: string[]; outposts: string[]; residents: number; fish: { fish: string; level: number }[] } {
  const gen = (c as P0Content & { cityPlaces?: (id: string) => ReturnType<typeof cityInfo> }).cityPlaces;
  if (cluster !== homeCluster(c) && gen) return gen(cluster);
  if (cluster !== homeCluster(c)) return { ponds: [], outposts: [], residents: 0, fish: [] };
  const ponds = Object.keys(c.fishing.places).filter(id => clusterOf(c, id) === cluster);
  const outposts = (c.outposts ?? []).filter(o => clusterOf(c, o.id) === cluster);
  return { ponds, outposts: outposts.map(o => o.id), residents: new Set(outposts.flatMap(o => o.residents)).size, fish: [] };
}

export type PassRefusal = { code: 'pass_required' | 'trip_expired'; detail: { message: string; preview: ReturnType<typeof preview> } };

/** requirePass (note §3): entering a pond or an outpost space, or a command there, needs a pass for that place's city.
 * What is already under way is never cut off (§11.5.1): a command at the place the player already entered, and a reel
 * of a line already out, pass; a new cast and a new entry are checked. */
export function requirePass(c: P0Content, s: P0State, space: unknown, place: unknown, now: number, kind?: string): PassRefusal | null {
  if ((space !== 'pond' && space !== 'outpost') || typeof place !== 'string' || place === '') return null;
  const cluster = clusterOf(c, place);
  if (!cluster || covers(s, cluster, now)) return null;
  if (kind === 'reel' && s.cast) return null;
  if (kind !== undefined && kind !== 'cast' && s.presence.entered === place) return null;
  const expired = !!s.travel.passes[cluster];
  return { code: expired ? 'trip_expired' : 'pass_required',
    detail: { message: expired ? 'Trip expired' : 'Pass required', preview: preview(c, s, cluster) } };
}

/** Remember the place the player is in, once its pass has been checked (so a pass running out never kicks them). */
export function noteEntered(s: P0State, space: unknown, place: unknown): void {
  if (typeof space !== 'string' || space === '') return;
  s.presence.entered = (space === 'pond' || space === 'outpost') && typeof place === 'string' && place !== '' ? place : null;
}

export interface Arrival { cluster: string; first: boolean; stamp: TravelStamp | null; energy: number; pass_until: number; km: number; trip: number }

/** travel {to}: free in the first version; a 24 h Day Pass from arrival; a first visit stamps the passport and, for the
 * first 2 counted first visits of the day, gives +10 Energy through the achievement channel (over the food cap). */
export function travel(c: P0Content, s: P0State, to: unknown, now: number, events: P0Event[]): { code: string } | null {
  if (typeof to !== 'string' || to === '') return { code: 'bad_city' };
  const t = s.travel;
  if (to === t.home) { t.here = t.home; return null; }
  if (!clusterById(c, to)) return { code: 'unknown_city' };
  if (to === t.here && covers(s, to, now)) return null;   // already there: unchanged, not an error
  const { km: d, trip } = tripOf(c, s, to);
  const first = !t.visits[to];
  const v = t.visits[to] ??= { n: 0, first_at: now, last_at: now, deliveries: 0, delivered_day: '' };
  v.n += 1; v.last_at = now;
  t.passes[to] = { kind: 'day', from: now, until: now + DAY_PASS_MS };
  t.here = to;
  let stamp: TravelStamp | null = null, energy = 0;
  if (first && !t.stamps.some(x => x.cluster === to)) {
    const today = dayKey(c, now);
    const countedToday = t.stamps.filter(x => x.counted_on === today).length;
    // Days already filled push the stamp to the next day with room (2 a day, §11.9.2).
    let on = today;
    for (let n = countedToday; n >= FIRST_VISITS_PER_DAY;) {
      on = new Date(Date.parse(`${on}T00:00:00Z`) + 86_400_000).toISOString().slice(0, 10);
      n = t.stamps.filter(x => x.counted_on === on).length;
    }
    stamp = { cluster: to, kind: (c as WithClusters).landmarks?.[to] ? 'landmark' : 'climate', at: now, counted_on: on };
    t.stamps.push(stamp);
    if (on === today) energy = gainEnergy(c, s, now, FIRST_VISIT_ENERGY, events, 'first_visit', maxEnergy(c, s) + c.rewards.max_over);
    const counted = t.stamps.filter(x => x.counted_on <= today).length;
    for (const [n, e] of EXPLORER) {
      if (counted < n || t.explorer >= n) continue;
      t.explorer = n;
      grantOnce(c, s, now, `explorer_${n}`, e, events);
    }
  }
  events.push({ kind: 'arrival', cluster: to, first, stamp, energy, pass_until: t.passes[to].until, km: d, trip });
  return null;
}

/** return_home {}: free, instant, needs no pass; passes are kept. */
export function returnHome(s: P0State): void { s.travel.here = s.travel.home; }

/** §11.9.1: a delivery away from home counts once per cluster per day toward Regular. */
export function noteDelivery(c: P0Content, s: P0State, now: number): void {
  const here = s.travel.here, v = s.travel.visits[here];
  if (here === s.travel.home || !v || !covers(s, here, now)) return;
  const today = dayKey(c, now);
  if (v.delivered_day === today) return;
  v.delivered_day = today; v.deliveries += 1;
}

/** view.travel (note §2): the block as stored, home's pass implied. */
export const travelView = (s: P0State) => s.travel;
