/** Homestead progression (v4q(1), batch 1 to Lv17): gates and Energy rewards are content-driven. */
import type { HomesteadLook, P0Content } from './content.js';
import { gainEnergy, type P0Event } from './progress.js';
import { maxEnergy, skillLevel } from './rules.js';
import type { P0State } from './state.js';
import { missing, takeStorageFirst } from './storage.js';
import { addPlots, clearNewBeds } from './garden.js';
import { wingOf, wingTaken, type YardFeatures } from './decor.js';
import type { Refusal } from './fishing.js';
import { cityStamps, climatesVisited } from './travel.js';

export function nextLevel(c: P0Content, s: P0State) {
  return c.homestead.levels.find(l => l.level === s.homestead.level + 1) ?? null;
}

/** The skills a level gates, in the order the button and the refusal name the first short one (v4q(1) ③). */
export const GATE_SKILLS = ['farming', 'fishing', 'cooking'] as const;

/** Unlocks granted at or below the current level (spice_rack, warming_cabinet, bag_upgrade_1, board_slot_3, fence). */
export function unlocked(c: P0Content, s: P0State, what: string): boolean {
  return c.homestead.levels.some(l => l.level <= s.homestead.level && l.unlocks.includes(what));
}

/** The value of a [from level, value] ladder at the current Homestead level, or fallback below its first step. */
export function stepAt(steps: [number, number][] | undefined, level: number, fallback: number): number {
  let v = fallback;
  for (const [from, n] of steps ?? []) if (level >= from) v = n;
  return v;
}

/** A count that grows with the Homestead level up to a most: base + per_level × level, at most `max` — raised from a
 * level on by `raise` ([from level, most]; v4q(1) ⑧: trees 8 → 10 and sprinklers 10 → 12 at Lv14). */
export interface LevelCap { base: number; per_level: number; max: number; raise?: [number, number][] }
export function levelCap(m: LevelCap | undefined, level: number): number {
  return m ? Math.min(stepAt(m.raise, level, m.max), m.base + m.per_level * level) : 0;
}

/** The most stoves a kitchen has (v4q(1) ⑧: the Fourth Stove at Lv17); content can never give more. */
export const MAX_STOVES = 4;

/** Stoves in the kitchen (v4q(1) ⑧): Lv1–3 1, Lv4–7 2, Lv8–16 3, Lv17 4. */
export function stoveCount(c: P0Content, s: P0State): number {
  return Math.min(MAX_STOVES, Math.max(1, stepAt(c.homestead.stoves, s.homestead.level, 1)));
}

/** Big Pot (Lv6, §7.7): any stove may cook Double. Chef's Sign (Lv10): the gold zone bonus, 0 before. */
export function bigPot(c: P0Content, s: P0State): boolean { return unlocked(c, s, 'big_pot'); }
export function chefSignGold(c: P0Content, s: P0State): number {
  return unlocked(c, s, 'chefs_sign') ? (c.homestead.chefs_sign_gold ?? 0) : 0;
}

export function boardSlots(c: P0Content, s: P0State): number {
  let slots = 0;
  for (const [from, n] of c.homestead.board_slots) if (s.homestead.level >= from) slots = n;
  return slots;
}

/** Coins a spend needs in the wallet: price + the 40-coin floor (q(32); seeds are exempt, §11.2.2 rule 9). */
export function coinsNeeded(c: P0Content, price: number): number { return price + c.wallet_floor; }

/** Why the next level can't be bought right now, in button order (v4q(1) 画面): each skill (Farming → Fishing →
 * Cooking), the travel gate (stamps → climates), then materials, then coins. */
export function upgradeBlock(c: P0Content, s: P0State): Refusal | null {
  const next = nextLevel(c, s);
  if (!next) return { code: 'max_level', detail: { level: s.homestead.level } };
  for (const skill of GATE_SKILLS) {
    const need = next.skills[skill], have = skillLevel(c, s, skill);
    if (need !== undefined && have < need) return { code: 'skills_short', detail: { skill, need, have } };
  }
  if (next.travel) {
    const stamps = cityStamps(s), climates = climatesVisited(c, s);
    if (stamps < next.travel.stamps) return { code: 'travel_short', detail: { kind: 'stamps', need: next.travel.stamps, have: stamps } };
    if (climates < next.travel.climates) return { code: 'travel_short', detail: { kind: 'climates', need: next.travel.climates, have: climates } };
  }
  const gap = missing(s, next.materials);
  if (gap) return { code: 'need_material', detail: gap };
  if (s.coins < coinsNeeded(c, next.coins)) return { code: 'no_coins', detail: { need: coinsNeeded(c, next.coins) - s.coins } };
  return null;
}

/** What stops the next level from standing where the house grows (q(303), SGODOT-450): Lv8's Kitchen Wing on cells a
 * piece or a yard facility still holds — for a client that draws the wing (`wing8`). Asked after every other gap (the
 * spec's last line); nothing is moved for the player (the user, 548). */
export function wingBlock(c: P0Content, s: P0State, wing8: boolean): Refusal | null {
  const next = nextLevel(c, s), w = wingOf(c);
  if (!wing8 || !next || !w || next.level !== w.homestead) return null;
  const taken = wingTaken(c, s);
  return taken ? { code: 'homestead_blocked', detail: taken } : null;
}

export function upgradeHomestead(c: P0Content, s: P0State, now: number, events: P0Event[], yard: YardFeatures = {}): Refusal | null {
  // §8.1.1 前置 ①: only at home. The command's space (SGODOT-228 q(41)) has already moved presence; "away" =
  // pond / outpost / mine. A command from the map leaves it as it was, so a map tap after leaving still refuses.
  if (s.presence.space === 'away') return { code: 'not_home' };
  const block = upgradeBlock(c, s) ?? wingBlock(c, s, !!yard.wing8);
  if (block) return block;
  const next = nextLevel(c, s)!;
  for (const [item, qty] of next.materials) {
    takeStorageFirst(s, item, qty);
    events.push({ kind: 'item', id: item, delta: -qty });
  }
  s.coins -= next.coins;
  events.push({ kind: 'coins', delta: -next.coins });
  s.homestead.level = next.level;
  s.homestead.plaque.push({ level: next.level, at: now });
  // v4q(1) ⑥: Lv2–15 give 50 back, Lv16 on none — only up to the pool, never reducing a bonus-zone value.
  const room = Math.max(0, maxEnergy(c, s) - s.energy.value);
  const gain = gainEnergy(c, s, now, Math.min(next.energy, room), events, 'homestead');
  // look: the stage this level opens (LOOK-PICK, SGODOT-282) — the client offers its two looks after HOME-2's banner.
  const look = lookStageAt(c, next.level);
  events.push({ kind: 'homestead', level: next.level, energy: gain, unlocks: next.unlocks, ...(look ? { look: look.id } : {}) });
  // the level's beds (homestead.plots: Lv1 8 … Lv17 41, tilled, SGODOT-355 b1), dropped in with the level's look.
  const added = addPlots(c, s);
  if (added.length > 0) events.push({ kind: 'plots_added', plots: added, reason: 'homestead' });
  clearNewBeds(c, s, added, events, yard);   // Lv7's beds on the field's edge: pieces standing there go back to storage (q(172))
  return null;
}

/** The look stage a Homestead level opens (Lv3 Fence & Mailbox, Lv5 Porch, Lv8 Kitchen Wing, Lv10 Master Farmhouse). */
export function lookStageAt(c: P0Content, level: number): HomesteadLook | undefined {
  return (c.homestead.looks ?? []).find(l => l.level === level);
}

/** A stage's look (§8.3.1, q(24) / q(112)): b (stone) once picked, else a (timber) — the default, and what closing the
 * card leaves (q(24)), so a save from before P1 or a player who never picked reads a. */
export function lookOf(s: P0State, stage: string): 'a' | 'b' {
  return s.homestead.looks?.[stage] === 'b' ? 'b' : 'a';
}

/** set_look (LOOK-PICK, SGODOT-282): free, no Energy, at home (it is picked looking at the real farmhouse), for a stage
 * the homestead has reached; changeable any time after (HOME-1 Looks). */
export function setLook(c: P0Content, s: P0State, cmd: { stage?: unknown; look?: unknown }, events: P0Event[]): Refusal | null {
  if (s.presence.space === 'away') return { code: 'not_home' };
  const stage = (c.homestead.looks ?? []).find(l => l.id === cmd.stage);
  if (!stage) return { code: 'bad_stage' };
  if (cmd.look !== 'a' && cmd.look !== 'b') return { code: 'bad_look' };
  if (s.homestead.level < stage.level) return { code: 'homestead_level', detail: { need: stage.level } };
  s.homestead.looks = { ...(s.homestead.looks ?? {}), [stage.id]: cmd.look };
  events.push({ kind: 'look', stage: stage.id, look: cmd.look });
  return null;
}
