import { afterAll,beforeAll,beforeEach,describe,expect,it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import pg from 'pg';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate,truncateAll } from '../../src/db/migrate.js';
import { migrateDomain } from '../../src/db/domain_migration.js';
import { DEFAULT_CONTENT_DIR,contentVersion,loadContent } from '../../src/domain/content.js';
import { createInitialState } from '../../src/domain/state.js';
import { loadPlot,isTillable } from '../../src/domain/plot.js';
import { generateFarmTerrain,terrainNavigation } from '../../src/geography/farm_terrain.js';
import type { FarmRow } from '../../src/http/dto.js';
import type { RelocationDraft } from '../../src/domain/farm_relocation.js';
import { CENTER,fixtureGeography } from '../geography/fixtures.js';
import { compactFixtureGeography } from '../geography/compact_fixtures.js';
const DSN=process.env.TEST_DATABASE_URL;
if(DSN&&!/(?:^|_)(?:test|migration)(?:_|$)/i.test(new URL(DSN).pathname.slice(1)))throw new Error('Compact tests require isolated database');
const content=loadContent(DEFAULT_CONTENT_DIR),cv=contentVersion(DEFAULT_CONTENT_DIR),plot=loadPlot(content.farm_plot),base=content.farm_plot.layouts[content.farm_plot.default_layout],now=Date.now();
const v1=generateFarmTerrain(CENTER,fixtureGeography(),base),v2=generateFarmTerrain(CENTER,compactFixtureGeography(),base,'east_asian',2);
describe.skipIf(!DSN)('PostgreSQL mixed-size geographic farms',()=>{
 let pool:pg.Pool,store:PgStore;
 const newStore=()=>new PgStore({pool,content,contentVersion:cv,plot,timezone:()=> 'Asia/Shanghai',now:()=>now});
 beforeAll(async()=>{pool=new pg.Pool({connectionString:DSN,max:4});await migrate(pool);store=newStore();});
 afterAll(async()=>{await pool?.end();});beforeEach(async()=>{await truncateAll(pool);});
 async function seed(version:0|1|2=0){
  const {player}=await store.authAnonymous(randomUUID()),terrain=version===1?v1:version===2?v2:undefined;
  const farm:FarmRow={id:randomUUID(),owner_id:player.id,region_id:'shanghai',layout_patch_id:terrain?.layout_id??'sh_a',blueprint_revision:terrain?1:2,
   ...(terrain?{farm_terrain:terrain}:{}),version:0,visit_access:'only_me',location_visible:false,state:createInitialState({now,player_day_id:'2026-09-21',field_condition:'sunny',wallet:187})};
  await store.createFarm({ownerId:player.id,idempotencyKey:'create',payloadHash:'create',regionId:farm.region_id,layoutPatchId:farm.layout_patch_id,blueprintRevision:farm.blueprint_revision,build:()=>farm});
  if(!terrain)await pool.query('UPDATE farms SET relocation_available=true WHERE id=$1',[farm.id]);return farm;
 }
 const draft=(farm:FarmRow,version:1|2=2):RelocationDraft=>({generation_version:version,preview_id:randomUUID(),base_version:farm.version,expires_at:now+100000,
  region_id:farm.region_id,location:CENTER,farm_terrain:version===1?v1:v2,moved_cells:0,moved_decorations:0});
 it('leaves legacy and generation 1 saves exact while persisting/reloading a new generation 2 farm',async()=>{
  const old=await seed(),large=await seed(1),small=await seed(2);
  const snapshot=async()=>(await pool.query('SELECT to_jsonb(f) AS row FROM farms f ORDER BY id')).rows;
  const before=await snapshot();store=newStore();
  expect((await store.farmById(old.id))!.farm_terrain).toBeUndefined();expect((await store.farmById(large.id))!.farm_terrain).toEqual(v1);
  expect((await store.farmById(small.id))!.farm_terrain).toEqual(v2);expect(terrainNavigation((await store.farmById(small.id))!.farm_terrain!).rows).toHaveLength(40);
  expect(await migrateDomain(pool,{plot,content,contentVersion:cv,apply:true})).toMatchObject({migrated:0});expect(await snapshot()).toEqual(before);
 });
 it('commits compact relocation exactly once, preserving assets through store restart and receipt replay',async()=>{
  const farm=await seed();farm.state.cells={'55,10':{state:'growing',crop:'R',watered_at:100,ready_at:1234567},'52,10':{state:'sown',crop:'L',watered_at:null,ready_at:null}};
  farm.state.decorations=[{prop_id:'bench',cell:[50,12],rotation_q:3}];await pool.query('UPDATE farms SET state=$2 WHERE id=$1',[farm.id,JSON.stringify(farm.state)]);
  const before=(await store.farmById(farm.id))!,preview=draft(before);expect(await store.saveRelocationPreview(farm.owner_id,preview)).toEqual({});
  const input={preview_id:preview.preview_id,base_version:preview.base_version,idempotency_key:'compact-confirm'};
  const results=await Promise.all([store.confirmFarmRelocation(farm.owner_id,input),newStore().confirmFarmRelocation(farm.owner_id,input)]);
  expect(results.map(r=>r.kind).sort()).toEqual(['applied','replayed']);const after=(await newStore().farmById(farm.id))!;
  expect(after.farm_terrain).toEqual(v2);expect(after.version).toBe(1);expect(after.relocation_used).toBe(true);expect(after.id).toBe(before.id);expect(after.owner_id).toBe(before.owner_id);
  expect({...after.state,cells:before.state.cells,decorations:before.state.decorations}).toEqual(before.state);
  expect(Object.values(after.state.cells)).toEqual(expect.arrayContaining(Object.values(before.state.cells)));expect(after.state.decorations![0].rotation_q).toBe(3);
  expect((await newStore().confirmFarmRelocation(farm.owner_id,input)).kind).toBe('replayed');
  const inside={type:'till_cells' as const,cell_ids:['26,15']};expect((await store.applyCommand(farm.owner_id,{type:inside.type,payload:{cell_ids:inside.cell_ids},base_version:1,idempotency_key:'inside',terrain_checksum:v2.plot.checksum},inside)).kind).toBe('applied');
  const outside={type:'till_cells' as const,cell_ids:['55,10']};expect(await store.applyCommand(farm.owner_id,{type:outside.type,payload:{cell_ids:outside.cell_ids},base_version:2,idempotency_key:'outside',terrain_checksum:v2.plot.checksum},outside)).toMatchObject({kind:'rejected',code:'CELL_NOT_CULTIVABLE'});
 });
 it('retains the exact frozen 64-cell preview when confirmation resumes under the v2-capable server',async()=>{
  const farm=await seed(),preview=draft(farm,1);delete preview.generation_version;await store.saveRelocationPreview(farm.owner_id,preview);
  const result=await newStore().confirmFarmRelocation(farm.owner_id,{preview_id:preview.preview_id,base_version:0,idempotency_key:'old-preview'});
  expect(result.kind).toBe('applied');expect((await store.farmById(farm.id))!.farm_terrain).toEqual(v1);
 });
 it('keeps a published old-v2 farm and old-v2 preview exact after the shoreline generator fix',async()=>{
  const published=JSON.parse(readFileSync(path.resolve(DEFAULT_CONTENT_DIR,'../../../tests/fixtures/generated_compact_farm_terrain.json'),'utf8'));
  const existing=await seed(2);
  await pool.query('UPDATE farms SET farm_terrain=$2,layout_patch_id=$3 WHERE id=$1',[existing.id,JSON.stringify(published),published.layout_id]);
  const before=(await pool.query('SELECT to_jsonb(f) AS row FROM farms f WHERE id=$1',[existing.id])).rows[0].row;
  expect((await newStore().farmById(existing.id))!.farm_terrain).toEqual(published);
  expect((await pool.query('SELECT to_jsonb(f) AS row FROM farms f WHERE id=$1',[existing.id])).rows[0].row).toEqual(before);
  const legacy=await seed(),preview={...draft(legacy,2),farm_terrain:published};await store.saveRelocationPreview(legacy.owner_id,preview);
  expect((await newStore().confirmFarmRelocation(legacy.owner_id,{preview_id:preview.preview_id,base_version:0,idempotency_key:'old-v2-preview'})).kind).toBe('applied');
  expect((await store.farmById(legacy.id))!.farm_terrain).toEqual(published);
 });
 it('atomically refuses insufficient capacity even at confirmation without changing saved JSON or opportunity',async()=>{
  const farm=await seed();for(let j=0;j<64;j++)for(let i=0;i<64;i++)if(isTillable(plot,`${i},${j}`))farm.state.cells[`${i},${j}`]={state:'tilled',crop:null,watered_at:null,ready_at:null};
  await pool.query('UPDATE farms SET state=$2 WHERE id=$1',[farm.id,JSON.stringify(farm.state)]);const preview=draft(farm);await store.saveRelocationPreview(farm.owner_id,preview);
  const before=(await pool.query('SELECT to_jsonb(f) AS row FROM farms f WHERE id=$1',[farm.id])).rows[0].row;
  expect(await store.confirmFarmRelocation(farm.owner_id,{preview_id:preview.preview_id,base_version:0,idempotency_key:'no-space'})).toEqual({kind:'rejected',code:'RELOCATION_NO_SPACE'});
  expect((await pool.query('SELECT to_jsonb(f) AS row FROM farms f WHERE id=$1',[farm.id])).rows[0].row).toEqual(before);
 });
});
