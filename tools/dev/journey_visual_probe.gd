extends "res://tools/dev/place_visual_probe.gd"

func _ready() -> void:
	_output = ProjectSettings.globalize_path("res://output/journey-visual-probe")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_journey_run")

func _settle(frames: int) -> void:
	for index in frames: await get_tree().process_frame
	# macOS can suppress frame_post_draw for an occluded probe window.
	RenderingServer.force_draw()

func _journey_run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(5)
		for stage in [0, 1, 2]:
			for id in PLACES:
				await _journey_capture(id, stage, size)
	if _captures.size() != 27: _errors.append("Expected 27 completed scene captures")
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures,
		"source": "synthetic fixtures; native rendering and navigation", "physical_device_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("JOURNEY_VISUAL_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _journey_capture(id: String, stage: int, size: Vector2i) -> void:
	var st := _fixture(3)
	st.journey = {"version": 1, "wood": 6, "completed": [], "facts": [],
		"unlocks": ["bistro", "kitchen", "crop_C", "gifts"], "exploration": {"round": 0, "collected": []},
		"opportunities": {"bistro": {"sequence": 0, "variant": 0}, "nursery": {"sequence": 0, "variant": 0}, "restorer": {"sequence": 0, "variant": 0}}}
	if stage >= 1:
		st.journey.facts = ["workbench", "planter_crafted", "planter_placed", "shared_meal", "side_path", "planter_planted"]
		st.journey.unlocks.append_array(["decorations", "tea", "crop_H", "growth"])
		st.decorations = [DecorationLayout.entry("planter", Vector2i(-6, 5))]
		st.nursery.stage = "built"
		for project in JourneyProgress.data().projects:
			for step in stage: st.journey.facts.append("project_%s_%d" % [project, step])
	var ss := FarmSession.new(ApiClient.new("https://place-probe.invalid/v1", _reject_http))
	ss.state = st
	Net.session = ss
	var place := JourneyPlace.new()
	place.place_id = id
	place.session = ss
	add_child(place)
	await _settle(50)
	var label := "%s-%d-%dx%d" % [id, stage, size.x, size.y]
	var errors: Array[String] = []
	_ui_bounds(place.ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
	var marker_positions := {}
	for target_id in place.targets:
		var target: Dictionary = place.targets[target_id]
		var rect: Rect2 = target.button.get_global_rect()
		marker_positions[target_id] = rect.position
		if rect.get_center().distance_to(place.cam.unproject_position(target.world)) > 0.1:
			errors.append("Marker left world anchor: " + target_id)
		if not target.button.visible: errors.append("Target hidden in initial view: " + target_id)
		if not place.mover.set_target_cell(place.nav.world_to_cell(target.approach - JourneyPlace.NAV_ORIGIN)):
			errors.append("Unreachable target: " + target_id)
	place.mover.stop()
	for target_id in place.targets:
		place.player.position = place.targets[target_id].approach
		place._sync_markers()
		for other in marker_positions:
			if place.targets[other].button.get_global_rect().position.distance_to(marker_positions[other]) > 0.1:
				errors.append("Player made a marker jump: " + other)
	place.player.position = place.mover.position + JourneyPlace.NAV_ORIGIN
	var pan_start: Vector2 = place.targets.resident.button.get_global_rect().get_center()
	var stationary: Vector3 = place.mover.position
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = pan_start
	get_viewport().push_input(down, true)
	var drag := InputEventScreenDrag.new()
	drag.position = pan_start + Vector2(70, 20)
	drag.relative = Vector2(70, 20)
	get_viewport().push_input(drag, true)
	var up := InputEventScreenTouch.new()
	up.position = drag.position
	get_viewport().push_input(up, true)
	if place.camera_pan.offset.length() < 0.2 or place.camera_pan.offset.length() > 2.1501: errors.append("Scene pan failed elastic bounds")
	if place.mover.is_moving() or not place.pending_target.is_empty() or place.mover.position != stationary: errors.append("Pan also activated a target")
	await _settle(3)
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + "-pan.png"))
	for frame in 180: place.camera_pan.step(1.0 / 60, place.cam)
	if place.camera_pan.offset.length() > 1.601: errors.append("Pan did not rebound")
	place.camera_pan.cancel()
	place.camera_pan.offset = Vector3.ZERO
	place._update_camera()
	if stage == 2:
		for factor in [2.0, 0.35]:
			await _pinch_capture(place, factor, label, errors)
		place.camera_pan.cancel()
		place.camera_pan.offset = Vector3.ZERO
		place.camera_pan._log_zoom = 0
		place._update_camera()
	for reachable in [true, false]:
		var destination := Vector3(-0.7, 0, 2.9) if reachable else Vector3(-3.5, 0, 4.8)
		place._ground_tap(place.cam.unproject_position(destination))
		if not place.ground_feedback._destination_visible or place.ground_feedback._reachable != reachable: errors.append("Missing ground tap feedback: " + str(reachable))
		await _settle(2)
		get_viewport().get_texture().get_image().save_png(_output.path_join(label + ("-ground.png" if reachable else "-blocked.png")))
		place.mover.stop()
	var before: Vector3 = place.player.position
	if not place.mover.set_target_cell(Vector2i(12, 5)): errors.append("Open path was not reachable")
	await _settle(15)
	if place.player.position.distance_to(before) < 0.05: errors.append("Avatar did not move")
	place.mover.stop()
	var pixels := _world_pixels(get_viewport().get_texture().get_image(), Rect2(10, 110, size.x - 20, size.y - 175))
	if not pixels.passed: errors.append("Scene pixels are blank")
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + ".png"))
	place._show_panel("workbench" if id == "nursery" else ("counter" if id == "bistro" else "planter"))
	await _settle(8)
	_ui_bounds(place.ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + "-panel.png"))
	if id == "bistro" and stage > 0:
		_check_actions_visible(place, ["Prepare salad", "Prepare tea"], errors)
	place.active_panel.busy = true
	if place._prepare_destination(): errors.append("Navigation interrupted a pending action")
	place.active_panel.busy = false
	if not place._prepare_destination() or place.panel.visible: errors.append("Destination button only dismissed the activity")
	place._show_panel("board")
	await _settle(8)
	_check_actions_visible(place, ["Nursery timber trail", "Courtyard stone trail", "Bistro reed trail"], errors)
	_ui_bounds(place.ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + "-routes.png"))
	place._close_panel()
	var scenery_id := place.scenery.get_instance_id()
	var cast_id := place.cast.get_instance_id()
	ss.state.journey.wood += 1
	place._refresh()
	if place.scenery.get_instance_id() != scenery_id or place.cast.get_instance_id() != cast_id:
		errors.append("Resource change rebuilt static scenery or residents")
	if id == "courtyard" and stage == 2:
		place._show_panel("planter")
		place._arrange()
		var editor := place.active_panel as DecorationPanel
		editor.rotate_selected()
		var continued := [0]
		var destination := func(): continued[0] += 1
		if place._prepare_destination(destination): errors.append("Unsaved arrangement left without confirmation")
		await _settle(2)
		_ui_bounds(place.ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
		place.is_back_navigation_locked()
		if place._pending_destination.is_valid(): errors.append("Canceled navigation retained its destination")
		if place._prepare_destination(destination): errors.append("Dirty draft did not ask again")
		editor._discard_and_leave()
		await _settle(2)
		if continued[0] != 1 or place.panel.visible: errors.append("Confirmed arrangement did not continue to its destination")
	_captures.append({"id": label, "pixels": pixels, "errors": errors})
	for error in errors: _errors.append(label + ": " + error)
	remove_child(place)
	place.queue_free()
	await _settle(3)

func _check_actions_visible(place: JourneyPlace, labels: Array[String], errors: Array[String]) -> void:
	var viewport_rect := place.panel_scroll.get_global_rect()
	for title in labels:
		var found := false
		for control in place.active_panel.content.find_children("*", "Button", true, false):
			if control.tooltip_text != title: continue
			found = true
			if not viewport_rect.encloses(control.get_global_rect()):
				errors.append("Action requires scrolling: " + title)
		if not found: errors.append("Missing action: " + title)

func _pinch_capture(place: JourneyPlace, factor: float, label: String, errors: Array[String]) -> void:
	var center := Vector2(place.ui.size.x * 0.5, place.ui.size.y * 0.48)
	var points := [center - Vector2(45, 0), center + Vector2(45, 0)]
	var player_before: Vector3 = place.mover.position
	for index in 2:
		var down := InputEventScreenTouch.new()
		down.index = index
		down.pressed = true
		down.position = points[index]
		get_viewport().push_input(down, true)
	for frame in 12:
		for index in 2:
			var drag := InputEventScreenDrag.new()
			drag.index = index
			drag.position = center + (points[index] - center) * lerpf(1, factor, float(frame + 1) / 12)
			get_viewport().push_input(drag, true)
		await _settle(1)
	var zoom: float = place.camera_pan.zoom
	if factor > 1 and zoom <= 1.4: errors.append("Zoom-in elasticity missing")
	if factor < 1 and zoom >= 0.8: errors.append("Zoom-out elasticity missing")
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + ("-zoom-in.png" if factor > 1 else "-zoom-out.png")))
	for index in 2:
		var up := InputEventScreenTouch.new()
		up.index = index
		up.position = center + (points[index] - center) * factor
		get_viewport().push_input(up, true)
	for frame in 180: place.camera_pan.step(1.0 / 60, place.cam)
	place._update_camera()
	await _settle(3)
	if place.camera_pan.zoom < 0.7999 or place.camera_pan.zoom > 1.4001: errors.append("Zoom did not rebound")
	if place.mover.is_moving() or place.mover.position != player_before or not place.pending_target.is_empty(): errors.append("Pinch triggered a world action")
	if not _world_pixels(get_viewport().get_texture().get_image(), Rect2(10, 140, place.ui.size.x - 20, place.ui.size.y - 200)).passed: errors.append("Zoom made scene blank")
