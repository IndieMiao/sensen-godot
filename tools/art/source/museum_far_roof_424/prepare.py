from pathlib import Path
import shutil,re
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/museum-far-roof-424';P=OUT/'project';REL=Path('assets/landmarks/alcatraz_island')
(P/REL).mkdir(parents=True,exist_ok=True)
for name in ['alc_museum.glb','alc_museum.glb.import','alc_museum_far.glb','alc_museum_far.glb.import','alc_museum_far_manifest.json','alc_far_material_import.gd','alc_far_material_import.gd.uid']:
 shutil.copy2(ROOT/REL/name,P/REL/name)
# Review the authored near triangles, independently of its generated internal LOD.
cfg=P/REL/'alc_museum.glb.import';cfg.write_text(cfg.read_text().replace('meshes/generate_lods=true','meshes/generate_lods=false'))
shutil.copy2(SRC/'review.gd',P/'review.gd')
(P/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="MuseumRoofLODReview" type="Node"]\nscript=ExtResource("1")\n')
(P/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-424 Museum Roof LOD Review"
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenMuseumFarRoof424QA"
run/main_scene="res://review.tscn"
[display]
window/size/viewport_width=960
window/size/viewport_height=800
window/size/borderless=true
window/vsync/vsync_mode=0
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
''')
print(P)
