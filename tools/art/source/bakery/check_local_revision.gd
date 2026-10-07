extends SceneTree
var meshes:=0
var surfaces:=0
var triangles:=0
func _initialize()->void:call_deferred("verify")
func inspect(n:Node)->void:
 if n is MeshInstance3D:
  meshes+=1
  for i in n.mesh.get_surface_count():
   surfaces+=1
   var indices:int=n.mesh.surface_get_array_index_len(i)
   triangles+=indices/3 if indices>0 else n.mesh.surface_get_array_len(i)/3
 for c in n.get_children():inspect(c)
func verify()->void:
 var room=(load("res://scenes/bakery/bakery_art.tscn") as PackedScene).instantiate();root.add_child(room)
 for i in 4:await physics_frame
 inspect(room)
 var space=room.get_world_3d().direct_space_state
 var capsule:=CapsuleShape3D.new();capsule.radius=.21;capsule.height=1.25
 var clear:=true
 var probes:Array=[]
 for i in range(13):
  var point:=Vector3(.48,.09,-1.20).lerp(Vector3(2.43,.09,-1.64),float(i)/12)
  var q:=PhysicsShapeQueryParameters3D.new();q.shape=capsule;q.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.65)
  var hits=space.intersect_shape(q);clear=clear and hits.is_empty();probes.append({"point":[point.x,point.y,point.z],"clear":hits.is_empty()})
 var passed:=clear and triangles<=200000 and surfaces<=60
 var result={"passed":passed,"scope":"Headless imported mesh/budget and relocated planter checkout-approach capsule checks only. Not a rendered route/video or colour test.","triangles":triangles,"surfaces":surfaces,"mesh_instances":meshes,"checkout_probes":probes}
 var f:=FileAccess.open("res://local-runtime-contract.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));print("LOCAL_CONTRACT ",JSON.stringify(result));quit(0 if passed else 1)
