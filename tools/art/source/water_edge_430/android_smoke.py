from pathlib import Path
import os,subprocess,time,json,hashlib
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/water-edge-430/android';OUT.mkdir(exist_ok=True)
pkg='com.sensen.wateredge430qa';adb=[os.environ['ADB'],'-s',os.environ['JOURNEY_SERIAL']]
def call(*a):return subprocess.check_output(adb+list(map(str,a)),stderr=subprocess.DEVNULL)
def wait(view,foam):
 end=time.monotonic()+120
 while time.monotonic()<end:
  try:
   s=json.loads(call('shell','run-as',pkg,'cat','files/water_edge_state.json'))
   assert str(s['pid'])==call('shell','pidof',pkg).decode().strip()
   if s['view']==view and s['foam']==foam and s['kit']=='430-v1':return s
  except (ValueError,AssertionError,subprocess.CalledProcessError):pass
  time.sleep(1)
 raise AssertionError('No fresh water-edge state')
records=[]
try:
 for i,(view,foam,name) in enumerate([(0,True,'default'),(1,True,'close'),(1,False,'control'),(1,True,'restored')]):
  s=wait(view,foam);assert s['renderer']=='mobile';time.sleep(2)
  (OUT/(name+'.png')).write_bytes(call('exec-out','screencap','-p'))
  (OUT/(name+'-viewport.png')).write_bytes(call('exec-out','run-as',pkg,'cat','files/water_edge_%d_%s.png'%(view,str(foam).lower())))
  records.append(s)
  if i<3:call('shell','input','tap',*s['button_view' if i==0 else 'button_foam'])
 path=call('shell','pm','path',pkg).decode().strip().removeprefix('package:');call('pull',path,OUT/'installed.apk')
 h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();apk=OUT.parent/'water-edge-qa.apk';assert h(apk)==h(OUT/'installed.apk')
 assert records[1]['draws']>records[2]['draws']
 (OUT/'smoke.json').write_text(json.dumps({'passed':True,'states':records,'apk_sha256':h(apk),'installed_apk_readback_equal':True,'scope':'API37 SwiftShader emulator, Mobile; 3 real button taps; not physical GPU performance'},indent=2)+'\n')
 print('WATER_EDGE_ANDROID_PASS',flush=True)
finally:
 call('shell','wm','size','720x1280');call('shell','wm','density','reset')
