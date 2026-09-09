extends "res://tools/dev/journey_visual_probe.gd"

func _ready() -> void:
	_output = ProjectSettings.globalize_path("res://output/journey-streets-2026-09-08/visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_streets_run")

func _streets_run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(5)
		for id in ["sh_b", "la_c", "safe_grid"]:
			await _street_capture(id, size)
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures,
		"state_source": "synthetic fixtures", "active_play_minutes_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("STREET_VISUAL_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _street_capture(id: String, size: Vector2i) -> void:
	var state := _fixture(3)
	state.journey = {"version": 1, "wood": 12, "materials": {"stone": 4, "fiber": 2}, "completed": [],
		"facts": ["met_nursery", "met_bistro", "workbench", "planter_crafted", "planter_placed", "side_path", "shared_meal"],
		"unlocks": ["bistro", "kitchen", "crop_C", "crop_H"], "exploration": {"round": 1, "collected": [],
			"branching_places": ["nursery", "bistro", "courtyard"], "routes_by_place": {"nursery": "woodland", "bistro": "gardens", "courtyard": "riverside"}},
		"opportunities": {"nursery": {"sequence": 0, "variant": 0}, "bistro": {"sequence": 0, "variant": 0}, "restorer": {"sequence": 0, "variant": 0}}}
	var session := FarmSession.new(ApiClient.new("https://street-probe.invalid/v1", _reject_http))
	session.state = state
	session.layout_patch_id = id
	session.blueprint_revision = 2
	Net.session = session
	var street := JourneyStreet.new()
	street.session = session
	add_child(street)
	await _settle(25)
	street.set_process(false)
	var label := "streets-%s-%dx%d" % [id, size.x, size.y]
	var errors: Array[String] = []
	street._focus_view(street.player.position, 18)
	var focus := Vector2(size) * Vector2(0.6, 0.6)
	var ground: Vector3 = street.camera_pan._ground(street.cam, focus)
	street.camera_pan.begin(0, focus)
	street.camera_pan.magnify(street.cam, focus, 1.3)
	street._update_camera()
	if street.cam.size >= 18: errors.append("Pinching out did not enlarge the world")
	if ground.distance_to(street.camera_pan._ground(street.cam, focus)) > 0.01: errors.append("Pinch moved its ground focus")
	street._focus_view(street.player.position, 18)
	if not is_equal_approx(street.camera_pan.zoom, 1.0) or street.camera_pan.offset != Vector3.ZERO or street.camera_pan.active(): errors.append("Focus did not reset the camera")
	street._camera_center = Vector3(19.2, 0, -19.2)
	street._base_size = 45
	street._update_camera()
	street._sync_markers()
	await _settle(3)
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + "-overview.png"))
	for target_id in street.targets:
		var target: Dictionary = street.targets[target_id]
		if street.layout.grid.point_path(street.mover.position, target.approach).is_empty(): errors.append("Unreachable: " + str(target_id))
		street._camera_center = target.approach
		street._base_size = 18
		street._update_camera()
		street._sync_markers()
		street._ground_tap(target.button.get_global_rect().get_center())
		if street.pending != target_id: errors.append("Wrong selected object: " + str(target_id) + " -> " + street.pending)
		street.mover.stop()
		street.pending = ""
	street._camera_center = street.layout.caches.nursery[0]
	street._update_camera()
	street._sync_markers()
	await _settle(3)
	var image := get_viewport().get_texture().get_image()
	image.save_png(_output.path_join(label + "-supplies.png"))
	if not _world_pixels(image, street._world_area()).passed: errors.append("Blank 3D world")
	var white := 0
	var pixels := 0
	for y in range(140, image.get_height() - 115, 6):
		for x in range(10, image.get_width() - 10, 6):
			var color := image.get_pixel(x, y)
			pixels += 1
			if minf(color.r, minf(color.g, color.b)) > 0.95: white += 1
	if float(white) / maxf(1, pixels) > 0.5: errors.append("World materials are washed out")
	_ui_bounds(street.ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
	var start: Vector3 = street.mover.position
	street.mover.set_target_position(street.layout.entrances.nursery)
	for frame in 30: street._process(1.0 / 60)
	if street.mover.position.distance_to(start) < 1: errors.append("Player did not run")
	var animation := street._rig.get_node("AnimationPlayer") as AnimationPlayer
	if animation.current_animation != "run": errors.append("Missing run animation")
	if not street.is_back_navigation_locked() or street.mover.is_moving(): errors.append("Back did not cancel movement")
	street.suspend()
	if street.cam.current or street.world_env.environment != null: errors.append("Street retained view while suspended")
	street.resume()
	if not street.cam.current or street.world_env.environment == null: errors.append("Street did not restore view")
	_captures.append({"id": label, "errors": errors})
	for error in errors: _errors.append(label + ": " + error)
	remove_child(street)
	street.queue_free()
	await _settle(3)
