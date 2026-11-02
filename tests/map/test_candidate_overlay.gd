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
	assert_int(node.get_child_count()).is_equal(1) # One closed boundary; map streets stay unobscured.
	var outline := (node.get_child(0) as MeshInstance3D).mesh
	assert_int((outline.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(24)
	var square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	assert_int((CandidateOverlay.block_mesh(square).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(6)
	assert_int((CandidateOverlay.path_mesh(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]), 4.0).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(12)

func test_select_changes_outline_color_and_reanchor_moves() -> void:
	var ov = auto_free(CandidateOverlay.new())
	add_child(ov)
	var bp := FarmBlueprint.load_file(FIX)
	ov.set_candidates([bp], 31.2, 121.4)
	var mi := ov.get_child(0).get_child(0) as MeshInstance3D
	assert_that((mi.material_override as StandardMaterial3D).albedo_color).is_equal(CandidateOverlay.IDLE_OUTLINE)
	assert_int((mi.material_override as StandardMaterial3D).transparency).is_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)
	ov.select("fix_grid")
	assert_str(ov.selected_id).is_equal("fix_grid")
	assert_that((mi.material_override as StandardMaterial3D).albedo_color).is_equal(GameUi.GOLD)
	var before := (ov.get_child(0) as Node3D).position
	ov.reanchor(31.2, 121.41)
	assert_bool((ov.get_child(0) as Node3D).position.x < before.x).is_true() # 锚点东移，候选相对西移

## 故意不 await 任何一帧：queue_free() 只是把释放排到本帧末尾，节点本帧内仍留在树里；
## 如果 set_candidates() 只 queue_free 不 remove_child，第二次调用会看到第一次的旧节点还没走，
## get_child_count() 会变成 2 而不是 1。
func test_set_candidates_twice_does_not_accumulate() -> void:
	var ov = auto_free(CandidateOverlay.new())
	add_child(ov)
	var bp := FarmBlueprint.load_file(FIX)
	ov.set_candidates([bp], 31.2, 121.4)
	ov.set_candidates([bp], 31.2, 121.4)
	assert_int(ov.get_child_count()).is_equal(1)
	assert_int(ov.candidate_ids().size()).is_equal(1)
	await get_tree().process_frame # 断言已完成；让第一次调用 remove_child 后排队的 queue_free 落地，避免误报 orphan
