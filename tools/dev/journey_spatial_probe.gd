extends "res://tools/dev/place_visual_probe.gd"

func _ready() -> void:
	_output = ProjectSettings.globalize_path("res://output/journey-spatial-2026-09-08/visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_run_spatial")

func _settle(frames: int = 15) -> void:
	for frame in frames: await get_tree().process_frame
	RenderingServer.force_draw()

func _run_spatial() -> void:
	for size in SIZES:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		for id in ["seedbeds", "terrace", "waystation"]:
			await _capture_spatial(id, size)
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures,
		"source": "synthetic fixtures; native Godot rendering and projected object taps"}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SPATIAL_VISUAL_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _capture_spatial(project: String, size: Vector2i) -> void:
	var st := _fixture(6)
	st.journey = {"version": 1, "wood": 12, "materials": {"stone": 12, "fiber": 12}, "completed": [],
		"facts": ["met_nursery", "met_bistro", "workbench", "planter_crafted", "planter_placed", "shared_meal", "crafted_lantern"],
		"unlocks": ["bistro", "kitchen", "crop_C", "crop_H", "gifts", "tea"],
		"exploration": {"round": 2, "collected": []}, "opportunities": {},
		"workshop": {"sequence": 0, "stock": {"planter": 1, "lantern": 1, "fountain": 1},
			"displays": {project: ["lantern", "planter", "fountain"]}}}
	for id in JourneyProgress.data().projects:
		for step in 2: st.journey.facts.append("project_%s_%d" % [id, step])
	var ss := FarmSession.new(ApiClient.new("https://place-probe.invalid/v1", _reject_http))
	ss.state = st
	Net.session = ss
	var place := JourneyPlace.new()
	place.place_id = str(JourneyProgress.data().projects[project].place)
	place.session = ss
	add_child(place)
	await _settle()
	var label := "%s-%dx%d" % [project, size.x, size.y]
	var errors: Array[String] = []
	await _shot(place, label + "-closed", errors)
	if project == "seedbeds":
		if not place.targets.path.button.visible: errors.append("Closed path entrance is hidden")
		var exit := Vector3(4.2, 0, -1.5) - JourneyPlace.NAV_ORIGIN
		if place.mover.set_target_position(exit): errors.append("Closed gate is traversable")
		st.journey.facts.append("side_path")
		place._refresh()
		if not place.mover.set_target_position(exit): errors.append("Open path is unreachable")
		place.mover.stop()
		await _shot(place, label + "-open", errors)
		if not place.targets.path.button.visible: errors.append("Open path entrance is hidden")
	for id in place.targets:
		if not place.mover.set_target_position(place.targets[id].approach - JourneyPlace.NAV_ORIGIN): errors.append("Unreachable: " + str(id))
		for resident in place.cast.get_children():
			if place.targets[id].approach.distance_to(resident.position) < JourneyPlace.RESIDENT_CLEARANCE: errors.append("Approach overlaps resident: " + str(id))
	place.mover.stop()
	place._show_panel("project_" + project)
	await _shot(place, label + "-facility", errors, true)
	place._close_panel()
	if project == "seedbeds":
		place._show_panel("workbench")
		await _shot(place, label + "-workbench", errors, true)
		place._close_panel()
	for id in place.targets:
		if not str(id).begins_with("display:") and not str(id).begins_with("resident"): continue
		place._ground_tap(place.cam.unproject_position(place.targets[id].body))
		if place.pending_target != id: errors.append("Object tap selected %s instead of %s" % [place.pending_target, id])
		place.pending_target = ""
		place.mover.stop()
	for slot in 3:
		place._show_panel("display:%s:%d" % [project, slot])
		await _shot(place, label + "-slot%d" % slot, errors, true)
		place._close_panel()
	st.journey.workshop.displays[project] = ["", "", ""]
	place._refresh()
	for slot in 3:
		if place.targets.has("display:%s:%d" % [project, slot]): errors.append("Empty display leaks into exploration")
	place._arrange_display(project)
	await _shot(place, label + "-arrange", errors)
	for slot in 3:
		var id := "display:%s:%d" % [project, slot]
		place._ground_tap(place.cam.unproject_position(place.targets[id].body))
		if place.pending_target != id: errors.append("Empty slot tap selected wrong object")
		place.pending_target = ""
		place.mover.stop()
	place._show_panel("display:%s:1" % project)
	await _shot(place, label + "-empty-panel", errors, true)
	place.is_back_navigation_locked()
	place.is_back_navigation_locked()
	if not place.display_project.is_empty() or place.panel.visible: errors.append("Back cannot leave arrangement")
	_captures.append({"id": label, "errors": errors})
	for error in errors: _errors.append(label + ": " + error)
	remove_child(place)
	place.queue_free()
	await _settle()

func _shot(place: JourneyPlace, label: String, errors: Array[String], compact := false) -> void:
	await _settle()
	_ui_bounds(place.ui, get_viewport().get_visible_rect(), errors)
	var image := get_viewport().get_texture().get_image()
	var pixels := _world_pixels(image, Rect2(10, 130, image.get_width() - 20, image.get_height() - 195))
	if not pixels.passed: errors.append("Blank world: " + label)
	if compact:
		for control in place.active_panel.content.find_children("*", "Button", true, false):
			if not place.panel_scroll.get_global_rect().encloses(control.get_global_rect()): errors.append("Action needs scrolling: " + str(control.tooltip_text))
	image.save_png(_output.path_join(label + ".png"))
