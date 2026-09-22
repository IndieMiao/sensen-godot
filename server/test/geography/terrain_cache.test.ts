import {describe,expect,it} from 'vitest';
import {loadContent,DEFAULT_CONTENT_DIR} from '../../src/domain/content.js';
import {generateFarmTerrain,plotForFarm} from '../../src/geography/farm_terrain.js';
import {rasterize} from '../../src/domain/plot.js';
import {CENTER,fixtureGeography} from './fixtures.js';
const content=loadContent(DEFAULT_CONTENT_DIR),base=content.farm_plot.layouts[content.farm_plot.default_layout];

describe('persisted terrain cache integrity',()=>{
  it('rejects changed geometry and anchors retaining a previously verified checksum',()=>{
    const terrain=generateFarmTerrain(CENTER,fixtureGeography(),base),fallback=rasterize('base',base);
    const verified=plotForFarm({farm_terrain:terrain},fallback);
    const changedGround=structuredClone(terrain);
    changedGround.plot.regions.push({kind:'water',rect:[0,0,64,64]});
    expect(()=>plotForFarm({farm_terrain:changedGround},fallback)).toThrow('TERRAIN_MISMATCH');
    const changedAnchor=structuredClone(terrain);
    changedAnchor.plot.anchors.spawn=[2,2];
    expect(()=>plotForFarm({farm_terrain:changedAnchor},fallback)).toThrow('TERRAIN_MISMATCH');
    const changedFormat={...structuredClone(terrain),format:2};
    expect(()=>plotForFarm({farm_terrain:changedFormat as typeof terrain},fallback)).toThrow('TERRAIN_MISMATCH');
    expect(plotForFarm({farm_terrain:structuredClone(terrain)},fallback)).toBe(verified);
    expect(verified.checksum).toBe(terrain.plot.checksum);
  });
});
