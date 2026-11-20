/**
 * Gathering and coming home (plan §10.4.8, q(40); v4q(4), SGODOT-355). Gathering is a city's points (`<cluster>~<kind><n>`,
 * gather_points.ts; see gatherPoint): the farm's six spots (Timber Grove … Old Tree, 0 Energy, 8 h) left the farm with
 * v4q(4) ① (the user, 11-02), and Gather Gloves with them (丁11: batch 2 makes them again with the tools). Coming home
 * moves the bag's materials to storage; seeds, fertilizer, bait and torches stay with the player.
 * q(46): seasonings (Rock Salt, Wild Herb) travel with the player until the Spice Rack (Homestead Lv2): before it they go
 * to the bag like worms and stay there at home, because the Lv1 stove cooks from the bag; the upgrade puts them away.
 * TODO(P1): only at home; the P0 server trusts cmd.space (absent on older clients).
 */
import { add, room, take } from './bag.js';
import type { P0Content } from './content.js';
import type { Refusal } from './fishing.js';
import { unlocked } from './homestead.js';
import type { GatherPoint } from './gather_points.js';
import { gatherPointById } from './gather_points.js';
import { cityPondPoints, pondName, pondPointById, pondPoints, pondShape } from './pond_gather.js';
import { energyDetail, spendEnergy, type P0Event } from './progress.js';
import type { P0State } from './state.js';
import { putInStorage } from './storage.js';

const H = 3_600_000;


/** Rock Salt and Wild Herb (materials with an ingredient family, §7.3.1). */
export function isSeasoning(c: P0Content, id: string): boolean { return !!c.materials[id]?.ingr; }

/** Does a gathered or mined item go to the bag first? Consumables always; seasonings until the Spice Rack (q(46)). */
export function carried(c: P0Content, s: P0State, id: string): boolean {
  return !c.materials[id] || (isSeasoning(c, id) && !unlocked(c, s, 'spice_rack'));
}

/** The gather command: a pond's point (`<pond>#<slot>`, SGODOT-409) or a city's point by id; anything else (a farm
 * spot's old id too) is bad_spot. A pond's point is gathered in that pond: the player's place (presence.place, set by
 * the entry read and the command's own space / place, pond and pass checked) is that pond, else not_here.
 * U2 (the user, bot 613 / 614: the town's points go): for a client that gathers in the ponds alone (`ponds`, feature
 * `pond_guide`) a city's point is bad_spot too; an older one keeps them (奕星, a), as the city read keeps sending them. */
export function gather(c: P0Content, s: P0State, cmd: { spot?: unknown; space?: string }, now: number, events: P0Event[], ponds = false): Refusal | null {
  const inPond = pondPointById(c, cmd.spot);
  if (inPond) {
    if (s.presence.place !== inPond.pond) return { code: 'not_here', detail: { pond: inPond.pond } };
    return collect(c, s, inPond, false, now, events);
  }
  const point = ponds ? undefined : gatherPointById(c, cmd.spot);
  return point ? gatherPoint(c, s, point, cmd.space, now, events) : { code: 'bad_spot' };
}

/**
 * A city's gathering point (v4q(4) ③–⑤; the user, 11-02: 丁9 / 丁10 / 丁11): in that city — `travel.here` is its cluster,
 * so on the farm (here is home) a home city's points are gathered from the map too (丁9) — from Homestead Lv1 (丁3). One
 * tap: 3 Energy (the point's), ready again 4 h after (its cooldown_h, by point id and player); T1 gives 4, T2 3, a reed
 * bank 2 worms besides. Away it all goes to the bag, home with the player (storeMaterials): the whole main yield must
 * fit or nothing is gathered — no Energy, no cooldown (丁10: `No room · free a slot first`); worms that don't fit go to
 * Farm Storage (q(44)). On the farm (space `home`) the material goes to storage at once, as coming home would put it, the
 * bag not asked; worms and seasonings before the Spice Rack go to the bag as far as they fit, as the farm's spots did.
 */
export function gatherPoint(c: P0Content, s: P0State, point: GatherPoint, space: string | undefined, now: number, events: P0Event[]): Refusal | null {
  if (s.travel.here !== point.cluster) return { code: 'not_here', detail: { cluster: point.cluster } };
  return collect(c, s, point, space === 'home', now, events);
}

/** One tap on a point already judged to be where the player is: cooldown, tempo, Energy, the bag (see gatherPoint). */
function collect(c: P0Content, s: P0State, point: { id: string; energy: number; cooldown_h: number; yield: [string, number][] }, onFarm: boolean,
  now: number, events: P0Event[]): Refusal | null {
  const ready = s.gather.ready_at[point.id] ?? 0;
  if (now < ready) return { code: 'not_ready', detail: { ready_in: ready - now } };
  if (now - s.gather.last_at < c.gather.tempo_ms) return { code: 'tempo', detail: { ready_in: c.gather.tempo_ms - (now - s.gather.last_at) } };
  if (s.energy.value < point.energy) return { code: 'need_energy', detail: energyDetail(c, s, now, point.energy) };
  const [main] = point.yield;
  if (!onFarm && main && room(c, s, main[0]) < main[1]) return { code: 'bag_full', detail: { item: main[0], need: main[1] } };
  spendEnergy(c, s, now, point.energy, events, 'gather');
  const items: [string, number, 'storage' | 'bag'][] = [];
  for (const [item, qty] of point.yield) {
    const toBag = !onFarm || carried(c, s, item) ? Math.min(qty, room(c, s, item)) : 0;
    if (toBag > 0) { add(c, s, item, toBag); items.push([item, toBag, 'bag']); events.push({ kind: 'item', id: item, delta: toBag }); }
    if (qty - toBag > 0) { putInStorage(s, item, qty - toBag); items.push([item, qty - toBag, 'storage']); }
  }
  s.gather.ready_at[point.id] = now + point.cooldown_h * H;
  s.gather.last_at = now;
  events.push({ kind: 'gather', spot: point.id, items, ready_in: point.cooldown_h * H });
  return null;
}

/**
 * q(40): the first command or space read back at home moves the bag's materials (content.materials) into Farm Storage,
 * seasonings only once the Spice Rack is there (q(46)). Called from presence.notePresence; events is null on the read
 * path, so the last move is kept in storage_auto for the client to float once.
 * reason 'spice_rack': the Homestead Lv2 upgrade puts the bag's seasonings away (HOME-2 says so; no storage_auto float).
 */
export function storeMaterials(c: P0Content, s: P0State, now: number, events: P0Event[] | null, reason: 'home' | 'spice_rack' = 'home'): void {
  const moved = new Map<string, number>();
  for (const b of s.bag) {
    if (b.gift || !c.materials[b.id]) continue;
    if (reason === 'spice_rack' ? !isSeasoning(c, b.id) : carried(c, s, b.id)) continue;
    moved.set(b.id, (moved.get(b.id) ?? 0) + b.qty);
  }
  if (!moved.size) return;
  for (const [id, qty] of moved) { take(s.bag, id, qty, 'skip'); putInStorage(s, id, qty); }
  const items = [...moved];
  if (reason === 'home') s.storage_auto = { at: now, items };
  events?.push({ kind: 'stored', items, reason });
}

/** A point's cooldown is kept only while it runs (SGODOT-396 ④): one gone by is the same as none — ready, as every
 * reader takes a missing one — so the save does not grow with every point of every city the player ever gathered at. */
export function pruneGather(s: P0State, now: number): void {
  for (const [id, at] of Object.entries(s.gather.ready_at)) if (at <= now) delete s.gather.ready_at[id];
}

/** city_ready: the city points still cooling down, id → ms until ready (v4q(4); 亚瑟 on #659: in the view, which every
 * command brings back, not the city read, which the client keeps per city). The farm's spots left with v4q(4) ①. */
export function gatherView(c: P0Content, s: P0State, now: number) {
  const city_ready: Record<string, number> = {};
  for (const [id, at] of Object.entries(s.gather.ready_at)) if ((id.includes('~') || id.includes('#')) && at > now) city_ready[id] = at - now;
  return { city_ready, ...pondView(c, s, now) };
}

/** pond (SGODOT-409): the pond the player is in — its shape and its points: where they stand (pond scene metres), what
 * they give, how long until ready (0: now) and the whole cooldown (cooldown_h, hours: how far a point has grown back,
 * 不知火舞's gather-compact spec v1, 亚瑟) — or null out of a pond; the client draws them from this alone.
 * ponds: every pond of the home city and of the city the player is in, in or out of one: its name and its points' id,
 * kind, item (what it gives first: a reed bank's fiber; U2, 亚瑟) and ready_in (亚瑟's map and Today: the source line's
 * nearest ready pond, its pin's Show, the pond card's kinds). */
function pondView(c: P0Content, s: P0State, now: number) {
  const ready = (id: string) => Math.max(0, (s.gather.ready_at[id] ?? 0) - now);
  const here = s.presence.place, inPond = here ? pondPoints(c, here) : [];
  const pond = here && inPond.length ? { pond: here, shape: pondShape(c, here), points: inPond.map(p => ({ id: p.id, slot: p.slot, kind: p.kind,
    name: p.name, yield: p.yield, energy: p.energy, x: p.x, z: p.z, stand: p.stand, ready_in: ready(p.id), cooldown_h: p.cooldown_h })) } : null;
  const ponds: Record<string, { name: string; cluster: string; points: { id: string; kind: string; item: string; ready_in: number }[] }> = {};
  for (const cluster of new Set([s.travel.home, s.travel.here])) {
    for (const [id, pts] of cityPondPoints(c, cluster)) {
      ponds[id] = { name: pondName(c, id), cluster, points: pts.map(p => ({ id: p.id, kind: p.kind, item: p.yield[0][0], ready_in: ready(p.id) })) };
    }
  }
  return { pond, ponds };
}
