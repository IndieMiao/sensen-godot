extends GdUnitTestSuite

func after_test() -> void:
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame

func _session(chapter: int) -> FarmSession:
	var s := FarmSession.new(ApiClient.new("http://test", FakeTransport.new([]).callable()))
	s.state = {"clock": {"chapter_index": chapter}, "nursery": {"stage": "derelict", "appearance": null}}
	return s

func test_place_access_uses_authoritative_chapter() -> void:
	assert_bool(PlaceCatalog.available("nursery", _session(0).state)).is_true()
	assert_bool(PlaceCatalog.available("courtyard", _session(0).state)).is_true()
	assert_bool(PlaceCatalog.available("bistro", _session(0).state)).is_false()
	assert_bool(PlaceCatalog.available("bistro", _session(1).state)).is_true()
	assert_bool(PlaceCatalog.available("unknown", _session(6).state)).is_false()
	assert_bool(PlaceCatalog.available("nursery", {})).is_false()

func test_enter_and_return_restore_previous_scene_and_camera() -> void:
	var previous := AppRouter.push_instance("res://tests/fixtures/scenes/stack_probe.tscn")
	var place := AppRouter.push_instance(AppRouter.PLACE, {"place_id": "bistro", "session": _session(1)})
	await get_tree().process_frame
	assert_bool(get_viewport().get_camera_3d() == place.cam).is_true()
	assert_int(previous.suspended).is_equal(1)
	assert_bool(get_viewport().transparent_bg).is_false()
	place._exit.pressed.emit()
	await get_tree().process_frame
	assert_bool(is_instance_valid(place)).is_false()
	assert_bool(AppRouter.top_instance() == previous).is_true()
	assert_bool(get_viewport().get_camera_3d() == previous.cam).is_true()
	assert_int(previous.resumed).is_equal(1)

func test_locked_scene_cannot_be_opened_by_direct_routing() -> void:
	var previous := AppRouter.push_instance("res://tests/fixtures/scenes/stack_probe.tscn")
	AppRouter.push_instance(AppRouter.PLACE, {"place_id": "bistro", "session": _session(0)})
	await get_tree().process_frame
	assert_bool(AppRouter.top_instance() == previous).is_true()

func test_places_tab_preserves_farm_selection_and_scroll() -> void:
	var panel := NearbyPanel.new()
	add_child(auto_free(panel))
	panel.set_entries([{"farm_id": "f1", "avatar_ref": "preset_a", "nursery_stage": "derelict"}], 1)
	panel.focus("f1")
	panel.set_place_state(_session(0).state)
	panel.show_places(true)
	assert_str(panel.focused_id).is_equal("f1")
	assert_bool(panel._farm_content.visible).is_false()
	assert_bool(panel._place_buttons.bistro.disabled).is_true()
	panel.set_place_state(_session(1).state)
	assert_bool(panel._place_buttons.bistro.disabled).is_false()
	panel.show_places(false)
	assert_str(panel.focused_id).is_equal("f1")
	assert_bool(panel._preview.visible).is_true()
