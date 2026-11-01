/**
 * q(272) (SGODOT-378, cross-city plan H step 2): local requests. Away from home (a second home too) every outpost keeper
 * gives the player some — per_day a city per player day (the home's 04:00, as today's 6 and the 100), drawn the first
 * time the player is there that day, each keeper drawing from its role's templates (content requests.local: fish at the
 * tackle shop, dishes at the tea house, crops at the market, materials at the travel post; an S-tier town's Trading Post
 * cabin all four). A template asks what it asks on a board (requirement, quantity, completion bonus, gates), drawn as
 * that city's Market Board would (its climate and regional fish). Taken and handed in at that keeper's outpost only,
 * dropped from anywhere; the coins only — the floor price and the template's bonus under the daily cap — never today's
 * 6, affinity, a title, a recipe, a stamp or XP. The tracked ones stay past their day (and outside the next day's
 * per_day); the untracked go at the next day's draw; a dropped one is not drawn again that day.
 */
import type { P0Content } from './content.js';
import type { Refusal } from './fishing.js';
import { drawable, handIn, haveForRequest, payout, regionalPool, requestFor, seededRand, tracked } from './boards.js';
import { everFish, pondCity } from './fishing_world.js';
import { homeFacts } from './home.js';
import { cityOutposts } from './home_city.js';
import type { P0Event } from './progress.js';
import { handOver, haveFor, noteDone, payBonus } from './requests.js';
import { dayKey, skillLevel } from './rules.js';
import type { BoardRequest, LocalCity, P0State } from './state.js';
import { clusterOf, homeOf, writtenCluster } from './travel.js';
import { cityPlaces } from './world.js';

export const LOCAL_PREFIX = 'req_loc_';
export const isLocal = (id: string) => id.startsWith(LOCAL_PREFIX);
const DAY = 86_400_000;

/** The keepers of a city who give local requests — each outpost whose role the content lists, its role and the
 * templates it draws from; a Trading Post cabin (`~cabin0`, an S-tier town's one keeper) draws from every role's. */
export function givers(c: P0Content, city: string): { place: string; role: string; templates: string[] }[] {
  const roles = c.requests.local?.roles ?? {};
  const all = [...new Set(Object.values(roles).flat())];
  return cityOutposts(c, city).flatMap(o => /~cabin\d+$/.test(o.id) ? [{ place: o.id, role: o.role, templates: all }]
    : roles[o.role] ? [{ place: o.id, role: o.role, templates: roles[o.role] }] : []);
}

/** The keeper giving a request: name plate and role as the outpost shows them, and the outpost's name (a generated
 * city's, or a hand-written one's from p0_outposts.json) — Deliver to names it from anywhere, the client not knowing
 * that city's places at home; empty where the city's places are not known. */
export function giverOf(c: P0Content, city: string, place: string): { giver: string; giver_role: string; place_name: string } {
  const gen = cityPlaces(c, city)?.detail.outposts.find(o => o.id === place);
  const own = (c.outposts ?? []).find(o => o.id === place);
  const k = gen?.keeper ?? own?.keeper;
  return { giver: k?.name ?? '', giver_role: k?.role ?? '', place_name: gen?.name ?? own?.name ?? '' };
}

/** A template a keeper may give in that city: as the city's Market Board could draw it, never an explore one; a fish one
 * only for a fish the player can land there now (奕星's review of q(272): River Run's trout where the city's waters hold
 * it, Local Waters' regional fish at the player's Fishing level). */
function localDrawable(c: P0Content, s: P0State, id: string, city: string): boolean {
  const t = c.requests.templates[id];
  if (!t || t.need.kind === 'visit' || t.need.where === 'not_home' || !drawable(c, s, id, 'market', city)) return false;
  if (t.need.kind !== 'fish') return true;
  if (t.need.id) return landable(c, s, t.need.id) && cityFish(c, city).has(t.need.id);
  return !t.need.regional || regionalPool(c, { travel: { home: city } }, t.need).some(f => landable(c, s, f));
}

/** A fish the player's Fishing level lands (a higher one gets away, §4.6). */
const landable = (c: P0Content, s: P0State, id: string) => (c.fish.find(f => f.id === id)?.level ?? Infinity) <= skillLevel(c, s, 'fishing');

const fishCache = new WeakMap<P0Content, Map<string, Set<string>>>();
/** Every fish a city's ponds and rivers can ever give (each site's habitat × the city's regional fish). */
export function cityFish(c: P0Content, city: string): Set<string> {
  let byCity = fishCache.get(c);
  if (!byCity) fishCache.set(c, byCity = new Map());
  let ids = byCity.get(city);
  if (!ids) {
    const sites = city === writtenCluster(c)
      ? Object.entries(c.fishing.places).filter(([id]) => pondCity(c, id).cluster === city).map(([, p]) => p.site)
      : (cityPlaces(c, city)?.detail.ponds ?? []).map(p => p.site);
    ids = new Set();
    for (const name of new Set(sites)) {
      const site = c.fishing.sites[name];
      if (site) for (const f of everFish(c, site, city)) ids.add(f.id);
    }
    byCity.set(city, ids);
  }
  return ids;
}

/**
 * The city the player is in, away from home, gets its day's local requests the first time that day: the tracked ones
 * kept, per_day new ones drawn from a stream of player, city and day (so the view and the next command draw the same),
 * dated from this stay's start as a city's Market Board (q(270) ①). Nothing at home, nor without the content.
 */
export function settleLocals(c: P0Content, s: P0State, now: number): void {
  const home = homeOf(c, s), here = s.travel?.here || home;
  if (!c.requests.local || here === home) return;
  const day = dayKey(c, s, now), had = s.locals?.[here];
  if (had?.day === day) return;
  const kept = (had?.slots ?? []).filter(sl => sl.req.status === 'accepted');
  const made = s.travel.passes[here]?.from ?? s.travel.visits[here]?.last_at ?? now;
  (s.locals ??= {})[here] = { day, slots: [...kept, ...drawLocals(c, s, here, day, made)] };
}

/** per_day requests on different keepers as far as they go, the roles first met first (q(272) ③); a keeper with no
 * template open to the player passes to the next; fewer when the city has too few. */
function drawLocals(c: P0Content, s: P0State, city: string, day: string, at: number): LocalCity['slots'] {
  const per = c.requests.local!.per_day, draw = seededRand(`${s.player}:local@${city}:${day}`);
  const shuffled = givers(c, city);
  for (let i = shuffled.length - 1; i > 0; i--) { const j = Math.floor(draw() * (i + 1)); [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]]; }
  const seen = new Set<string>();
  const first = shuffled.filter(g => !seen.has(g.role) && seen.add(g.role));
  const order = [...first, ...shuffled.filter(g => !first.includes(g))];
  const out: LocalCity['slots'] = [], used = new Set<string>();
  for (let n = 0; out.length < per && n < per * order.length; n++) {
    const g = order[n % order.length];
    const pool = g.templates.filter(id => !used.has(id) && localDrawable(c, s, id, city));
    if (!pool.length) continue;
    const template = pool[Math.floor(draw() * pool.length)];
    const req = requestFor(c, s, template, draw, 'market', city, `${LOCAL_PREFIX}${city}-${day}-${out.length}`, at,
      item => !item.startsWith('fish_') || landable(c, s, item));
    if (req) { out.push({ req, place: g.place }); used.add(template); }
  }
  return out;
}

/** The local requests the player sees: today's in the city they are in, and the tracked ones of every city. */
export function shownLocals(c: P0Content, s: P0State, now: number): { city: string; req: BoardRequest; place: string }[] {
  const here = s.travel?.here || homeOf(c, s), day = dayKey(c, s, now);
  return Object.entries(s.locals ?? {}).flatMap(([city, cell]) => cell.slots
    .filter(sl => sl.req.status === 'accepted' || (city === here && cell.day === day))
    .map(sl => ({ city, req: sl.req, place: sl.place })));
}

function findLocal(s: P0State, id: string): { city: string; cell: LocalCity; index: number } | null {
  for (const [city, cell] of Object.entries(s.locals ?? {})) {
    const index = cell.slots.findIndex(sl => sl.req.id === id);
    if (index >= 0) return { city, cell, index };
  }
  return null;
}

export function localCommand(c: P0Content, s: P0State, type: 'accept' | 'deliver' | 'drop', id: string, now: number, events: P0Event[],
  at: { space?: unknown; place?: unknown } = {}): Refusal | null {
  const found = findLocal(s, id);
  if (!found) return { code: s.req_done.includes(id) ? 'request_done' : 'bad_request' };
  const { city, cell, index } = found, slot = cell.slots[index], r = slot.req;
  if (r.status !== 'accepted' && cell.day !== dayKey(c, s, now)) return { code: 'bad_request' };   // a day gone: the next draw replaces it
  // q(272) ⑦: taken and handed in at the keeper's outpost (its greeting card is where the request shows); dropped anywhere
  if (type !== 'drop' && !(at.space === 'outpost' && at.place === slot.place)) return { code: 'wrong_place', detail: { place: slot.place, city } };
  if (type === 'accept') {
    if (r.status === 'accepted') return { code: 'already_accepted' };
    if (tracked(c, s) >= c.requests.track_max) return { code: 'track_limit', detail: { max: c.requests.track_max } };
    r.status = 'accepted';
    r.accepted_at = now;
    events.push({ kind: 'request', id, status: 'accepted', coins: 0 });
    return null;
  }
  if (type === 'drop') {   // gone for the day: the day's draw is not made again
    cell.slots.splice(index, 1);
    events.push({ kind: 'request', id, status: 'dropped', coins: 0 });
    return null;
  }
  const parts = handIn(c, s, r);
  if (!parts) {
    const short = r.items.length > 1 ? r.items.find(item => haveFor(c, s, { kind: r.kind }, [item]) < r.qty)! : null;
    return { code: 'not_enough', detail: short
      ? { item: short, need: r.qty, have: haveFor(c, s, { kind: r.kind }, [short]) }
      : { item: r.items[0] ?? null, need: r.qty, have: haveForRequest(c, s, r) } };
  }
  for (const [item, n] of parts) { handOver(c, s, item, n); events.push({ kind: 'item', id: item, delta: -n }); }
  const pay = payout(c, r, parts);
  const bonus = payBonus(c, s, pay.bonus);   // under the daily cap; not one of today's 6
  s.coins += pay.base + bonus;
  cell.slots.splice(index, 1);
  noteDone(s, id);
  events.push({ kind: 'coins', delta: pay.base + bonus }, { kind: 'request', id, status: 'done', coins: pay.base + bonus, bonus });
  return null;
}

/**
 * q(272) ⑪: a city not visited for prune_days, with nothing tracked there, loses its Market Board and its local
 * requests; the next visit makes them as a first one — they alone: its visits, stamp, Regular count and first-visit
 * gift stay (奕星's review). "Visited" is the later of the last arrival and the end of its Day Pass (a stay on one pass
 * does not move last_at). Never the home city, the one the player is in, one with a pass still running, nor the city of
 * the outpost or pond the player is still inside (a lapsed pass does not send them home from there).
 */
export function pruneCities(c: P0Content, s: P0State, now: number): void {
  const days = c.requests.local?.prune_days;
  if (!days) return;
  const t = s.travel, home = homeOf(c, s), here = t?.here || home;
  const inside = s.presence?.entered ? clusterOf(c, s.presence.entered) : null;
  for (const city of new Set([...Object.keys(s.markets ?? {}), ...Object.keys(s.locals ?? {})])) {
    if (city === home || city === here || city === inside) continue;
    const pass = t.passes[city]?.until ?? 0;
    if (pass > now || now - Math.max(t.visits[city]?.last_at ?? 0, pass) < days * DAY) continue;
    const held = (s.markets?.[city] ?? []).some(sl => sl.req?.status === 'accepted')
      || (s.locals?.[city]?.slots ?? []).some(sl => sl.req.status === 'accepted');
    if (held) continue;
    delete s.markets?.[city];
    delete s.locals?.[city];
  }
}

/** The city name the request is in, as a location chip writes it. */
export const cityName = (c: P0Content, city: string) => homeFacts(c, { travel: { home: city } }).name;
