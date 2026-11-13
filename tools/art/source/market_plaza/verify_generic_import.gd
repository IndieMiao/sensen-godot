extends SceneTree
func _initialize():call_deferred("check")
func check():
 var reports={}
 for variant in ["san_francisco","generic"]:
  var art=load("res://scenes/market_plaza/market_plaza_art.tscn").instantiate()
  art.city_variant=variant;root.add_child(art)
  await process_frame
  var count=0
  for m in art.get_node("FarFacades").find_children("*","MeshInstance3D",true,false):
   assert(m.mesh.get_surface_count()==1);count+=1
  assert(count==8)
  var colliders=[]
  for c in art.find_children("*","CollisionShape3D",true,false):
   colliders.append({"body_name":str(c.get_parent().name),"position":str(c.global_transform),"shape":str(c.shape.size) if c.shape is BoxShape3D else [c.shape.radius,c.shape.height]})
  reports[variant]={"facade_instances":count,"colliders":colliders}
  art.queue_free();await process_frame
 FileAccess.open("res://assembly-check.json",FileAccess.WRITE).store_string(JSON.stringify(reports,"  "))
 if reports.san_francisco.colliders!=reports.generic.colliders:
  push_error("Collision shapes differ between variants");quit(1);return
 print("GENERIC_COLD_ASSEMBLY_PASS 8+8 facade meshes; 1 surface each; identical collision shapes")
 quit()
