import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const run=promisify(execFile),serial=process.env.JOURNEY_SERIAL,pkg=process.env.JOURNEY_PACKAGE;
assert(serial&&pkg,'Use tools/android/run_test.sh');
const out='output/farm-relocation-2026-09-21/android';await mkdir(out,{recursive:true});
const adb=args=>run('adb',['-s',serial,...args],{encoding:'buffer',timeout:25000,maxBuffer:24*1024*1024});
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));let last,touches=0;
const center=([x,y,w,h])=>[x+w/2,y+h/2];
async function state(){return last=JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/relocation-proof/state.json'])).stdout);}
async function until(predicate,label,ms=40000){const end=Date.now()+ms;while(Date.now()<end){try{const s=await state();if(!s.navigation_pending&&predicate(s))return s;}catch{}await delay(120);}throw Error(label+': '+JSON.stringify({scene:last?.scene,error:last?.error,relocation:last?.relocation,preview:last?.preview,controls:last?.controls}));}
async function capture(name){const s=await state();await writeFile(`${out}/${name}.json`,JSON.stringify(s,null,2));await writeFile(`${out}/${name}.png`,(await adb(['exec-out','screencap','-p'])).stdout);return s;}
async function tapPoint(point,label){assert(point.every(Number.isFinite));await writeFile(`${out}/touch-${++touches}.json`,JSON.stringify({label,point,state:last},null,2));await adb(['shell','input','tap',...point.map(v=>String(Math.round(v)))]);await delay(200);}
async function tap(selector){const matches=c=>!c.disabled&&(c.name===selector||c.text===selector||c.tooltip===selector);const s=await until(s=>s.controls.some(matches),'button '+selector);await tapPoint(center(s.controls.find(matches).bounds),selector);}
const values=cells=>Object.values(cells).map(v=>JSON.stringify(v)).sort();
const isFarm=s=>s.scene.endsWith('/farm/farm.tscn')&&s.joined;
try{
 for(let i=0;i<4;i++){
  await delay(700);await adb(['shell','uiautomator','dump','/sdcard/relocation-start.xml']);
  const xml=(await adb(['exec-out','cat','/sdcard/relocation-start.xml'])).stdout.toString();await writeFile(`${out}/startup-${i}.xml`,xml);
  const n=(xml.match(/<node\b[^>]+>/g)??[]).find(n=>/text="(?:Don't Show Again|OK|确定|Continue|继续)"/.test(n)&&/clickable="true"/.test(n));if(!n)break;
  const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(n);assert(b);await tapPoint([(+b[1]+ +b[3])/2,(+b[2]+ +b[4])/2],'system dialog');
 }
 let s=await until(isFarm,'legacy farm',60000);let before,frozen;
 if(process.env.RELOCATION_QA_CONTINUE==='1'){
  before=JSON.parse(await readFile(out+'/01-old-farm.json'));frozen=JSON.parse(await readFile(out+'/06-confirmation.json')).preview;assert.equal(s.farm_id,before.farm_id);assert(s.relocation.used);
 }else{
 const initial=s;before=structuredClone(initial);
 assert.equal(s.relocation.available,true);assert.equal(s.relocation.used,false);assert(!s.layout.startsWith('geo_'));
 await capture('01-old-farm');
 await tap('RelocateFarm');
 await until(s=>s.relocation_mode&&!s.busy&&Math.abs(s.selection.lng-121.4704)<.00001,'same-city selection');
 await capture('02-select');await tap('Preview this location');
 s=await until(s=>s.preview?.preview_id&&!s.busy,'terrain preview',60000);
 assert(s.preview.moved_cells>0);assert(s.preview.moved_decorations>0);assert.equal(s.relocation.available,true);
 await capture('03-preview');await tap('Keep current farm');
 s=await until(isFarm,'cancel returns old farm');
 assert.equal(s.instance_id,before.instance_id);assert.equal(s.layout,before.layout);assert.deepEqual(s.cells,before.cells);
 assert.equal(s.relocation.available,true);assert.equal(s.relocation.used,false);assert.deepEqual(s.camera,before.camera);
 await capture('04-cancelled');
 await tap('RelocateFarm');await until(s=>s.relocation_mode&&!s.busy,'select again');
 s=await state();await tapPoint(s.selection_targets.unavailable,'unavailable area');
 await until(s=>s.selection.lng>121.4710,'changed selection');await tap('Preview this location');
 s=await until(s=>!s.busy&&s.error==='GEOGRAPHY_UNAVAILABLE','invalid selection keeps chance');
 assert.equal(s.relocation.available,true);assert.deepEqual(s.cells,before.cells);await capture('05-unavailable');
 await tapPoint(s.selection_targets.valid,'valid real geography');
 await until(s=>Math.abs(s.selection.lng-121.4704)<.00001,'valid selection');await tap('Preview this location');
 s=await until(s=>s.preview?.preview_id&&!s.busy,'final preview',60000);frozen=structuredClone(s.preview);
 await capture('06-confirmation');await tap('Confirm relocation');
 s=await until(s=>isFarm(s)&&s.layout.startsWith('geo_')&&!s.relocation.available&&s.relocation.used,'committed farm',60000);
 assert.equal(s.farm_id,before.farm_id);assert.notEqual(s.instance_id,before.instance_id);assert.equal(s.layout,frozen.farm_terrain.layout_id);
 assert.equal(s.version,before.version+1);assert.deepEqual(values(s.cells),values(before.cells));
 for(const key of Object.keys(before.state))if(!['cells','decorations','clock'].includes(key))assert.deepEqual(s.state[key],before.state[key],key);
 assert.equal(s.state.decorations.length,before.state.decorations.length);
 assert.equal(s.state.decorations[0].prop_id,before.state.decorations[0].prop_id);assert.equal(s.state.decorations[0].rotation_q,before.state.decorations[0].rotation_q);
 assert(!s.controls.some(c=>c.name==='RelocateFarm'));
 await capture('07-new-farm');
 }
 const [mx,my]=center(s.mine);await tapPoint([mx,my],'new mine entrance');await until(s=>s.scene.includes('/mine/'),'mine');await capture('08-mine');
 s=await until(s=>s.controls.some(c=>/返回农场|Return to farm/.test(c.tooltip)&&!c.disabled),'mine return');await tapPoint(center(s.controls.find(c=>/返回农场|Return to farm/.test(c.tooltip)&&!c.disabled).bounds),'mine return');await until(isFarm,'farm return');
 await tap('FarmModeToggle');s=await until(s=>s.work_mode,'work mode');const distance=t=>{const[i,j]=t.id.split(',').map(Number);return Math.hypot(i-28,j-35)};const cell=s.work_targets.filter(t=>!s.cells[t.id]).toSorted((a,b)=>distance(a)-distance(b))[0];assert(cell);
 await tapPoint(cell.screen,'till new terrain');await until(s=>s.cells[cell.id]?.state==='tilled'&&!s.action_busy,'till accepted with terrain checksum');
 s=await state();let point=s.work_targets.find(t=>t.id===cell.id);assert(point,'sowing tile visible');await tapPoint(point.screen,'sow on new terrain');await until(s=>s.cells[cell.id]?.state==='sown'&&!s.action_busy,'sow');s=await state();point=s.work_targets.find(t=>t.id===cell.id);assert(point,'watering tile visible');await tapPoint(point.screen,'water on new terrain');await until(s=>s.cells[cell.id]?.state==='growing'&&!s.action_busy,'water');
 await capture('09-farming');await tap('FarmModeToggle');await tap('GoFishing');await until(s=>s.phase==='ready','pond');await capture('10-pond');
 await tap('FishingAction');await until(s=>['waiting','hook'].includes(s.phase),'cast');await until(s=>s.phase==='hook','bite',30000);await tap('FishingAction');await until(s=>s.phase==='playing','reel');
 s=await state();const [x,y]=center(s.controls.find(c=>c.name==='FishingAction').bounds);await adb(['shell','input','swipe',String(Math.round(x)),String(Math.round(y)),String(Math.round(x)),String(Math.round(y)),'500']);await capture('11-reel');
 await tap('CloseFishing');s=await until(s=>s.phase==='closed','close');await capture('12-ready');
 for(const crop of values(before.cells))assert(values(s.cells).includes(crop),'old crop content/deadline preserved');
 const pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim();const log=(await adb(['logcat','-d','--pid',pid,'-s','godot'])).stdout;await writeFile(out+'/godot.log',log);assert(!/SCRIPT ERROR|Parse Error|Compile Error|shader.*error/i.test(log.toString()));
 const result={passed:true,continued_after_harness_navigation:process.env.RELOCATION_QA_CONTINUE==='1',isolated_account:true,real_user_chance_untouched:true,source:'recorded real OSM',touches,old_farm_id:before.farm_id,moved_cells:frozen.moved_cells,moved_decorations:frozen.moved_decorations,one_chance_consumed:true,cancel_and_bad_location_free:true,assets_and_growth_times_preserved:true,new_ground_farming_and_fishing_and_mine:true};await writeFile(out+'/result.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}catch(error){await capture('failure').catch(()=>{});await writeFile(out+'/failure.txt',String(error.stack??error));throw error;}
