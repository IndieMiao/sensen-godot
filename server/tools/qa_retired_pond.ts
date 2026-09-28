/** Isolated loopback QA server; never loads environment credentials or production saves. */
import { randomUUID } from 'node:crypto';
import { readFileSync, mkdirSync, writeFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { buildApp } from '../src/http/app.js';
import { MemoryStore } from '../src/http/memory_store.js';
import { loadContent, contentVersion, DEFAULT_CONTENT_DIR } from '../src/domain/content.js';
import { initialFarmState } from '../src/domain/farm_factory.js';
import { startJourney } from '../src/domain/journey.js';
import { ensureBag } from '../src/domain/bag.js';
import { loadPlot } from '../src/domain/plot.js';
import { retireFarmPond, plotForFarm } from '../src/geography/farm_terrain.js';
import type { FarmRow } from '../src/http/dto.js';

const output = process.env.FARM_POND_QA_OUTPUT;
if (!output || !path.isAbsolute(output)) throw new Error('Set an absolute FARM_POND_QA_OUTPUT');
const content = loadContent(DEFAULT_CONTENT_DIR), cv = contentVersion(DEFAULT_CONTENT_DIR), plot = loadPlot(content.farm_plot);
const root = path.resolve(DEFAULT_CONTENT_DIR,'../../..');
const terrain = retireFarmPond(JSON.parse(readFileSync(path.join(root,'tests/fixtures/generated_compact_farm_terrain.json'),'utf8')));
const store = new MemoryStore({content,contentVersion:cv,plot,timezone:'Asia/Shanghai',now:Date.now});
const app = await buildApp({ guestWrites: true,store,content,contentVersion:cv,blueprintDir:path.join(root,'assets/blueprints'),
  regionsFile:path.join(DEFAULT_CONTENT_DIR,'regions.json'),pepper:randomUUID(),now:Date.now});
const accountFile = path.join(output,'account.json');
const key: string = existsSync(accountFile) ? JSON.parse(readFileSync(accountFile,'utf8')).key : randomUUID().replaceAll('-','');
if (!/^[a-f0-9]{32}$/.test(key)) throw new Error('Invalid local QA install key');
// Use the real authentication route, including its keyed identity hash.
const auth = await app.inject({method:'POST',url:'/v1/auth/anonymous',payload:{install_key:key}});
if (auth.statusCode !== 200) throw new Error('Local QA authentication failed');
const owner: string = auth.json().player_id;
const state = startJourney(initialFarmState(content,plotForFarm({farm_terrain:terrain},plot),'Asia/Shanghai',Date.now()),content);
ensureBag(state,content);
const farm: FarmRow = {id:randomUUID(),owner_id:owner,region_id:'shanghai',layout_patch_id:terrain.layout_id,
  blueprint_revision:terrain.plot.revision,version:0,state,farm_terrain:terrain,location:terrain.source.center,
  visit_access:'only_me',location_visible:false};
await store.createFarm({ownerId:owner,idempotencyKey:'qa-create',payloadHash:'qa-only',regionId:farm.region_id,
  layoutPatchId:farm.layout_patch_id,blueprintRevision:farm.blueprint_revision,build:()=>farm});
mkdirSync(output,{recursive:true});
writeFileSync(path.join(output,'account.json'),JSON.stringify({key}),{mode:0o600});
const address = await app.listen({host:'127.0.0.1',port:Number(process.env.FARM_POND_QA_PORT ?? 3214)});
console.log('RETIRED_POND_QA_READY',address);
for (const signal of ['SIGINT','SIGTERM'] as const) process.on(signal,()=>void app.close().then(()=>process.exit(0)));
