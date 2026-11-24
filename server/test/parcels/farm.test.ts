/** 动态农场地块内命令（C-31）：首次进入的赠品、格子一致性、背包、按服务端时间成熟。 */
import { describe, expect, it } from 'vitest';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { applyFarmCommands, emptyFarm, MAX_BATCH, parseCell, parseFarmCommands, welcome, type FarmCommand, type ParcelFarmState } from '../../src/parcels/farm.js';
import { communityOf, loadParcelRules, parseParcelRules } from '../../src/parcels/rules.js';

const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const T0 = Date.UTC(2026, 10, 23, 4);
/** 首次进入后的农场。 */
const welcomed = (): ParcelFarmState => welcome(rules, emptyFarm(), T0)!;

function run(state: ParcelFarmState, commands: FarmCommand[], now = T0): ParcelFarmState {
  const out = applyFarmCommands(rules, state, commands, now);
  if (!out.ok) throw new Error(`${out.code} @${out.index}`);
  return out.state;
}

describe('dynamic_farm.json', () => {
  it('ships the owner-approved numbers: Q-39 (C-34#14) and Q-40 (C-33#14)', () => {
    // Q-39: 1 hoe and 3 carrot seeds on first entry, carrots ripe 60 s after sowing by server time.
    // Q-40: 1 first-house blueprint on first entry; the approved 3×3 cottage (C-30#12) is built as soon as it is placed.
    expect(rules.welcome_gift).toEqual({ hoe_starter: 1, seed_carrot: 3, blueprint_cottage: 1 });
    expect(rules.house).toEqual({ model: 'cottage', blueprint: 'blueprint_cottage', width: 3, depth: 3 });
    expect(rules.crops).toEqual({ crop_carrot: { seed: 'seed_carrot', grow_seconds: 60, yield: 1 } });
    expect(rules.till_tool).toBe('hoe_starter');
    expect(communityOf(rules, 'sf-dynamic-farm-20261118-r4')).toBe('sf');
    expect(communityOf(rules, 'sf-dynamic-farm-20261124-r6')).toBe('sf'); // C-43: r6, r5 without its broken building rings (V-167)
    expect(communityOf(rules, 'sf-dynamic-farm-20261124-r5')).toBeNull(); // never shipped
    expect(communityOf(rules, 'nope')).toBeNull();
  });

  it('refuses malformed rules at load time', () => {
    expect(() => parseParcelRules({ ...rules, version: 2 })).toThrow();
    expect(() => parseParcelRules({ ...rules, crops: { crop_carrot: { seed: 'seed_carrot', grow_seconds: 0, yield: 1 } } })).toThrow();
    expect(() => parseParcelRules({ ...rules, communities: [{ id: 'a', datasets: ['d'] }, { id: 'b', datasets: ['d'] }] })).toThrow();
    expect(() => parseParcelRules({ ...rules, house: { model: 'cottage', width: 3, depth: 3 } })).toThrow();
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
    expect(parseFarmCommands([{ type: 'water', cell: '1,2' }])).toBeNull();
    expect(parseFarmCommands([{ type: 'place_house', x: 1, y: 2, rotation: 4 }])).toBeNull();
    expect(parseFarmCommands(Array.from({ length: MAX_BATCH + 1 }, () => ({ type: 'till', cell: '1,2' })))).toBeNull();
  });

  it('runs the first loop: house built at once, clear, till, sow, harvest after 60 s of server time', () => {
    let s = welcomed();
    s = run(s, [{ type: 'place_house', x: 10, y: 10 }, { type: 'clear_obstacle', cell: '3,3' }, { type: 'till', cell: '3,3' },
      { type: 'sow', cell: '3,3', crop: 'crop_carrot' }]);
    expect(s.house).toEqual({ model: 'cottage', x: 10, y: 10, width: 3, depth: 3, rotation: 0, built_at: T0 });
    expect(s.cleared).toEqual(['3,3']);
    expect(s.crops['3,3']).toEqual({ crop: 'crop_carrot', planted_at: T0, ripe_at: T0 + 60_000 });
    // Clearing and tilling cost nothing; the blueprint and one seed are used.
    expect(s.bag).toEqual({ hoe_starter: 1, seed_carrot: 2 });

    const early = applyFarmCommands(rules, s, [{ type: 'harvest', cell: '3,3' }], T0 + 59_999);
    expect(early).toEqual({ ok: false, index: 0, code: 'NOT_RIPE', detail: { ripe_at: T0 + 60_000 } });
    s = run(s, [{ type: 'harvest', cell: '3,3' }], T0 + 60_000);
    expect(s.crops).toEqual({});
    expect(s.tilled).toEqual(['3,3']);
    expect(s.bag).toEqual({ hoe_starter: 1, seed_carrot: 2, crop_carrot: 1 });
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
