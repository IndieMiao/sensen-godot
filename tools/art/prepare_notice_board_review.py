#!/usr/bin/env python3
"""Stage SGODOT-284 in an offline project using the existing fixture avatar."""
from pathlib import Path
import json
import shutil

ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'output/notice-board-284/project'
DEST.mkdir(parents=True,exist_ok=True)
(ROOT/'output/.gdignore').touch()

def copy(p):
    src,dst=ROOT/p,DEST/p
    dst.parent.mkdir(parents=True,exist_ok=True)
    if src.is_dir():
        shutil.copytree(src,dst,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','*.blend','*.py'))
    else: shutil.copy2(src,dst)

for p in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):
    copy(p.removeprefix('res://'))
for p in ['modules/avatar','assets/avatar/demo_denylist.json','modules/farm/farm_art.gd',
          'modules/farm/shaders','assets/farm/art']:
    copy(p)
m=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text())
m['parts']=[p for p in m['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(DEST/'assets/avatar/parts_manifest.json').write_text(json.dumps(m,indent=2))
(DEST/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-284 Offline Art Review"
run/main_scene="res://review.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenNoticeBoard284QA"
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
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="NoticeBoardReview" type="Node"]\nscript = ExtResource("1")\n')
shutil.copy2(ROOT/'tools/art/review_notice_board.gd',DEST/'review.gd')
for path in (DEST/'assets/farm/art').glob('notice_board.glb.import'):
    text=path.read_text().replace('meshes/ensure_tangents=true','meshes/ensure_tangents=false').replace('meshes/generate_lods=true','meshes/generate_lods=false')
    path.write_text(text)
print(DEST)
