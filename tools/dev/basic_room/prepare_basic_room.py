#!/usr/bin/env python3
"""Stage a minimal offline Godot project without changing the game's launch/export settings."""
from pathlib import Path
import json
import shutil
import argparse

parser=argparse.ArgumentParser()
parser.add_argument("--output", default="output/basic-room-2026-10-06/qa-project")
args=parser.parse_args()

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "output/basic-room-2026-10-06"
PROJECT = ROOT / args.output
PROJECT.mkdir(parents=True, exist_ok=True)
(OUT.parent / ".gdignore").touch()

def copy(relative):
    src=ROOT/relative;dst=PROJECT/relative
    if src.is_dir():
        shutil.copytree(src,dst,dirs_exist_ok=True,ignore=shutil.ignore_patterns("*.import","__pycache__","*.py"))
    else:
        dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)

deps=json.loads((OUT/"avatar-dependencies.json").read_text())
for path in deps:copy(path.removeprefix("res://"))
for path in ["modules/avatar","scenes/basic_room","tools/dev/basic_room","assets/rooms/basic_room","assets/avatar/demo_denylist.json"]:copy(path)
manifest=json.loads((ROOT/"assets/avatar/parts_manifest.json").read_text())
manifest["parts"]=[p for p in manifest["parts"] if p["id"] in ["body00","eyes00","hairhat0","cloth0","shoes0"]]
(PROJECT/"assets/avatar/parts_manifest.json").write_text(json.dumps(manifest,indent=2))
(PROJECT/"project.godot").write_text('''config_version=5

[application]
config/name="Basic Room Review"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenBasicRoomQA"
run/main_scene="res://tools/dev/basic_room/basic_room.tscn"
boot_splash/bg_color=Color(0.91, 0.894, 0.784, 1)
boot_splash/show_image=false

[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"

[display]
window/size/viewport_width=360
window/size/viewport_height=640
window/size/window_width_override=720
window/size/window_height_override=1280
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=1
window/frame_pacing/android/enable_frame_pacing=false

[input_devices]
pointing/emulate_mouse_from_touch=true
pointing/android/enable_pan_and_scale_gestures=true

[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
anti_aliasing/quality/msaa_3d=2
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/size.mobile=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
lights_and_shadows/directional_shadow/soft_shadow_filter_quality.mobile=2
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
renderer/rendering_method.web="gl_compatibility"
''')
(PROJECT/"export_presets.cfg").write_text('''[preset.0]
name="Android Basic Room QA"
platform="Android"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.json"
exclude_filter="*.py,*.md,*.blend"
export_path="../basic-room-qa.apk"
script_export_mode=2

[preset.0.options]
custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=true
version/code=2026100601
version/name="0.1.0"
package/unique_name="com.sensen.basicroomqa"
package/name="Basic Room Review"
package/signed=true
package/app_category=2
package/retain_data_on_uninstall=false
screen/immersive_mode=true
screen/support_small=true
screen/support_normal=true
screen/support_large=true
screen/support_xlarge=true
permissions/internet=false
permissions/access_network_state=false
''')
print(PROJECT)
