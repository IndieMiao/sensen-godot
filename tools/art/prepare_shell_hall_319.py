"""Stage just the shared shell and native render harness, without game accounts."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "output/poi-hall-319/project"
KIT = "assets/rooms/_shared/shell_hall"
SCENE = "scenes/shell_hall"
for rel in [KIT, SCENE]:
    shutil.copytree(ROOT / rel, DEST / rel, dirs_exist_ok=True)
shutil.copy2(ROOT / "tools/art/review_shell_hall_319.gd", DEST / "review.gd")
(DEST / "project.godot").write_text('''config_version=5
[application]
config/name="SensenHall319QA"
run/main_scene="res://review.tscn"
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenHall319QA"
[display]
window/size/viewport_width=900
window/size/viewport_height=800
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
textures/default_filters/use_nearest_mipmap_filter=false
lights_and_shadows/directional_shadow/size=4096
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
''')
(DEST / "review.tscn").write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://review.gd" id="1"]
[node name="ShellHallReview" type="Node"]
script=ExtResource("1")
''')
print(DEST)
