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
try {
  await delay(1800);
  // System permission dialogs use the Android UI tree; game controls use the Godot scene tree.
  for (let attempt = 0; attempt < 3; attempt++) {
    await adb(['shell', 'uiautomator', 'dump', '/sdcard/fishing-ui.xml']);
    const xml = (await adb(['exec-out', 'cat', '/sdcard/fishing-ui.xml'])).stdout.toString();
    await writeFile(`${out}/startup-${attempt}.xml`, xml);
    const node = (xml.match(/<node\b[^>]+>/g) ?? []).find(n => /text="(?:Don't Show Again|OK|确定|Continue|继续)"/.test(n) && /clickable="true"/.test(n));
    if (!node) break;
    const b = /bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);
    await adb(['shell', 'input', 'tap', String(Math.round((+b[1] + +b[3]) / 2)), String(Math.round((+b[2] + +b[4]) / 2))]);
    await delay(300);
  }
  let s = await waitFor(s => s.joined, 'Not joined');
  const originalCount = count(s);
  await capture('farm-start');
  await tap('GoFishing');
  await waitFor(s => s.phase === 'ready' && s.site === 'farm_pond', 'Did not walk to pond');
  await capture('pond-ready');
  await tap('FishingAction');
  s = await driveFish('pond', true);
  assert.equal(s.fishing.last.outcome, 'caught');
  assert.equal(count(s), originalCount + 1);
  assert(realTouchEvents > 10);
  assert.equal(s.unconfirmed, false);
  await capture('pond-caught');
  checks.push('Pond walk, cast, bite, touch controls, HTTP settlement and persistent fish inventory');
  const fishId = s.fishing.last.fish_id;
  const stack = s.bag.slots.find(i => i.item_id === fishId);
  const wallet = s.wallet;
  await tap('CloseFishing');
  await capture('pond-water');
  await command('bag');
  await tap('BagSlot_' + stack.id);
  await tap('SellFish');
  await capture('sale-preview');
  await tap('ConfirmFishSale');
  s = await waitFor(s => s.wallet > wallet, 'Sale did not settle');
  assert.equal(count(s), originalCount);
  await capture('sold');
  checks.push('Bag grade and unit price, quantity/total preview, confirmed sale and wallet increase');
  await command('street');
  await waitFor(s => s.joined && !s.controls.some(c => c.name === 'GoFishing'), 'Street did not load');
  await command('visit:street_lake');
  await waitFor(s => s.phase === 'ready' && s.site === 'street_lake', 'Lake unreachable');
  await capture('lake-ready');
  await tap('FishingAction');
  s = await driveFish('lake');
  assert.equal(s.fishing.last.outcome, 'caught');
  await capture('lake-caught');
  checks.push('Street lake reachable with its independent fish pool and successful catch');
  await tap('CloseFishing');
  await command('visit:street_river');
  await waitFor(s => s.phase === 'ready' && s.site === 'street_river', 'River unreachable');
  await capture('river-ready');
  await tap('FishingAction');
  s = await driveFish('river', false, true);
  assert.equal(s.fishing.last.outcome, 'escaped');
  await capture('river-escaped');
  checks.push('Street river reachable; failing the minigame grants no fish');
  const beforePause = count(s);
  await tap('FishingAction');
  await waitFor(s => s.phase === 'hook', 'Pre-background bite failed');
  await tap('FishingAction');
  await waitFor(s => s.phase === 'playing', 'Pre-background hook failed');
  await adb(['shell', 'input', 'keyevent', '3']);
  await delay(800);
  const component = (await adb(['shell', 'cmd', 'package', 'resolve-activity', '--brief', pkg])).stdout.toString().trim().split('\n').at(-1);
  await adb(['shell', 'am', 'start', '-n', component]);
  s = await waitFor(s => s.joined && !s.busy && ['result', 'error', 'closed'].includes(s.phase), 'Background did not stop fishing');
  assert.equal(count(s), beforePause);
  await capture('background-return');
  checks.push('Background interrupts the current cast, releases held touch, preserves confirmed fish and reconnects');
  await writeFile(out + '/result.json', JSON.stringify({ passed: true, checks, touch_events: realTouchEvents }, null, 2));
  console.log(JSON.stringify({ passed: true, checks }));
} finally {
  const log = (await adb(['logcat', '-d', '-s', 'godot'])).stdout;
  await writeFile(out + '/godot.log', log);
  await capture('last-state').catch(() => {});
}
