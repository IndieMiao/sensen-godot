extends "res://tools/dev/journey_visual_probe.gd"

func _ready() -> void:
	_output = ProjectSettings.globalize_path("res://output/journey-projects-2026-09-08/visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_project_run")

func _project_run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for size in [Vector2i(360, 640), Vector2i(390, 844)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(5)
		for id in JourneyProgress.data().projects:
			for stage in [0, 1]:
				for ready in [false, true]: await _project_capture(str(id), stage, ready, size)
			await _trail_capture(str(JourneyProgress.data().projects[id].place), size)
	if _captures.size() != 30: _errors.append("Expected thirty completed project and trail cases")
	if not _blocked_requests.is_empty(): _errors.append("Unexpected network request")
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures,
		"state_source": "synthetic fixtures", "active_play_minutes_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("PROJECT_VISUAL_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _project_state() -> Dictionary:
	var st := _fixture(3)
	st.cells = {}
	st.journey = {"version": 1, "wood": 0, "materials": {"stone": 0, "fiber": 0}, "completed": [],
		"facts": ["met_nursery", "met_bistro", "shared_meal", "workbench", "planter_crafted", "planter_placed", "side_path", "crafted_lantern"],
		"unlocks": ["bistro", "kitchen", "crop_C", "gifts", "crop_H", "tea"], "exploration": {"round": 1, "collected": []},
		"opportunities": {"bistro": {"sequence": 0, "variant": 0}, "nursery": {"sequence": 0, "variant": 0}}}
	return st

func _new_place(id: String, st: Dictionary) -> JourneyPlace:
	var session := FarmSession.new(ApiClient.new("https://place-probe.invalid/v1", _reject_http))
	session.state = st
	Net.session = session
	var place := JourneyPlace.new()
	place.place_id = id
	place.session = session
	add_child(place)
	return place

func _project_capture(id: String, stage: int, ready: bool, size: Vector2i) -> void:
	var st := _project_state()
	st.journey.tracked_project = id
	for index in stage: st.journey.facts.append("project_%s_%d" % [id, index])
	for crop in st.inventory.produce: st.inventory.produce[crop] = 3 if ready else 0
	for dish in st.inventory.dishes: st.inventory.dishes[dish] = 3 if ready else 0
	if ready:
		st.journey.wood = 10
		st.journey.materials = {"stone": 10, "fiber": 10}
	var original := st.duplicate(true)
	var spec: Dictionary = JourneyProgress.data().projects[id]
	var place := _new_place(str(spec.place), st)
	await _settle(25)
	var errors: Array[String] = []
	var label := "%s-%d-%s-%dx%d" % [id, stage, "ready" if ready else "missing", size.x, size.y]
	var image := get_viewport().get_texture().get_image()
	image.save_png(_output.path_join(label + "-world.png"))
	if not _world_pixels(image, Rect2(10, place.header.size.y + 20, size.x - 20, size.y - place.header.size.y - 120)).passed:
		errors.append("Blank world")
	if not place.follow_goal.visible: errors.append("Missing selected goal navigation")
	if place.follow_goal.get_global_rect().intersects(place.objective.get_global_rect()): errors.append("Goal text overlaps navigation")
	for target in place.targets.values():
		if place.mover.grid.point_path(place.mover.position, target.approach - JourneyPlace.NAV_ORIGIN).is_empty():
			errors.append("Unreachable target: " + str(target.label))
		if target.button.get_global_rect().get_center().distance_to(place.cam.unproject_position(target.world)) > 0.1:
			errors.append("Marker left its anchor")
	place._show_panel("project_" + id)
	await _settle(5)
	_check_actions_visible(place, ["Stop tracking project", str(spec.stages[stage].name)], errors)
	_ui_bounds(place.ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + "-panel.png"))
	place._close_panel()
	if ready:
		place._follow_goal()
		for frame in 90: await _settle(1)
		if not place.panel.visible or place.selected_target != "project_" + id: errors.append("Goal did not reach its construction object")
	if st != original: errors.append("Navigation mutated gameplay state")
	_finish_case(place, label, errors)
	await _settle(3)

func _trail_capture(id: String, size: Vector2i) -> void:
	var st := _project_state()
	st.journey.exploration.collected = JourneyProgress.nodes(st, id).map(func(node): return node.id)
	var place := _new_place(id, st)
	await _settle(25)
	var errors: Array[String] = []
	var label := "%s-trail-%dx%d" % [id, size.x, size.y]
	if not place.targets.has("trail") or not place.objects.has_node("TrailSign"): errors.append("Missing world trail sign")
	elif not place.select_target("trail"): errors.append("Trail sign is unreachable")
	for frame in 90: await _settle(1)
	if not place.panel.visible or place.selected_target != "trail": errors.append("Trail sign did not open the local route")
	else: _check_actions_visible(place, ["Explore this trail"], errors)
	_ui_bounds(place.ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + ".png"))
	_finish_case(place, label, errors)
	await _settle(3)

func _finish_case(place: JourneyPlace, label: String, errors: Array[String]) -> void:
	_captures.append({"id": label, "errors": errors})
	for error in errors: _errors.append(label + ": " + error)
	remove_child(place)
	place.queue_free()
