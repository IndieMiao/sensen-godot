extends GdUnitTestSuite
## 候选高亮由同一份蓝图的 overlay_wgs84 生成（PRD §4.5「不允许分别临摹」），在 Godot 层贴地绘制。

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func test_to_local_center_is_origin() -> void:
	assert_that(CandidateOverlay.geo_to_local(31.2, 121.4, 31.2, 121.4)).is_equal(Vector2.ZERO)
	var east := CandidateOverlay.geo_to_local(31.2, 121.401, 31.2, 121.4)
	assert_bool(east.x > 0.0 and absf(east.y) < 1e-6).is_true()

func test_meshes_from_fixture() -> void:
	var ov = auto_free(CandidateOverlay.new())
	add_child(ov)
	var bp := FarmBlueprint.load_file(FIX)
	ov.set_candidates([bp], 31.2, 121.4)
	assert_that(ov.candidate_ids()).is_equal(PackedStringArray(["fix_grid"]))
	assert_that(ov.candidate_center("fix_grid")).is_equal(Vector2(31.2, 121.4))
	var node := ov.get_child(0) as Node3D
	assert_int(node.get_child_count()).is_equal(3) # 1 block + 2 paths
	var square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	assert_int((CandidateOverlay.block_mesh(square).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(6)
	assert_int((CandidateOverlay.path_mesh(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]), 4.0).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(12)

func test_select_changes_alpha_and_reanchor_moves() -> void:
	var ov = auto_free(CandidateOverlay.new())
	add_child(ov)
	var bp := FarmBlueprint.load_file(FIX)
	ov.set_candidates([bp], 31.2, 121.4)
	var mi := ov.get_child(0).get_child(0) as MeshInstance3D
	assert_float((mi.material_override as StandardMaterial3D).albedo_color.a).is_equal_approx(CandidateOverlay.ALPHA_IDLE, 1e-6)
	ov.select("fix_grid")
	assert_str(ov.selected_id).is_equal("fix_grid")
	assert_float((mi.material_override as StandardMaterial3D).albedo_color.a).is_equal_approx(CandidateOverlay.ALPHA_SELECTED, 1e-6)
	var before := (ov.get_child(0) as Node3D).position
	ov.reanchor(31.2, 121.41)
	assert_bool((ov.get_child(0) as Node3D).position.x < before.x).is_true() # 锚点东移，候选相对西移
