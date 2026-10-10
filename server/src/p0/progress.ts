/** Shared progression effects: energy spend / refund and XP with level-up rewards. */
import type { P0Content, Skill } from './content.js';
import { grantItems } from './parcels.js';
import { maxEnergy, nextTickIn, skillLevel } from './rules.js';
import type { P0State } from './state.js';

export type P0Event =
  | { kind: 'energy'; delta: number; reason: string }
  // capped: the day's anti-script limit cut it (§4.3.4); nth: a pot's place among today's pots of its Cookbook page (1st
  // full, 2nd half, 3rd on none, §7.6.2), so the float can say `· 2nd today` / `No XP · 3rd today` (q(94))
  | { kind: 'xp'; skill: Skill; amount: number; percent: number; capped?: true; nth?: number }
  | { kind: 'item'; id: string; delta: number }
  // Warming Cabinet (§7.7): delta portions in (+) or out (−); to_bag = portions that went to the bag instead (cabinet full) or out to it (Take one).
  // Once the cabinet is unlocked every kept dish sends one, so a dish that all went to the bag has delta 0 (Cabinet full · … sent to bag).
  | { kind: 'cabinet'; id: string; delta: number; to_bag: number; have: number; cap: number }
  // Portions left on the stove because neither the cabinet nor the bag had room (Bag full · dish left on the stove).
  | { kind: 'plate'; ids: string[]; cabinet: boolean }
  | { kind: 'parcel'; id: string; qty: number; key: string; waiting: boolean; expires_in?: number; gift?: true }   // a reward that did not fit the bag (§10.4.8)
  | { kind: 'coins'; delta: number }
  | { kind: 'milestone'; id: string; title: string; coins: number; cabinet: number; decor: string | null }   // Cookbook milestone (§7.6.1)
  | { kind: 'first'; what: string; xp: number; name?: string }   // name: the city of a fishing_city first (v5 keys are cluster ids)
  | { kind: 'level'; skill: Skill; level: number; energy: number; gifts: [string, number][] }
  | { kind: 'cast'; bite_in: number; rarity: number; breaks: 'level' | 'rod' | null; bait: string | null }
  | { kind: 'catch'; fish: string; rarity: number; result: 'landed' | 'escaped' | 'broke_free' | 'cancelled'; refund: number;
      need_level?: number; protected_left?: number }
  | { kind: 'pot'; id?: number; dish: string | null; rarity: number; ms: number; tried?: boolean; queued?: boolean; stove?: number; double?: boolean }   // tried: this combination failed before; queued: waits (Queue ×2)
  | { kind: 'queue'; id?: number; dish: string | null; started_at: number; ms: number }   // the waiting pot fired (Queue ×2)
  // A Mystery Dish (§7.5.2): tried = not new (no clue); refund = ingredients given back; clue = slots turned on a Hidden page.
  | { kind: 'mishap'; items: string[]; tried: boolean; refund: string[]; trial_left: number | null; clue: { page: string; slots: number[] } | null }
  // auto: kept by Queue ×2; none: a failed pot with its ingredients back (Newcomer Blessing) made no Mystery Dish (qty 0)
  | { kind: 'dish'; pot?: number; dish: string; quality: number; qty: number; first: boolean; mystery: boolean; hits: number; auto?: true; none?: true; trial_left?: number; lucky?: true }
  | { kind: 'meal'; dish: string; nominal: number; counted: number; gain: number; meals: number; cap: number }
  | { kind: 'reward'; id: string; energy: number }
  | { kind: 'arrival'; cluster: string; first: boolean; stamp: import('./travel.js').TravelStamp | null; energy: number; pass_until: number; km: number; trip: number }
  | { kind: 'request'; id: string; status: 'accepted' | 'done' | 'dropped'; coins: number; bonus?: number }
  | { kind: 'homestead'; level: number; energy: number; unlocks: string[] }
  | { kind: 'drink'; item: string; gain: number; price: number; left: number }
  | { kind: 'affinity'; resident: string; delta: number; total: number; stage: string; reason: string; verdict?: string }
  | { kind: 'gift_meal'; resident: string; dish: string; given: boolean; to?: 'parcel' }   // to: the bag was full, so it waits in the Inbox
  | { kind: 'recipe'; page: string; from: 'taught' | 'request' | 'card'; resident?: string }   // a page turned Tasted (§7.5.3; 哪吒's shape, card = Recipe Card)
  | { kind: 'visit'; id: string; place: string }   // an explore request checked in at its outpost (§9.6.3)
  | { kind: 'title'; id: string; resident: string }   // a story request's title (§9.4.4 Trusted)
  | { kind: 'sale'; item: string; qty: number; asked: number; coins: number; shop: string; quota: string | null }
  | { kind: 'mine'; action: 'enter' | 'continue' | 'floor' | 'torch' | 'rock' | 'cleared' | 'express' | 'express_unlocked'
      | 'hit' | 'defeat' | 'hurt' | 'knocked_out' | 'complete'; run: number; floor: number; cost: number;
      rock?: number; drop?: string | null;
      mob?: number; mob_kind?: string; hp?: number; damage?: number; loot?: [string, number] | null; quartz_spent?: boolean }
  | { kind: 'gather'; spot: string; items: [string, number, 'storage' | 'bag'][]; ready_in: number }
  | { kind: 'craft'; recipe: string; item: string; qty: number; to: 'bag' | 'gear' | 'owned' }
  // P1 (SGODOT-239): a facility placed or moved; started = sown plots it now waters (they began growing)
  | { kind: 'facility'; action: 'placed' | 'moved'; facility: number; facility_kind: string; plot: number; from?: number; covered: number; started: number[] }
  | { kind: 'plots_added'; plots: number[]; reason: 'homestead' }   // the Homestead unlock's new plots (client drops them in)
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

/**
 * Add XP; every level crossed gives its level gift and unlocks. No skill level restores Energy any more: Cooking never did
 * (q(37)), and Farming / Fishing stopped with q(101) (SGODOT-262: the first session's Fishing Lv2 +50 and first Fine fish
 * +20 paid for twelve casts, so the player never saw fishing cost Energy). level_up_energy stays in the content at 0, so
 * a later decision can bring an amount back without code. Level gifts go into the bag, and what does not fit becomes
 * Inbox parcels (§10.4.8).
 */
export function gainXp(c: P0Content, s: P0State, now: number, skill: Skill, amount: number, percent: number, events: P0Event[], nth?: number): void {
  const tag = nth ? { nth } : {};
  if (amount <= 0) { events.push({ kind: 'xp', skill, amount: 0, percent, ...tag }); return; }
  // §4.3.4: at most skill_daily_cap XP per skill per player day, first-time bonuses included. No human gets near it.
  const today = s.day.xp[skill] ?? 0, allowed = Math.max(0, Math.min(amount, c.skill_daily_cap - today));
  if (allowed < amount) {
    events.push({ kind: 'xp', skill, amount: allowed, percent, capped: true, ...tag });
    if (allowed <= 0) return;
  }
  s.day.xp[skill] = today + allowed;
  const capped = allowed < amount;
  amount = allowed;
  const before = skillLevel(c, s, skill);
  s.skills[skill] += amount;
  if (!capped) events.push({ kind: 'xp', skill, amount, percent, ...tag });
  const after = skillLevel(c, s, skill);
  for (let level = before + 1; level <= after; level++) {
    const paysEnergy = skill !== 'cooking';
    const firstEver = paysEnergy && !s.rewards.includes('levelup_first');
    const energy = !paysEnergy ? 0 : firstEver ? c.level_up_energy.first : c.level_up_energy.later;
    if (firstEver) s.rewards.push('levelup_first');
    const cap = maxEnergy(c, s) + c.energy.bonus_zone;
    const granted = energy > 0 ? Math.max(0, Math.min(energy, cap - s.energy.value)) : 0;
    if (granted > 0) {
      s.energy.value += granted;
      if (s.energy.value >= maxEnergy(c, s)) s.energy.tick_ms = now;
    }
    const gifts = c.level_gifts[`${skill}:${level}`] ?? [];
    events.push({ kind: 'level', skill, level, energy: granted, gifts });
    grantItems(c, s, now, `level:${skill}:${level}`, `${skill[0].toUpperCase()}${skill.slice(1)} Lv${level} reward`, gifts, events);
  }
}

/**
 * A first-time XP bonus (first cast, first catch of a species, first harvest, first pot of a page): the `first` event
 * says what it paid after the daily cap, and is left out when the cap took it all.
 */
export function firstXp(c: P0Content, s: P0State, now: number, skill: Skill, what: string, xp: number, events: P0Event[], name?: string): void {
  const paid = Math.max(0, Math.min(xp, c.skill_daily_cap - (s.day.xp[skill] ?? 0)));
  if (paid > 0) events.push({ kind: 'first', what, xp: paid, ...(name ? { name } : {}) });
  gainXp(c, s, now, skill, xp, 100, events);
}

/** §3.4.8: a one-time energy reward, shown with the moment that earned it; may pass max by ≤ max_over. */
export function grantOnce(c: P0Content, s: P0State, now: number, id: string, amount: number, events: P0Event[]): void {
  if (amount <= 0 || s.rewards.includes(id)) return;
  s.rewards.push(id);
  const granted = gainEnergy(c, s, now, amount, events, 'reward', maxEnergy(c, s) + c.rewards.max_over);
  events.push({ kind: 'reward', id, energy: granted });
}
