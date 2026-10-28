import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { buyback, sellDistance } from '../../src/p0/shops.js';

// q(251): home counters pay full price; away the Tackle Shop and the Market pay sell_distance's share for the Trip band of
// their city (Trip 1–2 90%, 3–4 80%, 5 70%, 6–7 60%), unit = max(1, ⌊full × share⌋); no daily limit at either. The real
// frozen clusters, from a San Francisco home: San Jose Trip 2, Los Angeles 4, Chicago 5, Tokyo 6 (q(251)'s own example).
const c = loadP0Content();   // not a structuredClone: the loader's clusters (non-enumerable) give the Trip bands
const T0 = Date.UTC(2026, 9, 10, 2, 0, 0);
const DAY = 86_400_000;
const SF = 'gn-5391959', SAN_JOSE = 'gn-5392171', LA = 'gn-5368361', CHICAGO = 'gn-4887398', TOKYO = 'gn-1850147';
const fresh = () => ({ ...freshState(c, 'player-sell-distance', T0, 7), created_at: T0 - 8 * DAY });
function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}

describe('selling by distance from home (q(251))', () => {
  it('home: the Homestead Stall always, and a Tackle Shop or Market in the home cluster, at full price', () => {
    const s = fresh();
    expect(sellDistance(c, s, 'tackle', SF)).toEqual({ home: true, factor: 1 });
    expect(sellDistance(c, s, 'market', SF)).toEqual({ home: true, factor: 1 });
    expect(sellDistance(c, s, 'homestead', TOKYO)).toEqual({ home: true, factor: 1 });   // the farm's stall is home's
    expect(buyback(c, 'tackle', 'fish_salmon', undefined, { s, cluster: SF })).toEqual({ unit: 32, quota: null });
  });

  it('away: the Trip band of the counter\'s city sets the share — Salmon 32 → 28 / 25 / 22 / 19', () => {
    const s = fresh();
    const at = (cluster: string) => buyback(c, 'tackle', 'fish_salmon', undefined, { s, cluster });
    expect(sellDistance(c, s, 'tackle', SAN_JOSE)).toEqual({ home: false, factor: 0.9, km: 66, trip: 2, band: 'Nearby' });
    expect(sellDistance(c, s, 'market', LA)).toEqual({ home: false, factor: 0.8, km: 558, trip: 4, band: 'Long Haul' });
    expect(sellDistance(c, s, 'tackle', CHICAGO)).toMatchObject({ factor: 0.7, trip: 5, band: 'Continental' });
    expect(sellDistance(c, s, 'tackle', TOKYO)).toMatchObject({ factor: 0.6, trip: 6, band: 'Intercontinental' });
    expect([SAN_JOSE, LA, CHICAGO, TOKYO].map(at)).toEqual([28, 25, 22, 19].map(unit => ({ unit, quota: null })));
    // the Market the same, its city's climate deciding only what it takes
    expect(buyback(c, 'market', 'fish_salmon', 'Temperate', { s, cluster: TOKYO })).toEqual({ unit: 19, quota: null });
  });

  it('a fallback city (the nearest three, Trip 1) is not home: 90%', () => {
    const s = fresh();
    const near = s.travel.fallback.near3[0];
    expect(sellDistance(c, s, 'tackle', near)).toMatchObject({ home: false, factor: 0.9, trip: 1 });
  });

  it('never below 1 coin: ⌊1 × 0.6⌋ sells for 1', () => {
    const cheap = structuredClone(c);
    Object.defineProperty(cheap, 'clusters', { value: (c as unknown as { clusters: unknown }).clusters });
    cheap.fish.find(f => f.id === 'fish_salmon')!.price = 1;
    expect(buyback(cheap, 'tackle', 'fish_salmon', undefined, { s: fresh(), cluster: TOKYO })).toEqual({ unit: 1, quota: null });
  });

  it('a sale away pays the share and has no daily limit; the view shows it on the counter', () => {
    let s = step(fresh(), { type: 'travel', to: LA }).s;   // a Day Pass there (free in the first version)
    s.bag.push({ id: 'fish_salmon', qty: 20 });
    const r = step(s, { type: 'sell', item: 'fish_salmon', qty: 'all', shop: 'tackle', space: 'outpost', place: `${LA}~tackle0` } as P0Command);
    expect(r.ev).toContainEqual({ kind: 'sale', item: 'fish_salmon', qty: 20, asked: 20, coins: 500, shop: 'tackle', quota: null });
    s = r.s;
    const v = viewOf(c, s, T0);
    expect(v.shops.tackle.distance).toEqual({ home: false, factor: 0.8, km: 558, trip: 4, band: 'Long Haul' });
    expect(v.shops.tackle.sell).toEqual([{ kind: 'fish', rate: 0.8, quota: null }]);   // an older client shows what it pays
    expect((v.shops.market.sell as { rate: number; quota: unknown }[]).every(x => x.rate === 0.8 && x.quota === null)).toBe(true);
    expect(v.shops.homestead.distance).toEqual({ home: true, factor: 1 });
    expect(v.shops.homestead.sell).toContainEqual({ kind: 'dish', rate: 1, quota: 'dish' });   // the Stall's caps stay
  });

  it('the retired quotas are gone from the view; the Stall\'s dish and material caps stay', () => {
    expect(Object.keys(viewOf(c, fresh(), T0).quotas).sort()).toEqual(['dish', 'material', 'request_bonus', 'sys_requests']);
  });
});
