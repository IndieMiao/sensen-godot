extends RefCounted
## Where the player walks at a P0 pond (the user 11-07, q(297): the map no bigger, the walk wider): the meadow half a
## metre in from its sides and near edge and to z −16 at the far one — WALK, x −2.5 to 14.5, z −16 to 1.5: further up the
## camera, held to the meadow, leaves them under the HUD (不知火舞 on q(297), shot) — less the water and WATER_PAD_M round it (the
## templates' own margin), and a trunk's TREE_R_M round each of the bank's trees. The templates' 12 × 16 m grids stopped
## 0.75 m in from x 0–12, z −16–0: the meadow below and beside the pond could not be walked, and Fern Pond's clay (R2,
## (12, −7.6)) left a gap too narrow to pass. The server's pond rooms hold positions to the meadow already (POND_BOUNDS).
## The grid keeps the template's cell; it starts below zero (FarmBlueprint.grid_origin), so world and grid stay one.

const WALK := Rect2(-2.5, -16.0, 17.0, 17.5)
const WATER_PAD_M := 0.3
const TREE_R_M := 0.4

## The pond's blueprint (SystemPonds.blueprint's: ids, revision, cell, spawn) with the walk widened to WALK.
static func blueprint(entry: Dictionary) -> FarmBlueprint:
	var bp := SystemPonds.blueprint(entry)
	var spec := SystemPonds.site(entry)
	var id := str(entry.id)
	var cell := bp.cell_m
	var lo := Vector2i(floori(WALK.position.x / cell), floori(-WALK.end.y / cell))
	var hi := Vector2i(floori((WALK.end.x - 0.001) / cell), floori(-(WALK.position.y + 0.001) / cell))
	var rows := PackedStringArray()
	for j in range(lo.y, hi.y + 1):
		var row := ""
		for i in range(lo.x, hi.x + 1):
			var w := bp.cell_to_world(Vector2i(i, j))
			row += "1" if WALK.has_point(Vector2(w.x, w.z)) and not FishingModel.contains(id, w, WATER_PAD_M, spec) else "0"
		rows.append(row)
	bp.grid_origin = lo
	bp.grid = hi - lo + Vector2i.ONE
	bp.masks = {"walkable": rows}
	return bp

## The bank's trees as they stand now (PondScenery.tree_points): their trunks block; the cells the last ones blocked
## (`was`, from the previous call) walk again. Returns the cells now blocked, for the next call.
static func set_trees(bp: FarmBlueprint, grid: BlueprintGrid, entry: Dictionary, trees: Array, was: Array = []) -> Array:
	for c in was:
		_walk_cell(bp, c, true)
		if grid: grid.set_solid(c, false)
	var now: Array = []
	var r := ceili(TREE_R_M / bp.cell_m)
	for t in trees:
		var at := bp.world_to_cell(t)
		for j in range(-r, r + 1):
			for i in range(-r, r + 1):
				var c := at + Vector2i(i, j)
				var w := bp.cell_to_world(c)
				if not bp.is_walkable(c) or Vector2(w.x - t.x, w.z - t.z).length() > TREE_R_M: continue
				_walk_cell(bp, c, false)
				if grid: grid.set_solid(c, true)
				now.append(c)
	return now

static func _walk_cell(bp: FarmBlueprint, c: Vector2i, walk: bool) -> void:
	if not bp.in_bounds(c): return
	var rows: PackedStringArray = bp.masks.walkable
	var y := c.y - bp.grid_origin.y
	var x := c.x - bp.grid_origin.x
	var row := rows[y]
	rows[y] = row.substr(0, x) + ("1" if walk else "0") + row.substr(x + 1)
	bp.masks.walkable = rows
