extends Node
class LocalMarket extends "res://scenes/p0/p0_outpost.gd":
	func _go_online(_session:P0Session) -> void:pass
var scene:LocalMarket
var rt:P0Runtime
var folder:String
var report:Dictionary={"views":{},"anchor_routes":{},"ring_paths":[]}
func _ready() -> void:
	folder=OS.get_environment("MARKET_REVIEW")
	DirAccess.make_dir_recursive_absolute(folder)
	Net.use_transport(FakeTransport.new([]).callable())
	rt=P0Runtime.ensure();rt.session.transport=func(_m,_p,_b,_c):pass
	await get_tree().process_frame
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"))
	fixture.energy.value=200;fixture.coins=200;rt.session.view=fixture;rt.session.busy=false
	rt.session.state_changed.emit(rt.session.view,[])
	scene=LocalMarket.new();scene.setup({"outpost_id":"sh_market_1"});add_child(scene)
	for f in 100:await get_tree().process_frame
	scene.actor.stand_still()
	report.layout_sha256=FileAccess.get_sha256("res://assets/rooms/market_plaza/layout.json")
	report.renderer=RenderingServer.get_current_rendering_method();report.gpu=RenderingServer.get_video_adapter_name()
	report.room_offset=xyz(scene.room.position);report.camera_width=scene.cam.size
	report.pitch=rad_to_deg(asin(scene._cam_dir.y));report.yaw=rad_to_deg(atan2(scene._cam_dir.x,scene._cam_dir.z))
	report.floor_y=scene.floor_y
	await capture("opening")
	var snapshot={"source":"P0RoomNav.build(shapes_from(live market_plaza_art))","cell_m":scene.bp.cell_m,"radius_m":P0RoomNav.RADIUS_M,
		"grid":[scene.bp.grid.x,scene.bp.grid.y],"room_offset":xyz(scene.room.position),"floor_y":scene.floor_y,"walkable":Array(scene.bp.masks.walkable),"layout_sha256":report.layout_sha256}
	FileAccess.open(folder.path_join("navigation_snapshot.json"),FileAccess.WRITE).store_string(JSON.stringify(snapshot,"  "))
	var spawn:Vector3=scene.anchor("spawn").global_position
	for a in scene.layout.anchors:
		var name_:String=a.name
		if not(name_.begins_with("stand_") or name_.begins_with("seat_") or name_=="exit"):continue
		var local:Vector3=vec(a.approach) if a.has("approach") else vec(a.position)
		var world:Vector3=local+scene.room.position
		var snapped:Vector3=scene.reachable(world)
		var path: Array[Vector3]=scene.grid.point_path(spawn,snapped)
		report.anchor_routes[name_]={"requested":xyz(local),"snapped":xyz(snapped-scene.room.position),"snap_xz":Vector2(world.x-snapped.x,world.z-snapped.z).length(),"points":path.size()}
	var ring:Array[Vector3]=[]
	for i in 17:
		var a:float=deg_to_rad(105.0+240.0*i/16)
		ring.append(scene.reachable(scene.room.position+Vector3(-.8+cos(a)*2.6,.05,-.8+sin(a)*2.6)))
	for i in ring.size()-1:
		var path: Array[Vector3]=scene.grid.point_path(ring[i],ring[i+1])
		report.ring_paths.append({"from":xyz(ring[i]-scene.room.position),"to":xyz(ring[i+1]-scene.room.position),"points":path.size(),"path":path.map(func(v):return xyz(v-scene.room.position))})
	for spec in [["far_corner",Vector3(-7,.05,-7)],["left_corner",Vector3(-7,.05,7)],["right_corner",Vector3(7,.05,-7)],["entry_corner",Vector3(6.4,.05,6.4)],["ring",Vector3(-3.4,.05,-.8)]]:
		stand(spec[1])
		# Preserve the short-settle diagnostic: the exit strip folds for 170 ms.
		if spec[0] in ["far_corner","ring"]:await capture(spec[0]+"_transition",10)
		await capture(spec[0])
	stand(Vector3(-7,.05,-7));scene.art.city_variant="generic";await capture("far_corner_generic");scene.art.city_variant="san_francisco"
	# P0's actual seat flow, local/offline claim. Two screenshots of resulting poses.
	for seat_ in ["seat_1","seat_2"]:
		stand(vec(scene.anchor_data(seat_).approach))
		scene._go_sit(seat_)
		for i in 600:
			scene.p0_frame(rt.session.view,1.0/60.0)
			if scene.seat==seat_:break
		for i in 60:scene.p0_frame(rt.session.view,1.0/60.0)
		for f in 90:await get_tree().process_frame
		await capture(seat_)
		report[seat_]={"selected":scene.seat,"root":xyz(scene.actor.position-scene.room.position),"surface_y":scene.anchor_data(seat_).position[1]}
		scene.p0_joystick(Vector2(.2,0));scene.p0_joystick(Vector2.ZERO)
		for i in 90:scene.p0_frame(rt.session.view,1.0/60.0)
	report.preflight_routes=[]
	for route in scene.layout.preflight.routes:
		var previous:Vector3=Vector3.INF
		var steps:Array=[]
		for p in route.points_xz:
			var target:Vector3=scene.reachable(scene.room.position+Vector3(p[0],scene.floor_y,p[1]))
			if previous!=Vector3.INF:
				steps.append(scene.grid.point_path(previous,target).size())
			previous=target
		report.preflight_routes.append({"name":route.name,"path_sizes":steps})
	var meshes:Array=[]
	for m:MeshInstance3D in scene.art.find_children("*","MeshInstance3D",true,false):
		if not m.get_meta("market_occluder",false):continue
		var faces:PackedVector3Array=m.mesh.get_faces();var points:Array=[]
		for v in faces:points.append(xyz(scene.room.global_transform.affine_inverse()*m.global_transform*v))
		meshes.append({"module":m.get_meta("market_module"),"faces":points})
	FileAccess.open(folder.path_join("occluders.json"),FileAccess.WRITE).store_string(JSON.stringify(meshes))
	FileAccess.open(folder.path_join("review.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	await overview()
	print("MARKET_REVIEW_COMPLETE views=",report.views.size()," grid=",scene.bp.grid," pitch=",report.pitch," width=",report.camera_width)
	get_tree().quit()
func stand(local:Vector3) -> void:
	var at:Vector3=scene.reachable(local+scene.room.position)
	scene.actor.teleport(Vector3(at.x,scene.floor_y,at.z));scene.actor.stand_still()
	scene._focus=scene.actor.position;scene._follow.hold();scene._update_camera()
func capture(label:String,settle_frames:int=30) -> void:
	# Wait beyond P0Ui name-strip collapse before taking the acceptance still.
	for f in settle_frames:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var im:Image=get_viewport().get_texture().get_image();assert(im.get_size()==Vector2i(360,800))
	assert(im.save_png(folder.path_join(label+".png"))==OK)
	var points:Dictionary={}
	for a in scene.layout.anchors:
		var at:Vector3=vec(a.position)+scene.room.position
		points[a.name]=xy(scene.cam.unproject_position(at))
	var bars:Dictionary={}
	for id in rt.ui._name_bars:
		var b:Control=rt.ui._name_bars[id]
		if b.visible:bars[id]=rect(b.get_global_rect())
	var icons:Dictionary={}
	for id in rt.ui._icons:
		var b:Control=rt.ui._icons[id]
		if b.visible:icons[id]=rect(b.get_global_rect())
	var exit_bar:Control=rt.ui._name_bars.get("room:exit")
	var exit_icon:Control=rt.ui._icons.get("room:exit")
	var exit_state={"bar_visible":exit_bar.visible if exit_bar else false,"bar_folding":exit_bar.get_meta("folding",false) if exit_bar else false,"bar_openness":exit_bar.openness() if exit_bar else 0.0,"bar_rect":rect(exit_bar.get_global_rect()) if exit_bar else [],"icon_visible":exit_icon.visible if exit_icon else false,"icon_rect":rect(exit_icon.get_global_rect()) if exit_icon else [],"marker_area":rect(rt.ui._marker_area())}
	report.views[label]={"exit_prompt_state":exit_state,"actor":xyz(scene.actor.position-scene.room.position),"player_box":rect(scene.actor.screen_box(scene.cam)),"anchor_pixels":points,"name_bars":bars,"icons":icons,"draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"triangles":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)}
func xyz(v:Vector3)->Array:return [v.x,v.y,v.z]
func xy(v:Vector2)->Array:return [v.x,v.y]
func rect(r:Rect2)->Array:return [r.position.x,r.position.y,r.size.x,r.size.y]
func vec(a)->Vector3:return Vector3(a[0],a[1],a[2])

func overview() -> void:
	var vp:=SubViewport.new();vp.size=Vector2i(1000,1000);vp.own_world_3d=true
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var art:Node3D=load("res://scenes/market_plaza/market_plaza_art.tscn").instantiate();vp.add_child(art)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("DDE8E7")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("FFF0DC");env.environment.ambient_light_energy=.7;vp.add_child(env)
	var sun:=DirectionalLight3D.new();sun.light_energy=1;sun.light_color=Color("FFF1D8");sun.shadow_enabled=true;vp.add_child(sun);sun.position=Vector3(-6,9,3);sun.look_at(Vector3.ZERO)
	var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=30;cam.far=120;vp.add_child(cam);cam.position=Vector3(22,29,22);cam.look_at(Vector3(0,1,0));cam.current=true
	for variant in ["san_francisco","generic"]:
		art.city_variant=variant
		for f in 10:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(folder.path_join("overview_"+variant+".png"))
	vp.queue_free()
