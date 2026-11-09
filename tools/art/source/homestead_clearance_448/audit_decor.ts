import {readFileSync,writeFileSync} from 'node:fs';
import {loadP0Content} from './project/server/src/p0/content.ts';
import {freshState,upgradeState} from './project/server/src/p0/state.ts';
import {yardBlock} from './project/server/src/p0/decor.ts';
const c=loadP0Content();const now=Date.now();const audit=JSON.parse(readFileSync(new URL('./clearance-validation.json',import.meta.url),'utf8'));const result={base:'b46c6ea7',yard:c.decor.yard,levels:{}};
for(const level of [8,15]){
 let s=freshState(c,'zhaoyun448-decor-audit',now,448,{guide:false});s.homestead.level=level;s=upgradeState(c,s,now);
 const out={};
 for(const [name,record] of Object.entries(audit.cells))out[name]=record.all_geometry.map(([x,y])=>({cell:[x,y],wall:record.wall_geometry.some(([a,b])=>a===x&&b===y),current_server_block:yardBlock(c,s,[[x,y]],{x,y})?.code??null}));
 result.levels[level]=out;
}
writeFileSync(new URL('./decor-occupancy.json',import.meta.url),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
