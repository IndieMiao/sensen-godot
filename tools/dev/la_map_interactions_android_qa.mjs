import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const run=promisify(execFile),serial=process.env.JOURNEY_SERIAL,pkg=process.env.JOURNEY_PACKAGE;
assert(serial&&pkg==='com.sensen.journeyuiqa','Isolated map QA package only');
const out=process.env.JOURNEY_QA_OUTPUT??'output/la-map-interactions-2026-09-22/android';await mkdir(out,{recursive:true});
const adb=a=>run('adb',['-s',serial,...a],{encoding:'buffer',timeout:45000,maxBuffer:32e6});
const delay=ms=>new Promise(r=>setTimeout(r,ms));let last,touches=0,restoreSize='reset',sizeChanged=false;
const center=([x,y,w,h])=>[x+w/2,y+h/2];
const inside=([x,y],[rx,ry,rw,rh],pad=0)=>x>=rx+pad&&y>=ry+pad&&x<=rx+rw-pad&&y<=ry+rh-pad;
async function state(){
 for(let i=0;i<12;i++){
  try{const s=JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/game-ui-proof/state.json'])).stdout);
   if(!s.scene.includes('map_poc')||s.city)return last=s;
  }catch{}
  await delay(40);
 }
 throw Error('Incomplete observer snapshot');
}
async function until(test,label,ms=40000){const end=Date.now()+ms;while(Date.now()<end){try{const s=await state();if(!s.navigation_pending&&test(s))return s}catch{}await delay(150)}throw Error(label+': '+JSON.stringify({scene:last?.scene,error:last?.error,city:last?.city}))}
async function point(pos,label,wait=350){assert(pos.every(Number.isFinite));await writeFile(`${out}/touch-${++touches}.json`,JSON.stringify({label,point:pos}));await adb(['shell','input','tap',...pos.map(x=>String(Math.round(x)))]);await delay(wait)}
async function tap(id){const s=await until(s=>s.controls.some(c=>c.name===id&&!c.disabled),'control '+id);await point(center(s.controls.find(c=>c.name===id&&!c.disabled).bounds),id)}
async function shot(name){await delay(500);const s=await state();await writeFile(out+'/'+name+'.json',JSON.stringify(s,null,2));await writeFile(out+'/'+name+'.png',(await adb(['exec-out','screencap','-p'])).stdout);console.log('MAP_QA',name);return s}
async function back(){await adb(['shell','input','keyevent','4']);await delay(800)}
function noDrawer(s){assert(!s.city.sheets.neighbours);assert(!s.controls.some(c=>c.name==='MapNav_nearby'||c.path.includes('NearbyPanel')));assert(!s.city.farm_miniature)}
function player(s,excluded=''){
 const selected=s.city.players.find(p=>p.id===s.city.selected_player);
 return [...s.city.players].reverse().find(p=>p.id!=='self'&&p.id!==excluded&&p.portrait&&inside(center(p.bounds),s.city.map_area,40)&&(!selected||!inside(center(p.bounds),selected.bounds)));
}
async function swipe(from,to,label){await writeFile(`${out}/touch-${++touches}.json`,JSON.stringify({label,from,to}));await adb(['shell','input','swipe',...from.map(x=>String(Math.round(x))),...to.map(x=>String(Math.round(x))),'850']);await delay(1100)}
async function trace(name){await delay(1100);const data=JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/game-ui-proof/motion.json'])).stdout);await writeFile(`${out}/${name}.json`,JSON.stringify(data));assert(data.length>20);let count=0,max=0;for(const f of data){assert(f.actors.length<=1);for(const p of [...f.markers,...f.players,...f.actors]){if(!p.scale)assert(p.shown);assert(Number.isFinite(p.offset));max=Math.max(max,p.offset);assert(p.offset<0.01,`${name} ${p.id} moved ${p.offset}`);count++}}return {frames:data.length,projections:count,max_offset:max,data}}
try{
 const sizeText=(await adb(['shell','wm','size'])).stdout.toString();restoreSize=/Override size: (\d+x\d+)/.exec(sizeText)?.[1]??'reset';await writeFile(out+'/original-display.txt',sizeText);
 await delay(2500);await adb(['shell','uiautomator','dump','/sdcard/map-qa-start.xml']);const xml=(await adb(['exec-out','cat','/sdcard/map-qa-start.xml'])).stdout.toString();await writeFile(out+'/system-start.xml',xml);
 const dialog=(xml.match(/<node\b[^>]+>/g)??[]).find(x=>/text="(?:Don't Show Again|OK|确定)"/.test(x)&&/clickable="true"/.test(x));if(dialog){const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(dialog);assert(b);await point([(+b[1]+ +b[3])/2,(+b[2]+ +b[4])/2],'system dialog')}
 let s=await until(s=>s.city&&s.city.markers.some(m=>m.kind==='landmark')&&s.city.players.length>2,'city loaded',90000);
 const before={farm_id:s.farm_id,wallet:s.wallet,cells:structuredClone(s.cells),bag:structuredClone(s.bag)};
 noDrawer(s);assert.deepEqual(s.city.actors.map(a=>a.cohort),['self']);await shot('10-overview');
 let a=center(s.city.map_area);await swipe(a,[a[0]-65,a[1]+75],'overview drag');s=await state();assert.deepEqual(s.city.selected,{});assert.equal(s.city.selected_player,'');
 const overview=await trace('overview-motion');
 await tap('MapRecenter');await tap('MapZoom_minus');await tap('MapZoom_minus');
 for(let i=0;i<5;i++){
  s=await state();const choices=s.city.players.filter(p=>p.id!=='self');
  const middle=center(s.city.map_area),near=choices.sort((a,b)=>Math.hypot(...center(a.bounds).map((v,j)=>v-middle[j]))-Math.hypot(...center(b.bounds).map((v,j)=>v-middle[j])))[0];
  if(near&&inside(center(near.bounds),[middle[0]-180,middle[1]-180,360,360])&&player(s))break;
  if(!near){await tap('MapZoom_minus');continue}
  const dest=center(near.bounds),delta=middle.map((v,j)=>Math.max(-240,Math.min(240,v-dest[j])));
  await swipe(middle,middle.map((v,j)=>v+delta[j]),'explore towards visible player anchors');
 }
 s=await until(s=>!!player(s),'explorable player portrait');await shot('11-player-portraits');
 await delay(3200);s=await state();
 const first=player(s);assert(first);const pose={lat:s.map_pose.lat,lng:s.map_pose.lng,zoom:s.map_pose.zoom};
 const recording=adb(['shell','screenrecord','--time-limit','18','--bit-rate','4500000','/sdcard/map-interactions.mp4']);
 await delay(800);await point(center(first.bounds),'select player '+first.id,100);
 s=await until(s=>s.city.expanded_player===first.id&&s.city.actors.some(a=>a.cohort==='farm:'+first.id&&a.visible),'3D player popup');
 assert.equal(s.city.selected_player,first.id);assert.equal(s.map_pose.lat,pose.lat);assert.equal(s.map_pose.lng,pose.lng);assert.equal(s.map_pose.zoom,pose.zoom);
 assert.equal(s.city.players.find(p=>p.id===first.id).portrait,false);noDrawer(s);
 const pop=await trace('popup-motion');const scales=pop.data.flatMap(f=>f.actors.filter(a=>a.id==='farm:'+first.id).map(a=>a.scale));
 assert(scales.some(v=>v[1]<0.6),'popup starts compressed');assert(scales.some(v=>v[1]>1.08),'popup stretches');assert(scales.some(v=>v[0]>1.06&&v[1]<0.95),'popup squashes');assert(scales.some(v=>Math.abs(v[1]-1)<0.005),'popup settles');
 s=await shot('12-player-expanded');let second=player(s,first.id);if(!second){await tap('MapZoom_plus');s=await state();second=player(s,first.id)}assert(second,'second visible player');await point(center(second.bounds),'switch player '+second.id,50);
 s=await until(s=>s.city.expanded_player===second.id,'second selected');assert.equal(s.city.actors.filter(a=>a.cohort!=='self').length,1);assert(s.city.players.find(p=>p.id===first.id).portrait);
 a=center(s.city.players.find(p=>p.id===second.id).bounds);await swipe(a,[a[0]-55,a[1]+65],'drag starting on selected character');
 s=await state();assert.equal(s.city.selected_player,second.id);noDrawer(s);const drag=await trace('selected-drag-motion');await shot('13-selected-after-drag');
 await back();s=await until(s=>s.city&&s.city.selected_player==='','dismiss player');assert.equal(s.city.actors.length,1);await shot('14-portraits-restored');
 await recording;await adb(['pull','/sdcard/map-interactions.mp4',`${out}/map-interactions.mp4`]);
 await tap('MapLandmarkList');await tap('MapPlace_griffith_observatory');s=await until(s=>s.city.selected.id==='griffith_observatory','landmark detail');assert(s.city.selected.address);await shot('15-landmark-details');await tap('MapCloseInfo');
 await tap('MapRecenter');await tap('MapZoom_minus');await tap('MapFilter_food');s=await until(s=>s.city.markers.some(m=>m.kind==='poi'),'real dining POIs',90000);await shot('16-dining');
 a=center(s.city.map_area);await swipe(a,[a[0]+50,a[1]-70],'dense POI drag one');await swipe(a,[a[0]-55,a[1]+65],'dense POI drag two');const dining=await trace('dining-drag-motion');
 s=await state();const poi=s.city.markers.find(m=>inside(center(m.bounds),s.city.map_area,50)&&!s.city.players.some(p=>inside(center(m.bounds),p.bounds)));assert(poi);await point(center(poi.bounds),'basic POI details');s=await until(s=>s.city.selected.kind==='poi','POI selected');assert(!s.controls.some(c=>c.name==='MapVisitResident'));await shot('17-poi-details');
 await tap('MapCloseInfo');await tap('MapFilter_all');await tap('MapLandmarkList');await tap('MapPlace_restorer');await tap('MapVisitResident');await until(s=>s.scene.includes('/place/'),'NPC route');await shot('18-resident');for(let i=0;i<3;i++){await back();if((await state()).scene.includes('map_poc'))break}await until(s=>s.scene.includes('map_poc'),'map resumed');
 await tap('MapNav_outfit');await until(s=>s.scene.includes('dressing'),'outfit');await back();await until(s=>s.scene.includes('map_poc'),'outfit returned');await tap('MapNav_farm');await until(s=>s.scene.endsWith('/farm/farm.tscn'),'farm');await back();await until(s=>s.scene.includes('map_poc'),'farm returned');
 const profiles=[];
 for(const [size,vw,vh] of [['720x1280',360,640],['960x1280',480,640]]){sizeChanged=true;await adb(['shell','wm','size',size]);await until(s=>s.viewport[0]===vw&&s.viewport[1]===vh,'viewport '+size);await tap('MapNav_map');s=await shot('size-'+size);noDrawer(s);assert(s.city.markers.every(m=>m.offset<0.01));profiles.push({physical:size,logical:[vw,vh],no_drawer:true,anchored:true})}
 await adb(['shell','wm','size',restoreSize]);sizeChanged=false;await until(s=>s.viewport[0]===360&&s.viewport[1]===780,'restored viewport');await tap('MapNav_map');s=await shot('19-final-overview');
 assert.equal(s.farm_id,before.farm_id);assert.equal(s.wallet,before.wallet);assert.deepEqual(s.cells,before.cells);assert.deepEqual(s.bag,before.bag);
 const pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim(),log=(await adb(['logcat','-d','--pid',pid,'-s','godot','GodotMapPlugin'])).stdout.toString();await writeFile(out+'/runtime.log',log);assert(!/SCRIPT ERROR|Parse Error|Compile Error/.test(log));
 const summaries=[overview,pop,drag,dining].map(({data,...result})=>result);
 const result={passed:true,touches,default_self_only:true,selected_matching_3d:true,jelly_popup:true,selection_does_not_move_camera:true,drag_does_not_select:true,no_nearby_list_or_visit_route:true,projection_traces:summaries,live_mapbox_pois:s.city.poi_count,npc_poi_farm_outfit_routes:true,isolated_assets_preserved:true,profiles};await writeFile(out+'/result.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}catch(error){await shot('failure').catch(()=>{});await writeFile(out+'/failure.txt',String(error.stack??error));throw error}
finally{if(sizeChanged)await adb(['shell','wm','size',restoreSize])}
