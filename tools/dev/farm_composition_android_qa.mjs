import{execFile}from'node:child_process';import{promisify}from'node:util';import{mkdir,writeFile,readFile}from'node:fs/promises';import assert from'node:assert/strict';
const run=promisify(execFile),serial=process.env.JOURNEY_SERIAL,pkg=process.env.JOURNEY_PACKAGE;
assert(serial&&pkg,'Use tools/android/run_test.sh');
const out='output/farm-composition-2026-09-18/android';await mkdir(out,{recursive:true});
const adb=args=>run('adb',['-s',serial,...args],{encoding:'buffer',maxBuffer:16*1024*1024,timeout:20000});const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function state(){for(let n=0;n<60;n++){try{let s=JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/free-farm-proof/state.json'])).stdout);if(s.cell_m===.75&&s.hard_zone_screen)return s;}catch{}await delay(200);}throw Error('Missing current composition probe');}
const center=([x,y,w,h])=>[x+w/2,y+h/2];
async function capture(name){let s=await state();await writeFile(`${out}/${name}.json`,JSON.stringify(s,null,2));await writeFile(`${out}/${name}.png`,(await adb(['exec-out','screencap','-p'])).stdout);return s;}
async function reset(){await adb(['shell','run-as',pkg,'sh','-c',"'echo reset > files/free-farm-proof/command'"]);await delay(350);return state();}
await delay(1800);
for(let attempt=0;attempt<4;attempt++){
 await adb(['shell','uiautomator','dump','/sdcard/composition-ui.xml']);const xml=(await adb(['exec-out','cat','/sdcard/composition-ui.xml'])).stdout.toString();await writeFile(`${out}/startup-${attempt}.xml`,xml);
 const n=(xml.match(/<node\b[^>]+>/g)??[]).find(n=>/text="(?:Don't Show Again|OK|确定|Continue|继续)"/.test(n)&&/clickable="true"/.test(n));if(!n)break;
 const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(n);assert(b);await adb(['shell','input','tap',String(Math.round((+b[1]+ +b[3])/2)),String(Math.round((+b[2]+ +b[4])/2))]);await delay(500);
}
let s=await capture('default');const checks=[];
assert(Math.abs(s.tile_ratio-1.5)<.005);assert.deepEqual(s.player_scale,[1,1,1]);assert.equal(s.camera_size,6);
const baseline=JSON.parse(await readFile('output/free-farm-2026-09-17/android/default.json','utf8'));
const oldPng=await readFile('output/free-farm-2026-09-17/android/default.png');const beforeHeight=(baseline.feet[1]-baseline.head[1])/oldPng.readUInt32BE(16);
assert(Math.abs((s.feet[1]-s.head[1])/s.viewport_rect[2]-beforeHeight)<.002);
checks.push('Tiles project at 1.5x the old width; avatar scale and projected height are unchanged');
const viewCenter=center(s.viewport_rect);
for(const key of ['dead_zone_screen','hard_zone_screen'])assert(Math.hypot(...center(s[key]).map((v,i)=>v-viewCenter[i]))<1);
for(const key of ['mine','house','well','storage']){const[x,y]=s[key],[vx,vy,vw,vh]=s.viewport_rect;assert(x>vx&&x<vx+vw&&y>vy&&y<vy+vh,key+' is visible at startup');}
checks.push('House, mine, well and storage are visible in the initial viewport');
const edges={};
for(const [name,dx,dy] of [['up',0,-1],['down',0,1],['left',-1,0],['right',1,0]]){
 s=await reset();const[x,y,w,h]=s.play_area;const from=[x+w/2,y+h/2];const to=[from[0]+dx*(w/2-28),from[1]+dy*(h/2-28)];
 for(let pass=0;pass<2;pass++)await adb(['shell','input','swipe',...from.map(v=>String(Math.round(v))),...to.map(v=>String(Math.round(v))),'350']);
 await delay(400);s=await capture('pan-'+name);const[hx,hy,hw,hh]=s.hard_zone_screen;
 if(dy)assert(Math.abs(s.focus[1]-(dy<0?hy:hy+hh))<2.5,name+' reaches the symmetric vertical limit');
 if(dx)assert(Math.abs(s.focus[0]-(dx<0?hx:hx+hw))<2.5,name+' reaches the symmetric horizontal limit');
 assert.equal(s.requests.length,0);edges[name]=s.focus;
}
assert(Math.abs((edges.up[1]+edges.down[1])/2-viewCenter[1])<2);
assert(Math.abs((edges.left[0]+edges.right[0])/2-viewCenter[0])<2);
checks.push('Real touch pans reach matching top/bottom and left/right margins without farming');
await reset();
const pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim();const log=(await adb(['logcat','-d','--pid',pid,'-s','godot'])).stdout;await writeFile(out+'/godot.log',log);assert(!/SCRIPT ERROR|Parse Error|Compile Error|shader.*error/i.test(log.toString()));
await writeFile(out+'/result.json',JSON.stringify({passed:true,checks,edges},null,2));console.log(JSON.stringify({passed:true,checks}));
