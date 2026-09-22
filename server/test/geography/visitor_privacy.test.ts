import {describe,expect,it} from 'vitest';
import {loadContent,DEFAULT_CONTENT_DIR} from '../../src/domain/content.js';
import {rasterize} from '../../src/domain/plot.js';
import {farmStyleForRegion,generateFarmTerrain,visitorTerrain} from '../../src/geography/farm_terrain.js';
import {CENTER,fixtureGeography} from './fixtures.js';

const content=loadContent(DEFAULT_CONTENT_DIR),base=content.farm_plot.layouts[content.farm_plot.default_layout];

describe('geographic visitor privacy',()=>{
  it('retains only whitelisted visual style when the farm hides its real location',()=>{
    for (const [city,style] of [['shanghai','east_asian'],['los_angeles','barn']] as const) {
      const terrain=generateFarmTerrain(CENTER,fixtureGeography(),base,farmStyleForRegion(city));
      const visible=visitorTerrain(terrain);
      expect(visible.farm_style).toBe(style);
      expect(visible).not.toHaveProperty('source');
      expect(visible).not.toHaveProperty('region_id');
      expect(visible).not.toHaveProperty('location');
      expect(JSON.stringify(visible)).not.toContain(String(CENTER.lat));
      expect(JSON.stringify(visible)).not.toContain(String(CENTER.lng));
      expect(rasterize(visible.layout_id,visible.plot).checksum).toBe(terrain.plot.checksum);
    }
    const legacy=generateFarmTerrain(CENTER,fixtureGeography(),base);
    expect(visitorTerrain(legacy)).not.toHaveProperty('farm_style');
    const corrupt={...legacy,farm_style:'res://untrusted'} as unknown as typeof legacy;
    expect(visitorTerrain(corrupt)).not.toHaveProperty('farm_style');
  });
  it('removes public OSM references while retaining the exact playable geometry and facility IDs',()=>{
    const geography=fixtureGeography();
    geography.features.forEach((feature,index)=>feature.id=index===0?'relation/987654321/0':`way/${397637440+index}`);
    const terrain=generateFarmTerrain(CENTER,geography,base);
    const original=structuredClone(terrain);
    const visible=visitorTerrain(terrain);
    const encoded=JSON.stringify(visible);
    expect(visible).not.toHaveProperty('source');
    for(const feature of geography.features) {
      expect(encoded).not.toContain(feature.id);
      expect(encoded).not.toContain(feature.id.replace(/[^a-zA-Z0-9_]/g,'_'));
    }
    expect(visible.plot.regions.filter(region=>region.id?.startsWith('geo_'))
      .every(region=>/^geo_surface_\d+$/.test(region.id!))).toBe(true);
    expect(visible.plot.regions.filter(region=>!region.id?.startsWith('geo_')))
      .toEqual(terrain.plot.regions.filter(region=>!region.id?.startsWith('geo_')));
    const ownerPlot=rasterize(terrain.layout_id,terrain.plot),visitorPlot=rasterize(visible.layout_id,visible.plot);
    expect(visitorPlot.checksum).toBe(ownerPlot.checksum);
    expect(visitorPlot.kinds).toEqual(ownerPlot.kinds);
    expect(visitorPlot.anchors).toEqual(ownerPlot.anchors);
    expect(terrain).toEqual(original);
  });
});
