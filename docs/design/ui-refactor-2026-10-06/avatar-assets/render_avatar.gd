extends SceneTree
var out_dir := ""
var records: Array = []
var v: SubViewport
var camera: Camera3D
var rig: AvatarRig
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	out_dir = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("thumbs"))
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("previews"))
	var avatar = root.get_node("Avatar")
	var thumber := PartThumbnailer.new()
	thumber.catalog = avatar.catalog
	root.add_child(thumber)
	await process_frame
	v = SubViewport.new()
	v.size = Vector2i(480, 560)
	v.transparent_bg = true
	v.own_world_3d = true
	v.msaa_3d = Viewport.MSAA_4X
	v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(v)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	v.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,35,0)
	light.light_energy = 1.0
	v.add_child(light)
	camera = Camera3D.new()
	camera.fov = 35
	camera.position = Vector3(0,1.0,3.72)
	v.add_child(camera)
	rig = avatar.create_rig()
	v.add_child(rig)
	var initial: AvatarConfig = avatar.slot_table.default_config()
	if "--defaults-only" in OS.get_cmdline_user_args():
		rig.apply_config(initial)
		if not await _settled():
			quit(2)
			return
		await _capture("defaults", initial)
		FileAccess.open(out_dir.path_join("render-records-defaults.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
		print("AVATAR_DEFAULTS_COMPLETE")
		quit()
		return
	initial.slots[&"cloth"] = "cloth28"
	initial.slots[&"hairHat"] = "hairhat43"
	initial.slots[&"shoes"] = "shoes0"
	rig.apply_config(initial)
	if not await _settled():
		quit(2)
		return
	await _capture("base", initial)
	var ids: Array = avatar.catalog.all_ids()
	ids.sort()
	for raw in ids:
		var id := String(raw)
		var meta = avatar.catalog.part(id)
		if meta.slot not in [&"hairHat",&"cloth",&"shoes",&"messengerBag",&"glass"]:
			continue
		var tex: Texture2D = await thumber.thumbnail(id)
		if tex == null:
			push_error("AVATAR_THUMB_FAILED " + id)
			quit(3)
			return
		tex.get_image().save_png(out_dir.path_join("thumbs/"+id+".png"))
		var cfg: AvatarConfig = initial.duplicate_config()
		cfg.slots[meta.slot] = id
		rig.apply_config(cfg)
		if not await _settled():
			quit(4)
			return
		await _capture(id, cfg)
		print("AVATAR_RENDERED ", id)
	FileAccess.open(out_dir.path_join("render-records.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
	print("AVATAR_RENDER_COMPLETE ", records.size())
	quit()
func _settled() -> bool:
	var start := Time.get_ticks_msec()
	while rig.is_busy() and Time.get_ticks_msec()-start<15000:
		await process_frame
	if rig.is_busy():
		push_error("AVATAR_SETTLE_TIMEOUT")
		return false
	rig.play_motion("idle")
	var player := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player:
		player.seek(0,true)
		player.pause()
	for n in 5:
		await process_frame
	return true
func _capture(id: String, cfg: AvatarConfig) -> void:
	await RenderingServer.frame_post_draw
	var image := v.get_texture().get_image()
	image.save_png(out_dir.path_join("previews/"+id+".png"))
	records.append({"id":id,"slots":cfg.slots,"preview":"previews/"+id+".png","size":[480,560]})
