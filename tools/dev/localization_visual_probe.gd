extends "res://tools/dev/place_visual_probe.gd"

var _latin := RegEx.create_from_string("[A-Za-z]{3,}")

func _ready() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sensen-localization-qa"):
		push_error("Run this probe in the isolated localization QA project")
		get_tree().quit(2)
		return
	_output = ProjectSettings.globalize_path("res://output/localization-visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_run_localization")

func _settle(frames: int) -> void:
	for index in frames: await get_tree().process_frame
	RenderingServer.force_draw()

func _run_localization() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(4)
		await _switch_city(size)
		await _switch_map(size)
		for locale in ["zh_CN", "en"]:
			Localization.select_language(locale)
			await _farm_capture(size)
			for id in PLACES: await _place_capture(id, size)
			var dressing := load("res://scenes/dressing_room/dressing_room.tscn").instantiate() as Node
			add_child(dressing)
			await _settle(45)
			await _capture_ui(dressing, "dressing", size)
			await _dispose(dressing)
	var extra_size := Vector2i(390, 844)
	get_tree().root.content_scale_size = extra_size
	get_tree().root.size = extra_size
	for locale in ["zh_CN", "en"]:
		Localization.select_language(locale)
		await _additional_panels(extra_size)
	Localization.select_language("zh_CN")
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures,
		"source": "synthetic fixtures; native Godot rendering", "physical_device_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("LOCALIZATION_VISUAL_RESULT captures=", _captures.size(), " errors=", JSON.stringify(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _switch_city(size: Vector2i) -> void:
	Localization.select_language("zh_CN")
	var city := load("res://scenes/city_select/city_select.tscn").instantiate() as Control
	add_child(city)
	await _settle(5)
	await _capture_ui(city, "city", size, false)
	var language := city.find_child("LanguageButton", true, false) as LanguageButton
	for index in [1, 0]:
		await _menu_choose(language, index, "city", size)
		await _capture_ui(city, "city-switched", size, false)
	await _dispose(city)

func _switch_map(size: Vector2i) -> void:
	FarmRegions.save_choice("shanghai")
	FarmChoice.clear()
	Net.session = FarmSession.new(ApiClient.new("https://localization.invalid/v1", _reject_http))
	var map_scene := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node3D
	add_child(map_scene)
	await _settle(45)
	await _capture_ui(map_scene.get_node("HUD/SafeArea"), "map-create", size, false)
	await _dispose(map_scene)
	FarmChoice.save("sh_a", 2)
	Net.session = _session()
	map_scene = load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node3D
	add_child(map_scene)
	await _settle(50)
	await _capture_ui(map_scene.get_node("HUD/SafeArea"), "map-home", size)
	map_scene._set_nearby_open(true)
	var selected := str(map_scene.nearby_panel.entries[0].farm_id)
	map_scene.nearby_panel.focus(selected)
	await get_tree().create_timer(0.7).timeout
	await _settle(5)
	var state_before := JSON.stringify(Net.session.state)
	var camera_before: Transform3D = map_scene.cam.transform
	var language := map_scene.find_child("LanguageButton", true, false) as LanguageButton
	if language.get_global_rect().intersects(map_scene.my_farm_btn.get_global_rect()): _errors.append("Language overlaps My Farm")
	if language.get_global_rect().intersects(map_scene.top_panel.get_global_rect()): _errors.append("Language overlaps map header")
	for index in [1, 0]:
		await _menu_choose(language, index, "map", size)
		if map_scene.nearby_panel.street_button.tr(map_scene.nearby_panel.street_button.text) != L10n.text("Street"): _errors.append("Street button did not follow locale switch")
		if JSON.stringify(Net.session.state) != state_before: _errors.append("Language changed farm state")
		if not map_scene.cam.transform.is_equal_approx(camera_before): _errors.append("Language moved map camera")
		if map_scene.nearby_panel.focused_id != selected: _errors.append("Language cleared farm selection")
		await _capture_ui(map_scene.get_node("HUD/SafeArea"), "map-nearby", size, false)
	await _dispose(map_scene)

func _menu_choose(button: LanguageButton, index: int, context: String, size: Vector2i) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = button.get_global_rect().get_center()
		click.pressed = pressed
		get_viewport().push_input(click, true)
	await _settle(3)
	var menu := button.get_popup()
	if not menu.visible:
		_errors.append("Language menu did not open: " + context)
		return
	get_viewport().get_texture().get_image().save_png(_output.path_join("%s-menu-%dx%d.png" % [context, size.x, size.y]))
	menu.set_focused_item(index)
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	get_viewport().push_input(key, true)
	key.pressed = false
	get_viewport().push_input(key, true)
	await _settle(5)
	if TranslationServer.get_locale() != Localization.SUPPORTED[index]: _errors.append("Menu did not switch locale")
	if Localization.load_preference() != Localization.SUPPORTED[index]: _errors.append("Menu did not persist locale")
	menu.hide()

func _session() -> FarmSession:
	var ss := FarmSession.new(ApiClient.new("https://localization.invalid/v1", _reject_http))
	ss.farm_id = "localization-probe"
	ss.state = _fixture(6)
	ss.state.journey = {"version": 1, "wood": 8, "materials": {"stone": 8, "fiber": 8}, "completed": [],
		"facts": ["met_nursery", "met_bistro", "met_restorer", "workbench", "planter_crafted", "planter_placed", "shared_meal", "side_path", "planter_planted", "crafted_lantern"],
		"unlocks": ["bistro", "kitchen", "crop_C", "gifts", "decorations", "tea", "crop_H", "growth"],
		"exploration": {"round": 1, "collected": []},
		"opportunities": {"bistro": {"sequence": 0, "variant": 0}, "nursery": {"sequence": 0, "variant": 0}, "restorer": {"sequence": 0, "variant": 0}}}
	ss.state.decorations = [DecorationLayout.entry("planter", Vector2i(-6, 5))]
	for project in JourneyProgress.data().projects: ss.state.journey.facts.append("project_%s_0" % project)
	return ss

func _farm_capture(size: Vector2i) -> void:
	var ss := _session()
	Net.session = ss
	var farm := load("res://scenes/farm/farm.tscn").instantiate() as Node3D
	farm.setup({"blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_a", 2)), "session": ss})
	add_child(farm)
	await _settle(45)
	await _capture_ui(farm.get_node("HUD/SafeArea"), "farm", size)
	farm._open_stall()
	await _settle(5)
	await _capture_ui(farm.get_node("HUD/SafeArea"), "farm-stall", size, false)
	farm.hud.close_modal()
	farm._open_life()
	await _settle(5)
	await _capture_ui(farm.get_node("HUD/SafeArea"), "farm-bag", size, false)
	farm.hud.close_modal()
	farm.hud.show_modal(farm.hud._goals)
	await _settle(5)
	await _capture_ui(farm.get_node("HUD/SafeArea"), "farm-goals", size, false)
	await _dispose(farm)

func _place_capture(id: String, size: Vector2i) -> void:
	Net.session = _session()
	var place := JourneyPlace.new()
	place.place_id = id
	place.session = Net.session
	add_child(place)
	await _settle(35)
	await _capture_ui(place.ui, id, size)
	var panels := ["resident", "board", "workbench", "project_seedbeds", "discovery_stone_hollow"] if id == "nursery" else (["resident", "counter", "table", "project_terrace", "discovery_kitchen_garden"] if id == "bistro" else ["resident", "planter", "project_waystation", "discovery_reed_garden"])
	for panel in panels:
		place._show_panel(panel)
		await _settle(5)
		await _capture_ui(place.ui, id + "-" + panel, size, false)
	await _dispose(place)

func _additional_panels(size: Vector2i) -> void:
	var ss := _session()
	ss.state.journey.facts.append_array(JourneyProgress.data().gatherings.requires)
	ss.state.journey.workshop = {"stock": {"planter": 1, "lantern": 1}}
	Net.session = ss
	var street := JourneyStreet.new()
	street.setup({"session": ss})
	add_child(street)
	await _settle(40)
	await _capture_ui(street.ui, "street", size)
	for gathering in ["garden", "lantern"]:
		ss.state.journey.gathering = {"planned": gathering}
		street._show_gathering(gathering)
		await _settle(5)
		if not JourneyGatherings.ready(ss.state, gathering): _errors.append("Gathering fixture is not ready")
		await _capture_ui(street.ui, "gathering-" + gathering, size, false)
	await _dispose(street)
	ss = _session()
	ss.state.erase("journey")
	Net.session = ss
	var legacy := PLACE.instantiate()
	legacy.setup({"place_id": "nursery", "session": ss})
	add_child(legacy)
	await _settle(35)
	for panel in legacy._tab_buttons.keys():
		legacy.select_tab(panel)
		await _settle(5)
		await _capture_ui(legacy.root, "chapters-" + str(panel), size, false)
	await _dispose(legacy)

func _capture_ui(ui: Node, id: String, size: Vector2i, world := true, world_region := Rect2()) -> void:
	await _settle(2)
	var label := "%s-%s-%dx%d" % [TranslationServer.get_locale(), id, size.x, size.y]
	var errors: Array[String] = []
	_ui_bounds(ui, Rect2(Vector2.ZERO, Vector2(size)), errors)
	# Full-bleed backings and scrims intentionally extend beyond the safe area.
	errors.assign(errors.filter(func(error): return not "/StatusBacking " in error and not "/ModalScrim " in error))
	var texts: Array[String] = []
	_collect_text(ui, texts, errors)
	var shot := get_viewport().get_texture().get_image()
	var region := Rect2(10, 125, size.x - 20, size.y - 230)
	if id == "map-home":
		var extent := Vector2(minf(440, size.x - 20), minf(400, size.y - 230))
		region = Rect2(Vector2(size) * 0.5 + Vector2(0, 20) - extent * 0.5, extent)
	if world_region.has_area(): region = world_region
	var pixels := _world_pixels(shot, region) if world else {}
	if world and not pixels.passed: errors.append("Scene pixels are blank")
	shot.save_png(_output.path_join(label + ".png"))
	_captures.append({"id": label, "texts": texts, "pixels": pixels, "errors": errors})
	for error in errors: _errors.append(label + ": " + error)
	print("LOCALIZATION_CAPTURE ", label, " errors=", errors.size())

func _collect_text(node: Node, texts: Array[String], errors: Array[String]) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is Label or node is Button:
		var rendered := node.tr(str(node.text))
		if not rendered.is_empty():
			texts.append(rendered)
			if TranslationServer.get_locale() == "zh_CN" and _latin.search(rendered) and rendered != "OpenStreetMap 贡献者": errors.append("English text: " + rendered)
	for child in node.get_children(): _collect_text(child, texts, errors)

func _dispose(node: Node) -> void:
	if AppRouter.instance_depth() > 0:
		_errors.append("Probe input unexpectedly navigated to another scene")
		while AppRouter.instance_depth() > 0: AppRouter.pop_instance()
	node.queue_free()
	await _settle(5)
