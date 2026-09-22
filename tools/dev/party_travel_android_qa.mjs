import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir,writeFile } from 'node:fs/promises';
const run=promisify(execFile), serial=process.env.JOURNEY_SERIAL, pkg=process.env.JOURNEY_PACKAGE;
const root='output/party-travel-2026-09-16/android';
const adb=args=>run('adb',['-s',serial,...args],{encoding:'buffer',maxBuffer:16*1024*1024,timeout:30000});
await mkdir(root,{recursive:true});
await adb(['shell','uiautomator','dump','/sdcard/party-travel-qa.xml']);
const ui=(await adb(['exec-out','cat','/sdcard/party-travel-qa.xml'])).stdout.toString();
await writeFile(root+'/initial-ui.xml',ui);
for(const node of ui.match(/<node\b[^>]+>/g)??[]){
 if(!/text="(?:OK|确定|Continue|继续)"/.test(node)||!/clickable="true"/.test(node))continue;
 const b=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);
 if(b)await adb(['shell','input','tap',String(Math.round((+b[1]+ +b[3])/2)),String(Math.round((+b[2]+ +b[4])/2))]);
}
const started=Date.now();
while(Date.now()-started<100000){
 await new Promise(r=>setTimeout(r,1000));
 let result;
 try{result=JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/party-travel-proof/result.json'])).stdout.toString());}catch{continue;}
 if(!result.passed)throw new Error('Probe failed');
 const logs=(await adb(['logcat','-d','-s','godot'])).stdout.toString();
 await writeFile(root+'/godot.log',logs);
 for(const name of ['farm.png','street.png','mine3.png','confirmation.png','returned.png','result.json'])
  await writeFile(root+'/'+name,(await adb(['exec-out','run-as',pkg,'cat','files/party-travel-proof/'+name])).stdout);
 console.log(JSON.stringify(result));process.exit(0);
}
throw new Error('Party travel probe timed out');
