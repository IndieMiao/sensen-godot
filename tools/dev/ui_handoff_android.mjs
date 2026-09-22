import{execFile}from'node:child_process';import{promisify}from'node:util';import{mkdir,writeFile,readFile}from'node:fs/promises';
const run=promisify(execFile),serial=process.env.JOURNEY_SERIAL,pkg=process.env.JOURNEY_PACKAGE,root='output/ui-handoff-2026-09-16';
const adb=args=>run('adb',['-s',serial,...args],{encoding:'buffer',maxBuffer:16e6,timeout:30000});const delay=ms=>new Promise(r=>setTimeout(r,ms));
await mkdir(root+'/raw',{recursive:true});let last=0,lastAt=Date.now(),pid='',lastFile='',permissionSaved=false;
let previous=[];try{previous=JSON.parse(await readFile(root+'/catalog.json','utf8'))}catch{}
const merge=rows=>[...new Map([...previous,...rows].map(x=>[x.id,x])).values()].sort((a,b)=>a.id.localeCompare(b.id));
async function read(name){return JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/ui-handoff/'+name])).stdout)}
async function systemDialog(permission=false){await adb(['shell','uiautomator','dump','/sdcard/ui-handoff.xml']);const xml=(await adb(['exec-out','cat','/sdcard/ui-handoff.xml'])).stdout.toString();const nodes=xml.match(/<node\b[^>]+>/g)??[];const b=nodes.find(n=>/text="Don't Show Again"/.test(n))??nodes.find(n=>/text="(?:OK|Continue|确定|继续)"/.test(n)&&/clickable="true"/.test(n))??(permission&&nodes.find(n=>/resource-id="[^"]*permission_deny(?:_and_dont_ask_again)?_button"/.test(n)));if(!b)return false;if(permission&&/permission_deny(?:_and_dont_ask_again)?_button/.test(b)){await writeFile(root+'/private/microphone-permission.png',(await adb(['exec-out','screencap','-p'])).stdout);permissionSaved=true;}const m=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(b);await adb(['shell','input','tap',String(Math.round((+m[1]+ +m[3])/2)),String(Math.round((+m[2]+ +m[4])/2))]);return true}
await delay(1800);for(let i=0;i<5;i++){if(!await systemDialog())break;await delay(600)}
pid=(await adb(['shell','pidof','-s',pkg])).stdout.toString().trim();
try{
 while(true){
  let step;try{step=await read('step.json')}catch{}
  if(step&&step.serial!==last){
   if(!/^[\p{L}\p{N}_.-]+\.png$/u.test(step.file))throw Error('Invalid image name');
   await delay(150);
   await writeFile(root+'/raw/'+step.file,step.dismiss_permission&&permissionSaved?await readFile(root+'/private/microphone-permission.png'):(await adb(['exec-out','screencap','-p'])).stdout);
   if(step.dismiss_permission)await systemDialog(true);
   await adb(['shell','run-as',pkg,'sh','-c',`'echo ${Number(step.serial)} > files/ui-handoff/ack.txt'`]);
   last=step.serial;lastFile=step.file;lastAt=Date.now();console.log(last,step.file);
   try{await writeFile(root+'/catalog.json',JSON.stringify(merge(await read('catalog.json')),null,2))}catch{}
  }
  try{const done=await read('done.json');if(done.done){await writeFile(root+'/catalog.json',JSON.stringify(merge(await read('catalog.json')),null,2));await writeFile(root+'/capture-result.json',JSON.stringify(done,null,2));console.log(JSON.stringify(done));break}}catch{}
  if(lastFile==='87-copy-toast.png'&&Date.now()-lastAt>1500&&!permissionSaved)await systemDialog(true);
  if(Date.now()-lastAt>100000)throw Error('Capture stalled');
  await delay(150);
 }
}finally{await writeFile(root+'/private/runtime.log',(await adb(['logcat','-d','--pid',pid])).stdout);try{await writeFile(root+'/catalog.json',JSON.stringify(merge(await read('catalog.json')),null,2))}catch{}}
