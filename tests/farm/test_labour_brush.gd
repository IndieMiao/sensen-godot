extends GdUnitTestSuite
## 刷子：轨迹去重、可耕作过滤、行级扩展。

func _bp() -> FarmBlueprint:
	return FarmPlot.blueprint_for()

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

## 输入事件是离散的：手指划快一点，相邻两个采样点就能差出好几格。只记录命中点
## 会在刷过的带子上留下窟窿——真机上 0.5m 格实测一划三格里漏一格。
func test_bridges_cells_between_far_apart_samples() -> void:
	var pts := PackedVector2Array([Vector2(5, 5), Vector2(45, 5)])
	assert_array(LabourBrush.trace(pts, _proj())).is_equal(
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)])

## 手指抬起再落下、或投影掠过地平线，会产生一次大跳变。那不是一笔划过去的，
## 不该凭空补出一长条格。
func test_does_not_bridge_across_an_implausible_jump() -> void:
	var far := 10.0 * float(LabourBrush.MAX_BRIDGE + 5)
	var pts := PackedVector2Array([Vector2(5, 5), Vector2(5 + far, 5)])
	assert_array(LabourBrush.trace(pts, _proj())).is_equal(
		[Vector2i(0, 0), Vector2i(LabourBrush.MAX_BRIDGE + 5, 0)])

func test_filter_keeps_only_cultivable_cells_in_order() -> void:
	var bp := _bp()
	var a := Vector2i(10, 10)
	var b := Vector2i(11, 10)
	var paved: Vector2i = bp.anchor("house")    # 建筑：不可开垦
	var raw := [paved, b, a, a]                 # a 重复一次
	assert_array(LabourBrush.filter_actionable(raw, bp)).is_equal([b, a])


func test_row_tool_thickens_along_the_stroke() -> void:
	# 田畦退役后，行工具是「沿四邻加粗一圈」：少划几下，不改产量也不缩短时长。
	var bp := _bp()
	var got: Array = LabourBrush.thicken([Vector2i(10, 10)], bp)
	assert_int(got.size()).is_equal(5)           # 自己 + 四邻
	assert_bool(got.has(Vector2i(10, 10))).is_true()
	assert_bool(got.has(Vector2i(11, 10))).is_true()

func test_row_tool_merges_overlapping_strokes_without_duplicates() -> void:
	var bp := _bp()
	var got: Array = LabourBrush.thicken([Vector2i(10, 10), Vector2i(11, 10)], bp)
	# 两个十字有两格重叠，去重后是 8 格而不是 10 格。
	assert_int(got.size()).is_equal(8)

func test_row_tool_never_thickens_onto_unfarmable_ground() -> void:
	# 加粗只在可开垦的地上扩散：碰到路或建筑就停。
	var bp := _bp()
	var edge := Vector2i(30, 20)                 # 主路东侧第一格土
	var got: Array = LabourBrush.thicken([edge], bp)
	for cell in got:
		assert_bool(bp.mask_has("cultivable", cell)).is_true()
