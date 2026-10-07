import { describe, expect, it } from 'vitest';
import { dishBuyback, loadP0Content } from '../../src/p0/content.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 2, 0, 0); // 10:00 Shanghai
const H = 3_600_000;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const refuse = (s: P0State, cmd: P0Command, now = T0) => applyP0(c, s, cmd, now);
const fresh = () => ({ ...freshState(c, 'player-shop-01', T0, 9), created_at: T0 - 8 * 24 * H });
const sale = (ev: P0Event[]) => ev.find(e => e.kind === 'sale') as Extract<P0Event, { kind: 'sale' }>;

describe('wallet floor (q(32))', () => {
  it('every spend but seeds keeps 40 coins in the wallet', () => {
    const s = fresh();
    s.coins = 41; s.skills.fishing = 70; // Fishing Lv2 for worms
    expect(refuse(s, { type: 'buy', item: 'bait_worm', qty: 1 })).toMatchObject({ ok: false, code: 'no_coins', detail: { need: 1 } });
    s.coins = 42;
    expect(step(s, { type: 'buy', item: 'bait_worm', qty: 1 }).s.coins).toBe(40);
    s.coins = 4;
    expect(step(s, { type: 'buy', item: 'seed_radish', qty: 1 }).s.coins).toBe(0); // seeds are exempt (§11.2.2 rule 9)
  });
});

describe('Hot Tea and Coffee (§3.4.4, §9.12)', () => {
  it('+30 up to max, 40 / 50 / 60, three cups a day shared by tea and coffee', () => {
    let s = fresh();
    s.coins = 300; s.energy = { value: 100, tick_ms: T0 };
    let r = step(s, { type: 'drink', item: 'drink_hot_tea', shop: 'tea' });
    expect(r.ev).toContainEqual({ kind: 'drink', item: 'drink_hot_tea', gain: 30, price: 40, left: 2 });
    r = step(r.s, { type: 'drink', item: 'drink_coffee', shop: 'post' });
    expect(r.s.coins).toBe(300 - 40 - 50);
    r = step(r.s, { type: 'drink', item: 'drink_hot_tea', shop: 'tea' });
    expect(r.s.energy.value).toBe(190);
    expect(r.s.bag.some(b => b.id.startsWith('drink_'))).toBe(false);   // drunk at once, never in the bag
    expect(r.s.day.meals).toBe(0);                                      // not counted against meals
    expect(refuse(r.s, { type: 'drink', item: 'drink_coffee', shop: 'post' })).toMatchObject({ ok: false, code: 'drink_limit' });
    // a new player day resets the count
    r.s.energy = { value: 0, tick_ms: T0 + 24 * H };
    expect(step(r.s, { type: 'drink', item: 'drink_coffee', shop: 'post' }, T0 + 24 * H).ev).toContainEqual(expect.objectContaining({ kind: 'drink', price: 40 }));
  });
  it('fills only to max, refuses at max and at the wrong counter', () => {
    const s = fresh();
    s.energy = { value: 188, tick_ms: T0 };
    expect(viewOf(c, s, T0).drinks).toMatchObject({ gain: 12, price: 40, need: 80, full: false, left: 3 });
    const r = step(s, { type: 'drink', item: 'drink_hot_tea', shop: 'tea' });
    expect(r.s.energy.value).toBe(200);
    expect(refuse(r.s, { type: 'drink', item: 'drink_hot_tea', shop: 'tea' })).toMatchObject({ ok: false, code: 'energy_full' });
    expect(refuse(s, { type: 'drink', item: 'drink_hot_tea', shop: 'post' })).toMatchObject({ ok: false, code: 'wrong_shop' });
  });
});

describe('selling by counter (§9.11, §9.13.1)', () => {
  it('the Tackle Shop pays ⌊price × 0.8⌋ for fish, up to 80 coins a day, and sells only what fits', () => {
    const s = fresh();
    s.bag.push({ id: 'fish_koi', qty: 10 }); // price 13 → 10 each
    const r = step(s, { type: 'sell', item: 'fish_koi', qty: 9, shop: 'tackle' });
    expect(sale(r.ev)).toMatchObject({ qty: 8, asked: 9, coins: 80, quota: 'fish_tackle' });
    expect(count(r.s.bag, 'fish_koi')).toBe(2);
    expect(refuse(r.s, { type: 'sell', item: 'fish_koi', qty: 1, shop: 'tackle' })).toMatchObject({ ok: false, code: 'limit_reached' });
    expect(viewOf(c, r.s, T0).quotas.fish_tackle).toMatchObject({ used: 80, cap: 80, scope: 'any Tackle Shop' });
    // at home the same fish sells at full price, no quota
    expect(sale(step(r.s, { type: 'sell', item: 'fish_koi', qty: 2 }).ev)).toMatchObject({ coins: 26, quota: null });
  });
  it('crops are sellable only at home; seeds nowhere', () => {
    const s = fresh();
    s.bag.push({ id: 'crop_radish', qty: 5 });
    expect(refuse(s, { type: 'sell', item: 'crop_radish', qty: 1, shop: 'tackle' })).toMatchObject({ ok: false, code: 'not_sellable_here' });
    expect(refuse(s, { type: 'sell', item: 'seed_radish', qty: 1, shop: 'tackle' })).toMatchObject({ ok: false, code: 'not_sellable' });
  });
  it('dishes sell only at the Homestead Stall at their buyback (120 a day); materials 30 a day; stone never', () => {
    // §7.14 buyback column (q(42)): ⌊Σ ingredient buyback × 0.8⌋
    expect(dishBuyback(c, 'dish_grilled_crucian')).toBe(2);    // ⌊3 × 0.8⌋
    expect(dishBuyback(c, 'dish_herb_grilled_fish')).toBe(3);  // ⌊(3 + 1) × 0.8⌋
    expect(dishBuyback(c, 'dish_fish_soup')).toBe(6);          // ⌊(crucian 3 + radish 5) × 0.8⌋
    expect(dishBuyback(c, 'dish_carrot_cake')).toBe(19);       // ⌊24 × 0.8⌋
    const s = fresh();
    s.bag.push({ id: 'dish_carrot_cake', qty: 5 }, { id: 'wood', qty: 20 }, { id: 'stone', qty: 3 });
    expect(refuse(s, { type: 'sell', item: 'dish_carrot_cake', qty: 1, shop: 'tackle' })).toMatchObject({ ok: false, code: 'not_sellable_here' });
    const cake = dishBuyback(c, 'dish_carrot_cake')!;
    expect(sale(step(s, { type: 'sell', item: 'dish_carrot_cake', qty: 2 }).ev)).toMatchObject({ coins: 2 * cake, quota: 'dish' });
    const wood = step(s, { type: 'sell', item: 'wood', qty: 20 });
    expect(sale(wood.ev)).toMatchObject({ qty: 15, coins: 30, quota: 'material' });
    expect(refuse(s, { type: 'sell', item: 'stone', qty: 1 })).toMatchObject({ ok: false, code: 'not_sellable' });
  });
  it('Sell All skips locked items and gift meals; lock is per item id and shows on every slot', () => {
    let s = fresh();
    s.bag.push({ id: 'crop_lettuce', qty: 4 }, { id: 'dish_carrot_cake', qty: 1, gift: { from: 'res_pip', day: '2026-10-08' } });
    s = step(s, { type: 'lock', item: 'crop_lettuce' }).s;
    expect(refuse(s, { type: 'sell', item: 'crop_lettuce', qty: 'all' })).toMatchObject({ ok: false, code: 'locked_item' });
    const slots = viewOf(c, s, T0).bag.slots;
    expect(slots.find(b => b.id === 'crop_lettuce')).toMatchObject({ locked: true, gifted: false });
    expect(slots.find(b => b.id === 'dish_carrot_cake')).toMatchObject({ locked: false, gifted: true, from: 'res_pip' });
    expect(refuse(s, { type: 'sell', item: 'dish_carrot_cake', qty: 1 })).toMatchObject({ ok: false, code: 'gifted' });
    s = step(s, { type: 'unlock', item: 'crop_lettuce' }).s;
    expect(sale(step(s, { type: 'sell', item: 'crop_lettuce', qty: 'all' }).ev)).toMatchObject({ qty: 4, coins: 32 });
  });
});

describe('Market and Homestead Stall goods (§9.11.1–9.11.5)', () => {
  it('Row Hoe: Farming Lv4, goes to Gear, and sows three plots for 2 Energy each', () => {
    let s = fresh();
    s.coins = 400;
    expect(refuse(s, { type: 'buy', item: 'tool_row_hoe', qty: 1, shop: 'market' })).toMatchObject({ ok: false, code: 'locked', detail: { level: 4 } });
    expect(refuse(s, { type: 'sow', plots: [0, 1], seed: 'seed_radish' })).toMatchObject({ ok: false, code: 'bad_plot', detail: { most: 1 } });
    s.skills.farming = 300;
    s = step(s, { type: 'buy', item: 'tool_row_hoe', qty: 1, shop: 'market' }).s;
    expect(s.gear).toMatchObject({ hoes: ['hoe_starter', 'tool_row_hoe'], hoe: 'tool_row_hoe' });
    expect(s.coins).toBe(160);
    expect(refuse(s, { type: 'buy', item: 'tool_row_hoe', qty: 1, shop: 'market' })).toMatchObject({ ok: false, code: 'owned' });
    const r = step(s, { type: 'sow', plots: [0, 1, 2], seed: 'seed_radish' });
    expect(r.s.energy.value).toBe(194);
    expect(r.s.plots.slice(0, 3).every(p => p.state === 'sown' && p.crop === 'crop_radish')).toBe(true);
    expect(refuse(r.s, { type: 'sow', plots: [3, 4, 5, 6], seed: 'seed_radish' })).toMatchObject({ ok: false, code: 'bad_plot', detail: { most: 3 } });
    expect(step(r.s, { type: 'equip', item: 'hoe_starter' }).s.gear.hoe).toBe('hoe_starter');
  });
  it('the Shanghai Postcard goes to farm storage, once', () => {
    let s = fresh();
    s = step(s, { type: 'buy', item: 'postcard_shanghai', qty: 1, shop: 'market' }).s;
    expect(s.storage).toEqual({ postcard_shanghai: 1 });
    expect(s.coins).toBe(80);
    expect(refuse(s, { type: 'buy', item: 'postcard_shanghai', qty: 1, shop: 'market' })).toMatchObject({ ok: false, code: 'owned' });
    expect(refuse(s, { type: 'buy', item: 'postcard_shanghai', qty: 1 })).toMatchObject({ ok: false, code: 'bad_item' });
  });
  it('Bag Upgrade I: Homestead Lv3, 150 coins + Reeds 10 + Timber 6 from storage, bag 25 → 30', () => {
    let s = fresh();
    s.coins = 300; s.storage = { fiber: 10, wood: 6 };
    expect(refuse(s, { type: 'buy', item: 'bag_upgrade_1', qty: 1 })).toMatchObject({ ok: false, code: 'homestead_level', detail: { need: 3 } });
    s.homestead.level = 3;
    expect(viewOf(c, s, T0).shops.homestead.buy.find(r => r.id === 'bag_upgrade_1')).toMatchObject({ price: 150, need: 190, homestead_ok: true,
      materials: [{ id: 'fiber', name: 'Reeds', need: 10, have: 10 }, { id: 'wood', name: 'Timber', need: 6, have: 6 }] });
    s = step(s, { type: 'buy', item: 'bag_upgrade_1', qty: 1 }).s;
    expect(s.bag_cap).toBe(30);
    expect(s.storage).toEqual({});
    expect(viewOf(c, s, T0).homestead.unlocks.bag_upgrade_1).toBe('owned');
    expect(viewOf(c, s, T0).bag.capacity).toBe(30);
  });
});

describe('Compost (§5.5)', () => {
  it('Farming Lv3 to buy; one per plot, before ripe; −20% of the grow time; gone at harvest', () => {
    let s = fresh();
    expect(refuse(s, { type: 'buy', item: 'fert_compost', qty: 2 })).toMatchObject({ ok: false, code: 'locked', detail: { level: 3 } });
    s.skills.farming = 150;
    s = step(s, { type: 'buy', item: 'fert_compost', qty: 2 }).s;
    s.bag.push({ id: 'seed_chamomile', qty: 2 });
    s = step(s, { type: 'sow', plot: 0, seed: 'seed_chamomile' }).s;
    s = step(s, { type: 'fertilize', plot: 0 }).s;                      // before watering: applied when it starts growing
    expect(refuse(s, { type: 'fertilize', plot: 0 })).toMatchObject({ ok: false, code: 'fertilized' });
    s = step(s, { type: 'water', plot: 0 }).s;
    expect(s.plots[0].ready_at! - T0).toBe(Math.round(18 * H * 0.8)); // 18 h chamomile → 14.4 h (§4.6.1)
    s = step(s, { type: 'sow', plot: 1, seed: 'seed_chamomile' }).s;
    s = step(s, { type: 'water', plot: 1 }).s;
    s = step(s, { type: 'fertilize', plot: 1 }, T0 + 4 * H).s;          // while growing: 3.6 h sooner
    expect(s.plots[1].ready_at! - T0).toBe(18 * H - Math.round(18 * H * 0.2));
    expect(refuse(s, { type: 'fertilize', plot: 2 })).toMatchObject({ ok: false, code: 'wrong_state' });
    const ripe = step(s, { type: 'harvest', plot: 0 }, T0 + 15 * H).s;
    expect(ripe.plots[0].fert).toBeUndefined();
  });
});

describe('farm storage hand-over (§10.4.8)', () => {
  it('stores materials, seeds and compost; takes them back while there is room; never fish or dishes', () => {
    let s = fresh();
    s.bag.push({ id: 'wood', qty: 8 });
    s = step(s, { type: 'store', item: 'wood', qty: 'all' }).s;
    expect(s.storage.wood).toBe(8);
    expect(count(s.bag, 'wood')).toBe(0);
    s = step(s, { type: 'take_out', item: 'wood', qty: 5 }).s;
    expect(s.storage.wood).toBe(3);
    expect(count(s.bag, 'wood')).toBe(5);
    s.bag.push({ id: 'fish_crucian', qty: 1 });
    expect(refuse(s, { type: 'store', item: 'fish_crucian', qty: 1 })).toMatchObject({ ok: false, code: 'not_storable' });
  });
});
