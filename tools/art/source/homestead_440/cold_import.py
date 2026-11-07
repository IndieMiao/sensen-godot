"""Cold-import the two assets in a disposable project; assert source/import stability."""
from pathlib import Path
import hashlib,json,shutil,subprocess
ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'output/homestead-440';QA=OUT/'cold-project'
if QA.exists():shutil.rmtree(QA)
(QA/'assets/farm/art').mkdir(parents=True)
files=[Path('assets/farm/art')/(n+s) for n in ['master_farmhouse_a','master_farmhouse_b'] for s in ['.glb','.glb.import']]
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before={str(p):digest(ROOT/p) for p in files}
for p in files:shutil.copy2(ROOT/p,QA/p)
(QA/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Homestead440 Cold Import"\n[rendering]\nrenderer/rendering_method="mobile"\n')
(QA/'verify.gd').write_text('''extends SceneTree
func _initialize():
 for id in ["master_farmhouse_a","master_farmhouse_b"]:
  var scene=load("res://assets/farm/art/"+id+".glb")
  assert(scene is PackedScene)
  var node=scene.instantiate();var meshes=node.find_children("*","MeshInstance3D",true,false)
  if node is MeshInstance3D:meshes.push_front(node)
  assert(meshes.size()==1)
  assert(meshes[0].mesh.get_surface_count()==1)
  assert(meshes[0].mesh.get_faces().size()/3<=9000)
  assert(meshes[0].mesh.get_aabb().end.y<=4.2)
  assert(node.get_script()==null)
  node.free()
 print("COLD_RESOURCE_PASS");quit()
''')
godot=shutil.which('godot') or '/home/deck/.local/bin/godot'
# Hold this lock for the full import and resource check.
cmd=['flock','/home/deck/gs66-render.lock',godot,'--headless','--path',str(QA)]
logs=[]
for args in [['--editor','--import'],['--script','res://verify.gd']]:
 result=subprocess.run(cmd+args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True);logs.append(result.stdout)
 assert result.returncode==0,result.stdout
 assert 'ERROR:' not in result.stdout and 'SCRIPT ERROR' not in result.stdout,result.stdout
assert 'COLD_RESOURCE_PASS' in logs[-1]
for p in files:assert digest(QA/p)==before[str(p)] and digest(ROOT/p)==before[str(p)],str(p)
(OUT/'cold-import.log').write_text('\n'.join(logs))
report={'passed':True,'godot':'4.7.2','source_and_import_hashes_unchanged':True,'files':before,'scope':'New assets with empty .godot cache; no class registry or existing import cache.'}
(OUT/'cold-import.json').write_text(json.dumps(report,indent=2)+'\n');print('COLD_IMPORT_PASS')
