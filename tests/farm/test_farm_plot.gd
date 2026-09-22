extends GdUnitTestSuite
## 农场地面属性的两端对账。
##
## checksum 是光栅化结果的指纹：Godot 与 Node 各算一份，都要等于 farm_plot.json 里写的那串。
## 谁改了数据或改歪了任一端的光栅化，这里立刻变红。

func test_rasterizes_to_the_checksum_written_in_the_data_file() -> void:
	var bp := FarmPlot.blueprint_for()
	assert_object(bp).is_not_null()
	assert_bool(FarmPlot.verify_checksum(bp)).is_true()

func test_tiles_are_fifty_percent_larger_without_scaling_the_character() -> void:
	var bp := FarmPlot.blueprint_for()
	assert_int(bp.grid.x).is_equal(64)
	assert_int(bp.cell_mm).is_equal(750)
	assert_float(bp.play_area_m).is_equal_approx(48.0, 0.001)

func test_counts_match_the_server_side_rasteriser() -> void:
	var bp := FarmPlot.blueprint_for()
	var till := 0
	var place := 0
	for j in bp.grid.y:
		for i in bp.grid.x:
			var c := Vector2i(i, j)
			if bp.mask_has("cultivable", c): till += 1
			if bp.mask_has("buildable", c): place += 1
	# 与 server/test/domain/plot.test.ts 的同一组数字。2495：房子周围的 homestead_yard
	# （草地）从可耕地里划走了 184 格——那圈院子是给既有美术构图留的地方。
	assert_int(till).is_equal(3003)
	assert_int(place).is_equal(3086)

func test_separates_farmable_ground_from_placeable_ground() -> void:
	var bp := FarmPlot.blueprint_for()
	var house: Vector2i = bp.anchor("house")
	# 建筑：既不能开垦也不能放置，且挡路
	assert_bool(bp.mask_has("cultivable", house)).is_false()
	assert_bool(bp.mask_has("buildable", house)).is_false()
	assert_bool(bp.is_walkable(house)).is_false()
	# 路：可放置、可通行，但不能开垦
	var path := Vector2i(29, 35)
	assert_bool(bp.mask_has("cultivable", path)).is_false()
	assert_bool(bp.mask_has("buildable", path)).is_true()
	assert_bool(bp.is_walkable(path)).is_true()

func test_farmed_ground_stays_walkable() -> void:
	# 与旧 FarmInterior 相反：开垦过的地能站上去，这是星露谷式操作的前提。
	var bp := FarmPlot.blueprint_for()
	var soil := Vector2i(0, 0)
	assert_bool(bp.mask_has("cultivable", soil)).is_true()
	assert_bool(bp.is_walkable(soil)).is_true()

func test_has_no_bed_anchors_left() -> void:
	# 田畦概念随渐进解锁一同退役。
	var bp := FarmPlot.blueprint_for()
	assert_array(bp.beds()).is_empty()
	assert_array(bp.reserved_bed().get("cells", [])).is_empty()

func test_woody_crops_block_movement_while_annuals_do_not() -> void:
	# 「某些种植可以穿越、某些不能」：判据是作物表的 woody，不是格子状态。
	assert_bool(CropInfo.is_woody("T")).is_true()
	for annual in ["R", "L", "C", "H"]:
		assert_bool(CropInfo.is_woody(annual)).is_false()
	assert_bool(CropInfo.blocks_movement({"state": "growing", "crop": "T"})).is_true()
	assert_bool(CropInfo.blocks_movement({"state": "growing", "crop": "R"})).is_false()
	# 只有真的种下去才挡路：空地与刚开垦的地都能走。
	assert_bool(CropInfo.blocks_movement({"state": "tilled", "crop": null})).is_false()
	assert_bool(CropInfo.blocks_movement({})).is_false()

func test_blocking_a_cell_is_incremental_and_reversible() -> void:
	# 果树随时种下、收走，为此重建整张 AStar 是纯浪费。
	var bp := FarmPlot.blueprint_for()
	var grid := BlueprintGrid.new(bp)
	var cell := Vector2i(10, 10)
	assert_bool(bp.is_walkable(cell)).is_true()
	assert_bool(grid.path(Vector2i(8, 10), Vector2i(12, 10)).has(cell)).is_true()
	grid.set_solid(cell, true)
	assert_bool(grid.path(Vector2i(8, 10), Vector2i(12, 10)).has(cell)).is_false()
	grid.set_solid(cell, false)
	assert_bool(grid.path(Vector2i(8, 10), Vector2i(12, 10)).has(cell)).is_true()
