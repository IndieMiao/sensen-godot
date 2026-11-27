// node --test tools/dev/run_serial.test.mjs (C-216, C-217)
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,readFile,rm,symlink,chmod} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {requireEmulator,runEmulator,runSerial} from './run_serial.mjs';
const here=path.dirname(fileURLToPath(import.meta.url));
const fake=path.join(here,'../android/fixtures/fake_adb.mjs');
await chmod(fake,0o755);

const pick=(names,env,options={})=>{
  const warnings=[];
  return {serial:runSerial(names,{env,warn:w=>warnings.push(w),...options}),warnings};
};

test('outside a Run the explicit variable wins, then ANDROID_SERIAL',()=>{
  assert.deepEqual(pick(['JOURNEY_SERIAL'],{JOURNEY_SERIAL:'emulator-5558',ANDROID_SERIAL:'emulator-5600'}),{serial:'emulator-5558',warnings:[]});
  assert.deepEqual(pick(['JOURNEY_SERIAL'],{ANDROID_SERIAL:'emulator-5600'}),{serial:'emulator-5600',warnings:[]});
  assert.deepEqual(pick(['JOURNEY_SERIAL'],{}),{serial:undefined,warnings:[]});
});
test('in a Run a variable naming one of its devices wins',()=>{
  const run={ANDROID_SERIAL:'emulator-5600',CARDIGAN_EMULATOR_SERIAL:'emulator-5600',CARDIGAN_DEVICE_SERIAL:'R5CT000'};
  assert.deepEqual(pick(['JOURNEY_SERIAL'],{...run,JOURNEY_SERIAL:'R5CT000'}),{serial:'R5CT000',warnings:[]});
  assert.deepEqual(pick(['JOURNEY_SERIAL'],run),{serial:'emulator-5600',warnings:[]});
});
test('in a Run a leftover variable naming another device is ignored with a warning',()=>{
  assert.deepEqual(pick(['JOURNEY_SERIAL'],{JOURNEY_SERIAL:'10AFAF162200319',CARDIGAN_DEVICE_SERIAL:'R5CT000'}),
    {serial:'R5CT000',warnings:['JOURNEY_SERIAL=10AFAF162200319 is not a device of this Run; ignoring it.']});
  assert.deepEqual(pick(['JOURNEY_SERIAL'],{JOURNEY_SERIAL:'emulator-5558',CARDIGAN_EMULATOR_SERIAL:'emulator-5602',CARDIGAN_DEVICE_SERIAL:'R5CT000'},
    {host:['CARDIGAN_EMULATOR_SERIAL']}),
    {serial:'emulator-5602',warnings:['JOURNEY_SERIAL=emulator-5558 is not a device of this Run; ignoring it.']});
});
test('requireEmulator accepts emulators only',()=>{
  assert.equal(requireEmulator('emulator-5602'),'emulator-5602');
  for(const serial of ['R5CT000','10AFAF162200319','127.0.0.1:5555'])assert.throws(()=>requireEmulator(serial),/emulators only/);
});

test('runEmulator: JOURNEY_SERIAL, the Run\'s emulator, emulator-5560 only outside a Run',()=>{
  const emulator=env=>{const warnings=[];return {serial:runEmulator({env,warn:w=>warnings.push(w)}),warnings};};
  assert.deepEqual(emulator({}),{serial:'emulator-5560',warnings:[]});
  assert.deepEqual(emulator({JOURNEY_SERIAL:'emulator-5558'}),{serial:'emulator-5558',warnings:[]});
  assert.deepEqual(emulator({CARDIGAN_EMULATOR_SERIAL:'emulator-5602',CARDIGAN_DEVICE_SERIAL:'R5CT000'}),{serial:'emulator-5602',warnings:[]});
  assert.throws(()=>emulator({JOURNEY_SERIAL:'R5CT000'}),/R5CT000 is not an emulator/);
});
test('runEmulator: a Run holding only a phone has no emulator to fall back to',()=>{
  const warnings=[];
  for(const env of [{CARDIGAN_DEVICE_SERIAL:'R5CT000'},{ANDROID_SERIAL:'R5CT000',CARDIGAN_DEVICE_SERIAL:'R5CT000'},
    {JOURNEY_SERIAL:'emulator-5560',ANDROID_SERIAL:'R5CT000',CARDIGAN_DEVICE_SERIAL:'R5CT000'}]){
    assert.throws(()=>runEmulator({env,warn:w=>warnings.push(w)}),/This Run holds no emulator .*R5CT000.*does not fall back to emulator-5560/,JSON.stringify(env));
  }
  // The leftover JOURNEY_SERIAL=emulator-5560 is not this Run's either.
  assert.deepEqual(warnings,['JOURNEY_SERIAL=emulator-5560 is not a device of this Run; ignoring it.']);
});

async function runScript(t,script,extra,args=[]){
  const dir=await mkdtemp(path.join(tmpdir(),'sensen-run-serial-'));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  await symlink(fake,path.join(dir,'adb'));
  const log=path.join(dir,'adb.jsonl');
  const set={JOURNEY_SERIAL:undefined,ANDROID_SERIAL:undefined,CARDIGAN_EMULATOR_SERIAL:undefined,CARDIGAN_DEVICE_SERIAL:undefined,...extra};
  const env=Object.fromEntries(Object.entries({...process.env,PATH:`${dir}:${process.env.PATH}`,FAKE_ADB_LOG:log,...set}).filter(([,v])=>v!==undefined));
  // The scripts write under output/ in their working directory.
  const child=spawn(process.execPath,[path.join(here,script),...args],{cwd:dir,env,stdio:['ignore','pipe','pipe']});
  let output='';child.stdout.on('data',s=>output+=s);child.stderr.on('data',s=>output+=s);
  const code=await new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',resolve);});
  let rows=[];try{rows=(await readFile(log,'utf8')).trim().split('\n').filter(Boolean).map(JSON.parse);}catch(error){if(error.code!=='ENOENT')throw error;}
  return {code,output,rows};
}
for(const script of ['combat_emulator_qa.mjs','combat_latency_emulator_qa.mjs','movement_emulator_qa.mjs']){
  test(`${script} refuses a phone before touching adb`,async t=>{
    for(const set of [{JOURNEY_SERIAL:'R5CT000'},{JOURNEY_SERIAL:'R5CT000',ANDROID_SERIAL:'R5CT000',CARDIGAN_DEVICE_SERIAL:'R5CT000'}]){
      const s=await runScript(t,script,set);
      assert.notEqual(s.code,0,s.output);assert.match(s.output,/R5CT000 is not an emulator/);assert.deepEqual(s.rows,[]);
    }
  });
}
for(const script of ['combat_emulator_qa.mjs','combat_latency_emulator_qa.mjs','movement_emulator_qa.mjs']){
  test(`${script} in a Run holding only a phone stops without touching adb`,async t=>{
    const s=await runScript(t,script,{ANDROID_SERIAL:'R5CT000',CARDIGAN_DEVICE_SERIAL:'R5CT000'});
    assert.notEqual(s.code,0,s.output);assert.match(s.output,/This Run holds no emulator/);assert.deepEqual(s.rows,[]);
  });
}
test('mine_routes_emulator_qa.mjs refuses a phone before touching adb',async t=>{
  const s=await runScript(t,'mine_routes_emulator_qa.mjs',{JOURNEY_SERIAL:'R5CT000',JOURNEY_PACKAGE:'com.sensen.journeycombatqa'},['social']);
  assert.notEqual(s.code,0,s.output);assert.match(s.output,/R5CT000 is not an emulator/);assert.deepEqual(s.rows,[]);
});
test('online_android_qa.mjs uses the Run\'s device over a leftover JOURNEY_SERIAL',async t=>{
  // The fake adb rejects the first operation, so the script stops after it.
  const s=await runScript(t,'online_android_qa.mjs',{JOURNEY_SERIAL:'10AFAF162200319',ANDROID_SERIAL:'emulator-5600',CARDIGAN_EMULATOR_SERIAL:'emulator-5600'});
  assert.match(s.output,/JOURNEY_SERIAL=10AFAF162200319 is not a device of this Run; ignoring it\./);
  assert.deepEqual(s.rows,[['-s','emulator-5600','logcat','-c']]);
});
