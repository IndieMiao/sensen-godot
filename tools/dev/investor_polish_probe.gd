extends "res://tools/dev/investor_visual_probe.gd"

func _run_investor() -> void:
	_output = ProjectSettings.globalize_path("res://output/investor-polish-visual")
	DirAccess.make_dir_recursive_absolute(_output)
	for locale in ["zh_CN", "en"]:
		Localization.select_language(locale)
		for size in [Vector2i(390, 844), Vector2i(960, 720)]:
			get_tree().root.content_scale_size = size
			get_tree().root.size = size
			await _settle(4)
			for layout_id in ["sh_b", "la_a"]:
				var ss := _new_session(layout_id, 4)
				Net.session = ss
				FarmRegions.save_choice(ss.region_id)
				FarmChoice.save(layout_id, 2)
				var map_scene := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node3D
				add_child(map_scene)
				await get_tree().create_timer(1).timeout
				await _settle(20)
				var markers: FarmMarkers = map_scene.farm_markers
				if markers.miniature.visible: _errors.append("Default map shows farm model")
				print("DEFAULT_MARKERS ", locale, " ", layout_id, " ", size, " count=", markers.visible_farm_ids.size())
				if markers.visible_farm_ids.size() < 3: _errors.append("Insufficient demo characters in default view: " + layout_id)
				await _capture_ui(map_scene.get_node("HUD/SafeArea"), layout_id + "-default-map", size, true, markers._avatar_targets["self"].get_global_rect().grow(8))
				for id in markers._badges:
					if markers._badges[id].visible:
						markers._badges[id].pressed.emit()
						await _settle(4)
						await _capture_ui(map_scene.get_node("HUD/SafeArea"), layout_id + "-expanded", size)
						break
				map_scene._focus_own_farm()
				await get_tree().create_timer(0.8).timeout
				await _settle(10)
				await _capture_ui(map_scene.get_node("HUD/SafeArea"), layout_id + "-selected-model", size)
				if not markers.miniature.visible or markers.miniature.get_parent() != map_scene: _errors.append("Selected model is not in map world")
				var model_point: Vector2 = map_scene.cam.unproject_position(markers.miniature.global_position)
				var bounds := Rect2(model_point - Vector2(70, 80), Vector2(140, 100)).intersection(Rect2(Vector2.ZERO, Vector2(size)))
				if not _world_pixels(get_viewport().get_texture().get_image(), bounds).passed: _errors.append("Farm model pixels blank")
				await _dispose(map_scene)
				var farm := load("res://scenes/farm/farm.tscn").instantiate() as Node3D
				farm.setup({"blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path(layout_id, 2)), "session": ss})
				add_child(farm)
				await _settle(30)
				farm.set_process(false)
				farm.hints.queued = [CropField._parse_cell(ss.state.field_progress.order[1]), CropField._parse_cell(ss.state.field_progress.order[2])]
				await _settle(4)
				await _capture_ui(farm.hud, layout_id + "-queued-plots", size)
				await _dispose(farm)
				var street := JourneyStreet.new()
				street.setup({"session": ss})
				add_child(street)
				await _settle(35)
				await _capture_ui(street.ui, layout_id + "-street", size)
				street._arrive("farm")
				await _settle(5)
				await _capture_ui(street.confirmation, layout_id + "-confirmation", size, false)
				street.confirmation.dismiss(false)
				await _dispose(street)
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures, "source": "native Godot synthetic fixtures", "physical_device_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("POLISH_VISUAL_RESULT captures=", _captures.size(), " errors=", JSON.stringify(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _collect_text(node: Node, texts: Array[String], errors: Array[String]) -> void:
	super._collect_text(node, texts, errors)
	if TranslationServer.get_locale() == "en":
		var cjk := RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]")
		for value in texts:
			if cjk.search(value): errors.append("Chinese text in English UI: " + value)
