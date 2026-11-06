extends SceneTree
const ROOT="res://assets/landmarks/alcatraz_island/"
var checks=[]
func check(ok,label):
 checks.append({"passed":bool(ok),"check":label})
 if not ok:push_error(label)
func _initialize():
 var m=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"alc_shore_foam_manifest.json"));var uids=[];var actual={}
 for name in m.assets:
  var spec=m.assets[name];var path=ROOT+name+".glb";var n=load(path).instantiate();var meshes=n.find_children("*","MeshInstance3D",true,false)
  if n is MeshInstance3D:meshes.push_front(n)
  check(meshes.size()==1,name+": one mesh");var mesh=meshes[0].mesh
  check(mesh.get_surface_count()==1,name+": one surface");var arrays=mesh.surface_get_arrays(0);var triangles=arrays[Mesh.ARRAY_INDEX].size()/3
  check(triangles==int(spec.triangles) and triangles<=int(spec.triangle_limit),name+": triangle budget")
  check(meshes[0].transform.is_equal_approx(Transform3D.IDENTITY),name+": identity mesh transform")
  var bounds=mesh.get_aabb();check(abs(bounds.get_center().x)<.001 and abs(bounds.get_center().z)<.001,name+": horizontal pivot")
  var mat=mesh.surface_get_material(0);check(mat is StandardMaterial3D,name+": imported standard material")
  var foam=str(name).begins_with("alc_foam")
  if foam:
   check(bounds.size.y<.00001 and abs(bounds.position.y)<.00001,name+": water-plane pivot")
   check(mat.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA and mat.depth_draw_mode==BaseMaterial3D.DEPTH_DRAW_DISABLED,name+": alpha blend without depth writes")
   check(mat.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED and mat.render_priority==1,name+": static unshaded overlay after sea")
   check(mat.albedo_texture!=null and mat.albedo_texture.get_size()==Vector2(512,128),name+": shared original foam texture")
   check(mat.albedo_texture.get_image().has_mipmaps(),name+": mipmapped soft edges")
   check(Array(arrays[Mesh.ARRAY_NORMAL]).all(func(x):return x.y>.99),name+": up-facing normals")
  else:
   check(mat.transparency==0 and mat.roughness>=.9 and mat.vertex_color_use_as_albedo,name+": opaque matte vertex colour")
   check(bounds.position.y<0 and bounds.end.y>0,name+": floating waterline pivot")
  var c=ConfigFile.new();check(c.load(path+".import")==OK,name+": generated import")
  var uid=c.get_value("remap","uid","");check(uid.begins_with("uid://") and uid not in uids,name+": unique UID");uids.append(uid)
  actual[name]={"triangles":triangles,"aabb":str(bounds),"mesh_arrays_sha256":var_to_bytes(arrays).hex_encode().sha256_text(),"material_path":mat.resource_path,"material_class":mat.get_class(),"alpha":mat.albedo_color.a,"transparency":mat.transparency,"unshaded":mat.shading_mode==0,"depth_draw_mode":mat.depth_draw_mode,"render_priority":mat.render_priority,"uid":uid};n.free()
 var passed=checks.all(func(c):return c.passed)
 FileAccess.open("res://../import-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"assets":actual},"\t")+"\n")
 print("ALC_FOAM_IMPORT ",passed," ",checks.size());quit(0 if passed else 1)
