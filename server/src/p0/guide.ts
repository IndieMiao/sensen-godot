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
 */
import type { MapMarker, MarkerKind } from './markers.js';
import type { P0Content, Skill } from './content.js';
import { cropById, itemName } from './content.js';
import { count } from './bag.js';
import { skillLevel } from './rules.js';
import type { P0Event } from './progress.js';
import type { P0State } from './state.js';

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
  all?: GuidePred[]; any?: GuidePred[]; not?: GuidePred;
}

/** An in-world mark the client lights for the step. The server reads `place` (map pins); the rest is the client's (340). */
export interface GuideMark { place?: string; resident?: string; plot?: string; button?: string; kind?: MarkerKind; pulse?: boolean }
export interface GuideShow { row?: Record<string, unknown>; tip?: string; marks?: GuideMark[] }
export interface GuideStep extends GuideShow {
  id: string; phase?: string;
  optional?: boolean;   // a suggestion that never holds the player up: it also passes once the step after it is done (339's t_sow_rest)
  done_on?: { key: string; count?: number; from_step?: boolean };
  done_if?: GuidePred;
  /** In order: the first whose `if` fails shows a recover entry — the first of `else` whose `when` holds (the last has none). */
  needs?: { if: GuidePred; else: string[] }[];
}
export interface GuideRecover extends GuideShow { id: string; when?: GuidePred }
export interface GuideContent {
  steps: GuideStep[]; recover?: GuideRecover[]; tips?: Record<string, string>;
  pond_catch?: boolean;   // false: a guided save starts without Pond Catch on the Stall Board (339 decides; default kept)
}

/** In the save (optional, no save version of its own). */
export interface GuideState {
  step: string | null;           // the current step; null once ended
  n: Record<string, number>;     // counts of the keys the step table names
  base?: Record<string, number>; // a from_step step's count when it began
  end?: 'done' | 'legacy';
  at: number;                    // when the current step began
}

/** Keys a step may count on (validateGuide); `ack:<step>` is the guide command's (§2.2). */
export const GUIDE_KEY_KINDS = ['sow', 'water', 'harvest', 'buy', 'sell', 'barter', 'enter', 'talk', 'gift', 'learn', 'cast', 'catch',
  'cook', 'dish', 'eat', 'accept', 'deliver', 'home_pick', 'travel', 'ack', 'speedup'] as const;
/** The client's built-in TipCard keys (P0Guide.TIPS) a step may name besides the table's own tips. */
const BUILT_IN_TIPS = ['sow', 'cast', 'creel', 'cook', 'heat', 'meal', 'map'];

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
    counted.set(c, set);
  }
  return set;
}

/** A new save's guide: on when the client can show it and the table has steps, else legacy. */
export function freshGuide(c: P0Content, now: number, on: boolean): GuideState {
  const first = stepsOf(c)[0];
  return on && first ? enter(first, { step: null, n: {}, at: now }, now) : legacyGuide(now);
}
export const legacyGuide = (now: number): GuideState => ({ step: null, n: {}, end: 'legacy', at: now });
export const guideOn = (s: P0State): boolean => !!s.guide && s.guide.step !== null;

function enter(st: GuideStep, g: GuideState, now: number): GuideState {
  g.step = st.id; g.at = now;
  if (st.done_on?.from_step) g.base = { [st.done_on.key]: g.n[st.done_on.key] ?? 0 };
  else delete g.base;
  return g;
}

/** Everything the player holds of an item: bag, farm storage, Warming Cabinet. */
const held = (s: P0State, id: string) => count(s.bag, id) + (s.storage[id] ?? 0) + s.cabinet.filter(x => x.id === id).reduce((n, x) => n + x.qty, 0);
const pots = (s: P0State) => [s.stove, s.queue, ...(s.burners ?? []).flatMap(b => [b.stove, b.queue])].filter(p => p !== null);

export function guidePred(c: P0Content, s: P0State, p: GuidePred | undefined, now: number): boolean {
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
  if (p.all && !p.all.every(q => guidePred(c, s, q, now))) return false;
  if (p.any && !p.any.some(q => guidePred(c, s, q, now))) return false;
  if (p.not && guidePred(c, s, p.not, now)) return false;
  return true;
}

/** How far the step's count is: have / need (have capped at need); null without done_on. */
function progress(st: GuideStep, g: GuideState): { have: number; need: number } | null {
  if (!st.done_on) return null;
  const k = st.done_on.key, need = st.done_on.count ?? 1;
  const have = (g.n[k] ?? 0) - (st.done_on.from_step ? g.base?.[k] ?? 0 : 0);
  return { have: Math.max(0, Math.min(have, need)), need };
}

function stepDone(c: P0Content, s: P0State, st: GuideStep, now: number): boolean {
  const p = progress(st, s.guide!);
  if (p && p.have >= p.need) return true;
  return st.done_if !== undefined && guidePred(c, s, st.done_if, now);
}

/** What a command (or a state read) did, as guide keys with counts. `before` is the save as it was before it. */
export function guideKeys(c: P0Content, before: P0State, s: P0State, cmd: { type?: string; [k: string]: unknown } | null, events: P0Event[]): Map<string, number> {
  const keys = new Map<string, number>();
  const add = (k: string, n = 1) => { if (n > 0) keys.set(k, (keys.get(k) ?? 0) + n); };
  // entering somewhere new: a space, and the pond or outpost in it
  const was = before.presence, now = s.presence;
  if (now.space && (now.space !== was.space || (now.entered ?? null) !== (was.entered ?? null))) {
    add(`enter:${now.space}`);
    if (now.entered) add(`enter:${now.entered}`);
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
      case 'barter': add(`barter:${e.item}`); break;
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
  if (type === 'gift') { add(`gift:${String(cmd!.resident)}`); add(`gift:${String(cmd!.resident)}:${String(cmd!.item)}`); }
  if (type === 'guide') add(`ack:${String(cmd!.step)}`);
  return keys;
}

/** Count what was done and pass every step now done. Runs after each command and on the state read of entering a place. */
export function settleGuide(c: P0Content, s: P0State, keys: Map<string, number>, now: number): void {
  const g = s.guide;
  if (!g || g.step === null) return;
  const want = countedKeys(c);
  for (const [k, n] of keys) if (want.has(k)) g.n[k] = (g.n[k] ?? 0) + n;
  const steps = stepsOf(c);
  let i = steps.findIndex(st => st.id === g.step);
  if (i < 0) { endGuide(g, now); return; }   // a step the table no longer has (content changed): never strand the player
  while (stepDone(c, s, steps[i], now) || (steps[i].optional && i + 1 < steps.length && stepDone(c, s, steps[i + 1], now))) {
    i += 1;
    if (i >= steps.length) { endGuide(g, now); return; }
    enter(steps[i], g, now);
  }
}

function endGuide(g: GuideState, now: number): void {
  g.step = null; g.end = 'done'; g.at = now;
  delete g.base;
}

/** The current step's recover entry when its needs fail, else null. */
export function guideRecover(c: P0Content, s: P0State, now: number): string | null {
  const st = currentStep(c, s);
  for (const need of st?.needs ?? []) {
    if (guidePred(c, s, need.if, now)) continue;
    const pick = need.else.find(id => guidePred(c, s, recoverOf(c, id)?.when, now));
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

/** view.guide: the step and its count, or the recover entry to show instead; {step: null, end} once there is none. */
export function guideView(c: P0Content, s: P0State, now: number) {
  const g = s.guide;
  const st = currentStep(c, s);
  if (!g || !st) return { step: null, end: g?.end ?? 'legacy' };
  return { step: st.id, phase: st.phase ?? null, recover: guideRecover(c, s, now), at: g.at, progress: progress(st, g) };
}

/** The map pins of the step shown (or its recover entry), tracked; while the guide is on they are the only ones (markers.ts). */
export function guideMarkers(c: P0Content, s: P0State, now: number): MapMarker[] {
  const st = currentStep(c, s);
  if (!st) return [];
  const rec = guideRecover(c, s, now);
  const shown: GuideShow = rec ? recoverOf(c, rec) ?? {} : st;
  return (shown.marks ?? []).filter(m => m.place)
    .map(m => ({ place: m.place!, kind: m.kind ?? 'request', why: { guide: rec ?? st.id, tracked: true as const } }));
}

/** dev/guide: put the save's guide on a step (`first`, `end` or an id), counts cleared; nothing else changes. */
export function setGuide(c: P0Content, s: P0State, to: string, now: number): { code: string } | null {
  const steps = stepsOf(c);
  if (to === 'end') { s.guide = { step: null, n: {}, end: 'done', at: now }; return null; }
  const st = to === 'first' ? steps[0] : steps.find(x => x.id === to);
  if (!st) return { code: 'bad_step' };
  s.guide = enter(st, { step: null, n: {}, at: now }, now);
  return null;
}

/** What is wrong with the step table (the content test runs it): unknown ids, keys, items, places, tips, dead ends. */
export function validateGuide(c: P0Content): string[] {
  const out: string[] = [];
  const steps = stepsOf(c), recover = c.guide?.recover ?? [];
  const tips = new Set([...BUILT_IN_TIPS, ...Object.keys(c.guide?.tips ?? {})]);
  const places = new Set(['home', ...(c.outposts ?? []).map(o => o.id), ...Object.keys(c.fishing.places)]);
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
      ...(p.pot ? [p.pot] : []), ...(p.known ? [p.known] : [])]) if (!known(id)) out.push(`${where}: unknown item ${id}`);
    for (const k of Object.keys(p.keys ?? {})) key(where, k);
    p.all?.forEach(q => pred(where, q)); p.any?.forEach(q => pred(where, q)); pred(where, p.not);
  };
  const show = (where: string, x: GuideShow) => {
    if (x.tip && !tips.has(x.tip)) out.push(`${where}: unknown tip ${x.tip}`);
    for (const m of x.marks ?? []) {
      if (m.place && !places.has(m.place)) out.push(`${where}: unknown place ${m.place}`);
      if (m.resident && !c.residents[m.resident]) out.push(`${where}: unknown resident ${m.resident}`);
    }
  };
  for (const st of steps) {
    const at = `step ${st.id}`;
    if (!st.done_on && !st.done_if) out.push(`${at}: neither done_on nor done_if`);
    if (st.done_on) key(at, st.done_on.key);
    if (st.done_on?.key.startsWith('ack:') && st.done_on.key !== `ack:${st.id}`) out.push(`${at}: an ack step acks itself`);
    pred(at, st.done_if);
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
