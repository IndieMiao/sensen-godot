import {execFile} from 'node:child_process';import{promisify}from'node:util';import{mkdir,readFile,writeFile}from'node:fs/promises';import assert from'node:assert/strict';
const run=promisify(execFile),serial=process.env.JOURNEY_SERIAL,pkg=process.env.JOURNEY_PACKAGE;assert(serial&&pkg);
const out=process.env.EQUIPMENT_QA_RESULTS??'output/equipment-2026-09-19/android';await mkdir(out+'/private',{recursive:true});
const adb=args=>run('adb',['-s',serial,...args],{encoding:'buffer',timeout:20000,maxBuffer:20*1024*1024});const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function state(){return JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/equipment-proof/state.json'])).stdout);}
async function waitFor(predicate,label,timeout=30000){let s;const until=Date.now()+timeout;while(Date.now()<until){try{s=await state();if(predicate(s))return s;}catch{}await delay(100);}throw Error(label+': '+JSON.stringify(s));}
const visible=c=>c&&!c.disabled&&c.bounds[2]>18&&c.bounds[3]>18;
async function press(bounds){const[x,y,w,h]=bounds;await adb(['shell','input','tap',String(Math.round(x+w/2)),String(Math.round(y+h/2))]);await delay(180);}
async function scroll(down){const s=await state(),c=s.scrolls.find(c=>c.name==='BagScroll');assert(c,'No inventory scroll surface');const[x,y,w,h]=c.bounds;await adb(['shell','input','swipe',String(Math.round(x+w*.65)),String(Math.round(y+h*(down ? .65 : .43))),String(Math.round(x+w*.65)),String(Math.round(y+h*(down ? .43 : .65))),'750']);await delay(500);}
async function tap(name){for(let i=0;i<10;i++){const s=await state(),c=s.controls.find(c=>c.name===name&&visible(c));if(c){await press(c.bounds);return;}if(i===0)await delay(250);else await scroll(true);}throw Error('Missing visible control '+name);}
async function character(){const s=await state();if(!s.controls.some(c=>c.name==='BagPage_character'&&visible(c)))await tap(s.scene.includes('mine/')?'OpenBag':'LifeButton');await tap('BagPage_character');for(let i=0;i<6;i++){if((await state()).scrolls.find(c=>c.name==='BagScroll')?.offset===0)break;await scroll(false);}}
async function closeBag(){for(let i=0;i<4;i++){const s=await state();if(!s.controls.some(c=>c.name==='BagPage_character'))return;await adb(['shell','input','keyevent','4']);await delay(300);}throw Error('Bag did not close');}
async function equip(id,slot){if((await state()).bag.equipped[slot]?.item_id===id)return;await character();await tap('ChangeEquipment_'+slot);const s=await state(),item=s.bag.slots.find(x=>x.item_id===id);assert(item,'Missing owned '+id);await tap('ChooseEquipment_'+item.id);await tap(slot.startsWith('ring_')?'EquipTo_'+slot:'EquipTool');await waitFor(s=>s.bag.equipped[slot]?.item_id===id,'Equip failed: '+id);}
async function capture(name){const s=await state();await writeFile(out+'/private/'+name+'.json',JSON.stringify(s,null,2),{mode:0o600});await writeFile(out+'/'+name+'.png',(await adb(['exec-out','screencap','-p'])).stdout);return s;}
async function world(name){for(let i=0;i<18;i++){const s=await state();if(s.world_targets?.[name]?.[2]>15){await press(s.world_targets[name]);return;}if(name==='mine'&&s.world_targets.mine_waypoint){await press(s.world_targets.mine_waypoint);await delay(300);await waitFor(s=>!s.moving,'Walking to mine stalled',15000);await delay(300);}else await delay(300);}throw Error('Missing world target '+name);}
async function mineRock(id){await world(id);await waitFor(s=>s.busy,'Dig did not begin',20000);const start=Date.now();await waitFor(s=>!s.busy&&s.world.rocks.some(r=>r.id===id&&r.broken),'Rock did not settle',15000);return Date.now()-start;}
try{
 await delay(2200);await adb(['shell','uiautomator','dump','/sdcard/equipment-ui.xml']);const xml=(await adb(['exec-out','cat','/sdcard/equipment-ui.xml'])).stdout.toString();await writeFile(out+'/startup.xml',xml);
 const node=(xml.match(/<node\b[^>]+>/g)??[]).find(n=>/text="(?:Don't Show Again|OK|确定|Continue|继续)"/.test(n)&&/clickable="true"/.test(n));if(node){const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);await press([+b[1],+b[2],+b[3]-b[1],+b[4]-b[2]]);}
 await delay(700);let s=await waitFor(s=>s.joined&&s.scene.includes('farm/farm'),'Farm not ready');assert.equal(s.bag.version,2);assert.equal(s.bag.equipped.fishing_rod.item_id,'starter_fishing_rod');
 await character();s=await capture('six-slots');assert.deepEqual(s.slots,['main_hand','fishing_rod','ring_1','ring_2','necklace','gloves']);
 for(const slot of s.slots)assert(s.controls.some(c=>c.name==='CharacterSlot_'+slot));
 await tap('UnequipSlot_fishing_rod');await waitFor(s=>s.bag.equipped.fishing_rod===null,'Rod did not unequip');await closeBag();await tap('GoFishing');
 s=await waitFor(s=>s.labels.some(x=>x.includes('装备鱼竿')),'Missing rod explanation');assert.equal(s.phase,'closed');await capture('rod-required');
 await equip('starter_fishing_rod','fishing_rod');await closeBag();await tap('GoFishing');await waitFor(s=>s.phase==='ready','Rod did not unlock fishing');await tap('FishingAction');await waitFor(s=>s.phase==='waiting','Cast failed');await capture('rod-equipped-cast');await tap('CloseFishing');await waitFor(s=>s.phase==='closed','Cast cancel failed');
 for(const[id,slot]of[['copper_ring','ring_1'],['wooden_ring','ring_2'],['copper_necklace','necklace'],['artisan_apron','gloves']])await equip(id,slot);
 await character();await capture('rings-necklace-gloves');
 await equip('copper_axe','main_hand');s=await capture('axe-attributes');assert.equal(s.hand_stats.wood_power,2);assert.equal(s.hand_stats.damage,10);
 await equip('rusty_sword','main_hand');s=await capture('sword-attributes');assert.equal(s.hand_stats.damage,14);assert(s.bag.slots.some(x=>x.item_id==='copper_axe'));
 await equip('hand_tools','main_hand');await closeBag();await world('mine');await waitFor(s=>s.joined&&s.scene.includes('mine/'),'Mine not ready');await capture('mine-basic-tool');
 const slow=await mineRock('rock_1');await capture('basic-tool-mined');
 await equip('copper_pickaxe','main_hand');s=await capture('pickaxe-attributes');assert.equal(s.hand_stats.ore_power,2);assert.equal(s.hand_stats.damage,7);await closeBag();
 const fast=await mineRock('rock_2');await capture('pickaxe-mined');assert(slow>1300,`Basic tools must take roughly 2 seconds: ${slow}`);assert(fast<slow*.65,`Pickaxe must be materially faster: ${fast} vs ${slow}`);
 s=await state();assert.equal(s.bag.equipped.fishing_rod.item_id,'starter_fishing_rod');assert.equal(s.bag.equipped.ring_1.item_id,'copper_ring');assert.equal(s.bag.equipped.ring_2.item_id,'wooden_ring');
 const result={passed:true,version:'0.16.2',slots:s.slots,rod_required:true,rod_cast:true,independent_rings:true,main_hand_swaps:true,server_mining_ms:{hand_tools:slow,copper_pickaxe:fast}};await writeFile(out+'/result.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}finally{const pid=(await adb(['shell','pidof','-s',pkg]).catch(()=>({stdout:Buffer.from('')}))).stdout.toString().trim();if(pid)await writeFile(out+'/app.log',(await adb(['logcat','-d','--pid',pid,'-s','godot','Godot'])).stdout);}
