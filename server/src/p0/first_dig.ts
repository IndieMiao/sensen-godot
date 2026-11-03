/**
 * 355 G (contract-efg §9.2, v4q(7) ③): Pip's First Dig — its own slot, not a request on Pip's line, no track_max, nothing
 * handed in. It shows from Homestead Lv3, counts the deepest floor of any mine and is done the moment that reaches its
 * floor: on the mine_record that gets there, or on the Lv3 upgrade itself for a player who went down first. Done is kept
 * with the one-time rewards (`first_dig`); a done one still shows, done, so Today's vein row tells it from one not yet
 * shown (v4q(9)). Pip's one line toward the iron vein (v4q(9) ②) follows it, said once: `line:pip_vein` in `seen`.
 */
import type { P0Content } from './content.js';
import { mineRank } from './mine.js';
import type { P0Event } from './progress.js';
import { addAffinity, residentDef } from './residents.js';
import type { P0State } from './state.js';
import { nearestFreeVein } from './wild.js';

const DONE = 'first_dig', SAID = 'line:pip_vein';
/** The floor Pip's line sends the player to: the vein's first elevator station (`Get down to Floor 10!`). */
const VEIN_FLOOR = 10;

/** view.first_dig: null before it shows (below its Homestead level), then {giver, floor, have, done}. */
export function firstDigView(c: P0Content, s: P0State) {
  const d = c.mine.first_dig;
  if (!d) return null;
  if (s.rewards.includes(DONE)) return { giver: d.giver, floor: d.floor, have: d.floor, done: true };
  if (s.homestead.level < d.gate.homestead) return null;
  return { giver: d.giver, floor: d.floor, have: Math.min(mineRank(s), d.floor), done: false };
}

/** Done once shown and reached: the reward weapon into the slot (in hand when it hits harder), the giver's points. */
export function settleFirstDig(c: P0Content, s: P0State, now: number, events: P0Event[]): void {
  const d = c.mine.first_dig;
  if (!d || s.rewards.includes(DONE) || s.homestead.level < d.gate.homestead || mineRank(s) < d.floor) return;
  s.rewards.push(DONE);
  const id = d.reward.weapon, arms = c.mine.combat.weapons, arm = id ? arms[id] : undefined;
  // Wooden 3 → Copper 5 is taken into hand; an Iron Sword (8) stays there
  const takes = !!arm && arm.attack > (arms[s.gear.weapon]?.attack ?? 0);
  events.push({ kind: 'first_dig', done: true, weapon: id ?? null, equipped: takes });
  if (id && arm) {
    if (!s.gear.weapons.includes(id)) s.gear.weapons.push(id);
    if (takes) s.gear.weapon = id;
    events.push({ kind: 'gear', item: id, equipped: takes });
  }
  if (d.reward.affinity && residentDef(c, d.giver)) addAffinity(c, s, d.giver, d.reward.affinity, 'first_dig', now, events);
}

/** view.pip_line: Pip's line toward the nearest free iron vein (the one Today's vein row names), once First Dig is done,
 * until said, and only while that vein's deepest is short of Floor 10; null otherwise or with no such vein. */
export function pipLine(c: P0Content, s: P0State): { key: 'pip_vein'; vein: string; name: string } | null {
  const d = c.mine.first_dig;
  if (!d?.lines?.pip_vein || !s.rewards.includes(DONE) || s.seen?.includes(SAID)) return null;
  const vein = nearestFreeVein(c, s, 'iron_ore');
  if (!vein || (s.mine.records[vein.id]?.deepest ?? 0) >= VEIN_FLOOR) return null;
  return { key: 'pip_vein', vein: vein.id, name: vein.name };
}

/** A talk with the giver while the line is due says it: kept as said, whatever the day's chat points did. */
export function notePipLine(c: P0Content, s: P0State, resident: unknown): void {
  if (String(resident ?? '') === c.mine.first_dig?.giver && pipLine(c, s)) (s.seen ??= []).push(SAID);
}
