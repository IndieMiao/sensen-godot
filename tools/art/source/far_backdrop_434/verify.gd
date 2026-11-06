extends SceneTree
const KIT="res://assets/landmarks/_shared/far_backdrop/"
var checks=[]
func check(ok,label):
 checks.append({"passed":bool(ok),"check":label})
 if not ok:push_error(label)
func _initialize():
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(KIT+"manifest.json"))
 var source=FileAccess.get_file_as_string(KIT+"far_card.gdshader")
 var old=FileAccess.get_file_as_string("res://original_far.gdshader")
 check(source.split("\n")[1]==old.split("\n")[1],"same unshaded / double-sided / blend / no-depth-write modes")
 check(not "texture(" in source and not "sampler" in source,"zero texture reads and no sampler")
 var total=0
 for name in manifest.assets:
  var scene=load(KIT+name+".glb").instantiate()
  var meshes=scene.find_children("*","MeshInstance3D",true,false)
  if scene is MeshInstance3D:meshes.push_front(scene)
  check(meshes.size()==1,name+": one imported mesh")
  var node=meshes[0];var mesh=node.mesh
  check(mesh.get_surface_count()==1,name+": one surface")
  var mat=mesh.surface_get_material(0)
  check(mat is ShaderMaterial and mat.shader.resource_path==KIT+"far_card.gdshader",name+": shared shader stored on mesh for reuse")
  check(mat.next_pass==null,name+": one pass")
  check(node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,name+": no shadow pass")
  check(node.extra_cull_margin==100,name+": projected geometry culling margin")
  var a=mesh.surface_get_arrays(0);var tri=a[Mesh.ARRAY_INDEX].size()/3;total+=tri
  check(tri==manifest.assets[name].triangles,name+": imported triangle count")
  var cfg=ConfigFile.new();assert(cfg.load(KIT+name+".glb.import")==OK)
  check(str(cfg.get_value("remap","uid")).begins_with("uid://"),name+": generated import uid")
  check("nodes/root_script=null" in FileAccess.get_file_as_string(KIT+name+".glb.import") and scene.get_script()==null,name+": root_script=null")
  check(not cfg.get_value("params","meshes/generate_lods"),name+": one static card LOD")
  scene.free()
 for combo in manifest.recommended_combinations:
  var tri=0
  for name in manifest.recommended_combinations[combo]:tri+=manifest.assets[name].triangles
  check(tri<=826 and manifest.recommended_combinations[combo].size()==3,combo+": <= original 826 triangles / 3 surfaces")
 for kind in ["city","hills","bridge"]:
  var mat=load(KIT+kind+".tres")
  for key in ["base_color","accent_color","shadow_color","fog_color","fog_amount","depth_fraction"]:
   check(mat.get_shader_parameter(key)!=null,kind+": configurable "+key)
 var result={"passed":checks.all(func(c):return c.passed),"checks":checks,"unique_triangles":total,"assets":manifest.assets.size()}
 FileAccess.open("res://../resource-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
 print("FAR_RESOURCES ",result.passed," ",checks.size());quit(0 if result.passed else 1)
