extends RefCounted
## Spill the core soil into the bordering extension grass as rounded lumps
## (reference image 2). Only paint moves: core tops stay full squares and the
## decoded cells (including paths, voids and permissions) remain authoritative.
const Edges = preload("res://modules/dynamic_farm/farm_edges.gd")
const SOIL := 0
const GRASS := 1
const MAX_SPILL := 0.48 # in cells; never reaches the next row or meets across a one-cell strip
const STEPS := 24
const CORNER_GAP := 0.5 # > MAX_SPILL

## Sides of an extension grass cell that touch core soil.
static func mask(rows: Dictionary, at: Vector2i) -> int:
	var row: Dictionary = rows.get(at, {})
	if row.get("zone") != "extension" or row.surface_id != GRASS:
		return 0
	var sides := 0
	for side in 4:
		var next: Dictionary = rows.get(at + Edges.NEIGHBORS[side], {})
		if next.get("zone") == "core" and next.surface_id == SOIL:
			sides |= 1 << side
	return sides

static func noise_for(seed_hex: String) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_hex.left(8).hex_to_int()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = 1.0
	return noise

## Spill depth (cells) at `along` (0..1, increasing grid x or y) on one side.
static func spill(at: Vector2i, side: int, along: float, masks: Dictionary, noise: FastNoiseLite) -> float:
	return _height(_lumps(at, side, masks, noise), at, side, along, noise)

## Each unit of a boundary line owns a few elliptical lumps. A lump may cross
## into the next unit only when that unit also spills on the same side, so the
## outline is continuous along a run and closes to zero where the run ends.
## Next to a concave soil corner a lump also keeps CORNER_GAP clear, which keeps
## the two sides' strips disjoint without any polygon clipping.
static func _lumps(at: Vector2i, side: int, masks: Dictionary, noise: FastNoiseLite) -> Array:
	var axis := _axis(side)
	var line := at.y if side % 2 == 0 else at.x
	var unit := at.x if side % 2 == 0 else at.y
	var low_side := 3 if side % 2 == 0 else 0
	var high_side := 1 if side % 2 == 0 else 2
	var open := []
	for j in range(-2, 3):
		open.append(int(masks.get(at + axis * j, 0)) & (1 << side) != 0)
	var lumps := []
	for j in range(-1, 2):
		if not open[j + 2]: continue
		var owner := int(masks.get(at + axis * j, 0))
		var low := 0.0 if open[j + 1] else (CORNER_GAP if owner & (1 << low_side) else 0.0)
		var high := 1.0 if open[j + 3] else (1.0 - CORNER_GAP if owner & (1 << high_side) else 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = noise.seed * 1000003 ^ side * 73856093 ^ line * 19349663 ^ (unit + j) * 83492791
		# Slow density along the line alternates heavy clumps and lighter
		# stretches, so a long, straight core edge does not read as a ruler.
		var crowd := smoothstep(0.3, 0.7, noise.get_noise_2d((unit + j + 0.5) * 0.35, line * 3.17 + side * 41.3) * 0.5 + 0.5)
		var big := clampi(roundi(crowd * 1.6 + rng.randf() * 0.9), 0, 2)
		var pebbles := 1 if rng.randf() < 0.5 else 0
		# Lumps of one unit huddle together like image 2's cauliflower clumps.
		var cluster := rng.randf_range(0.2, 0.8)
		for n in big + pebbles:
			var radius := rng.randf_range(0.08, 0.14) if n >= big else rng.randf_range(0.2, 0.3) + 0.08 * crowd
			var centre := clampf(cluster + rng.randf_range(-0.4, 0.4), 0.05, 0.95)
			var depth := minf(radius * rng.randf_range(1.05, 1.4) * (0.85 + 0.35 * crowd), MAX_SPILL)
			# Closed ends pull a lump inside its own unit (plus the corner gap).
			if not open[j + 1]: centre = maxf(centre, low + radius)
			if not open[j + 3]: centre = minf(centre, high - radius)
			if not open[j + 1] and centre - radius < low - 0.000001: continue
			lumps.append(Vector4(j, centre, radius, depth))
	return [lumps, open[1], open[3]]

static func _height(lumps: Array, at: Vector2i, side: int, along: float, noise: FastNoiseLite) -> float:
	var line := at.y if side % 2 == 0 else at.x
	var unit := at.x if side % 2 == 0 else at.y
	# A shallow, slow wobble keeps the gaps between lumps from reading as a ruler.
	var wobble := lerpf(0.03, 0.09, noise.get_noise_2d((unit + along) * 0.9, line * 7.31 + side * 53.7) * 0.5 + 0.5)
	if not lumps[1]: wobble *= smoothstep(0.0, 0.15, along)
	if not lumps[2]: wobble *= smoothstep(0.0, 0.15, 1.0 - along)
	var depth := wobble
	for lump: Vector4 in lumps[0]:
		# Unit-relative, so neighbours evaluate a shared end bit-identically.
		var x := ((along - lump.x) - lump.y) / lump.z
		if absf(x) < 1.0: depth = maxf(depth, lump.w * sqrt(1.0 - x * x))
	return depth

## Grid axis that increases along a side.
static func _axis(side: int) -> Vector2i:
	return Vector2i(1, 0) if side % 2 == 0 else Vector2i(0, 1)

## Inner soil contour of one side, in unit-square corner order.
static func _contour(at: Vector2i, side: int, masks: Dictionary, noise: FastNoiseLite) -> PackedVector2Array:
	var origin := Vector2(Edges.NEIGHBORS[side].max(Vector2i.ZERO))
	var axis := Vector2(_axis(side))
	var inward := -Vector2(Edges.NEIGHBORS[side])
	var lumps := _lumps(at, side, masks, noise)
	var contour := PackedVector2Array()
	for j in STEPS + 1:
		var along := float(j) / STEPS
		contour.append(origin + axis * along + inward * _height(lumps, at, side, along, noise))
	if side >= 2: contour.reverse()
	return contour

## The grass and soil share every contour vertex at y=0, and a strip never
## adds vertices along the core edge, so no T-junction meets the full core top.
static func emit(soil: SurfaceTool, grass: SurfaceTool, corners: Array, at: Vector2i,
		masks: Dictionary, noise: FastNoiseLite) -> void:
	var sides: int = masks.get(at, 0)
	var lawn := PackedVector2Array()
	for side in 4:
		var start := Vector2(Edges.CORNERS[side])
		var finish := Vector2(Edges.CORNERS[(side + 1) % 4])
		if not sides & (1 << side):
			if not sides & (1 << ((side + 3) % 4)): lawn.append(start)
			continue
		var contour := _contour(at, side, masks, noise)
		var strip := PackedVector2Array([start, finish])
		for j in range(contour.size() - 1, -1, -1):
			# A closed run end meets the boundary exactly at the corner.
			if contour[j] != start and contour[j] != finish: strip.append(contour[j])
		_fill(soil, corners, strip)
		for p in contour:
			if lawn.is_empty() or lawn[-1] != p: lawn.append(p)
	if lawn.size() > 1 and lawn[0] == lawn[-1]: lawn.remove_at(lawn.size() - 1)
	_fill(grass, corners, lawn)

static func _fill(tool: SurfaceTool, corners: Array, polygon: PackedVector2Array) -> void:
	# Lumps make concave outlines, so use ear clipping rather than a fan.
	var origin: Vector3 = corners[0]
	var indices := Geometry2D.triangulate_polygon(polygon)
	for j in range(0, indices.size(), 3):
		var a := polygon[indices[j]]
		var b := polygon[indices[j + 1]]
		var c := polygon[indices[j + 2]]
		# Unit (x, y) is world (x, -z). Front faces are clockwise from above.
		if (b - a).cross(c - a) > 0.0:
			var swap := b
			b = c
			c = swap
		for p: Vector2 in [a, b, c]:
			# Snap the unit edges to the shared cell corners to avoid cracks.
			var x: float = corners[1].x if p.x == 1.0 else origin.x + (corners[1].x - origin.x) * p.x
			var z: float = corners[3].z if p.y == 1.0 else origin.z + (corners[3].z - origin.z) * p.y
			tool.set_normal(Vector3.UP)
			tool.add_vertex(Vector3(x, origin.y, z))
