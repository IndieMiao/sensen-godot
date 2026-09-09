extends "res://tools/dev/journey_meal_probe.gd"

func _ready() -> void:
	_output = ProjectSettings.globalize_path("res://output/journey-residents-2026-09-08/visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_residents_run")

func _residents_run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(5)
		for guest in [false, true]:
			for dish in ["salad", "tea"]: await _meal_capture(size, guest, dish)
		for dish in ["salad", "tea"]: await _terrace_capture(size, dish)
		for id in ["nursery", "bistro", "courtyard"]: await _activity_capture(size, id)
	if _captures.size() != 27: _errors.append("Expected 27 resident scenarios")
	if not _blocked_requests.is_empty(): _errors.append("Unexpected network request")
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures,
		"state_source": "synthetic fixtures", "active_play_minutes_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("RESIDENT_VISUAL_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _resident_place(id: String) -> JourneyPlace:
	var st := _fixture(3)
	st.journey = {"version": 1, "wood": 8, "materials": {"stone": 4, "fiber": 4}, "completed": [],
		"facts": ["met_nursery", "met_bistro", "shared_meal", "workbench", "planter_crafted", "planter_placed", "planter_planted", "side_path"],
		"unlocks": ["bistro", "kitchen", "crop_C", "crop_H", "tea"], "exploration": {"round": 1, "collected": []},
		"opportunities": {"bistro": {"sequence": 0, "variant": 0}, "nursery": {"sequence": 0, "variant": 0}}}
	for project in ["terrace", "seedbeds", "waystation"]:
		st.journey.facts.append_array(["project_" + project + "_0", "project_" + project + "_1"])
	st.decorations = [DecorationLayout.entry("planter", Vector2i(-6, 5))]
	var session := FarmSession.new(ApiClient.new("https://place-probe.invalid/v1", _reject_http))
	session.state = st
	Net.session = session
	var place := JourneyPlace.new()
	place.place_id = id
	place.session = session
	add_child(place)
	return place

func _check_resident_positions(place: JourneyPlace, previous: Dictionary, errors: Array[String]) -> void:
	for actor in place.cast.get_children():
		if actor.position.distance_to(place.player.position) < 0.5: errors.append("Resident crossed player")
		if previous.has(actor.name) and actor.position.distance_to(previous[actor.name]) > 3.75 / 30 + 0.001:
			errors.append("Resident teleported")
		for other in place.cast.get_children():
			if actor != other and actor.position.distance_to(other.position) < 0.5: errors.append("Residents crossed")
		var target_id := "resident" if actor.name == JourneyActivityPanel.RESIDENTS[place.place_id] else "resident:" + str(actor.name)
		if place.targets[target_id].body.distance_to(actor.position + Vector3(0, 1.35, 0)) > 0.001: errors.append("Resident hit target left actor")

func _positions(place: JourneyPlace) -> Dictionary:
	var positions := {}
	for actor in place.cast.get_children(): positions[actor.name] = actor.position
	return positions

func _capture_world(place: JourneyPlace, label: String, errors: Array[String]) -> void:
	await _settle(4)
	var image := get_viewport().get_texture().get_image()
	image.save_png(_output.path_join(label + ".png"))
	var size := get_viewport().get_visible_rect().size
	if not _world_pixels(image, Rect2(10, 135, size.x - 20, size.y - 220)).passed: errors.append("Blank 3D world")
	_ui_bounds(place.ui, Rect2(Vector2.ZERO, size), errors)

func _terrace_capture(size: Vector2i, dish: String) -> void:
	var place := _resident_place("bistro")
	await _settle(25)
	place.set_process(false)
	place._activity_wait = 999.0
	place.mover.position = place.targets.project_terrace.approach - JourneyPlace.NAV_ORIGIN
	place.player.position = place.mover.position + JourneyPlace.NAV_ORIGIN
	var original := place.session.state.duplicate(true)
	var label := "terrace-%s-%dx%d" % [dish, size.x, size.y]
	var errors: Array[String] = []
	place._meal_served(dish, "project_terrace")
	place._activity_wait = 999.0
	if place.served_dish.position.distance_to(Vector3(2, 0.96, -1.65)) > 0.001: errors.append("Meal is on the wrong table")
	var reacted := {}
	for frame in 390:
		var previous := _positions(place)
		place._process(1.0 / 30)
		_check_resident_positions(place, previous, errors)
		for id in place.resident_moments:
			if place.resident_moments[id].phase == "reacting": reacted[id] = true
		if frame in [45, 90]: await _capture_world(place, label + "-%d" % frame, errors)
	if reacted.size() != 2: errors.append("Both residents must reach the terrace: " + str(reacted))
	for moment in place.resident_moments.values():
		if moment.active() or moment.actor.position.distance_to(moment.home) > 0.001: errors.append("Meal participant did not return: " + str(moment.actor.name))
	if place.served_dish.visible: errors.append("Served meal did not clear")
	if place.session.state != original: errors.append("Meal presentation mutated state")
	_finish_resident(place, label, errors)
	await _settle(3)

func _activity_capture(size: Vector2i, id: String) -> void:
	var place := _resident_place(id)
	await _settle(25)
	place.set_process(false)
	var original := place.session.state.duplicate(true)
	var label := "activity-%s-%dx%d" % [id, size.x, size.y]
	var errors: Array[String] = []
	var reacted := {}
	var captured := false
	for frame in 1200:
		var previous := _positions(place)
		place._process(1.0 / 30)
		_check_resident_positions(place, previous, errors)
		for resident in place.resident_moments:
			var moment: ResidentMoment = place.resident_moments[resident]
			if moment.phase != "reacting": continue
			reacted[resident] = true
			if not captured:
				await _capture_world(place, label, errors)
				captured = true
	if reacted.size() != (2 if id == "bistro" else 1): errors.append("Missing facility activity: " + str(reacted))
	var actor := place.cast.get_child(0) as Node3D
	if not place.select_target("resident"): errors.append("Active resident was not reachable")
	place.pending_target = ""
	place.mover.stop()
	place._show_panel("resident")
	var paused := _positions(place)
	for frame in 60: place._process(1.0 / 30)
	if _positions(place) != paused: errors.append("Activity continued during dialogue")
	place._close_panel()
	place._activity_wait = 999.0
	for moment in place.resident_moments.values(): moment.finish()
	for frame in 180: place._process(1.0 / 30)
	for moment in place.resident_moments.values():
		if moment.active() or moment.actor.position.distance_to(moment.home) > 0.001: errors.append("Activity failed to return")
	if place.session.state != original: errors.append("Ambient activity mutated state")
	_finish_resident(place, label, errors)
	await _settle(3)

func _finish_resident(place: JourneyPlace, label: String, errors: Array[String]) -> void:
	_captures.append({"id": label, "errors": errors})
	for error in errors: _errors.append(label + ": " + error)
	remove_child(place)
	place.queue_free()
