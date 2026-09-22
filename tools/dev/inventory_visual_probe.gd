extends "res://tools/dev/localization_visual_probe.gd"
## Synthetic ownership fixtures exercise native layout; server tests verify inventory arithmetic.

func _ready() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sensen-localization-qa"):
		get_tree().quit(2)
		return
	_output = ProjectSettings.globalize_path("res://output/inventory-visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_run_inventory")

func _inventory_session() -> FarmSession:
	var ss := _session()
	ss.layout_patch_id = "sh_a"
	ss.blueprint_revision = 2
	ss.region_id = "shanghai"
	ss.state.journey.materials.merge({"copper_ore": 8, "rock_salt": 3})
	ss.state.journey.workshop = {"sequence": 0, "stock": {"crate": 2}, "displays": {}}
	ss.state.inventory.dishes.vegetable_soup = 2
	var bag := {"version": 1, "sequence": 0, "capacity": 24, "next_id": 100,
		"slots": [], "overflow": [], "equipped": {"tool": {"id": "bag_99", "item_id": "row_tool", "quantity": 1, "quality": "normal", "instance_id": "item_99"}}}
	for id in ItemCatalog.data().items:
		if id in ["row_tool", "fountain", "sign", "copper_pickaxe", "foraging_gloves", "artisan_apron"]: continue
		var spec := ItemCatalog.definition(str(id))
		var entry := {"id": "bag_" + str(bag.slots.size() + 1), "item_id": id, "quantity": mini(8, int(spec.max_stack)), "quality": "normal"}
		if spec.source.kind == "seed": entry.seed_lot = "bound"
		if int(spec.max_stack) == 1: entry.instance_id = "item_" + str(bag.slots.size() + 1)
		bag.slots.append(entry)
	bag.slots.append({"id": "bag_70", "item_id": "copper_ore", "quantity": 98, "quality": "normal"})
	bag.overflow.append({"id": "bag_80", "item_id": "wood", "quantity": 99, "quality": "normal"})
	ss.state.bag = bag
	return ss

func _run_inventory() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for id in ItemCatalog.data().items:
		if not ResourceLoader.exists(str(ItemCatalog.definition(str(id)).icon)):
			_errors.append("Missing item image: " + str(id))
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(5)
		for locale in ["zh_CN", "en"]:
			Localization.select_language(locale)
			await _inventory_capture(size)
	Localization.select_language("zh_CN")
	if _captures.size() != 90: _errors.append("Incomplete inventory visual run: expected 90 captures, got " + str(_captures.size()))
	var report := {"passed": _errors.is_empty(), "errors": _errors, "captures": _captures,
		"source": "synthetic ownership fixtures; native Godot rendering and viewport input",
		"physical_device_verified": false, "natural_player_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("INVENTORY_VISUAL_RESULT captures=", _captures.size(), " errors=", JSON.stringify(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _inventory_capture(size: Vector2i) -> void:
	var ss := _inventory_session()
	Net.session = ss
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var sheet := BagSheet.new()
	sheet.setup(ss)
	canvas.add_child(sheet)
	await _settle(6)
	if sheet.active == null:
		_errors.append("Bag panel did not initialize")
		canvas.queue_free()
		await _settle(2)
		return
	sheet.open()
	await _settle(6)
	await _capture_ui(sheet, "bag-grid", size, false)
	var search := sheet.active.search
	search.grab_focus()
	search.text = "铜" if TranslationServer.get_locale() == "zh_CN" else "copper"
	search.text_changed.emit(search.text)
	await _settle(5)
	if sheet.active.search != search or not search.has_focus(): _errors.append("Search lost focus during filtering")
	var copper_stacks := sheet.active.grid.get_children().filter(func(button): return str(button.tooltip_text).begins_with(ItemCatalog.name_of("copper_ore") + " x"))
	if copper_stacks.size() != 2: _errors.append("Copper search did not show both stacks")
	await _capture_ui(sheet, "bag-search", size, false)
	search.clear()
	search.text_changed.emit("")
	search.release_focus()
	await _settle(5)
	for item_id in ["seed_R", "copper_ore", "rock_salt", "vegetable_soup", "crate", "hand_tools"]:
		var entry: Dictionary = ss.state.bag.slots.filter(func(value): return value.item_id == item_id)[0]
		var button := sheet.find_child("BagSlot_" + str(entry.id), true, false) as Button
		if button == null:
			_errors.append("Missing clickable item: " + str(item_id))
			continue
		sheet.active.body_scroll.ensure_control_visible(button)
		await _settle(4)
		await _press(button)
		if sheet.active.mode != "details": _errors.append("Item click did not open details: " + str(item_id))
		await _capture_ui(sheet, "bag-detail-" + str(item_id), size, false)
		if item_id == "copper_ore":
			for action in [["SplitStack", "split"], ["MergeStacks", "merge"], ["DiscardStack", "discard"]]:
				var command := sheet.find_child(action[0], true, false) as Button
				if command == null:
					_errors.append("Missing management action: " + str(action[0]))
					continue
				sheet.active.body_scroll.ensure_control_visible(command)
				await _settle(3)
				await _press(command)
				if sheet.active.mode != action[1]: _errors.append("Management click did not change view: " + str(action[0]))
				await _capture_ui(sheet, "bag-" + str(action[1]), size, false)
				sheet.consume_back()
				await _settle(4)
		sheet.consume_back()
		await _settle(5)
	await _press(sheet.find_child("BagEquipped", true, false) as Button)
	await _capture_ui(sheet, "bag-equipped", size, false)
	sheet.consume_back()
	await _settle(5)
	await _press(sheet.find_child("BagOverflow", true, false) as Button)
	await _capture_ui(sheet, "bag-overflow", size, false)
	sheet.consume_back()
	await _settle(5)
	while ss.state.bag.slots.size() < 24:
		ss.state.bag.slots.append({"id": "bag_" + str(ss.state.bag.slots.size() + 100), "item_id": "wood", "quantity": 99, "quality": "normal"})
	sheet.active.refresh()
	await _settle(5)
	await _capture_ui(sheet, "bag-full", size, false)
	ss.offline = true
	sheet.active.refresh()
	await _settle(5)
	await _capture_ui(sheet, "bag-offline", size, false)
	canvas.queue_free()
	await _settle(5)

func _press(button: Button) -> void:
	if button == null or button.disabled:
		_errors.append("Probe target is absent or disabled")
		return
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = button.get_global_rect().get_center()
		click.pressed = pressed
		get_viewport().push_input(click, true)
		await _settle(2)
	await _settle(5)
