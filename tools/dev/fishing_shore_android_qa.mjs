import { fishingPeer } from '../../server/tools/fishing_qa_peer.ts';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const run = promisify(execFile), serial = process.env.JOURNEY_SERIAL, pkg = process.env.JOURNEY_PACKAGE;
assert(serial && pkg, 'Use tools/android/run_test.sh');
const out = process.env.FISHING_QA_RESULTS ?? 'output/fishing-2026-09-18/android';
await mkdir(out, { recursive: true });
const adb = args => run('adb', ['-s', serial, ...args], { encoding: 'buffer', maxBuffer: 16 * 1024 * 1024, timeout: 20000 });
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function state() {
  for (let attempt = 0; attempt < 8; attempt++) {
    try { return JSON.parse((await adb(['exec-out', 'run-as', pkg, 'cat', 'files/fishing-proof/state.json'])).stdout); }
    catch (error) { if (attempt === 7) throw error; await delay(25); }
  }
}
async function waitFor(predicate, message, timeout = 30000) {
  const until = Date.now() + timeout;
  let latest;
  while (Date.now() < until) {
    try { latest = await state(); if (predicate(latest)) return latest; } catch {}
    await delay(100);
  }
  throw new Error(message + ': ' + JSON.stringify(latest));
}
async function command(value) {
  assert(/^[a-z_:]+$/.test(value));
  await adb(['shell', 'run-as', pkg, 'sh', '-c', `'echo ${value} > files/fishing-proof/command'`]);
}
async function tap(name) {
  const s = await waitFor(s => s.controls.some(c => c.name === name && !c.disabled), 'Missing control ' + name);
  const node = s.controls.find(c => c.name === name && !c.disabled);
  const [x, y, w, h] = node.bounds;
  await adb(['shell', 'input', 'tap', String(Math.round(x + w / 2)), String(Math.round(y + h / 2))]);
}
async function capture(name) {
  const s = await state();
  await writeFile(`${out}/${name}.json`, JSON.stringify(s, null, 2));
  await writeFile(`${out}/${name}.png`, (await adb(['exec-out', 'screencap', '-p'])).stdout);
  return s;
}
const count = s => [...s.bag.slots, ...s.bag.overflow].filter(i => i.item_id.startsWith('fish_')).reduce((a, b) => a + b.quantity, 0);
const checks = [];
let realTouchEvents = 0;
async function driveFish(name, holdProof = false, intentionallyLose = false) {
  await waitFor(s => s.phase === 'hook', 'No bite at ' + name, 12000);
  await tap('FishingAction');
  let s = await waitFor(s => s.phase === 'playing', 'Hook failed at ' + name);
  await capture(name + '-playing');
  const [x, y, w, h] = s.controls.find(c => c.name === 'FishingAction').bounds;
  const point = [String(Math.round(x + w / 2)), String(Math.round(y + h / 2))];
  if (holdProof) {
    const before = await state();
    await adb(['shell', 'input', 'motionevent', 'DOWN', ...point]);
    await delay(400);
    const mid = await state();
    await delay(300);
    const afterHold = await state();
    await adb(['shell', 'input', 'motionevent', 'UP', ...point]);
    realTouchEvents += 2;
    assert(afterHold.model.bar > mid.model.bar + .06 || afterHold.model.bar > .8, 'Holding must raise the bar after reversing its falling velocity');
    if (afterHold.presentation) {
      assert(afterHold.presentation.pull > .8);
      const distance = (a,b) => Math.hypot(...a.map((n,i)=>n-b[i]));
      assert(distance(before.presentation.hand,afterHold.presentation.hand) > .05);
      assert(distance(before.presentation.tip,afterHold.presentation.tip) > .2);
      await writeFile(out+'/hold-response.json',JSON.stringify({before,mid,held:afterHold},null,2));
    }
    s = await state();
  }

  let held = false;
  const until = Date.now() + 40000;
  while (s.phase === 'playing' && Date.now() < until) {
    const desired = !intentionallyLose && s.model.fish > s.model.bar + s.model.velocity * .15;
    if (desired !== held) {
      await adb(['shell', 'input', 'motionevent', desired ? 'DOWN' : 'UP', ...point]);
      held = desired;
      realTouchEvents++;
    }
    await delay(45);
    s = await state();
  }
  if (held) { await adb(['shell', 'input', 'motionevent', 'UP', ...point]); realTouchEvents++; }
  return waitFor(s => s.phase === 'result' && !s.busy, 'No result at ' + name);
}
let peer;
try {
  await delay(1800);
  await adb(['shell', 'uiautomator', 'dump', '/sdcard/fishing-ui.xml']);
  const xml=(await adb(['exec-out','cat','/sdcard/fishing-ui.xml'])).stdout.toString();
  await writeFile(out+'/startup.xml',xml);
  const node=(xml.match(/<node\b[^>]+>/g)??[]).find(n=>/text="(?:Don't Show Again|确定|Continue|继续)"/.test(n)&&/clickable="true"/.test(n));
  if(node){const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);await adb(['shell','input','tap',String(Math.round((+b[1]+ +b[3])/2)),String(Math.round((+b[2]+ +b[4])/2))]);}
  await delay(700);
  let s=await waitFor(s=>s.joined,'Not joined');
  await tap('GoFishing');
  s=await waitFor(s=>s.phase==='ready','No free shore');
  const firstOrigin=s.position;
  await capture('shore-ready');
  peer=await fishingPeer('output/fishing-shore-2026-09-19/private',s.position);
  await waitFor(s=>s.remote_fishing.length>0,'Peer fishing not visible');
  await capture('peer-casting');
  await tap('FishingAction');
  s=await driveFish('together',true);
  assert.equal(s.fishing.last.outcome,'caught');
  await capture('together-caught');
  await delay(500);
  assert(!peer.error,String(peer.error));
  await peer.close();peer=null;
  await waitFor(s=>s.remote_fishing.length===0,'Ghost rod after departure');
  await tap('CloseFishing');
  await waitFor(s=>s.phase==='closed','Close failed');
  await delay(300);
  await capture('shore-free');
  // Tap a different visible area of the water using the read-only scene projection.
  s=await state();
  const target=s.water_targets.find(p=>p.site==='farm_pond'&&p.screen[0]>32&&p.screen[0]<688&&p.screen[1]>220&&p.screen[1]<1250);
  assert(target);await adb(['shell','input','tap',...target.screen.map(v=>String(Math.round(v)))]);
  s=await waitFor(s=>s.phase==='ready','Water tap did not start fishing');
  await capture('water-tap-ready');
  await tap('FishingAction');
  s=await driveFish('water-tap');
  assert.equal(s.fishing.last.outcome,'caught');
  await capture('water-tap-caught');
  await tap('CloseFishing');
  await command('street');
  await waitFor(s=>s.joined&&!s.controls.some(c=>c.name==='GoFishing'),'Street missing');
  await delay(2000);
  // Fixture scene entry keeps the normal free-shore planner; casts and minigame are real touches.
  await command('visit:street_lake');
  await waitFor(s=>s.phase==='ready'&&s.site==='street_lake','Lake walk failed');
  await capture('lake-free-ready');
  await tap('FishingAction');s=await driveFish('lake');assert.equal(s.fishing.last.outcome,'caught');
  await capture('lake-caught');await tap('CloseFishing');
  await waitFor(s=>s.phase==='closed','Lake close failed');await delay(300);
  await command('visit:street_river');
  await waitFor(s=>s.phase==='ready'&&s.site==='street_river','River walk failed');
  await capture('river-free-ready');await tap('FishingAction');
  const beforeRiver=count(await state());
  s=await driveFish('river');assert(['caught','escaped'].includes(s.fishing.last.outcome));
  assert.equal(count(s),beforeRiver+(s.fishing.last.outcome==='caught'?1:0));await capture('river-result');
  await writeFile(out+'/result.json',JSON.stringify({passed:true,firstOrigin,realTouchEvents,riverOutcome:s.fishing.last.outcome,checks:['free shore','simultaneous visible rods','remote cleanup','water tap','lake','river']},null,2));
} finally {if(peer)await peer.close();await adb(['shell','input','motionevent','UP','0','0']).catch(()=>{});await writeFile(out+'/logcat.txt',(await adb(['logcat','-d','-v','threadtime'])).stdout);}
