from pathlib import Path
import hashlib,json,shutil,subprocess,re
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/alcatraz-museum-far-424';P=OUT/'project';KIT=ROOT/'assets/landmarks/alcatraz_island';REL='assets/landmarks/alcatraz_island';REF=json.loads((SRC/'reference/source.json').read_text())
P.mkdir(parents=True,exist_ok=True);(P/REL).mkdir(parents=True,exist_ok=True)
shutil.copy2(SRC/REF['near_file'],P/REL/'alc_museum.glb')
# Near reference is staged only, never written into the production branch.
for name in ['alc_museum','alc_museum_far']:
 target=(KIT if name.endswith('_far') else P/REL)/(name+'.glb.import')
 if not target.exists():
  raw=subprocess.check_output(['git','show','b16c3198:'+REL+'/'+name+'.glb.import'],cwd=ROOT).decode()
  raw=re.sub(r'^meshes/generate_lods=.*$','meshes/generate_lods=false',raw,flags=re.M)
  raw=re.sub(r'^animation/import=.*$','animation/import=false',raw,flags=re.M)
  raw=re.sub(r'^import_script/path=.*$','import_script/path="res://'+REL+'/alc_far_material_import.gd"',raw,flags=re.M)
  assert 'nodes/root_script=null' in raw;target.write_text(raw)
for name in ['alc_museum_far.glb','alc_museum_far.glb.import','alc_museum_far_manifest.json','alc_far_material_import.gd','alc_far_material_import.gd.uid']:shutil.copy2(KIT/name,P/REL/name)
shutil.copy2(SRC/'review.gd',P/'review.gd')
(P/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="MuseumFarReview" type="Node"]\nscript=ExtResource("1")\n')
(P/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-424 Museum LOD Review"
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenMuseumFar424QA"
run/main_scene="res://review.tscn"
[display]
window/size/viewport_width=960
window/size/viewport_height=800
window/size/borderless=true
window/vsync/vsync_mode=0
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=false
''')
print(P)
