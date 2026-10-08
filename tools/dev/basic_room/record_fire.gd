extends SceneTree
## Desktop review capture, wall-clock timestamps; separate from Android timing.
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var output := OS.get_cmdline_user_args()[0]
	var room = load("res://tools/dev/basic_room/basic_room.tscn").instantiate()
	root.add_child(room)
	await create_timer(4).timeout
	room._set_beauty(true)
	room.hud.hide()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 960)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.world_3d = room.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	room.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = room.zoom
	viewport.add_child(camera)
	camera.global_transform = room.camera.global_transform
	camera.current = true
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(output + "/whole.png")
	var target := Vector3(-2.05, .64, -2.30)
	camera.position = target + Vector3(.15, .32, 1.5)
	camera.look_at(target)
	camera.size = 1.25
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(output + "/fire-close.png")
	var frames: Array = []
	var start := Time.get_ticks_usec()
	var previous := -1.0
	while float(Time.get_ticks_usec()-start)/1000000.0 < 8.0:
		await process_frame
		var elapsed := float(Time.get_ticks_usec()-start)/1000000.0
		if elapsed-previous < .05: continue
		await RenderingServer.frame_post_draw
		var path := output + "/fire-%04d.jpg" % frames.size()
		viewport.get_texture().get_image().save_jpg(path, .94)
		frames.append({"file":path,"seconds":elapsed})
		previous = elapsed
	var f := FileAccess.open(output + "/fire-frames.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(frames,"  "))
	quit()
