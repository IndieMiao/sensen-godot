"""Isolated asset smoke under repository Android session runner; no player saves."""
from pathlib import Path
import subprocess,json,time,os,math
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/alcatraz-nature-424/android-v3';OUT.mkdir(exist_ok=True)
pkg='com.sensen.alcatraznature424qa';adb=[os.environ['ADB'],'-s',os.environ['JOURNEY_SERIAL']]
def call(*a):return subprocess.check_output(adb+list(map(str,a)),stderr=subprocess.DEVNULL)
def state():
 s=json.loads(call('shell','run-as',pkg,'cat','files/nature_state.json'));assert str(s['pid'])==call('shell','pidof',pkg).decode().strip();return s
def wait(pred,seconds=150):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  try:
   s=state()
   if pred(s):return s
  except (ValueError,AssertionError,subprocess.CalledProcessError):pass
  time.sleep(1)
 raise AssertionError('fresh Android state timeout')
def snap(n):(OUT/(n+'.png')).write_bytes(call('exec-out','screencap','-p'))
def tap(p):call('shell','input','tap',int(p[0]),int(p[1]))
try:
 before=wait(lambda s:s['revision']=='alcatraz-nature-424-v3' and s['assembled']);time.sleep(3);snap('dock-opening')
 assert before['instances']==114 and before['batches']==9 and before['renderer']=='mobile'
 tap(before['buttons']['ZoomOut']);out=wait(lambda s:s['zoom']<.9,30)
 tap(out['buttons']['ZoomIn']);back=wait(lambda s:abs(s['zoom']-1)<.001,30)
 snap('dock-after-input')
 next_seq=back['seq']+1;cmd=json.dumps({'seq':next_seq,'view':'assets'}).encode();subprocess.run(adb+['shell',f"run-as {pkg} sh -c 'cat > files/nature_command.tmp && mv files/nature_command.tmp files/nature_command.json'"],input=cmd,check=True)
 assets=wait(lambda s:s['seq']==next_seq and s['view']=='assets' and s['assembled']);time.sleep(3);snap('six-assets')
 (OUT/'smoke.json').write_text(json.dumps({'passed':True,'scope':'six rendered assets, native dock opening and two real zoom-button taps; not a full navigation/pinch or physical-phone performance test','before':before,'zoomed_out':out,'restored':back,'assets':assets},indent=2)+'\n')
 print('ALC_NATURE_ANDROID_V3_PASS',flush=True)
finally:
 call('shell','wm','size','720x1280');call('shell','wm','density','reset')
