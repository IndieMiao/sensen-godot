"""Stage an isolated actual P0 farm. All preview patches remain under output/."""
from pathlib import Path
import argparse,json,shutil,subprocess,tarfile,hashlib
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent;QA=ROOT/'output/homestead-439';P=QA/'project'
parser=argparse.ArgumentParser();parser.add_argument('--runtime-ref',default='8493a5c4');args=parser.parse_args()
P.mkdir(parents=True,exist_ok=True);(ROOT/'output/.gdignore').touch()
if not (QA/'stage.json').exists():
 head=subprocess.check_output(['git','rev-parse',args.runtime_ref],cwd=ROOT,text=True).strip()
 proc=subprocess.Popen(['git','archive',head],cwd=ROOT,stdout=subprocess.PIPE)
 with tarfile.open(fileobj=proc.stdout,mode='r|') as ar:ar.extractall(P,filter='data')
 assert proc.wait()==0
 (P/'docs/.gdignore').touch();(P/'tools/art/source/.gdignore').touch()
 # A verified local cache speeds import; source files always come from runtime git.
 cache=Path('/home/zhangshaoji/.herdr/worktrees/sensen-godot/zy-badge-401/output/badge-401/project/.godot')
 if cache.exists() and not (P/'.godot').exists():subprocess.run(['cp','-a','--reflink=auto',str(cache),str(P/'.godot')],check=True)
 preserved={s:hashlib.sha256((P/s).read_bytes()).hexdigest() for s in ['modules/p0/p0_garden.gd','scenes/p0/p0_farm.gd','scenes/p0/p0_garden_scenery.gd','modules/farm/farm_art.gd','assets/farm/art/house_cottage.glb']}
 (QA/'stage.json').write_text(json.dumps({'runtime_head':head,'original_sha256':preserved,'scope':'isolated local QA only; no runtime source changes committed'},indent=2)+'\n')
for name in ['porch_a','porch_b','kitchen_wing_a','kitchen_wing_b']:
 for suffix in ['.glb','.glb.import']:
  src=ROOT/'assets/farm/art'/(name+suffix)
  if src.exists():shutil.copy2(src,P/'assets/farm/art'/src.name)
for name in ['review.gd','audit_scenery.gd']:
 if (SRC/name).exists():shutil.copy2(SRC/name,P/name)
shutil.copy2(SRC/'asset_stats.json',P/'homestead_stats.json')
(P/'audit_scenery.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://audit_scenery.gd" id="1"]\n[node name="HomesteadSceneryAudit" type="Node"]\nscript=ExtResource("1")\n')
(P/'override.cfg').write_text('''[application]
config/name="ZhaoyunHomestead439QA"
config/use_custom_user_dir=true
config/custom_user_dir_name="ZhaoyunHomestead439QA"
run/main_scene="res://review.tscn"
[editor_plugins]
enabled=PackedStringArray()
[display]
window/size/viewport_width=360
window/size/viewport_height=800
window/size/window_width_override=360
window/size/window_height_override=800
[sensen]
network/base_url="http://127.0.0.1:9/v1"
network/mobile_base_url="http://127.0.0.1:9/v1"
''')
print(P)
