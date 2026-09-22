extends Node
## Native presentation proof with synthetic inventory; never connects to a game service.

const OUT := "res://output/game-ui-2026-09-21/inventory"
var _farm: Node3D
var _model: FarmSession
var _errors: Array[String] = []
var _shots: Array = []

func _ready() -> void:
	Localization.select_language("zh_CN")
	Engine.max_fps = 60
	get_tree().root.gui_embed_subwindows = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_model = FarmSession.new(ApiClient.new("https://ui-gallery.invalid/v1", func(_method, _path, _headers, _body):
		return ApiClient.Response.new(false, 503, {"code": "OFFLINE"})))
	_model.farm_id = "synthetic-ui-farm"
	_model.layout_patch_id = "sh_a"
	_model.blueprint_revision = 2
	_model.region_id = "shanghai"
	_model.version = 1
	_model.state = _state()
	Net.session = _model
	Net.online_available = false
	_farm = preload("res://scenes/farm/farm.tscn").instantiate()
	_farm.setup({"blueprint": FarmBlueprint.load_file("res://assets/blueprints/sh_a/r2/farm_blueprint.json"), "session": _model})
	add_child(_farm)
	_run.call_deferred()

func _state() -> Dictionary:
	var slots: Array = []
	for spec in [["stone", 12], ["copper_ore", 4], ["rock_salt", 4], ["R", 8], ["wood", 4], ["fish_crucian", 17], ["L", 3], ["seed_R", 8], ["vegetable_soup", 2], ["row_tool", 1]]:
		var item := {"id": "show_" + str(spec[0]), "item_id": spec[0], "quantity": spec[1], "quality": "normal"}
		if spec[0] == "seed_R": item.seed_lot = "bought"
		if spec[0] == "row_tool": item.instance_id = "show_row"
		slots.append(item)
	return {"clock": {"chapter_index": 3, "field_condition": "sunny"}, "wallet": 187, "cells": {}, "chapters": [], "tools": {"row_tool": true},
		"xp": {"total": 0, "first_harvest_crops": ["R"]}, "character": {"version": 1, "hp": 76, "buffs": []},
		"inventory": {"seeds": {"R": {"bought": 8, "bound": 3}, "L": {"bought": 3, "bound": 0}}, "produce": {"R": 8, "L": 3}, "dishes": {"vegetable_soup": 2}},
		"engineering": {"reserved": {}}, "stall": {"settled": 0},
		"journey": {"version": 1, "facts": ["workbench", "side_path", "shared_meal"], "unlocks": ["bistro", "kitchen", "crafting", "crop_C"],
			"materials": {"stone": 12, "copper_ore": 4, "rock_salt": 4}, "wood": 4, "workshop": {"stock": {}, "sequence": 0, "displays": {}},
			"exploration": {"round": 0, "collected": []}},
		"bag": {"version": 2, "sequence": 1, "capacity": 24, "next_id": 30, "slots": slots, "overflow": [], "equipped": {
			"main_hand": {"id": "equipped_hand", "item_id": "hand_tools", "quantity": 1, "quality": "normal", "instance_id": "hand_instance"},
			"fishing_rod": {"id": "equipped_rod", "item_id": "starter_fishing_rod", "quantity": 1, "quality": "normal", "instance_id": "rod_instance"}}}}

func _settle(frames := 5) -> void:
	for _frame in frames: await get_tree().process_frame

func _press(button: Button) -> void:
	if button == null or button.disabled:
		_errors.append("Missing or disabled interaction")
		return
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await _settle(2)
	await _settle(5)

func _shot(label: String, panel: Control, size: Vector2i) -> void:
	await _settle(8)
	await RenderingServer.frame_post_draw
	var file := OUT.path_join("%s-%dx%d.png" % [label, size.x, size.y])
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(file))
	var bounds := panel.get_global_rect()
	for control in panel.find_children("*", "BaseButton", true, false):
		if control.is_visible_in_tree() and (control.size.x < 43.9 or control.size.y < 43.9):
			_errors.append(label + " small touch target " + str(control.name) + " " + str(control.size))
	var viewport := Rect2(Vector2.ZERO, Vector2(size))
	if not viewport.grow(2).encloses(bounds): _errors.append(label + " exceeds viewport: " + str(bounds))
	_shots.append({"name": label, "file": file, "size": [size.x, size.y], "panel": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]})

func _run() -> void:
	await _settle(100)
	for screen_size in [Vector2i(328, 600), Vector2i(360, 780)]:
		get_tree().root.content_scale_size = screen_size
		get_tree().root.size = screen_size
		await _settle(10)
		var canvas := CanvasLayer.new()
		canvas.layer = 10
		add_child(canvas)
		var sheet := BagSheet.new()
		sheet.setup(_model)
		canvas.add_child(sheet)
		await _settle(5)
		var farm_camera_before: Transform3D = _farm.cam.global_transform
		sheet.open()
		await _settle(5)
		await _press(sheet.find_child("BagSlot_show_stone", true, false) as Button)
		if sheet.active.grid.columns != 5: _errors.append("Inventory is not five columns")
		if sheet.active.selected_stack != "show_stone": _errors.append("Item did not select through viewport input")
		await _shot("bag-selected", sheet.panel, screen_size)
		var search := sheet.active.search
		search.grab_focus()
		search.text = "铜"
		search.text_changed.emit(search.text)
		await _settle(5)
		if not search.has_focus() or sheet.active.grid.get_child_count() != 1: _errors.append("Search lost focus or results")
		await _shot("bag-search", sheet.panel, screen_size)
		search.clear()
		search.text_changed.emit("")
		search.release_focus()
		await _settle(5)
		await _press(sheet.find_child("BagPage_character", true, false) as Button)
		await _settle(90)
		var preview = sheet.active._character_preview
		if preview == null or preview.rig == null or preview.rig.is_busy(): _errors.append("Actual character did not load")
		if not _farm.cam.current: _errors.append("Character viewport stole the farm camera")
		await _shot("character", sheet.panel, screen_size)
		if not sheet.active.body_scroll.get_global_rect().grow(1).encloses(preview.get_global_rect()): _errors.append("Character preview is cropped")
		if not farm_camera_before.is_equal_approx(_farm.cam.global_transform): _errors.append("Opening inventory shifted the farm camera")
		await _press(sheet.find_child("CharacterSlot_fishing_rod", true, false) as Button)
		if sheet.active.mode != "grid" or not sheet.find_child("CharacterSlotActions_fishing_rod", true, false).is_visible_in_tree(): _errors.append("Equipment focus did not keep the portrait visible")
		await _press(sheet.find_child("BagPage_bag", true, false) as Button)
		if preview.viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED: _errors.append("Hidden portrait still renders")
		sheet.close()
		canvas.queue_free()
		await _settle(6)
		_farm._open_life()
		await _settle(6)
		_farm.life_sheet.active.select_stack("show_stone")
		await _shot("farm-bag", _farm.life_sheet, screen_size)
		await _press(_farm.life_sheet.find_child("CloseBag", true, false) as Button)
		if _farm.life_sheet.visible: _errors.append("Farm bag close header did not close")
		var stall: StallSheet = _farm.stall
		stall.refresh(_model.state, ["R", "L", "C", "H"])
		stall.open()
		stall.fit_height((stall.get_parent() as Control).size)
		await _settle(5)
		await _press(stall.find_child("StallPage_sell", true, false) as Button)
		await _shot("stall-sell", stall, screen_size)
		await _press(stall.find_child("StallPage_seeds", true, false) as Button)
		await _shot("stall-seeds", stall, screen_size)
		stall.set_uncertain(true)
		await _shot("stall-recovery", stall, screen_size)
		stall.set_uncertain(false)
		stall.hide()
	FileAccess.open(OUT.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify({"passed": _errors.is_empty(), "errors": _errors, "captures": _shots,
		"source": "Synthetic read-only inventory and real local avatar assets; native viewport input and rendering."}, "\t"))
	print("INVENTORY_UI_GALLERY ", JSON.stringify({"passed": _errors.is_empty(), "errors": _errors, "captures": _shots.size()}))
	get_tree().quit(0 if _errors.is_empty() else 1)
