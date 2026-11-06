"""Stage review only. Coast source is pinned; no owner assets enter this branch."""
from pathlib import Path
import shutil,json,subprocess,tarfile
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/water-edge-430-v11';QA=OUT/'project'
REL='assets/landmarks/_shared/water_edge';COAST='assets/landmarks/_shared/coast_kit'
QA.mkdir(parents=True,exist_ok=True);(OUT.parent/'.gdignore').touch()
shutil.copytree(ROOT/REL,QA/REL,dirs_exist_ok=True)
proc=subprocess.Popen(['git','archive','d72d74f4c0ccbcc922c5691cb8b6866eca1ca8f9',COAST],cwd=ROOT,stdout=subprocess.PIPE)
with tarfile.open(fileobj=proc.stdout,mode='r|') as tar:tar.extractall(QA,filter='data')
assert proc.wait()==0
# Verified game avatar, isolated outfit / user directory.
for rel in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text())+['modules/avatar','assets/avatar/demo_denylist.json']:
 rel=rel.removeprefix('res://');a=ROOT/rel;b=QA/rel
 if a.is_dir():shutil.copytree(a,b,dirs_exist_ok=True)
 else:b.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(a,b)
manifest=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text());manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(QA/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest))
for name in ['review.gd','configure_imports.gd','verify.gd','measure_v11.gd']:
 if (SRC/name).exists():shutil.copy2(SRC/name,QA/name)
(QA/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="WaterEdgeReview" type="Node"]\nscript=ExtResource("1")\n')
(QA/'project.godot').write_text('''config_version=5
[application]
config/name="Water Edge 430 Review"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenWaterEdge430QA"
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

(QA/"measure_v11.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://measure_v11.gd" id="1"]\n[node name="FoamMeasurement" type="Node"]\nscript=ExtResource("1")\n')
