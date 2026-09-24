import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const run=promisify(execFile), serial=process.env.JOURNEY_SERIAL, pkg=process.env.JOURNEY_PACKAGE;
assert(serial && pkg, 'Use tools/android/run_test.sh');
const out=process.env.POND_QA_RESULTS ?? 'output/system-ponds-2026-09-24/android';
await mkdir(out,{recursive:true});
const adb=args=>run('adb',['-s',serial,...args],{encoding:'buffer',maxBuffer:16*1024*1024,timeout:25000});
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let operations=0;
async function state(){
  for(let attempt=0;attempt<8;attempt++){
    try{return JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/pond-proof/state.json'])).stdout);}
    catch(error){if(attempt===7)throw error;await delay(20);}
  }
}
async function until(predicate,label,timeout=25000){
  const end=Date.now()+timeout;let last;
  while(Date.now()<end){try{last=await state();if(predicate(last))return last;}catch{}await delay(120);}
  throw new Error(label+': '+JSON.stringify(last));
}
async function point(x,y){await adb(['shell','input','tap',String(Math.round(x)),String(Math.round(y))]);operations++;await delay(200);}
async function tap(name){
  const s=await until(s=>s.controls.some(c=>c.name===name&&!c.disabled&&c.bounds[2]>5&&c.bounds[3]>5),'control '+name);
  const [x,y,w,h]=s.controls.find(c=>c.name===name&&!c.disabled&&c.bounds[2]>5&&c.bounds[3]>5).bounds;
  await point(x+w/2,y+h/2);
}
async function back(){await adb(['shell','input','keyevent','4']);operations++;await delay(250);}
async function shot(name){const s=await state();await writeFile(out+'/'+name+'.json',JSON.stringify(s,null,2));await writeFile(out+'/'+name+'.png',(await adb(['exec-out','screencap','-p'])).stdout);return s;}
async function select(entry){
  await tap('MapFilter_pond');await tap('MapLandmarkList');await tap('MapPlace_'+entry.id);
  return until(s=>s.map?.selected.id===entry.id,'pond selected');
}
async function enter(entry){
  await select(entry);
  const before=await shot(entry.template_id+'-entry');
  const button=before.controls.find(c=>c.text==='进入鱼塘'&&!c.disabled);assert(button);
  await tap(button.name);
  const inside=await until(s=>s.pond?.id===entry.id&&s.pond.joined&&s.pond.geometry_ready,'pond joined',40000);
  assert.equal(inside.pond.template,entry.template_id);
  return before.map.pose;
}
async function returnToMap(pose){
  await tap('PondBack');const s=await until(s=>Boolean(s.map),'return to map');
  for(let i=0;i<pose.length;i++)assert(Math.abs(s.map.pose[i]-pose[i])<.00001,'map pose restored');
  return s;
}
async function catchFish(){
  await tap('PondFish');await until(s=>s.phase==='ready','reachable fishing shore');
  await shot('fishing-ready');await tap('FishingAction');await until(s=>s.phase==='hook','bite',12000);await tap('FishingAction');
  let s=await until(s=>s.phase==='playing','hook');await shot('fishing-playing');
  const [x,y,w,h]=s.controls.find(c=>c.name==='FishingAction').bounds;
  const p=[String(Math.round(x+w/2)),String(Math.round(y+h/2))];let held=false;
  const end=Date.now()+38000;
  try{
    while(s.phase==='playing'&&Date.now()<end){
      const desired=s.model.fish>s.model.bar+s.model.velocity*.15;
      if(desired!==held){await adb(['shell','input','motionevent',desired?'DOWN':'UP',...p]);held=desired;operations++;}
      await delay(35);s=await state();
    }
  }finally{if(held){await adb(['shell','input','motionevent','UP',...p]);operations++;}}
  s=await until(s=>s.phase==='result'&&!s.busy,'fish result',18000);
  await shot('fishing-result');return s.fishing.last.outcome;
}

let originalSize,changed=false;
const results=[];
try{
  await delay(2500);
  const xml=(await adb(['exec-out','uiautomator','dump','/dev/tty'])).stdout.toString();await writeFile(out+'/startup.xml',xml);
  const node=(xml.match(/<node\b[^>]+>/g)??[]).find(n=>/text="(?:Don't Show Again|确定|Continue|继续)"/.test(n)&&/clickable="true"/.test(n));
  if(node){const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);await point((+b[1]+ +b[3])/2,(+b[2]+ +b[4])/2);}
  const before=await until(s=>s.map?.ponds.length===6,'six fixed city ponds',60000);
  await shot('map-initial');
  const sizeText=(await adb(['shell','wm','size'])).stdout.toString();
  originalSize=/Override size: (\d+x\d+)/.exec(sizeText)?.[1]??'reset';
  const first=before.map.ponds;
  const shapes=['crescent','gourd','meander'];
  for(const shape of shapes){
    const entry=first.find(p=>p.template_id===shape);assert(entry);
    const pose=await enter(entry);await shot(shape+'-default');
    const s=await state(), target=s.pond.targets.find(t=>t.walkable&&t.screen[0]>40&&t.screen[1]>140);
    assert(target);await point(...target.screen);await until(s=>!s.pond.moving,'walk complete');
    await tap('PondOverview');await shot(shape+'-overview');
    await tap('PondOverview');
    if(shape==='crescent'){
      let outcome;for(let attempt=0;attempt<3;attempt++){outcome=await catchFish();await back();await until(s=>s.phase==='closed','fishing closed');if(outcome==='caught')break;}
      assert.equal(outcome,'caught','a real touch-controlled catch');
      await tap('PondBag');await shot('pond-bag');await back();
    }
    await returnToMap(pose);results.push({shape,entered:true,walked:true,returned:true});
  }
  const entry=first[0];
  for(const physical of ['720x1280','960x1280']){
    changed=true;await adb(['shell','wm','size',physical]);await delay(1200);
    const pose=await enter(entry);await shot('size-'+physical);
    const s=await state(), width=+physical.split('x')[0], height=+physical.split('x')[1];
    for(const name of ['PondBack','PondFish','PondOverview','PondBag']){
      const c=s.controls.find(c=>c.name===name);assert(c);const[x,y,w,h]=c.bounds;assert(x>=0&&y>=0&&x+w<=width+1&&y+h<=height+1,name+' onscreen');
    }
    await adb(['shell','input','swipe',String(Math.round(width*.7)),String(Math.round(height*.4)),String(Math.round(width*.3)),String(Math.round(height*.6)),'350']);operations++;
    await delay(800);await shot('size-'+physical+'-pan');
    await returnToMap(pose);results.push({physical,controls:true,pan:true});
  }
  await adb(['shell','wm','size',originalSize]);changed=false;await delay(800);
  const after=await shot('map-returned');assert.equal(after.farm_id,before.farm_id);assert.equal(after.wallet,before.wallet);assert.deepEqual(after.cells,before.cells);assert.deepEqual(after.map.ponds,first);
  const count=s=>[...s.bag.slots,...s.bag.overflow].filter(p=>p.item_id.startsWith('fish_')).reduce((n,p)=>n+p.quantity,0);
  assert(count(after)>count(before));
  const pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim();
  const log=(await adb(['logcat','-d','--pid',pid,'-s','godot','GodotMapPlugin'])).stdout.toString();await writeFile(out+'/runtime.log',log);
  assert(!/SCRIPT ERROR|Parse Error|Compile Error/.test(log));
  const report={passed:true,operations,results,fish_gain:count(after)-count(before),farm_preserved:true,locations_fixed:true};
  await writeFile(out+'/validation.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}catch(error){await shot('failure').catch(()=>{});await writeFile(out+'/failure.txt',String(error.stack??error));throw error;}
finally{if(changed)await adb(['shell','wm','size',originalSize]);}
