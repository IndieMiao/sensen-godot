/**
 * Fish Trap (P1, SGODOT-283; plan §6.8, q(109) ⑦, 不知火舞's spec on 283): a Tackle Shop good (Fishing Lv5, 120 coins,
 * stack 3) that is set in a pond and fills by itself. Set from the bag (it leaves the bag and becomes a float), one per
 * pond per player, as many in the water at once as the level allows (Lv5 1, Lv8 2, Lv10 3). Every 8 hours of water time
 * it catches one fish of that pond's Common / Fine pool — regional fish and the time of day included, at the moment that
 * fish came in — up to 3 kept; from Fishing Lv9 one in ten is Rare. Nothing runs on a timer: the fish are worked out
 * when the player looks or collects (as Energy regen is). Collecting needs the player at that pond, costs nothing,
 * gives half the fish's catch XP (with the level gap) and leaves in the trap what the creel cannot hold.
 */
import { createHash } from 'node:crypto';
import { add, count, room, stackLimit, take } from './bag.js';
import { fishById, type Fish, type P0Content } from './content.js';
import { pondAt, poolAt } from './fishing_world.js';
import { noteFishdex } from './fishing.js';
import { gainXp, type P0Event } from './progress.js';
import { scaledXp, skillLevel, xpPercent } from './rules.js';
import type { P0State } from './state.js';

export const TRAP = 'trap_fish';
export interface TrapRules { every_h: number; keep: number; slots: [number, number][]; rare_from: number; rare_pct: number; xp_pct: number }
/** A trap in the water: where, when it was set, since when its next fish counts, how many it has caught (each fish's
 * draw is keyed by it) and what it holds. */
export interface Trap { place: string; set_at: number; from: number; n: number; fish: string[] }

type Refusal = { code: string; detail?: Record<string, unknown> };
const rules = (c: P0Content): TrapRules =>
  (c.fishing as { trap?: TrapRules }).trap ?? { every_h: 8, keep: 3, slots: [[5, 1], [8, 2], [10, 3]], rare_from: 9, rare_pct: 10, xp_pct: 50 };

/** How many traps may be in the water at once at this Fishing level (Lv5 1 / Lv8 2 / Lv10 3; 0 below Lv5). */
export function trapSlots(c: P0Content, s: P0State): number {
  const level = skillLevel(c, s, 'fishing');
  let n = 0;
  for (const [lv, slots] of rules(c).slots) if (level >= lv) n = slots;
  return n;
}

/** The level that adds the next slot (Lv8 after Lv5), or null at the top. */
export function nextSlotLevel(c: P0Content, s: P0State): number | null {
  const level = skillLevel(c, s, 'fishing');
  return rules(c).slots.find(([lv]) => lv > level)?.[0] ?? null;
}

/** A [0, 1) number for a trap's n-th fish: the same answer however often it is worked out. */
const roll = (s: P0State, t: Trap, n: number, what: string) =>
  createHash('sha256').update(`${s.player}:${t.place}:${t.set_at}:${n}:${what}`).digest().readUInt32BE(0) / 4294967296;

/** The fish a trap caught at an instant: Common / Fine of the pond's pool then (Rare one time in ten from Lv9). */
function trapFish(c: P0Content, s: P0State, t: Trap, n: number, at: number): Fish | null {
  const r = rules(c);
  const tiers = poolAt(c, c.fishing.sites[c.fishing.places[t.place]?.site ?? ''] ?? c.fishing.sites.pond, pondAt(c, t.place, at));
  const rare = skillLevel(c, s, 'fishing') >= r.rare_from && roll(s, t, n, 'rare') * 100 < r.rare_pct && tiers[2]?.length;
  const pool = rare ? tiers[2] : [...(tiers[0] ?? []), ...(tiers[1] ?? [])];
  if (!pool.length) return null;
  let pick = roll(s, t, n, 'fish') * pool.reduce((a, p) => a + p.weight, 0);
  for (const p of pool) { pick -= p.weight; if (pick < 0) return p.fish; }
  return pool[pool.length - 1].fish;
}

/** Work out the fish caught since `from`, up to the trap's keep (the clock stops while it is full). */
export function settleTrap(c: P0Content, s: P0State, t: Trap, now: number): void {
  const r = rules(c), every = r.every_h * 3_600_000;
  while (t.fish.length < r.keep && now - t.from >= every) {
    t.from += every;
    t.n += 1;
    const f = trapFish(c, s, t, t.n, t.from);
    if (f) t.fish.push(f.id);
  }
  if (t.fish.length >= r.keep) t.from = Math.max(t.from, now);   // full: the next 8 h start when a fish is taken out
}

/** ms until the trap's next fish (null when full). */
export function nextFishIn(c: P0Content, t: Trap, now: number): number | null {
  const r = rules(c);
  return t.fish.length >= r.keep ? null : Math.max(0, t.from + r.every_h * 3_600_000 - now);
}

/** The pond the player is at, as a cast takes it (presence, checked against the pass by the reducer). */
const atPond = (c: P0Content, s: P0State) => {
  const place = s.presence.place ?? '';
  return c.fishing.places[place] ? place : '';
};

/** set_trap: from the bag into the pond the player is at. */
export function setTrap(c: P0Content, s: P0State, now: number, events: P0Event[]): Refusal | null {
  const place = atPond(c, s);
  if (!place) return { code: 'not_at_pond' };
  if (count(s.bag, TRAP) < 1) return { code: 'no_trap' };
  s.traps ??= [];
  const slots = trapSlots(c, s);
  if (s.traps.some(t => t.place === place)) return { code: 'trap_here' };
  if (s.traps.length >= slots) return { code: 'trap_slots', detail: { used: s.traps.length, slots, next_level: nextSlotLevel(c, s) } };
  take(s.bag, TRAP, 1);
  s.traps.push({ place, set_at: now, from: now, n: 0, fish: [] });
  events.push({ kind: 'item', id: TRAP, delta: -1 });
  events.push({ kind: 'trap', action: 'set', place, fish: 0 });
  return null;
}

/** collect_trap {take_back?}: the fish into the creel (what fits), then with take_back the trap back into the bag. */
export function collectTrap(c: P0Content, s: P0State, cmd: { take_back?: unknown }, now: number, events: P0Event[]): Refusal | null {
  const place = atPond(c, s);
  const t = (s.traps ?? []).find(x => x.place === place);
  if (!t) return { code: 'no_trap_here' };
  settleTrap(c, s, t, now);
  const back = cmd.take_back === true;
  // q(109) ⑦: Take back only when every fish fits (`Take back · Collect first`), and the trap itself (`Bag full`);
  // Collect needs room for one at least (`Collect · Creel full`).
  if (back && !fitsAll(c, s, t.fish)) return { code: 'collect_first', detail: { fish: t.fish.length } };
  if (back && !fitsAll(c, s, [...t.fish, TRAP])) return { code: 'bag_full' };
  if (!back && t.fish.length && room(c, s, t.fish[0]) < 1 && !t.fish.some(id => room(c, s, id) > 0)) return { code: 'creel_full', detail: { fish: t.fish.length } };
  const r = rules(c), level = skillLevel(c, s, 'fishing'), was = t.fish.length;
  const kept: string[] = [];
  const got: string[] = [];
  for (const id of t.fish) {
    if (room(c, s, id) < 1) { kept.push(id); continue; }
    const f = fishById(c, id)!;
    add(c, s, id, 1);
    got.push(id);
    s.fishing.caught[id] = (s.fishing.caught[id] ?? 0) + 1;
    events.push({ kind: 'item', id, delta: 1 });
    const pct = xpPercent(c, level, f.level);
    gainXp(c, s, now, 'fishing', scaledXp(s, Math.round(c.fishing.catch_xp[f.rarity - 1] * r.xp_pct / 100), pct), pct, events);
  }
  if (got.length) noteFishdex(c, s, now, events);   // a trapped fish fills the Fish-dex as a rod's does
  if (was >= r.keep && kept.length < r.keep) t.from = now;   // it was full: the next fish counts from now
  t.fish = kept;
  if (back) {
    s.traps = (s.traps ?? []).filter(x => x !== t);
    add(c, s, TRAP, 1);
    events.push({ kind: 'item', id: TRAP, delta: 1 });
  }
  events.push({ kind: 'trap', action: back ? 'taken_back' : 'collected', place, fish: got.length, left: kept.length });
  return null;
}

/** How many of these, taken in order, fit in the bag now (as collect_trap takes them). */
function fitsCount(c: P0Content, s: P0State, ids: string[]): number {
  let n = 0;
  for (let i = 1; i <= ids.length; i++) if (fitsAll(c, s, ids.slice(0, i))) n = i; else break;
  return n;
}

/** Room for all of these at once (stacks of one id fill, then each new stack takes a slot). */
function fitsAll(c: P0Content, s: P0State, ids: string[]): boolean {
  const need: Record<string, number> = {};
  for (const id of ids) need[id] = (need[id] ?? 0) + 1;
  let slots = Math.max(0, s.bag_cap - s.bag.length);
  for (const [id, n] of Object.entries(need)) {
    const limit = stackLimit(c, id);
    const partial = s.bag.filter(b => b.id === id && !b.gift).reduce((a, b) => a + Math.max(0, limit - b.qty), 0);
    slots -= Math.ceil(Math.max(0, n - partial) / limit);
    if (slots < 0) return false;
  }
  return true;
}

/** view.fishing.traps: each trap with its fish (worked out to now) and the time to the next one; slots and the next level. */
export function trapsView(c: P0Content, s: P0State, now: number) {
  const traps = (s.traps ?? []).map(t => {
    const copy: Trap = { ...t, fish: [...t.fish] };
    settleTrap(c, s, copy, now);
    // fits: how many Collect would take now (the card writes `Collect 1 · Free` / `Collect · Creel full`); all_fit:
    // Take back can empty it (else `Take back · Collect first`); back_fits: and the trap itself fits (else `Bag full`)
    return { place: t.place, fish: copy.fish.length, keep: rules(c).keep, next_in: nextFishIn(c, copy, now),
      fits: fitsCount(c, s, copy.fish), all_fit: fitsAll(c, s, copy.fish), back_fits: fitsAll(c, s, [...copy.fish, TRAP]) };
  });
  return { traps, slots: trapSlots(c, s), next_level: nextSlotLevel(c, s), have: count(s.bag, TRAP),
    here: (s.traps ?? []).some(t => t.place === (s.presence.place ?? '')) };
}
