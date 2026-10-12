/** SGODOT-296 (不知火舞's spec): every city of M tier and up sells its own postcard on its Market Square 1's City
 * Specialty shelf — `<City> Postcard`, 100 coins, once per account, into Farm Storage. San Francisco and Shanghai keep
 * their old ids; every other city's is postcard_<cluster id>. */
import { describe, expect, it } from 'vitest';
import type { CityCluster } from '../../src/p0/clusters.js';
import { cityPostcardCluster, cityPostcardId, itemName, loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { catalog, offerOf, specialtyAt } from '../../src/p0/shops.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { cityPlaces } from '../../src/p0/world.js';

const c: P0Content = loadP0Content();
const clusters = (c as P0Content & { clusters: { get(id: string): CityCluster | undefined; byId: Map<string, CityCluster> } }).clusters;
const T0 = Date.parse('2026-10-12T15:00:00Z');
const SF = 'gn-5391959', SHANGHAI = 'gn-1796236', TOKYO = 'gn-1850147', OSAKA = 'gn-1853909';
const fresh = (): P0State => ({ ...freshState(c, 'player-postcard-01', T0, 9), coins: 500 });
const buy = (s: P0State, item: string, place?: string) =>
  applyP0(c, s, { type: 'buy', item, qty: 1, shop: 'market', ...(place ? { place } : {}) } as P0Command, T0);

describe('city postcards (SGODOT-296)', () => {
  it('derives postcard_<cluster id> from the cluster alone; San Francisco and Shanghai keep their old ids', () => {
    expect(cityPostcardId(c, TOKYO)).toBe(`postcard_${TOKYO}`);
    expect(cityPostcardId(c, SF)).toBe('postcard_san_francisco');
    expect(cityPostcardId(c, SHANGHAI)).toBe('postcard_shanghai');
    // no second San Francisco or Shanghai postcard: their cluster ids are not postcards
    for (const id of [`postcard_${SF}`, `postcard_${SHANGHAI}`]) {
      expect(cityPostcardCluster(c, id)).toBeNull();
      expect(offerOf(c, id)).toBeNull();
    }
    expect(itemName(c, `postcard_${TOKYO}`)).toBe('Tokyo Postcard');
    expect(offerOf(c, `postcard_${TOKYO}`)).toMatchObject({ price: 100, once: true, to: 'storage' });
  });

  it('sells a city\'s postcard only on its Market Square 1, from M tier up', () => {
    expect(catalog(c, 'market', fresh(), `${TOKYO}~market0`)).toContain(`postcard_${TOKYO}`);
    expect(specialtyAt(c, fresh(), `${TOKYO}~market1`)).toEqual([]);   // Market Square 2
    expect(specialtyAt(c, fresh(), `${TOKYO}~tea0`)).toEqual([]);
    expect(specialtyAt(c, fresh(), 'sh_market_1')).toEqual(['postcard_san_francisco']);
    expect(specialtyAt(c, fresh(), `${SHANGHAI}~market0`)).toEqual(['postcard_shanghai']);   // sold again (296)
    let sTowns = 0, sold = 0;
    const ids = new Set<string>();
    for (const cl of clusters.byId.values()) {
      const city = cityPlaces(c, cl.id);
      if (!city) continue;
      const here = city.outposts.flatMap(o => specialtyAt(c, fresh(), o));
      if (city.tier === 'S') { sTowns++; expect(here).toEqual([]); continue; }
      expect(here).toEqual([cityPostcardId(c, cl.id)]);   // exactly one, on market0
      expect(specialtyAt(c, fresh(), `${cl.id}~market0`)).toEqual(here);
      const price = offerOf(c, here[0])!.price;
      expect(price).toBeGreaterThanOrEqual(80);
      expect(price).toBeLessThanOrEqual(200);
      ids.add(here[0]); sold++;
    }
    expect(ids.size).toBe(sold);   // never two cities on one id
    expect(sTowns).toBeGreaterThan(10_000);
  });

  it('buys once per account into Farm Storage; another city\'s postcard is not on this Market', () => {
    let s = fresh();
    const r = buy(s, `postcard_${TOKYO}`, `${TOKYO}~market0`);
    if (!r.ok) throw new Error(r.code);
    s = r.state;
    expect(s.storage[`postcard_${TOKYO}`]).toBe(1);
    expect(s.coins).toBe(400);
    expect(buy(s, `postcard_${TOKYO}`, `${TOKYO}~market0`)).toMatchObject({ ok: false, code: 'owned' });
    expect(buy(fresh(), `postcard_${TOKYO}`, `${OSAKA}~market0`)).toMatchObject({ ok: false, code: 'bad_item' });
    expect(buy(fresh(), `postcard_${TOKYO}`, `${TOKYO}~market1`)).toMatchObject({ ok: false, code: 'bad_item' });
    expect(buy(fresh(), 'postcard_san_francisco', `${TOKYO}~market0`)).toMatchObject({ ok: false, code: 'bad_item' });
  });

  it('knows the outpost the player is in when the client sends no place (the counter never does)', () => {
    const at = (place: string) => { const s = fresh(); s.presence.entered = place; return s; };
    expect(buy(at(`${TOKYO}~market0`), `postcard_${TOKYO}`).ok).toBe(true);
    expect(buy(at(`${TOKYO}~market1`), `postcard_${TOKYO}`)).toMatchObject({ ok: false, code: 'bad_item' });
    // an account that bought the old Shanghai postcard in P0 owns Shanghai's already
    const old = at(`${SHANGHAI}~market0`);
    old.owned.push('postcard_shanghai'); old.storage.postcard_shanghai = 1;
    expect(buy(old, 'postcard_shanghai')).toMatchObject({ ok: false, code: 'owned' });
  });

  it('names postcards in the view and marks the City Specialty row', () => {
    const s = fresh();
    s.presence.entered = `${TOKYO}~market0`;
    s.owned.push(`postcard_${OSAKA}`); s.storage[`postcard_${OSAKA}`] = 1;
    const v = viewOf(c, s, T0) as unknown as { names: Record<string, string>; shops: { market: { buy: { id: string; specialty?: boolean }[] } } };
    expect(v.names[`postcard_${TOKYO}`]).toBe('Tokyo Postcard');
    expect(v.names[`postcard_${OSAKA}`]).toBe('Osaka Postcard');
    expect(v.names.postcard_shanghai).toBe('Shanghai Postcard');
    expect(v.shops.market.buy.filter(o => o.specialty).map(o => o.id)).toEqual([`postcard_${TOKYO}`]);
  });
});
