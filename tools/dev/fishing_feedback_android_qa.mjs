import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const run=promisify(execFile),serial=process.env.JOURNEY_SERIAL,pkg=process.env.JOURNEY_PACKAGE;
assert(serial&&pkg,'Use the Android runner');
const physical=pkg==='com.sensen.journeypreview';
const out=process.env.FISHING_QA_RESULTS??'output/fishing-feedback-2026-09-19/android';
await mkdir(out+'/private',{recursive:true});
const adb=args=>run('adb',['-s',serial,...args],{encoding:'buffer',maxBuffer:20*1024*1024,timeout:20000});
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const proof=physical?'physical-fishing-proof':'fishing-proof';
async function state(){for(let i=0;i<6;i++){try{return JSON.parse((await adb(['exec-out','run-as',pkg,'cat',`files/${proof}/state.json`])).stdout);}catch(e){if(i===5)throw e;await delay(30);}}}
async function waitFor(predicate,message,timeout=30000){const until=Date.now()+timeout;let s;while(Date.now()<until){try{s=await state();if(predicate(s))return s;}catch{}await delay(85);}throw Error(message+': '+JSON.stringify(s));}
async function tapWhere(predicate,description){const s=await waitFor(s=>s.controls.some(c=>predicate(c)&&!c.disabled),'Missing '+description);const c=s.controls.find(c=>predicate(c)&&!c.disabled);const[x,y,w,h]=c.bounds;await adb(['shell','input','tap',...[(x+w/2),(y+h/2)].map(n=>String(Math.round(n)))]);}
const tap=name=>tapWhere(c=>c.name===name,name);
async function capture(name){const s=await state();await writeFile(out+'/private/'+name+'.json',JSON.stringify(s,null,2),{mode:0o600});await writeFile(out+'/'+name+'.png',(await adb(['exec-out','screencap','-p'])).stdout);return s;}
const count=s=>[...(s.bag?.slots??[]),...(s.bag?.overflow??[])].filter(v=>v.item_id.startsWith('fish_')).reduce((n,v)=>n+v.quantity,0);
const symbols=new Set();let touches=0,recording=null,positiveShot=false,negativeShot=false;
async function drive(lose){
 await waitFor(s=>s.phase==='hook','No bite',12000);await tap('FishingAction');
 let s=await waitFor(s=>s.phase==='playing','No minigame');
 const[x,y,w,h]=s.controls.find(c=>c.name==='FishingAction').bounds,point=[x+w/2,y+h/2].map(n=>String(Math.round(n)));
 let held=false;const until=Date.now()+45000;
 while(s.phase==='playing'&&Date.now()<until){
  for(const p of s.feedback.particles)symbols.add(p.symbol);
  assert(s.feedback.particles.length<=6,'Bound feedback particles');
  const desired=lose?s.model.fish<s.model.bar+s.model.velocity*.15:s.model.fish>s.model.bar+s.model.velocity*.15;
  if(held!==desired){await adb(['shell','input','motionevent',desired?'DOWN':'UP',...point]);held=desired;touches++;}
  if(lose&&!negativeShot&&s.feedback.particles.some(p=>p.symbol==='−')){await capture('progress-decreasing');negativeShot=true;}
  if(!lose&&!positiveShot&&s.model.progress>.45&&s.feedback.particles.some(p=>p.symbol==='+')){await capture('progress-increasing');positiveShot=true;}
  await delay(45);s=await state();
 }
 if(held){await adb(['shell','input','motionevent','UP',...point]);touches++;}
 return waitFor(s=>s.phase==='result'&&!s.busy,'No settled result');
}
try{
 await delay(2200);
 await adb(['shell','uiautomator','dump','/sdcard/feedback-ui.xml']);
 const xml=(await adb(['exec-out','cat','/sdcard/feedback-ui.xml'])).stdout.toString();await writeFile(out+'/startup.xml',xml);
 const node=(xml.match(/<node\b[^>]+>/g)??[]).find(n=>/text="(?:Don't Show Again|OK|确定|Continue|继续)"/.test(n)&&/clickable="true"/.test(n));
 if(node){const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);await adb(['shell','input','tap',String(Math.round((+b[1]+ +b[3])/2)),String(Math.round((+b[2]+ +b[4])/2))]);}
 await delay(700);
 if(physical){
  let s=await waitFor(s=>s.logged_in&&s.has_farm,'Original account missing');
  if(s.scene.includes('city_select')){await capture('city');const saved=JSON.parse(await readFile(out+'/private/before/region_choice.json','utf8'));const city=saved.region_id==='los_angeles'?/洛杉矶|Los Angeles/:/上海|Shanghai/;await tapWhere(c=>city.test(c.text),'original city');}
  await waitFor(s=>s.scene.includes('map_poc'),'Map missing');await capture('map');await tap('MyFarm');
 }
 let s=await waitFor(s=>s.joined&&s.controls.some(c=>c.name==='GoFishing'),'Farm missing');
 const originalCount=count(s),original=structuredClone(s);await capture('farm-start');
 await tap('GoFishing');await waitFor(s=>s.phase==='ready','No shore');await delay(300);
 s=await capture('ready-top-notice');assert.equal(s.feedback.meter_width,14);
 const [sx,sy,sw,sh]=s.feedback.screen,p=s.presentation;
 assert(p.notice[1]<sy+sh*.3,'Move notice into upper part of scene');
 assert(p.action[1]+p.action[3]<sy+sh*.94,'Raise the action away from the bottom edge');
 await tap('FishingAction');
 s=await waitFor(s=>s.phase==='result'&&!s.busy,'Missed bite not settled',13000);
 assert.equal(s.heading,'鱼逃走了');assert.match(s.message,/错过咬钩/);assert.equal(count(s),originalCount);await delay(250);await capture('missed-bite');
 recording=spawn('adb',['-s',serial,'shell','screenrecord','--time-limit','20','--bit-rate','5000000','/sdcard/fishing-feedback-proof.mp4'],{stdio:'ignore'});
 await tap('FishingAction');s=await drive(true);assert.equal(s.fishing.last.outcome,'escaped');assert.equal(s.heading,'鱼逃走了');assert.match(s.message,/没有钓到鱼/);assert.equal(count(s),originalCount);await delay(250);await capture('fish-escaped');
 for(let attempt=0;attempt<3;attempt++){await tap('FishingAction');s=await drive(false);if(s.fishing.last.outcome==='caught')break;}
 assert.equal(s.fishing.last.outcome,'caught');assert.equal(s.heading,'钓到了！');assert.equal(count(s),originalCount+1);assert.equal(s.unconfirmed,false);await delay(250);await capture('fish-caught');
 assert(symbols.has('+')&&symbols.has('−'),'Both directions have visible glyph feedback');
 await tap('CloseFishing');s=await waitFor(s=>s.phase==='closed','Did not restore normal scene');await delay(250);await capture('restored');
 if(physical){
  assert.deepEqual(s.cells,original.cells);assert.deepEqual(s.inventory,original.inventory);assert.equal(s.wallet,original.wallet);
  for(const name of Object.keys(JSON.parse(await readFile(out+'/before-files.json','utf8'))))assert.deepEqual((await adb(['exec-out','run-as',pkg,'cat','files/'+name])).stdout,await readFile(out+'/private/before/'+name));
 }
 await writeFile(out+'/result.json',JSON.stringify({passed:true,device:serial,version:'0.16.1',realTouchEvents:touches,progress_width:14,symbols:[...symbols],notice_raised:true,action_raised:true,missed_bite_explicit:true,escape_explicit:true,retry_caught:true,original_save_preserved:physical,fish_delta:1},null,2));
 console.log('Fishing feedback touch verification passed on '+serial);
}finally{
 await adb(['shell','input','motionevent','UP','0','0']).catch(()=>{});
 if(recording){if(recording.exitCode===null){await Promise.race([new Promise(r=>recording.once('exit',r)),delay(21000)]);}await adb(['pull','/sdcard/fishing-feedback-proof.mp4',out+'/fishing-feedback.mp4']).catch(()=>{});}
 const pid=(await adb(['shell','pidof','-s',pkg]).catch(()=>({stdout:Buffer.from('')}))).stdout.toString().trim();
 if(pid)await writeFile(out+'/app.log',(await adb(['logcat','-d','--pid',pid,'-v','threadtime','-s','godot','Godot'])).stdout);
}
