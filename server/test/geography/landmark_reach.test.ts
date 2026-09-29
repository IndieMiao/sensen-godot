/** 客户端全国地标目录（assets/map/landmarks.json）里的每个地标，都至少能从一座可选城市的中心看到。 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { DEFAULT_CITIES_FILE } from '../../src/geography/cities.js';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';

const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const landmarks = JSON.parse(readFileSync(path.join(ROOT, 'assets', 'map', 'landmarks.json'), 'utf8')).landmarks as
  { id: string; lat: number; lng: number; reach_km: number }[];
const cities = readFileSync(DEFAULT_CITIES_FILE, 'utf8').split('\n').filter(l => l && !l.startsWith('#'))
  .map(l => l.split('\t')).map(f => ({ name: f[1], lat: Number(f[2]), lng: Number(f[3]) }));
const km = (a: number, b: number, c: number, d: number) => {
  const r = Math.PI / 180, x = (d - b) * r * Math.cos((a + c) / 2 * r), y = (c - a) * r;
  return 6371 * Math.hypot(x, y);
};

describe('designer landmarks', () => {
  it('are each within reach of at least one selectable city', () => {
    expect(landmarks.length).toBe(47);
    expect(cities.length).toBeGreaterThan(20000);
    const missing = landmarks.filter(g => !cities.some(c => km(c.lat, c.lng, g.lat, g.lng) <= g.reach_km)).map(g => g.id);
    expect(missing).toEqual([]);
  });
});
