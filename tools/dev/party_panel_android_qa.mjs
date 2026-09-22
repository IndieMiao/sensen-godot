import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const run = promisify(execFile), serial = process.env.JOURNEY_SERIAL, pkg = process.env.JOURNEY_PACKAGE;
const root = 'output/party-panel-2026-09-16/android';
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
async function state() {
  for (let n = 0; n < 80; n++) {
    try { return JSON.parse((await adb(['exec-out', 'run-as', pkg, 'cat', 'files/party-panel-proof/state.json'])).stdout); } catch {}
    await delay(150);
  }
  throw new Error('Missing party panel state');
}
const center = ([x,y,w,h]) => [Math.round(x+w/2),Math.round(y+h/2)];
const tap = rect => adb(['shell','input','tap',...center(rect).map(String)]);
const checks = [];
async function snapshot(name) {
  const s = await state();
  await writeFile(`${root}/${name}.json`,JSON.stringify(s,null,2));
  await writeFile(`${root}/${name}.png`,(await adb(['exec-out','screencap','-p'])).stdout);
  return s;
}
const pid = (await adb(['shell','pidof','-s',pkg])).stdout.toString().trim();
try {
  let s = await snapshot('opened');
  assert(s.open);
  const header = s.close;
  await tap(s.copy); await delay(180);
  s = await snapshot('copied');
  assert.equal(s.clipboard,'COPY-QA-123');
  assert.equal(s.toast,true);
  assert.equal(s.toast_text,'邀请码已复制');
  assert(s.toast_rect[1]+s.toast_rect[3] < s.panel[1], 'toast sits fully above panel');
  assert(s.toast_rect[3] <= 120, 'toast is compact and fits the screen');
  checks.push('Invite code copied to Android clipboard with Chinese toast');
  await delay(2200);
  s = await state(); assert.equal(s.toast,false);
  checks.push('Toast automatically hides');
  let [x,y] = center(s.copy);
  await adb(['shell','input','swipe',String(x),String(y),String(x),String(y-170),'400']);
  await delay(250);
  s = await snapshot('scrolled');
  assert(s.scroll > 20);
  assert.deepEqual(s.close,header);
  assert.equal(s.toast,false);
  assert.equal(s.commands,0);
  checks.push('Dragging invite code scrolls without copying; close remains fixed');
  await tap(s.close); await delay(250);
  s = await state(); assert.equal(s.open,false); assert.equal(s.world_clicks,0);
  checks.push('Top-right close dismisses without clicking the world');
  await tap(s.open_button); await delay(300);
  s = await state(); assert(s.open);
  const outside = s.outside;
  await adb(['shell','input','tap',String(Math.round(outside[2]/2)),String(Math.round(outside[3]-36))]);
  await delay(250);
  s = await snapshot('outside-closed');
  assert.equal(s.open,false); assert.equal(s.world_clicks,0);
  checks.push('Outside tap dismisses without clicking the world');
  await tap(s.open_button); await delay(300);
  s = await state(); assert(s.open);
  [x,y] = center(s.copy);
  await adb(['shell','input','swipe',String(x),String(y),String(x),String(Math.round(s.panel[1]+s.panel[3]+60)),'650']);
  await delay(250);
  s = await state(); assert(s.open); assert.equal(s.toast,false); assert.equal(s.world_clicks,0);
  checks.push('Drag starting inside and ending outside does not dismiss or copy');
  await tap(s.close);
  const result = {passed:true,checks};
  await writeFile(root+'/result.json',JSON.stringify(result,null,2));
  console.log(JSON.stringify(result));
} finally {
  const log=(await adb(['logcat','-d','--pid',pid,'-s','godot'])).stdout;
  await writeFile(root+'/godot.log',log);
  assert(!/SCRIPT ERROR|Parse Error|Compile Error/.test(log.toString()),'No script errors');
}
