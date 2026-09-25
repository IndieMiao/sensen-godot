import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import pg from 'pg';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import { migrateDomain } from '../../src/db/domain_migration.js';
import { PgStore } from '../../src/db/pg_store.js';
import { contentVersion, DEFAULT_CONTENT_DIR, loadContent } from '../../src/domain/content.js';
import { createInitialState } from '../../src/domain/state.js';
import { ensureBag } from '../../src/domain/bag.js';
import { loadPlot } from '../../src/domain/plot.js';
import type { FarmRow } from '../../src/http/dto.js';

const DSN = process.env.TEST_DATABASE_URL;
if (DSN && !/(?:^|_)(?:test|migration)(?:_|$)/i.test(new URL(DSN).pathname.slice(1))) throw new Error('Use an isolated test database');
const content = loadContent(DEFAULT_CONTENT_DIR), cv = contentVersion(DEFAULT_CONTENT_DIR), plot = loadPlot(content.farm_plot);
const options = {plot,content,contentVersion:cv,previousContentVersion:'50c2dbdde04c9678'};
const terrain = JSON.parse(readFileSync(path.resolve(DEFAULT_CONTENT_DIR,'../../../tests/fixtures/generated_compact_farm_terrain.json'),'utf8'));

describe.skipIf(!DSN)('explicit domain 27 pond retirement', () => {
  let pool: pg.Pool, store: PgStore;
  beforeAll(async () => {
    pool = new pg.Pool({connectionString:DSN,max:4}); await migrate(pool);
    store = new PgStore({pool,content,contentVersion:cv,plot,timezone:()=> 'Asia/Shanghai',now:()=>1000000});
  });
  beforeEach(async () => { await truncateAll(pool); });
  afterAll(async () => { await pool?.end(); });
  async function seed(geographic: boolean, active = false, id = randomUUID()) {
    const {player} = await store.authAnonymous(randomUUID().replaceAll('-',''));
    const state = createInitialState({now:1000000,player_day_id:'2026-09-25',field_condition:'sunny',wallet:321});
    ensureBag(state,content);
    state.cells = {'25,15':{state:'growing',crop:'R',watered_at:100,ready_at:1234567}};
    if (active) state.fishing = {version:1,sequence:7,active:{site:'farm_pond',fish_id:'fish_crucian',seed:12,bite_at:1000000,hook_until:1005000,nonce:'old-connection'}};
    const farm: FarmRow = {id,owner_id:player.id,region_id:'shanghai',version:17,
      layout_patch_id:geographic?terrain.layout_id:'sh_a',blueprint_revision:geographic?1:2,state,
      visit_access:'anyone',location_visible:false,...(geographic?{farm_terrain:structuredClone(terrain)}:{})};
    await store.createFarm({ownerId:player.id,idempotencyKey:'create',payloadHash:'original',regionId:farm.region_id,
      layoutPatchId:farm.layout_patch_id,blueprintRevision:farm.blueprint_revision,build:()=>farm});
    await pool.query(`UPDATE farms SET domain_version='27',content_version=$2,relocation_available=false,
      relocation_used=$3,relocation_draft=$4 WHERE id=$1`,[farm.id,options.previousContentVersion,geographic,JSON.stringify({preview_id:'frozen-old-preview',farm_terrain:terrain})]);
    return farm.id;
  }
  async function rows() { return (await pool.query('SELECT * FROM farms ORDER BY id')).rows; }

  it('dry run writes nothing; apply preserves holdings and opportunity, retires only artificial geometry, and is idempotent',async()=>{
    const geographic = await seed(true); await seed(false);
    await store.snapshotGetOrCreate(geographic,100, farm=>({farm_terrain:farm.farm_terrain}));
    const before = await rows();
    expect((await migrateDomain(pool,options)).status).toBe('ready');
    expect(await rows()).toEqual(before);
    const histories = (await pool.query('SELECT * FROM farm_creations ORDER BY idempotency_key')).rows;
    const report = await migrateDomain(pool,{...options,apply:true});
    expect(report).toMatchObject({status:'applied',migrated:2,retired_ponds:1,expired_previews:2,relocated_cells:0});
    const after = await rows();
    for (let i=0;i<after.length;i++) {
      for (const key of ['id','owner_id','state','version','location','relocation_used','relocation_available','created_at','updated_at'])
        expect(after[i][key]).toEqual(before[i][key]);
      expect(after[i].relocation_draft).toBeNull();
      expect(after[i].domain_version).toBe('28');
      if (before[i].farm_terrain) {
        expect(after[i].farm_terrain.source).toEqual(before[i].farm_terrain.source);
        expect(after[i].farm_terrain.plot.regions).toEqual(before[i].farm_terrain.plot.regions.map((r:any)=>r.id==='pond'?{...r,kind:'soil'}:r));
        expect(after[i].blueprint_checksum).toBe(after[i].farm_terrain.plot.checksum);
      }
    }
    expect((await pool.query('SELECT * FROM farm_creations ORDER BY idempotency_key')).rows).toEqual(histories);
    expect((await pool.query('SELECT * FROM farm_snapshots')).rowCount).toBe(0);
    const fresh = await store.snapshotGetOrCreate(geographic,100, farm=>({farm_terrain:farm.farm_terrain}));
    expect((fresh.body as any).farm_terrain.plot.regions.some((r:any)=>r.id==='pond'&&r.kind==='water')).toBe(false);
    expect((await migrateDomain(pool,{...options,apply:true})).migrated).toBe(0);
    expect(await rows()).toEqual(after);
  });

  it('cancels an in-flight farm cast without rewards or inventory changes',async()=>{
    await seed(true,true); const before=(await rows())[0];
    expect((await migrateDomain(pool,{...options,apply:true})).cancelled_farm_casts).toBe(1);
    const after=(await rows())[0];
    expect(after.state).toEqual({...before.state,fishing:{version:1,sequence:7,active:null,last:{sequence:7,outcome:'cancelled'}}});
  });

  it('rolls every row back if any persisted terrain fails verification',async()=>{
    await seed(true,true,'00000000-0000-4000-8000-000000000001');
    const id=await seed(true,false,'00000000-0000-4000-8000-000000000002');
    const damaged=structuredClone(terrain);damaged.plot.checksum='0'.repeat(64);
    await pool.query('UPDATE farms SET farm_terrain=$2 WHERE id=$1',[id,damaged]);
    const before=await rows();
    await expect(migrateDomain(pool,{...options,apply:true})).rejects.toThrow('TERRAIN_MISMATCH');
    expect(await rows()).toEqual(before);
  });
});
