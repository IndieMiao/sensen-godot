/** SGODOT-275: save v4 → v5 adds the travel block; the store keeps the old file once before rewriting it. */
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { freshState, SAVE_VERSION, upgradeState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { freshTravel } from '../../src/p0/travel.js';

const c = loadP0Content();
/** San Francisco's frozen fallback lists from the homestead (亚瑟's #213): Hayward, Concord, Fairfield … Chico. */
const SF_FALLBACK = freshTravel(c).fallback;
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
    expect(s.travel).toEqual({ home: 'gn-5391959', here: 'gn-5391959', passes: {}, visits: {}, stamps: [], fallback: SF_FALLBACK, explorer: 0 });
  });

  it('a v4 save gains the travel block and nothing else changes', () => {
    const raw = v4();
    const up = upgradeState(c, structuredClone(raw), now);
    expect(up.v).toBe(5);
    expect(up.travel).toEqual({ home: 'gn-5391959', here: 'gn-5391959', passes: {}, visits: {}, stamps: [], fallback: SF_FALLBACK, explorer: 0 });
    const { v: _a, travel: _b, ...rest } = up;   // (no fishing_city keys in this save)
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

  it('the store keeps the v4 file once, then rewrites it as v5', () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'p0-v5-'));
    const file = path.join(dir, 'p0-state.json');
    const input = JSON.stringify({ a: v4('a'), b: v4('b') });
    writeFileSync(file, input);
    const store = new P0Store(c, file);
    expect(store.migrated).toBe(2);
    expect(readFileSync(`${file}.v4.bak`, 'utf8')).toBe(input);
    store.put(store.peek('a')!);
    const written = JSON.parse(readFileSync(file, 'utf8')) as Record<string, P0State>;
    expect(Object.values(written).map(s => s.v)).toEqual([5, 5]);
    const again = new P0Store(c, file);
    expect(again.migrated).toBe(0);
    expect(readFileSync(`${file}.v4.bak`, 'utf8')).toBe(input);   // not overwritten by the second load
    expect(existsSync(`${file}.v5.bak`)).toBe(false);
  });
});
