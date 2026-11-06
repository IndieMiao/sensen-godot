/** The development mines (content.mine.dev_sites) exist only with P0_DEV_SITES=1 (亚瑟 / 奕星, 11-06): off, the live server
 * knows no wd-dev-* mine at all — not entered, not read; a wild site's mine is the same either way. */
import { afterEach, describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { devSitesFromEnv, mineSite, setDevSites } from '../../src/p0/mine.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState } from '../../src/p0/state.js';
import { wildNear3 } from '../../src/p0/wild.js';

const c = loadP0Content();
const T = Date.parse('2026-11-06T10:00:00Z');
afterEach(() => setDevSites(false));

describe('the development mines behind P0_DEV_SITES', () => {
  it('only "1" turns them on', () => {
    expect(devSitesFromEnv({})).toBe(false);
    expect(devSitesFromEnv({ P0_DEV_SITES: '0' })).toBe(false);
    expect(devSitesFromEnv({ P0_DEV_SITES: 'true' })).toBe(false);
    expect(devSitesFromEnv({ P0_DEV_SITES: '1' })).toBe(true);
  });

  it('off: no wd-dev-* mine is found or entered (unknown_place); on: they are; a wild mine either way', () => {
    const ids = (c.mine.dev_sites ?? []).map(d => d.id);
    expect(ids).toEqual(['wd-dev-quarry', 'wd-dev-vein']);
    const wild = wildNear3(c, freshState(c, 'dev-sites-0', T))[0];
    setDevSites(false);
    for (const id of ids) expect(mineSite(c, id)).toBeUndefined();
    expect(mineSite(c, wild)).toBeDefined();
    const s = freshState(c, 'dev-sites-1', T);
    s.energy.value = 100;
    const enter = () => applyP0(c, s, { type: 'mine_enter', mine: 'wd-dev-quarry', floor: 1, space: 'mine', place: 'wd-dev-quarry' } as unknown as P0Command, T);
    expect(enter()).toMatchObject({ ok: false, code: 'unknown_place' });
    setDevSites(true);
    for (const id of ids) expect(mineSite(c, id)?.id).toBe(id);
    expect(mineSite(c, wild)).toBeDefined();
    expect(enter().ok).toBe(true);   // no here check for a development mine (contract-efg §11)
  });
});
