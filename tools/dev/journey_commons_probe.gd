extends "res://tools/dev/journey_visual_probe.gd"

func _talk_http(method: String, url: String, headers: PackedStringArray, body: String) -> ApiClient.Response:
	var command: Dictionary = JSON.parse_string(body) if not body.is_empty() else {}
	if method == "POST" and command.get("type") == "talk_to_resident" and StreetCommons.RESIDENTS.values().has(command.get("payload", {}).get("resident_id")):
		return ApiClient.Response.new(true, 200, {"version": Net.session.version + 1, "state": Net.session.state.duplicate(true)}, "")
	return await _reject_http(method, url, headers, body)

func _ready() -> void:
	_output = ProjectSettings.globalize_path("res://output/journey-commons-2026-09-08/visual-" + RenderingServer.get_current_rendering_method())
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_commons_run")

func _commons_run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(4)
		for id in (["sh_a", "sh_b", "sh_c", "la_a", "la_b", "la_c", "safe_grid"] if size.x == 390 else ["sh_b", "la_c", "safe_grid"]):
			await _capture_commons(id, size)
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures, "state_source": "synthetic fixtures"}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("COMMONS_VISUAL_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _capture_commons(id: String, size: Vector2i) -> void:
	var state := _fixture(3)
	state.journey = {"version": 1, "wood": 12, "materials": {"stone": 4, "fiber": 2}, "completed": [],
		"facts": ["met_nursery", "met_bistro", "workbench", "planter_crafted", "planter_placed", "side_path", "shared_meal"],
		"unlocks": ["bistro", "kitchen", "crop_C", "crop_H"], "exploration": {"round": 1, "collected": [],
			"branching_places": ["nursery", "bistro", "courtyard"]},
		"opportunities": {"nursery": {"sequence": 0, "variant": 0}, "bistro": {"sequence": 0, "variant": 0}, "restorer": {"sequence": 0, "variant": 0}}}
	var session := FarmSession.new(ApiClient.new("https://commons-probe.invalid/v1", _talk_http))
	session.state = state
	session.layout_patch_id = id
	session.blueprint_revision = 2
	Net.session = session
	var street := JourneyStreet.new()
	street.session = session
	add_child(street)
	await _settle(30)
	street.set_process(false)
	var label := "commons-%s-%dx%d" % [id, size.x, size.y]
	var errors: Array[String] = []
	for stage in [0, 1, 3]:
		session.state.journey.contributions = {}
		for effect in StreetCommons.EFFECTS: session.state.journey.contributions[effect] = stage
		street._refresh()
		for slot in StreetCommons.PLACES:
			street._focus_view(street.layout.commons[slot].position, 10)
			await _settle(4)
			var image := get_viewport().get_texture().get_image()
			image.save_png(_output.path_join("%s-%s-%d.png" % [label, slot, stage]))
			if not _world_pixels(image, street._world_area()).passed: errors.append("Blank common " + slot)
	var motions := {}
	var phases := {}
	for slot in street.residents.moments: motions[slot] = []
	for slot in street.residents.moments: phases[slot] = []
	for frame in 1800:
		street._process(1.0 / 60.0)
		for slot in street.residents.moments:
			var moment: ResidentMoment = street.residents.moments[slot]
			var animation := moment.actor.get_node("AnimationPlayer") as AnimationPlayer
			if not motions[slot].has(animation.current_animation): motions[slot].append(animation.current_animation)
			if phases[slot].is_empty() or phases[slot].back() != moment.phase: phases[slot].append(moment.phase)
			if moment.actor.position.distance_to(street.player.position) < StreetResidents.CLEARANCE: errors.append("Resident crossed the player")
	for slot in street.residents.moments:
		if not motions[slot].has("run"): errors.append("Resident did not run: " + slot)
		if not phases[slot].has("returning") or phases[slot].count("idle") < 2: errors.append("Resident did not return home: " + slot)
		var moment: ResidentMoment = street.residents.moments[slot]
		street._focus_view(moment.actor.position, 12)
		street._sync_markers()
		var target: Dictionary = street.targets["resident:" + slot]
		street._ground_tap(target.button.get_global_rect().get_center())
		if street.pending != "resident:" + slot: errors.append("Resident selection failed: " + slot)
		var stopped: Vector3 = moment.actor.position
		for frame in 1500:
			street._process(1.0 / 60)
			if street.dialogue.visible: break
		if not street.dialogue.visible: errors.append("Conversation did not open: " + slot)
		if not moment.actor.position.is_equal_approx(stopped): errors.append("Selected resident moved away")
		await _settle(4)
		_ui_bounds(street.dialogue, Rect2(Vector2.ZERO, Vector2(size)), errors)
		get_viewport().get_texture().get_image().save_png(_output.path_join(label + "-dialogue-" + slot + ".png"))
		var before: Vector3 = street.player.position
		street._ground_tap(Vector2(size) * 0.5)
		if street.mover.is_moving() or not street.player.position.is_equal_approx(before): errors.append("Dialogue passed a world touch")
		if not street.is_back_navigation_locked() or street.dialogue.visible: errors.append("Back did not close conversation")
		street.mover.stop()
		street.pending = ""
	street.suspend()
	street.resume()
	if not street.cam.current or street.world_env.environment == null: errors.append("Resume lost 3D view")
	var residents := {}
	for slot in street.residents.moments:
		var moment: ResidentMoment = street.residents.moments[slot]
		for pair in street.layout.caches.values():
			for point in pair:
				if point.distance_to(moment.home) < 2.4: errors.append("Resident home overlaps supplies: " + slot)
		residents[slot] = {"home": str(moment.home), "work": str(street.layout.commons[slot].approach), "position": str(moment.actor.position), "phase": moment.phase}
		street._focus_view(moment.actor.position, 12)
		var animation := moment.actor.get_node("AnimationPlayer") as AnimationPlayer
		animation.play("labour_water" if slot == "nursery" else "labour_sow")
		await get_tree().create_timer(0.4).timeout
		var positions: Array[float] = []
		for frame in 8:
			await get_tree().create_timer(0.04).timeout
			positions.append(animation.current_animation_position)
		if positions.max() - positions.min() < 0.05: errors.append("Visible resident animation stayed asleep: " + slot)
		residents[slot].animation_advance = positions.max() - positions.min()
	street._focus_view(street.player.position, 18)
	street._play("run")
	var animation := street._rig.get_node("AnimationPlayer") as AnimationPlayer
	await get_tree().create_timer(0.4).timeout
	var positions: Array[float] = []
	for frame in 8:
		await get_tree().create_timer(0.04).timeout
		positions.append(animation.current_animation_position)
	if positions.max() - positions.min() < 0.05: errors.append("Visible player run animation stayed asleep")
	_captures.append({"id": label, "errors": errors, "animations": motions, "phases": phases, "residents": residents})
	for error in errors: _errors.append(label + ": " + error)
	remove_child(street)
	street.queue_free()
	await _settle(3)
