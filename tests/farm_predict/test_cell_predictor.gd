extends GdUnitTestSuite
## 预测器 vs 服务端归约器：同一条命令序列，逐格比对 state/crop/care_weather。
## fixture 由 server/tools/gen_predict_fixture.ts 用**真实服务端归约器**生成，
## 不是手写的期望值——这是跨语言状态机一致性的唯一硬证据。

const FIX := "res://tests/fixtures/farm_predict_sequence.json"

var _fx: Dictionary

func before_test() -> void:
	_fx = JSON.parse_string(FileAccess.get_file_as_string(FIX))

func _predictor() -> CellPredictor:
	return CellPredictor.new(_fx.cells0, _fx.cultivable, _fx.reserved)

func _payload(step: Dictionary) -> Dictionary:
	var p := {"cell_ids": step.cell_ids}
	match str(step.type):
		"sow_cells":
			p["crop"] = _fx.crop
			p["field_condition"] = _fx.field_condition
		"apply_care":
			p["kind"] = _fx.care_kind
			p["expected_kind"] = _fx.care_kind
	return p

## 预测器只对这几个字段负责；ready_at/tutorial 是服务端裁决量（方案 §3 D4）。
func _assert_same(actual: Dictionary, expected: Dictionary, where: String) -> void:
	for key in ["state", "crop", "care_weather", "careful"]:
		assert_that(actual.get(key)).override_failure_message(
			"%s 的 %s 与服务端不一致" % [where, key]).is_equal(expected.get(key))

func test_matches_server_state_machine_step_by_step() -> void:
	var p := _predictor()
	for step in _fx.steps:
		var s: Dictionary = step
		if str(s.type) == "harvest_cells":
			# 收获前必须先吃到服务端回包：ready_at 只有服务端知道。
			p.commit(_fx.steps[3].cells, 5)
		var r := p.predict(str(s.type), _payload(s), int(s.now))
		assert_bool(r.ok).override_failure_message(
			"%s 预测失败: %s" % [s.name, r.error]).is_true()
		for id in s.cell_ids:
			_assert_same(r.cells[id], s.cells[id], "%s@%s" % [s.name, id])

func test_does_not_predict_ready_at() -> void:
	# 时长归服务端：预测到 growing 就停手，作物渲染在阶段 0 等真值。
	var p := _predictor()
	var care: Dictionary = _fx.steps[3]
	p.commit(_fx.steps[2].cells, 3)
	var r := p.predict("apply_care", _payload(care), int(care.now))
	assert_bool(r.ok).is_true()
	assert_str(str(r.cells["1,1"].state)).is_equal("growing")
	assert_bool(r.cells["1,1"].ready_at == null).is_true()
	assert_bool(_fx.steps[3].cells["1,1"].ready_at != null).is_true()

func test_harvest_unpredictable_until_server_supplies_ready_at() -> void:
	var p := _predictor()
	p.commit(_fx.steps[2].cells, 3)                       # 已播种，ready_at 还是 null
	p.predict("apply_care", _payload(_fx.steps[3]), int(_fx.steps[3].now))
	var blocked := p.predict("harvest_cells", {"cell_ids": _fx.steps[4].cell_ids}, int(_fx.steps[4].now))
	assert_str(blocked.error).is_equal("NOT_RIPE")
	p.commit(_fx.steps[3].cells, 4)                       # 服务端补上真 ready_at
	var okr := p.predict("harvest_cells", {"cell_ids": _fx.steps[4].cell_ids}, int(_fx.steps[4].now))
	assert_bool(okr.ok).is_true()
	assert_str(str(okr.cells["1,1"].state)).is_equal("tilled")

func test_wrong_order_is_refused_locally() -> void:
	var p := _predictor()
	assert_str(p.predict("till_cells", {"cell_ids": ["1,1"]}, 0).error).is_equal("WRONG_STATE")
	assert_str(p.predict("sow_cells", {"cell_ids": ["1,1"], "crop": "R"}, 0).error).is_equal("WRONG_STATE")

func test_reserved_bed_locked_until_expanded() -> void:
	var p := _predictor()
	var res: String = _fx.reserved[0]
	assert_str(p.predict("clear_cells", {"cell_ids": [res]}, 0).error).is_equal("CELL_LOCKED")
	p.beds_unlocked = 4
	assert_bool(p.predict("clear_cells", {"cell_ids": [res]}, 0).ok).is_true()

func test_non_cultivable_and_duplicate_are_refused() -> void:
	var p := _predictor()
	assert_str(p.predict("clear_cells", {"cell_ids": ["0,0"]}, 0).error).is_equal("CELL_NOT_CULTIVABLE")
	assert_str(p.predict("clear_cells", {"cell_ids": ["1,1", "1,1"]}, 0).error).is_equal("DUPLICATE_CELL")

func test_unpredicted_commands_are_passed_through_untouched() -> void:
	# 钱、XP、关系都不归它管。
	var p := _predictor()
	assert_str(p.predict("sell_at_stall", {}, 0).error).is_equal("NOT_PREDICTED")
	assert_bool(p.has_pending()).is_false()

func test_failed_prediction_leaves_no_trace() -> void:
	var p := _predictor()
	p.predict("clear_cells", {"cell_ids": ["1,1", "2,1"]}, 0)
	var before := p.view()
	assert_str(p.predict("clear_cells", {"cell_ids": ["3,1", "1,1"]}, 0).error).is_equal("WRONG_STATE")
	assert_that(p.view()).is_equal(before)          # 3,1 没有被部分写入
	assert_int(p.pending().size()).is_equal(1)

func test_commit_overwrites_rather_than_merges() -> void:
	# 漂移一律服务端为准：预测过的格子被服务端结果整体替换。
	var p := _predictor()
	p.predict("clear_cells", {"cell_ids": ["1,1"]}, 0)
	assert_str(str(p.view()["1,1"].state)).is_equal("cleared")
	p.commit(_fx.cells0, 9)
	assert_str(str(p.view()["1,1"].state)).is_equal("wild")
	assert_bool(p.has_pending()).is_false()
	assert_int(p.version).is_equal(9)

func test_rollback_drops_predictions() -> void:
	var p := _predictor()
	p.predict("clear_cells", {"cell_ids": ["1,1"]}, 0)
	p.rollback()
	assert_str(str(p.view()["1,1"].state)).is_equal("wild")
	assert_bool(p.has_pending()).is_false()

func test_ripe_is_derived_never_stored() -> void:
	var p := CellPredictor.new(_fx.steps[3].cells, _fx.cultivable, _fx.reserved)
	var ready := int(_fx.steps[3].cells["1,1"].ready_at)
	assert_array(p.ripe_cells(ready - 1)).is_empty()
	assert_int(p.ripe_cells(ready).size()).is_equal(3)
	for id in p.ripe_cells(ready):
		assert_bool(CellPredictor.STATES.has(str(p.view()[id].state))).is_true()
		assert_str(str(p.view()[id].state)).is_not_equal("ripe")

func test_from_blueprint_reads_cultivable_and_reserved() -> void:
	var bp := FarmBlueprint.load_file("res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json")
	var p := CellPredictor.from_blueprint(bp)
	assert_int(p._cultivable.size()).is_equal(12)
	assert_int(p._reserved.size()).is_equal(3)
