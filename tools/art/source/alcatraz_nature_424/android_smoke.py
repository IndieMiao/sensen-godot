"""Run ONLY under tools/android/run_test.sh against the isolated QA package."""
from pathlib import Path
import subprocess,json,time,os,math
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/alcatraz-nature-424/android';OUT.mkdir(exist_ok=True)
pkg='com.sensen.alcatraznature424qa';adb=[os.environ.get('ADB','adb'),'-s',os.environ['JOURNEY_SERIAL']]
def call(*args):return subprocess.check_output(adb+list(map(str,args)))
def state():
 s=json.loads(call('shell','run-as',pkg,'cat','files/nature_state.json'))
 assert str(s['pid'])==call('shell','pidof',pkg).decode().strip()
 return s
def wait(predicate,timeout=60):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  try:
   s=state()
   if predicate(s):return s
  except (ValueError,AssertionError,subprocess.CalledProcessError):pass
  time.sleep(1)
 raise AssertionError('Timed out waiting for fresh observed state')
def capture(name):(OUT/(name+'.png')).write_bytes(call('exec-out','screencap','-p'))
def tap(point):call('shell','input','tap',int(point[0]),int(point[1]))
def gesture(*args):return call('shell','CLASSPATH=/data/local/tmp/alcatraz424-touch.dex','app_process','/','RoomTouch',*args).decode().strip()
try:
 before=wait(lambda s:s['revision']=='alcatraz-nature-424-v1' and s['assembled'] and s['navigation_ready'],140)
 time.sleep(4);capture('opening');checks=[]
 assert before['nature_instances']==114 and before['nature_batches']==9
 tap(before['walk_tap'])
 walked=wait(lambda s:math.dist(s['actor'],before['actor'])>.65)
 time.sleep(2);walked=state();capture('walk')
 checks.append('real tap moves assembled avatar on owner navigation')
 dex=Path(os.environ['NATURE_TOUCH_DEX']);call('push',dex,'/data/local/tmp/alcatraz424-touch.dex')
 drag=gesture('drag',180,320,235,355,1500,300)
 dragged=wait(lambda s:math.dist(s['focus'],walked['focus'])>.15)
 checks.append('real held drag moves camera focus')
 # Larger-span follow-up to the recorded 100-to-150 px failed gesture.
 # This is diagnostic, not a fix to the owner's unchanged controls.
 pinch=gesture('pinch',180,320,120,300,3000)
 try:
  pinched=wait(lambda s:s['zoom']>dragged['zoom']+.1,8);pinch_pass=True
 except AssertionError:
  pinched=state();pinch_pass=False
 checks.append('symmetric two-pointer pinch: '+('PASS' if pinch_pass else 'FAIL: no zoom change observed in owner whitebox'))
 tap(pinched['buttons']['ZoomOut'])
 button=wait(lambda s:s['zoom']<pinched['zoom']-.05);capture('touch')
 checks.append('real zoom-out button changes zoom')
 cmd=json.dumps({'seq':1,'view':'whole'}).encode()
 subprocess.run(adb+['shell',f"run-as {pkg} sh -c 'cat > files/nature_command.tmp && mv files/nature_command.tmp files/nature_command.json'"],input=cmd,check=True)
 whole=wait(lambda s:s['seq']==1);time.sleep(3);capture('whole')
 (OUT/'smoke.json').write_text(json.dumps({'passed':pinch_pass,'asset_render_smoke_passed':True,'checks':checks,'before':before,'walked':walked,'dragged':dragged,'pinched':pinched,'after_button':button,'whole':whole,'gesture_logs':[drag,pinch],'device':'API 37 software emulator; not physical phone','limitation':'Owner whitebox controls were not modified. Two earlier symmetric native pinch spans (100-150 and 120-300) left zoom at 1.0; preserve this integration follow-up.'},indent=2)+'\n')
 print('ALC_ANDROID_ASSET_SMOKE_PASS; ALL_INPUT_PASS',pinch_pass,checks,flush=True)
finally:
 call('shell','rm','-f','/data/local/tmp/alcatraz424-touch.dex')
 call('shell','wm','size','720x1280')
 call('shell','wm','density','reset')
