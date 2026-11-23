extends RefCounted
## Sparse, local-scene walking. No session, commands, navigation server or terrain generation.
const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const BODY_RADIUS := 0.3   # P0Actor.HALF_WIDTH_M; one fixed body clearance, independent of outfit.
const CONTACT_PASSES := 3  # direct leg + up to two slides (e.g. into a corner)
const SLIDE_CLEARANCE := 0.00001  # keeps a tangent leg from grazing the same face
var data: Dictionary
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
# Conservative layout/connectivity mask; never a wall for the walker.
var reserved := {}
var _connected_size := -1  # reserved.size() when every clear cell was last proven reachable
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

func clear_cell(cell: Vector2i) -> bool:
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
		var remaining := step
		for _contact in CONTACT_PASSES:
			if clear_position(position + remaining):
				position += remaining
				break
			# Advance to contact before trying to slide; a low frame rate
			# must not leave a full substep of empty ground before a tree.
			var lo := 0.0
			var hi := 1.0
			for _j in 10:
				var mid := (lo + hi) * 0.5
				if clear_position(position + remaining * mid): lo = mid
				else: hi = mid
			var blocked := position + remaining * hi
			position += remaining * lo
			var rest := remaining * (1.0 - lo)
			# Slide along the face actually touched: drop only the inward part.
			# The next pass re-checks bounds and neighbouring props.
			var normal := _blocking_normal(blocked, position)
			var inward := rest.dot(normal)
			if inward >= 0.0: break
			remaining = rest - normal * (inward - SLIDE_CLEARANCE)
	return position

## Outward XZ normal at `from` of the nearest feature that blocks `p`.
func _blocking_normal(p: Vector3, from: Vector3) -> Vector3:
	var best := INF
	var normal := Vector3.ZERO
	for proxy: Proxy in _proxies_by_cell.get(cell_at(p), []):
		var gap := proxy.gap(from)
		if proxy.touches(p, BODY_RADIUS) and gap < best:
			best = gap
			normal = proxy.away(from)
	var at := Vector2(p.x,-p.z) / cell_m + center_grid
	var origin := Vector2(from.x,-from.z) / cell_m + center_grid
	var radius := BODY_RADIUS / cell_m
	for y in range(floori(at.y-radius),floori(at.y+radius)+1):
		for x in range(floori(at.x-radius),floori(at.x+radius)+1):
			if data.by_cell.has(Vector2i(x,y)): continue
			if at.distance_to(Vector2(clampf(at.x,x,x+1),clampf(at.y,y,y+1))) >= radius: continue
			var closest := Vector2(clampf(origin.x,x,x+1),clampf(origin.y,y,y+1))
			var d := origin.distance_to(closest) * cell_m  # same measure as Proxy.gap()
			if d < best and origin != closest:
				best = d
				var grid := (origin - closest).normalized()
				normal = Vector3(grid.x, 0, -grid.y)
	return normal

## `shared`: already-reserved cells this prop may overlap (members of one grove or pile).
## `max_new`: reject a solid prop that would reserve more than this many new cells (-1: no limit).
func try_box(box: AABB, solid: bool, shared := {}, max_new := -1) -> Array[Vector2i]:
	var visual := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
	var area := visual.grow(BODY_RADIUS) if solid else visual
	var low := cell_at(Vector3(area.position.x, 0, area.end.y - 0.00001))
	var high := cell_at(Vector3(area.end.x - 0.00001, 0, area.position.y))
	var footprint: Array[Vector2i] = []
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var cell := Vector2i(x,y)
			if not data.by_cell.has(cell) or data.by_cell[cell].zone != "extension" or data.protected.has(cell) or (reserved.has(cell) and not shared.has(cell)):
				return []
			footprint.append(cell)
	if footprint.is_empty():
		return []
	if solid:
		var added: Array[Vector2i] = []
		for cell in footprint:
			if not reserved.has(cell): added.append(cell)
		if max_new >= 0 and added.size() > max_new:
			return []
		var was_connected := _connected_size == reserved.size()
		for cell in added:
			reserved[cell] = true
		var still := _still_connected(added) if was_connected else connected()
		if not still or not clear_position(point(data.spawn)) or not clear_position(point(data.entry)):
			for cell in added:
				reserved.erase(cell)
			return []
		_connected_size = reserved.size()
	return footprint

## Same answer as connected() when every clear cell was reachable before `added` were
## reserved: the rest stays connected iff the clear neighbours of `added` reach one another.
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
	return seen.size() == data.by_cell.size() - reserved.size()
