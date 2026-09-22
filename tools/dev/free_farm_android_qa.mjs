import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const run = promisify(execFile), serial = process.env.JOURNEY_SERIAL, pkg = process.env.JOURNEY_PACKAGE;
assert(serial && pkg, 'Run inside tools/android/run_test.sh');
const out = 'output/free-farm-2026-09-17/android';
const adb = args => run('adb', ['-s', serial, ...args], { encoding:'buffer', maxBuffer:16*1024*1024, timeout:30000 });
const delay = ms => new Promise(resolve=>setTimeout(resolve,ms));
await mkdir(out,{recursive:true});
await delay(2200);
for(let attempt=0;attempt<4;attempt++) {
  await adb(['shell','uiautomator','dump','/sdcard/free-farm-ui.xml']);
  const xml = (await adb(['exec-out','cat','/sdcard/free-farm-ui.xml'])).stdout.toString();
  await writeFile(`${out}/startup-${attempt}.xml`,xml);
  const node=(xml.match(/<node\b[^>]+>/g)??[]).find(n=>/text="(?:Don't Show Again|OK|确定|Continue|继续)"/.test(n)&&/clickable="true"/.test(n));
  if(!node)break;
  const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);
  assert(b);
  await adb(['shell','input','tap',String(Math.round((+b[1]+ +b[3])/2)),String(Math.round((+b[2]+ +b[4])/2))]);
  await delay(600);
}
async function state() {
  for(let n=0;n<50;n++) {
    try { return JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/free-farm-proof/state.json'])).stdout); } catch {}
    await delay(200);
  }
  throw new Error('No observed Godot scene state');
}
// Godot world/UI is drawn in one Android SurfaceView. Use the actual scene tree's
// screen-transformed control rectangles and Camera3D projection, never screenshot guesses.
const tapPoint=p=>adb(['shell','input','tap',...p.map(v=>String(Math.round(v)))]);
const tapRect=([x,y,w,h])=>tapPoint([x+w/2,y+h/2]);
async function capture(name) {
  const s=await state();
  await writeFile(`${out}/${name}.json`,JSON.stringify(s,null,2));
  await writeFile(`${out}/${name}.png`,(await adb(['exec-out','screencap','-p'])).stdout);
  return s;
}
const checks=[];
let s=await capture('default');
assert.equal(s.work_mode,false);assert.equal(s.hold_enabled,false);assert.equal(s.requests.length,0);
const before=s.position;
await tapPoint(s.wild);await delay(1000);s=await state();
assert(Math.hypot(s.position[0]-before[0],s.position[1]-before[1])>0.2);
assert.equal(s.requests.length,0);assert.equal(s.busy,false);
checks.push('Default grass tap moves without a farming command');
await tapPoint(s.crop);await delay(1200);s=await capture('walk-through-crops');
assert.equal(s.requests.length,0);assert.equal(s.busy,false);
assert(Math.hypot(s.position[0]-13.25,s.position[1]+19.25)<0.1);
checks.push('Ripe crop tap walks onto the crop without harvesting');
const p=s.wild.map(v=>String(Math.round(v)));
await adb(['shell','input','swipe',...p,...p,'700']);await delay(1000);
s=await state();assert.equal(s.requests.length,0);assert.equal(s.brush,0);
checks.push('Holding in walking mode does not till');
await tapRect(s.mode_button);await delay(200);s=await capture('work-mode');
assert.equal(s.work_mode,true);assert.equal(s.hold_enabled,true);
await tapPoint(s.wild);await delay(1500);s=await state();
assert.equal(s.requests.length,1);assert.equal(JSON.parse(s.requests[0].body).type,'till_cells');
checks.push('Explicit work mode sends till_cells for the selected empty cell');
await tapRect(s.mode_button);await delay(150);s=await state();
assert.equal(s.work_mode,false);assert.equal(s.hold_enabled,false);
await tapPoint(s.crop);await delay(1200);s=await state();
assert.equal(s.requests.length,1);
checks.push('Returning to walking restores movement over crops');
await adb(['shell','input','keyevent','KEYCODE_HOME']);await delay(300);
await adb(['shell','monkey','-p',pkg,'-c','android.intent.category.LAUNCHER','1']);await delay(600);
s=await capture('resumed');assert.equal(s.requests.length,1);assert.equal(s.brush,0);
checks.push('Background and resume leave no latent brush or extra commands');
await adb(['shell','run-as',pkg,'sh','-c',"'echo seeds > files/free-farm-proof/command'"]);
await delay(500);s=await capture('seed-strip');
assert.equal(s.seed_visible,true);
const selected=s.selected_crop;
const seedFeet=s.feet;
const [sx,sy,sw,sh]=s.first_seed;
await adb(['shell','input','swipe',String(Math.round(sx+sw/2)),String(Math.round(sy+sh/2)),String(Math.round(sx+sw/2-180)),String(Math.round(sy+sh/2)),'450']);
await delay(300);s=await capture('seed-strip-scrolled');
assert(s.seed_scroll>20);assert.equal(s.selected_crop,selected);assert.equal(s.requests.length,1);
assert(Math.hypot(s.feet[0]-seedFeet[0],s.feet[1]-seedFeet[1])<1,'Seed drag must not pan the world');
checks.push('Dragging a seed card scrolls the single row without selecting, farming or panning the world');
const pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim();
const log=(await adb(['logcat','-d','--pid',pid,'-s','godot'])).stdout;
await writeFile(`${out}/godot.log`,log);
assert(!/SCRIPT ERROR|Parse Error|Compile Error/.test(log.toString()));
await writeFile(`${out}/result.json`,JSON.stringify({passed:true,checks},null,2));
console.log(JSON.stringify({passed:true,checks}));
