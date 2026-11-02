"""Stage a disposable mine review; only the quarry import file returns to runtime."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[4]
QA=ROOT/"output/quarry-355"
parser=argparse.ArgumentParser();parser.add_argument("--runtime",required=True)
parser.add_argument("--sync-import",action="store_true");args=parser.parse_args()
runtime=Path(args.runtime).resolve();project=QA/"project"
asset="assets/mine/types/quarry/backdrop.glb.import"
if args.sync_import:
    shutil.copy2(project/asset,runtime/asset)
    raise SystemExit(0)
project.mkdir(parents=True,exist_ok=True)
for name in ["assets","modules","scenes","addons","tests"]:
    shutil.copytree(runtime/name,project/name,dirs_exist_ok=True,
        ignore=shutil.ignore_patterns("*.blend","*.blend1",".git",".godot","node_modules"))
for name in ["project.godot","icon.svg"]: shutil.copy2(runtime/name,project/name)
# Reuse the verified import cache, never link it to runtime or another artist's files.
cache=ROOT/"output/rock-beetle-355/project/.godot"
if cache.exists() and not (project/".godot").exists(): shutil.copytree(cache,project/".godot")
for name in ["review.gd","configure.gd"]:
    if (HERE/name).exists(): shutil.copy2(HERE/name,project/name)
palette='static var qa_band := 0\nstatic var QA_BANDS: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/mine/types/quarry/palette.json")).bands\n'
art=project/"modules/mining/mine_art.gd"
text=art.read_text().replace('extends RefCounted\n','extends RefCounted\n'+palette,1)
text=text.replace('var ground: Color = FLOOR_COLORS[number - 1]','var ground: Color = Color(QA_BANDS[qa_band].ground)')
text=text.replace('var wall: Color = WALL_COLORS[number - 1]','var wall: Color = Color(QA_BANDS[qa_band].wall)')
art.write_text(text)
backdrop=project/"modules/mining/mine_backdrop.gd"
text=backdrop.read_text().replace('extends RefCounted\n','extends RefCounted\n'+palette,1)
text=text.replace('res://assets/mine/backdrop/mine_backdrop.glb','res://assets/mine/types/quarry/backdrop.glb')
text=text.replace('return TINTS.get(floor_n, TINTS[2])','return Color(QA_BANDS[qa_band].backdrop_tint)')
text=text.replace('mat.set_shader_parameter("void_tint", VOID)','mat.set_shader_parameter("void_tint", Color(QA_BANDS[qa_band].fog))')
backdrop.write_text(text)
shader=project/"modules/mining/mine_backdrop.gdshader"
text=shader.read_text()
text=text.replace('COLOR.rgb * floor_tint','mix(COLOR.rgb * floor_tint, COLOR.rgb, clamp(UV2.y, 0.0, 1.0))')
shader.write_text(text)
test=project/"tests/p0/test_p0_mine_backdrop_depth.gd"
text=test.read_text()
text=text.replace('var high := -INF', 'var bounds_low := PackedVector2Array()\n\tvar bounds_high := PackedVector2Array()\n\tvar high := -INF',1)
text=text.replace('\t\t\tlows[t] = minf', '\t\t\tbounds_low.append(Vector2(minf(u[t*3],minf(u[t*3+1],u[t*3+2])),minf(v[t*3],minf(v[t*3+1],v[t*3+2]))))\n\t\t\tbounds_high.append(Vector2(maxf(u[t*3],maxf(u[t*3+1],u[t*3+2])),maxf(v[t*3],maxf(v[t*3+1],v[t*3+2]))))\n\t\t\tlows[t] = minf',1)
text=text.replace('\t\t\tvar t := order[k]\n','\t\t\tvar t := order[k]\n\t\t\tif bounds_low[t].x > cu+hx or bounds_high[t].x < cu-hx or bounds_low[t].y > cv+hy or bounds_high[t].y < cv-hy: continue\n',1)
text=text.replace('func test_the_backdrop_stays_inside_the_clip_planes_at_every_zoom_and_focus() -> void:',
    'func test_the_backdrop_stays_inside_the_clip_planes_at_every_zoom_and_focus(timeout = 7200000) -> void:')
text=text.replace('\t\t\treport.cases.append(case)','\t\t\tprint("QUARRY_DEPTH_CASE ", size, " floor=", floor_n, " views=", case.views, " far_margin=", case.worst.far_margin)\n\t\t\treport.cases.append(case)',1)
test.write_text(text)
(project/"review.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="Quarry355Review" type="Node"]\nscript=ExtResource("1")\n')
(project/"override.cfg").write_text('''[application]
config/name="Quarry355ArtQA"
config/use_custom_user_dir=true
config/custom_user_dir_name="Quarry355ArtQA"
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
    "local_only_overlays":["modules/mining/mine_art.gd","modules/mining/mine_backdrop.gd","modules/mining/mine_backdrop.gdshader","tests/p0/test_p0_mine_backdrop_depth.gd"],
    "depth_test":"Official test with cached triangle bounding-box rejection, case progress logging and extended timeout. Scan density, triangle clipping and assertions unchanged; MineBackdrop.SCENE points to quarry."},indent=2)+"\n")
print(project)
