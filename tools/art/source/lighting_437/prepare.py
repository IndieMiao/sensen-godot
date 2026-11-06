"""Isolated lighting review; all reference kits are staged only."""
from pathlib import Path
import shutil,json,subprocess,tarfile
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/lighting-437';QA=OUT/'project'
REL='assets/landmarks/_shared/lighting';COAST='assets/landmarks/_shared/coast_kit'
def main():
 QA.mkdir(parents=True,exist_ok=True);(OUT.parent/'.gdignore').touch()
 for rel in [REL,'assets/landmarks/_shared/water_edge','assets/landmarks/_shared/far_backdrop','assets/landmarks/_shared/sea_backdrop',COAST]:
  shutil.copytree(ROOT/rel,QA/rel,dirs_exist_ok=True)
 for ref,rel in [('a590b559dd6e776dc1047f858757c932c3a7cf2b','assets/landmarks/_shared/coast_plants')]:
  proc=subprocess.Popen(['git','archive',ref,rel],cwd=ROOT,stdout=subprocess.PIPE)
  with tarfile.open(fileobj=proc.stdout,mode='r|') as tar:tar.extractall(QA,filter='data')
  assert proc.wait()==0
 for rel in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text())+['modules/avatar','assets/avatar/demo_denylist.json']:
  rel=rel.removeprefix('res://');a=ROOT/rel;b=QA/rel
  if a.is_dir():shutil.copytree(a,b,dirs_exist_ok=True)
  else:b.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(a,b)
 m=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text());m['parts']=[p for p in m['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']];(QA/'assets/avatar/parts_manifest.json').write_text(json.dumps(m))
 for name in ['review.gd','verify.gd']:
  if (SRC/name).exists():shutil.copy2(SRC/name,QA/name)
 shutil.copy2(SRC/'reference/alcatraz_island.gd',QA/'alcatraz_reference.txt')
 shutil.copy2(SRC/'reference/griffith_observatory.gd',QA/'griffith_reference.txt')
 (QA/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="LightingReview" type="Node"]\nscript=ExtResource("1")\n')
 (QA/'project.godot').write_text('''config_version=5
[application]
config/name="Lighting 437 Review"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenLighting437QA"
run/main_scene="res://review.tscn"
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=360
window/size/viewport_height=800
window/size/window_width_override=360
window/size/window_height_override=800
window/stretch/mode="canvas_items"
window/handheld/orientation=1
window/frame_pacing/android/enable_frame_pacing=false
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
