/** q(256) (SGODOT-367 S1, 亚瑟's contract 043c0bc8 with 5b487f1f): travel costs the Trip band's Energy and coins, a
 * revisit half (rounded up), the wallet keeps 40, the fallback lists as before; option B — with a Day Pass still running
 * a new departure to that city pays the revisit fare and neither re-signs the pass nor counts a visit; requirePass
 * refuses walking into a city with a pass while `here` is another (travel_required). */
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Result } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { fareOf, preview, rankedCities, requirePass, tripOf } from '../../src/p0/travel.js';
import { viewOf } from '../../src/p0/view.js';

const SF = 'gn-5391959', LA = 'gn-5368361', TOKYO = 'gn-1850147';
const c: P0Content = structuredClone(loadP0Content());
Object.defineProperty(c, 'clusters', { value: (loadP0Content() as P0Content & { clusters?: unknown }).clusters });
const TOKYO_POND = `${TOKYO}~pond0`;
const T = Date.parse('2026-10-10T18:00:00Z');
const DAY = 86_400_000;
const ENERGY = [0, 10, 20, 30, 40, 50, 60], COINS = [0, 20, 60, 120, 200, 300, 500];

const fresh = (coins = 5000, energy = 200) => { const s = freshState(c, 'fare-player', T, 7); s.coins = coins; s.energy.value = energy; return s; };
const run = (s: P0State, cmd: P0Command, at = T): P0Result => applyP0(c, s, cmd, at);
function step(s: P0State, cmd: P0Command, at = T) { const r = run(s, cmd, at); if (!r.ok) throw new Error(`${r.code} ${JSON.stringify(r.detail ?? {})}`); return r; }

describe('fares (q(256) §11.2.1)', () => {
  it('the content table, and the view carries it as it is', () => {
    expect(c.travel?.fares).toEqual({ energy: ENERGY, coins: COINS });
    expect(viewOf(c, fresh(), T).travel.fares).toEqual({ energy: ENERGY, coins: COINS });
  });

  it('a first visit pays its Trip band, 1–7', () => {
    const s = fresh();
    const byTrip = new Map<number, string>();
    for (const r of rankedCities(c, s)) if (!byTrip.has(r.trip) && !s.travel.fallback.near10.includes(r.id)) byTrip.set(r.trip, r.id);
    for (let trip = 2; trip <= 7; trip++) {
      const city = byTrip.get(trip);
      if (!city) continue;   // every band the table reaches from San Francisco
      expect(tripOf(c, s, city).trip).toBe(trip);
      expect(fareOf(c, s, city, T)).toEqual({ energy: ENERGY[trip - 1], coins: COINS[trip - 1], revisit: false, renews: true });
    }
    expect([...byTrip.keys()].filter(t => t >= 2).length).toBeGreaterThanOrEqual(5);
    expect(fareOf(c, s, LA, T)).toEqual({ energy: 30, coins: 120, revisit: false, renews: true });   // Trip 4
    expect(fareOf(c, s, TOKYO, T)).toEqual({ energy: 50, coins: 300, revisit: false, renews: true });   // Trip 6
  });

  it('the nearest 3 cities are Trip 1, free; the nearest 10 cost at most Trip 2; home and the city the player is in cost nothing', () => {
    const s = fresh();
    for (const id of s.travel.fallback.near3) expect(fareOf(c, s, id, T)).toMatchObject({ energy: 0, coins: 0 });
    for (const id of s.travel.fallback.near10) {
      const f = fareOf(c, s, id, T);
      expect(f.energy).toBeLessThanOrEqual(ENERGY[1]);
      expect(f.coins).toBeLessThanOrEqual(COINS[1]);
    }
    expect(fareOf(c, s, SF, T)).toEqual({ energy: 0, coins: 0, revisit: false, renews: false });
    const there = step(s, { type: 'travel', to: LA }).state;
    expect(fareOf(c, there, LA, T + 1)).toMatchObject({ energy: 0, coins: 0, renews: false });
  });

  it('a Trip 1 trip takes nothing and needs no floor: a wallet under 40 still goes', () => {
    const s = fresh(10, 0);
    const r = step(s, { type: 'travel', to: s.travel.fallback.near3[0] });
    expect(r.state.coins).toBe(10);
    expect(r.events.filter(e => e.kind === 'coins' || (e.kind === 'energy' && e.delta < 0))).toEqual([]);
    expect(r.events).toContainEqual(expect.objectContaining({ kind: 'arrival', paid: { energy: 0, coins: 0 }, renewed: true }));
  });

  it('a revisit pays half, rounded up', () => {
    const odd = structuredClone(c);
    Object.defineProperty(odd, 'clusters', { value: (c as unknown as { clusters: unknown }).clusters });
    odd.travel!.fares = { energy: [0, 11, 21, 31, 41, 51, 61], coins: [0, 21, 61, 121, 201, 301, 501] };
    const s = fresh();
    s.travel.visits[LA] = { n: 1, first_at: T - 3 * DAY, last_at: T - 3 * DAY, deliveries: 0, delivered_day: '' };
    expect(fareOf(odd, s, LA, T)).toEqual({ energy: 16, coins: 61, revisit: true, renews: true });   // ⌈31/2⌉, ⌈121/2⌉
    expect(fareOf(c, s, LA, T)).toEqual({ energy: 15, coins: 60, revisit: true, renews: true });
  });
});

describe('travel takes the fare (q(256), contract E)', () => {
  it('the events in order: energy −, coins −, the first visit\'s +10, arrival with paid and renewed', () => {
    const s = fresh(1000, 100);
    const r = step(s, { type: 'travel', to: LA });
    const kinds = r.events.filter(e => ['energy', 'coins', 'arrival'].includes(e.kind)).map(e =>
      e.kind === 'energy' ? `energy ${e.delta} ${e.reason}` : e.kind === 'coins' ? `coins ${e.delta} ${e.reason}` : e.kind);
    expect(kinds).toEqual(['energy -30 travel', 'coins -120 travel', 'energy 10 first_visit', 'arrival']);
    expect(r.state.coins).toBe(880);
    expect(r.state.energy.value).toBe(80);
    expect(r.events.find(e => e.kind === 'arrival')).toMatchObject({ cluster: LA, first: true, paid: { energy: 30, coins: 120 }, renewed: true,
      pass_until: T + DAY });
  });

  it('the wallet keeps 40: exactly fare + 40 goes, a coin less is refused with need / have / cost / floor', () => {
    expect(step(fresh(160), { type: 'travel', to: LA }).state.coins).toBe(40);
    const s = fresh(159);
    const before = structuredClone(s);
    expect(run(s, { type: 'travel', to: LA })).toMatchObject({ ok: false, code: 'not_enough_coins', detail: { need: 1, have: 159, cost: 120, floor: 40 } });
    expect(s).toEqual(before);   // nothing taken, nothing changed
  });

  it('Energy short is refused with need / have / cost; with both short only the coins are named', () => {
    expect(run(fresh(1000, 29), { type: 'travel', to: LA })).toMatchObject({ ok: false, code: 'not_enough_energy', detail: { need: 1, have: 29, cost: 30 } });
    expect(run(fresh(100, 5), { type: 'travel', to: LA })).toMatchObject({ ok: false, code: 'not_enough_coins' });
    const s = fresh(1000, 29), before = structuredClone(s);
    run(s, { type: 'travel', to: LA });
    expect(s).toEqual(before);
  });

  it('back from home within the pass: the revisit fare, no new pass, no visit, no stamp, no +10 (option B)', () => {
    let s = step(fresh(), { type: 'travel', to: LA }).state;
    const until = s.travel.passes[LA].until;
    s = step(s, { type: 'return_home' }, T + 3_600_000).state;
    const coins = s.coins, energy = s.energy.value;
    const r = step(s, { type: 'travel', to: LA }, T + 2 * 3_600_000);
    expect(r.state.coins).toBe(coins - 60);
    expect(r.state.energy.value).toBe(energy - 15);
    expect(r.state.travel.passes[LA].until).toBe(until);
    expect(r.state.travel.visits[LA].n).toBe(1);
    expect(r.state.travel.stamps).toHaveLength(1);
    expect(r.state.travel.here).toBe(LA);
    expect(r.events.filter(e => e.kind === 'energy' && e.delta > 0)).toEqual([]);
    expect(r.events.find(e => e.kind === 'arrival')).toMatchObject({ first: false, stamp: null, energy: 0, renewed: false, pass_until: until,
      paid: { energy: 15, coins: 60 } });
  });

  it('after the pass ran out: the revisit fare, a new pass and a visit', () => {
    let s = step(fresh(), { type: 'travel', to: LA }).state;
    s = step(s, { type: 'return_home' }, T + 1000).state;
    const at = T + DAY + 1000;
    const r = step(s, { type: 'travel', to: LA }, at);
    expect(r.events.find(e => e.kind === 'arrival')).toMatchObject({ first: false, renewed: true, paid: { energy: 15, coins: 60 }, pass_until: at + DAY });
    expect(r.state.travel.visits[LA].n).toBe(2);
  });

  it('within X\'s pass to Y without one: Y\'s pass is signed at Y\'s fare, X\'s kept', () => {
    let s = step(fresh(), { type: 'travel', to: LA }).state;
    const laUntil = s.travel.passes[LA].until;
    const r = step(s, { type: 'travel', to: TOKYO }, T + 1000);
    s = r.state;
    expect(r.events.find(e => e.kind === 'arrival')).toMatchObject({ cluster: TOKYO, renewed: true, paid: { energy: 50, coins: 300 } });
    expect(s.travel.passes[TOKYO].until).toBe(T + 1000 + DAY);
    expect(s.travel.passes[LA].until).toBe(laUntil);
    expect(s.travel.here).toBe(TOKYO);
  });
});

describe('the preview and requirePass (contract C, F)', () => {
  it('the preview prices what travel would take, says revisit and until when the pass runs', () => {
    let s = fresh();
    expect(preview(c, s, LA, T)).toMatchObject({ cost: { energy: 30, coins: 120, item: null }, revisit: false, pass_until: null, first_visit: true });
    s = step(s, { type: 'travel', to: LA }).state;
    s = step(s, { type: 'return_home' }, T + 1000).state;
    expect(preview(c, s, LA, T + 2000)).toMatchObject({ cost: { energy: 15, coins: 60, item: null }, revisit: true, pass_until: T + DAY, first_visit: false });
    expect(preview(c, s, SF, T + 2000)).toMatchObject({ cost: { energy: 0, coins: 0, item: null }, pass_until: null });
  });

  it('a pass running but the player elsewhere: a new entry or cast is travel_required with the revisit preview', () => {
    const c2 = structuredClone(c);
    Object.defineProperty(c2, 'clusters', { value: (c as unknown as { clusters: unknown }).clusters });
    c2.fishing.places[TOKYO_POND] = { ...c2.fishing.places.pond_san_francisco_03, city: 'tokyo' } as never;
    let s = step(fresh(), { type: 'travel', to: TOKYO }).state;
    s = step(s, { type: 'return_home' }, T + 1000).state;
    const refused = requirePass(c2, s, 'pond', TOKYO_POND, T + 2000);
    expect(refused).toMatchObject({ code: 'travel_required', detail: { message: 'Travel first', preview: { cluster: TOKYO, revisit: true,
      cost: { energy: 25, coins: 150, item: null }, pass_until: T + DAY } } });
    // what is under way is never cut off: the place already entered, a line already out
    s.presence.entered = TOKYO_POND;
    expect(requirePass(c2, s, 'pond', TOKYO_POND, T + 2000, 'reel')).toBeNull();
    expect(requirePass(c2, s, 'pond', TOKYO_POND, T + 2000, 'cast')).toMatchObject({ code: 'travel_required' });
    // in the city: no refusal; home's places need nothing
    s.travel.here = TOKYO;
    expect(requirePass(c2, s, 'pond', TOKYO_POND, T + 2000, 'cast')).toBeNull();
    expect(requirePass(c2, s, 'pond', 'pond_san_francisco_03', T + 2000, 'cast')).toBeNull();
  });
});
