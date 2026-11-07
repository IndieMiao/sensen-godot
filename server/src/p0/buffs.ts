/**
 * The priest's buffs (the user 11-07; plan zhuge-355/priest-buff 2026-11-07, all 8 points as recommended): Grace
 * Cathedral's Gabriel gives a farm buff and a fish buff, each for content.buffs.minutes of real time (it runs on offline
 * too: the save keeps when it ends). Both can be on at once, each on its own clock; taking one that is on starts it over,
 * never longer. Taken in the cathedral only (an outpost of role church). Takes are counted a player day, both kinds
 * together; from the player day content.buffs.limit_from on they are limited to `daily` (the demo week before it is not).
 * What they do is decided when it happens, as a snapshot: a crop sown under the farm one ripens faster all the way
 * (garden.ts growMs reads Plot.boost); a line cast under the fish one lands two (fishing.ts, Cast.twin).
 */
import type { P0Content } from './content.js';
import type { P0Event } from './progress.js';
import { dayKey, untilRollover } from './rules.js';
import type { P0State } from './state.js';

export const BUFFS = ['farm', 'fish'] as const;
export type BuffId = typeof BUFFS[number];
type Refusal = { code: string; detail?: Record<string, unknown> };

/** ms left on a buff, 0 when it is off (or this build has no buffs). */
export function buffLeft(c: P0Content, s: P0State, id: BuffId, now: number): number {
  return c.buffs ? Math.max(0, (s.buffs?.[id] ?? 0) - now) : 0;
}

/** The day's limit: null before content.buffs.limit_from (the demo week), else `daily`. */
const limitOf = (c: P0Content, s: P0State, now: number): number | null =>
  c.buffs && dayKey(c, s, now) >= c.buffs.limit_from ? c.buffs.daily : null;

/** The buff command: `{type: 'buff', buff, space, place}`, in the cathedral (space outpost, place an outpost of role church). */
export function takeBuff(c: P0Content, s: P0State, cmd: { buff?: unknown; space?: unknown; place?: unknown }, now: number,
  events: P0Event[]): Refusal | null {
  const b = c.buffs;
  if (!b || !BUFFS.includes(cmd.buff as BuffId)) return { code: 'bad_buff' };
  const id = cmd.buff as BuffId;
  const church = c.outposts?.find(o => o.role === 'church');
  if (cmd.space !== 'outpost' || !c.outposts?.some(o => o.id === cmd.place && o.role === 'church')) return { code: 'not_here', detail: { place: church?.id ?? null } };
  const limit = limitOf(c, s, now), used = s.day.buffs ?? 0;
  if (limit !== null && used >= limit) return { code: 'buff_limit', detail: { limit, resets_in: untilRollover(c, s, now) } };
  const renewed = buffLeft(c, s, id, now) > 0;
  const kept: Partial<Record<BuffId, number>> = {};
  for (const k of BUFFS) if (k !== id && buffLeft(c, s, k, now) > 0) kept[k] = s.buffs![k];   // one gone by goes from the save
  s.buffs = { ...kept, [id]: now + b.minutes * 60_000 };
  s.day.buffs = used + 1;
  events.push({ kind: 'buff', id, left: b.minutes * 60_000, renewed });
  return null;
}

/** view.buffs: the ones on, `[{id, left}]` (none: []); view.buff_takes: today's takes, the limit (null in the demo week). */
export function buffsView(c: P0Content, s: P0State, now: number) {
  const on = BUFFS.filter(id => buffLeft(c, s, id, now) > 0).map(id => ({ id, left: buffLeft(c, s, id, now) }));
  return { buffs: on, buff_takes: { used: s.day.buffs ?? 0, limit: limitOf(c, s, now), resets_in: untilRollover(c, s, now) } };
}

/** The farm buff's share of a ripening time for a crop sown now, or undefined when it is off. */
export const farmBoost = (c: P0Content, s: P0State, now: number): number | undefined =>
  buffLeft(c, s, 'farm', now) > 0 ? c.buffs!.farm_mult : undefined;

/** Whether a line cast now lands fish_qty of its fish. */
export const fishTwin = (c: P0Content, s: P0State, now: number): boolean => buffLeft(c, s, 'fish', now) > 0;
