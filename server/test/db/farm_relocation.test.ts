import { afterAll,beforeAll,beforeEach,describe,expect,it } from 'vitest';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate,truncateAll } from '../../src/db/migrate.js';
import { migrateDomain } from '../../src/db/domain_migration.js';
import { contentVersion,loadContent,DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { initialFarmState } from '../../src/domain/farm_factory.js';
import { plotFor } from '../../src/http/app.js';
import { generateFarmTerrain } from '../../src/geography/farm_terrain.js';
import type { FarmRow } from '../../src/http/dto.js';
import { CENTER,fixtureGeography } from '../geography/fixtures.js';
import type { RelocationDraft } from '../../src/domain/farm_relocation.js';
const DSN=process.env.TEST_DATABASE_URL;
if(DSN&&!/(?:^|_)(?:test|migration)(?:_|$)/i.test(new URL(DSN).pathname.slice(1)))throw new Error('Relocation tests require isolated database');
const content=loadContent(DEFAULT_CONTENT_DIR),cv=contentVersion(DEFAULT_CONTENT_DIR),plot=plotFor(content);
const terrain=generateFarmTerrain(CENTER,fixtureGeography(),content.farm_plot.layouts[content.farm_plot.default_layout]);
const now=Date.now();
describe.skipIf(!DSN)('PostgreSQL atomic legacy relocation',()=>{
 let pool:pg.Pool,store:PgStore;
 const newStore=()=>new PgStore({pool,content,contentVersion:cv,plot,timezone:()=> 'Asia/Shanghai',now:()=>now});
 beforeAll(async()=>{pool=new pg.Pool({connectionString:DSN,max:8});await migrate(pool);store=newStore();});
 afterAll(async()=>{await pool?.end();});beforeEach(async()=>{await truncateAll(pool);});
 async function seed(generated=false){
  const {player}=await store.authAnonymous(randomUUID());const farm:FarmRow={id:randomUUID(),owner_id:player.id,region_id:'shanghai',layout_patch_id:generated?terrain.layout_id:'sh_a',blueprint_revision:generated?1:2,
   ...(generated?{farm_terrain:terrain}:{}),version:0,visit_access:'only_me',location_visible:false,state:initialFarmState(content,plot,'Asia/Shanghai',now)};
  farm.state.cells['42,45']={state:'growing',crop:'R',watered_at:now,ready_at:now+300000};
  await store.createFarm({ownerId:player.id,idempotencyKey:'create',payloadHash:'create',regionId:'shanghai',layoutPatchId:farm.layout_patch_id,blueprintRevision:farm.blueprint_revision,build:()=>farm});return farm;
 }
 const draft=(farm:FarmRow):RelocationDraft=>({preview_id:randomUUID(),base_version:farm.version,expires_at:now+100000,region_id:'shanghai',location:CENTER,farm_terrain:terrain,moved_cells:1,moved_decorations:0});
 async function upgrade(farm:FarmRow){await pool.query("UPDATE farms SET domain_version='26' WHERE id=$1",[farm.id]);await migrateDomain(pool,{plot,content,contentVersion:cv,apply:true});}
 it('grants exactly once to existing legacy farms while preserving every saved byte, new farms get none',async()=>{
  const legacy=await seed(),geo=await seed(true);
  await pool.query("UPDATE farms SET domain_version='26'");
  const before=(await pool.query('SELECT id,state::text AS state,version,owner_id,layout_patch_id,location FROM farms ORDER BY id')).rows;
  expect(await migrateDomain(pool,{plot,content,contentVersion:cv,apply:true})).toMatchObject({migrated:2});
  expect((await pool.query('SELECT id,state::text AS state,version,owner_id,layout_patch_id,location FROM farms ORDER BY id')).rows).toEqual(before);
  expect((await store.farmById(legacy.id))!.relocation_available).toBe(true);expect((await store.farmById(geo.id))!.relocation_available).toBe(false);
  const newer=await seed();expect((await store.farmById(newer.id))!.relocation_available).toBe(false);
  await pool.query('UPDATE farms SET relocation_available=false,relocation_used=true WHERE id=$1',[legacy.id]);
  expect(await migrateDomain(pool,{plot,content,contentVersion:cv,apply:true})).toMatchObject({migrated:0});expect((await store.farmById(legacy.id))!.relocation_available).toBe(false);
 });
 it('concurrent duplicate confirmation commits once and survives restart with no source fetch or asset loss',async()=>{
  const farm=await seed();await upgrade(farm);const d=draft(farm);const before=(await store.farmById(farm.id))!;
  expect(await store.saveRelocationPreview(farm.owner_id,d)).toEqual({});
  const input={preview_id:d.preview_id,base_version:0,idempotency_key:'confirm'};
  const results=await Promise.all([store.confirmFarmRelocation(farm.owner_id,input),newStore().confirmFarmRelocation(farm.owner_id,input)]);
  expect(results.map(r=>r.kind).sort()).toEqual(['applied','replayed']);
  const after=(await newStore().farmById(farm.id))!;
  expect(after.version).toBe(1);expect(after.relocation_available).toBe(false);expect(after.relocation_used).toBe(true);expect(after.relocation_draft).toBeNull();expect(after.farm_terrain).toEqual(terrain);
  expect({...after.state,cells:before.state.cells,decorations:before.state.decorations}).toEqual(before.state);expect(Object.values(after.state.cells)).toEqual(Object.values(before.state.cells));
  expect((await newStore().confirmFarmRelocation(farm.owner_id,input)).kind).toBe('replayed');
  expect((await pool.query("SELECT count(*)::int AS count FROM commands WHERE type='relocate_farm'")).rows[0].count).toBe(1);
 });
 it('different concurrent keys can never spend twice; locked command conflict preserves the old map',async()=>{
  const farm=await seed();await upgrade(farm);const d=draft(farm);await store.saveRelocationPreview(farm.owner_id,d);
  const input={preview_id:d.preview_id,base_version:0,idempotency_key:'first'};
  const results=await Promise.all([store.confirmFarmRelocation(farm.owner_id,input),store.confirmFarmRelocation(farm.owner_id,{...input,idempotency_key:'second'})]);
  expect(results.filter(r=>r.kind==='applied')).toHaveLength(1);expect(results.filter(r=>r.kind==='rejected')).toHaveLength(1);
  const other=await seed();await upgrade(other);const otherDraft=draft(other);await store.saveRelocationPreview(other.owner_id,otherDraft);
  const writer=await pool.connect();await writer.query('BEGIN');await writer.query('SELECT id FROM farms WHERE id=$1 FOR UPDATE',[other.id]);
  const pending=store.confirmFarmRelocation(other.owner_id,{preview_id:otherDraft.preview_id,base_version:0,idempotency_key:'stale'});
  await writer.query('UPDATE farms SET version=version+1 WHERE id=$1',[other.id]);await writer.query('COMMIT');writer.release();
  expect(await pending).toEqual({kind:'rejected',code:'RELOCATION_CONFLICT'});
  expect((await store.farmById(other.id))!.farm_terrain).toBeUndefined();expect((await store.farmById(other.id))!.relocation_available).toBe(true);
 });
 it('rolls back terrain, entitlement, snapshot and command log together on injected persistence failure',async()=>{
  const farm=await seed();await upgrade(farm);const d=draft(farm);await store.saveRelocationPreview(farm.owner_id,d);
  const before=(await pool.query('SELECT to_jsonb(f) AS row FROM farms f WHERE id=$1',[farm.id])).rows[0].row;
  await store.snapshotGetOrCreate(farm.id,now,()=>({original:true}));
  await pool.query(`CREATE FUNCTION reject_relocation_test() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected relocation failure'; END $$`);
  await pool.query('CREATE TRIGGER reject_relocation_test BEFORE INSERT ON commands FOR EACH ROW EXECUTE FUNCTION reject_relocation_test()');
  const input={preview_id:d.preview_id,base_version:0,idempotency_key:'retry'};
  try {await expect(store.confirmFarmRelocation(farm.owner_id,input)).rejects.toThrow('injected relocation failure');}
  finally {await pool.query('DROP TRIGGER reject_relocation_test ON commands');await pool.query('DROP FUNCTION reject_relocation_test()');}
  expect((await pool.query('SELECT to_jsonb(f) AS row FROM farms f WHERE id=$1',[farm.id])).rows[0].row).toEqual(before);
  expect((await pool.query('SELECT body FROM farm_snapshots WHERE farm_id=$1',[farm.id])).rows[0].body).toEqual({original:true});
  expect((await store.confirmFarmRelocation(farm.owner_id,input)).kind).toBe('applied');expect((await pool.query('SELECT * FROM farm_snapshots WHERE farm_id=$1',[farm.id])).rows).toEqual([]);
 });
 it('builds visitor snapshots from the current locked farm even if the caller loaded the previous map',async()=>{
  const old=await seed();await upgrade(old);const d=draft(old);await store.saveRelocationPreview(old.owner_id,d);
  await store.confirmFarmRelocation(old.owner_id,{preview_id:d.preview_id,base_version:0,idempotency_key:'move'});
  const snapshot=await store.snapshotGetOrCreate(old.id,now,current=>({layout_patch_id:current.layout_patch_id,version:current.version}));
  expect(old.layout_patch_id).toBe('sh_a');expect(snapshot.body).toEqual({layout_patch_id:terrain.layout_id,version:1});expect(snapshot.farm.farm_terrain).toEqual(terrain);
 });
 it('checks persisted geometry after replay but before a rebased coordinate write, preserving historical receipts',async()=>{
  const farm=await seed();await upgrade(farm);
  const command={type:'till_cells' as const,cell_ids:['17,8']};
  const env={type:command.type,payload:{cell_ids:command.cell_ids},base_version:0,idempotency_key:'old-map-edit',terrain_checksum:plot.checksum};
  expect((await store.applyCommand(farm.owner_id,env,command)).kind).toBe('applied');
  const pending=draft((await store.farmById(farm.id))!);await store.saveRelocationPreview(farm.owner_id,pending);
  await store.confirmFarmRelocation(farm.owner_id,{preview_id:pending.preview_id,base_version:pending.base_version,idempotency_key:'relocate'});
  const after=(await store.farmById(farm.id))!,savedState=(await pool.query('SELECT state::text AS state FROM farms WHERE id=$1',[farm.id])).rows[0].state;
  expect((await newStore().applyCommand(farm.owner_id,env,command)).kind).toBe('replayed');
  const edit={type:'till_cells' as const,cell_ids:['19,8']};
  const rebased={type:edit.type,payload:{cell_ids:edit.cell_ids},base_version:after.version,idempotency_key:'stale-rebased',terrain_checksum:plot.checksum};
  expect(await newStore().applyCommand(farm.owner_id,rebased,edit)).toEqual({kind:'rejected',code:'FARM_RELOCATED'});
  const missing={...rebased,idempotency_key:'legacy-rebased'};delete (missing as {terrain_checksum?:string}).terrain_checksum;
  expect(await newStore().applyCommand(farm.owner_id,missing,edit)).toEqual({kind:'rejected',code:'FARM_RELOCATED'});
  expect((await store.farmById(farm.id))!).toEqual(after);
  expect((await pool.query('SELECT state::text AS state FROM farms WHERE id=$1',[farm.id])).rows[0].state).toBe(savedState);
  expect((await newStore().applyCommand(farm.owner_id,{...rebased,idempotency_key:'correct-map',terrain_checksum:terrain.plot.checksum},edit)).kind).toBe('applied');
  expect((await store.farmById(farm.id))!.state.cells['19,8']?.state).toBe('tilled');
  expect(await newStore().applyCommand(farm.owner_id,{...rebased,terrain_checksum:terrain.plot.checksum},edit)).toEqual({kind:'idempotency_mismatch'});
  expect(await newStore().applyCommand(farm.owner_id,rebased,edit)).toMatchObject({kind:'replayed',record:{outcome:'rejected',result:{code:'FARM_RELOCATED'}}});
 });
});
