import { describe, expect, it } from 'vitest';
import { freshMineB1DailyFields, freshMineB1Fields, freshMineB1Weapons, type MineB1Day, type MineB1Notice } from '../../src/p0/state.js';

describe('355 E/F/G v7 field initializers (contract v0.1 section 3)', () => {
  it('starts outside every mine with no records, kill counts, notices or legacy run fields', () => {
    expect(freshMineB1Fields()).toEqual({
      mine: { records: {}, day: null, notice: null }, kills: {}, guard_firsts: {},
    });
  });

  it('keeps accounts independent, including their owned weapon arrays', () => {
    const a = freshMineB1Fields(), b = freshMineB1Fields();
    a.mine.records['wd-dev-quarry'] = { deepest: 10, guards: [10], first_at: 1000 };
    a.kills.mob_slime = 3;
    a.guard_firsts.boss_slime_king = { at: 2000, mine: 'wd-dev-quarry', floor: 10 };
    const first = freshMineB1Weapons('weapon_wooden_sword'), second = freshMineB1Weapons('weapon_wooden_sword');
    first.weapons.push('weapon_copper_sword');
    first.weapon = 'weapon_copper_sword';
    expect(b).toEqual({ mine: { records: {}, day: null, notice: null }, kills: {}, guard_firsts: {} });
    expect(second).toEqual({ weapons: ['weapon_wooden_sword'], weapon: 'weapon_wooden_sword' });
  });

  it('does not hard-code a starting weapon instead of the content-selected one', () => {
    expect(freshMineB1Weapons('weapon_test')).toEqual({ weapons: ['weapon_test'], weapon: 'weapon_test' });
  });

  it('starts daily content-limited drops empty and never shares counters between players or days', () => {
    const today = freshMineB1DailyFields(), other = freshMineB1DailyFields();
    today.once.mob_test = 1;
    expect(other).toEqual({ once: {} });
    expect(freshMineB1DailyFields()).toEqual({ once: {} });
    expect(JSON.parse(JSON.stringify(today))).toEqual({ once: { mob_test: 1 } });
  });

  it('round-trips per-mine floors, daily pickups, timers and KO notices without mixing long-term records', () => {
    const fields = freshMineB1Fields();
    fields.mine.records = {
      'wd-dev-quarry': { deepest: 21, guards: [10, 20], first_at: 1000 },
      'wd-dev-vein': { deepest: 11, guards: [], first_at: 2000 },
    };
    const day: MineB1Day = {
      key: '2026-11-02', at: { mine: 'wd-dev-vein', floor: 11 }, hp: 76,
      floors: {
        'wd-dev-quarry:11': { paid: true, broken: [0], lit: false, mobs: [0, 0, 18], ground: [], ground_seq: 0 },
        'wd-dev-vein:11': { paid: true, broken: [1, 3], lit: true, mobs: [18, 0, 5], ground: [{ id: 1, item: 'iron_ore', qty: 2, from: 1 }], ground_seq: 1 },
      },
      picked: [['iron_ore', 3]], attack_at: 3000, hurt_at: 4000, drink_at: 5000, swing_at: 6000,
    };
    fields.mine.day = day;
    fields.mine.notice = { kind: 'ko', at: 7000, floor: 11, lost: [['iron_ore', 1]] };
    const restored = JSON.parse(JSON.stringify(fields));
    expect(restored).toEqual(fields);
    restored.mine.day.floors['wd-dev-quarry:11'].mobs[2] = 0;
    expect(restored.mine.day.floors['wd-dev-vein:11'].mobs).toEqual([18, 0, 5]);
    expect(restored.mine.records).toEqual(fields.mine.records);
  });

  it('can discard the daily state while retaining mine records and lifetime kill/guard facts', () => {
    const fields = freshMineB1Fields();
    fields.mine.records['wd-dev-vein'] = { deepest: 20, guards: [20], first_at: 1000 };
    fields.kills.boss_slime_king_iron = 1;
    fields.guard_firsts.boss_slime_king_iron = { at: 2000, mine: 'wd-dev-vein', floor: 20 };
    fields.mine.day = { key: '2026-11-02', at: { mine: 'wd-dev-vein', floor: 20 }, hp: 76, floors: {}, picked: [] };
    const permanent = structuredClone({ records: fields.mine.records, kills: fields.kills, firsts: fields.guard_firsts });
    fields.mine.day = null;
    const notice: MineB1Notice = { kind: 'reset', at: 3000, floor: 20 };
    fields.mine.notice = notice;
    expect({ records: fields.mine.records, kills: fields.kills, firsts: fields.guard_firsts }).toEqual(permanent);
    expect(JSON.parse(JSON.stringify(fields)).mine).toMatchObject({ day: null, notice });
  });
});
