import{execFile,spawn}from'node:child_process';import{promisify}from'node:util';import{mkdir,writeFile,readFile}from'node:fs/promises';import assert from'node:assert/strict';
const run=promisify(execFile),serial=process.env.JOURNEY_SERIAL,pkg=process.env.JOURNEY_PACKAGE,root='output/mine-art-video-2026-09-16';
const adb=args=>run('adb',['-s',serial,...args],{encoding:'buffer',maxBuffer:12e6,timeout:30000});
const delay=ms=>new Promise(r=>setTimeout(r,ms));const recordings=process.argv.includes('--finish')?JSON.parse(await readFile(root+'/timeline.json','utf8')):[];let rec=null,cmd=0;
async function state(){let error;for(let i=0;i<5;i++){try{return JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/mine-art/state.json'])).stdout)}catch(e){error=e;await delay(35)}}throw error}
async function until(check,label,ms=25000){const end=Date.now()+ms;let s;while(Date.now()<end){try{s=await state();if(check(s))return s}catch{}await delay(170)}if(s)await writeFile(root+'/private/failure-state.json',JSON.stringify(s,null,2));throw Error('Timeout: '+label)}
async function command(body){const request={id:String(++cmd),...body};const text=JSON.stringify(request);await adb(['shell','run-as',pkg,'sh','-c',`'printf %s ${JSON.stringify(text).replaceAll("'","'\\''")} > files/mine-art/command.tmp && mv files/mine-art/command.tmp files/mine-art/command.json'`]);await until(s=>s.last_command===request.id,'command '+body.op,6000)}
async function tapRect([x,y,w,h]){await adb(['shell','input','tap',String(Math.round(x+w/2)),String(Math.round(y+h/2))])}
async function button(name){await command({op:'reveal',name});const s=await until(s=>s.controls.some(c=>c.name===name&&!c.disabled),'button '+name);const b=s.controls.find(c=>c.name===name);assert(b.rect[1]>=0&&b.rect[1]+b.rect[3]<=1560,'Button inside screen');await tapRect(b.rect)}
async function start(label){assert(!rec);const n=recordings.length+1,file=`/sdcard/sensen-mine-art-${n}.mp4`;const child=spawn('adb',['-s',serial,'shell','screenrecord','--size','720x1560','--bit-rate','6000000','--time-limit','180',file],{stdio:'ignore'});const exit=new Promise(r=>child.once('exit',r));await delay(600);const pid=(await adb(['shell','pidof','screenrecord'])).stdout.toString().trim();assert(/^\d+$/.test(pid));rec={label,n,file,child,exit,pid,t0:Date.now()-600,events:[]};mark(label);await delay(1000)}
function mark(text){if(rec){const event={time:(Date.now()-rec.t0)/1000,text};rec.events.push(event);console.log(JSON.stringify({clip:rec.n,...event}))}}
async function stop(){if(!rec)return;const r=rec;rec=null;await adb(['shell','kill','-2',r.pid]).catch(()=>{});await r.exit;const local=`${root}/raw/clip-${String(r.n).padStart(2,'0')}.mp4`;await adb(['pull',r.file,local]);recordings.push({label:r.label,file:local,events:r.events});await writeFile(root+'/timeline.json',JSON.stringify(recordings,null,2))}
async function digFloor(floor){
 for(let i=0;i<6;i++){
  let s=await until(s=>s.floor===floor&&s.joined&&!s.busy&&s.can_act,'ready to mine');
  const rocks=s.targets.filter(t=>t.id.startsWith('rock_')).sort((a,b)=>Math.hypot(a.x-s.player[0],a.z-s.player[1])-Math.hypot(b.x-s.player[0],b.z-s.player[1]));
  if(!rocks.length)break;
  const rock=rocks[0];mark(i===0?'点击矿石：角色走近并开采，进度条完成后材料入包':'继续开采本层矿石');
  await command({op:'target',target:rock.id});
  await until(s=>s.floor===floor&&s.mine.broken[String(floor)]?.includes(rock.id),'rock mined',18000);
  await delay(i===0?1200:300);
 }
}
async function down(floor){mark('本层通行条件达成：前往梯子进入下一层');await command({op:'target',target:'down'});await until(s=>s.floor===floor+1&&s.joined,'descend to '+(floor+1),20000);await delay(1400)}
async function approachEnemy(enemy,s){
 const nav=s.navigation,cell=nav.cell,candidates=[];
 const walk=(x,z)=>nav.rows[Math.floor(-z/cell)]?.[Math.floor(x/cell)]==='1';
 const clear=(x,z)=>{const count=Math.ceil(Math.hypot(x-enemy.x,z-enemy.z)/(cell*.2));for(let i=0;i<=count;i++){const t=i/Math.max(1,count);if(!walk(x+(enemy.x-x)*t,z+(enemy.z-z)*t))return false}return true};
 for(let y=0;y<nav.rows.length;y++)for(let x=0;x<nav.rows[y].length;x++){
  if(nav.rows[y][x]!=='1')continue;const px=(x+.5)*cell,pz=-(y+.5)*cell,d=Math.hypot(px-enemy.x,pz-enemy.z);
  if(d<.8||d>1.25||!clear(px,pz))continue;
  candidates.push({x:px,z:pz,cost:Math.hypot(px-s.player[0],pz-s.player[1])+.2*d});
 }
 candidates.sort((a,b)=>a.cost-b.cost);assert(candidates.length,'Walkable attack approach exists');await command({op:'move',x:candidates[0].x,z:candidates[0].z});
}
async function fight(floor){
 await until(s=>s.floor===floor&&s.joined,'combat floor');
 mark(floor===5?'精英史莱姆：300 生命，预警后冲撞，不易被打断':'史莱姆进入警戒范围后靠近，蓄力预警并冲撞');
 const initial=await state();if(initial.enemies.length)await approachEnemy(initial.enemies[0],initial);await delay(1800);
 mark('持续攻击：挥剑时显示武器，命中扣血并反馈击退');await command({op:'attack',enabled:true});
 const end=Date.now()+40000;let lastMove=Date.now(),lastDodge=0;
 while(Date.now()<end){
  const s=await state();assert(s.floor===floor&&s.hp>0,'Player survived combat');
  if(s.mine.cleared_floors?.includes(floor)||!s.enemies.length){await command({op:'attack',enabled:false});mark('击败怪物获得掉落；第三、四层清完怪物即可下楼');await delay(2200);return}
  const nearest=s.enemies.reduce((a,b)=>Math.hypot(a.x-s.player[0],a.z-s.player[1])<Math.hypot(b.x-s.player[0],b.z-s.player[1])?a:b);
  if(Date.now()-lastMove>900&&Date.now()-lastDodge>900&&Math.hypot(nearest.x-s.player[0],nearest.z-s.player[1])>1.55){await approachEnemy(nearest,s);lastMove=Date.now()}
  if(floor===5&&nearest.phase==='windup'&&Date.now()-lastDodge>1100){
   const dx=s.player[0]-nearest.x,dz=s.player[1]-nearest.z,d=Math.hypot(dx,dz)||1,cell=s.navigation.cell;
   for(const sign of [1,-1]){const x=s.player[0]-dz/d*2*sign,z=s.player[1]+dx/d*2*sign;
    if(s.navigation.rows[Math.floor(-z/cell)]?.[Math.floor(x/cell)]==='1'){await command({op:'move',x,z});lastDodge=Date.now();break}}
  }
  await delay(200);
 }
 await writeFile(root+'/private/combat-stalled.json',JSON.stringify(await state(),null,2));throw Error('Combat did not finish');
}
await mkdir(root+'/raw',{recursive:true});await delay(1600);
for(let i=0;i<4;i++){await adb(['shell','uiautomator','dump','/sdcard/mine-art-dialog.xml']);const xml=(await adb(['exec-out','cat','/sdcard/mine-art-dialog.xml'])).stdout.toString();const nodes=xml.match(/<node\b[^>]+>/g)??[];const node=nodes.find(n=>/text="Don't Show Again"/.test(n))??nodes.find(n=>/text="OK"/.test(n)&&/clickable="true"/.test(n));if(!node)break;const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);await tapRect([+b[1],+b[2],+b[3]-b[1],+b[4]-b[2]]);await delay(600)}
const pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim();
try{
 let s=await until(s=>s.scene.endsWith('/farm.tscn')&&s.entrance?.[2]>0,'farm ready');
 if(process.argv.includes('--finish')){
  await start('04 战败恢复与再战通关');mark('战败后返回农场，生命降至 1；物品和通关进度保留');
  await command({op:'rescue'});await delay(3200);mark('在农场休息恢复生命，再次进入同一个矿井');await button('RestCharacter');await delay(2200);
  await command({op:'close_farm_bag'});s=await state();await tapRect(s.entrance);await until(s=>s.floor===1&&s.joined,'return to mine');
  for(let f=1;f<5;f++)await down(f);
  mark('再次挑战精英：边移动边攻击，躲开蓄力后的冲撞');await fight(5);
  mark('精英击败后，永久解锁第一层与第五层的电梯');await delay(2000);await command({op:'target',target:'elevator'});
  await until(s=>s.floor===1&&s.joined,'elevator to floor 1');await delay(3000);await command({op:'target',target:'up'});
  await until(s=>s.scene.endsWith('/farm.tscn'),'farm');mark('返回农场，本次矿井演示结束');await delay(2400);await stop();
 }else{
 await start('01 农场入口与采矿');await delay(2400);mark('农场中的矿洞模型就是入口');await tapRect(s.entrance);
 await until(s=>s.scene.endsWith('/online_mine.tscn')&&s.joined&&s.floor===1,'enter mine',25000);await delay(2200);
 mark('界面：生命与楼层在上方，摇杆、采矿和攻击在下方');await delay(2300);
 await digFloor(1);await down(1);mark('第二层继续采矿；矿石布局与掉落属于本次副本');await digFloor(2);await stop();
 await start('02 普通怪战斗与背包');await down(2);await fight(3);await down(3);await fight(4);
 mark('战斗后打开背包，查看矿物、装备和料理');await command({op:'bag'});await delay(1800);
 await command({op:'item',item:'vegetable_soup'});await delay(2300);
 mark('料理可以恢复生命，并提供有限次数的采矿加成');
 s=await state();const eat=s.controls.find(c=>c.name==='EatItem'&&!c.disabled);if(eat)await button('EatItem');
 await delay(1700);await command({op:'close_bag'});await delay(1500);await stop();
 await start('03 精英怪与永久电梯');await down(4);await fight(5);
 mark('击败第五层精英后，永久解锁第一层与第五层的电梯');await delay(2400);await command({op:'target',target:'elevator'});
 await until(s=>s.floor===1&&s.joined,'elevator to floor 1',25000);mark('乘电梯回到第一层；已开采的矿石与通关进度保留');await delay(3500);
 await command({op:'target',target:'up'});await until(s=>s.scene.endsWith('/farm.tscn'),'return to farm',25000);mark('返回农场，结束本次矿井演示');await delay(3000);await stop();
 }
 await writeFile(root+'/recording-result.json',JSON.stringify({passed:true,clips:recordings.length,real_gameplay:true,environment:'isolated local realtime server / Android emulator',equipment:['copper_sword','trail_boots','copper_pickaxe'],final:await state()},null,2));
 console.log('MINE_ART_RECORDING_PASSED');
}finally{await stop();await writeFile(root+'/private/runtime.log',(await adb(['logcat','-d','--pid',pid])).stdout)}
