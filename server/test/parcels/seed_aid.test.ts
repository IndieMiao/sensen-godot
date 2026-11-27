/**
 * 种子兜底（C-197，所有者 SEN-Q-281）：没钱（不够买 1 颗胡萝卜种子）、没种子、没作物（背包和地里都没有）三条同时满足，
 * 每个玩家日在 Jasmine 那里领一次 3 颗胡萝卜种子；任一条不满足不送；领过的玩家日存档；旧存档按没领过读。
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { dayKey, nextRollover } from '../../src/parcels/energy.js';
import { applyFarmCommands, emptyFarm, NEVER, parseFarmCommands, rebaseFarm, welcome, withEconomy, type FarmCommand, type ParcelFarmState } from '../../src/parcels/farm.js';
import { loadParcelRules, parseParcelRules } from '../../src/parcels/rules.js';
import { seedAidRefusal } from '../../src/parcels/seed_aid.js';

const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
/** 太平洋时间 11-23 早上 8 点（玩家日 4 点换，离换日还远）。 */
const T0 = Date.UTC(2026, 10, 23, 16);
const CLAIM: FarmCommand[] = [{ type: 'claim_seed_aid' }];
/** 进过农场、种子用完、钱花光、没作物。 */
const broke = (extra: Partial<ParcelFarmState> = {}): ParcelFarmState => {
  const s = welcome(rules, emptyFarm(), T0)!;
  delete s.bag.seed_carrot;
  return { ...s, ...extra };
};
const claim = (s: ParcelFarmState, now: number) => applyFarmCommands(rules, s, CLAIM, now);
const given = (s: ParcelFarmState, now: number): ParcelFarmState => {
  const out = claim(s, now);
  if (!out.ok) throw new Error(`${out.code} ${JSON.stringify(out.detail)}`);
  return out.state;
};

describe('dynamic_farm.json seed_aid (C-197)', () => {
  it('ships SEN-Q-281: 3 carrot seeds; "no money" is less than one carrot seed at Jasmine\'s (9)', () => {
    expect(rules.seed_aid).toEqual({ item: 'seed_carrot', amount: 3 });
    expect(rules.economy.buy_prices.seed_carrot).toBe(9);
  });

  it('refuses malformed rules at load time; rules without seed_aid give nothing', () => {
    const bad = (seed_aid: unknown) => () => parseParcelRules({ ...structuredClone(rules), seed_aid });
    expect(bad({ item: 'seed_carrot', amount: 0 })).toThrow();
    expect(bad({ item: 'seed_carrot', amount: 100 })).toThrow();
    expect(bad({ item: 'seed_carrot' })).toThrow();
    expect(bad({ item: 'egg', amount: 3 })).toThrow();   // 不是作物的种子
    expect(bad([])).toThrow();
    // Jasmine 不卖的种子没法判断“没钱”。
    expect(() => parseParcelRules({ ...structuredClone(rules), economy: { ...rules.economy, buy_prices: {} } })).toThrow(/seed_aid/);
    const none = parseParcelRules({ ...structuredClone(rules), seed_aid: undefined });
    expect(applyFarmCommands(none, broke(), CLAIM, T0)).toEqual({ ok: false, index: 0, code: 'NO_SEED_AID' });
  });

  it('parses the command with no fields (anything else in it is dropped)', () => {
    expect(parseFarmCommands([{ type: 'claim_seed_aid', item: 'seed_carrot', amount: 99 }])).toEqual([{ type: 'claim_seed_aid' }]);
  });
});

describe('claim_seed_aid (C-197)', () => {
  it('all three met: 3 carrot seeds go into the bag, the player day is saved, nothing else changes (no Energy)', () => {
    const s = broke();
    const out = given(s, T0 + 1000);
    expect(out.bag).toEqual({ ...s.bag, seed_carrot: 3 });
    expect(out.seed_aid_day).toBe(dayKey(rules, T0));
    expect(out.coins).toBe(0);
    expect({ ...out, bag: s.bag, seed_aid_day: null, energy: undefined, board: undefined })
      .toEqual({ ...withEconomy(s), energy: undefined, board: undefined });
    expect(out.energy!.value).toBe(withEconomy(s).energy?.value ?? out.energy!.value);
    // 存进数据库再读出来一样。
    expect(withEconomy(JSON.parse(JSON.stringify(out)))).toEqual(out);
  });

  it('at most once a player day: the second the same day is refused with when it comes back; from 4 am Pacific it comes again', () => {
    const once = given(broke(), T0);
    delete once.bag.seed_carrot;   // 又种完了
    const frozen = structuredClone(once);
    const roll = nextRollover(rules, T0);
    expect(claim(once, T0 + 3_600_000)).toEqual({ ok: false, index: 0, code: 'SEED_AID_TODAY', detail: { resets_at: roll } });
    expect(claim(once, roll - 1)).toMatchObject({ ok: false, code: 'SEED_AID_TODAY' });
    expect(once).toEqual(frozen);
    const again = given(once, roll);
    expect(again.bag.seed_carrot).toBe(3);
    expect(again.seed_aid_day).toBe(dayKey(rules, roll));
    expect(again.seed_aid_day).not.toBe(once.seed_aid_day);
    // 一批里领两次：第二条被拒，整批不生效。
    expect(applyFarmCommands(rules, broke(), [...CLAIM, ...CLAIM], T0)).toMatchObject({ ok: false, index: 1, code: 'SEED_AID_TODAY' });
  });

  it('any one condition unmet: not given, the save unchanged', () => {
    const refusals: [string, ParcelFarmState, string][] = [
      ['9 coins buy a seed', broke({ coins: 9 }), 'coins'],
      ['lots of coins', broke({ coins: 500 }), 'coins'],
      ['one seed left', broke({ bag: { hoe_starter: 1, seed_carrot: 1 } }), 'seeds'],
      ['a carrot in the bag', broke({ bag: { crop_carrot: 1 } }), 'crops'],
      ['a sown, dry carrot', broke({ tilled: ['1,1'], crops: { '1,1': { crop: 'crop_carrot', planted_at: T0, ripe_at: NEVER, watered_at: null } } }), 'crops'],
      ['a growing carrot', broke({ tilled: ['1,1'], crops: { '1,1': { crop: 'crop_carrot', planted_at: T0, ripe_at: T0 + 60_000, watered_at: T0 } } }), 'crops'],
      ['a ripe carrot not harvested', broke({ tilled: ['1,1'], crops: { '1,1': { crop: 'crop_carrot', planted_at: T0 - 120_000, ripe_at: T0 - 60_000, watered_at: T0 - 120_000 } } }), 'crops'],
    ];
    for (const [label, s, reason] of refusals) {
      const frozen = structuredClone(s);
      const out = claim(s, T0);
      expect(out, label).toMatchObject({ ok: false, index: 0, code: 'CONDITION_NOT_MET', detail: { reason } });
      expect(s, label).toEqual(frozen);
    }
    // 8 金币买不起一颗 9 金币的种子：还算没钱。
    expect(given(broke({ coins: 8 }), T0).bag.seed_carrot).toBe(3);
  });

  it('other goods (eggs, wood, stone, herbs, blueprints) do not count against it', () => {
    const out = given(broke({ bag: { hoe_starter: 1, egg: 4, wood: 9, stone: 2, wild_herb: 1, blueprint_coop: 1 } }), T0);
    expect(out.bag.seed_carrot).toBe(3);
  });

  it('seedAidRefusal says the same as the command, for the client to decide whether to ask', () => {
    expect(seedAidRefusal(rules, withEconomy(broke()), T0)).toBeNull();
    expect(seedAidRefusal(rules, withEconomy(broke({ coins: 20 })), T0)).toMatchObject({ code: 'CONDITION_NOT_MET', detail: { reason: 'coins' } });
    expect(seedAidRefusal(rules, given(broke({ bag: {} }), T0), T0)).toMatchObject({ code: 'SEED_AID_TODAY' });
  });
});

describe('saves (C-197)', () => {
  it('a save from before the aid has no seed_aid_day: it reads as never given; an unreadable one too', () => {
    const old = { ...broke() } as Partial<ParcelFarmState>;
    delete old.seed_aid_day;
    expect(withEconomy(old as ParcelFarmState).seed_aid_day).toBeNull();
    expect(withEconomy({ ...broke(), seed_aid_day: 'monday' } as ParcelFarmState).seed_aid_day).toBeNull();
    expect(withEconomy({ ...broke(), seed_aid_day: 7 } as unknown as ParcelFarmState).seed_aid_day).toBeNull();
    expect(emptyFarm().seed_aid_day).toBeNull();
    expect(given(old as ParcelFarmState, T0).bag.seed_carrot).toBe(3);
  });

  it('moving to a newer dataset keeps the day it was given', () => {
    const out = given(broke(), T0);
    expect(rebaseFarm(rules, out, T0 + 1000).seed_aid_day).toBe(out.seed_aid_day);
  });
});

/**
 * 客户端和服务端同一套种子兜底规则：tests/dynamic_farm/fixtures/seed_aid_cases.json 的每个用例在这里按服务端跑，
 * 在 tests/dynamic_farm/test_seed_aid.gd 里按客户端 parcel_farm.gd 跑，两边结果都要等于文件里记的结果。
 */
describe('C-197 the client runs the same seed aid cases (shared fixture)', () => {
  const shared = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, '..', '..', '..', 'tests', 'dynamic_farm', 'fixtures', 'seed_aid_cases.json'), 'utf8'));
  it('has the cases', () => expect(shared.cases.length).toBeGreaterThanOrEqual(12));
  for (const c of shared.cases) {
    it(c.name, () => {
      const r = applyFarmCommands(rules, structuredClone(c.farm), c.commands, c.now);
      expect(r.ok ? { ok: true, bag: r.state.bag, coins: r.state.coins, seed_aid_day: r.state.seed_aid_day }
        : { ok: false, index: r.index, code: r.code, detail: r.detail ?? {} }).toEqual(c.expect);
    });
  }
});
