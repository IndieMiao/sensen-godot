extends "res://tools/dev/combat_visual_probe.gd"

const Layout = preload("res://modules/mining/mine_layout.gd")

func _ready() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sensen-localization-qa"):
		get_tree().quit(2)
		return
	_output = ProjectSettings.globalize_path("res://output/mine-routes-visual")
	DirAccess.make_dir_recursive_absolute(_output)
	_run_routes.call_deferred()

func _run_routes() -> void:
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		for locale in ["zh_CN", "en"]:
			Localization.select_language(locale)
			FarmRegions.save_choice("shanghai")
			FarmChoice.save("sh_a", 2)
			Net.session = _session()
			var map_scene := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node3D
			add_child(map_scene)
			await _settle(50)
			map_scene._set_nearby_open(true)
			var id := str(map_scene.nearby_panel.entries[-1].farm_id)
			map_scene.nearby_panel.focus(id)
			await get_tree().create_timer(0.9).timeout
			await _settle(12)
			var markers: FarmMarkers = map_scene.farm_markers
			var anchor: Vector2 = map_scene.cam.unproject_position(markers.miniature.position) - markers.global_position
			if not markers.miniature.visible or anchor.x <= markers._selected_anchor.x: _errors.append("Farm is not on the owner's right")
			await _capture_ui(map_scene.get_node("HUD/SafeArea"), "farm-right", size, false)
			await _dispose(map_scene)
			for floor_number in [3, 4, 5]:
				var ss := _combat_session(floor_number)
				ss.state.mine.combat.version = 2
				ss.state.mine.combat.monsters["5"] = [300]
				if floor_number == 3:
					ss.state.mine.combat.monsters["3"] = [0]
					ss.state.mine.cleared_floors = [1, 2, 3]
				elif floor_number == 4:
					ss.state.mine.broken["4"] = Layout.rocks(4).map(func(rock): return rock.id)
					ss.state.mine.cleared_floors = [1, 2, 3, 4]
				var mine := load("res://scenes/mine/mine.tscn").instantiate() as Node3D
				mine.setup({"session": ss})
				add_child(mine)
				mine.combat.grace = 999
				await _settle(20)
				mine.set_process(false)
				if floor_number in [3, 4] and not mine.targets.has("down"): _errors.append("Missing route ladder")
				if floor_number == 5 and mine.targets.keys().any(func(key): return str(key).begins_with("rock_")): _errors.append("Boss arena has rocks")
				await _capture_ui(mine.ui, "route-floor-%d" % floor_number, size)
				await _dispose(mine)
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures, "artificial_qa": true}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MINE_ROUTES_VISUAL_RESULT captures=", _captures.size(), " errors=", JSON.stringify(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)
