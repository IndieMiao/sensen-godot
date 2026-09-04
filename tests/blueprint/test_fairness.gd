extends GdUnitTestSuite
## 公平指标（PRD §4.4，2026-09-04 决策③改为绝对秒数）：
## 含预留畦的最远田格 ≤ 12 s；六蓝图纯步行巡回时间两两相差 ≤ 5 s。
## 同时验证真实蓝图 checksum 与 Node 侧跨语言一致。

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func test_metrics_on_fixture_match_node_formula() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	var m := BlueprintFairness.metrics(bp, BlueprintGrid.new(bp))
	assert_float(m.far_bed_9_s).is_equal_approx(2.0, 1e-6) # 最远田格 5 格 / 2.5
	# 纯步行巡回 5+4+8+5 = 22 格；动作时间是加在后面的常数，不再掺进被比较的量。
	assert_float(m.walk_tour_9_s).is_equal_approx(22.0 / 2.5, 1e-6)
	assert_float(m.tour_s).is_equal_approx(22.0 / 2.5 + 36 * 2.0, 1e-6)
	# 预留畦在第 7 行，比初始三畦远；r1 的指标完全看不到它。
	assert_float(m.far_bed_12_s).is_greater(m.far_bed_9_s)
	assert_float(m.walk_tour_12_s).is_greater(m.walk_tour_9_s)

func test_spread_is_absolute_seconds_not_a_ratio() -> void:
	assert_float(BlueprintFairness.spread_seconds([23.6, 25.2, 24.4])).is_equal_approx(1.6, 1e-6)
	assert_float(BlueprintFairness.spread_seconds([])).is_equal(0.0)

func test_shipped_blueprints_fair_and_checksummed() -> void:
	var regions := FarmRegions.load_default()
	assert_object(regions).is_not_null()
	var walk9: Array = []
	var walk12: Array = []
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
			assert_float(m.far_bed_9_s).is_less_equal(BlueprintFairness.MAX_FAR_BED_S)
			assert_float(m.far_bed_12_s).override_failure_message(
				"含第四畦的最远田格超上限: %s" % id).is_less_equal(BlueprintFairness.MAX_FAR_BED_S)
			walk9.append(m.walk_tour_9_s)
			walk12.append(m.walk_tour_12_s)
	assert_int(seen.size()).override_failure_message("需要 6 个真实蓝图（G0-A Task 10）").is_equal(6)
	# 九格与十二格两条路线各自守自己的预算：扩地路线的 12 格操作时长是 PRD Gate 2 的
	# 验收项，而 r1 的指标只遍历初始三畦，第四畦怎么摆都不触发门槛。
	assert_float(BlueprintFairness.spread_seconds(walk9)).is_less_equal(
		BlueprintFairness.MAX_WALK_TOUR_SPREAD_S)
	assert_float(BlueprintFairness.spread_seconds(walk12)).is_less_equal(
		BlueprintFairness.MAX_WALK_TOUR_SPREAD_S)
