import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { buyback } from '../../src/p0/shops.js';

// The Market Square's buy-back (§9.13.1): its own climate's regional crops and fish; at home at full price with no daily
// limit (q(251): the 60-coin per-city quota is gone; away from home see p1_sell_distance).
const content = loadP0Content();
const c = { ...content, profile: { ...content.profile, timezone: 'Asia/Shanghai' } };
const T0 = Date.UTC(2026, 9, 10, 2, 0, 0);
const DAY = 86_400_000;
const AT_MARKET = { shop: 'market', space: 'outpost', place: 'sh_market_1' } as const;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const fresh = () => ({ ...freshState(c, 'player-market-buy', T0, 3), created_at: T0 - 8 * DAY });

describe('the Market Square buys its climate\'s regional crops and fish (§9.13.1)', () => {
  it('Pumpkin and the Temperate regional fish at full price; other crops, other climates\' items and dishes are not taken', () => {
    expect(buyback(c, 'market', 'crop_pumpkin')).toEqual({ unit: 22, quota: null });
    expect(buyback(c, 'market', 'fish_salmon')).toEqual({ unit: 32, quota: null });
    expect(buyback(c, 'market', 'crop_radish')).toEqual({ code: 'not_sellable_here' });
    expect(buyback(c, 'market', 'crop_pineapple')).toEqual({ code: 'not_sellable_here' });           // Tropical
    expect(buyback(c, 'market', 'fish_tilapia')).toEqual({ code: 'not_sellable_here' });
    expect(buyback(c, 'market', 'fish_crucian')).toEqual({ code: 'not_sellable_here' });             // a global fish
    expect(buyback(c, 'market', 'dish_grilled_crucian')).toEqual({ code: 'not_sellable_here' });
    expect(buyback(c, 'homestead', 'crop_pumpkin')).toMatchObject({ unit: 22, quota: null });       // the same as home
  });

  it('no daily limit: the whole stack sells; an old save\'s count for the retired quota is never read', () => {
    const s = fresh();
    s.day.key = '2026-10-10';
    s.day.quota['regional_market@gn-5391959'] = 60;   // what a save from before q(251) may carry
    s.bag.push({ id: 'crop_pumpkin', qty: 5 });
    const r = step(s, { type: 'sell', item: 'crop_pumpkin', qty: 'all', ...AT_MARKET });
    expect(r.ev).toContainEqual({ kind: 'sale', item: 'crop_pumpkin', qty: 5, asked: 5, coins: 110, shop: 'market', quota: null });
    expect(viewOf(c, r.s, T0).quotas).not.toHaveProperty('regional_market');
  });

  it('the market\'s sell list names what it takes here', () => {
    const v = viewOf(c, fresh(), T0);
    const sell = v.shops.market.sell as { kind: string; regional?: boolean; items?: string[] }[];
    expect(sell.find(x => x.kind === 'crop')).toMatchObject({ regional: true, items: ['crop_pumpkin'] });
    expect(sell.find(x => x.kind === 'fish')?.items).toEqual(expect.arrayContaining(['fish_smelt', 'fish_arctic_char', 'fish_salmon']));
  });
});
