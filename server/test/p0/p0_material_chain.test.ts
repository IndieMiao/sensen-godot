/** SGODOT-231: gathering spots, mine floors 1–2, the workbench, coming home and Timber Run from storage (floors 3–5,
 * combat, Express, quartz and the Old Tree: SGODOT-275, p0_mine_deep.test.ts). */
import { describe, expect, it } from 'vitest';
import { add, count } from '../../src/p0/bag.js';
import { loadP0Content } from '../../src/p0/content.js';
import { rockDrop } from '../../src/p0/mine.js';
import { notePresence } from '../../src/p0/presence.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
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
const energySpent = (ev: P0Event[]) => ev.filter(e => e.kind === 'energy').reduce((n, e) => n + (e.kind === 'energy' ? -e.delta : 0), 0);
/** Break every rock of one floor, one swing a second; returns the state, the clock after the last swing and the Energy spent. */
function clearFloor(s: P0State, floor: number, t: number): { s: P0State; t: number; spent: number } {
  let spent = 0;
  for (let rock = 0; rock < c.mine.rocks; rock++) {
    t += STEP;
    const r = step(s, { type: 'mine_rock', floor, rock, space: 'mine' }, t);
    s = r.s; spent += energySpent(r.ev);
  }
  return { s, t, spent };
}

describe('mine floors 1–2 (§13.3, LOCK-21)', () => {
  it('Enter mine pays floor 1 (2 Energy) and starts run 1 of 2; Continue run is free and lands on the deepest paid floor', () => {
    let { s, ev } = step(fresh(), { type: 'mine_enter', space: 'home' });
    expect(energySpent(ev)).toBe(2);
    expect(ev).toContainEqual({ kind: 'mine', action: 'enter', run: 1, floor: 1, cost: 2 });
    expect(s.day.mine_runs).toBe(1);
    ({ s, ev } = step(s, { type: 'mine_enter', space: 'home' }, T0 + STEP));
    expect(energySpent(ev)).toBe(0);
    expect(ev).toContainEqual({ kind: 'mine', action: 'continue', run: 1, floor: 1, cost: 0 });
    expect(s.day.mine_runs).toBe(1);
  });

  it('a full A run (floors 1 → 2, 12 rocks) costs 28 Energy: floor fees 4 + rocks 24 (§13.3.5)', () => {
    let s = fresh(), t = T0, spent = 0, cleared;
    let r = step(s, { type: 'mine_enter' }, t); s = r.s; spent += energySpent(r.ev);
    cleared = clearFloor(s, 1, t); s = cleared.s; t = cleared.t; spent += cleared.spent;
    r = step(s, { type: 'mine_floor', floor: 2, space: 'mine' }, t += STEP); s = r.s; spent += energySpent(r.ev);
    cleared = clearFloor(s, 2, t); s = cleared.s; spent += cleared.spent;
    expect(spent).toBe(28);
    expect(count(s.bag, 'stone')).toBe(12);
    expect(s.mine.run!.floors.slice(0, 2).every(f => f.broken.length === 6)).toBe(true);
  });

  it('every rock is 2 Energy and gives Stone (1 with the Starter Pickaxe) plus its derived drop; a broken rock is gone', () => {
    let { s } = step(fresh(), { type: 'mine_enter' });
    const before = s.energy.value;
    const r = step(s, { type: 'mine_rock', floor: 1, rock: 0, space: 'mine' }, T0 + STEP);
    expect(before - r.s.energy.value).toBe(2);
    expect(count(r.s.bag, 'stone')).toBe(1);
    const drop = rockDrop(c, r.s, r.s.mine.run!, 1, 0);
    expect(r.ev).toContainEqual({ kind: 'mine', action: 'rock', run: 1, floor: 1, rock: 0, drop, cost: 2 });
    if (drop) expect(count(r.s.bag, drop)).toBe(1);
    s = r.s;
    expect(refuse(s, { type: 'mine_rock', floor: 1, rock: 0 }, T0 + 2 * STEP).code).toBe('rock_gone');
  });

  it('swings faster than 0.9 s are refused as tempo (anti-script tempo)', () => {
    let { s } = step(fresh(), { type: 'mine_enter' });
    s = step(s, { type: 'mine_rock', floor: 1, rock: 0 }, T0 + STEP).s;
    expect(refuse(s, { type: 'mine_rock', floor: 1, rock: 1 }, T0 + STEP + 300).code).toBe('tempo');
  });

  it('floor 2 needs floor 1 cleared, then pays 2 once; going back to a paid floor is free', () => {
    let { s } = step(fresh(), { type: 'mine_enter' });
    expect(refuse(s, { type: 'mine_floor', floor: 2 })).toEqual({ code: 'clear_floor_first', detail: { floor: 1 } });
    let t = T0;
    ({ s, t } = clearFloor(s, 1, t));
    let r = step(s, { type: 'mine_floor', floor: 2 }, t += STEP);
    expect(energySpent(r.ev)).toBe(2);
    r = step(r.s, { type: 'mine_floor', floor: 1 }, t += STEP);
    expect(energySpent(r.ev)).toBe(0);
    r = step(r.s, { type: 'mine_floor', floor: 2 }, t += STEP);
    expect(energySpent(r.ev)).toBe(0);
    expect(refuse(r.s, { type: 'mine_rock', floor: 3, rock: 0 }, t + STEP).code).toBe('floor_not_paid');
    expect(refuse(r.s, { type: 'mine_rock', floor: 6, rock: 0 }, t + STEP).code).toBe('bad_floor');
  });

  it('a floor clears with its sixth rock (Floor 1 cleared · Elevator stop)', () => {
    let { s } = step(fresh(), { type: 'mine_enter' });
    let t = T0;
    for (let rock = 0; rock < 5; rock++) s = step(s, { type: 'mine_rock', floor: 1, rock }, t += STEP).s;
    const last = step(s, { type: 'mine_rock', floor: 1, rock: 5 }, t + STEP);
    expect(last.ev).toContainEqual({ kind: 'mine', action: 'cleared', run: 1, floor: 1, cost: 0 });
  });

  it('New run needs this run\'s floor 2 cleared, costs 2 and counts; a third run of the day is refused', () => {
    let { s } = step(fresh(), { type: 'mine_enter' });
    expect(refuse(s, { type: 'mine_new_run' })).toEqual({ code: 'clear_floor_first', detail: { floor: 2 } });
    let t = T0;
    ({ s, t } = clearFloor(s, 1, t));
    s = step(s, { type: 'mine_floor', floor: 2 }, t += STEP).s;
    ({ s, t } = clearFloor(s, 2, t));
    const r = step(s, { type: 'mine_new_run' }, t += STEP);
    expect(energySpent(r.ev)).toBe(2);
    expect(r.s.mine.run!.id).toBe(2);
    expect(r.s.mine.run!.floors.map(f => f.paid)).toEqual([true, false, false, false, false]);
    expect(r.s.day.mine_runs).toBe(2);
    s = r.s;
    ({ s, t } = clearFloor(s, 1, t));
    s = step(s, { type: 'mine_floor', floor: 2 }, t += STEP).s;
    ({ s, t } = clearFloor(s, 2, t));
    expect(refuse(s, { type: 'mine_new_run' }, t + STEP).code).toBe('no_runs');
  });

  it('the 04:00 rollover ends an unfinished run once (Run ended at daily reset); the next Enter mine starts a new run', () => {
    let { s } = step(fresh(), { type: 'mine_enter' });
    const after = T0 + 20 * H;   // 06:00 next day Shanghai
    const v = viewOf(c, s, after);
    expect(v.mine.run).toBeNull();
    expect(v.mine.ended).toEqual({ reason: 'reset', at: T0 + 18 * H });   // 04:00 Shanghai on 10-09, the same on every read
    expect(viewOf(c, s, after + H).mine.ended).toEqual(v.mine.ended);
    expect(v.mine.runs.used).toBe(0);
    expect(refuse(s, { type: 'mine_rock', floor: 1, rock: 0 }, after).code).toBe('no_run');
    const r = step(s, { type: 'mine_enter' }, after);
    expect(r.ev).toContainEqual({ kind: 'mine', action: 'enter', run: 2, floor: 1, cost: 2 });
    expect(r.s.mine.ended).toBeNull();
  });

  it('drops derive from the run, floor and rock: a torch preview matches what the rocks give; floor 2 never gives clay', () => {
    let { s } = step(fresh(), { type: 'mine_enter' });
    add(c, s, 'torch', 2);
    expect(viewOf(c, s, T0).mine.run!.floors[0].preview).toBeNull();
    const lit = step(s, { type: 'mine_torch', floor: 1, space: 'mine' }, T0 + STEP);
    expect(count(lit.s.bag, 'torch')).toBe(1);
    expect(refuse(lit.s, { type: 'mine_torch', floor: 1 }, T0 + 2 * STEP).code).toBe('lit');
    const preview = viewOf(c, lit.s, T0 + STEP).mine.run!.floors[0].preview!;
    s = lit.s;
    let t = T0 + STEP;
    for (let rock = 0; rock < 6; rock++) {
      const r = step(s, { type: 'mine_rock', floor: 1, rock }, t += STEP);
      expect(r.ev).toContainEqual(expect.objectContaining({ kind: 'mine', action: 'rock', rock, drop: preview[rock] }));
      s = r.s;
    }
    const run = s.mine.run!;
    const floor2 = new Set(Array.from({ length: 400 }, (_, i) => rockDrop(c, s, { ...run, seed: i }, 2, i % 6)));
    expect(floor2.has('clay')).toBe(false);
    expect([...floor2].sort()).toEqual(['copper_ore', 'quartz', 'rock_salt', null].sort());
  });

  it('P1 restores floor 2\'s quartz: copper 30 / rock salt 20 / quartz 15 / none 35 (§13.3.3; P0 had folded it into salt, q(47)); floor 1 is unchanged', () => {
    const { s } = step(fresh(), { type: 'mine_enter' });
    const run = s.mine.run!;
    const share = (floor: number) => {
      const n: Record<string, number> = {};
      for (let seed = 0; seed < 3000; seed++) {
        const id = String(rockDrop(c, s, { ...run, seed }, floor, seed % 6));
        n[id] = (n[id] ?? 0) + 1;
      }
      return Object.fromEntries(Object.entries(n).map(([k, v]) => [k, Math.round(v / 30)]));   // percent
    };
    const f2 = share(2);
    expect(Object.keys(f2).sort()).toEqual(['copper_ore', 'null', 'quartz', 'rock_salt']);
    expect(Math.abs(f2.copper_ore - 30)).toBeLessThanOrEqual(3);
    expect(Math.abs(f2.rock_salt - 20)).toBeLessThanOrEqual(3);
    expect(Math.abs(f2.quartz - 15)).toBeLessThanOrEqual(3);
    expect(Math.abs(f2.null - 35)).toBeLessThanOrEqual(3);
    expect(c.mine.floors[0].drops).toEqual([['copper_ore', 35], ['rock_salt', 25], ['clay', 15], [null, 25]]);
  });

  it('a fee is never paid into a floor whose first rock would not fit: Enter mine / New run / Floor 2 · Bag full (q(48))', () => {
    const full = fresh();
    for (let i = 0; i < 22; i++) full.bag.push({ id: 'fish_crucian', qty: 10 });   // 1 free slot: Stone + an ore need 2
    expect(viewOf(c, full, T0).mine.entry_bag_ok).toBe(false);
    expect(refuse(full, { type: 'mine_enter' })).toEqual({ code: 'bag_full', detail: { floor: 1 } });
    expect(full.day.mine_runs).toBe(0);
    // Inside a run: floor 1 cleared, then the bag fills before the stairs.
    let { s } = step(fresh(), { type: 'mine_enter' });
    let t = T0;
    ({ s, t } = clearFloor(s, 1, t));
    s.bag = Array.from({ length: s.bag_cap }, () => ({ id: 'fish_crucian', qty: 10 }));   // no slot, no Stone stack
    const energy = s.energy.value;
    expect(refuse(s, { type: 'mine_floor', floor: 2 }, t + STEP)).toEqual({ code: 'bag_full', detail: { floor: 2 } });
    expect(s.energy.value).toBe(energy);
    // Continue run and a paid floor stay free and open.
    expect(step(s, { type: 'mine_enter' }, t + STEP).ev).toContainEqual(expect.objectContaining({ kind: 'mine', action: 'continue' }));
    expect(step(s, { type: 'mine_floor', floor: 1 }, t + STEP).ev).toContainEqual(expect.objectContaining({ kind: 'mine', action: 'floor', floor: 1, cost: 0 }));
  });

  it('New run with a full bag is refused before any Energy (q(48))', () => {
    let { s } = step(fresh(), { type: 'mine_enter' });
    let t = T0;
    ({ s, t } = clearFloor(s, 1, t));
    s = step(s, { type: 'mine_floor', floor: 2 }, t += STEP).s;
    ({ s, t } = clearFloor(s, 2, t));
    s.bag = Array.from({ length: s.bag_cap }, () => ({ id: 'fish_crucian', qty: 10 }));
    const energy = s.energy.value;
    expect(refuse(s, { type: 'mine_new_run' }, t + STEP)).toEqual({ code: 'bag_full', detail: { floor: 1 } });
    expect(s.energy.value).toBe(energy);
  });

  it('a torch needs one in the bag', () => {
    const { s } = step(fresh(), { type: 'mine_enter' });
    expect(refuse(s, { type: 'mine_torch', floor: 1 }, T0 + STEP)).toEqual({ code: 'no_item', detail: { item: 'torch' } });
  });

  it('the Copper Pickaxe gives 2 Stone per rock, still 2 Energy (LOCK-29)', () => {
    let s = fresh();
    s.gear.picks.push('pick_copper');
    s = step(s, { type: 'equip', item: 'pick_copper' }).s;
    s = step(s, { type: 'mine_enter' }, T0 + STEP).s;
    const before = s.energy.value;
    s = step(s, { type: 'mine_rock', floor: 1, rock: 0 }, T0 + 2 * STEP).s;
    expect(count(s.bag, 'stone')).toBe(2);
    expect(before - s.energy.value).toBe(2);
    expect(viewOf(c, s, T0 + 2 * STEP).gear.slots.mining).toBe('pick_copper');
  });

  it('a full bag greys the whole floor by the worst case (Stone + any ore), not by the rock\'s real drop (q(44))', () => {
    let { s } = step(fresh(), { type: 'mine_enter' });
    // 25 slots: 2 seed stacks + 22 fish stacks = 24 used, 1 free. Stone and an ore would need 2 slots.
    for (let i = 0; i < 22; i++) s.bag.push({ id: 'fish_crucian', qty: 10 });
    expect(viewOf(c, s, T0).mine.run!.floors[0].bag_ok).toBe(false);
    expect(refuse(s, { type: 'mine_rock', floor: 1, rock: 0 }, T0 + STEP)).toEqual({ code: 'bag_full', detail: { floor: 1 } });
    s.bag.pop();   // 2 free slots
    expect(viewOf(c, s, T0).mine.run!.floors[0].bag_ok).toBe(true);
    expect(step(s, { type: 'mine_rock', floor: 1, rock: 0 }, T0 + STEP).s.mine.run!.floors[0].broken).toEqual([0]);
  });

  it('commands inside the mine from another space are refused; older clients without space still work', () => {
    const { s } = step(fresh(), { type: 'mine_enter', space: 'home' });
    expect(refuse(s, { type: 'mine_rock', floor: 1, rock: 0, space: 'home' }, T0 + STEP).code).toBe('not_in_mine');
    expect(step(s, { type: 'mine_rock', floor: 1, rock: 0 }, T0 + STEP).s.mine.run!.floors[0].broken).toEqual([0]);
  });

  it('a retried swing with the same expect_seq never applies twice (SGODOT-211)', () => {
    const { s } = step(fresh(), { type: 'mine_enter' });
    const cmd: P0Command = { type: 'mine_rock', floor: 1, rock: 0, expect_seq: s.seq };
    const once = step(s, cmd, T0 + STEP).s;
    expect(refuse(once, cmd, T0 + 3 * STEP).code).toBe('stale_state');
  });

  it('Enter mine with less than 2 Energy is need_energy; with no runs left no_runs', () => {
    const s = fresh();
    s.energy = { value: 1, tick_ms: T0 };
    expect(refuse(s, { type: 'mine_enter' })).toMatchObject({ code: 'need_energy', detail: { need: 2, have: 1 } });
    const t = fresh();
    t.day = { ...t.day, key: '2026-10-08', mine_runs: 2 };
    expect(refuse(t, { type: 'mine_enter' })).toMatchObject({ code: 'no_runs', detail: { used: 2, limit: 2 } });
  });
});

describe('gathering spots (§13.2, q(44))', () => {
  it('a spot is 0 Energy, its material goes to Farm Storage, and it is ready again 8 h later', () => {
    const s0 = fresh();
    let { s, ev } = step(s0, { type: 'gather', spot: 'spot_grove', space: 'home' });
    expect(s.energy.value).toBe(s0.energy.value);
    expect(s.storage.wood).toBe(6);
    expect(count(s.bag, 'wood')).toBe(0);
    expect(ev).toContainEqual({ kind: 'gather', spot: 'spot_grove', items: [['wood', 6, 'storage']], ready_in: 8 * H });
    expect(refuse(s, { type: 'gather', spot: 'spot_grove' }, T0 + 7 * H)).toEqual({ code: 'not_ready', detail: { ready_in: H } });
    ({ s } = step(s, { type: 'gather', spot: 'spot_grove' }, T0 + 8 * H));
    expect(s.storage.wood).toBe(12);
  });

  it('Gather Gloves add 1 to the material only; the Reed Bank\'s worms go to the bag', () => {
    const s0 = fresh();
    s0.owned.push('gather_gloves');
    const { s, ev } = step(s0, { type: 'gather', spot: 'spot_reed_bank' });
    expect(s.storage.fiber).toBe(4);
    expect(count(s.bag, 'bait_worm')).toBe(2);
    expect(ev).toContainEqual({ kind: 'gather', spot: 'spot_reed_bank', items: [['fiber', 4, 'storage'], ['bait_worm', 2, 'bag']], ready_in: 8 * H });
  });

  it('worms that do not fit in the bag go to storage with the reeds', () => {
    const s0 = fresh();
    for (let i = 0; i < 23; i++) s0.bag.push({ id: 'fish_crucian', qty: 10 });   // 25 / 25
    const { s } = step(s0, { type: 'gather', spot: 'spot_reed_bank' });
    expect(count(s.bag, 'bait_worm')).toBe(0);
    expect(s.storage).toEqual({ fiber: 3, bait_worm: 2 });
  });

  it('the Herb Patch\'s Wild Herb goes to the bag before the Spice Rack and to storage from Homestead Lv2 (q(46))', () => {
    const lv1 = step(fresh(), { type: 'gather', spot: 'spot_herb_patch' });
    expect(count(lv1.s.bag, 'wild_herb')).toBe(2);
    expect(lv1.ev).toContainEqual({ kind: 'gather', spot: 'spot_herb_patch', items: [['wild_herb', 2, 'bag']], ready_in: 8 * H });
    const s2 = fresh();
    s2.homestead.level = 2;
    const lv2 = step(s2, { type: 'gather', spot: 'spot_herb_patch' });
    expect(lv2.s.storage.wild_herb).toBe(2);
    expect(count(lv2.s.bag, 'wild_herb')).toBe(0);
  });

  it('the Clay Bank opens at Homestead Lv2, the Old Tree at Lv3 with 1 Hardwood a round (P1, §13.2.1)', () => {
    const s = fresh();
    expect(refuse(s, { type: 'gather', spot: 'spot_clay_bank' })).toEqual({ code: 'homestead_level', detail: { need: 2 } });
    s.homestead.level = 2;
    expect(step(s, { type: 'gather', spot: 'spot_clay_bank' }).s.storage.clay).toBe(2);
    expect(refuse(s, { type: 'gather', spot: 'spot_old_tree' }, T0 + STEP)).toEqual({ code: 'homestead_level', detail: { need: 3 } });
    s.homestead.level = 3;
    const tree = step(s, { type: 'gather', spot: 'spot_old_tree' }, T0 + STEP).s;
    expect(tree.storage.hardwood).toBe(1);
    expect(refuse(tree, { type: 'gather', spot: 'spot_old_tree' }, T0 + 2 * STEP).code).toBe('not_ready');
    expect(viewOf(c, fresh(), T0).gather.spots.map(sp => sp.id)).toEqual(['spot_grove', 'spot_rock_pile', 'spot_reed_bank', 'spot_herb_patch', 'spot_clay_bank', 'spot_old_tree']);
  });

  it('taps faster than 0.9 s are refused as tempo; gathering from away is not_home', () => {
    const { s } = step(fresh(), { type: 'gather', spot: 'spot_grove' });
    expect(refuse(s, { type: 'gather', spot: 'spot_rock_pile' }, T0 + 500).code).toBe('tempo');
    expect(refuse(fresh(), { type: 'gather', spot: 'spot_grove', space: 'mine' }).code).toBe('not_home');
  });

  it('the view says which spots are open and ready, and what a gather gives now (gloves included)', () => {
    const s = fresh();
    s.owned.push('gather_gloves');
    const v = viewOf(c, s, T0).gather;
    expect(v.gloves).toBe(true);
    expect(v.spots[0]).toEqual({ id: 'spot_grove', name: 'Timber Grove', open: true, homestead: 1, ready: true, ready_in: 0, yield: [['wood', 7]] });
    expect(v.spots[4]).toMatchObject({ id: 'spot_clay_bank', open: false, ready: false });
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

  it('Gather Gloves work at once and are owned', () => {
    const s0 = fresh();
    s0.storage = { fiber: 8, wood: 4 };
    const { s } = step(s0, { type: 'craft', recipe: 'craft_gather_gloves' });
    expect(s.owned).toContain('gather_gloves');
    expect(step(s, { type: 'gather', spot: 'spot_grove' }, T0 + STEP).s.storage.wood).toBe(7);
    expect(refuse(s, { type: 'craft', recipe: 'craft_gather_gloves' }).code).toBe('owned');
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
    let { s } = step(fresh(), { type: 'mine_enter', space: 'home' });
    s = step(s, { type: 'mine_rock', floor: 1, rock: 0, space: 'mine' }, T0 + STEP).s;
    add(c, s, 'torch', 2); add(c, s, 'bait_worm', 3); add(c, s, 'wild_herb', 3); add(c, s, 'rock_salt', 1); add(c, s, 'copper_ore', 2);
    const stone = count(s.bag, 'stone');
    const r = step(s, { type: 'gather', spot: 'spot_grove', space: 'home' }, T0 + 2 * STEP);
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
    expect(count(r.s.bag, 'seed_radish')).toBe(20);
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
    expect(s.v).toBe(6);
    expect(s.gear).toMatchObject({ picks: ['pick_starter'], pick: 'pick_starter' });
    expect(s.gather).toEqual({ ready_at: {}, last_at: 0 });
    expect(s.mine).toEqual({ run: null, count: 0, ended: null, swing_at: 0 });
    expect(s.storage_auto).toBeNull();
    expect(s.day.mine_runs).toBe(0);
  });
});
