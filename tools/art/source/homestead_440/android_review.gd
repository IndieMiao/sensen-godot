extends Node
# Dedicated asset smoke only. Actual farm acceptance captures use review.gd.
const Art=preload("res://modules/farm/farm_art.gd")
const NAMES=["house_cottage","master_farmhouse_a","master_farmhouse_b"]
var vp:SubViewport
var camera:Camera3D
var house:MeshInstance3D
var sign:MeshInstance3D
var rig
var index=0
var button:Button
var ready_for_input=false
var sequence=0
func _ready():run.call_deferred()
func run():
 vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var display=TextureRect.new();display.texture=vp.get_texture();display.size=Vector2(360,800);display.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(display)
 var world=Node3D.new();vp.add_child(world)
 var env=WorldEnvironment.new();env.environment=Environment.new()
 env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("e3ebe8")
 env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.79,.88,.94);env.environment.ambient_light_energy=.42
 world.add_child(env)
 var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-51,-38,0);sun.light_color=Color(1,.96,.87);sun.light_energy=1.1;sun.shadow_enabled=true;world.add_child(sun)
 sun.shadow_opacity=.58;sun.shadow_bias=.1;sun.shadow_normal_bias=1;sun.shadow_blur=1.4
 sun.directional_shadow_max_distance=0;sun.directional_shadow_fade_start=1;sun.directional_shadow_pancake_size=4;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
 var ground=MeshInstance3D.new();ground.mesh=PlaneMesh.new();ground.mesh.size=Vector2(20,20);ground.position.y=-.01
 var grass=StandardMaterial3D.new();grass.albedo_color=Color("87ad60");grass.roughness=.9;ground.material_override=grass;world.add_child(ground)
 house=Art.instance(NAMES[index]);world.add_child(house)
 sign=Art.instance("chef_sign_a",Vector3(-2.52,0,1.3));world.add_child(sign)
 var actor=Node3D.new();actor.position=Vector3(1.85,0,1.2);world.add_child(actor)
 rig=Avatar.create_rig();rig.assembler=AvatarAssemblerMerged.new();actor.add_child(rig);rig.apply_config(Avatar.load_outfit())
 for i in 12:await get_tree().process_frame
 var waits=0
 while rig.is_busy() and waits<600:waits+=1;await get_tree().process_frame
 assert(not rig.is_busy(),"avatar assembly")
 var bounds=AABB();var first=true
 for m in rig.find_children("*","MeshInstance3D",true,false):
  var b=actor.global_transform.affine_inverse()*m.global_transform*m.get_aabb()
  bounds=b if first else bounds.merge(b);first=false
 actor.scale=Vector3.ONE*1.75/bounds.size.y;rig.play_motion("idle")
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.size=6.72;camera.far=150;world.add_child(camera)
 var pitch=deg_to_rad(43);var yaw=deg_to_rad(14.5);var target=Vector3(-.3,1.3,.2)
 camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*30;camera.look_at(target);camera.make_current()
 button=Button.new();button.position=Vector2(90,735);button.size=Vector2(180,48);button.text="Next house";button.pressed.connect(next);add_child(button)
 ready_for_input=true;await record()
func next():
 if not ready_for_input:return
 ready_for_input=false;index=(index+1)%3;sequence+=1
 house.mesh=Art.mesh_for(NAMES[index]);sign.mesh=Art.mesh_for("chef_sign_b" if index==2 else "chef_sign_a")
 await record();ready_for_input=true
func record():
 for i in 30:await RenderingServer.frame_post_draw
 var file="user://homestead-"+NAMES[index]+".png"
 vp.get_texture().get_image().save_png(file)
 var state={"pid":OS.get_process_id(),"asset":NAMES[index],"sequence":sequence,"assembled":not rig.is_busy(),"surfaces":house.mesh.get_surface_count(),"model_triangles":house.mesh.get_faces().size()/3,"height":house.mesh.get_aabb().end.y,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"viewport":[360,800],"button":[180,759],"frames":Engine.get_frames_drawn()}
 FileAccess.open("user://homestead_state.tmp",FileAccess.WRITE).store_string(JSON.stringify(state))
 DirAccess.rename_absolute("user://homestead_state.tmp","user://homestead_state.json")
