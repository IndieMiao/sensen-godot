extends SceneTree
func _initialize() -> void:
 call_deferred("verify")
func vec(a:Array)->Vector3: return Vector3(float(a[0]),float(a[1]),float(a[2]))
func verify()->void:
 var room=(load("res://scenes/deluxe_room_10/deluxe_room_10_art.tscn") as PackedScene).instantiate()
 root.add_child(room)
 for i in 4: await physics_frame
 var layout:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/deluxe_room_10/layout.json"))
 var checks:Array=[]
 var passed:=true
 for a in layout.anchors:
  var marker=room.find_child(str(a.name),true,false) as Marker3D
  var entry:Dictionary={"name":a.name,"exists":marker!=null}
  if marker:
   entry.position_error_m=marker.global_position.distance_to(vec(a.position))
   entry.up_dot=marker.global_basis.y.normalized().dot(Vector3.UP)
   entry.module=marker.get_parent().name if marker.get_parent()!=room else null
   entry.module_matches=not a.has("module") or str(marker.get_parent().name)==str(a.module)
   if a.has("yaw_degrees"):
    entry.yaw_error=absf(wrapf(rad_to_deg(marker.global_rotation.y)-float(a.yaw_degrees),-180,180))
   if str(a.name).begins_with("stand_") or a.name=="spawn":
    var capsule:=CapsuleShape3D.new();capsule.radius=.21;capsule.height=1.25
    var q:=PhysicsShapeQueryParameters3D.new();q.shape=capsule;q.transform=Transform3D(Basis.IDENTITY,marker.global_position+Vector3.UP*.65)
    var space=room.get_world_3d().direct_space_state
    var hits=space.intersect_shape(q);entry.capsule_clear=hits.is_empty();entry.blockers=[]
    for hit in hits:entry.blockers.append(str(hit.collider.get_path()))
    var ray:=PhysicsRayQueryParameters3D.create(marker.global_position+Vector3.UP*.18,marker.global_position-Vector3.UP*.25)
    var floor_hit=space.intersect_ray(ray);entry.supported_floor=not floor_hit.is_empty() and floor_hit.normal.y>.7
   entry.passed=entry.position_error_m<.0001 and entry.up_dot>.999 and entry.module_matches and float(entry.get("yaw_error",0))<.001 and bool(entry.get("capsule_clear",true)) and bool(entry.get("supported_floor",true))
  else:entry.passed=false
  passed=passed and entry.passed;checks.append(entry)
 var result={"passed":passed,"checks":checks,"scope":"Headless instantiated-art marker, module/yaw and standing physics contract only; no new rendered art/movement claim."}
 var f:=FileAccess.open("res://anchor-runtime-verification.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"))
 print("ANCHOR_RUNTIME_CHECK ",JSON.stringify(result));quit(0 if passed else 1)
