"""Three actual Android material views with two physical input tap commands."""
from pathlib import Path
import os,subprocess,time,json,hashlib
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/ground-detail-428/android'
OUT.mkdir(exist_ok=True);pkg='com.sensen.groundkit428qa'
adb=[os.environ['ADB'],'-s',os.environ['JOURNEY_SERIAL']]
def call(*a):return subprocess.check_output(adb+list(map(str,a)),stderr=subprocess.DEVNULL)
def state():
 s=json.loads(call('shell','run-as',pkg,'cat','files/ground_state.json'))
 assert str(s['pid'])==call('shell','pidof',pkg).decode().strip()
 return s
def wait(view):
 end=time.monotonic()+120
 while time.monotonic()<end:
  try:
   s=state()
   if s['view']==view and s['kit']=='428-v1':return s
  except (ValueError,AssertionError,subprocess.CalledProcessError):pass
  time.sleep(1)
 raise AssertionError('No fresh material view')
try:
 records=[]
 for i,name in enumerate(['default','grass','sand']):
  s=wait(i);assert s['renderer']=='mobile';time.sleep(3)
  (OUT/(name+'.png')).write_bytes(call('exec-out','screencap','-p'));records.append(s)
  if i<2:call('shell','input','tap',*map(round,s['button']))
 installed=call('shell','pm','path',pkg).decode().strip().removeprefix('package:')
 call('pull',installed,OUT/'installed.apk')
 source=OUT.parent/'ground-kit-qa.apk'
 h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 assert h(source)==h(OUT/'installed.apk')
 report={'passed':True,'scope':'static material rendering and two real view-button taps; no game integration or physical-phone performance result','states':records,'apk_sha256':h(source),'installed_apk_readback_equal':True}
 (OUT/'smoke.json').write_text(json.dumps(report,indent=2)+'\n')
 print('GROUND_KIT_ANDROID_PASS',flush=True)
finally:
 call('shell','wm','size','720x1280');call('shell','wm','density','reset')
