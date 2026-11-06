extends SceneTree
const ROOT="res://assets/landmarks/_shared/ground_detail/"
func _initialize():
 var records=[]
 var names=["palette_example","grass","paving","wood","sand","wet_sand"]
 for i in names.size():
  var mat=load(ROOT+"ground_"+names[i]+".tres") as ShaderMaterial
  assert(mat!=null and mat.shader!=null)
  assert(mat.get_shader_parameter("finish_kind")==i)
  var textures={}
  for key in ["fields","surfaces"]:
   var tex=mat.get_shader_parameter(key) as Texture2D
   assert(tex!=null and tex.get_size()==Vector2(1024,1024))
   assert(tex.get_image().has_mipmaps())
   textures[key]={"path":tex.resource_path,"size":[1024,1024],"mipmaps":true}
  records.append({"preset":names[i],"kind":i,"textures":textures,"shader_sha256":mat.shader.code.sha256_text()})
 var output="user://" if OS.has_feature("android") else "res://../"
 FileAccess.open(output+"resource-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"materials":records},"\t")+"\n")
 print("GROUND_KIT_RESOURCES_PASS")
 quit()
