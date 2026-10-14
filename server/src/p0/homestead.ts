/** Homestead Lv1–3 (plan §8.1–8.3): materials + coins + Farming + Fishing levels; upgrading refills Energy to the new max. */
import type { HomesteadLook, P0Content } from './content.js';
import { gainEnergy, type P0Event } from './progress.js';
import { maxEnergy, skillLevel } from './rules.js';
import type { P0State } from './state.js';
import { missing, takeStorageFirst } from './storage.js';
import { addPlots, clearNewBeds } from './garden.js';
import type { Refusal } from './fishing.js';

export function nextLevel(c: P0Content, s: P0State) {
  return c.homestead.levels.find(l => l.level === s.homestead.level + 1) ?? null;
}

export function skillsTotal(c: P0Content, s: P0State): number {
  return skillLevel(c, s, 'farming') + skillLevel(c, s, 'fishing');
}

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

/** The most stoves a kitchen has (§8.3.2: the Third Stove is the last); content can never give more. */
export const MAX_STOVES = 3;

/** Stoves in the kitchen (§8.3.2): Lv1–3 1, Lv4–7 2, Lv8 on 3. */
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

/** Why the next level can't be bought right now, in button order: skills, then materials, then coins (§8.6.1). */
export function upgradeBlock(c: P0Content, s: P0State): Refusal | null {
  const next = nextLevel(c, s);
  if (!next) return { code: 'max_level', detail: { level: s.homestead.level } };
  const skills = skillsTotal(c, s);
  if (skills < next.skills) return { code: 'skills_short', detail: { need: next.skills, have: skills } };
  const gap = missing(s, next.materials);
  if (gap) return { code: 'need_material', detail: gap };
  if (s.coins < coinsNeeded(c, next.coins)) return { code: 'no_coins', detail: { need: coinsNeeded(c, next.coins) - s.coins } };
  return null;
}

export function upgradeHomestead(c: P0Content, s: P0State, now: number, events: P0Event[]): Refusal | null {
  // §8.1.1 前置 ①: only at home. The command's space (SGODOT-228 q(41)) has already moved presence; "away" =
  // pond / outpost / mine. A command from the map leaves it as it was, so a map tap after leaving still refuses.
  if (s.presence.space === 'away') return { code: 'not_home' };
  const block = upgradeBlock(c, s);
  if (block) return block;
  const next = nextLevel(c, s)!;
  for (const [item, qty] of next.materials) {
    takeStorageFirst(s, item, qty);
    events.push({ kind: 'item', id: item, delta: -qty });
  }
  s.coins -= next.coins;
  events.push({ kind: 'coins', delta: -next.coins });
  s.homestead.level = next.level;
  s.homestead.bartered = {};   // the barter share counts toward one level at a time (§8.4.5)
  s.homestead.plaque.push({ level: next.level, at: now });
  // §8.1.1: Energy refills to the new max (200/200 → 210/210); a bonus-zone value above it is kept.
  const max = maxEnergy(c, s);
  const gain = gainEnergy(c, s, now, max - s.energy.value, events, 'homestead');
  // look: the stage this level opens (LOOK-PICK, SGODOT-282) — the client offers its two looks after HOME-2's banner.
  const look = lookStageAt(c, next.level);
  events.push({ kind: 'homestead', level: next.level, energy: gain, unlocks: next.unlocks, ...(look ? { look: look.id } : {}) });
  // P1 (q(59) §1.1): Lv3 brings 10 wild plots (30–39, homestead.plots), dropped in with the fence (HOME-2's plots_40 line).
  const added = addPlots(c, s);
  if (added.length > 0) events.push({ kind: 'plots_added', plots: added, reason: 'homestead' });
  clearNewBeds(c, s, added, events);   // Lv7's beds on the field's edge: pieces standing there go back to storage (q(172))
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
