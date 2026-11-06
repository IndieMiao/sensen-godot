"""Prepare the additive v1.1 atlas/layout from the immutable accepted v1 base.
Run with Python + Pillow before build_increment.py. Existing Godot UIDs retained.
"""
from pathlib import Path
import json,hashlib,subprocess,math,io
from PIL import Image,ImageDraw
SRC=Path(__file__).resolve().parent;KIT=SRC.parent;ROOT=KIT.parents[2]
BASE=json.loads((SRC/'reuse_provenance.json').read_text())['base_head']
def base_file(name):return subprocess.check_output(['git','show',BASE+':assets/rooms/poi_church/'+name],cwd=ROOT)
def write(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
im=Image.open(io.BytesIO(base_file('room_albedo_ao.png'))).convert('RGB')
ImageDraw.Draw(im).rectangle((1896,124,1911,139),fill='#986D61');im.save(KIT/'room_albedo_ao.png')
layout=json.loads(base_file('layout.json'));r=math.sqrt(.5)
for name,pos,yaw in [('aisle_carpet',[-.045*r,.083,-.045*r],45),('vault_extension',[0,.08,0],0),('grass_extension',[0,0,0],0)]:
 layout['assets'].append({'name':name,'file':name+'.glb','position':pos,'yaw_degrees':yaw,'colliders':[],'material':'opaque','vegetation':False,'review_only':False,'cast_shadow':False,'provenance':'assets/rooms/poi_church/_source_v11/reuse_provenance.json'})
 rel=f'res://assets/rooms/poi_church/{name}.glb';cache=f'res://.godot/imported/{name}.glb-{hashlib.md5(rel.encode()).hexdigest()}.scn'
 cfg=KIT/(name+'.glb.import')
 if not cfg.exists():cfg.write_text(f'[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath="{cache}"\n[deps]\nsource_file="{rel}"\ndest_files=["{cache}"]\n[params]\nnodes/root_scale=1.0\nmeshes/ensure_tangents=true\nmeshes/generate_lods=false\nmeshes/create_shadow_meshes=true\nmeshes/light_baking=1\nanimation/import=false\nmaterials/extract=0\ngltf/texture_map_mode=1\n')
layout['revision']='v1.1';write(KIT/'layout.json',layout)
print('Prepared atlas/layout; export additions with Blender next, then measure GLBs.')
