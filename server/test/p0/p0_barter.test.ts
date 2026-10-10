/** SGODOT-282: specialty barter (§8.4.5) — 2 regional items → 1 mineral at the Market Square, ≤ 50 % of a level, ≤ 6 a day. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, count, type P0Command } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const base = loadP0Content();
// The regional list comes with Li Bai's P1 data; radishes stand in for a Temperate regional crop here.
const c = { ...base, homestead: { ...base.homestead, barter: { ...base.homestead.barter!, items: { Temperate: ['crop_radish'] } } } };
const T0 = Date.UTC(2026, 9, 10, 18);
const at = (level: number): P0State => {
  const s = { ...freshState(c, 'barter-player', T0, 7), created_at: T0 - 8 * 86_400_000 };
  s.homestead.level = level;
  s.bag = [{ id: 'crop_radish', qty: 40 }];
  return s;
};
const trade = (mineral: string, shop = 'market'): P0Command => ({ type: 'barter', item: 'crop_radish', mineral, shop });
const run = (s: P0State, cmd: P0Command) => applyP0(c, s, cmd, T0);

describe('Barter (§8.4.5)', () => {
  it('2 regional items become 1 mineral in farm storage', () => {
    const r = run(at(4), trade('quartz'));   // Lv5 needs Quartz 2: one by barter
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(count(r.state.bag, 'crop_radish')).toBe(38);
    expect(r.state.storage.quartz).toBe(1);
    expect(r.state.day.barters).toBe(1);
  });

  it('at most half of the next level\'s need per mineral, counted until the next upgrade', () => {
    let s = at(4);   // Lv5: Copper Ore 10 → 5 by barter
    for (let i = 0; i < 5; i++) { const r = run(s, trade('copper_ore')); if (!r.ok) throw new Error(r.code); s = r.state; }
    expect(run(s, trade('copper_ore'))).toMatchObject({ ok: false, code: 'barter_share' });
    expect(viewOf(c, s, T0).shops.market.barter).toMatchObject({ left: 1, minerals: expect.arrayContaining([{ id: 'copper_ore', name: 'Copper Ore', room: 0 }]) });
    expect(run(at(4), trade('wood'))).toMatchObject({ ok: false, code: 'not_barterable' });   // Timber is gathered, never bartered
    expect(run(at(3), trade('quartz'))).toMatchObject({ ok: false, code: 'barter_share' });   // Lv4 needs no Quartz
  });

  it('six a day, only at the Market Square, only this climate\'s regional items', () => {
    let s = at(4);
    const minerals = ['stone', 'stone', 'stone', 'clay', 'clay', 'clay'];
    for (const m of minerals) { const r = run(s, trade(m)); if (!r.ok) throw new Error(r.code); s = r.state; }
    expect(run(s, trade('stone'))).toMatchObject({ ok: false, code: 'barter_limit' });
    expect(run(at(4), trade('stone', 'homestead'))).toMatchObject({ ok: false, code: 'wrong_shop' });
    expect(run(at(4), { type: 'barter', item: 'fish_crucian', mineral: 'stone', shop: 'market' })).toMatchObject({ ok: false, code: 'not_barterable' });
  });

  it('the base content lists no regional items yet, so the counter shows the rule with nothing to give', () => {
    expect(viewOf(base, at(4), T0).shops.market.barter).toMatchObject({ give: 2, daily: 6, items: [] });
  });
});
