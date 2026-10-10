/** SGODOT-283 Fish Trap (plan §6.8, q(109) ④⑦) and the Fish-dex milestones' coins and badge (§6.9.2). */
import { describe, expect, it } from 'vitest';
import { count } from '../../src/p0/bag.js';
import { itemKind, loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { settleTrap, trapSlots, TRAP } from '../../src/p0/fish_trap.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 10, 20);   // 13:00 in San Francisco
const H = 3_600_000;
const FERN = 'pond_san_francisco_03', BLOSSOM = 'pond_san_francisco_06', CLOVER = 'pond_san_francisco_02';
const LV = (n: number) => c.skills.fishing[n - 1];

function fresh(level = 5): P0State {
  const s = freshState(c, 'p1-trap-01', T0, 7);
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
function refuse(s: P0State, cmd: P0Command, now = T0) {
  const r = applyP0(c, s, cmd, now);
  if (r.ok) throw new Error(`${cmd.type} was accepted`);
  return { code: r.code, detail: r.detail };
}
const at = (place: string) => ({ space: 'pond', place }) as const;
const buy = (s: P0State, qty = 1) => step(s, { type: 'buy', item: TRAP, qty, shop: 'tackle' }).s;

describe('the Fish Trap as a good (§6.8, q(109) ④)', () => {
  it('trap_fish is its own kind (not a fish), stacks 3, sold at the Tackle Shop from Fishing Lv5 for 120, never bought back', () => {
    expect(itemKind(TRAP)).toBe('trap');
    expect(c.bag.stack.trap).toBe(3);
    expect(c.tackle.buy).toContain(TRAP);
    expect(refuse(fresh(4), { type: 'buy', item: TRAP, qty: 1, shop: 'tackle' }).code).toBe('locked');   // Fishing Lv5
    let s = buy(fresh(5), 3);
    expect(count(s.bag, TRAP)).toBe(3);
    expect(s.coins).toBe(1000 - 360);
    expect(s.bag.filter(b => b.id === TRAP)).toHaveLength(1);   // one slot of 3
    expect(refuse(s, { type: 'sell', item: TRAP, qty: 1, shop: 'tackle' }).code).toMatch(/not_sellable/);
  });

  it('slots: Lv5 1, Lv8 2, Lv10 3, none below Lv5', () => {
    expect([4, 5, 7, 8, 9, 10].map(l => trapSlots(c, fresh(l)))).toEqual([0, 1, 1, 2, 2, 3]);
  });
});

describe('setting a trap', () => {
  it('leaves the bag, one per pond, as many in the water as the slots (q(109) ⑦)', () => {
    let s = buy(fresh(5), 2);
    s = step(s, { type: 'set_trap', ...at(FERN) }).s;
    expect(count(s.bag, TRAP)).toBe(1);
    expect(s.traps).toEqual([{ place: FERN, set_at: T0, from: T0, n: 0, fish: [] }]);
    expect(refuse(s, { type: 'set_trap', ...at(FERN) }).code).toBe('trap_here');
    expect(refuse(s, { type: 'set_trap', ...at(BLOSSOM) })).toEqual({ code: 'trap_slots', detail: { used: 1, slots: 1, next_level: 8 } });
    s.skills.fishing = LV(8);
    s = step(s, { type: 'set_trap', ...at(BLOSSOM) }).s;
    expect(s.traps!.map(t => t.place)).toEqual([FERN, BLOSSOM]);
  });

  it('needs a trap in the bag and the player at a pond', () => {
    expect(refuse(fresh(5), { type: 'set_trap', ...at(FERN) }).code).toBe('no_trap');
    expect(refuse(buy(fresh(5)), { type: 'set_trap', space: 'home' } as P0Command).code).toBe('not_at_pond');
  });
});

describe('what a trap catches (§6.8)', () => {
  it('one fish per 8 hours, up to 3, then it stops until emptied; the same answer however often it is looked at', () => {
    let s = buy(fresh(5));
    s = step(s, { type: 'set_trap', ...at(FERN) }).s;
    const t = s.traps![0];
    settleTrap(c, s, t, T0 + 7.9 * H);
    expect(t.fish).toHaveLength(0);
    settleTrap(c, s, t, T0 + 8 * H);
    expect(t.fish).toHaveLength(1);
    const first = t.fish[0];
    settleTrap(c, s, t, T0 + 100 * H);
    expect(t.fish).toHaveLength(3);
    expect(t.fish[0]).toBe(first);
    expect(viewOf(c, s, T0 + 100 * H).fishing.trap.traps[0]).toMatchObject({ place: FERN, fish: 3, keep: 3, next_in: null });
  });

  it('only Common and Fine of that pond (its regional fish included), Rare one in ten from Lv9', () => {
    const tally = (level: number, place: string) => {
      const n: Record<number, number> = {};
      const ids = new Set<string>();
      for (let i = 0; i < 600; i++) {
        const s = fresh(level);
        s.player = `p1-trap-${i}`;
        s.traps = [{ place, set_at: T0 + i * 7919, from: T0 + i * 7919, n: 0, fish: [] }];
        settleTrap(c, s, s.traps[0], T0 + i * 7919 + 24 * H);
        for (const id of s.traps[0].fish) { const f = c.fish.find(x => x.id === id)!; n[f.rarity] = (n[f.rarity] ?? 0) + 1; ids.add(id); }
      }
      return { n, ids };
    };
    const lv5 = tally(5, FERN);
    expect(Object.keys(lv5.n).sort()).toEqual(['1', '2']);
    expect(lv5.ids).toContain('fish_arctic_char');   // San Francisco's regional fish swims in Fern
    expect([...lv5.ids].every(id => ['fish_crucian', 'fish_carp', 'fish_perch', 'fish_bass', 'fish_arctic_char'].includes(id))).toBe(true);
    const lv9 = tally(9, BLOSSOM);
    const rare = (lv9.n[3] ?? 0) / Object.values(lv9.n).reduce((a, b) => a + b, 0);
    expect(Math.abs(rare - 0.10)).toBeLessThanOrEqual(0.03);
    expect(tally(5, CLOVER).ids).toEqual(new Set(['fish_mullet', 'fish_mackerel']));   // Coast: Common Mullet, Fine Mackerel
  });
});

describe('collecting (q(109) ⑦)', () => {
  const full = () => {
    let s = buy(fresh(5));
    s = step(s, { type: 'set_trap', ...at(FERN) }).s;
    return { s, now: T0 + 24 * H };
  };

  it('Collect puts the fish in the creel at the pond, for half the catch XP, and counts them caught', () => {
    const { s, now } = full();
    const xp = s.skills.fishing;
    const r = step(s, { type: 'collect_trap', ...at(FERN) }, now);
    expect(r.ev).toContainEqual(expect.objectContaining({ kind: 'trap', action: 'collected', place: FERN, fish: 3, left: 0 }));
    expect(r.s.bag.filter(b => b.id.startsWith('fish_')).reduce((n, b) => n + b.qty, 0)).toBe(3);
    expect(r.s.traps![0].fish).toEqual([]);
    expect(r.s.traps![0].from).toBe(now);   // full until now: the next fish counts from the collect
    expect(r.s.skills.fishing).toBeGreaterThanOrEqual(xp);
    expect(Object.values(r.s.fishing.caught).reduce((a, b) => a + b, 0)).toBe(3);
  });

  it('takes what fits and leaves the rest; refuses with nothing fitting (`Collect · Creel full`)', () => {
    const { s, now } = full();
    settleTrap(c, s, s.traps![0], now);
    s.traps![0].fish = ['fish_carp', 'fish_crucian', 'fish_perch'];
    s.bag = Array.from({ length: s.bag_cap - 1 }, (_, i) => ({ id: `seed_test_${i}`, qty: 1 }));
    s.bag.push({ id: 'fish_carp', qty: 9 });
    const r = step(s, { type: 'collect_trap', ...at(FERN) }, now);
    expect(r.ev).toContainEqual(expect.objectContaining({ kind: 'trap', action: 'collected', fish: 1, left: 2 }));
    expect(r.s.traps![0].fish).toEqual(['fish_crucian', 'fish_perch']);
    expect(refuse(r.s, { type: 'collect_trap', ...at(FERN) }, now)).toEqual({ code: 'creel_full', detail: { fish: 2 } });
  });

  it('a fish that does not fit is skipped and the next still taken; the view counts it the same way (苏烈 on #249)', () => {
    const { s, now } = full();
    settleTrap(c, s, s.traps![0], now);
    s.traps![0].fish = ['fish_pike', 'fish_crucian'];   // no free slot; a part stack of Crucian takes the second only
    s.bag = Array.from({ length: s.bag_cap - 1 }, (_, i) => ({ id: `seed_test_${i}`, qty: 1 }));
    s.bag.push({ id: 'fish_crucian', qty: 5 });
    expect(viewOf(c, s, now).fishing.trap.traps[0]).toMatchObject({ fish: 2, fits: 1, all_fit: false });
    const r = step(s, { type: 'collect_trap', ...at(FERN) }, now);
    expect(r.ev).toContainEqual(expect.objectContaining({ kind: 'trap', action: 'collected', fish: 1, left: 1 }));
    expect(r.s.traps![0].fish).toEqual(['fish_pike']);
    expect(viewOf(c, r.s, now).fishing.trap.traps[0]).toMatchObject({ fish: 1, fits: 0 });
    expect(refuse(r.s, { type: 'collect_trap', ...at(FERN) }, now)).toEqual({ code: 'creel_full', detail: { fish: 1 } });
  });

  it('Take back empties the trap into the creel and the trap into the bag; only when everything fits', () => {
    const { s, now } = full();
    const r = step(s, { type: 'collect_trap', take_back: true, ...at(FERN) }, now);
    expect(r.ev).toContainEqual(expect.objectContaining({ kind: 'trap', action: 'taken_back', fish: 3, left: 0 }));
    expect(r.s.traps).toEqual([]);
    expect(count(r.s.bag, TRAP)).toBe(1);
    const tight = full();
    settleTrap(c, tight.s, tight.s.traps![0], tight.now);
    tight.s.bag = Array.from({ length: tight.s.bag_cap - 1 }, (_, i) => ({ id: `seed_test_${i}`, qty: 1 }));
    expect(refuse(tight.s, { type: 'collect_trap', take_back: true, ...at(FERN) }, tight.now).code).toBe('collect_first');
  });

  it('needs the player at that pond', () => {
    const { s, now } = full();
    expect(refuse(s, { type: 'collect_trap', ...at(BLOSSOM) }, now).code).toBe('no_trap_here');
  });

  it('the view: each trap with its fish and the time to the next, the slots and the next level', () => {
    let s = buy(fresh(5), 2);
    s = step(s, { type: 'set_trap', ...at(FERN) }).s;
    const v = viewOf(c, s, T0 + 3 * H).fishing.trap;
    expect(v).toMatchObject({ slots: 1, next_level: 8, have: 1, here: true });
    expect(v.traps).toEqual([{ place: FERN, fish: 0, keep: 3, next_in: 5 * H, fits: 0, all_fit: true, back_fits: true }]);
    const later = viewOf(c, s, T0 + 24 * H).fishing.trap.traps[0];
    expect(later).toMatchObject({ fish: 3, next_in: null, fits: 3, all_fit: true, back_fits: true });
    s.bag = Array.from({ length: s.bag_cap - 1 }, (_, i) => ({ id: `seed_test_${i}`, qty: 1 }));
    // one free slot: the 3 fish fit only if they stack in it (all the same kind) — fits is what Collect would take
    const tight = viewOf(c, s, T0 + 24 * H).fishing.trap.traps[0];
    expect(tight.fits).toBeGreaterThanOrEqual(1);
    expect(tight.back_fits).toBe(false);
  });
});

describe('Fish-dex milestones (§6.9.2)', () => {
  it('10 kinds: +30 Energy and 100 coins; 20 kinds: +50 Energy, 300 coins and the badge — once, from a trap too', () => {
    let s = buy(fresh(5));
    s = step(s, { type: 'set_trap', ...at(FERN) }).s;
    const kinds = c.fish.map(f => f.id).filter(id => id !== 'fish_crucian');
    for (const id of kinds.slice(0, 9)) s.fishing.caught[id] = 1;
    settleTrap(c, s, s.traps![0], T0 + 24 * H);
    s.traps![0].fish = ['fish_crucian'];
    const coins = s.coins;
    const r = step(s, { type: 'collect_trap', ...at(FERN) }, T0 + 24 * H);
    expect(r.ev).toContainEqual(expect.objectContaining({ kind: 'milestone', id: 'fishdex_10', coins: 100 }));
    expect(r.ev).toContainEqual(expect.objectContaining({ kind: 'reward', id: 'fishdex_10' }));
    expect(r.s.coins).toBe(coins + 100);
    const again = step(r.s, { type: 'collect_trap', ...at(FERN) }, T0 + 24 * H);
    expect(again.ev.filter(e => e.kind === 'milestone')).toEqual([]);
    for (const f of c.fish) again.s.fishing.caught[f.id] = 1;
    again.s.traps![0].fish = ['fish_carp'];
    const all = step(again.s, { type: 'collect_trap', ...at(FERN) }, T0 + 24 * H);
    expect(all.ev).toContainEqual(expect.objectContaining({ kind: 'milestone', id: 'fishdex_20', coins: 300, title: 'Fish-dex complete' }));
  });
});
