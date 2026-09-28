import { afterEach, describe, expect, it } from 'vitest';
import path from 'node:path';
import { buildApp, plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { loadContent, contentVersion, DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { fixtureGeography, CENTER, rectangle } from '../geography/fixtures.js';
import { GeographyError, type GeographyProvider } from '../../src/geography/farm_terrain.js';
import type { FastifyInstance } from 'fastify';
const content=loadContent(DEFAULT_CONTENT_DIR),root=path.resolve(DEFAULT_CONTENT_DIR,'../../..');
let app:FastifyInstance,now=Date.now();
afterEach(async()=>{await app?.close();});
async function setup(provider:GeographyProvider=async()=>fixtureGeography(),eligible=true) {
 const store=new MemoryStore({content,contentVersion:contentVersion(DEFAULT_CONTENT_DIR),plot:plotFor(content),timezone:'Asia/Shanghai',now:()=>now});
 app=await buildApp({ guestWrites: true,store,content,contentVersion:contentVersion(DEFAULT_CONTENT_DIR),blueprintDir:path.join(root,'assets/blueprints'),regionsFile:path.join(DEFAULT_CONTENT_DIR,'regions.json'),pepper:'test',now:()=>now,geographyProvider:provider,realtimeEnabled:false});
 const auth=(await app.inject({method:'POST',url:'/v1/auth/anonymous',payload:{install_key:'abcdef9876543210abcdef9876543210'}})).json();
 const headers={authorization:'Bearer '+auth.token};
 await app.inject({method:'POST',url:'/v1/farms',headers,payload:{idempotency_key:'old',region_id:'shanghai',layout_patch_id:'sh_a',blueprint_revision:2}});
 const farm=(await store.farmByOwner(auth.player_id))!;
 // Memory test fixture emulates the explicit database migration; production never grants on read.
 farm.relocation_available=eligible;farm.relocation_used=false;
 farm.state.cells={'42,45':{state:'growing',crop:'R',watered_at:now,ready_at:now+100000}};
 const preview=()=>app.inject({method:'POST',url:'/v1/farms/me/relocation/preview',headers,payload:{region_id:'shanghai',location:CENTER}});
 const confirm=(draft:Record<string,unknown>,key='move')=>app.inject({method:'POST',url:'/v1/farms/me/relocation/confirm',headers,
  payload:{preview_id:draft.preview_id,base_version:draft.base_version,idempotency_key:key}});
 return {store,headers,auth,farm,preview,confirm};
}
describe('one-time legacy farm relocation API',()=>{
 it('previews without mutating gameplay, atomically preserves assets and replays confirmations/current historical commands',async()=>{
  let calls=0;const {store,farm,headers,preview,confirm}=await setup(async()=>{calls++;return fixtureGeography();});
  const old=await app.inject({method:'POST',url:'/v1/farms/me/commands',headers,payload:{type:'set_location_visible',idempotency_key:'old-setting',base_version:0,payload:{visible:false}}});expect(old.statusCode).toBe(200);
  const before=structuredClone((await store.farmByOwner(farm.owner_id))!);
  const response=await preview();expect(response.statusCode).toBe(200);const draft=response.json();expect(draft.moved_cells).toBe(1);
  const loaded=(await app.inject({method:'GET',url:'/v1/farms/me',headers})).json();
  expect(loaded.state.cells).toEqual(before.state.cells);expect(loaded.version).toBe(before.version);expect(loaded).not.toHaveProperty('farm_terrain');expect(loaded.relocation).toEqual({available:true,used:false});expect(loaded).not.toHaveProperty('relocation_draft');
  const [first,retry]=await Promise.all([confirm(draft),confirm(draft)]);expect(first.statusCode).toBe(200);expect(retry.statusCode).toBe(200);
  const saved=(await store.farmByOwner(farm.owner_id))!;expect(saved.id).toBe(before.id);expect(saved.owner_id).toBe(before.owner_id);expect(saved.version).toBe(before.version+1);expect(saved.farm_terrain).toEqual(draft.farm_terrain);
  expect({...saved.state,cells:before.state.cells,decorations:before.state.decorations}).toEqual(before.state);
  expect(Object.values(saved.state.cells)).toEqual(Object.values(before.state.cells));expect(saved.location_visible).toBe(false);expect(first.json().relocation).toEqual({available:false,used:true});
  expect((await preview()).json().code).toBe('RELOCATION_UNAVAILABLE');expect((await confirm(draft,'second')).json().code).toBe('RELOCATION_UNAVAILABLE');expect(calls).toBe(1);
  const historical=await app.inject({method:'POST',url:'/v1/farms/me/commands',headers,payload:{type:'set_location_visible',idempotency_key:'old-setting',base_version:0,payload:{visible:false}}});
  expect(historical.json().outcome).toBe('replayed');expect(historical.json().farm_terrain).toEqual(draft.farm_terrain);expect(historical.json().version).toBe(saved.version);
  expect((await confirm({...draft,preview_id:'other'})).json().code).toBe('IDEMPOTENCY_MISMATCH');
 });
 it.each([['water','LOCATION_ALL_WATER'],['desert','LOCATION_ALL_DESERT']] as const)('invalid %s preview preserves save and opportunity',async(kind,code)=>{
  const {farm,preview}=await setup(async()=>fixtureGeography([{id:'invalid',kind,polygon:rectangle(-100,-100,300,300)}]));const before=structuredClone(farm);
  const result=await preview();expect(result.statusCode).toBe(422);expect(result.json().code).toBe(code);expect(farm).toEqual(before);
 });
 it('rejects unavailable geography without consuming opportunity and permits retry/cancel',async()=>{
  let calls=0;const {farm,preview}=await setup(async()=>{if(calls++===0)throw new GeographyError('GEOGRAPHY_UNAVAILABLE');return fixtureGeography();});const before=structuredClone(farm.state);
  expect((await preview()).statusCode).toBe(503);expect((await preview()).statusCode).toBe(200);expect(farm.state).toEqual(before);expect(farm.relocation_available).toBe(true);
 });
 it('requires fresh preview after a gameplay write and does not spend on expiry or conflict',async()=>{
  const {farm,headers,preview,confirm}=await setup();const draft=(await preview()).json();
  await app.inject({method:'POST',url:'/v1/farms/me/commands',headers,payload:{type:'set_location_visible',idempotency_key:'change',base_version:0,payload:{visible:false}}});
  expect((await confirm(draft)).json().code).toBe('RELOCATION_CONFLICT');expect(farm.relocation_available).toBe(true);
  const next=(await preview()).json();now=next.expires_at+1;expect((await confirm(next,'expired')).json().code).toBe('RELOCATION_EXPIRED');expect(farm.relocation_available).toBe(true);
  const last=(await preview()).json();expect((await confirm(last,'fresh')).statusCode).toBe(200);
 });
 it('does not grant any opportunity to a legacy farm created after migration',async()=>{
  const {headers,preview}=await setup(undefined,false);expect((await preview()).json().code).toBe('RELOCATION_UNAVAILABLE');
  expect((await app.inject({method:'GET',url:'/v1/farms/me',headers})).json().relocation).toEqual({available:false,used:false});
 });
 it('binds preview to owner and original city and rejects active mine saves',async()=>{
  const {farm,headers,preview,confirm}=await setup();expect((await confirm({preview_id:'some-other-player',base_version:0})).json().code).toBe('RELOCATION_EXPIRED');
  const other=await app.inject({method:'POST',url:'/v1/farms/me/relocation/preview',headers,payload:{region_id:'los_angeles',location:CENTER}});expect(other.json().code).toBe('LOCATION_OUTSIDE_REGION');
  farm.state.mine={version:1,run:0,floor:1,deepest_floor:1,cleared_floors:[],broken:{},elevator_unlocked:false};expect((await preview()).json().code).toBe('RELOCATION_BUSY');expect(farm.relocation_available).toBe(true);
 });
 it('blocks stale spatial edits even after a version rebase, but replays pre-move edits and accepts the new terrain',async()=>{
  const {farm,headers,preview,confirm}=await setup();
  const post=(payload:Record<string,unknown>)=>app.inject({method:'POST',url:'/v1/farms/me/commands',headers,payload});
  const legacy={type:'till_cells',idempotency_key:'before-move',base_version:0,terrain_checksum:plotFor(content).checksum,payload:{cell_ids:['17,8']}};
  expect((await post(legacy)).statusCode).toBe(200);
  const oldUnbound={...legacy,idempotency_key:'old-client-before-move',base_version:1,payload:{cell_ids:['18,8']}};
  delete (oldUnbound as Record<string,unknown>).terrain_checksum;expect((await post(oldUnbound)).statusCode).toBe(200);
  const draft=(await preview()).json();expect((await confirm(draft)).statusCode).toBe(200);
  const before=structuredClone(farm),checksum=draft.farm_terrain.plot.checksum;
  for(const old of [legacy,oldUnbound]) {
   const replay=await post(old);expect(replay.json().outcome).toBe('replayed');expect(replay.json().farm_terrain).toEqual(draft.farm_terrain);
  }
  const payloads:Record<string,unknown>={till_cells:{cell_ids:['19,8']},sow_cells:{cell_ids:['17,8'],crop:'R',lot:'bought'},
   water_cells:{cell_ids:['17,8']},harvest_cells:{cell_ids:['17,8']},clear_plot:{cell_ids:['17,8']},save_decorations:{props:[]}};
  for(const [type,payload] of Object.entries(payloads)) for(const binding of [{},{terrain_checksum:legacy.terrain_checksum}]) {
   const result=await post({type,payload,base_version:farm.version,idempotency_key:type+String(Object.keys(binding).length),...binding});
   expect(result.statusCode).toBe(422);expect(result.json().code).toBe('FARM_RELOCATED');expect(farm).toEqual(before);
  }
  const current={type:'till_cells',payload:{cell_ids:['19,8']},base_version:farm.version,idempotency_key:'new-map',terrain_checksum:checksum};
  expect((await post(current)).json().outcome).toBe('applied');expect(farm.version).toBe(before.version+1);expect(farm.state.cells['19,8']?.state).toBe('tilled');
  expect((await post({...current,terrain_checksum:legacy.terrain_checksum})).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await post({type:'set_location_visible',payload:{visible:false},base_version:farm.version,idempotency_key:'non-spatial'})).json().outcome).toBe('applied');
 });
});
