"""Prepare an isolated Godot mine art viewer, optionally its Android QA export."""
from pathlib import Path
import argparse
import re
import shutil

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--android", action="store_true")
parser.add_argument("--camera-qa", action="store_true")
parser.add_argument("--output", default="output/mine-art-2026-09-24")
args = parser.parse_args()
output = ROOT / args.output
folder = output / ("android-project" if args.android else "project")
folder.mkdir(parents=True, exist_ok=True)
(ROOT / "output/.gdignore").touch()
config = (ROOT / "project.godot").read_text()
config = config.replace('config/name="SensenAvatar"', 'config/name="Mine Art Preview"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="sensen-mine-art-20260924"')
config = re.sub(r'^run/main_scene=.*$', 'run/main_scene="res://tools/dev/mine_art_preview.tscn"', config, flags=re.M)
config = config.replace('[sensen]', '[sensen]\nnetwork/online_qa=true')
config = config.replace('enabled=PackedStringArray("res://addons/gdUnit4/plugin.cfg")', 'enabled=PackedStringArray()')
config += '\n[mine_art]\noutput="' + str(output / "after") + '"\n'
config += 'camera_qa=' + ('true' if args.camera_qa else 'false') + '\n'
(folder / "project.godot").write_text(config)
for name in ["assets", "modules", "scenes", "icon.svg"] + ([] if args.android else ["tools"]):
    if not (folder / name).exists():
        (folder / name).symlink_to(ROOT / name, target_is_directory=(ROOT / name).is_dir())
(folder / ".godot").mkdir(exist_ok=True)
if not (folder / ".godot/imported").exists():
    (folder / ".godot/imported").symlink_to(ROOT / ".godot/imported", target_is_directory=True)
if args.android:
    (folder / "tools/dev").mkdir(parents=True, exist_ok=True)
    for name in ["mine_art_preview.gd", "mine_art_preview.tscn"]:
        shutil.copyfile(ROOT / "tools/dev" / name, folder / "tools/dev" / name)
    preset = (ROOT / "export_presets.cfg").read_text().split("[preset.1]")[0]
    replacements = {
        'name="Android"': 'name="Android Mine Art QA"',
        'gradle_build/use_gradle_build=true': 'gradle_build/use_gradle_build=false',
        'com.sensen.journeypreview': 'com.sensen.journeymineartqa',
        'Sensen Journey Preview': 'Journey Mine Art QA',
    }
    for old, new in replacements.items():
        preset = preset.replace(old, new)
    for key, value in {
        'include_filter': '"assets/**/*.json"',
        'exclude_filter': '"assets/avatar/source/*.fbx,addons/*,tests/*,docs/*,server/*,output/*,build/*"',
        'export_path': '"../mine-art-qa.apk"',
        'version/code': '2026092402' if args.camera_qa else '2026092401',
        'version/name': '"0.16.32-cameraqa"' if args.camera_qa else '"0.16.32-artqa"',
    }.items():
        preset = re.sub(r'^' + re.escape(key) + r'=.*$', key + '=' + value, preset, flags=re.M)
    (folder / "export_presets.cfg").write_text(preset)
print(folder)
