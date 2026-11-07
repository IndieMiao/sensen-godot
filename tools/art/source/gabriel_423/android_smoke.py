"""Dedicated offline emulator fixture: three real taps, animation and package readback."""
from pathlib import Path
import hashlib,json,os,re,subprocess,time,zipfile
R=Path(__file__).resolve().parents[4];O=R/'output/gabriel-423';D=O/'android';D.mkdir(exist_ok=True)
PKG='com.sensen.gabriel423qa';ADB=['/home/deck/Android/Sdk/platform-tools/adb','-s','emulator-5592'];env=dict(os.environ,ADB_SERVER_SOCKET='tcp:127.0.0.1:5071')
def call(*args):return subprocess.check_output(ADB+list(map(str,args)),env=env,stderr=subprocess.STDOUT)
def override(kind):
 m=re.search(r'Override .*?:\s*(\S+)',call('shell','wm',kind).decode());return m[1] if m else 'reset'
oldsize=override('size');olddensity=override('density')
def wait(seq):
 end=time.monotonic()+150
 while time.monotonic()<end:
  try:
   state=json.loads(call('shell','run-as',PKG,'cat','files/state.json'))
   if state['sequence']==seq and state['assembled'] and str(state['pid'])==call('shell','pidof',PKG).decode().strip():return state
  except (ValueError,subprocess.CalledProcessError):pass
  time.sleep(1)
 raise AssertionError('No rendered state for '+str(seq))
records=[]
try:
 call('install','-r',O/'gabriel-qa.apk');call('shell','am','force-stop',PKG)
 call('shell','wm','size','360x800');call('shell','wm','density','160');call('shell','monkey','-p',PKG,'1')
 for seq in range(4):
  state=wait(seq);records.append(state);assert state['renderer']=='mobile'
  (D/(str(seq)+'-viewport.png')).write_bytes(call('exec-out','run-as',PKG,'cat','files/viewport.png'))
  (D/(str(seq)+'-screen.png')).write_bytes(call('exec-out','screencap','-p'))
  print('GABRIEL_MOBILE',seq,state['gpu'],flush=True)
  if seq==2:
   time.sleep(3);nextstate=wait(seq);assert state['time']!=nextstate['time'];records.append(nextstate)
  if seq<3:call('shell','input','tap',*state['button'])
 log=call('logcat','-d','--pid='+str(records[-1]['pid'])).decode(errors='replace');(D/'logcat.txt').write_text(log)
 assert not re.search(r'SCRIPT ERROR|Parse Error|VK_ERROR|Failed to load',log)
 path=call('shell','pm','path',PKG).decode().strip().removeprefix('package:');call('pull',path,D/'installed.apk')
 digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 assert digest(O/'gabriel-qa.apk')==digest(D/'installed.apk')
 z=zipfile.ZipFile(D/'installed.apk');part='assets/avatar/parts/cloth1_npc_gabriel.res';key='assets/'+part
 assert z.read(key)==(R/part).read_bytes()
 tex=[n for n in z.namelist() if n.endswith('.ctex') and 'T_gabriel_cloth_D' in n];assert tex
 for n in tex:assert z.read(n)==(O/'mobile-project'/n.removeprefix('assets/')).read_bytes()
 (D/'smoke.json').write_text(json.dumps({'passed':True,'states':records,'real_button_taps':3,'walk_time_advanced':True,'apk_sha256':digest(O/'gabriel-qa.apk'),'installed_apk_readback_equal':True,'packed_part_and_texture_exact':True,'scope':'Offline asset fixture / API37 GFXStream SwiftShader / Vulkan Mobile. No physical-phone timing or full-game claim.'},indent=2)+'\n')
 print('GABRIEL_ANDROID_PASS',flush=True)
finally:
 call('shell','am','force-stop',PKG);call('shell','wm','size',oldsize);call('shell','wm','density',olddensity)
