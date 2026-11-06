import { describe, expect, it, vi } from 'vitest';
import { count, room } from '../../src/p0/bag.js';
import { loadP0Content } from '../../src/p0/content.js';
import { bagFitsFloor, floorSpec, mineSite, mineView, rockDrops, stations } from '../../src/p0/mine.js';
import { notePresence } from '../../src/p0/presence.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { dayKey } from '../../src/p0/rules.js';
import { freshState } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { catalogue, wildById } from '../../src/p0/wild.js';
import { setDevSites } from '../../src/p0/mine.js';
setDevSites(true);   // wd-dev-quarry / wd-dev-vein: tests only (P0_DEV_SITES)

const T = Date.UTC(2026, 10, 2, 2), DAY = 86400000, Q = 'wd-dev-quarry', V = 'wd-dev-vein';
function scenario() {
  const c = loadP0Content(); c.profile.timezone = 'Asia/Shanghai';
  let s = freshState(c, 'mine-b1-test', T, 7), now = T;
  s.created_at = T - 30 * DAY; s.homestead.level = 8;
  const send = (cmd: Record<string, unknown>) => {
    now += 1000;
    const r = applyP0(c, s, { space: 'mine', day: dayKey(c, s, now), ...cmd } as P0Command, now);
    if (!r.ok) throw new Error(JSON.stringify(r));
    s = r.state; return r;
  };
  /** At this same moment, as a command queued behind a held-up reply reaches the server right after the one before. */
  const again = (cmd: Record<string, unknown>) => {
    const r = applyP0(c, s, { space: 'mine', day: dayKey(c, s, now), ...cmd } as P0Command, now);
    if (!r.ok) throw new Error(JSON.stringify(r));
    s = r.state; return r;
  };
  const fail = (cmd: Record<string, unknown>) => {
    const before = structuredClone(s);
    const r = applyP0(c, s, { space: 'mine', day: dayKey(c, s, now), ...cmd } as P0Command, now);
    expect(r.ok).toBe(false); expect(s).toEqual(before); return r;
  };
  const start = (mine = Q, floor = 1) => {
    if (floor > 1) {
      const record = s.mine.records[mine] ??= { deepest: 0, guards: [], first_at: T - DAY };
      record.deepest = Math.max(record.deepest, floor);
    }
    return send({ type: 'mine_enter', mine, floor });
  };
  const state = () => s.mine.day!.floors[`${s.mine.day!.at!.mine}:${s.mine.day!.at!.floor}`];
  const kill = (index: number) => {
    let tries = 0;
    while (state().mobs[index] > 0) {
      if (++tries > 1000) throw new Error('kill did not terminate');
      send({ type: 'mine_attack', floor: s.mine.day!.at!.floor, targets: [index] });
    }
  };
  return { c, send, again, fail, start, state, kill, get s() { return s; }, get now() { return now; } };
}

describe('355 E deterministic content (cases 1-3,5)', () => {
  it('view and commands share generation; player/day change it without advancing shared RNG', () => {
    const x = scenario(); x.start();
    const site = mineSite(x.c, Q)!, key = x.s.mine.day!.key, rng = x.s.rng;
    const spec = floorSpec(x.c, site, 1, x.s.player, key), v = viewOf(x.c, x.s, x.now).mine.at!;
    expect(v.floor_state.mobs.map(m => m.kind)).toEqual(spec.mobs);
    expect(v.floor_state.rocks).toBe(spec.rocks); expect(x.s.rng).toBe(rng);
    const signature = (p: string, d: string) => Array.from({ length: 30 }, (_, i) => floorSpec(x.c, site, i + 1, p, d));
    expect(signature(x.s.player, key)).toEqual(signature(x.s.player, key));
    expect(signature('another', key)).not.toEqual(signature(x.s.player, key));
    expect(signature(x.s.player, '2026-11-03')).not.toEqual(signature(x.s.player, key));
  });
  it('honors quarry bands, specials, guard-only floors and HP multipliers', () => {
    const x = scenario(), site = mineSite(x.c, Q)!, type = x.c.mine.types.quarry;
    for (let n = 1; n <= site.mine.floors; n++) {
      const spec = floorSpec(x.c, site, n, 'p', '2026-11-02'), special = type.floors[n];
      if (special?.guard) expect(spec).toMatchObject({ mobs: [special.guard], rocks: 0, hpMult: special.hp_mult ?? 1 });
      else {
        const band = type.bands.find(b => b.from <= n && n <= b.to)!;
        for (const [kind, min, max] of band.mobs) {
          const size = spec.mobs.filter(m => m === kind).length;
          expect(size).toBeGreaterThanOrEqual(min); expect(size).toBeLessThanOrEqual(max);
        }
        expect(spec.rocks).toBeGreaterThanOrEqual(band.rocks[0]); expect(spec.rocks).toBeLessThanOrEqual(band.rocks[1]);
        if (special?.elite) expect(spec.mobs.at(-1)).toBe(special.elite);
      }
    }
    x.start(Q, 20);
    expect(viewOf(x.c, x.s, x.now).mine.at!.floor_state.mobs[0].max)
      .toBe(Math.ceil(x.c.mine.monsters.boss_slime_king.hp * type.floors['20'].hp_mult!));
  });
  it('vein F10 inherits prior rocks/drops, F20/F40 have guards and F41 is not open', () => {
    const x = scenario(), site = mineSite(x.c, V)!;
    const spec = floorSpec(x.c, site, 10, 'p', 'd'), band = x.c.mine.types.vein.bands[0];
    expect(spec.mobs).toEqual(x.c.mine.types.vein.floors['10'].only);
    expect(spec.rocks).toBeGreaterThanOrEqual(band.rocks[0]); expect(spec.rocks).toBeLessThanOrEqual(band.rocks[1]);
    expect(spec.drops).toEqual(expect.arrayContaining(band.drops));
    for (const n of [20, 40]) expect(floorSpec(x.c, site, n, 'p', 'd').guard).toBe(x.c.mine.types.vein.floors[n].guard);
    x.start(V, 40); expect(x.fail({ type: 'mine_floor', to: 41 })).toMatchObject({ code: 'bad_floor', detail: { max: 40, not_open: true } });
    expect(viewOf(x.c, x.s, x.now).mine.at!.next).toMatchObject({ floor: 41, locked: 'not_open', open: false });
    x.kill(0);
    expect(viewOf(x.c, x.s, x.now).mine.at!.next).toMatchObject({ floor: 41, locked: 'not_open', open: true });
    expect(x.fail({ type: 'mine_floor', to: 41 })).toMatchObject({ code: 'bad_floor', detail: { not_open: true } });
  });
  it('main ore second-band threshold follows the catalogue; torch counts match the deck', () => {
    const x = scenario(), site = structuredClone(mineSite(x.c, V)!); site.mine.main_from = 7;
    x.c.mine.types.vein.main_weight = [[1, 13], [10, 31]];
    const before = floorSpec(x.c, site, 6, 'p', 'd'), after = floorSpec(x.c, site, 7, 'p', 'd');
    expect(before.drops.find(([id]) => id === site.mine.main)![1]).toBe(x.c.mine.types.vein.main_weight![0][1]);
    expect(after.drops.find(([id]) => id === site.mine.main)![1]).toBe(x.c.mine.types.vein.main_weight![1][1]);
    x.start(); x.s.bag.push({ id: 'torch', qty: 1 }); x.send({ type: 'mine_torch', floor: 1 });
    const view = viewOf(x.c, x.s, x.now).mine.at!.floor_state;
    const deck = floorSpec(x.c, mineSite(x.c, Q)!, 1, x.s.player, x.s.mine.day!.key).deck;
    const counts = new Map<string, number>();
    for (const id of deck) if (id) counts.set(id, (counts.get(id) ?? 0) + 1);
    expect(view.deck).toEqual([...counts]); expect(view).not.toHaveProperty('preview');
    const drop = deck[0], r = x.send({ type: 'mine_rock', floor: 1, rock: 0 });
    expect(r.events).toContainEqual(expect.objectContaining({ kind: 'mine', action: 'rock', drop }));
    expect(r.events).toContainEqual({ kind: 'energy', delta: -x.c.mine.rock_energy, reason: 'mine_rock' });
    expect(x.fail({ type: 'mine_rock', floor: 1, rock: 0 })).toMatchObject({ code: 'rock_gone' });
  });
});

describe('355 E progression, fees and exits (cases 4,6-9,12a,15,18-19)', () => {
  it('requires all monsters defeated, never requires rocks, and allows immediate upward travel', () => {
    const x = scenario(); x.start();
    expect(x.fail({ type: 'mine_floor', to: 2 })).toMatchObject({ code: 'floor_locked', detail: { left: x.state().mobs.length } });
    for (let i = 0; i < x.state().mobs.length; i++) x.kill(i);
    expect(x.state().broken).toEqual([]);
    x.send({ type: 'mine_floor', to: 2 }); x.send({ type: 'mine_floor', to: 1 });
    expect(x.s.mine.records[Q].deepest).toBe(2);
  });
  it('opens empty layers immediately and rejects malformed or skipped floors', () => {
    const x = scenario(); x.c.mine.types.quarry.bands[0].mobs = []; x.start();
    expect(viewOf(x.c, x.s, x.now).mine.at!.next!.open).toBe(true);
    expect(x.fail({ type: 'mine_floor', to: 3 })).toMatchObject({ code: 'bad_floor' });
    expect(x.fail({ type: 'mine_floor', to: '2' })).toMatchObject({ code: 'bad_floor' });
    x.send({ type: 'mine_floor', to: 2 });
  });
  it('charges once per home day and keeps mine records independent', () => {
    const x = scenario(); x.c.mine.floor_energy = 7; x.c.mine.types.quarry.bands[0].mobs = [];
    expect(x.start().events).toContainEqual({ kind: 'energy', delta: -7, reason: 'mine_floor' });
    expect(x.send({ type: 'mine_floor', to: 2 }).events).toContainEqual({ kind: 'mine_record', mine: Q, deepest: 2 });
    expect(x.send({ type: 'mine_floor', to: 1 }).events.filter(e => e.kind === 'energy')).toEqual([]);
    notePresence(x.c, x.s, 'map', x.now, null);
    expect(x.start(V).events).toContainEqual({ kind: 'mine_record', mine: V, deepest: 1 });
    expect(viewOf(x.c, x.s, x.now).mine.rank).toBe(2);
    expect(x.s.mine.records[Q].deepest).toBe(2); expect(x.s.mine.records[V].deepest).toBe(1);
  });
  it('elevators offer only reached ten-floor stations and charge only the destination', () => {
    const x = scenario(); x.s.mine.records[Q] = { deepest: 23, guards: [10, 20], first_at: T }; x.start();
    expect(stations(x.s.mine.records[Q])).toEqual([10, 20]);
    const r = x.send({ type: 'mine_floor', to: 20, via: 'elevator' });
    expect(r.events.filter(e => e.kind === 'energy')).toEqual([{ kind: 'energy', delta: -x.c.mine.floor_energy, reason: 'mine_floor' }]);
    expect(x.fail({ type: 'mine_floor', to: 1, via: 'elevator' })).toMatchObject({ code: 'bad_floor' });
    x.send({ type: 'mine_floor', to: 19 });
    expect(x.fail({ type: 'mine_floor', to: 10, via: 'elevator' })).toMatchObject({ code: 'bad_floor' });
  });
  it('previews upward fees after an elevator jump, then reflects payment and the next day', () => {
    const x = scenario(); x.c.mine.floor_energy = 7;
    x.s.mine.records[Q] = { deepest: 20, guards: [10, 20], first_at: T };
    x.start(); expect(viewOf(x.c, x.s, x.now).mine.at!.prev).toBeNull();
    x.send({ type: 'mine_floor', to: 20, via: 'elevator' });
    expect(viewOf(x.c, x.s, x.now).mine.at!.prev).toEqual({ floor: 19, paid: false, fee: 7 });
    expect(x.send({ type: 'mine_floor', to: 19 }).events).toContainEqual({ kind: 'energy', delta: -7, reason: 'mine_floor' });
    for (let i = 0; i < x.state().mobs.length; i++) x.kill(i);
    x.send({ type: 'mine_floor', to: 20 });
    expect(viewOf(x.c, x.s, x.now).mine.at!.prev).toEqual({ floor: 19, paid: true, fee: 0 });
    expect(viewOf(x.c, x.s, x.now + DAY).mine.at!.prev).toEqual({ floor: 19, paid: false, fee: 7 });
  });
  it('departing heals living elites, retains ordinary damage/deaths; failed travel does not heal', () => {
    const x = scenario(); x.start(Q, 10);
    for (const to of [9, 8, 7, 6, 5]) x.send({ type: 'mine_floor', to });
    const hp = [...x.state().mobs], elite = hp.length - 1;
    x.send({ type: 'mine_attack', floor: 5, targets: [0, elite] }); x.kill(1);
    const ordinary = x.state().mobs[0];
    expect(x.fail({ type: 'mine_floor', to: 20, via: 'elevator' })).toMatchObject({ code: 'bad_floor' });
    expect(x.state().mobs[elite]).toBeLessThan(hp[elite]);
    x.send({ type: 'mine_floor', to: 4 });
    const saved = x.s.mine.day!.floors[`${Q}:5`];
    expect(saved.mobs[elite]).toBe(hp[elite]); expect(saved.mobs[0]).toBe(ordinary); expect(saved.mobs[1]).toBe(0);
  });
  it('cannot refill HP by Enter in place; an exit heals the guard and clears its hit timer', () => {
    const x = scenario(); x.start(Q, 10);
    x.send({ type: 'mine_attack', floor: 10, targets: [0], hurt_by: 0 });
    const hp = x.s.mine.day!.hp; expect(x.state().guard_hit_at).toBe(x.now);
    expect(x.fail({ type: 'mine_enter', mine: Q, floor: 10 })).toMatchObject({ code: 'not_here' });
    expect(x.s.mine.day!.hp).toBe(hp);
    notePresence(x.c, x.s, 'map', x.now, null);
    expect(x.s.mine.day!.floors[`${Q}:10`].guard_hit_at).toBeUndefined();
    x.send({ type: 'mine_enter', mine: Q, floor: 10 }); expect(x.state().mobs[0]).toBe(x.c.mine.monsters.boss_slime_king.hp);
  });
  it('records per-mine guards and per-kind first rewards, with no cleared guard respawn', () => {
    const x = scenario(), warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    try {
      x.start(Q, 10); x.kill(0);
      const kind = x.c.mine.types.quarry.floors['10'].guard!, def = x.c.mine.monsters[kind];
      expect(x.s.mine.records[Q].guards).toEqual([10]); expect(x.s.kills[kind]).toBe(1);
      expect(x.s.guard_firsts[kind]).toMatchObject({ mine: Q, floor: 10, home: x.s.travel.home });
      for (const [id, qty] of def.first!) expect(count(x.s.bag, id)).toBe(qty);
      expect(count(x.s.bag, 'copper_ore')).toBe(def.pack![1]);
      notePresence(x.c, x.s, 'map', x.now, null); x.send({ type: 'mine_enter', mine: Q, floor: 10 });
      expect(viewOf(x.c, x.s, x.now).mine.at!.floor_state).toMatchObject({ guard: null, mobs: [], cleared: true });
      notePresence(x.c, x.s, 'map', x.now, null); x.start(Q, 20); x.kill(0);
      for (const [id, qty] of def.first!) expect(count(x.s.bag, id)).toBe(qty);
      expect(count(x.s.bag, 'copper_ore')).toBe(def.pack![1] * 2); expect(x.s.kills[kind]).toBe(2);
      expect(x.s.mine.records[Q].guards).toEqual([10, 20]);
    } finally { warn.mockRestore(); }
  });
  it('rejects missing/closed/not-here sites, energy shortages and legacy commands atomically', () => {
    const x = scenario(), real = [...catalogue(x.c)!.byId.values()].find(site => site.open && site.type === 'quarry')!;
    expect(x.fail({ type: 'mine_enter', mine: 'missing' })).toMatchObject({ code: 'unknown_place' });
    expect(x.fail({ type: 'mine_enter', mine: real.id })).toMatchObject({ code: 'not_here' });
    real.open = false; expect(x.fail({ type: 'mine_enter', mine: real.id })).toMatchObject({ code: 'not_open' });
    x.s.energy.value = 0; x.s.energy.tick_ms = x.now;
    expect(x.fail({ type: 'mine_enter', mine: Q })).toMatchObject({ code: 'need_energy' });
    for (const type of ['mine_new_run', 'mine_express']) expect(x.fail({ type })).toMatchObject({ code: 'unknown_command' });
    delete x.c.mine.dev_sites; expect(x.fail({ type: 'mine_enter', mine: Q })).toMatchObject({ code: 'unknown_place' });
  });
  it('resolves the real C catalogue before dev fixtures and preserves its here id during mine commands', () => {
    const x = scenario(), site = [...catalogue(x.c)!.byId.values()].find(s => s.open && s.type === 'quarry')!;
    expect(wildById(x.c, site.id)?.mine?.main).toBeNull();
    expect(x.fail({ type: 'mine_enter', mine: site.id })).toMatchObject({ code: 'not_here' });
    x.s.travel.here = site.id;
    x.send({ type: 'mine_enter', mine: site.id });
    expect(x.s.travel.here).toBe(site.id);
    expect(viewOf(x.c, x.s, x.now).mine.at).toMatchObject({ mine: site.id, type: 'quarry', floor: 1 });
    x.send({ type: 'mine_attack', floor: 1, targets: [0] });
    expect(x.s.travel.here).toBe(site.id);
  });
});

describe('355 E reset and pickups (cases 12-14)', () => {
  it('outside daily reset clears the session and charges the next entry, without erasing records', () => {
    const x = scenario(); x.start(); notePresence(x.c, x.s, 'map', x.now, null);
    const now = x.now + DAY, before = structuredClone(x.s.mine.records);
    expect(viewOf(x.c, x.s, now).mine.at).toBeNull();
    const r = applyP0(x.c, x.s, { type: 'mine_enter', mine: Q }, now);
    expect(r.ok).toBe(true); if (!r.ok) return;
    expect(r.state.mine.records).toEqual(before);
    expect(r.state.mine.day!.key).toBe(dayKey(x.c, x.s, now));
    expect(r.events).toContainEqual({ kind: 'energy', delta: -x.c.mine.floor_energy, reason: 'mine_floor' });
  });
  it('a failed layer fee cannot heal an elite, move the player or clear pickups', () => {
    const x = scenario(); x.start(Q, 10); for (const to of [9, 8, 7, 6, 5]) x.send({ type: 'mine_floor', to });
    const elite = x.state().mobs.length - 1; x.send({ type: 'mine_attack', floor: 5, targets: [elite] });
    x.s.mine.day!.picked = [['coal', 5]]; x.s.energy.value = 0; x.s.energy.tick_ms = x.now;
    const before = structuredClone(x.s.mine);
    expect(x.fail({ type: 'mine_floor', to: 4 })).toMatchObject({ code: 'need_energy' });
    expect(x.s.mine).toEqual(before);
  });
  it('a new view of a cleared guard floor never resurrects it after daily reset', () => {
    const x = scenario(); x.start(Q, 10); x.kill(0);
    const v = viewOf(x.c, x.s, x.now + DAY).mine;
    expect(v.at!.floor_state).toMatchObject({ guard: null, mobs: [], cleared: true, paid: true });
    expect(v.at!.floor).toBe(10); expect(v.records[Q].guards).toEqual([10]);
  });
  it('day reset keeps the floor, refills HP (q(291)), rebuilds it paid and refuses stale commands without acting', () => {
    const x = scenario(); x.start(Q, 10); x.send({ type: 'mine_attack', floor: 10, targets: [0], hurt_by: 0 });
    expect(x.s.mine.day!.hp).toBeLessThan(x.c.mine.combat.hp);
    const input = structuredClone(x.s), now = x.now + DAY, v = viewOf(x.c, input, now).mine;
    expect(input).toEqual(x.s);
    expect(v.at).toMatchObject({ floor: 10, hp: x.c.mine.combat.hp, day: dayKey(x.c, x.s, now) });
    expect(v.at!.floor_state.paid).toBe(true); expect(v.at!.floor_state.mobs[0].hp).toBe(x.c.mine.monsters.boss_slime_king.hp);
    expect(v.notice).toMatchObject({ kind: 'reset', floor: 10 });
    const r = applyP0(x.c, input, { type: 'mine_attack', day: x.s.mine.day!.key, floor: 10, targets: [0], space: 'mine' }, now);
    expect(r).toMatchObject({ ok: false, code: 'new_day' });
    if (r.ok) throw new Error('old command accepted');
    expect(r.state!.seq).toBe(input.seq); expect(r.state!.mine.day!.picked).toEqual([]);
    expect(r.state!.mine.day!.floors[`${Q}:10`].guard_hit_at).toBeUndefined(); expect(mineView(x.c, r.state!, now)).toEqual(v);
    expect(applyP0(x.c, input, { type: 'mine_rock', floor: 10, rock: 0 } as P0Command, now)).toMatchObject({ code: 'new_day' });
  });
  it.each([10, 20])('KO on floor %i loses only this-entry bag pickups by configured threshold/share', floor => {
    const x = scenario(); x.start(Q, floor); x.s.mine.day!.hp = 1;
    x.s.bag = [{ id: 'coal', qty: 9 }, { id: 'iron_ore', qty: 1 }, { id: 'wood', qty: 20 }];
    x.s.mine.day!.picked = [['coal', 5], ['iron_ore', 7]]; x.send({ type: 'mine_attack', floor, hurt_by: 0 });
    const n = floor >= x.c.mine.combat.ko_keep_from ? Math.floor(5 * x.c.mine.combat.ko_lose) : 0;
    expect(count(x.s.bag, 'coal')).toBe(9 - n); expect(count(x.s.bag, 'wood')).toBe(20);
    expect(x.s.mine.day!.at).toBeNull(); expect(x.s.mine.day!.hp).toBe(x.c.mine.combat.ko_hp);   // q(291): 30, not full
    expect(x.s.mine.notice).toMatchObject({ kind: 'ko', floor }); expect(x.s.mine.day!.picked).toEqual([]);
    expect(x.s.mine.day!.floors[`${Q}:${floor}`].paid).toBe(true);
  });
  it('once-a-day loot limits by kind while lifetime kills continue', () => {
    const x = scenario(); x.c.mine.monsters.mob_test = { name: 'Test', hp: 1, damage: 1, once_a_day: 'coal', loot: [['coal', 1, 100]] };
    x.c.mine.types.quarry.bands[0].mobs = [['mob_test', 2, 2]]; x.start(); x.kill(0); x.kill(1);
    expect(count(x.s.bag, 'coal')).toBe(1); expect(x.s.day.once.mob_test).toBe(1); expect(x.s.kills.mob_test).toBe(2);
    expect(x.c.mine.monsters.mob_elite_slime.loot!.every(([id]) => id !== 'quartz')).toBe(true);
  });
  it('rocks honor next-card bag space, sequence retries and swing tempo', () => {
    const x = scenario(); x.c.mine.types.quarry.bands[0].rocks = [6, 6]; x.start(); x.s.gear.pick = 'pick_copper';
    const site = mineSite(x.c, Q)!, expected = rockDrops(x.c, x.s, site, 1, 0), seq = x.s.seq;
    x.send({ type: 'mine_rock', floor: 1, rock: 0, expect_seq: seq });
    expect(count(x.s.bag, 'stone')).toBe(x.c.mine.picks.pick_copper.stone + expected.filter(id => id === 'stone').length);
    expect(x.fail({ type: 'mine_rock', floor: 1, rock: 0, expect_seq: seq })).toMatchObject({ code: 'stale_state' });
    // tempo_burst 2: two more at once, then the next waits a whole 0.9 s
    x.again({ type: 'mine_rock', floor: 1, rock: 1 }); x.again({ type: 'mine_rock', floor: 1, rock: 2 });
    expect(x.fail({ type: 'mine_rock', floor: 1, rock: 3 })).toMatchObject({ code: 'tempo', detail: { ready_in: 900 } });
    x.s.bag = [{ id: 'stone', qty: 99 }]; x.s.bag_cap = 1;
    expect(bagFitsFloor(x.c, x.s, site, 1, x.s.mine.day!.key)).toBe(false);
  });
});

describe('355 E combat settlement needed for clear-to-descend (F cases 10-11)', () => {
  it.each(['weapon_wooden_sword', 'weapon_copper_sword', 'weapon_iron_sword'])('uses content damage and ceil under-tier multiplier for %s', id => {
    const x = scenario(); x.s.gear.weapon = id; x.s.gear.weapons.push(id); x.c.mine.combat.under_tier = 0.4;
    x.start(V, 20);
    const before = x.state().mobs[0], w = x.c.mine.combat.weapons[id];
    x.send({ type: 'mine_attack', floor: 20, targets: [0] });
    const boss = x.c.mine.monsters[x.c.mine.types.vein.floors['20'].guard!];
    expect(before - x.state().mobs[0]).toBe(w.tier < boss.tier! ? Math.max(1, Math.ceil(w.attack * 0.4)) : w.attack);
  });
  it('stun only amplifies an eligible monster in this swing, caps targets and preserves untargeted HP', () => {
    const x = scenario(); x.c.mine.types.quarry.bands[0].mobs = [['mob_rock_beetle', 5, 5], ['mob_slime', 1, 1]];
    x.start(); const hp = [...x.state().mobs], dmg = x.c.mine.combat.weapons[x.s.gear.weapon].attack;
    x.send({ type: 'mine_attack', floor: 1, targets: [0, 1, 2, 3, 4, 5], stunned: [0, 4, 5, -1, 999] });
    expect(x.state().mobs[0]).toBe(hp[0] - dmg * x.c.mine.monsters.mob_rock_beetle.stun_mult!);
    for (const i of [1, 2, 3]) expect(x.state().mobs[i]).toBe(hp[i] - dmg);
    expect(x.state().mobs.slice(4)).toEqual(hp.slice(4));
    x.send({ type: 'mine_attack', floor: 1, targets: [5], stunned: [5] });
    expect(x.state().mobs[5]).toBe(hp[5] - dmg);
  });
  it('rejects duplicate/invalid/dead targets, enforces swing tempo and independent hurt invulnerability', () => {
    const x = scenario(); x.c.mine.monsters.mob_slime.hp = 99; x.start();
    expect(x.fail({ type: 'mine_attack', floor: 1, targets: [0, 0] })).toMatchObject({ code: 'bad_target' });
    expect(x.fail({ type: 'mine_attack', floor: 1, targets: [-1] })).toMatchObject({ code: 'bad_target' });
    expect(x.fail({ type: 'mine_attack', floor: 2, targets: [0] })).toMatchObject({ code: 'bad_floor' });
    x.send({ type: 'mine_attack', floor: 1, targets: [0], hurt_by: 0 });
    const hp = x.s.mine.day!.hp;
    x.again({ type: 'mine_attack', floor: 1, targets: [0] }); x.again({ type: 'mine_attack', floor: 1, targets: [0] });
    expect(x.fail({ type: 'mine_attack', floor: 1, targets: [0] })).toMatchObject({ code: 'tempo' });
    const noHurt = applyP0(x.c, x.s, { type: 'mine_attack', day: x.s.mine.day!.key, floor: 1, hurt_by: 0, space: 'mine' }, x.now);
    expect(noHurt.ok).toBe(true); if (noHurt.ok) expect(noHurt.state.mine.day!.hp).toBe(hp);
    x.kill(0); expect(x.fail({ type: 'mine_attack', floor: 1, targets: [0] })).toMatchObject({ code: 'mob_gone' });
  });
  it('a lethal swing wins a simultaneous hit, leaves overflow on the floor and counts the kill once', () => {
    const x = scenario(); x.c.mine.monsters.mob_slime.hp = x.c.mine.combat.weapons.weapon_wooden_sword.attack;
    x.c.mine.monsters.mob_slime.loot = [['copper_ore', 2, 100]]; x.start();
    x.s.bag = [{ id: 'seed_radish', qty: 99 }]; x.s.bag_cap = 1; x.s.mine.day!.hp = 1;
    x.send({ type: 'mine_attack', floor: 1, targets: [0], hurt_by: 0 });
    expect(x.s.mine.day!.hp).toBe(1); expect(x.s.mine.day!.at).not.toBeNull();
    expect(x.s.storage.copper_ore ?? 0).toBe(0); expect(x.s.mine.day!.picked).toEqual([]); expect(x.s.kills.mob_slime).toBe(1);
    expect(x.state().ground).toEqual([{ id: 1, item: 'copper_ore', qty: 2, from: 0 }]);
  });
  it('guard first-hit time survives a state round-trip, only suspicious kills produce the diagnostic', () => {
    const x = scenario(), warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    try {
      x.start(Q, 10); x.send({ type: 'mine_attack', floor: 10, targets: [0] });
      expect(JSON.parse(JSON.stringify(x.s)).mine.day.floors[`${Q}:10`].guard_hit_at).toBe(x.now);
      x.state().mobs[0] = 1; // simulate an impossibly fast damaged snapshot, never accept a client HP value
      x.send({ type: 'mine_attack', floor: 10, targets: [0] });
      expect(warn).toHaveBeenCalledOnce(); expect(JSON.parse(warn.mock.calls[0][0])).toMatchObject({ kind: 'guard_fast', mine: Q, floor: 10 });
      expect(x.s.mine.records[Q].guards).toEqual([10]);
    } finally { warn.mockRestore(); }
  });
});

describe('355 E v0.5 rock deck, ground and first acquisitions (cases 5,14,15a,15b)', () => {
  it('different rock choices deal the same card order and torch counts only the remaining cards', () => {
    const x = scenario(), y = scenario(); x.start(); y.start();
    const site = mineSite(x.c, Q)!, spec = floorSpec(x.c, site, 1, x.s.player, x.s.mine.day!.key);
    x.s.bag.push({ id: 'torch', qty: 1 }); x.send({ type: 'mine_torch', floor: 1 });
    for (let k = 0; k < spec.rocks; k++) {
      const a = x.send({ type: 'mine_rock', floor: 1, rock: k });
      const b = y.send({ type: 'mine_rock', floor: 1, rock: spec.rocks - k - 1 });
      expect(a.events.filter(e => e.kind === 'item')).toEqual(b.events.filter(e => e.kind === 'item'));
      // q(292): the k-th rock broken deals cards 2k and 2k + 1
      expect(a.events).toContainEqual(expect.objectContaining({ kind: 'mine', action: 'rock', drops: spec.deck.slice(2 * k, 2 * k + 2) }));
      const counts = new Map<string, number>();
      for (const id of spec.deck.slice(2 * k + 2)) if (id) counts.set(id, (counts.get(id) ?? 0) + 1);
      expect(viewOf(x.c, x.s, x.now).mine.at!.floor_state.deck).toEqual([...counts]);
    }
    expect(x.s.firsts.filter(id => id === 'loot:stone')).toHaveLength(1);
  });
  it('a full bag allows entry and descent, but refuses the entire next rock card without a partial grant', () => {
    const x = scenario(); x.c.mine.types.quarry.bands[0].mobs = [];
    x.c.mine.types.quarry.bands[0].drops = [['copper_ore', 1]];
    x.s.bag = [{ id: 'stone', qty: 98 }]; x.s.bag_cap = 1;
    x.start(); const before = structuredClone(x.s);
    expect(x.fail({ type: 'mine_rock', floor: 1, rock: 0 })).toMatchObject({ code: 'bag_full' });
    expect(x.s).toEqual(before); x.send({ type: 'mine_floor', to: 2 });
    expect(x.s.mine.day!.at!.floor).toBe(2);
  });
  it('ground is collectible once, stays while full, and only acquisition records firsts and KO pickups', () => {
    const x = scenario(); x.c.mine.monsters.mob_slime.hp = 1; x.c.mine.monsters.mob_slime.loot = [['coal', 3, 100]];
    x.s.bag = [{ id: 'seed_radish', qty: 99 }]; x.s.bag_cap = 1; x.start(); x.kill(0);
    expect(x.s.firsts).not.toContain('loot:coal'); expect(x.s.mine.day!.picked).toEqual([]);
    const g = x.state().ground[0];
    expect(x.fail({ type: 'mine_pick', floor: 1, ground: g.id })).toMatchObject({ code: 'bag_full' });
    x.s.bag = []; x.send({ type: 'mine_pick', floor: 1, ground: g.id });
    expect(count(x.s.bag, 'coal')).toBe(g.qty); expect(x.state().ground).toEqual([]);
    expect(x.s.firsts.filter(id => id === 'loot:coal')).toHaveLength(1);
    expect(x.s.mine.day!.picked).toEqual([['coal', g.qty]]);
    expect(x.fail({ type: 'mine_pick', floor: 1, ground: g.id })).toMatchObject({ code: 'no_item' });
  });
  it.each(['up', 'elevator', 'exit', 'ko', 'day'])('ground is discarded on %s and never reaches storage/inbox', how => {
    const x = scenario(); x.c.mine.types.quarry.floors['10'] = { only: ['mob_slime', 'mob_slime'] };
    x.c.mine.monsters.mob_slime.hp = 1; x.c.mine.monsters.mob_slime.loot = [['coal', 3, 100]];
    x.s.bag = [{ id: 'seed_radish', qty: 99 }]; x.s.bag_cap = 1; x.start(Q, 10); x.kill(0);
    expect(x.state().ground).toHaveLength(1);
    if (how === 'up') x.send({ type: 'mine_floor', to: 9 });
    if (how === 'elevator') { x.s.mine.records[Q].deepest = 20; x.send({ type: 'mine_floor', to: 20, via: 'elevator' }); }
    if (how === 'exit') notePresence(x.c, x.s, 'map', x.now, null);
    if (how === 'ko') { x.s.mine.day!.hp = 1; x.send({ type: 'mine_attack', floor: 10, hurt_by: 1 }); }
    if (how === 'day') expect(viewOf(x.c, x.s, x.now + DAY).mine.at!.floor_state.ground).toEqual([]);
    else expect(x.s.mine.day!.floors[`${Q}:10`].ground).toEqual([]);
    expect(x.s.storage.coal ?? 0).toBe(0); expect(x.s.inbox.parcels).toEqual([]);
  });
  it('a defeated elite never respawns that day after exit/reentry', () => {
    const x = scenario(); x.start(Q, 10);
    for (const to of [9, 8, 7, 6, 5]) x.send({ type: 'mine_floor', to });
    const elite = x.state().mobs.length - 1; x.kill(elite);
    const copper = count(x.s.bag, 'copper_ore');
    notePresence(x.c, x.s, 'map', x.now, null); x.send({ type: 'mine_enter', mine: Q, floor: 10 });
    for (const to of [9, 8, 7, 6, 5]) x.send({ type: 'mine_floor', to });
    expect(x.state().mobs[elite]).toBe(0);
    expect(x.fail({ type: 'mine_attack', floor: 5, targets: [elite] })).toMatchObject({ code: 'mob_gone' });
    expect(count(x.s.bag, 'copper_ore')).toBe(copper);
  });
  it('quarry guard pack uses explicit copper even when C supplies main:null', () => {
    const x = scenario(); mineSite(x.c, Q)!.mine.main = null;
    x.start(Q, 10); x.kill(0);
    const pack = x.c.mine.monsters.boss_slime_king.pack!;
    expect(count(x.s.bag, pack[0])).toBe(pack[1]);
  });
});

describe('view.mine.paid_today: the floors paid for today, out of the mine too (LOCK-21, 亚瑟 for the mine card)', () => {
  it('lists each mine\'s paid floors, keeps them after leaving, makes F1 free again, and empties at the rollover', () => {
    const x = scenario();
    const paid = () => (viewOf(x.c, x.s, x.now).mine as unknown as { paid_today: Record<string, number[]> }).paid_today;
    expect(paid()).toEqual({});
    x.start();
    expect(paid()).toEqual({ [Q]: [1] });
    for (let i = 0; i < x.state().mobs.length; i++) x.kill(i);
    x.send({ type: 'mine_floor', floor: 1, to: 2 });
    expect(paid()).toEqual({ [Q]: [1, 2] });
    x.send({ type: 'talk', resident: 'res_pip', space: 'home' });   // out of the mine
    expect(x.s.mine.day!.at).toBeNull();
    expect(paid()).toEqual({ [Q]: [1, 2] });
    const energy = x.s.energy.value;
    const again = x.send({ type: 'mine_enter', mine: Q });
    expect(again.events.some(e => e.kind === 'energy' && e.delta < 0)).toBe(false);   // `Enter mine · Free`
    expect(x.s.energy.value).toBeGreaterThanOrEqual(energy);
    x.send({ type: 'talk', resident: 'res_pip', space: 'home' });
    expect((viewOf(x.c, x.s, x.now + DAY).mine as unknown as { paid_today: Record<string, number[]> }).paid_today).toEqual({});
  });
});

describe('view.mine.records: each record says its mine\'s type and main (v4q(9) ①, 亚瑟 on #711)', () => {
  it('a quarry and a vein say theirs; a mine no longer known says null; the save keeps no new field', () => {
    const x = scenario();
    x.s.mine.records[Q] = { deepest: 3, guards: [], first_at: T };
    x.s.mine.records[V] = { deepest: 12, guards: [10], first_at: T };
    x.s.mine.records['wd-gone'] = { deepest: 5, guards: [], first_at: T };
    const records = (viewOf(x.c, x.s, x.now).mine as unknown as { records: Record<string, unknown> }).records;
    expect(records[Q]).toEqual({ deepest: 3, guards: [], type: 'quarry', main: 'copper_ore' });
    expect(records[V]).toEqual({ deepest: 12, guards: [10], type: 'vein', main: 'iron_ore' });
    expect(records['wd-gone']).toEqual({ deepest: 5, guards: [], type: null, main: null });
    expect(Object.keys(x.s.mine.records[V]).sort()).toEqual(['deepest', 'first_at', 'guards']);
  });
});

describe('preview B on a slow line (奕星 11-05: swings that hit took no HP)', () => {
  const swing = (targets: number[], extra: Record<string, unknown> = {}) => ({ type: 'mine_attack', floor: 1, targets, ...extra });
  it('a swing passes over a monster already down and hits the rest; one naming only the fallen is mob_gone', () => {
    const x = scenario(); x.c.mine.types.quarry.bands[0].mobs = [['mob_slime', 2, 2]]; x.c.mine.monsters.mob_slime.hp = 99;
    x.start(); x.kill(0);
    const dmg = x.c.mine.combat.weapons[x.s.gear.weapon].attack, before = x.state().mobs[1];
    const r = x.send(swing([0, 1]));
    expect(x.state().mobs[1]).toBe(before - dmg);
    expect(r.events.filter(e => e.kind === 'mine' && e.action === 'hit')).toEqual([expect.objectContaining({ mob: 1, damage: dmg })]);
    // its hurt_by gone too: the swing still lands, no HP lost to the fallen one
    const hp = x.s.mine.day!.hp;
    x.send(swing([1], { hurt_by: 0 }));
    expect([x.state().mobs[1], x.s.mine.day!.hp]).toEqual([before - 2 * dmg, hp]);
    expect(x.fail(swing([0]))).toMatchObject({ code: 'mob_gone' });
    expect(x.fail({ type: 'mine_attack', floor: 1, hurt_by: 0 })).toMatchObject({ code: 'mob_gone' });
  });
  it('tempo_burst swings may come ahead of their slot, then a whole interval; never faster on average', () => {
    const x = scenario(); x.c.mine.monsters.mob_slime.hp = 9999; x.start();
    const w = x.c.mine.combat.weapons[x.s.gear.weapon], interval = 1000 / w.speed * x.c.mine.rules.attack_tempo_factor;
    expect(x.c.mine.rules.tempo_burst).toBe(2);
    x.send(swing([0])); x.again(swing([0])); x.again(swing([0]));
    expect(x.fail(swing([0]))).toMatchObject({ code: 'tempo', detail: { ready_in: Math.ceil(interval) } });
    // hammered every 100 ms for 30 s: one per interval, the burst once
    const c = x.c, start = x.now + 5000;
    let s = x.s, ok = 0;
    for (let t = start; t < start + 30_000; t += 100) {
      const r = applyP0(c, s, { space: 'mine', day: dayKey(c, s, t), ...swing([0]) } as P0Command, t);
      if (r.ok) { ok++; s = r.state; } else expect(r.code).toBe('tempo');
    }
    expect(ok).toBe(Math.floor(30_000 / interval) + 3);
  });
  it('swings spaced at the client cooldown over a 100–800 ms round trip with stalls: every one lands (none did before)', () => {
    // P0Session posts one command at a time, the next when the last reply is back; the line's two legs each 50–400 ms,
    // every seventh uplink held 1.2 s more (a lost packet's resend).
    const run = (burst: number | undefined) => {
      const x = scenario(); x.c.mine.monsters.mob_slime.hp = 9999; x.c.mine.rules.tempo_burst = burst; x.start();
      const c = x.c, cooldown = 1000 / c.mine.combat.weapons[x.s.gear.weapon].speed, t0 = x.now + 5000;
      let s = x.s, seed = 7, back = t0, refused = 0;
      const leg = () => { seed = (seed * 1103515245 + 12345) % 2 ** 31; return 50 + seed % 351; };
      for (let k = 0; k < 120; k++) {
        const press = t0 + k * cooldown, arrive = Math.max(press, back) + leg() + (k % 7 === 3 ? 1200 : 0);
        const r = applyP0(c, s, { space: 'mine', day: dayKey(c, s, arrive), ...swing([0]) } as P0Command, arrive);
        if (r.ok) s = r.state; else { expect(r.code).toBe('tempo'); refused++; }
        back = arrive + leg();
      }
      return refused;
    };
    expect(run(undefined)).toBeGreaterThan(5);   // the strict tempo: swings the client spaced right, refused
    expect(run(2)).toBe(0);
  });
});

describe('q(292) fewer, bigger rocks (SGODOT-421)', () => {
  it('every ordinary band of both kinds has 2–3 rocks, a guard floor none; each rock deals two cards', () => {
    const c = loadP0Content();
    expect(c.mine.rules.rock_cards).toBe(2);
    for (const [kind, type] of Object.entries(c.mine.types)) {
      for (const band of type.bands) expect([kind, band.from, band.rocks]).toEqual([kind, band.from, [2, 3]]);
      const site = mineSite(c, kind === 'quarry' ? Q : V)!, seen = new Set<number>();
      let cards = 0, floors = 0;
      for (let n = 1; n <= Math.min(site.mine.floors, site.mine.open_to ?? site.mine.floors); n++) for (let p = 0; p < 40; p++) {
        const spec = floorSpec(c, site, n, `rocks-${p}`, '2026-11-05');
        if (type.floors[String(n)]?.guard) { expect([spec.rocks, spec.deck.length]).toEqual([0, 0]); continue; }
        expect(spec.deck.length).toBe(spec.rocks * 2);
        seen.add(spec.rocks); cards += spec.deck.length; floors++;
      }
      expect([...seen].sort()).toEqual([2, 3]);
      expect(cards / floors).toBeGreaterThan(4.6); expect(cards / floors).toBeLessThan(5.4);   // a floor's cards as before: 4–6, 5 on average
    }
  });
  it("a rock gives the pick's stone once and its own two cards; the torch shows the cards still in the rocks", () => {
    const x = scenario(); x.c.mine.types.quarry.bands[0].mobs = [['mob_slime', 1, 1]]; x.start(); x.s.gear.pick = 'pick_copper';
    const site = mineSite(x.c, Q)!, spec = floorSpec(x.c, site, 1, x.s.player, x.s.mine.day!.key);
    x.s.bag = []; x.s.bag_cap = 25; x.s.bag.push({ id: 'torch', qty: 1 });
    x.send({ type: 'mine_torch', floor: 1 });
    const r = x.send({ type: 'mine_rock', floor: 1, rock: 1 });
    const rock = r.events.find(e => e.kind === 'mine' && e.action === 'rock')!;
    expect(rock).toMatchObject({ drops: spec.deck.slice(0, 2), drop: spec.deck[0] });
    const gained = (id: string) => r.events.filter(e => e.kind === 'item' && e.id === id).reduce((n, e) => n + (e.kind === 'item' ? e.delta : 0), 0);
    expect(gained('stone')).toBe(x.c.mine.picks.pick_copper.stone + spec.deck.slice(0, 2).filter(id => id === 'stone').length);
    for (const id of new Set(spec.deck.slice(0, 2).filter(id => id && id !== 'stone') as string[]))
      expect(gained(id)).toBe(spec.deck.slice(0, 2).filter(d => d === id).length);
    // the second rock broken deals cards 2 and 3, whichever rock it is
    expect(rockDrops(x.c, x.s, site, 1, 1)).toEqual(spec.deck.slice(2, 4));
    const left = new Map<string, number>();
    for (const id of spec.deck.slice(2)) if (id) left.set(id, (left.get(id) ?? 0) + 1);
    expect(new Map(mineView(x.c, x.s, x.now).at!.floor_state.deck!)).toEqual(left);
  });
  it('a floor broken further today, before q(292), reads none left, not below 0 (亚瑟 on #772)', () => {
    const x = scenario(); x.start(); const site = mineSite(x.c, Q)!, spec = floorSpec(x.c, site, 1, x.s.player, x.s.mine.day!.key);
    x.state().broken = [0, 1, 2, 3, 4];   // five broken under the old 4–6
    expect(mineView(x.c, x.s, x.now).at!.floor_state).toMatchObject({ rocks: spec.rocks, left: 0 });
    expect(bagFitsFloor(x.c, x.s, site, 1, x.s.mine.day!.key)).toBe(true);
    expect(x.fail({ type: 'mine_rock', floor: 1, rock: spec.rocks })).toMatchObject({ code: 'bad_rock' });
  });
  it('a full bag stops a rock when either of its two cards has no room', () => {
    // a player whose first rock deals two different cards, neither of them stone
    let x = scenario(), spec = floorSpec(x.c, mineSite(x.c, Q)!, 1, 'p', '2026-11-02');
    for (let p = 0; ; p++) {
      x = scenario(); x.s.player = `q292-bag-${p}`; x.start();
      spec = floorSpec(x.c, mineSite(x.c, Q)!, 1, x.s.player, x.s.mine.day!.key);
      const [a, b] = spec.deck;
      if (a && b && a !== b && a !== 'stone' && b !== 'stone') break;
      if (p > 500) throw new Error('no such player');
    }
    const site = mineSite(x.c, Q)!, [a, b] = spec.deck as string[], fits = () => bagFitsFloor(x.c, x.s, site, 1, x.s.mine.day!.key);
    const stack = (id: string) => room(x.c, { bag: [], bag_cap: 1, skills: x.s.skills }, id);
    // three slots, each with room for exactly what the rock gives: it fits
    const full = (qa: number, qb: number) => {
      x.s.bag_cap = 3;
      x.s.bag = [{ id: 'stone', qty: stack('stone') - x.c.mine.picks[x.s.gear.pick].stone }, { id: a, qty: qa }, { id: b, qty: qb }];
    };
    full(stack(a) - 1, stack(b) - 1); expect(fits()).toBe(true);
    full(stack(a), stack(b) - 1); expect(fits()).toBe(false);   // the first card has no room
    full(stack(a) - 1, stack(b)); expect(fits()).toBe(false);   // the second card has no room
    expect(x.fail({ type: 'mine_rock', floor: 1, rock: 0 })).toMatchObject({ code: 'bag_full' });
  });
});
