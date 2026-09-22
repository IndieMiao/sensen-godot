import { afterEach,describe,expect,it } from 'vitest';
import path from 'node:path';
import type { FastifyInstance } from 'fastify';
import { buildApp,plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { DEFAULT_CONTENT_DIR,contentVersion,loadContent } from '../../src/domain/content.js';
import { isTillable } from '../../src/domain/plot.js';
import { FARM_GENERATIONS } from '../../src/geography/farm_terrain.js';
import { CENTER,fixtureGeography } from '../geography/fixtures.js';
import { compactFixtureGeography } from '../geography/compact_fixtures.js';
const content=loadContent(DEFAULT_CONTENT_DIR),cv=contentVersion(DEFAULT_CONTENT_DIR),root=path.resolve(DEFAULT_CONTENT_DIR,'../../..');
let app:FastifyInstance;afterEach(async()=>{await app?.close();});
async function setup(legacy=false){
 const extents:number[]=[];const store=new MemoryStore({content,contentVersion:cv,plot:plotFor(content),timezone:'Asia/Shanghai',now:Date.now});
 app=await buildApp({store,content,contentVersion:cv,blueprintDir:path.join(root,'assets/blueprints'),regionsFile:path.join(DEFAULT_CONTENT_DIR,'regions.json'),pepper:'test',now:Date.now,realtimeEnabled:false,
  geographyProvider:async(_center,extent)=>{extents.push(extent);return extent===160?compactFixtureGeography():fixtureGeography();}});
 const auth=(await app.inject({method:'POST',url:'/v1/auth/anonymous',payload:{install_key:'11111111222222223333333344444444'}})).json();
 const headers={authorization:'Bearer '+auth.token};const post=(url:string,payload:object)=>app.inject({method:'POST',url,headers,payload});
 if(legacy){await post('/v1/farms',{idempotency_key:'legacy',region_id:'shanghai',layout_patch_id:'sh_a',blueprint_revision:2});const farm=(await store.farmByOwner(auth.player_id))!;farm.relocation_available=true;}
 return {store,auth,headers,post,extents};
}
describe('additive compact farm generation API',()=>{
 it('advertises both generation contracts and creates only the explicitly requested size',async()=>{
  const {post,extents,headers}=await setup();const capabilities=(await app.inject({method:'GET',url:'/v1/regions'})).json();
  expect(capabilities).toMatchObject({farm_generation_version:2,farm_geography_extent_m:160,farm_generations:Object.values(FARM_GENERATIONS)});
  const input={generation_version:2,idempotency_key:'new-compact',region_id:'shanghai',location:CENTER};
  const first=await post('/v1/farms',input);expect(first.statusCode).toBe(201);const farm=first.json();
  expect(farm.farm_terrain.plot.grid).toEqual([40,40]);expect(farm.farm_terrain.source).toMatchObject({generator_version:2,extent_m:160});expect(extents).toEqual([160]);
  expect((await post('/v1/farms',input)).json()).toMatchObject({farm_id:farm.farm_id,farm_terrain:farm.farm_terrain});expect(extents).toEqual([160]);
  expect((await post('/v1/farms',{...input,generation_version:1})).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await app.inject({method:'GET',url:'/v1/farms/me',headers})).json().farm_terrain).toEqual(farm.farm_terrain);
  expect((await post('/v1/farms/me/commands',{type:'till_cells',idempotency_key:'outside',base_version:0,payload:{cell_ids:['55,10']}})).json().code).toBe('CELL_NOT_CULTIVABLE');
 });
 it('still creates 48m version 1 farms for old clients and rejects unsupported generation values',async()=>{
  const {post,extents}=await setup();const base={idempotency_key:'old-client',region_id:'shanghai',location:CENTER};
  for(const generation_version of [3,'2',2.5])expect((await post('/v1/farms',{...base,generation_version})).statusCode).toBe(400);
  const result=await post('/v1/farms',{...base,generation_version:1});expect(result.statusCode).toBe(201);expect(result.json().farm_terrain.plot.grid).toEqual([64,64]);expect(extents).toEqual([240]);
 });
 it('keeps omitted preview generation as v1 and confirms its original frozen size',async()=>{
  const {post,store,auth,extents}=await setup(true);
  for(const generation_version of [3,'2',null])expect((await post('/v1/farms/me/relocation/preview',{region_id:'shanghai',location:CENTER,generation_version})).statusCode).toBe(400);
  const draft=(await post('/v1/farms/me/relocation/preview',{region_id:'shanghai',location:CENTER})).json();
  expect(draft.generation_version).toBe(1);expect(draft.farm_terrain.plot.grid).toEqual([64,64]);expect(extents).toEqual([240]);
  const result=await post('/v1/farms/me/relocation/confirm',{preview_id:draft.preview_id,base_version:draft.base_version,idempotency_key:'confirm-v1'});
  expect(result.statusCode).toBe(200);expect(result.json().farm_terrain).toEqual(draft.farm_terrain);expect((await store.farmByOwner(auth.player_id))!.farm_terrain!.source.generator_version).toBe(1);
 });
 it('moves a legacy farm to the explicit v2 preview atomically with crops preserved',async()=>{
  const {post,store,auth,extents}=await setup(true);const old=(await store.farmByOwner(auth.player_id))!;
  old.state.cells={'55,10':{state:'growing',crop:'R',watered_at:100,ready_at:1234567}};const before=structuredClone(old);
  const preview=await post('/v1/farms/me/relocation/preview',{region_id:'shanghai',location:CENTER,generation_version:2});expect(preview.statusCode).toBe(200);const draft=preview.json();
  expect(draft.farm_terrain.plot.grid).toEqual([40,40]);expect(draft.moved_cells).toBe(1);expect(old.state).toEqual(before.state);expect(extents).toEqual([160]);
  const input={preview_id:draft.preview_id,base_version:draft.base_version,idempotency_key:'confirm-v2'};
  expect((await post('/v1/farms/me/relocation/confirm',input)).statusCode).toBe(200);expect((await post('/v1/farms/me/relocation/confirm',input)).statusCode).toBe(200);
  expect(old.version).toBe(before.version+1);expect(old.farm_terrain).toEqual(draft.farm_terrain);expect(Object.values(old.state.cells)).toEqual(Object.values(before.state.cells));
  expect({...old.state,cells:before.state.cells}).toEqual(before.state);
 });
 it('keeps a dense valid old farm and its opportunity unchanged when the smaller parcel cannot fit',async()=>{
  const {post,store,auth}=await setup(true);const farm=(await store.farmByOwner(auth.player_id))!,plot=plotFor(content);
  for(let j=0;j<64;j++)for(let i=0;i<64;i++)if(isTillable(plot,`${i},${j}`))farm.state.cells[`${i},${j}`]={state:'tilled',crop:null,watered_at:null,ready_at:null};
  const before=structuredClone(farm);const result=await post('/v1/farms/me/relocation/preview',{region_id:'shanghai',location:CENTER,generation_version:2});
  expect(result.statusCode).toBe(422);expect(result.json().code).toBe('RELOCATION_NO_SPACE');expect(farm).toEqual(before);
 });
});
