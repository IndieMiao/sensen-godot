"""Small asset smoke project, with the real farm material/light and fixture avatar."""
from pathlib import Path
import shutil,json
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent
OUT=ROOT/'output/homestead-440';QA=OUT/'android-project'
QA.mkdir(parents=True,exist_ok=True)
def copy(rel):
 a=ROOT/rel;b=QA/rel;b.parent.mkdir(parents=True,exist_ok=True)
 if a.is_dir():shutil.copytree(a,b,dirs_exist_ok=True)
 else:shutil.copy2(a,b)
for rel in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text())+['modules/avatar','assets/avatar/demo_denylist.json']:
 copy(rel.removeprefix('res://'))
manifest=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text());manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(QA/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest))
for name in ['house_cottage','master_farmhouse_a','master_farmhouse_b','chef_sign_a','chef_sign_b']:
 for suffix in ['.glb','.glb.import']:copy('assets/farm/art/'+name+suffix)
for rel in ['modules/farm/farm_art.gd','modules/farm/shaders/garden_path.gdshader','modules/farm/shaders/garden_soil.gdshader','assets/farm/art/meadow.png','assets/farm/art/meadow.png.import']:copy(rel)
copy('icon.svg');copy('icon.svg.import')
shutil.copy2(SRC/'android_review.gd',QA/'review.gd')
(QA/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="HomesteadAssetSmoke" type="Node"]\nscript=ExtResource("1")\n')
(QA/'project.godot').write_text('''config_version=5
[application]
config/name="Homestead 440 Asset Smoke"
config/icon="res://icon.svg"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenHomestead440Smoke"
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
(QA/'export_presets.cfg').write_text('''[preset.0]
name="Android Homestead QA"
platform="Android"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter=""
[preset.0.options]
gradle_build/use_gradle_build=false
architectures/arm64-v8a=false
architectures/x86_64=true
version/code=44001
version/name="440-art-review"
package/unique_name="com.sensen.homestead440qa"
package/name="Homestead Art QA"
package/signed=true
''')
print(QA)
