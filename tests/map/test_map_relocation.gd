extends GdUnitTestSuite

func before_test() -> void:
	# 覆盖没有城市配置时的旧附近列表 UI（上海已改用城市地图框架）。
	CityMapData.force_legacy = true
	FarmChoice.save("sh_b", 2)
	FarmRegions.save_choice("shanghai")
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""

func after_test() -> void:
	CityMapData.force_legacy = false
	FarmChoice.clear()
	FarmRegions.clear_choice()
	UiState.clear()
	Net.use_transport(FakeTransport.new([]).callable())

func _session(responses: Array) -> FarmSession:
	var session := FarmSession.new(ApiClient.new("https://owner-only.test/v1", FakeTransport.new(responses).callable()))
	session._adopt({"farm_id": "owner-farm", "region_id": "shanghai", "layout_patch_id": "sh_b", "blueprint_revision": 2,
		"version": 8, "state": {"wallet": 187}, "relocation": {"available": true, "used": false}})
	return session

func _preview() -> Dictionary:
	return {"preview_id": "preview", "base_version": 8, "expires_at": 123456,
		"farm_terrain": JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_farm_terrain.json")),
		"moved_cells": 2, "moved_decorations": 3}

func _map() -> Node:
	var scene := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node
	add_child(auto_free(scene))
	return scene

func test_legacy_home_enters_owner_session_relocation_and_preserves_choice_through_preview() -> void:
	var saved := FarmChoice.load()
	var session := _session([{"status": 200, "json": {"farm_generation_version": 2}}, {"status": 200, "json": _preview()}])
	var map := _map()
	assert_object(map.my_farm_btn).is_not_null()
	map.enter_relocation_mode(FarmRegions.load_default().region("shanghai"), session)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(map._relocation_mode).is_true()
	assert_bool(map.my_farm_btn.visible).is_false()
	assert_bool(map.nearby_panel.visible).is_false()
	assert_bool(map.farm_markers.visible).is_false()
	assert_bool(map.select_panel.relocation_mode).is_true()
	assert_that(map._relocation_session).is_equal(session)
	await map._preview_relocation()
	assert_object(map._relocation_preview).is_not_null()
	assert_bool(map.select_panel.visible).is_false()
	assert_that(FarmChoice.load()).is_equal(saved)
	assert_str(session.layout_patch_id).is_equal("sh_b")
	assert_bool(session.relocation_available()).is_true()
	map._reselect_relocation()
	assert_object(map._relocation_preview).is_null()
	assert_bool(map.select_panel.visible).is_true()
	assert_that(FarmChoice.load()).is_equal(saved)
	await get_tree().process_frame

func test_same_city_commit_replaces_map_marker_blueprint_and_geographic_center() -> void:
	var map := _map()
	await get_tree().process_frame
	var old_layout: String = map.farm_markers.points.self.bp.layout_patch_id
	var terrain: Dictionary = _preview().farm_terrain
	var choice := {"layout_patch_id": terrain.layout_id, "revision": 1, "farm_terrain": terrain,
		"region_id": "shanghai", "location": terrain.source.center}
	map.refresh_owned_farm_after_relocation(choice)
	assert_str(map.farm_markers.points.self.bp.layout_patch_id).is_equal(terrain.layout_id)
	assert_str(map.farm_markers.points.self.bp.layout_patch_id).is_not_equal(old_layout)
	assert_that(map._farm_choice).is_equal(choice)
	var center: Vector2 = map.farm_markers.points.self.bp.overlay.center
	assert_float(map.center_lat).is_equal_approx(center.x, 0.000001)
	assert_float(map.center_lng).is_equal_approx(center.y, 0.000001)
	assert_float(map.home_lat).is_equal_approx(center.x, 0.000001)
	assert_bool(map.farm_overlay.visible).is_false()
	await get_tree().process_frame

func test_first_relocation_tap_moves_selection_even_with_hidden_old_farm_selection() -> void:
	var map := _map()
	await get_tree().process_frame
	map.farm_markers.selected_id = "self"
	UiState.write({"selected_farm_id": "self"})
	var saved_ui := UiState.read()
	map.enter_relocation_mode(FarmRegions.load_default().region("shanghai"), _session([]))
	map._update_cameras()
	assert_bool(map.farm_markers.visible).is_false()
	assert_str(map.farm_markers.selected_id).is_equal("self")
	var old_lng: float = map.center_lng
	var old_placement: Dictionary = map._placement_location.duplicate(true)
	var target: Vector2 = map.cam.unproject_position(map.center_world + Vector3(40, 0, 0))
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = target
		touch.pressed = pressed
		map._unhandled_input(touch)
	map._update_cameras()
	assert_float(map.center_lng - old_lng).is_greater(0.0001)
	assert_that(map._placement_location).is_not_equal(old_placement)
	assert_str(map.farm_markers.selected_id).is_equal("self")
	assert_that(UiState.read()).is_equal(saved_ui)
	assert_bool(map.nearby_panel.visible).is_false()
	await get_tree().process_frame

func _touch(map: Node, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	map._unhandled_input(event)

func _drag(map: Node, point: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = point
	event.relative = relative
	map._unhandled_input(event)

func test_short_relocation_drags_do_not_recenter_again_on_release() -> void:
	var map := _map()
	map.enter_relocation_mode(FarmRegions.load_default().region("shanghai"), _session([]))
	for distance in [12.0, 24.0]:
		map._reset_gesture()
		map._update_cameras()
		var origin: Vector2 = map.cam.unproject_position(map.center_world + Vector3(40, 0, 0))
		_touch(map, origin, true)
		_drag(map, origin + Vector2(distance, 0), Vector2(distance, 0))
		map._update_cameras()
		var after_drag_lat: float = map.center_lat
		var after_drag_lng: float = map.center_lng
		var after_drag_location: Dictionary = map._placement_location.duplicate(true)
		assert_float(map._fling_vel.length()).is_greater(0)
		_touch(map, origin + Vector2(distance, 0), false)
		map._update_cameras()
		assert_float(map.center_lat).is_equal(after_drag_lat)
		assert_float(map.center_lng).is_equal(after_drag_lng)
		assert_that(map._placement_location).is_equal(after_drag_location)
		assert_float(map._fling_vel.length()).is_greater(0)
		assert_int(map._last_tap_ms).is_zero()
	await get_tree().process_frame

func test_relocation_tap_with_small_finger_jitter_still_places_without_fling() -> void:
	var map := _map()
	map.enter_relocation_mode(FarmRegions.load_default().region("shanghai"), _session([]))
	map._update_cameras()
	var origin: Vector2 = map.cam.unproject_position(map.center_world + Vector3(40, 0, 0))
	_touch(map, origin, true)
	_drag(map, origin + Vector2(4, 0), Vector2(4, 0))
	map._update_cameras()
	var after_drag_lng: float = map.center_lng
	_touch(map, origin + Vector2(4, 0), false)
	map._update_cameras()
	assert_float(map.center_lng - after_drag_lng).is_greater(0.0001)
	assert_float(map._fling_vel.length()).is_zero()
	var after_tap_lng: float = map.center_lng
	map._step_fling(1.0 / 60.0)
	assert_float(map.center_lng).is_equal(after_tap_lng)
	await get_tree().process_frame

func test_preview_errors_keep_selected_location_and_distinguish_coverage_service_and_validation() -> void:
	var invalid := _preview()
	invalid.farm_terrain.plot.checksum = "0".repeat(64)
	var failures := [
		{"status": 422, "json": {"code": "GEOGRAPHY_INCOMPLETE"}, "expected": "GEOGRAPHY_INCOMPLETE"},
		{"status": 503, "json": {"code": "GEOGRAPHY_UNAVAILABLE"}, "expected": "GEOGRAPHY_UNAVAILABLE"},
		{"status": 200, "json": invalid, "expected": "INVALID_FARM_TERRAIN"},
	]
	var responses := []
	for failure in failures:
		responses.append({"status": 200, "json": {"farm_generation_version": 2}})
		responses.append(failure)
	var session := _session(responses)
	var map := _map()
	map.enter_relocation_mode(FarmRegions.load_default().region("shanghai"), session)
	map.fly_to(31.233333, 121.472222)
	map._update_cameras()
	var selected: Dictionary = map._placement_location.duplicate(true)
	var saved := FarmChoice.load()
	var messages := {}
	for failure in failures:
		await map._preview_relocation()
		assert_str(session.last_error_code).is_equal(failure.expected)
		assert_str(map.select_panel._capacity.text).is_equal(map._generation_error(failure.expected))
		messages[map.select_panel._capacity.text] = true
		assert_that(map._placement_location).is_equal(selected)
		assert_that(FarmChoice.load()).is_equal(saved)
		assert_bool(session.relocation_available()).is_true()
		assert_bool(session.relocation_pending()).is_false()
		assert_bool(map.select_panel.confirm_button.disabled).is_false()
		assert_bool(map.select_panel._cancel.disabled).is_false()
		map._update_cameras()
		assert_str(map.select_panel._capacity.text).is_equal(map._generation_error(failure.expected))
	assert_int(messages.size()).is_equal(3)
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	assert_str(L10n.text(map._generation_error("GEOGRAPHY_INCOMPLETE"))).contains("重新选址")
	assert_str(L10n.text(map._generation_error("GEOGRAPHY_UNAVAILABLE"))).contains("稍后重试")
	assert_str(L10n.text(map._generation_error("INVALID_FARM_TERRAIN"))).contains("校验未通过")
	TranslationServer.set_locale(locale)
	await get_tree().process_frame
