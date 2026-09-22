import { describe, expect, it } from 'vitest';
import { loadContent, DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { generateFarmTerrain, plotForFarm, terrainNavigation, visitorTerrain } from '../../src/geography/farm_terrain.js';
import { isTillable, isWalkable, pointInRing, rasterize } from '../../src/domain/plot.js';
import { CENTER, fixtureGeography, rectangle } from './fixtures.js';
const content = loadContent(DEFAULT_CONTENT_DIR), base = content.farm_plot.layouts[content.farm_plot.default_layout];
const generate = (geo = fixtureGeography()) => generateFarmTerrain(CENTER, geo, base);

describe('geographic farm terrain', () => {
  it('generates different terrain from actual shapes while keeping facilities and a stable checksum', () => {
    const terrain = generate(), plot = plotForFarm({ farm_terrain: terrain }, rasterize('base',base));
    expect(terrain.plot.grid).toEqual([64,64]); expect(terrain.plot.cell_mm).toBe(750);
    expect(terrain.plot.anchors).toEqual(base.anchors);
    expect(plot.checksum).toBe(terrain.plot.checksum);
    expect(isWalkable(plot, '42,45')).toBe(false);
    expect(isWalkable(plot, '46,47')).toBe(true); // actual island hole
    expect(isTillable(plot, '39,10')).toBe(false); // real meadow
    expect(isTillable(plot, '17,8')).toBe(true);
    expect(isWalkable(plot, '28,35')).toBe(true);
    expect(isWalkable(plot, '12,41')).toBe(false); // guaranteed fishing pond
    expect(isWalkable(plot, '12,37')).toBe(true); // its south shore is reachable
    const other = generate(fixtureGeography([{id:'other/land',kind:'land',polygon:rectangle(-1,-1,66,66)}]));
    expect(other.layout_id).not.toBe(terrain.layout_id);
    expect(generate().plot.checksum).toBe(terrain.plot.checksum);
    const nav = terrainNavigation(terrain);
    expect(nav.spawn).toEqual([21.375,-26.625]); expect(nav.rows[45][42]).toBe('0');
    expect(visitorTerrain(terrain)).not.toHaveProperty('source');
  });
  it.each([['water','LOCATION_ALL_WATER'], ['desert','LOCATION_ALL_DESERT']] as const)('rejects all %s before adding facilities', (kind, code) => {
    expect(() => generate(fixtureGeography([{id:'all',kind,polygon:rectangle(-100,-100,300,300)}]))).toThrow(code);
  });
  it('rejects unknown coverage and a tiny habitable island', () => {
    expect(() => generate(fixtureGeography([]))).toThrow('GEOGRAPHY_UNAVAILABLE');
    expect(() => generate(fixtureGeography([{id:'water',kind:'water',polygon:rectangle(-1,-1,66,66),holes:[rectangle(10,10,5,5)]},
      {id:'land',kind:'land',polygon:rectangle(10,10,5,5)}]))).toThrow('LOCATION_UNSUITABLE');
  });
  it('treats hole boundaries as water exclusion and outer polygon boundaries as inside', () => {
    expect(pointInRing([0,0], [[0,0],[5,0],[5,5],[0,5],[0,0]])).toBe(true);
    expect(pointInRing([5.001,0], [[0,0],[5,0],[5,5],[0,5],[0,0]])).toBe(false);
  });
  it('detects a corrupted persisted checksum', () => {
    const terrain=generate(); terrain.plot.checksum='invalid';
    expect(()=>plotForFarm({farm_terrain:terrain},rasterize('base',base))).toThrow('TERRAIN_MISMATCH');
  });
});
