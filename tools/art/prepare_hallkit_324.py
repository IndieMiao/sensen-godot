#!/usr/bin/env python3
"""Stage the hall kit and a fixed Basic Room avatar in an isolated art project."""
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / 'output/hallkit-324/project'
PROJECT.mkdir(parents=True, exist_ok=True)


def copy(relative):
    source, target = ROOT/relative, PROJECT/relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, target, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('__pycache__', '*.blend'))
    else:
        shutil.copy2(source, target)


assert (ROOT/'output/.gdignore').exists()
for path in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):
    copy(path.removeprefix('res://'))
for path in ['modules/avatar', 'assets/avatar/demo_denylist.json', 'assets/rooms/_shared/shell_hall',
             'tools/art/review_hallkit_324.gd']:
    copy(path)
manifest = json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text())
manifest['parts'] = [p for p in manifest['parts'] if p['id'] in ['body00', 'eyes00', 'hairhat0', 'cloth0', 'shoes0']]
(PROJECT/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
(PROJECT/'project.godot').write_text('''config_version=5
[application]
config/name="Hall Kit 324 Review"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenHuangzhongHallkit324QA"
run/main_scene="res://review.tscn"
boot_splash/show_image=false
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=960
window/size/viewport_height=480
[rendering]
renderer/rendering_method="mobile"
anti_aliasing/quality/msaa_3d=2
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
''')
(PROJECT/'review.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tools/art/review_hallkit_324.gd" id="1"]
[node name="HallkitReview" type="Node"]
script=ExtResource("1")
''')
print(PROJECT)
