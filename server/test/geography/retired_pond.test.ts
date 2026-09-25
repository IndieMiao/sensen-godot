import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { DEFAULT_CONTENT_DIR, loadContent } from '../../src/domain/content.js';
import { loadPlot } from '../../src/domain/plot.js';
import { generateFarmTerrain, retireFarmPond, plotForFarm, terrainNavigation } from '../../src/geography/farm_terrain.js';
import { CENTER } from './fixtures.js';
import { compactFixtureGeography } from './compact_fixtures.js';

const content = loadContent(DEFAULT_CONTENT_DIR);
const base = content.farm_plot.layouts[content.farm_plot.default_layout];
const fallback = loadPlot(content.farm_plot);
const root = path.resolve(DEFAULT_CONTENT_DIR, '../../..');

describe('retired artificial farm ponds', () => {
  it('creates generation 3 farms without pond allocation, while preserving actual water and facilities', () => {
    const terrain = generateFarmTerrain(CENTER, compactFixtureGeography(), base, 'barn', 3);
    expect(terrain.source).toMatchObject({ generator_version: 3, extent_m: 160 });
    expect(terrain.plot.regions.some(r => r.id === 'pond' || r.id?.startsWith('facility_pond'))).toBe(false);
    expect(terrain.plot.regions.some(r => r.kind === 'water' && r.polygon)).toBe(true);
    expect(terrain.plot.anchors).not.toHaveProperty('pond_shore');
    const plot = plotForFarm({ farm_terrain: terrain }, fallback);
    for (const key of ['spawn', 'mine_approach', 'stall']) {
      const [x,y] = plot.anchors[key];
      expect(plot.walk[y * plot.gx + x]).toBe(1);
    }
    expect(terrainNavigation(terrain).rows).toHaveLength(40);
    expect(generateFarmTerrain(CENTER, compactFixtureGeography(), base, 'barn', 3)).toEqual(terrain);
  });

  it.each(['generated_farm_terrain.json','generated_compact_farm_terrain.json','generated_shoreline_farm_terrain.json'])(
    'reclaims only the authored pond in %s without moving anything else', name => {
      const old = JSON.parse(readFileSync(path.join(root, 'tests/fixtures', name), 'utf8'));
      const before = structuredClone(old), prior = plotForFarm({ farm_terrain: old }, fallback);
      const next = retireFarmPond(old), plot = plotForFarm({ farm_terrain: next }, fallback);
      expect(old).toEqual(before);
      expect(next.source).toEqual(old.source);
      expect(next.farm_style).toEqual(old.farm_style);
      expect(next.layout_id).not.toBe(old.layout_id);
      expect(next.plot.regions).toEqual(old.plot.regions.map((r: any) => r.id === 'pond' && r.kind === 'water' && r.ellipse ? {...r,kind:'soil'} : r));
      for (const [key, value] of Object.entries(old.plot.anchors))
        if (!key.startsWith('pond_')) expect(next.plot.anchors[key]).toEqual(value);
      let added = 0;
      for (let n = 0; n < prior.walk.length; n++) {
        expect(plot.walk[n]).toBeGreaterThanOrEqual(prior.walk[n]);
        expect(plot.till[n]).toBeGreaterThanOrEqual(prior.till[n]);
        expect(plot.place[n]).toBeGreaterThanOrEqual(prior.place[n]);
        added += plot.till[n] - prior.till[n];
      }
      expect(added).toBeGreaterThan(0);
      expect(retireFarmPond(next)).toEqual(next);
    });

  it('rejects damaged persisted geometry instead of inventing replacement land', () => {
    const old = JSON.parse(readFileSync(path.join(root,'tests/fixtures/generated_compact_farm_terrain.json'),'utf8'));
    old.plot.regions[0].kind = 'water';
    expect(() => retireFarmPond(old)).toThrow('TERRAIN_MISMATCH');
  });

  it('produces the same layout after JSONB-style object key reordering', () => {
    const original = JSON.parse(readFileSync(path.join(root,'tests/fixtures/generated_compact_farm_terrain.json'),'utf8'));
    const reorder = (value: any): any => Array.isArray(value) ? value.map(reorder)
      : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).reverse().map(key=>[key,reorder(value[key])])) : value;
    expect(retireFarmPond(reorder(original))).toEqual(retireFarmPond(original));
  });
});
