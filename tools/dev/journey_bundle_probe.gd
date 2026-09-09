extends "res://tools/dev/journey_resident_probe.gd"

func _ready() -> void:
	_output = ProjectSettings.globalize_path("res://output/journey-bundles-2026-09-08/visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_bundle_run")

func _bundle_run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(5)
		for id in ["nursery", "bistro", "courtyard"]:
			await _bundle_capture(size, id)
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures,
		"state_source": "synthetic fixtures", "active_play_minutes_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BUNDLE_VISUAL_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _bundle_capture(size: Vector2i, id: String) -> void:
	var place := _resident_place(id)
	place.session.state.journey.exploration.branching_places = ["nursery", "bistro", "courtyard"]
	place.session.state.journey.exploration.routes_by_place = {"nursery": "woodland", "bistro": "gardens", "courtyard": "riverside"}
	place._refresh()
	await _settle(20)
	place.set_process(false)
	var label := "bundles-%s-%dx%d" % [id, size.x, size.y]
	var errors: Array[String] = []
	var count := 0
	for target_id in place.targets:
		var target: Dictionary = place.targets[target_id]
		if not target.has("bundle"): continue
		count += 1
		var screen := place.cam.unproject_position(target.body)
		place._ground_tap(screen)
		if place.pending_target != target_id: errors.append("Wrong bundle selected: " + str(target_id) + " -> " + place.pending_target)
		if not place.mover.is_moving(): errors.append("Bundle approach did not start: " + str(target_id))
		place.mover.stop()
		place.pending_target = ""
	if count != (6 if id == "nursery" else 4): errors.append("Missing bundle choices")
	var rects: Array[Rect2] = []
	for target in place.targets.values():
		if not target.has("caption"): continue
		var caption: Label = target.caption
		var rect := caption.get_global_rect()
		if not caption.visible: errors.append("Bundle label is hidden: " + caption.text)
		if not Rect2(Vector2(0, 120), Vector2(size.x, size.y - 184)).encloses(rect): errors.append("Bundle label outside world: " + caption.text)
		for other in rects:
			if other.intersects(rect): errors.append("Overlapping bundle labels")
		rects.append(rect)
	await _capture_world(place, label, errors)
	_finish_resident(place, label, errors)
	await _settle(3)
