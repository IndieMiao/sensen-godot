"""Prepare (do not run) a tiny standalone viewer QA project. No import/editor needed."""
import pathlib
import shutil
import sys

repo = pathlib.Path(__file__).resolve().parents[2]
target = pathlib.Path(sys.argv[1]).resolve()
if target == repo or repo in target.parents:
    raise SystemExit("Use a separate temporary project outside the repository")
(target / "scenes").mkdir(parents=True, exist_ok=True)
shutil.copytree(repo / "scenes/geo_farm_demo", target / "scenes/geo_farm_demo", dirs_exist_ok=True)
(target / "tests/geo_farm_demo").mkdir(parents=True, exist_ok=True)
for path in pathlib.Path(__file__).parent.glob("*.gd*"):
    shutil.copy2(path, target / "tests/geo_farm_demo" / path.name)
(target / "project.godot").write_text('''config_version=5
[application]
config/name="GeoFarm View QA"
run/main_scene="res://scenes/geo_farm_demo/farm_view.tscn"
[display]
window/size/viewport_width=360
window/size/viewport_height=640
window/size/window_width_override=360
window/size/window_height_override=640
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="gl_compatibility"
''')
print(target)
