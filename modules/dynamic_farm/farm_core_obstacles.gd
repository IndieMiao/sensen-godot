extends RefCounted
## Single-cell props on authoritative schema-4 core cells. Per Q-16, stones, bushes
## and saplings block with their model-fitted inventory profile (Scenery.build);
## weeds do not. Cells, masks and farming permissions are unchanged. A blocking
## prop only takes a cell whose eight neighbours are open ground and whose loss
## keeps every other cell reachable, so no existing path or area is cut off.
const ROLES := ["weed", "stone", "bush", "sapling"]
const AROUND := [Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1), Vector2i(-1,0),
	Vector2i(1,0), Vector2i(-1,1), Vector2i(0,1), Vector2i(1,1)]

static func plan(data: Dictionary, walk: RefCounted, inventory: Dictionary, recipe: Dictionary, rng: RefCounted) -> Dictionary:
	var candidates: Array[Vector2i] = []
	# Data.decode guarantees canonical (y,x) order inside each zone.
	for cell: Dictionary in data.cells:
		if cell.zone != "core": continue
		var at := Vector2i(cell.x, cell.y)
		if _near_arrival(at, data.spawn) or _near_arrival(at, data.entry): continue
		candidates.append(at)

	var target := roundi(int(data.counts.core) * float(recipe.coverage))
	var counts := {}
	var layout := []
	var signature := PackedStringArray()
	var blocking := {}
	# Candidates in [index, limit) are open; cells a blocking prop may not take
	# are parked after `limit` for good, as weeds have already been placed.
	var limit := candidates.size()
	for role: String in ROLES:
		var spec: Dictionary = recipe.roles[role]
		# The last role receives the rounding remainder, so the total stays exact.
		var count := target - layout.size() if role == ROLES.back() else roundi(target * float(spec.share))
		counts[role] = 0
		for i in count:
			# Partial Fisher-Yates: sample distinct cells in bounded time.
			var index := layout.size()
			var at := Vector2i.ZERO
			var asset := ""
			while index < limit:
				var pick := index + int(rng.next()) % (limit - index)
				at = candidates[pick]
				asset = spec.ids[int(rng.next()) % spec.ids.size()]
				if not bool(inventory[asset].collision_proxy.solid) or _keeps_open(at, data, walk, blocking):
					candidates[pick] = candidates[index]
					candidates[index] = at
					break
				limit -= 1
				candidates[pick] = candidates[limit]
				candidates[limit] = at
			if index >= limit: break
			var record: Dictionary = inventory[asset]
			var solid := bool(record.collision_proxy.solid)
			if solid: blocking[at] = true
			var transform := _fit_cell(record, walk.point(at), data.cell_m, rng)
			layout.append({"asset":asset, "role":role, "cell":at, "transform":transform,
				"solid":solid, "shadow":role != "weed", "triangles":int(record.triangles)})
			signature.append("%s:%s:%s:%s" % [at, role, asset, transform])
			counts[role] += 1
	return {"layout":layout, "roles":counts, "layout_sha256":"\n".join(signature).sha256_text()}

## A blocking prop fills its cell and reaches a little into the neighbours, so it
## needs open ground all around and must leave every remaining cell connected.
static func _keeps_open(at: Vector2i, data: Dictionary, walk: RefCounted, blocking: Dictionary) -> bool:
	for offset: Vector2i in AROUND:
		var next: Vector2i = at + offset
		if not walk.clear_cell(next) or blocking.has(next): return false
	blocking[at] = true
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
	blocking.erase(at)
	return seen.size() == open

static func _near_arrival(at: Vector2i, arrival: Vector2i) -> bool:
	var offset := (at - arrival).abs()
	return maxi(offset.x, offset.y) <= 1

## Keep the original ground pivot, rotate first, then fit the whole visible XZ
## extent. This keeps one occupied visual cell equivalent to one sampled cell.
static func _fit_cell(record: Dictionary, center: Vector3, cell_m: float, rng: RefCounted) -> Transform3D:
	var low: Array = record.bounds_godot_m[0]
	var high: Array = record.bounds_godot_m[1]
	var minimum := Vector3(low[0], low[1], low[2])
	var maximum := Vector3(high[0], high[1], high[2])
	var bounds := AABB(minimum, maximum - minimum)
	var basis := Basis(Vector3.UP, float(rng.unit()) * TAU)
	var rotated := Transform3D(basis, Vector3.ZERO) * bounds
	var extent := rotated.position.abs().max(rotated.end.abs())
	var scale_value := cell_m * 0.5 * lerpf(0.76, 0.95, rng.unit()) / maxf(extent.x, extent.z)
	return Transform3D(basis.scaled(Vector3.ONE * scale_value), center)
