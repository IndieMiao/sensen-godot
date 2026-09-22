import { describe,expect,it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { DEFAULT_CONTENT_DIR,loadContent } from '../../src/domain/content.js';
import { loadPlot,regionContains } from '../../src/domain/plot.js';
import { generateFarmTerrain,supplementGeography,projectToPlot,clipRing,plotForFarm,terrainNavigation,farmPondSite,type Geography,type LandCoverSupplement } from '../../src/geography/farm_terrain.js';
import { validFishingCast } from '../../src/domain/fishing.js';
import { walkable } from '../../src/realtime/model.js';
import { CENTER,fixtureGeography } from './fixtures.js';
import { compactPoint,compactRectangle } from './compact_fixtures.js';
const content=loadContent(DEFAULT_CONTENT_DIR),base=content.farm_plot.layouts[content.farm_plot.default_layout],root=path.resolve(DEFAULT_CONTENT_DIR,'../../..');
const read=(name:string)=>JSON.parse(readFileSync(path.join(root,'tests/fixtures',name),'utf8'));
const osm=read('shore_osm_geography.json') as Geography,cover=read('shore_land_cover.json') as LandCoverSupplement,center={lat:34.09875,lng:-118.26627};
const syntheticCover=(kind:'land'|'water'|'desert'):LandCoverSupplement=>({source:{...cover.source,source_checksum:'synthetic-'+kind,attribution:'Explicit synthetic test fixture'},features:[{id:'test/cover',kind,polygon:compactRectangle(-1,-1,42,42)}]});
describe('fetched shoreline coverage and dry facility placement',()=>{
 it('reproduces the real failed location as incomplete data rather than a request failure',()=>{
  expect(osm.features.filter(f=>f.kind==='land')).toHaveLength(0);expect(osm.features.filter(f=>f.kind==='water')).toHaveLength(1);
  expect(()=>generateFarmTerrain(center,osm,base,'barn',2)).toThrow('GEOGRAPHY_INCOMPLETE');
 });
 it('generates the actual site with recorded OSM and ESA data, preserving every observed water cell',()=>{
  const merged=supplementGeography(osm,cover),terrain=generateFarmTerrain(center,merged,base,'barn',2);
  expect(terrain).toEqual(read('generated_shoreline_farm_terrain.json'));
  const plot=plotForFarm({farm_terrain:terrain},loadPlot(content.farm_plot));let realWater=0;
  for(const feature of osm.features.filter(f=>f.kind==='water')){
   const region={kind:'water' as const,polygon:clipRing(feature.polygon!.map(p=>projectToPlot(p,center,2)),40)};
   for(let j=0;j<40;j++)for(let i=0;i<40;i++)if(regionContains(region,i,j)){realWater++;expect(plot.kinds[j*40+i]).toBe(3);}
  }
  expect(realWater).toBe(628);expect(terrain.source.water_fraction).toBe(628/1600);expect(terrain.source.known_fraction).toBe(1);
  expect(terrain.source.land_cover).toEqual(cover.source);expect(terrain.source.license).toContain('CC BY 4.0');
  expect(terrain.plot.anchors.house).not.toEqual([24,30]);expect(plot.till.reduce((a,b)=>a+b,0)).toBeGreaterThanOrEqual(128);
  const nav=terrainNavigation(terrain),site=farmPondSite(terrain,content.fishing.sites.farm_pond);
  expect(validFishingCast(site,site.stand,site.center,content.fishing,p=>walkable(nav,p))).toBe(true);
  for(const name of ['spawn','pond_shore','pond_stand','mine_approach','stall','exit']){
   const [x,y]=terrain.plot.anchors[name];expect(plot.walk[y*40+x]).toBe(1);
  }
 });
 it('does not mutate either source, and existing 48m/32m terrain remains exactly loadable',()=>{
  const beforeOsm=structuredClone(osm),beforeCover=structuredClone(cover);generateFarmTerrain(center,supplementGeography(osm,cover),base,'barn',2);
  expect(osm).toEqual(beforeOsm);expect(cover).toEqual(beforeCover);
  for(const name of ['generated_farm_terrain.json','generated_compact_farm_terrain.json']){
   const frozen=read(name),before=structuredClone(frozen);expect(plotForFarm({farm_terrain:frozen},loadPlot(content.farm_plot)).checksum).toBe(frozen.plot.checksum);expect(frozen).toEqual(before);
  }
 });
 it.each([['water','LOCATION_ALL_WATER'],['desert','LOCATION_ALL_DESERT']] as const)('never uses supplemental land to erase known OSM %s', (kind,error)=>{
  const primary=fixtureGeography([{id:'known',kind,polygon:compactRectangle(-1,-1,42,42)}]);
  expect(()=>generateFarmTerrain(CENTER,supplementGeography(primary,syntheticCover('land')),base,undefined,2)).toThrow(error);
 });
 it.each([['water','LOCATION_ALL_WATER'],['desert','LOCATION_ALL_DESERT']] as const)('rejects supplemental all-%s even when OSM contains a road', (kind,error)=>{
  const primary=fixtureGeography([{id:'road',kind:'road',line:[compactPoint(2,20),compactPoint(38,20)]}]);
  expect(()=>generateFarmTerrain(CENTER,supplementGeography(primary,syntheticCover(kind)),base,undefined,2)).toThrow(error);
 });
 it('requests coverage when unknown land could decide suitability even below the old 50% cutoff',()=>{
  const geography=fixtureGeography([
   {id:'water',kind:'water',polygon:compactRectangle(-1,-1,42,42),holes:[compactRectangle(-.5,-.5,25,20)]},
   {id:'known-land',kind:'land',polygon:compactRectangle(-.5,-.5,10,20)}]);
  expect(()=>generateFarmTerrain(CENTER,geography,base,undefined,2)).toThrow('GEOGRAPHY_INCOMPLETE');
  const impossible=fixtureGeography([
   {id:'water',kind:'water',polygon:compactRectangle(-1,-1,42,42),holes:[compactRectangle(-.5,-.5,10,21)]},
   {id:'known-land',kind:'land',polygon:compactRectangle(-.5,-.5,10,20)}]);
  expect(()=>generateFarmTerrain(CENTER,impossible,base,undefined,2)).toThrow('LOCATION_UNSUITABLE');
 });
});
