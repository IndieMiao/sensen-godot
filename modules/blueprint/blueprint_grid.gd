class_name BlueprintGrid
extends RefCounted
## walkable mask → AStarGrid2D。4 邻接 + 曼哈顿，与 Node 校验器的 BFS 距离一致。

var bp: FarmBlueprint
var astar := AStarGrid2D.new()
var _obstacles: Array[AABB] = []

func _init(p_bp: FarmBlueprint) -> void:
	bp = p_bp
	astar.region = Rect2i(bp.grid_origin, bp.grid)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	for j in bp.grid.y:
		for i in bp.grid.x:
			var c := bp.grid_origin + Vector2i(i, j)
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

## Whether a point goes from `from` to `to` through walkable cells only (trace_hit).
func trace_walkable(from: Vector3, to: Vector3, world_scale := 1.0) -> bool:
	return trace_hit(from, to, world_scale) > 1.0

## The cell the last trace_hit stopped at, and the way out of it through the face it went in by (ZERO when it began
## in a blocked cell or met none).
var hit_cell := Vector2i.ZERO
var hit_face := Vector2i.ZERO

## How far along `from` → `to` (0–1) a point first enters a cell it cannot walk — the cells the segment crosses,
## traced (one through a corner exactly takes a cell beside it) — or 2 when it never does. The stick's slide asks it a
## few dozen times a step against a wall, where segment_walkable's look at every obstacle would cost too much; the step
## it picks still goes through segment_walkable.
func trace_hit(from: Vector3, to: Vector3, world_scale := 1.0) -> float:
	var size := bp.cell_m * world_scale
	var a := Vector2(from.x, -from.z) / size
	var b := Vector2(to.x, -to.z) / size
	var c := Vector2i(floori(a.x), floori(a.y))
	var end := Vector2i(floori(b.x), floori(b.y))
	hit_cell = c
	hit_face = Vector2i.ZERO
	if _blocked(c): return 0.0
	var d := b - a
	var step := Vector2i(1 if d.x > 0.0 else -1, 1 if d.y > 0.0 else -1)
	var t_max := Vector2(INF, INF)
	var t_delta := Vector2(INF, INF)
	if d.x != 0.0:
		t_delta.x = absf(1.0 / d.x)
		t_max.x = (float(c.x + (1 if d.x > 0.0 else 0)) - a.x) / d.x
	if d.y != 0.0:
		t_delta.y = absf(1.0 / d.y)
		t_max.y = (float(c.y + (1 if d.y > 0.0 else 0)) - a.y) / d.y
	var left := absi(end.x - c.x) + absi(end.y - c.y)
	while c != end and left > 0:
		left -= 1
		var t := 0.0
		var face := Vector2i.ZERO
		if t_max.x < t_max.y:
			t = t_max.x
			c.x += step.x
			t_max.x += t_delta.x
			face = Vector2i(-step.x, 0)
		else:
			t = t_max.y
			c.y += step.y
			t_max.y += t_delta.y
			face = Vector2i(0, -step.y)
		if _blocked(c):
			hit_cell = c
			hit_face = face
			return t
	return 2.0

## The way out of the wall the last trace_hit met, about `at` (world, just short of it), flat and unit: the face it met
## when that runs straight two cells or more (a wall, a pond's edge — a corner's other wall near by does not bend it);
## else, a lone step (a 45° row's staircase, a post), a line fitted through the faces about it (wall_normal), unless
## that fit lies across the face met. ZERO when none.
func hit_normal(at: Vector3, radius_cells: float, world_scale := 1.0) -> Vector3:
	var face := hit_face
	if face != Vector2i.ZERO:
		var along := Vector2i(face.y, face.x)
		var run := 1
		for side in [1, -1]:
			var c: Vector2i = hit_cell + along * side
			if _blocked(c) and not _blocked(c + face): run += 1
		if run >= 2: return Vector3(face.x, 0.0, -face.y)
	var n := wall_normal(at, radius_cells, world_scale)
	if face == Vector2i.ZERO: return n
	# A fit across the face met (a door's two jambs, a gap) is not that wall: the face it is.
	var own := Vector3(face.x, 0.0, -face.y)
	return n if n.dot(own) > 0.2 else own

## The way out of the walls about `at` (world, flat, unit): a line fitted through the middles of the open faces within
## `radius_cells` that `at` is in front of, and its normal on their side — a straight wall's, a 45° staircase's slant
## (its faces' middles lie on the one line, wherever along it `at` is), a corner's bisector. ZERO with none near.
func wall_normal(at: Vector3, radius_cells: float, world_scale := 1.0) -> Vector3:
	var size := bp.cell_m * world_scale
	var a := Vector2(at.x, -at.z) / size
	var c := Vector2i(floori(a.x), floori(a.y))
	var r := ceili(radius_cells) + 1
	var mids: Array[Vector2] = []
	var outs := Vector2.ZERO
	for j in range(-r, r + 1):
		for i in range(-r, r + 1):
			var cell := c + Vector2i(i, j)
			if not _blocked(cell): continue
			for f in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _blocked(cell + f): continue
				var mid := Vector2(cell) + Vector2(maxi(f.x, 0), maxi(f.y, 0)) + Vector2(absi(f.y), absi(f.x)) * 0.5
				if (a - mid).dot(Vector2(f)) <= 0.0 or a.distance_to(mid) >= radius_cells: continue   # behind it, or far
				mids.append(mid)
				outs += Vector2(f)
	if mids.is_empty(): return Vector3.ZERO
	var n := outs.normalized()
	if mids.size() >= 2:
		var mean := Vector2.ZERO
		for m in mids: mean += m
		mean /= mids.size()
		var xx := 0.0
		var xy := 0.0
		var yy := 0.0
		for m in mids:
			var d := m - mean
			xx += d.x * d.x
			xy += d.x * d.y
			yy += d.y * d.y
		var along := 0.5 * atan2(2.0 * xy, xx - yy)
		n = Vector2(-sin(along), cos(along))
		if outs.dot(n) < 0.0: n = -n
	if n == Vector2.ZERO: return Vector3.ZERO
	return Vector3(n.x, 0.0, -n.y)

func _blocked(c: Vector2i) -> bool:
	return not bp.is_walkable(c) or astar.is_point_solid(c)

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
