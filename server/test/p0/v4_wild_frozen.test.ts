/** v4q(3) (contract-c §3, §5): a save freezes the free 3 wild sites and the priced guarantee's 4 with its city fallback —
 * at creation, again when the home is picked or changed — and the view sends them (view.wild). The real catalogue. */
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { catalogue, near3Sites, nearestFreeVein, parseBbox, siteFor, viewport, wildById, wildNearOf, wildPricedOf } from '../../src/p0/wild.js';
import { siteContinent } from '../../src/p0/clusters.js';
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
    const v = viewOf(c, s, T0) as { wild: { near3: string[]; near3_sites: unknown[]; here: unknown } };
    expect(v.wild).toEqual({ near3: s.travel.wild_near3, near3_sites: near3Sites(c, s), here: null });   // at home: no wild site here
  });

  it('near3_sites: the free 3 in near3\'s order with type, main and name; the nearest free iron and quartz veins (v4q(9))', () => {
    const s = freshState(c, 'wild-frozen-sites', T0);
    const sites = (viewOf(c, s, T0) as { wild: { near3_sites: { id: string; type: string; main: string | null; name: string; lat: number; lng: number }[] } }).wild.near3_sites;
    expect(sites.map(x => x.id)).toEqual(s.travel.wild_near3);
    for (const x of sites) {
      const site = wildById(c, x.id)!;
      expect(x).toEqual({ id: site.id, type: site.type, main: site.mine?.main ?? null, name: site.name, lat: site.lat, lng: site.lng });   // lat / lng for Show (亚瑟)
      expect(x.name).toBe(siteFor(c, s, site, T0).name);   // the pin's and the mine card's name
    }
    expect(sites.map(x => x.type === 'quarry' ? 'quarry' : x.main).sort()).toEqual(['iron_ore', 'quarry', 'quartz']);   // 庚3: one of each
    const iron = nearestFreeVein(c, s, 'iron_ore')!, quartz = nearestFreeVein(c, s, 'quartz')!;
    expect(iron).toEqual({ id: sites.find(x => x.main === 'iron_ore')!.id, name: sites.find(x => x.main === 'iron_ore')!.name });
    expect(quartz.id).toBe(sites.find(x => x.main === 'quartz')!.id);
    expect(nearestFreeVein(c, s, 'copper_ore')).toBeNull();   // none of the 3
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

describe('the catalogue as made (v4 3.3; 李白\'s c6v4 count, 11-04)', () => {
  const c = loadP0Content();
  const sites = [...catalogue(c)!.byId.values()];
  it('a ruin on each continent, one each — Siberia counts as Asia, so Europe has its own', () => {
    expect(siteContinent('europe', 'RU', 162.7)).toBe('asia');   // Chukotka
    expect(siteContinent('europe', 'RU', 37.6)).toBe('europe');   // Moscow's side of the Urals
    expect(siteContinent('europe', 'FI', 25)).toBe('europe');
    const ruins = sites.filter(s => s.type === 'ruin').map(s => s.continent).sort();
    expect(ruins).toEqual(['africa', 'asia', 'europe', 'north_america', 'oceania', 'south_america']);
  });
  it('every region (continent × climate × coast) holds 1–3 abyss', () => {
    const all = new Map<string, number>(), abyss = new Map<string, number>();
    for (const s of sites) {
      const k = `${s.continent}|${s.climate}|${s.coastal}`;
      all.set(k, (all.get(k) ?? 0) + 1);
      if (s.type === 'abyss') abyss.set(k, (abyss.get(k) ?? 0) + 1);
    }
    for (const k of all.keys()) expect([1, 2, 3], k).toContain(abyss.get(k) ?? 0);
  });
});
