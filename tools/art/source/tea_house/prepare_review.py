"""Stage the tea art and unchanged scene_bench in an isolated desktop project."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[4]
SRC=Path(__file__).resolve().parent
KIT=ROOT/'assets/rooms/tea_house'
OUT=ROOT/'output/tea-216'
DEST=OUT/'project'
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
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=0
animation/import=false
materials/extract=0
gltf/texture_map_mode=1
''')
atlas=KIT/'room_albedo_ao.png.import'
if not atlas.exists():atlas.write_text('''[remap]
importer="texture"
type="CompressedTexture2D"
[deps]
source_file="res://assets/rooms/tea_house/room_albedo_ao.png"
[params]
compress/mode=2
compress/high_quality=true
mipmaps/generate=true
detect_3d/compress_to=2
''')
subprocess.run([sys.executable,str(ROOT/'tools/dev/scene_bench/prepare.py'),'tea_house','--output','output/tea-216/project'],check=True,cwd=ROOT)
for name in ['review.gd','configure_imports.gd']:
    if (SRC/name).is_file():shutil.copy2(SRC/name,DEST/name)
animation_commit='f4bb293bb8800ca96624912815bc8acae2943285'
animation=subprocess.check_output(['git','show',animation_commit+':assets/avatar/base/animations.res'],cwd=ROOT)
(DEST/'assets/avatar/base/animations.res').write_bytes(animation)
(DEST/'animation-provenance.json').write_text(json.dumps({'commit':animation_commit,'sha256':hashlib.sha256(animation).hexdigest(),
    'use':'Existing production sit_idle in isolated desktop art review only'},indent=2)+'\n')
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="TeaReview" type="Node"]\nscript=ExtResource("1")\n')
print(DEST)
