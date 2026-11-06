"""Small offline art project; imports generate UIDs rather than copying them."""
from pathlib import Path
import hashlib,json,shutil,re
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent
KIT=ROOT/'assets/landmarks/alcatraz_island';OUT=ROOT/'output/alcatraz-far-424';P=OUT/'project'
P.mkdir(parents=True,exist_ok=True)
for obsolete in ['alc_far_skyline','alc_far_goldengate']:
 for suffix in ['.glb','.glb.import']:
  old=P/'assets/landmarks/alcatraz_island'/(obsolete+suffix)
  if old.exists():old.unlink() # only our obsolete staging copies, not source assets
for name in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):
 rel=name.removeprefix('res://');dest=P/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,dest)
shutil.copytree(ROOT/'modules/avatar',P/'modules/avatar',dirs_exist_ok=True)
parts=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text());parts['parts']=[p for p in parts['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(P/'assets/avatar/parts_manifest.json').write_text(json.dumps(parts,indent=2)+'\n')
for path in KIT.glob('alc_*.glb'):
 cfg=Path(str(path)+'.import')
 if not cfg.exists():
  resource='res://'+str(path.relative_to(ROOT));cache=f'res://.godot/imported/{path.name}-{hashlib.md5(resource.encode()).hexdigest()}.scn'
  cfg.write_text(f'''[remap]
importer="scene"
importer_version=1
type="PackedScene"
path="{cache}"
[deps]
source_file="{resource}"
dest_files=["{cache}"]
[params]
nodes/root_scale=1.0
meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=1
animation/import=false
materials/extract=0
gltf/texture_map_mode=1
import_script/path="res://assets/landmarks/alcatraz_island/alc_far_material_import.gd"
''')
 else:
  setting='import_script/path="res://assets/landmarks/alcatraz_island/alc_far_material_import.gd"'
  txt=cfg.read_text();txt=re.sub(r'^import_script/path=.*$',setting,txt,flags=re.M) if 'import_script/path=' in txt else txt+'\n'+setting+'\n';cfg.write_text(txt)
 for file in [path,cfg]:
  dest=P/file.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(file,dest)
shutil.copy2(KIT/'alc_far_manifest.json',P/'assets/landmarks/alcatraz_island/alc_far_manifest.json')
for name in ['alc_far_material_import.gd','alc_far_material_import.gd.uid']:
 if (KIT/name).exists():shutil.copy2(KIT/name,P/'assets/landmarks/alcatraz_island'/name)
for name in ['review.gd','configure.gd']:
 if (SRC/name).exists():shutil.copy2(SRC/name,P/name)
(P/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="AlcatrazFarReview" type="Node"]\nscript=ExtResource("1")\n')
(P/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-424 Far Art Review"
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenAlcatrazFar424QA"
run/main_scene="res://review.tscn"
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
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
