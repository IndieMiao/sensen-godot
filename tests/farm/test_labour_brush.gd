extends GdUnitTestSuite
## 刷子：轨迹去重、可耕作过滤、行级扩展。

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func _bp() -> FarmBlueprint:
	return FarmBlueprint.load_file(FIX)

## 假投影器：屏幕点每 10 px 一格，负坐标表示没打到地面。
func _proj() -> Callable:
	return func(p: Vector2):
		if p.x < 0.0 or p.y < 0.0:
			return null
		return Vector2i(int(p.x / 10.0), int(p.y / 10.0))

func test_collapses_consecutive_repeats_only() -> void:
	# 来回描同一格只算一次；但 A→B→A 的回头路，第二次经过 A 是玩家的真实意图。
	var pts := PackedVector2Array([
		Vector2(5, 5), Vector2(7, 7),            # 都是 0,0
		Vector2(15, 5), Vector2(17, 6),          # 都是 1,0
		Vector2(5, 5),                           # 回到 0,0
	])
	assert_array(LabourBrush.trace(pts, _proj())).is_equal(
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 0)])

func test_skips_points_that_miss_the_ground() -> void:
	var pts := PackedVector2Array([Vector2(-1, -1), Vector2(5, 5), Vector2(-3, 2)])
	assert_array(LabourBrush.trace(pts, _proj())).is_equal([Vector2i(0, 0)])

func test_empty_trace_is_empty() -> void:
	assert_array(LabourBrush.trace(PackedVector2Array(), _proj())).is_empty()

func test_filter_keeps_only_unlocked_cultivable_cells_in_order() -> void:
	var bp := _bp()
	var beds: Array = bp.beds()
	var a: Vector2i = beds[0].cells[1]
	var b: Vector2i = beds[1].cells[0]
	var res: Vector2i = bp.reserved_bed().cells[0]
	var raw := [Vector2i(0, 0), b, a, res, a]          # 0,0 非耕地；a 重复
	assert_array(LabourBrush.filter_actionable(raw, bp, 3)).is_equal([b, a])
	assert_array(LabourBrush.filter_actionable(raw, bp, 4)).is_equal([b, a, res])

func test_row_tool_expands_to_whole_bed_but_keeps_cells_separate() -> void:
	# 扩到整畦是少划两下，不是效率道具：仍然是 3 格，逐格播放（PRD §6.3 L408）。
	var bp := _bp()
	var bed: Array = bp.beds()[0].cells
	var got := LabourBrush.expand_rows([bed[1]], bp)
	assert_int(got.size()).is_equal(3)
	for c in bed:
		assert_bool(got.has(c)).is_true()

func test_row_tool_merges_overlapping_beds_without_duplicates() -> void:
	var bp := _bp()
	var b0: Array = bp.beds()[0].cells
	var b1: Array = bp.beds()[1].cells
	var got := LabourBrush.expand_rows([b0[0], b0[2], b1[1]], bp)
	assert_int(got.size()).is_equal(6)

func test_row_tool_leaves_non_bed_cells_alone() -> void:
	var bp := _bp()
	assert_array(LabourBrush.expand_rows([Vector2i(0, 0)], bp)).is_equal([Vector2i(0, 0)])
