extends GdUnitTestSuite
## 受限模式下地图加载 region 的候选：高亮层 + 卡片；聚焦候选时相机飞到蓝图中心并设边界。

const MAP_POC_SCENE := "res://scenes/map_poc/map_poc.tscn"

func after_test() -> void:
	while AppRouter._navigation_pending: await get_tree().process_frame
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame
	FarmChoice.clear()
	Net.use_transport(FakeTransport.new([]).callable())

func _map_with_region() -> Node:
	var scene := (load(MAP_POC_SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	var regions := FarmRegions.load_default()
	scene.enter_street_mode(regions.region("shanghai"))
	return scene

func test_city_starts_directly_in_free_location_selection_without_template_cards() -> void:
	var m := _map_with_region()
	assert_object(m.candidate_overlay).is_not_null()
	assert_int(m.select_panel.card_count()).is_zero()
	assert_bool(m.select_panel.generation_mode).is_true()
	assert_bool(m._placement_mode).is_true()
	assert_str(m.select_panel.focused_id).is_equal("map_selection")
	assert_bool(FarmChoice.load().is_empty()).is_true()

func test_placement_preview_moves_freely_beyond_the_original_city_center() -> void:
	var m := _map_with_region()
	var id: String = m.select_panel.focused_id
	var original: Vector2 = m._candidate_bps[id].overlay.center
	m._apply_world_delta(Vector3(900, 0, -600))
	m._update_cameras()
	assert_bool(FarmPlacement.generated_contains(m.region, m._placement_location)).is_true()
	assert_float(absf(float(m._placement_location.lng) - original.y)).is_greater(0.005)
	var preview: Vector2 = m.candidate_overlay.candidate_center(id)
	assert_float(preview.x).is_equal_approx(float(m._placement_location.lat), 0.000002)
	assert_float(preview.y).is_equal_approx(float(m._placement_location.lng), 0.00001)
	assert_vector(m._candidate_bps[id].overlay.center).is_equal(original)
	assert_bool(FarmChoice.load().is_empty()).is_true()
	await get_tree().process_frame

func test_offline_placement_failure_keeps_the_preview_without_saving() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""
	var m := _map_with_region()
	var id: String = m.select_panel.focused_id
	m._begin_placement(id)
	await m._on_candidate_confirmed(id)
	assert_bool(m._placement_mode).is_true()
	assert_bool(FarmChoice.load().is_empty()).is_true()
	assert_bool(m.select_panel.confirm_button.disabled).is_false()
	assert_str(m.select_panel._capacity.text).is_equal("Could not connect. Try again.")
	await get_tree().process_frame

func test_missing_farm_can_be_placed_and_enters_with_a_server_session() -> void:
	var t := FakeTransport.new([])
	Net.use_transport(t.callable())
	Net.client.token = "tok"
	Net.session.last_error_code = "NO_FARM"
	var m := _map_with_region()
	var id: String = m.select_panel.focused_id
	m._begin_placement(id)
	var location: Dictionary = m._placement_location.duplicate()
	var terrain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_compact_farm_terrain.json"))
	t.responses = [
		{"status": 404, "json": {"code": "NO_FARM"}},
		{"status": 200, "json": {"farm_generation_version": 2}},
		{"status": 201, "json": {"farm_id": "new_farm", "version": 0, "state": {},
			"layout_patch_id": terrain.layout_id, "blueprint_revision": 1, "farm_terrain": terrain, "region_id": "shanghai", "location": location}},
	]
	await m._on_candidate_confirmed(id)
	while AppRouter._navigation_pending: await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_object(AppRouter.top_instance().session).is_not_null()
	assert_str(AppRouter.top_instance().session.farm_id).is_equal("new_farm")
	for stored: Dictionary in [t.last_body().location, FarmChoice.load().location]:
		assert_float(float(stored.lat)).is_equal_approx(float(location.lat), 0.000000001)
		assert_float(float(stored.lng)).is_equal_approx(float(location.lng), 0.000000001)

func test_generation_failure_keeps_chosen_location_and_allows_reselection() -> void:
	var t := FakeTransport.new([])
	Net.use_transport(t.callable())
	Net.client.token = "tok"
	Net.session.last_error_code = "NO_FARM"
	var m := _map_with_region()
	var location: Dictionary = m._placement_location.duplicate()
	for code in ["LOCATION_ALL_WATER", "LOCATION_ALL_DESERT", "LOCATION_UNSUITABLE", "GEOGRAPHY_UNAVAILABLE", "GEOGRAPHY_INCOMPLETE"]:
		t._cursor = 0
		t.responses = [{"status": 404, "json": {"code": "NO_FARM"}},
			{"status": 200, "json": {"farm_generation_version": 2}},
			{"status": 422, "json": {"code": code}}]
		await m._on_candidate_confirmed(m.select_panel.focused_id)
		assert_that(m._placement_location).is_equal(location)
		assert_bool(m._placement_mode).is_true()
		assert_bool(m.select_panel.confirm_button.disabled).is_false()
		assert_str(m.select_panel._capacity.text).is_equal(m._generation_error(code))
		assert_int(AppRouter.instance_depth()).is_zero()
		assert_bool(FarmChoice.load().is_empty()).is_true()
