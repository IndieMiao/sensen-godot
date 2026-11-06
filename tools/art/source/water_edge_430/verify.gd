extends SceneTree
const ROOT="res://assets/landmarks/_shared/water_edge/"
var checks=[]
func check(ok,label):
 checks.append({"passed":bool(ok),"check":label})
 if not ok:push_error(label)
func _initialize():
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"manifest.json"));var uids=[];var assets={}
 for name in manifest.assets:
  var path=ROOT+name+".glb";var n=load(path).instantiate();var meshes=n.find_children("*","MeshInstance3D",true,false)
  if n is MeshInstance3D:meshes.push_front(n)
  check(meshes.size()==1,name+": one mesh");var mesh=meshes[0].mesh
  check(mesh.get_surface_count()==1,name+": one surface");var a=mesh.surface_get_arrays(0)
  var tris=a[Mesh.ARRAY_INDEX].size()/3;check(tris==int(manifest.assets[name].triangles) and tris<=80,name+": triangle count")
  check(meshes[0].transform.is_equal_approx(Transform3D.IDENTITY),name+": identity transform")
  check(mesh.get_aabb().size.y<.00001 and abs(mesh.get_aabb().position.y)<.00001,name+": waterplane pivot")
  check(Array(a[Mesh.ARRAY_NORMAL]).all(func(x):return x.y>.999),name+": upward normals")
  var mat=mesh.surface_get_material(0);check(mat is ShaderMaterial,name+": shared shader binding")
  check(mat.resource_path==ROOT+"water_edge_material.tres",name+": shared material path")
  check(mat.next_pass==null and mat.render_priority==1,name+": single pass / sea overlay")
  var texture=mat.get_shader_parameter("foam_texture");check(texture.get_size()==Vector2(512,128) and texture.get_image().has_mipmaps(),name+": original size / mipmaps")
  var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=2
  mm.set_instance_transform(0,Transform3D.IDENTITY);mm.set_instance_transform(1,Transform3D(Basis.IDENTITY,Vector3(2,0,0)))
  check(mm.mesh==mesh and mm.instance_count==2,name+": MultiMesh resource")
  var cfg=ConfigFile.new();check(cfg.load(path+".import")==OK,name+": import loaded")
  var uid=cfg.get_value("remap","uid","");check(uid.begins_with("uid://") and uid not in uids,name+": distinct generated uid");uids.append(uid)
  check("nodes/root_script=null" in FileAccess.get_file_as_string(path+".import"),name+": explicit root_script null")
  assets[name]={"triangles":tris,"uid":uid,"aabb":str(mesh.get_aabb()),"material":mat.resource_path,"mesh_arrays_sha256":var_to_bytes(a).hex_encode().sha256_text()};n.free()
 var cfg=ConfigFile.new();assert(cfg.load(ROOT+"water_edge_soft.png.import")==OK)
 check(cfg.get_value("params","compress/mode")==0,"lossless RGBA texture / Android supported")
 var code=FileAccess.get_file_as_string(ROOT+"water_edge.gdshader")
 check(code.count("texture(")==1 and not "hint_depth_texture" in code and not "hint_screen_texture" in code,"exactly one texture read / no depth or screen sampling")
 var result={"passed":checks.all(func(c):return c.passed),"checks":checks,"assets":assets}
 FileAccess.open("res://../import-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
 print("WATER_EDGE_IMPORT ",result.passed," ",checks.size());quit(0 if result.passed else 1)
