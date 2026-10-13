/** SGODOT-303, the server's first step: every "home" read takes the save's home city (travel.home), the written city's
 * facts staying content.profile's. Every save's home is still San Francisco (upgradeState moves any other back), so a
 * San Francisco save must play exactly as before — the rollover above all; a save whose home is another city (as
 * choosing a home will make) gets that city's clock, climate, farm point, trips, fallback list and far fish. */
import { describe, expect, it } from 'vitest';
import { farFish, regionalPool } from '../../src/p0/boards.js';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { regionalFish } from '../../src/p0/fishing_world.js';
import { homeFacts, homeOf, writtenCluster } from '../../src/p0/home.js';
import { dayKey, rolloverAfter, untilRollover } from '../../src/p0/rules.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { clusterById, fallbackOf, homeClimate, rankedCities, tripOf } from '../../src/p0/travel.js';
import { viewOf } from '../../src/p0/view.js';

const c: P0Content = loadP0Content();
const T0 = Date.parse('2026-10-13T15:00:00Z');
const H = 3_600_000;
const SF = 'gn-5391959', TOKYO = 'gn-1850147', OSAKA = 'gn-1853909';
const fresh = (): P0State => freshState(c, 'player-home-01', T0, 9);
/** A save whose home is another city, as choosing a home will make it (its fallback list frozen for that home). */
const homedIn = (cluster: string): P0State => {
  const s = fresh();
  s.travel = { ...s.travel, home: cluster, here: cluster, fallback: fallbackOf(c, cluster) };
  return s;
};

describe('a San Francisco save plays as before (SGODOT-303)', () => {
  it('home is the written city, with content.profile\'s facts', () => {
    const s = fresh();
    expect(writtenCluster(c)).toBe(SF);
    expect(homeOf(c, s)).toBe(SF);
    expect(homeFacts(c, s)).toEqual({ cluster: SF, name: c.profile.city, climate: c.profile.climate, timezone: c.profile.timezone,
      farm: { lat: c.profile.farm_at![0], lng: c.profile.farm_at![1] } });
    expect(homeFacts(c, null)).toEqual(homeFacts(c, s));   // no save: the written city
  });

  it('the day still turns at 04:00 Pacific time, daylight saving included', () => {
    const s = fresh();
    expect(dayKey(c, s, Date.UTC(2026, 9, 9, 10, 59))).toBe('2026-10-08');   // 03:59 PDT
    expect(dayKey(c, s, Date.UTC(2026, 9, 9, 11, 0))).toBe('2026-10-09');    // 04:00 PDT
    expect(rolloverAfter(c, s, '2026-10-31')).toBe(Date.UTC(2026, 10, 1, 12));   // DST ends: 04:00 PST
    expect(rolloverAfter(c, s, '2027-03-13')).toBe(Date.UTC(2027, 2, 14, 11));   // DST starts: 04:00 PDT
    for (let t = Date.UTC(2026, 9, 25); t < Date.UTC(2026, 10, 8); t += H) {   // two weeks across the switch, hourly
      expect(dayKey(c, s, t)).toBe(dayKey(c, null, t));
      expect(untilRollover(c, s, t)).toBe(untilRollover(c, null, t));
    }
  });

  it('loading a save keeps its home, here and fallback list', () => {
    const s = fresh();
    const before = structuredClone(s.travel);
    expect(upgradeState(c, structuredClone(s), T0).travel).toEqual(before);
    expect(before.fallback).toEqual(fallbackOf(c, SF));
  });
});

describe('a save whose home is another city reads that city (SGODOT-303)', () => {
  const tokyo = clusterById(c, TOKYO)!;

  it('takes its name, climate, time zone and farm point from the cluster', () => {
    const s = homedIn(TOKYO);
    const climate = tokyo.climate[0].toUpperCase() + tokyo.climate.slice(1);
    expect(homeFacts(c, s)).toEqual({ cluster: TOKYO, name: 'Tokyo', climate, timezone: 'Asia/Tokyo', farm: { lat: tokyo.lat, lng: tokyo.lng } });
    expect(homeClimate(c, s)).toBe(climate);
    expect(viewOf(c, s, T0).profile).toMatchObject({ city: 'Tokyo', climate });
  });

  it('turns its day at 04:00 Tokyo time', () => {
    const s = homedIn(TOKYO);
    expect(dayKey(c, s, Date.UTC(2026, 9, 9, 18, 59))).toBe('2026-10-09');   // 03:59 JST on the 10th
    expect(dayKey(c, s, Date.UTC(2026, 9, 9, 19, 0))).toBe('2026-10-10');    // 04:00 JST
    expect(untilRollover(c, s, Date.UTC(2026, 9, 9, 20))).toBe(23 * H);       // 05:00 JST → 04:00 tomorrow
    expect(viewOf(c, s, Date.UTC(2026, 9, 9, 20)).rest.resets_in).toBe(23 * H);
  });

  it('measures trips, the ranked cities and the frozen fallback list from its own farm', () => {
    const s = homedIn(TOKYO), sf = fresh();
    expect(tripOf(c, s, OSAKA).km).toBeGreaterThan(350);
    expect(tripOf(c, s, OSAKA).km).toBeLessThan(450);
    expect(tripOf(c, s, OSAKA).km).not.toBe(tripOf(c, sf, OSAKA).km);
    expect(rankedCities(c, s)[0].km).toBeLessThan(100);   // a Tokyo neighbour, not a Bay Area one
    expect(rankedCities(c, s).map(r => r.id)).not.toContain(TOKYO);
    expect(s.travel.fallback.near3).not.toEqual(fresh().travel.fallback.near3);
  });

  it('draws regional requests and far fish for its own city', () => {
    const s = homedIn(TOKYO), sf = fresh();
    const own = regionalFish(c, TOKYO);
    for (const id of own) expect(farFish(c, s)).not.toContain(id);
    for (const id of regionalFish(c, SF).filter(id => !own.includes(id))) expect(farFish(c, s)).toContain(id);
    expect(farFish(c, sf)).toEqual(farFish(c, null));   // San Francisco's unchanged
    const zone = homeClimate(c, s);
    const crops = regionalPool(c, s, { kind: 'crop', regional: 'zone' } as never);
    for (const id of crops) expect([c.crops.find(cr => cr.id === id)!.zone].flat()).toContain(zone);
  });

  it('is moved back to the written city on load until players choose a home', () => {
    const s = upgradeState(c, homedIn(TOKYO), T0);
    expect(s.travel.home).toBe(SF);
    expect(s.travel.fallback).toEqual(fallbackOf(c, SF));
  });
});
