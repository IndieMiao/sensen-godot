/** Real HTTP + PostgreSQL loop. Only this isolated tool owns the accelerated clock. */
import pg from 'pg';
import { readFileSync, writeFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
import { buildApp, plotFor } from '../src/http/app.js';
import { PgStore } from '../src/db/pg_store.js';
import { migrate } from '../src/db/migrate.js';
import { loadContent, contentVersion, DEFAULT_CONTENT_DIR } from '../src/domain/content.js';
import path from 'node:path';
const env=parseEnv(readFileSync(new URL('../.env',import.meta.url),'utf8'));
const url=new URL(env.TEST_DATABASE_URL);const database='sensen_farm_free_loop_test_20260917';
const admin=new pg.Pool({connectionString:url.toString(),max:1});
if(!(await admin.query('select 1 from pg_database where datname=$1',[database])).rowCount)await admin.query(`CREATE DATABASE "${database}"`);
await admin.end();url.pathname='/'+database;
const pool=new pg.Pool({connectionString:url.toString(),max:3});await migrate(pool);
const content=loadContent(DEFAULT_CONTENT_DIR),cv=contentVersion(DEFAULT_CONTENT_DIR),plot=plotFor(content);
let now=Date.now();const store=new PgStore({pool,content,contentVersion:cv,plot,timezone:()=> 'Asia/Shanghai',now:()=>now});
let app=await buildApp({ guestWrites: true,store,content,contentVersion:cv,plot,now:()=>now,pepper:'isolated-free-loop-only',regionsFile:path.join(DEFAULT_CONTENT_DIR,'regions.json'),blueprintDir:path.resolve(DEFAULT_CONTENT_DIR,'../../blueprints')});
let base=await app.listen({port:0,host:'127.0.0.1'});base+='/v1';
let token='';const key=randomUUID().replaceAll('-','');let version=0;
async function request(endpoint:string,body?:unknown,status=200){const r=await fetch(base+endpoint,{method:body===undefined?'GET':'POST',headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body)});const result:any=await r.json();assert.equal(r.status,status,JSON.stringify({endpoint,status:r.status,result}));return result;}
async function command(type:string,payload:unknown,status=200){const envelope={type,payload,idempotency_key:randomUUID().replaceAll('-',''),base_version:version};const result=await request('/farms/me/commands',envelope,status);if(result.version!==undefined)version=result.version;return {result,envelope};}
try {
 token=(await request('/auth/anonymous',{install_key:key})).token;
 const created=await request('/farms',{idempotency_key:randomUUID(),region_id:'shanghai',layout_patch_id:'sh_a',blueprint_revision:2},201);version=created.version;
 await command('start_journey',{});
 const cell_ids=['28,35'];const initial=await request('/farms/me');
 let {result:r}=await command('buy_seeds',{crop:'R',qty:2});assert.equal(r.state.wallet,initial.state.wallet-2*content.crops.crops.R.seed_price);
 ({result:r}=await command('till_cells',{cell_ids}));assert.equal(r.state.cells['28,35'].state,'tilled');
 ({result:r}=await command('sow_cells',{cell_ids,crop:'R',lot:'bought',field_condition:'sunny'}));assert.equal(r.state.cells['28,35'].state,'sown');assert.equal(r.state.inventory.seeds.R.bought,1);
 ({result:r}=await command('water_cells',{cell_ids}));const ripeAt=r.state.cells['28,35'].ready_at;assert(ripeAt>now);assert.equal(r.state.cells['28,35'].state,'growing');
 await command('harvest_cells',{cell_ids},422);
 now=ripeAt+1;const before=(await request('/farms/me')).state.inventory.produce.R;
 const harvest=await command('harvest_cells',{cell_ids});r=harvest.result;assert.equal(r.state.cells['28,35'].state,'tilled');assert.equal(r.state.inventory.produce.R,before+content.crops.crops.R.yield);
 const replay=await request('/farms/me/commands',harvest.envelope);assert.equal(replay.outcome,'replayed');assert.equal(replay.state.inventory.produce.R,r.state.inventory.produce.R);
 const saved=await request('/farms/me');await app.close();
 app=await buildApp({ guestWrites: true,store:new PgStore({pool,content,contentVersion:cv,plot,timezone:()=> 'Asia/Shanghai',now:()=>now}),content,contentVersion:cv,plot,now:()=>now,pepper:'isolated-free-loop-only',regionsFile:path.join(DEFAULT_CONTENT_DIR,'regions.json'),blueprintDir:path.resolve(DEFAULT_CONTENT_DIR,'../../blueprints')});
 base=(await app.listen({port:0,host:'127.0.0.1'}))+'/v1';token=(await request('/auth/anonymous',{install_key:key})).token;
 const restored=await request('/farms/me');assert.deepEqual(restored.state,saved.state);assert.equal(restored.version,saved.version);
 const proof={passed:true,database,real_http:true,postgres:true,isolated_clock:true,checks:['buy seeds charges correct price','till free cell','sow consumes one seed','water starts server deadline','early harvest rejected','mature harvest creates produce','replay does not duplicate reward','restart and login retain exact state'],version};
 writeFileSync(process.env.FREE_FARM_QA_OUTPUT ?? '../output/free-farm-loop-2026-09-17/http-loop.json',JSON.stringify(proof,null,2));console.log(JSON.stringify(proof));
} finally {await app.close();await pool.end();}
