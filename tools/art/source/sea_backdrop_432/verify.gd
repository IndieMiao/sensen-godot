extends SceneTree
const ROOT="res://assets/landmarks/_shared/sea_backdrop/"
var checks=[]
func check(ok,label):
 checks.append({"passed":bool(ok),"check":label})
 if not ok:push_error(label)
func _initialize():
 var source=FileAccess.get_file_as_string("res://original_sea.gdshader")
 var current=FileAccess.get_file_as_string(ROOT+"sea_backdrop.gdshader")
 check(source.count("sin(")==5 and current.count("sin(")==5,"same five sine evaluations")
 check(source.count("texture(")==0 and current.count("texture(")==0,"zero texture reads retained")
 check(not "sampler2D" in current and not "hint_screen_texture" in current and not "hint_depth_texture" in current,"no texture / scene-depth / screen resources")
 check(source.split("\n")[1]==current.split("\n")[1],"same render modes / depth / culling / blend")
 var required=["shallow_color","deep_color","far_color","ripple_wavelength_m","color_patch_scale","motion_speed","ripple_strength","far_fade_screen_y","far_color_amount","reveal_far_background"]
 var presets={}
 for name in ["bay","lake"]:
  var mat=load(ROOT+name+".tres")
  check(mat is ShaderMaterial,name+": native ShaderMaterial")
  check(mat.shader.resource_path==ROOT+"sea_backdrop.gdshader",name+": shared shader")
  check(mat.next_pass==null and mat.render_priority==0,name+": one pass before foam priority 1")
  for key in required:check(mat.get_shader_parameter(key)!=null,name+": parameter "+key)
  check(not mat.get_shader_parameter("reveal_far_background"),name+": opaque default horizon")
  check(mat.get_shader_parameter("ripple_wavelength_m")>0,name+": nonzero ripple wavelength")
  check(mat.get_shader_parameter("far_fade_screen_y").y>mat.get_shader_parameter("far_fade_screen_y").x,name+": ordered fade range")
  var plane=PlaneMesh.new();plane.size=Vector2(512,512);plane.material=mat
  check(plane.get_surface_count()==1,name+": one standard plane surface")
  presets[name]={"shallow":mat.get_shader_parameter("shallow_color").to_html(),"deep":mat.get_shader_parameter("deep_color").to_html(),"far":mat.get_shader_parameter("far_color").to_html(),"ripple_wavelength_m":mat.get_shader_parameter("ripple_wavelength_m"),"speed":mat.get_shader_parameter("motion_speed")}
 check(presets.bay.shallow!=presets.lake.shallow and presets.bay.deep!=presets.lake.deep,"distinct bay / lake palette")
 check(presets.lake.ripple_wavelength_m>presets.bay.ripple_wavelength_m and presets.lake.speed<presets.bay.speed,"lake wider slower ripples")
 var uid=FileAccess.get_file_as_string(ROOT+"sea_backdrop.gdshader.uid").strip_edges();check(uid.begins_with("uid://"),"generated shader uid")
 var result={"passed":checks.all(func(c):return c.passed),"checks":checks,"presets":presets,"shader_uid":uid,"import_note":"Native .gdshader/.tres only; no new GLB or texture, so no .import or root_script entry is applicable."}
 FileAccess.open("res://../resource-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
 print("SEA_BACKDROP_RESOURCES ",result.passed," ",checks.size());quit(0 if result.passed else 1)
