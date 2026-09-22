import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const run=promisify(execFile),serial=process.env.JOURNEY_SERIAL,pkg=process.env.JOURNEY_PACKAGE;
assert(serial&&pkg==='com.sensen.journeyuiqa','Isolated QA account only');
const out='output/farm-mode-2026-09-22/android';await mkdir(out,{recursive:true});
const adb=a=>run('adb',['-s',serial,...a],{encoding:'buffer',timeout:25000,maxBuffer:24e6});
const delay=ms=>new Promise(r=>setTimeout(r,ms));let last,touches=0;
async function state(){return last=JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/game-ui-proof/state.json'])).stdout)}
async function until(test,label,ms=50000){const end=Date.now()+ms;while(Date.now()<end){try{const s=await state();if(!s.navigation_pending&&test(s))return s}catch{}await delay(170)}throw Error(label+': '+JSON.stringify({scene:last?.scene,error:last?.error,work_mode:last?.work_mode,controls:last?.controls}))}
async function point(pos,label){assert(pos.every(Number.isFinite));await writeFile(`${out}/touch-${++touches}.json`,JSON.stringify({label,point:pos}));await adb(['shell','input','tap',...pos.map(x=>String(Math.round(x)))]);await delay(250)}
async function tap(id){const s=await until(s=>s.controls.some(c=>c.name===id&&!c.disabled),'control '+id);const[x,y,w,h]=s.controls.find(c=>c.name===id&&!c.disabled).bounds;assert(w>4&&h>4);await point([x+w/2,y+h/2],id)}
async function shot(name){const s=await state();await writeFile(out+'/'+name+'.json',JSON.stringify(s,null,2));await writeFile(out+'/'+name+'.png',(await adb(['exec-out','screencap','-p'])).stdout);console.log('FARM_MODE',name);return s}
const seedCount=s=>Object.values(s.inventory.seeds).reduce((sum,e)=>sum+e.bound+e.bought,0);
try{
 await delay(2000);
 for(let i=0;i<3;i++){
  await adb(['shell','uiautomator','dump','/sdcard/farm-mode-start.xml']);
  const xml=(await adb(['exec-out','cat','/sdcard/farm-mode-start.xml'])).stdout.toString();await writeFile(out+'/startup-'+i+'.xml',xml);
  const node=(xml.match(/<node\b[^>]+>/g)??[]).find(x=>/text="(?:Don't Show Again|OK|确定|Continue|继续)"/.test(x)&&/clickable="true"/.test(x));
  if(!node)break;
  const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);assert(b);await point([(+b[1]+ +b[3])/2,(+b[2]+ +b[4])/2],'system startup dialog');await delay(500);
 }
 let s=await until(s=>s.scene.endsWith('/farm/farm.tscn')&&s.joined&&Array.isArray(s.farm_targets),'farm',90000);
 assert.equal(s.work_mode,false);assert.equal(s.controls.find(c=>c.name==='FarmModeToggle').text,'行走');assert.equal(seedCount(s),0);await shot('01-walking');
 const before=structuredClone(s),existing=s.farm_targets.filter(t=>s.cells[t.id]?.state==='tilled').sort((a,b)=>a.distance-b.distance)[0];assert(existing);
 await point(existing.screen,'walk onto tilled ground');await delay(1800);s=await state();assert.equal(s.version,before.version);assert.deepEqual(s.cells,before.cells);
 await tap('FarmModeToggle');await until(s=>s.work_mode,'work mode');s=await shot('02-farming-no-seeds');assert.equal(s.controls.find(c=>c.name==='FarmModeToggle').text,'种地');
 const target=s.farm_targets.find(t=>t.id===existing.id);assert(target);await point(target.screen,'try sowing with no seeds');await delay(250);s=await shot('03-no-seeds-feedback');assert(s.labels.some(x=>/种子用完|种子不足/.test(x)));assert.equal(s.version,before.version);
 await tap('Title');await tap('Stall');await tap('StallPage_seeds');await tap('StallSeed_R');s=await until(s=>seedCount(s)>0,'buy seeds accepted');assert(s.wallet<before.wallet);await shot('04-seeds-purchased');await tap('CloseStall');
 s=await state();if(!s.work_mode)await tap('FarmModeToggle');
 const wild=s.farm_targets.filter(t=>!s.cells[t.id]).sort((a,b)=>a.distance-b.distance)[0];assert(wild,'visible wild cultivable tile');
 await point(wild.screen,'till');s=await until(s=>s.cells[wild.id]?.state==='tilled'&&!s.action_busy,'till confirmed');await shot('05-tilled');
 await point(s.farm_targets.find(t=>t.id===wild.id).screen,'sow');s=await until(s=>s.cells[wild.id]?.state==='sown'&&!s.action_busy,'sow confirmed');await shot('06-sown');
 await point(s.farm_targets.find(t=>t.id===wild.id).screen,'water');s=await until(s=>s.cells[wild.id]?.state==='growing'&&!s.action_busy,'water confirmed');await shot('07-growing');
 const planted=structuredClone(s.cells[wild.id]),version=s.version,position=s.position;
 await tap('FarmModeToggle');s=await until(s=>!s.work_mode,'back to walk');assert.equal(s.controls.find(c=>c.name==='FarmModeToggle').text,'行走');
 const next=s.farm_targets.filter(t=>!s.cells[t.id]&&t.distance>0.7).sort((a,b)=>a.distance-b.distance)[0];assert(next);await point(next.screen,'walk without farming');await delay(2000);s=await shot('08-walking-again');assert.equal(s.version,version);assert(!s.cells[next.id]);assert.deepEqual(s.cells[wild.id],planted);assert(Math.hypot(s.position[0]-position[0],s.position[1]-position[1])>.2);
 const pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim(),log=(await adb(['logcat','-d','--pid',pid,'-s','godot'])).stdout.toString();await writeFile(out+'/godot.log',log);assert(!/SCRIPT ERROR|Parse Error|Compile Error/.test(log));
 const result={passed:true,isolated_account:true,touches,walking_and_farming_labels_visible:true,empty_seeds_explained:true,real_seed_purchase:true,real_till_sow_water:true,walking_does_not_farm:true,public_save_untouched:true};await writeFile(out+'/result.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}catch(error){await shot('failure').catch(()=>{});await writeFile(out+'/failure.txt',String(error.stack??error));throw error}
