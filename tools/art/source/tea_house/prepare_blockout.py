"""Prepare isolated desktop-only tea layout review."""
from pathlib import Path
import json
import shutil

ROOT=Path(__file__).resolve().parents[4]
SRC=Path(__file__).resolve().parent
OUT=ROOT/'output/tea-216'
DEST=OUT/'blockout_project'
DEST.mkdir(parents=True,exist_ok=True)


def copy(path):
    source=ROOT/path;target=DEST/path;target.parent.mkdir(parents=True,exist_ok=True)
    if source.is_dir():shutil.copytree(source,target,dirs_exist_ok=True)
    else:shutil.copy2(source,target)


for path in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):copy(path.removeprefix('res://'))
copy('modules/avatar');copy('assets/avatar/demo_denylist.json')
manifest=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text())
manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(DEST/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
shutil.copytree(OUT/'blockout_assets',DEST/'models',dirs_exist_ok=True)
for name in ['blockout_plan.json','blockout_review.gd']:shutil.copy2(SRC/name,DEST/name)
(DEST/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-216 Tea Blockout"
run/main_scene="res://review.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenTea216BlockoutQA"
boot_splash/show_image=false
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=960
window/size/viewport_height=800
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
lights_and_shadows/directional_shadow/size=4096
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
''')
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://blockout_review.gd" id="1"]\n[node name="TeaBlockout" type="Node"]\nscript=ExtResource("1")\n')
print(DEST)
