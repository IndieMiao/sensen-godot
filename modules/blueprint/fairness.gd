class_name BlueprintFairness
extends RefCounted
## 与 packages/blueprint-core/src/fairness.ts 同一套公式，Godot 侧再算一遍做双端守卫。
##
## 全部是绝对秒数（2026-09-04 决策③）。r1 用的是相对差值，而 tour_s 里掺了一个对所有蓝图
## 都相同的常数动作时间：常数取 18 秒时六蓝图算出 6.8% 过线，取 0（纯步行）时算出 29% 不
## 过线——同一批蓝图换个常数就在过线与不过线之间跳。基数只有 5.6 秒时，1.6 秒的差就是
## 29%，而 1.6 秒玩家根本感觉不到。far_bed 的相对差值更是结构性恒为 0（anchors.place()
## 选畦永远优先离出生点最近的三条），那条断言什么也证明不了，已删除。
##
## 另一处扩大：指标现在覆盖预留畦（扩地路线的 12 格）。r1 的指标只遍历初始三畦，第四畦
## 可以离得很远甚至不可达而不触发任何门槛，但 12 格操作时长是 PRD Gate 2 的明确验收项。

const WALK_SPEED := 2.5
const ACTION_S := 2.0
## 一轮完整九格农活的动作次数：清理、翻土、播种、照料各一遍（PRD §6.3）。
const ACTIONS_PER_ROUND := 36
const MAX_FAR_BED_S := 12.0
## 六蓝图之间纯步行巡回时间的最大允许差（秒）。
const MAX_WALK_TOUR_SPREAD_S := 5.0

static func metrics(bp: FarmBlueprint, grid: BlueprintGrid) -> Dictionary:
	var spawn := bp.anchor("spawn")
	var nine: Array = bp.beds()
	var twelve: Array = nine + [bp.reserved_bed()]
	var to_s := func(steps: float) -> float: return steps * bp.cell_m / WALK_SPEED
	var far := func(beds: Array) -> float:
		var d := 0.0
		for bed in beds:
			for c in bed.cells:
				d = maxf(d, grid.distance_cells(spawn, c))
		return d
	var tour := func(beds: Array) -> float:
		var steps := 0.0
		var cur := spawn
		var stops: Array[Vector2i] = []
		for bed in beds:
			stops.append(bed.cells[0])
		stops.append(spawn)
		for nxt in stops:
			steps += grid.distance_cells(cur, nxt)
			cur = nxt
		return steps
	var walk_tour_9: float = to_s.call(tour.call(nine))
	return {
		"far_bed_9_s": to_s.call(far.call(nine)),
		"far_bed_12_s": to_s.call(far.call(twelve)),
		"walk_tour_9_s": walk_tour_9,
		"walk_tour_12_s": to_s.call(tour.call(twelve)),
		"tour_s": walk_tour_9 + ACTIONS_PER_ROUND * ACTION_S,
	}

## 六蓝图之间的绝对差（秒）；调用方传同一指标在各蓝图上的取值。
static func spread_seconds(values: Array) -> float:
	if values.is_empty():
		return 0.0
	return float(values.max()) - float(values.min())
