/** SGODOT-275: save v4 → v5 adds the travel block; the store keeps the old file once before rewriting it. */
import { chmodSync, existsSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { wildNearOf, wildPricedOf } from '../../src/p0/wild.js';
import { loadP0Content } from '../../src/p0/content.js';
import { freshState, SAVE_VERSION, START_WEAPON, upgradeState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { freshTravel } from '../../src/p0/travel.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
/** San Francisco's frozen fallback lists from the homestead (亚瑟's #213): Hayward, Concord, Fairfield … Chico. */
const SF_FALLBACK = freshTravel(c).fallback;
// v4q(3): the wild sites a new San Francisco save freezes with its fallback (the free 3, the priced guarantee's 4)
const SF_WILD = { wild_near3: wildNearOf(c, 'gn-5391959'), wild_priced: wildPricedOf(c, 'gn-5391959') };
const now = Date.parse('2026-10-10T03:00:00Z');
/** A v4 save as the live server writes it today: the current shape without the travel block. */
const v4 = (player = 'p0-test'): P0State => {
  const s = freshState(c, player, now) as unknown as Record<string, unknown> & P0State;
  delete (s as Record<string, unknown>).travel;
  (s as Record<string, unknown>).v = 4;
  s.coins = 123; s.skills.fishing = 77; s.firsts.push('catch:fish_crucian');
  return s;
};

describe('save v5 (SGODOT-275)', () => {
  it('new players start at home with nothing visited', () => {
    expect(SF_FALLBACK.near3).toHaveLength(3);
    expect(SF_FALLBACK.near10).toHaveLength(10);
    const s = freshState(c, 'p0-new', now);
    expect(s.v).toBe(SAVE_VERSION);
    expect(s.travel).toEqual({ home: 'gn-5391959', here: 'gn-5391959', passes: {}, visits: {}, stamps: [], fallback: SF_FALLBACK, ...SF_WILD, explorer: 0 });
  });

  it('a v4 save gains the travel block and nothing else changes', () => {
    const raw = v4();
    const up = upgradeState(c, structuredClone(raw), now);
    expect(up.v).toBe(SAVE_VERSION);   // v5, v6 (q(270)), v7 (355): upgradeState still fills a hand-made old save
    expect(up.travel).toEqual({ home: 'gn-5391959', here: 'gn-5391959', passes: {}, visits: {}, stamps: [], fallback: SF_FALLBACK, ...SF_WILD, explorer: 0 });
    // v7's own fields (355): the weapon slot, kills and guard firsts, filled empty
    expect(up.gear.weapons).toEqual([START_WEAPON]);
    expect(up.kills).toEqual({});
    expect(up.guard_firsts).toEqual({});
    const { v: _a, travel: _b, ...rest } = up;   // (no fishing_city keys in this save; the fixture is a v7 fresh save, its own fields kept)
    const { v: _c, ...was } = raw;
    expect(rest).toEqual(was);
  });

  it('the first-catch-in-a-city key moves to the cluster id', () => {
    const raw = v4();
    raw.firsts.push('fishing_city:san francisco', 'fishing_city:shanghai', 'fishing_city:gn-5391959');
    const up = upgradeState(c, raw, now);
    expect(up.firsts.filter(f => f.startsWith('fishing_city:'))).toEqual(['fishing_city:gn-5391959', 'fishing_city:gn-1796236']);
  });

  it('upgrading twice is the same as once', () => {
    const once = upgradeState(c, v4(), now);
    const twice = upgradeState(c, structuredClone(once), now);
    expect(twice).toEqual(once);
  });

  it('a v5 save keeps its travel block', () => {
    const s = freshState(c, 'p0-been', now);
    s.travel.visits['gn-1850147'] = { n: 2, first_at: now, last_at: now, deliveries: 0, delivered_day: '' };
    s.travel.stamps.push({ cluster: 'gn-1850147', kind: 'climate', at: now, counted_on: '2026-10-09' });
    expect(upgradeState(c, structuredClone(s), now).travel).toEqual(s.travel);
  });

  it('the store keeps an older file once and clears its saves: v7 starts every player afresh (355, q row B)', () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'p0-v5-'));
    const file = path.join(dir, 'p0-state.json');
    const input = JSON.stringify({ a: v4('a'), b: v4('b') });
    writeFileSync(file, input);
    const store = new P0Store(c, file);
    expect(store.migrated).toBe(2);
    expect(readFileSync(`${file}.v4.bak`, 'utf8')).toBe(input);
    expect(store.peek('a')).toBeUndefined();   // cleared, not brought up
    const fresh = store.get('a', now);   // the next read makes a new save
    expect(fresh.v).toBe(SAVE_VERSION);
    const written = JSON.parse(readFileSync(file, 'utf8')) as Record<string, P0State>;
    expect(Object.keys(written)).toEqual(['a']);
    expect(written.a.v).toBe(SAVE_VERSION);
    const again = new P0Store(c, file);
    expect(again.migrated).toBe(0);
    expect(again.peek('a')!.created_at).toBe(fresh.created_at);   // a v7 save is kept across a restart
    expect(readFileSync(`${file}.v4.bak`, 'utf8')).toBe(input);   // not overwritten by the second load
  });

  it('an older file met again beside a kept one is kept under its own time, never skipped (后裔 on #611)', () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'p0-v5-'));
    const file = path.join(dir, 'p0-state.json');
    writeFileSync(`${file}.v4.bak`, 'an earlier copy');
    const input = JSON.stringify({ a: v4('a') });
    writeFileSync(file, input);
    const store = new P0Store(c, file);
    expect(store.migrated).toBe(1);
    expect(readFileSync(`${file}.v4.bak`, 'utf8')).toBe('an earlier copy');   // the earlier copy untouched
    const stamped = readdirSync(dir).filter(n => /^p0-state\.json\.v4\..+\.bak$/.test(n));
    expect(stamped).toHaveLength(1);
    expect(readFileSync(path.join(dir, stamped[0]), 'utf8')).toBe(input);
  });

  it('a copy that cannot be made stops the store before any save is cleared', () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'p0-v5-'));
    const file = path.join(dir, 'p0-state.json');
    const input = JSON.stringify({ a: v4('a') });
    writeFileSync(file, input);
    chmodSync(dir, 0o500);   // nothing new can be written beside the file
    try {
      expect(() => new P0Store(c, file)).toThrow(/could not keep/);
    } finally { chmodSync(dir, 0o700); }
    expect(readFileSync(file, 'utf8')).toBe(input);   // the saves are as they were
  });

  it('the view says the save version this server writes (a v7 client shows maintenance on an older server)', () => {
    expect(viewOf(c, freshState(c, 'p0-v', now), now).save_version).toBe(SAVE_VERSION);
  });
});
