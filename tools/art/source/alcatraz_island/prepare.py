"""Copy only this scene and the existing default avatar into an offline QA project."""
from pathlib import Path
import json
import shutil
import argparse

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
QA=ROOT/'output/alcatraz-424/project'
parser=argparse.ArgumentParser()
parser.add_argument('--sync-imports',action='store_true')
args=parser.parse_args()
if args.sync_imports:
    for rel in ['assets/landmarks/alcatraz_island','scenes/landmark']:
        for p in (QA/rel).iterdir():
            if p.name.endswith(('.import','.uid')):
                shutil.copy2(p,ROOT/rel/p.name)
    raise SystemExit(0)

QA.mkdir(parents=True,exist_ok=True)
(ROOT/'output/.gdignore').touch()
def copy(rel):
    src=ROOT/rel;dst=QA/rel
    if src.is_dir():
        if rel=='assets/landmarks/alcatraz_island' and dst.exists():
            for old in dst.glob('*.glb*'):
                if not (src/old.name).exists(): old.unlink()
        shutil.copytree(src,dst,dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.blend','__pycache__'))
    else:
        dst.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(src,dst)

for p in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):copy(p.removeprefix('res://'))
for p in ['modules/avatar','modules/farm/farm_camera.gd','modules/farm/scene_pan.gd','modules/farm/scene_pan.gd.uid',
    'assets/avatar/demo_denylist.json','assets/ui/icons/game/door-open.svg',
    'assets/landmarks/alcatraz_island','scenes/landmark/alcatraz_island.gd',
    'scenes/landmark/alcatraz_island.tscn']:copy(p)
manifest=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text())
manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(QA/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
shutil.copy2(HERE/'review.gd',QA/'review.gd')
(QA/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="Review" type="Node"]\nscript=ExtResource("1")\n')
(QA/'project.godot').write_text('''config_version=5
[application]
config/name="Alcatraz 424 Blockout QA"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenAlcatraz424ArtQA"
run/main_scene="res://review.tscn"
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=360
window/size/viewport_height=800
window/size/window_width_override=360
window/size/window_height_override=800
window/stretch/mode="canvas_items"
[input_devices]
pointing/emulate_mouse_from_touch=true
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
anti_aliasing/quality/msaa_3d=2
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
''')
print(QA)
