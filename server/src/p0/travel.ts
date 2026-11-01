/**
 * Cross-city travel (P1, SGODOT-275 / 278; gameplay plan v2 §11): instant; since q(256) (SGODOT-367) it costs the Trip
 * band's Energy and coins (fareOf), and a Day Pass means free movement inside its city, never a free way back to it.
 * Save v5 adds the travel block; the shape and the error codes follow 亚瑟's technical note (275, comment 0fc0bc5e):
 * every key is a city cluster id (`gn-<GeoNames id>` of the cluster's seed city, San Francisco gn-5391959).
 */
import { distanceKm, tripByKm, TRIP_NAMES, type CityClusters } from './clusters.js';
import type { P0Content } from './content.js';
import { clusterById, clustersOf as clusters, countryPart, HOME_ALIAS, homeBase, homeFacts, writtenCluster, type DayHold, type Homed, type HomeSet } from './home.js';
import { gainEnergy, grantOnce, spendEnergy, type P0Event } from './progress.js';
import { dayKey, maxEnergy } from './rules.js';
import type { P0State } from './state.js';
import { isWild, wildById, wildNear3, wildPriced } from './wild.js';
import { worldOf } from './world.js';

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
  // Choosing a home (q(160)–q(163), SGODOT-303): optional, no save version. A save without them chose San Francisco
  // and farms at content.profile.farm_at (q(163) ③).
  farm_at?: [number, number];                    // the homestead's map point, the picked spot (q(160) ②)
  home_set?: HomeSet;                            // home's outposts and beginner pond, frozen when the home is picked
  home_chosen_at?: number;                       // when the home was picked or last changed
  home_changes?: number;                         // free changes used (q(161): one)
  pending?: true;                                // a new player who has not picked yet: plays from the written city meanwhile
  day_hold?: DayHold;                            // q(173): the day a home change carries over (rules.dayKey)
}


const DAY_PASS_MS = 24 * 3_600_000;
const FIRST_VISIT_ENERGY = 10;
const FIRST_VISITS_PER_DAY = 2;
const EXPLORER: [number, number][] = [[3, 30], [10, 50], [30, 70], [100, 100]];

export { clusterById, HOME_ALIAS, homeOf, writtenCluster, type HomeSet } from './home.js';

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
  if (isWild(place)) return wildById(c, place) ? place : null;   // v4q(3): a wild site is a place of its own, no city's
  const cut = place.indexOf('~');
  if (cut > 0) return place.slice(0, cut);
  const pond = c.fishing.places[place] as { cluster?: string; city?: string } | undefined;
  const outpost = c.outposts?.find(o => o.id === place) as { cluster?: string } | undefined;
  const known = pond ?? outpost;
  if (!known) return null;
  if (known.cluster) return known.cluster;
  if (pond?.city) return clusterOfCityName(c, pond.city);
  return writtenCluster(c);   // a hand-written outpost without its cluster field yet: the written city's
}

const ranks = new WeakMap<CityClusters, Map<string, { id: string; km: number; trip: number }[]>>();
/**
 * The cities a cross-city request may send the player to (q(128), SGODOT-284): clusters of ≥ 100,000 people outside
 * home, nearest first, each with its trip tier as the travel preview gives it (the save's frozen fallback included).
 * Cached per home and fallback; empty without the clusters table.
 */
export function rankedCities(c: P0Content, s: P0State): { id: string; km: number; trip: number }[] {
  const at = homeBase(c, s), cl = clusters(c);   // q(184): the home's base point, one ranking a city
  if (!at || !cl) return [];
  let byHome = ranks.get(cl);
  if (!byHome) ranks.set(cl, byHome = new Map());
  const fb = s.travel.fallback;
  const key = `${s.travel.home}|${at.lat},${at.lng}|${fb.near3.join(',')}|${fb.near10.join(',')}`;
  let list = byHome.get(key);
  if (!list) {
    list = cl.ranked(s.travel.home, at, fb);
    if (byHome.size > 32) byHome.delete(byHome.keys().next().value!);
    byHome.set(key, list);
  }
  return list;
}

/** §11.2.3: frozen into the save when the block is made (CityClusters.fallback), from the home's base point (q(184));
 * empty without the table. */
export function fallbackOf(c: P0Content, home: string): { near3: string[]; near10: string[] } {
  const at = homeBase(c, { travel: { home } }), cl = clusters(c);
  return at && cl ? cl.fallback(home, at) : { near3: [], near10: [] };
}

/** A new save's travel block: home is the written city until the player picks one; `pending` asks the client to offer
 * the pick (SGODOT-303: only a client that can show it, so an older one's new player is San Francisco's, q(163) ⑤). */
export const freshTravel = (c: P0Content, pending = false): TravelState => {
  const home = writtenCluster(c);
  return { home, here: home, passes: {}, visits: {}, stamps: [], fallback: fallbackOf(c, home), explorer: 0, ...(pending ? { pending: true as const } : {}) };
};

/** The climate zone (`Temperate`, as profile.climate) of a place's city, or of the city the player is in; home's when
 * the clusters are absent. */
export function climateAt(c: P0Content, s: P0State, place?: unknown): string {
  const cluster = (typeof place === 'string' && place !== '' ? clusterOf(c, place) : null) ?? s.travel?.here;
  return climateOfCluster(c, cluster);
}

/** The farm's climate zone: its home city's (the farm never travels; 哪吒 on #235: not profile.climate, once a home
 * may be another city). */
export const homeClimate = (c: P0Content, s?: Homed): string => homeFacts(c, s).climate;

function climateOfCluster(c: P0Content, cluster: string | null | undefined): string {
  const z = cluster ? (isWild(cluster) ? wildById(c, cluster)?.climate : clusterById(c, cluster)?.climate) : undefined;
  return z ? z[0].toUpperCase() + z.slice(1) : c.profile.climate;
}

/** Distance from the home's base point (q(184)) and the Trip band, by CityClusters.trip (the client's P0Clusters rule). */
export function tripOf(c: P0Content, s: P0State, cluster: string): { km: number; trip: number; name: string } {
  const at = homeBase(c, s), cl = clusters(c);
  const site = wildById(c, cluster);
  if (site) {   // v4q(3): a wild site's Trip by its distance from the home's base point (no fallback list: wild has its own)
    if (!at) return { km: 0, trip: 1, name: 'Local' };
    const km = distanceKm(at, site), trip = tripByKm(km);
    return { km: Math.round(km * 10) / 10, trip, name: TRIP_NAMES[trip - 1] };
  }
  if (!at || !cl?.get(cluster)) return { km: 0, trip: 1, name: 'Local' };
  return cl.trip(cluster, s.travel.home, at, s.travel.fallback);
}

/** Home is always covered; elsewhere a Day Pass still running (second home and guest passes come later). */
export const covers = (s: P0State, cluster: string, now: number): boolean =>
  cluster === s.travel.home || (s.travel.passes[cluster]?.until ?? 0) > now;

/** q(256) §11.2.1 / §11.2.2 (SGODOT-367, 亚瑟's contract 043c0bc8 B): what going to `cluster` costs now. The Trip band's
 * Energy and coins (content.travel.fares, Trip 1–7; tripOf already folds in the fallback lists: the nearest 3 cities
 * Trip 1, free, the nearest 10 at most Trip 2); a city visited before at half, rounded up. Home, and the city the player
 * is already in with a pass, cost nothing. renews: whether the trip signs a new Day Pass and counts a visit — no pass
 * or an expired one; a pass still running (going back from home or another city, option B) only takes the fare. */
export interface Fare { energy: number; coins: number; revisit: boolean; renews: boolean }
/** world_gen.json wild.fares (v4q(3) ③a): the priced guarantee, off until the user settles it. */
export const wildFares = (c: P0Content): { guarantee: boolean; max_trip: number; min_trip: number } =>
  (worldOf(c) as unknown as { wild?: { fares?: { guarantee: boolean; max_trip: number; min_trip: number } } } | undefined)?.wild?.fares
  ?? { guarantee: false, max_trip: 2, min_trip: 2 };
export function fareOf(c: P0Content, s: P0State, cluster: string, now: number): Fare {
  const t = s.travel, revisit = !!t.visits[cluster], renews = !covers(s, cluster, now);
  if (cluster === t.home || (cluster === t.here && !renews)) return { energy: 0, coins: 0, revisit, renews: false };
  let trip = tripOf(c, s, cluster).trip;
  if (isWild(cluster)) {
    // v4q(3): the nearest 3 wild sites are free for good; with the priced guarantee (③a, pending the user: wild.fares)
    // the nearest iron and quartz veins and 2 quarries cost at most its max_trip, every other wild site at least min_trip
    if (wildNear3(c, s).includes(cluster)) return { energy: 0, coins: 0, revisit, renews };
    const g = wildFares(c);
    if (g.guarantee) trip = wildPriced(c, s).includes(cluster) ? Math.min(trip, g.max_trip) : Math.max(trip, g.min_trip);
  }
  const band = Math.max(trip, 1) - 1;
  const at = (xs: number[] | undefined) => (xs?.length ? xs[Math.min(band, xs.length - 1)] : 0);
  const half = (n: number) => (revisit ? Math.ceil(n / 2) : n);
  return { energy: half(at(c.travel?.fares?.energy)), coins: half(at(c.travel?.fares?.coins)), revisit, renews };
}

/** What the confirm panel needs (§11.8.2): the fare as travel takes it (fareOf), whether it is a revisit, and until when
 * the city's Day Pass runs (null without one: home needs none). */
export function preview(c: P0Content, s: P0State, cluster: string, now = Date.now()) {
  const site = wildById(c, cluster);
  if (site) return wildPreview(c, s, site.id, now);
  const cl = clusterById(c, cluster);
  const { km: d, trip, name: tripName } = tripOf(c, s, cluster);
  const info = cityInfo(c, cluster);
  const fare = fareOf(c, s, cluster, now);
  const pass = cluster !== s.travel.home && covers(s, cluster, now) ? s.travel.passes[cluster].until : null;
  // q(210): the card's country as the rows write it (CLDR's name; none for a city-only place or `Mexico City`)
  return { cluster, name: cl?.name ?? '', country: cl ? countryPart(c, cl) : '', km: d, trip, trip_name: tripName,
    cost: { energy: fare.energy, coins: fare.coins, item: null }, revisit: fare.revisit, pass_until: pass, first_visit: !s.travel.visits[cluster],
    climate: cl?.climate ?? '', utc_offset_min: utcOffsetMin(cl?.timezone, now),   // the silhouette card (MAP-3-FREE, §11.8.3)
    fishing: info.fish, counts: { ponds: info.ponds.length, outposts: info.outposts.length, residents: info.residents } };
}

/** A wild site's travel card (contract-c §6): the city card's fields that make sense there, and `wild`, `type`, `free`.
 * No country, fish or counts: a wild site is no city. */
function wildPreview(c: P0Content, s: P0State, id: string, now: number) {
  const site = wildById(c, id)!;
  const { km: d, trip, name: tripName } = tripOf(c, s, id), fare = fareOf(c, s, id, now);
  const pass = covers(s, id, now) ? s.travel.passes[id].until : null;
  return { cluster: id, name: site.name, country: '', km: d, trip, trip_name: tripName,
    cost: { energy: fare.energy, coins: fare.coins, item: null }, revisit: fare.revisit, pass_until: pass, first_visit: !s.travel.visits[id],
    climate: site.climate, utc_offset_min: null, fishing: [], counts: { ponds: 0, outposts: 0, residents: 0 },
    wild: true as const, type: site.type, open: site.open, free: wildNear3(c, s).includes(id) };
}

/** A city's UTC offset in minutes now (the clients carry no tz database: they add it to their own clock for the card's
 * "Local time 09:12"); null when the zone is unknown. */
export function utcOffsetMin(zone: string | undefined, now: number): number | null {
  if (!zone) return null;
  try {
    const parts = new Intl.DateTimeFormat('en-US', { timeZone: zone, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric',
      hour: 'numeric', minute: 'numeric', second: 'numeric' }).formatToParts(new Date(now));
    const n = (t: string) => Number(parts.find(p => p.type === t)?.value ?? 0);
    const local = Date.UTC(n('year'), n('month') - 1, n('day'), n('hour'), n('minute'), n('second'));
    return Math.round((local - Math.floor(now / 1000) * 1000) / 60_000);
  } catch { return null; }
}

/** A city's places for GET /v1/p0/city/:cluster and the silhouette card. Shell: the written city returns the hand-written tables;
 * generated cities come from 后裔's cityPlaces(cluster) (SGODOT-280) once it lands. */
export interface CityInfo { ponds: string[]; outposts: string[]; residents: number; fish: { fish: string; level: number }[]; detail?: unknown }
export function cityInfo(c: P0Content, cluster: string): CityInfo {
  const gen = (c as P0Content & { cityPlaces?: (id: string) => CityInfo }).cityPlaces;
  if (cluster !== writtenCluster(c) && gen) return gen(cluster);
  if (cluster !== writtenCluster(c)) return { ponds: [], outposts: [], residents: 0, fish: [] };
  const ponds = Object.keys(c.fishing.places).filter(id => clusterOf(c, id) === cluster);
  // the card room (SGODOT-351) is no outpost of the city's set: not in its counts, as a generated city has none
  const outposts = (c.outposts ?? []).filter(o => clusterOf(c, o.id) === cluster && o.role !== 'casino');
  return { ponds, outposts: outposts.map(o => o.id), residents: new Set(outposts.flatMap(o => o.residents)).size, fish: [] };
}

export type PassRefusal = { code: 'pass_required' | 'trip_expired' | 'travel_required'; detail: { message: string; preview: ReturnType<typeof preview> } };

/** requirePass (note §3): entering a pond or an outpost space, or a command there, needs a pass for that place's city
 * and, since q(256) ④ (option B), being in that city: with a pass still running but `here` another city (home, or a
 * city flown to since), the way back is a travel at the revisit fare — `travel_required`, with that preview — never a
 * walk in. Home's places need neither. What is already under way is never cut off (§11.5.1): a command at the place the
 * player already entered, and a reel of a line already out, pass; a new cast and a new entry are checked. */
export function requirePass(c: P0Content, s: P0State, space: unknown, place: unknown, now: number, kind?: string): PassRefusal | null {
  // v4q(3): a wild site's mine is checked the same way (its pass, and being there); a mine read without its place is E's
  // to judge (mine_enter checks here === the mine)
  const wildMine = space === 'mine' && isWild(place);
  if ((space !== 'pond' && space !== 'outpost' && !wildMine) || typeof place !== 'string' || place === '') return null;
  const cluster = clusterOf(c, place);
  if (!cluster || cluster === s.travel.home) return null;
  const pass = covers(s, cluster, now);
  if (pass && s.travel.here === cluster) return null;
  if (kind === 'reel' && s.cast) return null;
  // Already in that place (entered with a pass): its commands and the client's refresh reads pass; a new cast does not.
  if (kind !== 'cast' && s.presence.entered === place) return null;
  if (pass) return { code: 'travel_required', detail: { message: 'Travel first', preview: preview(c, s, cluster, now) } };
  const expired = !!s.travel.passes[cluster];
  return { code: expired ? 'trip_expired' : 'pass_required',
    detail: { message: expired ? 'Trip expired' : 'Pass required', preview: preview(c, s, cluster, now) } };
}

/** Remember the place the player is in, once its pass has been checked (so a pass running out never kicks them). */
export function noteEntered(s: P0State, space: unknown, place: unknown): void {
  if (typeof space !== 'string' || space === '') return;
  s.presence.entered = (space === 'pond' || space === 'outpost' || (space === 'mine' && isWild(place))) && typeof place === 'string' && place !== '' ? place : null;
}

export interface Arrival { cluster: string; first: boolean; stamp: TravelStamp | null; energy: number; pass_until: number; km: number; trip: number;
  paid: { energy: number; coins: number }; renewed: boolean }

/** travel {to}: takes fareOf's Energy and coins (q(256); the wallet keeps content.wallet_floor), then — without a pass
 * running there — a 24 h Day Pass from arrival and a visit; a first visit stamps the passport and, for the first 2
 * counted first visits of the day, gives +10 Energy through the achievement channel (over the food cap). With a pass
 * still running (option B) it takes the revisit fare only: the pass is not re-signed, no visit, no stamp, no +10.
 * Refused whole (nothing taken): coins short first, then Energy, so with both short only the coins are named (q(257) ③).
 * Events in this order, for the client's floats (contract 043c0bc8 E): energy −, coins −, the first visit's +10, arrival. */
export function travel(c: P0Content, s: P0State, to: unknown, now: number, events: P0Event[]): { code: string; detail?: Record<string, unknown> } | null {
  if (typeof to !== 'string' || to === '') return { code: 'bad_city' };
  const t = s.travel;
  if (to === t.home) { t.here = t.home; return null; }
  const site = isWild(to) ? wildById(c, to) : undefined;
  if (isWild(to) && !site) return { code: 'unknown_place' };
  if (site && !site.open) return { code: 'not_open', detail: { type: site.type } };   // a grey pin: no Go (v4q(3) ⑤)
  if (!site && !clusterById(c, to)) return { code: 'unknown_city' };
  if (to === t.here && covers(s, to, now)) return null;   // already there: unchanged, not an error
  const fare = fareOf(c, s, to, now), floor = c.wallet_floor;
  if (fare.coins > 0 && s.coins < fare.coins + floor) {
    return { code: 'not_enough_coins', detail: { need: fare.coins + floor - s.coins, have: s.coins, cost: fare.coins, floor } };
  }
  if (s.energy.value < fare.energy) {
    return { code: 'not_enough_energy', detail: { need: fare.energy - s.energy.value, have: s.energy.value, cost: fare.energy } };
  }
  if (fare.energy > 0) spendEnergy(c, s, now, fare.energy, events, 'travel');
  if (fare.coins > 0) { s.coins -= fare.coins; events.push({ kind: 'coins', delta: -fare.coins, reason: 'travel' }); }
  const { km: d, trip } = tripOf(c, s, to);
  const paid = { energy: fare.energy, coins: fare.coins };
  if (!fare.renews) {   // option B: back to a city whose pass still runs — the fare only
    t.here = to;
    events.push({ kind: 'arrival', cluster: to, first: false, stamp: null, energy: 0, pass_until: t.passes[to].until, km: d, trip, paid, renewed: false, ...(site ? { wild: true } : {}) });
    return null;
  }
  const first = !t.visits[to];
  const v = t.visits[to] ??= { n: 0, first_at: now, last_at: now, deliveries: 0, delivered_day: '' };
  v.n += 1; v.last_at = now;
  t.passes[to] = { kind: 'day', from: now, until: now + DAY_PASS_MS };
  t.here = to;
  let stamp: TravelStamp | null = null, energy = 0;
  // v4q(3) ④: a wild site is visited (it counts as having been in its climate band) but stamps nothing — no first visit's
  // +10, no Explorer medal (第 34 条: no wild stamps)
  if (site) {
    events.push({ kind: 'arrival', cluster: to, first, stamp: null, energy: 0, pass_until: t.passes[to].until, km: d, trip, paid, renewed: true, wild: true });
    return null;
  }
  if (first && !t.stamps.some(x => x.cluster === to)) {
    const today = dayKey(c, s, now);
    const countedToday = t.stamps.filter(x => x.counted_on === today).length;
    // Days already filled push the stamp to the next day with room (2 a day, §11.9.2).
    let on = today;
    for (let n = countedToday; n >= FIRST_VISITS_PER_DAY;) {
      on = new Date(Date.parse(`${on}T00:00:00Z`) + 86_400_000).toISOString().slice(0, 10);
      n = t.stamps.filter(x => x.counted_on === on).length;
    }
    stamp = { cluster: to, kind: c.travel?.landmarks?.[to] ? 'landmark' : 'climate', at: now, counted_on: on };   // 表 11-18
    t.stamps.push(stamp);
    if (on === today) energy = gainEnergy(c, s, now, FIRST_VISIT_ENERGY, events, 'first_visit', maxEnergy(c, s) + c.rewards.max_over);
    settleExplorer(c, s, now, events);
  }
  events.push({ kind: 'arrival', cluster: to, first, stamp, energy, pass_until: t.passes[to].until, km: d, trip, paid, renewed: true });
  return null;
}

/** Whether a cluster is one the game has: the written city, or a row of the table (a closed country's is not, q(189)). */
export const openCity = (c: P0Content, cluster: string): boolean =>
  cluster === writtenCluster(c) || !!clusterById(c, cluster) || !!wildById(c, cluster);   // a wild site is kept as an open place (v4q(3))

/** view.travel (q(189) ③): visits, stamps and passes of a city the table no longer has are kept in the save, never shown. */
export function travelShown(c: P0Content, t: TravelState): Pick<TravelState, 'visits' | 'stamps' | 'passes'> {
  const keep = <V>(o: Record<string, V>) => Object.fromEntries(Object.entries(o).filter(([id]) => openCity(c, id)));
  return { visits: keep(t.visits), stamps: t.stamps.filter(x => openCity(c, x.cluster)), passes: keep(t.passes) };
}

/** Explorer medals (§11.9.2) by the stamps counted up to today: after travel, and on any command, so a stamp
 * pushed to tomorrow earns its medal tomorrow without another trip (亚瑟 on #206). */
export function settleExplorer(c: P0Content, s: P0State, now: number, events: P0Event[]): void {
  const today = dayKey(c, s, now);
  // q(189) ③: a stamp of a city not in the table (a closed country's) is kept but not counted; medals already given stay
  const counted = s.travel.stamps.filter(x => x.counted_on <= today && openCity(c, x.cluster)).length;
  for (const [n, e] of EXPLORER) {
    if (counted < n || s.travel.explorer >= n) continue;
    s.travel.explorer = n;
    grantOnce(c, s, now, `explorer_${n}`, e, events);
  }
}

/**
 * Where the player is follows what they do (李元芳's cold start, 2026-10-10): the city they stand in is the one their
 * scene is in, not only the last `travel` / `return_home`. Called with every command and state read, after requirePass:
 * - the homestead's space (home: the farm and its kitchen) is the home city; a mine is its wild site (v4q(5) ①);
 * - entering a pond or an outpost (its pass already checked) puts the player in that place's city;
 * - otherwise (the map, a read without a space) a city whose Day Pass ran out lets go: back home, unless the player is
 *   still in a place there they entered with the pass (never cut off, §11.5.1).
 * Quiet: no event, no welcome (the client's own Go home says Welcome home). True when `here` changed.
 */
const HOMESTEAD_SPACES = new Set(['home']);
export function settleHere(c: P0Content, s: P0State, space: unknown, place: unknown, now: number): boolean {
  const t = s.travel, was = t.here;
  // v4q(3) / v4q(5) ①: the mines are out of the home city — a wild site's mine is that site, not home (Rest and the rest
  // judged by "away" read it so); a mine read without its place leaves `here` as it is (周瑜's contract #625: mine reads
  // and commands carry place = the mine's id)
  if (space === 'mine') { if (isWild(place) && covers(s, place, now)) t.here = place; }
  else if (typeof space === 'string' && HOMESTEAD_SPACES.has(space)) t.here = t.home;
  else if ((space === 'pond' || space === 'outpost') && typeof place === 'string' && place !== '') {
    const cluster = clusterOf(c, place);
    if (cluster && covers(s, cluster, now)) t.here = cluster;
  } else if (t.here !== t.home && !covers(s, t.here, now)) {
    const inside = s.presence.entered ? clusterOf(c, s.presence.entered) : null;
    if (inside !== t.here) t.here = t.home;
  }
  return t.here !== was;
}

/** return_home {}: free, instant, needs no pass; passes are kept. */
export function returnHome(s: P0State): void { s.travel.here = s.travel.home; }

/** §11.9.1: a delivery away from home counts once per cluster per day toward Regular — in `city`, the player's
 * current one, or a cross-city check-in's outpost city (q(128)). */
export function noteDelivery(c: P0Content, s: P0State, now: number, city: string = s.travel.here): void {
  const v = s.travel.visits[city];
  if (city === s.travel.home || isWild(city) || !v || !covers(s, city, now)) return;   // a wild site is never a Regular's (v4q(3))
  const today = dayKey(c, s, now);
  if (v.delivered_day === today) return;
  v.delivered_day = today; v.deliveries += 1;
}

/** view.travel (note §2): the block as stored, home's pass implied. */
export const travelView = (s: P0State) => s.travel;
