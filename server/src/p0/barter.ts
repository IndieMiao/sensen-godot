/** Specialty barter (plan §8.4.5, SGODOT-282): a player who never mines can still climb the Homestead. At the Market
 * Square keeper, `give` of this climate's regional crops or fish become 1 Stone / Clay / Copper Ore / Quartz, into
 * farm storage. Each mineral at most `level_share` of the next level's need comes by barter (counted until the next
 * upgrade); at most `daily` barters a day. No affinity, no buyback quota, not a local delivery. */
import type { P0Content } from './content.js';
import { count, take } from './bag.js';
import { nextLevel } from './homestead.js';
import type { P0Event } from './progress.js';
import type { P0State } from './state.js';
import { putInStorage } from './storage.js';
import type { Refusal } from './fishing.js';

/** Regional crops and fish this home climate can barter. */
export function barterItems(c: P0Content): string[] {
  return c.homestead.barter?.items[c.profile.climate] ?? [];
}

/** How many of a mineral the next level still lets the player get by barter. */
export function barterRoom(c: P0Content, s: P0State, mineral: string): number {
  const b = c.homestead.barter, next = nextLevel(c, s);
  if (!b || !next) return 0;
  const need = next.materials.find(([id]) => id === mineral)?.[1] ?? 0;
  return Math.max(0, Math.floor(need * b.level_share) - (s.homestead.bartered?.[mineral] ?? 0));
}

export function barter(c: P0Content, s: P0State, cmd: { item?: unknown; mineral?: unknown; shop?: unknown }, events: P0Event[]): Refusal | null {
  const b = c.homestead.barter;
  if (!b) return { code: 'bad_item' };
  if (cmd.shop !== 'market') return { code: 'wrong_shop', detail: { shop: 'market' } };
  const item = String(cmd.item ?? ''), mineral = String(cmd.mineral ?? '');
  if (!b.minerals.includes(mineral)) return { code: 'not_barterable', detail: { mineral } };
  if (!barterItems(c).includes(item)) return { code: 'not_barterable', detail: { item } };
  const done = s.day.barters ?? 0;
  if (done >= b.daily) return { code: 'barter_limit', detail: { daily: b.daily } };
  if (barterRoom(c, s, mineral) < 1) return { code: 'barter_share', detail: { mineral } };
  if (count(s.bag, item) < b.give) return { code: 'not_enough', detail: { item, need: b.give, have: count(s.bag, item) } };
  take(s.bag, item, b.give);
  events.push({ kind: 'item', id: item, delta: -b.give });
  putInStorage(s, mineral, 1);
  events.push({ kind: 'item', id: mineral, delta: 1 });
  s.day.barters = done + 1;
  s.homestead.bartered = { ...(s.homestead.bartered ?? {}), [mineral]: (s.homestead.bartered?.[mineral] ?? 0) + 1 };
  return null;
}
