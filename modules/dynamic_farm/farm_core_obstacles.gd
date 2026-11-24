extends RefCounted
## Props on authoritative schema-4 core cells. Per Q-16, stones, bushes and trees
## block with their model-fitted inventory profile (Scenery.build); weeds do not.
## Cells, masks and farming permissions are unchanged. Weeds, stones and bushes take
## one cell; a tree takes a square block (`cells` per side, 2x2 by default) at the
## same scale as the outer grove trees. A blocking prop only takes cells whose
## neighbours are open ground and whose loss keeps every other cell reachable, so no
## existing path or area is cut off.
const ROLES := ["weed", "stone", "bush", "tree"]
## Trees need the most room, so they choose first; the smaller props then keep off
## the ring of cells under their crowns.
const ORDER := ["tree", "weed", "stone", "bush"]

static func plan(data: Dictionary, walk: RefCounted, inventory: Dictionary, recipe: Dictionary, rng: RefCounted) -> Dictionary:
	var candidates: Array[Vector2i] = []
	# Data.decode guarantees canonical (y,x) order inside each zone.
	for cell: Dictionary in data.cells:
		if cell.zone != "core": continue
		var at := Vector2i(cell.x, cell.y)
		if _near_arrival(at, data.spawn) or _near_arrival(at, data.entry): continue
		candidates.append(at)

	var target := roundi(int(data.counts.core) * float(recipe.coverage))
	var wanted := {}
	var assigned := 0
	for role: String in ROLES:
		# The last role receives the rounding remainder, so the total stays exact.
		wanted[role] = target - assigned if role == ROLES.back() else roundi(target * float(recipe.roles[role].share))
		assigned += wanted[role]
	var counts := {}
	for role: String in ROLES: counts[role] = 0
	var layout := []
	var signature := PackedStringArray()
	var blocking := {}
	# Cells under or beside a tree: no other prop may take them.
	var taken := {}
	for role: String in ORDER:
		var spec: Dictionary = recipe.roles[role]
		var size := int(spec.get("cells", 1))
		# Candidates in [index, limit) are open; cells this role may not take are
		# parked after `limit`. Blocking only grows, so they stay unusable for it.
		var limit := candidates.size()
		for i in wanted[role]:
			# Partial Fisher-Yates: sample distinct cells in bounded time.
			var index := layout.size()
			var at := Vector2i.ZERO
			var asset := ""
			var transform := Transform3D.IDENTITY
			var cells: Array[Vector2i] = []
			while index < limit:
				var pick := index + int(rng.next()) % (limit - index)
				at = candidates[pick]
				asset = spec.ids[int(rng.next()) % spec.ids.size()]
				var record: Dictionary = inventory[asset]
				if size == 1:
					cells = [at]
					transform = _fit_cell(record, walk.point(at), data.cell_m, rng)
				else:
					cells = _block(at, size, data, walk, taken)
					transform = _fit_block(record, cells, walk, spec.scale, rng)
				if not cells.is_empty() and not taken.has(at) and (size == 1 or _inside_ring(record, transform, cells, data, walk)) \
						and (not bool(record.collision_proxy.solid) or _keeps_open(cells, data, walk, blocking)):
					candidates[pick] = candidates[index]
					candidates[index] = at
					break
				limit -= 1
				candidates[pick] = candidates[limit]
				candidates[limit] = at
			if index >= limit: break
			var record: Dictionary = inventory[asset]
			var solid := bool(record.collision_proxy.solid)
			for cell: Vector2i in cells:
				if solid: blocking[cell] = true
			if size > 1:
				for cell: Vector2i in cells + _ring(cells): taken[cell] = true
			layout.append({"asset":asset, "role":role, "cell":at, "cells":cells, "transform":transform,
				"solid":solid, "shadow":role != "weed", "triangles":int(record.triangles)})
			signature.append("%s:%s:%s:%s" % [at, role, asset, transform])
			counts[role] += 1
	return {"layout":layout, "roles":counts, "layout_sha256":"\n".join(signature).sha256_text()}

## The `size` x `size` core cells from `at` up, or none if any is unavailable.
static func _block(at: Vector2i, size: int, data: Dictionary, walk: RefCounted, taken: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in size:
		for x in size:
			var cell := at + Vector2i(x, y)
			if not walk.clear_cell(cell) or data.by_cell[cell].zone != "core" or taken.has(cell) \
					or _near_arrival(cell, data.spawn) or _near_arrival(cell, data.entry):
				return []
			cells.append(cell)
	return cells

## The cells bordering `cells` (eight-way), excluding `cells` themselves.
static func _ring(cells: Array[Vector2i]) -> Array[Vector2i]:
	var inside := {}
	for cell: Vector2i in cells: inside[cell] = true
	var ring: Array[Vector2i] = []
	for cell: Vector2i in cells:
		for y in range(-1, 2):
			for x in range(-1, 2):
				var next := cell + Vector2i(x, y)
				if not inside.has(next) and not ring.has(next): ring.append(next)
	return ring

## A tree crown overhangs its block by less than one cell. The whole model must stay
## over the block and its ring, and the ring must be open core ground, so the crown
## never leaves the core; `taken` keeps every later prop off the ring.
static func _inside_ring(record: Dictionary, transform: Transform3D, cells: Array[Vector2i], data: Dictionary,
		walk: RefCounted) -> bool:
	var low := Vector2(INF, INF)
	var high := -low
	for cell: Vector2i in cells:
		var p: Vector3 = walk.point(cell)
		low = low.min(Vector2(p.x, p.z))
		high = high.max(Vector2(p.x, p.z))
	var reach: float = walk.cell_m * 1.5
	var box: AABB = transform * _bounds(record)
	if box.position.x < low.x - reach or box.position.z < low.y - reach or box.end.x > high.x + reach or box.end.z > high.y + reach:
		return false
	for cell: Vector2i in _ring(cells):
		if not walk.clear_cell(cell) or data.by_cell[cell].zone != "core": return false
	return true

## A blocking prop fills its cells and reaches a little into the neighbours, so it
## needs open ground all around and must leave every remaining cell connected.
static func _keeps_open(cells: Array[Vector2i], data: Dictionary, walk: RefCounted, blocking: Dictionary) -> bool:
	for cell: Vector2i in _ring(cells):
		if not walk.clear_cell(cell) or blocking.has(cell): return false
	for cell: Vector2i in cells: blocking[cell] = true
	var open := 0
	for cell: Vector2i in data.by_cell:
		if walk.clear_cell(cell) and not blocking.has(cell): open += 1
	var queue: Array[Vector2i] = [data.spawn]
	var seen := {data.spawn: true}
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for offset: Vector2i in walk.NEIGHBORS:
			var next: Vector2i = cell + offset
			if walk.clear_cell(next) and not blocking.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	for cell: Vector2i in cells: blocking.erase(cell)
	return seen.size() == open

static func _near_arrival(at: Vector2i, arrival: Vector2i) -> bool:
	var offset := (at - arrival).abs()
	return maxi(offset.x, offset.y) <= 1

## Keep the original ground pivot, rotate first, then fit the whole visible XZ
## extent. This keeps one occupied visual cell equivalent to one sampled cell.
static func _fit_cell(record: Dictionary, center: Vector3, cell_m: float, rng: RefCounted) -> Transform3D:
	var basis := Basis(Vector3.UP, float(rng.unit()) * TAU)
	var rotated := Transform3D(basis, Vector3.ZERO) * _bounds(record)
	var extent := rotated.position.abs().max(rotated.end.abs())
	var scale_value := cell_m * 0.5 * lerpf(0.76, 0.95, rng.unit()) / maxf(extent.x, extent.z)
	return Transform3D(basis.scaled(Vector3.ONE * scale_value), center)

## A tree keeps its original ground pivot at the centre of its block, at the outer
## groves' tree scale, turned in quarter turns like their solid props.
static func _fit_block(record: Dictionary, cells: Array[Vector2i], walk: RefCounted, scale_range: Array,
		rng: RefCounted) -> Transform3D:
	if cells.is_empty(): return Transform3D.IDENTITY
	var center: Vector3 = (walk.point(cells[0]) + walk.point(cells.back())) * 0.5
	var basis := Basis(Vector3.UP, float(int(rng.next()) % 4) * PI * 0.5)
	var scale_value := lerpf(float(scale_range[0]), float(scale_range[1]), rng.unit())
	return Transform3D(basis.scaled(Vector3.ONE * scale_value), center)

static func _bounds(record: Dictionary) -> AABB:
	var low: Array = record.bounds_godot_m[0]
	var high: Array = record.bounds_godot_m[1]
	var minimum := Vector3(low[0], low[1], low[2])
	return AABB(minimum, Vector3(high[0], high[1], high[2]) - minimum)
