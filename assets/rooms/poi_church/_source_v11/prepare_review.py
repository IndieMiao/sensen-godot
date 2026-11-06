"""Stage art + shared benchmark. Run every Godot/Blender command under render.lock."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent
KIT=ROOT/'assets/rooms/poi_church';OUT=ROOT/'output/church-423-v11';DEST=OUT/'project'
for path in KIT.glob('*.glb'):
 imported=Path(str(path)+'.import')
 if imported.exists():continue
 resource='res://'+str(path.relative_to(ROOT));cache=f'res://.godot/imported/{path.name}-{hashlib.md5(resource.encode()).hexdigest()}.scn'
 imported.write_text(f'''[remap]
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
''')
atlas=KIT/'room_albedo_ao.png.import'
if not atlas.exists():atlas.write_text('''[remap]
importer="texture"
type="CompressedTexture2D"
[deps]
source_file="res://assets/rooms/poi_church/room_albedo_ao.png"
[params]
compress/mode=2
compress/high_quality=true
mipmaps/generate=true
detect_3d/compress_to=2
''')
subprocess.run([sys.executable,str(ROOT/'tools/dev/scene_bench/prepare.py'),'poi_church','--output','output/church-423-v11/project'],check=True,cwd=ROOT)
# This kit and the tea comparison have self-contained atlases/meshes; exclude
# unrelated shared kits from import to keep the shared GPU slot short.
(DEST/'assets/rooms/_shared/.gdignore').touch()
for rel in ['assets/rooms/tea_house','scenes/tea_house','assets/p0/icons']:
 shutil.copytree(ROOT/rel,DEST/rel,dirs_exist_ok=True)
(DEST/'review_icons').mkdir(exist_ok=True)
for name in ['seat','door']:
 (DEST/'review_icons'/(name+'.svg')).write_bytes(subprocess.check_output(['git','show','64f5c7a3:assets/p0/icons/'+name+'.svg'],cwd=ROOT))
for name in ['review.gd']:
 if (SRC/name).exists():shutil.copy2(SRC/name,DEST/name)
cache=ROOT/'output/tea-216/project/.godot'
if not (DEST/'.godot').exists() and cache.exists():shutil.copytree(cache,DEST/'.godot',dirs_exist_ok=True)
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="ChurchReview" type="Node"]\nscript=ExtResource("1")\n')
config=DEST/'project.godot';s=config.read_text().replace('custom_user_dir_name="SensenSceneBench"','custom_user_dir_name="SensenChurch423V11QA"').replace('import_etc2_astc=true','import_etc2_astc=false');config.write_text(s)
print(DEST)
