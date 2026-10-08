/**
 * Counters by role (plan §9.11): buying with the 40-coin wallet floor (q(32); seeds exempt), drinks (§3.4.4, §9.12),
 * selling with buyback rates and daily quotas (§9.13.1), Sell All locks (F-07) and the farm storage hand-over (§10.4.8).
 * TODO(P1): the P0 server has no position; `shop` only says which counter's rules apply. Check room membership via
 * /v1/p0/online later (SGODOT-227).
 */
import { cropBySeed, dishParts, itemKind, rodById, sellPriceOf, SHOPS, type P0Content, type QuotaId, type ShopId, type Skill } from './content.js';
import { add, count, room, take } from './bag.js';
import { coinsNeeded } from './homestead.js';
import { gainEnergy, type P0Event } from './progress.js';
import { maxEnergy, skillLevel, untilRollover } from './rules.js';
import type { P0State } from './state.js';
import { missing, putInStorage, stored, takeStorageFirst } from './storage.js';
import type { Refusal } from './fishing.js';

/** The counter a command talks to; older clients send 'stall' or nothing for the Homestead Stall. */
export function shopOf(raw: unknown): ShopId | null {
  if (raw === undefined || raw === null || raw === 'stall') return 'homestead';
  return SHOPS.includes(raw as ShopId) ? raw as ShopId : null;
}

/** Everything a counter sells. */
export function catalog(c: P0Content, shop: ShopId): string[] {
  if (shop === 'homestead') return [...c.stall.buy, ...c.bag_upgrades.map(u => u.id)];
  if (shop === 'tackle') return c.tackle.buy;
  if (shop === 'market') return [...c.market.buy, ...c.market.specialty];
  return [];
}

export interface Offer {
  price: number; skill: Skill | null; gate: number; daily: number;
  to: 'bag' | 'gear' | 'storage' | 'bag_cap'; once: boolean; floor: boolean;
  homestead?: number; materials?: [string, number][]; capacity?: number;
}

export function offerOf(c: P0Content, id: string): Offer | null {
  const crop = cropBySeed(c, id);
  if (crop) return { price: crop.seed_price, skill: 'farming', gate: crop.gate, daily: 0, to: 'bag', once: false, floor: false };
  const rod = rodById(c, id);
  if (rod) return { price: rod.price, skill: 'fishing', gate: rod.level, daily: 0, to: 'gear', once: true, floor: true };
  const hoe = c.tools.row_hoe;
  if (id === hoe.id) return { price: hoe.price, skill: hoe.skill, gate: hoe.gate, daily: 0, to: 'gear', once: true, floor: true };
  const g = c.goods[id];
  if (g) return { price: g.price, skill: g.skill, gate: g.gate, daily: g.daily, to: 'bag', once: false, floor: true };
  const up = c.bag_upgrades.find(u => u.id === id);
  if (up) return { price: up.price, skill: null, gate: 0, daily: 0, to: 'bag_cap', once: true, floor: true, homestead: up.homestead, materials: up.materials, capacity: up.capacity };
  const sp = c.specialty[id];
  if (sp) return { price: sp.price, skill: null, gate: 0, daily: 0, to: 'storage', once: true, floor: true };
  return null;
}

export function owns(c: P0Content, s: P0State, id: string): boolean {
  if (rodById(c, id)) return s.gear.rods.includes(id);
  if (id === c.tools.row_hoe.id) return s.gear.hoes.includes(id);
  return s.owned.includes(id);
}

/** Coins the wallet must hold for a spend: the price, plus the 40-coin floor for everything but seeds. */
export function walletNeed(c: P0Content, offer: { price: number; floor: boolean }, qty = 1): number {
  const cost = offer.price * qty;
  return offer.floor ? coinsNeeded(c, cost) : cost;
}

export function buyItem(c: P0Content, s: P0State, cmd: { item?: unknown; qty?: unknown; shop?: unknown }, events: P0Event[]): Refusal | null {
  const shop = shopOf(cmd.shop), id = String(cmd.item ?? ''), qty = Number(cmd.qty ?? 1);
  if (!Number.isInteger(qty) || qty < 1 || qty > 99) return { code: 'bad_qty' };
  if (!shop || !catalog(c, shop).includes(id)) return { code: 'bad_item' };
  const offer = offerOf(c, id)!;
  if (offer.skill && skillLevel(c, s, offer.skill) < offer.gate)
    return { code: 'locked', detail: { skill: offer.skill, level: offer.gate, xp_to_go: c.skills[offer.skill][offer.gate - 1] - s.skills[offer.skill] } };
  if (offer.homestead && s.homestead.level < offer.homestead) return { code: 'homestead_level', detail: { need: offer.homestead } };
  if (offer.once && qty !== 1) return { code: 'bad_qty' };
  if (offer.once && owns(c, s, id)) return { code: 'owned' };
  const bought = s.day.bought[id] ?? 0;
  if (offer.daily && bought + qty > offer.daily) return { code: 'sold_out', detail: { left: Math.max(0, offer.daily - bought) } };
  const need = walletNeed(c, offer, qty);
  if (s.coins < need) return { code: 'no_coins', detail: { need: need - s.coins } };
  const gap = offer.materials && missing(s, offer.materials);
  if (gap) return { code: 'need_material', detail: gap };
  if (offer.to === 'bag' && room(c, s, id) < qty) return { code: 'bag_full', detail: { room: room(c, s, id) } };
  const cost = offer.price * qty;
  s.coins -= cost;
  events.push({ kind: 'coins', delta: -cost });
  for (const [item, n] of offer.materials ?? []) { takeStorageFirst(s, item, n); events.push({ kind: 'item', id: item, delta: -n }); }
  if (offer.daily) s.day.bought[id] = bought + qty;
  if (offer.to === 'bag') add(c, s, id, qty);
  else if (offer.to === 'storage') putInStorage(s, id, qty);
  else if (offer.to === 'bag_cap') s.bag_cap = Math.max(s.bag_cap, offer.capacity!);
  else if (rodById(c, id)) { s.gear.rods.push(id); s.gear.rod = id; }   // a new rod / hoe is equipped right away
  else { s.gear.hoes.push(id); s.gear.hoe = id; }
  if (offer.once && offer.to !== 'gear') s.owned.push(id);
  events.push({ kind: 'item', id, delta: qty });
  return null;
}

/** §3.4.4 / §9.12: +30, only up to max; 40 / 50 / 60 for the day's 1st / 2nd / 3rd cup, tea and coffee shared. */
export function drinkPrice(c: P0Content, s: P0State): number | null {
  return s.day.drinks < c.drinks.daily ? c.drinks.prices[s.day.drinks] : null;
}

export function drink(c: P0Content, s: P0State, cmd: { item?: unknown; shop?: unknown }, now: number, events: P0Event[]): Refusal | null {
  const id = String(cmd.item ?? ''), def = c.drinks.items[id];
  if (!def) return { code: 'bad_item' };
  if (shopOf(cmd.shop) !== def.shop) return { code: 'wrong_shop', detail: { shop: def.shop } };
  const price = drinkPrice(c, s);
  if (price === null) return { code: 'drink_limit', detail: { resets_in: untilRollover(c, now) } };
  const max = maxEnergy(c, s);
  if (s.energy.value >= max) return { code: 'energy_full' };
  if (s.coins < coinsNeeded(c, price)) return { code: 'no_coins', detail: { need: coinsNeeded(c, price) - s.coins } };
  s.coins -= price;
  s.day.drinks += 1;
  events.push({ kind: 'coins', delta: -price });
  const gain = gainEnergy(c, s, now, c.drinks.energy, events, 'drink');
  events.push({ kind: 'drink', item: id, gain, price, left: c.drinks.daily - s.day.drinks });
  return null;
}

/** Buyback for one id at one counter: per-unit coins and the quota it counts against, or why it can't be sold here. */
export function buyback(c: P0Content, shop: ShopId, id: string): { unit: number; quota: QuotaId | null } | { code: 'not_sellable' | 'not_sellable_here' } {
  const kind = itemKind(id), base = sellPriceOf(c, id);
  const anywhere = base !== null && base > 0 && SHOPS.some(sh => c.shops[sh].buys[kind]);
  if (!anywhere || (kind === 'dish' && dishParts(id).base === c.cooking.mystery.id)) return { code: 'not_sellable' };
  const rule = c.shops[shop].buys[kind];
  if (!rule) return { code: 'not_sellable_here' };
  return { unit: Math.max(1, Math.floor(base! * rule.rate + 1e-9)), quota: rule.quota };
}

export function quotaLeft(c: P0Content, s: P0State, q: QuotaId): number {
  return Math.max(0, c.quotas[q].cap - (s.day.quota[q] ?? 0));
}

/** §9.6.4: items a tracked request names are kept back from Sell All. */
export function protectedQty(s: P0State, id: string): number {
  let n = 0;
  for (const slot of [...s.boards.stall, ...s.boards.market]) {
    const r = slot.req;
    if (r?.status === 'accepted' && (r.kind === 'crop' || r.kind === 'material') && r.items.includes(id)) n += r.qty;
  }
  return n;
}

export function sellItem(c: P0Content, s: P0State, cmd: { item?: unknown; qty?: unknown; shop?: unknown }, now: number, events: P0Event[]): Refusal | null {
  const shop = shopOf(cmd.shop), id = String(cmd.item ?? '');
  if (!shop) return { code: 'bad_shop' };
  const all = cmd.qty === 'all';
  const qty = all ? 0 : Number(cmd.qty);
  if (!all && (!Number.isInteger(qty) || qty < 1)) return { code: 'bad_qty' };
  const price = buyback(c, shop, id);
  if ('code' in price) return { code: price.code };
  if (all && s.locked.includes(id)) return { code: 'locked_item' };
  const have = count(s.bag, id, 'skip');
  if (have === 0 && count(s.bag, id) > 0) return { code: 'gifted' };
  const want = all ? Math.max(0, have - protectedQty(s, id)) : qty;
  if (want < 1 || have < want) return { code: 'not_enough', detail: { have, protected: all ? have - want : 0 } };
  let n = want;
  if (price.quota) {
    n = Math.min(want, Math.floor(quotaLeft(c, s, price.quota) / price.unit));
    if (n < 1) return { code: 'limit_reached', detail: { quota: price.quota, resets_in: untilRollover(c, now) } };
  }
  const coins = n * price.unit;
  take(s.bag, id, n, 'skip');
  s.coins += coins;
  if (price.quota) s.day.quota[price.quota] = (s.day.quota[price.quota] ?? 0) + coins;
  events.push({ kind: 'item', id, delta: -n }, { kind: 'coins', delta: coins },
    { kind: 'sale', item: id, qty: n, asked: want, coins, shop, quota: price.quota });
  return null;
}

/** F-07: a locked item stays out of Sell All on every device. */
export function setLock(c: P0Content, s: P0State, cmd: { item?: unknown }, lock: boolean): Refusal | null {
  const id = String(cmd.item ?? '');
  if (!/^[a-z0-9_@]{2,48}$/.test(id)) return { code: 'bad_item' };
  const at = s.locked.indexOf(id);
  if (lock && at < 0) s.locked.push(id);
  if (!lock && at >= 0) s.locked.splice(at, 1);
  return null;
}

/** What the player can Store at home (§10.4.8, q(40)): materials, seeds, fertilizer, bait, torches; never produce, fish or dishes. */
export function storable(c: P0Content, id: string): boolean {
  return ['seed', 'fert', 'bait', 'torch', 'material'].includes(itemKind(id)) && !c.drinks.items[id];
}

/** Bag → farm storage (Store) and back (Take). TODO(P1): at home only; the client offers both at home. */
export function moveStorage(c: P0Content, s: P0State, cmd: { item?: unknown; qty?: unknown }, toStorage: boolean, events: P0Event[]): Refusal | null {
  const id = String(cmd.item ?? '');
  if (!storable(c, id)) return { code: 'not_storable' };
  const have = toStorage ? count(s.bag, id, 'skip') : stored(s, id);
  const qty = cmd.qty === 'all' ? have : Number(cmd.qty);
  if (!Number.isInteger(qty) || qty < 1) return { code: 'bad_qty' };
  if (have < qty) return { code: 'not_enough', detail: { have } };
  if (toStorage) {
    take(s.bag, id, qty, 'skip');
    putInStorage(s, id, qty);
    events.push({ kind: 'item', id, delta: -qty });
  } else {
    const n = Math.min(qty, room(c, s, id));
    if (n < 1) return { code: 'bag_full' };
    s.storage[id] = have - n;
    if (s.storage[id] === 0) delete s.storage[id];
    add(c, s, id, n);
    events.push({ kind: 'item', id, delta: n });
  }
  return null;
}
