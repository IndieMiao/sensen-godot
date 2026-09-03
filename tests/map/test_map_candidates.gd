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
