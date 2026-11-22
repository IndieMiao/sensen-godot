extends RefCounted
## Sparse, local-scene walking. No session, commands, navigation server or terrain generation.
const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const BODY_RADIUS := 0.3   # P0Actor.HALF_WIDTH_M; one fixed body clearance, independent of outfit.
var data: Dictionary
var blocked := {}
var _connected_size := -1  # blocked.size() when every clear cell was last proven reachable
var cell_m := 0.8
var center_grid := Vector2.ZERO
var position := Vector3.ZERO

func _init(decoded: Dictionary) -> void:
	data = decoded
	cell_m = decoded.cell_m
	center_grid = Vector2(decoded.grid_size) * 0.5
	position = point(decoded.spawn)

func point(cell: Vector2i) -> Vector3:
	# Subtract the same origin+centre translation from every layer, before float conversion.
	return Vector3((cell.x + 0.5 - center_grid.x) * cell_m, 0, -(cell.y + 0.5 - center_grid.y) * cell_m)

func cell_at(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / cell_m + center_grid.x), floori(-p.z / cell_m + center_grid.y))

func clear_cell(cell: Vector2i) -> bool:
	return data.by_cell.has(cell) and not blocked.has(cell)

func clear_position(p: Vector3) -> bool:
	if not clear_cell(cell_at(p)):
		return false
	var at := Vector2(p.x,-p.z) / cell_m + center_grid
	var radius := BODY_RADIUS / cell_m
	var low := Vector2i(floori(at.x-radius),floori(at.y-radius))
	var high := Vector2i(floori(at.x+radius),floori(at.y+radius))
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			if data.by_cell.has(Vector2i(x,y)): continue
			var closest := Vector2(clampf(at.x,x,x+1),clampf(at.y,y,y+1))
			if at.distance_squared_to(closest) < radius*radius-0.00000001:
				return false
	return true

func move(displacement: Vector3) -> Vector3:
	var step_count := maxi(1, ceili(displacement.length() / (cell_m * 0.18)))
	var step := displacement / step_count
	for _i in step_count:
		if clear_position(position + step):
			position += step
		else:
			var x := Vector3(step.x, 0, 0)
			var z := Vector3(0, 0, step.z)
			var first := x if absf(step.x) >= absf(step.z) else z
			var second := z if absf(step.x) >= absf(step.z) else x
			if clear_position(position + first):
				position += first
			if clear_position(position + second):
				position += second
	return position

## `shared`: already-blocked cells this prop may overlap (members of one grove or pile).
## `max_new`: reject a solid prop that would block more than this many new cells (-1: no limit).
func try_box(box: AABB, solid: bool, shared := {}, max_new := -1) -> Array[Vector2i]:
	var visual := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
	var area := visual.grow(BODY_RADIUS) if solid else visual
	var low := cell_at(Vector3(area.position.x, 0, area.end.y - 0.00001))
	var high := cell_at(Vector3(area.end.x - 0.00001, 0, area.position.y))
	var footprint: Array[Vector2i] = []
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var cell := Vector2i(x,y)
			if not data.by_cell.has(cell) or data.by_cell[cell].zone != "extension" or data.protected.has(cell) or (blocked.has(cell) and not shared.has(cell)):
				return []
			footprint.append(cell)
	if footprint.is_empty():
		return []
	if solid:
		var added: Array[Vector2i] = []
		for cell in footprint:
			if not blocked.has(cell): added.append(cell)
		if max_new >= 0 and added.size() > max_new:
			return []
		var was_connected := _connected_size == blocked.size()
		for cell in added:
			blocked[cell] = true
		var still := _still_connected(added) if was_connected else connected()
		if not still or not clear_position(point(data.spawn)) or not clear_position(point(data.entry)):
			for cell in added:
				blocked.erase(cell)
			return []
		_connected_size = blocked.size()
	return footprint

## Same answer as connected() when every clear cell was reachable before `added` were
## blocked: the rest stays connected iff the clear neighbours of `added` reach one another.
func _still_connected(added: Array[Vector2i]) -> bool:
	if not clear_cell(data.spawn) or not clear_cell(data.entry):
		return false
	var targets := {}
	for cell in added:
		for offset in NEIGHBORS:
			if clear_cell(cell + offset): targets[cell + offset] = true
	if targets.size() <= 1:
		return true
	var start: Vector2i = targets.keys()[0]
	var queue: Array[Vector2i] = [start]
	var seen := {start: true}
	var found := 1
	var index := 0
	while index < queue.size():
		var at := queue[index]
		index += 1
		for offset in NEIGHBORS:
			var next: Vector2i = at + offset
			if clear_cell(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
				if targets.has(next):
					found += 1
					if found == targets.size(): return true
	return false

func connected() -> bool:
	if not clear_cell(data.spawn) or not clear_cell(data.entry):
		return false
	var queue: Array[Vector2i] = [data.spawn]
	var seen := {data.spawn: true}
	var index := 0
	while index < queue.size():
		var at := queue[index]
		index += 1
		for offset in NEIGHBORS:
			var next: Vector2i = at + offset
			if clear_cell(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size() == data.by_cell.size() - blocked.size()
