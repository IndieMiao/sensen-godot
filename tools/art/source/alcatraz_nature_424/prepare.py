"""Stage pinned blockout plus the six supplied prototypes in an offline project."""
from pathlib import Path
import json,shutil,subprocess,tarfile
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/alcatraz-nature-424';QA=OUT/'project'
BASE='34df9c0b6af42a85567dfb5318c6717f929a4ab8'
def main():
 QA.mkdir(parents=True,exist_ok=True);(OUT.parent/'.gdignore').touch()
 # Re-extract only owner assets / scene, never copy them into the art branch.
 proc=subprocess.Popen(['git','archive',BASE,'assets/landmarks/alcatraz_island','scenes/landmark/alcatraz_island.gd','scenes/landmark/alcatraz_island.tscn'],cwd=ROOT,stdout=subprocess.PIPE)
 with tarfile.open(fileobj=proc.stdout,mode='r|') as tar:tar.extractall(QA,filter='data')
 assert proc.wait()==0
 def copy(rel):
  src=ROOT/rel;dst=QA/rel
  if src.is_dir():shutil.copytree(src,dst,dirs_exist_ok=True)
  else:dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
 for p in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):copy(p.removeprefix('res://'))
 for p in ['modules/avatar','modules/farm/farm_camera.gd','modules/farm/scene_pan.gd','assets/avatar/demo_denylist.json','assets/ui/icons/game/door-open.svg','assets/landmarks/alcatraz_island']:copy(p)
 manifest=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text());manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
 (QA/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest))
 for name in ['review.gd','verify.gd','android_review.gd','prepare_android.gd','configure_imports.gd']:
  if (SRC/name).exists():shutil.copy2(SRC/name,QA/name)
 (QA/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="AlcatrazNatureReview" type="Node"]\nscript=ExtResource("1")\n')
 (QA/'project.godot').write_text('''config_version=5
[application]
config/name="Alcatraz Nature 424 QA"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenAlcatrazNature424QA"
run/main_scene="res://review.tscn"
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=720
window/size/viewport_height=800
window/size/window_width_override=720
window/size/window_height_override=800
window/stretch/mode="disabled"
[input_devices]
pointing/emulate_mouse_from_touch=true
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
anti_aliasing/quality/msaa_3d=2
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
''')
 print(QA)
if __name__=='__main__':main()
