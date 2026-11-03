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
	check(triangles==stats.scene_triangles and surfaces==stats.static_draw_surfaces,"assembled room budget matches asset stats")
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
	for name_ in ["desk_1","desk_2","desk_3","desk_4","desk_5","desk_6","teacher_desk","blackboard","name_sign"]:
		var rect:=screen_bounds(room.art.get_node(name_))
		report.subject_screen_bounds[name_]={"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"hud_bag_clear":rect.position.y>=100 and rect.end.y<=710}
		check(rect.position.y>=100 and rect.end.y<=710,"HUD/Bag vertical clearance: "+name_)
		check(rect.position.x>=0 and rect.end.x<=360,"default frame includes full subject: "+name_)
	var nav: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../navigation.json"))
	check(nav.passed,"actual scene capsule sweeps passed")
	var config:=ConfigFile.new()
	for asset in room.layout.assets:
		var name_: String=asset.name
		check(config.load(KIT+name_+".glb.import")==OK and str(config.get_value("remap","uid","")).begins_with("uid://"),name_+" import UID")
		check(config.get_value("params","gltf/texture_map_mode",0)==1,name_+" texture map mode one")
	var globe: Node3D=room.art.get_node("globe")
	var mount: Node3D=room.art.get_node("teacher_desk").find_child("globe_mount",true,false)
	check(globe.global_position.distance_to(mount.global_position)<.0001,"globe uses approved teacher desk mount")
	var books:=screen_bounds(room.art.get_node("reading_books"))
	check(books.intersects(Rect2(0,100,360,610)),"reading books visible in default safe view")
	report.reading_books_screen_rect=[books.position.x,books.position.y,books.size.x,books.size.y]
	check(room.art.find_children("*","OmniLight3D",true,false).size()<=6,"at most six unshadowed local lights")
	report.pendant_clearance=[]
	for lamp_name in ["pendant_1","pendant_2"]:
		var lamp_rect:=screen_bounds(room.art.get_node(lamp_name))
		for subject in ["blackboard","teacher_desk","rear_bookcase"]:
			var subject_rect:=screen_bounds(room.art.get_node(subject))
			var overlap:=lamp_rect.intersection(subject_rect).get_area()
			report.pendant_clearance.append({"lamp":lamp_name,"subject":subject,"overlap_px2":overlap})
			check(overlap<.01,lamp_name+" clears "+subject+" in default camera")

func sample_furniture() -> void:
	var image:=vp.get_texture().get_image()
	report.color_samples=[]
	for name_ in ["desk_2","desk_3","desk_4","desk_5"]:
		var desk: Node3D=room.art.get_node(name_)
		for x in [-.3,0.0,.3]:
			for z in [-.12,.12]:
				var at:=desk.to_global(Vector3(x,1.13425,z))
				var pixel:=Vector2i(room.cam.unproject_position(at))
				var color:=image.get_pixelv(pixel)
				report.color_samples.append({"surface":name_,"pixel":[pixel.x,pixel.y],"rgb":color.to_html(false)})

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
	report.native_clip_before=[room.cam.near,room.cam.far]
	room.cam.near=float(room.layout.camera.near);room.cam.far=float(room.layout.camera.far)
	report.review_clip=[room.cam.near,room.cam.far]
	room.actor.rig.play_motion("idle")
	var animation: AnimationPlayer=room.actor.rig.get_node("AnimationPlayer");animation.seek(.3,true);animation.advance(0);animation.pause()
	runtime.ui.visible=false
	validate()
	var native: Transform3D=room.cam.global_transform
	await capture("default_clean_360",Vector2i(360,800))
	await capture("default_clean_720",Vector2i(720,1600))
	sample_furniture()
	var projected_before: Vector2=room.cam.unproject_position(room.actor.global_position)
	room.cam.near=float(report.native_clip_before[0]);room.cam.far=float(report.native_clip_before[1])
	await capture("default_native_clip_720",Vector2i(720,1600))
	check(projected_before.distance_to(room.cam.unproject_position(room.actor.global_position))<.001,"clip adjustment preserves native camera framing")
	room.cam.near=float(room.layout.camera.near);room.cam.far=float(room.layout.camera.far)
	for lamp in room.art.find_children("*","OmniLight3D",true,false):lamp.visible=false
	await capture("local_lights_off",Vector2i(720,1600))
	for lamp in room.art.find_children("*","OmniLight3D",true,false):lamp.visible=true
	await populate_seats()
	room.cam.global_transform=native;room.cam.size=6.72
	await capture("default_seated_720",Vector2i(720,1600))
	var focus: Vector3=room.room.global_position+Vector3(0,1.90,.2)
	room.cam.rotation_degrees=Vector3(-43,45,0);room.cam.global_position=focus+room.cam.global_basis.z*20;room.cam.size=11.5
	await capture("seated_overview",Vector2i(1200,1000))
	for rig in seats:rig.visible=false
	room.actor.visible=false
	await capture("overview",Vector2i(1200,1000))
	# R3 roof edges rise 0.574 px per horizontal pixel: asin(.574) ~= 35 deg.
	room.cam.rotation_degrees=Vector3(-35,45,0)
	room.cam.global_position=room.room.global_position+Vector3(0,1.75,0)+room.cam.global_basis.z*20;room.cam.size=10.8
	await capture("reference_view",Vector2i(1181,1079))
	room.cam.rotation_degrees=Vector3(-43,45,0)
	for entry in [{"name":"reading_detail","at":Vector3(-2.1,1.1,-.3),"size":4.3}, {"name":"teaching_detail","at":Vector3(.4,2.0,-2.5),"size":4.8}]:
		room.cam.global_position=room.room.global_position+entry.at+room.cam.global_basis.z*20;room.cam.size=entry.size
		await capture(entry.name,Vector2i(1000,850))
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
