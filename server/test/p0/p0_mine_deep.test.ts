/** SGODOT-275: mine floors 3–5 (§13.3.2–13.3.4, §13.3.9), fighting, Express, the elite's quartz once a day and quartz in
 * floors 2–4. Floors 1–2 and gathering are in p0_material_chain.test.ts. */
import { describe, expect, it } from 'vitest';
import { add, count } from '../../src/p0/bag.js';
import { loadP0Content } from '../../src/p0/content.js';
import { floorCleared, mobLoot, rockDrop } from '../../src/p0/mine.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { dayKey } from '../../src/p0/rules.js';
import { viewOf } from '../../src/p0/view.js';

const content = loadP0Content();
const c = { ...content, profile: { ...content.profile, timezone: 'Asia/Shanghai' } };
const T0 = Date.UTC(2026, 9, 8, 2, 0, 0);   // 10:00 Shanghai
const H = 3_600_000;
const STEP = 1_000;   // past the 0.9 s rock tempo and the 0.5 s swing
const IN = { space: 'mine' } as const;

const fresh = (player = 'player-deep-01') => {
  const s = { ...freshState(c, player, T0, 7), created_at: T0 - 8 * 24 * H };
  s.energy.value = 250;
  s.bag = [];   // room for a whole run's Stone and drops
  return s;
};
function step(s: P0State, cmd: P0Command, now: number): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
function refuse(s: P0State, cmd: P0Command, now: number) {
  const r = applyP0(c, s, cmd, now);
  if (r.ok) throw new Error(`${cmd.type} was accepted`);
  return { code: r.code, detail: r.detail };
}
const spent = (ev: P0Event[]) => ev.filter(e => e.kind === 'energy').reduce((n, e) => n + (e.kind === 'energy' ? -e.delta : 0), 0);
const mine = (ev: P0Event[], action: string) => ev.filter(e => e.kind === 'mine' && e.action === action);

/** Break every rock on a floor; keep the bag empty so floors never stop on Bag full. */
function clear(s: P0State, floor: number, t: number) {
  let n = 0;
  for (let rock = 0; rock < 6; rock++) {
    const r = step(s, { type: 'mine_rock', floor, rock, ...IN }, t += STEP);
    s = r.s; n += spent(r.ev); s.bag = [];
  }
  return { s, t, spent: n };
}
/** From the mouth down to `to`, clearing floors 1..to-1 on the way. */
function descend(s: P0State, to: number, t: number) {
  let r = step(s, { type: 'mine_enter' }, t += STEP); s = r.s; let n = spent(r.ev);
  for (let f = 1; f < to; f++) {
    const cl = clear(s, f, t); s = cl.s; t = cl.t; n += cl.spent;
    r = step(s, { type: 'mine_floor', floor: f + 1, ...IN }, t += STEP); s = r.s; n += spent(r.ev);
  }
  return { s, t, spent: n };
}
/** Swing at one monster until it is down; the swing cooldown is 0.5 s. */
function kill(s: P0State, floor: number, mob: number, t: number) {
  const all: P0Event[] = [];
  while (s.mine.run && (s.mine.run.floors[floor - 1].mobs?.[mob] ?? 0) > 0) {
    const r = step(s, { type: 'mine_attack', floor, targets: [mob], ...IN }, t += STEP);
    s = r.s; all.push(...r.ev);
  }
  return { s, t, ev: all };
}

describe('mine floors 3–5 (§13.3.2)', () => {
  it('floor 3 has one slime, floor 4 three, floor 5 only the elite and no rocks; the view lists them', () => {
    const { s } = step(fresh(), { type: 'mine_enter' }, T0);
    const floors = viewOf(c, s, T0).mine.run!.floors;
    expect(floors.map(f => f.rocks)).toEqual([6, 6, 6, 6, 0]);
    expect(floors.map(f => f.mobs.map(m => m.kind))).toEqual([[], [], ['mob_slime'], ['mob_slime', 'mob_slime', 'mob_slime'], ['mob_elite_slime']]);
    expect(floors[4].mobs[0]).toEqual({ kind: 'mob_elite_slime', hp: 36, max: 36 });
    expect(viewOf(c, s, T0).mine.floors).toBe(5);
  });

  it('a B run (floors 1 → 4, 24 rocks) costs 56 Energy and walking on to floor 5 makes it 58 (§13.3.5)', () => {
    let { s, t, spent: n } = descend(fresh(), 4, T0);
    const cl = clear(s, 4, t); s = cl.s; t = cl.t; n += cl.spent;
    expect(n).toBe(56);
    const r = step(s, { type: 'mine_floor', floor: 5, ...IN }, t += STEP);
    expect(n + spent(r.ev)).toBe(58);
  });

  it('floors 3–4 clear by their rocks with the slimes left alive; floor 4 needs floor 3 cleared', () => {
    let { s, t } = descend(fresh(), 3, T0);
    expect(refuse(s, { type: 'mine_floor', floor: 4, ...IN }, t + STEP)).toEqual({ code: 'clear_floor_first', detail: { floor: 3 } });
    ({ s, t } = clear(s, 3, t));
    expect(floorCleared(c, s.mine.run!, 3)).toBe(true);
    expect(s.mine.run!.floors[2].mobs).toEqual([9]);
    expect(step(s, { type: 'mine_floor', floor: 4, ...IN }, t + STEP).s.mine.run!.floors[3].paid).toBe(true);
  });

  it('floor 5 has no rocks: Mine and a torch are refused there', () => {
    let { s, t } = descend(fresh(), 4, T0);
    ({ s, t } = clear(s, 4, t));
    s = step(s, { type: 'mine_floor', floor: 5, ...IN }, t += STEP).s;
    add(c, s, 'torch', 1);
    expect(refuse(s, { type: 'mine_rock', floor: 5, rock: 0, ...IN }, t + STEP).code).toBe('no_rocks');
    expect(refuse(s, { type: 'mine_torch', floor: 5, ...IN }, t + STEP).code).toBe('no_rocks');
  });

  it('floors 2–4 give quartz (15 / 15 / 20), floor 1 never does (§13.3.3)', () => {
    const { s } = step(fresh(), { type: 'mine_enter' }, T0);
    const run = s.mine.run!;
    const share = (floor: number) => {
      let q = 0;
      for (let seed = 0; seed < 3000; seed++) if (rockDrop(c, s, { ...run, seed }, floor, seed % 6) === 'quartz') q++;
      return Math.round(q / 30);
    };
    expect(share(1)).toBe(0);
    expect(Math.abs(share(2) - 15)).toBeLessThanOrEqual(3);
    expect(Math.abs(share(3) - 15)).toBeLessThanOrEqual(3);
    expect(Math.abs(share(4) - 20)).toBeLessThanOrEqual(3);
  });
});

describe('fighting (§13.3.4, §13.3.8)', () => {
  it('the Wooden Sword (3) takes a slime in 3 swings; fighting is 0 Energy; the kill drops loot', () => {
    let { s, t } = descend(fresh(), 3, T0);
    const energy = s.energy.value;
    const k = kill(s, 3, 0, t);
    expect(mine(k.ev, 'hit').length).toBe(3);
    expect(k.s.energy.value).toBe(energy);
    const defeat = mine(k.ev, 'defeat')[0];
    expect(defeat).toMatchObject({ mob: 0, mob_kind: 'mob_slime' });
    const [id, qty] = (defeat as { loot: [string, number] }).loot;
    expect(['copper_ore', 'rock_salt', 'bait_worm']).toContain(id);
    expect(count(k.s.bag, id)).toBe(qty);
    expect(k.s.mine.run!.floors[2].mobs).toEqual([0]);
  });

  it('a swing faster than the weapon allows, a dead or unknown target, and a swing with nothing are refused', () => {
    let { s, t } = descend(fresh(), 4, T0);
    s = step(s, { type: 'mine_attack', floor: 4, targets: [0], ...IN }, t += STEP).s;
    expect(refuse(s, { type: 'mine_attack', floor: 4, targets: [1], ...IN }, t + 100).code).toBe('tempo');
    expect(refuse(s, { type: 'mine_attack', floor: 4, targets: [3], ...IN }, t + STEP).code).toBe('bad_target');
    expect(refuse(s, { type: 'mine_attack', floor: 4, targets: [0, 0], ...IN }, t + STEP).code).toBe('bad_target');
    expect(refuse(s, { type: 'mine_attack', floor: 4, ...IN }, t + STEP).code).toBe('bad_target');
    expect(refuse(s, { type: 'mine_attack', floor: 2, targets: [0], ...IN }, t + STEP).code).toBe('bad_target');   // no monsters on floor 2
    ({ s, t } = kill(s, 4, 0, t));
    expect(refuse(s, { type: 'mine_attack', floor: 4, targets: [0], ...IN }, t + STEP).code).toBe('mob_gone');
  });

  it('one swing can reach several slimes', () => {
    const { s, t } = descend(fresh(), 4, T0);
    const r = step(s, { type: 'mine_attack', floor: 4, targets: [0, 1, 2], ...IN }, t + STEP);
    expect(r.s.mine.run!.floors[3].mobs).toEqual([6, 6, 6]);
  });

  it('a slime\'s hit costs HP once per invulnerability second; HP 0 knocks the player out with the run kept and HP full', () => {
    let { s, t } = descend(fresh(), 3, T0);
    let r = step(s, { type: 'mine_attack', floor: 3, hurt_by: 0, ...IN }, t += STEP);
    expect(r.s.mine.run!.hp).toBe(90);
    r = step(r.s, { type: 'mine_attack', floor: 3, hurt_by: 0, ...IN }, t + 500);   // inside the 1 s window: nothing
    expect(r.s.mine.run!.hp).toBe(90);
    s = r.s;
    for (let i = 0; i < 9; i++) s = step(s, { type: 'mine_attack', floor: 3, hurt_by: 0, ...IN }, t += 1_100).s;
    expect(s.mine.run!.hp).toBe(100);   // the ninth hit took it to 0: back at the mouth, full again
    expect(s.mine.run!.floors[2].paid).toBe(true);   // the run and its paid floors are kept
    expect(viewOf(c, s, t).mine.run!.hp).toBe(100);
  });

  it('a lethal swing wins the clash with the monster it kills', () => {
    let { s, t } = descend(fresh(), 3, T0);
    s = step(s, { type: 'mine_attack', floor: 3, targets: [0], ...IN }, t += STEP).s;
    s = step(s, { type: 'mine_attack', floor: 3, targets: [0], ...IN }, t += STEP).s;
    const r = step(s, { type: 'mine_attack', floor: 3, targets: [0], hurt_by: 0, ...IN }, t + STEP);
    expect(mine(r.ev, 'hurt')).toEqual([]);
    expect(r.s.mine.run!.hp).toBe(100);
  });

  it('entering the mine again (Continue run) refills HP', () => {
    let { s, t } = descend(fresh(), 3, T0);
    s = step(s, { type: 'mine_attack', floor: 3, hurt_by: 0, ...IN }, t += STEP).s;
    expect(s.mine.run!.hp).toBe(90);
    expect(step(s, { type: 'mine_enter' }, t + STEP).s.mine.run!.hp).toBe(100);
  });
});

describe('the elite, Run complete and quartz once a day (§13.3.4)', () => {
  it('the elite takes 12 swings; beating it ends the run (Run complete) and the mouth offers Enter mine again', () => {
    let { s, t } = descend(fresh(), 4, T0);
    ({ s, t } = clear(s, 4, t));
    s = step(s, { type: 'mine_floor', floor: 5, ...IN }, t += STEP).s;
    const k = kill(s, 5, 0, t);
    expect(mine(k.ev, 'hit').length).toBe(12);
    expect(mine(k.ev, 'complete')).toHaveLength(1);
    expect(k.s.mine.run).toBeNull();
    expect(k.s.mine.completed).toEqual({ run: 1, at: k.t });
    expect(viewOf(c, k.s, k.t).mine.completed).toEqual({ run: 1, at: k.t });
    expect(mine(step(k.s, { type: 'mine_enter' }, k.t + STEP).ev, 'enter')).toHaveLength(1);
  });

  it('its quartz drops on the day\'s first kill only; a second kill shares quartz\'s weight over the others', () => {
    const s = fresh();
    const run = step(s, { type: 'mine_enter' }, T0).s.mine.run!;
    const tally = (kills: number) => {
      s.mine.elite = kills ? { day: dayKey(c, T0), kills } : undefined;
      const n: Record<string, number> = {};
      for (let seed = 0; seed < 4000; seed++) {
        const [id] = mobLoot(c, s, { ...run, seed }, 5, 0, T0)!;
        n[id] = (n[id] ?? 0) + 1;
      }
      return Object.fromEntries(Object.entries(n).map(([k, v]) => [k, Math.round(v / 40)]));
    };
    const first = tally(0), second = tally(1);
    expect(Math.abs(first.quartz - 20)).toBeLessThanOrEqual(3);
    expect(second.quartz).toBeUndefined();
    expect(Math.abs(second.copper_ore - 37.5)).toBeLessThanOrEqual(3);
    expect(Math.abs(second.rock_salt - 31.25)).toBeLessThanOrEqual(3);
    expect(Math.abs(second.bait_worm - 31.25)).toBeLessThanOrEqual(3);
  });

  it('the elite\'s kills count by player day; the next day it drops quartz again', () => {
    let { s, t } = descend(fresh(), 4, T0);
    ({ s, t } = clear(s, 4, t));
    s = step(s, { type: 'mine_floor', floor: 5, ...IN }, t += STEP).s;
    ({ s, t } = kill(s, 5, 0, t));
    expect(s.mine.elite).toEqual({ day: dayKey(c, t), kills: 1 });
    expect(viewOf(c, s, t).mine.elite_quartz_today).toBe(false);
    expect(viewOf(c, s, T0 + 20 * H).mine.elite_quartz_today).toBe(true);   // past 04:00
  });

  it('loot that does not fit in the bag goes to Farm Storage', () => {
    let { s, t } = descend(fresh(), 3, T0);
    s.bag = Array.from({ length: s.bag_cap }, (_, i) => ({ id: `seed_test_${i}`, qty: 1 }));
    const k = kill(s, 3, 0, t);
    const [id, qty] = (mine(k.ev, 'defeat')[0] as { loot: [string, number] }).loot;
    expect(k.s.storage[id]).toBe(qty);
  });
});

describe('Express (§13.3.1, §13.3.9)', () => {
  it('opens for the account with the first clear of floor 4', () => {
    let { s, t } = descend(fresh(), 4, T0);
    expect(refuse(s, { type: 'mine_express', ...IN }, t + STEP)).toEqual({ code: 'express_locked', detail: { floor: 4 } });
    expect(viewOf(c, s, t).mine.express).toBe(false);
    const cl = clear(s, 4, t);
    expect(cl.s.mine.express).toBe(true);
    expect(viewOf(c, cl.s, cl.t).mine.express).toBe(true);
  });

  it('inside a run it rides to floor 5 for 0 Energy without paying floor 5 and without a new run', () => {
    let { s, t } = descend(fresh(), 4, T0);
    ({ s, t } = clear(s, 4, t));
    s = step(s, { type: 'mine_floor', floor: 1, ...IN }, t += STEP).s;
    const r = step(s, { type: 'mine_express', ...IN }, t += STEP);
    expect(spent(r.ev)).toBe(0);
    expect(r.s.mine.run!.id).toBe(1);
    expect(r.s.mine.run!.floors[4].paid).toBe(true);
    expect(r.s.day.mine_runs).toBe(1);
  });

  it('from the mouth it is a new run straight to floor 5 for 0 Energy; it counts toward the 2 runs a day', () => {
    let { s, t } = descend(fresh(), 4, T0);
    ({ s, t } = clear(s, 4, t));
    s = step(s, { type: 'mine_floor', floor: 5, ...IN }, t += STEP).s;
    ({ s, t } = kill(s, 5, 0, t));   // run 1 complete
    const r = step(s, { type: 'mine_express', space: 'home' }, t += STEP);
    expect(spent(r.ev)).toBe(0);
    expect(r.s.mine.run).toMatchObject({ id: 2, express: true });
    expect(r.s.mine.run!.floors.map(f => f.paid)).toEqual([false, false, false, false, true]);
    expect(r.s.day.mine_runs).toBe(2);
    expect(viewOf(c, r.s, t).mine.run!.can_new_run).toBe(false);   // 2/2 runs today
    expect(refuse(r.s, { type: 'mine_floor', floor: 2, ...IN }, t + STEP)).toEqual({ code: 'clear_floor_first', detail: { floor: 1 } });
  });

  it('an Express run counts as having cleared floor 2 for New run; an unfinished ordinary run needs it', () => {
    let { s, t } = descend(fresh(), 4, T0);
    ({ s, t } = clear(s, 4, t));
    s = step(s, { type: 'mine_floor', floor: 5, ...IN }, t += STEP).s;
    ({ s, t } = kill(s, 5, 0, t));
    s.day.mine_runs = 0;   // a fresh day's runs, the account still unlocked
    let r = step(s, { type: 'mine_enter' }, t += STEP);   // an ordinary run, floor 2 not cleared
    expect(refuse(r.s, { type: 'mine_express', space: 'home' }, t + STEP)).toEqual({ code: 'clear_floor_first', detail: { floor: 2 } });
    r.s.mine.run = null;
    r.s.day.mine_runs = 0;
    r = step(r.s, { type: 'mine_express', space: 'home' }, t += STEP);
    expect(viewOf(c, r.s, t).mine.run!.can_new_run).toBe(true);
  });

  it('a third run of the day by Express is refused (no_runs)', () => {
    const s = fresh();
    s.mine.express = true;
    s.day = { ...s.day, key: dayKey(c, T0), mine_runs: 2 };
    expect(refuse(s, { type: 'mine_express', space: 'home' }, T0).code).toBe('no_runs');
  });
});

describe('saves from before SGODOT-275', () => {
  it('a two-floor run loads with floors 3–5 unpaid and its monsters met at full HP', () => {
    let { s } = step(fresh(), { type: 'mine_enter' }, T0);
    const old = structuredClone(s) as P0State;
    old.mine.run!.floors = old.mine.run!.floors.slice(0, 2).map(f => ({ paid: f.paid, broken: f.broken, lit: f.lit }));
    delete old.mine.run!.hp;
    s = upgradeState(c, old, T0);
    expect(s.mine.run!.floors).toHaveLength(5);
    expect(s.mine.run!.floors.slice(2).map(f => f.paid)).toEqual([false, false, false]);
    const v = viewOf(c, s, T0).mine;
    expect(v.run!.hp).toBe(100);
    expect(v.run!.floors[3].mobs.map(m => m.hp)).toEqual([9, 9, 9]);
    expect(v.express).toBe(false);
  });
});
