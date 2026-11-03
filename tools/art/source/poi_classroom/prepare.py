"""Isolated P0 art fixture. No farm-dev checkout files or final Huangzhong assets are changed."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/"output/classroom-322"
parser=argparse.ArgumentParser();parser.add_argument("--runtime",required=True);parser.add_argument("--sync-import",action="store_true");args=parser.parse_args()
runtime=Path(args.runtime).resolve();project=QA/"project";kit="assets/rooms/poi_classroom"
if args.sync_import:
    for name in ["blockout_student_desk","blockout_student_stool","blockout_box","blockout_cylinder","blockout_ball"]:
        shutil.copy2(project/kit/(name+".glb.import"),ROOT/kit/(name+".glb.import"))
    for file in (project/"scenes/poi_classroom").glob("*.uid"):shutil.copy2(file,ROOT/"scenes/poi_classroom"/file.name)
    raise SystemExit(0)
project.mkdir(parents=True,exist_ok=True)
for name in ["assets","modules","scenes","addons"]:
    shutil.copytree(runtime/name,project/name,dirs_exist_ok=True,ignore=shutil.ignore_patterns("*.blend","*.blend1",".godot","node_modules"))
for name in ["project.godot","icon.svg"]:shutil.copy2(runtime/name,project/name)
for rel in [kit,"assets/rooms/_shared/shell_hall","scenes/poi_classroom","scenes/shell_hall"]:
    shutil.copytree(ROOT/rel,project/rel,dirs_exist_ok=True,ignore=shutil.ignore_patterns("*.blend","*.blend1"))
template="assets/rooms/poi_hotel_lobby/round_side_table.glb.import"
(project/template).parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/template,project/template)
cache=ROOT/"output/quarry-355/project/.godot"
if cache.exists() and not (project/".godot").exists():shutil.copytree(cache,project/".godot")
for name in ["review.gd","configure.gd","check_navigation.gd"]:
    if (HERE/name).exists():shutil.copy2(HERE/name,project/name)
shutil.copy2(QA/"navigation-fixture.json",project/"navigation-fixture.json")
(project/"review.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="Classroom322Review" type="Node"]\nscript=ExtResource("1")\n')
(project/"override.cfg").write_text('''[application]
config/name="Classroom322WhiteQA"
config/use_custom_user_dir=true
config/custom_user_dir_name="Classroom322WhiteQA"
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
(QA/"stage.json").write_text(json.dumps({"runtime_base":subprocess.check_output(["git","rev-parse","HEAD"],cwd=runtime,text=True).strip(),
    "art_base":subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip(),
    "scope":"Isolated copied P0 runtime. Asset/scene overlay only; no runtime code edits, network localhost:9."},indent=2)+"\n")
print(project)
