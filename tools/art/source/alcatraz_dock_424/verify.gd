extends SceneTree
const ROOT="res://assets/landmarks/alcatraz_island/"
var checks=[]
func check(ok,label):
 checks.append({"check":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"alc_dock_manifest.json"))
 var uids=[];var actual={}
 for name in manifest.assets:
  var path=ROOT+name+".glb";var s=load(path).instantiate();var nodes=s.find_children("*","MeshInstance3D",true,false)
  if s is MeshInstance3D:nodes.push_front(s)
  check(nodes.size()==1,name+": one mesh")
  var m=nodes[0].mesh;check(m.get_surface_count()==1,name+": one surface")
  var arrays=m.surface_get_arrays(0);var count=arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX].size()>0 else arrays[Mesh.ARRAY_VERTEX].size()/3
  check(count==int(manifest.assets[name].triangles) and count<=int(manifest.assets[name].triangle_limit),name+": triangle budget")
  check(nodes[0].transform.is_equal_approx(Transform3D.IDENTITY),name+": identity mesh transform")
  var b=m.get_aabb();check(abs(b.position.y)<.001,name+": grounded pivot")
  check(abs(b.get_center().x)<.001 and abs(b.get_center().z)<.001,name+": centred footprint")
  var mat=m.surface_get_material(0)
  check(mat is BaseMaterial3D and mat.vertex_color_use_as_albedo,name+": imported vertex colour")
  check(mat.roughness>=.9 and mat.metallic==0 and mat.transparency==0,name+": opaque matte material")
  check(mat.albedo_texture==null,name+": no external texture dependency")
  var cfg=ConfigFile.new();check(cfg.load(path+".import")==OK,name+": generated import")
  var uid=cfg.get_value("remap","uid","");check(uid.begins_with("uid://") and uid not in uids,name+": unique UID");uids.append(uid)
  actual[name]={"triangles":count,"aabb":str(b),"mesh_arrays_sha256":var_to_bytes(arrays).hex_encode().sha256_text(),"material_class":mat.get_class(),"vertex_color":mat.vertex_color_use_as_albedo,"material_roughness":mat.roughness,"uid":uid};s.free()
 var passed=checks.all(func(c):return c.passed)
 FileAccess.open("res://../import-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"assets":actual},"\t")+"\n")
 print("ALC_DOCK_IMPORT ",passed," ",checks.size());quit(0 if passed else 1)
