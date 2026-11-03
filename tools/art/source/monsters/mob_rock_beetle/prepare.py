"""Isolated farm-dev art fixture. No account, save, production network or runtime-code edits."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
parser = argparse.ArgumentParser()
parser.add_argument("--runtime", required=True)
args = parser.parse_args()
runtime = Path(args.runtime).resolve()
qa = ROOT / "output/rock-beetle-355"
project = qa / "project"
project.mkdir(parents=True,exist_ok=True)
for name in ["assets","modules","scenes","addons"]:
    shutil.copytree(runtime/name, project/name, dirs_exist_ok=True,
        ignore=shutil.ignore_patterns("*.blend","*.blend1",".git",".godot","node_modules"))
for name in ["project.godot","icon.svg"]: shutil.copy2(runtime/name,project/name)
(qa/"stage-snapshot.json").write_text(json.dumps({"runtime_commit":subprocess.check_output(
    ["git","rev-parse","HEAD"],cwd=runtime,text=True).strip(),"runtime_game_base":subprocess.check_output(
    ["git","merge-base","HEAD","origin/farm-dev"],cwd=runtime,text=True).strip(),"runtime_path":str(runtime)},indent=2)+"\n")
for name in ["review.gd","configure.gd"]:
    if (HERE/name).exists(): shutil.copy2(HERE/name,project/name)
(project/"review.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="Beetle355Review" type="Node"]\nscript=ExtResource("1")\n')
(project/"override.cfg").write_text('''[application]
config/name="RockBeetle355ArtQA"
config/use_custom_user_dir=true
config/custom_user_dir_name="RockBeetle355ArtQA"
run/main_scene="res://review.tscn"
[editor_plugins]
enabled=PackedStringArray()
[display]
window/size/viewport_width=800
window/size/viewport_height=800
window/size/window_width_override=800
window/size/window_height_override=800
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
[sensen]
network/base_url="http://127.0.0.1:9/v1"
network/mobile_base_url="http://127.0.0.1:9/v1"
''')
print(project)
