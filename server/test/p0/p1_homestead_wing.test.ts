import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { wingOf, wingTaken } from '../../src/p0/decor.js';
import { nearestYardCell } from '../../src/p0/garden.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

// q(303), SGODOT-450: Homestead Lv8's Kitchen Wing stands on seven yard cells. For a client that draws it (feature
// wing8): the upgrade into Lv8 waits until nothing holds them (homestead_blocked, next.blocked), from Lv8 they are the
// house's (`Space taken`) and a save that still has something there is told so (wing_blocked). Nothing is moved for the
// player (the user, 548); a client without wing8 keeps the yard and the upgrade as they were.
const c = loadP0Content();
const T0 = Date.UTC(2026, 10, 9, 6, 0, 0);
const WING8 = { wing8: true };
const WING: [number, number][] = [[5, 17], [5, 18], [6, 18], [7, 16], [7, 17], [7, 18], [8, 18]];

/** A Homestead Lv7 save with everything the Lv8 upgrade asks for. */
function lv7(): P0State {
  const s = freshState(c, 'player-wing', T0, 3);
  s.homestead.level = 7;
  s.coins = 2000;
  s.skills = { farming: 300, fishing: 480, cooking: 220 };
  for (const [id, qty] of c.homestead.levels.find(l => l.level === 8)!.materials) s.storage[id] = qty + 1;
  s.decor = { placed: [], count: 0 };
  s.facilities = [];
  return s;
}
const piece = (s: P0State, id: string, x: number, y: number, rot: 0 | 1 = 0) => {
  s.decor!.placed.push({ uid: ++s.decor!.count, id, x, y, rot });
  return s.decor!.count;
};
const bin = (s: P0State, x: number, y: number) => {
  s.facilities = [...(s.facilities ?? []), { id: (s.facility_count = (s.facility_count ?? 0) + 1), kind: 'compost_bin', plot: -1, cell: [x, y] }];
  return s.facility_count!;
};
const up: P0Command = { type: 'homestead_upgrade', space: 'home' } as P0Command;
const run = (s: P0State, cmd: P0Command, opts = WING8) => applyP0(c, s, cmd, T0, opts);

describe('the Kitchen Wing\'s cells (content decor.yard.wing)', () => {
  it('are the seven the wing stands on, from Homestead Lv8', () => {
    expect(wingOf(c)).toEqual({ homestead: 8, cells: WING });
  });

  it('what holds them: a piece with any cell on them (a 2×1 bench half over counts), pieces first, then yard facilities', () => {
    const s = lv7();
    expect(wingTaken(c, s)).toBeNull();
    piece(s, 'deco_planter', 3, 15);              // off the wing
    const bench = piece(s, 'deco_bench', 4, 17);  // (4,17)–(5,17): half on it
    const b = bin(s, 6, 18);
    const lamp = piece(s, 'deco_lantern', 7, 16);
    const t = wingTaken(c, s)!;
    expect(t.pieces.map(p => p.uid)).toEqual([bench, lamp]);
    expect(t.pieces[0]).toEqual({ uid: bench, item: 'deco_bench', x: 4, y: 17, rot: 0 });
    expect(t.facilities).toEqual([{ id: b, kind: 'compost_bin', x: 6, y: 18 }]);
    expect(t.cells).toEqual([[5, 17], [6, 18], [7, 16]]);   // in the content's order, only the taken
  });
});

describe('the upgrade into Lv8 (wing8)', () => {
  it('waits while something holds the wing\'s cells: homestead_blocked with what, nothing taken from the player', () => {
    const s = lv7();
    piece(s, 'deco_planter', 7, 16);
    const coins = s.coins, wood = s.storage.wood;
    const r = run(s, up);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe('homestead_blocked');
    expect(r.detail).toEqual({ cells: [[7, 16]], pieces: [{ uid: 1, item: 'deco_planter', x: 7, y: 16, rot: 0 }], facilities: [] });
    expect(s.homestead.level).toBe(7);
    expect(s.coins).toBe(coins);
    expect(s.storage.wood).toBe(wood);
  });

  it('is the last gap: a coin or material short is said first', () => {
    const s = lv7();
    piece(s, 'deco_planter', 7, 16);
    s.coins = 10;
    const r = run(s, up);
    expect(r.ok ? '' : r.code).toBe('no_coins');
  });

  it('goes through once they are clear (the piece moved off, the bin moved off)', () => {
    let s = lv7();
    const p = piece(s, 'deco_planter', 7, 16);
    const b = bin(s, 6, 18);
    for (const cmd of [{ type: 'move_decor', uid: p, x: 3, y: 17, space: 'home' }, { type: 'move_facility', facility: b, x: 2, y: 17, space: 'home' }]) {
      const r = run(s, cmd as P0Command);
      expect(r.ok, cmd.type).toBe(true);
      if (r.ok) s = r.state;
    }
    const r = run(s, up);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.state.homestead.level).toBe(8);
  });

  it('a client without wing8 upgrades as before, things and all', () => {
    const s = lv7();
    piece(s, 'deco_planter', 7, 16);
    const r = applyP0(c, s, up, T0);
    expect(r.ok).toBe(true);
  });
});

describe('the view (wing8)', () => {
  it('next.blocked before Lv8: can_upgrade false and block homestead_blocked; gone when clear; none without wing8', () => {
    const s = lv7();
    piece(s, 'deco_lantern', 5, 17);
    const v = viewOf(c, s, T0, WING8).homestead;
    expect(v.next?.blocked).toEqual({ cells: [[5, 17]], pieces: [{ uid: 1, item: 'deco_lantern', x: 5, y: 17, rot: 0 }], facilities: [] });
    expect(v.next?.can_upgrade).toBe(false);
    expect(v.next?.block?.code).toBe('homestead_blocked');
    expect('wing_blocked' in v).toBe(false);
    const old = viewOf(c, s, T0).homestead;
    expect(old.next && 'blocked' in old.next).toBe(false);
    expect(old.next?.can_upgrade).toBe(true);
    s.decor!.placed = [];
    const clear = viewOf(c, s, T0, WING8).homestead;
    expect(clear.next && 'blocked' in clear.next).toBe(false);
    expect(clear.next?.can_upgrade).toBe(true);
  });

  it('wing_blocked from Lv8 (a save that got there with things on the cells), not next.blocked; none without wing8', () => {
    const s = lv7();
    s.homestead.level = 8;
    const b = bin(s, 7, 18);
    const v = viewOf(c, s, T0, WING8).homestead;
    expect(v.wing_blocked).toEqual({ cells: [[7, 18]], pieces: [], facilities: [{ id: b, kind: 'compost_bin', x: 7, y: 18 }] });
    expect(v.next && 'blocked' in v.next).toBe(false);
    expect('wing_blocked' in viewOf(c, s, T0).homestead).toBe(false);
  });

  it('a move\'s answer already has the cells it cleared out of it', () => {
    const s = lv7();
    s.homestead.level = 8;
    const a = piece(s, 'deco_planter', 7, 16);
    piece(s, 'deco_lantern', 5, 17);
    const r = run(s, { type: 'move_decor', uid: a, x: 3, y: 17, space: 'home' } as P0Command);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(viewOf(c, r.state, T0, WING8).homestead.wing_blocked?.cells).toEqual([[5, 17]]);
  });
});

describe('from Lv8 the cells are the house\'s (wing8)', () => {
  it('a piece or a yard facility placed or moved onto one: decor_overlap (Space taken); at Lv7, or without wing8, as before', () => {
    const s = lv7();
    s.storage.deco_planter = 2;
    s.homestead.level = 8;
    const place = { type: 'place_decor', item: 'deco_planter', x: 7, y: 17, space: 'home' } as P0Command;
    const r = run(s, place);
    expect(r.ok ? '' : r.code).toBe('decor_overlap');
    expect(applyP0(c, s, place, T0).ok).toBe(true);
    const at7 = lv7();
    at7.storage.deco_planter = 1;
    expect(run(at7, place).ok).toBe(true);
    // moving a piece in, and the Compost Bin
    const p = piece(s, 'deco_lantern', 3, 15);
    const b = bin(s, 2, 17);
    expect((r => r.ok ? '' : r.code)(run(s, { type: 'move_decor', uid: p, x: 8, y: 18, space: 'home' } as P0Command))).toBe('decor_overlap');
    expect((r => r.ok ? '' : r.code)(run(s, { type: 'move_facility', facility: b, x: 6, y: 18, space: 'home' } as P0Command))).toBe('decor_overlap');
    expect(applyP0(c, s, { type: 'move_facility', facility: b, x: 6, y: 18, space: 'home' } as P0Command, T0).ok).toBe(true);
  });

  it('the nearest free yard cell for a facility skips them', () => {
    const s = lv7();
    s.homestead.level = 8;
    const from: [number, number] = [6, 18];
    expect(nearestYardCell(c, s, from, 0)).toEqual(from);
    const to = nearestYardCell(c, s, from, 0, undefined, true)!;
    expect(WING.some(([x, y]) => x === to[0] && y === to[1])).toBe(false);
  });
});
