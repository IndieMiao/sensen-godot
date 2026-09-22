import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const run = promisify(execFile), serial = process.env.JOURNEY_SERIAL, pkg = process.env.JOURNEY_PACKAGE;
const root = 'output/scroll-ui-2026-09-16/android';
const adb = args => run('adb', ['-s', serial, ...args], { encoding: 'buffer', maxBuffer: 16 * 1024 * 1024, timeout: 30000 });
const delay = ms => new Promise(r => setTimeout(r, ms));
await mkdir(root, { recursive: true });
await delay(1800);
for (let attempt = 0; attempt < 5; attempt++) {
  await adb(['shell', 'uiautomator', 'dump', '/sdcard/scroll-qa.xml']);
  const xml = (await adb(['exec-out', 'cat', '/sdcard/scroll-qa.xml'])).stdout.toString();
  await writeFile(`${root}/startup-${attempt}.xml`, xml);
  const nodes = xml.match(/<node\b[^>]+>/g) ?? [];
  const button = nodes.find(n => /text="Don't Show Again"/.test(n)) ?? nodes.find(n => /text="(?:OK|确定|Continue|继续)"/.test(n) && /clickable="true"/.test(n));
  if (!button) break;
  const b = /bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(button);
  assert(b, 'system dialog button has bounds');
  await adb(['shell', 'input', 'tap', String(Math.round((+b[1] + +b[3]) / 2)), String(Math.round((+b[2] + +b[4]) / 2))]);
  await delay(800);
}
async function state(phase) {
  const deadline = Date.now() + 25000;
  while (Date.now() < deadline) {
    try {
      const s = JSON.parse((await adb(['exec-out', 'run-as', pkg, 'cat', 'files/scroll-proof/state.json'])).stdout);
      if (!phase || s.phase === phase) return s;
    } catch {}
    await delay(200);
  }
  throw new Error(`Timed out waiting for ${phase}`);
}
const center = ([x, y, w, h]) => [Math.round(x + w / 2), Math.round(y + h / 2)];
const tap = rect => adb(['shell', 'input', 'tap', ...center(rect).map(String)]);
const proof = [];
const pid = (await adb(['shell', 'pidof', '-s', pkg])).stdout.toString().trim();
try {
  for (const phase of ['party', 'nearby', 'stall', 'bag', 'wardrobe_parts', 'wardrobe_tabs', 'nested']) {
    const before = await state(phase);
    assert.equal(before.clicks, 0, phase + ' starts without clicks');
    const [x, y] = center(before.target);
    // Coordinates come from the actual Godot Control tree, which Android exposes as one SurfaceView.
    const horizontal = ['nearby', 'wardrobe_tabs'].includes(phase);
    const distance = Math.round((before.next[2] / 250) * (horizontal ? 100 : 85));
    await writeFile(`${root}/${phase}-before.json`, JSON.stringify(before, null, 2));
    await writeFile(`${root}/${phase}-before.png`, (await adb(['exec-out', 'screencap', '-p'])).stdout);
    await adb(['shell', 'input', 'swipe', String(x), String(y), String(x - (horizontal ? distance : 0)), String(y - (horizontal ? 0 : distance)), '400']);
    await delay(450);
    const after = await state(phase);
    await writeFile(`${root}/${phase}-after.json`, JSON.stringify(after, null, 2));
    await writeFile(`${root}/${phase}-after.png`, (await adb(['exec-out', 'screencap', '-p'])).stdout);
    const axis = horizontal ? 0 : 1;
    const moved = phase === 'nested' ? after.outer[1] - before.outer[1] : after.scroll[axis] - before.scroll[axis];
    assert(moved >= 20, `${phase} must scroll; moved ${moved}`);
    assert.equal(after.clicks, 0, `${phase} drag must not click`);
    assert.equal(after.commands, 0, `${phase} drag must not send commands`);
    if (phase === 'nested') assert.equal(after.scroll[0], 0, 'vertical gesture does not move inner horizontal strip');
    if (phase === 'nearby') {
      const card = after.controls.find(c => /@Button@/.test(c.path) && c.rect[2] >= 120 * before.next[2] / 250 && !c.disabled);
      assert(card, 'a visible farm card remains clickable');
      await tap(card.rect);
      await delay(300);
      assert.equal((await state(phase)).clicks, 1, 'farm card tap activates exactly once');
    }
    proof.push({ phase, moved, clicks_after_drag: after.clicks, commands: after.commands });
    console.log(JSON.stringify(proof.at(-1)));
    await tap(after.next);
    await delay(250);
  }
  await writeFile(root + '/result.json', JSON.stringify({ passed: true, checks: proof }, null, 2));
} finally {
  await writeFile(root + '/godot.log', (await adb(['logcat', '-d', '--pid', pid, '-s', 'godot'])).stdout);
}
