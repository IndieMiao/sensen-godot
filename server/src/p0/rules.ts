/** Pure P0 rules: energy (plan §3.1), levels (§4.5), level-difference XP (§4.2.1), player day (§3.1.1). */
import type { P0Content, Skill } from './content.js';
import type { P0State } from './state.js';

export function maxEnergy(c: P0Content, _s: P0State): number {
  return c.energy.max_base; // Homestead Lv1 in M1; +10 per Homestead level later.
}

/** §3.4.6 Newcomer Blessing: the first 7 × 24 h after the account is created. */
export function blessed(c: P0Content, s: P0State, now: number): boolean {
  return now - s.created_at < c.blessing.days * 86_400_000;
}

/** Milliseconds per +1: 4:00, or 2:40 under the blessing (×1.5). */
export function regenMs(c: P0Content, s: P0State, now: number): number {
  return blessed(c, s, now) ? Math.round(c.energy.regen_ms / c.blessing.regen_mult) : c.energy.regen_ms;
}

export function foodCap(c: P0Content, s: P0State, now: number): number {
  return c.cooking.food_cap + (blessed(c, s, now) ? c.blessing.food_bonus : 0);
}

/**
 * Bring the stored value up to `now`. Linear +1 per regen_ms; stops at max (or stays above it in the
 * bonus zone without regenerating). While full the timer is held at `now`, so the next +1 after a
 * spend is a full period away (§3.1.1 "满条后消费 1 点，下一个 +1 从消费时刻起算 4 分钟").
 */
export function settleEnergy(c: P0Content, s: P0State, now: number): void {
  const max = maxEnergy(c, s), period = regenMs(c, s, now);
  if (s.energy.value >= max) { s.energy.tick_ms = now; return; }
  const steps = Math.floor((now - s.energy.tick_ms) / period);
  if (steps <= 0) return;
  s.energy.value = Math.min(max, s.energy.value + steps);
  s.energy.tick_ms = s.energy.value >= max ? now : s.energy.tick_ms + steps * period;
}

/** Milliseconds until the next +1, or null while at / above max. Call after settleEnergy. */
export function nextTickIn(c: P0Content, s: P0State, now: number): number | null {
  if (s.energy.value >= maxEnergy(c, s)) return null;
  return Math.max(0, s.energy.tick_ms + regenMs(c, s, now) - now);
}

export function levelFor(thresholds: number[], xp: number): number {
  let level = 1;
  for (let i = 0; i < thresholds.length; i++) if (xp >= thresholds[i]) level = i + 1;
  return level;
}

export function skillLevel(c: P0Content, s: P0State, skill: Skill): number {
  return levelFor(c.skills[skill], s.skills[skill]);
}

/** XP percentage for d = player level − content level: 100 / 75 / 50 / 25, or −1 for "outleveled" (5 % chance of 1 XP). */
export function xpPercent(c: P0Content, playerLevel: number, contentLevel: number): number {
  const d = playerLevel - contentLevel;
  if (d <= 1) return 100;
  const row = c.xp_multiplier.find(([gap]) => gap === d);
  return row ? row[1] : -1;
}

/** mulberry32 over the state's rng word — deterministic per player, advances on every draw. */
export function draw(s: P0State): number {
  s.rng = (s.rng + 0x6d2b79f5) | 0;
  let t = s.rng;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

/** Scale base XP by a locked percentage with random rounding of the fraction (§4.2.1). */
export function scaledXp(s: P0State, base: number, percent: number): number {
  if (percent < 0) return draw(s) < 0.05 ? 1 : 0;
  const exact = base * percent / 100, whole = Math.floor(exact);
  return whole + (draw(s) < exact - whole ? 1 : 0);
}

/** Player day key: home-city time shifted back by the 04:00 rollover (§3.1.1). */
export function dayKey(c: P0Content, now: number): string {
  const shifted = now + (c.day.utc_offset_hours - c.day.rollover_hour) * 3_600_000;
  return new Date(shifted).toISOString().slice(0, 10);
}

/** Milliseconds until the next 04:00 rollover. */
export function untilRollover(c: P0Content, now: number): number {
  const shifted = now + (c.day.utc_offset_hours - c.day.rollover_hour) * 3_600_000;
  return 86_400_000 - (((shifted % 86_400_000) + 86_400_000) % 86_400_000);
}
