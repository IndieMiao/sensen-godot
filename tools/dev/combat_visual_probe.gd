extends "res://tools/dev/character_visual_probe.gd"

func _ready() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sensen-localization-qa"):
		get_tree().quit(2)
		return
	_output = ProjectSettings.globalize_path("res://output/combat-visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_run_combat")

func _combat_session(floor_number: int) -> FarmSession:
	var ss := _character_session()
	ss.state.character.hp = 72
	ss.state.character.starter_weapon_granted = true
	ss.state.bag.equipped.weapon = {"id": "bag_100", "item_id": "rusty_sword", "quantity": 1, "quality": "normal", "instance_id": "item_100"}
	ss.state.bag.slots.append({"id": "bag_101", "item_id": "copper_sword", "quantity": 1, "quality": "normal", "instance_id": "item_101"})
	ss.state.bag.slots.append({"id": "bag_102", "item_id": "trail_boots", "quantity": 1, "quality": "normal", "instance_id": "item_102"})
	ss.state.mine = {"version": 1, "run": 0, "floor": floor_number, "deepest_floor": floor_number,
		"broken": {}, "cleared_floors": [], "elevator_unlocked": false,
		"combat": {"version": 1, "sequence": 0, "monsters": {"1": [], "2": [], "3": [38], "4": [38, 38, 38], "5": [150]}}}
	return ss

func _run_combat() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(4)
		for locale in ["zh_CN", "en"]:
			Localization.select_language(locale)
			for floor_number in [3, 4, 5]:
				var ss := _combat_session(floor_number)
				Net.session = ss
				var mine := load("res://scenes/mine/mine.tscn").instantiate() as Node3D
				mine.setup({"session": ss})
				add_child(mine)
				mine.combat.grace = 999
				await _settle(25)
				mine.set_process(false)
				await _capture_ui(mine.ui, "combat-floor-%d" % floor_number, size)
				if mine.combat.enemies.size() != {3: 1, 4: 3, 5: 1}[floor_number]: _errors.append("Wrong population")
				for enemy in mine.combat.enemies.values():
					var point: Vector2 = mine.cam.unproject_position(enemy.node.position)
					if not mine.world_area().has_point(point): _errors.append("Enemy outside visible world")
				if floor_number == 5:
					var enemy: Dictionary = mine.combat.enemies.slime_1
					enemy.phase = "windup"
					enemy.timer = 0.8
					mine.combat.grace = 0
					mine.combat.step(0.01, mine.mover, false)
					mine.combat._show_swing(mine.mover.position, Vector3.FORWARD, 1.65)
					await _settle(4)
					await _capture_ui(mine.ui, "combat-windup-and-swing", size)
					ss.state.mine.broken["5"] = mine.Layout.rocks(5).map(func(rock): return rock.id)
					mine._refresh()
					await _settle(4)
					await _capture_ui(mine.ui, "combat-monsters-block-ladder", size)
					mine.pause_button.button_pressed = true
					await _settle(4)
					await _capture_ui(mine.ui, "combat-paused", size)
					mine._open_bag()
					await _settle(6)
					mine.bag_sheet.active.select_page("character")
					await _settle(4)
					await _capture_ui(mine.bag_sheet, "combat-character", size, false)
					mine.bag_sheet.active.select_stack("bag_101")
					await _settle(4)
					await _capture_ui(mine.bag_sheet, "combat-weapon-details", size, false)
					mine.bag_sheet.active.select_stack("bag_102")
					await _settle(4)
					await _capture_ui(mine.bag_sheet, "combat-boots-details", size, false)
				await _dispose(mine)
	var report := {"passed": _errors.is_empty(), "captures": _captures, "errors": _errors,
		"artificial_qa": true, "natural_player_verified": false, "physical_device_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("COMBAT_VISUAL_RESULT captures=", _captures.size(), " errors=", JSON.stringify(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)
