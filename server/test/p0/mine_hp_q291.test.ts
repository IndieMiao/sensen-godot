// q(291) A (SGODOT-421; the user 11-05 16:20 "291 A", q row 99d2cca1): mine HP goes with the player — leaving and
// entering again no longer refill it; outside it refills 0 to full in 60 minutes; 04:00 refills it, in the mine too; a
// knock-out leaves 30. Bosses and elites still refill when you leave their floor.
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { mineHp, mineHpFullIn } from '../../src/p0/mine.js';
import { notePresence } from '../../src/p0/presence.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { dayKey } from '../../src/p0/rules.js';
import { freshState } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { setDevSites } from '../../src/p0/mine.js';
setDevSites(true);   // wd-dev-quarry / wd-dev-vein: tests only (P0_DEV_SITES)

const T = Date.UTC(2026, 10, 2, 2), DAY = 86400000, Q = 'wd-dev-quarry', V = 'wd-dev-vein';
function scenario() {
  const c = loadP0Content(); c.profile.timezone = 'Asia/Shanghai';
  let s = freshState(c, 'mine-hp-q291', T, 7), now = T;
  s.created_at = T - 30 * DAY; s.homestead.level = 8;
  const send = (cmd: Record<string, unknown>) => {
    now += 1000;
    const r = applyP0(c, s, { space: 'mine', day: dayKey(c, s, now), ...cmd } as P0Command, now);
    if (!r.ok) throw new Error(JSON.stringify(r));
    s = r.state; return r;
  };
  const start = (mine = Q, floor = 1) => {
    if (floor > 1) {
      const record = s.mine.records[mine] ??= { deepest: 0, guards: [], first_at: T - DAY };
      record.deepest = Math.max(record.deepest, floor);
    }
    return send({ type: 'mine_enter', mine, floor });
  };
  return { c, send, start, get s() { return s; }, get now() { return now; } };
}
describe('q(291) A: mine HP goes with the player (SGODOT-421)', () => {
  const MIN = 60_000, STEP = 36_000;   // 100 HP over 60 minutes: +1 every 36 s
  const leave = (x: ReturnType<typeof scenario>, at: number) => notePresence(x.c, x.s, 'map', at, null);
  it('the content: a knock-out leaves 30, outside 0 to full in 60 minutes', () => {
    const c = loadP0Content();
    expect([c.mine.combat.hp, c.mine.combat.ko_hp, c.mine.combat.regen_full_ms]).toEqual([100, 30, 60 * MIN]);
  });
  it('leaving keeps the HP and it refills outside, a point every 36 s; entering again brings what refilled', () => {
    const x = scenario(); x.start(); x.s.mine.day!.hp = 40;
    const out = x.now + 1000; leave(x, out);
    expect(x.s.mine.day).toMatchObject({ at: null, hp: 40, hp_at: out });
    expect([mineHp(x.c, x.s.mine.day, out), mineHpFullIn(x.c, x.s.mine.day, out)]).toEqual([40, 36 * MIN]);   // `40% · Full in 36m`
    expect(mineHp(x.c, x.s.mine.day, out + STEP - 1)).toBe(40);
    expect(mineHp(x.c, x.s.mine.day, out + STEP)).toBe(41);
    expect(mineHp(x.c, x.s.mine.day, out + 10 * MIN)).toBe(56);
    expect(mineHpFullIn(x.c, x.s.mine.day, out + 10 * MIN)).toBe(26 * MIN);
    const v = viewOf(x.c, x.s, out + 10 * MIN).mine;
    expect([v.hp, v.hp_max, v.hp_full_in, v.at]).toEqual([56, 100, 26 * MIN, null]);
    // in again 10 minutes on: 56, and no more refilling inside
    const r = applyP0(x.c, x.s, { type: 'mine_enter', mine: Q, floor: 1 } as P0Command, out + 10 * MIN);
    if (!r.ok) throw new Error(r.code);
    expect(r.state.mine.day!.hp).toBe(56); expect(r.state.mine.day!.hp_at).toBeUndefined();
    const inside = viewOf(x.c, r.state, out + 50 * MIN).mine;
    expect([inside.at!.hp, inside.hp, inside.hp_full_in]).toEqual([56, 56, 0]);
  });
  it('it never refills past full; a full player shows no time left', () => {
    const x = scenario(); x.start(); x.s.mine.day!.hp = 90;
    const out = x.now + 1000; leave(x, out);
    expect([mineHp(x.c, x.s.mine.day, out + 6 * MIN), mineHpFullIn(x.c, x.s.mine.day, out + 6 * MIN)]).toEqual([100, 0]);
    expect(mineHp(x.c, x.s.mine.day, out + 600 * MIN)).toBe(100);
    expect(viewOf(x.c, x.s, out + 7 * MIN).mine).toMatchObject({ hp: 100, hp_full_in: 0 });
  });
  it('a knock-out leaves 30, refilling from then; F1–10 lose nothing', () => {
    const x = scenario(); x.start(); x.s.mine.day!.hp = 1;
    x.send({ type: 'mine_attack', floor: 1, hurt_by: 0 });
    const ko = x.now;
    expect(x.s.mine.day).toMatchObject({ at: null, hp: 30, hp_at: ko });
    expect(viewOf(x.c, x.s, ko).mine).toMatchObject({ hp: 30, hp_full_in: 42 * MIN });   // `30% · Full in 42m`
    expect(mineHp(x.c, x.s.mine.day, ko + 42 * MIN)).toBe(100);
  });
  it('04:00 refills it: out of the mine (the day is gone) and in it (the floor kept, HP full)', () => {
    const x = scenario(); x.start(); x.s.mine.day!.hp = 20; leave(x, x.now + 1000);
    const next = x.now + DAY;
    expect(viewOf(x.c, x.s, next).mine).toMatchObject({ hp: 100, hp_full_in: 0 });
    const r = applyP0(x.c, x.s, { type: 'mine_enter', mine: Q, floor: 1 } as P0Command, next);
    if (!r.ok) throw new Error(r.code);
    expect(r.state.mine.day!.hp).toBe(100);
    const y = scenario(); y.start(V, 10); y.s.mine.day!.hp = 20;
    const v = viewOf(y.c, y.s, y.now + DAY).mine;
    expect([v.at!.floor, v.at!.hp, v.hp]).toEqual([10, 100, 100]);
  });
  it("an old save's day (left before q(291), HP written full, no hp_at) reads full; one in the mine reads its own", () => {
    const x = scenario(); x.start(); x.s.mine.day!.hp = 63;
    expect([mineHp(x.c, x.s.mine.day, x.now + 9 * MIN), mineHpFullIn(x.c, x.s.mine.day, x.now + 9 * MIN)]).toEqual([63, 0]);
    x.s.mine.day!.at = null; x.s.mine.day!.hp = 100;
    expect(mineHp(x.c, x.s.mine.day, x.now)).toBe(100);
    expect(mineHp(x.c, null, x.now)).toBe(100);
  });
  it('the bosses still refill when you leave their floor (q(291) ⑤)', () => {
    const x = scenario(); x.start(Q, 10); x.send({ type: 'mine_attack', floor: 10, targets: [0] });
    const hit = x.s.mine.day!.floors[`${Q}:10`].mobs[0];
    expect(hit).toBeLessThan(x.c.mine.monsters.boss_slime_king.hp);
    leave(x, x.now + 1000);
    expect(x.s.mine.day!.floors[`${Q}:10`].mobs[0]).toBe(x.c.mine.monsters.boss_slime_king.hp);
  });
});
