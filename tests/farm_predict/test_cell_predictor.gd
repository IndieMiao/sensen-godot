extends GdUnitTestSuite
## 预测器 vs 服务端归约器：同一条命令序列，逐格比对每一次跃迁。
##
## fixture 由 `server/test/domain/export_predict_fixture.test.ts` 用**真实服务端归约器**
## 跑出来，不是手写的期望值——这是跨语言状态机一致性的唯一硬证据。两边只要有一处对不上，
## 玩家就会看到「本地变了、服务端拒绝、又弹回去」的闪烁。

const FIX := "res://tests/fixtures/farm_predict_sequence.json"

var _fx: Dictionary

func before_test() -> void:
	_fx = JSON.parse_string(FileAccess.get_file_as_string(FIX))

func _predictor() -> CellPredictor:
	return CellPredictor.new(_fx.cells0, _fx.cultivable)

func _payload(step: Dictionary) -> Dictionary:
	var p := {"cell_ids": step.cell_ids}
	if str(step.type) == "sow_cells":
		p["crop"] = str(step.get("crop", "R"))
	return p

## 预测器只对状态与作物负责；ready_at 是服务端裁决量。
func _assert_same(actual: Dictionary, expected: Dictionary, where: String) -> void:
	for key in ["state", "crop"]:
		assert_that(actual.get(key)).override_failure_message(
			"%s 的 %s 与服务端不一致" % [where, key]).is_equal(expected.get(key))

func test_matches_server_state_machine_step_by_step() -> void:
	var p := _predictor()
	for step in _fx.steps:
		var s: Dictionary = step
		if str(s.type) == "harvest_cells":
			# 收获前必须先吃到服务端回包：ready_at 只有服务端知道。
			p.commit(_fx.steps[2].cells, 3)
		var r := p.predict(str(s.type), _payload(s), int(s.now))
		assert_bool(r.ok).override_failure_message(
			"%s 预测失败: %s" % [s.name, r.error]).is_true()
		for id in s.cell_ids:
			_assert_same(r.cells[id], s.cells[id], "%s@%s" % [s.name, id])

func test_does_not_predict_ready_at() -> void:
	# 时长归服务端：预测到 growing 就停手，作物渲染停在阶段 0 等真值。
	var p := _predictor()
	p.commit(_fx.steps[1].cells, 2)
	var water: Dictionary = _fx.steps[2]
	var r := p.predict("water_cells", _payload(water), int(water.now))
	assert_bool(r.ok).is_true()
	for id in water.cell_ids:
		assert_str(str(r.cells[id].state)).is_equal("growing")
		assert_object(r.cells[id].ready_at).is_null()

func test_untracked_ground_is_wild_and_can_be_tilled() -> void:
	# 稀疏存储在客户端的全部体现：cells 里没有这个 key 就是荒地。
	var p := _predictor()
	var id: String = _fx.cultivable[0]
	assert_bool(p.view().has(id)).is_false()
	var r := p.predict("till_cells", {"cell_ids": [id]}, 0)
	assert_bool(r.ok).is_true()
	assert_str(str(r.cells[id].state)).is_equal("tilled")

func test_tilling_the_same_ground_twice_is_refused_locally() -> void:
	var p := _predictor()
	var id: String = _fx.cultivable[0]
	assert_bool(p.predict("till_cells", {"cell_ids": [id]}, 0).ok).is_true()
	var again := p.predict("till_cells", {"cell_ids": [id]}, 0)
	assert_bool(again.ok).is_false()
	assert_str(str(again.error)).is_equal("WRONG_STATE")

func test_clearing_empty_ground_removes_it_from_state() -> void:
	var p := _predictor()
	var id: String = _fx.cultivable[0]
	p.predict("till_cells", {"cell_ids": [id]}, 0)
	var r := p.predict("clear_plot", {"cell_ids": [id]}, 0)
	assert_bool(r.ok).is_true()
	# 铲平后格子从视图里消失，而不是留一个 wild 槽。
	assert_bool(p.view().has(id)).is_false()

func test_refuses_ground_the_layout_forbids() -> void:
	var p := _predictor()
	var r := p.predict("till_cells", {"cell_ids": ["63,63"]}, 0)
	assert_bool(r.ok).is_false()
	assert_str(str(r.error)).is_equal("CELL_NOT_CULTIVABLE")

func test_commit_replaces_rather_than_merges() -> void:
	# 漂移一律以服务端为准：commit 是整体覆盖，不做字段级合并。
	var p := _predictor()
	var id: String = _fx.cultivable[0]
	p.predict("till_cells", {"cell_ids": [id]}, 0)
	p.commit({}, 7)
	assert_bool(p.view().has(id)).is_false()
	assert_int(p.version).is_equal(7)

func test_rollback_drops_every_prediction() -> void:
	var p := _predictor()
	var id: String = _fx.cultivable[0]
	p.predict("till_cells", {"cell_ids": [id]}, 0)
	p.rollback()
	assert_bool(p.view().has(id)).is_false()

func test_ripe_is_derived_never_stored() -> void:
	var p := _predictor()
	var slot := {"state": "growing", "crop": "R", "ready_at": 100}
	assert_bool(p.is_ripe(slot, 99)).is_false()
	assert_bool(p.is_ripe(slot, 100)).is_true()
	# ready_at 未知一律不熟：客户端从不猜时长。
	assert_bool(p.is_ripe({"state": "growing", "ready_at": null}, 999)).is_false()
