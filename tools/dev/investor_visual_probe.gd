extends "res://tools/dev/localization_visual_probe.gd"
const Miniature = preload("res://scenes/map/farm_miniature.gd")

func _ready() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sensen-localization-qa"):
		get_tree().quit(2)
		return
	_output = ProjectSettings.globalize_path("res://output/investor-visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_run_investor")

func _new_session(layout_id: String, count: int) -> FarmSession:
	var ss := _session()
	ss.layout_patch_id = layout_id
	ss.blueprint_revision = 2
	ss.state = _fixture(0)
	ss.state.journey = {"version": 1, "facts": [], "unlocks": [], "completed": [], "exploration": {"round": 0, "collected": []}}
	ss.state.cells = {}
	ss.state.beds_unlocked = 3
	var source := FarmBlueprint.load_file(FarmBlueprint.asset_path(layout_id, 2))
	ss.region_id = source.region_id
	var ids := []
	for bed in source.beds():
		for cell in bed.cells: ids.append(FarmBlueprint._cs(cell))
	var order := []
	for index in JourneyProgress.data().field_growth.order: order.append(ids[int(index)])
	ss.state.field_progress = {"order": order, "plots": count, "planted": 4 if count >= 6 else 0, "harvested": 6 if count >= 9 else 0}
	for id in ids: ss.state.cells[id] = {"state": "wild", "crop": null, "ready_at": null}
	for cell in source.reserved_bed().cells: ss.state.cells[FarmBlueprint._cs(cell)] = {"state": "wild", "crop": null, "ready_at": null}
	return ss

func _run_investor() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	Localization.select_language("zh_CN")
	await _previews()
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(4)
		for layout_id in ["sh_b", "la_a"]:
			for count in [4, 6, 9]:
				var ss := _new_session(layout_id, count)
				Net.session = ss
				var farm := load("res://scenes/farm/farm.tscn").instantiate() as Node3D
				farm.setup({"blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path(layout_id, 2)), "session": ss})
				add_child(farm)
				await _settle(35)
				await _capture_ui(farm.hud, "%s-%d-plots" % [layout_id, count], size)
				if farm.props.get_children().filter(func(prop): return prop.has_meta("cell_id") and prop.visible).size() != count: _errors.append("Wrong visible plot count")
				await _dispose(farm)
		for region_id in ["shanghai", "los_angeles"]:
			var layout_id := "sh_a" if region_id == "shanghai" else "la_a"
			FarmRegions.save_choice(region_id)
			FarmChoice.save(layout_id, 2)
			Net.session = _new_session(layout_id, 4)
			var map_scene := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node3D
			add_child(map_scene)
			await get_tree().create_timer(0.8).timeout
			await _settle(50)
			await _capture_ui(map_scene.get_node("HUD/SafeArea"), region_id + "-social-map", size, true, map_scene.farm_markers.miniature.get_global_rect())
			var avatar_bounds: Rect2 = map_scene.farm_markers._avatar_targets["self"].get_global_rect().grow(8)
			if not _world_pixels(get_viewport().get_texture().get_image(), avatar_bounds).passed: _errors.append("Own map avatar has no rendered pixels: %s %s" % [region_id, size])
			map_scene._set_nearby_open(true)
			var selected := str(map_scene.nearby_panel.entries.filter(func(entry): return str(entry.avatar_ref).begins_with("demo_"))[0].farm_id)
			map_scene.nearby_panel.focus(selected)
			await get_tree().create_timer(0.8).timeout
			await _settle(10)
			await _capture_ui(map_scene.get_node("HUD/SafeArea"), region_id + "-selected-farm", size)
			if map_scene.journey_map.visible or map_scene.nearby_panel._place_tab.visible: _errors.append("NPC entry on social map")
			if not map_scene.farm_markers.miniature.visible: _errors.append("Selected farm miniature is hidden: %s %s" % [region_id, size])
			await _dispose(map_scene)
			var snap := PresetSnapshots.snapshot(selected)
			var street := JourneyStreet.new()
			street.setup({"visitor_snapshot": snap, "blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path(str(snap.layout_patch_id), 2))})
			add_child(street)
			await _settle(35)
			await _capture_ui(street.ui, region_id + "-visitor-street", size)
			street._arrive("farm")
			await _settle(4)
			await _capture_ui(street.confirmation, region_id + "-entry-confirmation", size, false)
			street.confirmation.dismiss(false)
			await _dispose(street)
		var loading := preload("res://modules/ui/loading_overlay.gd").new()
		add_child(loading)
		await _settle(5)
		await _capture_ui(loading, "scene-loading", size, false)
		loading.failed()
		await _settle(5)
		await _capture_ui(loading, "scene-load-failure", size, false)
		await _dispose(loading)
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures, "source": "synthetic fixtures; native Godot rendering", "physical_device_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("INVESTOR_VISUAL_RESULT captures=", _captures.size(), " errors=", JSON.stringify(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _previews() -> void:
	var directory := ProjectSettings.globalize_path("res://assets/farm/art/previews")
	DirAccess.make_dir_recursive_absolute(directory)
	var preview := Miniature.new()
	add_child(preview)
	preview.size = Vector2(512, 448)
	for style in preload("res://modules/farm/farm_art.gd").STYLES:
		preview.show_style(str(style))
		await _settle(4)
		await RenderingServer.frame_post_draw
		var pixels := preview.viewport.get_texture().get_image()
		pixels.save_png(directory.path_join(str(style) + ".png"))
	preview.queue_free()
	await _settle(3)
