/**
 * Stall Board and Market Board (plan §9.6, §9.13.2): drawn per player from the template pool, refilled 4 h after a
 * delivery and 8 h after a drop; an untaken request is swapped after 72 h. Draws happen in settleBoards, which the
 * view runs on a copy and every command runs on the save: ids and draw times come from the slot (its refill time),
 * never from the request's clock, so the id a client saw is the id the next command finds. Draws use their own
 * stream seeded by player, board, slot and time, so they never shift the fishing or cooking rolls.
 */
import { dishParts, type BoardId, type Need, type P0Content, type RequestTemplate } from './content.js';
import { everFish, pondCity, pondFishIds, regionalFish as pondRegional } from './fishing_world.js';
import type { Refusal } from './fishing.js';
import { boardSlots } from './homestead.js';
import type { P0Event } from './progress.js';
import { handOver, haveFor, floorPrice, noteDone, payBonus, pick, rarityOf } from './requests.js';
import { skillLevel, untilRollover } from './rules.js';
import { catalog } from './shops.js';
import type { BoardRequest, BoardSlot, P0State } from './state.js';
import { clusterById, clusterOf, homeClimate, homeOf, noteDelivery, rankedCities, writtenCluster } from './travel.js';
import { homeFacts, type Homed } from './home.js';
import { cityOutposts, homeSetOf } from './home_city.js';
import { cityPlaces, genPonds, type WorldContent } from './world.js';

const H = 3_600_000;
export const BOARDS: readonly BoardId[] = ['stall', 'market'];

/**
 * q(270) (SGODOT-378, §9.6.4): a board and the city it hangs in — the Stall Board at home, one Market Board per city
 * cluster (s.markets), the same board at every market square of that city. A city's board is made the first
 * time the player is there (settleBoards), so a city never visited takes no room in the save.
 */
export interface BoardAt { board: BoardId; city: string; slots: BoardSlot[] }
export function boardsOf(c: P0Content, s: P0State): BoardAt[] {
  const home = homeOf(c, s);
  return [{ board: 'stall', city: home, slots: s.boards.stall }, { board: 'market', city: home, slots: s.boards.market },
    ...Object.entries(s.markets ?? {}).filter(([city]) => city !== home).map(([city, slots]) => ({ board: 'market' as const, city, slots }))];
}
/** A board's slots: the Stall Board, the home Market Board (`market`), or another city's ([] while it has none yet). */
export function slotsOf(c: P0Content, s: P0State, board: BoardId, city = homeOf(c, s)): BoardSlot[] {
  return board === 'stall' ? s.boards.stall : city === homeOf(c, s) ? s.boards.market : s.markets?.[city] ?? [];
}
/** Whether a city has a Market Board to hang: home always; elsewhere a city with a market square (an S-tier town has none). */
export function hasMarket(c: P0Content, s: P0State, city: string): boolean {
  return city === homeOf(c, s) || cityOutposts(c, city).some(o => o.role === 'market');
}
/** A city as its board's draw reads it (climate, regional fish, outposts): the save itself at home, else that city as a home. */
const asHome = (c: P0Content, s: P0State, city: string): Homed => (city === homeOf(c, s) ? s : { travel: { home: city } });

export function slotCount(c: P0Content, s: P0State, board: BoardId): number {
  return board === 'stall' ? boardSlots(c, s) : c.requests.boards.market.slots ?? 2;
}

/** Any one gate opens it; a gate is a skill level or the Homestead level (李白's Clay for Pots: Homestead Lv2). */
function gateMet(c: P0Content, s: P0State, t: RequestTemplate): boolean {
  return t.gate.length === 0 || t.gate.some(([what, level]) => (what === 'homestead' ? s.homestead.level : skillLevel(c, s, what)) >= level);
}

/** §9.6.1: regional templates are drawn only where their climate is — the board's city's (q(270); the home's for the Stall Board). */
function climateMet(c: P0Content, h: Homed, t: RequestTemplate): boolean {
  return !t.climate?.length || t.climate.includes(homeClimate(c, h));
}

/**
 * The templates a board can draw now. A Market Board elsewhere (q(270) ②) draws from its own city — climate, regional
 * items and fish, Stamp Run's outposts in that city — and never a `home_only` template (content: those measured from
 * home, q(128)'s four and the two out-of-zone ones), which stay on the home city's board.
 */
export function eligible(c: P0Content, s: P0State, board: BoardId, city = homeOf(c, s)): string[] {
  return c.requests.boards[board].templates.filter(id => drawable(c, s, id, board, city));
}

/** One template can be drawn now for that board in that city (eligible); a keeper's local request (q(272)) asks it as
 * the city's Market Board would. */
export function drawable(c: P0Content, s: P0State, id: string, board: BoardId, city = homeOf(c, s)): boolean {
  const home = city === homeOf(c, s), h = asHome(c, s, city), t = c.requests.templates[id];
  return !!t && t.enabled !== false && gateMet(c, s, t) && climateMet(c, h, t) && (home || !t.home_only)
    && (!t.need.regional || regionalPool(c, h, t.need).length > 0) && (t.need.kind !== 'visit' || visitOpen(c, s, board, t.need, h))
    && (t.need.where !== 'not_home' || farTries(c, s).length > 0);
}

/** An explore template can be drawn: one of the board's city's outposts to send the player to (Stamp Run), or a city elsewhere with one. */
function visitOpen(c: P0Content, s: P0State, board: BoardId, need: Need, h: Homed = s): boolean {
  const v = need.visit;
  if (!v || v.where === 'same_city') return visitPlaces(c, board, h).length > 0;
  return crossCities(c, s, v).some(id => crossTarget(c, id, v.role ?? 'market') !== null);
}

/**
 * q(128) cross-city explore (李白; SGODOT-284): the cities a request may send the player to, nearest first — those of
 * the template's trip tiers (Tea Trail 1–2, Postcard Trip 2–3; the tier as the travel preview has it), or every city in
 * another climate zone than home's (New Climate takes the nearest that has an outpost).
 */
export function crossCities(c: P0Content, s: P0State, v: NonNullable<Need['visit']>): string[] {
  const ranked = rankedCities(c, s);
  if (v.where === 'other_zone') {
    const zone = clusterById(c, s.travel.home)?.climate;
    return ranked.filter(r => clusterById(c, r.id)?.climate !== zone).map(r => r.id);
  }
  const [lo, hi] = v.trip ?? [1, 7];
  return ranked.filter(r => r.trip >= lo && r.trip <= hi).map(r => r.id);
}

/** The outpost a cross-city request checks in at: the city's first of that role (`~tea0`, `~market0`), or, in a small
 * city, its Trading Post cabin (all four counters in one room). Null: the city has no places (no world content). */
export function crossTarget(c: P0Content, cluster: string, role: string): string | null {
  const outposts = cityPlaces(c, cluster)?.detail.outposts ?? [];
  const first = outposts.find(o => o.id === `${cluster}~${role}0`) ?? outposts.find(o => o.role === role && !o.cabin);
  return (first ?? outposts.find(o => o.cabin))?.id ?? null;
}

/** The home city's 2 regional fish (§6.2.5: content fishing.regional.curated by city name; generated cities come with 280). */
function cityFish(c: P0Content, s: Homed): string[] {
  const curated = (c.fishing as { regional?: { curated?: Record<string, string[]> } }).regional?.curated ?? {};
  return curated[homeFacts(c, s).name.toLowerCase()] ?? [];
}

/** Items a player can get somewhere today: a crop whose seed some counter sells, a fish some pond or river holds, a dish
 * page (it is cooked from such items). A regional template is drawn only when one of its items can be got, so turning
 * on the regional seeds (farm line) or the regional fish in the ponds (fishing line) opens it without another change. */
export function obtainable(c: P0Content, id: string): boolean {
  if (id.startsWith('crop_')) {
    const seed = c.crops.find(cr => cr.id === id)?.seed;
    return !!seed && (['homestead', 'tackle', 'market'] as const).some(shop => catalog(c, shop).includes(seed));
  }
  if (id.startsWith('fish_')) return pondFishIds(c).has(id);   // some pond gives it (habitat × the city's regional fish, SGODOT-283)
  if (id.startsWith('dish_')) return c.cooking.recipes.some(r => r.id === id) && c.cooking.recipes.find(r => r.id === id)!.in.every(x => !/^(crop|fish)_/.test(x) || obtainable(c, x));
  return true;
}

/** §9.6.3 regional: the items one regional template may ask for, home climate first; only those the player can get. */
export function regionalPool(c: P0Content, s: Homed, need: Need): string[] {
  const zone = homeClimate(c, s), rv = need.regional;
  const inZone = (z: string | string[] | undefined) => (Array.isArray(z) ? z.includes(zone) : z === zone);
  let ids: string[] = [];
  if (need.kind === 'crop') ids = c.crops.filter(cr => cr.regional && (rv === 'other_zone' ? cr.zone && cr.zone !== zone : inZone(cr.zone))).map(cr => cr.id);
  if (need.kind === 'fish') {
    ids = rv === 'city' ? cityFish(c, s)
      : c.fish.filter(f => f.regional && (rv === 'other_zone' ? !inZone(f.zones) : inZone(f.zones))).map(f => f.id);
  }
  if (need.kind === 'dish') {
    ids = c.cooking.recipes.filter(r => r.regional && (rv === 'other_zone' ? !(inZone(r.card_zone) || inZone(r.card_zones)) : inZone(r.card_zone) || inZone(r.card_zones)))
      .filter(r => need.max_rarity === undefined || rarityOf(c, r.id) <= need.max_rarity).map(r => r.id);
  }
  return ids.filter(id => obtainable(c, id));
}

/** §9.6.3 explore (Stamp Run): the home set's outposts a board request may send the player to (SGODOT-303) — not the
 * board's own (the Market Board hangs in the market square). */
export function visitPlaces(c: P0Content, board: BoardId, s: Homed): string[] {
  const set = homeSetOf(c, s);
  if (!set) return [];
  return (board === 'market' ? [set.tackle, set.tea, set.post] : [set.tackle, set.tea, set.post, set.market]);
}

/** What an empty board shows while no template is open yet: the lowest gate (e.g. Market Basket · Farming Lv4). */
export function lockedTemplate(c: P0Content, s: P0State, board: BoardId, city = homeOf(c, s)): { template: string; gate: [string, number][] } | null {
  // The lowest skill gate (`Dusk Haul · Fishing Lv3`, the first session's Market Board): a regional / explore template
  // that could not draw anything yet, or one gated by the Homestead level, is not named there.
  const closed = c.requests.boards[board].templates.filter(id => {
    const t = c.requests.templates[id];
    return t.enabled !== false && !t.need.regional && t.need.kind !== 'visit' && !t.gate.some(([g]) => g === 'homestead');
  });
  if (eligible(c, s, board, city).length || !closed.length) return null;
  const low = (id: string) => Math.min(...c.requests.templates[id].gate.map(g => g[1]));
  const template = [...closed].sort((a, b) => low(a) - low(b))[0];
  return { template, gate: c.requests.templates[template].gate };
}

export type Rand = () => number;

/** mulberry32 seeded from the slot's identity: the same slot at the same time always draws the same request. A Market
 * Board elsewhere (q(270)) adds its city, so two cities' boards never draw alike; the home boards keep their v5 seed. */
function slotRand(s: P0State, board: BoardId, slot: number, at: number, away = ''): Rand {
  return seededRand(`${s.player}:${board}${away ? `@${away}` : ''}:${slot}:${at}`);
}

/** mulberry32 seeded from a key's FNV-1a hash: its own stream, never shifting the fishing or cooking rolls. */
export function seededRand(key: string): Rand {
  let h = 2166136261;
  for (const ch of key) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
  let a = h | 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), a | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Quantity by the template's skill level: Lv1–3 2–3, Lv4–6 4–6, Lv7–10 6–10 (§9.6.2). */
function qtyFor(c: P0Content, s: P0State, t: RequestTemplate, draw: Rand): number {
  const level = skillLevel(c, s, t.skill);
  let band = c.requests.qty[0];
  for (const row of c.requests.qty) if (level >= row[0]) band = row;
  return Math.ceil((band[1] + Math.floor(draw() * (band[2] - band[1] + 1))) * (t.scale ?? 1) - 1e-9);
}

/** Crops the player can already buy seeds for (§9.6.2: a request never asks for what can't be grown yet). */
function growable(c: P0Content, s: P0State): string[] {
  const level = skillLevel(c, s, 'farming');
  return c.crops.filter(cr => cr.gate <= level).map(cr => cr.id);
}

function drawRequest(c: P0Content, s: P0State, board: BoardId, slot: number, at: number, city = homeOf(c, s)): BoardRequest | null {
  const open = eligible(c, s, board, city);
  if (!open.length) return null;
  const away = city === homeOf(c, s) ? '' : city;
  const draw = slotRand(s, board, slot, at, away);
  const taken = slotsOf(c, s, board, city).map(sl => sl.req?.template);
  const fresh = open.filter(t => !taken.includes(t));
  const pool = fresh.length ? fresh : open;
  const template = pool[Math.floor(draw() * pool.length)];
  return requestFor(c, s, template, draw, board, city, `${template}-${board}${slot}-${away ? `${away}-` : ''}${at.toString(36)}`, at);
}

/** The request one template makes in a city — its items and quantity from the draw's stream, after the template's own
 * pick (a board slot's, or a keeper's local request, q(272)); null when an explore one finds nowhere to send the player.
 * `keep`: the regional items it may ask for (a keeper's: only the fish the player can land now). */
export function requestFor(c: P0Content, s: P0State, template: string, draw: Rand, board: BoardId, city: string, id: string, at: number,
  keep: (item: string) => boolean = () => true): BoardRequest | null {
  const h = asHome(c, s, city), t = c.requests.templates[template];
  let items: string[] = [];
  let visit: BoardRequest['visit'];
  if (t.need.kind === 'visit' && t.need.visit && t.need.visit.where !== 'same_city') {   // cross-city: one city, its outpost
    const v = t.need.visit, cities = crossCities(c, s, v);
    // New Climate goes to the nearest such city; the trip-tier ones to any of their tier, from a drawn start
    const start = v.where === 'other_zone' ? 0 : Math.floor(draw() * cities.length);
    for (let k = 0; k < cities.length && !visit; k++) {
      const place = crossTarget(c, cities[(start + k) % cities.length], v.role ?? 'market');
      if (place) visit = { place, done: false };
    }
    if (!visit) return null;
  } else if (t.need.kind === 'visit') {   // explore: one outpost to check in at, no items
    const places = visitPlaces(c, board, h);
    visit = { place: places[Math.floor(draw() * places.length)], done: false };
  } else if (t.need.regional) {   // regional: one of the climate's / city's items
    const pool = regionalPool(c, h, t.need).filter(keep);
    if (!pool.length) return null;
    items = [pool[Math.floor(draw() * pool.length)]];
  } else if (t.need.id) items = [t.need.id];   // a template naming one crop, fish or material asks for exactly that
  // A crop request by rarity or family takes any such crop the player can grow (李白's Fine Produce, Orchard Basket).
  else if (t.need.kind === 'crop' && (t.need.rarity !== undefined || t.need.family !== undefined)) items = [];
  else if (t.need.kind === 'crop') {
    const crops = growable(c, s);
    for (let i = crops.length - 1; i > 0; i--) { const j = Math.floor(draw() * (i + 1)); [crops[i], crops[j]] = [crops[j], crops[i]]; }
    items = crops.slice(0, t.need.distinct ?? 1);
  }
  return {
    id, template, items, rarity: t.need.rarity,
    ...(t.need.style ? { style: t.need.style } : {}), ...(t.need.family ? { family: t.need.family } : {}), kind: t.need.kind as BoardRequest['kind'],
    qty: visit ? 1 : qtyFor(c, s, t, draw), bonus: t.bonus, drawn_at: at, status: 'open', ...(visit ? { visit } : {}),
    ...(t.need.where ? { where: t.need.where } : {}),
  };
}

/**
 * Bring the boards the player can reach up to now — the Stall Board, the home city's Market Board and, away, the Market
 * Board of the city they are in (made here the first time, q(270): its slots date from this stay's arrival, so the view
 * and the next command draw the same) — slot count follows the Homestead level; empty slots refill; untaken requests
 * expire. Another city's board waits as it was until the player is back there; its times catch up then.
 */
export function settleBoards(c: P0Content, s: P0State, now: number): void {
  const home = homeOf(c, s), here = s.travel?.here || home;
  s.markets ??= {};
  s.markets[home] = s.boards.market ??= [];   // `market` is the home board; markets[home] the same array (state.ts P0State.markets)
  const reach: [BoardId, string][] = [['stall', home], ['market', home]];
  if (here !== home && hasMarket(c, s, here)) reach.push(['market', here]);
  for (const [board, city] of reach) {
    const slots = board === 'stall' ? s.boards.stall : city === home ? s.boards.market : (s.markets[city] ??= []);
    // a city's board dates from this stay's start: the Day Pass's (q(270) ①), else the arrival (a free Trip 1 city)
    const made = city === home ? s.created_at : s.travel.passes[city]?.from ?? s.travel.visits[city]?.last_at ?? now;
    // §14.1.2: a Stall Board slot added in the account's first 72 h (slot 2 at creation, slot 3 from a Homestead Lv3
    // reached that early) stays empty until created_at + refill_h, so the first session has one request; a slot added
    // later fills at once.
    while (slots.length < slotCount(c, s, board))
      slots.push({ req: null, refill_at: board === 'stall' ? s.created_at + c.requests.refill_h * H : made });
    slots.forEach((sl: BoardSlot, i) => {
      // The tutorial request is once per account and never swapped out.
      while (sl.req?.status === 'open' && sl.req.id !== c.requests.tutorial.id && now >= sl.req.drawn_at + c.requests.expire_h * H) {
        const at = sl.req.drawn_at + c.requests.expire_h * H;
        sl.req = drawRequest(c, s, board, i, at, city);
        sl.refill_at = at;
      }
      if (!sl.req && now >= sl.refill_at) sl.req = drawRequest(c, s, board, i, sl.refill_at, city);
    });
  }
}

/**
 * §14.1.2: a Stall Board slot added in the account's first refill_h (72 h) stays empty until created_at + refill_h —
 * slot 2 at creation, and any slot a Homestead upgrade adds in that time. Until it fills it is a held slot (q(99),
 * 李白 / 不知火舞; wording 周瑜 on #168): the view draws it as a plain empty slot with no countdown and leaves it out of
 * `Next request`, which counts only slots refilling after a delivery or a drop. The rule itself is unchanged.
 */
export function heldSlot(c: P0Content, s: P0State, board: BoardId, sl: BoardSlot): boolean {
  return board === 'stall' && !sl.req && sl.refill_at === s.created_at + c.requests.refill_h * H;
}

/**
 * q(215) ④⑦: a guided save starts without Pond Catch (guide.pond_catch false), so the Stall Board's first slot is held
 * like slot 2. Delivering Nadia's first request (guide.stall_refill_on) refills it done_refill_h later, as delivering
 * Pond Catch would (`Next request 4h`, q(99)); the guide ending before that (the fallback, a changed table) refills it
 * at once. Only a first slot still held moves: one already drawn or counting down keeps its time.
 */
export function releaseFirstStallSlot(c: P0Content, s: P0State, at: number): void {
  const first = s.boards.stall?.[0];
  if (first && heldSlot(c, s, 'stall', first)) first.refill_at = at;
}

/**
 * Entering an outpost checks in a tracked explore request that sends the player there (§9.6.3 Stamp Run). A check-in
 * in another city counts as that city's delivery for its card (q(128): Deliveries +1 there, once a day; the hand-in at
 * home adds none); getting in already took a pass there (requirePass runs first).
 */
export function noteVisit(c: P0Content, s: P0State, space: unknown, place: unknown, now: number, events: P0Event[]): void {
  if (space !== 'outpost' || typeof place !== 'string') return;
  for (const { slots } of boardsOf(c, s)) for (const sl of slots) {
    const r = sl.req;
    if (r?.kind !== 'visit' || r.status !== 'accepted' || !r.visit || r.visit.done || r.visit.place !== place) continue;
    r.visit.done = true;
    events.push({ kind: 'visit', id: r.id, place });
    const city = clusterOf(c, place);
    if (city && city !== s.travel.home) noteDelivery(c, s, now, city);   // that city, whatever `here` says yet (周瑜 on #285: the entry read settles here after)
  }
}

const farCache = new WeakMap<P0Content, Map<string, string[]>>();   // per home city
/**
 * Far Pond (q(128) 甲; the user, 2026-10-10: what is in the bag counts, wherever and whenever it was caught): every fish
 * the home city's ponds don't have — neither one its ponds can ever give (each site's habitat × the city's regional
 * fish) nor one of its 2 regional fish. San Francisco: other cities' regional fish, and the Coast fish (no Coast site).
 */
export function farFish(c: P0Content, s: Homed): string[] {
  const home = homeOf(c, s);
  let byHome = farCache.get(c);
  if (!byHome) farCache.set(c, byHome = new Map());
  let ids = byHome.get(home);
  if (!ids) {
    const pool = new Set(pondRegional(c, home));
    // the written city's ponds are the hand-written ones; another home's, its generated ones (SGODOT-303)
    const sites = home === writtenCluster(c)
      ? Object.entries(c.fishing.places).filter(([id]) => pondCity(c, id).cluster === home).map(([, p]) => p.site)
      : (cityPlaces(c, home)?.detail.ponds ?? []).map(p => p.site);
    for (const name of sites) {
      const site = c.fishing.sites[name];
      if (site) for (const f of everFish(c, site, home)) pool.add(f.id);
    }
    byHome.set(home, ids = c.fish.map(f => f.id).filter(id => !pool.has(id)));
  }
  return ids;
}

/** How many fish Far Pond's example line names (q(128): `Try Tilapia, Smelt or Grey Mullet`). */
export const FAR_TRIES = 3;
const tryCache = new WeakMap<P0Content, WeakMap<object, Map<number, string[]>>>();
/**
 * Far Pond's draw check and its example line, one computation (q(128)): the Trip 1–3 cities nearest first and, of each,
 * the fish its ponds can give (any time, any weather) that Far Pond takes and the player can land at this Fishing level
 * — its regional fish first, then by level — up to FAR_TRIES. Empty: none within Trip 3 at this level, so Far Pond is
 * not drawn. Cached per home (rankedCities' list) and level; generating only the cities' ponds, it stops at the third.
 */
export function farTries(c: P0Content, s: P0State): string[] {
  const ranked = rankedCities(c, s), level = skillLevel(c, s, 'fishing');
  let byHome = tryCache.get(c);
  if (!byHome) tryCache.set(c, byHome = new WeakMap());
  let byLevel = byHome.get(ranked);
  if (!byLevel) byHome.set(ranked, byLevel = new Map());
  let out = byLevel.get(level);
  if (out) return out;
  out = [];
  const w = (c as P0Content & { world?: WorldContent }).world, far = new Set(farFish(c, s)), sites = new Set(Object.keys(c.fishing.sites));
  for (const city of ranked) {
    if (out.length >= FAR_TRIES || !w) break;
    const cl = clusterById(c, city.id);
    if (city.trip > 3 || !cl) continue;
    const here = new Set<string>(), regional = pondRegional(c, city.id);
    for (const p of genPonds(w, cl, sites)) for (const f of everFish(c, c.fishing.sites[p.site], city.id)) here.add(f.id);
    const fish = c.fish.filter(f => here.has(f.id) && far.has(f.id) && f.level <= level && !out!.includes(f.id))
      .sort((a, b) => Number(regional.includes(b.id)) - Number(regional.includes(a.id)) || a.level - b.level);
    out.push(...fish.slice(0, FAR_TRIES - out.length).map(f => f.id));
  }
  byLevel.set(level, out);
  return out;
}

/** The units a request's need counts in the bag now (its card's have): Far Pond the fish its home city's ponds don't have. */
export function haveForRequest(c: P0Content, s: P0State, r: BoardRequest): number {
  if (r.where === 'not_home') return farFish(c, s).length ? haveFor(c, s, { kind: 'fish' }, farFish(c, s)) : 0;
  return haveFor(c, s, { kind: r.kind, rarity: r.rarity, style: r.style, family: r.family }, r.items);
}

export function findBoardRequest(c: P0Content, s: P0State, id: string): { board: BoardId; city: string; slot: BoardSlot } | null {
  for (const { board, city, slots } of boardsOf(c, s)) for (const slot of slots) if (slot.req?.id === id) return { board, city, slot };
  return null;
}

/** Requests tracked now, every board of every city, the residents' and the keepers' local ones (q(272)) together
 * (track_max is the account's). */
export function tracked(c: P0Content, s: P0State): number {
  return boardsOf(c, s).reduce((n, b) => n + b.slots.filter(sl => sl.req?.status === 'accepted').length, 0)
    + Object.values(s.residents).filter(r => r.req).length
    + Object.values(s.locals ?? {}).reduce((n, l) => n + l.slots.filter(sl => sl.req.status === 'accepted').length, 0);
}

/** The bag units a board request would take now, or null when short. A visit takes nothing: it is ready once checked in. */
export function handIn(c: P0Content, s: P0State, r: BoardRequest): [string, number][] | null {
  if (r.kind === 'visit') return r.visit?.done ? [] : null;
  if (r.where === 'not_home') return farFish(c, s).length ? pick(c, s, { kind: 'fish' }, farFish(c, s), r.qty) : null;   // Far Pond: cheapest first
  if (r.items.length > 1) {   // Market Basket: N of each of the drawn crops
    const out: [string, number][] = [];
    for (const item of r.items) {
      const part = pick(c, s, { kind: r.kind }, [item], r.qty);
      if (!part) return null;
      out.push(...part);
    }
    return out;
  }
  return pick(c, s, { kind: r.kind, rarity: r.rarity, style: r.style, family: r.family }, r.items, r.qty);
}

/** Coins for a hand-in: floor prices, a dish quality bonus on the whole request (lowest quality handed in), the bonus capped daily. */
export function payout(c: P0Content, r: BoardRequest, parts: [string, number][]): { base: number; bonus: number } {
  const quality = r.kind === 'dish' && parts.length ? Math.min(...parts.map(([id]) => dishParts(id).quality)) : 0;
  const mult = 1 + (c.requests.quality_bonus[quality] ?? 0);
  const floor = parts.reduce((n, [id, q]) => n + floorPrice(c, id) * q, 0);
  return { base: Math.floor(floor * mult + 1e-9), bonus: Math.floor(r.bonus * mult + 1e-9) };
}

export function boardCommand(c: P0Content, s: P0State, type: 'accept' | 'deliver' | 'drop', id: string, now: number, events: P0Event[],
  at: { space?: unknown; place?: unknown } = {}): Refusal | null {
  const found = findBoardRequest(c, s, id);
  if (!found) return { code: s.req_done.includes(id) ? 'request_done' : 'bad_request' };
  const { slot } = found, r = slot.req!;
  // q(270) ①: a city's Market Board request is taken and handed in in that city — the outpost the command comes from
  // says which (a Day Pass keeps `here` on the map too: no hand-in from afar, §9.3.4); a command without one falls back
  // to the city the player is in. Only the city is checked, not that the outpost is a market square: the client sends
  // these from a market's board alone (亚瑟 on #606). A drop goes from anywhere (it hands nothing in).
  if (found.board === 'market' && type !== 'drop') {
    const from = at.space === 'outpost' && typeof at.place === 'string' ? clusterOf(c, at.place) : null;
    if ((from ?? (s.travel?.here || homeOf(c, s))) !== found.city) return { code: 'wrong_city', detail: { city: found.city } };
  }
  if (type === 'accept') {
    if (r.status === 'accepted') return { code: 'already_accepted' };
    if (tracked(c, s) >= c.requests.track_max) return { code: 'track_limit', detail: { max: c.requests.track_max } };
    r.status = 'accepted';
    r.accepted_at = now;   // q(143): Today keeps a row for the latest tracked request
    events.push({ kind: 'request', id, status: 'accepted', coins: 0 });
    return null;
  }
  if (type === 'drop') {
    slot.req = null;
    slot.refill_at = now + c.requests.drop_refill_h * H;
    events.push({ kind: 'request', id, status: 'dropped', coins: 0 });
    return null;
  }
  if (s.day.sys_done >= c.quotas.sys_requests.cap)
    return { code: 'daily_limit', detail: { cap: c.quotas.sys_requests.cap, resets_in: untilRollover(c, s, now) } };
  const parts = handIn(c, s, r);
  if (!parts && r.kind === 'visit') return { code: 'not_visited', detail: { place: r.visit?.place ?? null } };
  if (!parts) {
    const short = r.items.length > 1 ? r.items.find(item => haveFor(c, s, { kind: r.kind }, [item]) < r.qty)! : null;
    return { code: 'not_enough', detail: short
      ? { item: short, need: r.qty, have: haveFor(c, s, { kind: r.kind }, [short]) }
      : { item: r.items[0] ?? null, need: r.qty, have: haveForRequest(c, s, r) } };
  }
  for (const [item, n] of parts) { handOver(c, s, item, n); events.push({ kind: 'item', id: item, delta: -n }); }
  // §9.13.2 explore: a fixed reward with no floor (40 for Stamp Run), all of it a completion bonus under the daily cap.
  const pay = r.kind === 'visit' ? { base: 0, bonus: r.bonus } : payout(c, r, parts);
  const bonus = payBonus(c, s, pay.bonus);
  s.coins += pay.base + bonus;
  s.day.sys_done += 1;
  slot.req = null;
  slot.refill_at = now + c.requests.done_refill_h * H;
  noteDone(s, id);
  events.push({ kind: 'coins', delta: pay.base + bonus }, { kind: 'request', id, status: 'done', coins: pay.base + bonus, bonus });
  return null;
}
