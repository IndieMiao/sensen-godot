/** Dedicated local accounts and service. No production identities or farm snapshots. */
import { randomUUID } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { buildApp, plotFor } from '../src/http/app.js';
import { MemoryStore } from '../src/http/memory_store.js';
import { installKeyHmac } from '../src/http/auth.js';
import { loadContent, contentVersion, DEFAULT_CONTENT_DIR } from '../src/domain/content.js';
import { initialFarmState } from '../src/domain/farm_factory.js';
import { startJourney } from '../src/domain/journey.js';
import { ensureBag } from '../src/domain/bag.js';
import { ensureCharacter } from '../src/domain/character.js';
import type { FarmRow } from '../src/http/dto.js';

const content=loadContent(DEFAULT_CONTENT_DIR), cv=contentVersion(DEFAULT_CONTENT_DIR), plot=plotFor(content);
const pepper='system-ponds-isolated-20260924';
const store=new MemoryStore({content,contentVersion:cv,plot,timezone:'America/Los_Angeles',now:Date.now});
const key=randomUUID().replaceAll('-',''), auth=await store.authAnonymous(installKeyHmac(key,pepper));
const state=startJourney(initialFarmState(content,plot,'America/Los_Angeles',Date.now()),content);
ensureBag(state,content);ensureCharacter(state,content);
const farm:FarmRow={id:randomUUID(),owner_id:auth.player.id,version:0,region_id:'los_angeles',layout_patch_id:'la_a',blueprint_revision:2,visit_access:'only_me',location_visible:true,state};
await store.createFarm({ownerId:auth.player.id,idempotencyKey:'pond-qa-create',payloadHash:'pond-qa-create',regionId:farm.region_id,layoutPatchId:farm.layout_patch_id,blueprintRevision:2,build:()=>farm});
const dir=path.resolve(DEFAULT_CONTENT_DIR,'../../../output/system-ponds-2026-09-24/private');
mkdirSync(dir,{recursive:true,mode:0o700});
writeFileSync(path.join(dir,'qa-account.json'),JSON.stringify({key,farm_id:farm.id,player_id:auth.player.id}),{mode:0o600});
const app=await buildApp({store,content,contentVersion:cv,plot,now:Date.now,pepper,blueprintDir:path.resolve(DEFAULT_CONTENT_DIR,'../../blueprints'),regionsFile:path.join(DEFAULT_CONTENT_DIR,'regions.json')});
await app.listen({port:3201,host:'127.0.0.1'});
console.log(JSON.stringify({ready:true,port:3201,isolated:true,content:cv}));
for(const signal of ['SIGINT','SIGTERM'] as const)process.on(signal,()=>{void app.close().then(()=>process.exit(0));});
