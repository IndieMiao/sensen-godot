extends GdUnitTestSuite
## PRD §4.4：出生点到最远田畦时间差 <10%，九格巡回时间差 <10%；同时验证真实蓝图 checksum 跨语言一致。

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func test_metrics_on_fixture_match_node_formula() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	var m := BlueprintFairness.metrics(bp, BlueprintGrid.new(bp))
	assert_float(m.far_bed_s).is_equal_approx(2.0, 1e-6) # 最远田格 5 格 / 2.5
	assert_float(m.tour_s).is_equal_approx(22.0 / 2.5 + 18.0, 1e-6) # 5+4+8+5 格 + 9×2 s

func test_spread() -> void:
	assert_float(BlueprintFairness.spread([10.0, 10.5, 11.0])).is_equal_approx(0.1, 1e-9)
	assert_float(BlueprintFairness.spread([])).is_equal(0.0)

func test_shipped_blueprints_fair_and_checksummed() -> void:
	var regions := FarmRegions.load_default()
	assert_object(regions).is_not_null()
	var far: Array = []
	var tour: Array = []
	var seen := {}
	for rid in regions.ids():
		for c in regions.candidates(rid):
			var id := str(c.layout_patch_id)
			if seen.has(id) or id.begins_with("safe"):
				continue
			seen[id] = true
			var bp := FarmBlueprint.load_file(FarmBlueprint.asset_path(id, int(c.revision)))
			assert_object(bp).override_failure_message("缺少蓝图 %s" % id).is_not_null()
			assert_bool(bp.verify_checksum()).override_failure_message("checksum 跨语言不一致: %s" % id).is_true()
			var m := BlueprintFairness.metrics(bp, BlueprintGrid.new(bp))
			assert_float(m.far_bed_s).is_less_equal(BlueprintFairness.MAX_FAR_BED_S)
			far.append(m.far_bed_s)
			tour.append(m.tour_s)
	assert_int(seen.size()).override_failure_message("需要 6 个真实蓝图（G0-A Task 10）").is_equal(6)
	# far 的 spread 结构性地恒为 0（选畦总是优先离出生点最近，见 fairness.gd 类注释），
	# 这一条实际是 0 <= 0.10，测不出任何东西；真正的守卫是上面第 32 行逐蓝图的
	# MAX_FAR_BED_S 断言。留着这一行只是保持与 tour_s 对称，不代表它验证了公平性。
	assert_float(BlueprintFairness.spread(far)).is_less_equal(BlueprintFairness.MAX_SPREAD)
	assert_float(BlueprintFairness.spread(tour)).is_less_equal(BlueprintFairness.MAX_SPREAD)
