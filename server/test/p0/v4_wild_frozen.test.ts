/** v4q(3) (contract-c §3, §5): a save freezes the free 3 wild sites and the priced guarantee's 4 with its city fallback —
 * at creation, again when the home is picked or changed — and the view sends them (view.wild). The real catalogue. */
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { parseBbox, siteFor, viewport, wildById, wildNearOf, wildPricedOf } from '../../src/p0/wild.js';
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

  it('a save sent back to the written city on load freezes its lists again (周瑜 on #635)', () => {
    const s = freshState(c, 'wild-frozen-3', T0);
    s.travel.home = TOKYO; s.travel.here = TOKYO;   // a home never picked that is not the written city (q(163) ③)
    s.travel.wild_near3 = wildNearOf(c, TOKYO); s.travel.wild_priced = wildPricedOf(c, TOKYO);
    const up = upgradeState(c, structuredClone(s) as P0State, T0);
    expect(up.travel.home).toBe(SF);
    expect(up.travel.wild_near3).toEqual(wildNearOf(c, SF));
    expect(up.travel.wild_priced).toEqual(wildPricedOf(c, SF));
  });

  it('a picked home brought back from its home set on load freezes that city\'s lists again (周瑜 on #635)', () => {
    const r = applyP0(opened, freshState(opened, 'wild-frozen-4', T0, 7, { pending: true }), { type: 'choose_home', city: TOKYO, spot: 0 } as unknown as P0Command, T0);
    if (!r.ok) throw new Error(r.code);
    const rolled = structuredClone(r.state) as P0State;   // a rollback moved home to the written city, the pick's fields kept
    rolled.travel.home = SF; rolled.travel.here = SF;
    rolled.travel.wild_near3 = wildNearOf(opened, SF); rolled.travel.wild_priced = wildPricedOf(opened, SF);
    const up = upgradeState(opened, rolled, T0);
    expect(up.travel.home).toBe(TOKYO);
    expect(up.travel.wild_near3).toEqual(wildNearOf(opened, TOKYO));
    expect(up.travel.wild_priced).toEqual(wildPricedOf(opened, TOKYO));
  });

  it('a site says the deepest floor the player reached in its mine — the viewport and view.wild.here alike (contract-c §3)', () => {
    const s = freshState(c, 'wild-best-1', T0);
    const [id, other] = s.travel.wild_near3!, site = wildById(c, id)!;
    expect(siteFor(c, s, site, T0).best_floor).toBe(0);   // not been down
    s.mine.records[id] = { deepest: 14, guards: [10], first_at: T0 };
    expect(siteFor(c, s, site, T0).best_floor).toBe(14);
    expect(siteFor(c, s, wildById(c, other)!, T0).best_floor).toBe(0);   // a record is its own mine's
    const box = parseBbox(`${site.lat - 0.3},${site.lng - 0.3},${site.lat + 0.3},${site.lng + 0.3}`)!;
    expect(viewport(c, s, box, 10, T0).sites.find(x => x.id === id)?.best_floor).toBe(14);
    s.travel.here = id;
    expect((viewOf(c, s, T0) as { wild: { here: { id: string; best_floor: number } } }).wild.here).toMatchObject({ id, best_floor: 14 });
  });
});
