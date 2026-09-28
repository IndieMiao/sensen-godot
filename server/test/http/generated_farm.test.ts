import { afterEach, describe, expect, it } from 'vitest';
import path from 'node:path';
import { buildApp, plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { loadContent, contentVersion, DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { fixtureGeography, CENTER, rectangle } from '../geography/fixtures.js';
import { GeographyError, type GeographyProvider } from '../../src/geography/farm_terrain.js';
import type { FastifyInstance } from 'fastify';
const content=loadContent(DEFAULT_CONTENT_DIR), root=path.resolve(DEFAULT_CONTENT_DIR,'../../..');
let app:FastifyInstance;
afterEach(async()=>{await app?.close();});
async function setup(provider:GeographyProvider=async()=>fixtureGeography()) {
  const store=new MemoryStore({content,contentVersion:contentVersion(DEFAULT_CONTENT_DIR),plot:plotFor(content),timezone:'Asia/Shanghai',now:()=>Date.now()});
  app=await buildApp({ guestWrites: true,store,content,contentVersion:contentVersion(DEFAULT_CONTENT_DIR),blueprintDir:path.join(root,'assets/blueprints'),regionsFile:path.join(DEFAULT_CONTENT_DIR,'regions.json'),pepper:'test',now:()=>Date.now(),geographyProvider:provider});
  const auth=(await app.inject({method:'POST',url:'/v1/auth/anonymous',payload:{install_key:'9876543210abcdef9876543210abcdef'}})).json();
  const headers={authorization:'Bearer '+auth.token};
  const payload={generation_version:1,idempotency_key:'generated-farm',region_id:'shanghai',location:CENTER};
  return {store,headers,payload,auth};
}
describe('generated farm creation',()=>{
  it('creates a location-only private farm, freezes terrain across concurrent retry and reload, uses it for farming',async()=>{
    let calls=0;const {headers,payload}=await setup(async()=>{calls++;return fixtureGeography();});
    const results=await Promise.all([app.inject({method:'POST',url:'/v1/farms',headers,payload}),app.inject({method:'POST',url:'/v1/farms',headers,payload})]);
    expect(results.map(r=>r.statusCode).sort()).toEqual([200,201]);expect(calls).toBe(1);
    const farm=results[0].json();expect(farm.layout_patch_id).toMatch(/^geo_[0-9a-f]{20}$/);expect(farm.visit_access).toBe('only_me');expect(farm.farm_terrain.plot.cell_mm).toBe(750);expect(farm.farm_terrain.farm_style).toBe('east_asian');
    const loaded=(await app.inject({method:'GET',url:'/v1/farms/me',headers})).json();expect(loaded.farm_terrain).toEqual(farm.farm_terrain);
    const wet=await app.inject({method:'POST',url:'/v1/farms/me/commands',headers,payload:{type:'till_cells',idempotency_key:'wet',base_version:0,payload:{cell_ids:['42,45']}}});
    expect(wet.statusCode).toBe(422);
    const dry=await app.inject({method:'POST',url:'/v1/farms/me/commands',headers,payload:{type:'till_cells',idempotency_key:'dry',base_version:0,payload:{cell_ids:['17,8']}}});
    expect(dry.statusCode).toBe(200);expect(dry.json().farm_terrain).toEqual(farm.farm_terrain);
    const conflict=await app.inject({method:'POST',url:'/v1/farms',headers,payload:{...payload,location:{...CENTER,lat:CENTER.lat+.01}}});expect(conflict.statusCode).toBe(409);expect(calls).toBe(1);
  });
  it.each([['water','LOCATION_ALL_WATER'],['desert','LOCATION_ALL_DESERT']] as const)('rejects all %s without creating a save',async(kind,code)=>{
    const {headers,payload}=await setup(async()=>fixtureGeography([{id:'all',kind,polygon:rectangle(-100,-100,300,300)}]));
    const result=await app.inject({method:'POST',url:'/v1/farms',headers,payload});expect(result.statusCode).toBe(422);expect(result.json().code).toBe(code);
    expect((await app.inject({method:'GET',url:'/v1/farms/me',headers})).statusCode).toBe(404);
  });
  it('allows retry after unavailable data and replays a successful save without accessing provider again',async()=>{
    let calls=0;const {headers,payload}=await setup(async()=>{calls++;if(calls!==2)throw new GeographyError('GEOGRAPHY_UNAVAILABLE');return fixtureGeography();});
    expect((await app.inject({method:'POST',url:'/v1/farms',headers,payload})).statusCode).toBe(503);
    expect((await app.inject({method:'POST',url:'/v1/farms',headers,payload})).statusCode).toBe(201);
    expect((await app.inject({method:'POST',url:'/v1/farms',headers,payload})).statusCode).toBe(200);expect(calls).toBe(2);
  });
  it('retains the legacy creation contract and preserves its state',async()=>{
    const {headers}=await setup();const payload={idempotency_key:'legacy',region_id:'shanghai',layout_patch_id:'sh_a',blueprint_revision:2};
    const created=(await app.inject({method:'POST',url:'/v1/farms',headers,payload})).json();expect(created).not.toHaveProperty('farm_terrain');
    const loaded=(await app.inject({method:'GET',url:'/v1/farms/me',headers})).json();expect(loaded.state).toEqual(created.state);
  });
});
