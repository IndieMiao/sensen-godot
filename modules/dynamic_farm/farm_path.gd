extends RefCounted
## Grid routes on the dynamic farm walker (C-73): the player walks up to a cell before working it.
## A cell is open when the walker's body fits at its centre (Walk.clear_position: the parcel's
## outline and the same fitted prop profiles the joystick collides with), and a step between two
## neighbouring centres (diagonals included) is taken only if the body fits all along it, so a
## route never asks the walker to pass where it would collide. Cleared props leave the walk and
## therefore every later route.
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
## Spacing of the body checks along a step or a straightened leg, in metres.
const SAMPLE_M := 0.1
## Searches give up after this many expanded cells (a parcel has a few thousand).
const MAX_EXPANDED := 20000
## Straightening tries legs over at most this many waypoints.
const SMOOTH_LOOKAHEAD := 12
const DIAGONAL := 1.4142135623730951

var walk: RefCounted
var _open := {}

func _init(p_walk: RefCounted) -> void:
	walk = p_walk

## The walker's body fits at the cell's centre. Valid until the walk changes (see `forget`).
func open(cell: Vector2i) -> bool:
	if not _open.has(cell): _open[cell] = walk.data.by_cell.has(cell) and walk.clear_position(walk.point(cell))
	return _open[cell]

## Drops cached cells after props were added to or removed from the walk.
func forget() -> void:
	_open.clear()

## The body fits all along the straight leg from `a` to `b` (both ends included but `a`).
func segment_clear(a: Vector3, b: Vector3) -> bool:
	var n := maxi(1, ceili(a.distance_to(b) / SAMPLE_M))
	for i in range(1, n + 1):
		if not walk.clear_position(a.lerp(b, float(i) / n)): return false
	return true

## Open cells next to `targets` (8 neighbours) where the player can stand to work them, with a
## small extra cost for the diagonal ones so a side is preferred: {cell: extra_m}.
func stand_cells(targets: Array) -> Dictionary:
	var inside := {}
	for cell: Vector2i in targets: inside[cell] = true
	var stands := {}
	for cell: Vector2i in targets:
		for d: Vector2i in DIRS:
			var at: Vector2i = cell + d
			if inside.has(at) or not open(at): continue
			var extra: float = 0.0 if d.x == 0 or d.y == 0 else walk.cell_m * 0.5
			# A cell beside one target but diagonal to another keeps the side cost.
			stands[at] = minf(float(stands.get(at, INF)), extra)
	return stands

## Waypoints from `from` to the cheapest of `goals` ({cell: extra cost in metres}), straightened
## where the body fits; the last one is the goal cell's centre. [] when no goal is reachable.
func route(from: Vector3, goals: Dictionary) -> Array[Vector3]:
	var none: Array[Vector3] = []
	if goals.is_empty(): return none
	var heap := _Heap.new()
	var g := {}
	var came := {}
	var start: Vector2i = walk.cell_at(from)
	# The player rarely stands on a centre: start from the open cells around them it can step to.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell: Vector2i = start + Vector2i(dx, dy)
			if not open(cell) or not segment_clear(from, walk.point(cell)): continue
			var cost: float = from.distance_to(walk.point(cell))
			if cost < float(g.get(cell, INF)):
				g[cell] = cost
				heap.push(cost + _estimate(cell, goals), cell)
	var best := INF
	var best_cell = null
	var expanded := 0
	while not heap.is_empty() and expanded < MAX_EXPANDED:
		var top := heap.pop()
		if float(top[0]) >= best: break
		var at: Vector2i = top[1]
		var at_g: float = g[at]
		if float(top[0]) > at_g + _estimate(at, goals) + 0.000001: continue  # stale entry
		expanded += 1
		if goals.has(at) and at_g + float(goals[at]) < best:
			best = at_g + float(goals[at])
			best_cell = at
		for d: Vector2i in DIRS:
			var next: Vector2i = at + d
			if not open(next): continue
			var step: float = walk.cell_m * (1.0 if d.x == 0 or d.y == 0 else DIAGONAL)
			var next_g: float = at_g + step
			if next_g >= float(g.get(next, INF)) or not _step_clear(at, next): continue
			g[next] = next_g
			came[next] = at
			heap.push(next_g + _estimate(next, goals), next)
	if best_cell == null: return none
	var cells: Array[Vector2i] = [best_cell]
	while came.has(cells.back()): cells.append(came[cells.back()])
	cells.reverse()
	var points: Array[Vector3] = []
	for cell in cells: points.append(walk.point(cell))
	return _straighten(from, points)

## The cheapest admissible guess: straight distance to the nearest goal, plus its extra.
func _estimate(cell: Vector2i, goals: Dictionary) -> float:
	var p: Vector3 = walk.point(cell)
	var low := INF
	for goal: Vector2i in goals:
		low = minf(low, p.distance_to(walk.point(goal)) + float(goals[goal]))
	return low

## One step between neighbouring centres. Two cells with nothing to collide in reach need no
## sampling: every point of the step lies in one of them and the body stays on the parcel.
func _step_clear(a: Vector2i, b: Vector2i) -> bool:
	if _roomy(a) and _roomy(b): return true
	return segment_clear(walk.point(a), walk.point(b))

func _roomy(cell: Vector2i) -> bool:
	if walk._proxies_by_cell.has(cell): return false
	for d: Vector2i in DIRS:
		if not walk.data.by_cell.has(cell + d): return false
	return true

## Skips waypoints the body can walk to in a straight line.
func _straighten(from: Vector3, points: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var anchor := from
	var index := 0
	while index < points.size():
		var reach := index
		for j in range(index + 1, mini(points.size(), index + SMOOTH_LOOKAHEAD + 1)):
			if segment_clear(anchor, points[j]): reach = j
			else: break
		anchor = points[reach]
		out.append(anchor)
		index = reach + 1
	return out

## Binary min-heap of [priority, cell].
class _Heap extends RefCounted:
	var items: Array = []
	func is_empty() -> bool: return items.is_empty()
	func push(priority: float, cell: Vector2i) -> void:
		items.append([priority, cell])
		var i := items.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if float(items[parent][0]) <= priority: break
			items[i] = items[parent]
			i = parent
		items[i] = [priority, cell]
	func pop() -> Array:
		var top: Array = items[0]
		var last: Array = items.pop_back()
		if items.is_empty(): return top
		var i := 0
		var n := items.size()
		while true:
			var child := i * 2 + 1
			if child >= n: break
			if child + 1 < n and float(items[child + 1][0]) < float(items[child][0]): child += 1
			if float(items[child][0]) >= float(last[0]): break
			items[i] = items[child]
			i = child
		items[i] = last
		return top
