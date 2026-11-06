extends Node
const ROOT="res://assets/landmarks/_shared/ground_detail/"
const KEYS=["86A84F","DFCBA7","BB8B52","D4C096","9B8F70"]
var material=preload(ROOT+"ground_palette_example.tres")
var terrain:MeshInstance3D
var vp:SubViewport
var camera:Camera3D
var output:String
var report={"checks":[],"captures":[]}
var view_index=0
var button:Button

func _ready():run.call_deferred()
func check(ok,label):
 report.checks.append({"passed":bool(ok),"check":label})
 if not ok:push_error(label)
func pad():
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 # 20 x 20 m gently graded terrain; no production model, UV, collision or layout.
 for band in 5:
  st.set_color(Color(KEYS[band]).srgb_to_linear())
  st.set_normal(Vector3(0,1,0.025).normalized())
  for iz in 8:
   for ix in 40:
    var x=-10+ix*0.5;var z=-10+band*4+iz*0.5
    for p in [Vector2(x,z),Vector2(x+0.5,z),Vector2(x,z+0.5),Vector2(x+0.5,z),Vector2(x+0.5,z+0.5),Vector2(x,z+0.5)]:
     st.add_vertex(Vector3(p.x,(10-p.y)*0.025,p.y))
 terrain=MeshInstance3D.new();terrain.mesh=st.commit();terrain.material_override=material;vp.add_child(terrain)
func setup():
 vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
 vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var display=TextureRect.new();display.texture=vp.get_texture();display.size=Vector2(360,800);add_child(display)
 var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
 env.environment.background_color=Color("d5e0e4");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color=Color("d5e4ee");env.environment.ambient_light_energy=0.72;vp.add_child(env)
 var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-56,-34,0);sun.light_color=Color(1,0.965,0.88)
 sun.light_energy=0.98;sun.shadow_enabled=true;sun.shadow_opacity=0.48;sun.directional_shadow_max_distance=120;vp.add_child(sun)
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
 camera.far=200;vp.add_child(camera);camera.current=true
 pad();set_view("default")
func set_view(name):
 var target=Vector3(0,0.25,0)
 var width=6.72
 vp.size=Vector2i(360,800)
 if name=="whole":width=28;vp.size=Vector2i(1000,1000)
 if name=="grass_close":target=Vector3(0,0.45,-8);width=8;vp.size=Vector2i(1000,650)
 if name=="hard_close":target=Vector3(0,0.3,-2);width=5.5;vp.size=Vector2i(1000,800)
 if name=="sand_close":target=Vector3(0,0.08,6);width=6;vp.size=Vector2i(1000,800)
 camera.size=width
 var pitch=deg_to_rad(43.0);var yaw=deg_to_rad(14.5)
 camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*40
 camera.look_at(target)
func capture(name):
 for i in 8:await RenderingServer.frame_post_draw
 var img=vp.get_texture().get_image()
 check(img.save_png(output+"/"+name+".png")==OK,"save "+name)
 report.captures.append({"name":name,"size":[vp.size.x,vp.size.y],"camera_width_m":camera.size,"pitch":43,"yaw":14.5,
 "visible_draw_calls":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
 print("GROUND_KIT_CAPTURE ",name)
 return img
func android_state():
 var state={"pid":OS.get_process_id(),"kit":"428-v1","view":view_index,"renderer":RenderingServer.get_current_rendering_method(),
 "button": [button.position.x+button.size.x/2,button.position.y+button.size.y/2],"size":[vp.size.x,vp.size.y]}
 FileAccess.open("user://ground_state.json",FileAccess.WRITE).store_string(JSON.stringify(state))
func change_android_view():
 view_index=(view_index+1)%3
 var targets=[Vector3(0,.25,0),Vector3(0,.45,-8),Vector3(0,.08,6)]
 set_view("default");camera.position+=targets[view_index]-Vector3(0,.25,0)
 if view_index>0:camera.size=4.5
 android_state()
func run():
 setup()
 if OS.has_feature("android"):
  button=Button.new();button.text="Next material view";button.position=Vector2(70,740);button.size=Vector2(220,48)
  button.pressed.connect(change_android_view);add_child(button)
  for i in 20:await RenderingServer.frame_post_draw
  android_state();return
 output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
 var diagnostic=material.duplicate();diagnostic.shader=load("res://diagnostic.gdshader")
 var neutral=material.duplicate()
 for key in ["grass_deep_color","grass_base_color","grass_sun_color","sand_color","wet_sand_color","tide_color"]:
  neutral.set_shader_parameter(key,Color("86A84F"))
 for key in ["grass_detail_strength","sand_macro_strength","sand_grain_strength","tide_band_strength"]:neutral.set_shader_parameter(key,0.0)
 neutral.set_shader_parameter("wet_roughness",0.94)
 for view in ["default","whole","grass_close","hard_close","sand_close"]:
  set_view(view);terrain.material_override=material;await capture(view)
  terrain.material_override=diagnostic;await capture(view+"-classes")
  terrain.material_override=neutral;await capture(view+"-lighting")
 # Confirm static detail and the pure vertex-colour fallback.
 set_view("default");terrain.material_override=material
 var first=await capture("static-a");var second=await capture("static-b")
 check(first.get_data()==second.get_data(),"static material: byte-identical rendered frames")
 material.set_shader_parameter("strength",0.0);var zero=await capture("zero")
 var original=StandardMaterial3D.new();original.vertex_color_use_as_albedo=true;original.roughness=.94;original.metallic_specular=.15
 terrain.material_override=original;var original_img=await capture("vertex-original")
 var total=0.0;var maximum=0.0
 for y in zero.get_height():
  for x in zero.get_width():
   var a=zero.get_pixel(x,y);var b=original_img.get_pixel(x,y)
   var d=max(abs(a.r-b.r),max(abs(a.g-b.g),abs(a.b-b.b)))*255.0
   total+=d;maximum=max(maximum,d)
 report.zero_control={"mean_max_rgb_255":total/(zero.get_width()*zero.get_height()),"max_rgb_255":maximum}
 check(maximum<1.001 and report.zero_control.mean_max_rgb_255<0.01,"strength zero matches vertex material within 8-bit rounding")
 material.set_shader_parameter("strength",1.0)
 # Changing identification keys in a .tres is sufficient; unmatched colour falls back.
 var alternate=material.duplicate();alternate.set_shader_parameter("grass_key",Color("ff0000"))
 terrain.material_override=alternate;await capture("unmatched-key")
 alternate.set_shader_parameter("finish_kind",1);await capture("forced-grass")
 report.renderer={"engine":Engine.get_version_info().string,"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
 report.terrain={"dimensions_m":[20,20],"triangles":3200,"surfaces":1,"uv_required":false}
 report.passed=report.checks.all(func(c):return c.passed)
 FileAccess.open(output+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 get_tree().quit(0 if report.passed else 1)
