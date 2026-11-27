import {execFile} from 'node:child_process';
import {promisify,isDeepStrictEqual} from 'node:util';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {requireEmulator,runSerial} from './run_serial.mjs';

const run=promisify(execFile);
const output='output/movement-emulator-2026-09-15';
await mkdir(output,{recursive:true});
// The session's serial (run_test.sh), else this Run's emulator (C-212), else the local default; emulators only (C-216).
const serial=requireEmulator(runSerial(['JOURNEY_SERIAL'],{host:['CARDIGAN_EMULATOR_SERIAL']})||'emulator-5560');
const adb=args=>run('adb',['-s',serial,...args],{maxBuffer:8*1024*1024,timeout:15000,encoding:'buffer'});
const snapshot=async()=> (await fetch('http://127.0.0.1:3155/v1/qa/journey/scene')).json();
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function waitFor(test){
  const deadline=Date.now()+15000;
  while(Date.now()<deadline){const s=await snapshot();if(test(s))return s;await delay(250);}
  throw new Error('Scene did not reach expected state');
}
function center(s,name){
  const target=[...s.controls,...s.world.controls].find(c=>c.path===name||c.path.endsWith('/'+name));
  assert.ok(target&&!target.disabled,'Missing enabled scene node: '+name);
  return [target.rect[0]+target.rect[2]/2,target.rect[1]+target.rect[3]/2];
}
async function walk(name){
  const before=await snapshot();const point=center(before,name).map(Math.round).map(String);
  await adb(['shell','input','swipe',...point,...point,'100']);
  return waitFor(s=>s.ticks_ms>before.ticks_ms+1500&&!s.world.moving&&!s.world.busy);
}
async function gesture(label,dx,dz,duration=2000){
  const before=await snapshot();
  assert.equal(before.world.floor,1);assert.equal(Object.keys(before.world.combat.enemies).length,0);
  const stick=center(before,'MineMoveStick');const attack=center(before,'MineAttack');
  const points=[...stick,...attack,stick[0]+dx,stick[1]+dz,...attack].map(String);
  const started=adb(['shell','env','CLASSPATH=/data/local/tmp/journey-touch.dex','app_process','/data/local/tmp','JourneyTouch',...points,String(duration)]);
  await delay(duration*0.6);
  await writeFile(`${output}/${label}.png`,(await adb(['exec-out','screencap','-p'])).stdout);
  await started;
  const after=await waitFor(s=>s.ticks_ms>before.ticks_ms+duration+1500&&!s.world.moving);
  const motion=after.motion.filter(m=>m.place==='mine'&&m.ticks_ms>before.ticks_ms);
  const nav=before.world.navigation;
  assert.ok(motion.length>5);
  for(const frame of motion){const [x,z]=frame.position;assert.equal(nav.walkable[Math.floor(-z/nav.cell_m)]?.[Math.floor(x/nav.cell_m)],'1');}
  assert.equal(after.version,before.version);
  assert.ok(isDeepStrictEqual(after.state,before.state));
  assert.ok(isDeepStrictEqual(after.world.camera_pan,before.world.camera_pan));
  const report={label,before:before.world.player,after:after.world.player,points,motion,version:after.version,
    all_positions_walkable:true,save_unchanged:true,camera_unchanged:true};
  await writeFile(`${output}/${label}.json`,JSON.stringify({before,after,report},null,2));
  return report;
}

// Coordinates are scene node IDs from the observed run-2 mine, not screenshot estimates.
const results=[];
await walk('walk:10,7');
const west=await gesture('rock-west-slide',84,-28);
const slideWest=west.motion.filter(m=>m.position[0]>5.4&&m.position[0]<5.5&&m.position[1]<-3.8&&m.position[1]>-4.5);
assert.ok(slideWest.length>3,'No sustained movement along west face');
assert.ok(west.after[2]<-4.4,'Did not clear the rock corner');
results.push({...west,motion:undefined,sliding_samples:slideWest.length});
await walk('walk:9,6');
const east=await gesture('rock-east-slide',-84,-28);
const slideEast=east.motion.filter(m=>m.position[0]>4&&m.position[0]<4.1&&m.position[1]<-3.4);
assert.ok(slideEast.length>3,'No sustained movement along east face');
results.push({...east,motion:undefined,sliding_samples:slideEast.length});
await walk('walk:10,7');
const wall=await gesture('rock-head-on',84,0,1000);
assert.ok(wall.after[0]<5.5&&wall.after[0]>5.4);
assert.ok(Math.abs(wall.after[2]-wall.before[2])<0.02);
const away=await gesture('rock-back-away',-84,0,700);
assert.ok(away.before[0]-away.after[0]>0.5);
results.push({...wall,motion:undefined},{...away,motion:undefined});
await writeFile(`${output}/playtest.json`,JSON.stringify({passed:true,results,physical_device_verified:false,artificial_save_edits:false},null,2));
console.log(JSON.stringify({passed:true,results:results.map(r=>({label:r.label,before:r.before,after:r.after,sliding_samples:r.sliding_samples}))}));
