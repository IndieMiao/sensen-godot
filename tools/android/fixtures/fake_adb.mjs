#!/usr/bin/env node
import {appendFileSync,readFileSync} from 'node:fs';
const args=process.argv.slice(2);
appendFileSync(process.env.FAKE_ADB_LOG,JSON.stringify(args)+'\n');
const command=args.slice(2);
if(command[0]==='get-state')console.log('device');
else if(command.join(' ')==='shell pm list packages com.sensen.'){
  console.log('package:com.sensen.test\npackage:com.sensen.other\npackage:com.unrelated.app');
}else if(command.slice(0,5).join(' ')==='shell cmd package resolve-activity --brief'){
  console.log(command[5]+'/com.godot.game.GodotAppLauncher');
}else if(command.slice(0,4).join(' ')==='shell am start -W'){
  console.log(process.env.FAKE_LAUNCH_FAIL?'Error: unable to start':'Status: ok');
}else if(command.slice(0,3).join(' ')==='shell am force-stop'){
  const rows=readFileSync(process.env.FAKE_ADB_LOG,'utf8').trim().split('\n').map(JSON.parse);
  if(process.env.FAKE_CLEANUP_FAIL&&rows.filter(r=>r.includes('force-stop')).length>1)process.exitCode=1;
}else throw Error('Unexpected adb operation: '+JSON.stringify(args));
