extends GdUnitTestSuite

const FARM := preload("res://scenes/farm/farm.tscn")
var _locale := ""
var _posted := false

func before_test() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")

func after_test() -> void:
	TranslationServer.set_locale(_locale)
	FarmChoice.clear()
	for frame in 3: await get_tree().process_frame

func _farm(size: Vector2i) -> Node:
	var viewport := auto_free(SubViewport.new()) as SubViewport
	viewport.size = size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var plot := FarmPlot.blueprint_for()
	var available: Array[Vector2i] = []
	for y in plot.grid.y:
		for x in plot.grid.x:
			if plot.mask_has("cultivable", Vector2i(x, y)): available.append(Vector2i(x, y))
	available.sort_custom(func(a, b): return (a - plot.anchor("spawn")).length_squared() < (b - plot.anchor("spawn")).length_squared())
	var cells := {"%d,%d" % [available[0].x, available[0].y]: {"state": "growing", "crop": "R", "ready_at": 1},
		"%d,%d" % [available[1].x, available[1].y]: {"state": "tilled", "crop": null}}
	var session := FarmSession.new(ApiClient.new("https://farm-ui-fixture.invalid/v1", FakeTransport.new([]).callable()))
	session._adopt({"farm_id": "farm-ui-fixture", "region_id": "los_angeles", "layout_patch_id": "la_c",
		"blueprint_revision": 2, "version": 1,
		"state": {"wallet": 5432, "cells": cells, "clock": {"chapter_index": 0, "field_condition": "sunny"},
			"inventory": {"seeds": {"R": {"bound": 6}, "L": {"bound": 3}, "C": {"bound": 2}, "H": {"bound": 1}}, "produce": {}},
			"xp": {"total": 0, "first_harvest_crops": []}, "chapters": []}})
	var farm := FARM.instantiate()
	farm.setup({"session": session})
	viewport.add_child(farm)
	farm.set_process(false)
	farm.get_node("HUD/SafeArea").apply_margins(Rect2i(0, 24, size.x, size.y - 40), size, size)
	for frame in 120:
		await get_tree().process_frame
		if frame >= 4 and not farm._focus_button._rendering and farm._focus_button._shown_key == farm._focus_button._desired_key: break
	farm._update_camera()
	return farm

func _drawn() -> void:
	_posted = true

## The screenshot is only a review aid: a window that does not draw (headless, the runner's minimized window on macOS,
## an occluded one) never posts a draw, so it waits at most 2 s for one and skips the picture without it.
func _capture(farm: Node, file: String) -> void:
	if DisplayServer.get_name() == "headless" or not DisplayServer.window_can_draw(): return
	await get_tree().process_frame
	_posted = false
	RenderingServer.frame_post_draw.connect(_drawn, CONNECT_ONE_SHOT)
	var start := Time.get_ticks_msec()
	while not _posted and Time.get_ticks_msec() - start < 2000: await get_tree().process_frame
	if not _posted:
		RenderingServer.frame_post_draw.disconnect(_drawn)
		return
	var directory := "res://output/ui-redesign-2026-09-21/farm"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	assert_int(farm.get_viewport().get_texture().get_image().save_png(directory.path_join(file))).is_equal(OK)

func test_chinese_phone_hud_is_compact_readable_and_quick_actions_leave_world_visible() -> void:
	for size in [Vector2i(360, 640), Vector2i(390, 844)]:
		var farm := await _farm(size)
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		var top: Rect2 = farm.get_node("HUD/SafeArea/Root/TopBar").get_global_rect()
		var dock: Rect2 = farm.hud._bottom.get_global_rect()
		assert_float(top.size.y).is_less_equal(48)
		assert_float(dock.size.y).is_less_equal(56)
		assert_bool(screen.encloses(top)).is_true()
		assert_bool(screen.encloses(dock)).is_true()
		assert_str(farm.title.text).is_equal("我的农场")
		assert_str(farm.hud._condition.text).is_equal("晴天")
		assert_str(farm.hud._coins.text).is_equal("5432")
		assert_str(farm.hud._timer_label.text).is_equal(L10n.text("Harvest ready"))
		assert_bool(farm.hud._seed_scroll.is_visible_in_tree()).is_false()
		for button in [farm.exit_btn, farm.title, farm.hud._goals_header, farm.hud._mode_toggle, farm.hud._cta, farm.hud._life_button, farm._focus_button]:
			assert_float(button.get_global_rect().size.y).is_greater_equal(44)
			assert_bool(screen.grow(1).encloses(button.get_global_rect())).is_true()
		assert_bool(farm.hud._work_backing.visible).is_false()
		await _capture(farm, "walking-%d.png" % size.x)
		farm._set_work_mode(true)
		farm.hud.set_seeds(farm.session.state.inventory, ["R", "L", "C", "H"], true)
		for frame in 3: await get_tree().process_frame
		assert_bool(farm.hud._seed_scroll.is_visible_in_tree()).is_true()
		assert_float(farm.hud._bottom.size.y).is_less_equal(122)
		await _capture(farm, "farming-%d.png" % size.x)
		var camera: Transform3D = farm.cam.global_transform
		farm.title.pressed.emit()
		for frame in 3: await get_tree().process_frame
		assert_bool(farm.hud._quick_actions.is_visible_in_tree()).is_true()
		assert_bool(GameUi.modal_is_open(farm)).is_true()
		assert_bool(screen.grow(1).encloses(farm.hud._quick_actions.get_global_rect())).is_true()
		assert_float(farm.hud._quick_actions.global_position.y).is_greater(float(size.y) * 0.25)
		assert_that(farm.cam.global_transform).is_equal(camera)
		await _capture(farm, "actions-%d.png" % size.x)
		farm.hud.close_modal()
		await get_tree().process_frame
