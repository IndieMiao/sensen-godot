extends "res://tools/dev/localization_visual_probe.gd"
## UI-only fixtures; real request commands are validated separately against the local service.

func _ready() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sensen-localization-qa"):
		get_tree().quit(2)
		return
	_output = ProjectSettings.globalize_path("res://output/requests-visual")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_run_requests")

func _request_session() -> FarmSession:
	var ss := _session()
	ss.layout_patch_id = "sh_a"
	ss.blueprint_revision = 2
	ss.region_id = "shanghai"
	ss.state.journey.unlocks.append("crafting")
	ss.state.journey.opportunities = {"nursery": {"sequence": 0, "variant": 0, "accepted": false},
		"bistro": {"sequence": 0, "variant": 0, "accepted": false}, "restorer": {"sequence": 0, "variant": 2, "accepted": false}}
	ss.state.journey.workshop = {"sequence": 0, "stock": {}, "displays": {}}
	ss.state.journey.materials = {"stone": 0, "fiber": 0, "copper_ore": 0, "rock_salt": 0}
	ss.state.journey.wood = 0
	ss.state.journey.contributions = {}
	for id in ["R", "L", "C", "H"]:
		ss.state.inventory.produce[id] = 0
		ss.state.inventory.seeds[id] = {"bought": 0, "bound": 0}
	ss.state.inventory.dishes = {"salad": 0, "tea": 0, "vegetable_soup": 0}
	ss.state.bag = {"version": 1, "sequence": 0, "capacity": 24, "next_id": 2, "slots": [], "overflow": [],
		"equipped": {"tool": {"id": "bag_1", "instance_id": "item_1", "item_id": "hand_tools", "quantity": 1, "quality": "normal"}, "accessory": null}}
	ss.state.character = {"version": 1, "buffs": []}
	for id in {"R": 1, "L": 2, "C": 1, "H": 1, "wood": 4, "stone": 3, "fiber": 2, "copper_ore": 2, "salad": 1, "tea": 1, "planter": 1}:
		_set_item(ss, id, {"R": 1, "L": 2, "C": 1, "H": 1, "wood": 4, "stone": 3, "fiber": 2, "copper_ore": 2, "salad": 1, "tea": 1, "planter": 1}[id])
	return ss

func _set_item(ss: FarmSession, id: String, quantity: int) -> void:
	ss.state.bag.slots = ss.state.bag.slots.filter(func(entry): return entry.item_id != id)
	if quantity > 0:
		ss.state.bag.slots.append({"id": "bag_" + str(ss.state.bag.next_id), "item_id": id, "quantity": quantity, "quality": "normal"})
		ss.state.bag.next_id += 1
	var source: Dictionary = ItemCatalog.definition(id).source
	match str(source.kind):
		"produce": ss.state.inventory.produce[source.id] = quantity
		"dish": ss.state.inventory.dishes[source.id] = quantity
		"material":
			if id == "wood": ss.state.journey.wood = quantity
			else: ss.state.journey.materials[source.id] = quantity
		"prop": ss.state.journey.workshop.stock[source.id] = quantity

func _run_requests() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		get_tree().root.content_scale_size = size
		get_tree().root.size = size
		await _settle(5)
		for locale in ["zh_CN", "en"]:
			Localization.select_language(locale)
			await _request_capture(size)
	if _captures.size() != 84: _errors.append("Incomplete request capture set: " + str(_captures.size()))
	var report := {"passed": _errors.is_empty(), "captures": _captures, "errors": _errors,
		"source": "synthetic request and inventory states; native Godot rendering and viewport input",
		"natural_player_verified": false, "physical_device_verified": false}
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("REQUESTS_VISUAL_RESULT captures=", _captures.size(), " errors=", JSON.stringify(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _request_capture(size: Vector2i) -> void:
	var ss := _request_session()
	Net.session = ss
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var sheet := BagSheet.new()
	sheet.setup(ss)
	canvas.add_child(sheet)
	await _settle(6)
	if sheet.active == null:
		_errors.append("Request panel did not initialize")
		canvas.queue_free()
		await _settle(3)
		return
	sheet.open()
	await _settle(5)
	await _click(sheet, "BagPage_requests")
	if sheet.active.page != "requests": _errors.append("Request page did not open")
	await _capture_ui(sheet, "requests-available", size, false)
	for slot in JourneyRequests.SLOTS: ss.state.journey.opportunities[slot].accepted = true
	ss.state.journey.tracked_opportunity = {"slot": "nursery", "sequence": 0}
	sheet.active.refresh()
	await _settle(5)
	await _capture_ui(sheet, "requests-multiple-accepted", size, false)
	await _click(sheet, "RequestDetails_restorer")
	await _capture_ui(sheet, "requests-copper-details", size, false)
	sheet.consume_back()
	await _settle(5)
	await _click(sheet, "AbandonRequest_restorer")
	await _capture_ui(sheet, "requests-abandon-confirmation", size, false)
	sheet.consume_back()
	await _settle(5)
	ss.state.journey.opportunities.bistro.variant = 2
	ss.state.journey.tracked_opportunity = {"slot": "bistro", "sequence": 0}
	sheet.active.refresh()
	await _settle(5)
	var goal := JourneyRequests.goal(ss.state, -1, "bistro")
	if goal.get("place") != "farm" or goal.get("target") != "mine": _errors.append("Missing soup salt did not lead to mine")
	await _capture_ui(sheet, "requests-missing-salt", size, false)
	await _click(sheet, "RequestDetails_bistro")
	await _capture_ui(sheet, "requests-soup-details", size, false)
	sheet.consume_back()
	await _settle(5)
	ss.state.journey.opportunities.restorer.variant = 3
	ss.state.journey.tracked_opportunity = {"slot": "restorer", "sequence": 0}
	sheet.active.refresh()
	await _settle(5)
	goal = JourneyRequests.goal(ss.state, -1, "restorer")
	if goal.get("place") != "farm" or goal.get("target") != "mine": _errors.append("Missing crate copper did not lead to mine")
	await _capture_ui(sheet, "requests-crate-missing-copper", size, false)
	_set_item(ss, "copper_ore", 3)
	sheet.active.refresh()
	await _settle(5)
	goal = JourneyRequests.goal(ss.state, -1, "restorer")
	if goal.get("place") != "nursery" or goal.get("target") != "workbench": _errors.append("Ready crate ingredients did not lead to workbench")
	await _capture_ui(sheet, "requests-crate-ready-to-make", size, false)
	ss.state.journey.opportunities.nursery = {"sequence": 1, "variant": 1, "accepted": false,
		"last_completed": {"offer_id": "fresh_nursery_leaves", "resident_id": "nursery_keeper", "sequence": 0,
			"consumed": {"L": 2}, "coins": 18, "effect": "leaves", "contribution": 1}}
	ss.state.journey.contributions.leaves = 1
	_set_item(ss, "L", 0)
	sheet.active.refresh()
	await _settle(5)
	await _click(sheet, "LastRequest_nursery")
	await _capture_ui(sheet, "requests-delivery-history", size, false)
	sheet.consume_back()
	ss.offline = true
	sheet.active.refresh()
	await _settle(5)
	await _capture_ui(sheet, "requests-offline", size, false)
	ss.offline = false
	ss.state.journey.facts.erase("shared_meal")
	ss.state.journey.opportunities.bistro.accepted = false
	sheet.active.refresh()
	await _settle(5)
	await _capture_ui(sheet, "requests-bistro-locked", size, false)
	canvas.queue_free()
	await _settle(5)
	ss.state.journey.facts.append("shared_meal")
	for id in ["nursery", "bistro", "courtyard"]:
		var place := JourneyPlace.new()
		place.place_id = id
		place.session = ss
		add_child(place)
		await _settle(30)
		place._show_panel("resident")
		await _settle(5)
		await _capture_ui(place.ui, "requests-npc-" + id, size, false)
		await _dispose(place)

func _click(sheet: BagSheet, name: String) -> void:
	var button := sheet.find_child(name, true, false) as Button
	if button == null or button.disabled:
		_errors.append("Request probe target unavailable: " + name)
		return
	if str(button.get_path()).contains("BagScroll"):
		sheet.active.body_scroll.ensure_control_visible(button)
		await _settle(4)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = button.get_global_rect().get_center()
		click.pressed = pressed
		get_viewport().push_input(click, true)
		await _settle(2)
	await _settle(5)
