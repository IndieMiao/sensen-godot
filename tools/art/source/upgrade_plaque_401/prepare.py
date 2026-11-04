"""Stage an isolated b1 farm; preview substitution never edits the game checkout."""
from pathlib import Path
import argparse,difflib,json,shutil,subprocess
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/"output/plaque-401";PROJECT=QA/"project"
parser=argparse.ArgumentParser();parser.add_argument("--runtime-ref",default="6cf0bcb2");parser.add_argument("--sync-import",action="store_true");args=parser.parse_args()
KIT="assets/farm/art/"
if args.sync_import:
    for name in ["upgrade_plaque.glb.import","upgrade_plaque_import.gd.uid"]:
        shutil.copy2(PROJECT/KIT/name,ROOT/KIT/name)
    raise SystemExit()
PROJECT.mkdir(parents=True,exist_ok=True);(ROOT/"output/.gdignore").touch()
runtime_head=subprocess.check_output(["git","rev-parse",args.runtime_ref],cwd=ROOT,text=True).strip()
archive=subprocess.Popen(["git","archive",runtime_head],cwd=ROOT,stdout=subprocess.PIPE)
subprocess.run(["tar","-x","-C",str(PROJECT)],stdin=archive.stdout,check=True);archive.stdout.close();assert archive.wait()==0
(PROJECT/"docs/.gdignore").touch()
for name in ["upgrade_plaque.glb","upgrade_plaque.glb.import","upgrade_plaque_import.gd","upgrade_plaque_import.gd.uid"]:
    if (ROOT/KIT/name).exists():shutil.copy2(ROOT/KIT/name,PROJECT/KIT/name)
shutil.copy2(HERE/"spec.json",PROJECT/"upgrade_plaque_spec.json")
for name in ["review.gd","configure.gd"]:
    if (HERE/name).exists():shutil.copy2(HERE/name,PROJECT/name)
farm=PROJECT/"scenes/p0/p0_farm.gd";original=farm.read_text()
old='\t_plaque_node = FarmArt.instance("sign", _plaque, 0.6)'
new='\t_plaque_node = load("res://assets/farm/art/upgrade_plaque.glb").instantiate()\n\t_plaque_node.position = _plaque'
assert original.count(old)==1
replaced=original.replace(old,new);farm.write_text(replaced)
(QA/"farm-preview.patch").write_text("".join(difflib.unified_diff(original.splitlines(True),replaced.splitlines(True),fromfile="b1/scenes/p0/p0_farm.gd",tofile="isolated-preview/scenes/p0/p0_farm.gd")))
(PROJECT/"review.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="UpgradePlaque401Review" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT/"override.cfg").write_text('''[application]
config/name="ZhaoyunPlaque401QA"
config/use_custom_user_dir=true
config/custom_user_dir_name="ZhaoyunPlaque401QA"
run/main_scene="res://review.tscn"
[editor_plugins]
enabled=PackedStringArray()
[display]
window/size/viewport_width=360
window/size/viewport_height=800
window/size/window_width_override=360
window/size/window_height_override=800
[sensen]
network/base_url="http://127.0.0.1:9/v1"
network/mobile_base_url="http://127.0.0.1:9/v1"
''')
(QA/"stage.json").write_text(json.dumps(dict(runtime_head=runtime_head,scope="Isolated copied b1; temporary placeholder substitution only; real game farm/camera/UI/movement; no committed client edits"),indent=2)+"\n")
print(PROJECT)
