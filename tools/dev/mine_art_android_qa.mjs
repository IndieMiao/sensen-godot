import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const run = promisify(execFile);
const serial = process.env.JOURNEY_SERIAL, pkg = process.env.JOURNEY_PACKAGE;
assert.equal(pkg, 'com.sensen.journeymineartqa', 'Run the isolated viewer through tools/android/run_test.sh');
assert.ok(serial?.startsWith('emulator-'), 'This QA is restricted to an emulator');
const folder = 'output/mine-art-2026-09-24/android';
const adb = args => run('adb', ['-s', serial, ...args], { encoding: 'buffer', timeout: 30000, maxBuffer: 16e6 });
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
let touches = 0;
const evidence = [];
await mkdir(folder, { recursive: true });
async function state() {
  return JSON.parse((await adb(['exec-out', 'run-as', pkg, 'cat', 'files/mine-art-state.json'])).stdout);
}
async function until(test, label, timeout = 18000) {
  const end = Date.now() + timeout;
  let value;
  while (Date.now() < end) {
    try { value = await state(); if (test(value)) return value; } catch {}
    await delay(140);
  }
  await writeFile(`${folder}/failure-state.json`, JSON.stringify(value, null, 2));
  throw new Error(`Timed out: ${label}`);
}
async function tapPoint(p) {
  touches++;
  await adb(['shell', 'input', 'tap', ...p.map(x => String(Math.round(x)))]);
}
async function button(name) {
  const s = await until(s => s.controls.some(c => c.name === name && !c.disabled), name);
  const { rect: [x, y, w, h] } = s.controls.find(c => c.name === name);
  await tapPoint([x + w / 2, y + h / 2]);
}
async function target(id) {
  const s = await until(s => s.targets.some(t => t.id === id && t.pick === id), `pick ${id}`);
  await tapPoint(s.targets.find(t => t.id === id).point);
}
async function capture(name) {
  await writeFile(`${folder}/${name}.png`, (await adb(['exec-out', 'screencap', '-p'])).stdout);
  const s = await state();
  evidence.push({ name, floor: s.floor, targets: s.targets, draw_calls: s.draw_calls, primitives: s.primitives });
  console.log(`Captured ${name}`);
}
async function dismissNativeDialogs() {
  for (let i = 0; i < 3; i++) {
    await adb(['shell', 'uiautomator', 'dump', '/sdcard/mine-art-dialog.xml']);
    const xml = (await adb(['exec-out', 'cat', '/sdcard/mine-art-dialog.xml'])).stdout.toString();
    await writeFile(`${folder}/native-ui-${i}.xml`, xml);
    const node = (xml.match(/<node\b[^>]+>/g) ?? []).find(n => /text="(?:OK|Don't Show Again)"/.test(n) && /clickable="true"/.test(n));
    if (!node) break;
    const b = /bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);
    await tapPoint([(+b[1] + +b[3]) / 2, (+b[2] + +b[4]) / 2]);
    await delay(400);
  }
}

const originalSize = (await adb(['shell', 'wm', 'size'])).stdout.toString();
const override = /Override size: (\d+x\d+)/.exec(originalSize)?.[1];
let pid;
try {
  await dismissNativeDialogs();
  pid = (await adb(['shell', 'pidof', '-s', pkg])).stdout.toString().trim();
  await until(s => s.floor === 1 && s.targets.length >= 8, 'first floor');
  await target('elevator');
  await until(s => s.feedback.includes('5') && !s.moving, 'locked elevator feedback');
  await capture('locked-elevator');

  await button('ReviewReset');
  await delay(350);
  let before = await state();
  const [x, y, w, h] = before.stick;
  const center = [x + w / 2, y + h / 2];
  touches++;
  await adb(['shell', 'input', 'swipe', ...center.map(Math.round).map(String), String(Math.round(center[0] + w * 0.28)), String(Math.round(center[1])), '550']);
  await delay(200);
  let after = await state();
  const dx = after.player_screen[0] - before.player_screen[0], dy = after.player_screen[1] - before.player_screen[1];
  assert.ok(dx > 8 && Math.abs(dy) < Math.abs(dx) * 0.2, `Screen-right joystick: ${dx}, ${dy}`);
  await capture('screen-relative-movement');

  before = await state();
  const [wx, wy, ww, wh] = before.world_area;
  const panStart = [wx + ww * 0.5, wy + wh * 0.18];
  touches++;
  await adb(['shell', 'input', 'swipe', ...panStart.map(Math.round).map(String), String(Math.round(panStart[0] + 90)), String(Math.round(panStart[1] + 40)), '350']);
  await delay(350);
  after = await state();
  assert.ok(Math.hypot(...after.pan) > 0.05, 'World drag pans the diagonal camera');
  assert.equal(after.commands.length, before.commands.length, 'Pan does not mine');
  await button('ReviewReset');
  await delay(400);

  for (let i = 0; i < 6; i++) {
    const s = await state();
    const id = s.targets.find(t => t.id.startsWith('rock_')).id;
    await target(id);
    await until(s => !s.targets.some(t => t.id === id) && !s.busy, `dig ${id}`);
  }
  await capture('six-rocks-cleared');
  await target('down');
  await until(s => s.floor === 2 && !s.busy, 'descend by ladder');
  await capture('ladder-arrival');
  await target('up');
  await until(s => s.floor === 1 && !s.busy, 'ascend by ladder');

  await button('OpenBag');
  await until(s => s.bag, 'bag opens');
  await capture('bag');
  const close = (await state()).controls.find(c => /close/i.test(c.name) || /close|关闭/i.test(c.text));
  assert.ok(close, 'Bag close control exists in Godot UI tree');
  await button(close.name);
  await until(s => !s.bag, 'bag closes');

  for (const resolution of ['720x1280', '780x1688', '960x720']) {
    await adb(['shell', 'wm', 'size', resolution]);
    await delay(700);
    for (let floor = 1; floor <= 5; floor++) {
      await button(`ReviewFloor${floor}`);
      await until(s => s.floor === floor && s.targets.length > 0, `floor ${floor}`);
      await delay(300);
      const s = await state();
      assert.ok(s.targets.every(t => t.id === t.pick), `Model picking at ${resolution} / B${floor}`);
      if (floor === 5) assert.ok(!s.targets.some(t => t.id.startsWith('rock_')));
      await capture(`${resolution}-floor-${floor}`);
    }
  }
  const report = { passed: true, touches, package: pkg, serial, gameplay_source: 'Isolated local command fixtures; no production account or server', evidence };
  await writeFile(`${folder}/report.json`, JSON.stringify(report, null, 2));
  console.log(`MINE_ART_ANDROID_PASSED touches=${touches}`);
} finally {
  await adb(['shell', 'wm', 'size', override ?? 'reset']);
  if (pid) await writeFile(`${folder}/runtime.log`, (await adb(['logcat', '-d', '--pid', pid])).stdout);
}
