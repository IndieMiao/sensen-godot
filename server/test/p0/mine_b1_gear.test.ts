/** 355 G (contract-efg §9.1, §9.3, §9.5; §12 item 17): the weapon slot — a new save's Wooden Sword in hand, `equip` to a
 * weapon the player owns, and the Iron Sword made at the workbench (Homestead Lv8, its materials and coins, once). */
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { DEFAULT_P0_CONTENT, loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { dayKey } from '../../src/p0/rules.js';
import { freshState, START_WEAPON, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const T = Date.UTC(2026, 10, 4, 2);
const c = loadP0Content(); c.profile.timezone = 'Asia/Shanghai';
const recipe = c.workbench.recipes.find(r => r.id === 'craft_iron_sword')!;
const COPPER = 'weapon_copper_sword', IRON = 'weapon_iron_sword';

function scenario() {
  let s = freshState(c, 'gear-test', T, 7), now = T;
  const send = (cmd: Record<string, unknown>) => {
    now += 1000;
    const r = applyP0(c, s, { day: dayKey(c, s, now), ...cmd } as P0Command, now);
    if (r.ok) s = r.state;
    return r;
  };
  const ok = (cmd: Record<string, unknown>): P0Event[] => {
    const r = send(cmd);
    if (!r.ok) throw new Error(JSON.stringify({ code: r.code, detail: r.detail }));
    return r.events;
  };
  /** Everything the Iron Sword asks, in Farm Storage, and `coins` in the wallet. */
  const stock = (coins: number) => {
    s.homestead.level = recipe.homestead!;
    for (const [id, n] of recipe.cost) s.storage[id] = (s.storage[id] ?? 0) + n;
    s.coins = coins;
  };
  const card = () => (viewOf(c, s, now) as unknown as { workbench: { recipes: Record<string, unknown>[] } })
    .workbench.recipes.find(r => r.id === recipe.id)!;
  return { send, ok, stock, card, get s(): P0State { return s; } };
}

describe('355 G weapons: the slot and equip (§9.1, §9.5)', () => {
  it('a new save holds the Wooden Sword alone, in hand', () => {
    const { s } = scenario();
    expect(s.gear.weapons).toEqual([START_WEAPON]);
    expect(s.gear.weapon).toBe(START_WEAPON);
  });

  it('equip takes a weapon the player owns into hand, and leaves the other slots as they were', () => {
    const t = scenario();
    t.s.gear.weapons.push(COPPER);
    const before = { rod: t.s.gear.rod, hoe: t.s.gear.hoe, pick: t.s.gear.pick };
    expect(t.ok({ type: 'equip', item: COPPER })).toEqual([]);
    expect(t.s.gear.weapon).toBe(COPPER);
    expect({ rod: t.s.gear.rod, hoe: t.s.gear.hoe, pick: t.s.gear.pick }).toEqual(before);
    t.ok({ type: 'equip', item: START_WEAPON });
    expect(t.s.gear.weapon).toBe(START_WEAPON);
  });

  it('a weapon not owned, or one the table does not have, is not_owned and nothing changes', () => {
    const t = scenario();
    const r = t.send({ type: 'equip', item: IRON });
    expect(r.ok ? null : r.code).toBe('not_owned');
    t.s.gear.weapons.push('weapon_made_up');   // a hand-made save
    const made = t.send({ type: 'equip', item: 'weapon_made_up' });
    expect(made.ok ? null : made.code).toBe('not_owned');
    expect(t.s.gear.weapon).toBe(START_WEAPON);
  });
});

describe('355 G the Iron Sword at the workbench (§9.3)', () => {
  it('reads its numbers from the content table: weapon_iron_sword to the weapon slot, Homestead Lv8, coins', () => {
    expect(recipe).toMatchObject({ out: IRON, to: 'weapon', qty: 1, tab: 'tools' });
    expect(recipe.homestead).toBeGreaterThan(0);
    expect(recipe.coins).toBeGreaterThan(0);
    expect(recipe.cost.length).toBeGreaterThan(0);
    expect(c.mine.combat.weapons[IRON]).toBeDefined();
  });

  it('below its Homestead level it is homestead_level, with everything else in hand', () => {
    const t = scenario();
    t.stock(10_000);
    t.s.homestead.level = recipe.homestead! - 1;
    const r = t.send({ type: 'craft', recipe: recipe.id });
    expect(r.ok ? null : [r.code, r.detail]).toEqual(['homestead_level', { need: recipe.homestead }]);
    expect(t.card()).toMatchObject({ homestead: { level: recipe.homestead, ok: false }, can_craft: false,
      block: { code: 'homestead_level', detail: { need: recipe.homestead } } });
  });

  it('a material short is need_material; coins short of the price and the 40 floor is no_coins', () => {
    const t = scenario();
    const need = recipe.coins! + c.wallet_floor;
    t.stock(need);
    const [item, qty] = recipe.cost[recipe.cost.length - 1];
    t.s.storage[item] = qty - 1;
    const r = t.send({ type: 'craft', recipe: recipe.id });
    expect(r.ok ? null : [r.code, r.detail]).toEqual(['need_material', { item, need: qty, have: qty - 1 }]);
    t.s.storage[item] = qty;
    t.s.coins = need - 1;
    const poor = t.send({ type: 'craft', recipe: recipe.id });
    expect(poor.ok ? null : [poor.code, poor.detail]).toEqual(['no_coins', { need: 1 }]);
    expect(t.card()).toMatchObject({ coins: recipe.coins, coins_need: need, coins_have: need - 1 });
  });

  it('made: the materials (Farm Storage first) and the coins go, the sword goes into weapons, not into hand', () => {
    const t = scenario();
    const need = recipe.coins! + c.wallet_floor;
    t.stock(need);
    expect(t.card()).toMatchObject({ to: 'weapon', homestead: { level: recipe.homestead, ok: true }, owned: false,
      equipped: false, can_craft: true, block: null });
    const ev = t.ok({ type: 'craft', recipe: recipe.id });
    expect(t.s.coins).toBe(need - recipe.coins!);
    for (const [id] of recipe.cost) expect(t.s.storage[id] ?? 0).toBe(0);
    expect(t.s.gear.weapons).toEqual([START_WEAPON, IRON]);
    expect(t.s.gear.weapon).toBe(START_WEAPON);
    expect(ev).toContainEqual({ kind: 'coins', delta: -recipe.coins! });
    for (const [id, n] of recipe.cost) expect(ev).toContainEqual({ kind: 'item', id, delta: -n });
    expect(ev).toContainEqual({ kind: 'craft', recipe: recipe.id, item: IRON, qty: 1, to: 'weapon' });
    expect(t.card()).toMatchObject({ owned: true, equipped: false, can_craft: false, block: { code: 'owned' } });
    t.ok({ type: 'equip', item: IRON });
    expect(t.s.gear.weapon).toBe(IRON);
    expect(t.card()).toMatchObject({ owned: true, equipped: true });
  });

  it('once made it is owned: a second craft takes nothing', () => {
    const t = scenario();
    t.stock(recipe.coins! + c.wallet_floor);
    t.ok({ type: 'craft', recipe: recipe.id });
    t.stock(10_000);
    const r = t.send({ type: 'craft', recipe: recipe.id });
    expect(r.ok ? null : r.code).toBe('owned');
    expect(t.s.coins).toBe(10_000);
    expect(t.s.gear.weapons.filter(w => w === IRON)).toHaveLength(1);
  });

  it('a weapon recipe whose out is not a weapon of mine.combat fails the load', () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'p0-gear-'));
    try {
      cpSync(path.dirname(DEFAULT_P0_CONTENT), dir, { recursive: true });
      const file = path.join(dir, 'content', 'mine_b1.json');
      const t = JSON.parse(readFileSync(file, 'utf8'));
      t.workbench.recipes[0].out = 'weapon_made_up';
      writeFileSync(file, JSON.stringify(t));
      expect(() => loadP0Content(path.join(dir, 'p0_content.json'))).toThrow(/craft_iron_sword makes weapon_made_up/);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
});
