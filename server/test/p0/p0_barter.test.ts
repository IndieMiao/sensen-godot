/**
 * SGODOT-282 / 284: specialty barter (§8.4.5) — 2 regional items → 1 mineral at any Market Square, ≤ 50 % of a level,
 * ≤ 6 a day. What can go is the market's climate's regional crops and fish, from the regional data (李白 on 284: the
 * market's climate, as its buyback §9.13.1); a Gifted stack never goes.
 */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, count, type P0Command } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { barterItems } from '../../src/p0/barter.js';
import { dayKey } from '../../src/p0/rules.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 10, 18);
const SINGAPORE = 'gn-1880252';   // tropical: another climate than San Francisco's temperate
const at = (level: number): P0State => {
  const s = { ...freshState(c, 'barter-player', T0, 7), created_at: T0 - 8 * 86_400_000 };
  s.homestead.level = level;
  s.bag = [{ id: 'crop_pumpkin', qty: 40 }];   // Temperate's regional crop
  return s;
};
const trade = (mineral: string, shop = 'market', item = 'crop_pumpkin'): P0Command => ({ type: 'barter', item, mineral, shop });
const run = (s: P0State, cmd: P0Command) => applyP0(c, s, cmd, T0);
const barterView = (s: P0State) => viewOf(c, s, T0).shops.market.barter!;

describe('Barter (§8.4.5)', () => {
  it('2 regional items become 1 mineral in farm storage', () => {
    const r = run(at(4), trade('quartz'));   // Lv5 needs Quartz 2: one by barter
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(count(r.state.bag, 'crop_pumpkin')).toBe(38);
    expect(r.state.storage.quartz).toBe(1);
    expect(r.state.day.barters).toBe(1);
    expect(r.events).toEqual(expect.arrayContaining([{ kind: 'item', id: 'crop_pumpkin', delta: -2 }, { kind: 'item', id: 'quartz', delta: 1 }]));
    expect(r.events.at(-1)).toEqual({ kind: 'barter', item: 'crop_pumpkin', give: 2, mineral: 'quartz', left: 5 });   // the client's toast
  });

  it('at most half of the next level\'s need per mineral, counted until the next upgrade', () => {
    let s = at(4);   // Lv5: Copper Ore 10 → 5 by barter
    expect(barterView(s).minerals).toEqual(expect.arrayContaining([{ id: 'copper_ore', name: 'Copper Ore', room: 5, share: 5 }]));
    for (let i = 0; i < 5; i++) { const r = run(s, trade('copper_ore')); if (!r.ok) throw new Error(r.code); s = r.state; }
    expect(run(s, trade('copper_ore'))).toMatchObject({ ok: false, code: 'barter_share' });
    expect(barterView(s)).toMatchObject({ left: 1, minerals: expect.arrayContaining([{ id: 'copper_ore', name: 'Copper Ore', room: 0, share: 5 }]) });
    expect(run(at(4), trade('wood'))).toMatchObject({ ok: false, code: 'not_barterable' });   // Timber is gathered, never bartered
    expect(run(at(3), trade('quartz'))).toMatchObject({ ok: false, code: 'barter_share' });   // Lv4 needs no Quartz
  });

  it('six a day, only at the Market Square; the view says when they come back', () => {
    let s = at(4);
    const minerals = ['stone', 'stone', 'stone', 'clay', 'clay', 'clay'];
    for (const m of minerals) { const r = run(s, trade(m)); if (!r.ok) throw new Error(r.code); s = r.state; }
    expect(run(s, trade('stone'))).toMatchObject({ ok: false, code: 'barter_limit' });
    expect(barterView(s)).toMatchObject({ left: 0, daily: 6, give: 2 });
    expect(barterView(s).resets_in).toBeGreaterThan(0);
    expect(run(at(4), trade('stone', 'homestead'))).toMatchObject({ ok: false, code: 'wrong_shop' });
  });

  it('what can go is the regional data of the market\'s climate, not a hand list', () => {
    // San Francisco (temperate): its regional crop and the fish whose zones hold Temperate; no common crop or fish
    const temperate = barterItems(c, 'Temperate');
    expect(temperate).toEqual(expect.arrayContaining(['crop_pumpkin', 'fish_smelt', 'fish_arctic_char', 'fish_salmon']));
    for (const id of ['crop_radish', 'fish_crucian', 'crop_pineapple', 'fish_tilapia']) expect(temperate).not.toContain(id);
    expect(barterView(at(4)).items).toEqual(expect.arrayContaining([{ id: 'crop_pumpkin', name: 'Pumpkin', have: 40, spare: 40 }]));
    expect(run(at(4), trade('stone', 'market', 'crop_radish'))).toMatchObject({ ok: false, code: 'not_barterable' });
    // at a market in Singapore (tropical) Singapore's go and the pumpkin does not (as its buyback, §9.13.1)
    const rich = at(4); rich.coins += 5000;   // Singapore's fare (q(256))
    const flown = run(rich, { type: 'travel', to: SINGAPORE });   // a Day Pass there
    if (!flown.ok) throw new Error(flown.code);
    const away = flown.state;
    away.bag.push({ id: 'crop_pineapple', qty: 4 });
    expect(barterView(away).items.map(i => i.id)).toContain('crop_pineapple');
    expect(barterView(away).items.map(i => i.id)).not.toContain('crop_pumpkin');
    const there = { space: 'outpost', place: `${SINGAPORE}~market0` };
    expect(run(away, { ...trade('stone'), ...there } as P0Command)).toMatchObject({ ok: false, code: 'not_barterable' });
    expect(run(away, { ...trade('stone', 'market', 'crop_pineapple'), ...there } as P0Command).ok).toBe(true);
  });

  it('a Gifted stack never goes: not counted, not taken', () => {
    const s = at(4);
    s.bag = [{ id: 'crop_pumpkin', qty: 5, gift: { from: 'res_pip', day: dayKey(c, s, T0) } } as never, { id: 'crop_pumpkin', qty: 1 }];
    expect(barterView(s).items).toEqual(expect.arrayContaining([{ id: 'crop_pumpkin', name: 'Pumpkin', have: 1, spare: 1 }]));
    expect(run(s, trade('stone'))).toMatchObject({ ok: false, code: 'not_enough', detail: { item: 'crop_pumpkin', need: 2, have: 1 } });
    s.bag.push({ id: 'crop_pumpkin', qty: 1 });
    const r = run(s, trade('stone'));
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.state.bag.find(b => b.gift)?.qty).toBe(5);   // the gift stays
  });
});

describe('what the pick may take, and the top level (q(166) review)', () => {
  it('a locked stack is spare 0; a tracked request keeps back what it needs, as Sell All', () => {
    const s = at(4);
    const item = () => barterView(s).items.find(i => i.id === 'crop_pumpkin')!;
    expect(item()).toMatchObject({ have: 40, spare: 40 });
    s.boards.market = [{ req: { status: 'accepted', kind: 'crop', items: ['crop_pumpkin'], qty: 30 } } as never];
    expect(item()).toMatchObject({ have: 40, spare: 10 });
    s.locked.push('crop_pumpkin');
    expect(item()).toMatchObject({ have: 40, spare: 0 });
  });

  it('at the top level there is no barter group: nothing left to climb to', () => {
    const s = at(10);
    expect(viewOf(c, s, T0).shops.market.barter).toBeNull();
  });
});
