import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { decorCap, decorOf, spotBlock } from '../../src/p0/decor.js';
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

  it('refuses the field, the house, other pieces, the spawn path and an empty storage; only at home', () => {
    let s = stocked();
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 6, y: 5, ...HOME })).toMatchObject({ ok: false, code: 'decor_outside' });   // the field
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 9, y: 16, ...HOME })).toMatchObject({ ok: false, code: 'decor_outside' });  // the house
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 9, y: 1, ...HOME })).toMatchObject({ ok: false, code: 'decor_outside' });   // spawn
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 0, y: 18, ...HOME })).toMatchObject({ ok: false, code: 'decor_outside' });  // off the yard
    s = step(s, { type: 'place_decor', item: 'deco_bench', x: 6, y: 18, ...HOME }).s;   // 2 × 1: cells 6–7, 18
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 7, y: 18, ...HOME })).toMatchObject({ ok: false, code: 'decor_overlap' });
    expect(refuse(s, { type: 'place_decor', item: 'deco_lantern', x: 4, y: 18, ...HOME })).toMatchObject({ ok: false, code: 'not_stored' });
    expect(refuse(s, { type: 'place_decor', item: 'deco_planter', x: 4, y: 18, space: 'mine' })).toMatchObject({ ok: false, code: 'not_home' });
    // a rotated piece takes h × w: the 3 × 2 pergola turned stands 2 wide and 3 tall
    expect(spotBlock(c, s, 'deco_pergola', 1, 17, 1)).toBeNull();
    expect(spotBlock(c, s, 'deco_pergola', 1, 17, 0)).toMatchObject({ code: 'decor_outside' });   // 3 × 2 would reach the herb patch
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
});
