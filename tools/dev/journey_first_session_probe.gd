extends "res://tools/dev/journey_visual_probe.gd"

func _ready() -> void:
	_output = ProjectSettings.globalize_path("res://output/journey-first-session-2026-09-08/visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_first_session_run")

func _first_session_run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(5)
		for id in ["nursery", "bistro"]:
			for phase in 2: await _first_session_capture(id, phase, size)
	if not _blocked_requests.is_empty(): _errors.append("Unexpected network request")
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures,
		"state_source": "synthetic fixtures", "active_play_minutes_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("FIRST_SESSION_VISUAL_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _first_session_capture(id: String, phase: int, size: Vector2i) -> void:
	var st := _fixture(3)
	st.journey = {"version": 1, "wood": 6, "completed": [], "facts": ["met_nursery", "met_bistro"],
		"unlocks": ["bistro", "kitchen", "crop_C", "gifts"], "exploration": {"round": 0, "collected": []},
		"opportunities": {"bistro": {"sequence": 0, "variant": 0}, "nursery": {"sequence": 0, "variant": 0}}}
	st.inventory.dishes.salad = 0
	st.inventory.dishes.tea = 0
	st.cells[st.cells.keys()[0]] = {"state": "growing", "crop": "C", "ready_at": 1000}
	if phase == 1:
		st.journey.facts.append("workbench")
		st.inventory.dishes.salad = 1
	var session := FarmSession.new(ApiClient.new("https://place-probe.invalid/v1", _reject_http))
	session.state = st
	Net.session = session
	var place := JourneyPlace.new()
	place.place_id = id
	place.session = session
	add_child(place)
	await _settle(35)
	place._show_panel("resident")
	await _settle(8)
	var errors: Array[String] = []
	var label := "%s-%d-%dx%d" % [id, phase, size.x, size.y]
	var expected: Array[String] = []
	if id == "nursery" and phase == 1: expected.append("Seeds worth keeping")
	if id == "bistro": expected.append("Visit the prep counter" if phase == 0 else "Take a seat at the table")
	_check_actions_visible(place, expected, errors)
	_ui_bounds(place.ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
	if place.farm_return.text != "My farm: 1 ready": errors.append("Missing harvest hint during dialogue")
	var controls := place.active_panel.content.find_children("*", "Label", true, false)
	var resident := "nursery_keeper" if id == "nursery" else "bistro_owner"
	if phase == 0 or id == "bistro":
		if controls.any(func(control): return control.text == JourneyProgress.data().stories[resident][0].hint):
			errors.append("Premature story")
	var image := get_viewport().get_texture().get_image()
	image.save_png(_output.path_join(label + "-dialogue.png"))
	var pixels := _world_pixels(image, Rect2(10, 125, size.x - 20, place.panel.global_position.y - 130))
	if not pixels.passed: errors.append("Blank 3D scene")
	var original := st.duplicate(true)
	var message := "Your first meal together. Chamomile seeds are in your bag."
	place.feedback.text = message
	place._world_action("table")
	await _settle(8)
	if not place.world_notice.visible or place.world_notice_label.text != message or place.panel.visible:
		errors.append("World result disappeared with the panel")
	if place.world_notice_label.get_visible_line_count() != place.world_notice_label.get_line_count():
		errors.append("World result text clipped")
	if place.world_notice.get_global_rect().intersects(place.farm_return.get_global_rect()):
		errors.append("World result overlaps footer")
	_ui_bounds(place.ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + "-result.png"))
	place._process(6.1)
	if place.world_notice.visible: errors.append("World result did not expire")
	if st != original: errors.append("Presenting a result changed game state")
	_captures.append({"id": label, "pixels": pixels, "errors": errors})
	for error in errors: _errors.append(label + ": " + error)
	remove_child(place)
	place.queue_free()
	await _settle(3)
