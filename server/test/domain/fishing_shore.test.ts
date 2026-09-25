import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { defaultFishingTarget, validFishingCast, type FishingPoint } from '../../src/domain/fishing.js';
import { walkable, type Navigation } from '../../src/realtime/model.js';
import { content, freshFarm, plot, SH, T0 } from './helpers.js';
import { apply, makeCtx } from '../../src/domain/reducer.js';
const maps = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, 'online_navigation.json'), 'utf8')).maps as Record<string, Navigation>;

describe('continuous shore geometry', () => {
  it.each(['farm_pond', 'street_lake', 'street_river'])('%s accepts multiple continuous shores on the real navigation', id => {
    const site = content.fishing.sites[id];
    const nav = Object.entries(maps).find(([key]) => key.startsWith(site.space === 'farm' ? 'farm' : 'street'))?.[1];
    expect(nav).toBeDefined();
    const accepted: FishingPoint[] = [];
    for (let z = 0; z < nav!.rows.length; z++) for (let x = 0; x < nav!.rows[z].length; x++) {
      const p: FishingPoint = [(x + .5) * nav!.cell, -(z + .5) * nav!.cell];
      if (validFishingCast(site, p, defaultFishingTarget(site, p), content.fishing, point => walkable(nav!, point))) accepted.push(p);
    }
    expect(accepted.length).toBeGreaterThan(12);
    const p = accepted[Math.floor(accepted.length / 2)];
    let continuous = 0;
    for (let offset = -.1; offset <= .1; offset += .01) {
      const origin: FishingPoint = [p[0] + offset, p[1]];
      if (validFishingCast(site, origin, defaultFishingTarget(site, origin), content.fishing, point => walkable(nav!, point))) continuous++;
    }
    expect(continuous).toBeGreaterThan(10);
  });
  it('rejects invalid targets, inland, wet, blocked and cross-bank casts', () => {
    const site = content.fishing.sites.farm_pond, c = content.fishing;
    for (const target of [null, [], [NaN, 0], [9, -20], [9, -34], [999, 999]])
      expect(validFishingCast(site, [9.375, -27.375], target, c)).toBe(false);
    expect(validFishingCast(site, [9, -30.75], [10, -30.75], c)).toBe(false);
    expect(validFishingCast(site, [9, -24], [9, -30], c)).toBe(false);
    expect(validFishingCast(site, [9.375, -27.375], [9, -30], c, () => false)).toBe(false);
    expect(validFishingCast(site, [9.375, -27.375], [9, -30], c, p => p[1] > -27.5)).toBe(false);
  });
  it('rejects old owner and visitor farm casts without changing their state', () => {
    const state = freshFarm(), before = structuredClone(state);
    for (const home of ['my-farm', 'hosts-farm']) {
      const ctx = makeCtx(state, T0, SH, content, plot, T0, 'my-farm');
      ctx.fishingPresence = { space: 'farm', home, room: 'old-room', nonce: 'one', x: 9.123, z: -27.4 };
      expect(apply(state, { type: 'cast_fishing', sequence: 0, site_id: 'farm_pond', target: [9,-29] }, ctx))
        .toMatchObject({ ok: false, code: 'FISHING_LOCATION' });
      expect(state).toEqual(before);
    }
  });
});
