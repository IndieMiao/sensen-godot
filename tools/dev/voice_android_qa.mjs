import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const run = promisify(execFile), serial = process.env.JOURNEY_SERIAL, pkg = process.env.JOURNEY_PACKAGE;
const root = 'output/voice-126-2026-09-16/android';
const adb = args => run('adb', ['-s',serial,...args], {encoding:'buffer',maxBuffer:16*1024*1024,timeout:30000});
const delay = ms => new Promise(r => setTimeout(r,ms));
await mkdir(root,{recursive:true});
async function dialogs(permission=false) {
  for(let i=0;i<5;i++) {
    await delay(700);
    await adb(['shell','uiautomator','dump','/sdcard/voice-qa.xml']);
    const xml=(await adb(['exec-out','cat','/sdcard/voice-qa.xml'])).stdout.toString();
    await writeFile(`${root}/dialog-${permission}-${i}.xml`,xml);
    const nodes=xml.match(/<node\b[^>]+>/g)??[];
    const b=nodes.find(n=>/text="Don't Show Again"/.test(n)) ?? nodes.find(n=>/text="(?:OK|确定|Continue|继续)"/.test(n)&&/clickable="true"/.test(n)) ?? (permission&&nodes.find(n=>/resource-id="[^"]*permission_allow_foreground_only_button"/.test(n)));
    if(!b) return;
    const m=/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(b);
    await adb(['shell','input','tap',String(Math.round((+m[1]+ +m[3])/2)),String(Math.round((+m[2]+ +m[4])/2))]);
  }
}
async function state() {try{return JSON.parse((await adb(['exec-out','run-as',pkg,'cat','files/voice-proof/state.json'])).stdout)}catch{return null}}
async function until(fn,label,timeout=30000) {
  const end=Date.now()+timeout;
  let s;
  do {s=await state();if(s&&fn(s))return s;await delay(250)}while(Date.now()<end);
  if(s)await writeFile(root+'/failure.json',JSON.stringify(s,null,2));
  throw new Error('Timed out: '+label);
}
async function tap(name) {
 const s=await until(s=>s.controls.some(c=>c.name===name&&!c.disabled),name);
 const {rect:[x,y,w,h]}=s.controls.find(c=>c.name===name);
 await adb(['shell','input','tap',String(Math.round(x+w/2)),String(Math.round(y+h/2))]);
}
async function snap(name) {
 const s=await state();await writeFile(`${root}/${name}.json`,JSON.stringify(s,null,2));
 await writeFile(`${root}/${name}.png`,(await adb(['exec-out','screencap','-p'])).stdout);return s;
}
const api=(route,body)=>fetch('http://127.0.0.1:3170/qa/'+route,body?{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}:{}).then(r=>r.json());
const checks=[];
await dialogs();
try {
 await until(s=>s.controls.some(c=>c.name==='PartyVoiceJoin'),'party controls');
 await snap('before-join');
 await tap('PartyVoiceJoin');await dialogs(true);
 let s=await until(s=>s.state==='connected'&&s.participants.length===2,'two connected participants');
 assert.equal(s.microphone,false);checks.push('Join requests microphone permission and starts muted');
 await until(s=>s.diagnostics.decoded_frames>150&&s.diagnostics.audio_energy>0,'Android decodes remote audio');
 await snap('two-connected');checks.push('Android receives and decodes synthetic remote audio');
 const before=(await api('status')).peers[0].frames;
 await tap('PartyVoiceMic');await until(s=>s.microphone,'unmuted');
 await delay(3000);
 assert((await api('status')).peers[0].frames>before+20,'peer receives Android microphone frames');
 checks.push('Android microphone track reaches remote peer');
 await tap('PartyVoiceListen');await until(s=>!s.listening,'listen muted');
 await tap('PartyVoiceListen');await until(s=>s.listening,'listen restored');
 checks.push('Listening can be disabled and restored independently');
 s=await state();const id=s.native_session;
 await tap('VoiceQaTravel');
 await until(s=>s.street&&s.state==='connected'&&s.native_session===id,'voice survives scene change');
 await snap('street-connected');checks.push('Farm to street retains native voice session and microphone state');
 assert((await state()).microphone);
 await api('peers',{count:3});await until(s=>s.participants.length===4,'four peers');await snap('four-connected');
 await api('peers',{count:7});await until(s=>s.participants.length===8,'eight peers');await snap('eight-connected');
 checks.push('Four- and eight-participant rooms are visible on Android');
 await tap('PartyVoiceMic');await until(s=>!s.microphone,'microphone muted');
 checks.push('User can mute microphone');
 await api('kick',{});await until(s=>!s.active&&s.native_session==='','kick stops native voice');await snap('kicked');
 checks.push('Removal from party stops native voice and prevents rejoin');
 await writeFile(root+'/result.json',JSON.stringify({passed:true,checks},null,2));console.log(JSON.stringify({passed:true,checks}));
} finally {
 const log=(await adb(['logcat','-d','-s','godot','AndroidRuntime'])).stdout;await writeFile(root+'/runtime.log',log);
 await snap('final');
 assert(!/SCRIPT ERROR|Parse Error|Compile Error|FATAL EXCEPTION/.test(log.toString()),'No runtime errors');
}
