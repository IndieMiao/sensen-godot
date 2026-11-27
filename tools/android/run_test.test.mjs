import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,readFile,rm,chmod} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const fake=path.join(here,'fixtures/fake_adb.mjs');
await chmod(fake,0o755);

async function scenario(t,args,extra={}){
  const dir=await mkdtemp(path.join(tmpdir(),'sensen-android-runner-'));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const log=path.join(dir,'adb.jsonl');
  // An undefined value in extra removes that variable from the runner's environment.
  const env=Object.fromEntries(Object.entries({...process.env,ADB:fake,FAKE_ADB_LOG:log,JOURNEY_SERIAL:'emulator-5560',...extra}).filter(([,v])=>v!==undefined));
  const child=spawn('bash',[path.join(here,'run_test.sh'),...args],{env,stdio:['ignore','pipe','pipe']});
  let output='';child.stdout.on('data',s=>output+=s);child.stderr.on('data',s=>output+=s);
  const finished=new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',(code,signal)=>resolve({code,signal}));});
  t.after(()=>{if(child.exitCode===null&&child.signalCode===null)child.kill('SIGKILL');});
  const rows=async()=>{try{return(await readFile(log,'utf8')).trim().split('\n').filter(Boolean).map(JSON.parse);}catch(error){if(error.code==='ENOENT')return[];throw error;}};
  return {child,finished,rows,output:()=>output};
}
const command=(script)=>['com.sensen.test','--',process.execPath,'-e',script];
const stops=rows=>rows.filter(r=>r[4]==='force-stop').map(r=>r[5]);

test('clean launch and normal completion preserve explicit arguments and device',async t=>{
  const s=await scenario(t,['--serial','emulator-5558',...command('console.log(process.env.JOURNEY_PACKAGE,process.argv[1])'),'two words']);
  assert.equal((await s.finished).code,0,s.output());
  const rows=await s.rows();assert.deepEqual(stops(rows),['com.sensen.test','com.sensen.test']);
  assert.ok(rows.every(r=>r[0]==='-s'&&r[1]==='emulator-5558'));
  assert.ok(s.output().includes('com.sensen.test two words'));
  assert.ok(rows.findIndex(r=>r[4]==='force-stop')<rows.findIndex(r=>r[4]==='start'));
});
const hostSerials={JOURNEY_SERIAL:undefined,DEV:undefined,ANDROID_SERIAL:undefined,CARDIGAN_EMULATOR_SERIAL:undefined,CARDIGAN_DEVICE_SERIAL:undefined};
for(const [name,set,expected] of [
  ['outside a Run an explicit JOURNEY_SERIAL wins over ANDROID_SERIAL',{JOURNEY_SERIAL:'emulator-5558',ANDROID_SERIAL:'emulator-5600'},'emulator-5558'],
  ['outside a Run DEV wins over ANDROID_SERIAL',{DEV:'emulator-5562',ANDROID_SERIAL:'emulator-5600'},'emulator-5562'],
  ['in a Run JOURNEY_SERIAL naming one of its devices wins',{JOURNEY_SERIAL:'R5CT000',ANDROID_SERIAL:'emulator-5600',CARDIGAN_EMULATOR_SERIAL:'emulator-5600',CARDIGAN_DEVICE_SERIAL:'R5CT000'},'R5CT000'],
  ['in a Run DEV naming one of its devices wins',{DEV:'emulator-5602',CARDIGAN_EMULATOR_SERIAL:'emulator-5602'},'emulator-5602'],
  ['ANDROID_SERIAL comes before the Cardigan serials',{ANDROID_SERIAL:'emulator-5600',CARDIGAN_EMULATOR_SERIAL:'emulator-5602',CARDIGAN_DEVICE_SERIAL:'R5CT000'},'emulator-5600'],
  ['CARDIGAN_EMULATOR_SERIAL comes before the device',{CARDIGAN_EMULATOR_SERIAL:'emulator-5602',CARDIGAN_DEVICE_SERIAL:'R5CT000'},'emulator-5602'],
  ['CARDIGAN_DEVICE_SERIAL alone selects the device',{CARDIGAN_DEVICE_SERIAL:'R5CT000'},'R5CT000'],
  ['without any serial the local default stays emulator-5560',{},'emulator-5560'],
]){
  test(`serial: ${name}`,async t=>{
    const s=await scenario(t,command('console.log("ON",process.env.JOURNEY_SERIAL)'),{...hostSerials,...set});
    assert.equal((await s.finished).code,0,s.output());
    const rows=await s.rows();assert.ok(rows.length>0&&rows.every(r=>r[0]==='-s'&&r[1]===expected),JSON.stringify(rows));
    assert.ok(s.output().includes(`ON ${expected}`),s.output());
    assert.ok(!s.output().includes('not a device of this Run'),s.output());
  });
}
for(const [name,set,expected,warnings] of [
  ['a leftover JOURNEY_SERIAL',{JOURNEY_SERIAL:'emulator-5558',ANDROID_SERIAL:'emulator-5600',CARDIGAN_EMULATOR_SERIAL:'emulator-5600'},'emulator-5600',['JOURNEY_SERIAL=emulator-5558']],
  ['a leftover DEV',{DEV:'10AFAF162200319',CARDIGAN_EMULATOR_SERIAL:'emulator-5602',CARDIGAN_DEVICE_SERIAL:'R5CT000'},'emulator-5602',['DEV=10AFAF162200319']],
  ['leftover JOURNEY_SERIAL and DEV',{JOURNEY_SERIAL:'emulator-5558',DEV:'emulator-5562',CARDIGAN_DEVICE_SERIAL:'R5CT000'},'R5CT000',['JOURNEY_SERIAL=emulator-5558','DEV=emulator-5562']],
]){
  test(`serial: in a Run ${name} outside its devices is ignored with a warning`,async t=>{
    const s=await scenario(t,command('console.log("ON",process.env.JOURNEY_SERIAL,process.env.ANDROID_SERIAL)'),{...hostSerials,...set});
    assert.equal((await s.finished).code,0,s.output());
    const rows=await s.rows();assert.ok(rows.length>0&&rows.every(r=>r[0]==='-s'&&r[1]===expected),JSON.stringify(rows));
    assert.ok(s.output().includes(`ON ${expected} ${expected}`),s.output());
    for(const warning of warnings)assert.ok(s.output().includes(`${warning} is not a device of this Run; ignoring it.`),s.output());
  });
}
test('a --serial outside the Run is used as given and handed to the scenario as ANDROID_SERIAL too',async t=>{
  const s=await scenario(t,['--serial','emulator-5604',...command('console.log("ON",process.env.JOURNEY_SERIAL,process.env.ANDROID_SERIAL)')],
    {...hostSerials,ANDROID_SERIAL:'emulator-5600',CARDIGAN_EMULATOR_SERIAL:'emulator-5600'});
  assert.equal((await s.finished).code,0,s.output());
  assert.ok((await s.rows()).every(r=>r[1]==='emulator-5604'));
  assert.ok(s.output().includes('ON emulator-5604 emulator-5604'),s.output());
  assert.ok(!s.output().includes('not a device of this Run'),s.output());
});
test('run_serial.sh: android_p0.sh SERIAL follows the same rule',async()=>{
  const pick=(set)=>new Promise((resolve,reject)=>{
    const env=Object.fromEntries(Object.entries({...process.env,...hostSerials,SERIAL:undefined,...set}).filter(([,v])=>v!==undefined));
    const child=spawn('bash',['-c','source "$0"; run_serial SERIAL',path.join(here,'run_serial.sh')],{env,stdio:['ignore','pipe','pipe']});
    let out='',err='';child.stdout.on('data',s=>out+=s);child.stderr.on('data',s=>err+=s);
    child.on('error',reject);child.on('exit',code=>resolve({code,out:out.trim(),err}));
  });
  assert.deepEqual(await pick({}),{code:0,out:'',err:''});
  assert.deepEqual(await pick({SERIAL:'emulator-5572',ANDROID_SERIAL:'emulator-5600'}),{code:0,out:'emulator-5572',err:''});
  assert.deepEqual(await pick({SERIAL:'emulator-5572',CARDIGAN_EMULATOR_SERIAL:'emulator-5602'}),
    {code:0,out:'emulator-5602',err:'SERIAL=emulator-5572 is not a device of this Run; ignoring it.\n'});
  assert.deepEqual(await pick({SERIAL:'R5CT000',CARDIGAN_DEVICE_SERIAL:'R5CT000'}),{code:0,out:'R5CT000',err:''});
});
test('--device selects CARDIGAN_DEVICE_SERIAL over every other serial and --serial still overrides it',async t=>{
  const set={...hostSerials,JOURNEY_SERIAL:'emulator-5558',ANDROID_SERIAL:'emulator-5600',CARDIGAN_DEVICE_SERIAL:'R5CT000'};
  for(const [args,expected] of [[['--device'],'R5CT000'],[['--device','--serial','emulator-5604'],'emulator-5604']]){
    const s=await scenario(t,[...args,...command('process.exit(0)')],set);
    assert.equal((await s.finished).code,0,s.output());
    assert.ok((await s.rows()).every(r=>r[1]===expected));
  }
  const s=await scenario(t,['--device',...command('process.exit(0)')],{...hostSerials,ANDROID_SERIAL:'emulator-5600'});
  assert.equal((await s.finished).code,2,s.output());assert.deepEqual(await s.rows(),[]);
  assert.ok(s.output().includes('CARDIGAN_DEVICE_SERIAL is not set'));
});
test('test failure propagates its exit code and stops the app',async t=>{
  const s=await scenario(t,command('process.exit(17)'));
  assert.equal((await s.finished).code,17,s.output());
  assert.deepEqual(stops(await s.rows()),['com.sensen.test','com.sensen.test']);
});
test('failed launch still cleans up and never runs the test',async t=>{
  const s=await scenario(t,command('console.log("SHOULD_NOT_RUN")'),{FAKE_LAUNCH_FAIL:'1'});
  assert.equal((await s.finished).code,1,s.output());
  assert.ok(!s.output().includes('SHOULD_NOT_RUN'));
  assert.deepEqual(stops(await s.rows()),['com.sensen.test','com.sensen.test']);
});
for(const [signal,code] of [['SIGINT',130],['SIGTERM',143],['SIGHUP',129]]){
  test(`${signal} interrupts the scenario and stops the app`,{timeout:7000},async t=>{
    const s=await scenario(t,command('console.log("READY",process.pid);setInterval(()=>{},1000)'));
    const deadline=Date.now()+4000;
    while(!s.output().includes('READY')&&Date.now()<deadline)await new Promise(r=>setTimeout(r,20));
    assert.ok(s.output().includes('READY'),s.output());
    const pid=Number(s.output().match(/READY (\d+)/)[1]);
    s.child.kill(signal);
    assert.equal((await s.finished).code,code,s.output());
    assert.deepEqual(stops(await s.rows()),['com.sensen.test','com.sensen.test']);
    assert.throws(()=>process.kill(pid,0),/ESRCH/);
  });
}
test('clean-all is scoped to Sensen packages and never closes the emulator',async t=>{
  const s=await scenario(t,['--clean-all']);
  assert.equal((await s.finished).code,0,s.output());
  assert.deepEqual(stops(await s.rows()),['com.sensen.test','com.sensen.other']);
});
test('cleanup failure is observable',async t=>{
  const s=await scenario(t,command('process.exit(0)'),{FAKE_CLEANUP_FAIL:'1'});
  assert.equal((await s.finished).code,1,s.output());assert.ok(s.output().includes('Cleanup failed'));
});
test('invalid package and noninteractive unbounded runs have no device side effects',async t=>{
  for(const args of [['com.unrelated.app','--wait','1'],['com.sensen.test'],['--wait','0','com.sensen.test']]){
    const s=await scenario(t,args);assert.equal((await s.finished).code,2,s.output());assert.deepEqual(await s.rows(),[]);
  }
});
