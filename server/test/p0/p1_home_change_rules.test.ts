/** SGODOT-303 0.2.6, three approved rows on choosing and changing a home: q(184) Trip from the home's base point,
 * q(173) the day a change of home carries over, q(177) traps in home ponds only and recalled on a change. */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { add, count } from '../../src/p0/bag.js';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { homeBase, homeFacts } from '../../src/p0/home.js';
import { dayHoldFor, homeSpots } from '../../src/p0/home_city.js';
import { TRAP } from '../../src/p0/fish_trap.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { dayKey, rolloverAfter, untilRollover } from '../../src/p0/rules.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { fallbackOf, rankedCities, tripOf } from '../../src/p0/travel.js';

const c: P0Content = loadP0Content();
const SF = 'gn-5391959', TOKYO = 'gn-1850147', LONDON = 'gn-2643743', LA = 'gn-5368361';
const H = 3_600_000, DAY = 24 * H;
const T = Date.UTC(2026, 9, 14, 1, 0);   // 18:00 PDT on 13 Oct in San Francisco
const run = (s: P0State, cmd: Record<string, unknown>, at = T) => applyP0(c, s, cmd as unknown as P0Command, at);
const ok = (r: ReturnType<typeof run>) => { if (!r.ok) throw new Error(r.code); return r; };
/** A San Francisco save that never picked (q(163) ③), a day old: it may change home once. */
const sfSave = (id = 'player-rules-01') => freshState(c, id, T - DAY, 5);
const pickedIn = (city: string, id: string) => ok(run(freshState(c, id, T - DAY, 5, { pending: true }), { type: 'choose_home', city, spot: 0 })).state;

describe('q(184): Trip, tiers and the fallback lists from the home base point', () => {
  it('two players of one city with different farm spots rank, tier and fall back alike', () => {
    const a = pickedIn(TOKYO, 'player-rules-a1'), b = ok(run(freshState(c, 'player-rules-b2', T - DAY, 5, { pending: true }), { type: 'choose_home', city: TOKYO, spot: 2 })).state;
    expect(a.travel.farm_at).not.toEqual(b.travel.farm_at);
    expect(homeBase(c, a)).toEqual(homeBase(c, b));
    expect(a.travel.fallback).toEqual(b.travel.fallback);
    expect(a.travel.fallback).toEqual(fallbackOf(c, TOKYO));
    expect(rankedCities(c, a)).toEqual(rankedCities(c, b));
    expect(tripOf(c, a, LONDON)).toEqual(tripOf(c, b, LONDON));
    expect(homeFacts(c, a).farm).toEqual({ lat: a.travel.farm_at![0], lng: a.travel.farm_at![1] });   // the pin stays the pick
  });

  it('San Francisco keeps its content point (Noe Valley), so saves there are unchanged', () => {
    const s = sfSave();
    expect(homeBase(c, s)).toEqual({ lat: c.profile.farm_at![0], lng: c.profile.farm_at![1] });
    expect(s.travel.fallback).toEqual(fallbackOf(c, SF));
  });
});

describe('q(173): a changed home carries its day to the new home\'s first fitting 04:00', () => {
  const change = (to: string, at = T) => ok(run(sfSave(), { type: 'change_home', city: to, spot: 0 }, at)).state;

  it('San Francisco → Tokyo: 32 h; → London: 40 h; → Los Angeles (one zone): 24 h', () => {
    for (const [to, hours] of [[TOKYO, 32], [LONDON, 40], [LA, 24]] as const) {
      const s = change(to), hold = s.travel.day_hold!;
      expect(hold.key).toBe('2026-10-13');
      expect((hold.until - hold.start) / H, to).toBe(hours);
      expect(hold.start).toBe(Date.UTC(2026, 9, 13, 11));   // 04:00 PDT on 13 Oct
      expect(dayKey(c, s, hold.until - 1)).toBe('2026-10-13');
      expect(dayKey(c, s, hold.until) > '2026-10-13').toBe(true);   // a later date, never back
      expect(rolloverAfter(c, s, '2026-10-13')).toBe(hold.until);
      expect(untilRollover(c, s, T)).toBe(hold.until - T);   // Rest, tea, Limit reached all count to it
      expect(s.day.key).toBe('2026-10-13');   // the day the change ran in, carried
    }
  });

  it('a whole day apart (Tonga → Pago Pago, 24 h of zones): the new calendar must turn past the day first, 48 h', () => {
    const s = sfSave('player-rules-09');
    s.travel = { ...s.travel, home: 'gn-4032402', here: 'gn-4032402', home_chosen_at: T - DAY };   // Nuku'alofa, UTC+13
    const hold = dayHoldFor(c, s, 'gn-5881576', T), next = { travel: { home: 'gn-5881576' } };   // Pago Pago, UTC−11
    expect((hold.until - hold.start) / H).toBe(48);
    expect(dayKey(c, next, hold.until) > hold.key).toBe(true);   // never back a date: no negative countdown after
    expect(dayKey(c, next, hold.until - 1) <= hold.key).toBe(true);
  });

  it('the day is kept: today\'s counts stay after the change', () => {
    const s = sfSave();
    s.day = { ...s.day, key: dayKey(c, s, T), drinks: 2, rest: 1 };
    const after = ok(run(s, { type: 'change_home', city: TOKYO, spot: 0 })).state;
    expect(after.day).toMatchObject({ key: '2026-10-13', drinks: 2, rest: 1 });
    const later = ok(run(after, { type: 'equip', item: c.tools.fishing }, T + 17 * H)).state;   // 17 h on: still the carried day
    expect(later.day).toMatchObject({ key: '2026-10-13', drinks: 2 });
    const turned = ok(run(later, { type: 'equip', item: c.tools.fishing }, after.travel.day_hold!.until)).state;   // 04:00 in Tokyo
    expect(turned.day).toMatchObject({ key: '2026-10-15', drinks: 0 });
  });

  it('a first pick does not carry: it turns to the new home\'s day at once', () => {
    const s = pickedIn(TOKYO, 'player-rules-02');
    expect(s.travel.day_hold).toBeUndefined();
    expect(dayKey(c, s, T)).toBe('2026-10-14');   // 10:00 on 14 Oct in Tokyo
  });

  it('a gift meal\'s parcel due at the old 04:00 lasts to the new turn; the hold goes once it is over', () => {
    const s = sfSave(), oldEnd = rolloverAfter(c, s, dayKey(c, s, T));
    s.inbox.parcels.push({ key: 'gift:1', id: 'dish_fresh_fish_soup', qty: 1, gift: { from: 'res_pip' } as never, source: 'Pip', created_at: T - H, expires_at: oldEnd });
    const after = ok(run(s, { type: 'change_home', city: TOKYO, spot: 0 })).state;
    expect(after.inbox.parcels[0].expires_at).toBe(Math.min(T - H + DAY, after.travel.day_hold!.until));
    expect(upgradeState(c, structuredClone(after), after.travel.day_hold!.until).travel.day_hold).toBeUndefined();
  });

  it('the change confirm card learns when today resets (spots → resets_at); a first pick gets none', async () => {
    const app = Fastify(), store = new P0Store(c);
    registerP0Routes(app, { content: c, store, now: () => T, dev: true });
    const old = (await app.inject({ method: 'GET', url: `/v1/p0/home/spots/${TOKYO}`, headers: { 'x-p0-player': 'player-rules-03' } })).json();
    expect(old.resets_at).toBe(dayHoldFor(c, store.peek('player-rules-03')!, TOKYO, T).until);
    const fresh = (await app.inject({ method: 'GET', url: `/v1/p0/home/spots/${TOKYO}`, headers: { 'x-p0-player': 'player-rules-04', 'x-p0-features': 'choose_home' } })).json();
    expect(fresh.resets_at).toBeNull();
  });
});

describe('q(177): traps in home ponds only; a change of home brings them in', () => {
  const trapper = (s: P0State) => { s.skills.fishing = 1e7; add(c, s, TRAP, 2); return s; };

  it('a generated home pond takes a trap; a pond in another city does not (`Home ponds only`)', () => {
    const s = trapper(pickedIn(TOKYO, 'player-rules-05'));
    s.presence.place = `${TOKYO}~pond0`;
    const r = ok(run(s, { type: 'set_trap' }));
    expect(r.state.traps?.[0].place).toBe(`${TOKYO}~pond0`);
    const away = trapper(sfSave('player-rules-06'));
    away.presence.place = `${TOKYO}~pond0`;
    expect(run(away, { type: 'set_trap' })).toMatchObject({ ok: false, code: 'home_ponds_only' });
  });

  it('changing home brings the old ponds\' traps in: worked out to now, fish caught as Collect, the trap back', () => {
    const s = trapper(sfSave('player-rules-07'));
    s.presence.place = 'pond_san_francisco_03';
    const set = ok(run(s, { type: 'set_trap' }, T - 20 * H)).state;
    const traps = count(set.bag, TRAP);
    const r = ok(run(set, { type: 'change_home', city: TOKYO, spot: 0 }));
    expect(r.state.traps ?? []).toEqual([]);
    expect(count(r.state.bag, TRAP)).toBe(traps + 1);
    const caught = Object.values(r.state.fishing.caught).reduce((a, b) => a + b, 0) - Object.values(set.fishing.caught).reduce((a, b) => a + b, 0);
    expect(caught).toBe(2);   // 20 h at one fish each 8 h
    expect(r.events).toContainEqual(expect.objectContaining({ kind: 'trap', action: 'recalled', place: 'pond_san_francisco_03', fish: 2 }));
    expect(r.events.some(e => e.kind === 'xp')).toBe(true);
  });

  it('what the bag cannot hold comes as parcels', () => {
    const s = trapper(sfSave('player-rules-08'));
    s.presence.place = 'pond_san_francisco_03';
    const set = ok(run(s, { type: 'set_trap' }, T - 20 * H)).state;
    while (set.bag.length < set.bag_cap) set.bag.push({ id: 'crop_radish', qty: 1 } as never);   // every slot taken
    set.bag = set.bag.filter(b => b.id !== TRAP);   // no stack for the trap to join
    const r = ok(run(set, { type: 'change_home', city: TOKYO, spot: 0 }));
    expect(r.state.inbox.parcels.some(p => p.id === TRAP)).toBe(true);
  });
});
