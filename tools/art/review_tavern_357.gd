extends SceneTree
## Actual offline P0Outpost assembly/opening camera and bracket hiding, in farm-dev.
var elapsed = 0.0
var vp: SubViewport
var room
var output = "res://output/npc-batch3/tavern-captures"
var report = {"captures":[]}
func _initialize(): run.call_deferred()
func _process(delta):
	elapsed += delta
	if elapsed > 180.0:
		push_error("Tavern capture watchdog")
		quit(2)
	return false
func shot(name_):
	for i in 12: await RenderingServer.frame_post_draw
	var image = vp.get_texture().get_image()
	assert(image.save_png(output+"/"+name_+".png")==OK)
	report.captures.append({"name":name_,"size":[image.get_width(),image.get_height()],"camera_size":room.cam.size,
		"camera_transform":str(room.cam.global_transform)})
	print("TAVERN_357_CAPTURE ",name_)
func run():
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true
	vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	room=load("res://scenes/p0/p0_outpost.gd").new()
	room.use_runtime=false;room.setup({"outpost_id":"sf_card_room_1"});vp.add_child(room)
	print("TAVERN_357_ROOM_READY")
	for i in 30:await process_frame
	print("TAVERN_357_ASSEMBLED")
	for player in room.find_children("*","AnimationPlayer",true,false):player.seek(.3,true);player.pause()
	room.frame_all()
	print("TAVERN_357_FRAMED")
	for i in 3:await process_frame
	room.process_mode=Node.PROCESS_MODE_DISABLED
	report.spawn=str(room.actor.position);report.hidden_art=room.hidden_art
	report.original_opening_transform=str(room.cam.global_transform)
	report.renderer=RenderingServer.get_current_rendering_method()
	report.adapter=RenderingServer.get_video_adapter_name()
	var opening=room.cam.global_transform;var width=room.cam.size
	# Double the pixel dimensions after the native 360px opening camera is fixed.
	vp.size=Vector2i(720,1600)
	var atlas=load("res://assets/rooms/tavern/room_albedo_ao.png")
	var baseline: Texture2D=load("res://output/npc-batch3/tavern-original.ctex")
	var materials=[]
	for mesh in room.art.find_children("*","MeshInstance3D",true,false):
		var mat=mesh.material_override as StandardMaterial3D
		if mat and mat.albedo_texture==atlas and not materials.has(mat):materials.append(mat)
	assert(not materials.is_empty())
	print("TAVERN_357_MATERIALS ",materials.size())
	for state in ["before","after"]:
		for material in materials:
			material.albedo_texture=baseline if state=="before" else atlas
			if material.emission_texture==atlas or material.emission_texture==baseline:material.emission_texture=material.albedo_texture
		room.cam.global_transform=opening;room.cam.size=width;vp.size=Vector2i(720,1600)
		await shot("opening-"+state)
		vp.size=Vector2i(1440,900)
		var focus=room.room.to_global(Vector3(.18,3.18,-3.30))
		room.cam.rotation_degrees=Vector3(-18,18,0)
		room.cam.position=focus+room.cam.basis.z*16
		room.cam.size=2.8
		await shot("bracket-"+state)
	FileAccess.open(output+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	room.queue_free();await process_frame
	quit()
