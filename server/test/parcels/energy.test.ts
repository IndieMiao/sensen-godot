/** 地块体力（C-148，所有者 C-137#15 第 3 题“照搬p0”）：数值照 P0、每个动作的价、不够时拒绝不改存档、按服务端时间恢复、休息、老存档满体力。 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { dayKey, maxEnergy, nextRollover, nextTickIn, regenMs, settleEnergy } from '../../src/parcels/energy.js';
import { applyFarmCommands, emptyFarm, grant, parseFarmCommands, rebaseFarm, welcome, withEconomy,
  type FarmCommand, type ParcelFarmState } from '../../src/parcels/farm.js';
import { loadParcelRules, parseParcelRules } from '../../src/parcels/rules.js';

const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const p0 = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, '..', '..', 'p0', 'p0_content.json'), 'utf8'));
const T0 = Date.UTC(2026, 10, 23, 20);   // 12:00 in San Francisco (UTC−8)
const DAY = 86_400_000;
const MIN = 60_000;
const PARCEL = 'p-3512001';
const TREE = `${PARCEL}:outer-groves-v2:wild_pz_tree_20:41,7:0`;
const ctx = { parcel_id: PARCEL };

/** 首次进入（新手期从这里算）在 welcomedAt 的农场。 */
const farmAt = (welcomedAt = T0): ParcelFarmState => welcome(rules, emptyFarm(), welcomedAt)!;
/** 过了新手期的农场：8 天前首次进入。 */
const veteran = (): ParcelFarmState => farmAt(T0 - 8 * DAY);
function run(state: ParcelFarmState, commands: FarmCommand[], now = T0): ParcelFarmState {
  const out = applyFarmCommands(rules, state, commands, now, ctx);
  if (!out.ok) throw new Error(`${out.code} @${out.index}`);
  return out.state;
}
/** 体力定在 value、计时从 at 起的农场。 */
const withEnergy = (s: ParcelFarmState, value: number, at = T0, rested_on: string | null = null): ParcelFarmState =>
  ({ ...structuredClone(s), energy: { value, at, rested_on } });
const energy = (s: ParcelFarmState) => s.energy!.value;

describe('C-148 numbers are P0’s (assets/p0/p0_content.json, server/src/p0/rules.ts)', () => {
  it('pool 200 (+10 a farm level, level 1 here), +1 every 4 min, Newcomer 7 days ×1.5, Rest +60; carrot sow 3', () => {
    expect(rules.energy.max_base).toBe(p0.energy.max_base);
    expect(rules.energy.max_base).toBe(200);
    expect(rules.energy.per_level).toBe(10);
    expect(rules.energy.regen_ms).toBe(p0.energy.regen_ms);
    expect(rules.energy.regen_ms).toBe(240_000);
    expect(rules.energy.rest_amount).toBe(p0.energy.rest_amount);
    expect(rules.energy.blessing).toEqual({ days: p0.blessing.days, regen_mult: p0.blessing.regen_mult });
    expect(rules.energy.day.rollover_hour).toBe(p0.day.rollover_hour);
    const carrot = p0.crops.find((c: { id: string }) => c.id === 'crop_carrot');
    expect(rules.crops.crop_carrot.energy).toBe(carrot.energy);
    // C-151: drawing a pail at the well is the “打一桶水 2” of C-137#10 q3, which the owner took as P0's (C-137#15).
    // C-154: feeding an animal 1, P0's.
    expect(rules.energy.costs).toEqual({ clear_obstacle: 2, till: 2, gather: 2, feed: 1, draw_water: 2 });
    expect(maxEnergy(rules, emptyFarm())).toBe(200);
  });

  it('refuses malformed Energy rules at load time', () => {
    const bad = (energy: unknown) => () => parseParcelRules({ ...rules, energy });
    expect(bad(undefined)).toThrow();
    expect(bad({ ...rules.energy, regen_ms: 0 })).toThrow();
    expect(bad({ ...rules.energy, blessing: { days: 7, regen_mult: 0.5 } })).toThrow();
    expect(bad({ ...rules.energy, day: { utc_offset_hours: -8, rollover_hour: 24 } })).toThrow();
    expect(bad({ ...rules.energy, costs: { harvest: 1 } })).toThrow();
    expect(() => parseParcelRules({ ...rules, crops: { crop_carrot: { seed: 'seed_carrot', grow_seconds: 60, yield: 1 } } })).toThrow();
  });

  it('rest is a command with no fields', () => {
    expect(parseFarmCommands([{ type: 'rest' }])).toEqual([{ type: 'rest' }]);
  });
});

describe('C-148 each action costs its Energy', () => {
  it('clear 2, till 2, sow a carrot 3, gather a tree 3 (C-236, SEN-Q-342), draw water 2; watering, harvest, sell, blueprint and buildings are free', () => {
    let s = grant(rules, veteran(), T0)!.state;
    expect(energy(settle(s))).toBe(200);
    s = run(s, [{ type: 'place_house', x: 10, y: 10 }]);
    expect(energy(s)).toBe(200);
    s = run(s, [{ type: 'clear_obstacle', cell: '3,3' }]);
    expect(energy(s)).toBe(198);
    s = run(s, [{ type: 'till', cell: '3,3' }]);
    expect(energy(s)).toBe(196);
    s = run(s, [{ type: 'sow', cell: '3,3', crop: 'crop_carrot' }]);
    expect(energy(s)).toBe(193);
    s = run(s, [{ type: 'gather', object: TREE }]);
    expect(energy(s)).toBe(190);
    s = run(s, [{ type: 'place_building', building: 'well', x: 30, y: 30, rotation: 0 }]);
    expect(energy(s)).toBe(190);
    s = run(s, [{ type: 'draw_water', building: 2 }]);
    expect(energy(s)).toBe(188);
    s = run(s, [{ type: 'water', cell: '3,3' }]);
    expect(energy(s)).toBe(188);
    // 60 s after watering the carrot is ripe; less than 4 min, so no point has come back yet.
    s = run(s, [{ type: 'harvest', cell: '3,3' }, { type: 'sell', item: 'crop_carrot', count: 1 }, { type: 'claim_blueprint', blueprint: 'coop' }], T0 + MIN);
    expect(energy(s)).toBe(188);
    expect(s.bag).toMatchObject({ blueprint_coop: 1, wood: 2 });
  });

  it('a batch pays for every command in it', () => {
    const s = run(veteran(), [{ type: 'till', cell: '1,1' }, { type: 'till', cell: '2,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' }]);
    expect(energy(s)).toBe(200 - 2 - 2 - 3);
  });
});

describe('C-148 not enough Energy: the server refuses and the save does not change', () => {
  it('NO_ENERGY with what it needs, what there is and when the next point comes; nothing else changes', () => {
    const s = withEnergy(run(veteran(), [{ type: 'till', cell: '1,1' }]), 2, T0 - MIN);
    const before = structuredClone(s);
    const sow = applyFarmCommands(rules, s, [{ type: 'sow', cell: '1,1', crop: 'crop_carrot' }], T0, ctx);
    expect(sow).toEqual({ ok: false, index: 0, code: 'NO_ENERGY', detail: { need: 3, have: 2, next_in: 3 * MIN } });
    expect(s).toEqual(before);
    for (const [c, need] of [[{ type: 'clear_obstacle', cell: '5,5' }, 2], [{ type: 'till', cell: '2,2' }, 2], [{ type: 'gather', object: TREE }, 3]] as [FarmCommand, number][]) {
      const low = withEnergy(s, 1, T0);
      expect(applyFarmCommands(rules, low, [c], T0, ctx)).toMatchObject({ ok: false, code: 'NO_ENERGY', detail: { need, have: 1 } });
    }
    // Free actions still work at 0.
    expect(applyFarmCommands(rules, withEnergy(s, 0), [{ type: 'place_house', x: 10, y: 10 }], T0, ctx).ok).toBe(true);
    expect(applyFarmCommands(rules, withEnergy(s, 0), [{ type: 'place_building', building: 'cottage', x: 10, y: 10, rotation: 0 }], T0, ctx).ok).toBe(true);
  });

  it('a batch that runs out half way is refused whole', () => {
    const s = withEnergy(veteran(), 5);
    const out = applyFarmCommands(rules, s, [{ type: 'till', cell: '1,1' }, { type: 'till', cell: '2,1' }, { type: 'till', cell: '3,1' }], T0, ctx);
    expect(out).toMatchObject({ ok: false, index: 2, code: 'NO_ENERGY', detail: { need: 2, have: 1 } });
    expect(s.tilled).toEqual([]);
    expect(energy(s)).toBe(5);
  });

  it('its own reason comes first: a tilled cell says ALREADY_TILLED, not NO_ENERGY', () => {
    const s = withEnergy(run(veteran(), [{ type: 'till', cell: '1,1' }]), 0);
    expect(applyFarmCommands(rules, s, [{ type: 'till', cell: '1,1' }], T0, ctx)).toMatchObject({ code: 'ALREADY_TILLED' });
  });
});

/** 结算后的副本。 */
const settle = (s: ParcelFarmState, now = T0): ParcelFarmState => {
  const c = structuredClone(s);
  settleEnergy(rules, c, now);
  return c;
};

describe('C-148 Energy comes back by server time, offline too', () => {
  it('+1 every 4 minutes, whole points only, and never past the pool', () => {
    const s = withEnergy(veteran(), 100, T0);
    expect(energy(settle(s, T0 + 4 * MIN - 1))).toBe(100);
    expect(energy(settle(s, T0 + 4 * MIN))).toBe(101);
    expect(settle(s, T0 + 10 * MIN).energy).toEqual({ value: 102, at: T0 + 8 * MIN, rested_on: null });
    // Away a whole day: 360 points would come back, the pool stops it at 200.
    expect(settle(s, T0 + DAY).energy).toEqual({ value: 200, at: T0 + DAY, rested_on: null });
    expect(nextTickIn(rules, settle(s, T0 + DAY), T0 + DAY)).toBeNull();
  });

  it('a full pool holds its timer: spending one point after a long time full waits a whole 4 minutes', () => {
    const full = withEnergy(veteran(), 200, T0 - DAY);
    const spent = run(full, [{ type: 'till', cell: '1,1' }], T0);
    expect(spent.energy).toEqual({ value: 198, at: T0, rested_on: null });
    expect(energy(settle(spent, T0 + 4 * MIN - 1))).toBe(198);
    expect(energy(settle(spent, T0 + 4 * MIN))).toBe(199);
  });

  it('what came back while offline is there to spend: the next command settles first', () => {
    const s = withEnergy(veteran(), 1, T0);
    expect(applyFarmCommands(rules, s, [{ type: 'till', cell: '1,1' }], T0 + 3 * MIN, ctx)).toMatchObject({ code: 'NO_ENERGY' });
    const later = run(s, [{ type: 'till', cell: '1,1' }], T0 + 4 * MIN);
    expect(later.energy).toEqual({ value: 0, at: T0 + 4 * MIN, rested_on: null });
  });

  it('Newcomer: the first 7 days after the first entry come back ×1.5 (every 2:40)', () => {
    const fresh = farmAt(T0);
    expect(regenMs(rules, fresh, T0)).toBe(160_000);
    expect(regenMs(rules, fresh, T0 + 7 * DAY - 1)).toBe(160_000);
    expect(regenMs(rules, fresh, T0 + 7 * DAY)).toBe(240_000);
    const s = withEnergy(fresh, 100, T0);
    expect(energy(settle(s, T0 + 160_000))).toBe(101);
    expect(energy(settle(s, T0 + 16 * MIN))).toBe(106);
    expect(energy(settle(withEnergy(veteran(), 100, T0), T0 + 16 * MIN))).toBe(104);
    // Not entered yet: no blessing.
    expect(regenMs(rules, emptyFarm(), T0)).toBe(240_000);
  });
});

describe('C-148 Rest at the cottage: +60 once a player day', () => {
  const housed = (value: number) => withEnergy(run(veteran(), [{ type: 'place_house', x: 10, y: 10 }]), value);

  it('needs the cottage, gives up to 60 and only once a day', () => {
    expect(applyFarmCommands(rules, withEnergy(veteran(), 50), [{ type: 'rest' }], T0, ctx)).toMatchObject({ ok: false, code: 'NO_HOUSE' });
    const rested = run(housed(50), [{ type: 'rest' }]);
    expect(rested.energy).toEqual({ value: 110, at: T0, rested_on: '2026-11-23' });
    const again = applyFarmCommands(rules, rested, [{ type: 'rest' }], T0 + MIN, ctx);
    expect(again).toEqual({ ok: false, index: 0, code: 'RESTED_TODAY', detail: { resets_at: Date.UTC(2026, 10, 24, 12) } });
    // Near the top it gives only what fits, and a full pool cannot rest (the day's rest is kept).
    expect(run(housed(180), [{ type: 'rest' }]).energy).toEqual({ value: 200, at: T0, rested_on: '2026-11-23' });
    expect(applyFarmCommands(rules, housed(200), [{ type: 'rest' }], T0, ctx)).toMatchObject({ ok: false, code: 'ENERGY_FULL' });
  });

  it('finds the cottage in the building list (C-150), placed either way or carried over from an old house-only save', () => {
    const built = withEnergy(run(veteran(), [{ type: 'place_building', building: 'cottage', x: 10, y: 10, rotation: 1 }]), 50);
    expect(run(built, [{ type: 'rest' }]).energy).toEqual({ value: 110, at: T0, rested_on: '2026-11-23' });
    // A save from before C-150: only house, no buildings. It reads as building 1, a cottage, so Rest works.
    const old = housed(50) as Partial<ParcelFarmState> & ParcelFarmState;
    delete (old as Partial<ParcelFarmState>).buildings;
    expect(run(old, [{ type: 'rest' }]).energy).toEqual({ value: 110, at: T0, rested_on: '2026-11-23' });
    // The building list decides, not the old house mirror: buildings without a cottage cannot rest.
    const stale = { ...withEnergy(veteran(), 50), buildings: [], house: housed(50).house };
    expect(applyFarmCommands(rules, stale, [{ type: 'rest' }], T0, ctx)).toMatchObject({ ok: false, code: 'NO_HOUSE' });
  });

  it('the player day turns at 04:00 San Francisco time (12:00 UTC); the next day rests again', () => {
    expect(dayKey(rules, Date.UTC(2026, 10, 24, 11, 59))).toBe('2026-11-23');
    expect(dayKey(rules, Date.UTC(2026, 10, 24, 12))).toBe('2026-11-24');
    expect(nextRollover(rules, T0)).toBe(Date.UTC(2026, 10, 24, 12));
    const rested = withEnergy(run(housed(50), [{ type: 'rest' }]), 50, T0, '2026-11-23');
    expect(applyFarmCommands(rules, rested, [{ type: 'rest' }], Date.UTC(2026, 10, 24, 11, 59), ctx)).toMatchObject({ code: 'RESTED_TODAY' });
    const next = Date.UTC(2026, 10, 24, 12);
    const out = run(withEnergy(rested, 50, next, '2026-11-23'), [{ type: 'rest' }], next);
    expect(out.energy).toEqual({ value: 110, at: next, rested_on: '2026-11-24' });
  });
});

describe('C-148 old saves read at full Energy', () => {
  /** C-58 之后、C-148 之前写下的存档：没有 energy。 */
  const legacy = (): ParcelFarmState => {
    const s = run(veteran(), [{ type: 'place_house', x: 6, y: 6 }, { type: 'till', cell: '1,2' }]);
    delete s.energy;
    return s;
  };

  it('no energy field: full, nothing else changes; the first command writes it', () => {
    const old = legacy();
    expect(withEconomy(old)).toEqual(old);
    expect(settle(old).energy).toEqual({ value: 200, at: T0, rested_on: null });
    const { energy: _e, ...rest } = settle(old);
    expect(rest).toEqual(old);
    const after = run(old, [{ type: 'till', cell: '2,2' }]);
    expect(after).toEqual({ ...old, tilled: ['1,2', '2,2'], energy: { value: 198, at: T0, rested_on: null } });
  });

  it('a malformed energy field reads as full rather than locking the farm', () => {
    const odd = { ...legacy(), energy: { value: -3, at: 'x', rested_on: 5 } } as unknown as ParcelFarmState;
    expect(settle(odd).energy).toEqual({ value: 200, at: T0, rested_on: null });
  });

  it('moving to a newer dataset keeps Energy and the day’s rest (they are not cell progress)', () => {
    const s = withEnergy(legacy(), 42, T0, '2026-11-23');
    expect(rebaseFarm(rules, s, T0).energy).toEqual({ value: 42, at: T0, rested_on: '2026-11-23' });
  });
});

/**
 * 客户端和服务端同一套规则：tests/dynamic_farm/fixtures/energy_cases.json 的每个用例在这里按服务端跑，
 * 在 tests/dynamic_farm/test_parcel_farming.gd 里按客户端 parcel_farm.gd 跑，两边结果都要等于文件里记的结果。
 */
describe('C-148 the client runs the same Energy cases (shared fixture)', () => {
  const shared = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, '..', '..', '..', 'tests', 'dynamic_farm', 'fixtures', 'energy_cases.json'), 'utf8'));
  for (const c of shared.cases) {
    it(c.name, () => {
      const r = applyFarmCommands(rules, structuredClone(c.farm), c.commands, c.now, { parcel_id: shared.parcel_id });
      expect(r.ok ? { ok: true, energy: r.state.energy } : { ok: false, index: r.index, code: r.code, detail: r.detail ?? {} }).toEqual(c.expect);
    });
  }
});
