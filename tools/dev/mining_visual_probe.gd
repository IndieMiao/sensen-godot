extends "res://tools/dev/localization_visual_probe.gd"
## Native rendering fixtures and optional loopback HTTP playthrough use an isolated profile.

var _live_actions: Array = []

func _ready() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sensen-localization-qa"):
		get_tree().quit(2)
		return
	_output = ProjectSettings.globalize_path("res://output/mining-visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_run_mining")

func _mine_session(level: int, complete := false) -> FarmSession:
	var ss := _session()
	ss.layout_patch_id = "sh_a"
	ss.blueprint_revision = 2
	ss.region_id = "shanghai"
	ss.state.journey.materials.merge({"copper_ore": 5, "rock_salt": 3})
	ss.state.journey.workshop = {"sequence": 0, "stock": {"crate": 1}, "displays": {}}
	ss.state.inventory.dishes.vegetable_soup = 2
	var cleared: Array = []
	var broken := {}
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/mining.json"))
	for previous in range(1, 6 if complete else level):
		cleared.append(previous)
		broken[str(previous)] = config.rocks.map(func(rock): return rock.id)
	ss.state.mine = {"version": 1, "run": 0, "floor": level, "deepest_floor": 5 if complete else level,
		"cleared_floors": cleared, "broken": broken, "elevator_unlocked": complete}
	return ss

func _run_mining() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(4)
		for locale in ["zh_CN", "en"]:
			Localization.select_language(locale)
			for level in range(1, 6):
				await _mine_capture(_mine_session(level), "floor-%d" % level, size)
			await _mine_capture(_mine_session(5, true), "elevator-unlocked", size)
			await _mine_capture(_mine_session(0, true), "completed-entry", size)
			await _farm_entry_capture(size)
			await _material_capture(size)
	var live_base := OS.get_environment("SENSEN_MINING_PROBE_BASE")
	if not live_base.is_empty(): await _live_playthrough(live_base)
	if _captures.size() < 60: _errors.append("Incomplete visual run: expected at least 60 captures")
	if not live_base.is_empty() and _live_actions.size() < 36:
		_errors.append("Incomplete live playthrough: expected 30 rocks, four ladders and two elevator trips")
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures,
		"live_actions": _live_actions, "source": "native Godot rendering; labeled fixtures and optional loopback HTTP actions",
		"physical_device_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MINING_VISUAL_RESULT captures=", _captures.size(), " actions=", _live_actions.size(), " errors=", JSON.stringify(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _mine_capture(ss: FarmSession, label: String, size: Vector2i) -> void:
	Net.session = ss
	var scene := load("res://scenes/mine/mine.tscn").instantiate() as Node3D
	scene.setup({"session": ss})
	add_child(scene)
	await _settle(30)
	await _capture_ui(scene.ui, "mine-" + label, size)
	if int(ss.state.mine.floor) > 0:
		for id in scene.targets:
			var target: Dictionary = scene.targets[id]
			var point: Vector2 = scene.cam.unproject_position(target.body)
			if not Rect2(Vector2(0, 75), Vector2(size.x, size.y - 170)).has_point(point):
				_errors.append("Mine target outside visible scene: %s %s %s" % [label, id, size])
	await _dispose(scene)

func _farm_entry_capture(size: Vector2i) -> void:
	var ss := _mine_session(0)
	ss.state.journey.facts = []
	ss.state.journey.unlocks = []
	Net.session = ss
	var farm := load("res://scenes/farm/farm.tscn").instantiate() as Node3D
	farm.setup({"blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_a", 2)), "session": ss})
	add_child(farm)
	await _settle(35)
	await _capture_ui(farm.get_node("HUD/SafeArea"), "farm-mine-entrance", size)
	await _dispose(farm)

func _material_capture(size: Vector2i) -> void:
	var ss := _mine_session(0, true)
	Net.session = ss
	for place_id in ["nursery", "bistro"]:
		var place := JourneyPlace.new()
		place.place_id = place_id
		place.session = ss
		add_child(place)
		await _settle(30)
		place._show_panel("workbench" if place_id == "nursery" else "counter")
		await _settle(4)
		await _capture_ui(place.ui, "mining-" + place_id, size, false)
		await _dispose(place)

func _live_playthrough(base: String) -> void:
	if not base.begins_with("http://127.0.0.1:") or not base.ends_with("/v1"):
		_errors.append("Live mining probe requires a loopback /v1 service")
		return
	Localization.select_language("zh_CN")
	get_tree().root.content_scale_size = Vector2i(390, 844)
	get_tree().root.size = Vector2i(390, 844)
	var ss := FarmSession.new(ApiClient.new(base, ApiClient.make_http_transport(self)), "user://mining-probe-journal")
	if not await ss.login() or not await ss.ensure_farm("shanghai", "sh_a", 2):
		_errors.append("Live mining login/create failed: " + ss.last_error_code)
		return
	Net.session = ss
	if int(ss.state.get("mine", {}).get("floor", 0)) > 0:
		await ss.send("leave_mine", {"run": int(ss.state.mine.run), "floor": int(ss.state.mine.floor)})
	if ss.state.get("mine", {}).get("cleared_floors", []).any(func(value): return int(value) == 5):
		await ss.send("restart_mine", {"run": int(ss.state.mine.run)})
	var farm: Node3D = AppRouter.push_instance(AppRouter.FARM, {"session": ss})
	await _settle(35)
	await _capture_ui(farm.get_node("HUD/SafeArea"), "live-farm-before-entry", Vector2i(390, 844))
	var entrance_rect: Rect2 = farm._mine_pick_rect()
	if not entrance_rect.has_area():
		_errors.append("Live farm entrance model has no visible hit area")
		await _close_live()
		return
	await _press(entrance_rect.get_center())
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		var current := AppRouter.top_instance()
		if current and current.scene_file_path == AppRouter.MINE and int(ss.state.get("mine", {}).get("floor", 0)) == 1 and not AppRouter._navigation_pending: break
		await get_tree().process_frame
	var scene := AppRouter.top_instance() as Node3D
	if scene == null or scene.scene_file_path != AppRouter.MINE or int(ss.state.get("mine", {}).get("floor", 0)) != 1:
		_errors.append("Live farm entrance did not open the mine")
		await _close_live()
		return
	_live_actions.append({"target": "farm-mine-entrance", "input": "viewport mouse press/release", "passed": true})
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/mining.json"))
	for level in range(1, 6):
		for rock in config.rocks:
			if ss.state.mine.broken.get(str(level), []).has(rock.id): continue
			if not await _live_click(scene, str(rock.id), ss):
				await _close_live()
				return
		await _capture_ui(scene.ui, "live-floor-%d-cleared" % level, Vector2i(390, 844))
		if level < 5 and not await _live_click(scene, "down", ss):
			await _close_live()
			return
	if not ss.state.mine.elevator_unlocked: _errors.append("Live floor five did not unlock elevator")
	for expected in [1, 5]:
		if not await _live_click(scene, "elevator", ss): break
		if int(ss.state.mine.floor) != expected: _errors.append("Live elevator reached wrong floor")
	var saved := ss.state.duplicate(true)
	if not await ss.refresh() or ss.state != saved: _errors.append("Live refresh changed mine or inventory")
	await _capture_ui(scene.ui, "live-elevator-return", Vector2i(390, 844))
	await _press(scene.primary.get_global_rect().get_center())
	deadline = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline and AppRouter.top_instance() != farm:
		await get_tree().process_frame
	var returned := AppRouter.top_instance() == farm and int(ss.state.mine.floor) == 0
	_live_actions.append({"target": "return-to-farm", "input": "viewport mouse press/release", "passed": returned})
	if not returned: _errors.append("Live return to farm failed")
	else:
		await _settle(10)
		await _capture_ui(farm.get_node("HUD/SafeArea"), "live-farm-return", Vector2i(390, 844))
	await _close_live()

func _close_live() -> void:
	while AppRouter.instance_depth() > 0: AppRouter.pop_instance()
	await _settle(5)

func _press(point: Vector2) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.pressed = pressed
		get_viewport().push_input(click, true)
		await _settle(1)

func _live_click(scene: Node3D, id: String, ss: FarmSession) -> bool:
	if not scene.targets.has(id):
		_errors.append("Live target missing: " + id)
		return false
	var button: Control = scene.targets[id].button
	var point: Vector2 = button.get_global_rect().get_center() if button.is_visible_in_tree() else scene.cam.unproject_position(scene.targets[id].body)
	var before := ss.version
	await _press(point)
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline and (ss.version == before or scene.busy):
		await get_tree().process_frame
	var passed: bool = ss.version > before and not scene.busy
	_live_actions.append({"target": id, "floor": ss.state.mine.floor, "version_before": before,
		"version_after": ss.version, "input": "viewport mouse press/release", "passed": passed})
	if not passed: _errors.append("Live interaction timed out: %s (%s)" % [id, ss.last_error_code])
	await _settle(4)
	return passed
