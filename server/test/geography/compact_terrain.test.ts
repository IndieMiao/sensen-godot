import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { loadContent, DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { loadPlot, isTillable, rasterize } from '../../src/domain/plot.js';
import { generateFarmTerrain, plotForFarm, terrainNavigation, farmPondSite } from '../../src/geography/farm_terrain.js';
import { validFishingCast } from '../../src/domain/fishing.js';
import { walkable } from '../../src/realtime/model.js';
import { relocateFarmState } from '../../src/domain/farm_relocation.js';
import { createInitialState } from '../../src/domain/state.js';
import { CENTER, fixtureGeography } from './fixtures.js';
import { compactFixtureGeography, compactPoint, compactRectangle } from './compact_fixtures.js';
const content=loadContent(DEFAULT_CONTENT_DIR),base=content.farm_plot.layouts[content.farm_plot.default_layout],oldPlot=loadPlot(content.farm_plot);
const compact=()=>generateFarmTerrain(CENTER,compactFixtureGeography(),base,'east_asian',2);
const root=path.resolve(DEFAULT_CONTENT_DIR,'../../..');
describe('generation 2 compact geographic farms',()=>{
 it('keeps the existing generation 1 golden layout byte-for-byte and never mutates its base',()=>{
  const before=structuredClone(base),legacy=generateFarmTerrain(CENTER,fixtureGeography(),base);
  expect(legacy).toEqual(JSON.parse(readFileSync(path.join(root,'tests/fixtures/generated_farm_terrain.json'),'utf8')));
  compact();expect(base).toEqual(before);expect(generateFarmTerrain(CENTER,fixtureGeography(),base)).toEqual(legacy);
  expect(plotForFarm({farm_terrain:legacy},oldPlot).gx).toBe(64);
 });
 it('uses a 32m world and 160m source while preserving cell size, full-size avatar and valid facilities and valid fishing',()=>{
  const terrain=compact(),plot=plotForFarm({farm_terrain:terrain},oldPlot),nav=terrainNavigation(terrain);
  expect(terrain.plot.grid).toEqual([40,40]);expect(terrain.plot.cell_mm).toBe(800);expect(plot.gx*plot.cellMm/1000).toBe(32);
  expect(terrain.source).toMatchObject({generator_version:2,extent_m:160,center:CENTER});expect(terrain.plot.anchors).toMatchObject({spawn:[24,27],house:[24,30],mine:[21,28],pond_shore:[8,29],mine_approach:[21,26]});
  expect(nav.rows).toHaveLength(40);expect(nav.rows.every(row=>row.length===40)).toBe(true);expect(nav.spawn).toEqual([19.6,-22]);
  expect(walkable(nav,[32.1,-10])).toBe(false);expect(isTillable(plot,'40,10')).toBe(false);
  expect(plot.walk[29*40+8]).toBe(1);expect(plot.walk[26*40+21]).toBe(1);expect(plot.walk[33*40+8]).toBe(0);
  const pond=farmPondSite(terrain,content.fishing.sites.farm_pond);
  expect(validFishingCast(pond,pond.stand,pond.center,content.fishing,point=>walkable(nav,point))).toBe(true);
  expect(terrain.plot.regions.find(r=>r.id==='pond')?.ellipse).toEqual([8,33,4.8,3.1]);
  expect(farmPondSite(undefined,content.fishing.sites.farm_pond)).toEqual(content.fishing.sites.farm_pond);
  expect(farmPondSite(generateFarmTerrain(CENTER,fixtureGeography(),base),content.fishing.sites.farm_pond)).toEqual(content.fishing.sites.farm_pond);
  expect(terrain.plot.regions.find(r=>r.id==='north_cliff')).not.toEqual(base.regions.find(r=>r.id==='north_cliff'));
  expect(compact()).toEqual(terrain);
 });
 it('matches the client compact golden fixture and clips real geometry to the selected window',()=>{
  const frozen=JSON.parse(readFileSync(path.join(root,'tests/fixtures/generated_compact_farm_terrain.json'),'utf8')),before=structuredClone(frozen);
  expect(plotForFarm({farm_terrain:frozen},oldPlot).checksum).toBe(frozen.plot.checksum);expect(frozen).toEqual(before);
  const terrain=compact();
  for(const region of terrain.plot.regions.filter(r=>r.id?.startsWith('geo_')))for(const point of [...(region.polygon??[]),...(region.path??[])])
   expect(point.every(n=>n>=-.50000001&&n<=39.50000001)).toBe(true);
  expect(terrain.plot.regions.find(r=>r.id==='geo_compact_fixture_water')?.polygon).toHaveLength(5);
 });
 it.each([['water','LOCATION_ALL_WATER'],['desert','LOCATION_ALL_DESERT']] as const)('rejects all %s before mandatory facilities are fitted', (kind,code)=>{
  expect(()=>generateFarmTerrain(CENTER,compactFixtureGeography([{id:'all',kind,polygon:compactRectangle(-10,-10,80,80)}]),base,undefined,2)).toThrow(code);
 });
 it('rejects insufficient usable land and unusable source data instead of substituting a template',()=>{
  expect(()=>generateFarmTerrain(CENTER,compactFixtureGeography([]),base,undefined,2)).toThrow('GEOGRAPHY_UNAVAILABLE');
  expect(()=>generateFarmTerrain(CENTER,compactFixtureGeography([{id:'water',kind:'water',polygon:compactRectangle(-1,-1,50,50),holes:[compactRectangle(10,10,5,5)]},
   {id:'land',kind:'land',polygon:compactRectangle(10,10,5,5)}]),base,undefined,2)).toThrow('LOCATION_UNSUITABLE');
 });
 it('validates stored generation/grid/extent associations even after caching the geometry',()=>{
  const terrain=compact();plotForFarm({farm_terrain:terrain},oldPlot);
  const wrongVersion=structuredClone(terrain);wrongVersion.source.generator_version=1;
  expect(()=>plotForFarm({farm_terrain:wrongVersion},oldPlot)).toThrow('TERRAIN_MISMATCH');
  const wrongExtent=structuredClone(terrain);wrongExtent.source.extent_m=240;
  expect(()=>plotForFarm({farm_terrain:wrongExtent},oldPlot)).toThrow('TERRAIN_MISMATCH');
 });
 it('moves outlying legacy crops and decorations without changing their ownership, attributes or mature time',()=>{
  const state=createInitialState({now:100,player_day_id:'2026-09-21',field_condition:'sunny',wallet:187});
  state.cells={'55,10':{state:'growing',crop:'R',watered_at:100,ready_at:1234567},'25,15':{state:'sown',crop:'L',watered_at:null,ready_at:null}};
  state.decorations=[{prop_id:'bench',cell:[50,12],rotation_q:3}];const before=structuredClone(state);
  expect(isTillable(oldPlot,'55,10')).toBe(true);const moved=relocateFarmState(state,plotForFarm({farm_terrain:compact()},oldPlot),content);
  expect(moved.moved_cells).toBe(1);expect(moved.moved_decorations).toBe(1);expect(state).toEqual(before);
  expect(moved.state.cells['25,15']).toEqual(before.cells['25,15']);expect(Object.values(moved.state.cells)).toEqual(expect.arrayContaining(Object.values(before.cells)));
  expect({...moved.state,cells:before.cells,decorations:before.decorations}).toEqual(before);expect(moved.state.decorations![0].rotation_q).toBe(3);
 });
 it('rejects a valid dense legacy farm atomically when its complete holdings cannot fit',()=>{
  const state=createInitialState({now:100,player_day_id:'2026-09-21',field_condition:'sunny',wallet:187});
  for(let j=0;j<64;j++)for(let i=0;i<64;i++)if(isTillable(oldPlot,`${i},${j}`))state.cells[`${i},${j}`]={state:'tilled',crop:null,watered_at:null,ready_at:null};
  expect(Object.keys(state.cells)).toHaveLength(3050);const before=structuredClone(state);
  expect(()=>relocateFarmState(state,plotForFarm({farm_terrain:compact()},oldPlot),content)).toThrow('RELOCATION_NO_SPACE');expect(state).toEqual(before);
 });
});
