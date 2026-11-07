"""Private emulator: real taps select each asset; read back package and rendered pixels."""
from pathlib import Path
import hashlib,json,os,re,subprocess,time
from package_models import verify as verify_package
ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'output/homestead-440';DEST=OUT/'android';DEST.mkdir(exist_ok=True)
PKG='com.sensen.homestead440qa';ADB=[os.environ.get('ADB','/home/deck/Android/Sdk/platform-tools/adb'),'-s',os.environ.get('JOURNEY_SERIAL','emulator-5592')]
env=dict(os.environ,ADB_SERVER_SOCKET=os.environ.get('ADB_SERVER_SOCKET','tcp:127.0.0.1:5071'))
def call(*args):return subprocess.check_output(ADB+list(map(str,args)),env=env,stderr=subprocess.STDOUT)
def override(kind):
 data=call('shell','wm',kind).decode();m=re.search(r'Override .*?:\s*(\S+)',data);return m[1] if m else 'reset'
old_size=override('size');old_density=override('density')
def wait(asset,sequence):
 end=time.monotonic()+150
 while time.monotonic()<end:
  try:
   state=json.loads(call('shell','run-as',PKG,'cat','files/homestead_state.json'))
   if str(state['pid'])==call('shell','pidof',PKG).decode().strip() and state['asset']==asset and state['sequence']==sequence:return state
  except (ValueError,subprocess.CalledProcessError):pass
  time.sleep(1)
 raise AssertionError('No current-process rendered state for '+asset)
records=[]
try:
 call('install','-r',OUT/'homestead-qa.apk')
 call('shell','am','force-stop',PKG)
 call('shell','wm','size','360x800');call('shell','wm','density','160')
 call('shell','monkey','-p',PKG,'1')
 for seq,asset in enumerate(['house_cottage','master_farmhouse_a','master_farmhouse_b','house_cottage']):
  state=wait(asset,seq);assert state['renderer']=='mobile' and state['surfaces']==1 and state['assembled']
  (DEST/(asset+'-viewport.png')).write_bytes(call('exec-out','run-as',PKG,'cat','files/homestead-'+asset+'.png'))
  (DEST/(asset+'-screen.png')).write_bytes(call('exec-out','screencap','-p'))
  records.append(state);print('Rendered',asset,state['gpu'],flush=True)
  if seq<3:call('shell','input','tap',*state['button'])
 log=call('logcat','-d','--pid='+str(records[-1]['pid'])).decode(errors='replace');(DEST/'logcat.txt').write_text(log)
 assert not re.search(r'SCRIPT ERROR|Parse Error|VK_ERROR|Failed to load',log)
 path=call('shell','pm','path',PKG).decode().strip().removeprefix('package:');call('pull',path,DEST/'installed.apk')
 digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 assert digest(OUT/'homestead-qa.apk')==digest(DEST/'installed.apk')
 packaged=verify_package(DEST/'installed.apk',OUT/'android-project',ROOT)
 (DEST/'smoke.json').write_text(json.dumps({'passed':True,'states':records,'real_button_taps':3,'apk_sha256':digest(OUT/'homestead-qa.apk'),'installed_apk_readback_equal':True,'packaged_imported_models_match':packaged,'scope':'Dedicated asset fixture, API37 SwiftShader / Vulkan Mobile. Not a full-game or physical-phone test.'},indent=2)+'\n')
 print('HOMESTEAD_ANDROID_PASS',flush=True)
finally:
 call('shell','am','force-stop',PKG)
 call('shell','wm','size',old_size);call('shell','wm','density',old_density)
