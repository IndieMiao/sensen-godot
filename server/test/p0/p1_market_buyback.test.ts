import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { buyback, quotaLeft } from '../../src/p0/shops.js';

// The Market Square's buy-back (§9.13.1): its own climate's regional crops and fish at 0.8, 60 coins a day per city
// cluster, the city's market squares sharing one count (§11.7.3).
const content = loadP0Content();
const c = { ...content, profile: { ...content.profile, timezone: 'Asia/Shanghai' } };
const T0 = Date.UTC(2026, 9, 10, 2, 0, 0);
const DAY = 86_400_000;
const SF = 'gn-5391959', TOKYO = 'gn-1850147';
const AT_MARKET = { shop: 'market', space: 'outpost', place: 'sh_market_1' } as const;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const refuse = (s: P0State, cmd: P0Command, now = T0) => applyP0(c, s, cmd, now);
const fresh = () => ({ ...freshState(c, 'player-market-buy', T0, 3), created_at: T0 - 8 * DAY });

describe('the Market Square buys its climate\'s regional crops and fish (§9.13.1)', () => {
  it('Pumpkin and the Temperate regional fish at 0.8; other crops, other climates\' items and dishes are not taken', () => {
    expect(buyback(c, 'market', 'crop_pumpkin')).toEqual({ unit: 17, quota: 'regional_market' });   // ⌊22 × 0.8⌋
    expect(buyback(c, 'market', 'fish_salmon')).toEqual({ unit: 25, quota: 'regional_market' });    // ⌊32 × 0.8⌋
    expect(buyback(c, 'market', 'crop_radish')).toEqual({ code: 'not_sellable_here' });
    expect(buyback(c, 'market', 'crop_pineapple')).toEqual({ code: 'not_sellable_here' });           // Tropical
    expect(buyback(c, 'market', 'fish_tilapia')).toEqual({ code: 'not_sellable_here' });
    expect(buyback(c, 'market', 'fish_crucian')).toEqual({ code: 'not_sellable_here' });             // a global fish
    expect(buyback(c, 'market', 'dish_grilled_crucian')).toEqual({ code: 'not_sellable_here' });
    expect(buyback(c, 'homestead', 'crop_pumpkin')).toMatchObject({ unit: 22, quota: null });       // home pays full, no limit
  });

  it('60 coins a day for the city; a sale past it stops at what fits; the view shows this city\'s count', () => {
    let s = fresh();
    s.bag.push({ id: 'crop_pumpkin', qty: 5 });
    let r = step(s, { type: 'sell', item: 'crop_pumpkin', qty: 'all', ...AT_MARKET });
    expect(r.ev).toContainEqual({ kind: 'sale', item: 'crop_pumpkin', qty: 3, asked: 5, coins: 51, shop: 'market', quota: 'regional_market' });
    expect(r.s.day.quota[`regional_market@${SF}`]).toBe(51);
    expect(quotaLeft(c, r.s, 'regional_market', SF)).toBe(9);
    expect(viewOf(c, r.s, T0).quotas.regional_market).toMatchObject({ used: 51, cap: 60, scope: 'this city' });
    expect(refuse(r.s, { type: 'sell', item: 'crop_pumpkin', qty: 1, ...AT_MARKET })).toMatchObject({ ok: false, code: 'limit_reached' });
    s = r.s;
    r = step(s, { type: 'sell', item: 'crop_pumpkin', qty: 1, ...AT_MARKET }, T0 + DAY);   // the next day
    expect(r.s.day.quota[`regional_market@${SF}`]).toBe(17);
  });

  it('another city has its own count (§11.7.3); the Tackle Shop\'s fish buy-back stays one for the account', () => {
    const s = fresh();
    s.day.key = '2026-10-10';
    s.day.quota[`regional_market@${SF}`] = 60;
    expect(quotaLeft(c, s, 'regional_market', SF)).toBe(0);
    expect(quotaLeft(c, s, 'regional_market', TOKYO)).toBe(60);
    s.day.quota.fish_tackle = 50;
    expect(quotaLeft(c, s, 'fish_tackle', TOKYO)).toBe(30);   // not per city
    expect(c.quotas.fish_tackle.per_city).toBeUndefined();
  });

  it('the market\'s sell list names what it takes here', () => {
    const v = viewOf(c, fresh(), T0);
    const sell = v.shops.market.sell as { kind: string; regional?: boolean; items?: string[] }[];
    expect(sell.find(x => x.kind === 'crop')).toMatchObject({ regional: true, items: ['crop_pumpkin'] });
    expect(sell.find(x => x.kind === 'fish')?.items).toEqual(expect.arrayContaining(['fish_smelt', 'fish_arctic_char', 'fish_salmon']));
  });
});
