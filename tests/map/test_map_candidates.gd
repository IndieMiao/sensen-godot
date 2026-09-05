extends GdUnitTestSuite
## 受限模式下地图加载 region 的候选：高亮层 + 卡片；聚焦候选时相机飞到蓝图中心并设边界。

const MAP_POC_SCENE := "res://scenes/map_poc/map_poc.tscn"

func after_test() -> void:
	FarmChoice.clear()

func _map_with_region() -> Node:
	var scene := (load(MAP_POC_SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	var regions := FarmRegions.load_default()
	scene.enter_street_mode(regions.region("shanghai"))
	return scene

func test_candidates_loaded_into_overlay_and_panel() -> void:
	var m := _map_with_region()
	var n := FarmRegions.load_default().candidates("shanghai").size()
	assert_object(m.candidate_overlay).is_not_null()
	assert_int(m.candidate_overlay.get_child_count()).is_equal(m._candidate_bps.size())
	assert_int(m.select_panel.card_count()).is_equal(n)
	assert_bool(m._candidate_bps.size() >= 1).is_true()

func test_focus_flies_to_center_and_sets_bounds() -> void:
	var m := _map_with_region()
	var id: String = m._candidate_bps.keys()[0]
	var center: Vector2 = m._candidate_bps[id].overlay.center
	m.focus_candidate(id)
	assert_float(m.center_lat).is_equal_approx(center.x, 1e-9)
	assert_float(m.center_lng).is_equal_approx(center.y, 1e-9)
	assert_bool(m.pan_bounds.size.x > 0.0).is_true()
	assert_str(m.candidate_overlay.selected_id).is_equal(id)
	assert_str(m.select_panel.focused_id).is_equal(id)

func test_confirm_saves_choice() -> void:
	var m := _map_with_region()
	var id: String = m._candidate_bps.keys()[0]
	m._save_choice(id)
	assert_str(FarmChoice.load().layout_patch_id).is_equal(id)

func test_placement_preview_moves_freely_beyond_the_template_neighborhood() -> void:
	var m := _map_with_region()
	var id: String = m.select_panel.focused_id
	var original: Vector2 = m._candidate_bps[id].overlay.center
	m._begin_placement(id)
	m._apply_world_delta(Vector3(900, 0, -600))
	m._update_cameras()
	assert_bool(m._placement_mode).is_true()
	assert_bool(FarmPlacement.contains(m.region, m._placement_location)).is_true()
	assert_float(absf(float(m._placement_location.lng) - original.y)).is_greater(0.005)
	var preview: Vector2 = m.candidate_overlay.candidate_center(id)
	assert_float(preview.x).is_equal_approx(float(m._placement_location.lat), 0.000002)
	assert_float(preview.y).is_equal_approx(float(m._placement_location.lng), 0.00001)
	assert_vector(m._candidate_bps[id].overlay.center).is_equal(original)
	m._cancel_placement()
	assert_bool(m._placement_mode).is_false()
	assert_bool(m.select_panel._row.visible).is_true()
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
	assert_str(m.select_panel._capacity.text).is_equal("Connect to save your farm")
	await get_tree().process_frame
