extends Node
const Art:=preload("res://modules/farm/farm_art.gd")
func _ready() -> void:run.call_deferred()
func a(v:Vector3) -> Array:return [v.x,v.y,v.z]
func run() -> void:
 var bp:=P0Garden.blueprint();var house:=bp.cell_to_world(bp.anchor("house"))
 var node=load("res://scenes/p0/p0_garden_scenery.gd").new();get_tree().root.add_child(node);node.build(bp,"cottage")
 await get_tree().process_frame
 await get_tree().process_frame
 var out:={"house":a(house),"scenery":[],"existing_props":[],"fences":{}}
 for n in node.find_children("*","MultiMeshInstance3D",true,false):
  var mm:MultiMesh=n.multimesh
  for i in mm.instance_count:
   var t:Transform3D=n.global_transform*mm.get_instance_transform(i);var box:AABB=t*mm.mesh.get_aabb()
   if box.end.x<house.x-4.5 or box.position.x>house.x+2.5 or box.end.z<house.z-2.0 or box.position.z>house.z+2.0:continue
   out.scenery.append({"name":str(n.name),"index":i,"origin":a(t.origin-house),"bounds":[a(box.position-house),a(box.end-house)],"resource":str(mm.mesh.resource_path)})
 for spec in [["Bench","res://assets/rooms/basic_room/bench.glb",Vector3(-2.275,0,0),1.0],["Mailbox","res://assets/props/mailbox_placeholder/red_post_box.glb",Vector3(1.95,0,0),.65]]:
  var obj:Node3D=load(spec[1]).instantiate();get_tree().root.add_child(obj);obj.position=house+spec[2];obj.scale=Vector3.ONE*spec[3]
  var meshes:=obj.find_children("*","MeshInstance3D",true,false)
  if obj is MeshInstance3D:meshes.push_front(obj)
  var box:AABB;var first:=true
  for m in meshes:
   var b:AABB=m.global_transform*m.mesh.get_aabb();box=b if first else box.merge(b);first=false
  out.existing_props.append({"name":spec[0],"origin":a(obj.position-house),"bounds":[a(box.position-house),a(box.end-house)]});obj.queue_free()
 var fence=load("res://scenes/p0/p0_fence.gd").new();get_tree().root.add_child(fence);fence.build(bp);fence._shown=true
 for look in ["a","b"]:
  fence.set_look(look,false)
  await get_tree().process_frame
  await get_tree().process_frame
  out.fences[look]=[]
  for n in fence.find_children("*","GeometryInstance3D",true,false):
   if not n.is_visible_in_tree():continue
   var instances:Array[Transform3D]=[];var mesh:Mesh
   if n is MultiMeshInstance3D:
    mesh=n.multimesh.mesh
    for i in n.multimesh.instance_count:instances.append(n.global_transform*n.multimesh.get_instance_transform(i))
   elif n is MeshInstance3D:
    mesh=n.mesh;instances.append(n.global_transform)
   else:continue
   for i in instances.size():
    var t:=instances[i];var box:AABB=t*mesh.get_aabb()
    if box.end.x<house.x-4.5 or box.position.x>house.x+2.5 or box.end.z<house.z-2.0 or box.position.z>house.z+2.0:continue
    out.fences[look].append({"name":str(n.name),"index":i,"origin":a(t.origin-house),"bounds":[a(box.position-house),a(box.end-house)]})
 fence.queue_free()
 var found:=false
 for row in out.scenery:
  var origin:=Vector3(row.origin[0],row.origin[1],row.origin[2])
  if origin.distance_to(Vector3(-1.75,0,-.9))<.001:found=true
 if not found:
  push_error("MultiMesh readback did not return the known left shrub; use Vulkan, not headless dummy")
  get_tree().quit(1);return
 out.renderer=RenderingServer.get_current_rendering_method()
 FileAccess.open("res://../native-layout.json",FileAccess.WRITE).store_string(JSON.stringify(out,"\t")+"\n")
 print("HOMESTEAD_LAYOUT ",out.scenery.size()," nearby scenery instances")
 node.queue_free();get_tree().quit()
