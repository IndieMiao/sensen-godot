class_name BlueprintGrid
extends RefCounted
## walkable mask → AStarGrid2D。4 邻接 + 曼哈顿，与 Node 校验器的 BFS 距离一致。

var bp: FarmBlueprint
var astar := AStarGrid2D.new()
var _obstacles: Array[AABB] = []

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
				var half := bp.cell_m * 0.5
				_obstacles.append(AABB(bp.cell_to_world(c) - Vector3(half, 0.5, half), Vector3(bp.cell_m, 1, bp.cell_m)))

## 运行时开关一格的通行性。木本作物与道具会挡路，而它们随时增删——
## 为此重建整张 AStar（64×64 扫一遍 + 重建障碍表）是纯浪费，这里只动一个点。
func set_solid(c: Vector2i, solid: bool) -> void:
	if not bp.in_bounds(c) or astar.is_point_solid(c) == solid: return
	astar.set_point_solid(c, solid)
	var half := bp.cell_m * 0.5
	var box := AABB(bp.cell_to_world(c) - Vector3(half, 0.5, half), Vector3(bp.cell_m, 1, bp.cell_m))
	if solid:
		_obstacles.append(box)
	else:
		for index in _obstacles.size():
			if _obstacles[index].position.is_equal_approx(box.position):
				_obstacles.remove_at(index)
				break

func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not bp.in_bounds(from) or not bp.in_bounds(to):
		return []
	if astar.is_point_solid(from) or astar.is_point_solid(to):
		return []
	return astar.get_id_path(from, to)

func segment_walkable(from: Vector3, to: Vector3, world_scale := 1.0) -> bool:
	if not bp.is_walkable(bp.world_to_cell(from, world_scale)) or not bp.is_walkable(bp.world_to_cell(to, world_scale)):
		return false
	var start := Vector3(from.x, 0, from.z) / world_scale
	var end := Vector3(to.x, 0, to.z) / world_scale
	for obstacle in _obstacles:
		if obstacle.intersects_segment(start, end) != null: return false
	return true

## Keep grid distances for blueprint validation; movement skips every visible waypoint.
func point_path(from: Vector3, to: Vector3, world_scale := 1.0) -> Array[Vector3]:
	var end := Vector3(to.x, 0, to.z)
	if segment_walkable(from, end, world_scale): return [end]
	var cells := path(bp.world_to_cell(from, world_scale), bp.world_to_cell(end, world_scale))
	if cells.is_empty(): return []
	var points: Array[Vector3] = []
	for c in cells: points.append(bp.cell_to_world(c, world_scale))
	points.append(end)
	var result: Array[Vector3] = []
	var cursor := from
	var index := 0
	while index < points.size():
		var next := points.size() - 1
		while next >= index and not segment_walkable(cursor, points[next], world_scale): next -= 1
		if next < index: return []
		cursor = points[next]
		result.append(cursor)
		index = next + 1
	return result

func distance_cells(from: Vector2i, to: Vector2i) -> float:
	var p := path(from, to)
	return INF if p.is_empty() else float(p.size() - 1)

func walk_time(from: Vector2i, to: Vector2i, speed := 2.5) -> float:
	var d := distance_cells(from, to)
	return INF if d == INF else d * bp.cell_m / speed
