/**
 * 驿站委托板（C-191，0.4.6）：照搬 P0 系统委托板。抽单、交单（扣物品、加金币）、交完补位、放弃后补位、过期换单、
 * 每天 6 单和完成奖 100 的上限；物品不够时不能交，存档不变；累计单数存档。报酬和每单件数按所有者 SEN-Q-281
 * （采纳 SEN-C-189 第 4.1 节，C-197）：售价 × 件数 + 完成奖，件数和完成奖按物品、按农场 3 级及以下 / 4 级起分档。
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { dayKey, nextRollover } from '../../src/parcels/energy.js';
import { applyFarmCommands, emptyFarm, parseFarmCommands, rebaseFarm, welcome, withEconomy, type FarmCommand, type ParcelFarmState } from '../../src/parcels/farm.js';
import { floorPrice, hash32, settleBoard, tierFor, type BoardRequest } from '../../src/parcels/requests.js';
import { loadParcelRules, parseParcelRules, type ParcelRules } from '../../src/parcels/rules.js';

const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const H = 3_600_000;
/** 太平洋时间 11-23 早上 8 点（玩家日 4 点换，离换日还远）。 */
const T0 = Date.UTC(2026, 10, 23, 16);

const welcomed = (bag: Record<string, number> = {}): ParcelFarmState => {
  const s = welcome(rules, emptyFarm(), T0)!;
  s.bag = { ...s.bag, ...bag };
  return s;
};
/** 读档看到的样子：副本补到 now（routes farmView）。 */
const view = (s: ParcelFarmState, now: number, r: ParcelRules = rules): ParcelFarmState => {
  const v = withEconomy(s);
  settleBoard(r, v, now);
  return v;
};
function run(s: ParcelFarmState, commands: FarmCommand[], now: number, r: ParcelRules = rules): ParcelFarmState {
  const out = applyFarmCommands(r, s, commands, now);
  if (!out.ok) throw new Error(`${out.code} @${out.index} ${JSON.stringify(out.detail)}`);
  return out.state;
}
const reqs = (s: ParcelFarmState): (BoardRequest | null)[] => s.board.slots.map(sl => sl.req);
const req = (s: ParcelFarmState, slot: number): BoardRequest => s.board.slots[slot].req!;
/** 背包里够交这一格的单子。 */
const stocked = (s: ParcelFarmState, ...slots: number[]): ParcelFarmState => {
  const out = structuredClone(s);
  for (const i of slots) out.bag[req(out, i).item] = (out.bag[req(out, i).item] ?? 0) + req(out, i).qty;
  return out;
};
const deliver = (id: number): FarmCommand => ({ type: 'deliver_request', request: id });
/** SEN-Q-281 的分档：物品 → [3 级及以下件数, 4 级起件数, 完成奖]。 */
const Q281: Record<string, [[number, number], [number, number], number]> = {
  crop_carrot: [[3, 5], [5, 8], 10], wood: [[4, 6], [6, 10], 10], stone: [[4, 6], [6, 10], 10],
  egg: [[2, 3], [3, 5], 20], milk: [[1, 2], [2, 3], 20], wool: [[1, 2], [2, 3], 20],
};
/** 这件物品在 level 级时一单的件数范围和完成奖。 */
const band = (item: string, level: number): [number, number, number] => {
  const [low, high, bonus] = Q281[item];
  return [...(level >= 4 ? high : low), bonus];
};
/** 盖好的鸡场（建筑 2），出鸡蛋单要它。 */
const withCoop = (s: ParcelFarmState): ParcelFarmState =>
  ({ ...structuredClone(s), buildings: [...s.buildings, { id: 2, type: 'coop', model: 'chicken_yard', x: 10, y: 10, width: 7, depth: 5, rotation: 0, built_at: T0, animals: ['hen_white'] }] });
/** 盖好的牛棚（建筑 3），出牛奶单要它（C-192）。 */
const withBarn = (s: ParcelFarmState): ParcelFarmState =>
  ({ ...structuredClone(s), buildings: [...s.buildings, { id: 3, type: 'barn', model: 'cow_barn', x: 20, y: 10, width: 8, depth: 6, rotation: 0, built_at: T0, animals: ['cow', 'cow'] }] });

describe('dynamic_farm.json requests (C-191)', () => {
  it('ships SEN-Q-281: 2 slots, at once / 8 h / 72 h, 6 a day, bonus 100 a day, Jasmine\'s price × count + bonus, count by item', () => {
    const tiers = ([low, high, bonus]: (typeof Q281)[string]) => [{ level: 1, qty: low, bonus }, { level: 4, qty: high, bonus }];
    expect(rules.requests).toEqual({
      slots: 2, done_refill_seconds: 0, drop_refill_seconds: 8 * 3600, expire_seconds: 72 * 3600, daily_max: 6, daily_bonus_max: 100,
      floor_percent: 100,
      tiers: tiers(Q281.crop_carrot),
      item_tiers: Object.fromEntries(Object.entries(Q281).map(([item, b]) => [item, tiers(b)])),
      templates: { fresh_greens: { item: 'crop_carrot' }, timber_run: { item: 'wood' }, stone_order: { item: 'stone' },
        egg_basket: { item: 'egg', building: 'coop' }, fresh_milk: { item: 'milk', building: 'barn' } },
    });
    // 不再打折：一件的价就是 Jasmine 的售价（胡萝卜 12、木材 2、石头 2、鸡蛋 20、牛奶 45，C-192）。
    expect(['crop_carrot', 'wood', 'stone', 'egg', 'milk'].map(i => floorPrice(rules, i))).toEqual([12, 2, 2, 20, 45]);
    // 每种单子按它要的物品分档，3 级及以下一档、4 级起一档，再高也不变。
    const at = (template: string, level: number) => { const x = tierFor(rules.requests!, level, template); return [...x.qty, x.bonus]; };
    for (const [template, item] of [['fresh_greens', 'crop_carrot'], ['timber_run', 'wood'], ['stone_order', 'stone'], ['egg_basket', 'egg'], ['fresh_milk', 'milk']])
      for (const level of [1, 3, 4, 5, 7, 99]) expect(at(template, level)).toEqual(band(item, level));
  });

  it('refuses malformed request rules at load time; rules without requests have no board', () => {
    const q = rules.requests!;
    const bad = (change: Record<string, unknown>) => () => parseParcelRules({ ...rules, requests: { ...q, ...change } });
    expect(bad({ slots: 0 })).toThrow();
    expect(bad({ slots: 9 })).toThrow();
    expect(bad({ expire_seconds: 60 })).toThrow();
    expect(bad({ daily_max: 0 })).toThrow();
    expect(bad({ floor_percent: 0 })).toThrow();
    expect(bad({ floor_percent: 101 })).toThrow();
    expect(bad({ tiers: [] })).toThrow();
    expect(bad({ tiers: [{ level: 2, qty: [2, 3], bonus: 10 }] })).toThrow();
    expect(bad({ tiers: [{ level: 1, qty: [3, 2], bonus: 10 }] })).toThrow();
    expect(bad({ tiers: [{ level: 1, qty: [2, 3], bonus: 10 }, { level: 1, qty: [2, 3], bonus: 20 }] })).toThrow();
    expect(bad({ templates: {} })).toThrow();
    expect(bad({ templates: { x: { item: 'seed_carrot' } } })).toThrow();   // Jasmine 不收的东西不能出单
    expect(bad({ templates: { x: { item: 'egg', building: 'pen' } } })).toThrow();   // 没有这类建筑（羊圈还没上）
    expect(bad({ templates: { x: { item: 'egg', tiers: [{ level: 2, qty: [1, 2], bonus: 20 }] } } })).toThrow();   // 模板自己的分档也从 1 级起
    expect(bad({ item_tiers: [] })).toThrow();
    expect(bad({ item_tiers: { egg: [] } })).toThrow();
    expect(bad({ item_tiers: { egg: [{ level: 1, qty: [3, 2], bonus: 20 }] } })).toThrow();   // 按物品的分档同样的边界
    expect(bad({ item_tiers: { 'Egg!': [{ level: 1, qty: [1, 2], bonus: 20 }] } })).toThrow();
    // 按物品的分档可以写还没上线、Jasmine 还不收的物品（羊毛等羊圈上线）；没有 item_tiers 也行。
    expect(() => parseParcelRules({ ...rules, requests: { ...q, item_tiers: { future_item: [{ level: 1, qty: [1, 1], bonus: 0 }] } } })).not.toThrow();
    expect(() => parseParcelRules({ ...rules, requests: { ...q, item_tiers: undefined } })).not.toThrow();
    const none = parseParcelRules({ ...structuredClone(rules), requests: undefined });
    const s = view(welcomed(), T0, none);
    expect(s.board.slots).toEqual([]);
    expect(applyFarmCommands(none, s, [deliver(1)], T0)).toMatchObject({ ok: false, code: 'NO_REQUEST' });
  });

  it('parses the three commands with a positive whole request id only', () => {
    expect(parseFarmCommands([{ type: 'accept_request', request: 1 }, { type: 'deliver_request', request: 2 }, { type: 'drop_request', request: 3, x: 1 }]))
      .toEqual([{ type: 'accept_request', request: 1 }, { type: 'deliver_request', request: 2 }, { type: 'drop_request', request: 3 }]);
    for (const request of [0, -1, 1.5, '1', undefined, 2 ** 31]) expect(parseFarmCommands([{ type: 'deliver_request', request }])).toBeNull();
  });

  it('the hash is the 32-bit FNV-1a with the murmur3 finish the client copies', () => {
    // tests/dynamic_farm/test_parcel_board.gd checks the same four values.
    expect(['', 'a', 'abc', '1795406400000:0:1795406400000:1:t'].map(hash32)).toEqual([2872998923, 444641715, 482950588, 3549447585]);
  });
});

describe('drawing requests (C-191)', () => {
  it('a farm not entered yet has no board; the first entry fills both slots at once with two different kinds', () => {
    expect(view(emptyFarm(), T0).board.slots).toEqual([]);
    const s = view(welcomed(), T0);
    expect(s.board.slots.map(sl => sl.refill_at)).toEqual([T0, T0]);
    const [a, b] = reqs(s) as BoardRequest[];
    expect([a.id, b.id]).toEqual([1, 2]);
    expect(s.board.seq).toBe(2);
    expect(a.template).not.toBe(b.template);
    for (const r of [a, b]) {
      const [lo, hi, bonus] = band(r.item, 1);
      expect(r).toMatchObject({ status: 'open', drawn_at: T0, bonus });
      expect(r.qty).toBeGreaterThanOrEqual(lo);
      expect(r.qty).toBeLessThanOrEqual(hi);
      expect(rules.requests!.templates[r.template].item).toBe(r.item);
    }
  });

  it('what the view shows is what the next command finds: same ids, same items, written by the command', () => {
    const shown = view(welcomed(), T0 + 5000);
    const after = run(welcomed(), [{ type: 'accept_request', request: 1 }], T0 + 9000);
    expect(reqs(after).map(r => r && { ...r, status: 'open' })).toEqual(reqs(shown));
    expect(req(after, 0).status).toBe('accepted');
    // 两次读档之间没有命令，看到的一样。
    expect(view(welcomed(), T0 + 3 * H)).toEqual(view(welcomed(), T0 + 5000));
  });

  it('only what the farm can make: no eggs without a coop, no milk without a barn; with them, they come up among the kinds', () => {
    const kinds = (s: ParcelFarmState) => {
      const seen = new Set<string>();
      // 每次放弃再到点补位换一张，看 60 张单子都出了什么。
      let t = T0, x = view(s, t);
      for (let n = 0; n < 30; n++) {
        for (const r of reqs(x)) seen.add(r!.item);
        x = run(x, [{ type: 'drop_request', request: req(x, 0).id }, { type: 'drop_request', request: req(x, 1).id }], t);
        t += 8 * H;
        x = view(x, t);
      }
      return [...seen].sort();
    };
    expect(kinds(welcomed())).toEqual(['crop_carrot', 'stone', 'wood']);
    expect(kinds(withCoop(welcomed()))).toEqual(['crop_carrot', 'egg', 'stone', 'wood']);
    expect(kinds(withBarn(welcomed()))).toEqual(['crop_carrot', 'milk', 'stone', 'wood']);
    expect(kinds(withBarn(withCoop(welcomed())))).toEqual(['crop_carrot', 'egg', 'milk', 'stone', 'wood']);
  });

  it('count and completion bonus follow the item and the farm level when drawn (SEN-Q-281): Lv3 and below one band, Lv4 on the other', () => {
    for (const level of [1, 3, 4, 5, 7]) {
      const qty: Record<string, Set<number>> = {};
      let t = T0, x = view({ ...withCoop(welcomed()), level }, t);
      for (let n = 0; n < 60; n++) {
        for (const r of reqs(x)) {
          (qty[r!.item] ??= new Set()).add(r!.qty);
          expect(r!.bonus).toBe(band(r!.item, level)[2]);
        }
        x = view(run(x, [{ type: 'drop_request', request: req(x, 0).id }, { type: 'drop_request', request: req(x, 1).id }], t), t += 8 * H);
      }
      // 每种都抽到过，件数恰好铺满这一档的范围。
      expect(Object.keys(qty).sort()).toEqual(['crop_carrot', 'egg', 'stone', 'wood']);
      for (const [item, seen] of Object.entries(qty)) {
        const [lo, hi] = band(item, level);
        expect([...seen].sort((p, q) => p - q), `${item} Lv${level}`).toEqual(Array.from({ length: hi - lo + 1 }, (_, i) => lo + i));
      }
    }
  });

  it('a milk (or any later) template follows its item\'s tiers with no other change: 1–2 for +20, from Lv4 2–3', () => {
    // C-192 的牛奶单合并进来时只加一行模板（和奶的售价）；这里用没有牛棚限定的同样一行代替。
    const raw = structuredClone(rules);
    raw.economy.sell_prices.milk = 45;
    raw.requests!.templates = { fresh_milk: { item: 'milk' } };
    const milk = parseParcelRules(raw);
    expect(tierFor(milk.requests!, 3, 'fresh_milk')).toEqual({ level: 1, qty: [1, 2], bonus: 20 });
    expect(tierFor(milk.requests!, 4, 'fresh_milk')).toEqual({ level: 4, qty: [2, 3], bonus: 20 });
    const s = view({ ...welcomed(), level: 4 }, T0, milk);
    const r = req(s, 0);
    expect(r).toMatchObject({ item: 'milk', bonus: 20 });
    expect([2, 3]).toContain(r.qty);
    // 交单：45 × 件数 + 20。
    const out = run(stocked(s, 0), [deliver(r.id)], T0 + 1000, milk);
    expect(out.coins).toBe(45 * r.qty + 20);
  });
});

describe('delivering (C-191)', () => {
  it('takes the items and pays floor × count + bonus; the slot is refilled at once with a new request; the count is saved', () => {
    const s0 = stocked(view(welcomed(), T0), 0);
    const r = req(s0, 0), other = req(s0, 1);
    const pay = floorPrice(rules, r.item) * r.qty + 10;
    const s1 = run(s0, [deliver(r.id)], T0 + H);
    expect(s1.coins).toBe(pay);
    expect(s1.bag[r.item] ?? 0).toBe((s0.bag[r.item] ?? 0) - r.qty);
    expect(s1.requests_done).toBe(1);
    expect(s1.board).toMatchObject({ day: dayKey(rules, T0 + H), done_today: 1, bonus_today: 10, seq: 3 });
    expect(req(s1, 0)).toMatchObject({ id: 3, drawn_at: T0 + H, status: 'open' });
    expect(req(s1, 1)).toEqual(other);
    // 交单不花体力，接没接都能交。
    expect(s1.energy).toEqual(s0.energy ?? s1.energy);
    // 再读一次存档，看到的就是存下的。
    expect(view(JSON.parse(JSON.stringify(s1)), T0 + 2 * H)).toEqual(s1);
  });

  it('a carrot request: 3 carrots pay 3 × 12 + 10 = 46; an egg request: 2 eggs pay 2 × 20 + 20 = 60 (never less than selling them)', () => {
    const s = view(withCoop(welcomed()), T0);
    s.board.slots[0].req = { id: 1, template: 'fresh_greens', item: 'crop_carrot', qty: 3, bonus: 10, drawn_at: T0, status: 'open' };
    s.board.slots[1].req = { id: 2, template: 'egg_basket', item: 'egg', qty: 2, bonus: 20, drawn_at: T0, status: 'accepted' };
    s.bag.crop_carrot = 4;
    s.bag.egg = 2;
    const out = run(s, [deliver(1), deliver(2)], T0 + 1000);
    expect(out.coins).toBe(46 + 60);
    expect(out.board).toMatchObject({ done_today: 2, bonus_today: 30 });
    expect(out.bag).toMatchObject({ crop_carrot: 1 });
    expect(out.bag.egg).toBeUndefined();
    expect(out.requests_done).toBe(2);
    expect(reqs(out).map(r => r!.id)).toEqual([3, 4]);
  });

  it('too few items: refused with what is missing, the whole batch and the save unchanged', () => {
    const s = view(welcomed(), T0);
    const r = req(s, 0);
    s.bag[r.item] = r.qty - 1;
    const frozen = structuredClone(s);
    const out = applyFarmCommands(rules, s, [{ type: 'accept_request', request: r.id }, deliver(r.id)], T0 + 1000);
    expect(out).toEqual({ ok: false, index: 1, code: 'NOT_ENOUGH', detail: { item: r.item, have: r.qty - 1, need: r.qty } });
    expect(s).toEqual(frozen);
  });

  it('an unknown or gone request is refused; a second accept says it is taken', () => {
    const s = view(welcomed(), T0);
    expect(applyFarmCommands(rules, s, [deliver(99)], T0)).toEqual({ ok: false, index: 0, code: 'NO_REQUEST', detail: { request: 99 } });
    const taken = run(s, [{ type: 'accept_request', request: 1 }], T0);
    expect(applyFarmCommands(rules, taken, [{ type: 'accept_request', request: 1 }], T0)).toMatchObject({ ok: false, code: 'ALREADY_ACCEPTED' });
    const done = run(stocked(taken, 0), [deliver(1)], T0);
    expect(applyFarmCommands(rules, done, [deliver(1)], T0)).toMatchObject({ ok: false, code: 'NO_REQUEST' });
  });

  it('at most 6 a player day: the 7th is refused (DAILY_LIMIT, when it resets) and changes nothing; the next day it goes', () => {
    let s = view(welcomed(), T0), t = T0;
    for (let n = 0; n < 6; n++) {
      s = run(stocked(s, 0), [deliver(req(s, 0).id)], t += 60_000);
    }
    expect(s.board).toMatchObject({ done_today: 6, bonus_today: 60 });
    expect(s.requests_done).toBe(6);
    const full = stocked(s, 0, 1), frozen = structuredClone(full);
    expect(applyFarmCommands(rules, full, [deliver(req(full, 1).id)], t + 1000))
      .toEqual({ ok: false, index: 0, code: 'DAILY_LIMIT', detail: { max: 6, resets_at: nextRollover(rules, t + 1000) } });
    expect(full).toEqual(frozen);
    // 接和放弃照常。
    expect(applyFarmCommands(rules, full, [{ type: 'accept_request', request: req(full, 1).id }], t + 1000).ok).toBe(true);
    const tomorrow = nextRollover(rules, t);
    const next = run(full, [deliver(req(full, 1).id)], tomorrow);
    expect(next.board).toMatchObject({ day: dayKey(rules, tomorrow), done_today: 1, bonus_today: 10 });
    expect(next.requests_done).toBe(7);
  });

  it('completion bonuses stop at 100 a day: with +20 each the sixth pays its price only; the next day the bonus is back', () => {
    // 现在只有蛋（还有以后的奶、羊毛）是 +20；这里让每种单子都 +20，看上限。
    const all20 = parseParcelRules({ ...structuredClone(rules), requests: { ...rules.requests!, item_tiers: undefined,
      tiers: [{ level: 1, qty: [2, 3], bonus: 20 }] } });
    let s = view({ ...welcomed(), level: 4 }, T0, all20), t = T0;
    const paid: number[] = [];
    for (let n = 0; n < 6; n++) {
      const r = req(s, 0), before = s.coins;
      s = run(stocked(s, 0), [deliver(r.id)], t += 60_000, all20);
      paid.push(s.coins - before - floorPrice(all20, r.item) * r.qty);
    }
    expect(paid).toEqual([20, 20, 20, 20, 20, 0]);
    expect(s.board.bonus_today).toBe(100);
    const r = req(s, 0), before = s.coins;
    s = run(stocked(s, 0), [deliver(r.id)], nextRollover(rules, t), all20);
    expect(s.coins - before).toBe(floorPrice(all20, r.item) * r.qty + 20);
  });

  it('a template with its own tiers draws its own count and bonus; the others keep their item\'s tiers', () => {
    const own = parseParcelRules({ ...structuredClone(rules), requests: { ...rules.requests!, templates: {
      ...rules.requests!.templates, egg_basket: { item: 'egg', building: 'coop', tiers: [{ level: 1, qty: [1, 1], bonus: 20 }, { level: 4, qty: [3, 3], bonus: 25 }] },
    } } });
    expect(tierFor(own.requests!, 1, 'egg_basket')).toEqual({ level: 1, qty: [1, 1], bonus: 20 });
    expect(tierFor(own.requests!, 5, 'egg_basket')).toEqual({ level: 4, qty: [3, 3], bonus: 25 });
    expect(tierFor(own.requests!, 5, 'fresh_greens')).toEqual(rules.requests!.item_tiers!.crop_carrot[1]);
    // 物品没有自己的分档时用公共的。
    const shared = parseParcelRules({ ...structuredClone(rules), requests: { ...rules.requests!, item_tiers: { egg: rules.requests!.item_tiers!.egg } } });
    expect(tierFor(shared.requests!, 5, 'timber_run')).toEqual(rules.requests!.tiers[1]);
    expect(tierFor(shared.requests!, 5, 'egg_basket')).toEqual(rules.requests!.item_tiers!.egg[1]);
    let t = T0, x = view(withCoop(welcomed()), t, own);
    for (let n = 0; n < 20; n++) {
      for (const r of reqs(x)) {
        if (r!.item === 'egg') expect([r!.qty, r!.bonus]).toEqual([1, 20]);
        else {
          const [lo, hi, bonus] = band(r!.item, 1);
          expect(r!.bonus).toBe(bonus);
          expect(r!.qty >= lo && r!.qty <= hi).toBe(true);
        }
      }
      x = view(run(x, [{ type: 'drop_request', request: req(x, 0).id }, { type: 'drop_request', request: req(x, 1).id }], t, own), t += 8 * H, own);
    }
  });

  it('a bonus partly left pays what is left: 40-coin requests pay 40, 40, 20, then 0', () => {
    const big = parseParcelRules({ ...structuredClone(rules), requests: { ...rules.requests!, item_tiers: undefined,
      tiers: [{ level: 1, qty: [2, 2], bonus: 40 }] } });
    let s = view(welcomed(), T0, big), t = T0;
    const paid: number[] = [];
    for (let n = 0; n < 4; n++) {
      const r = req(s, 0), before = s.coins;
      s = run(stocked(s, 0), [deliver(r.id)], t += 60_000, big);
      paid.push(s.coins - before - floorPrice(big, r.item) * r.qty);
    }
    expect(paid).toEqual([40, 40, 20, 0]);
  });
});

describe('dropping and swapping (C-191)', () => {
  it('a dropped request leaves its slot empty for 8 h, the items stay in the bag; then a new one is drawn', () => {
    const s0 = stocked(view(welcomed(), T0), 0);
    const r = req(s0, 0);
    const s1 = run(s0, [{ type: 'accept_request', request: r.id }, { type: 'drop_request', request: r.id }], T0 + H);
    expect(s1.board.slots[0]).toEqual({ req: null, refill_at: T0 + 9 * H });
    expect(s1.bag).toEqual(s0.bag);
    expect(s1.requests_done).toBe(0);
    expect(view(s1, T0 + 9 * H - 1).board.slots[0].req).toBeNull();
    const back = view(s1, T0 + 9 * H);
    expect(req(back, 0)).toMatchObject({ id: 3, drawn_at: T0 + 9 * H, status: 'open' });
    // 读档早晚不影响抽到的：12 小时后才回来，单子仍是 9 小时那一刻抽的。
    expect(view(s1, T0 + 12 * H)).toEqual(back);
  });

  it('an open request nobody takes is swapped 72 h after it was drawn, for another kind; a taken one never expires', () => {
    const s0 = view(welcomed(), T0);
    const taken = run(s0, [{ type: 'accept_request', request: req(s0, 1).id }], T0 + H);
    expect(reqs(view(taken, T0 + 72 * H - 1))).toEqual(reqs(taken));
    const later = view(taken, T0 + 72 * H);
    expect(req(later, 0)).toMatchObject({ id: 3, drawn_at: T0 + 72 * H, status: 'open' });
    expect(req(later, 0).template).not.toBe(req(s0, 0).template);
    expect(req(later, 1)).toEqual(req(taken, 1));
    // 隔了很久才回来：只换一次，抽单时刻是最近一期到期的那一刻。
    const long = view(taken, T0 + 31 * 24 * H);
    expect(req(long, 0)).toMatchObject({ id: 3, drawn_at: T0 + 10 * 72 * H });
    expect(req(long, 1)).toEqual(req(taken, 1));
  });
});

describe('saves (C-191)', () => {
  it('an old save has no board and no count: it reads as an empty board and 0 done, then fills from its first entry', () => {
    const old = { ...welcomed() } as Partial<ParcelFarmState>;
    delete old.board;
    delete old.requests_done;
    const read = withEconomy(old as ParcelFarmState);
    expect(read.board).toEqual({ slots: [], seq: 0, day: null, done_today: 0, bonus_today: 0 });
    expect(read.requests_done).toBe(0);
    expect(reqs(view(old as ParcelFarmState, T0 + 10 * H)).map(r => r!.drawn_at)).toEqual([T0, T0]);
  });

  it('malformed slots and requests are left out; the id counter never goes below a request on the board', () => {
    const s = view(welcomed(), T0);
    const odd = JSON.parse(JSON.stringify(s));
    odd.board.slots.push({ req: { id: 'x' }, refill_at: T0 }, 'nope');
    odd.board.seq = 0;
    odd.requests_done = -3;
    const read = withEconomy(odd);
    expect(read.board.slots).toEqual(s.board.slots);
    expect(read.board.seq).toBe(2);
    expect(read.requests_done).toBe(0);
  });

  it('moving to a newer dataset keeps the board and the count', () => {
    const s = run(stocked(view(welcomed(), T0), 0), [deliver(1)], T0);
    const moved = rebaseFarm(rules, s, T0 + H);
    expect(moved.board).toEqual(s.board);
    expect(moved.requests_done).toBe(1);
  });
});

/**
 * 客户端和服务端同一套委托板规则：tests/dynamic_farm/fixtures/request_cases.json 的每个用例在这里按服务端跑，
 * 在 tests/dynamic_farm/test_parcel_board.gd 里按客户端 parcel_farm.gd 跑，两边结果都要等于文件里记的结果。
 * 没有 commands 的用例是读档（在副本上补到 now）。
 */
describe('C-191 the client runs the same request cases (shared fixture)', () => {
  const shared = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, '..', '..', '..', 'tests', 'dynamic_farm', 'fixtures', 'request_cases.json'), 'utf8'));
  it('has the cases', () => expect(shared.cases.length).toBeGreaterThanOrEqual(12));
  for (const c of shared.cases) {
    it(c.name, () => {
      if (!c.commands) {
        const v = view(structuredClone(c.farm), c.now);
        expect({ ok: true, board: v.board, bag: v.bag, coins: v.coins, requests_done: v.requests_done }).toEqual(c.expect);
        return;
      }
      const r = applyFarmCommands(rules, structuredClone(c.farm), c.commands, c.now);
      expect(r.ok ? { ok: true, board: r.state.board, bag: r.state.bag, coins: r.state.coins, requests_done: r.state.requests_done }
        : { ok: false, index: r.index, code: r.code, detail: r.detail ?? {} }).toEqual(c.expect);
    });
  }
});
