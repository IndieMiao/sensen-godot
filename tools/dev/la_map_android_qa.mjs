import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const run=promisify(execFile),serial=process.env.JOURNEY_SERIAL,pkg=process.env.JOURNEY_PACKAGE;
assert(serial&&pkg==='com.sensen.journeyuiqa','Isolated map QA package only');
const out=process.env.JOURNEY_QA_OUTPUT??'output/la-map-2026-09-22/android';await mkdir(out,{recursive:true});
const adb=a=>run('adb',['-s',serial,...a],{encoding:'buffer',timeout:25000,maxBuffer:24e6});
const delay=ms=>new Promise(r=>setTimeout(r,ms));let last,touches=0;
const responsive=process.env.JOURNEY_QA_RESPONSIVE==='1';let restoreSize='reset',sizeChanged=false;
async function state(){return last=JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/game-ui-proof/state.json'])).stdout)}
async function until(test,label,ms=40000){const end=Date.now()+ms;while(Date.now()<end){try{const s=await state();if(!s.navigation_pending&&test(s))return s}catch{}await delay(250)}throw Error(label+': '+JSON.stringify({scene:last?.scene,error:last?.error,city:last?.city}))}
async function point(pos,label){assert(pos.every(Number.isFinite));await writeFile(`${out}/touch-${++touches}.json`,JSON.stringify({label,point:pos}));await adb(['shell','input','tap',...pos.map(x=>String(Math.round(x)))]);await delay(350)}
async function tap(id){const s=await until(s=>s.controls.some(c=>c.name===id&&!c.disabled),'control '+id);const[x,y,w,h]=s.controls.find(c=>c.name===id&&!c.disabled).bounds;assert(w>4&&h>4);await point([x+w/2,y+h/2],id)}
async function shot(name){await delay(700);const s=await state();await writeFile(out+'/'+name+'.json',JSON.stringify(s,null,2));await writeFile(out+'/'+name+'.png',(await adb(['exec-out','screencap','-p'])).stdout);console.log('MAP_QA',name);return s}
async function back(){await adb(['shell','input','keyevent','4']);await delay(800)}
function checkDrawer(s){
 const [x,y,w,h]=s.city.sheets.neighbour_bounds,[dx,dy,dw,dh]=s.city.ui_layout.dock;
 assert(x>=0&&y>=0&&x+w<=s.screen_bounds[2]+1);assert(y+h<=dy-14);
 const [cx,cy,cw,ch]=s.city.sheets.neighbour_close;assert(cx>=x&&cy>=y&&cx+cw<=x+w+1&&cy+ch<=y+h+1);
 assert(cw>=88&&ch>=88);assert(s.city.sheets.nav_neighbours);
}
try{
 if(responsive){const sizeText=(await adb(['shell','wm','size'])).stdout.toString();restoreSize=/Override size: (\d+x\d+)/.exec(sizeText)?.[1]??'reset';await writeFile(out+'/original-display.txt',sizeText)}
 await delay(2500);
 await adb(['shell','uiautomator','dump','/sdcard/map-qa-start.xml']);
 const xml=(await adb(['exec-out','cat','/sdcard/map-qa-start.xml'])).stdout.toString();await writeFile(out+'/system-start.xml',xml);
 const node=(xml.match(/<node\b[^>]+>/g)??[]).find(x=>/text="(?:Don't Show Again|OK|确定)"/.test(x)&&/clickable="true"/.test(x));
 if(node){const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);assert(b);await point([(+b[1]+ +b[3])/2,(+b[2]+ +b[4])/2],'system dialog')}
 let s=await until(s=>s.city&&s.city.status===''&&s.city.markers.length>1,'city loaded',90000);
 const before={farm_id:s.farm_id,version:s.version,wallet:s.wallet,cells:structuredClone(s.cells),bag:structuredClone(s.bag)};
 assert.deepEqual(s.city.actors.map(a=>a.cohort),['self']);assert(s.city.markers.some(m=>m.kind==='landmark'));
 await shot('10-city-overview');
 if(responsive){await tap('MapNav_nearby');s=await until(s=>s.city.sheets.neighbours,'neighbours opened');checkDrawer(s)}
 await tap('MapLandmarkList');await until(s=>s.city.list_visible,'places opened');await shot('11-places-list');
 if(responsive){s=await state();assert(!s.city.sheets.neighbours&&!s.city.sheets.nav_neighbours)}
 await tap('MapPlace_griffith_observatory');s=await until(s=>s.city.selected.id==='griffith_observatory'&&s.city.poi_count>0,'real POIs loaded',60000);
 assert(s.city.selected.address);await shot('12-observatory-selected');
 await tap('MapCloseInfo');await tap('MapRecenter');await until(s=>s.map_pose.zoom>=15,'street zoom');await tap('MapZoom_minus');await tap('MapFilter_food');s=await until(s=>s.city.filter==='food'&&s.city.markers.some(m=>m.kind==='poi'),'food filter with real restaurants',60000);await shot('13-dining-filter');
 assert(s.city.markers.every(m=>m.kind==='poi'));
 await tap('MapFilter_all');await tap('MapLandmarkList');await tap('MapPlace_restorer');s=await until(s=>s.city.selected.id==='restorer','NPC selected');await shot('14-resident-card');
 await tap('MapVisitResident');await until(s=>s.scene.includes('/place/'),'existing resident destination');await shot('15-resident-destination');
 for(let i=0;i<3;i++){await back();if((await state()).scene.includes('map_poc'))break}await until(s=>s.scene.includes('map_poc'),'map resumed');
 await tap('MapNav_map');await tap('MapNav_nearby');s=await shot('16-neighbours');
 const neighbour=s.controls.find(c=>c.path.includes('NearbyPanel')&&c.path.includes('ScrollContainer')&&c.bounds[2]>120&&c.bounds[3]>40&&!c.text);assert(neighbour);await tap(neighbour.name);
 s=await until(s=>s.controls.some(c=>/^(Visit|访问|拜访|参观)$/.test(c.text)&&!c.disabled&&c.bounds[2]>0),'visit enabled');
 await shot('16a-neighbour-preview');
 await tap(s.controls.find(c=>/^(Visit|访问|拜访|参观)$/.test(c.text)&&!c.disabled&&c.bounds[2]>0).name);await until(s=>s.scene.endsWith('/farm/farm.tscn'),'visitor farm');await shot('16b-visit-neighbour');await back();await until(s=>s.scene.includes('map_poc'),'visit returned');await tap('MapNav_map');
 await tap('MapNav_outfit');await until(s=>s.scene.includes('dressing'),'outfit opened');await shot('17-outfit');await back();await until(s=>s.scene.includes('map_poc'),'outfit returned');
 await tap('MapNav_farm');await until(s=>s.scene.endsWith('/farm/farm.tscn'),'farm opened');await shot('18-existing-farm');await back();await until(s=>s.scene.includes('map_poc'),'farm returned');
 await tap('MapNav_map');s=await state();
 const marker=s.city.markers.find(m=>m.kind==='landmark');assert(marker);const[x,y,w,h]=marker.bounds;
 await adb(['shell','input','swipe',String(Math.round(x+w/2)),String(Math.round(y+h/2)),String(Math.round(x+w/2-90)),String(Math.round(y+h/2+110)),'450']);await delay(900);s=await state();assert.deepEqual(s.city.selected,{});await shot('19-drag-no-selection');
 await tap('MapNav_map');await tap('MapLandmarkList');await tap('MapPlace_griffith_observatory');await shot('20-review-state');
 await tap('MapCloseInfo');await tap('MapNav_map');s=await until(s=>s.city.markers.some(m=>m.kind==='landmark'),'overview marker');
 const selectedMarker=s.city.markers.find(m=>m.kind==='landmark');const[mx,my,mw,mh]=selectedMarker.bounds;await point([mx+mw/2,my+mh/2],'select landmark on overview');await until(s=>s.city.selected.id===selectedMarker.id,'overview detail');await shot('21-overview-selected');
 const responsiveProfiles=[];
 if(responsive){
  for(const [size,vw,vh] of [['720x1280',360,640],['960x1280',480,640]]){
   sizeChanged=true;await adb(['shell','wm','size',size]);await until(s=>s.viewport[0]===vw&&s.viewport[1]===vh,'viewport '+size);await delay(600);
   await tap('MapNav_map');await tap('MapNav_nearby');s=await until(s=>s.city.sheets.neighbours,'resized neighbours');checkDrawer(s);
   const card=s.controls.find(c=>c.path.includes('NearbyPanel')&&c.path.includes('ScrollContainer')&&c.bounds[2]>120&&c.bounds[3]>40&&!c.text);assert(card);await tap(card.name);
   s=await until(s=>s.city.sheets.neighbour_preview&&s.controls.some(c=>/^(Visit|访问|拜访|参观)$/.test(c.text)&&!c.disabled),'resized preview');checkDrawer(s);await shot('size-'+size+'-neighbours');
   await tap('MapLandmarkList');s=await until(s=>s.city.list_visible&&!s.city.sheets.neighbours,'exclusive places');await shot('size-'+size+'-places');
   const[lx,ly,lw,lh]=s.city.sheets.list_bounds;assert(lx>=0&&ly>=0&&lx+lw<=s.screen_bounds[2]+1&&ly+lh<=s.screen_bounds[3]);
   await tap('MapPlace_restorer');s=await until(s=>s.city.selected.id==='restorer','resized resident');await shot('size-'+size+'-resident');
   const[ix,iy,iw,ih]=s.city.info_layout.bounds,[ax,ay,aw,ah]=s.city.sheets.info_action;assert(iy+ih<=s.city.ui_layout.dock[1]-14);assert(ax>=ix&&ay>=iy&&ax+aw<=ix+iw&&ay+ah<=iy+ih);assert(ah>=88);
   responsiveProfiles.push({physical:size,logical:[vw,vh],drawer_clear_of_navigation:true,resident_action_visible:true,sheets_exclusive:true});
  }
  await adb(['shell','wm','size',restoreSize]);sizeChanged=false;await until(s=>s.viewport[0]===360&&s.viewport[1]===780,'original viewport restored');await tap('MapNav_map');await shot('22-restored-overview');
  await writeFile(out+'/responsive.json',JSON.stringify({passed:true,profiles:responsiveProfiles,display_restored:true},null,2));
 }
 s=await state();assert.equal(s.farm_id,before.farm_id);assert.equal(s.wallet,before.wallet);assert.deepEqual(s.cells,before.cells);assert.deepEqual(s.bag,before.bag);
 const pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim(),log=(await adb(['logcat','-d','--pid',pid,'-s','godot','GodotMapPlugin'])).stdout.toString();await writeFile(out+'/runtime.log',log);assert(!/SCRIPT ERROR|Parse Error|Compile Error/.test(log));
 const result={passed:true,touches,single_3d_self:true,live_mapbox_pois:s.city.poi_count,landmark_info:true,npc_route:true,neighbours:true,visit_neighbour:true,outfit:true,farm:true,drag_does_not_select:true,isolated_assets_preserved:true,responsive_profiles:responsiveProfiles};await writeFile(out+'/result.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}catch(error){await shot('failure').catch(()=>{});await writeFile(out+'/failure.txt',String(error.stack??error));throw error}
finally{if(sizeChanged)await adb(['shell','wm','size',restoreSize])}
