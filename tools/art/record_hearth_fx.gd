extends SceneTree
var room: Node3D
var output: String
var layout: Dictionary
var world: Node3D
func _initialize()->void:call_deferred("run")
func vec(a:Array)->Vector3:return Vector3(float(a[0]),float(a[1]),float(a[2]))
func run()->void:
 root.borderless=true;root.position=Vector2i.ZERO;root.size=Vector2i(960,720)
 var args:=OS.get_cmdline_user_args();var slug:String=args[0];output=args[1]
 layout=JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/"+slug+"/layout.json"))
 world=Node3D.new();root.add_child(world)
 room=(load("res://scenes/"+slug+"/"+slug+"_art.tscn") as PackedScene).instantiate() as Node3D;world.add_child(room)
 var lighting:Dictionary=layout.review_lighting
 var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(lighting.get("background","eae4c8"));env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(lighting.get("ambient_color","fff0dc"));env.ambient_light_energy=float(lighting.ambient);env.tonemap_mode=Environment.TONE_MAPPER_ACES
 var environment:=WorldEnvironment.new();environment.environment=env;world.add_child(environment)
 var sun:=DirectionalLight3D.new();world.add_child(sun);sun.position=vec(lighting.sun_position);sun.look_at(vec(lighting.sun_target));sun.light_color=Color(lighting.sun_color);sun.light_energy=float(lighting.sun);sun.shadow_enabled=true;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.directional_shadow_max_distance=float(lighting.shadow_distance);sun.shadow_bias=float(lighting.shadow_bias);sun.shadow_normal_bias=float(lighting.shadow_normal_bias);sun.light_angular_distance=1.4
 for spec in lighting.points:
  var lamp:=OmniLight3D.new();world.add_child(lamp);lamp.position=vec(spec.position);lamp.light_color=Color(spec.color);lamp.light_energy=float(spec.energy);lamp.omni_range=float(spec.range);lamp.shadow_enabled=false
 var view:Dictionary=layout.fx_review_camera
 var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=float(view.size)*.75;camera.near=.03;camera.far=50;world.add_child(camera);camera.position=vec(view.position);camera.look_at(vec(view.target));camera.current=true
 for i in 90:await process_frame
 var ready:=FileAccess.open(output+"/fx-state.json",FileAccess.WRITE);ready.store_string(JSON.stringify({"pid":OS.get_process_id(),"phase":"record-ready"}));ready.close()
 var deadline:=Time.get_ticks_msec()+30000
 while Time.get_ticks_msec()<deadline:
  if FileAccess.file_exists(output+"/fx-go") and FileAccess.get_file_as_string(output+"/fx-go").strip_edges()==str(OS.get_process_id()):break
  await process_frame
 assert(Time.get_ticks_msec()<deadline)
 var fx:Node=room.get_node("fx_hearth_fire");var lamp:OmniLight3D=fx.light
 var low:=INF;var high:=-INF;var draws:Array=[];var samples:=-1;var start:=Time.get_ticks_msec()
 while Time.get_ticks_msec()-start<8300:
  await process_frame
  low=minf(low,lamp.light_energy);high=maxf(high,lamp.light_energy)
  var second:int=int((Time.get_ticks_msec()-start)/1000)
  if second!=samples:
   samples=second;await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output+"/fire-frame-"+str(second)+".png")
   draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
 var spec:Dictionary=layout.effects[0];var base:float=float(spec.light.energy)
 var passed:=low>=base*.9 and high<=base*1.1 and high-low>base*.015
 var result={"passed":passed,"scene":slug,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"light_min":low,"light_max":high,"light_base":base,"light_position":[lamp.global_position.x,lamp.global_position.y,lamp.global_position.z],"particle_capacity":int(spec.flame_count)+int(spec.spark_count),"frame_draw_calls":draws,"capture":"8 second real-time X11 video; no speed adjustment"}
 var f:=FileAccess.open(output+"/fire-runtime.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));print("HEARTH_MOTION_VERIFIED ",JSON.stringify(result));quit(0 if passed else 1)
