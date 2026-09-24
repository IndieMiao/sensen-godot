import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';

const run=promisify(execFile), serial=process.env.JOURNEY_SERIAL, pkg=process.env.JOURNEY_PACKAGE;
assert.equal(pkg,'com.sensen.journeymineartqa');
assert.ok(serial?.startsWith('emulator-'),'Use the emulator test runner');
const folder='output/mine-camera-2026-09-24/android';
await mkdir(folder,{recursive:true});
const adb=args=>run('adb',['-s',serial,...args],{encoding:'buffer',timeout:30000,maxBuffer:16e6});
const delay=ms=>new Promise(r=>setTimeout(r,ms));
let touches=0, pid;
const evidence=[];
const state=async()=>JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/mine-art-state.json'])).stdout);
const distance=(a,b)=>Math.hypot(...a.map((n,i)=>n-b[i]));
async function until(test,label,timeout=16000){
  const end=Date.now()+timeout;let s;
  while(Date.now()<end){try{s=await state();if(test(s))return s;}catch{}await delay(130);}
  await writeFile(`${folder}/failure-state.json`,JSON.stringify(s,null,2));throw Error(label);
}
async function tap(point){touches++;await adb(['shell','input','tap',...point.map(Math.round).map(String)]);}
async function button(name){
  const s=await until(s=>s.controls.some(c=>c.name===name&&!c.disabled),name);
  const [x,y,w,h]=s.controls.find(c=>c.name===name).rect;await tap([x+w/2,y+h/2]);
}
async function capture(name){
  await writeFile(`${folder}/${name}.png`,(await adb(['exec-out','screencap','-p'])).stdout);
  const s=await state();evidence.push({name,center:s.camera_center,zoom:s.zoom,size:s.camera_size,player:s.player,focus:s.focus_visible});
  console.log(`Captured ${name}`);
}
async function panLeft(){
  const s=await state(), [x,y,w,h]=s.world_area;
  touches++;
  await adb(['shell','input','swipe',String(Math.round(x+w*.77)),String(Math.round(y+h*.6)),String(Math.round(x+w*.15)),String(Math.round(y+h*.6)),'600']);
  await delay(850);
}
async function pinch(factor){
  const s=await state(), [x,y,w,h]=s.world_area, cx=x+w*.5,cy=y+h*.62,half=w*.12;
  const points=[cx-half,cy,cx+half,cy,cx-half*factor,cy,cx+half*factor,cy].map(v=>String(Math.round(v)));
  touches++;
  await adb(['shell','env','CLASSPATH=/data/local/tmp/journey-touch.dex','app_process','/data/local/tmp','JourneyTouch',...points,'550']);
  await delay(800);
}
async function dismissDialogs(){
  for(let i=0;i<3;i++){
    await adb(['shell','uiautomator','dump','/sdcard/mine-camera-dialog.xml']);
    const xml=(await adb(['exec-out','cat','/sdcard/mine-camera-dialog.xml'])).stdout.toString();
    await writeFile(`${folder}/native-ui-${i}.xml`,xml);
    const node=(xml.match(/<node\b[^>]+>/g)??[]).find(n=>/text="(?:OK|Don't Show Again)"/.test(n)&&/clickable="true"/.test(n));
    if(!node)break;
    const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);await tap([(+b[1]+ +b[3])/2,(+b[2]+ +b[4])/2]);await delay(400);
  }
}
const sizeText=(await adb(['shell','wm','size'])).stdout.toString();
const override=/Override size: (\d+x\d+)/.exec(sizeText)?.[1];
try{
  await dismissDialogs();pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim();
  await until(s=>s.floor===1&&s.camera_center&&s.camera_size<8,'Close camera loaded');
  for(const resolution of ['720x1280','780x1688','960x720']){
    await adb(['shell','wm','size',resolution]);await delay(650);
    await button('ReviewFloor1');await delay(500);
    let s=await state();assert.ok(s.camera_size<=7.21,'Farm-sized close view');
    assert.ok(!s.focus_visible);await capture(`${resolution}-default`);

    const rock=s.targets.find(t=>t.id.startsWith('rock_')&&t.id===t.pick);
    assert.ok(rock,'A visible ore target is pickable');
    const originalCenter=s.camera_center;
    await tap(rock.point);
    await until(s=>!s.targets.some(t=>t.id===rock.id)&&!s.busy,'Close-view mining');
    s=await state();assert.ok(distance(s.camera_center,originalCenter)<.002,'Mining retains camera position');

    for(let i=0;i<5&&!(await state()).focus_visible;i++)await panLeft();
    s=await until(s=>s.focus_visible,'Offscreen portrait');
    const panned=s.camera_center, actor=s.player, zoom=s.zoom;
    await delay(1300);s=await state();
    assert.ok(distance(s.camera_center,panned)<.03,'Released pan does not spring back');
    await capture(`${resolution}-offscreen`);
    await button('AvatarFocus');
    await until(s=>!s.focus_visible&&distance(s.camera_center,s.player)<.01,'Portrait recenter');
    s=await state();assert.ok(distance(s.player,actor)<.002);assert.ok(Math.abs(s.zoom-zoom)<.001);
    await capture(`${resolution}-recentered`);

    const commandCount=s.commands.length;
    await pinch(1.28);
    s=await state();assert.ok(s.zoom>1.12,'Two-finger zoom in');
    assert.equal(s.commands.length,commandCount,'Pinch cannot mine');
    await capture(`${resolution}-zoom-in`);
    const closeZoom=s.zoom;
    await pinch(.75);
    s=await state();assert.ok(s.zoom<closeZoom-.1,'Two-finger zoom out');

    const beforeBag=s.camera_center;
    await button('OpenBag');await until(s=>s.bag,'Open bag');
    s=await state();assert.ok(!s.focus_visible);assert.ok(distance(s.camera_center,beforeBag)<.01);
    await button('CloseBag');await until(s=>!s.bag,'Close bag');

    for(const number of [2,3,4,5]){
      await button(`ReviewFloor${number}`);await until(s=>s.floor===number,'Change fixture floor');await delay(250);
      s=await state();assert.ok(distance(s.camera_center,s.player)<.002,'New floor frames arrival');
      assert.ok(Math.abs(s.zoom-1)<.001);await capture(`${resolution}-floor-${number}`);
    }
  }
  await writeFile(`${folder}/report.json`,JSON.stringify({passed:true,touches,evidence,serial,package:pkg,source:'Native Android OS touch; isolated local command fixtures'},null,2));
  console.log(`MINE_CAMERA_ANDROID_PASSED touches=${touches}`);
}finally{
  await adb(['shell','wm','size',override??'reset']);
  if(pid)await writeFile(`${folder}/runtime.log`,(await adb(['logcat','-d','--pid',pid])).stdout);
}
