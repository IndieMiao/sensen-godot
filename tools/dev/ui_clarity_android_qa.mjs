import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const run=promisify(execFile),serial=process.env.JOURNEY_SERIAL,pkg=process.env.JOURNEY_PACKAGE;
assert(serial&&pkg==='com.sensen.journeyuiqa');
const out='output/ui-clarity-2026-09-21/android';await mkdir(out,{recursive:true});
const adb=a=>run('adb',['-s',serial,...a],{encoding:'buffer',timeout:30000,maxBuffer:24e6});
const delay=ms=>new Promise(r=>setTimeout(r,ms));let last,touches=0;
async function state(){return last=JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/game-ui-proof/state.json'])).stdout)}
async function until(predicate,label,ms=40000){const end=Date.now()+ms;while(Date.now()<end){try{const s=await state();if(!s.navigation_pending&&predicate(s))return s}catch{}await delay(150)}throw Error(label+': '+JSON.stringify({scene:last?.scene,error:last?.error,avatar:last?.avatar_indicator,controls:last?.controls}))}
const matching=(c,id)=>!c.disabled&&c.bounds[2]>4&&c.bounds[3]>4&&[c.name,c.text,c.tooltip].includes(id);
async function tap(id){const s=await until(s=>s.controls.some(c=>matching(c,id)),'button '+id);const[x,y,w,h]=s.controls.find(c=>matching(c,id)).bounds;await adb(['shell','input','tap',String(Math.round(x+w/2)),String(Math.round(y+h/2))]);touches++;await delay(300)}
async function shot(name){const s=await state();await writeFile(out+'/'+name+'.json',JSON.stringify(s,null,2));await writeFile(out+'/'+name+'.png',(await adb(['exec-out','screencap','-p'])).stdout);console.log('CLARITY_CAPTURE',name);return s}
async function back(){await adb(['shell','input','keyevent','4']);await delay(300)}
try{
 await delay(1800);
 for(let i=0;i<3;i++){
  await adb(['shell','uiautomator','dump','/sdcard/clarity-start.xml']);const xml=(await adb(['exec-out','cat','/sdcard/clarity-start.xml'])).stdout.toString();await writeFile(out+'/startup-'+i+'.xml',xml);
  const node=(xml.match(/<node\b[^>]+>/g)??[]).find(x=>/text="(?:Don't Show Again|OK|确定|Continue|继续)"/.test(x)&&/clickable="true"/.test(x));if(!node)break;
  const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);await adb(['shell','input','tap',String((+b[1]+ +b[3])/2),String((+b[2]+ +b[4])/2)]);await delay(500);
 }
 let s=await until(s=>s.scene.endsWith('/farm/farm.tscn')&&s.joined,'farm',90000);const before=structuredClone(s);
 assert.equal(s.ui_density.icon_pixels,96);assert.deepEqual(s.ui_density.icon_logical,[24,24]);
 assert.equal(s.avatar_indicator.visible,false,'Onscreen avatar indicator must be hidden');await shot('01-farm-hd');
 const directions=process.env.CLARITY_QA_POND_ONLY==='1'?[]:[['left',-1,0],['right',1,0],['up',0,-1],['down',0,1],['upper-left',-1,-1],['upper-right',1,-1],['lower-left',-1,1],['lower-right',1,1]];
 for(const[name,dx,dy]of directions){
  for(let n=0;n<5;n++){
   s=await state();const[x,y,w,h]=s.world_area,cx=x+w*.5,cy=y+h*.5;
   const start=[cx-dx*w*.34,cy-dy*h*.34],end=[cx+dx*w*.34,cy+dy*h*.34];
   await adb(['shell','input','swipe',...start.concat(end).map(v=>String(Math.round(v))),'500']);touches++;await delay(900);
   s=await state();if(s.avatar_indicator.visible)break;
  }
  await delay(1500);s=await state();assert(s.avatar_indicator.visible,name+' indicator');
  const[rx,ry,rw,rh]=s.avatar_indicator.rect,[vx,vy,vw,vh]=s.screen_bounds;
  assert(rx>=vx&&ry>=vy&&rx+rw<=vx+vw&&ry+rh<=vy+vh,name+' safe bounds');
  const px=s.player_focus_screen[0]-(vx+vw*.5),py=s.player_focus_screen[1]-(vy+vh*.5),ix=rx+rw*.5-(vx+vw*.5),iy=ry+rh*.5-(vy+vh*.5);
  assert(px*ix+py*iy>0,name+' points toward character');
  if(dx)assert(Math.sign(ix)===dx,name+' horizontal edge');if(dy)assert(Math.sign(iy)===dy,name+' vertical edge');
  await shot('direction-'+name);await tap('AvatarFocus');await until(s=>!s.avatar_indicator.visible,'recenter hides portrait');await delay(500);
 }
 s=await state();assert.deepEqual(s.position,before.position,'Panning moved character');await shot('02-recentered');
 await tap('LifeButton');await until(s=>s.bag_panels.length===1,'bag');s=await state();assert.equal(s.bag_panels[0].columns,5);await shot('03-bag-hd');
 await tap('BagFilter');await shot('04-filter-hd');await adb(['shell','input','keyevent','111']);await delay(300);
 await tap('BagPage_character');await until(s=>s.character_previews.length===1,'character');await delay(1200);s=await shot('05-character-hd');const preview=s.character_previews[0];
 assert(preview.pixels[0]>=preview.logical[0]*1.95&&preview.pixels[1]>=preview.logical[1]*1.95,'Preview must match physical density');
 await tap('CloseBag');await tap('Title');await tap('GoFishing');await until(s=>s.phase==='ready','pond route',90000);s=await shot('06-pond-hd');assert.equal(s.avatar_indicator.visible,false,'Fishing hides indicator');
 await tap('FishingAction');await until(s=>['waiting','hook'].includes(s.phase),'cast accepted');await shot('07-cast');await tap('CloseFishing');await until(s=>s.phase==='closed','leave fishing');
 s=await shot('08-farm-return');assert.deepEqual(s.cells,before.cells);assert.equal(s.wallet,before.wallet);assert.deepEqual(s.bag,before.bag);
 const pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim(),log=(await adb(['logcat','-d','--pid',pid,'-s','godot'])).stdout.toString();await writeFile(out+'/godot.log',log);assert(!/SCRIPT ERROR|Parse Error|Compile Error|shader.*error/i.test(log));
 const result={passed:true,focused_pond_and_density:process.env.CLARITY_QA_POND_ONLY==='1',isolated_account:true,touches,directions:directions.map(x=>x[0]),onscreen_hidden:true,recenter_hides:true,saved_position_preserved:true,icons_96_pixels_24_logical:true,character_physical_density:true,five_column_bag:true,menu_checked:true,pond_route_and_server_cast:true,inventory_wallet_cells_preserved:true};await writeFile(out+(process.env.CLARITY_QA_POND_ONLY==='1'?'/pond-result.json':'/result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}catch(error){await shot('failure').catch(()=>{});await writeFile(out+'/failure.txt',String(error.stack??error));throw error}
