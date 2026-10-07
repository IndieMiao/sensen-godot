#!/usr/bin/env python3
"""Stage the shared rendered scene benchmark without production autoloads/saves."""
from pathlib import Path
import argparse
import json
import shutil

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('slug')
parser.add_argument('--output')
args = parser.parse_args()
assert args.slug.replace('_', '').isalnum()
project = ROOT / (args.output or f'output/scene-bench/{args.slug}/project')
project.mkdir(parents=True, exist_ok=True)
(ROOT / 'output/.gdignore').touch()

def copy(relative):
    source, target = ROOT / relative, project / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, target, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('__pycache__', '*.blend'))
    else:
        shutil.copy2(source, target)

for file in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):
    copy(file.removeprefix('res://'))
for file in ['modules/avatar', 'tools/dev/scene_bench', 'assets/avatar/demo_denylist.json',
             f'scenes/{args.slug}', f'assets/rooms/{args.slug}']:
    copy(file)
# The only shared dependency family allowed here is authored room art.
if (ROOT/'assets/rooms/_shared').exists(): copy('assets/rooms/_shared')
manifest = json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text())
manifest['parts'] = [p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(project/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest, indent=2))
(project/'project.godot').write_text('''config_version=5
[application]
config/name="Scene Benchmark"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenSceneBench"
run/main_scene="res://tools/dev/scene_bench/scene_bench.tscn"
boot_splash/show_image=false
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=960
window/size/viewport_height=720
window/size/borderless=true
window/stretch/mode="canvas_items"
[input_devices]
pointing/emulate_mouse_from_touch=true
pointing/android/enable_pan_and_scale_gestures=true
[rendering]
renderer/rendering_method="mobile"
anti_aliasing/quality/msaa_3d=2
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
''')
print(project)
