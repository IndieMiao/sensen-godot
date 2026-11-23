/** 动态农场地块内命令（C-31）：格子一致性、背包、按服务端时间成熟。 */
import { describe, expect, it } from 'vitest';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { applyFarmCommands, MAX_BATCH, parseCell, parseFarmCommands, starterFarm, type FarmCommand, type ParcelFarmState } from '../../src/parcels/farm.js';
import { communityOf, loadParcelRules, parseParcelRules } from '../../src/parcels/rules.js';

const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const T0 = Date.UTC(2026, 10, 23, 4);

function run(state: ParcelFarmState, commands: FarmCommand[], now = T0): ParcelFarmState {
  const out = applyFarmCommands(rules, state, commands, now);
  if (!out.ok) throw new Error(`${out.code} @${out.index}`);
  return out.state;
}

describe('dynamic_farm.json', () => {
  it('ships the PM defaults: starter hoe and carrot seeds, a 3×3 cottage, carrots ripe in 60 s', () => {
    expect(rules.starter_bag).toEqual({ hoe_starter: 1, seed_carrot: 5 });
    expect(rules.house).toEqual({ model: 'cottage', width: 3, depth: 3 });
    expect(rules.crops.crop_carrot).toEqual({ seed: 'seed_carrot', grow_seconds: 60, yield: 1 });
    expect(communityOf(rules, 'sf-dynamic-farm-20261118-r4')).toBe('sf');
    expect(communityOf(rules, 'nope')).toBeNull();
  });

  it('refuses malformed rules at load time', () => {
    expect(() => parseParcelRules({ ...rules, version: 2 })).toThrow();
    expect(() => parseParcelRules({ ...rules, crops: { crop_carrot: { seed: 'seed_carrot', grow_seconds: 0, yield: 1 } } })).toThrow();
    expect(() => parseParcelRules({ ...rules, communities: [{ id: 'a', datasets: ['d'] }, { id: 'b', datasets: ['d'] }] })).toThrow();
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

  it('runs the first loop: house, clear, till, sow, harvest after the server-time ripening', () => {
    let s = starterFarm(rules);
    s = run(s, [{ type: 'place_house', x: 10, y: 10 }, { type: 'clear_obstacle', cell: '3,3' }, { type: 'till', cell: '3,3' },
      { type: 'sow', cell: '3,3', crop: 'crop_carrot' }]);
    expect(s.house).toEqual({ model: 'cottage', x: 10, y: 10, width: 3, depth: 3, rotation: 0, built_at: T0 });
    expect(s.cleared).toEqual(['3,3']);
    expect(s.crops['3,3']).toEqual({ crop: 'crop_carrot', planted_at: T0, ripe_at: T0 + 60_000 });
    expect(s.bag).toEqual({ hoe_starter: 1, seed_carrot: 4 });

    const early = applyFarmCommands(rules, s, [{ type: 'harvest', cell: '3,3' }], T0 + 59_999);
    expect(early).toEqual({ ok: false, index: 0, code: 'NOT_RIPE', detail: { ripe_at: T0 + 60_000 } });
    s = run(s, [{ type: 'harvest', cell: '3,3' }], T0 + 60_000);
    expect(s.crops).toEqual({});
    expect(s.tilled).toEqual(['3,3']);
    expect(s.bag).toEqual({ hoe_starter: 1, seed_carrot: 4, crop_carrot: 1 });
  });

  it('keeps the house off tilled ground and tilling off the house', () => {
    const s = run(starterFarm(rules), [{ type: 'till', cell: '5,5' }]);
    expect(applyFarmCommands(rules, s, [{ type: 'place_house', x: 4, y: 4 }], T0)).toMatchObject({ ok: false, code: 'CELL_OCCUPIED', detail: { cells: ['5,5'] } });
    const housed = run(s, [{ type: 'place_house', x: 6, y: 6 }]);
    expect(applyFarmCommands(rules, housed, [{ type: 'till', cell: '8,8' }], T0)).toMatchObject({ ok: false, code: 'CELL_OCCUPIED' });
    expect(applyFarmCommands(rules, housed, [{ type: 'place_house', x: 20, y: 20 }], T0)).toMatchObject({ ok: false, code: 'HOUSE_PLACED' });
    expect(applyFarmCommands(rules, starterFarm(rules), [{ type: 'place_house', x: 1022, y: 0 }], T0)).toMatchObject({ ok: false, code: 'OUT_OF_BOUNDS' });
  });

  it('needs the hoe, a tilled cell and a seed; a refused batch changes nothing', () => {
    const noHoe = { ...starterFarm(rules), bag: { seed_carrot: 1 } };
    expect(applyFarmCommands(rules, noHoe, [{ type: 'till', cell: '1,1' }], T0)).toMatchObject({ ok: false, code: 'NO_TOOL' });
    const s = starterFarm(rules);
    expect(applyFarmCommands(rules, s, [{ type: 'sow', cell: '1,1', crop: 'crop_carrot' }], T0)).toMatchObject({ ok: false, code: 'NOT_TILLED' });
    expect(applyFarmCommands(rules, s, [{ type: 'till', cell: '1,1' }, { type: 'sow', cell: '1,1', crop: 'crop_potato' }], T0))
      .toMatchObject({ ok: false, index: 1, code: 'UNKNOWN_CROP' });
    expect(s).toEqual(starterFarm(rules));
    const cells = Array.from({ length: 6 }, (_, i) => `${i},0`);
    const tilled = run(s, cells.map(cell => ({ type: 'till', cell }) as FarmCommand));
    const sown = run(tilled, cells.slice(0, 5).map(cell => ({ type: 'sow', cell, crop: 'crop_carrot' }) as FarmCommand));
    expect(sown.bag.seed_carrot).toBeUndefined();
    expect(applyFarmCommands(rules, sown, [{ type: 'sow', cell: '5,0', crop: 'crop_carrot' }], T0)).toMatchObject({ ok: false, code: 'NO_SEED' });
    expect(applyFarmCommands(rules, sown, [{ type: 'sow', cell: '0,0', crop: 'crop_carrot' }], T0)).toMatchObject({ ok: false, code: 'CELL_OCCUPIED' });
    expect(applyFarmCommands(rules, sown, [{ type: 'till', cell: '0,0' }], T0)).toMatchObject({ ok: false, code: 'ALREADY_TILLED' });
    expect(applyFarmCommands(rules, sown, [{ type: 'harvest', cell: '9,9' }], T0)).toMatchObject({ ok: false, code: 'NO_CROP' });
    expect(applyFarmCommands(rules, run(s, [{ type: 'clear_obstacle', cell: '2,2' }]), [{ type: 'clear_obstacle', cell: '2,2' }], T0))
      .toMatchObject({ ok: false, code: 'ALREADY_CLEARED' });
  });
});
