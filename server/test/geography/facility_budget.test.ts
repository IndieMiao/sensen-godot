import { describe,expect,it } from 'vitest';
import { loadContent,DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { generateFarmTerrain,MAX_FACILITY_RASTERIZATIONS,MAX_FACILITY_CANDIDATES,type GeoFeature } from '../../src/geography/farm_terrain.js';
import { CENTER,fixtureGeography } from './fixtures.js';
import { compactRectangle } from './compact_fixtures.js';
const content=loadContent(DEFAULT_CONTENT_DIR),base=content.farm_plot.layouts[content.farm_plot.default_layout];
describe('bounded facility fitting on fragmented land',()=>{
 it.each([3,4])('caps rasterization for an unfit narrow peninsula and spaced land fingers (gap %i)',gap=>{
  // A connected mapped peninsula exceeds the area threshold, but its usable interior
  // cannot fit this facility composition and the required cultivation area. Thin
  // fingers create many plausible placements without making the interior wider.
  const features:GeoFeature[]=[
   {id:'peninsula',kind:'land',surface:'lawn',polygon:compactRectangle(-.5,9.5,11,30)},
   {id:'spine',kind:'land',surface:'lawn',polygon:compactRectangle(9.5,-.5,1,40)}];
  for(let y=0;y<40;y+=gap)features.push({id:'finger-'+y,kind:'land',surface:'lawn',polygon:compactRectangle(10.5,y-.5,29,1)});
  const input=fixtureGeography(features),before=structuredClone(input),counter={facility_candidates:0,facility_rasterizations:0};
  expect(()=>generateFarmTerrain(CENTER,input,base,undefined,2,counter)).toThrow('LOCATION_UNSUITABLE');
  expect(counter.facility_rasterizations).toBe(MAX_FACILITY_RASTERIZATIONS);
  expect(counter.facility_candidates).toBeLessThanOrEqual(MAX_FACILITY_CANDIDATES);expect(input).toEqual(before);
 });
 it('prunes disconnected home/pond combinations before rasterizing and finds a reachable same-island layout',()=>{
  const geography=fixtureGeography([
   {id:'land',kind:'land',surface:'lawn',polygon:compactRectangle(-.5,-.5,40,40)},
   {id:'channel',kind:'water',polygon:compactRectangle(18.5,-.5,1,40)}]);
  const counter={facility_candidates:0,facility_rasterizations:0};
  const terrain=generateFarmTerrain(CENTER,geography,base,undefined,2,counter);
  // The original pond is on the other island. Testing those combinations with full
  // navigation would exhaust the budget before finding a valid local pond.
  expect(terrain.plot.anchors.spawn[0]).toBeGreaterThan(19);expect(terrain.plot.anchors.pond_shore[0]).toBeGreaterThan(19);
  expect(counter.facility_rasterizations).toBe(3);expect(counter.facility_candidates).toBe(25);
 });
});
