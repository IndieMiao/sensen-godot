/**
 * New-player guide steps (SGODOT-341, 338·L1; plan in 341's comment f09e3203). The save keeps which step the player is
 * on and a count per guide key; every command (and the state read on entering a place) settles it once against the
 * step table, assets/p0/content/guide_steps.json (`guide`, filled from 339's §14 v3). The server only keeps the state:
 * the client draws the step from the same table (Today's first row, a TipCard, in-world marks), never locks a control
 * and never moves the player (LOCK-08).
 *
 * - Keys: what a command did, one name per kind (`sow:crop_radish`, `enter:sh_market_1`, `gift:res_nadia:dish_fish_soup`,
 *   see guideKeys). Only keys some step counts on are kept, so the save stays small.
 * - Counting comes first, whatever the step: something done ahead of its step is not lost, and the step is passed as
 *   soon as it comes up. A step is done when its count is reached (done_on; from_step: only what was done since the
 *   step began) or when the save already shows its result (done_if); one settle can pass several steps.
 * - Off the path (both radishes sold, the soup eaten): the step's needs fail and the view names a recover entry to show
 *   instead (`Sow 1 Radish`); nothing is refused, nothing goes back, and the save keeps no trace of it.
 * - While the guide is on, the map's pins are the shown step's own (339 §2, in place of q(48)'s first-session rule).
 * - Saves made before the guide, and new saves of clients that do not say they can show it, are `legacy`: no guide.
 *   A client says so with `x-p0-features: guide_v3` (the PR-C display layer); 0.2.11 already sends `guide` without it,
 *   so `guide` alone no longer starts the guide (341 c6f3189a).
 * - Places a step names may be the player's home set (`home:market`, `home:pond`, …, §9.3.2 / q(162)): the server reads
 *   them off the save, so the marks, the `enter:` keys and Today's names follow any home city, and a home change.
 * - view.guide carries what the client draws, resolved: Today's row with the place names filled in, the marks with real
 *   place ids and plots, the count, and Pip (q(222): on the farm while the guide is on, his `!` and his line).
 * - Pip gives two Quick Radish Seeds again when the player has run out (q(217) ③, at most `resend.max` times, counted in
 *   guide.n.resend); the guide ends by itself at the save's second home-day rollover (q(215), `end: 'timeout'`).
 */
import type { MapMarker, MarkerKind } from './markers.js';
import type { P0Content, Skill } from './content.js';
import { cropById, dishParts, ingredient, itemName, quickCrop, recipeById } from './content.js';
import { count, room } from './bag.js';
import { dayKey, maxEnergy, skillLevel } from './rules.js';
import { releaseFirstStallSlot } from './boards.js';
import { grantItems } from './parcels.js';
import { homeSetOf } from './home_city.js';
import { homeFacts, homeOf } from './home.js';
import { gatherPointsOf, type GatherPoint } from './gather_points.js';
import { upgradeBlock } from './homestead.js';
import { pondName, pondPoints } from './pond_gather.js';
import { cityPlaces, placeOf } from './world.js';
import type { HomeSet } from './travel.js';
import type { P0Event } from './progress.js';
import type { P0State } from './state.js';

const H = 3_600_000;

/** A condition on the save. Every field given must hold (an object is an AND); counts are "at least". */
export interface GuidePred {
  have?: Record<string, number>;      // held anywhere: bag, farm storage, Warming Cabinet
  planted?: Record<string, number>;   // plots holding the crop, sown or growing (ripe included)
  ripe?: Record<string, number>;      // plots whose crop is ready to harvest
  pot?: string;                       // a pot of this dish on any stove or queue
  keys?: Record<string, number>;      // guide counts reached
  done?: string;                      // a request handed in (req_done)
  known?: string;                     // a Cookbook page known
  coins?: number;
  level?: Partial<Record<Skill, number>>;
  energy_full?: boolean;              // Energy at its maximum (q(215) S8: a full bar cannot eat, so the meal step passes)
  gather?: Record<string, number>;    // S6a (v4q(11) ⑦): a beginner pond's point can be gathered now for one of these still short
  homestead?: number;                 // Homestead at least this level
  can_upgrade?: boolean;              // the next Homestead level can be bought now (S7a: else the step passes)
  fish?: number;                      // cookable fish held, any kind (S8–S10: enough fish to cook)
  dish?: number;                      // edible dishes held, any recipe (the Mystery Dish is not one; S10's ♥)
  common_crop?: number;               // Common crops held, any kind (q(217) ③: soup needs one)
  parcel?: string;                    // an Inbox parcel of this item not yet claimed, queued ones too (q(254) ①: Pip's seeds)
  meal?: true | MealWhere;            // S8 (SGODOT-368): a dish to eat is picked (mealPick), there if a place is named
  all?: GuidePred[]; any?: GuidePred[]; not?: GuidePred;
}

/** An in-world mark the client lights for the step (340). `place`: an id, `home` or `home:<role>` (the home set);
 * `plot: 'teach'`: the two teaching plots (view resolves both); the server also reads `place` for the map pins. */
/** The client's keys (341 de0bbb81, 5422f7e2): button — a HUD / panel control: `sow` / `water` / `harvest` / `cast` / `cook` /
 * `gift` / `request` / `location` (the location chip) / `quickbar:<item>`; object — a world object: `farmhouse` (its door's
 * mark), `stove`; page: a Cookbook page (its Cook key); item: a bag item's cell in the open drawer (the Gift drawer's soup);
 * plot: `teach` (the two teaching plots) / `teach1` (the first; view: plot ids). */
export interface GuideMark { place?: string; resident?: string; plot?: string; button?: string; object?: string; page?: string; item?: string; kind?: MarkerKind | 'gift'; pulse?: boolean; why?: string }
/** row.line / row.go, a mark's why and pip may name the home set: `{market}`, `{pond}`, … in a line, `home:<role>` in go
 * (`inbox`: the Inbox's Parcels page, q(254) ①); `{have}` / `{need}`: the count shown (the step's, or the recover
 * entry's own). row.countdown (a crop id): view adds ready_in (ms to that crop's soonest ripening, null if none grows),
 * count (its plots growing: one or more) and format (`mss` for a Quick Radish, q(217) ④; else `minutes`, q(97)); the
 * client writes `<line> in <time>`. */
export interface GuideShow { row?: Record<string, unknown>; tip?: string; marks?: GuideMark[]; pip?: string }
export interface GuideStep extends GuideShow {
  id: string; phase?: string;
  optional?: boolean;   // a suggestion that never holds the player up: it also passes once the step after it is done (339's t_sow_rest)
  done_on?: { key: string; count?: number; from_step?: boolean };
  done_if?: GuidePred;
  /** In order: the first whose `if` fails shows a recover entry — the first of `else` whose `when` holds (the last has none). */
  needs?: { if: GuidePred; else: string[] }[];
  /** S6a (v4q(11) ⑦ t_gather): the materials to gather and how many, in the order Today asks for them; view.guide.target
   * names the point (gatherTarget) and the row's `{gather_item}` / `{gather_spot}` (its pond's name) / icon `{gather}`
   * are filled from it. */
  gather?: Record<string, number>;
}
/** progress.fish: the entry's own count, cookable fish held against `fish` (339 2e08a1a1: `Catch 2 fish · 1/2`). */
export interface GuideRecover extends GuideShow { id: string; when?: GuidePred; progress?: { fish: number } }
export interface GuideContent {
  steps: GuideStep[]; recover?: GuideRecover[]; tips?: Record<string, string>;
  pond_catch?: boolean;   // false: a guided save starts without Pond Catch on the Stall Board (339 decides; default kept)
  /** The key that refills that held first slot done_refill_h later (q(215) ④: `deliver:req_res_nadia_radish`). */
  stall_refill_on?: string;
  /** q(217) ③ Pip's resend: `qty` of `item` when the player is out (see resendReady), at most `max` times a save. */
  resend?: { item: string; qty: number; max: number; line: string; radish: string; deliver: string; dish: string; source: string };   // source: the parcel's From line in the Inbox (苏烈 on #503)
  /** The home-day rollovers after the save was made at which an unfinished guide ends by itself (q(215): 2). */
  timeout_days?: number;
  /** S8's dish to eat (SGODOT-368, 不知火舞's spec): `prefer` first; else any other edible dish but `keep`; `keep` (the soup
   * S10 hands in) only with no cookable fish left. A shown line, icon, mark item or Pip line names it as `{dish}`. */
  meal?: { prefer: string; keep: string };
}

/** In the save (optional, no save version of its own). */
export interface GuideState {
  step: string | null;           // the current step; null once ended
  n: Record<string, number>;     // counts of the keys the step table names
  base?: Record<string, number>; // a from_step step's count when it began
  end?: 'done' | 'legacy' | 'timeout';   // timeout: the fallback end (q(215), timeout_days rollovers after start)
  at: number;                    // when the current step began
  start?: number;                // when the guide began (a new save); the fallback end counts rollovers from here
  ended_at?: number;             // when it ended (done or timeout)
}

/** The home-set roles a step may name as `home:<role>` (HomeSet, §9.3.2). */
const HOME_ROLES = ['market', 'tea', 'tackle', 'post', 'pond'] as const;
type HomeRole = typeof HOME_ROLES[number];

/** Keys a step may count on (validateGuide); `ack:<step>` is the guide command's (§2.2). */
export const GUIDE_KEY_KINDS = ['sow', 'water', 'harvest', 'buy', 'sell', 'enter', 'talk', 'gift', 'learn', 'cast', 'catch',
  'cook', 'dish', 'eat', 'accept', 'deliver', 'home_pick', 'travel', 'ack'] as const;
/** The client's built-in TipCard keys (P0Guide.TIPS) a step may name besides the table's own tips. */
const BUILT_IN_TIPS = ['sow', 'cast', 'creel', 'cook', 'heat', 'meal', 'map', 'travel'];

const stepsOf = (c: P0Content): GuideStep[] => c.guide?.steps ?? [];
const recoverOf = (c: P0Content, id: string) => c.guide?.recover?.find(r => r.id === id);

const counted = new WeakMap<P0Content, Set<string>>();
/** The keys the step table counts on (cached per content). */
function countedKeys(c: P0Content): Set<string> {
  let set = counted.get(c);
  if (!set) {
    set = new Set();
    const walk = (p?: GuidePred) => {
      if (!p) return;
      for (const k of Object.keys(p.keys ?? {})) set!.add(k);
      p.all?.forEach(walk); p.any?.forEach(walk); walk(p.not);
    };
    for (const st of stepsOf(c)) {
      if (st.done_on) set.add(st.done_on.key);
      walk(st.done_if);
      for (const n of st.needs ?? []) walk(n.if);
    }
    for (const r of c.guide?.recover ?? []) walk(r.when);
    // Pip's `!` (first talk) and the resend's two conditions are counted whatever the table says (q(222) ③, q(217) ③)
    set.add('talk:res_pip');
    if (c.guide?.resend) { set.add(c.guide.resend.deliver); set.add(c.guide.resend.dish); }
    counted.set(c, set);
  }
  return set;
}

/** A new save's guide: on when the client can show it and the table has steps, else legacy. */
export function freshGuide(c: P0Content, now: number, on: boolean): GuideState {
  const first = stepsOf(c)[0];
  return on && first ? enter(first, { step: null, n: {}, at: now, start: now }, now, stepsOf(c)[1]) : legacyGuide(now);
}
export const legacyGuide = (now: number): GuideState => ({ step: null, n: {}, end: 'legacy', at: now });
export const guideOn = (s: P0State): boolean => !!s.guide && s.guide.step !== null;

/** Begin a step. A from_step count starts here; so does the next step's when this one is optional, since the next
 * one may pass it (苏烈 on #472: else the look-ahead read the next step's count from the very start). */
function enter(st: GuideStep, g: GuideState, now: number, next?: GuideStep): GuideState {
  g.step = st.id; g.at = now;
  const base: Record<string, number> = {};
  for (const x of [st, ...(st.optional && next ? [next] : [])]) if (x.done_on?.from_step) base[x.done_on.key] = g.n[x.done_on.key] ?? 0;
  if (Object.keys(base).length) g.base = base;
  else delete g.base;
  return g;
}

/** Everything the player holds of an item: bag, farm storage, Warming Cabinet. */
const held = (s: P0State, id: string) => count(s.bag, id) + (s.storage[id] ?? 0) + s.cabinet.filter(x => x.id === id).reduce((n, x) => n + x.qty, 0);
/** Everything held of the items `ok` picks: bag, farm storage, Warming Cabinet. */
function heldWhere(s: P0State, ok: (id: string) => boolean): number {
  let n = 0;
  for (const x of s.bag) if (ok(x.id)) n += x.qty;
  for (const [id, q] of Object.entries(s.storage)) if (ok(id)) n += q;
  for (const x of s.cabinet) if (ok(x.id)) n += x.qty;
  return n;
}
const isCookFish = (c: P0Content, id: string) => id.startsWith('fish_') && ingredient(c, id) !== null;
const isCommonCrop = (c: P0Content, id: string) => !!cropById(c, id) && ingredient(c, id)?.rarity === 1;
function isEdibleDish(c: P0Content, id: string): boolean {
  const base = dishParts(id).base;
  return base !== c.cooking.mystery.id && !!recipeById(c, base);
}
export type MealWhere = 'bag' | 'pot' | 'cabinet';
/**
 * S8's dish to eat (SGODOT-368): its base recipe and where to eat it — the bag (anywhere), a done pot not yet taken (at
 * the stove: its card's Eat), the Warming Cabinet (at home). The dish by guide.meal's rule; for that dish, the bag before
 * the pot before the cabinet. null: nothing to eat, or only the soup while a fish is left to grill (the step's own Cook it).
 */
export function mealPick(c: P0Content, s: P0State, now: number): { dish: string; where: MealWhere } | null {
  const rule = c.guide?.meal;
  if (!rule) return null;
  const found: { dish: string; where: MealWhere }[] = [];
  const add = (id: string, where: MealWhere) => { if (isEdibleDish(c, id)) found.push({ dish: dishParts(id).base, where }); };
  for (const x of s.bag) if (x.qty > 0) add(x.id, 'bag');
  for (const p of pots(s)) {
    if (p.left?.length) p.left.forEach(id => add(id, 'pot'));
    else if (!p.mystery && p.started_at + p.ms <= now && [s.stove, ...(s.burners ?? []).map(b => b.stove)].includes(p)) add(p.dish, 'pot');
  }
  for (const x of s.cabinet) if (x.qty > 0) add(x.id, 'cabinet');
  const dish = found.find(f => f.dish === rule.prefer)?.dish ?? found.find(f => f.dish !== rule.keep)?.dish
    ?? (found.length && heldWhere(s, id => isCookFish(c, id)) === 0 ? rule.keep : null);
  if (!dish) return null;
  for (const where of ['bag', 'pot', 'cabinet'] as const) if (found.some(f => f.dish === dish && f.where === where)) return { dish, where };
  return null;
}

/** An Inbox parcel of this item not yet claimed, those queued behind a full Inbox too. */
const inboxHolds = (s: P0State, id: string) => [...s.inbox.parcels, ...s.inbox.waiting].some(p => p.id === id);
const pots = (s: P0State) => [s.stove, s.queue, ...(s.burners ?? []).flatMap(b => [b.stove, b.queue])].filter(p => p !== null);

/**
 * S6a's point (亚瑟's view.guide.target): the first material of `need` still short (held anywhere, as `have`) with a point
 * ready (none cooling down) that fits the bag; null: none can be gathered (a material whose points all cool down, or do
 * not fit, gives way to the next), and the step passes by its done_if. The same save always gets the same point.
 * - `ponds` (feature `pond_guide`, U2: the town's points are gone for that client, v4q(11) ⑦): the home set's beginner
 *   pond's (Timber 2, Stone 2, Reeds 1, Clay 1, pond_gather.ts: one trip gathers all S6a asks), the first in its order
 *   (a pond's point always gathers to the bag). `pond` names it.
 * - else (an older client, which looks the point up among the town's points; v4q(4) ⑥): a home-city town point, the one
 *   nearest the farm, the table's order breaking a tie; on the farm the bag is not asked (gathering there puts it in
 *   storage).
 */
export function gatherTarget(c: P0Content, s: P0State, need: Record<string, number>, now: number, ponds = false):
    { spot: { id: string; name: string }; pond?: string; item: string; left: number } | null {
  const short = Object.entries(need).map(([item, n]) => ({ item, left: n - held(s, item) })).filter(x => x.left > 0);
  const ready = (id: string) => (s.gather.ready_at[id] ?? 0) <= now;
  if (ponds) {
    const pond = guidePlace(c, s, 'home:pond'), points = pond ? pondPoints(c, pond) : [];
    for (const { item, left } of short) {
      const spot = points.find(p => p.yield[0]?.[0] === item && ready(p.id) && room(c, s, item) >= p.yield[0][1]);
      if (spot) return { spot: { id: spot.id, name: pondName(c, spot.pond) }, pond: spot.pond, item, left };
    }
    return null;
  }
  const points = gatherPointsOf(c, homeOf(c, s)), farm = homeFacts(c, s).farm;
  const far = (p: GatherPoint) => (farm ? (p.lat - farm.lat) ** 2 + ((p.lng - farm.lng) * Math.cos(farm.lat * Math.PI / 180)) ** 2 : 0);
  for (const { item, left } of short) {
    const open = points.filter(p => p.yield[0]?.[0] === item && ready(p.id) && (s.presence.space === 'home' || room(c, s, item) >= p.yield[0][1]));
    if (open.length) return { spot: open.reduce((a, b) => (far(b) < far(a) ? b : a)), item, left };
  }
  return null;
}

export function guidePred(c: P0Content, s: P0State, p: GuidePred | undefined, now: number, ponds = false): boolean {
  if (!p) return true;
  const g = s.guide;
  const plotsOf = (crop: string, ripe: boolean) => s.plots.filter(pl => pl.crop === crop && (pl.state === 'sown' || pl.state === 'growing')
    && (!ripe || (pl.state === 'growing' && (pl.ready_at ?? Infinity) <= now))).length;
  for (const [id, n] of Object.entries(p.have ?? {})) if (held(s, id) < n) return false;
  for (const [id, n] of Object.entries(p.planted ?? {})) if (plotsOf(id, false) < n) return false;
  for (const [id, n] of Object.entries(p.ripe ?? {})) if (plotsOf(id, true) < n) return false;
  if (p.pot !== undefined && !pots(s).some(x => x.dish === p.pot)) return false;
  for (const [k, n] of Object.entries(p.keys ?? {})) if ((g?.n[k] ?? 0) < n) return false;
  if (p.done !== undefined && !s.req_done.includes(p.done)) return false;
  if (p.known !== undefined && !s.cookbook.includes(p.known)) return false;
  if (p.coins !== undefined && s.coins < p.coins) return false;
  for (const [skill, n] of Object.entries(p.level ?? {})) if (skillLevel(c, s, skill as Skill) < (n ?? 0)) return false;
  if (p.energy_full !== undefined && (s.energy.value >= maxEnergy(c, s)) !== p.energy_full) return false;
  if (p.fish !== undefined && heldWhere(s, id => isCookFish(c, id)) < p.fish) return false;
  if (p.dish !== undefined && heldWhere(s, id => isEdibleDish(c, id)) < p.dish) return false;
  if (p.common_crop !== undefined && heldWhere(s, id => isCommonCrop(c, id)) < p.common_crop) return false;
  if (p.parcel !== undefined && !inboxHolds(s, p.parcel)) return false;
  if (p.gather !== undefined && !gatherTarget(c, s, p.gather, now, ponds)) return false;
  if (p.homestead !== undefined && s.homestead.level < p.homestead) return false;
  if (p.can_upgrade !== undefined && (upgradeBlock(c, s) === null) !== p.can_upgrade) return false;
  if (p.meal !== undefined) {
    const m = mealPick(c, s, now);
    if (!m || (p.meal !== true && m.where !== p.meal)) return false;
  }
  if (p.all && !p.all.every(q => guidePred(c, s, q, now, ponds))) return false;
  if (p.any && !p.any.some(q => guidePred(c, s, q, now, ponds))) return false;
  if (p.not && guidePred(c, s, p.not, now, ponds)) return false;
  return true;
}

/** How far the step's count is: have / need (have capped at need); null without done_on. */
function progress(st: GuideStep, g: GuideState): { have: number; need: number } | null {
  if (!st.done_on) return null;
  const k = st.done_on.key, need = st.done_on.count ?? 1;
  const have = (g.n[k] ?? 0) - (st.done_on.from_step ? g.base?.[k] ?? 0 : 0);
  return { have: Math.max(0, Math.min(have, need)), need };
}

function stepDone(c: P0Content, s: P0State, st: GuideStep, now: number, ponds: boolean): boolean {
  const p = progress(st, s.guide!);
  if (p && p.have >= p.need) return true;
  return st.done_if !== undefined && guidePred(c, s, st.done_if, now, ponds);
}

/** What a command (or a state read) did, as guide keys with counts. `before` is the save as it was before it. */
export function guideKeys(c: P0Content, before: P0State, s: P0State, cmd: { type?: string; [k: string]: unknown } | null, events: P0Event[]): Map<string, number> {
  const keys = new Map<string, number>();
  const add = (k: string, n = 1) => { if (n > 0) keys.set(k, (keys.get(k) ?? 0) + n); };
  // entering somewhere new: a space, and the pond or outpost in it
  const was = before.presence, now = s.presence;
  if (now.space && (now.space !== was.space || (now.entered ?? null) !== (was.entered ?? null))) {
    add(`enter:${now.space}`);
    if (now.entered) {
      add(`enter:${now.entered}`);
      const set = homeSetOf(c, s);   // the same place by its home-set role (`enter:home:market`), for any home city
      for (const role of HOME_ROLES) if (set?.[role] === now.entered) add(`enter:home:${role}`);
    }
  }
  // sown and watered plots, read off the plots themselves (a Row Hoe sows 3; under a sprinkler a sown plot is already growing)
  const old = new Map(before.plots.map(p => [p.id, p]));
  for (const p of s.plots) {
    const o = old.get(p.id);
    if (!p.crop || (p.state !== 'sown' && p.state !== 'growing')) continue;
    const fresh = !o || o.crop !== p.crop || (o.state !== 'sown' && o.state !== 'growing');
    if (fresh) add(`sow:${p.crop}`);
    if (p.state === 'growing' && (fresh || o!.state === 'sown')) add(`water:${p.crop}`);
  }
  const type = cmd?.type;
  for (const e of events) {
    switch (e.kind) {
      case 'item':
        if (type === 'harvest' && e.delta > 0 && cropById(c, e.id)) add(`harvest:${e.id}`, e.delta);
        if (type === 'buy' && e.delta > 0) add(`buy:${e.id}`, e.delta);
        break;
      case 'sale': add(`sell:${e.item}`, e.qty); add(`sell:${e.item}:${e.shop}`, e.qty); break;
      case 'cast': add('cast'); break;
      case 'catch': if (e.result === 'landed') { add('catch'); add(`catch:${e.fish}`); } break;
      case 'pot': add('cook'); if (e.dish) add(`cook:${e.dish}`); break;
      case 'dish': if (e.qty > 0 && !e.none) { add('dish', e.qty); add(`dish:${e.dish}`, e.qty); } break;
      case 'meal': add('eat'); add(`eat:${e.dish}`); break;
      case 'request': if (e.status === 'accepted') add(`accept:${e.id}`); else if (e.status === 'done') add(`deliver:${e.id}`); break;
      case 'home': if (e.action === 'chosen') add('home_pick'); break;
      case 'arrival': add(`travel:${e.cluster}`); break;
    }
  }
  if (type === 'talk' || type === 'learn') add(`${type}:${String(cmd!.resident)}`);
  if (type === 'gift') {
    // `gift:<resident>` is an edible dish given (q(215) S10: the Mystery Dish's −2 does not count); the item key names any
    if (dishParts(String(cmd!.item)).base !== c.cooking.mystery.id) add(`gift:${String(cmd!.resident)}`);
    add(`gift:${String(cmd!.resident)}:${String(cmd!.item)}`);
  }
  if (type === 'guide') add(`ack:${String(cmd!.step)}`);
  return keys;
}

/** Count what was done and pass every step now done. Runs after each command and on every state read (a read with no
 * keys still passes a step whose result came by itself: Quick Radishes ripe while the player only watched, 341 c6f3189a
 * ③). `events` (a command's) gets the step changes (`guide`, for the observation log, plan §14.8.1) and Pip's resend. */
export function settleGuide(c: P0Content, s: P0State, keys: Map<string, number>, now: number, events: P0Event[] = [], ponds = false): void {
  const g = s.guide;
  const refill = c.guide?.stall_refill_on;
  if (g && refill && keys.has(refill)) releaseFirstStallSlot(c, s, now + c.requests.done_refill_h * H);
  if (!g || g.step === null) return;
  if (timedOut(c, s, now)) { endGuide(c, s, now, events, 'timeout'); return; }   // q(215): the fallback end comes first
  const want = countedKeys(c);
  for (const [k, n] of keys) if (want.has(k)) g.n[k] = (g.n[k] ?? 0) + n;
  // q(217) ③: talking to Pip on the farm while he has seeds to give (his `!`) gives them
  if (keys.has('talk:res_pip') && s.presence.space === 'home' && resendReady(c, s)) resend(c, s, now, events);
  const steps = stepsOf(c);
  let i = steps.findIndex(st => st.id === g.step);
  if (i < 0) { endGuide(c, s, now, events); return; }   // a step the table no longer has (content changed): never strand the player
  const from = g.step;
  for (;;) {
    // an optional step whose next step is done (counted from the optional one's start) passes with it: both go
    const pass = stepDone(c, s, steps[i], now, ponds) ? 1
      : steps[i].optional && i + 1 < steps.length && stepDone(c, s, steps[i + 1], now, ponds) ? 2 : 0;
    if (!pass) break;
    i += pass;
    if (i >= steps.length) { endGuide(c, s, now, events); return; }
    enter(steps[i], g, now, steps[i + 1]);
  }
  if (g.step !== from) events.push({ kind: 'guide', action: 'step', from, to: g.step });
}

/** The fallback end (q(215)): the save has passed `timeout_days` home-day rollovers since the guide began. */
function timedOut(c: P0Content, s: P0State, now: number): boolean {
  const days = c.guide?.timeout_days, start = s.guide?.start;
  if (!days || start === undefined) return false;
  return (Date.parse(dayKey(c, s, now)) - Date.parse(dayKey(c, s, start))) / 86_400_000 >= days;
}

/**
 * Pip has seeds to give (q(217) ③): the guide is on, resends are left, and the player is out of Quick Radishes —
 * none held, none waiting in the Inbox, none sown, growing or ripe — while either Nadia's first request still wants a
 * Radish and none is held, or the soup is still to be made and no Common crop is held.
 */
export function resendReady(c: P0Content, s: P0State): boolean {
  const r = c.guide?.resend, g = s.guide;
  if (!r || !g || g.step === null || (g.n.resend ?? 0) >= r.max) return false;
  const quick = quickCrop(c, r.item)?.id;
  if (held(s, r.item) > 0) return false;
  if (inboxHolds(s, r.item)) return false;
  if (quick && s.plots.some(p => p.crop === quick && (p.state === 'sown' || p.state === 'growing'))) return false;
  const radishFor1 = (g.n[r.deliver] ?? 0) === 0 && held(s, r.radish) === 0;
  const cropForSoup = (g.n[r.dish] ?? 0) === 0 && heldWhere(s, id => isCommonCrop(c, id)) === 0;
  return radishFor1 || cropForSoup;
}

function resend(c: P0Content, s: P0State, now: number, events: P0Event[]): void {
  const r = c.guide!.resend!, g = s.guide!;
  const nth = (g.n.resend ?? 0) + 1;
  // the bag first, else a parcel (grantItems, §10.4.8); the key keeps a retried command from giving twice
  const bagged = grantItems(c, s, now, `guide_resend:${nth}`, r.source, [[r.item, r.qty]], events);
  if (bagged === null) return;
  g.n.resend = nth;
  events.push({ kind: 'guide', action: 'resend', item: r.item, qty: r.qty, bagged: bagged[r.item] ?? 0, left: r.max - nth });
}

/** At load (upgradeState): a guide on a step the table no longer has ends at once, not on the next command (苏烈 on #472). */
export function checkGuideTable(c: P0Content, s: P0State, now: number): void {
  const g = s.guide;
  if (g?.step && !stepsOf(c).some(st => st.id === g.step)) endGuide(c, s, now);
}

/** The guide's one way out. A Stall Board first slot still held (Nadia's first request not delivered) fills now
 * (q(215) ⑦: the fallback end refills it at once). Pip leaves the farm with it (view.guide.pip.here false). */
function endGuide(c: P0Content, s: P0State, now: number, events: P0Event[] = [], end: 'done' | 'timeout' = 'done'): void {
  const g = s.guide!;
  const from = g.step;
  g.step = null; g.end = end; g.at = now; g.ended_at = now;
  delete g.base;
  releaseFirstStallSlot(c, s, now);
  events.push({ kind: 'guide', action: 'end', from, to: null, end });
}

/** The current step's recover entry when its needs fail, else null. */
export function guideRecover(c: P0Content, s: P0State, now: number, ponds = false): string | null {
  const st = currentStep(c, s);
  for (const need of st?.needs ?? []) {
    if (guidePred(c, s, need.if, now, ponds)) continue;
    const pick = need.else.find(id => guidePred(c, s, recoverOf(c, id)?.when, now, ponds));
    return pick ?? need.else[need.else.length - 1] ?? null;
  }
  return null;
}

const currentStep = (c: P0Content, s: P0State) => s.guide?.step ? stepsOf(c).find(st => st.id === s.guide!.step) : undefined;

/** `ack` (the guide command, plan §2.2): only the current step, and only one that waits for exactly that. */
export function guideAck(c: P0Content, s: P0State, step: unknown): { code: string } | null {
  const st = currentStep(c, s);
  if (!st || st.id !== step || st.done_on?.key !== `ack:${st.id}`) return { code: 'guide_not_now' };
  return null;
}

/** A place a step names, as the save sees it: `home:<role>` is the home set's (null when the save has none). */
export function guidePlace(c: P0Content, s: P0State, place: string): string | null {
  if (!place.startsWith('home:')) return place;
  return homeSetOf(c, s)?.[place.slice(5) as HomeRole] ?? null;
}

/** A place's display name: a pond's, an outpost's (the written table or the generated city's). */
function placeName(c: P0Content, id: string): string {
  if (id === 'home') return 'Home';   // SGODOT-461: Homestead is Home in English
  const pond = placeOf(c, id);
  if (pond) return pond.name;
  const own = (c.outposts ?? []).find(o => o.id === id);
  if (own?.name) return own.name;
  const cut = id.indexOf('~');
  const gen = cut > 0 ? cityPlaces(c, id.slice(0, cut))?.detail.outposts.find(o => o.id === id) : undefined;
  return gen?.name ?? id;
}

/** `{market}` / `{pond}` / … in a line: the home set's names (q(162): every home city its own); `{have}` / `{need}`: the count. */
function fill(c: P0Content, s: P0State, line: string, count: { have: number; need: number } | null = null): string {
  const set: HomeSet | null = homeSetOf(c, s);
  return line.replace(/\{(market|tea|tackle|post|pond)\}/g, (all, role: HomeRole) => (set?.[role] ? placeName(c, set[role]) : all))
    .replace(/\{(have|need)\}/g, (all, k: 'have' | 'need') => (count ? String(count[k]) : all));
}

/** The two teaching plots (q(222), 340 GUIDE-S2): plots holding a Quick Radish first, then the lowest empty tilled ones. */
function teachPlots(c: P0Content, s: P0State): number[] {
  const quick = c.guide?.resend ? quickCrop(c, c.guide.resend.item)?.id : undefined;
  const sown = s.plots.filter(p => quick && p.crop === quick && (p.state === 'sown' || p.state === 'growing')).map(p => p.id);
  const built = new Set((s.facilities ?? []).map(f => f.plot));
  const free = s.plots.filter(p => p.state === 'tilled' && !p.crop && !built.has(p.id)).map(p => p.id);
  return [...sown, ...free].slice(0, 2);
}

/** The marks resolved: real place ids (a home role the save lacks drops), `plot: 'teach'` as one mark per plot. */
function resolveMarks(c: P0Content, s: P0State, marks: GuideMark[] = [], count: { have: number; need: number } | null = null) {
  const out: (Omit<GuideMark, 'plot'> & { plot?: number | string })[] = [];
  for (const m of marks) {
    const place = m.place !== undefined ? guidePlace(c, s, m.place) : undefined;
    if (place === null) continue;
    if (m.plot === 'teach' || m.plot === 'teach1') {   // teach1: the first only (q(229): `Sow 1 Radish`, one plot's halo)
      for (const id of teachPlots(c, s).slice(0, m.plot === 'teach1' ? 1 : 2)) out.push({ ...m, plot: id });
      continue;
    }
    out.push({ ...m, ...(place !== undefined ? { place } : {}), ...(m.why !== undefined ? { why: fill(c, s, m.why, count) } : {}) });
  }
  return out;
}

/** A countdown row's numbers (341 de0bbb81): the crop's plots growing and the soonest one's time left. */
function countdown(c: P0Content, s: P0State, crop: string, now: number) {
  const growing = s.plots.filter(p => p.crop === crop && p.state === 'growing' && p.ready_at !== undefined);
  const soonest = growing.reduce((m, p) => Math.min(m, p.ready_at!), Infinity);
  return { ready_in: growing.length ? Math.max(0, soonest - now) : null, count: growing.length, format: quickCrop(c, crop) ? 'mss' : 'minutes' };
}

/** The count shown: a recover entry's own (progress.fish), else the step's. */
function shownProgress(c: P0Content, s: P0State, st: GuideStep, rec: string | null) {
  const own = rec ? recoverOf(c, rec)?.progress : undefined;
  if (own) return { have: Math.min(heldWhere(s, id => isCookFish(c, id)), own.fish), need: own.fish };
  return progress(st, s.guide!);
}

/**
 * view.guide (341 c6f3189a ②): the step and its count, the recover entry shown instead, and what the client draws for
 * whichever is shown — Today's row (names filled, `go` a real place or `home`), the marks resolved, Pip on the farm
 * ({here, bang: his `!`, line, resend_left}). {step: null, end, ended_at} once there is none.
 */
export function guideView(c: P0Content, s: P0State, now: number, ponds = false) {
  const g = s.guide;
  const st = currentStep(c, s);
  if (!g || !st) return { step: null, end: g?.end ?? (g?.step ? 'done' : 'legacy'), ended_at: g?.ended_at ?? null, pip: { here: false } };
  const rec = guideRecover(c, s, now, ponds);
  const shown: GuideShow = rec ? recoverOf(c, rec) ?? {} : st;
  const count = shownProgress(c, s, st, rec);
  const row = shown.row ? { ...shown.row } : null;
  const meal = rec ? mealPick(c, s, now) : null;   // only a `{dish}` in what is shown takes it (S8's eat entries)
  const dish = (x: string) => (meal ? x.replace(/\{dish\}/g, m => (x === m ? meal.dish : itemName(c, meal.dish))) : x);   // alone: the id
  if (row) for (const k of ['line', 'icon'] as const) if (typeof row[k] === 'string') row[k] = dish(row[k] as string);
  const target = !rec && st.gather ? gatherTarget(c, s, st.gather, now, ponds) : null;
  if (row && target) {
    if (typeof row.line === 'string') row.line = row.line.replace('{gather_item}', itemName(c, target.item)).replace('{gather_spot}', target.spot.name);
    if (row.icon === '{gather}') row.icon = target.item;
  }
  if (row && typeof row.line === 'string') row.line = fill(c, s, row.line, count);
  if (row && typeof row.go === 'string') row.go = guidePlace(c, s, row.go);
  if (row && typeof row.countdown === 'string') Object.assign(row, countdown(c, s, row.countdown, now));
  const ready = resendReady(c, s), r = c.guide?.resend;
  const pipLine = ready && r ? r.line : shown.pip ?? st.pip;
  return {
    step: st.id, phase: st.phase ?? null, recover: rec, at: g.at, progress: count,
    row, tip: shown.tip ?? null,
    // absent in JSON when none; pond (pond_guide): the point's pond (亚瑟: away from it Show opens the map at it, in it marks the spot)
    target: target ? { kind: 'gather' as const, spot: target.spot.id, item: target.item, pond: target.pond } : undefined,
    marks: resolveMarks(c, s, shown.marks, count).map(m => (meal && typeof m.item === 'string' ? { ...m, item: dish(m.item) } : m)),
    pip: { here: true, bang: (g.n['talk:res_pip'] ?? 0) === 0 || ready, line: pipLine ? fill(c, s, dish(pipLine)) : null,
      resend_left: r ? Math.max(0, r.max - (g.n.resend ?? 0)) : 0 },
    end: null, ended_at: null,
  };
}

/** The map pins of the step shown (or its recover entry), tracked; while the guide is on they are the only ones (markers.ts). */
export function guideMarkers(c: P0Content, s: P0State, now: number, ponds = false): MapMarker[] {
  const st = currentStep(c, s);
  if (!st) return [];
  const rec = guideRecover(c, s, now, ponds);
  const shown: GuideShow = rec ? recoverOf(c, rec) ?? {} : st;
  return resolveMarks(c, s, shown.marks, shownProgress(c, s, st, rec)).filter(m => m.place)
    .map(m => ({ place: m.place!, kind: (m.kind === 'gift' ? 'request' : m.kind ?? 'request') as MarkerKind,
      why: { guide: rec ?? st.id, tracked: true as const } }));
}

/** dev/guide: put the save's guide on a step (`first`, `end` or an id), counts cleared; nothing else changes. */
export function setGuide(c: P0Content, s: P0State, to: string, now: number): { code: string } | null {
  const steps = stepsOf(c);
  if (to === 'end') { s.guide = { step: null, n: {}, end: 'done', at: now, ended_at: now }; releaseFirstStallSlot(c, s, now); return null; }
  const st = to === 'first' ? steps[0] : steps.find(x => x.id === to);
  if (!st) return { code: 'bad_step' };
  s.guide = enter(st, { step: null, n: {}, at: now, start: now }, now, steps[steps.indexOf(st) + 1]);
  return null;
}

/** What is wrong with the step table (the content test runs it): unknown ids, keys, items, places, tips, dead ends. */
export function validateGuide(c: P0Content): string[] {
  const out: string[] = [];
  const steps = stepsOf(c), recover = c.guide?.recover ?? [];
  const tips = new Set([...BUILT_IN_TIPS, ...Object.keys(c.guide?.tips ?? {})]);
  const places = new Set(['home', ...HOME_ROLES.map(r => `home:${r}`), ...(c.outposts ?? []).map(o => o.id), ...Object.keys(c.fishing.places)]);
  const known = (id: string) => itemName(c, id) !== id || c.cooking.recipes.some(r => r.id === id);
  const ids = new Set<string>();
  for (const x of [...steps, ...recover]) { if (ids.has(x.id)) out.push(`duplicate id ${x.id}`); ids.add(x.id); }
  const key = (where: string, k: string) => {
    const kind = k.split(':')[0];
    if (!(GUIDE_KEY_KINDS as readonly string[]).includes(kind)) out.push(`${where}: unknown key ${k}`);
  };
  const pred = (where: string, p?: GuidePred) => {
    if (!p) return;
    for (const id of [...Object.keys(p.have ?? {}), ...Object.keys(p.planted ?? {}), ...Object.keys(p.ripe ?? {}),
      ...Object.keys(p.gather ?? {}), ...(p.pot ? [p.pot] : []), ...(p.known ? [p.known] : []), ...(p.parcel ? [p.parcel] : [])]) if (!known(id)) out.push(`${where}: unknown item ${id}`);
    for (const k of Object.keys(p.keys ?? {})) key(where, k);
    p.all?.forEach(q => pred(where, q)); p.any?.forEach(q => pred(where, q)); pred(where, p.not);
  };
  const show = (where: string, x: GuideShow) => {
    if (x.tip && !tips.has(x.tip)) out.push(`${where}: unknown tip ${x.tip}`);
    for (const m of x.marks ?? []) {
      if (m.place && !places.has(m.place)) out.push(`${where}: unknown place ${m.place}`);
      if (m.plot !== undefined && m.plot !== 'teach' && m.plot !== 'teach1') out.push(`${where}: unknown plot ${m.plot} (only "teach" / "teach1")`);
      if (m.resident && !c.residents[m.resident]) out.push(`${where}: unknown resident ${m.resident}`);
    }
  };
  if (c.guide?.stall_refill_on !== undefined) key('stall_refill_on', c.guide.stall_refill_on);
  const rs = c.guide?.resend;
  if (rs) {
    if (!known(rs.item) || !known(rs.radish)) out.push(`resend: unknown item ${rs.item} / ${rs.radish}`);
    key('resend', rs.deliver); key('resend', rs.dish);
  }
  steps.forEach((st, i) => {
    if (st.optional && (i + 1 >= steps.length || steps[i + 1].optional)) out.push(`step ${st.id}: an optional step needs a step after it that is not optional`);
  });
  for (const st of steps) {
    const at = `step ${st.id}`;
    if (!st.done_on && !st.done_if) out.push(`${at}: neither done_on nor done_if`);
    if (st.done_on) key(at, st.done_on.key);
    if (st.done_on?.key.startsWith('ack:') && st.done_on.key !== `ack:${st.id}`) out.push(`${at}: an ack step acks itself`);
    pred(at, st.done_if);
    for (const id of Object.keys(st.gather ?? {})) if (!known(id)) out.push(`${at}: unknown gather item ${id}`);
    show(at, st);
    for (const n of st.needs ?? []) {
      pred(at, n.if);
      if (!n.else.length) out.push(`${at}: a need with no recover entry`);
      for (const id of n.else) if (!recover.some(r => r.id === id)) out.push(`${at}: unknown recover ${id}`);
      const last = recover.find(r => r.id === n.else[n.else.length - 1]);
      if (last?.when) out.push(`${at}: the last recover entry of a need must have no "when" (${last.id})`);
    }
  }
  for (const r of recover) { pred(`recover ${r.id}`, r.when); show(`recover ${r.id}`, r); }
  return out;
}
