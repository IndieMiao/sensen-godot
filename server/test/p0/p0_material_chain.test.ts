/** Material workflows retained during 355 E. Mine rules now live in mine_b1*.test.ts. */
import { describe, expect, it } from 'vitest';
import { add, count } from '../../src/p0/bag.js';
import { loadP0Content } from '../../src/p0/content.js';
import { notePresence } from '../../src/p0/presence.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State, SAVE_VERSION } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const content = loadP0Content();
// The 04:00 instants in these tests are Shanghai's (UTC+8), whatever the home city is; p0_city_switch checks the city's zone.
const c = { ...content, profile: { ...content.profile, timezone: 'Asia/Shanghai' } };
const T0 = Date.UTC(2026, 9, 8, 2, 0, 0); // 10:00 Shanghai
const H = 3_600_000;
const STEP = 1_000;   // past the 0.9 s anti-script tempo

const fresh = () => ({ ...freshState(c, 'player-mine-01', T0, 7), created_at: T0 - 8 * 24 * H });

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
function refuse(s: P0State, cmd: P0Command, now = T0): { code: string; detail?: Record<string, unknown> } {
  const r = applyP0(c, s, cmd, now);
  if (r.ok) throw new Error(`${cmd.type} was accepted`);
  return { code: r.code, detail: r.detail };
}
describe('the farm has no gathering spots (v4q(4) ①; the user, 11-02)', () => {
  it('a farm spot\'s old id is bad_spot, the content has none, and the view lists only the city points cooling down', () => {
    for (const spot of ['spot_grove', 'spot_rock_pile', 'spot_reed_bank', 'spot_herb_patch', 'spot_clay_bank', 'spot_old_tree']) {
      expect(refuse(fresh(), { type: 'gather', spot, space: 'home' }).code).toBe('bad_spot');
    }
    expect('spots' in c.gather).toBe(false);
    expect(viewOf(c, fresh(), T0).gather).toEqual({ city_ready: {} });
    expect(c.homestead.levels.flatMap(l => l.unlocks).filter(u => u === 'clay_bank' || u === 'old_tree')).toEqual([]);
  });
});

describe('workbench (§13.4, q(31) / q(44))', () => {
  it('Torch ×2 from Timber 1 + Reeds 1, storage first then the bag; it goes to the bag', () => {
    const s0 = fresh();
    s0.storage = { wood: 1 };
    add(c, s0, 'fiber', 1);
    const { s, ev } = step(s0, { type: 'craft', recipe: 'craft_torch', space: 'home' });
    expect(s.storage).toEqual({});
    expect(count(s.bag, 'fiber')).toBe(0);
    expect(count(s.bag, 'torch')).toBe(2);
    expect(ev).toContainEqual({ kind: 'craft', recipe: 'craft_torch', item: 'torch', qty: 2, to: 'bag' });
  });

  it('torches stack by 20 (§13.1.2)', () => {
    const s = fresh();
    add(c, s, 'torch', 25);
    expect(s.bag.filter(b => b.id === 'torch').map(b => b.qty)).toEqual([20, 5]);
  });

  it('missing materials: need_material with the first gap', () => {
    const s = fresh();
    s.storage = { copper_ore: 4, wood: 4 };
    expect(refuse(s, { type: 'craft', recipe: 'craft_copper_pickaxe' })).toEqual({ code: 'need_material', detail: { item: 'copper_ore', need: 5, have: 4 } });
  });

  it('Compost needs Farming Lv3, like the stall (q(44)); the gate is a refusal, written on the button by the client', () => {
    const s = fresh();
    s.storage = { fiber: 2, wood: 1 };
    expect(refuse(s, { type: 'craft', recipe: 'craft_compost' })).toMatchObject({ code: 'locked', detail: { skill: 'farming', level: 3 } });
    s.skills.farming = 150;
    expect(count(step(s, { type: 'craft', recipe: 'craft_compost' }).s.bag, 'fert_compost')).toBe(2);
  });

  it('no room in the bag: nothing is made and nothing is taken (No room · free a slot first)', () => {
    const s = fresh();
    s.storage = { wood: 1, fiber: 1 };
    for (let i = 0; i < 23; i++) s.bag.push({ id: 'fish_crucian', qty: 10 });
    expect(refuse(s, { type: 'craft', recipe: 'craft_torch' })).toEqual({ code: 'bag_full', detail: { room: 0 } });
    expect(s.storage).toEqual({ wood: 1, fiber: 1 });
  });

  it('the Copper Pickaxe goes to Gear (not equipped until Equip); a second one is owned', () => {
    const s0 = fresh();
    s0.storage = { copper_ore: 10, wood: 8 };
    const { s } = step(s0, { type: 'craft', recipe: 'craft_copper_pickaxe' });
    expect(s.gear.picks).toEqual(['pick_starter', 'pick_copper']);
    expect(s.gear.pick).toBe('pick_starter');
    expect(count(s.bag, 'pick_copper')).toBe(0);
    expect(refuse(s, { type: 'craft', recipe: 'craft_copper_pickaxe' }).code).toBe('owned');
    const v = viewOf(c, step(s, { type: 'equip', item: 'pick_copper' }).s, T0);
    expect(v.gear.picks).toEqual([
      { id: 'pick_starter', name: 'Starter Pickaxe', owned: true, equipped: false, stone: 1, level: 0, price: 0, source: 'start' },
      { id: 'pick_copper', name: 'Copper Pickaxe', owned: true, equipped: true, stone: 2, level: 0, price: 0, source: 'workbench' },
    ]);
  });

  it('Gather Gloves are no recipe any more (the user, 11-02 丁11)', () => {
    const s0 = fresh();
    s0.storage = { fiber: 8, wood: 4 };
    expect(c.workbench.recipes.some(r => r.out === 'gather_gloves')).toBe(false);
    expect(refuse(s0, { type: 'craft', recipe: 'craft_gather_gloves' }).code).toBe('bad_recipe');
    expect(s0.storage).toEqual({ fiber: 8, wood: 4 });
  });

  it('the view gives each recipe\'s costs (storage and bag apart), gate, owned and first block', () => {
    const s = fresh();
    s.storage = { copper_ore: 4, wood: 2 };
    add(c, s, 'wood', 2);
    const w = viewOf(c, s, T0).workbench;
    expect(w.tabs).toEqual(['tools', 'supplies', 'facilities']);   // P1 adds Facilities (SGODOT-239); the P0 client keeps its own two
    const pick = w.recipes.find(r => r.id === 'craft_copper_pickaxe')!;
    expect(pick).toMatchObject({ tab: 'tools', item: 'pick_copper', name: 'Copper Pickaxe', to: 'gear', have: null, owned: false, can_craft: false,
      block: { code: 'need_material', detail: { item: 'copper_ore', need: 5, have: 4 } } });
    expect(pick.cost).toEqual([
      { id: 'copper_ore', name: 'Copper Ore', need: 5, have: 4, storage: 4, bag: 0 },
      { id: 'wood', name: 'Timber', need: 4, have: 4, storage: 2, bag: 2 },
    ]);
    expect(w.recipes.find(r => r.id === 'craft_compost')!.gate).toEqual({ skill: 'farming', level: 3, ok: false, xp_to_go: 150 });
  });

  it('Supplies say You have N over the bag and Farm Storage together (B2-06)', () => {
    const s = fresh();
    s.storage = { torch: 3 };
    add(c, s, 'torch', 2);
    expect(viewOf(c, s, T0).workbench.recipes.find(r => r.id === 'craft_torch')!.have).toBe(5);
  });
});

describe('coming home (q(40)) and Timber Run from storage', () => {
  it('the first command back at home moves the bag\'s materials to storage; seeds, worms, torches and (Lv1) seasonings stay', () => {
    let { s } = step(fresh(), { type: 'mine_enter', mine: 'wd-dev-quarry', space: 'home' });
    s = step(s, { type: 'mine_rock', day: s.mine.day!.key, floor: 1, rock: 0, space: 'mine' }, T0 + STEP).s;
    add(c, s, 'torch', 2); add(c, s, 'bait_worm', 3); add(c, s, 'wild_herb', 3); add(c, s, 'rock_salt', 1); add(c, s, 'copper_ore', 2);
    const stone = count(s.bag, 'stone');
    // the first command read at home (any: the farm has no gathering spot now, v4q(4) ①)
    const r: { s: P0State; ev: P0Event[] } = { s: structuredClone(s), ev: [] };
    expect(notePresence(c, r.s, 'home', T0 + 2 * STEP, r.ev)).toBe(true);
    expect(count(r.s.bag, 'stone')).toBe(0);
    expect(count(r.s.bag, 'copper_ore')).toBe(0);
    expect(r.s.storage.stone).toBe(stone);
    expect(r.s.storage.copper_ore).toBeGreaterThanOrEqual(2);
    // q(46): before the Spice Rack the Lv1 stove cooks from the bag, so seasonings stay with the player.
    expect(count(r.s.bag, 'wild_herb')).toBe(3);
    expect(count(r.s.bag, 'rock_salt')).toBeGreaterThanOrEqual(1);
    expect(r.s.storage.wild_herb).toBeUndefined();
    expect(count(r.s.bag, 'torch')).toBe(2);
    expect(count(r.s.bag, 'bait_worm')).toBe(3);
    expect(count(r.s.bag, 'seed_radish')).toBe(12);   // the start bag's (v4q(4) ⑥ 戊1)
    const stored = r.ev.find(e => e.kind === 'stored');
    expect(stored).toMatchObject({ kind: 'stored', reason: 'home' });
    expect(r.s.storage_auto?.at).toBe(T0 + 2 * STEP);
    expect(viewOf(c, r.s, T0 + 2 * STEP).storage.auto).toEqual(r.s.storage_auto);
  });

  it('with the Spice Rack (Homestead Lv2) seasonings are stored on coming home like any material (q(46))', () => {
    const s = fresh();
    s.homestead.level = 2;
    s.presence.space = 'away';
    add(c, s, 'rock_salt', 2); add(c, s, 'wild_herb', 3);
    expect(notePresence(c, s, 'home', T0, null)).toBe(true);
    expect(s.storage).toEqual({ rock_salt: 2, wild_herb: 3 });
    expect(count(s.bag, 'rock_salt')).toBe(0);
  });

  it('the Homestead Lv2 upgrade puts the bag\'s seasonings away (Spice Rack · seasonings off your bag), nothing else', () => {
    const s = fresh();
    s.skills = { farming: 50, fishing: 0, cooking: 0 };
    s.storage = { wood: 6, stone: 4, fiber: 3 };
    s.coins = 80;
    add(c, s, 'rock_salt', 2); add(c, s, 'wild_herb', 3); add(c, s, 'bait_worm', 2);
    const { s: after, ev } = step(s, { type: 'homestead_upgrade' });
    expect(after.homestead.level).toBe(2);
    expect(after.storage).toEqual({ rock_salt: 2, wild_herb: 3 });
    expect(count(after.bag, 'bait_worm')).toBe(2);
    expect(ev).toContainEqual({ kind: 'stored', items: [['rock_salt', 2], ['wild_herb', 3]], reason: 'spice_rack' });
    expect(after.storage_auto).toBeNull();   // HOME-2 says it; no second float
  });

  it('the space read on entering home (no events) stores too and records storage_auto', () => {
    const s = fresh();
    s.presence.space = 'away';
    add(c, s, 'copper_ore', 3);
    expect(notePresence(c, s, 'home', T0, null)).toBe(true);
    expect(s.storage.copper_ore).toBe(3);
    expect(s.storage_auto).toEqual({ at: T0, items: [['copper_ore', 3]] });
  });

  it('Timber Run takes Timber from Farm Storage first (gathered wood is never in the bag)', () => {
    const s = fresh();
    s.storage = { wood: 2 };
    add(c, s, 'wood', 1);
    s.boards.stall = [{ req: { id: 'req-wood-1', template: 'req_sys_material_wood', items: ['wood'], kind: 'material', qty: 3, bonus: 10,
      drawn_at: T0, status: 'accepted' }, refill_at: 0 }];
    const v = viewOf(c, s, T0).boards.stall.slots[0] as { have: number; ready: boolean };
    expect(v).toMatchObject({ have: 3, ready: true });
    const { s: after, ev } = step(s, { type: 'deliver', request: 'req-wood-1' });
    expect(after.storage.wood).toBeUndefined();
    expect(count(after.bag, 'wood')).toBe(0);
    expect(ev).toContainEqual({ kind: 'request', id: 'req-wood-1', status: 'done', coins: 3 * 2 + 10, bonus: 10 });
  });

  it('Timber Run is in the Stall Board pool now that gathering is live', () => {
    expect(c.requests.templates.req_sys_material_wood.enabled).toBeUndefined();
  });
});

describe('save v4', () => {
  it('a v3 save gains the Starter Pickaxe slot, empty gathering timers and no mine run', () => {
    const old = structuredClone(fresh()) as unknown as Record<string, unknown>;
    for (const k of ['gather', 'mine', 'storage_auto']) delete old[k];
    const gear = old.gear as Record<string, unknown>;
    delete gear.picks; delete gear.pick;
    old.v = 3;
    const s = upgradeState(c, old as unknown as P0State, T0);
    expect(s.v).toBe(SAVE_VERSION);
    expect(s.gear).toMatchObject({ picks: ['pick_starter'], pick: 'pick_starter' });
    expect(s.gather).toEqual({ ready_at: {}, last_at: 0 });
    expect(s.mine).toEqual({ records: {}, day: null, notice: null });
    expect(s.storage_auto).toBeNull();
    expect(s.day.once).toEqual({});
  });
});
