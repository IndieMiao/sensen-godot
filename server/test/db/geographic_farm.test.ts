import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import { migrateDomain } from '../../src/db/domain_migration.js';
import { loadContent, DEFAULT_CONTENT_DIR, contentVersion } from '../../src/domain/content.js';
import { initialFarmState } from '../../src/domain/farm_factory.js';
import { startJourney } from '../../src/domain/journey.js';
import { plotFor } from '../../src/http/app.js';
import { DOMAIN_VERSION } from '../../src/domain/version.js';
import { generateFarmTerrain, plotForFarm } from '../../src/geography/farm_terrain.js';
import { CENTER, fixtureGeography } from '../geography/fixtures.js';
import type { FarmRow } from '../../src/http/dto.js';
const DSN=process.env.TEST_DATABASE_URL;
if (DSN && !/(?:^|_)(?:test|migration)(?:_|$)/i.test(new URL(DSN).pathname.slice(1))) throw new Error('Geographic farm tests need isolated database');
const content=loadContent(DEFAULT_CONTENT_DIR), cv=contentVersion(DEFAULT_CONTENT_DIR), plot=plotFor(content);
const terrain=generateFarmTerrain(CENTER,fixtureGeography(),content.farm_plot.layouts[content.farm_plot.default_layout]);
describe.skipIf(!DSN)('persisted geographic farm and legacy migration',()=>{
 let pool:pg.Pool,store:PgStore;
 beforeAll(async()=>{pool=new pg.Pool({connectionString:DSN,max:4});await migrate(pool);store=new PgStore({pool,content,contentVersion:cv,plot,timezone:()=> 'Asia/Shanghai',now:Date.now});});
 afterAll(async()=>{await pool?.end();});beforeEach(async()=>{await truncateAll(pool);});
 async function farm(generated=true){const {player}=await store.authAnonymous(randomUUID());let calls=0;
  const input={ownerId:player.id,idempotencyKey:'create',payloadHash:'payload',regionId:'shanghai',layoutPatchId:generated?terrain.layout_id:'sh_a',blueprintRevision:generated?1:2,
   build:async():Promise<FarmRow>=>{calls++;return {id:randomUUID(),owner_id:player.id,region_id:'shanghai',layout_patch_id:generated?terrain.layout_id:'sh_a',blueprint_revision:generated?1:2,
    location:CENTER,...(generated?{farm_terrain:terrain}:{}),version:0,location_visible:false,visit_access:'only_me',state:startJourney(initialFarmState(content,generated?plotForFarm({farm_terrain:terrain},plot):plot,'Asia/Shanghai',Date.now()),content)};}};
  const result=await Promise.all([store.createFarm(input),store.createFarm(input)]);expect(calls).toBe(1);return {player,input,farm:('farm' in result[0]?result[0].farm:null)!};}
 it('persists terrain atomically and commands use persisted wet/dry cells after store reload',async()=>{
   const {player,farm:created}=await farm();const saved=(await store.farmByOwner(player.id))!;expect(saved.farm_terrain).toEqual(terrain);
   const wet={type:'till_cells' as const,cell_ids:['42,45']};const out=await store.applyCommand(player.id,{type:wet.type,idempotency_key:'wet',base_version:0,payload:{cell_ids:wet.cell_ids}},wet);expect(out.kind).toBe('rejected');
   const dry={type:'till_cells' as const,cell_ids:['17,8']};const applied=await store.applyCommand(player.id,{type:dry.type,idempotency_key:'dry',base_version:0,payload:{cell_ids:dry.cell_ids}},dry);expect(applied.kind).toBe('applied');
   expect((await store.farmById(created.id))!.farm_terrain).toEqual(terrain);
 });
 it('upgrades domain25 without touching state JSON text, identity, crops, equipment, commands or layout',async()=>{
   const {player,farm:created}=await farm(false);
   await pool.query("UPDATE farms SET domain_version='25', state=jsonb_set(state,'{wallet}','777'::jsonb) WHERE id=$1",[created.id]);
   const before=(await pool.query("SELECT state::text AS state, location, layout_patch_id, owner_id, version FROM farms WHERE id=$1",[created.id])).rows[0];
   const result=await migrateDomain(pool,{plot,content,contentVersion:cv,apply:true});expect(result.status).toBe('applied');expect(result.migrated).toBe(1);
   const after=(await pool.query("SELECT state::text AS state, location, layout_patch_id, owner_id, version, domain_version, farm_terrain FROM farms WHERE id=$1",[created.id])).rows[0];
   expect(after).toEqual({...before,domain_version:DOMAIN_VERSION,farm_terrain:null});expect((await store.farmByOwner(player.id))!.farm_terrain).toBeUndefined();
 });
});
