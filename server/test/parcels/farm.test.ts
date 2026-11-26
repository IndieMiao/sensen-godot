/** 动态农场地块内命令（C-31）：首次进入的赠品、格子一致性、背包、按服务端时间成熟。 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { applyFarmCommands, emptyFarm, grant, MAX_BATCH, MAX_BUY_COUNT, MAX_COINS, MAX_SELL_COUNT, NEVER, parseCell, parseFarmCommands, rebaseFarm,
  welcome, withEconomy, type FarmCommand, type ParcelFarmState } from '../../src/parcels/farm.js';
import { maxEnergy } from '../../src/parcels/energy.js';
import { buildingMax, communityOf, isNewerDataset, loadParcelRules, nextFarmLevel, parseParcelRules } from '../../src/parcels/rules.js';

const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const T0 = Date.UTC(2026, 10, 23, 4);
/** 首次进入后的农场。 */
const welcomed = (): ParcelFarmState => welcome(rules, emptyFarm(), T0)!;

function run(state: ParcelFarmState, commands: FarmCommand[], now = T0): ParcelFarmState {
  const out = applyFarmCommands(rules, state, commands, now);
  if (!out.ok) throw new Error(`${out.code} @${out.index}`);
  return out.state;
}
/** 井在这一格（C-151 的测试用位置，离其它测试用的格子都远）。 */
const WELL_AT = { x: 30, y: 30 };
/**
 * C-151：浇 cells 这几格。没有井就先领补发（井的蓝图、水桶）、把井盖在 WELL_AT；每 3 格打一次水。
 */
function watered(state: ParcelFarmState, cells: string[], now = T0): ParcelFarmState {
  let s = state.buildings?.some(b => b.type === 'well') ? state
    : run(grant(rules, state, now)?.state ?? state, [{ type: 'place_building', building: 'well', ...WELL_AT, rotation: 0 }], now);
  const well = s.buildings.find(b => b.type === 'well')!.id;
  for (let i = 0; i < cells.length; i += 3)
    s = run(s, [{ type: 'draw_water', building: well }, ...cells.slice(i, i + 3).map(cell => ({ type: 'water', cell }) as FarmCommand)], now);
  return s;
}

describe('dynamic_farm.json', () => {
  it('ships the owner-approved numbers: Q-39 (C-34#14) and Q-40 (C-33#14)', () => {
    // Q-39: 1 hoe and 3 carrot seeds on first entry, carrots ripe 60 s after sowing by server time.
    // Q-40: 1 first-house blueprint on first entry; the approved 3×3 cottage (C-30#12) is built as soon as it is placed.
    expect(rules.welcome_gift).toEqual({ hoe_starter: 1, seed_carrot: 3, blueprint_cottage: 1 });
    // C-150: the cottage, at most one per parcel, as Q-40's single first house. C-151: the well (well.glb, SEN-C-151's goal) on
    // one cell as P0's well (modules/p0/p0_garden.gd), one at level 1 (more wells come with farm levels, SEN-C-152).
    expect(rules.buildings).toEqual({ cottage: { model: 'cottage', blueprint: 'blueprint_cottage', width: 3, depth: 3, max: 1 },
      well: { model: 'well', blueprint: 'blueprint_well', width: 1, depth: 1, max: 1 } });
    // C-151 (owner SEN-C-137#6, #15): a pail holds 3 waterings, filled at a well; every farm gets one well blueprint and one pail, once.
    expect(rules.watering).toEqual({ well: 'well', pail: 'pail', pail_uses: 3 });
    expect(rules.grants).toEqual({ watering: { blueprint_well: 1, pail: 1 } });
    // C-148: sowing a carrot costs 3 Energy, P0's carrot (assets/p0/p0_content.json crops.crop_carrot.energy).
    expect(rules.crops).toEqual({ crop_carrot: { seed: 'seed_carrot', grow_seconds: 60, yield: 1, energy: 3 } });
    expect(rules.till_tool).toBe('hoe_starter');
    expect(communityOf(rules, 'sf-dynamic-farm-20261118-r4')).toBe('sf');
    expect(communityOf(rules, 'sf-dynamic-farm-20261124-r6')).toBe('sf'); // C-43: r6, r5 without its broken building rings (V-167)
    expect(communityOf(rules, 'sf-dynamic-farm-20261125-r8')).toBe('sf'); // C-113: r8, r6's parcels plus OSM buildings where DataSF has none
    expect(communityOf(rules, 'sf-dynamic-farm-20261124-r5')).toBeNull(); // never shipped
    expect(communityOf(rules, 'nope')).toBeNull();
  });

  it('refuses malformed rules at load time', () => {
    expect(() => parseParcelRules({ ...rules, version: 2 })).toThrow();
    expect(() => parseParcelRules({ ...rules, crops: { crop_carrot: { seed: 'seed_carrot', grow_seconds: 0, yield: 1 } } })).toThrow();
    expect(() => parseParcelRules({ ...rules, communities: [{ id: 'a', datasets: ['d'] }, { id: 'b', datasets: ['d'] }] })).toThrow();
    expect(() => parseParcelRules({ ...rules, buildings: { cottage: { model: 'cottage', width: 3, depth: 3, max: 1 } } })).toThrow();
    expect(() => parseParcelRules({ ...rules, buildings: { cottage: { ...rules.buildings.cottage, max: 0 } } })).toThrow();
    expect(() => parseParcelRules({ ...rules, buildings: { cottage: { ...rules.buildings.cottage, width: 17 } } })).toThrow();
    // The cottage must stay: old saves' house and old clients' place_house are cottages.
    expect(() => parseParcelRules({ ...rules, buildings: { well: { ...rules.buildings.cottage, model: 'well' } } })).toThrow();
    expect(() => parseParcelRules({ ...rules, buildings: undefined })).toThrow();
    expect(() => parseParcelRules({ ...rules, till_tool: undefined })).toThrow();
    expect(() => parseParcelRules({ ...rules, welcome_gift: undefined })).toThrow();
  });
});

describe('first entry gift', () => {
  it('a claimed parcel starts empty; the first entry gives the gift once, never again', () => {
    expect(emptyFarm()).toMatchObject({ bag: {}, welcomed_at: null, house: null });
    const once = welcomed();
    expect(once.bag).toEqual({ hoe_starter: 1, seed_carrot: 3, blueprint_cottage: 1 });
    expect(once.welcomed_at).toBe(T0);
    expect(welcome(rules, once, T0 + 1000)).toBeNull();
    // Spent the gift: entering again still gives nothing back.
    const spent = run(once, [{ type: 'place_house', x: 9, y: 9 }, { type: 'till', cell: '1,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' }]);
    expect(welcome(rules, spent, T0 + 2000)).toBeNull();
  });
});

describe('parcel farm commands', () => {
  it('accepts only canonical cells and known command shapes', () => {
    expect(parseCell('0,12')).toEqual([0, 12]);
    for (const bad of ['01,2', '1, 2', '-1,2', '1024,0', '1,2,3', 3]) expect(parseCell(bad)).toBeNull();
    expect(parseFarmCommands([{ type: 'till', cell: '1,2' }])).toEqual([{ type: 'till', cell: '1,2' }]);
    expect(parseFarmCommands([{ type: 'place_house', x: 1, y: 2 }])).toEqual([{ type: 'place_house', x: 1, y: 2, rotation: 0 }]);
    expect(parseFarmCommands([])).toBeNull();
    expect(parseFarmCommands([{ type: 'teleport', cell: '1,2' }])).toBeNull();
    expect(parseFarmCommands([{ type: 'place_house', x: 1, y: 2, rotation: 4 }])).toBeNull();
    expect(parseFarmCommands(Array.from({ length: MAX_BATCH + 1 }, () => ({ type: 'till', cell: '1,2' })))).toBeNull();
  });

  it('runs the first loop: house built at once, clear, till, sow, water, harvest 60 s of server time after watering', () => {
    let s = welcomed();
    s = run(s, [{ type: 'place_house', x: 10, y: 10 }, { type: 'clear_obstacle', cell: '3,3' }, { type: 'till', cell: '3,3' },
      { type: 'sow', cell: '3,3', crop: 'crop_carrot' }]);
    expect(s.house).toEqual({ model: 'cottage', x: 10, y: 10, width: 3, depth: 3, rotation: 0, built_at: T0 });
    expect(s.cleared).toEqual(['3,3']);
    // C-151: sown on dry soil it does not grow until it is watered.
    expect(s.crops['3,3']).toEqual({ crop: 'crop_carrot', planted_at: T0, ripe_at: NEVER, watered_at: null });
    // The blueprint and one seed are used.
    expect(s.bag).toEqual({ hoe_starter: 1, seed_carrot: 2 });
    expect(applyFarmCommands(rules, s, [{ type: 'harvest', cell: '3,3' }], T0 + 86_400_000)).toEqual({ ok: false, index: 0, code: 'NOT_WATERED' });

    const W = T0 + 30_000;
    s = watered(s, ['3,3'], W);
    expect(s.crops['3,3']).toEqual({ crop: 'crop_carrot', planted_at: T0, ripe_at: W + 60_000, watered_at: W });
    const early = applyFarmCommands(rules, s, [{ type: 'harvest', cell: '3,3' }], W + 59_999);
    expect(early).toEqual({ ok: false, index: 0, code: 'NOT_RIPE', detail: { ripe_at: W + 60_000 } });
    s = run(s, [{ type: 'harvest', cell: '3,3' }], W + 60_000);
    expect(s.crops).toEqual({});
    expect(s.tilled).toEqual(['3,3']);
    expect(s.bag).toEqual({ hoe_starter: 1, seed_carrot: 2, crop_carrot: 1, pail: 1 });
  });

  it('the house needs the blueprint, goes down once, and stays off tilled ground; tilling stays off the house', () => {
    expect(applyFarmCommands(rules, emptyFarm(), [{ type: 'place_house', x: 4, y: 4 }], T0)).toMatchObject({ ok: false, code: 'NO_BLUEPRINT' });
    const s = run(welcomed(), [{ type: 'till', cell: '5,5' }]);
    expect(applyFarmCommands(rules, s, [{ type: 'place_house', x: 4, y: 4 }], T0)).toMatchObject({ ok: false, code: 'CELL_OCCUPIED', detail: { cells: ['5,5'] } });
    const housed = run(s, [{ type: 'place_house', x: 6, y: 6 }]);
    expect(housed.bag.blueprint_cottage).toBeUndefined();
    expect(applyFarmCommands(rules, housed, [{ type: 'till', cell: '8,8' }], T0)).toMatchObject({ ok: false, code: 'CELL_OCCUPIED' });
    expect(applyFarmCommands(rules, housed, [{ type: 'place_house', x: 20, y: 20 }], T0)).toMatchObject({ ok: false, code: 'HOUSE_PLACED' });
    expect(applyFarmCommands(rules, welcomed(), [{ type: 'place_house', x: 1022, y: 0 }], T0)).toMatchObject({ ok: false, code: 'OUT_OF_BOUNDS' });
  });

  it('needs the hoe, a tilled cell and a seed; a refused batch changes nothing', () => {
    expect(applyFarmCommands(rules, emptyFarm(), [{ type: 'till', cell: '1,1' }], T0)).toMatchObject({ ok: false, code: 'NO_TOOL' });
    const s = welcomed();
    expect(applyFarmCommands(rules, s, [{ type: 'sow', cell: '1,1', crop: 'crop_carrot' }], T0)).toMatchObject({ ok: false, code: 'NOT_TILLED' });
    expect(applyFarmCommands(rules, s, [{ type: 'till', cell: '1,1' }, { type: 'sow', cell: '1,1', crop: 'crop_potato' }], T0))
      .toMatchObject({ ok: false, index: 1, code: 'UNKNOWN_CROP' });
    expect(s).toEqual(welcomed());
    const cells = Array.from({ length: 4 }, (_, i) => `${i},0`);
    const tilled = run(s, cells.map(cell => ({ type: 'till', cell }) as FarmCommand));
    const sown = run(tilled, cells.slice(0, 3).map(cell => ({ type: 'sow', cell, crop: 'crop_carrot' }) as FarmCommand));
    expect(sown.bag.seed_carrot).toBeUndefined();
    expect(applyFarmCommands(rules, sown, [{ type: 'sow', cell: '3,0', crop: 'crop_carrot' }], T0)).toMatchObject({ ok: false, code: 'NO_SEED' });
    expect(applyFarmCommands(rules, sown, [{ type: 'sow', cell: '0,0', crop: 'crop_carrot' }], T0)).toMatchObject({ ok: false, code: 'CELL_OCCUPIED' });
    expect(applyFarmCommands(rules, sown, [{ type: 'till', cell: '0,0' }], T0)).toMatchObject({ ok: false, code: 'ALREADY_TILLED' });
    expect(applyFarmCommands(rules, sown, [{ type: 'harvest', cell: '9,9' }], T0)).toMatchObject({ ok: false, code: 'NO_CROP' });
    expect(applyFarmCommands(rules, run(s, [{ type: 'clear_obstacle', cell: '2,2' }]), [{ type: 'clear_obstacle', cell: '2,2' }], T0))
      .toMatchObject({ ok: false, code: 'ALREADY_CLEARED' });
  });
});

/** C-58（0.4.3）：地块金币、出售、外围采集、鸡舍蓝图。数值出处 C-30#29 第 3–5 题（C-30#30 按推荐写入）。 */
describe('parcel economy (C-58)', () => {
  const ME = { parcel_id: 'p-3512001' };
  const RECIPE = 'outer-groves-v2';
  const obj = (model: string, cell: string, parcel = ME.parcel_id, recipe = RECIPE, n = 0) => `${parcel}:${recipe}:${model}:${cell}:${n}`;
  const DAY = 24 * 3600 * 1000;
  const runAt = (state: ParcelFarmState, commands: FarmCommand[], now = T0) => {
    const out = applyFarmCommands(rules, state, commands, now, ME);
    if (!out.ok) throw new Error(`${out.code} @${out.index}`);
    return out.state;
  };
  /** ctx=null: no server-verified parcel at all. */
  const tryAt = (state: ParcelFarmState, commands: FarmCommand[], now = T0, ctx: { parcel_id: string } | null = ME) =>
    applyFarmCommands(rules, state, commands, now, ctx ?? undefined);
  /** 背包里有 n 个萝卜的农场（经种收得来，不直接改背包）。 */
  const withCarrots = (): ParcelFarmState => {
    let s = run(welcomed(), [{ type: 'till', cell: '1,1' }, { type: 'till', cell: '2,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' },
      { type: 'sow', cell: '2,1', crop: 'crop_carrot' }]);
    s = run(watered(s, ['1,1', '2,1']), [{ type: 'harvest', cell: '1,1' }, { type: 'harvest', cell: '2,1' }], T0 + 60_000);
    expect(s.bag.crop_carrot).toBe(2);
    return s;
  };

  it('ships the C-30#29 numbers: carrot 12, timber 2, wild herb 1, stone 2; 24 h respawn; coop blueprint after the first sale', () => {
    expect(rules.economy.sell_prices).toEqual({ crop_carrot: 12, wood: 2, wild_herb: 1, stone: 2 });
    expect(rules.economy.gather.respawn_seconds).toBe(24 * 3600);
    expect(Object.fromEntries(Object.entries(rules.economy.gather.sources).map(([k, v]) => [k, [v.item, v.amount]])))
      .toEqual({ tree: ['wood', 1], flower: ['wild_herb', 1], rock: ['stone', 1] });
    expect(rules.economy.blueprints).toEqual({ coop: { item: 'blueprint_coop', amount: 1, min_sales: 1 } });
    // Coins start at 0, separate from the main farm.
    expect(emptyFarm()).toMatchObject({ coins: 0, sales: 0, gathered: {}, blueprints_claimed: {} });
  });

  it('locks the outer-object ids to the art recipe the client places (version and model names)', () => {
    const recipe = JSON.parse(readFileSync(path.resolve(DEFAULT_CONTENT_DIR, '..', '..', 'dynamic_farm', '499-art-recipe.json'), 'utf8'));
    expect(rules.economy.gather.recipe_version).toBe(recipe.outer_groves.version);
    for (const [role, src] of Object.entries(rules.economy.gather.sources)) {
      for (const m of src.models) expect(recipe.roles[role].ids).toContain(m);
      // A parcel never holds more of one kind than the recipe's cap, so neither can one day's gathering.
      expect(src.max_objects).toBe(recipe.outer_groves.targets[role].cap);
    }
    // Main-farm prices the defaults follow (C-30#29 Q3): carrot 12, timber 2, wild herb 1; stone has none there.
    const p0 = JSON.parse(readFileSync(path.resolve(DEFAULT_CONTENT_DIR, '..', '..', 'p0', 'p0_content.json'), 'utf8'));
    expect(p0.crops.find((c: { id: string }) => c.id === 'crop_carrot').price).toBe(rules.economy.sell_prices.crop_carrot);
    expect(p0.materials.wood.price).toBe(rules.economy.sell_prices.wood);
    expect(p0.materials.wild_herb.price).toBe(rules.economy.sell_prices.wild_herb);
    expect(p0.materials.stone.price).toBeNull();
  });

  it('refuses out-of-bounds economy numbers at load time', () => {
    const eco = rules.economy;
    const bad = (economy: unknown) => () => parseParcelRules({ ...rules, economy });
    expect(bad(undefined)).toThrow();
    expect(bad({ ...eco, sell_prices: {} })).toThrow();
    expect(bad({ ...eco, sell_prices: { crop_carrot: 0 } })).toThrow();
    expect(bad({ ...eco, sell_prices: { crop_carrot: 1.5 } })).toThrow();
    expect(bad({ ...eco, sell_prices: { crop_carrot: 100_001 } })).toThrow();
    expect(bad({ ...eco, gather: { ...eco.gather, respawn_seconds: 0 } })).toThrow();
    expect(bad({ ...eco, gather: { ...eco.gather, respawn_seconds: 31 * 24 * 3600 } })).toThrow();
    expect(bad({ ...eco, gather: { ...eco.gather, recipe_version: 'Bad Version' } })).toThrow();
    expect(bad({ ...eco, gather: { ...eco.gather, sources: { tree: { item: 'wood', amount: 0, max_objects: 1, models: ['a'] } } } })).toThrow();
    expect(bad({ ...eco, gather: { ...eco.gather, sources: { tree: { item: 'wood', amount: 1, max_objects: 1, models: [] } } } })).toThrow();
    expect(bad({ ...eco, gather: { ...eco.gather, sources: { tree: { item: 'wood', amount: 1, models: ['a'] } } } })).toThrow();
    expect(bad({ ...eco, gather: { ...eco.gather, sources: { tree: { item: 'wood', amount: 1, max_objects: 0, models: ['a'] } } } })).toThrow();
    expect(bad({ ...eco, gather: { ...eco.gather, sources: { a: { item: 'wood', amount: 1, max_objects: 1, models: ['m'] },
      b: { item: 'stone', amount: 1, max_objects: 1, models: ['m'] } } } })).toThrow();
    // The shipped file itself parses.
    expect(() => parseParcelRules(structuredClone(rules))).not.toThrow();
    expect(bad({ ...eco, blueprints: { coop: { item: 'blueprint_coop', amount: 1, min_sales: -1 } } })).toThrow();
    expect(bad({ ...eco, blueprints: { coop: { item: 'blueprint_coop', amount: 100, min_sales: 1 } } })).toThrow();
    expect(bad({ ...eco, blueprints: undefined })).toThrow();
  });

  it('an old C-31 save without economy fields reads as 0 coins, nothing sold, gathered or claimed; existing fields untouched', () => {
    const legacy = { v: 1, house: null, cleared: ['2,2'], tilled: ['1,1'], crops: {}, bag: { hoe_starter: 1, crop_carrot: 1 }, welcomed_at: T0 } as unknown as ParcelFarmState;
    const frozen = structuredClone(legacy);
    expect(withEconomy(legacy)).toEqual({ ...frozen, buildings: [], coins: 0, sales: 0, gathered: {}, blueprints_claimed: {}, pail_water: 0, grants: {},
      level: 1 });
    expect(legacy).toEqual(frozen);
    expect(withEconomy({ ...legacy, coins: 30, sales: 2 } as ParcelFarmState)).toMatchObject({ coins: 30, sales: 2 });
    // And it can sell straight away.
    expect(runAt(legacy, [{ type: 'sell', item: 'crop_carrot', count: 1 }])).toMatchObject({ coins: 12, sales: 1, bag: { hoe_starter: 1 } });
  });

  it('sell: refuses too few or unpriced items; on success the bag shrinks and coins grow by the configured price', () => {
    const s = withCarrots();
    expect(tryAt(s, [{ type: 'sell', item: 'crop_carrot', count: 3 }])).toEqual({ ok: false, index: 0, code: 'NOT_ENOUGH', detail: { item: 'crop_carrot', have: 2, need: 3 } });
    expect(tryAt(s, [{ type: 'sell', item: 'wood', count: 1 }])).toMatchObject({ ok: false, code: 'NOT_ENOUGH', detail: { have: 0 } });
    expect(tryAt(s, [{ type: 'sell', item: 'hoe_starter', count: 1 }])).toMatchObject({ ok: false, code: 'NOT_SELLABLE' });
    expect(tryAt(s, [{ type: 'sell', item: 'blueprint_cottage', count: 1 }])).toMatchObject({ ok: false, code: 'NOT_SELLABLE' });
    expect(tryAt(s, [{ type: 'sell', item: 'constructor', count: 1 }])).toMatchObject({ ok: false, code: 'NOT_SELLABLE' });
    const one = runAt(s, [{ type: 'sell', item: 'crop_carrot', count: 1 }]);
    expect(one).toMatchObject({ coins: 12, sales: 1 });
    expect(one.bag.crop_carrot).toBe(1);
    const two = runAt(one, [{ type: 'sell', item: 'crop_carrot', count: 1 }]);
    expect(two).toMatchObject({ coins: 24, sales: 2 });
    expect(two.bag.crop_carrot).toBeUndefined();
    // A refused batch leaves coins and bag as they were.
    expect(tryAt(s, [{ type: 'sell', item: 'crop_carrot', count: 2 }, { type: 'sell', item: 'crop_carrot', count: 1 }])).toMatchObject({ ok: false, index: 1, code: 'NOT_ENOUGH' });
    expect(s.coins).toBe(0);
    expect(s.bag.crop_carrot).toBe(2);
    // Coins are capped.
    expect(tryAt({ ...s, coins: MAX_COINS - 23 }, [{ type: 'sell', item: 'crop_carrot', count: 2 }])).toMatchObject({ ok: false, code: 'COINS_CAP' });
  });

  it('sell: the request carries no price; counts must be whole and bounded', () => {
    expect(parseFarmCommands([{ type: 'sell', item: 'crop_carrot', count: 2, price: 9999 }])).toEqual([{ type: 'sell', item: 'crop_carrot', count: 2 }]);
    for (const count of [0, -1, 1.5, MAX_SELL_COUNT + 1, '2', undefined]) expect(parseFarmCommands([{ type: 'sell', item: 'crop_carrot', count }])).toBeNull();
    expect(parseFarmCommands([{ type: 'sell', item: 7, count: 1 }])).toBeNull();
  });

  it('gather: gives one of the configured item; again within 24 h of server time is refused, after that it is back', () => {
    const s = welcomed();
    const tree = obj('wild_pz_tree_20', '41,7');
    const a = runAt(s, [{ type: 'gather', object: tree }, { type: 'gather', object: obj('wild_pz_flower_23', '40,9') },
      { type: 'gather', object: obj('wild_pz_rock_13', '3,30') }]);
    expect(a.bag).toMatchObject({ wood: 1, wild_herb: 1, stone: 1 });
    expect(a.gathered[tree]).toBe(T0);
    expect(tryAt(a, [{ type: 'gather', object: tree }], T0 + DAY - 1)).toEqual({ ok: false, index: 0, code: 'NOT_RESPAWNED', detail: { ready_at: T0 + DAY } });
    // Two objects of one model in one cell are told apart by their ordinal.
    expect(runAt(a, [{ type: 'gather', object: obj('wild_pz_tree_20', '41,7', ME.parcel_id, RECIPE, 1) }]).bag.wood).toBe(2);
    // The same object twice in one batch: the second is refused and nothing lands.
    expect(tryAt(s, [{ type: 'gather', object: tree }, { type: 'gather', object: tree }])).toMatchObject({ ok: false, index: 1, code: 'NOT_RESPAWNED' });
    const b = runAt(a, [{ type: 'gather', object: tree }], T0 + DAY);
    expect(b.bag.wood).toBe(2);
    // Respawned records are dropped when the next gather lands; only live ones are kept.
    expect(b.gathered).toEqual({ [tree]: T0 + DAY });
  });

  it('gather: refuses ids that do not exist, belong to another parcel, an old recipe, or a core cell', () => {
    const s = run(welcomed(), [{ type: 'place_house', x: 10, y: 10 }, { type: 'clear_obstacle', cell: '5,5' }, { type: 'till', cell: '6,6' }]);
    const code = (object: string, ctx: { parcel_id: string } | null = ME) => {
      const out = tryAt(s, [{ type: 'gather', object }], T0, ctx);
      return out.ok ? 'OK' : out.code;
    };
    for (const bad of ['', 'wild_pz_tree_20', `${ME.parcel_id}:${RECIPE}:wild_pz_tree_20:41,7`, `${ME.parcel_id}:${RECIPE}:wild_pz_tree_20:041,7:0`,
      `${ME.parcel_id}:${RECIPE}:wild_pz_tree_20:1024,7:0`, `${ME.parcel_id}:${RECIPE}:wild_pz_tree_20:41,7:100`, `3512001:${RECIPE}:wild_pz_tree_20:41,7:0`])
      expect(code(bad)).toBe('UNKNOWN_OBJECT');
    // Not gatherable: shrubs, groundcover, core obstacles, the house, made-up models.
    for (const model of ['wild_pz_bush_05', 'wild_pz_grass_24', 'cottage', 'gold_tree']) expect(code(obj(model, '41,7'))).toBe('UNKNOWN_OBJECT');
    expect(code(obj('wild_pz_tree_20', '41,7', 'p-3512002'))).toBe('NOT_YOUR_PARCEL');
    expect(code(obj('wild_pz_tree_20', '41,7'), null)).toBe('NOT_YOUR_PARCEL');
    expect(code(obj('wild_pz_tree_20', '41,7', ME.parcel_id, 'outer-groves-v1'))).toBe('STALE_RECIPE');
    // Cells the server knows are core: under the house, cleared obstacles, tilled ground.
    for (const cell of ['11,11', '5,5', '6,6']) expect(code(obj('wild_pz_tree_20', cell))).toBe('NOT_OUTER');
    expect(code(obj('wild_pz_tree_20', '41,7'))).toBe('OK');
    expect(parseFarmCommands([{ type: 'gather', object: 'x'.repeat(257) }])).toBeNull();
  });

  it('gather: within one respawn window no more objects of a kind than the recipe can place (made-up ids gain nothing more)', () => {
    const cap = rules.economy.gather.sources.rock.max_objects;
    const rocks = Array.from({ length: cap }, (_, i) => ({ type: 'gather', object: obj('wild_pz_rock_08', `${i},40`) }) as FarmCommand);
    let s = welcomed();
    for (let i = 0; i < rocks.length; i += MAX_BATCH) s = runAt(s, rocks.slice(i, i + MAX_BATCH));
    expect(s.bag.stone).toBe(cap);
    expect(tryAt(s, [{ type: 'gather', object: obj('wild_pz_rock_13', '200,40') }])).toEqual({ ok: false, index: 0, code: 'TOO_MANY_OBJECTS', detail: { max: cap } });
    // Other kinds are counted separately; after the respawn the rocks are available again.
    expect(runAt(s, [{ type: 'gather', object: obj('wild_pz_tree_20', '200,40') }]).bag.wood).toBe(1);
    expect(runAt(s, [{ type: 'gather', object: obj('wild_pz_rock_13', '200,40') }], T0 + DAY).bag.stone).toBe(cap + 1);
    expect(parseFarmCommands([{ type: 'gather' }])).toBeNull();
  });

  it('coop blueprint: refused before the first sale, given once after it, never again', () => {
    const s = withCarrots();
    expect(tryAt(s, [{ type: 'claim_blueprint', blueprint: 'coop' }])).toEqual({ ok: false, index: 0, code: 'CONDITION_NOT_MET', detail: { sales: 0, min_sales: 1 } });
    // Gathering is not selling.
    expect(tryAt(runAt(s, [{ type: 'gather', object: obj('wild_pz_tree_20', '41,7') }]), [{ type: 'claim_blueprint', blueprint: 'coop' }]))
      .toMatchObject({ ok: false, code: 'CONDITION_NOT_MET' });
    const sold = runAt(s, [{ type: 'sell', item: 'crop_carrot', count: 1 }]);
    const got = runAt(sold, [{ type: 'claim_blueprint', blueprint: 'coop' }], T0 + 5);
    expect(got.bag.blueprint_coop).toBe(1);
    expect(got.blueprints_claimed).toEqual({ coop: T0 + 5 });
    expect(tryAt(got, [{ type: 'claim_blueprint', blueprint: 'coop' }])).toMatchObject({ ok: false, code: 'BLUEPRINT_CLAIMED' });
    // Spending or selling more does not re-open it.
    const more = runAt(got, [{ type: 'sell', item: 'crop_carrot', count: 1 }]);
    expect(tryAt(more, [{ type: 'claim_blueprint', blueprint: 'coop' }])).toMatchObject({ ok: false, code: 'BLUEPRINT_CLAIMED' });
    expect(tryAt(sold, [{ type: 'claim_blueprint', blueprint: 'castle' }])).toMatchObject({ ok: false, code: 'UNKNOWN_BLUEPRINT' });
    expect(tryAt(sold, [{ type: 'claim_blueprint', blueprint: '__proto__' }])).toMatchObject({ ok: false, code: 'UNKNOWN_BLUEPRINT' });
    // Selling and claiming in one batch works (the sale counts at once).
    expect(runAt(s, [{ type: 'sell', item: 'crop_carrot', count: 1 }, { type: 'claim_blueprint', blueprint: 'coop' }]).bag.blueprint_coop).toBe(1);
  });
});

/** C-149（0.4.5）：Jasmine 卖种子。胡萝卜种子 9 金币照 P0（所有者 C-137#15 第 3 题“照搬p0”）；单价只看服务端配置。 */
describe('parcel buy (C-149)', () => {
  /** 卖过 2 个萝卜、有 24 金币的农场（经种、浇（C-151）、收、卖得来，不直接改金币）。 */
  const with24 = (): ParcelFarmState => {
    let s = run(welcomed(), [{ type: 'till', cell: '1,1' }, { type: 'till', cell: '2,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' },
      { type: 'sow', cell: '2,1', crop: 'crop_carrot' }]);
    s = watered(s, ['1,1', '2,1']);
    s = run(s, [{ type: 'harvest', cell: '1,1' }, { type: 'harvest', cell: '2,1' }, { type: 'sell', item: 'crop_carrot', count: 2 }], T0 + 60_000);
    expect(s).toMatchObject({ coins: 24, bag: { seed_carrot: 1 } });
    return s;
  };

  it('ships carrot seeds at 9 coins, the P0 seed price, and nothing else for sale', () => {
    expect(rules.economy.buy_prices).toEqual({ seed_carrot: 9 });
    const p0 = JSON.parse(readFileSync(path.resolve(DEFAULT_CONTENT_DIR, '..', '..', 'p0', 'p0_content.json'), 'utf8'));
    const carrot = p0.crops.find((c: { id: string }) => c.id === 'crop_carrot');
    expect(carrot.seed).toBe('seed_carrot');
    expect(rules.economy.buy_prices[carrot.seed]).toBe(carrot.seed_price);
    // Selling prices are unchanged by C-149.
    expect(rules.economy.sell_prices).toEqual({ crop_carrot: 12, wood: 2, wild_herb: 1, stone: 2 });
  });

  it('refuses out-of-bounds buy prices at load time; an economy without buy_prices sells nothing', () => {
    const eco = rules.economy;
    const bad = (economy: unknown) => () => parseParcelRules(structuredClone({ ...rules, economy }));
    expect(bad({ ...eco, buy_prices: { seed_carrot: 0 } })).toThrow();
    expect(bad({ ...eco, buy_prices: { seed_carrot: 1.5 } })).toThrow();
    expect(bad({ ...eco, buy_prices: { seed_carrot: 100_001 } })).toThrow();
    expect(bad({ ...eco, buy_prices: { 'Seed Carrot': 9 } })).toThrow();
    expect(bad({ ...eco, buy_prices: [9] })).toThrow();
    const { buy_prices: _, ...without } = eco;
    const none = parseParcelRules(structuredClone({ ...rules, economy: without }));
    expect(none.economy.buy_prices).toEqual({});
    const out = applyFarmCommands(none, with24(), [{ type: 'buy', item: 'seed_carrot', count: 1 }], T0 + 60_000);
    expect(out).toMatchObject({ ok: false, code: 'NOT_FOR_SALE' });
  });

  it('a purchase takes 9 coins a seed and adds the seeds to the bag; sales and other fields stay', () => {
    const s = with24();
    const after = run(s, [{ type: 'buy', item: 'seed_carrot', count: 2 }], T0 + 60_000);
    expect(after).toEqual({ ...s, coins: 6, bag: { ...s.bag, seed_carrot: 3 } });
    // The seeds bought can be sown; sown, they are dry soil like any seed and need water (C-151).
    const resown = run(after, [{ type: 'sow', cell: '1,1', crop: 'crop_carrot' }], T0 + 60_000);
    expect(resown.bag.seed_carrot).toBe(2);
    expect(resown.crops['1,1']).toMatchObject({ ripe_at: NEVER, watered_at: null });
    expect(watered(resown, ['1,1'], T0 + 120_000).crops['1,1']).toMatchObject({ ripe_at: T0 + 180_000, watered_at: T0 + 120_000 });
  });

  it('too few coins: refused, the whole batch unchanged; spending exactly all coins is allowed', () => {
    const s = with24();
    const frozen = structuredClone(s);
    const out = applyFarmCommands(rules, s, [{ type: 'buy', item: 'seed_carrot', count: 1 }, { type: 'buy', item: 'seed_carrot', count: 2 }], T0 + 60_000);
    expect(out).toEqual({ ok: false, index: 1, code: 'NOT_ENOUGH_COINS', detail: { coins: 15, need: 18 } });
    expect(s).toEqual(frozen);
    expect(applyFarmCommands(rules, emptyFarm(), [{ type: 'buy', item: 'seed_carrot', count: 1 }], T0))
      .toEqual({ ok: false, index: 0, code: 'NOT_ENOUGH_COINS', detail: { coins: 0, need: 9 } });
    const legacy = { v: 1, house: null, cleared: [], tilled: [], crops: {}, bag: {}, welcomed_at: T0 } as unknown as ParcelFarmState;
    expect(applyFarmCommands(rules, legacy, [{ type: 'buy', item: 'seed_carrot', count: 1 }], T0)).toMatchObject({ ok: false, code: 'NOT_ENOUGH_COINS' });
    const all = run({ ...s, coins: 27 }, [{ type: 'buy', item: 'seed_carrot', count: 3 }], T0 + 60_000);
    expect(all).toMatchObject({ coins: 0, bag: { seed_carrot: 4 } });
  });

  it('only what Jasmine sells can be bought', () => {
    for (const item of ['crop_carrot', 'hoe_starter', 'blueprint_coop', 'toString', '__proto__'])
      expect(applyFarmCommands(rules, with24(), [{ type: 'buy', item, count: 1 }], T0 + 60_000))
        .toEqual({ ok: false, index: 0, code: 'NOT_FOR_SALE', detail: { item } });
  });

  it('a price in the request is dropped at parse time; the count is bounded', () => {
    expect(parseFarmCommands([{ type: 'buy', item: 'seed_carrot', count: 2, price: 0 }])).toEqual([{ type: 'buy', item: 'seed_carrot', count: 2 }]);
    expect(parseFarmCommands([{ type: 'buy', item: 'seed_carrot', count: MAX_BUY_COUNT }])).not.toBeNull();
    for (const count of [0, -1, 1.5, MAX_BUY_COUNT + 1, '2', undefined])
      expect(parseFarmCommands([{ type: 'buy', item: 'seed_carrot', count }])).toBeNull();
    expect(parseFarmCommands([{ type: 'buy', item: 'x'.repeat(65), count: 1 }])).toBeNull();
    expect(parseFarmCommands([{ type: 'buy', count: 1 }])).toBeNull();
  });
});

describe('rebase onto a newer dataset (C-136, Q-168)', () => {
  const R4 = 'sf-dynamic-farm-20261118-r4', R6 = 'sf-dynamic-farm-20261124-r6';

  it('only to a later registered dataset of the same community, never back', () => {
    expect(isNewerDataset(rules, R4, R6)).toBe(true);
    expect(isNewerDataset(rules, R6, R4)).toBe(false);
    expect(isNewerDataset(rules, R6, R6)).toBe(false);
    expect(isNewerDataset(rules, R4, 'sf-dynamic-farm-20261124-r5')).toBe(false); // not registered
    expect(isNewerDataset(rules, 'nope', R6)).toBe(false);
    const R8 = 'sf-dynamic-farm-20261125-r8'; // C-113
    expect(isNewerDataset(rules, R6, R8)).toBe(true);
    expect(isNewerDataset(rules, R4, R8)).toBe(true);
    expect(isNewerDataset(rules, R8, R6)).toBe(false);
    const two = parseParcelRules({ ...rules, communities: [...rules.communities, { id: 'ny', datasets: ['ny-1', 'ny-2'] }] });
    expect(isNewerDataset(two, R4, 'ny-2')).toBe(false); // another community
    expect(isNewerDataset(two, 'ny-1', 'ny-2')).toBe(true);
  });

  it('clears what sits on cells and gives back a seed per crop and the cottage blueprint; keeps bag, coins, sales, blueprints, gift', () => {
    let s = run(welcomed(), [{ type: 'place_house', x: 9, y: 9 }, { type: 'clear_obstacle', cell: '3,3' }, { type: 'till', cell: '1,1' },
      { type: 'till', cell: '2,1' }, { type: 'till', cell: '3,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' }]);
    s = run(watered(s, ['1,1']), [{ type: 'harvest', cell: '1,1' }, { type: 'sell', item: 'crop_carrot', count: 1 }, { type: 'claim_blueprint', blueprint: 'coop' },
      { type: 'sow', cell: '1,1', crop: 'crop_carrot' }, { type: 'sow', cell: '2,1', crop: 'crop_carrot' }], T0 + 60_000);
    s = watered(s, ['2,1'], T0 + 60_000);
    const tree = 'p-3512001:outer-groves-v2:wild_pz_tree_20:41,7:0';
    const out = applyFarmCommands(rules, s, [{ type: 'gather', object: tree }], T0 + 61_000, { parcel_id: 'p-3512001' });
    if (!out.ok) throw new Error(out.code);
    s = out.state;
    // One crop is dry, one watered and growing: both are in the ground and each gives its seed back; the well its blueprint.
    expect(s).toMatchObject({ coins: 12, sales: 1, bag: { hoe_starter: 1, blueprint_coop: 1, wood: 1, pail: 1 }, welcomed_at: T0, pail_water: 2 });
    expect(s.bag.seed_carrot).toBeUndefined();
    const before = structuredClone(s);
    const moved = rebaseFarm(rules, s);
    // The pail and what is left in it are not on cells: they stay, as do the one-off grants already given.
    expect(moved).toEqual({ ...before, buildings: [], house: null, cleared: [], tilled: [], crops: {}, gathered: {},
      bag: { hoe_starter: 1, blueprint_coop: 1, wood: 1, pail: 1, seed_carrot: 2, blueprint_cottage: 1, blueprint_well: 1 } });
    expect(s).toEqual(before); // the input is untouched
    // The cottage goes back up on the new cells with the returned blueprint.
    expect(run(moved, [{ type: 'place_house', x: 2, y: 2 }]).house).toMatchObject({ x: 2, y: 2 });
  });

  it('an empty or never-entered farm stays as it is; a crop no longer in the rules gives nothing back', () => {
    expect(rebaseFarm(rules, emptyFarm())).toEqual(emptyFarm());
    expect(rebaseFarm(rules, welcomed())).toEqual(welcomed());
    const odd = { ...welcomed(), tilled: ['1,1'], crops: { '1,1': { crop: 'crop_gone', planted_at: T0, ripe_at: T0 + 1 } } };
    expect(rebaseFarm(rules, odd).bag).toEqual(welcomed().bag);
    // A C-31 era save without the economy fields comes out with them.
    const legacy = { v: 1, house: null, cleared: ['1,2'], tilled: [], crops: {}, bag: { hoe_starter: 1 }, welcomed_at: T0 } as unknown as ParcelFarmState;
    expect(rebaseFarm(rules, legacy)).toEqual({ ...legacy, buildings: [], cleared: [], coins: 0, sales: 0, gathered: {}, blueprints_claimed: {},
      pail_water: 0, grants: {}, level: 1 });
  });
});

/**
 * C-150（0.4.5）：多栋建筑、按类型配置、四个朝向（所有者 SEN-C-134#22 第 3 题）。发布的规则只有小屋；
 * 这里在规则副本里加两种测试用类型（不是新建筑）：1×1、最多 3 口的 well，4×2、最多 1 栋的 coop。
 */
describe('buildings (C-150)', () => {
  const multi = parseParcelRules({ ...structuredClone(rules), farm_levels: [], buildings: { ...rules.buildings,
    well: { model: 'well', blueprint: 'blueprint_well', width: 1, depth: 1, max: 3 },
    coop: { model: 'coop', blueprint: 'blueprint_coop', width: 4, depth: 2, max: 1 } } });
  const stocked = (): ParcelFarmState => {
    const s = welcomed();
    s.bag = { ...s.bag, blueprint_well: 5, blueprint_coop: 2 };
    return s;
  };
  const place = (building: string, x: number, y: number, rotation = 0): FarmCommand => ({ type: 'place_building', building, x, y, rotation });
  const go = (state: ParcelFarmState, commands: FarmCommand[], now = T0) => {
    const out = applyFarmCommands(multi, state, commands, now);
    if (!out.ok) throw new Error(`${out.code} @${out.index}`);
    return out.state;
  };
  const tryIt = (state: ParcelFarmState, commands: FarmCommand[]) => applyFarmCommands(multi, state, commands, T0);

  it('parses place_building: a type, a cell and a rotation of 0–3 quarter turns (default 0)', () => {
    expect(parseFarmCommands([{ type: 'place_building', building: 'well', x: 3, y: 4 }]))
      .toEqual([{ type: 'place_building', building: 'well', x: 3, y: 4, rotation: 0 }]);
    expect(parseFarmCommands([{ type: 'place_building', building: 'well', x: 3, y: 4, rotation: 3 }])).toMatchObject([{ rotation: 3 }]);
    for (const bad of [{ building: 'well', x: 3, y: 4, rotation: 4 }, { building: 'well', x: 3, y: 4, rotation: 1.5 }, { x: 3, y: 4 },
      { building: 7, x: 3, y: 4 }, { building: 'w'.repeat(65), x: 3, y: 4 }, { building: 'well', x: -1, y: 4 }, { building: 'well', x: 3, y: 1024 }])
      expect(parseFarmCommands([{ type: 'place_building', ...bad }])).toBeNull();
  });

  it('saves several buildings with their own type, spot, rotation and footprint; ids count up; house mirrors the cottage', () => {
    const s = go(stocked(), [place('well', 2, 2), place('cottage', 10, 10, 2), place('coop', 20, 5, 1), place('well', 4, 2, 3)]);
    expect(s.buildings).toEqual([
      { id: 1, type: 'well', model: 'well', x: 2, y: 2, width: 1, depth: 1, rotation: 0, built_at: T0 },
      { id: 2, type: 'cottage', model: 'cottage', x: 10, y: 10, width: 3, depth: 3, rotation: 2, built_at: T0 },
      { id: 3, type: 'coop', model: 'coop', x: 20, y: 5, width: 4, depth: 2, rotation: 1, built_at: T0 },
      { id: 4, type: 'well', model: 'well', x: 4, y: 2, width: 1, depth: 1, rotation: 3, built_at: T0 },
    ]);
    expect(s.house).toEqual({ model: 'cottage', x: 10, y: 10, width: 3, depth: 3, rotation: 2, built_at: T0 });
    expect(s.bag).toMatchObject({ blueprint_well: 3, blueprint_coop: 1 });
    expect(s.bag.blueprint_cottage).toBeUndefined();
    // A server round trip (JSON) keeps them all.
    expect(withEconomy(JSON.parse(JSON.stringify(s)))).toEqual(s);
  });

  it('refuses a building on another one, naming the shared cells; the rotated footprint counts', () => {
    const s = go(stocked(), [place('cottage', 10, 10)]); // cells 10–12 × 10–12
    expect(tryIt(s, [place('well', 12, 12)])).toEqual({ ok: false, index: 0, code: 'BUILDING_OVERLAP', detail: { cells: ['12,12'] } });
    // The coop unturned is 4 wide, 2 deep: at 6,9 it covers x 6–9, y 9–10 and stops short of the cottage.
    const beside = go(s, [place('coop', 6, 9)]);
    expect(beside.buildings).toHaveLength(2);
    // Turned a quarter it is 2 wide, 4 deep: at 9,7 it covers x 9–10, y 7–10 and reaches into the cottage's corner.
    expect(tryIt(s, [place('coop', 9, 7, 1)])).toEqual({ ok: false, index: 0, code: 'BUILDING_OVERLAP', detail: { cells: ['10,10'] } });
    expect(tryIt(s, [place('coop', 9, 7, 3)])).toMatchObject({ ok: false, code: 'BUILDING_OVERLAP' });
    // Unturned (or turned half) the same spot covers x 9–12, y 7–8, clear of it.
    expect(go(s, [place('coop', 9, 7, 0)]).buildings).toHaveLength(2);
    expect(go(s, [place('coop', 9, 7, 2)]).buildings).toHaveLength(2);
    // Two buildings in one batch may not overlap each other either; the refused batch changes nothing.
    const before = structuredClone(s);
    expect(tryIt(s, [place('well', 1, 1), place('well', 1, 1)])).toMatchObject({ ok: false, index: 1, code: 'BUILDING_OVERLAP', detail: { cells: ['1,1'] } });
    expect(s).toEqual(before);
  });

  it('refuses a building on tilled ground or crops, the rotated footprint as well; tilling and gathering stay off every building', () => {
    const s = go(stocked(), [{ type: 'till', cell: '5,8' }, { type: 'till', cell: '7,4' }, { type: 'sow', cell: '7,4', crop: 'crop_carrot' }]);
    // Turned, the coop at 5,5 covers x 5–6, y 5–8: the tilled cell 5,8 is under it.
    expect(tryIt(s, [place('coop', 5, 5, 1)])).toEqual({ ok: false, index: 0, code: 'CELL_OCCUPIED', detail: { cells: ['5,8'] } });
    // Unturned it covers x 5–8, y 5–6: clear.
    expect(go(s, [place('coop', 5, 5)]).buildings).toHaveLength(1);
    // Unturned at 4,3 it covers x 4–7, y 3–4: the sown cell 7,4 (tilled too) is under it.
    expect(tryIt(s, [place('coop', 4, 3)])).toEqual({ ok: false, index: 0, code: 'CELL_OCCUPIED', detail: { cells: ['7,4'] } });
    const built = go(s, [place('coop', 5, 5), place('well', 12, 12)]);
    for (const cell of ['8,6', '12,12'])
      expect(tryIt(built, [{ type: 'till', cell }])).toEqual({ ok: false, index: 0, code: 'CELL_OCCUPIED', detail: { cells: [cell] } });
    const tree = 'p-3512001:outer-groves-v2:wild_pz_tree_20:12,12:0';
    expect(applyFarmCommands(multi, built, [{ type: 'gather', object: tree }], T0, { parcel_id: 'p-3512001' })).toMatchObject({ ok: false, code: 'NOT_OUTER' });
  });

  it('checks the type, its limit, the blueprint and the bounds', () => {
    const s = stocked();
    expect(tryIt(s, [place('barn', 1, 1)])).toEqual({ ok: false, index: 0, code: 'UNKNOWN_BUILDING', detail: { building: 'barn' } });
    expect(tryIt(s, [place('constructor', 1, 1)])).toMatchObject({ code: 'UNKNOWN_BUILDING' }); // not an inherited key
    const wells = go(s, [place('well', 1, 1), place('well', 3, 1), place('well', 5, 1)]);
    expect(tryIt(wells, [place('well', 7, 1)])).toEqual({ ok: false, index: 0, code: 'BUILDING_LIMIT', detail: { building: 'well', max: 3 } });
    expect(tryIt({ ...s, bag: { blueprint_well: 1 } }, [place('coop', 1, 1)])).toEqual({ ok: false, index: 0, code: 'NO_BLUEPRINT', detail: { item: 'blueprint_coop' } });
    // A 4×2 coop at x 1020 reaches x 1023, the last cell; at 1021 it would leave the grid; turned it is only 2 wide.
    expect(go(s, [place('coop', 1020, 0)]).buildings).toHaveLength(1);
    expect(tryIt(s, [place('coop', 1021, 0)])).toMatchObject({ code: 'OUT_OF_BOUNDS' });
    expect(go(s, [place('coop', 1021, 0, 1)]).buildings).toHaveLength(1);
    expect(tryIt(s, [place('coop', 0, 1021, 1)])).toMatchObject({ code: 'OUT_OF_BOUNDS' });
  });

  it('place_house (0.4.4 and older clients) is the cottage: one only, HOUSE_PLACED for a second either way', () => {
    const viaOld = go(stocked(), [{ type: 'place_house', x: 9, y: 9, rotation: 1 }]);
    expect(viaOld.buildings).toEqual([{ id: 1, type: 'cottage', model: 'cottage', x: 9, y: 9, width: 3, depth: 3, rotation: 1, built_at: T0 }]);
    expect(tryIt({ ...viaOld, bag: { ...viaOld.bag, blueprint_cottage: 1 } }, [place('cottage', 20, 20)]))
      .toEqual({ ok: false, index: 0, code: 'BUILDING_LIMIT', detail: { building: 'cottage', max: 1 } });
    const viaNew = go(stocked(), [place('well', 1, 1), place('cottage', 9, 9)]);
    expect(tryIt({ ...viaNew, bag: { ...viaNew.bag, blueprint_cottage: 1 } }, [{ type: 'place_house', x: 20, y: 20 }])).toMatchObject({ code: 'HOUSE_PLACED' });
    // An old client's house lands beside the new buildings under the same overlap rule.
    expect(tryIt(go(stocked(), [place('well', 10, 10)]), [{ type: 'place_house', x: 9, y: 9 }])).toMatchObject({ code: 'BUILDING_OVERLAP', detail: { cells: ['10,10'] } });
  });

  it('an old save with one house reads it as cottage 1 where it stood and facing as it did, still solid to tilling and new buildings', () => {
    for (const rotation of [0, 1, 2, 3]) {
      const house = { model: 'cottage', x: 6, y: 6, width: 3, depth: 3, rotation, built_at: T0 - 5 };
      const legacy = { v: 1, house, cleared: [], tilled: ['1,1'], crops: {}, bag: { hoe_starter: 1, blueprint_well: 1 }, welcomed_at: T0 } as unknown as ParcelFarmState;
      const frozen = structuredClone(legacy);
      const read = withEconomy(legacy);
      expect(read.buildings).toEqual([{ id: 1, type: 'cottage', ...house }]);
      expect(read.house).toEqual(house);
      expect(legacy).toEqual(frozen);
      expect(tryIt(legacy, [{ type: 'till', cell: '8,8' }])).toMatchObject({ code: 'CELL_OCCUPIED' });
      expect(tryIt(legacy, [place('well', 7, 7)])).toMatchObject({ code: 'BUILDING_OVERLAP', detail: { cells: ['7,7'] } });
      const more = go(legacy, [place('well', 9, 6)]);
      expect(more.buildings.map(b => [b.id, b.type])).toEqual([[1, 'cottage'], [2, 'well']]);
      expect(more.house).toEqual(house);
      expect(tryIt(legacy, [{ type: 'place_house', x: 20, y: 20 }])).toMatchObject({ code: 'HOUSE_PLACED' });
    }
  });

  it('a rebase gives back one blueprint per building of a known type', () => {
    const s = go(stocked(), [place('cottage', 9, 9), place('well', 1, 1), place('well', 3, 1), place('coop', 20, 20, 1)]);
    const moved = rebaseFarm(multi, { ...s, buildings: [...s.buildings, { ...s.buildings[1], id: 9, type: 'gone' }] });
    expect(moved.buildings).toEqual([]);
    expect(moved.house).toBeNull();
    expect(moved.bag).toMatchObject({ blueprint_cottage: 1, blueprint_well: 5, blueprint_coop: 2 });
  });
});

/**
 * C-151（0.4.5）：井和水桶浇水，没浇水的作物不长（所有者 SEN-C-137#6、#15）。打一桶水 2 体力，一桶 3 次，每浇一格用一次；
 * 服务端核实桶里的次数、格子播下了还没浇、体力；“人在井边”由客户端限定。
 */
describe('watering (C-151)', () => {
  const ME = { parcel_id: 'p-3512001' };
  const MIN = 60_000, DAY = 86_400_000;
  /** 领了补发、盖好小屋和井、开垦并播下 cells 的农场（都还没浇）。 */
  const sown = (cells: string[]): ParcelFarmState => {
    const s = grant(rules, welcomed(), T0)!.state;
    s.bag.seed_carrot = cells.length;
    return run(s, [{ type: 'place_house', x: 10, y: 10 }, { type: 'place_building', building: 'well', ...WELL_AT, rotation: 0 },
      ...cells.map(cell => ({ type: 'till', cell }) as FarmCommand), ...cells.map(cell => ({ type: 'sow', cell, crop: 'crop_carrot' }) as FarmCommand)]);
  };
  const wellOf = (s: ParcelFarmState) => s.buildings.find(b => b.type === 'well')!.id;
  const draw = (s: ParcelFarmState): FarmCommand => ({ type: 'draw_water', building: wellOf(s) });
  const water = (cell: string): FarmCommand => ({ type: 'water', cell });
  const tryAt = (s: ParcelFarmState, commands: FarmCommand[], now = T0) => applyFarmCommands(rules, s, commands, now, ME);

  it('parses draw_water (a building id) and water (a cell)', () => {
    expect(parseFarmCommands([{ type: 'draw_water', building: 2 }, { type: 'water', cell: '3,4' }]))
      .toEqual([{ type: 'draw_water', building: 2 }, { type: 'water', cell: '3,4' }]);
    for (const building of [0, -1, 1.5, '2', undefined, 2 ** 30 + 1]) expect(parseFarmCommands([{ type: 'draw_water', building }])).toBeNull();
    for (const cell of ['03,4', '1024,0', 7, undefined]) expect(parseFarmCommands([{ type: 'water', cell }])).toBeNull();
  });

  it('without water a sown crop does not count time; watered, it grows from that moment', () => {
    const s = sown(['1,1']);
    expect(s.crops['1,1']).toEqual({ crop: 'crop_carrot', planted_at: T0, ripe_at: NEVER, watered_at: null });
    // A day later it is still not growing: harvest is refused and nothing changes.
    expect(tryAt(s, [{ type: 'harvest', cell: '1,1' }], T0 + DAY)).toEqual({ ok: false, index: 0, code: 'NOT_WATERED' });
    const later = T0 + DAY;
    const wet = run(s, [draw(s), water('1,1')], later);
    expect(wet.crops['1,1']).toEqual({ crop: 'crop_carrot', planted_at: T0, ripe_at: later + MIN, watered_at: later });
    expect(tryAt(wet, [{ type: 'harvest', cell: '1,1' }], later + MIN - 1)).toMatchObject({ ok: false, code: 'NOT_RIPE', detail: { ripe_at: later + MIN } });
    expect(run(wet, [{ type: 'harvest', cell: '1,1' }], later + MIN).bag.crop_carrot).toBe(1);
  });

  it('drawing a pail costs 2 Energy and fills it to 3; watering costs none and uses one', () => {
    const s = sown(['1,1', '2,1', '3,1', '4,1']);
    const before = s.energy!.value;
    const filled = run(s, [draw(s)]);
    expect(filled.pail_water).toBe(3);
    expect(filled.energy!.value).toBe(before - 2);
    const one = run(filled, [water('1,1')]);
    expect(one.pail_water).toBe(2);
    expect(one.energy!.value).toBe(before - 2);
    // Short of 2 Energy the well gives nothing: NO_ENERGY, the pail stays as it was.
    const tired = { ...structuredClone(s), energy: { value: 1, at: T0, rested_on: null } };
    expect(tryAt(tired, [draw(tired)])).toMatchObject({ ok: false, index: 0, code: 'NO_ENERGY', detail: { need: 2, have: 1 } });
    // Watering needs no Energy at all.
    expect(run({ ...structuredClone(filled), energy: { value: 0, at: T0, rested_on: null } }, [water('1,1')]).pail_water).toBe(2);
  });

  it('an empty pail cannot water: after 3 cells it has to go back to the well', () => {
    const s = sown(['1,1', '2,1', '3,1', '4,1']);
    expect(tryAt(s, [water('1,1')])).toEqual({ ok: false, index: 0, code: 'PAIL_EMPTY' });
    const three = run(s, [draw(s), water('1,1'), water('2,1'), water('3,1')]);
    expect(three.pail_water).toBe(0);
    expect(tryAt(three, [water('4,1')])).toEqual({ ok: false, index: 0, code: 'PAIL_EMPTY' });
    // A fourth in the same batch is refused whole: none of the three lands.
    expect(tryAt(s, [draw(s), water('1,1'), water('2,1'), water('3,1'), water('4,1')])).toMatchObject({ ok: false, index: 4, code: 'PAIL_EMPTY' });
    expect(run(three, [draw(three), water('4,1')]).pail_water).toBe(2);
  });

  it('the same cell cannot be watered twice, nor a cell with nothing sown', () => {
    const s = run(sown(['1,1']), [{ type: 'till', cell: '5,5' }]);
    const once = run(s, [draw(s), water('1,1')]);
    expect(tryAt(once, [water('1,1')])).toEqual({ ok: false, index: 0, code: 'ALREADY_WATERED' });
    expect(tryAt(s, [draw(s), water('1,1'), water('1,1')])).toMatchObject({ ok: false, index: 2, code: 'ALREADY_WATERED' });
    // Tilled but not sown, or not even tilled: nothing to water.
    expect(tryAt(once, [water('5,5')])).toEqual({ ok: false, index: 0, code: 'NO_CROP' });
    expect(tryAt(once, [water('9,9')])).toEqual({ ok: false, index: 0, code: 'NO_CROP' });
    // Ripe and harvested, the cell is dry soil again: sown again, it needs water again.
    const harvested = run(once, [{ type: 'harvest', cell: '1,1' }], T0 + MIN);
    const regrown = run({ ...harvested, bag: { ...harvested.bag, seed_carrot: 1 } }, [{ type: 'sow', cell: '1,1', crop: 'crop_carrot' }], T0 + MIN);
    expect(regrown.crops['1,1']).toMatchObject({ watered_at: null, ripe_at: NEVER });
  });

  it('the well: a built well of the watering type, with the pail in the bag; a full pail is not drawn again', () => {
    const s = sown(['1,1']);
    const home = s.buildings.find(b => b.type === 'cottage')!.id;
    expect(tryAt(s, [{ type: 'draw_water', building: home }])).toEqual({ ok: false, index: 0, code: 'NO_WELL', detail: { building: home } });
    expect(tryAt(s, [{ type: 'draw_water', building: 99 }])).toEqual({ ok: false, index: 0, code: 'NO_WELL', detail: { building: 99 } });
    const full = run(s, [draw(s)]);
    expect(tryAt(full, [draw(full)])).toEqual({ ok: false, index: 0, code: 'PAIL_FULL', detail: { water: 3 } });
    const { pail: _pail, ...rest } = full.bag;
    const noPail = { ...structuredClone(full), bag: rest };
    expect(tryAt(noPail, [water('1,1')])).toEqual({ ok: false, index: 0, code: 'NO_PAIL', detail: { item: 'pail' } });
    expect(tryAt({ ...noPail, pail_water: 0 }, [draw(noPail)])).toEqual({ ok: false, index: 0, code: 'NO_PAIL', detail: { item: 'pail' } });
    // One well at level 1: a second is BUILDING_LIMIT.
    expect(tryAt({ ...structuredClone(s), bag: { ...s.bag, blueprint_well: 1 } }, [{ type: 'place_building', building: 'well', x: 40, y: 40, rotation: 0 }]))
      .toEqual({ ok: false, index: 0, code: 'BUILDING_LIMIT', detail: { building: 'well', max: 1 } });
  });

  it('a crop sown before watering existed (no watered_at) counts as watered and ripens at its own time', () => {
    const legacy = { v: 1, house: null, cleared: [], tilled: ['1,1', '2,1'], bag: { hoe_starter: 1 }, welcomed_at: T0 - DAY,
      crops: { '1,1': { crop: 'crop_carrot', planted_at: T0 - DAY, ripe_at: T0 - DAY + MIN }, '2,1': { crop: 'crop_carrot', planted_at: T0, ripe_at: T0 + MIN } } } as unknown as ParcelFarmState;
    expect(tryAt(legacy, [{ type: 'harvest', cell: '2,1' }], T0 + MIN - 1)).toMatchObject({ code: 'NOT_RIPE', detail: { ripe_at: T0 + MIN } });
    const out = run(legacy, [{ type: 'harvest', cell: '1,1' }, { type: 'harvest', cell: '2,1' }], T0 + MIN);
    expect(out.bag.crop_carrot).toBe(2);
    // It cannot be watered again either.
    const pailed = { ...grant(rules, legacy, T0)!.state, pail_water: 3 };
    expect(tryAt(pailed, [water('2,1')])).toEqual({ ok: false, index: 0, code: 'ALREADY_WATERED' });
  });

  it('a dry crop is stored as a whole number that JSON and older clients read (never ripe), not null', () => {
    expect(Number.isSafeInteger(NEVER)).toBe(true);
    expect(new Date(NEVER).getTime()).toBe(NEVER);
    const s = sown(['1,1']);
    expect(JSON.parse(JSON.stringify(s)).crops['1,1']).toEqual({ crop: 'crop_carrot', planted_at: T0, ripe_at: NEVER, watered_at: null });
  });

  it('the one-off grant: the well blueprint and the pail, once per farm, the first entry or the next one for older farms', () => {
    // A new player: entering grants it with the first-entry gift.
    const first = grant(rules, welcomed(), T0)!;
    expect(first.gift).toEqual({ blueprint_well: 1, pail: 1 });
    expect(first.state.bag).toEqual({ hoe_starter: 1, seed_carrot: 3, blueprint_cottage: 1, blueprint_well: 1, pail: 1 });
    expect(first.state.grants).toEqual({ watering: T0 });
    expect(grant(rules, first.state, T0 + 1)).toBeNull();
    // Used up (the well built, the pail kept), entering again still gives nothing more.
    expect(grant(rules, watered(first.state, []), T0 + 2)).toBeNull();
    // An older farm (from before watering, no grants field) gets it once on its next entry; the rest of the save stays.
    const old = { v: 1, house: null, cleared: ['2,2'], tilled: ['1,1'], crops: {}, bag: { hoe_starter: 1, crop_carrot: 4 }, welcomed_at: T0 - DAY } as unknown as ParcelFarmState;
    const frozen = structuredClone(old);
    const topped = grant(rules, old, T0)!;
    expect(topped.state).toEqual({ ...withEconomy(old), bag: { hoe_starter: 1, crop_carrot: 4, blueprint_well: 1, pail: 1 }, grants: { watering: T0 } });
    expect(old).toEqual(frozen);
    expect(grant(rules, topped.state, T0 + DAY)).toBeNull();
    // Moving to a newer dataset keeps the record: nothing is granted twice.
    expect(grant(rules, rebaseFarm(rules, topped.state), T0 + DAY)).toBeNull();
  });

  /**
   * 客户端和服务端同一套浇水规则：tests/dynamic_farm/fixtures/watering_cases.json 的每个用例在这里按服务端跑，
   * 在 tests/dynamic_farm/test_parcel_farming.gd 里按客户端 parcel_farm.gd 跑，两边结果都要等于文件里记的结果。
   */
  describe('the client runs the same watering cases (shared fixture)', () => {
    const shared = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, '..', '..', '..', 'tests', 'dynamic_farm', 'fixtures', 'watering_cases.json'), 'utf8'));
    for (const c of shared.cases) {
      it(c.name, () => {
        const r = applyFarmCommands(rules, structuredClone(c.farm), c.commands, c.now, { parcel_id: shared.parcel_id });
        expect(r.ok ? { ok: true, crops: r.state.crops, pail_water: r.state.pail_water, bag: r.state.bag, energy: r.state.energy }
          : { ok: false, index: r.index, code: r.code, detail: r.detail ?? {} }).toEqual(c.expect);
      });
    }
  });

  it('refuses malformed watering rules or grants at load time', () => {
    const bad = (patch: object) => () => parseParcelRules({ ...structuredClone(rules), ...patch });
    expect(bad({ watering: undefined })).toThrow();
    expect(bad({ watering: { ...rules.watering, well: 'castle' } })).toThrow();   // not a building type
    expect(bad({ watering: { ...rules.watering, pail_uses: 0 } })).toThrow();
    expect(bad({ watering: { ...rules.watering, pail: 'Pail!' } })).toThrow();
    expect(bad({ grants: undefined })).toThrow();
    expect(bad({ grants: { watering: {} } })).toThrow();
    expect(bad({ grants: { watering: { pail: 0 } } })).toThrow();
    expect(bad({ energy: { ...rules.energy, costs: { ...rules.energy.costs, water: 1 } } })).toThrow();   // watering stays free
  });
});

/**
 * C-152（0.4.5）：农场等级，照 P0 家园等级。在 Scott 处升级，花金币、木材、石头（数值是作者的默认值，SEN-C-152#14 列给所有者确认）；
 * 每级体力上限 +10；井 1 级 1 口、3 级 2 口、5 级 3 口（3 级、5 级各送一张井的蓝图）；开垦格数不设上限（所有者 SEN-C-137#10）。
 */
describe('farm levels (C-152)', () => {
  const UP: FarmCommand = { type: 'upgrade_farm' };
  /** level 级、背包里另有 bag、金币 coins 的农场（首次进入后）。 */
  const at = (level: number, bag: Record<string, number> = {}, coins = 0): ParcelFarmState => {
    const s = welcomed();
    return { ...s, level, coins, bag: { ...s.bag, ...bag } };
  };
  const enough = (level: number) => {
    const next = nextFarmLevel(rules, level)!;
    return at(level, next.items, next.coins);
  };
  const wellAt = (x: number): FarmCommand => ({ type: 'place_building', building: 'well', x, y: 30, rotation: 0 });

  it('ships Lv1 to Lv5: coins as P0 Homestead Lv2–5, Timber and Stone rising; wells 1 / 2 / 3 at Lv1 / 3 / 5; Max Energy 200 + 10 a level', () => {
    expect(rules.farm_levels).toEqual([
      { level: 2, coins: 40, items: { wood: 6, stone: 4 } },
      { level: 3, coins: 60, items: { wood: 10, stone: 8 }, buildings: { well: 2 }, gift: { blueprint_well: 1 } },
      { level: 4, coins: 70, items: { wood: 14, stone: 12 } },
      { level: 5, coins: 80, items: { wood: 20, stone: 16 }, buildings: { well: 3 }, gift: { blueprint_well: 1 } },
    ]);
    expect([1, 2, 3, 4, 5].map(l => maxEnergy(rules, at(l)))).toEqual([200, 210, 220, 230, 240]);
    expect([1, 2, 3, 4, 5].map(l => buildingMax(rules, 'well', l))).toEqual([1, 1, 2, 2, 3]);
    expect([1, 3, 5].map(l => buildingMax(rules, 'cottage', l))).toEqual([1, 1, 1]);
    expect(nextFarmLevel(rules, 5)).toBeNull();
  });

  it('an old save has no level and reads as Lv1; a new farm starts at Lv1; moving datasets keeps the level', () => {
    expect(emptyFarm().level).toBe(1);
    const legacy = { ...welcomed() } as Partial<ParcelFarmState>;
    delete legacy.level;
    expect(withEconomy(legacy as ParcelFarmState).level).toBe(1);
    expect(maxEnergy(rules, legacy as ParcelFarmState)).toBe(200);
    expect(withEconomy({ ...welcomed(), level: 0 }).level).toBe(1);   // malformed: Lv1
    expect(rebaseFarm(rules, at(4)).level).toBe(4);
  });

  it('upgrading takes the next level\'s coins, Timber and Stone, costs no Energy and raises Max Energy by 10', () => {
    const out = applyFarmCommands(rules, enough(1), [UP], T0);
    expect(out.ok).toBe(true);
    if (!out.ok) return;
    expect(out.state).toMatchObject({ level: 2, coins: 0, energy: { value: 200, at: T0 } });
    expect(out.state.bag).toEqual(welcomed().bag);
    expect(maxEnergy(rules, out.state)).toBe(210);
    // Below the new top, the 10 come back at the usual pace from the upgrade on (the newcomer's 2:40 here).
    const later = run(out.state, [{ type: 'clear_obstacle', cell: '9,9' }], T0 + 10 * 160_000);
    expect(later.energy).toEqual({ value: 208, at: T0 + 10 * 160_000, rested_on: null });
    // Lv3 and Lv5 put one more well blueprint in the bag; leftover coins and materials stay.
    const three = run({ ...enough(2), coins: 65, bag: { ...enough(2).bag, wood: 11 } }, [UP]);
    expect(three).toMatchObject({ level: 3, coins: 5, bag: { wood: 1, blueprint_well: 1 } });
    expect(run(enough(4), [UP]).bag.blueprint_well).toBe(1);
  });

  it('short of Timber, Stone or coins is refused whole and the save is untouched; materials are named before coins; Lv5 is the top', () => {
    const next = nextFarmLevel(rules, 1)!;
    const refuse = (s: ParcelFarmState, commands: FarmCommand[] = [UP]) => {
      const frozen = structuredClone(s);
      const out = applyFarmCommands(rules, s, commands, T0);
      expect(s).toEqual(frozen);
      return out;
    };
    expect(refuse(at(1))).toEqual({ ok: false, index: 0, code: 'NOT_ENOUGH', detail: { item: 'wood', have: 0, need: 6 } });
    expect(refuse(at(1, { wood: 6, stone: 3 }, 40))).toEqual({ ok: false, index: 0, code: 'NOT_ENOUGH', detail: { item: 'stone', have: 3, need: 4 } });
    expect(refuse(at(1, next.items, 39))).toEqual({ ok: false, index: 0, code: 'NOT_ENOUGH_COINS', detail: { coins: 39, need: 40 } });
    expect(refuse(at(1, { wood: 5, stone: 4 }, 0))).toEqual({ ok: false, index: 0, code: 'NOT_ENOUGH', detail: { item: 'wood', have: 5, need: 6 } });
    // Two upgrades in one batch pay for both; with only Lv2's price the second is refused and the first is undone.
    expect(refuse(enough(1), [UP, UP])).toEqual({ ok: false, index: 1, code: 'NOT_ENOUGH', detail: { item: 'wood', have: 0, need: 10 } });
    expect(refuse(at(5, { wood: 99, stone: 99 }, 999))).toEqual({ ok: false, index: 0, code: 'MAX_LEVEL', detail: { level: 5 } });
  });

  it('wells: one at Lv1 and Lv2, a second from Lv3, a third from Lv5; the refusal names the level\'s limit', () => {
    const bp = { blueprint_well: 3 };
    expect(applyFarmCommands(rules, at(2, bp), [wellAt(30), wellAt(32)], T0)).toEqual({ ok: false, index: 1, code: 'BUILDING_LIMIT', detail: { building: 'well', max: 1 } });
    const three = run(at(3, bp), [wellAt(30), wellAt(32)]);
    expect(three.buildings.filter(b => b.type === 'well')).toHaveLength(2);
    expect(applyFarmCommands(rules, three, [wellAt(34)], T0)).toEqual({ ok: false, index: 0, code: 'BUILDING_LIMIT', detail: { building: 'well', max: 2 } });
    expect(run(at(5, bp), [wellAt(30), wellAt(32), wellAt(34)]).buildings.filter(b => b.type === 'well')).toHaveLength(3);
    // Upgrading to Lv3 at Scott's, then building the second well with the blueprint it gave, in one batch.
    const lv2 = enough(2);
    const one = run({ ...lv2, bag: { ...lv2.bag, blueprint_well: 1 } }, [wellAt(30)]);
    expect(one.bag.blueprint_well).toBeUndefined();
    expect(run(one, [UP, wellAt(32)]).buildings.filter(b => b.type === 'well')).toHaveLength(2);
    // The cottage stays one at every level.
    expect(applyFarmCommands(rules, at(5, { blueprint_cottage: 2 }), [{ type: 'place_house', x: 1, y: 20 }, { type: 'place_house', x: 6, y: 20 }], T0))
      .toMatchObject({ ok: false, index: 1, code: 'HOUSE_PLACED' });
  });

  it('parses upgrade_farm without fields; refuses malformed farm levels at load time', () => {
    expect(parseFarmCommands([{ type: 'upgrade_farm', level: 9, coins: 0 }])).toEqual([{ type: 'upgrade_farm' }]);
    const bad = (farm_levels: unknown) => () => parseParcelRules({ ...structuredClone(rules), farm_levels });
    const lv2 = rules.farm_levels[0];
    expect(parseParcelRules({ ...structuredClone(rules), farm_levels: undefined }).farm_levels).toEqual([]);   // only Lv1
    expect(bad({})).toThrow();
    expect(bad([{ ...lv2, level: 3 }])).toThrow();                                   // not from Lv2
    expect(bad([lv2, lv2])).toThrow();                                               // not one level each
    expect(bad([{ ...lv2, coins: -1 }])).toThrow();
    expect(bad([{ ...lv2, items: { wood: 0 } }])).toThrow();
    expect(bad([{ ...lv2, items: undefined }])).toThrow();
    expect(bad([{ ...lv2, gift: { 'Well!': 1 } }])).toThrow();
    expect(bad([{ ...lv2, buildings: { castle: 2 } }])).toThrow();                   // not a building type
    expect(bad([{ ...lv2, buildings: { well: 0 } }])).toThrow();                     // below the base limit
    expect(bad([{ ...lv2, buildings: { well: 3 } }, { ...rules.farm_levels[1], buildings: { well: 2 } }])).toThrow();   // goes down
  });

  /**
   * 客户端和服务端同一套等级规则：tests/dynamic_farm/fixtures/level_cases.json 的每个用例在这里按服务端跑，
   * 在 tests/dynamic_farm/test_parcel_farming.gd 里按客户端 parcel_farm.gd 跑，两边结果都要等于文件里记的结果。
   */
  describe('the client runs the same level cases (shared fixture)', () => {
    const shared = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, '..', '..', '..', 'tests', 'dynamic_farm', 'fixtures', 'level_cases.json'), 'utf8'));
    for (const c of shared.cases) {
      it(c.name, () => {
        const r = applyFarmCommands(rules, structuredClone(c.farm), c.commands, c.now, { parcel_id: shared.parcel_id });
        expect(r.ok ? { ok: true, level: r.state.level, coins: r.state.coins, bag: r.state.bag, buildings: r.state.buildings.map(b => b.type),
          energy: r.state.energy } : { ok: false, index: r.index, code: r.code, detail: r.detail ?? {} }).toEqual(c.expect);
      });
    }
  });
});
