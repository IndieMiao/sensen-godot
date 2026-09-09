extends "res://tools/dev/journey_visual_probe.gd"

func _ready() -> void:
	_output = ProjectSettings.globalize_path("res://output/journey-meals-2026-09-08/visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_meal_run")

func _meal_run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(5)
		for guest in [false, true]:
			for dish in ["salad", "tea"]: await _meal_capture(size, guest, dish)
	if _captures.size() != 12: _errors.append("Expected twelve completed meal scenes")
	if not _blocked_requests.is_empty(): _errors.append("Unexpected network request")
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures,
		"state_source": "synthetic fixtures", "active_play_minutes_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MEAL_VISUAL_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _meal_capture(size: Vector2i, guest: bool, dish: String) -> void:
	var st := _fixture(3)
	st.journey = {"version": 1, "wood": 6, "completed": [], "facts": ["met_nursery", "met_bistro", "shared_meal"],
		"unlocks": ["bistro", "kitchen", "crop_C", "gifts", "tea"], "exploration": {"round": 0, "collected": []},
		"opportunities": {"bistro": {"sequence": 0, "variant": 0}, "nursery": {"sequence": 0, "variant": 0}}}
	if guest: st.journey.facts.append_array(["project_terrace_0", "project_terrace_1"])
	st.inventory.dishes.salad = 0
	st.inventory.dishes.tea = 0
	var session := FarmSession.new(ApiClient.new("https://place-probe.invalid/v1", _reject_http))
	session.state = st
	Net.session = session
	var place := JourneyPlace.new()
	place.place_id = "bistro"
	place.session = session
	add_child(place)
	await _settle(25)
	place.set_process(false)
	place.mover.position = place.targets.table.approach - JourneyPlace.NAV_ORIGIN
	place.player.position = place.mover.position + JourneyPlace.NAV_ORIGIN
	var errors: Array[String] = []
	var label := "%s-%s-%dx%d" % [dish, "guest" if guest else "host", size.x, size.y]
	var original := st.duplicate(true)
	place._show_panel("resident")
	await _settle(5)
	_check_actions_visible(place, ["Visit the prep counter"], errors)
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + "-dialogue.png"))
	place._close_panel()
	place.feedback.text = "Tea served. +22 coins" if dish == "tea" else "Salad served. +28 coins"
	place._world_action("table")
	place._meal_served(dish)
	var home: Vector3 = place.meal_moment.home
	var phases := []
	var max_distance := 0.0
	var minimum_clearance := INF
	for frame in 150:
		var previous: Vector3 = place.meal_moment.actor.position
		place._process(1.0 / 30)
		var actor: Node3D = place.meal_moment.actor
		max_distance = maxf(max_distance, actor.position.distance_to(home))
		minimum_clearance = minf(minimum_clearance, actor.position.distance_to(place.player.position))
		if actor.position.distance_to(previous) > 3.75 / 30 + 0.001: errors.append("Resident teleported")
		if not phases.has(place.meal_moment.phase): phases.append(place.meal_moment.phase)
		if guest and actor.position.distance_to(place.cast.get_node("nursery_keeper").position) < 0.5: errors.append("Resident crossed the guest")
		var target: Dictionary = place.targets.resident
		if target.body.distance_to(actor.position + Vector3(0, 1.35, 0)) > 0.001: errors.append("Resident hit target left actor")
		if frame in [5, 30]:
			await _settle(3)
			var image := get_viewport().get_texture().get_image()
			image.save_png(_output.path_join(label + "-%d.png" % frame))
			if not _world_pixels(image, Rect2(10, 135, size.x - 20, size.y - 220)).passed: errors.append("Blank world")
	if max_distance < 0.6 or not phases.has("reacting") or not phases.has("returning"): errors.append("Missing table visit")
	if place.meal_moment.active() or place.meal_moment.actor.position.distance_to(home) > 0.001: errors.append("Resident did not return home")
	if minimum_clearance < 0.5: errors.append("Resident crossed the player")
	if place.panel.visible or not place.served_dish.visible or place.served_recipe != dish: errors.append("Meal result not visible")
	if place.targets.table.button.visible: errors.append("Table badge covers the served dish")
	if place.world_notice.get_global_rect().intersects(place.farm_return.get_global_rect()): errors.append("Meal notice overlaps footer")
	_ui_bounds(place.ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
	place._process(4.0)
	if place.served_dish.visible: errors.append("Meal did not clear")
	# A new action interrupts the actor in place; closing it resumes a freshly planned route.
	place._meal_served(dish)
	place._process(0.1)
	var interrupted: Vector3 = place.meal_moment.actor.position
	if not place.select_target("resident"): errors.append("Moving resident is not selectable")
	place.pending_target = ""
	place.mover.stop()
	place._show_panel("resident")
	for frame in 60: place._process(1.0 / 30)
	if place.meal_moment.actor.position.distance_to(interrupted) > 0.001: errors.append("Resident moved during interaction")
	place._process(9.0)
	if place.meal_moment.phase != "returning" or place.served_dish.visible: errors.append("Expired meal continued during dialogue")
	place._close_panel()
	place.pending_target = ""
	place.mover.stop()
	for frame in 90: place._process(1.0 / 30)
	if place.meal_moment.active() or place.meal_moment.actor.position.distance_to(home) > 0.001:
		errors.append("Resident did not resume the return after dialogue")
	if st != original: errors.append("Presentation mutated gameplay state")
	_captures.append({"id": label, "phases": phases, "distance": max_distance, "clearance": minimum_clearance, "errors": errors})
	for error in errors: _errors.append(label + ": " + error)
	remove_child(place)
	place.queue_free()
	await _settle(3)
