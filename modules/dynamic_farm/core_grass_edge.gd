extends RefCounted
## Paint only the shared side of a core soil tile and extension grass. The
## decoded cells (including paths, voids and permissions) remain authoritative.
const Edges = preload("res://modules/dynamic_farm/farm_edges.gd")
const GRASS := 1
const MAX_INSET := 0.42 # in cells; even a one-cell-wide strip keeps its centre
const STEPS := 8

static func mask(rows: Dictionary, at: Vector2i) -> int:
	var row: Dictionary = rows.get(at, {})
	if row.get("zone") != "core" or row.surface_id != 0:
		return 0
	var sides := 0
	for side in 4:
		var next: Dictionary = rows.get(at + Edges.NEIGHBORS[side], {})
		if next.get("zone") == "extension" and next.surface_id == GRASS:
			sides |= 1 << side
	return sides

static func noise_for(seed_hex: String) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_hex.left(8).hex_to_int()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = 1.0
	return noise

static func depth(p: Vector2, noise: FastNoiseLite) -> float:
	# Broad bites and shorter, rounded shoulders; sampled in parcel coordinates
	# (not chunk-local coordinates), so long runs and reloads stay continuous.
	var lobe := noise.get_noise_2dv(p * 1.9) + 0.45 * noise.get_noise_2dv(p * 4.1)
	return lerpf(0.055, MAX_INSET, smoothstep(-0.45, 0.45, lobe))

static func corner_depth(at: Vector2i, corner: int, sides: int, noise: FastNoiseLite) -> float:
	var adjacent := (1 << corner) | (1 << ((corner + 3) % 4))
	# Keep adjacent wavy sides in disjoint strips at a convex soil corner.
	return MAX_INSET if (sides & adjacent) == adjacent else depth(Vector2(at + Edges.CORNERS[corner]), noise)

## The two materials share the very same contour vertices at y=0. No decals,
## coplanar overlay, per-cell materials, or additional shadow pass.
static func emit(soil: SurfaceTool, grass: SurfaceTool, corners: Array, at: Vector2i,
		sides: int, metres: float, noise: FastNoiseLite) -> void:
	var inside := PackedVector3Array()
	for i in 4:
		var shift := Vector3.ZERO
		for side: int in [i, (i + 3) % 4]:
			if sides & (1 << side): shift -= Edges.normal(side)
		inside.append(corners[i] + shift * (metres * corner_depth(at, i, sides, noise)))
	var outline := PackedVector3Array()
	for side in 4:
		var end := (side + 1) % 4
		outline.append(inside[side])
		if not (sides & (1 << side)): continue
		var a: Vector3 = corners[side]
		var b: Vector3 = corners[end]
		var strip := PackedVector3Array([b, a, inside[side]])
		var dir := (b - a).normalized()
		var inward := -Edges.normal(side)
		for j in range(1, STEPS):
			# Sample along the shortened edge, not past a convex corner.
			var along := dir.dot(inside[side].lerp(inside[end], float(j) / STEPS) - a)
			var p := Vector2(at + Edges.CORNERS[side]).lerp(Vector2(at + Edges.CORNERS[end]), along / metres)
			var inner := a + dir * along + inward * (metres * depth(p, noise))
			strip.append(inner)
			outline.append(inner)
		strip.append(inside[end])
		_fill(grass, strip)
	_fill(soil, outline)

static func _fill(tool: SurfaceTool, outline: PackedVector3Array) -> void:
	# Concave notches need ear clipping rather than a triangle fan.
	var polygon := PackedVector2Array()
	for p in outline: polygon.append(Vector2(p.x, -p.z))
	var indices := Geometry2D.triangulate_polygon(polygon)
	for j in range(0, indices.size(), 3):
		# Godot returns CCW indices in the (x,-z) plane. Front faces are CW.
		for k: int in [j, j + 2, j + 1]:
			tool.set_normal(Vector3.UP)
			tool.add_vertex(outline[indices[k]])
