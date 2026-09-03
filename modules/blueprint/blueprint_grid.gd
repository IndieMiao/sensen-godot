class_name BlueprintGrid
extends RefCounted
## walkable mask → AStarGrid2D。4 邻接 + 曼哈顿，与 Node 校验器的 BFS 距离一致。

var bp: FarmBlueprint
var astar := AStarGrid2D.new()

func _init(p_bp: FarmBlueprint) -> void:
	bp = p_bp
	astar.region = Rect2i(0, 0, bp.grid.x, bp.grid.y)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	for j in bp.grid.y:
		for i in bp.grid.x:
			var c := Vector2i(i, j)
			if not bp.is_walkable(c):
				astar.set_point_solid(c, true)

func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not bp.in_bounds(from) or not bp.in_bounds(to):
		return []
	if astar.is_point_solid(from) or astar.is_point_solid(to):
		return []
	return astar.get_id_path(from, to)

func distance_cells(from: Vector2i, to: Vector2i) -> float:
	var p := path(from, to)
	return INF if p.is_empty() else float(p.size() - 1)

func walk_time(from: Vector2i, to: Vector2i, speed := 2.5) -> float:
	var d := distance_cells(from, to)
	return INF if d == INF else d * bp.cell_m / speed
