extends Node
const KIT:="res://assets/rooms/poi_culture_hall/"
const OUT:="res://../captures/"
const OUTPOST=preload("res://scenes/p0/p0_outpost.gd")
var vp: SubViewport
var room
var runtime
var seated: Array=[]
var report:={"checks":[],"captures":[],"seats":[]}
var elapsed:=0.0
func _ready() -> void:run.call_deferred()
func _process(dt: float) -> void:
	elapsed+=dt
	if elapsed>180:get_tree().quit(2)
func vec(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])
func check(ok: bool,label: String) -> void:
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func capture(name_: String,size_: Vector2i) -> void:
	vp.size=size_
	for i in 8:
		await get_tree().process_frame
		RenderingServer.force_draw(true)
	var image:=vp.get_texture().get_image();check(image.save_png(OUT+name_+".png")==OK,name_+" capture")
	report.captures.append({"name":name_,"size":[size_.x,size_.y],"width_m":room.cam.size,"transform":str(room.cam.global_transform)})
func rect(node: Node3D) -> Rect2:
	var lo:=Vector2(INF,INF);var hi:=Vector2(-INF,-INF)
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree():continue
		for i in 8:
			var q: Vector2=room.cam.unproject_position(mesh.to_global(mesh.get_aabb().get_endpoint(i)))
			lo=lo.min(q);hi=hi.max(q)
	return Rect2(lo,hi-lo)
func row_rect(r: Rect2) -> Array:return [r.position.x,r.position.y,r.size.x,r.size.y]
func validate() -> void:
	var stats: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(KIT+"asset_stats.json"))
	var triangles:=0;var surfaces:=0
	for mesh in room.art.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			triangles+=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size()/3;surfaces+=1
	report.triangles=triangles;report.surfaces=surfaces
	check(triangles==stats.scene_triangles and surfaces==stats.static_draw_surfaces,"actual assembled mesh budget matches manifest")
	report.stage=room.layout.stage
	check(triangles<=150000 and surfaces<=50,"within POI scene budget")
	check(room.art.find_children("seat_*","Marker3D",true,false).size()==4,"exactly four seat anchors")
	check(room.art.find_children("npc_*","Marker3D",true,false).is_empty() and room.art.find_children("use_*","Marker3D",true,false).is_empty(),"no NPC or service anchors")
	check(room.anchor("sign_door")!=null,"blank runtime sign anchor exists")
	check(absf(room.cam.size-6.72)<.001 and absf(room.cam.rotation_degrees.x+43)<.001,"native default 43 degree / 6.72 m")
	var requested: Vector3=room.anchor("spawn").global_position
	check(room.actor.position.distance_to(requested)<.12,"native spawn snaps within .12 m")
	report.native_camera={"spawn":room.layout.spawn,"actual_spawn_local":str(room.actor.position-room.room.position),
		"width_m":room.cam.size,"pitch":room.cam.rotation_degrees.x,"yaw":room.cam.rotation_degrees.y,
		"transform":str(room.cam.global_transform),"scope":"Original P0Room.frame_all and player, hall near/far contract"}
	var display:=rect(room.art.get_node("display_plinth")).merge(rect(room.art.get_node("plinth_exhibit")))
	var player:=rect(room.actor.rig)
	report.entry_exhibit={"display_rect":row_rect(display),"player_rect":row_rect(player),"overlap_px2":display.intersection(player).get_area()}
	check(display.position.y>=100 and display.end.y<=710,"front exhibit clears top 100 / bottom 90 safe bands")
	check(display.position.x>=0 and display.end.x<=360,"front exhibit fully inside default view")
	check(display.intersection(player).get_area()<.01,"front exhibit does not overlap entering player")
	report.artwork_visibility=[]
	for i in range(1,7):
		var bounds:=rect(room.art.get_node("artwork_%d"%i))
		report.artwork_visibility.append({"name":"artwork_%d"%i,"rect":row_rect(bounds),"visible_fraction":bounds.intersection(Rect2(0,100,360,610)).get_area()/bounds.get_area()})
	for spec in room.layout.assets:
		var config:=ConfigFile.new();check(config.load(KIT+spec.file+".import")==OK and str(config.get_value("remap","uid","")).begins_with("uid://"),spec.name+" import UID")
		check(config.get_value("params","gltf/texture_map_mode",0)==1,spec.name+" texture_map_mode=1")
	var nav: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../navigation.json"));check(nav.passed,"actual assembly navigation checks passed")
	var plant=room.art.get_node("plant_pot")
	for mesh in plant.find_children("*","MeshInstance3D",true,false):
		var material:=mesh.get_active_material(0) as StandardMaterial3D
		check(material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and absf(material.alpha_scissor_threshold-.45)<.001,"runtime Monstera alpha scissor .45")
		check(material.cull_mode==BaseMaterial3D.CULL_DISABLED,"runtime Monstera double-sided")
		check(material.albedo_texture.resource_path==KIT+"room_albedo_ao.png","runtime Monstera uses the sole room atlas")
	check(room.art.find_children("*","Light3D",true,false).size()==5,"three track spots plus two wall lights")
func populate_seats() -> void:
	for spec in room.layout.anchors:
		if not str(spec.name).begins_with("seat_"):continue
		var rig=Avatar.create_rig()
		for child in rig.get_children():
			if child is RigActivity:child.free()
		rig.assembler=AvatarAssemblerMerged.new();room.room.add_child(rig);rig.apply_config(Avatar.slot_table.default_config())
		var count:=0
		while rig.is_busy() and count<240:count+=1;await get_tree().process_frame
		check(not rig.is_busy(),spec.name+" actor assembled")
		rig.position=vec(spec.position)-Vector3.UP*OUTPOST.SIT_ROOT_BELOW_SEAT;rig.rotation_degrees.y=float(spec.yaw_degrees)+180
		var animation: AnimationPlayer=rig.get_node("AnimationPlayer");check(animation.has_animation("sit_idle"),spec.name+" native sitting animation")
		OUTPOST._play_seated(rig,false);animation.seek(.3,true);animation.advance(0);animation.pause()
		check(absf(float(spec.position[1])-.08-.715)<.0001,spec.name+" seat .715 m above floor")
		seated.append(rig);report.seats.append({"name":spec.name,"surface_y":spec.position[1],"root_y":rig.position.y,"yaw_degrees":spec.yaw_degrees,"animation":"sit_idle"})
func run() -> void:
	if DisplayServer.get_name()=="headless":get_tree().quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var preview:=TextureRect.new();preview.texture=vp.get_texture();preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(preview)
	runtime=load("res://modules/p0/p0_runtime.gd").new();runtime.session.transport=func(_method,_path,_body,_meta):pass
	vp.add_child(runtime);runtime.set_process(false);runtime.session.set_process(false)
	room=load("res://scenes/p0/rooms/p0_room.gd").new();room.use_runtime=false;room.use_art("poi_culture_hall")
	vp.add_child(room);room.rt=runtime;runtime.attach(room)
	for i in 20:await get_tree().process_frame
	var frames:=0
	while room.actor.rig.is_busy() and frames<240:frames+=1;await get_tree().process_frame
	room.frame_all();room.set_process(false);room.actor.set_process(false);room.actor.set_physics_process(false)
	report.native_clip=[room.cam.near,room.cam.far];room.cam.near=.1;room.cam.far=40;report.review_clip=[.1,40]
	room.actor.rig.play_motion("idle");var animation: AnimationPlayer=room.actor.rig.get_node("AnimationPlayer")
	animation.seek(.3,true);animation.advance(0);animation.pause();runtime.ui.visible=false
	validate();var native: Transform3D=room.cam.global_transform
	await capture("default_clean_360",Vector2i(360,800));await capture("default_clean_720",Vector2i(720,1600))
	for lamp in room.art.find_children("*","OmniLight3D",true,false):lamp.visible=false
	await capture("wall_lights_off",Vector2i(720,1600))
	for lamp in room.art.find_children("*","OmniLight3D",true,false):lamp.visible=true
	var entering_position: Vector3=room.actor.position
	vp.size=Vector2i(360,800);room.actor.position=room.room.position+Vector3(.65,.08,-1.70);room.frame_all()
	report.viewing_area={"fixture_player_local":[.65,.08,-1.70],"camera_transform":str(room.cam.global_transform),"artworks":[]}
	for i in range(1,7):
		var bounds:=rect(room.art.get_node("artwork_%d"%i))
		report.viewing_area.artworks.append({"name":"artwork_%d"%i,"rect":row_rect(bounds),"visible_fraction":bounds.intersection(Rect2(0,100,360,610)).get_area()/bounds.get_area()})
	await capture("viewing_area_720",Vector2i(720,1600))
	vp.size=Vector2i(360,800);room.actor.position=entering_position;room.frame_all();room.cam.global_transform=native
	await populate_seats();room.cam.global_transform=native;room.cam.size=6.72
	await capture("default_seated_720",Vector2i(720,1600))
	room.cam.rotation_degrees=Vector3(-43,45,0);room.cam.global_position=room.room.global_position+Vector3(0,1.9,.2)+room.cam.global_basis.z*20;room.cam.size=11.5
	await capture("seated_overview",Vector2i(1200,1000))
	for rig in seated:rig.visible=false
	room.actor.visible=false;await capture("overview",Vector2i(1200,1000))
	for lamp in room.art.find_children("*","SpotLight3D",true,false):lamp.visible=false
	await capture("spots_off",Vector2i(1200,1000))
	for lamp in room.art.find_children("*","SpotLight3D",true,false):lamp.visible=true
	for view in [{"name":"seating_plant_detail","at":Vector3(-2.5,.9,1.35),"size":3.6},{"name":"track_detail","at":Vector3(1.85,2.95,-2.70),"size":3.6}]:
		room.cam.global_position=room.room.global_position+view.at+room.cam.global_basis.z*20;room.cam.size=view.size
		await capture(view.name,Vector2i(1000,850))
	room.cam.rotation_degrees=Vector3(-90,0,0);room.cam.global_position=room.room.global_position+Vector3(0,20,0);room.cam.size=8
	await capture("topdown",Vector2i(1200,1200))
	report.renderer=RenderingServer.get_current_rendering_method();report.adapter=RenderingServer.get_video_adapter_name();report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(OUT+"validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("CULTURE_RENDER ",report.passed," checks=",report.checks.size())
	room.queue_free();runtime.queue_free();await get_tree().process_frame;get_tree().quit(0 if report.passed else 1)
