extends SceneTree
const ROOT="res://assets/landmarks/alcatraz_island/ground/"
func _initialize():
 var records=[]
 for name in ["alc_terrain_detail","alc_dock_detail"]:
  var material=load(ROOT+name+".tres") as ShaderMaterial
  assert(material!=null and material.shader!=null)
  var expected=0 if name=="alc_terrain_detail" else 1
  assert(material.get_shader_parameter("finish_kind")==expected)
  if expected==0:
   assert(material.get_shader_parameter("grass_deep_color").is_equal_approx(Color("527E35")))
   assert(material.get_shader_parameter("grass_base_color").is_equal_approx(Color("78A044")))
   assert(material.get_shader_parameter("grass_sun_color").is_equal_approx(Color("A2B95D")))
  var textures={}
  for key in ["fields","surfaces"]:
   var tex=material.get_shader_parameter(key) as Texture2D
   assert(tex!=null and tex.get_size()==Vector2(1024,1024))
   assert(tex.get_image().has_mipmaps())
   textures[key]={"path":tex.resource_path,"size":[tex.get_width(),tex.get_height()],"mipmaps":true}
  records.append({"name":name,"finish_kind":expected,"textures":textures,"shader_sha256":material.shader.code.sha256_text()})
 FileAccess.open("res://../package-resource-validation.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"materials":records},"\t")+"\n")
 print("ALC_GROUND_PACKAGED_RESOURCES_PASS")
 quit()
