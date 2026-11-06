extends Node
const SEA="res://assets/landmarks/_shared/sea_backdrop/"
const FOAM="res://assets/landmarks/_shared/water_edge/"
const COAST="res://assets/landmarks/_shared/coast_kit/"
var vp:SubViewport
var world:Node3D
var assembly:Node3D
var camera:Camera3D
var foam_material:ShaderMaterial
var foam_nodes=[]
var report={"checks":[],"captures":[]}
var output:String
var sea:MeshInstance3D
var sea_mat:ShaderMaterial
const FAR="res://assets/landmarks/_shared/far_backdrop/"
var far_nodes=[]
const LIGHTING="res://assets/landmarks/_shared/lighting/"
const PLANTS="res://assets/landmarks/_shared/coast_plants/"
const PRESETS=["warm_noon","cool_morning","golden_dusk"]
var lighting
var preset_index=0
var current_combo=0
var bridge_cool=false
func _ready():run.call_deferred()
func check(ok,label):
 report.checks.append({"passed":bool(ok),"check":label})
 if not ok:push_error(label)
func mesh_of(path):
 var n=load(path).instantiate();var m=n.find_children("*","MeshInstance3D",true,false)
 if n is MeshInstance3D:m.push_front(n)
 var mesh=m[0].mesh;n.free();return mesh
func instance(path,pos,angle=0.0,material=null):
 var node=MeshInstance3D.new();node.mesh=mesh_of(path);node.position=pos;node.rotation_degrees.y=angle
 if material:node.material_override=material
 assembly.add_child(node);return node
func foam(name,pos,angle=0.0,cap=Vector2.ZERO):
 var material=foam_material
 if cap!=Vector2.ZERO:
  material=foam_material.duplicate();material.set_shader_parameter("end_fade_uv",cap)
 var node=MultiMeshInstance3D.new();node.multimesh=MultiMesh.new();node.multimesh.transform_format=MultiMesh.TRANSFORM_3D
 node.multimesh.mesh=mesh_of(FOAM+"water_edge_"+name+".glb");node.multimesh.instance_count=1;node.multimesh.set_instance_transform(0,Transform3D.IDENTITY)
 node.position=pos+Vector3(0,.218,0);node.rotation_degrees.y=angle;node.material_override=material;assembly.add_child(node)
 node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
 foam_nodes.append(node);return node
func box(pos,size,color):
 var n=MeshInstance3D.new();n.mesh=BoxMesh.new();n.mesh.size=size
 var mat=StandardMaterial3D.new();mat.albedo_color=Color(color);mat.roughness=.94;n.material_override=mat;n.position=pos;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;assembly.add_child(n)
func frame(target,width):
 camera.size=width
 var pitch=deg_to_rad(43);var yaw=deg_to_rad(14.5)
 camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*30
 camera.look_at(target)
func capture(name):
 for i in 4:await RenderingServer.frame_post_draw
 var img=vp.get_texture().get_image();check(img.get_size()==vp.size,name+": size")
 check(img.save_png(output+"/"+name+".png")==OK,name+": save")
 report.captures.append({"name":name,"dimensions":[vp.size.x,vp.size.y],"width_m":camera.size,"draws":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"triangles":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"shadow_draws":vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"shadow_triangles":vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
func clock_set(seconds):
 for node in foam_nodes:node.material_override.set_shader_parameter("review_time",seconds)
 sea_mat.set_shader_parameter("review_time",seconds)
func run():
 output=ProjectSettings.globalize_path("user://captures" if OS.has_feature("android") else "res://../captures");DirAccess.make_dir_recursive_absolute(output)
 vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var display=TextureRect.new();display.texture=vp.get_texture();display.size=Vector2(360,800);display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;add_child(display)
 world=Node3D.new();vp.add_child(world);assembly=Node3D.new();world.add_child(assembly)
 lighting=load(LIGHTING+"lighting_rig.tscn").instantiate();world.add_child(lighting)
 # Shared background on the same isolated water plane; host sea is untouched.
 sea=MeshInstance3D.new();sea.mesh=PlaneMesh.new();sea.mesh.size=Vector2(512,512);sea.position.y=.2
 sea_mat=make_sea("bay");sea_mat.render_priority=-100;sea.material_override=sea_mat;sea.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;world.add_child(sea)
 # Owner #831 v1.1 opaque wet band, with the fixture water level.
 var wet=load(COAST+"coast_cool_gray.tres").duplicate(true)
 wet.set_shader_parameter("water_level",.2)
 # Unchanged steps export stores vertex paint; its imported default disables that flag.
 var steps_mat=StandardMaterial3D.new();steps_mat.vertex_color_use_as_albedo=true;steps_mat.roughness=.94;steps_mat.metallic_specular=.15
 foam_material=load(FOAM+"water_edge_material.tres").duplicate(true)
 var shader=Shader.new();shader.code=foam_material.shader.code.replace("void vertex()", "uniform float review_time=0.0;\nvoid vertex()").replace("TIME", "review_time");foam_material.shader=shader
 # 6 nominal 2m slots: four shore pieces, two turns, stair access occupies one straight slot.
 var pieces=[['straight',Vector3(-2,0,4),0],['outer',Vector3(0,0,4),0],['straight',Vector3(0,0,2),90],['inner',Vector3(0,0,0),90],['steps',Vector3(2,0,0),0],['straight',Vector3(4,0,0),0]]
 for i in pieces.size():
  var p=pieces[i];var asset="coast_water_steps" if p[0]=="steps" else "coast_rock_"+p[0]+("_high" if i==2 else "_low")
  instance(COAST+asset+".glb",p[1],p[2],steps_mat if p[0]=="steps" else wet)
  var cap=Vector2(.12,0) if i==0 else Vector2(0,.12) if i==5 else Vector2.ZERO
  # The stair outlet ends at the adjoining rocks; fade its two free short ends.
  if p[0]=="steps":cap=Vector2.ZERO
  if i==3:cap=Vector2.ZERO
  if i==5:cap=Vector2(0,.12)
  foam(p[0],p[1],p[2],cap)
 box(Vector3(-1.55,.28,1.3),Vector3(1.7,.56,5.4),"8c9e6b")
 box(Vector3(1.45,.28,-1.5),Vector3(7.1,.56,1.8),"8c9e6b")
 var dock_mat=load(COAST+"coast_warm_sand.tres").duplicate(true);dock_mat.set_shader_parameter("water_level",.2)
 for z in [5.0,7.0]:instance(COAST+"coast_dock_straight.glb",Vector3(-2,0,z),90,dock_mat)
 # Only seaward piles receive rings. No rings over the shoreline ribbon.
 for x in [-2.72,-1.28]:foam("pile_ring",Vector3(x,0,7.66))
 var plant_rows=[
  ["coast_shrub_b",Vector3(-1.45,.56,1.7),20],
  ["coast_shrub_a",Vector3(-1.55,.56,.0),-30],
  ["coast_grass_a",Vector3(-1.8,.56,3.15),35],
  ["coast_grass_b",Vector3(3.7,.56,-1.45),-40],
  ["coast_iceplant_a",Vector3(1.8,.56,-1.2),0],
  ["coast_iceplant_b",Vector3(.3,.56,-1.45),-20]]
 for p in plant_rows:instance(PLANTS+p[0]+".glb",p[1],p[2])
 var actor=Node3D.new();actor.position=Vector3(-2,1.2,6.7);assembly.add_child(actor)
 var rig=Avatar.create_rig();rig.assembler=AvatarAssemblerMerged.new();actor.add_child(rig);rig.apply_config(Avatar.load_outfit())
 for i in 12:await get_tree().process_frame
 var waits=0
 while rig.is_busy() and waits<600:waits+=1;await get_tree().process_frame
 check(not rig.is_busy(),"avatar assembled")
 var bound=AABB();var first=true
 for m in rig.find_children("*","MeshInstance3D",true,false):
  var b=actor.global_transform.affine_inverse()*m.global_transform*m.get_aabb()
  if first:bound=b;first=false
  else:bound=bound.merge(b)
 actor.scale=Vector3.ONE*1.75/bound.size.y;rig.play_motion("idle")
 for i in 20:await get_tree().process_frame
 rig.process_mode=Node.PROCESS_MODE_DISABLED
 assembly.rotation_degrees.y=65
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.far=150;world.add_child(camera);camera.make_current()
 frame(assembly.to_global(Vector3(.2,.2,2.6)),6.72)
 build_combo(0)
 if OS.has_feature("android"):
  await android_start();return
 clock_set(0)
 # Compare the original scene's exact environment/sun with the extracted noon.
 var env=lighting.get_node("Environment");var sun=lighting.get_node("Sun")
 apply_original(env,sun)
 await capture("original-noon");var original=vp.get_texture().get_image()
 set_preset(0)
 await capture("warm-noon-default-review");var noon=vp.get_texture().get_image()
 report.noon_parity=diff(original,noon)
 check(report.noon_parity.maximum_rgb_255==0.0,"warm noon equals original lighting pixel-for-pixel")
 for i in 3:
  set_preset(i)
  var prefix=["warm-noon","cool-morning","golden-dusk"][i]
  if i>0:await capture(prefix+"-default-review")
  sun.shadow_enabled=false;await capture(prefix+"-shadow-off");sun.shadow_enabled=true
 report.renderer={"engine":Engine.get_version_info().string,"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
 report.budget={"directional_lights":1,"world_environments":1,"shadow_cascades":1,"shadow_map_size":2048,"filter_quality":2,"ssao":false,"ssr":false,"sdfgi":false,"volumetric_fog":false,"fog":false,"glow":false,"runtime_process_callbacks":0}
 # Uncapped, interleaved viewport timing. TIME is frozen only in desktop review.
 if "--benchmark" in OS.get_cmdline_user_args():await benchmark()
 report.passed=report.checks.all(func(c):return c.passed)
 FileAccess.open(output+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 print("LIGHTING_RENDER ",report.passed);get_tree().quit(0 if report.passed else 1)

func set_preset(index):
 preset_index=index
 lighting.preset=load(LIGHTING+PRESETS[index]+".tres")
func apply_original(env,sun):
 env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("d000d0")
 env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("d5e4ee");env.environment.ambient_light_energy=.72
 sun.rotation_degrees=Vector3(-56,-34,0);sun.light_color=Color(1,.965,.88);sun.light_energy=.98
 sun.shadow_enabled=true;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.directional_shadow_max_distance=120.0
 sun.shadow_opacity=.48;sun.shadow_bias=.035;sun.shadow_normal_bias=.28
func benchmark():
 RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(),true)
 report.timing=[]
 for cycle in 3:
  # Reverse ordering every other cycle to reduce thermal/order bias.
  var order=[-1,0,1,2] if cycle%2==0 else [2,1,0,-1]
  for index in order:
   if index<0:apply_original(lighting.get_node("Environment"),lighting.get_node("Sun"))
   else:set_preset(index)
   for i in 45:await RenderingServer.frame_post_draw
   var cpu=[];var gpu=[]
   for i in 90:
    await RenderingServer.frame_post_draw
    cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()))
    gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
   report.timing.append({"cycle":cycle,"preset":"original" if index<0 else PRESETS[index],"cpu_ms":cpu,"gpu_ms":gpu})

func make_sea(preset):
 var material=load(SEA+preset+".tres").duplicate(true)
 if not OS.has_feature("android"):
  var shader=Shader.new();shader.code=material.shader.code.replace("void vertex()", "uniform float review_time=0.0;\nvoid vertex()").replace("TIME", "review_time");material.shader=shader
 return material
func build_combo(index):
 for n in far_nodes:n.free()
 far_nodes.clear();current_combo=index;bridge_cool=false
 var rows=[["far_hills_a",0.0,.84],["far_city_high",1.23,.82],["far_bridge",-2.1,1.0]] if index==0 else [["far_hills_b",0.0,.84],["far_city_medium",-1.56,.64],["far_city_low",1.62,.64]]
 for row in rows:
  var node=MeshInstance3D.new();node.name=row[0];node.mesh=mesh_of(FAR+row[0]+".glb")
  node.material_override=node.mesh.surface_get_material(0).duplicate(true)
  node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;node.extra_cull_margin=100
  var view_height=camera.size*vp.size.y/vp.size.x
  node.position=camera.global_transform*Vector3(row[1],view_height*(.5-.16),-60)
  node.scale=Vector3.ONE*row[2];world.add_child(node);far_nodes.append(node)
func recolor_bridge(cool):
 bridge_cool=cool
 for n in far_nodes:
  if n.name=="far_bridge":
   if cool:
    n.material_override.set_shader_parameter("base_color",Color("779ba7"));n.material_override.set_shader_parameter("accent_color",Color("9ebbc1"));n.material_override.set_shader_parameter("shadow_color",Color("557c8d"))
   else:n.material_override=load(FAR+"bridge.tres").duplicate(true)
func diff(a,b):
 var total=0.0;var peak=0.0;var count=0
 for y in a.get_height():
  for x in a.get_width():
   var c=a.get_pixel(x,y);var d=b.get_pixel(x,y);var v=max(abs(c.r-d.r),max(abs(c.g-d.g),abs(c.b-d.b)));total+=v;peak=max(peak,v);count+=int(v>1.0/255)
 return {"maximum_rgb_255":peak*255,"mean_rgb_255":total*255/(a.get_width()*a.get_height()),"pixels_over_one":count}
func android_state():
 for i in 4:await RenderingServer.frame_post_draw
 var state={"pid":OS.get_process_id(),"preset":PRESETS[preset_index],"index":preset_index,"kit":"437-v1","renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"button_next":[180,760],"draws":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
 FileAccess.open("user://lighting_state.json",FileAccess.WRITE).store_string(JSON.stringify(state))
 vp.get_texture().get_image().save_png("user://lighting_%s.png"%PRESETS[preset_index])
func android_start():
 for n in foam_nodes:n.material_override.shader=load(FOAM+"water_edge.gdshader")
 var button=Button.new();button.text="Next lighting preset";button.position=Vector2(48,738);button.size=Vector2(264,44);add_child(button)
 button.pressed.connect(func():set_preset((preset_index+1)%3);android_state())
 set_preset(0);await android_state()
