import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {requireEmulator} from './run_serial.mjs';

const execute=promisify(execFile),mode=process.argv[2];
assert.ok(['social','monsters','rocks','boss','boss-finish'].includes(mode));
const serial=process.env.JOURNEY_SERIAL;
assert.ok(serial&&process.env.JOURNEY_PACKAGE,'Use tools/android/run_test.sh');
requireEmulator(serial);
const dir='output/mine-routes-emulator-2026-09-15';
await mkdir(dir,{recursive:true});
const boot=Date.now()/1000-5;
const adb=args=>execute('adb',['-s',serial,...args],{encoding:'buffer',timeout:30000,maxBuffer:8*1024*1024});
const snapshot=async()=> (await fetch(process.env.JOURNEY_SCENE_URL??'http://127.0.0.1:3157/v1/qa/journey/scene',{signal:AbortSignal.timeout(5000)})).json();
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const controls=s=>[...(s.controls??[]),...(s.world?.controls??[])];
async function poll(test,seconds=25){
  const until=Date.now()+seconds*1000;
  while(Date.now()<until){const s=await snapshot();if(test(s))return s;await delay(180);}
  throw Error('Timed out waiting for '+test.toString());
}
async function tapNode(s,c,duration=100){
  assert.ok(c&&!c.disabled,'Missing enabled control');
  const [x,y,w,h]=c.rect;
  const top=s.scene==='/root/MapPoc'&&y<96?Math.min(y+h-2,96):y;
  const p=[Math.round(x+w/2),Math.round((top+y+h)/2)].map(String);
  await adb(['shell','input',...(s.scene==='/root/MapPoc'&&duration===100?['tap',...p]:['swipe',...p,...p,String(duration)])]);
}
async function tap(key,duration=100){
  const s=await snapshot();
  const c=controls(s).find(c=>c.path===key||c.path.endsWith('/'+key));
  await tapNode(s,c,duration);
}
async function capture(name){await writeFile(`${dir}/${mode}-${name}.png`,(await adb(['exec-out','screencap','-p'])).stdout);}
const amount=(s,item)=>[...s.bag.slots,...s.bag.overflow,...Object.values(s.bag.equipped).filter(Boolean)]
  .filter(stack=>stack.item_id===item).reduce((n,stack)=>n+stack.quantity,0);
await adb(['shell','uiautomator','dump','/sdcard/sensen-qa-ui.xml']);
const uiFile=`${dir}/${mode}-native-ui.xml`;
await writeFile(uiFile,(await adb(['exec-out','cat','/sdcard/sensen-qa-ui.xml'])).stdout);
const title=(await execute('xmllint',['--xpath','string(//node[@resource-id="android:id/alertTitle"]/@text)',uiFile])).stdout;
if(title.trim()==='Android App Compatibility'){
  const bounds=(await execute('xmllint',['--xpath','string(//node[@resource-id="android:id/button1"]/@bounds)',uiFile])).stdout;
  const numbers=bounds.match(/\d+/g)?.map(Number);assert.equal(numbers?.length,4);
  await adb(['shell','input','tap',String(Math.round((numbers[0]+numbers[2])/2)),String(Math.round((numbers[1]+numbers[3])/2))]);
}
await poll(s=>s.scene==='/root/MapPoc'&&Number(s.launch_id)>boot);
await delay(1500);
if(mode==='social'){
  const before=await snapshot();
  const owner=controls(before).find(c=>c.button&&!c.disabled&&/^(My neighbourhood|我的街区)$/.test(c.tooltip));
  await tapNode(before,owner);
  let after;
  try{after=await poll(s=>s.social?.selected==='self'&&s.social.model_visible,5);}
  catch{await tapNode(await snapshot(),owner);after=await poll(s=>s.social?.selected==='self'&&s.social.model_visible);}
  const [x,y]=after.social.model_screen,[ownerX,ownerY]=after.social.owner_screen;
  const checks={right_of_owner:x>ownerX+100,beside_owner:Math.abs(y-ownerY)<200,model_visible:after.social.model_visible,
    selection_retained:after.social.selected==='self',save_unchanged:before.version===after.version};
  await capture('right');
  await writeFile(`${dir}/social.json`,JSON.stringify({passed:Object.values(checks).every(Boolean),checks,before,after},null,2));
  console.log(JSON.stringify({mode,checks}));assert.ok(Object.values(checks).every(Boolean));
}else{
  await tap('MyFarm');
  try{await poll(s=>s.scene==='/root/Farm',6);}catch{await tap('MyFarm');await poll(s=>s.scene==='/root/Farm');}
  await tap('body:mine_entrance');
  const before=await poll(s=>s.scene==='/root/Mine');
  const expected=mode==='monsters'?3:mode==='rocks'?4:5;
  assert.equal(before.world.floor,expected);
  const checks={};let after;
  if(mode==='rocks'){
    assert.equal(before.state.mine.broken['4'].length,5);
    for(let attempt=0;attempt<4;attempt++){
      await tap('body:rock_6');
      try{after=await poll(s=>s.state.mine.broken['4']?.includes('rock_6'),5);break;}catch(error){if(attempt===3)throw error;}
    }
    checks.live_monsters_preserved=after.state.mine.combat.monsters['4'].every(hp=>hp>0);
    checks.rocks_route_open=after.state.mine.cleared_floors.includes(4);
  }else{
    if(expected===5){
      checks.no_rocks=!controls(before).some(c=>c.path.startsWith('body:rock_'));
      const elite=before.world.combat.enemies.slime_1;
      checks.elite_attributes=elite.max_hp===300&&elite.move_speed===2.8&&elite.stun_resistant;
      if(mode==='boss')checks.full_health_arena=elite.hp===300;
    }
    await capture('before');
    for(let attempt=0;attempt<(mode==='monsters'?3:1);attempt++){
      await tap('MineAttack',mode==='monsters'?6500:5000);
      after=await poll(s=>s.ticks_ms>before.ticks_ms+1000&&!s.world?.busy&&!s.world?.combat?.sending&&!s.world?.combat?.pending);
      if(mode!=='monsters'||after.state.mine.combat.monsters[String(expected)].every(hp=>hp===0))break;
    }
    if(mode==='boss'){
      checks.combat_advances=after.state.mine.combat.monsters['5'][0]<300;
      checks.boss_still_required=after.state.mine.combat.monsters['5'][0]===0||!after.state.mine.cleared_floors.includes(5);
    }else{
      checks.defeated=after.state.mine.combat.monsters[String(expected)].every(hp=>hp===0);
      checks.monsters_route_open=after.state.mine.cleared_floors.includes(expected);
      checks.rocks_untouched=(after.state.mine.broken[String(expected)]??[]).length===0;
      const loot=after.state.mine.combat.last_result.loot;
      checks.random_loot=Object.keys(loot).length===1&&Object.keys(loot).every(item=>['seed_R','seed_L','copper_ore','rock_salt'].includes(item));
      checks.loot_received=Object.entries(loot).every(([item,n])=>amount(after.state,item)-amount(before.state,item)===n);
      if(expected===5)checks.elevator_unlocked=!before.state.mine.elevator_unlocked&&after.state.mine.elevator_unlocked;
    }
  }
  await capture('after');
  let descended=null;
  if(expected<5){
    await poll(s=>s.world?.can_act&&!s.world?.combat?.pending&&!s.world?.combat?.sending);
    await tap('MinePrimary');
    descended=await poll(s=>s.scene==='/root/Mine'&&s.world.floor===expected+1);
    checks.descended=descended.state.mine.floor===expected+1;
    await tap('PauseCombat');
  }else if(after.scene==='/root/Mine')await tap('PauseCombat');
  await writeFile(`${dir}/${mode}.json`,JSON.stringify({passed:Object.values(checks).every(Boolean),checks,before,after,descended,artificial_fixture:true},null,2));
  console.log(JSON.stringify({mode,checks,hp:after.state.character.hp,version:after.version}));
  assert.ok(Object.values(checks).every(Boolean));
}
