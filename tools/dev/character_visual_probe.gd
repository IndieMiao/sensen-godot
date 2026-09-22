extends "res://tools/dev/inventory_visual_probe.gd"
## Native UI fixtures are separate from the HTTP and emulator action evidence.

func _ready() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sensen-localization-qa"):
		get_tree().quit(2)
		return
	_output = ProjectSettings.globalize_path("res://output/character-visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_run_character")

func _character_session() -> FarmSession:
	var ss := _inventory_session()
	ss.state.bag.slots = ss.state.bag.slots.filter(func(entry): return entry.item_id in ["hand_tools", "copper_ore", "rock_salt", "tea", "salad", "vegetable_soup", "wood", "stone", "fiber"])
	ss.state.bag.overflow = []
	ss.state.bag.equipped.accessory = null
	ss.state.character = {"version": 1, "buffs": []}
	var index := 90
	for id in ["copper_pickaxe", "foraging_gloves", "artisan_apron"]:
		ss.state.bag.slots.append({"id": "bag_" + str(index), "item_id": id, "quantity": 1, "quality": "normal", "instance_id": "item_" + str(index)})
		index += 1
	return ss

func _run_character() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for id in CharacterModel.data().equipment:
		if not ResourceLoader.exists(str(ItemCatalog.definition(str(id)).icon)): _errors.append("Missing equipment image: " + str(id))
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(5)
		for locale in ["zh_CN", "en"]:
			Localization.select_language(locale)
			await _character_capture(size)
	if _captures.size() != 72: _errors.append("Incomplete character capture set: " + str(_captures.size()))
	var report := {"passed": _errors.is_empty(), "captures": _captures, "errors": _errors,
		"source": "synthetic ownership and meal fixtures; native Godot rendering and viewport input",
		"physical_device_verified": false, "natural_player_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CHARACTER_VISUAL_RESULT captures=", _captures.size(), " errors=", JSON.stringify(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _character_capture(size: Vector2i) -> void:
	var ss := _character_session()
	Net.session = ss
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var sheet := BagSheet.new()
	sheet.setup(ss)
	canvas.add_child(sheet)
	await _settle(6)
	if sheet.active == null:
		_errors.append("Character panel did not initialize")
		canvas.queue_free()
		await _settle(3)
		return
	sheet.open()
	await _settle(5)
	await _press(sheet.find_child("BagPage_character", true, false) as Button)
	if sheet.active.page != "character": _errors.append("Character tab did not open")
	await _capture_ui(sheet, "character-base", size, false)
	sheet.active.body_scroll.scroll_vertical = 10000
	await _settle(4)
	await _capture_ui(sheet, "character-equipment-slots", size, false)
	var change := sheet.find_child("ChangeEquipment_accessory", true, false) as Button
	sheet.active.body_scroll.ensure_control_visible(change)
	await _settle(4)
	await _press(change)
	await _capture_ui(sheet, "character-accessory-choice", size, false)
	for id in ["bag_90", "bag_91", "bag_92"]:
		sheet.active.select_stack(id)
		await _settle(5)
		await _capture_ui(sheet, "character-compare-" + str(BagModel.stack(ss.state, id).item_id), size, false)
	var soup: Dictionary = ss.state.bag.slots.filter(func(entry): return entry.item_id == "vegetable_soup")[0]
	sheet.active.select_stack(str(soup.id))
	await _settle(5)
	await _capture_ui(sheet, "character-eat-soup", size, false)
	ss.state.bag.equipped.tool = BagModel.stack(ss.state, "bag_90").duplicate(true)
	ss.state.bag.equipped.accessory = BagModel.stack(ss.state, "bag_91").duplicate(true)
	ss.state.bag.slots = ss.state.bag.slots.filter(func(entry): return entry.id not in ["bag_90", "bag_91"])
	ss.state.character.buffs = []
	for id in CharacterModel.data().consumables:
		ss.state.character.buffs.append({"id": CharacterModel.consumable(str(id)).buff_id, "source_item_id": id, "remaining_uses": 2})
	sheet.active.refresh()
	await _settle(5)
	var eat := sheet.find_child("EatItem", true, false) as Button
	if eat == null or not eat.disabled: _errors.append("Active meal can be consumed twice")
	await _capture_ui(sheet, "character-active-meal-detail", size, false)
	sheet.active.select_page("character")
	await _settle(5)
	for stat in {"tool_scope": 1, "gather_bonus": 2, "mining_bonus": 2, "craft_savings": 1}:
		var label := sheet.find_child("CharacterStat_" + stat, true, false) as Label
		if label == null or int(label.text) != {"tool_scope": 1, "gather_bonus": 2, "mining_bonus": 2, "craft_savings": 1}[stat]: _errors.append("Character display differs from equipped and meal bonuses: " + stat)
	await _capture_ui(sheet, "character-active-attributes", size, false)
	sheet.active.body_scroll.scroll_vertical = 10000
	await _settle(4)
	await _capture_ui(sheet, "character-active-meals", size, false)
	ss.offline = true
	sheet.active.refresh()
	await _settle(5)
	await _capture_ui(sheet, "character-offline", size, false)
	canvas.queue_free()
	await _settle(5)
	ss.offline = false
	var place := JourneyPlace.new()
	place.place_id = "nursery"
	place.session = ss
	add_child(place)
	await _settle(30)
	place._show_panel("workbench")
	await _settle(5)
	await _capture_ui(place.ui, "character-workbench", size, false)
	await _dispose(place)
