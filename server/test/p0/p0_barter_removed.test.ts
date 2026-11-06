import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0 } from '../../src/p0/reducer.js';
import { freshState } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 10, 2, 1, 0, 0);

// v4 第 38 条 / 355 H（SGODOT-355）: Specialty Barter is gone — minerals come only from the mines (q(175)), so q(166)'s
// two regional items for one mineral at the Market Square keeper no longer exist anywhere.
describe('Specialty Barter removed (355 H, v4 #38)', () => {
  it('the command is unknown and changes nothing', () => {
    const s = freshState(c, 'player-barter-gone', T0, 7);
    const before = structuredClone(s);
    expect(applyP0(c, s, { type: 'barter', item: 'crop_pumpkin', mineral: 'stone', shop: 'market' } as never, T0))
      .toMatchObject({ ok: false, code: 'unknown_command' });
    expect(s).toEqual(before);
  });

  it('no counter offers it and the content has none', () => {
    const v = viewOf(c, freshState(c, 'player-barter-gone', T0, 7), T0);
    for (const shop of Object.values(v.shops)) expect(shop).not.toHaveProperty('barter');
    expect(c.homestead).not.toHaveProperty('barter');
  });
});
