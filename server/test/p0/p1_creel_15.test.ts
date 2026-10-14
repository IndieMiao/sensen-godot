/**
 * The creel at Fishing Lv10 (§4.6.2: a fish slot holds 15, not 10; content fishing.creel). Read from the player's level
 * each time, so nothing in the save changes; every place that fills or splits stacks (landing a fish, a trap's collect,
 * the Inbox's parcels) and Sell All see the same 15.
 */
import { describe, expect, it } from 'vitest';
import { add, count, room, stackLimit } from '../../src/p0/bag.js';
import { loadP0Content } from '../../src/p0/content.js';
import { grantItems } from '../../src/p0/parcels.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { settleTrap, TRAP } from '../../src/p0/fish_trap.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 13, 20);
const H = 3_600_000;
const FERN = 'pond_san_francisco_03';
const LV = (n: number) => c.skills.fishing[n - 1];

function player(level: number): P0State {
  const s = freshState(c, 'p1-creel-01', T0, 7);
  s.skills.fishing = LV(level);
  s.coins = 1000;
  s.bag = [];
  return s;
}
function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
/** Every slot but `free` taken by one seed each, plus the given stacks. */
const filled = (s: P0State, stacks: { id: string; qty: number }[], free = 0) => {
  s.bag = [...stacks.map(b => ({ ...b })), ...Array.from({ length: s.bag_cap - stacks.length - free }, (_, i) => ({ id: `seed_test_${i}`, qty: 1 }))];
  return s;
};

describe('the creel at Fishing Lv10 (§4.6.2)', () => {
  it('a fish slot holds 15 from Fishing Lv10, 10 before; other kinds, and no player, keep their own', () => {
    expect(c.fishing.creel).toEqual({ level: 10, stack: 15 });
    expect(stackLimit(c, 'fish_crucian', player(9))).toBe(10);
    expect(stackLimit(c, 'fish_crucian', player(10))).toBe(15);
    expect(stackLimit(c, 'fish_crucian')).toBe(10);   // without the player: the kind's base
    expect(stackLimit(c, 'crop_radish', player(10))).toBe(c.bag.stack.crop);
    expect(stackLimit(c, TRAP, player(10))).toBe(3);   // a trap is its own kind, not a fish
  });

  it('a stack fills to 15 before a new slot is taken; the save holds only the stacks', () => {
    const s = player(10);
    add(c, s, 'fish_crucian', 12);
    expect(s.bag).toEqual([{ id: 'fish_crucian', qty: 12 }]);
    add(c, s, 'fish_crucian', 5);
    expect(s.bag).toEqual([{ id: 'fish_crucian', qty: 15 }, { id: 'fish_crucian', qty: 2 }]);
    const below = player(9);
    add(c, below, 'fish_crucian', 12);
    expect(below.bag).toEqual([{ id: 'fish_crucian', qty: 10 }, { id: 'fish_crucian', qty: 2 }]);
  });

  it('a full bag still has room in a fish stack under 15, at Lv10 only', () => {
    expect(room(c, filled(player(10), [{ id: 'fish_crucian', qty: 10 }]), 'fish_crucian')).toBe(5);
    expect(room(c, filled(player(9), [{ id: 'fish_crucian', qty: 10 }]), 'fish_crucian')).toBe(0);
  });

  it("a trap's collect into a full bag fills a stack to 15 (`Collect · Creel full` only when none fits)", () => {
    const at = { space: 'pond', place: FERN } as const;
    let s = player(10);
    s = step(s, { type: 'buy', item: TRAP, qty: 1, shop: 'tackle' }).s;
    s = step(s, { type: 'set_trap', ...at }).s;
    const now = T0 + 24 * H;
    settleTrap(c, s, s.traps![0], now);
    s.traps![0].fish = ['fish_crucian', 'fish_crucian', 'fish_crucian'];
    filled(s, [{ id: 'fish_crucian', qty: 13 }]);
    const r = step(s, { type: 'collect_trap', ...at }, now);
    expect(r.ev).toContainEqual(expect.objectContaining({ kind: 'trap', action: 'collected', fish: 2, left: 1 }));
    expect(count(r.s.bag, 'fish_crucian')).toBe(15);
    const nine = structuredClone(s);
    nine.skills.fishing = LV(9);
    nine.bag[0].qty = 10;
    const refused = applyP0(c, nine, { type: 'collect_trap', ...at }, now);
    expect(refused).toMatchObject({ ok: false });   // at Lv9 the 10 is full: nothing fits
  });

  it('fish that do not fit go to the Inbox in parcels of 15 at Lv10 (10 before)', () => {
    const s = filled(player(10), []);
    const ev: P0Event[] = [];
    grantItems(c, s, T0, 'test:creel', 'Test', [['fish_crucian', 20]], ev);
    expect(s.inbox.parcels.filter(p => p.id === 'fish_crucian').map(p => p.qty)).toEqual([15, 5]);
    const nine = filled(player(9), []);
    grantItems(c, nine, T0, 'test:creel', 'Test', [['fish_crucian', 20]], []);
    expect(nine.inbox.parcels.filter(p => p.id === 'fish_crucian').map(p => p.qty)).toEqual([10, 10]);
  });

  it('Sell All sells every fish across stacks of 15', () => {
    const s = player(10);
    s.bag = [{ id: 'fish_koi', qty: 15 }, { id: 'fish_koi', qty: 15 }, { id: 'fish_koi', qty: 4 }];
    const r = step(s, { type: 'sell', item: 'fish_koi', qty: 'all' });
    expect(r.ev).toContainEqual(expect.objectContaining({ kind: 'sale', item: 'fish_koi', qty: 34 }));
    expect(count(r.s.bag, 'fish_koi')).toBe(0);
  });
});
