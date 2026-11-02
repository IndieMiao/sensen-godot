/** v4q(3) ④ (SGODOT-355 C, contract-c §5–§8): travel to a wild site — its Trip from the home's base point, the nearest 3
 * free, a grey pin refused, a visit and a Day Pass but no stamp, no first visit's +10 and no Regular; the priced guarantee
 * behind wild.fares; a wild mine checked like a pond and counted as that site, not home; a save keeps its wild pass. */
import { afterEach, describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { homeBase } from '../../src/p0/home.js';
import type { P0Event } from '../../src/p0/progress.js';
import { applyP0 } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { fareOf, noteDelivery, preview, requirePass, settleHere, travel } from '../../src/p0/travel.js';
import { viewOf } from '../../src/p0/view.js';
import { catalogueOf, useCatalogue, wildNearOf, wildPricedOf } from '../../src/p0/wild.js';
import { worldOf } from '../../src/p0/world.js';

const SF = 'gn-5391959', T = Date.parse('2026-11-02T18:00:00Z'), G = 0.5;
const TYPES = ['quarry', 'vein', 'geode', 'abyss', 'ruin', 'woodland', 'waterside', 'bloom'];
const FIELDS = ['row', 'col', 'lat', 'lng', 'type', 'main', 'side', 'floors', 'coastal', 'near', 'word', 'country'];
const cellOf = (lat: number, lng: number) => [Math.floor((lat + 90) / G), Math.floor((lng + 180) / G)];

let content: P0Content | null = null;
afterEach(() => { if (content) useCatalogue(content, null); content = null; });

/** Sites at (dLat, dLng) from San Francisco's base point; returns their ids in the order given. */
function setup(rows: [number, number, string, string?][], fares?: { guarantee: boolean; max_trip: number; min_trip: number }) {
  const c = loadP0Content(); content = c;
  const w = worldOf(c)!, base = homeBase(c, { travel: { home: SF } })!;
  if (fares) (w as unknown as { wild: { fares: unknown } }).wild.fares = fares;
  const ids: string[] = [];
  const table = { seed: w.seed, revision: w.revision, grid_deg: G, types: TYPES, fields: FIELDS, rows: rows.map(([dLat, dLng, type, main], i) => {
    const lat = base.lat + dLat, lng = base.lng + dLng, [row, col] = cellOf(lat, lng);
    ids.push(`wd-${row}-${col}`);
    return [row, col, lat, lng, TYPES.indexOf(type), type === 'vein' ? main ?? 'iron_ore' : null, 0, 30, 0, SF, `W${i}`, 'US'];
  }) };
  useCatalogue(c, catalogueOf(c, table));
  const s = freshState(c, 'wild-travel', T);
  s.coins = 5000;
  return { c, s, ids };
}
// near: two quarries and a vein within ~60 km; far: a vein ~250 km, a quarry ~390 km, a grey geode
const ROWS: [number, number, string, string?][] = [[0.3, 0.3, 'quarry'], [0.4, -0.3, 'quarry'], [-0.5, 0.2, 'vein', 'iron_ore'],
  [2.2, 0.6, 'vein', 'quartz'], [-3.5, 0.6, 'quarry'], [1.3, 1.5, 'geode']];

describe('travel to a wild site (v4q(3) ④)', () => {
  it('the free 3 (the nearest quarry, iron vein and quartz vein) cost nothing; another, its Trip from the home\'s base point; a grey pin and an unknown id refused', () => {
    const { c, s, ids } = setup(ROWS);
    expect(wildNearOf(c, SF)).toEqual([ids[0], ids[2], ids[3]]);   // the user, 11-02 庚3: one of each, the quartz vein ~250 km away too
    for (const id of [ids[0], ids[2], ids[3]]) expect(fareOf(c, s, id, T)).toMatchObject({ energy: 0, coins: 0 });
    const far = preview(c, s, ids[4], T);
    expect(far).toMatchObject({ wild: true, type: 'quarry', open: true, free: false, country: '' });
    expect(far.trip).toBeGreaterThanOrEqual(3);
    expect(far.cost.coins).toBeGreaterThan(0);
    expect(preview(c, s, ids[1], T).free).toBe(false);   // the second quarry, near as it is, is not one of the free 3
    expect(travel(c, s, ids[5], T, [])).toEqual({ code: 'not_open', detail: { type: 'geode' } });
    expect(travel(c, s, 'wd-1-1', T, [])).toEqual({ code: 'unknown_place' });
  });

  it('arriving: a visit and a Day Pass, here is the site; no stamp, no +10, no Explorer medal, never a Regular', () => {
    const { c, s, ids } = setup(ROWS);
    const r = applyP0(c, s, { type: 'travel', to: ids[3] }, T);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const t = r.state.travel, events = r.events as P0Event[];
    expect(t.here).toBe(ids[3]);
    expect(t.visits[ids[3]]).toMatchObject({ n: 1 });
    expect(t.passes[ids[3]].until).toBe(T + 24 * 3_600_000);
    expect(t.stamps).toEqual([]);
    expect(events.find(e => e.kind === 'arrival')).toMatchObject({ cluster: ids[3], first: true, stamp: null, energy: 0, wild: true });
    expect(events.some(e => e.kind === 'energy' && (e as { reason?: string }).reason === 'first_visit')).toBe(false);
    noteDelivery(c, r.state, T + 1000);
    expect(r.state.travel.visits[ids[3]].deliveries).toBe(0);
  });

  it('the priced guarantee (wild.fares; the user, 11-02 丁7): the nearest iron and quartz veins and 2 quarries at most Trip 2, the rest at least Trip 2', () => {
    const fares = { guarantee: true, max_trip: 2, min_trip: 2 };
    const { c, s, ids } = setup([...ROWS, [0.6, 0.6, 'quarry']], fares);
    expect(wildPricedOf(c, SF).sort()).toEqual([ids[0], ids[1], ids[2], ids[3]].sort());   // iron, quartz, the nearest 2 quarries
    const at = (id: string) => fareOf(c, s, id, T);
    const trip2 = c.travel!.fares!.coins[1];
    expect(at(ids[3]).coins).toBe(0);                      // the quartz vein ~250 km: one of the free 3 now (庚3)
    expect(at(ids[1]).coins).toBe(trip2);                  // the second quarry, priced, ~47 km (Trip 1): outside the free 3, Trip 2
    expect(at(ids[6]).coins).toBe(trip2);                  // a quarry outside the free 3 within Trip 1–2 costs at least Trip 2
    expect(at(ids[4]).coins).toBe(c.travel!.fares!.coins[2]);   // the far quarry, not priced: its own Trip 3
  });

  it('a wild mine needs its pass and being there; inside, here is the site, not home', () => {
    const { c, s, ids } = setup(ROWS);
    expect(requirePass(c, s, 'mine', ids[3], T)).toMatchObject({ code: 'pass_required', detail: { preview: { wild: true } } });
    expect(requirePass(c, s, 'mine', undefined, T)).toBeNull();   // without its place: E's mine_enter checks here
    const r = applyP0(c, s, { type: 'travel', to: ids[3] }, T);
    if (!r.ok) throw new Error(r.code);
    const there = r.state;
    there.travel.here = there.travel.home;                      // back on the farm
    settleHere(c, there, 'mine', ids[3], T + 1000);
    expect(there.travel.here).toBe(ids[3]);
    settleHere(c, there, 'mine', undefined, T + 2000);
    expect(there.travel.here).toBe(ids[3]);                     // a mine read without its place leaves here as it is
    settleHere(c, there, 'home', undefined, T + 3000);
    expect(there.travel.here).toBe(there.travel.home);          // the farm is home
  });

  it('no local requests at a wild site (v4q(3) B6 (a)): none drawn, no entry kept', () => {
    const { c, s, ids } = setup(ROWS);
    const r = applyP0(c, s, { type: 'travel', to: ids[3] }, T);
    if (!r.ok) throw new Error(r.code);
    expect((r.state as { locals?: Record<string, unknown> }).locals?.[ids[3]]).toBeUndefined();
    expect(r.state.markets?.[ids[3]]).toBeUndefined();   // nor a Market Board (hasMarket: no market square there)
  });

  it('a save keeps a wild site\'s pass and the player there; the view reads with the player at a wild site', () => {
    const { c, s, ids } = setup(ROWS);
    const r = applyP0(c, s, { type: 'travel', to: ids[3] }, T);
    if (!r.ok) throw new Error(r.code);
    const loaded = upgradeState(c, structuredClone(r.state) as P0State, T + 1000);
    expect(loaded.travel.here).toBe(ids[3]);
    expect(loaded.travel.passes[ids[3]]).toBeDefined();
    const v = viewOf(c, loaded, T + 1000) as { travel: { here: string; passes: Record<string, unknown>; visits: Record<string, unknown> } };
    expect(v.travel.here).toBe(ids[3]);
    expect(v.travel.passes[ids[3]]).toBeDefined();
    expect(v.travel.visits[ids[3]]).toBeDefined();
    const here = (v as unknown as { wild: { here: { id: string; visited: boolean; pass_until: number } | null } }).wild.here;
    expect(here).toMatchObject({ id: ids[3], visited: true, pass_until: T + 24 * 3_600_000 });   // contract-c §5
  });
});
