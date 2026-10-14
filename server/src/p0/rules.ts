/** Pure P0 rules: energy (plan §3.1), levels (§4.5), level-difference XP (§4.2.1), player day (§3.1.1). */
import type { P0Content, Skill } from './content.js';
import { homeFacts, type Homed } from './home.js';
import type { P0State } from './state.js';

/** §8.3.2: 200 + 10 × (Homestead Lv − 1). */
export function maxEnergy(c: P0Content, s: P0State): number {
  return c.energy.max_base + c.homestead.per_level.energy * (s.homestead.level - 1);
}

/** §3.4.6 Newcomer Blessing: the first 7 × 24 h after the account is created. */
export function blessed(c: P0Content, s: P0State, now: number): boolean {
  return now - s.created_at < c.blessing.days * 86_400_000;
}

/** Milliseconds per +1: 4:00, or 2:40 under the blessing (×1.5). */
export function regenMs(c: P0Content, s: P0State, now: number): number {
  return blessed(c, s, now) ? Math.round(c.energy.regen_ms / c.blessing.regen_mult) : c.energy.regen_ms;
}

/** §8.3.2: daily meals 200 + 10 × (Homestead Lv − 1), +100 under the Newcomer Blessing. */
export function foodCap(c: P0Content, s: P0State, now: number): number {
  return c.cooking.food_cap + c.homestead.per_level.meals * (s.homestead.level - 1) + (blessed(c, s, now) ? c.blessing.food_bonus : 0);
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

const zones = new Map<string, Intl.DateTimeFormat>();
/**
 * The player's home city's UTC offset at an instant, in ms. Its time zone (an IANA name, e.g. America/Los_Angeles: the
 * written city's content.profile.timezone, another home's cluster's) follows daylight saving; without one the fixed
 * day.utc_offset_hours applies (SGODOT-270: San Francisco moves between −7 and −8 hours; SGODOT-303: each home its own).
 */
function homeOffset(c: P0Content, s: Homed, at: number): number {
  const tz = homeFacts(c, s).timezone;
  if (!tz) return c.day.utc_offset_hours * 3_600_000;
  let f = zones.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', { timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' });
    zones.set(tz, f);
  }
  const p = Object.fromEntries(f.formatToParts(at).map(x => [x.type, x.value]));
  return Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second) - Math.floor(at / 1000) * 1000;
}

/** Player day key: home-city time shifted back by the 04:00 rollover (§3.1.1). */
export function dayKey(c: P0Content, s: Homed, now: number): string {
  const hold = s?.travel?.day_hold;   // q(173): the day a home change carries over
  if (hold && now >= hold.start && now < hold.until) return hold.key;
  return new Date(now + homeOffset(c, s, now) - c.day.rollover_hour * 3_600_000).toISOString().slice(0, 10);
}

/** The home-time 04:00 that ends player day `day` (YYYY-MM-DD): the next day's rollover, as an instant. */
export function rolloverAfter(c: P0Content, s: Homed, day: string): number {
  const hold = s?.travel?.day_hold;
  if (hold && day === hold.key) return hold.until;   // q(173) ①: every "next 04:00" of the carried day is the stored one
  const local = Date.parse(`${day}T00:00:00Z`) + 86_400_000 + c.day.rollover_hour * 3_600_000;   // 04:00 the next day, home clock
  const guess = local - homeOffset(c, s, local);
  return local - homeOffset(c, s, guess);   // the offset in force at that moment (04:00 is clear of the 02:00 DST switch)
}

/** Milliseconds until the next 04:00 rollover. */
export function untilRollover(c: P0Content, s: Homed, now: number): number {
  return rolloverAfter(c, s, dayKey(c, s, now)) - now;
}
