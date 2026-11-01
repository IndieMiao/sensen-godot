/** v4q(3) (contract-c §3, §5): a save freezes the free 3 wild sites and the priced guarantee's 4 with its city fallback —
 * at creation, again when the home is picked or changed — and the view sends them (view.wild). The real catalogue. */
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { wildById, wildNearOf, wildPricedOf } from '../../src/p0/wild.js';
import type { WorldContent } from '../../src/p0/world.js';

const c: P0Content = loadP0Content();
const w = (c as P0Content & { world: WorldContent }).world;
const SF = 'gn-5391959', TOKYO = 'gn-1850147', T0 = Date.parse('2026-11-02T15:00:00Z');
const opened = (() => {
  const o = Object.create(Object.getPrototypeOf(c), Object.getOwnPropertyDescriptors(c)) as P0Content & { world: WorldContent };
  o.world = { ...w, home: { ...(w as { home?: object }).home, cities: [TOKYO] } } as WorldContent;
  return o;
})();

describe('the wild sites a save freezes (v4q(3))', () => {
  it('a new save freezes San Francisco\'s free 3 (a quarry and a vein among them) and the priced 4', () => {
    const s = freshState(c, 'wild-frozen-1', T0);
    expect(s.travel.wild_near3).toEqual(wildNearOf(c, SF));
    expect(s.travel.wild_priced).toEqual(wildPricedOf(c, SF));
    const types = s.travel.wild_near3!.map(id => wildById(c, id)!.type);
    expect(types).toContain('quarry');
    expect(types).toContain('vein');
    expect(s.travel.wild_priced).toHaveLength(4);
    const v = viewOf(c, s, T0) as { wild: { near3: string[]; here: unknown } };
    expect(v.wild).toEqual({ near3: s.travel.wild_near3, here: null });   // at home: no wild site here
  });

  it('picking a home freezes that city\'s lists instead', () => {
    const r = applyP0(opened, freshState(opened, 'wild-frozen-2', T0, 7, { pending: true }), { type: 'choose_home', city: TOKYO, spot: 0 } as unknown as P0Command, T0);
    if (!r.ok) throw new Error(r.code);
    expect(r.state.travel.wild_near3).toEqual(wildNearOf(opened, TOKYO));
    expect(r.state.travel.wild_priced).toEqual(wildPricedOf(opened, TOKYO));
    expect(r.state.travel.wild_near3).not.toEqual(wildNearOf(opened, SF));
  });
});
