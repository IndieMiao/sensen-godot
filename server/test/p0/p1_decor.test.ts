import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { decorCap, decorOf, spotBlock, yardRoom } from '../../src/p0/decor.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { storable } from '../../src/p0/shops.js';

// Decorate (SGODOT-284; plan §9.11.6, §8.3, q(29)).
const content = loadP0Content();
const c = { ...content, profile: { ...content.profile, timezone: 'Asia/Shanghai' } };
const T0 = Date.UTC(2026, 9, 10, 2, 0, 0);
const DAY = 86_400_000;
const HOME = { space: 'home' } as const;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const refuse = (s: P0State, cmd: P0Command, now = T0) => applyP0(c, s, cmd, now);
const fresh = () => { const s = { ...freshState(c, 'player-decor', T0, 3), created_at: T0 - 8 * DAY }; s.coins = 2000; return s; };

describe('the Decor page (§9.11.6)', () => {
  it('ten pieces at the Homestead Stall, each from its Homestead level; the Recipe Stand is not sold', () => {
    const buy = viewOf(c, fresh(), T0).shops.homestead.buy.map(o => o.id);
    for (const id of ['deco_planter', 'deco_lantern', 'deco_path', 'deco_bench', 'deco_scarecrow', 'deco_fence', 'deco_birdbath', 'deco_windmill', 'deco_fountain', 'deco_pergola'])
      expect(buy, id).toContain(id);
    expect(buy).not.toContain('recipe_stand');
    // q(111) / q(113): every single piece has a short line (≤ 14 characters, a greyed button's second line); the
    // multi-piece ones read `5 pieces` instead
    for (const [id, d] of Object.entries(decorOf(c)!.items)) {
      if (d.pieces > 1) { expect(d.blurb, id).toBeUndefined(); continue; }
      expect(d.blurb, id).toMatch(/^[A-Z][a-z ]/);   // sentence case (`A sunny seat`, q(131))
      expect(d.blurb?.length ?? 99, id).toBeLessThanOrEqual(14);   // q(131): the four rewritten ones fit 14 too (Bluebird perch)
    }
    expect(Object.values(decorOf(c)!.items).filter(d => d.buy).reduce((n, d) => n + d.price, 0)).toBe(1420);   // §9.15.2's catalog total
  });

  it('a purchase goes to Farm Storage, the path and fence come as 5 and 6 pieces, 1 a day each; never the bag, never sold', () => {
    let s = fresh();
    s = step(s, { type: 'buy', item: 'deco_planter', qty: 1, shop: 'homestead', ...HOME }).s;
    expect(s.storage.deco_planter).toBe(1);
    expect(count(s.bag, 'deco_planter')).toBe(0);
    expect(s.coins).toBe(1970);
    s = step(s, { type: 'buy', item: 'deco_path', qty: 1, shop: 'homestead', ...HOME }).s;
    expect(s.storage.deco_path).toBe(5);
    expect(refuse(s, { type: 'buy', item: 'deco_planter', qty: 1, shop: 'homestead', ...HOME })).toMatchObject({ ok: false, code: 'sold_out' });
    expect(step(s, { type: 'buy', item: 'deco_planter', qty: 1, shop: 'homestead', ...HOME }, T0 + DAY).s.storage.deco_planter).toBe(2);
    expect(storable(c, 'deco_planter')).toBe(false);   // never taken to the bag
    expect(refuse(s, { type: 'take_out', item: 'deco_planter', qty: 1, ...HOME } as never)).toMatchObject({ ok: false });
    expect(refuse(s, { type: 'buy', item: 'deco_windmill', qty: 1, shop: 'homestead', ...HOME })).toMatchObject({ ok: false, code: 'homestead_level', detail: { need: 3 } });
  });
});

describe('placing in the yard', () => {
  const stocked = () => { const s = fresh(); s.storage = { deco_planter: 2, deco_bench: 1, deco_pergola: 1 }; return s; };

  it('place takes one from storage onto the yard; move is free; store puts it back', () => {
    let r = step(stocked(), { type: 'place_decor', item: 'deco_planter', x: 2, y: 18, ...HOME });
    expect(r.ev).toContainEqual({ kind: 'decor', action: 'placed', uid: 1, item: 'deco_planter', x: 2, y: 18, rot: 0 });
    expect(r.s.storage.deco_planter).toBe(1);
    expect(viewOf(c, r.s, T0).decor).toMatchObject({ placed: [{ uid: 1, id: 'deco_planter', x: 2, y: 18, rot: 0 }], used: 1, cap: 20, stored: { deco_planter: 1 } });
    const coins = r.s.coins;
    r = step(r.s, { type: 'move_decor', uid: 1, x: 4, y: 18, ...HOME });
    expect(r.s.decor?.placed[0]).toMatchObject({ x: 4, y: 18 });
    expect(r.s.coins).toBe(coins);
    r = step(r.s, { type: 'store_decor', uid: 1, ...HOME });
    expect(r.s.decor?.placed).toEqual([]);
    expect(r.s.storage.deco_planter).toBe(2);
  });

  it('refuses the field and off the yard, objects and other pieces, the paths and an empty storage; only at home', () => {
    let s = stocked();
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 6, y: 5, ...HOME })).toMatchObject({ ok: false, code: 'decor_outside' });   // the field
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 9, y: 16, ...HOME })).toMatchObject({ ok: false, code: 'decor_overlap' });  // the house: Space taken
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 12, y: 16, ...HOME })).toMatchObject({ ok: false, code: 'decor_overlap' }); // the mailbox
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 6, y: 13, ...HOME })).toMatchObject({ ok: false, code: 'decor_overlap' });  // the front fence
    // q(120): Keep the path clear — two cells wide to the door, the stall, the workbench, one to before the bench (no mine mouth since 355 b1); the path to
    // the map exit now runs through the field (355 grid), so it is the field that keeps it clear
    for (const [x, y] of [[9, -1], [10, -2]] as const)
      expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x, y, ...HOME })).toMatchObject({ ok: false, code: 'decor_outside' });
    for (const [x, y, where] of [[8, 14, 'door'], [10, 13, 'door'], [13, 14, 'stall'], [17, 15, 'workbench'], [6, 15, 'bench'], [7, 15, 'bench']] as const)
      expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x, y, ...HOME }), where).toMatchObject({ ok: false, code: 'decor_path' });
    for (const [x, y] of [[1, 13], [2, 14], [4, 13]] as const)   // the mine mouth and its path were here (355 b1, v4q(5) ①)
      expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x, y, ...HOME })).toMatchObject({ ok: true });
    expect(refuse(s, { type: 'place_decor', item: 'deco_bench', x: 4, y: 15, ...HOME })).toMatchObject({ ok: true });
    expect(refuse(s, { type: 'place_decor', item: 'deco_bench', x: 3, y: 14, ...HOME })).toMatchObject({ ok: false, code: 'decor_overlap' });   // (4, 14): under the Chef's Sign's board
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 0, y: 18, ...HOME })).toMatchObject({ ok: false, code: 'decor_outside' });  // off the yard
    s = step(s, { type: 'place_decor', item: 'deco_bench', x: 6, y: 18, ...HOME }).s;   // 2 × 1: cells 6–7, 18
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 7, y: 18, ...HOME })).toMatchObject({ ok: false, code: 'decor_overlap' });
    expect(refuse(s, { type: 'place_decor', item: 'deco_lantern', x: 4, y: 18, ...HOME })).toMatchObject({ ok: false, code: 'not_stored' });
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 4, y: 18, space: 'mine' })).toMatchObject({ ok: false, code: 'not_home' });
    // a rotated piece takes h × w: the 3 × 2 pergola turned stands 2 wide and 3 tall
    expect(spotBlock(c, s, 'deco_pergola', 1, 16, 1)).toBeNull();
    // its third row would be row 19, behind the Homestead fence ring (李元芳's 0.2.1 smoke d83191bb)
    expect(spotBlock(c, s, 'deco_pergola', 4, 17, 1)).toMatchObject({ code: 'decor_outside' });
    expect(spotBlock(c, s, 'deco_fountain', 5, 18, 0)).toMatchObject({ code: 'decor_outside' });   // on the back wall
    expect(spotBlock(c, s, 'deco_planter', 19, 14, 0)).toMatchObject({ code: 'decor_outside' });   // on the east wall
    expect(spotBlock(c, s, 'deco_pergola', 4, 17, 0)).toMatchObject({ code: 'decor_overlap' });   // 3 × 2 would reach the tree at (6, 17)
    // the garden's own dressing is taken (不知火舞 on 290): a tree, a rock; the sign by the gate and the bush now stand
    // inside the field (355 grid), which keeps them clear first
    for (const [x, y, what] of [[12, 18, 'tree'], [16, 18, 'rock']] as const)
      expect(spotBlock(c, s, 'deco_planter', x, y, 0), what).toMatchObject({ code: 'decor_overlap' });
    for (const [x, y, what] of [[7, -1, 'sign'], [1, 0, 'bush']] as const)
      expect(spotBlock(c, s, 'deco_planter', x, y, 0), what).toMatchObject({ code: 'decor_outside' });
  });

  it('yard2 (v4q(12)): paths2 — the way to the bench past the porch and to the mailbox — kept clear for that client alone', () => {
    const s = stocked();
    for (const [x, y] of [[6, 14], [12, 14], [12, 15]]) {
      expect(applyP0(c, s, { type: 'place_decor', item: 'deco_planter', x, y, ...HOME } as P0Command, T0, { wing8: true, yard2: true }), `${x},${y}`)
        .toMatchObject({ ok: false, code: 'decor_path', detail: { x, y } });
      expect(applyP0(c, s, { type: 'place_decor', item: 'deco_planter', x, y, ...HOME } as P0Command, T0, { wing8: true }).ok, `${x},${y} older`).toBe(true);
    }
    const r = step(s, { type: 'place_decor', item: 'deco_planter', x: 13, y: 15, ...HOME });
    expect(applyP0(c, r.s, { type: 'move_decor', uid: 1, x: 12, y: 15, ...HOME } as P0Command, T0, { yard2: true })).toMatchObject({ ok: false, code: 'decor_path' });
    expect(spotBlock(c, s, 'deco_pergola', 11, 13, 0, undefined, { yard2: true })).toMatchObject({ code: 'decor_overlap' });   // objects come first, as before
    expect(spotBlock(c, s, 'deco_planter', 12, 16, 0, undefined, { yard2: true })).toMatchObject({ code: 'decor_overlap' });   // the mailbox itself
  });

  it('the cap is 20 + 4 per Homestead level above 1 (§8.3.2)', () => {
    const s = stocked();
    expect(decorCap(c, s)).toBe(20);
    s.homestead.level = 4;
    expect(decorCap(c, s)).toBe(32);
    s.homestead.level = 1;
    s.decor = { placed: Array.from({ length: 20 }, (_, i) => ({ uid: i + 1, id: 'deco_planter', x: 99, y: i, rot: 0 as const })), count: 20 };
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 2, y: 18, ...HOME })).toMatchObject({ ok: false, code: 'decor_cap', detail: { cap: 20, used: 20 } });
  });

  it('stops at decor_max.max: 52 from Lv9 (the user, 11-02, 丁22; the yard has 58 free cells)', () => {
    const capped = structuredClone(c);
    (capped.homestead as { decor_max?: object }).decor_max = { base: 20, per_level: 4, max: 52 };
    const s = stocked();
    s.homestead.level = 8;
    expect(decorCap(capped, s)).toBe(48);
    s.homestead.level = 9;
    expect(decorCap(capped, s)).toBe(52);
    s.homestead.level = 17;
    expect(decorCap(capped, s)).toBe(52);
    expect(decorCap(c, s)).toBe(52);   // the content's own max
    delete (capped.homestead as { decor_max?: { max?: number } }).decor_max!.max;
    expect(decorCap(capped, s)).toBe(84);   // no max: the formula alone
  });
});

describe('yard2: the yard grows with the Home level (v4q(12), the user 11-10 bot 655)', () => {
  const NEW = { wing8: true, yard2: true };
  const at = (lv: number) => { const s = fresh(); s.homestead.level = lv; s.storage = { deco_planter: 9 }; return s; };
  const place = (s: P0State, x: number, y: number, f: object = NEW) => applyP0(c, s, { type: 'place_decor', item: 'deco_planter', x, y, ...HOME } as P0Command, T0, f);

  it('① the cap is min(20 + 4 per level, the cells the yard can take), no 52: the cells as 后裔 counted them (v4q(12) ① table, ④ taken)', () => {
    const want: [number, number, number][] = [[1, 55, 20], [7, 55, 44], [8, 48, 48], [9, 48, 48], [12, 48, 48], [13, 61, 61], [14, 102, 72], [15, 102, 76], [16, 102, 80], [17, 102, 84]];
    for (const [lv, room, cap] of want) {
      expect(yardRoom(c, at(lv), NEW), `Lv${lv} cells`).toBe(room);
      expect(decorCap(c, at(lv), NEW), `Lv${lv} cap`).toBe(cap);
    }
    // an older client: as before, 52 from Lv9 (⑦)
    expect(decorCap(c, at(9), { wing8: true })).toBe(52);
    expect(decorCap(c, at(17))).toBe(52);
  });

  it('① the Compost Bin takes a cell, so one less; pieces already placed are not taken from it, and over the cap they stay', () => {
    const s = at(9);
    s.facilities = [{ id: 1, kind: 'compost_bin', plot: -1, cell: [4, 15] }];
    expect(decorCap(c, s, NEW)).toBe(47);
    const full = at(9), free: [number, number][] = [];
    for (let y = 13; y < 19; y++) for (let x = 1; x < 19; x++) if (!spotBlock(c, full, 'deco_planter', x, y, 0, undefined, NEW)) free.push([x, y]);
    expect(free).toHaveLength(48);
    // 48 on every free cell and 2 more an older client put on the new paths (q(303): not taken back)
    full.decor = { placed: [...free, [6, 14], [12, 15]].map(([x, y], i) => ({ uid: i + 1, id: 'deco_planter', x, y, rot: 0 as const })), count: 50 };
    expect(decorCap(c, full, NEW)).toBe(48);   // the pieces' own cells still count as cells the yard can take
    expect(place(full, 2, 18)).toMatchObject({ ok: false, code: 'decor_cap', detail: { cap: 48, used: 50 } });
    expect(viewOf(c, full, T0, NEW).decor).toMatchObject({ cap: 48, used: 50 });
  });

  it('③ ④ Lv13 opens row 19, Lv14 columns 19–20 (the field\'s two east columns too, its rocks off); an older client\'s yard never grows', () => {
    expect(place(at(12), 2, 19)).toMatchObject({ ok: false, code: 'decor_outside' });
    expect(place(at(13), 2, 19).ok).toBe(true);
    expect(place(at(13), 3, 19)).toMatchObject({ ok: false, code: 'decor_overlap' });   // a rock, registered
    expect(place(at(13), 19, 14)).toMatchObject({ ok: false, code: 'decor_outside' });
    for (const [x, y] of [[19, 14], [20, 19], [19, -2], [20, 12]]) expect(place(at(14), x, y).ok, `${x},${y}`).toBe(true);
    expect(place(at(14), 20, 4)).toMatchObject({ ok: false, code: 'decor_overlap' });    // the rocks in the field's edge
    expect(place(at(14), 18, 11)).toMatchObject({ ok: false, code: 'decor_outside' });   // the field still ends at x 18
    expect(place(at(17), 2, 19, { wing8: true })).toMatchObject({ ok: false, code: 'decor_outside' });
    expect(place(at(17), 19, 14, { wing8: true })).toMatchObject({ ok: false, code: 'decor_outside' });
  });

  it('the view says the next level\'s cap with the yard counted (`Home Lv13 adds 13`); none at the top, none for an older client', () => {
    expect(viewOf(c, at(8), T0, NEW).decor).toMatchObject({ cap: 48, next_cap: 48 });
    expect(viewOf(c, at(12), T0, NEW).decor).toMatchObject({ cap: 48, next_cap: 61 });
    expect(viewOf(c, at(13), T0, NEW).decor).toMatchObject({ cap: 61, next_cap: 72 });
    expect(viewOf(c, at(17), T0, NEW).decor).toMatchObject({ cap: 84, next_cap: null });
    expect('next_cap' in viewOf(c, at(12), T0, { wing8: true }).decor!).toBe(false);
  });

  it('the view says the cells now and next (What changes: `Decor 61 · Yard +13 spaces`) and the first level that adds (不知火舞 spec v1)', () => {
    expect(viewOf(c, at(12), T0, NEW).decor).toMatchObject({ room: 48, next_room: 61, grows: { level: 13, adds: 13 } });
    expect(viewOf(c, at(13), T0, NEW).decor).toMatchObject({ room: 61, next_room: 102, grows: { level: 14, adds: 11 } });
    expect(viewOf(c, at(8), T0, NEW).decor).toMatchObject({ grows: { level: 13, adds: 13 } });   // Lv8–12: Lv13 is the next that adds
    expect(viewOf(c, at(7), T0, NEW).decor).toMatchObject({ grows: { level: 8, adds: 4 } });
    expect(viewOf(c, at(17), T0, NEW).decor).toMatchObject({ room: 102, next_room: null, grows: null });
    expect('grows' in viewOf(c, at(12), T0, { wing8: true }).decor!).toBe(false);
  });

  it('the upgrade that grows the yard says the cap and the spaces it gained on HOME-2 (yard2 only)', () => {
    const up = (lv: number, f: object) => {
      const s = at(lv);
      const next = c.homestead.levels.find(l => l.level === lv + 1)!;
      for (const [id, qty] of next.materials) s.storage[id] = qty;
      s.coins = next.coins + 1000;
      for (const [skill, n] of Object.entries(next.skills)) s.skills[skill as 'farming'] = (c.skills as Record<string, number[]>)[skill][(n as number) - 1];
      for (const sk of ['farming', 'fishing', 'cooking'] as const) s.skills[sk] = Math.max(s.skills[sk], (c.skills as Record<string, number[]>)[sk][9]);
      if (next.travel) { s.travel.stamps = Array.from({ length: 20 }, (_, i) => `x${i}`) as never; }
      const r = applyP0(c, s, { type: 'homestead_upgrade', ...HOME } as P0Command, T0, f);
      if (!r.ok) throw new Error(`Lv${lv}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
      return r.events.find(e => e.kind === 'homestead') as { yard?: object };
    };
    expect(up(12, NEW).yard).toEqual({ cap: 61, spaces: 13 });
    expect(up(13, NEW).yard).toEqual({ cap: 72, spaces: 41 });
    expect(up(11, NEW).yard).toBeUndefined();
    expect(up(12, { wing8: true }).yard).toBeUndefined();
  });
});
