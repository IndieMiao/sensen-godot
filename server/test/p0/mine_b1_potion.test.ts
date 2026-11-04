/** 355 G (contract-efg §9.4, §7.1; §12 item 16): the Healing Potion — sold at the Homestead Stall from its Homestead
 * level with a daily stock, drunk in the mine (mine_drink) on a floor it allows, never past full HP, then its cooldown,
 * which view.mine.at.potion_ready_in counts down. Every number from content.mine.potions. */
import { describe, expect, it } from 'vitest';
import { add, count, room, stackLimit } from '../../src/p0/bag.js';
import { itemKind, loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { dayKey } from '../../src/p0/rules.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const T = Date.UTC(2026, 10, 4, 2), DAY = 86400000, Q = 'wd-dev-quarry', ID = 'potion_heal';
const c = loadP0Content(); c.profile.timezone = 'Asia/Shanghai';
const potion = c.mine.potions[ID], MAX = c.mine.combat.hp;

type Mine = { hp_max: number; at: null | { floor: number; hp: number; day: string; potion_ready_in: number } };
type Row = { id: string; price: number; need: number; homestead: number | null; homestead_ok: boolean; left: number | null; daily: number | null };

function scenario() {
  let s = freshState(c, 'potion-test', T, 7), now = T;
  s.created_at = T - 30 * DAY;
  const send = (cmd: Record<string, unknown>, at = now + 1000) => {
    now = at;
    const r = applyP0(c, s, { day: dayKey(c, s, now), ...cmd } as P0Command, now);
    if (r.ok) s = r.state;
    return r;
  };
  const ok = (cmd: Record<string, unknown>, at?: number): P0Event[] => {
    const r = send(cmd, at);
    if (!r.ok) throw new Error(JSON.stringify({ code: r.code, detail: r.detail }));
    return r.events;
  };
  const refused = (cmd: Record<string, unknown>, at?: number) => {
    const r = send(cmd, at);
    return r.ok ? null : { code: r.code, ...(r.detail === undefined ? {} : { detail: r.detail }) };
  };
  const drink = { type: 'mine_drink', space: 'mine', place: Q, item: ID };
  const enter = () => ok({ type: 'mine_enter', space: 'mine', mine: Q });
  const hurt = (hp: number) => { s.mine.day!.hp = hp; };
  const mine = () => (viewOf(c, s, now) as unknown as { mine: Mine }).mine;
  const row = (shop = 'homestead') => (viewOf(c, s, now) as unknown as { shops: Record<string, { buy: Row[] }> }).shops[shop].buy
    .find(r => r.id === ID);
  return { send, ok, refused, drink, enter, hurt, mine, row, get s(): P0State { return s; }, get now() { return now; } };
}

/** The potion's content for the length of `fn`, restored after. */
function withPotion(patch: Partial<typeof potion>, fn: () => void) {
  const was = { ...potion };
  Object.assign(potion, patch);
  try { fn(); } finally { Object.assign(potion, was); }
}

describe('355 G the Healing Potion at the Homestead Stall (§9.4)', () => {
  it('is on the counter its sold_at names, from its Homestead level, with its daily stock and the 40 floor', () => {
    expect(potion.sold_at).toBe('homestead');
    const t = scenario();
    t.s.homestead.level = potion.gate.homestead - 1;
    expect(t.row()).toMatchObject({ price: potion.price, need: potion.price + c.wallet_floor, homestead: potion.gate.homestead,
      homestead_ok: false, left: potion.stock, daily: potion.stock });
    expect(t.row('tackle')).toBeUndefined();
    expect(t.row('market')).toBeUndefined();
  });

  it('below its Homestead level a buy is homestead_level', () => {
    const t = scenario();
    t.s.homestead.level = potion.gate.homestead - 1; t.s.coins = 10_000;
    expect(t.refused({ type: 'buy', item: ID, qty: 1, shop: 'homestead' })).toEqual({ code: 'homestead_level', detail: { need: potion.gate.homestead } });
    expect(count(t.s.bag, ID)).toBe(0);
  });

  it('bought: the price goes, the potion into the bag; the floor is kept; the stock runs out for the day and comes back', () => {
    const t = scenario();
    t.s.homestead.level = potion.gate.homestead;
    t.s.coins = potion.price + c.wallet_floor - 1;
    expect(t.refused({ type: 'buy', item: ID, qty: 1, shop: 'homestead' })).toEqual({ code: 'no_coins', detail: { need: 1 } });
    t.s.coins = 10_000;
    const ev = t.ok({ type: 'buy', item: ID, qty: 1, shop: 'homestead' });
    expect(t.s.coins).toBe(10_000 - potion.price);
    expect(count(t.s.bag, ID)).toBe(1);
    expect(ev).toContainEqual({ kind: 'item', id: ID, delta: 1 });
    expect(t.row()).toMatchObject({ homestead_ok: true, left: potion.stock - 1 });
    t.ok({ type: 'buy', item: ID, qty: potion.stock - 1, shop: 'homestead' });
    expect(t.refused({ type: 'buy', item: ID, qty: 1, shop: 'homestead' })).toEqual({ code: 'sold_out', detail: { left: 0 } });
    expect(count(t.s.bag, ID)).toBe(potion.stock);
    t.ok({ type: 'buy', item: ID, qty: 1, shop: 'homestead' }, t.now + DAY);   // the next player day
    expect(count(t.s.bag, ID)).toBe(potion.stock + 1);
  });

  it('is not sold at another counter', () => {
    const t = scenario();
    t.s.homestead.level = 10; t.s.coins = 10_000;
    expect(t.refused({ type: 'buy', item: ID, qty: 1, shop: 'market' })).toEqual({ code: 'bad_item' });
  });
});

describe('355 G mine_drink (§9.4)', () => {
  it('only in the mine, and only with today\'s day', () => {
    const t = scenario();
    t.s.bag.push({ id: ID, qty: 2 });
    expect(t.refused(t.drink)).toEqual({ code: 'not_in_mine' });
    t.enter(); t.hurt(10);
    expect(t.refused({ ...t.drink, day: '2026-01-01' })).toEqual({ code: 'new_day' });
    expect(t.refused({ ...t.drink, space: 'farm' })).toEqual({ code: 'not_in_mine' });
    expect(t.s.mine.day!.hp).toBe(10);
  });

  it('refuses in order: not a potion, a floor it does not allow, none in the bag, HP full', () => {
    const t = scenario();
    t.enter(); t.hurt(10);
    expect(t.refused({ ...t.drink, item: 'torch' })).toEqual({ code: 'bad_item' });
    expect(t.refused({ ...t.drink, item: 'toString' })).toEqual({ code: 'bad_item' });
    withPotion({ floors: [2, 3] }, () => expect(t.refused(t.drink)).toEqual({ code: 'not_here' }));
    expect(t.refused(t.drink)).toEqual({ code: 'no_potion' });
    t.s.storage[ID] = 3;   // Farm Storage is not the bag
    expect(t.refused(t.drink)).toEqual({ code: 'no_potion' });
    t.s.bag.push({ id: ID, qty: 1 });
    t.hurt(MAX);
    expect(t.refused(t.drink)).toEqual({ code: 'hp_full' });
    expect(count(t.s.bag, ID)).toBe(1);
  });

  it('drunk: one bottle goes, HP back to full (heal "full"), the heal event, the cooldown in the view', () => {
    expect(potion.heal).toBe('full');
    const t = scenario();
    t.s.bag.push({ id: ID, qty: 2 });
    t.enter();
    expect(t.mine().at!.potion_ready_in).toBe(0);
    t.hurt(7);
    const ev = t.ok(t.drink);
    expect(t.s.mine.day!.hp).toBe(MAX);
    expect(count(t.s.bag, ID)).toBe(1);
    expect(ev).toEqual([{ kind: 'item', id: ID, delta: -1 }, { kind: 'heal', hp: MAX, item: ID }]);
    expect(t.mine().at!.potion_ready_in).toBe(potion.cooldown_ms);
  });

  it('a number heals that much and never past the cap; "any" allows any floor', () => {
    const t = scenario();
    t.s.bag.push({ id: ID, qty: 3 });
    t.enter();
    withPotion({ heal: 30 }, () => {
      t.hurt(50); t.ok(t.drink);
      expect(t.s.mine.day!.hp).toBe(80);
      t.hurt(MAX - 5); t.ok(t.drink, t.now + potion.cooldown_ms);
      expect(t.s.mine.day!.hp).toBe(MAX);
    });
    withPotion({ floors: [1] }, () => { t.hurt(1); t.ok(t.drink, t.now + potion.cooldown_ms); });
    expect(count(t.s.bag, ID)).toBe(0);
  });

  it('within the cooldown it is potion_cooldown with ready_in, the view the same number; after it, it drinks', () => {
    const t = scenario();
    t.s.bag.push({ id: ID, qty: 2 });
    t.enter(); t.hurt(10); t.ok(t.drink);
    const drunk = t.now;
    t.hurt(10);
    const wait = 1000;
    expect(t.refused(t.drink, drunk + potion.cooldown_ms - wait)).toEqual({ code: 'potion_cooldown', detail: { ready_in: wait } });
    expect(t.mine().at!.potion_ready_in).toBe(wait);
    expect(count(t.s.bag, ID)).toBe(1);
    t.ok(t.drink, drunk + potion.cooldown_ms);
    expect(t.s.mine.day!.hp).toBe(MAX);
    expect(count(t.s.bag, ID)).toBe(0);
  });

  it('out of the mine the view has no at, so no potion_ready_in; the rollover clears the drink with the day', () => {
    const t = scenario();
    t.s.bag.push({ id: ID, qty: 2 });
    expect(t.mine().at).toBeNull();
    t.enter();
    withPotion({ cooldown_ms: 2 * DAY }, () => {   // a cooldown past the rollover: only the new day ends it
      t.hurt(10); t.ok(t.drink);
      t.hurt(10);
      expect(t.refused(t.drink)).toMatchObject({ code: 'potion_cooldown' });
      const next = t.now + DAY;   // still on this floor after the rollover (丁15), HP kept
      t.ok(t.drink, next);
      expect(t.s.mine.day!.drink_at).toBe(next);
      expect(t.s.mine.day!.hp).toBe(MAX);
    });
  });
});

describe('355 G the potion\'s bag tier (v4q(7) ⑥)', () => {
  it('a potion is its own kind, a slot of it holds bag.stack.potion (10), not a material\'s 99', () => {
    expect(itemKind(ID)).toBe('potion');
    expect(c.bag.stack.potion).toBe(10);
    expect(stackLimit(c, ID)).toBe(c.bag.stack.potion);
    expect(stackLimit(c, ID)).toBeLessThan(stackLimit(c, 'iron_ore'));
  });

  it('twelve potions take two slots; the room counts a slot as ten', () => {
    const t = scenario();
    const free = t.s.bag_cap - t.s.bag.length;
    add(c, t.s, ID, 12);
    expect(t.s.bag.filter(b => b.id === ID).map(b => b.qty).sort((a, b) => b - a)).toEqual([10, 2]);
    expect(room(c, t.s, ID)).toBe(8 + (free - 2) * 10);
  });

  it('the view says its kind is potion', () => {
    const t = scenario();
    t.s.bag.push({ id: ID, qty: 1 });
    const items = (viewOf(c, t.s, t.now) as unknown as { items: Record<string, { kind: string }> }).items;
    expect(items[ID].kind).toBe('potion');
  });
});
