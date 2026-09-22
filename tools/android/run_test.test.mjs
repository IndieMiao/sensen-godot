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
  const child=spawn('bash',[path.join(here,'run_test.sh'),...args],{
    env:{...process.env,ADB:fake,FAKE_ADB_LOG:log,JOURNEY_SERIAL:'emulator-5560',...extra},stdio:['ignore','pipe','pipe']});
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
