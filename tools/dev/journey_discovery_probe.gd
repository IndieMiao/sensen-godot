extends "res://tools/dev/place_visual_probe.gd"

func _ready() -> void:
	_output = ProjectSettings.globalize_path("res://output/journey-discoveries-2026-09-08/visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_run_discoveries")

func _settle(frames: int = 12) -> void:
	for frame in frames: await get_tree().process_frame
	RenderingServer.force_draw()

func _run_discoveries() -> void:
	for size in [Vector2i(360, 640), Vector2i(390, 844)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		for id in JourneyProgress.data().discoveries:
			for stage in 3:
				await _capture_discovery(str(id), stage, size)
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures,
		"source": "synthetic fixtures; native Godot rendering"}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("DISCOVERY_VISUAL_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _capture_discovery(id: String, stage: int, size: Vector2i) -> void:
	var st := _fixture(6)
	st.journey = {"version": 1, "wood": 4, "materials": {"stone": 0, "fiber": 2}, "completed": [],
		"facts": ["met_nursery", "met_bistro", "workbench", "planter_crafted", "planter_placed", "shared_meal", "side_path", "crafted_lantern"],
		"unlocks": ["bistro", "kitchen", "crop_C", "crop_H", "gifts", "tea"],
		"exploration": {"round": 2, "collected": []}, "opportunities": {},
		"workshop": {"sequence": 0, "stock": {"planter": 1, "lantern": 1, "fountain": 1},
			"displays": {"seedbeds": ["lantern", "planter", "fountain"], "terrace": ["lantern", "planter", "fountain"], "waystation": ["lantern", "planter", "fountain"]}}}
	for project in JourneyProgress.data().projects:
		for step in 2: st.journey.facts.append("project_%s_%d" % [project, step])
	if stage > 0: st.journey.facts.append("discovery_" + id)
	if stage == 2:
		st.journey.exploration.collected.append("discovery_" + id)
		st.journey.discovery_choices = {id: JourneyProgress.data().discoveries[id].choices.keys()[0]}
	var ss := FarmSession.new(ApiClient.new("https://place-probe.invalid/v1", _reject_http))
	ss.state = st
	Net.session = ss
	var place := JourneyPlace.new()
	place.place_id = str(JourneyProgress.data().discoveries[id].place)
	place.session = ss
	add_child(place)
	await _settle()
	var errors: Array[String] = []
	_ui_bounds(place.ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
	for target in place.targets:
		if not place.mover.set_target_cell(place.nav.world_to_cell(place.targets[target].approach - JourneyPlace.NAV_ORIGIN)):
			errors.append("Unreachable target: " + str(target))
	place.mover.stop()
	var button: Button = place.targets["discovery_" + id].button
	if not button.visible: errors.append("Discovery marker is hidden")
	for target in place.targets:
		if target == "discovery_" + id: continue
		var other: Button = place.targets[target].button
		if other.visible and button.get_global_rect().intersection(other.get_global_rect()).get_area() > 44 * 14:
			errors.append("Discovery marker overlaps " + str(target))
	var label := "%s-%d-%dx%d" % [id, stage, size.x, size.y]
	var pixels := _world_pixels(get_viewport().get_texture().get_image(), Rect2(10, 130, size.x - 20, size.y - 195))
	if not pixels.passed: errors.append("Blank world pixels")
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + ".png"))
	place._show_panel("discovery_" + id)
	await _settle()
	_ui_bounds(place.ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
	for control in place.active_panel.content.find_children("*", "Button", true, false):
		if not place.panel_scroll.get_global_rect().encloses(control.get_global_rect()):
			errors.append("Discovery action requires scrolling: " + str(control.tooltip_text))
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + "-panel.png"))
	_captures.append({"id": label, "pixels": pixels, "errors": errors})
	for error in errors: _errors.append(label + ": " + error)
	remove_child(place)
	place.queue_free()
	await _settle()
