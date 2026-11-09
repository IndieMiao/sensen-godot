extends SceneTree
## Run in each fresh, minimal import project; capture the actual Godot import.
func digest(value):
 var ctx=HashingContext.new();ctx.start(HashingContext.HASH_SHA256)
 ctx.update(var_to_bytes(value));return ctx.finish().hex_encode()
func _initialize():
 var scene=load("res://assets/avatar/source/shoes3_npc_gabriel/SK_dt_skin03.fbx")
 assert(scene is PackedScene)
 var node=scene.instantiate();root.add_child(node)
 var report={"meshes":{},"skeletons":{},"animations":{}}
 for mesh_node in node.find_children("*","MeshInstance3D",true,false):
  var mesh:ArrayMesh=mesh_node.mesh
  var surfaces=[]
  for i in mesh.get_surface_count():
   var arrays=mesh.surface_get_arrays(i);var attributes=[]
   for attr in arrays.size():attributes.append(digest(arrays[attr]))
   var mat=mesh.surface_get_material(i)
   surfaces.append({"name":mesh.surface_get_name(i),"arrays_sha256":digest(arrays),"attribute_sha256":attributes,"primitive":mesh.surface_get_primitive_type(i),"material_name":mat.resource_name if mat else ""})
  var binds=[]
  if mesh_node.skin:
   for i in mesh_node.skin.get_bind_count():
    binds.append([mesh_node.skin.get_bind_bone(i),str(mesh_node.skin.get_bind_name(i)),mesh_node.skin.get_bind_pose(i)])
  report.meshes[str(mesh_node.name)]={"surfaces":surfaces,"bounds":str(mesh.get_aabb()),"triangles":mesh.get_faces().size()/3,"skin_bind_count":binds.size(),"skin_bind_sha256":digest(binds),"transform_sha256":digest(mesh_node.transform),"skeleton_path":str(mesh_node.skeleton)}
  if str(mesh_node.name)=="shoes":
   assert(ResourceSaver.save(mesh,"res://imported_shoes_mesh.res")==OK)
   assert(ResourceSaver.save(mesh_node.skin,"res://imported_shoes_skin.res")==OK)
 for skeleton in node.find_children("*","Skeleton3D",true,false):
  var bones=[]
  for i in skeleton.get_bone_count():
   bones.append([skeleton.get_bone_name(i),skeleton.get_bone_parent(i),skeleton.get_bone_rest(i),skeleton.get_bone_pose(i)])
  report.skeletons[str(node.get_path_to(skeleton))]={"bone_count":bones.size(),"names_parents_rest_pose_sha256":digest(bones)}
 for player in node.find_children("*","AnimationPlayer",true,false):
  for name in player.get_animation_list():
   var anim=player.get_animation(name);var tracks=[]
   for i in anim.get_track_count():
    var keys=[]
    for k in anim.track_get_key_count(i):keys.append([anim.track_get_key_time(i,k),anim.track_get_key_value(i,k),anim.track_get_key_transition(i,k)])
    tracks.append([anim.track_get_type(i),str(anim.track_get_path(i)),anim.track_get_interpolation_type(i),keys])
   report.animations[name]={"length":anim.length,"tracks":tracks.size(),"tracks_sha256":digest(tracks)}
 FileAccess.open("res://import-structure.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 node.free();print("IMPORTED_SHOE_STRUCTURE_SAVED");quit()
