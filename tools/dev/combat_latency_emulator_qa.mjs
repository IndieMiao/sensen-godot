import {execFile} from 'node:child_process';
import {promisify,isDeepStrictEqual} from 'node:util';
import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';

const execute=promisify(execFile);
const dir='output/combat-latency-emulator-2026-09-15';
const snapshot=async()=> (await fetch('http://127.0.0.1:3155/v1/qa/journey/scene')).json();
// The session's serial (run_test.sh), else this Run's emulator (C-212), else the local default.
const serial=process.env.JOURNEY_SERIAL||process.env.CARDIGAN_EMULATOR_SERIAL||'emulator-5560';
const adb=args=>execute('adb',['-s',serial,...args],{encoding:'buffer',timeout:30000,maxBuffer:8*1024*1024});
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const center=(s,name)=>{
  const node=[...s.controls,...(s.world?.controls??[])].find(n=>n.path===name||n.path.endsWith('/'+name));
  assert.ok(node&&!node.disabled,`Missing ${name}`);
  return [node.rect[0]+node.rect[2]/2,node.rect[1]+node.rect[3]/2].map(Math.round);
};
async function poll(test,seconds=25){
  const until=Date.now()+seconds*1000;
  while(Date.now()<until){const s=await snapshot();if(test(s))return s;await delay(200);}
  throw new Error('Timed out waiting for scene');
}
const mode=process.argv[2];
async function enterMine(){
  const s=await snapshot();
  if(s.scene==='/root/Farm'){
    const point=center(s,'body:mine_entrance').map(String);
    await adb(['shell','input','swipe',...point,...point,'100']);
  }
  return poll(s=>s.scene==='/root/Mine'&&s.world?.floor===5);
}
if(mode==='combat'){
  const before=await enterMine();
  assert.equal(before.world?.floor,5);
  const point=center(before,'MineAttack').map(String);
  let finished=false;
  const held=adb(['shell','input','swipe',...point,...point,'10000']).finally(()=>{finished=true;});
  const samples=[];
  while(!finished){samples.push(await snapshot());await delay(180);}
  await held;
  const after=await poll(s=>s.world?.combat?.pending===0&&!s.world?.combat?.sending);
  await writeFile(dir+'/combat-after.png',(await adb(['exec-out','screencap','-p'])).stdout);
  const proxy=await(await fetch('http://127.0.0.1:3156/latency')).json();
  const checks={observed_pending_hit:samples.some(s=>s.world?.combat?.sending&&s.world?.combat?.enemies?.slime_1?.hp!==s.state?.mine?.combat?.monsters?.['5']?.[0]),
    delay_injected:proxy.events.length>0&&proxy.events.every(e=>e.returned-e.upstream>=590),
    no_server_rejections:proxy.events.filter(e=>e.version>before.version).every(e=>e.status===200),
    survived:after.state.character.hp>1,
    defeated:after.state.mine.combat.monsters['5'][0]===0,
    prediction_reconciled:after.world.combat.pending===0&&after.world.combat.predicted_hp===after.state.character.hp};
  const report={passed:Object.values(checks).every(Boolean),checks,before,after,samples,proxy,artificial_fixture:true};
  await writeFile(dir+'/combat.json',JSON.stringify(report,null,2));
  console.log(JSON.stringify({passed:report.passed,checks,version:after.version,hp:after.state.character.hp}));
  if(!report.passed)process.exitCode=1;
}else if(mode==='rescue'){
  const before=await enterMine();
  assert.equal(before.state.character.hp,1);assert.equal(before.world?.floor,5);
  const after=await poll(s=>s.scene==='/root/Farm'&&s.controls.some(c=>c.path.endsWith('/RestCharacter')&&!c.disabled));
  const checks={auto_return:after.scene==='/root/Farm',character_page:after.controls.some(c=>c.path.endsWith('/RestCharacter')),
    possessions_preserved:isDeepStrictEqual(before.state.bag,after.state.bag),wallet_preserved:before.state.wallet===after.state.wallet,
    rescued_hp:after.state.character.hp===1,mine_outside:after.state.mine.floor===0};
  await writeFile(dir+'/rescue.png',(await adb(['exec-out','screencap','-p'])).stdout);
  await writeFile(dir+'/rescue.json',JSON.stringify({passed:Object.values(checks).every(Boolean),checks,before,after,artificial_fixture:true},null,2));
  console.log(JSON.stringify({passed:Object.values(checks).every(Boolean),checks,version:after.version}));
  if(!Object.values(checks).every(Boolean))process.exitCode=1;
}else throw new Error('Use combat or rescue');
