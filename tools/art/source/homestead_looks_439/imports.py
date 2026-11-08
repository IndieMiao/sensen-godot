"""Minimal isolated import with Godot-generated stable UIDs; GPU calls use flock."""
from pathlib import Path
import argparse,shutil,re
ROOT=Path(__file__).resolve().parents[4];KIT=Path('assets/farm/art');QA=ROOT/'output/homestead-439/import-project'
NAMES=['porch_a','porch_b','kitchen_wing_a','kitchen_wing_b']
p=argparse.ArgumentParser();p.add_argument('action',choices=['stage','configure','sync','cold']);a=p.parse_args()
if a.action=='stage':
 (QA/KIT).mkdir(parents=True,exist_ok=True)
 for name in NAMES:
  for suffix in ['.glb','.glb.import']:
   s=ROOT/KIT/(name+suffix)
   if s.exists():shutil.copy2(s,QA/KIT/s.name)
 (QA/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Homestead439Import"\nconfig/features=PackedStringArray("4.7", "Mobile")\n[rendering]\nrenderer/rendering_method="mobile"\n')
elif a.action=='configure':
 settings={'gltf/texture_map_mode':'1','meshes/light_baking':'1','meshes/generate_lods':'false','meshes/ensure_tangents':'false','meshes/create_shadow_meshes':'false','animation/import':'false'}
 for name in NAMES:
  p=QA/KIT/(name+'.glb.import');s=p.read_text();assert 'uid="uid://' in s and 'nodes/root_script=null' in s
  for key,value in settings.items():s,n=re.subn('^'+re.escape(key)+r'=.*$',key+'='+value,s,flags=re.M);assert n==1,key
  p.write_text(s)
elif a.action=='cold':
 if (QA/'.godot').exists():shutil.rmtree(QA/'.godot')
else:
 for name in NAMES:
  p=QA/KIT/(name+'.glb.import');s=p.read_text();assert 'uid="uid://' in s and 'nodes/root_script=null' in s and 'gltf/texture_map_mode=1' in s
  shutil.copy2(p,ROOT/KIT/p.name)
print(a.action,QA)
