"""Isolated six-asset cold import, retaining each Godot UID. Run Godot under flock."""
from pathlib import Path
import argparse,shutil,re,json,hashlib,subprocess
ROOT=Path(__file__).resolve().parents[4];Q=ROOT/'output/homestead-448';P=Q/'import-project';K=Path('assets/farm/art')
N=['porch_a','porch_b','kitchen_wing_a','kitchen_wing_b','master_farmhouse_a','master_farmhouse_b']
a=argparse.ArgumentParser();a.add_argument('action',choices=['stage','cold','sync','verify']);op=a.parse_args().action
uid=lambda p:re.search(r'^uid="([^"]+)"$',p.read_text(),re.M).group(1)
if op=='stage':
 (Q/'before').mkdir(parents=True,exist_ok=True)
 for name in N:
  for ext in ['.glb','.glb.import']:
   old=Q/'before'/(name+ext)
   expected=subprocess.check_output(['git','show','6151fef82a16e822367ee076dacc5eef85c19002:assets/farm/art/'+name+ext],cwd=ROOT)
   if old.exists():assert old.read_bytes()==expected
   else:old.write_bytes(expected)
 (P/K).mkdir(parents=True,exist_ok=True)
 for name in N:
  for ext in ['.glb','.glb.import']:shutil.copy2(ROOT/K/(name+ext),P/K/(name+ext))
 (P/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Homestead448ColdImport"\nconfig/features=PackedStringArray("4.7", "Mobile")\n[rendering]\nrenderer/rendering_method="mobile"\n')
elif op=='cold':
 if (P/'.godot').exists():shutil.rmtree(P/'.godot')
elif op=='sync':
 for name in N:
  src=P/K/(name+'.glb.import');dst=ROOT/K/src.name;s=src.read_text()
  assert uid(src)==uid(Q/'before'/src.name)
  assert all(x in s.splitlines() for x in ['nodes/root_script=null','meshes/create_shadow_meshes=true','gltf/texture_map_mode=1'])
  shutil.copy2(src,dst)
else:
 result={}
 for name in N:
  src=P/K/(name+'.glb.import');dst=ROOT/K/src.name
  assert src.read_bytes()==dst.read_bytes();assert uid(src)==uid(Q/'before'/src.name)
  assert (P/K/(name+'.glb')).read_bytes()==(ROOT/K/(name+'.glb')).read_bytes()
  result[name]={'uid':uid(src),'import_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'glb_sha256':hashlib.sha256((ROOT/K/(name+'.glb')).read_bytes()).hexdigest()}
 (Q/'cold-import-validation.json').write_text(json.dumps(result,indent=2)+'\n')
print(op,'six assets')
