class_name BlueprintFairness
extends RefCounted
## 与 tools/geo_blueprint/src/anchors.ts validate() 同一套公式，Godot 侧再算一遍做双端守卫。

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
