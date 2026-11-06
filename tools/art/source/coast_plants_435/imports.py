"""Stage/cold-import/sync only SGODOT-435. Invoke Godot under the render lock."""
from pathlib import Path
import argparse,json,re,shutil
ROOT=Path(__file__).resolve().parents[4];KIT=Path('assets/landmarks/_shared/coast_plants');QA=ROOT/'output/coast-plants/import-project'
p=argparse.ArgumentParser();p.add_argument('action',choices=['stage','configure','cold','sync']);a=p.parse_args()
names=json.loads((ROOT/KIT/'manifest.json').read_text())['assets']
if a.action=='stage':
 (QA/KIT).mkdir(parents=True,exist_ok=True)
 for name in names:
  for suffix in ['.glb','.glb.import']:
   src=ROOT/KIT/(name+suffix)
   if src.exists():shutil.copy2(src,QA/KIT/src.name)
 for src in (ROOT/KIT).iterdir():
  if src.suffix in ['.gd','.tres','.uid','.json']:shutil.copy2(src,QA/KIT/src.name)
 (QA/'project.godot').write_text('config_version=5\n[application]\nconfig/name="CoastPlants435Import"\nconfig/features=PackedStringArray("4.7", "Mobile")\n[rendering]\nrenderer/rendering_method="mobile"\n')
elif a.action=='configure':
 settings={'gltf/texture_map_mode':'1','meshes/light_baking':'1','meshes/generate_lods':'false','meshes/ensure_tangents':'false','meshes/create_shadow_meshes':'false','animation/import':'false'}
 for name in names:
  p=QA/KIT/(name+'.glb.import');s=p.read_text()
  assert 'uid="uid://' in s and 'nodes/root_script=null' in s
  for key,value in settings.items():
   s,n=re.subn('^'+re.escape(key)+r'=.*$',key+'='+value,s,flags=re.M);assert n==1,key
  s,n=re.subn(r'^import_script/path=.*$', 'import_script/path="res://assets/landmarks/_shared/coast_plants/coast_plants_import.gd"',s,flags=re.M);assert n==1
  p.write_text(s)
elif a.action=='cold':
 if (QA/'.godot').exists():shutil.rmtree(QA/'.godot')
else:
 for name in names:
  p=QA/KIT/(name+'.glb.import');s=p.read_text()
  assert 'uid="uid://' in s and 'nodes/root_script=null' in s and 'gltf/texture_map_mode=1' in s
  shutil.copy2(p,ROOT/KIT/p.name)
 if (QA/KIT/'coast_plants_import.gd.uid').exists():shutil.copy2(QA/KIT/'coast_plants_import.gd.uid',ROOT/KIT/'coast_plants_import.gd.uid')
print(a.action,QA)
