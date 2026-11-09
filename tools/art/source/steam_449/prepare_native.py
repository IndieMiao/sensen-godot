"""Pin the programmer host and stage supplied cookreal fixture in an isolated project.
No host/runtime source is edited. Observer changes only QA render layers/recording.
"""
from pathlib import Path
import argparse,subprocess,tarfile,shutil,json,hashlib
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];REF='5d50bf0c2aa3868aba89b777a3c8a4925cdd15c9'
ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--fixture',type=Path,required=True);ap.add_argument('--shot-script',type=Path,required=True);ap.add_argument('--cache',type=Path);a=ap.parse_args();O=a.out.resolve();P=O/'project';P.mkdir(parents=True,exist_ok=True)
if not (O/'runtime-staged.json').exists():
 paths=['assets','modules','scenes','tests','addons','project.godot','icon.svg','server','package.json','pnpm-workspace.yaml','pnpm-lock.yaml','packages','tools/geo_blueprint/package.json']
 proc=subprocess.Popen(['git','archive',REF,*paths],cwd=ROOT,stdout=subprocess.PIPE)
 with tarfile.open(fileobj=proc.stdout,mode='r|') as ar:ar.extractall(P,filter='data')
 assert proc.wait()==0
 if a.cache:shutil.copytree(a.cache,P/'.godot',dirs_exist_ok=True)
 (O/'runtime-staged.json').write_text(json.dumps({'host_commit':REF},indent=2)+'\n')
shutil.copytree(ROOT/'assets/props/cooking_pot_wait',P/'assets/props/cooking_pot_wait',dirs_exist_ok=True)
(P/'assets/avatar/source/.gdignore').touch()
shutil.copy2(SRC/'native_observer.gd',P/'steam_live_observer.gd')
F=O/'fixtures';F.mkdir(exist_ok=True);shutil.copy2(a.fixture,F/'cookreal.base.json');shutil.copy2(a.shot_script,F/'shoot449.sh')
(P/'override.cfg').write_text('''[application]
config/name="Steam449NativeQA"
config/use_custom_user_dir=true
config/custom_user_dir_name="HuangzhongSteam449NativeQA"
run/main_scene="res://scenes/p0/p0_boot.tscn"
[editor_plugins]
enabled=PackedStringArray()
[display]
window/size/viewport_width=360
window/size/viewport_height=800
window/size/window_width_override=360
window/size/window_height_override=800
window/stretch/mode="disabled"
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
textures/vram_compression/import_etc2_astc=true
textures/vram_compression/import_s3tc_bptc=true
[sensen]
network/base_url="http://127.0.0.1:9/v1"
network/mobile_base_url="http://127.0.0.1:9/v1"
[autoload]
SteamLiveObserver="*res://steam_live_observer.gd"
''')
protected={}
for f in ['scenes/p0/kitchen/p0_wait_pot.gd','scenes/p0/kitchen/p0_wait_pot_layer.gdshader','scenes/p0/kitchen/p0_kitchen.gd']:
 data=subprocess.check_output(['git','show',REF+':'+f],cwd=ROOT);assert (P/f).read_bytes()==data;protected[f]=hashlib.sha256(data).hexdigest()
(O/'host-protected.json').write_text(json.dumps(protected,indent=2)+'\n')
print(P)
