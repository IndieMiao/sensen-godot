extends RefCounted
## Pure presentation layer. Authoritative schema-4 core cells stay plantable/walkable;
## in particular, the reserve prohibits solid decor, not this non-solid appearance.
const ROLES := ["weed", "stone", "bush", "sapling"]

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
	for role: String in ROLES:
		var spec: Dictionary = recipe.roles[role]
		# The last role receives the rounding remainder, so the total stays exact.
		var count := target - layout.size() if role == ROLES.back() else roundi(target * float(spec.share))
		counts[role] = count
		for i in count:
			# Partial Fisher-Yates: sample distinct cells in bounded time without retries.
			var index := layout.size()
			var pick := index + int(rng.next()) % (candidates.size() - index)
			var at := candidates[pick]
			candidates[pick] = candidates[index]
			var asset: String = spec.ids[int(rng.next()) % spec.ids.size()]
			var record: Dictionary = inventory[asset]
			var transform := _fit_cell(record, walk.point(at), data.cell_m, rng)
			layout.append({"asset":asset, "role":role, "cell":at, "transform":transform,
				"solid":false, "shadow":role != "weed", "triangles":int(record.triangles)})
			signature.append("%s:%s:%s:%s" % [at, role, asset, transform])
	return {"layout":layout, "roles":counts, "layout_sha256":"\n".join(signature).sha256_text()}

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
