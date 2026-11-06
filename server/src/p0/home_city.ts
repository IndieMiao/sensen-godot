/**
 * Choosing a home (SGODOT-303, q(160)–q(163); the server's second step). A new player picks a city from the open list
 * (M1 tier and up, q(160) ①), then one of 3 farm spots the server offers; the save keeps the home, the spot and the
 * home's set of outposts (q(163) ①). One free change follows, within 7 days or before Homestead Lv2 (q(161)). The farm
 * itself never changes with the place (q(160) ⑤): the point only places the home pin and measures trips.
 *
 * Spots (q(160) ②): three directions 120° apart round the city's beginner pond; 0.5–3 km from it; at least 300 m from
 * every outpost and pond centre (§9.3.2 farm exclusion, placement.farm_exclusion_m); at least 1 km apart; each
 * player's spot scattered 100–200 m off the city's, the same for the same player every time. Land (≥ 50 m from water)
 * and the district name need data the server does not hold at run time: tools/home_spots.ts finds them offline, as the
 * water table was made, into server/data/home_spots.json; a city without rows there falls back to the geometry alone.
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { P0Content } from './content.js';
import { clusterById, clustersOf, countryName, countryPart, homeBase, homeFacts, homeOf, writtenCluster, type DayHold, type Homed, type HomeSet } from './home.js';
export { countryName, countryPart, namesCountry } from './home.js';
import { recallAwayTraps } from './fish_trap.js';
import { carryGiftParcels } from './parcels.js';
import { dayKey, rolloverAfter } from './rules.js';
import type { P0Event } from './progress.js';
import { letGoAway, type P0State } from './state.js';
import { clusterOf, fallbackOf, wildFrozen } from './travel.js';
import { cityPlaces, clusterAdmin, hash32, km, offset, tierOf, worldOf } from './world.js';

type Point = { lat: number; lng: number };
interface CityOutpost { id: string; role: string; residents: string[]; at: Point | null; nearest?: string }
interface CityPond { id: string; name: string; beginner: boolean; at: Point | null }

/** The rules (world_gen.json `home`): the open list and the spot and change rules, with q(160) / q(161)'s numbers. */
export interface HomeRules {
  cities: string[];
  spot: { pond_km: [number, number]; apart_km: number; scatter_m: [number, number] };
  change: { days: number; before_level: number };
  /** q(205) ②: `Near you` names an open city only this close to the address's point; farther, no guess. */
  near_max_km: number;
  /** q(216) (SGODOT-342, user 10-26: method D): a free pin stands within range_km of the city's base (homeBase) and,
   * clear_m > 0, that far from every outpost, hut and pond centre of the city; no land or water test. */
  pin: { range_km: number; clear_m: number };
}
const DEFAULT_RULES: HomeRules = { cities: [], spot: { pond_km: [0.5, 3], apart_km: 1, scatter_m: [100, 200] }, change: { days: 7, before_level: 2 },
  near_max_km: 1500, pin: { range_km: 10, clear_m: 300 } };
export const homeRules = (c: P0Content): HomeRules => {
  const r = (worldOf(c) as { home?: Partial<HomeRules> } | undefined)?.home;
  return { ...DEFAULT_RULES, ...r, spot: { ...DEFAULT_RULES.spot, ...r?.spot }, change: { ...DEFAULT_RULES.change, ...r?.change },
    pin: { ...DEFAULT_RULES.pin, ...r?.pin } };
};
const exclusionKm = (c: P0Content) => ((worldOf(c)?.placement as { farm_exclusion_m?: number } | undefined)?.farm_exclusion_m ?? 300) / 1000;

/** A city's outposts: the written city's from the outpost table (its points from p0_outposts.json), another's generated. */
export function cityOutposts(c: P0Content, cluster: string): CityOutpost[] {
  if (cluster === writtenCluster(c)) {
    return (c.outposts ?? []).filter(o => clusterOf(c, o.id) === cluster)
      .map(o => ({ id: o.id, role: o.role, residents: o.residents, at: o.lat !== undefined && o.lng !== undefined ? { lat: o.lat, lng: o.lng } : null }));
  }
  return (cityPlaces(c, cluster)?.detail.outposts ?? [])
    .map(o => ({ id: o.id, role: o.role, residents: o.residents, at: { lat: o.lat, lng: o.lng }, nearest: o.nearest?.name }));
}

/** q(204): a city's Mine Huts (generated cities only: the written city has none). Not outposts: no keeper or counter. */
export function cityHuts(c: P0Content, cluster: string): CityOutpost[] {
  return (cityPlaces(c, cluster)?.detail.huts ?? []).map(h => ({ id: h.id, role: h.role, residents: h.residents, at: { lat: h.lat, lng: h.lng } }));
}

/** The cities that have a Mine Hut (q(204) ①): those with the hut rule's trait in the hand table (world.coastal),
 * once world.room has the room; the generator decides each (its tier). A short list: never the 12,000 clusters. */
export function hutCities(c: P0Content): string[] {
  const w = worldOf(c), rule = w?.placement.hut;
  if (!w || !rule || !w.room.mine_hut) return [];
  return Object.keys(w.coastal).filter(id => !id.startsWith('_') && (w.coastal[id] ?? []).includes(rule.needs) && cityHuts(c, id).length > 0);
}

/** The huts a resident lives in (Ivo, q(204) ④), in any city. */
const hutsOf = (c: P0Content, resident: string) => hutCities(c).flatMap(cl => cityHuts(c, cl)).filter(h => h.residents.includes(resident));

/**
 * Where this player finds a resident (the map pin, the Today `Show on map`, view.residents[id].place): Pip at the home
 * city's travel post (q(162) ③); anyone else at their outpost in the home city; a hut dweller (Ivo) in a hut, whatever
 * the home city — the hut of the city last visited, else the first (P1 has one, Denver's). Null: not found.
 */
export function residentPlace(c: P0Content, s: P0State, resident: string): string | null {
  if (resident === 'res_pip') return homeSetOf(c, s)?.post ?? null;
  const own = cityOutposts(c, homeOf(c, s)).find(o => o.residents.includes(resident));
  if (own) return own.id;
  const huts = hutsOf(c, resident);
  const last = (id: string) => s.travel.visits[clusterOf(c, id) ?? '']?.last_at ?? -1;
  return huts.sort((a, b) => last(b.id) - last(a.id))[0]?.id ?? null;
}

/** A city's ponds: the written city's hand-written ones, another's generated. */
export function cityPonds(c: P0Content, cluster: string): CityPond[] {
  if (cluster === writtenCluster(c)) {
    return Object.entries(c.fishing.places).filter(([id]) => clusterOf(c, id) === cluster)
      .map(([id, p]) => ({ id, name: p.name, beginner: !!p.beginner, at: p.at ? { lat: p.at[0], lng: p.at[1] } : null }));
  }
  return (cityPlaces(c, cluster)?.detail.ponds ?? []).map(p => ({ id: p.id, name: p.name, beginner: p.beginner, at: { lat: p.lat, lng: p.lng } }));
}

/**
 * A city's home set (§9.3.2 家一套): its first market square, tea house and travel post, its beginner pond and that
 * pond's tackle shop (the one named after it, else the nearest). Null: one is missing, so the city cannot be a home.
 */
export function citySet(c: P0Content, cluster: string): HomeSet | null {
  const outposts = cityOutposts(c, cluster), pond = cityPonds(c, cluster).find(p => p.beginner);
  const first = (role: string) => outposts.find(o => o.role === role)?.id;
  const tackles = outposts.filter(o => o.role === 'tackle');
  const near = (o: CityOutpost) => (o.at && pond?.at ? km(o.at, pond.at) : Infinity);
  const tackle = tackles.find(o => o.nearest === pond?.name) ?? [...tackles].sort((a, b) => near(a) - near(b))[0];
  const market = first('market'), tea = first('tea'), post = first('post');
  return pond && tackle && market && tea && post ? { market, tea, tackle: tackle.id, post, pond: pond.id } : null;
}

/** The player's home set: frozen in the save when the home was picked (q(163) ①), else the home city's. */
export const homeSetOf = (c: P0Content, s: Homed): HomeSet | null =>
  s?.travel?.home_set ?? citySet(c, homeOf(c, s));

/** Whether a resident lives in a city (Pip is at every travel post, q(162) ③). */
export const livesIn = (c: P0Content, cluster: string, resident: string): boolean =>
  resident === 'res_pip' || cityOutposts(c, cluster).some(o => o.residents.includes(resident));

/**
 * Whether a city can be picked: open (the written city, or on the open list with a full home set), small (S tier:
 * travel only, `Small town · pick a nearby city`), or not_open (M1 and up, not on the list yet). Null: no such city.
 */
export type HomeStatus = 'open' | 'small' | 'not_open';
export function homeStatus(c: P0Content, cluster: string): HomeStatus | null {
  if (cluster === writtenCluster(c)) return 'open';
  const cl = clusterById(c, cluster), w = worldOf(c);
  if (!cl || !w) return null;
  if (tierOf(w, cl) === 'S') return 'small';
  return homeRules(c).cities.includes(cluster) && citySet(c, cluster) ? 'open' : 'not_open';
}

/** One offered farm spot: its point, the distance to the beginner pond and the side of the pond it is on (`1.2 km to
 * Fern Pond · northeast`: northeast of the pond, as the pick page's map draws it; 不知火舞 on 303). */
/** pond: the beginner pond the spot is measured from, with its point (HOME-PICK-3's map draws it with the spots). */
export interface HomeSpot { spot: number; lat: number; lng: number; km: number; toward: string; pond: { id: string; name: string; lat: number; lng: number }; hood: string | null }

const COMPASS = ['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest'];
/** The compass word from a to b (flat, fine within a city). */
function toward(a: Point, b: Point): string {
  const deg = (Math.atan2((b.lng - a.lng) * Math.cos((a.lat * Math.PI) / 180), b.lat - a.lat) * 180) / Math.PI;
  return COMPASS[Math.round(((deg + 360) % 360) / 45) % 8];
}

type Refusal = { code: string; detail?: Record<string, unknown> };

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
/** server/data/home_spots.json (tools/home_spots.ts): per city, 3 base spots on built-up land at least 250 m from
 * water (so a scattered spot keeps q(160)'s 50 m), with district names, for the world seed and revision. */
export interface SpotTable { seed: string; revision: number; cities: Record<string, { lat: number; lng: number; hood: string }[]> }
let spotFile: SpotTable | null | undefined;
export function spotTable(): SpotTable | null {
  if (spotFile === undefined) {
    try { spotFile = JSON.parse(readFileSync(path.join(ROOT, 'server/data/home_spots.json'), 'utf8')) as SpotTable; }
    catch { spotFile = null; }
  }
  return spotFile;
}

/**
 * The city's three spots before a player's scatter: the offline table's (a table made for another world is not used;
 * p1_choose_home.test.ts fails on it), else found here from the rules alone. Null when the city cannot be a home or a
 * direction has no room.
 */
export function citySpots(c: P0Content, cluster: string, table = spotTable()): { at: Point; pond: CityPond; hood: string | null }[] | null {
  const set = citySet(c, cluster), w = worldOf(c);
  const pond = set && cityPonds(c, cluster).find(p => p.id === set.pond);
  if (!pond?.at || !w) return null;
  const rows = table && table.seed === w.seed && table.revision === w.revision ? table.cities[cluster] : undefined;
  if (rows?.length === 3) return rows.map(r => ({ at: { lat: r.lat, lng: r.lng }, pond, hood: r.hood }));
  const r = homeRules(c).spot, ex = exclusionKm(c), sc = r.scatter_m[1] / 1000;
  const blocks = [...cityOutposts(c, cluster), ...cityPonds(c, cluster)].flatMap(p => (p.at ? [p.at] : []));
  // Distances try the middle of the band first; the scatter must stay inside it, and keep the exclusion and the spacing.
  const dists = [1.2, 1.6, 0.9, 2.0, 2.4, 0.7, 2.8].filter(d => d - sc >= r.pond_km[0] && d + sc <= r.pond_km[1]);
  const turns = [0, 15, -15, 30, -30, 45, -45];
  const base = hash32(w.seed, cluster, 'home:spots') % 360;
  const out: { at: Point; pond: CityPond; hood: string | null }[] = [];
  for (let k = 0; k < 3; k++) {
    let found: Point | null = null;
    for (const t of turns) {
      for (const d of dists) {
        const at = offset(pond.at.lat, pond.at.lng, d, base + 120 * k + t);
        if (blocks.every(b => km(at, b) >= ex + sc) && out.every(o => km(at, o.at) >= r.apart_km + 2 * sc)) { found = at; break; }
      }
      if (found) break;
    }
    if (!found) return null;
    out.push({ at: found, pond, hood: null });
  }
  return out;
}

/** The 3 spots this player is offered in a city (q(160) ②): the city's, each scattered 100–200 m by the player id. */
export function homeSpots(c: P0Content, cluster: string, player: string): HomeSpot[] | null {
  const spots = citySpots(c, cluster), w = worldOf(c);
  if (!spots || !w) return null;
  const [lo, hi] = homeRules(c).spot.scatter_m;
  return spots.map(({ at, pond, hood }, k) => {
    const turn = hash32(w.seed, cluster, `home:spot:${player}:${k}`) % 360;
    const m = lo + (hash32(w.seed, cluster, `home:spot-m:${player}:${k}`) / 0x1_0000_0000) * (hi - lo);
    const p = offset(at.lat, at.lng, m / 1000, turn);
    return { spot: k, lat: p.lat, lng: p.lng, km: Math.round(km(p, pond.at!) * 1000) / 1000, toward: toward(pond.at!, p),
      pond: { id: pond.id, name: pond.name, lat: pond.at!.lat, lng: pond.at!.lng }, hood };
  });
}

/** A free pin's point ([lat, lng] on the earth), else null. */
function pinPoint(at: unknown): Point | null {
  if (!Array.isArray(at) || at.length !== 2) return null;
  const [lat, lng] = at.map(Number);
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? { lat, lng } : null;
}

/** The places a free pin keeps clear of (q(216)): the city's outposts, huts and ponds, with their points. */
export function pinBlocks(c: P0Content, cluster: string): { id: string; lat: number; lng: number }[] {
  return [...cityOutposts(c, cluster), ...cityHuts(c, cluster), ...cityPonds(c, cluster)]
    .flatMap(p => (p.at ? [{ id: p.id, lat: p.at.lat, lng: p.at.lng }] : []));
}

/**
 * What the pick page needs to place a free pin in a city (q(216)): the circle (its base and range), how clear of the
 * places it stays and those places, and where the pin starts (the player's first offered spot, one of the checked
 * three). Null when the city cannot be a home.
 */
export function pinArea(c: P0Content, cluster: string, player: string) {
  const r = homeRules(c).pin, base = homeBase(c, { travel: { home: cluster } }), first = homeSpots(c, cluster, player)?.[0];
  if (!base || !first) return null;
  return { base, range_km: r.range_km, clear_m: r.clear_m, start: { lat: first.lat, lng: first.lng },
    blocks: r.clear_m > 0 ? pinBlocks(c, cluster) : [] };
}

/** Whether a free pin may stand at a point of an open city (q(216), method D): inside the circle, clear of the places. */
export function pinRefusal(c: P0Content, cluster: string, at: Point): Refusal | null {
  const r = homeRules(c).pin, base = homeBase(c, { travel: { home: cluster } });
  if (!base) return { code: 'home_not_open', detail: { city: cluster, status: 'no_base' } };
  const d = km(at, base);
  if (d > r.range_km) return { code: 'home_out_of_range', detail: { km: Math.round(d * 1000) / 1000, range_km: r.range_km } };
  if (r.clear_m > 0) {
    let near: { id: string; m: number } | null = null;
    for (const b of pinBlocks(c, cluster)) {
      const m = km(at, b) * 1000;
      if (m < r.clear_m && (!near || m < near.m)) near = { id: b.id, m };
    }
    if (near) return { code: 'home_too_close', detail: { place: near.id, m: Math.round(near.m), clear_m: r.clear_m } };
  }
  return null;
}

/**
 * q(173) ①: the day a change of home carries over. The key stays the old home's day until both its own end (the old
 * home's next 04:00) has come and the new home's calendar has turned past it, then the day turns at the first such
 * 04:00 of the new home (the very instant, when that is one): 24–49 h, never shorter, never back a date. `start` is
 * when the day began on the old clock, so times earlier in it read the same key.
 */
export function dayHoldFor(c: P0Content, s: P0State, city: string, now: number): DayHold {
  const key = dayKey(c, s, now), before = new Date(Date.parse(`${key}T00:00:00Z`) - 86_400_000).toISOString().slice(0, 10);
  const start = rolloverAfter(c, s, before), end = rolloverAfter(c, s, key), next: Homed = { travel: { home: city } };
  let until = rolloverAfter(c, next, dayKey(c, next, end - 1));   // the new home's first 04:00 at or after the old end
  while (dayKey(c, next, until) <= key) until = rolloverAfter(c, next, dayKey(c, next, until));
  return { key, start, until };
}

/** Whether the free change is still open (q(161) ①): one, within `days` of the account or before Homestead Lv`before_level`. */
export function changeOpen(c: P0Content, s: P0State, now: number): { open: boolean; until: number } {
  const r = homeRules(c).change, until = s.created_at + r.days * 86_400_000;
  return { open: !s.travel.pending && (s.travel.home_changes ?? 0) < 1 && now < until && s.homestead.level < r.before_level, until };
}

/**
 * choose_home {city, spot} (a new player's first pick) and change_home {city, spot} (the free change, q(161); q(216) B,
 * user 10-27: the home city itself too, to move the pin). With
 * `at: [lat, lng]` (q(216), SGODOT-342: a free pin, 0.2.11 on) the farm stands at that point instead, checked by
 * pinRefusal; `spot` is then not read (an older client sends only `spot`).
 * Everything on the farm goes along (q(161) ②); the old home becomes a city visited (④). Requests to hand in at home
 * follow the new home on their own (no hand-in checks the place); an accepted resident request whose resident does not
 * live in the new home is dropped, free (③). A pond or outpost in the old city is let go as when a home moved.
 */
export function chooseHome(c: P0Content, s: P0State, cmd: { type: 'choose_home' | 'change_home'; city?: unknown; spot?: unknown; at?: unknown },
  now: number, events: P0Event[]): Refusal | null {
  const t = s.travel, city = String(cmd.city ?? ''), spot = Number(cmd.spot ?? 0);
  if (cmd.type === 'choose_home' && !t.pending) return { code: 'home_chosen' };
  if (cmd.type === 'change_home') {
    const gate = changeOpen(c, s, now);
    if (!gate.open) return { code: 'home_set_for_good', detail: { until: gate.until } };
  }
  const status = homeStatus(c, city);
  if (status !== 'open') return { code: 'home_not_open', detail: { city, status } };
  let at: Point | null | undefined;
  const set = citySet(c, city);
  if (cmd.at !== undefined) {
    at = pinPoint(cmd.at);
    if (!at) return { code: 'bad_pin' };
    const no = pinRefusal(c, city, at);
    if (no) return no;
  } else {
    if (!Number.isInteger(spot) || spot < 0 || spot > 2) return { code: 'bad_spot' };
    at = homeSpots(c, city, s.player)?.[spot];
  }
  if (!at || !set) return { code: 'home_not_open', detail: { city, status: 'no_spot' } };
  const from = t.home, first = !!t.pending, dropped: string[] = [];
  // q(173) ③: a first pick (a new player, nothing played) turns to the new home's day at once; a change carries its day.
  const hold = cmd.type === 'change_home' ? dayHoldFor(c, s, city, now) : null;
  const oldEnd = hold ? rolloverAfter(c, s, hold.key) : 0;
  if (from !== city) {
    for (const [id, r] of Object.entries(s.residents)) {
      // q(204): a hut dweller (Ivo) lives where his hut is, whatever the home: his request stays
      if (r.req && !livesIn(c, city, id) && !hutsOf(c, id).length) { dropped.push(r.req.id); r.req = null; }
    }
    // The old home becomes a city visited (④) — on a change only: a first pick leaves San Francisco, where a pending save
    // stands in meanwhile and plays nothing (SGODOT-303), never visited (李元芳 on 0.2.10, 286 ad0c1580: a new Shanghai
    // player read San Francisco as Visited ×1, Cities 1/3).
    const v = t.visits[from];
    if (!v && !first) t.visits[from] = { n: 1, first_at: t.home_chosen_at ?? s.created_at, last_at: now, deliveries: 0, delivered_day: '' };
    delete t.passes[city];   // home needs no pass
    // q(272): home gives no local requests — one tracked in the new home is dropped, free, as a resident's above
    for (const sl of s.locals?.[city]?.slots ?? []) if (sl.req.status === 'accepted') dropped.push(sl.req.id);
    delete s.locals?.[city];
  }
  if (t.here === from) t.here = city;
  t.home = city;
  // q(270) ⑦: on a change each city keeps its Market Board and the home board (`market`) is the new home's, made there
  // if new; the first pick takes the board the pending save had under San Francisco along (q(270) ⑤: no extra board)
  s.markets ??= {};
  if (first) { delete s.markets[from]; s.markets[city] = s.boards.market ??= []; }
  else s.boards.market = s.markets[city] ??= [];
  t.farm_at = [at.lat, at.lng];
  t.home_set = set;
  t.home_chosen_at = now;
  if (cmd.type === 'change_home') t.home_changes = (t.home_changes ?? 0) + 1;
  delete t.pending;
  t.fallback = fallbackOf(c, city);
  delete t.wild_near3; delete t.wild_priced;
  Object.assign(t, wildFrozen(c, city));   // v4q(3): the free 3 and the priced guarantee frozen again with the fallback
  if (hold) { t.day_hold = hold; carryGiftParcels(s, oldEnd, hold.until); }
  letGoAway(c, s);
  recallAwayTraps(c, s, now, events);   // q(177) ③
  // spot -1: a free pin (q(216))
  events.push({ kind: 'home', action: cmd.type === 'choose_home' ? 'chosen' : 'changed', city, from, spot: cmd.at !== undefined ? -1 : spot, dropped });
  return null;
}

/** view.home (SGODOT-303): the home, whether the player still has to pick one, its set, and the free change's window. */
export function homeView(c: P0Content, s: P0State, now: number) {
  const f = homeFacts(c, s), ch = changeOpen(c, s, now), r = homeRules(c).change;
  return { city: f.cluster, name: f.name, pending: !!s.travel.pending, farm: f.farm, set: homeSetOf(c, s),
    change: { open: ch.open, until: ch.until, before_level: r.before_level, used: s.travel.home_changes ?? 0 } };
}

/** q(188) ① / q(205) ②: the open city nearest a point (the player's address, ip_city.ts) for the pick page's `Near you`
 * row; none when the nearest is farther than home.near_max_km (Sydney is not near Singapore). */
export function nearestOpen(c: P0Content, at: { lat: number; lng: number }): HomeCityRow | null {
  let best: { row: HomeCityRow; d: number } | null = null;
  for (const r of homeCities(c).open) {
    const cl = clusterById(c, r.id) ?? (r.id === writtenCluster(c) ? clustersOf(c)?.byId.get(r.id) : undefined);
    if (!cl) continue;
    const d = km(at, cl);
    if (!best || d < best.d) best = { row: r, d };
  }
  return best && best.d <= homeRules(c).near_max_km ? best.row : null;
}

/** Country + name of cities that share both in the city directory (q(208) ①: 83 pairs outside the US, two Ji'ans, two
 * Suzhous), worked out once per content. */
const twins = new WeakMap<object, Set<string>>();
function twinNames(c: P0Content): Set<string> {
  const all = clustersOf(c);
  if (!all) return new Set();
  let set = twins.get(all);
  if (!set) {
    const seen = new Map<string, number>();
    for (const cl of all.byId.values()) seen.set(`${cl.country_code}|${cl.name}`, (seen.get(`${cl.country_code}|${cl.name}`) ?? 0) + 1);
    set = new Set([...seen].filter(([, n]) => n > 1).map(([k]) => k));
    twins.set(all, set);
  }
  return set;
}

/**
 * The second part of a city row (q(208) ①, every CityRow: the home pick, Near you, a search, MAP-8 Nearby): a US city
 * its state (`San Francisco · California`); elsewhere its country (countryPart: `Tokyo · Japan`, `Istanbul · Türkiye`;
 * none for `Singapore`, `Mexico City`, `Taipei`), and its province for one of two same-named cities in a country
 * (`Ji'an · Jilin`; two in one province both read the province, q(209) ①). "" for none; the client leaves it out.
 */

export function cityRegion(c: P0Content, id: string): string {
  const cl = clusterById(c, id);
  if (!cl) return '';
  if (cl.country_code === 'US') return clusterAdmin(id) || countryName(c, cl);
  const part = countryPart(c, cl);
  if (part === '') return '';
  if (twinNames(c).has(`${cl.country_code}|${cl.name}`)) return clusterAdmin(id) || part;
  return part;
}

/** A city row for the pick page: open ones only on the list; a search also returns the others, greyed with the reason. */
/** region: cityRegion (q(208) ①). */
export interface HomeCityRow { id: string; name: string; country: string; region: string; climate: string; status: HomeStatus }
const row = (c: P0Content, id: string): HomeCityRow | null => {
  const cl = clusterById(c, id), status = homeStatus(c, id);
  if (!status) return null;
  const climate = cl?.climate ?? c.profile.climate.toLowerCase();
  const country = cl ? countryPart(c, cl) : '';   // q(210) ⑤: every exit writes the country one way (countryPart)
  return { id, name: id === writtenCluster(c) ? c.profile.city : cl?.name ?? id, country, region: cityRegion(c, id), climate, status };
};

/** The open cities (the written city first, then the list), and with `query` (2+ letters) the cities whose name starts
 * with it, the most populous first, up to `limit`. */
export function homeCities(c: P0Content, query = '', limit = 20): { open: HomeCityRow[]; matches: HomeCityRow[] } {
  const open = [writtenCluster(c), ...homeRules(c).cities.filter(id => id !== writtenCluster(c))]
    .map(id => row(c, id)).filter((r): r is HomeCityRow => !!r && r.status === 'open');
  // a typed ' finds the directory's ’ (Ji’an, Xi’an): both read as one
  const fold = (t: string) => t.toLowerCase().replace(/[’‘`]/g, "'");
  const q = fold(query.trim());
  if (q.length < 2) return { open, matches: [] };
  const all = [...(clustersOf(c)?.byId.values() ?? [])].filter(cl => fold(cl.name).startsWith(q))
    .sort((a, b) => b.population - a.population).slice(0, limit);
  return { open, matches: all.map(cl => row(c, cl.id)).filter((r): r is HomeCityRow => !!r) };
}
