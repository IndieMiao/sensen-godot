extends GdUnitTestSuite
## 作物渲染：阶段分段、各层实例数、以及「阶段是派生量」的边界。

func _field() -> CropField:
	var bp := FarmPlot.blueprint_for()
	var f := CropField.new(bp, 1.0)
	add_child(auto_free(f))
	return f

func _slot(state: String, crop = null, started = null, ready = null) -> Dictionary:
	return {"state": state, "crop": crop, "watered_at": started, "ready_at": ready}

func test_stage_splits_progress_into_quarters() -> void:
	var s := _slot("growing", "R", 0, 300)
	assert_int(CropField.stage_of(s, 0)).is_equal(0)
	assert_int(CropField.stage_of(s, 99)).is_equal(0)
	assert_int(CropField.stage_of(s, 100)).is_equal(1)
	assert_int(CropField.stage_of(s, 199)).is_equal(1)
	assert_int(CropField.stage_of(s, 200)).is_equal(2)
	assert_int(CropField.stage_of(s, 299)).is_equal(2)
	assert_int(CropField.stage_of(s, 300)).is_equal(3)
	assert_int(CropField.stage_of(s, 999)).is_equal(3)

func test_unknown_ready_at_stays_at_stage_zero() -> void:
	# 刚播种、或预测器预测了照料但服务端还没回包：客户端不猜时长。
	assert_int(CropField.stage_of(_slot("sown", "R"), 999_999)).is_equal(0)
	assert_int(CropField.stage_of(_slot("growing", "R", 100, null), 999_999)).is_equal(0)

func test_only_planted_ground_draws_a_crop_layer() -> void:
	# 荒地与开垦过的空地都由地面 shader 表达；这一层只画立体作物。
	assert_str(CropField.layer_of({})).is_equal("")
	assert_str(CropField.layer_of(_slot("tilled"))).is_equal("")
	assert_str(CropField.layer_of(_slot("sown", "L"))).is_equal("L")

func test_sync_buckets_cells_per_crop() -> void:
	var f := _field()
	f.sync({
		"3,1": _slot("tilled"),
		"2,2": _slot("sown", "R"), "3,2": _slot("growing", "R", 0, 400),
		"1,3": _slot("growing", "L", 0, 400), "2,3": _slot("growing", "C", 0, 400),
		"3,3": _slot("growing", "H", 0, 400),
	}, 200)
	assert_that(f.cell_counts()).is_equal({"R": 2, "L": 1, "C": 1, "H": 1, "T": 0, "B": 0, "P": 0, "I": 0, "M": 0, "weed": 0, "soil": 0})
	assert_int(f.counts()["R"]).is_equal(2 * CropField.PER_CELL)

func test_sync_is_idempotent_and_shrinks() -> void:
	# 收获后作物层必须真的清空，不能留上一帧的实例。
	var f := _field()
	f.sync({"1,1": _slot("growing", "R", 0, 400)}, 100)
	assert_int(f.cell_counts()["R"]).is_equal(1)
	f.sync({"1,1": _slot("tilled")}, 100)
	assert_int(f.counts()["R"]).is_equal(0)

func test_ripe_cells_are_visually_distinct() -> void:
	# 成熟阶段更高更亮，玩家一眼能挑出该收的格子。
	var young := CropField.STAGE_SIZE[0]
	var ripe := CropField.STAGE_SIZE[CropField.STAGES - 1]
	assert_bool(ripe.y > young.y * 2.0).is_true()
	var c_ripe := CropField._stage_color("R", 3)
	var c_young := CropField._stage_color("R", 0)
	assert_bool(c_ripe.v > c_young.v).is_true()

func test_instances_land_on_their_cells() -> void:
	var f := _field()
	f.sync({"2,2": _slot("growing", "R", 0, 400)}, 400)
	var mm: MultiMesh = f._mm["R"].multimesh
	var want: Vector3 = f.bp.cell_to_world(Vector2i(2, 2), 1.0)
	for i in mm.instance_count:
		var p := mm.get_instance_transform(i).origin
		assert_bool(Vector2(p.x, p.z).distance_to(Vector2(want.x, want.z)) < 0.5).is_true()
		assert_bool(p.y > 0.0).is_true()   # 立在地面之上，不半埋


func test_everything_sits_on_top_of_the_ground_not_inside_it() -> void:
	# 2026-09-04 真机教训：矮的东西全埋进地里，玩家看不到自己种了什么。
	var f := _field()
	f.ground_y = 0.15
	f.sync({"3,1": _slot("sown", "R")}, 0)
	for layer in ["R"]:
		var mm: MultiMesh = f._mm[layer].multimesh
		assert_bool(mm.instance_count > 0).is_true()
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			var bottom := t.origin.y - t.basis.get_scale().y * 0.5
			assert_bool(bottom >= 0.15 - 0.001).override_failure_message(
				"%s 第 %d 个实例底面 %.3f 低于畦面 0.15" % [layer, i, bottom]).is_true()

func test_planted_and_growing_look_different_from_each_other() -> void:
	# 播下与生长中必须是两个样子；开垦与荒地的差别交给地面 shader。
	var f := _field()
	f.sync({"1,2": _slot("sown", "R"), "2,2": _slot("growing", "R", 0, 400)}, 200)
	var mm: MultiMesh = f._mm["R"].multimesh
	assert_int(mm.instance_count).is_equal(2)
	var a := mm.get_instance_transform(0).basis.get_scale()
	var b := mm.get_instance_transform(1).basis.get_scale()
	assert_bool(a.is_equal_approx(b)).is_false()


func test_instance_colors_are_declared_srgb() -> void:
	# 不声明的话 8 位实例色被当线性色，整体发白：真机上深棕翻土板成了浅褐。
	var f := _field()
	for layer in f._mm:
		var mat := (f._mm[layer] as MultiMeshInstance3D).material_override as StandardMaterial3D
		assert_bool(mat.vertex_color_is_srgb).is_true()

func test_plants_and_furrows_are_nonempty_colored_meshes_in_fixed_shared_layers() -> void:
	var f := _field()
	assert_int(f.get_child_count()).is_equal(CropField.CROPS.size() + 2 + CropField.DETAIL_STAGE.size())
	for layer in f._mm:
		var mesh: Mesh = f._mm[layer].multimesh.mesh
		assert_int(mesh.get_surface_count()).is_equal(1)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		assert_int(vertices.size()).is_greater(24)
		assert_int(colors.size()).is_equal(vertices.size())
		assert_bool(mesh.get_aabb().size.y > 0.65).is_true()
		assert_bool(mesh.get_aabb().position.y >= -0.501).is_true()
		assert_bool(mesh.get_faces().size() / 3 < 3000).is_true()
		var palette := {}
		for color in colors:
			palette[color.to_html()] = true
		assert_int(palette.size()).is_greater(1)

func test_mature_crop_silhouettes_differ_and_one_plant_per_cell() -> void:
	# 一格一株：0.5m 格里塞 4 株会糊成一团，实例数也翻四倍。
	var f := _field()
	f.sync({"1,2": _slot("growing", "R", 0, 100), "2,2": _slot("growing", "H", 0, 100)}, 100)
	assert_int(f.counts()["R"]).is_equal(1)
	assert_int(CropField.PER_CELL).is_equal(1)
	# 成熟株不能宽过一格，否则邻格的作物互相穿插。
	assert_bool(CropField.STAGE_SIZE[3].x < 1.0).is_true()


func test_seedlings_have_no_roots_or_flowers_and_harvest_clears_both_parts() -> void:
	var f := _field()
	f.sync({"1,1": _slot("sown", "R"), "2,1": _slot("sown", "C"), "3,1": _slot("sown", "H")}, 0)
	for crop in ["R", "C", "H"]:
		assert_int(f._detail_mm[crop].multimesh.instance_count).is_equal(0)

	f.sync({"1,1": _slot("growing", "R", 0, 300), "2,1": _slot("growing", "C", 0, 300),
		"3,1": _slot("growing", "H", 0, 300)}, 250)
	assert_int(f._detail_mm["R"].multimesh.instance_count).is_equal(1)
	assert_int(f._detail_mm["C"].multimesh.instance_count).is_equal(1)
	assert_int(f._detail_mm["H"].multimesh.instance_count).is_equal(0)
	f.sync_snapshot([{"cell_id": "3,1", "state": "growing", "crop": "H", "ripe": true}])
	assert_int(f._detail_mm["H"].multimesh.instance_count).is_equal(1)
	f.sync({"3,1": _slot("tilled")}, 1000)
	for crop in ["R", "C", "H"]:
		assert_int(f._detail_mm[crop].multimesh.instance_count).is_equal(0)

func test_a_full_field_of_mature_crops_stays_within_the_plant_mesh_budget() -> void:
	# 自由种植下同时在种的格数由服务端软上限（600）兜底；这里验证渲染侧的实例预算。
	var f := _field()
	var cells := {}
	for i in 200: cells["%d,%d" % [i % 20, i / 20]] = _slot("growing", "H", 0, 100)
	f.sync(cells, 100)
	# 一格一株 + 成熟期的花朵细节层，总实例数与格数同阶，不随格数平方增长。
	assert_int(f.counts()["H"]).is_equal(200)
	assert_int(f._detail_mm["H"].multimesh.instance_count).is_equal(200)
