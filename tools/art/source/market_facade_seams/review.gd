extends Node
class LocalMarket extends "res://scenes/p0/p0_outpost.gd":
 func _go_online(_session:P0Session)->void:pass
var scene:LocalMarket
var rt:P0Runtime
var folder:String
var report:Dictionary={"opening":{},"seams":{},"video":{}}
var view:SubViewport
var art:Node3D
var cam:Camera3D
var dir=Vector3(sin(deg_to_rad(45))*cos(deg_to_rad(33)),sin(deg_to_rad(33)),cos(deg_to_rad(45))*cos(deg_to_rad(33)))
var mode:String
func _ready():
 folder=OS.get_environment("MARKET_SEAM_REVIEW");DirAccess.make_dir_recursive_absolute(folder)
 Net.use_transport(FakeTransport.new([]).callable())
 rt=P0Runtime.ensure();rt.session.transport=func(_m,_p,_b,_c):pass
 await get_tree().process_frame
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"))
 fixture.energy.value=200;fixture.coins=200;rt.session.view=fixture;rt.session.busy=false;rt.session.state_changed.emit(fixture,[])
 scene=LocalMarket.new();scene.setup({"outpost_id":"sh_market_1"});add_child(scene)
 for i in 120:await get_tree().process_frame
 scene.actor.stand_still()
 if is_instance_valid(rt.ui._dev_box):rt.ui._dev_box.queue_free();rt.ui._dev_box=null
 for a in scene.find_children("*","AnimationPlayer",true,false):a.pause()
 scene.set_process(false)
 mode=OS.get_environment("MARKET_SEAM_MODE")
 if mode=="video":await video();get_tree().quit();return
 for variant in ["san_francisco","generic"]:
  for stage in ["before","after"]:
   choose(scene.art,variant,stage)
   await still(get_viewport(),"opening_"+variant+"_"+stage)
   report.opening[variant+"_"+stage]={"position":xyz(scene.cam.global_position),"width":scene.cam.size,"actor":xyz(scene.actor.position),"variant":scene.art.city_variant}
 make_view()
 for variant in ["san_francisco","generic"]:
  for stage in ["before","after"]:
   choose(art,variant,stage)
   for seam in seam_specs():
    var target:Vector3=seam.target;cam.position=target+dir*28;cam.look_at(target);cam.size=7.70607471466064
    await still(view,"seam_"+variant+"_"+stage+"_"+seam.id)
    report.seams[variant+"_"+stage+"_"+seam.id]={"target":xyz(target),"position":xyz(cam.position),"width":cam.size,"resolution":[720,1600],"magnification":"2x native portrait pixel dimensions; same yaw/pitch and world width"}
 FileAccess.open(folder.path_join("review.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("FACADE_SEAMS_STILLS_COMPLETE 4 P0 openings + 28 joint closeups")
 get_tree().quit()
func choose(node,variant:String,stage:String):
 for p in node.layout.assets:
  if p.get("group","")!="FarFacades":continue
  for key in ["san_francisco","generic"]:
   var s:String=p.variants[key];s=s.trim_prefix("before_")
   p.variants[key]="before_"+s if stage=="before" else s
 node.city_variant=variant
func seam_specs()->Array:
 var specs=[]
 for x in [-4,0,4]:specs.append({"id":"north_"+str(x),"target":Vector3(x,3.4,-7.9)})
 for z in [-4,0,4]:specs.append({"id":"west_"+str(z),"target":Vector3(-7.9,3.4,z)})
 specs.append({"id":"corner","target":Vector3(-7.9,3.4,-7.9)})
 return specs
func make_view():
 view=SubViewport.new();view.size=Vector2i(720,1600);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
 art=load("res://scenes/market_plaza/market_plaza_art.tscn").instantiate();view.add_child(art)
 var env=WorldEnvironment.new();env.environment=scene.get_node("WorldEnvironment").environment.duplicate() if scene.has_node("WorldEnvironment") else Environment.new()
 if not scene.has_node("WorldEnvironment"):
  env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("DDE8E7");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("FFF0DC");env.environment.ambient_light_energy=.7
 view.add_child(env)
 var sun=DirectionalLight3D.new();sun.light_energy=1;sun.light_color=Color("FFF1D8");sun.shadow_enabled=true;view.add_child(sun);sun.position=Vector3(-6,9,3);sun.look_at(Vector3.ZERO)
 cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH;cam.near=.1;cam.far=120;view.add_child(cam);cam.current=true
func still(vp:Viewport,label:String):
 for i in 12:await get_tree().process_frame
 await RenderingServer.frame_post_draw
 var im=vp.get_texture().get_image();assert(im.save_png(folder.path_join(label+".png"))==OK)
func video():
 # Two 12 s sweeps at 30 fps; 2.23 m/s of target movement, no video retime.
 var frame=0
 # The runtime calls p0_frame and would recenter even when scene processing is
 # disabled. Pause that review-only driver; keep the production HUD visible.
 rt.set_process(false);rt.set_physics_process(false)
 report.video_start_frame=Engine.get_frames_drawn()
 for variant in ["san_francisco","generic"]:
  choose(scene.art,variant,"after")
  rt.ui.set_place("San Francisco · Mission Market Square" if variant=="san_francisco" else "SF · Market (other-city preview)")
  var first_target=Vector3(-7.9,3.4,5.5)+scene.room.position
  scene.cam.position=first_target+dir*28;scene.cam.look_at(first_target)
  for i in 30:await get_tree().process_frame
  var camera_width=scene.cam.size
  var targets=[Vector3(-7.9,3.4,5.5),Vector3(-7.9,3.4,-7.9),Vector3(5.5,3.4,-7.9)]
  for leg in range(2):
   for i in 180:
    var t=float(i)/179.0;var target=targets[leg].lerp(targets[leg+1],t)+scene.room.position
    scene.cam.position=target+dir*28;scene.cam.look_at(target);scene.cam.size=camera_width
    scene._markers(rt.session.view)
    await get_tree().process_frame;frame+=1
    assert(scene.cam.position.distance_to(target+dir*28)<.001)
  report.video[variant]={"frames":360,"seconds":12,"world_path_m":26.8,"target_speed_mps":26.8/12.0,"yaw":45,"pitch":33,"width":camera_width}
 report.video_end_frame=Engine.get_frames_drawn()
 FileAccess.open(folder.path_join("video.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("FACADE_SEAMS_VIDEO_COMPLETE ",frame," sweep frames at 30 fps")
func xyz(v:Vector3):return [v.x,v.y,v.z]
