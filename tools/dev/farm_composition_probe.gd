extends "res://tools/dev/free_farm_probe.gd"
## Same real farm scene at three relevant views; isolated visual evidence, no live account.
func _capture() -> void:
	var directory := OS.get_environment("FREE_FARM_CAPTURE")
	DirAccess.make_dir_recursive_absolute(directory)
	for frame in 100: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join("default.png"))
	var report := _state()
	var viewport_size := get_viewport().get_visible_rect().size
	report.viewport = [viewport_size.x, viewport_size.y]
	var origin: Vector2 = farm.cam.unproject_position(farm.player.position)
	var old_end: Vector2 = farm.cam.unproject_position(farm.player.position + Vector3.RIGHT * 0.5)
	var new_end: Vector2 = farm.cam.unproject_position(farm.player.position + Vector3.RIGHT * farm.bp.cell_m)
	report.tile_ratio = origin.distance_to(new_end) / origin.distance_to(old_end)
	FileAccess.open(directory.path_join("metrics.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	farm.set_process(false)
	for view in [{"name": "pond", "cell": Vector2i(12, 37)}, {"name": "boundary", "cell": Vector2i(6, 29)}]:
		farm.mover.position = farm.bp.cell_to_world(view.cell)
		farm.player.position = farm.mover.position
		farm._camera_initialized = false
		farm._update_camera()
		for frame in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join(str(view.name) + ".png"))
	get_tree().quit()

func _state() -> Dictionary:
	var result := super._state()
	var transform := get_viewport().get_screen_transform()
	var viewport := transform * get_viewport().get_visible_rect()
	var hard: Rect2 = transform * farm.camera_hard_zone()
	var dead: Rect2 = transform * farm.camera_dead_zone()
	var play: Rect2 = transform * farm._camera_play_area()
	result.viewport_rect = [viewport.position.x, viewport.position.y, viewport.size.x, viewport.size.y]
	result.hard_zone_screen = [hard.position.x, hard.position.y, hard.size.x, hard.size.y]
	result.dead_zone_screen = [dead.position.x, dead.position.y, dead.size.x, dead.size.y]
	result.play_area = [play.position.x, play.position.y, play.size.x, play.size.y]
	result.focus = _point(farm.player.position + Vector3.UP * 0.7)
	result.player_scale = [farm.player.scale.x, farm.player.scale.y, farm.player.scale.z]
	var a: Vector2 = farm.cam.unproject_position(farm.player.position)
	var b: Vector2 = farm.cam.unproject_position(farm.player.position + Vector3.RIGHT * farm.bp.cell_m)
	var c: Vector2 = farm.cam.unproject_position(farm.player.position + Vector3.RIGHT * 0.5)
	result.tile_ratio = a.distance_to(b) / a.distance_to(c)
	return result
