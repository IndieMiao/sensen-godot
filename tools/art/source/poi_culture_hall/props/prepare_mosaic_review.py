"""Read-only extraction of the real N3 floor and atlas into a small isolated review."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4];OUT=ROOT/'output/culture-mosaic-323';PROJECT=OUT/'project'
ART='a5ffdae184629cd12c082944e2019b5c79248afd'
PROJECT.mkdir(parents=True,exist_ok=True);inputs={}
paths=['assets/rooms/_shared/shell_hall/'+name for name in ['hall_floor.glb','hall_floor.glb.import','hall_albedo_ao.png','hall_albedo_ao.png.import','layout.json']]
paths+=['assets/rooms/poi_culture_hall/'+name for name in ['room_albedo_ao.png','room_albedo_ao.png.import','layout.json']]
for relative in paths:
    data=subprocess.check_output(['git','show',ART+':'+relative],cwd=ROOT)
    path=PROJECT/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    inputs[relative]=hashlib.sha256(data).hexdigest()
for name in ['floor_mosaic.glb','floor_mosaic.glb.import','material_import.gd','material_import.gd.uid','prop_manifest.json']:
    relative=Path('assets/rooms/poi_culture_hall/props')/name;path=PROJECT/relative
    path.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/relative,path)
shutil.copy2(SRC/'mosaic_review.gd',PROJECT/'review.gd')
(PROJECT/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-323 mosaic v1.2 review"
run/main_scene="res://review.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenCulture323MosaicQA"
boot_splash/show_image=false
[display]
window/size/viewport_width=900
window/size/viewport_height=800
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
lights_and_shadows/directional_shadow/size=4096
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
''')
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="MosaicReview" type="Node"]\nscript=ExtResource("1")\n')
(OUT/'floor-source.json').write_text(json.dumps({'art_commit':ART,'files':inputs,
    'scope':'Exact N3 hall_floor geometry and terracotta room atlas; only copied into output; no source/scene edits'},indent=2)+'\n')
print(PROJECT)
