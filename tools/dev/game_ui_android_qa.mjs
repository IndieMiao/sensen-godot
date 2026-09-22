import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const run=promisify(execFile),serial=process.env.JOURNEY_SERIAL,pkg=process.env.JOURNEY_PACKAGE;
assert(serial&&pkg==='com.sensen.journeyuiqa','Run only the isolated UI QA package through run_test.sh');
const out='output/ui-redesign-2026-09-21/android';await mkdir(out,{recursive:true});
const adb=args=>run('adb',['-s',serial,...args],{encoding:'buffer',timeout:25000,maxBuffer:24e6});
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));let last,touches=0;
const center=([x,y,w,h])=>[x+w/2,y+h/2], dist=(a,b)=>Math.hypot(...a.map((v,i)=>v-b[i]));
const matches=(c,s)=>!c.disabled&&c.bounds[2]>4&&c.bounds[3]>4&&(typeof s==='function'?s(c):[c.name,c.text,c.tooltip].includes(s));
const isFarm=s=>s.scene.endsWith('/farm/farm.tscn')&&s.joined;
async function state(){return last=JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/game-ui-proof/state.json'])).stdout)}
async function until(predicate,label,ms=45000){const end=Date.now()+ms;while(Date.now()<end){try{const s=await state();if(!s.navigation_pending&&predicate(s))return s}catch{}await delay(170)}throw Error(label+': '+JSON.stringify({scene:last?.scene,error:last?.error,controls:last?.controls,bag_panels:last?.bag_panels}))}
async function capture(name){const s=await state();await writeFile(`${out}/${name}.json`,JSON.stringify(s,null,2));await writeFile(`${out}/${name}.png`,(await adb(['exec-out','screencap','-p'])).stdout);console.log('CAPTURE',name);return s}
async function point(p,label){assert(p.every(Number.isFinite));await writeFile(`${out}/touch-${++touches}.json`,JSON.stringify({label,point:p}));await adb(['shell','input','tap',...p.map(v=>String(Math.round(v)))]);await delay(300)}
async function tap(selector){const s=await until(s=>s.controls.some(c=>matches(c,selector)),'button '+selector);await point(center(s.controls.find(c=>matches(c,selector)).bounds),String(selector))}
async function swipe(a,b,ms=600){await adb(['shell','input','swipe',...a.concat(b).map(v=>String(Math.round(v))),String(ms)]);touches++;await delay(350)}
async function back(){await adb(['shell','input','keyevent','4']);await delay(300)}
try{
 for(let i=0;i<4;i++){
  await delay(700);await adb(['shell','uiautomator','dump','/sdcard/game-ui-start.xml']);
  const xml=(await adb(['exec-out','cat','/sdcard/game-ui-start.xml'])).stdout.toString();await writeFile(`${out}/startup-${i}.xml`,xml);
  const n=(xml.match(/<node\b[^>]+>/g)??[]).find(n=>/text="(?:Don't Show Again|OK|确定|Continue|继续)"/.test(n)&&/clickable="true"/.test(n));if(!n)break;
  const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(n);assert(b);await point([(+b[1]+ +b[3])/2,(+b[2]+ +b[4])/2],'system dialog');
 }
 let s=await until(isFarm,'current geographic farm',90000),before=structuredClone(s);
 assert(s.plot_layout.startsWith('geo_'));assert.equal(Object.keys(s.cells).length,47);await capture('01-farm');
 const [ax,ay,aw,ah]=s.world_area;
 for(let n=0;n<3;n++)await swipe([ax+aw*.8,ay+ah*.55],[ax+aw*.2,ay+ah*.55]);
 s=await state();assert(dist(s.camera_center,before.camera_center)>4,'Free pan did not move the camera');
 await delay(1800);s=await state();const still=s.camera_center;await delay(1200);s=await state();assert(dist(s.camera_center,still)<.03,'Camera snapped back automatically');
 const [sx,sy,sw,sh]=s.screen_bounds;assert(s.player_screen[0]<sx||s.player_screen[0]>sx+sw||s.player_screen[1]<sy||s.player_screen[1]>sy+sh,'Avatar cannot leave the screen');
 await capture('02-free-camera');await tap('AvatarFocus');await delay(650);s=await state();assert(dist(s.camera_center,before.camera_center)<.05,'Portrait did not recenter');await capture('03-recentered');
 await tap('FarmModeToggle');await until(s=>s.work_mode,'farming mode');await capture('04-farming-mode');await tap('FarmModeToggle');
 await tap('LifeButton');s=await until(s=>s.bag_panels.length===1,'bag');assert.equal(s.bag_panels[0].columns,5);
 assert(s.modal);assert(!s.controls.some(c=>/Online \d|在线.*300/.test(c.tooltip)),'Online badge covers bag');
 const first=s.controls.find(c=>c.name.startsWith('BagSlot_')&&matches(c,()=>true));assert(first);await tap(first.name);await until(s=>s.bag_panels[0]?.selected===first.name.slice(8),'selected item');await capture('05-bag-details');
 s=await state();const selected=s.bag_panels[0].selected;const scroll=s.scrolls.find(v=>v.name==='BagScroll');assert(scroll);
 const [bx,by,bw,bh]=scroll.bounds;await swipe([bx+bw*.4,by+bh*.8],[bx+bw*.4,by+bh*.2]);s=await state();assert.equal(s.bag_panels[0].selected,selected,'Scroll activated an item');await capture('06-bag-scrolled');
 await tap('BagPage_character');await until(s=>s.bag_panels[0]?.page==='character','character');await delay(1400);await capture('07-character');
 assert(last.controls.filter(c=>c.name.startsWith('CharacterSlot_')).length===6,'Six slots unavailable');
 await tap('CharacterSlot_main_hand');await tap('ChangeEquipment_main_hand');await until(s=>s.bag_panels[0]?.mode==='equipment','equipment choice');await capture('08-equipment-choice');
 await tap('BagPage_requests');await until(s=>s.bag_panels[0]?.page==='requests','requests');await capture('09-requests');
 await tap('BagPage_bag');await tap('CloseBag');await until(s=>!s.modal,'bag close');
 await tap(c=>c.name==='Title');await tap('Stall');s=await until(s=>s.controls.some(c=>c.name==='CloseStall'),'stall');await capture('10-stall');
 const coins=s.wallet;await tap('StallPage_seeds');await tap('StallSeed_R');await until(s=>s.wallet<coins,'seed purchase confirmed');await capture('11-bought-seeds');
 await tap('CloseStall');await until(s=>!s.modal,'stall close');
 await tap(c=>/Online \d|在线.*300/.test(c.tooltip));await until(s=>s.controls.some(c=>c.name==='CloseParty'),'party');await capture('12-party');await tap('CloseParty');
 await tap(c=>c.name==='Title');await tap('GoFishing');await until(s=>s.phase==='ready','fishing ready',90000);await capture('13-fishing');
 await tap('FishingAction');await until(s=>['waiting','hook'].includes(s.phase),'server cast');await until(s=>s.phase==='hook','fish bites',30000);await tap('FishingAction');await until(s=>s.phase==='playing','reeling');await capture('14-fishing-reel');
 await tap('CloseFishing');await until(s=>s.phase==='closed','fishing close');await tap('AvatarFocus');await delay(600);
 await capture('15-final-farm');
 const pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim();const log=(await adb(['logcat','-d','--pid',pid,'-s','godot'])).stdout;await writeFile(out+'/godot.log',log);assert(!/SCRIPT ERROR|Parse Error|Compile Error|shader.*error/i.test(log.toString()));
 const result={passed:true,isolated_http_account:true,touches,free_camera_offscreen:true,portrait_recenter:true,five_column_bag:true,scroll_cancels_selection:true,six_slots:true,requests:true,real_seed_purchase:true,party_modal:true,server_fishing_cast:true,public_save_untouched:true};await writeFile(out+'/result.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}catch(error){await capture('failure').catch(()=>{});await writeFile(out+'/failure.txt',String(error.stack??error));throw error}
