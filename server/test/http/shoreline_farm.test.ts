import { retireFarmPond } from '../../src/geography/farm_terrain.js';
import { afterEach,describe,expect,it,vi } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import type { FastifyInstance } from 'fastify';
import { buildApp,plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { DEFAULT_CONTENT_DIR,contentVersion,loadContent } from '../../src/domain/content.js';
import { GeographyError,type Geography,type GeographyProvider,type LandCoverProvider,type LandCoverSupplement } from '../../src/geography/farm_terrain.js';
import { fixtureGeography } from '../geography/fixtures.js';
import { compactRectangle } from '../geography/compact_fixtures.js';
const content=loadContent(DEFAULT_CONTENT_DIR),cv=contentVersion(DEFAULT_CONTENT_DIR),root=path.resolve(DEFAULT_CONTENT_DIR,'../../..');
const read=(name:string)=>JSON.parse(readFileSync(path.join(root,'tests/fixtures',name),'utf8'));
const osm=read('shore_osm_geography.json') as Geography,cover=read('shore_land_cover.json') as LandCoverSupplement,location={lat:34.09875,lng:-118.26627};
let app:FastifyInstance;afterEach(async()=>{vi.useRealTimers();await app?.close();});
async function setup(geo:GeographyProvider=async()=>osm,landCover:LandCoverProvider=async()=>cover,legacy=true){
 const calls={osm:0,cover:0};const store=new MemoryStore({content,contentVersion:cv,plot:plotFor(content),timezone:'America/Los_Angeles',now:Date.now});
 app=await buildApp({store,content,contentVersion:cv,blueprintDir:path.join(root,'assets/blueprints'),regionsFile:path.join(DEFAULT_CONTENT_DIR,'regions.json'),pepper:'test',now:Date.now,realtimeEnabled:false,
  geographyProvider:async(...args)=>{calls.osm++;return geo(...args);},landCoverProvider:async(...args)=>{calls.cover++;return landCover(...args);}});
 const account=(await app.inject({method:'POST',url:'/v1/auth/anonymous',payload:{install_key:'99999999000000001111111122222222'}})).json(),headers={authorization:'Bearer '+account.token};
 const post=(url:string,payload:object)=>app.inject({method:'POST',url,headers,payload});
 if(legacy){await post('/v1/farms',{idempotency_key:'legacy',region_id:'los_angeles',layout_patch_id:'la_a',blueprint_revision:2});
  const farm=(await store.farmByOwner(account.player_id))!;farm.relocation_available=true;
  farm.state.cells={'55,10':{state:'growing',crop:'R',watered_at:100,ready_at:1234567}};}
 const preview=()=>post('/v1/farms/me/relocation/preview',{region_id:'los_angeles',location,generation_version:2});
 return {calls,store,account,post,preview};
}
describe('real shoreline fallback is evidence-based and bounded',()=>{
 it('previews and confirms the original real failure point without mutating the old save during preview',async()=>{
  const {calls,store,account,post,preview}=await setup();const before=structuredClone((await store.farmByOwner(account.player_id))!);
  const response=await preview();expect(response.statusCode).toBe(200);const draft=response.json();expect(calls).toEqual({osm:1,cover:1});
  expect(draft.farm_terrain).toEqual(retireFarmPond(read('generated_shoreline_farm_terrain.json')));
  const shown=(await store.farmByOwner(account.player_id))!;expect(shown.state).toEqual(before.state);expect(shown.version).toBe(before.version);expect(shown.relocation_available).toBe(true);
  const input={preview_id:draft.preview_id,base_version:draft.base_version,idempotency_key:'shore-confirm'};
  expect((await post('/v1/farms/me/relocation/confirm',input)).statusCode).toBe(200);expect((await post('/v1/farms/me/relocation/confirm',input)).statusCode).toBe(200);
  const moved=(await store.farmByOwner(account.player_id))!;expect(moved.id).toBe(before.id);expect(Object.values(moved.state.cells)).toEqual(Object.values(before.state.cells));expect({...moved.state,cells:before.state.cells}).toEqual(before.state);
  expect(calls).toEqual({osm:1,cover:1});
 });
 it('uses the same actual-source path for fresh v2 creation and never refetches a creation replay',async()=>{
  const {calls,post}=await setup(undefined,undefined,false);const input={idempotency_key:'new-shore',generation_version:2,region_id:'los_angeles',location};
  expect((await post('/v1/farms',input)).statusCode).toBe(201);expect((await post('/v1/farms',input)).statusCode).toBe(200);expect(calls).toEqual({osm:1,cover:1});
 });
 it.each([['GEOGRAPHY_INCOMPLETE',422],['GEOGRAPHY_UNAVAILABLE',503]] as const)('preserves the old farm and opportunity on supplemental %s',async(code,status)=>{
  const {store,account,preview}=await setup(undefined,async()=>{throw new GeographyError(code);});const before=structuredClone((await store.farmByOwner(account.player_id))!);
  const result=await preview();expect(result.statusCode).toBe(status);expect(result.json().code).toBe(code);expect(await store.farmByOwner(account.player_id)).toEqual(before);
 });
 it('never calls supplemental coverage when the primary OSM request fails',async()=>{
  const {preview,calls}=await setup(async()=>{throw new GeographyError('GEOGRAPHY_UNAVAILABLE');});expect((await preview()).statusCode).toBe(503);expect(calls).toEqual({osm:1,cover:0});
 });
 it('does not fetch coverage when ordinary mapped geography is already sufficient',async()=>{
  const {post,calls}=await setup(async()=>fixtureGeography(),undefined,false);
  const response=await post('/v1/farms',{idempotency_key:'already-known',generation_version:1,region_id:'shanghai',location:{lat:31.2304,lng:121.4737}});
  expect(response.statusCode).toBe(201);expect(calls).toEqual({osm:1,cover:0});
 });
 it('bounds the optional supplemental stage at ten seconds and classifies timeout as temporary',async()=>{
  let started!:()=>void;const began=new Promise<void>(resolve=>started=resolve);
  const {preview,calls}=await setup(undefined,async()=>{started();return new Promise<LandCoverSupplement>(()=>{});});
  vi.useFakeTimers({toFake:['setTimeout','clearTimeout','Date']});const pending=preview().then(response=>response);await began;await vi.advanceTimersByTimeAsync(10000);
  const response=await pending;expect(response.statusCode).toBe(503);expect(response.json().code).toBe('GEOGRAPHY_UNAVAILABLE');expect(calls.cover).toBe(1);
 });
});
