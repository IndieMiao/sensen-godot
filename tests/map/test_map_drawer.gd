extends GdUnitTestSuite

func before_test() -> void:
	FarmChoice.save("sh_a", 2)
	FarmRegions.save_choice("shanghai")
	Net.use_transport(FakeTransport.new([]).callable())
	Net.session.state = {"journey": {"version": 1, "unlocks": ["bistro"], "facts": []}, "clock": {"chapter_index": 0}}

func after_test() -> void:
	FarmChoice.clear()
	FarmRegions.clear_choice()
	UiState.clear()
	Net.use_transport(FakeTransport.new([]).callable())

func _map(viewport_size := Vector2i(390, 844)) -> Node:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	add_child(auto_free(viewport))
	var map := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node
	viewport.add_child(map)
	return map

func _settle() -> void:
	for frame in 8: await get_tree().process_frame

func test_drawer_and_footer_never_overlap_when_tabs_preview_or_viewport_change() -> void:
	var map := _map()
	map._set_nearby_open(true)
	var panel: NearbyPanel = map.nearby_panel
	for viewport_size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720), Vector2i(844, 390)]:
		map.get_viewport().size = viewport_size
		for places in [true, false]:
			panel.show_places(places)
			if not places:
				panel.focus(str(panel.entries[0].farm_id))
			await _settle()
			var rect := panel.get_global_rect()
			var footer: Rect2 = map.journey_footer.get_global_rect()
			var header: Rect2 = map.top_panel.get_global_rect()
			assert_float(rect.end.y).is_less_equal(footer.position.y - 7.5)
			assert_float(rect.position.y).is_greater_equal(header.end.y + 11.5)
			assert_float(rect.end.x).is_less_equal(float(viewport_size.x))
			assert_bool(rect.encloses(panel.close_button.get_global_rect())).is_true()
			assert_float(panel.close_button.size.y).is_greater_equal(44)
			assert_float(panel.close_button.size.x).is_greater_equal(44)
			assert_bool(footer.intersects(panel.close_button.get_global_rect())).is_false()

func test_close_button_toggle_and_router_back_all_dismiss_the_drawer() -> void:
	var map := _map()
	await _settle()
	for method in ["button", "toggle", "back"]:
		map.neighbours_toggle.pressed.emit()
		assert_bool(map.nearby_panel.visible).is_true()
		assert_bool(map.neighbours_toggle.button_pressed).is_true()
		map.nearby_panel.show_places(true)
		match method:
			"button": map.nearby_panel.close_button.pressed.emit()
			"toggle": map.neighbours_toggle.pressed.emit()
			"back": assert_bool(AppRouter.scene_locks_back_navigation(map)).is_true()
		await _settle()
		assert_bool(map.nearby_panel.visible).is_false()
		assert_bool(map.neighbours_toggle.button_pressed).is_false()
		assert_bool(map.journey_map.visible).is_true()
		assert_bool(AppRouter.scene_locks_back_navigation(map)).is_false()

func test_map_background_tap_closes_without_opening_a_place_or_zooming() -> void:
	var map := _map()
	await _settle()
	map._set_nearby_open(true)
	await _settle()
	var zoom: float = map.zoom
	var point := Vector2(200, 300)
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.pressed = pressed
		map._unhandled_input(event)
	assert_bool(map.nearby_panel.visible).is_false()
	assert_float(map.zoom).is_equal(zoom)
	assert_int(map._touch_count).is_equal(0)
	assert_int(map._last_tap_ms).is_equal(0)
	assert_int(AppRouter.instance_depth()).is_equal(0)

func test_neighbourhood_focus_fits_all_entrance_labels_and_does_not_recenter_on_sync() -> void:
	var map := _map()
	await _settle()
	for viewport_size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		map.get_viewport().size = viewport_size
		await _settle()
		for layout_id in ["sh_a", "sh_b", "sh_c", "la_a", "la_b", "la_c", "safe_grid"]:
			map.journey_map.configure(FarmBlueprint.load_file(FarmBlueprint.asset_path(layout_id, 2)))
			map.center_lat += 0.002
			map.zoom = 18
			map._focus_journey_map(false)
			map._update_cameras()
			var origin := MapGeoMath.geo_to_world(map.home_lat, map.home_lng, map.anchor_lat, map.anchor_lng)
			map.journey_map.sync(map.cam, origin, map._journey_area(), Net.session.state, false)
			for id in map.journey_map.buttons:
				var button: Button = map.journey_map.buttons[id]
				assert_bool(button.visible).override_failure_message("%s %s %s" % [viewport_size, layout_id, id]).is_true()
				assert_bool(map._journey_area().encloses(button.get_rect())).is_true()
				assert_float(button.modulate.a).is_greater(0.5)
			var latitude: float = map.center_lat
			map._sync_farm_markers()
			assert_float(map.center_lat).is_equal(latitude)
