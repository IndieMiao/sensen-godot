extends Node
const KIT:="res://assets/rooms/poi_classroom/"
const OUT:="res://../captures/"
const OUTPOST=preload("res://scenes/p0/p0_outpost.gd")
var vp: SubViewport
var room
var runtime
var seats: Array=[]
var report:={"checks":[],"captures":[],"seats":[]}
var elapsed:=0.0

func _ready() -> void:run.call_deferred()
func _process(dt: float) -> void:
	elapsed+=dt
	if elapsed>180:get_tree().quit(2)
func check(ok: bool,label: String) -> void:
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func vec(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])
func capture(name_: String,size_: Vector2i) -> void:
	vp.size=size_
	for i in 8:
		await get_tree().process_frame
		RenderingServer.force_draw(true)
	var image:=vp.get_texture().get_image()
	check(image.save_png(OUT+name_+".png")==OK,name_+" screenshot")
	report.captures.append({"name":name_,"size":[size_.x,size_.y],"width_m":room.cam.size,"transform":str(room.cam.global_transform)})

func screen_bounds(node: Node3D) -> Rect2:
	var lo:=Vector2(INF,INF);var hi:=Vector2(-INF,-INF)
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		for i in 8:
			var p: Vector2=room.cam.unproject_position(mesh.to_global(mesh.get_aabb().get_endpoint(i)))
			lo=lo.min(p);hi=hi.max(p)
	return Rect2(lo,hi-lo)

func populate_seats() -> void:
	for spec in room.layout.anchors:
		if not str(spec.name).begins_with("seat_"):continue
		var rig=Avatar.create_rig()
		for child in rig.get_children():
			if child is RigActivity:child.free()
		rig.assembler=AvatarAssemblerMerged.new();room.room.add_child(rig)
		rig.apply_config(Avatar.slot_table.default_config())
		var count:=0
		while rig.is_busy() and count<240:
			count+=1;await get_tree().process_frame
		check(not rig.is_busy(),spec.name+" avatar assembled")
		rig.position=vec(spec.position)-Vector3.UP*OUTPOST.SIT_ROOT_BELOW_SEAT
		rig.rotation_degrees.y=float(spec.yaw_degrees)+180
		var animation: AnimationPlayer=rig.get_node("AnimationPlayer")
		check(animation.has_animation("sit_idle"),spec.name+" native sit_idle exists")
		OUTPOST._play_seated(rig,false)
		animation.seek(.3,true);animation.advance(0);animation.pause()
		check(absf(rig.position.y+.34-float(spec.position[1]))<.0001,spec.name+" existing seated root offset")
		check(absf(float(spec.position[1])-.08-.715)<.0001,spec.name+" seat surface .715 above floor")
		seats.append(rig)
		report.seats.append({"name":spec.name,"surface_y":spec.position[1],"root_y":rig.position.y,"yaw_degrees":spec.yaw_degrees,
			"animation":"sit_idle","root_below_surface":OUTPOST.SIT_ROOT_BELOW_SEAT})
	check(seats.size()==6,"exactly six native seated avatars")

func validate() -> void:
	var low:=INF;var high:=-INF
	for mesh in room.actor.rig.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree():continue
		var posed=mesh.bake_mesh_from_current_skeleton_pose() if mesh.skin!=null else mesh.mesh
		for surface in posed.get_surface_count():
			for vertex in posed.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p: Vector3=mesh.to_global(vertex)
				low=minf(low,p.y);high=maxf(high,p.y)
	report.standing_avatar_height_m=high-low
	check(high-low>=1.745*.85 and high-low<=1.745*1.15,"native player height within Basic Room baseline tolerance")
	var triangles:=0;var surfaces:=0
	for mesh in room.art.find_children("*","MeshInstance3D",true,false):
		for index in mesh.mesh.get_surface_count():
			var arrays: Array=mesh.mesh.surface_get_arrays(index)
			triangles+=arrays[Mesh.ARRAY_INDEX].size()/3;surfaces+=1
	report.triangles=triangles;report.surfaces=surfaces
	var stats: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(KIT+"asset_stats.json"))
	check(triangles==stats.placed_proxy_triangles+stats.shared_shell_stats.scene_triangles and surfaces==stats.placed_proxy_surfaces+stats.shared_shell_stats.static_draw_surfaces,"actual shared shell and white proxy budget matches asset stats")
	check(triangles<=150000 and surfaces<=50,"room budget below 150k triangles / 50 surfaces")
	check(room.art.find_children("seat_*","Marker3D",true,false).size()==6,"six art seat anchors")
	check(room.art.find_children("npc_*","Marker3D",true,false).is_empty() and room.art.find_children("use_*","Marker3D",true,false).is_empty(),"no NPC or service anchors")
	check(room.anchor("sign_door")!=null and room._data.sign_door.size==[1.30,.28],"runtime sign anchor matches approved prop")
	check(absf(room.cam.size-6.72)<.001 and absf(room.cam.rotation_degrees.x+43)<.001,"native 43 degree / 6.72 m camera")
	var spawn: Vector3=room.anchor("spawn").global_position
	var actual: Vector3=room.actor.position
	report.native_camera={"spawn_requested":room.layout.spawn,"spawn_actual_local":Array([actual.x-room.room.position.x,actual.y-room.room.position.y,actual.z-room.room.position.z]),
		"spawn_snap_distance":actual.distance_to(spawn),"width_m":room.cam.size,"pitch":room.cam.rotation_degrees.x,
		"yaw":room.cam.rotation_degrees.y,"transform":str(room.cam.global_transform),"room_offset":str(room.room.position),"source":"Unmodified P0Room.frame_all with P0Ui bag-only layout"}
	check(actual.distance_to(spawn)<.12,"native spawn snaps less than .12m")
	report.subject_screen_bounds={}
	for name_ in ["desk_1","desk_2","desk_3","desk_4","desk_5","desk_6","proxy_teacher_desk","proxy_blackboard","proxy_sign"]:
		var rect:=screen_bounds(room.art.get_node(name_))
		report.subject_screen_bounds[name_]={"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"hud_bag_clear":rect.position.y>=100 and rect.end.y<=710}
		check(rect.position.y>=100 and rect.end.y<=710,"HUD/Bag vertical clearance: "+name_)
		check(rect.position.x>=0 and rect.end.x<=360,"default frame includes full subject: "+name_)
	var nav: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../navigation.json"))
	check(nav.passed,"actual scene capsule sweeps passed")
	var config:=ConfigFile.new()
	for name_ in ["blockout_student_desk","blockout_student_stool","blockout_box","blockout_cylinder","blockout_ball"]:
		check(config.load(KIT+name_+".glb.import")==OK and str(config.get_value("remap","uid","")).begins_with("uid://"),name_+" import UID")
		check(config.get_value("params","gltf/texture_map_mode",0)==1,name_+" texture map mode one")

func run() -> void:
	if DisplayServer.get_name()=="headless":get_tree().quit(2);return
	if not FileAccess.file_exists("res://../navigation.json"):
		push_error("Run check_navigation.gd before rendering");get_tree().quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var preview:=TextureRect.new();preview.texture=vp.get_texture();preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(preview)
	runtime=load("res://modules/p0/p0_runtime.gd").new()
	runtime.session.transport=func(_method,_path,_body,_meta):pass
	vp.add_child(runtime);runtime.set_process(false);runtime.session.set_process(false)
	room=load("res://scenes/p0/rooms/p0_room.gd").new();room.use_runtime=false;room.use_art("poi_classroom")
	vp.add_child(room);room.rt=runtime;runtime.attach(room)
	for i in 20:await get_tree().process_frame
	var frames:=0
	while room.actor.rig.is_busy() and frames<240:
		frames+=1;await get_tree().process_frame
	room.frame_all();room.set_process(false);room.actor.set_process(false);room.actor.set_physics_process(false)
	room.actor.rig.play_motion("idle")
	var animation: AnimationPlayer=room.actor.rig.get_node("AnimationPlayer");animation.seek(.3,true);animation.advance(0);animation.pause()
	runtime.ui.visible=false
	validate()
	var native: Transform3D=room.cam.global_transform
	await capture("default_clean_360",Vector2i(360,800))
	await capture("default_clean_720",Vector2i(720,1600))
	await populate_seats()
	room.cam.global_transform=native;room.cam.size=6.72
	await capture("default_seated_720",Vector2i(720,1600))
	var focus: Vector3=room.room.global_position+Vector3(0,1.90,.2)
	room.cam.rotation_degrees=Vector3(-43,45,0);room.cam.global_position=focus+room.cam.global_basis.z*20;room.cam.size=11.5
	await capture("seated_overview",Vector2i(1200,1000))
	for rig in seats:rig.visible=false
	room.actor.visible=false
	room.cam.rotation_degrees=Vector3(-90,0,0);room.cam.global_position=room.room.global_position+Vector3(0,20,0);room.cam.size=8.0
	await capture("topdown",Vector2i(1200,1200))
	report.topdown_projection={}
	for spec in room.layout.placements:
		var p: Vector2=room.cam.unproject_position(room.room.to_global(vec(spec.position)))
		report.topdown_projection[spec.name]=[p.x,p.y]
	report.renderer=RenderingServer.get_current_rendering_method();report.adapter=RenderingServer.get_video_adapter_name()
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(OUT+"validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("CLASSROOM_RENDER ",report.passed," checks=",report.checks.size())
	room.queue_free();runtime.queue_free();await get_tree().process_frame
	get_tree().quit(0 if report.passed else 1)
