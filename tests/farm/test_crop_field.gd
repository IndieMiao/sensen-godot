extends GdUnitTestSuite
## 作物渲染：阶段分段、各层实例数、以及「阶段是派生量」的边界。

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func _field() -> CropField:
	var bp := FarmBlueprint.load_file(FIX)
	var f := CropField.new(bp, 1.0)
	add_child(auto_free(f))
	return f

func _slot(state: String, crop = null, started = null, ready = null) -> Dictionary:
	return {"state": state, "crop": crop, "care_weather": null,
		"care_done_at": started, "ready_at": ready, "careful": false, "tutorial": false}

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

func test_empty_states_draw_nothing_and_wild_draws_weeds() -> void:
	# 只有 cleared 是真正的空地；tilled 画翻土板——两个服务端状态在画面上必须是两个样子。
	assert_str(CropField.layer_of(_slot("cleared"))).is_equal("")
	assert_str(CropField.layer_of(_slot("tilled"))).is_equal("soil")
	assert_str(CropField.layer_of(_slot("wild"))).is_equal("weed")
	assert_str(CropField.layer_of(_slot("sown", "L"))).is_equal("L")

func test_sync_buckets_cells_per_crop() -> void:
	var f := _field()
	f.sync({
		"1,1": _slot("wild"), "2,1": _slot("wild"),
		"3,1": _slot("tilled"), "1,2": _slot("cleared"),
		"2,2": _slot("sown", "R"), "3,2": _slot("growing", "R", 0, 400),
		"1,3": _slot("growing", "L", 0, 400), "2,3": _slot("growing", "C", 0, 400),
		"3,3": _slot("growing", "H", 0, 400),
	}, 200)
	assert_that(f.cell_counts()).is_equal({"R": 2, "L": 1, "C": 1, "H": 1, "weed": 2, "soil": 1})
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
	if DisplayServer.get_name() == "headless":
		return # 依赖真实渲染（出帖 / 着色器 / 布局尺寸）：headless CI 跳过，本地开窗跑测照常覆盖
	var f := _field()
	f.sync({"2,2": _slot("growing", "R", 0, 400)}, 400)
	var mm: MultiMesh = f._mm["R"].multimesh
	var want: Vector3 = f.bp.cell_to_world(Vector2i(2, 2), 1.0)
	for i in mm.instance_count:
		var p := mm.get_instance_transform(i).origin
		assert_bool(Vector2(p.x, p.z).distance_to(Vector2(want.x, want.z)) < 0.5).is_true()
		assert_bool(p.y > 0.0).is_true()   # 立在地面之上，不半埋


func test_everything_sits_on_top_of_the_bed_not_inside_it() -> void:
	if DisplayServer.get_name() == "headless":
		return # 依赖真实渲染（MultiMesh AABB）：headless CI 跳过
	# 2026-09-04 真机：草 0.18 高、苗 0.10 高，全埋在 0.15 高的畦面盒子里，清理了什么都看不见。
	var f := _field()
	f.ground_y = 0.15
	f.sync({"1,1": _slot("wild"), "2,1": _slot("tilled"), "3,1": _slot("sown", "R")}, 0)
	for layer in ["weed", "soil", "R"]:
		var mm: MultiMesh = f._mm[layer].multimesh
		assert_bool(mm.instance_count > 0).is_true()
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			var bottom := t.origin.y - t.basis.get_scale().y * 0.5
			assert_bool(bottom >= 0.15 - 0.001).override_failure_message(
				"%s 第 %d 个实例底面 %.3f 低于畦面 0.15" % [layer, i, bottom]).is_true()

func test_wild_tilled_sown_look_different_from_each_other_and_from_cleared() -> void:
	var f := _field()
	f.sync({"1,1": _slot("wild"), "2,1": _slot("cleared"), "3,1": _slot("tilled"), "1,2": _slot("sown", "R")}, 0)
	var c: Dictionary = f.cell_counts()
	assert_int(int(c["weed"])).is_equal(1)
	assert_int(int(c["soil"])).is_equal(1)
	assert_int(int(c["R"])).is_equal(1)
	# 草要明显高出畦面，苗要比草矮但亮
	assert_bool(CropField.WEED_SIZE.y >= 0.3).is_true()
	assert_bool(CropField._stage_color("R", 0).g > CropField.WEED_COLOR.g).is_true()


func test_instance_colors_are_declared_srgb() -> void:
	# 不声明的话 8 位实例色被当线性色，整体发白：真机上深棕翻土板成了浅褐。
	var f := _field()
	for layer in f._mm:
		var mat := (f._mm[layer] as MultiMeshInstance3D).material_override as StandardMaterial3D
		assert_bool(mat.vertex_color_is_srgb).is_true()

func test_plants_and_furrows_are_nonempty_colored_meshes_in_fixed_shared_layers() -> void:
	var f := _field()
	assert_int(f.get_child_count()).is_equal(9)
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

func test_mature_crop_silhouettes_differ_and_four_plants_fit_each_bed() -> void:
	if DisplayServer.get_name() == "headless":
		return # 依赖真实渲染（网格 AABB）：headless CI 跳过
	var f := _field()
	var cells := {}
	for i in CropField.CROPS.size():
		cells["%d,1" % i] = _slot("growing", CropField.CROPS[i], 0, 300)
	f.sync(cells, 300)
	var signatures := {}
	for crop in CropField.CROPS:
		var mm: MultiMesh = f._mm[crop].multimesh
		signatures[mm.mesh.get_faces().size()] = true
		assert_int(mm.instance_count).is_equal(4)
		var vertices: PackedVector3Array = mm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for instance in mm.instance_count:
			var transform := mm.get_instance_transform(instance)
			var crop_index := CropField.CROPS.find(crop)
			var center := f.bp.cell_to_world(Vector2i(crop_index, 1))
			var fits := true
			for vertex in vertices:
				var point: Vector3 = transform * vertex
				fits = fits and absf(point.x - center.x) < 0.46 and absf(point.z - center.z) < 0.46 and point.y < 0.5
			assert_bool(fits).override_failure_message("%s plant extends past the bed" % crop).is_true()
	assert_int(signatures.size()).is_equal(4)

func test_seedlings_have_no_roots_or_flowers_and_harvest_clears_both_parts() -> void:
	var f := _field()
	f.sync({"1,1": _slot("sown", "R"), "2,1": _slot("sown", "C"), "3,1": _slot("sown", "H")}, 0)
	for crop in ["R", "C", "H"]:
		assert_int(f._detail_mm[crop].multimesh.instance_count).is_equal(0)
	f.sync({"1,1": _slot("growing", "R", 0, 300), "2,1": _slot("growing", "C", 0, 300),
		"3,1": _slot("growing", "H", 0, 300)}, 250)
	assert_int(f._detail_mm["R"].multimesh.instance_count).is_equal(4)
	assert_int(f._detail_mm["C"].multimesh.instance_count).is_equal(4)
	assert_int(f._detail_mm["H"].multimesh.instance_count).is_equal(0)
	f.sync_snapshot([{"cell_id": "3,1", "state": "growing", "crop": "H", "ripe": true}])
	assert_int(f._detail_mm["H"].multimesh.instance_count).is_equal(4)
	f.sync({"3,1": _slot("tilled")}, 1000)
	for crop in ["R", "C", "H"]:
		assert_int(f._detail_mm[crop].multimesh.instance_count).is_equal(0)
