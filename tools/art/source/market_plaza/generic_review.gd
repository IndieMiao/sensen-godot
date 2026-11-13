extends Node
class LocalMarket extends "res://scenes/p0/p0_outpost.gd":
 func _go_online(_session:P0Session)->void:pass
var scene:LocalMarket
var rt:P0Runtime
var folder:String
var report:Dictionary={"views":{},"assemblies":{}}
func _ready()->void:
 folder=OS.get_environment("MARKET_REVIEW");DirAccess.make_dir_recursive_absolute(folder)
 Net.use_transport(FakeTransport.new([]).callable())
 rt=P0Runtime.ensure();rt.session.transport=func(_m,_p,_b,_c):pass
 await get_tree().process_frame
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"))
 fixture.energy.value=200;fixture.coins=200;rt.session.view=fixture;rt.session.busy=false;rt.session.state_changed.emit(fixture,[])
 scene=LocalMarket.new();scene.setup({"outpost_id":"sh_market_1"});add_child(scene)
 for f in 120:await get_tree().process_frame
 scene.actor.stand_still()
 report.layout_sha256=FileAccess.get_sha256("res://assets/rooms/market_plaza/layout.json")
 report.renderer=RenderingServer.get_current_rendering_method();report.gpu=RenderingServer.get_video_adapter_name()
 report.camera_width=scene.cam.size;report.pitch=rad_to_deg(asin(scene._cam_dir.y));report.yaw=rad_to_deg(atan2(scene._cam_dir.x,scene._cam_dir.z))
 var art=scene.art
 for variant in ["san_francisco","generic_v1","generic"]:
  change_variant(art,variant)
  await capture("opening_"+variant)
  var shapes=P0RoomNav.shapes_from(art)
  var rebuilt=P0RoomNav.build(shapes)
  report.assemblies[variant]={"collision_shapes":str(shapes),"walkable":Array(rebuilt.bp.masks.walkable),"grid":[rebuilt.bp.grid.x,rebuilt.bp.grid.y],"offset":xyz(rebuilt.offset)}
 change_variant(art,"generic")
 scene.actor.teleport(scene.room.position+Vector3(-7,scene.floor_y-scene.room.position.y,-7));scene.actor.stand_still()
 scene._focus=scene.actor.position;scene._follow.hold();scene._update_camera()
 await capture("far_corner_generic")
 var goals:Dictionary={}
 var spawn:Vector3=scene.anchor("spawn").global_position
 for a in scene.layout.anchors:
  if not (str(a.name).begins_with("stand_") or str(a.name).begins_with("seat_") or a.name=="exit"):continue
  var at=vec(a.get("approach",a.position))+scene.room.position
  var target:Vector3=scene.reachable(at);var path:Array=scene.grid.point_path(spawn,target)
  goals[a.name]={"path_points":path.size(),"snap_xz_m":Vector2(at.x-target.x,at.z-target.z).length()}
 report.anchor_routes=goals
 await overview()
 FileAccess.open(folder.path_join("review.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("GENERIC_REVIEW_COMPLETE ",report.camera_width," yaw/pitch ",report.yaw,"/",report.pitch)
 get_tree().quit()
func change_variant(art,variant:String)->void:
 # Existing renderer dispatch; review-only v1 references are never saved to layout.
 for p in art.layout.assets:
  if p.get("group","")!="FarFacades":continue
  var file:String=p.variants.generic
  var original_index=int(str(p.name).get_slice("_",2))
  if variant=="generic_v1":p.variants.generic="generic_v1_%d.glb"%original_index
  else:p.variants.generic="facade_generic_%d.glb"%((original_index+1)%4 if str(p.name).begins_with("facade_west_") else original_index)
 art.city_variant="san_francisco" if variant=="san_francisco" else "generic"
func capture(label:String)->void:
 for f in 45:await get_tree().process_frame
 await RenderingServer.frame_post_draw
 var image_=get_viewport().get_texture().get_image();assert(image_.get_size()==Vector2i(360,800));assert(image_.save_png(folder.path_join(label+".png"))==OK)
 report.views[label]={"camera_position":xyz(scene.cam.global_position),"size":scene.cam.size,"actor":xyz(scene.actor.position-scene.room.position),"triangles":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),"draws":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
func overview()->void:
 var vp=SubViewport.new();vp.size=Vector2i(1000,1000);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var art=load("res://scenes/market_plaza/market_plaza_art.tscn").instantiate();vp.add_child(art)
 var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("DDE8E7");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("FFF0DC");env.environment.ambient_light_energy=.7;vp.add_child(env)
 var sun=DirectionalLight3D.new();sun.light_energy=1;sun.light_color=Color("FFF1D8");sun.shadow_enabled=true;vp.add_child(sun);sun.position=Vector3(-6,9,3);sun.look_at(Vector3.ZERO)
 var cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=30;cam.far=120;vp.add_child(cam);cam.position=Vector3(22,29,22);cam.look_at(Vector3(0,1,0));cam.current=true
 for variant in ["san_francisco","generic_v1","generic"]:
  change_variant(art,variant)
  for f in 20:await get_tree().process_frame
  await RenderingServer.frame_post_draw
  vp.get_texture().get_image().save_png(folder.path_join("overview_"+variant+".png"))
 vp.queue_free()
func xyz(v:Vector3)->Array:return [v.x,v.y,v.z]
func vec(a)->Vector3:return Vector3(a[0],a[1],a[2])
