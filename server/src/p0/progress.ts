/** Shared progression effects: energy spend / refund and XP with level-up rewards. */
import type { P0Content, Skill } from './content.js';
import { add, room } from './bag.js';
import { maxEnergy, nextTickIn, skillLevel } from './rules.js';
import type { P0State } from './state.js';

export type P0Event =
  | { kind: 'energy'; delta: number; reason: string }
  | { kind: 'xp'; skill: Skill; amount: number; percent: number }
  | { kind: 'item'; id: string; delta: number }
  // Warming Cabinet (§7.7): delta portions in (+) or out (−); to_bag = portions that went to the bag instead (cabinet full) or out to it (Take one).
  | { kind: 'cabinet'; id: string; delta: number; to_bag: number; have: number; cap: number }
  | { kind: 'coins'; delta: number }
  | { kind: 'first'; what: string; xp: number }
  | { kind: 'level'; skill: Skill; level: number; energy: number; gifts: [string, number][] }
  | { kind: 'cast'; bite_in: number; rarity: number; breaks: 'level' | 'rod' | null; bait: string | null }
  | { kind: 'catch'; fish: string; rarity: number; result: 'landed' | 'escaped' | 'broke_free' | 'cancelled'; refund: number;
      need_level?: number; protected_left?: number }
  | { kind: 'pot'; dish: string | null; rarity: number; ms: number }
  | { kind: 'dish'; dish: string; quality: number; qty: number; first: boolean; mystery: boolean; hits: number }
  | { kind: 'meal'; dish: string; nominal: number; counted: number; gain: number; meals: number; cap: number }
  | { kind: 'reward'; id: string; energy: number }
  | { kind: 'request'; id: string; status: 'accepted' | 'done' | 'dropped'; coins: number; bonus?: number }
  | { kind: 'homestead'; level: number; energy: number; unlocks: string[] }
  | { kind: 'drink'; item: string; gain: number; price: number; left: number }
  | { kind: 'affinity'; resident: string; delta: number; total: number; stage: string; reason: string; verdict?: string }
  | { kind: 'gift_meal'; resident: string; dish: string; given: boolean }
  | { kind: 'sale'; item: string; qty: number; asked: number; coins: number; shop: string; quota: string | null }
  | { kind: 'mine'; action: 'enter' | 'continue' | 'floor' | 'torch' | 'rock' | 'cleared'; run: number; floor: number; cost: number;
      rock?: number; drop?: string | null }
  | { kind: 'gather'; spot: string; items: [string, number, 'storage' | 'bag'][]; ready_in: number }
  | { kind: 'craft'; recipe: string; item: string; qty: number; to: 'bag' | 'gear' | 'owned' }
  | { kind: 'stored'; items: [string, number][]; reason: 'home' | 'spice_rack' };

export function energyDetail(c: P0Content, s: P0State, now: number, need: number) {
  return { need, have: s.energy.value, next_in: nextTickIn(c, s, now) };
}

export function spendEnergy(c: P0Content, s: P0State, now: number, amount: number, events: P0Event[], reason: string): void {
  const wasFull = s.energy.value >= maxEnergy(c, s);
  s.energy.value -= amount;
  if (wasFull) s.energy.tick_ms = now;
  events.push({ kind: 'energy', delta: -amount, reason });
}

/** Give energy back without passing max (+ bonus zone for refunds of a pre-paid cost). */
export function gainEnergy(c: P0Content, s: P0State, now: number, amount: number, events: P0Event[], reason: string, ceiling = maxEnergy(c, s)): number {
  const gain = Math.max(0, Math.min(amount, ceiling - s.energy.value));
  if (gain <= 0) return 0;
  s.energy.value += gain;
  if (s.energy.value >= maxEnergy(c, s)) s.energy.tick_ms = now;
  events.push({ kind: 'energy', delta: gain, reason });
  return gain;
}

/** Add XP; every level crossed grants the one-time energy reward (may enter the bonus zone, §3.4.8) and gifts. */
export function gainXp(c: P0Content, s: P0State, now: number, skill: Skill, amount: number, percent: number, events: P0Event[]): void {
  if (amount <= 0) { events.push({ kind: 'xp', skill, amount: 0, percent }); return; }
  const before = skillLevel(c, s, skill);
  s.skills[skill] += amount;
  events.push({ kind: 'xp', skill, amount, percent });
  const after = skillLevel(c, s, skill);
  for (let level = before + 1; level <= after; level++) {
    const firstEver = !s.rewards.includes('levelup_first');
    const energy = firstEver ? c.level_up_energy.first : c.level_up_energy.later;
    if (firstEver) s.rewards.push('levelup_first');
    const cap = maxEnergy(c, s) + c.energy.bonus_zone;
    const granted = Math.max(0, Math.min(energy, cap - s.energy.value));
    s.energy.value += granted;
    if (s.energy.value >= maxEnergy(c, s)) s.energy.tick_ms = now;
    const gifts = c.level_gifts[`${skill}:${level}`] ?? [];
    for (const [id, qty] of gifts) {
      if (id.startsWith('recipe:')) { const page = id.slice(7); if (!s.cookbook.includes(page)) s.cookbook.push(page); continue; }
      const put = Math.min(qty, room(c, s, id));
      if (put > 0) add(c, s, id, put);
    }
    events.push({ kind: 'level', skill, level, energy: granted, gifts });
  }
}

/** §3.4.8: a one-time energy reward, shown with the moment that earned it; may pass max by ≤ max_over. */
export function grantOnce(c: P0Content, s: P0State, now: number, id: string, amount: number, events: P0Event[]): void {
  if (amount <= 0 || s.rewards.includes(id)) return;
  s.rewards.push(id);
  const granted = gainEnergy(c, s, now, amount, events, 'reward', maxEnergy(c, s) + c.rewards.max_over);
  events.push({ kind: 'reward', id, energy: granted });
}
