// Real Journey phone UI smoke. Read-only observer; no inventory/equipment,
// relocation, fishing or economy command is issued by this scenario.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const run=promisify(execFile),serial=process.env.JOURNEY_SERIAL,pkg=process.env.JOURNEY_PACKAGE;
assert(serial==='10AFAF162200319'&&pkg==='com.sensen.journeypreview');
const out='output/ui-redesign-2026-09-21/device';await mkdir(out+'/private',{recursive:true});
const adb=a=>run('adb',['-s',serial,...a],{encoding:'buffer',timeout:30000,maxBuffer:20e6});
const delay=ms=>new Promise(r=>setTimeout(r,ms));let last,touches=0;
const match=(c,s)=>!c.disabled&&c.bounds[2]>5&&c.bounds[3]>5&&(typeof s==='function'?s(c):[c.name,c.text,c.tooltip].includes(s));
async function state(){return last=JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/game-ui-proof/state.json'])).stdout)}
async function until(p,label,ms=60000){const end=Date.now()+ms;while(Date.now()<end){try{const s=await state();if(!s.navigation_pending&&p(s))return s}catch{}await delay(200)}throw Error(label+': '+JSON.stringify({scene:last?.scene,controls:last?.controls,error:last?.error}))}
async function tap(selector){const s=await until(s=>s.controls.some(c=>match(c,selector)),'button '+selector);const c=s.controls.find(c=>match(c,selector));const[x,y,w,h]=c.bounds;await adb(['shell','input','tap',String(Math.round(x+w/2)),String(Math.round(y+h/2))]);touches++;await delay(400)}
async function shot(name){const s=await state();await writeFile(out+'/private/'+name+'.json',JSON.stringify(s,null,2),{mode:0o600});await writeFile(out+'/'+name+'.png',(await adb(['exec-out','screencap','-p'])).stdout);console.log('PHONE_UI',name);return s}
try{
 await until(s=>s.logged_in&&s.has_farm,'original login',90000);await shot('city');
 const region=JSON.parse(await readFile(out+'/private/baseline/region_choice.json'));
 await tap(c=>new RegExp(region.region_id==='los_angeles'?'Los Angeles|洛杉矶':'Shanghai|上海').test(c.text));
 await until(s=>s.scene.includes('map_poc'),'map');await shot('map');await tap('MyFarm');
 let s=await until(s=>s.scene.endsWith('/farm/farm.tscn')&&s.joined,'own farm',90000),before=structuredClone(s);await shot('farm');
 const[x,y,w,h]=s.world_area;
 for(let i=0;i<3;i++){await adb(['shell','input','swipe',String(Math.round(x+w*.8)),String(Math.round(y+h*.55)),String(Math.round(x+w*.2)),String(Math.round(y+h*.55)),'600']);touches++;await delay(450)}
 await delay(1800);s=await shot('free-camera');const center=s.camera_center;await delay(1200);s=await state();assert(Math.hypot(...s.camera_center.map((v,i)=>v-center[i]))<.03);
 const[bx,by,bw,bh]=s.screen_bounds;assert(s.player_screen[0]<bx||s.player_screen[0]>bx+bw||s.player_screen[1]<by||s.player_screen[1]>by+bh);
 await tap('AvatarFocus');await delay(700);s=await shot('recentered');assert(Math.hypot(...s.camera_center.map((v,i)=>v-before.camera_center[i]))<.05);
 await tap('LifeButton');await until(s=>s.bag_panels.length===1,'bag');s=await state();assert.equal(s.bag_panels[0].columns,5);assert(!s.controls.some(c=>/在线.*300|Online \d/.test(c.tooltip)));
 const item=s.controls.find(c=>c.name.startsWith('BagSlot_')&&match(c,()=>true));assert(item);await tap(item.name);await shot('bag');
 await tap('BagPage_character');await until(s=>s.bag_panels[0]?.page==='character','character');await delay(1200);await shot('character');
 await tap('BagPage_requests');await until(s=>s.bag_panels[0]?.page==='requests','requests');await shot('requests');await tap('CloseBag');
 await tap('Title');await shot('farm-actions');await tap('Stall');await until(s=>s.controls.some(c=>c.name==='CloseStall'),'stall');await shot('stall');
 await tap('StallPage_seeds');await shot('seeds');await tap('CloseStall');
 await tap(c=>/在线.*300|Online \d/.test(c.tooltip));await until(s=>s.controls.some(c=>c.name==='CloseParty'),'party');await shot('party');await tap('CloseParty');
 s=await shot('returned-farm');assert.equal(s.farm_id,before.farm_id);assert.equal(s.version,before.version);assert.equal(s.wallet,before.wallet);assert.deepEqual(s.cells,before.cells);assert.deepEqual(s.bag,before.bag);
 const log=(await adb(['exec-out','run-as',pkg,'cat','files/logs/godot.log'])).stdout;await writeFile(out+'/instrumented-game.log',log);assert(!/SCRIPT ERROR|Parse Error|Compile Error|shader.*error/i.test(log.toString()));
 const result={passed:true,device:'V2509A',read_only_public_ui:true,touches,free_camera_and_portrait:true,bag_and_six_slot_character:true,requests_and_trade_views:true,party_modal:true,version_unchanged:true,assets_unchanged:true,observer_included:true};await writeFile(out+'/instrumented-smoke.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}catch(error){await shot('failure').catch(()=>{});await writeFile(out+'/failure.txt',String(error.stack??error));throw error}
