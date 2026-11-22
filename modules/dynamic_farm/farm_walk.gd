extends RefCounted
## Sparse, local-scene walking. No session, commands, navigation server or terrain generation.
const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const BODY_RADIUS := 0.3   # P0Actor.HALF_WIDTH_M; one fixed body clearance, independent of outfit.
var data: Dictionary
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
# Conservative layout/connectivity mask; never a wall for the walker.
var reserved := {}
var _proxies_by_cell := {}
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

func _unreserved_cell(cell: Vector2i) -> bool:
	return data.by_cell.has(cell) and not reserved.has(cell)

func clear_position(p: Vector3) -> bool:
	var cell := cell_at(p)
	if not data.by_cell.has(cell):
		return false
	for proxy: Proxy in _proxies_by_cell.get(cell, []):
		if proxy.touches(p, BODY_RADIUS): return false
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

func add_prop(proxy: Proxy) -> void:
	if not proxy.solid: return
	# Cells are only a broad-phase index. Multiple shapes may share a bucket.
	var box := proxy.bounds().grow(BODY_RADIUS)
	var low := cell_at(Vector3(box.position.x, 0, box.end.z))
	var high := cell_at(Vector3(box.end.x, 0, box.position.z))
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var cell := Vector2i(x,y)
			if not _proxies_by_cell.has(cell): _proxies_by_cell[cell] = []
			_proxies_by_cell[cell].append(proxy)

func move(displacement: Vector3) -> Vector3:
	var step_count := maxi(1, ceili(displacement.length() / (cell_m * 0.18)))
	var step := displacement / step_count
	for _i in step_count:
		if clear_position(position + step):
			position += step
		else:
			# Advance to contact before trying to slide; a low frame rate
			# must not leave a full substep of empty ground before a tree.
			var lo := 0.0
			var hi := 1.0
			for _j in 8:
				var mid := (lo + hi) * 0.5
				if clear_position(position + step * mid): lo = mid
				else: hi = mid
			position += step * lo
			var remainder := step * (1.0 - lo)
			var x := Vector3(remainder.x, 0, 0)
			var z := Vector3(0, 0, remainder.z)
			var first := x if absf(step.x) >= absf(step.z) else z
			var second := z if absf(step.x) >= absf(step.z) else x
			if clear_position(position + first):
				position += first
			if clear_position(position + second):
				position += second
	return position

func try_box(box: AABB, solid: bool) -> Array[Vector2i]:
	var visual := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
	var area := visual.grow(BODY_RADIUS) if solid else visual
	var low := cell_at(Vector3(area.position.x, 0, area.end.y - 0.00001))
	var high := cell_at(Vector3(area.end.x - 0.00001, 0, area.position.y))
	var footprint: Array[Vector2i] = []
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var cell := Vector2i(x,y)
			if not data.by_cell.has(cell) or data.by_cell[cell].zone != "extension" or data.protected.has(cell) or reserved.has(cell):
				return []
			footprint.append(cell)
	if footprint.is_empty():
		return []
	if solid:
		for cell in footprint:
			reserved[cell] = true
		if not connected() or not clear_position(point(data.spawn)) or not clear_position(point(data.entry)):
			for cell in footprint:
				reserved.erase(cell)
			return []
	return footprint

func connected() -> bool:
	if not _unreserved_cell(data.spawn) or not _unreserved_cell(data.entry):
		return false
	var queue: Array[Vector2i] = [data.spawn]
	var seen := {data.spawn: true}
	var index := 0
	while index < queue.size():
		var at := queue[index]
		index += 1
		for offset in NEIGHBORS:
			var next: Vector2i = at + offset
			if _unreserved_cell(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size() == data.by_cell.size() - reserved.size()
