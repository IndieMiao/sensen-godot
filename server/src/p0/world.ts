/**
 * Global generation (SGODOT-280; plan v2 §9.3.2 outposts, §6.3.3 ponds, §9.4.3 residents): a city cluster's ponds,
 * outposts, keepers and residents from the world seed and the cluster id alone, the same on every call and every
 * server. Pure: nothing here reads the network or a save. The hand-written home set (San Francisco) is never generated.
 *
 * Ids are `<cluster>~<kind><n>` (亚瑟's cross-city note §4, 275 0fc0bc5e): `gn-1850147~pond0` is Tokyo's beginner pond,
 * `~tea0..`, `~tackle0..`, `~market0..`, `~post0..`, and `~cabin0` for an S-tier trading post. clusterOf (travel.ts)
 * reads the cluster from the id, and placeOf below answers for a generated pond the way c.fishing.places does for a
 * hand-written one, so presence, casts and save loading treat both alike.
 *
 * Numbers come from content.world (assets/p0/content/world_gen.json: 李白's tiers, placement, word and name pools).
 * There is no built-up-area, coastline or water data offline yet: the tier is the population tier raised by a hand
 * list (world.area_tier), city traits come from world.coastal, and places are laid out by geometry alone.
 */
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { CityCluster, Climate } from './clusters.js';
import type { FishPlace, P0Content } from './content.js';
import { homeCluster } from './travel.js';
import { regionalFish as pondRegionalFish } from './fishing_world.js';

export type Tier = 'S' | 'M1' | 'M2' | 'L1' | 'L2' | 'L3';
export type Role = 'tea' | 'tackle' | 'market' | 'post';
export type Site = 'pond' | 'river' | 'coast';

export interface GenPond {
  id: string; name: string; site: Site; beginner: boolean; lat: number; lng: number;
  template_id: string; decoration_seed: number;
}
export interface GenOutpost {
  id: string; role: Role; name: string; lat: number; lng: number; category: string;
  keeper: { role: string; name: string; look: string }; residents: string[];
  art: string; anchors: string; capacity: number; nearest?: { name: string; site: Site }; cabin?: true;
}
export interface CityPlaces {
  cluster: string; tier: Tier; climate: Climate;
  ponds: string[]; outposts: string[]; residents: number;
  fish: { fish: string; level: number }[];
  detail: { ponds: GenPond[]; outposts: GenOutpost[] };
}

interface TierRow { tier: Tier; pop_max: number | null; tea?: number; tackle_max?: number; market?: number; travel?: number; trading_post?: number }
export interface WorldContent {
  revision: number; seed: string;
  tiers: TierRow[];
  placement: { market_1: { from_centre_km: [number, number]; beginner_pond_max_m: number }; travel_1: { from_centre_max_km: number };
    tea: { min_apart_km: number }; tackle: { shore_max_m: number }; market_n: { from_market_1_min_km: number };
    same_kind_min_km: number; other_kind_min_m: number };
  rooms: { indoor_cap: number; market_cap: number };
  tea_words: Record<string, string[]>;
  keeper_names: Record<string, string[]>;
  ponds: { base: number; per_pop: number; max: number; ring_km: [number, number]; words: string[]; suffix: Record<Site, string>; templates: string[] };
  area_tier: Record<string, Tier>;
  coastal: Record<string, string[]>;
  room: Record<Role | 'cabin', { art: string; anchors: string; category: string }>;
  keeper_roles: Record<Role, string>;
  keeper_looks?: Record<string, Record<string, string>>;
  residents?: ResidentRules;
}

interface ResidentRule { id: string; needs?: string[]; tier_min?: Tier; pop_max?: number; at?: string }
interface ResidentRules { per_outpost: number; rank: ResidentRule[]; fixed: Record<string, string>; s_order: ResidentRule[] }

const TIERS: Tier[] = ['S', 'M1', 'M2', 'L1', 'L2', 'L3'];
const CLIMATE_KEY: Record<Climate, string> = { tropical: 'Tropical', subtropical: 'Subtropical', temperate: 'Temperate', cool: 'Cool' };
/** The 12 resident names keepers never take (§9.3.2 name plates). */
const RESIDENT_NAMES = ['Pip', 'Kai', 'Wu', 'Mira', 'Rafa', 'Ivo', 'Hana', 'Sam', 'Lena', 'Tomo', 'Theo', 'Nadia'];
const KM_PER_DEG = 111.32;

/** 32 bits of sha256(seed:cluster:topic): the only randomness, so a city never changes between calls or servers. */
export function hash32(seed: string, cluster: string, topic: string): number {
  return createHash('sha256').update(`${seed}:${cluster}:${topic}`).digest().readUInt32BE(0);
}
const unit = (seed: string, cluster: string, topic: string) => hash32(seed, cluster, topic) / 0x1_0000_0000;

/** The point `km` from (lat, lng) at bearing `deg` (0 = north, clockwise), flat-earth: fine within a city. */
export function offset(lat: number, lng: number, km: number, deg: number): { lat: number; lng: number } {
  const r = (deg * Math.PI) / 180;
  const dLat = (km * Math.cos(r)) / KM_PER_DEG;
  const dLng = (km * Math.sin(r)) / (KM_PER_DEG * Math.max(0.05, Math.cos((lat * Math.PI) / 180)));
  return { lat: round6(lat + dLat), lng: round6(lng + dLng) };
}
const round6 = (v: number) => Math.round(v * 1e6) / 1e6;

/** Great-circle distance in km. */
export function km(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const rad = Math.PI / 180, dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.min(1, Math.sqrt(h)));
}

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
let memberPop: Map<string, number> | null = null;
/**
 * q(114) ①: a cluster's population is the sum of its member cities (server/data/city_cluster_members.tsv over
 * server/data/cities.tsv). The cluster table keeps its seed city's own figure (Miami 487,014 alone, 780,231 with its
 * members), which would make a metro area an S-tier town. Read once; a cluster missing from the files keeps its own.
 */
export function clusterPopulation(cl: CityCluster): number {
  if (!memberPop) {
    memberPop = new Map();
    const rows = (f: string) => readFileSync(path.join(ROOT, f), 'utf8').split('\n').filter(l => l && !l.startsWith('#')).map(l => l.split('\t'));
    const pop = new Map(rows('server/data/cities.tsv').map(r => [r[0], Number(r[7]) || 0] as [string, number]));
    for (const [city, cluster] of rows('server/data/city_cluster_members.tsv')) memberPop.set(cluster, (memberPop.get(cluster) ?? 0) + (pop.get(city) ?? 0));
  }
  return Math.max(cl.population, memberPop.get(cl.id) ?? 0);
}

/** §9.3.2: the larger of the population tier and the built-up-area tier (world.area_tier until there is area data). */
export function tierOf(w: WorldContent, cl: CityCluster): Tier {
  const people = clusterPopulation(cl);
  const byPop = w.tiers.find(t => t.pop_max === null || people < t.pop_max)?.tier ?? 'L3';
  const byArea = w.area_tier[cl.id];
  return byArea && TIERS.indexOf(byArea) > TIERS.indexOf(byPop) ? byArea : byPop;
}

/** §6.3.3: 3 ponds from the first 500,000 people, +1 per 500,000 more, at most 6. */
export function pondCount(w: WorldContent, cl: CityCluster): number {
  const p = w.ponds;
  return Math.min(p.max, p.base + Math.max(0, Math.floor((clusterPopulation(cl) - p.per_pop) / p.per_pop)));
}

/**
 * Ponds (§6.3.3): pond 0 is the beginner Pond on the 2.5 km ring nearest the centre, 1 a River, 2 a Coast for a
 * coastal cluster (else River), 3–5 by hash with at least one Pond kept. Ponds 0–2 sit at 0° / 120° / 240° of the
 * ring turned by the cluster's hash, 3–5 on the 5 km ring between them. Names from the word pool, never repeated
 * in a city, with the site's suffix (Pond / Creek / Cove).
 */
export function genPonds(w: WorldContent, cl: CityCluster, sites: Set<string>): GenPond[] {
  const n = pondCount(w, cl), seed = w.seed, coastal = (w.coastal[cl.id] ?? []).includes('coast');
  const turn = unit(seed, cl.id, 'pond-turn') * 360;
  const has = (s: Site): Site => (sites.has(s) ? s : 'river');   // no Coast site in the content yet: a River
  const kinds: Site[] = ['pond', 'river', coastal ? has('coast') : 'river'];
  for (let i = 3; i < n; i++) {
    const pick = (['pond', 'river', 'coast'] as Site[])[hash32(seed, cl.id, `pond-kind:${i}`) % 3];
    kinds.push(pick === 'coast' && !coastal ? 'river' : has(pick));
  }
  const words = [...w.ponds.words];
  const out: GenPond[] = [];
  for (let i = 0; i < n; i++) {
    const ring = i < 3 ? w.ponds.ring_km[0] : w.ponds.ring_km[1];
    const deg = i < 3 ? turn + i * 120 : turn + 60 + (i - 3) * 120;
    const at = offset(cl.lat, cl.lng, ring, deg);
    const word = words.splice(hash32(seed, cl.id, `pond-word:${i}`) % words.length, 1)[0];
    const site = kinds[i];
    out.push({
      id: `${cl.id}~pond${i}`, name: `${word} ${w.ponds.suffix[site]}`, site, beginner: i === 0, ...at,
      template_id: w.ponds.templates[hash32(seed, cl.id, `pond-shape:${i}`) % w.ponds.templates.length],
      decoration_seed: hash32(seed, cl.id, `pond-deco:${i}`),
    });
  }
  return out;
}

/** The place name an outpost takes: tea houses from the climate's word pool; the others from the cluster's name. */
function placeWord(w: WorldContent, cl: CityCluster, used: Set<string>, salt: string): string {
  const pool = w.tea_words[CLIMATE_KEY[cl.climate]] ?? w.tea_words.Temperate;
  for (let k = 0; k < pool.length; k++) {
    const word = pool[(hash32(w.seed, cl.id, salt) + k) % pool.length];
    if (!used.has(word)) { used.add(word); return word; }
  }
  return pool[hash32(w.seed, cl.id, salt) % pool.length];
}

/** Names ≤ 24 characters, no numbers (§9.3.2 name rules). The place name is the city's when it fits, else the word
 * pool's (no district data yet: the plan's order is district → quarter → satellite town → word pool). */
function named(w: WorldContent, cl: CityCluster, used: Set<string>, kind: string, salt: string, max = 24): string {
  const own = `${cl.name} ${kind}`;
  if (own.length <= max && !/[0-9]/.test(own) && !used.has(own)) { used.add(own); return own; }
  return `${placeWord(w, cl, used, salt)} ${kind}`;
}

/** Counts per role for a tier (§9.3.2 table, 李白's tiers row): tackle follows the ponds, at least one. */
export function outpostCounts(w: WorldContent, tier: Tier, ponds: number): Record<Role, number> {
  const row = w.tiers.find(t => t.tier === tier)!;
  if (tier === 'S') return { tea: 0, tackle: 0, market: 0, post: 0 };
  return { tea: row.tea ?? 0, tackle: Math.max(1, Math.min(ponds, row.tackle_max ?? 1)), market: row.market ?? 1, post: row.travel ?? 1 };
}

/**
 * Outposts (§9.3.2 placement): Travel Post 1 by the centre, Market Square 1 between 1 and 2 km out and ≤ 800 m from
 * the beginner pond (on the pond's side), tackle shops beside ponds (≤ 300 m from the shore, the beginner pond's
 * first), tea houses and further squares and posts spread on rings around the centre. Same kind ≥ 3 km apart,
 * different kinds ≥ 300 m: a candidate that breaks either turns round its ring until it fits. S tier: one trading post.
 */
export function genOutposts(w: WorldContent, cl: CityCluster, tier: Tier, ponds: GenPond[]): GenOutpost[] {
  const seed = w.seed, pl = w.placement;
  const out: GenOutpost[] = [];
  const used = new Set<string>();
  const sameKm = pl.same_kind_min_km, otherKm = pl.other_kind_min_m / 1000;
  const fits = (p: { lat: number; lng: number }, role: Role) =>
    out.every(o => km(o, p) >= (o.role === role ? sameKm : otherKm));
  const put = (role: Role, index: number, at: { lat: number; lng: number }, name: string, extra: Partial<GenOutpost> = {}) => {
    const room = w.room[extra.cabin ? 'cabin' : role];
    out.push({ id: `${cl.id}~${extra.cabin ? 'cabin' : role}${index}`, role, name, ...at, category: room.category,
      keeper: { role: w.keeper_roles[role], name: '', look: '' }, residents: [], art: room.art, anchors: room.anchors,
      capacity: role === 'market' ? w.rooms.market_cap : w.rooms.indoor_cap, ...extra });
  };
  /** Turn round the centre on a ring until the point fits; widen the ring if a whole turn cannot. */
  const spot = (role: Role, ringKm: number, deg: number) => {
    for (let r = ringKm; r <= ringKm + 6; r += 1.5) {
      for (let k = 0; k < 24; k++) {
        const p = offset(cl.lat, cl.lng, r, deg + k * 15);
        if (fits(p, role)) return p;
      }
    }
    return offset(cl.lat, cl.lng, ringKm + 7.5, deg);
  };
  const turn = (topic: string) => unit(seed, cl.id, topic) * 360;

  if (tier === 'S') {
    put('post', 0, offset(cl.lat, cl.lng, 0.6, turn('cabin')), named(w, cl, used, 'Trading Post', 'cabin-word'), { cabin: true });
    return out;
  }
  const n = outpostCounts(w, tier, ponds.length);
  const beginner = ponds.find(p => p.beginner)!;

  // Travel Post 1: within 1 km of the centre.
  put('post', 0, offset(cl.lat, cl.lng, Math.min(0.6, pl.travel_1.from_centre_max_km), turn('post0')), named(w, cl, used, 'Travel Post', 'post-word:0'));
  // Market Square 1: 1–2 km from the centre and ≤ 800 m from the beginner pond — on the line to the pond, 2 km out
  // of a 2.5 km ring pond is 500 m from it.
  const toPond = (Math.atan2((beginner.lng - cl.lng) * Math.cos((cl.lat * Math.PI) / 180), beginner.lat - cl.lat) * 180) / Math.PI;
  const m1Km = Math.min(pl.market_1.from_centre_km[1], Math.max(pl.market_1.from_centre_km[0], km(cl, beginner) - 0.5));
  put('market', 0, offset(cl.lat, cl.lng, m1Km, toPond), named(w, cl, used, 'Market Square', 'market-word:0'));
  // Tackle shops: one per pond, the beginner pond's first, 200 m off its shore, skipping a pond whose shop would sit
  // within 3 km of another (tackle follows ponds, up to the tier's count).
  for (const p of [...ponds].sort((a, b) => Number(b.beginner) - Number(a.beginner))) {
    if (out.filter(o => o.role === 'tackle').length >= n.tackle) break;
    const at = offset(p.lat, p.lng, Math.min(0.2, pl.tackle.shore_max_m / 1000), turn(`tackle:${p.id}`));
    if (!fits(at, 'tackle')) continue;
    const i = out.filter(o => o.role === 'tackle').length;
    put('tackle', i, at, `${p.name.split(' ')[0]} Tackle Shop`, { nearest: { name: p.name, site: p.site } });
  }
  // Tea houses: spread on rings (3, 5.5, 8 km …) at least 3 km apart; names from the climate's word pool.
  for (let i = 0; i < n.tea; i++) {
    const at = spot('tea', 3 + 2.5 * Math.floor(i / 3), turn(`tea${i}`) + i * 120);
    put('tea', i, at, `${placeWord(w, cl, used, `tea-word:${i}`)} Tea House`);
  }
  // Further market squares: ≥ 5 km from Market Square 1, spread round the centre.
  for (let i = 1; i < n.market; i++) {
    const at = spot('market', Math.max(pl.market_n.from_market_1_min_km, 5) + 1.5 * (i - 1), toPond + 180 + (i - 1) * 90);
    put('market', i, at, `${placeWord(w, cl, used, `market-word:${i}`)} Market Square`);
  }
  // Travel Post 2 (M2 and up): opposite Travel Post 1, on the far side of the city.
  for (let i = 1; i < n.post; i++) {
    const at = spot('post', 6 + 2 * (i - 1), turn('post0') + 180);
    put('post', i, at, `${placeWord(w, cl, used, `post-word:${i}`)} Travel Post`);
  }
  return out;
}

/**
 * Keeper name plates (§9.3.2): from the climate's pool, never twice in a city, never a resident's name. A city with
 * more counters than its pool borrows from the next climate band (the plan's pools hold 8; L2 / L3 need up to 17 —
 * flagged to 李白). Looks: `<role>_<climate>_<0..2>`, one of three per role and climate by the outpost's hash.
 */
export function nameKeepers(w: WorldContent, cl: CityCluster, outposts: GenOutpost[]): void {
  const bands = ['Tropical', 'Subtropical', 'Temperate', 'Cool'];
  const home = bands.indexOf(CLIMATE_KEY[cl.climate]);
  const order = [home, home + 1, home - 1, home + 2, home - 2, home + 3, home - 3].filter(i => i >= 0 && i < bands.length);
  const taken = new Set<string>();
  const left = order.map(i => (w.keeper_names[bands[i]] ?? []).filter(n => !RESIDENT_NAMES.includes(n)));
  for (const o of outposts) {
    const k = hash32(w.seed, cl.id, `keeper:${o.id}`);
    const band = left.find(names => names.some(n => !taken.has(n))) ?? [];
    const open = band.filter(n => !taken.has(n));
    o.keeper.name = open.length ? open[k % open.length] : 'Keeper';
    taken.add(o.keeper.name);
    o.keeper.look = `${o.cabin ? 'post' : o.role}_${cl.climate}_${k % 3}`;
  }
}

/** §6.2.5: the cluster's two regional fish with the level each needs — the same pair the cluster's ponds hold
 * (fishing_world.ts regionalFish: hand-picked cities, else hashed, the first able to bite in a Pond all day, q(109)),
 * so the city card never names a fish its ponds do not give (SGODOT-283). */
export function regionalFish(c: P0Content, cl: CityCluster): { fish: string; level: number }[] {
  const level = (id: string) => c.fish.find(f => f.id === id)?.level ?? 1;
  return pondRegionalFish(c, cl.id).map(f => ({ fish: f, level: level(f) }));
}

const worldOf = (c: P0Content) => (c as P0Content & { world?: WorldContent }).world;

/** A cluster's generated places, from the content's world block and the frozen cluster table. Throws for an unknown cluster. */
/**
 * Residents (§9.4.3): Pip at every travel post and trading post; Nadia at Market Square 1 and Sam at Travel Post 1
 * (M and up); then the rank list in order — a resident whose city traits (world.coastal: coast / river / highland) or
 * tier the city lacks is skipped — each to the outpost of their trade, never more than per_outpost residents in one
 * outpost, never more fixed residents than outposts in the city. S tier: the trading post holds Pip and the first
 * eligible of s_order. Ivo's Mine Hut is not built yet (he waits for it); Lena takes the tea house nearest the sea
 * (the plan's M-tier rule) until a Lighthouse Room exists.
 */
export function placeResidents(w: WorldContent, cl: CityCluster, tier: Tier, ponds: GenPond[], outposts: GenOutpost[], known: Set<string>): void {
  const rules = w.residents;
  if (!rules) return;
  const traits = new Set(w.coastal[cl.id] ?? []);
  const ok = (r: ResidentRule) => known.has(r.id) && (r.needs ?? []).every(t => traits.has(t))
    && (!r.tier_min || TIERS.indexOf(tier) >= TIERS.indexOf(r.tier_min)) && (r.pop_max === undefined || clusterPopulation(cl) < r.pop_max);
  const room = (o: GenOutpost | undefined) => !!o && o.residents.length < rules.per_outpost;
  const put = (o: GenOutpost | undefined, id: string) => { if (o && room(o) && known.has(id) && !o.residents.includes(id)) o.residents.push(id); };
  const placed = () => new Set(outposts.flatMap(o => o.residents));

  if (tier === 'S') {
    const cabin = outposts[0];
    put(cabin, rules.fixed.post);
    const first = rules.s_order.find(ok);
    if (first) put(cabin, first.id);
    return;
  }
  const byRole = (role: Role, n: number) => outposts.find(o => o.id === `${cl.id}~${role}${n}`);
  for (const o of outposts.filter(x => x.role === 'post')) put(o, rules.fixed.post);   // Pip in every travel post
  put(byRole('market', 0), rules.fixed['market:0']);
  const beginner = ponds.find(p => p.beginner);
  const tackleBy = (pond: GenPond | undefined) => outposts.find(o => o.role === 'tackle' && pond && o.nearest?.name === pond.name);
  const where = (at: string): GenOutpost | undefined => {
    if (at === 'tackle:beginner') return tackleBy(beginner);
    if (at === 'tackle:river') return tackleBy(ponds.find(p => p.site === 'river' && tackleBy(p))) ?? byRole('tackle', 1);
    if (at === 'tea:sea') return byRole('tea', 1) ?? byRole('tea', 0);   // no coastline geometry yet: the second tea house
    const [role, n] = at.split(':');
    return ['tea', 'tackle', 'market', 'post'].includes(role) ? byRole(role as Role, Number(n)) : undefined;
  };
  const cap = outposts.length;
  for (const r of rules.rank) {
    if (placed().size >= cap) break;
    if (!ok(r) || placed().has(r.id) || !r.at) continue;
    put(where(r.at), r.id);
  }
}

export function generateCity(c: P0Content, cl: CityCluster): CityPlaces {
  const w = worldOf(c);
  if (!w) throw new Error('p0 world: no world block in the content (assets/p0/content/world_gen.json)');
  const tier = tierOf(w, cl);
  const ponds = genPonds(w, cl, new Set(Object.keys(c.fishing.sites)));
  const outposts = genOutposts(w, cl, tier, ponds);
  nameKeepers(w, cl, outposts);
  placeResidents(w, cl, tier, ponds, outposts, new Set(Object.keys((c as P0Content & { residents?: Record<string, unknown> }).residents ?? {})));
  return {
    cluster: cl.id, tier, climate: cl.climate,
    ponds: ponds.map(p => p.id), outposts: outposts.map(o => o.id),
    residents: new Set(outposts.flatMap(o => o.residents)).size,
    fish: regionalFish(c, cl),
    detail: { ponds, outposts },
  };
}

/** The most recent CACHE_MAX cities, newest last: 12,490 clusters stay out of memory (256 MB container). */
const CACHE_MAX = 256;
const caches = new WeakMap<P0Content, Map<string, CityPlaces>>();

/** cityPlaces for GET /v1/p0/city/:cluster and travel.ts cityInfo: generated, cached by cluster. Null: no such cluster,
 * or the home city (hand-written, never generated). */
export function cityPlaces(c: P0Content, cluster: string): CityPlaces | null {
  let cache = caches.get(c);
  if (!cache) caches.set(c, cache = new Map());
  const hit = cache.get(cluster);
  if (hit) { cache.delete(cluster); cache.set(cluster, hit); return hit; }
  const cl = (c as P0Content & { clusters?: { get(id: string): CityCluster | undefined } }).clusters?.get(cluster);
  if (!cl || !worldOf(c) || cluster === homeCluster(c)) return null;   // the home city keeps its hand-written tables
  const made = generateCity(c, cl);
  cache.set(cluster, made);
  if (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value!);
  return made;
}

/**
 * A pond by id, hand-written or generated, shaped like c.fishing.places' entries: the one lookup presence, casts and
 * save loading use, so a pond in Tokyo is a pond the way Fern Pond is. Undefined: not a pond we know.
 */
export function placeOf(c: P0Content, id: string): (FishPlace & { cluster?: string }) | undefined {
  const own = c.fishing.places[id];
  if (own) return own;
  const cut = id.indexOf('~');
  if (cut <= 0) return undefined;
  const city = cityPlaces(c, id.slice(0, cut));
  const p = city?.detail.ponds.find(x => x.id === id);
  if (!p || !c.fishing.sites[p.site]) return undefined;
  return { name: p.name, site: p.site, city: city!.cluster, cluster: city!.cluster, beginner: p.beginner, at: [p.lat, p.lng] };
}
