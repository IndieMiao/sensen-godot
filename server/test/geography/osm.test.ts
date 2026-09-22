import { describe, expect, it } from 'vitest';
import { createOsmProvider, geographyQuery, parseGeography, type OsmElement } from '../../src/geography/osm.js';
import { generateFarmTerrain } from '../../src/geography/farm_terrain.js';
import { loadContent, DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { CENTER, rectangle } from './fixtures.js';
const geometry = (points: [number,number][]) => points.map(([lon,lat]) => ({lon,lat}));
const outer=rectangle(-100,-100,300,300), inner=rectangle(40,40,5,5);

describe('OSM geography provider', () => {
  it('queries enclosing areas and geometry instead of assuming an empty bbox is dry land', () => {
    const query=geographyQuery(CENTER,240);
    expect(query).toContain('is_in(');expect(query).toContain('way(pivot.enclosing)');expect(query).toContain('rel(pivot.enclosing)');
    expect(query).toContain('out geom');expect(query).toContain('coastline');expect(query).toContain('desert');
  });
  it('stitches fragmented multipolygon outer and inner rings, preserving islands', () => {
    const result=parseGeography({elements:[{type:'relation',id:100,tags:{type:'multipolygon',natural:'water'},members:[
      {type:'way',ref:1,role:'outer',geometry:geometry(outer.slice(0,3))},
      {type:'way',ref:2,role:'outer',geometry:geometry([outer[0],outer[3],outer[2]])},
      {type:'way',ref:3,role:'inner',geometry:geometry(inner)},
    ]}]}, 'fixture');
    expect(result.features).toHaveLength(1);expect(result.features[0].polygon).toHaveLength(5);expect(result.features[0].holes).toEqual([inner]);
  });
  it('assigns each island hole to its own outer and suppresses duplicated tagged outer ways', () => {
    const secondOuter=rectangle(40,42,15,12), secondHole=rectangle(45,46,3,3);
    const firstOuter=rectangle(4,4,12,12), firstHole=rectangle(8,8,3,3);
    const result=parseGeography({elements:[
      {type:'way',id:10,tags:{natural:'water'},geometry:geometry(firstOuter)},
      {type:'way',id:20,tags:{natural:'water'},geometry:geometry(secondOuter)},
      {type:'relation',id:100,tags:{type:'multipolygon',natural:'water'},members:[
        {type:'way',ref:10,role:'outer',geometry:geometry(firstOuter)},
        {type:'way',ref:20,role:'outer',geometry:geometry(secondOuter)},
        {type:'way',ref:11,role:'inner',geometry:geometry(firstHole)},
        {type:'way',ref:21,role:'inner',geometry:geometry(secondHole)},
      ]},
    ]}, 'fixture');
    expect(result.features).toHaveLength(2);
    expect(result.features[0].holes).toEqual([firstHole]);
    expect(result.features[1].holes).toEqual([secondHole]);
  });
  it('rejects partial upstream results and unclosed water rings', () => {
    expect(()=>parseGeography({elements:[],remark:'runtime error: timeout'},'fixture')).toThrow('GEOGRAPHY_UNAVAILABLE');
    expect(()=>parseGeography({elements:[{type:'way',id:1,tags:{natural:'water'},geometry:geometry(outer.slice(0,3))}]},'fixture')).toThrow('GEOGRAPHY_UNAVAILABLE');
    expect(()=>parseGeography({elements:[]},'fixture')).toThrow('GEOGRAPHY_UNAVAILABLE');
  });
  it('classifies an enclosing water polygon as all water although its vertices are outside the selection', () => {
    const geo=parseGeography({elements:[{type:'way',id:1,tags:{natural:'water'},geometry:geometry(outer)}]},'fixture');
    const content=loadContent(DEFAULT_CONTENT_DIR);
    expect(()=>generateFarmTerrain(CENTER,geo,content.farm_plot.layouts[content.farm_plot.default_layout])).toThrow('LOCATION_ALL_WATER');
  });
  it('bounds response bytes and converts HTTP/provider failures to retriable errors', async () => {
    const big=createOsmProvider({fetcher:async()=>new Response('x'.repeat(50)),maxBytes:16});
    await expect(big(CENTER,240)).rejects.toThrow('GEOGRAPHY_UNAVAILABLE');
    const unavailable=createOsmProvider({fetcher:async()=>new Response('',{status:504})});
    await expect(unavailable(CENTER,240)).rejects.toThrow('GEOGRAPHY_UNAVAILABLE');
    const good=createOsmProvider({fetcher:async()=>new Response(JSON.stringify({elements:[{type:'way',id:2,tags:{landuse:'farmland'},geometry:geometry(outer)} satisfies OsmElement]}))});
    expect((await good(CENTER,240)).features[0].kind).toBe('land');
  });
});
