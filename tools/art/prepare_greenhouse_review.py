#!/usr/bin/env python3
"""Stage the isolated SGODOT-294 review with the existing fixture avatar."""
from pathlib import Path
import json,shutil
root=Path(__file__).resolve().parents[2]; dest=root/'output/greenhouse-294/project';dest.mkdir(parents=True,exist_ok=True)
def copy(p):
 src=root/p;dst=dest/p;dst.parent.mkdir(parents=True,exist_ok=True)
 if src.is_dir():shutil.copytree(src,dst,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','*.blend','*.py'))
 else:shutil.copy2(src,dst)
for p in json.loads((root/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):copy(p.removeprefix('res://'))
for p in ['modules/avatar','assets/avatar/demo_denylist.json','modules/farm/farm_art.gd','modules/farm/shaders','assets/farm/art']:copy(p)
m=json.loads((root/'assets/avatar/parts_manifest.json').read_text());m['parts']=[p for p in m['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(dest/'assets/avatar/parts_manifest.json').write_text(json.dumps(m,indent=2))
(dest/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-294 Offline Art Review"
run/main_scene="res://review.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenGreenhouse294QA"
boot_splash/show_image=false
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=1152
window/size/viewport_height=720
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
lights_and_shadows/directional_shadow/size=4096
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
''')
(dest/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="GreenhouseReview" type="Node"]\nscript = ExtResource("1")\n')
shutil.copy2(root/'tools/art/review_greenhouse.gd',dest/'review.gd')
for path in (dest/'assets/farm/art').glob('greenhouse_*.glb.import'):
 text=path.read_text().replace('meshes/ensure_tangents=true','meshes/ensure_tangents=false').replace('meshes/generate_lods=true','meshes/generate_lods=false')
 path.write_text(text)
print(dest)
