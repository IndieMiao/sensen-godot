extends Node
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
 var mat=StandardMaterial3D.new();mat.albedo_color=Color(color);mat.roughness=.94;n.material_override=mat;n.position=pos;assembly.add_child(n)
func frame(target,width):
 camera.size=width
 var pitch=deg_to_rad(43);var yaw=deg_to_rad(14.5)
 camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*30
 camera.look_at(target)
func capture(name):
 for i in 4:await RenderingServer.frame_post_draw
 var img=vp.get_texture().get_image();check(img.get_size()==vp.size,name+": size")
 check(img.save_png(output+"/"+name+".png")==OK,name+": save")
 report.captures.append({"name":name,"dimensions":[vp.size.x,vp.size.y],"width_m":camera.size,"draws":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"triangles":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
func clock_set(seconds):
 for node in foam_nodes:node.material_override.set_shader_parameter("review_time",seconds)
func run():
 output=ProjectSettings.globalize_path("user://captures" if OS.has_feature("android") else "res://../captures");DirAccess.make_dir_recursive_absolute(output)
 vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var display=TextureRect.new();display.texture=vp.get_texture();display.size=Vector2(360,800);display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;add_child(display)
 world=Node3D.new();vp.add_child(world);assembly=Node3D.new();world.add_child(assembly)
 var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("a5c6c5")
 env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("d5e4ee");env.environment.ambient_light_energy=.72;world.add_child(env)
 var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-56,-34,0);sun.light_color=Color(1,.965,.88);sun.light_energy=.98;sun.shadow_enabled=true;sun.shadow_opacity=.48;world.add_child(sun)
 # Review-only water, never a game sea resource.
 var sea=MeshInstance3D.new();sea.mesh=PlaneMesh.new();sea.mesh.size=Vector2(100,100);sea.position.y=.2
 var sea_mat=StandardMaterial3D.new();sea_mat.albedo_color=Color("609da7");sea_mat.roughness=.94;sea_mat.metallic_specular=.12;sea.material_override=sea_mat;world.add_child(sea)
 # 0.25 m opaque wet band is a QA simulation; #831 has not supplied it yet.
 var wet=ShaderMaterial.new();wet.shader=Shader.new()
 wet.shader.code="shader_type spatial; varying float h; void vertex(){h=(MODEL_MATRIX*vec4(VERTEX,1.0)).y;} void fragment(){ float w=1.0-smoothstep(0.20,0.45,h); ALBEDO=COLOR.rgb*mix(1.0,0.68,w); ROUGHNESS=0.94; SPECULAR=0.15;}"
 foam_material=load(FOAM+"water_edge_material.tres").duplicate(true)
 var shader=Shader.new();shader.code=foam_material.shader.code.replace("void vertex()", "uniform float review_time=0.0;\nvoid vertex()").replace("TIME", "review_time");foam_material.shader=shader
 # 6 nominal 2m slots: four shore pieces, two turns, stair access occupies one straight slot.
 var pieces=[['straight',Vector3(-2,0,4),0],['outer',Vector3(0,0,4),0],['straight',Vector3(0,0,2),90],['inner',Vector3(0,0,0),90],['steps',Vector3(2,0,0),0],['straight',Vector3(4,0,0),0]]
 for i in pieces.size():
  var p=pieces[i];var asset="coast_water_steps" if p[0]=="steps" else "coast_rock_"+p[0]+("_high" if i==2 else "_low")
  instance(COAST+asset+".glb",p[1],p[2],wet)
  var cap=Vector2(.12,0) if i==0 else Vector2(0,.12) if i==5 else Vector2.ZERO
  # The stair outlet ends at the adjoining rocks; fade its two free short ends.
  if p[0]=="steps":cap=Vector2.ZERO
  if i==3:cap=Vector2.ZERO
  if i==5:cap=Vector2(0,.12)
  foam(p[0],p[1],p[2],cap)
 box(Vector3(-1.55,.28,1.3),Vector3(1.7,.56,5.4),"8c9e6b")
 box(Vector3(1.45,.28,-1.5),Vector3(7.1,.56,1.8),"8c9e6b")
 var dock_mat=StandardMaterial3D.new();dock_mat.vertex_color_use_as_albedo=true;dock_mat.roughness=.94;dock_mat.metallic_specular=.15
 for z in [5.0,7.0]:instance(COAST+"coast_dock_straight.glb",Vector3(-2,0,z),90,dock_mat)
 # Only seaward piles receive rings. No rings over the shoreline ribbon.
 for x in [-2.72,-1.28]:foam("pile_ring",Vector3(x,0,7))
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
 if OS.has_feature("android"):
  await android_start();return
 clock_set(0);await capture("default-review")
 for n in foam_nodes:n.hide()
 await capture("default-control-no-foam")
 for n in foam_nodes:n.show()
 vp.size=Vector2i(1000,800);frame(assembly.to_global(Vector3(.5,.2,2.1)),10.6);await capture("coast-overview")
 vp.size=Vector2i(900,700);frame(assembly.to_global(Vector3(.25,.2,2.4)),5.2);await capture("close-review")
 vp.size=Vector2i(900,650);frame(assembly.to_global(Vector3(2,.2,.55)),4.2);await capture("steps-review")
 vp.size=Vector2i(700,650);frame(assembly.to_global(Vector3(-2.72,.2,7)),2.1);await capture("pile-review")
 vp.size=Vector2i(360,800);frame(assembly.to_global(Vector3(.2,.2,2.6)),6.72)
 DirAccess.make_dir_recursive_absolute(output+"/motion")
 for i in 110:
  clock_set(i/20.0)
  for j in 2:await RenderingServer.frame_post_draw
  vp.get_texture().get_image().save_png(output+"/motion/%03d.png"%i)
 clock_set(5.5)
 for i in 2:await RenderingServer.frame_post_draw
 vp.get_texture().get_image().save_png(output+"/loop-end.png")
 report.renderer={"engine":Engine.get_version_info().string,"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
 report.review_only=true;report.coast_commit="d72d74f4c0ccbcc922c5691cb8b6866eca1ca8f9"
 report.wet_band="QA opaque vertex-colour treatment, y=.20 to .45; not owner revision"
 report.motion={"duration_s":5.5,"frames":110,"fps":20,"clock":"uniform substituted for TIME only in QA; exact 5.5s cycle"}
 report.passed=report.checks.all(func(c):return c.passed)
 FileAccess.open(output+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 print("WATER_EDGE_RENDER ",report.passed);get_tree().quit(0 if report.passed else 1)

var android_view=0
var android_foam=true
func android_state():
 for i in 3:await RenderingServer.frame_post_draw
 var state={"pid":OS.get_process_id(),"view":android_view,"foam":android_foam,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"kit":"430-v11","button_view":[92,760],"button_foam":[268,760],"draws":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
 FileAccess.open("user://water_edge_state.json",FileAccess.WRITE).store_string(JSON.stringify(state))
 vp.get_texture().get_image().save_png("user://water_edge_%d_%s.png"%[android_view,str(android_foam)])
func android_start():
 for n in foam_nodes:n.material_override.shader=load(FOAM+"water_edge.gdshader")
 var button=Button.new();button.text="Default / close";button.position=Vector2(10,738);button.size=Vector2(164,44);add_child(button)
 button.pressed.connect(func():
  android_view=1-android_view
  frame(assembly.to_global(Vector3(.2,.2,2.6) if android_view==0 else Vector3(.25,.2,2.4)),6.72 if android_view==0 else 5.2)
  android_state())
 var toggle=Button.new();toggle.text="Foam on / off";toggle.position=Vector2(186,738);toggle.size=Vector2(164,44);add_child(toggle)
 toggle.pressed.connect(func():
  android_foam=not android_foam
  for n in foam_nodes:n.visible=android_foam
  android_state())
 await android_state()
