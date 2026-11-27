// node --test tools/dev/dynamic_farm/crash_repro.test.mjs (C-216): the argument checks only; adb is /usr/bin/false.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const script=path.join(path.dirname(fileURLToPath(import.meta.url)),'crash_repro.sh');

async function run(t,args){
  const dir=await mkdtemp(path.join(tmpdir(),'sensen-crash-repro-'));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const child=spawn('bash',[script,'--port','5999','--serial','emulator-5600','--out',path.join(dir,'out'),...args],
    {env:{...process.env,ADB:'false'},stdio:['ignore','pipe','pipe']});
  let output='';child.stdout.on('data',s=>output+=s);child.stderr.on('data',s=>output+=s);
  const code=await new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',resolve);});
  return {code,output};
}
test('the default package and the dynamic farm packages pass the package check',async t=>{
  for(const args of [[],['--package','com.gensen.mapfarm'],['--package','com.gensen.mapfarm.internal'],['--package','com.sensen.gatherqa']]){
    // Past the checks the first adb call fails (exit 1), never the usage error (exit 2).
    const s=await run(t,args);
    assert.equal(s.code,1,`${args} ${s.output}`);assert.ok(!s.output.includes('Bad --package'),s.output);
  }
});
test('other packages are refused',async t=>{
  for(const name of ['com.gensen.other','com.gensen.mapfarm.internal.x','com.unrelated.app']){
    const s=await run(t,['--package',name]);
    assert.equal(s.code,2,s.output);assert.ok(s.output.includes('Bad --package'),s.output);
  }
});
