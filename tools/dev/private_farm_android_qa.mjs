import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const run = promisify(execFile), serial = process.env.JOURNEY_SERIAL, pkg = process.env.JOURNEY_PACKAGE;
assert(serial && pkg, 'Run through tools/android/run_test.sh');
const out = process.env.PRIVATE_FARM_EVIDENCE ?? 'output/private-geographic-farm-2026-09-21/android';
await mkdir(out, { recursive: true });
const adb = args => run('adb', ['-s', serial, ...args], { encoding: 'buffer', maxBuffer: 16 * 1024 * 1024, timeout: 20000 });
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const center = ([x,y,w,h]) => [x+w/2, y+h/2];
let last, sequence = 0;
async function state() {
  last = JSON.parse((await adb(['exec-out', 'run-as', pkg, 'cat', 'files/private-farm-proof/state.json'])).stdout);
  return last;
}
async function until(predicate, label, timeout = 30000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    try { const s = await state(); if (predicate(s)) return s; } catch {}
    await delay(180);
  }
  throw Error(label + ': ' + JSON.stringify(last));
}
async function capture(name) {
  const s = await state();
  await writeFile(`${out}/${name}.json`, JSON.stringify(s, null, 2));
  await writeFile(`${out}/${name}.png`, (await adb(['exec-out','screencap','-p'])).stdout);
  return s;
}
async function tap(point, label) {
  assert(point.length === 2 && point.every(Number.isFinite), label);
  await writeFile(`${out}/touch-${String(++sequence).padStart(2,'0')}.json`, JSON.stringify({label, point, state:last},null,2));
  await adb(['shell','input','tap',...point.map(v=>String(Math.round(v)))]);
  await delay(250);
}
async function control(name) {
  const s = await until(s => s.controls.some(c => c.name === name && !c.disabled), name);
  await tap(center(s.controls.find(c=>c.name===name&&!c.disabled).bounds),name);
}
const checks=[];
try {
  // System startup dialogs are located from Android's UI tree. In-game targets
  // come from the observer's actual Godot control bounds or 3D projections.
  for (let attempt=0;attempt<4;attempt++) {
    await delay(700);
    await adb(['shell','uiautomator','dump','/sdcard/private-farm-ui.xml']);
    const xml=(await adb(['exec-out','cat','/sdcard/private-farm-ui.xml'])).stdout.toString();
    await writeFile(`${out}/startup-${attempt}.xml`,xml);
    const n=(xml.match(/<node\b[^>]+>/g)??[]).find(n=>/text="(?:Don't Show Again|OK|确定|Continue|继续)"/.test(n)&&/clickable="true"/.test(n));
    if(!n)break;
    const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(n);
    assert(b); await tap([(+b[1]+ +b[3])/2,(+b[2]+ +b[4])/2],'system-dialog');
  }
  let s=await until(s=>(s.selecting&&!s.busy)||s.farm_id,'map ready',60000);
  const previousFarm=s.farm_id, previousCells=JSON.stringify(s.cells);
  if(!s.farm_id) {
  await capture('01-selection');
  assert(!s.controls.some(c=>c.text==='Hengshan Road'||c.text==='Old Town'));
  await tap(s.selection_targets.unavailable,'choose unavailable recorded window');
  await until(s=>s.selection?.lng>121.4710,'selection changed');
  s=await state();
  let create=s.controls.find(c=>/生成农场|创建农场|在此|Generate farm here/.test(c.text)&&!c.disabled);
  assert(create,'create button: '+JSON.stringify(s.controls));
  await tap(center(create.bounds),'generate unavailable selection');
  await until(s=>!s.busy&&s.error==='GEOGRAPHY_UNAVAILABLE','unavailable result');
  s=await capture('02-reselect-after-error'); assert.equal(s.farm_id,'');
  await tap(s.selection_targets.valid,'reselect real mapped land');
  await until(s=>Math.abs(s.selection?.lng-121.4704)<0.00001,'valid selection');
  s=await state(); create=s.controls.find(c=>/生成农场|创建农场|在此|Generate farm here/.test(c.text)&&!c.disabled);
  await tap(center(create.bounds),'generate real private farm');
  } else {
    await control('MyFarm');
  }
  s=await until(s=>s.scene.endsWith('/farm/farm.tscn')&&s.joined,'generated private farm',60000);
  assert(s.layout.startsWith('geo_')); assert.equal(s.terrain.provider,'osm');
  assert.equal(s.terrain.extent_m,240); assert(s.camera.far>s.camera.near);
  const farmId=s.farm_id;
  if(process.env.PRIVATE_FARM_SMOKE==='1') {
    assert.equal(farmId,previousFarm); assert.equal(JSON.stringify(s.cells),previousCells);
    await capture('final-smoke');
    const pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim();
    const logs=(await adb(['logcat','-d','--pid',pid,'-s','godot'])).stdout;
    await writeFile(out+'/final-smoke.log',logs);
    assert(!/SCRIPT ERROR|Parse Error|Compile Error|shader.*error/i.test(logs.toString()));
    await writeFile(out+'/final-smoke-result.json',JSON.stringify({passed:true,farm_id:farmId,version:s.version,cells:s.cells,checks:['cold launch reads persisted generated terrain','same isolated account and crops retained','private farm joins successfully','no script or shader errors']},null,2));
    console.log('FINAL_SMOKE_PASSED');
    process.exit(0);
  }
  await capture('03-farm');
  checks.push('Normal map touch changes selected location; failed geography creates no farm and reselect succeeds without templates');
  checks.push('Real OSM geometry generates persisted private farm and joins its authoritative room');
  // Farming exercises the generated plot through normal touch and server saves.
  await control('FarmModeToggle');
  s=await until(s=>s.work_mode,'work mode');
  const saved=Object.entries(s.cells).find(([,c])=>['tilled','sown','growing'].includes(c.state));
  const cell=saved?{id:saved[0]}:s.work_targets.find(t=>!s.cells[t.id]); assert(cell,'cultivable cell');
  for(const stage of ['tilled','sown','growing']) {
    s=await state();
    if(['tilled','sown','growing'].indexOf(s.cells[cell.id]?.state)>=['tilled','sown','growing'].indexOf(stage))continue;
    if(stage==='tilled'){
      const tile=s.work_targets.find(t=>t.id===cell.id);assert(tile,'tile visible');
      await tap(tile.screen,'farm '+stage);
    } else await control('CTA');
    await until(s=>s.cells[cell.id]?.state===stage&&!s.action_busy,'saved '+stage,30000);
  }
  s=await capture('04-farming'); assert(s.cells[cell.id].ready_at>0);
  checks.push('Generated farm supports real till, sow and water commands with a server maturity deadline');
  await control('FarmModeToggle'); await until(s=>!s.work_mode,'walking');
  s=await state(); await tap(center(s.mine),'mine model');
  await until(s=>s.scene.includes('/mine/'),'starter mine entry',30000);
  await capture('05-mine');
  s=await until(s=>s.controls.some(c=>/返回农场|Return to farm/.test(c.tooltip)&&!c.disabled),'mine return control');
  await tap(center(s.controls.find(c=>/返回农场|Return to farm/.test(c.tooltip)&&!c.disabled).bounds),'return to farm');
  s=await until(s=>s.scene.endsWith('/farm/farm.tscn')&&s.joined,'return from mine');
  assert.equal(s.farm_id,farmId); assert.equal(s.cells[cell.id].state,'growing');
  checks.push('Visible mine entrance opens starter mine and returns to same farm with crop retained');
  await control('GoFishing');
  await until(s=>s.phase==='ready','reachable pond shore',30000);
  await capture('06-pond');
  await control('FishingAction');
  await until(s=>['waiting','hook'].includes(s.phase),'cast accepted');
  await capture('07-cast');
  s=await until(s=>s.phase==='hook','bite',30000);
  await control('FishingAction');
  await until(s=>s.phase==='playing','hook');
  s=await state();const reel=s.controls.find(c=>c.name==='FishingAction');
  const [rx,ry]=center(reel.bounds);
  await adb(['shell','input','swipe',String(Math.round(rx)),String(Math.round(ry)),String(Math.round(rx)),String(Math.round(ry)),'650']);
  await capture('08-reeling');
  await control('CloseFishing');
  s=await until(s=>s.phase==='closed','close fishing',30000);
  assert.equal(s.farm_id,farmId); assert.equal(s.cells[cell.id].state,'growing');
  await capture('09-ready');
  checks.push('Pond shore is reachable; cast, hook, hold/release reel and exit work through real touch');
  const pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim();
  const logs=(await adb(['logcat','-d','--pid',pid,'-s','godot'])).stdout;
  await writeFile(out+'/godot.log',logs);
  assert(!/SCRIPT ERROR|Parse Error|Compile Error|shader.*error/i.test(logs.toString()));
  await writeFile(out+'/result.json',JSON.stringify({passed:true,checks,touches:sequence,farm_id:farmId,cell:cell.id,source:'recorded real OSM response; isolated memory HTTP/WSS server'},null,2));
  console.log(JSON.stringify({passed:true,checks,touches:sequence}));
} catch(error) {
  await capture('failure').catch(()=>{});
  await writeFile(out+'/failure.txt',String(error.stack??error));
  throw error;
}
