class_name BlueprintFairness
extends RefCounted
## 与 tools/geo_blueprint/src/anchors.ts validate() 同一套公式，Godot 侧再算一遍做双端守卫。
##
## 口径局限（与 tools/geo_blueprint/src/cli.ts:33-37 的 NOTE 同一条，尚待评审，
## 不是本文件的新发现，只是把上游已经写在代码里的记录抄一份过来）：
## far_bed_s 是管线结构性保证——anchors.ts::place() 选畦永远优先离出生点最近的
## 三条，所以它在候选之间的 spread 恒为 0，测不出任何公平性差异，只验证"最远
## 畦格没有超过 MAX_FAR_BED_S 上限"。tour_s 里恒定的 9 * ACTION_S = 18s
## （INITIAL_BEDS * BED_CELLS * ACTION_S）会把真实的步行耗时差异稀释：六个真实
## 蓝图未稀释前的纯步行时间 spread ≈ 29%，稀释后只剩 ~6.8%（< MAX_SPREAD）。

const WALK_SPEED := 2.5
const ACTION_S := 2.0
const MAX_FAR_BED_S := 12.0
const MAX_SPREAD := 0.10

static func metrics(bp: FarmBlueprint, grid: BlueprintGrid) -> Dictionary:
	var spawn := bp.anchor("spawn")
	var far := 0.0
	var firsts: Array[Vector2i] = []
	for bed in bp.beds():
		for c in bed.cells:
			far = maxf(far, grid.distance_cells(spawn, c))
		firsts.append(bed.cells[0])
	var tour := 0.0
	var cur := spawn
	for nxt in firsts + [spawn]:
		tour += grid.distance_cells(cur, nxt)
		cur = nxt
	# n_cells 恒等于 Node 侧字面量 INITIAL_BEDS * BED_CELLS = 9：anchors.ts::place() 总是
	# 恰好产出 3 条 3 格的畦（beds.slice(0, config.INITIAL_BEDS)），不是巧合，是管线保证。
	var n_cells := 0
	for bed in bp.beds():
		n_cells += bed.cells.size()
	return {
		"far_bed_s": far * bp.cell_m / WALK_SPEED,
		"tour_s": tour * bp.cell_m / WALK_SPEED + n_cells * ACTION_S,
	}

static func spread(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var lo: float = values.min()
	var hi: float = values.max()
	return (hi - lo) / maxf(lo, 1e-9)
