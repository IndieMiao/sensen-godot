extends SceneTree
## Recomputes the solid collision profiles from the imported meshes and prints
## them as inventory JSON. Each primitive is the largest one inside the visible
## outline (`tests/dynamic_farm/prop_outline.gd`; trees: the trunk/root hull)
## whose default-fit footprint, grown by the body radius, still covers every
## solid model point. Lengths are rounded inward to millimetres;
## test_prop_proxies.gd checks the committed values.
##   godot --headless --path "$QA" --script res://tools/dev/dynamic_farm/fit_prop_proxies.gd
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Outline = preload("res://tests/dynamic_farm/prop_outline.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const CELL := 0.004
const FAR := 1e12
const TREE_TOP_M := 0.1  # trunk cylinders: fitted to (and drawn as) the low trunk
const CAPSULE_GAIN := 1.1  # a capsule must add 10% area over the best cylinder
var fit := 1.0

func _initialize() -> void: _run.call_deferred()

class Raster:
	var origin: Vector2
	var size: Vector2i
	var dist := PackedFloat32Array()  # metres from a cell centre to the nearest outside cell

	func _init(triangles: Array[PackedVector2Array]) -> void:
		var low := Vector2(INF, INF)
		var high := -low
		for t in triangles:
			for p in t:
				low = low.min(p)
				high = high.max(p)
		origin = low - Vector2.ONE * CELL * 2
		size = Vector2i(((high - origin) / CELL).ceil()) + Vector2i(3, 3)
		var inside := PackedByteArray()
		inside.resize(size.x * size.y)
		for t in triangles:
			var a := Vector2i(((t[0].min(t[1]).min(t[2]) - origin) / CELL).floor())
			var b := Vector2i(((t[0].max(t[1]).max(t[2]) - origin) / CELL).ceil())
			for y in range(a.y, b.y + 1):
				for x in range(a.x, b.x + 1):
					if Geometry2D.point_is_inside_triangle(center(x, y), t[0], t[1], t[2]): inside[y * size.x + x] = 1
		# Exact squared distance transform (Felzenszwalb–Huttenlocher), rows then columns.
		var grid := PackedFloat32Array()
		grid.resize(size.x * size.y)
		for i in grid.size(): grid[i] = 0.0 if inside[i] == 0 else FAR
		for y in size.y:
			var row := edt(grid.slice(y * size.x, (y + 1) * size.x))
			for x in size.x: grid[y * size.x + x] = row[x]
		for x in size.x:
			var column := PackedFloat32Array()
			for y in size.y: column.append(grid[y * size.x + x])
			column = edt(column)
			for y in size.y: grid[y * size.x + x] = column[y]
		dist.resize(grid.size())
		# Conservative: measure to the near edge of the outside cell.
		for i in grid.size(): dist[i] = maxf(0.0, sqrt(grid[i]) * CELL - CELL * 0.71)

	static func edt(f: PackedFloat32Array) -> PackedFloat32Array:
		var n := f.size()
		var d := PackedFloat32Array()
		d.resize(n)
		var v := PackedInt32Array()
		v.resize(n)
		var z := PackedFloat32Array()
		z.resize(n + 1)
		var k := 0
		z[0] = -FAR
		z[1] = FAR
		for q in range(1, n):
			var s := ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k])
			while s <= z[k]:
				k -= 1
				s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k])
			k += 1
			v[k] = q
			z[k] = s
			z[k + 1] = FAR
		k = 0
		for q in n:
			while z[k + 1] < q: k += 1
			d[q] = (q - v[k]) * (q - v[k]) + f[v[k]]
		return d

	func center(x: int, y: int) -> Vector2: return origin + (Vector2(x, y) + Vector2.ONE * 0.5) * CELL

	func at(p: Vector2) -> float:
		var c := Vector2i(((p - origin) / CELL).floor())
		if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y: return 0.0
		return dist[c.y * size.x + c.x]

func covers(points: PackedVector2Array, c: Vector2, axis: Vector2, half: float, radius: float) -> bool:
	# Default-fit footprint (segment ± half, rounded by radius) grown by the body.
	var reach := radius * fit + Walk.BODY_RADIUS - 0.002
	for p in points:
		var t := clampf((p - c).dot(axis), -half * fit, half * fit)
		if p.distance_to(c + axis * t) >= reach: return false
	return true

func best_cylinder(raster: Raster, points: PackedVector2Array) -> Dictionary:
	var best := {}
	for y in raster.size.y:
		for x in raster.size.x:
			var r := raster.dist[y * raster.size.x + x]
			if r <= best.get("radius", 0.0): continue
			var c := raster.center(x, y)
			if covers(points, c, Vector2.RIGHT, 0.0, r): best = {"center": c, "radius": r}
	return best

func best_capsule(raster: Raster, points: PackedVector2Array) -> Dictionary:
	var best := {}
	var area := 0.0
	for yaw_step in 90:
		var yaw := deg_to_rad(yaw_step * 2.0)
		var axis := Vector2(cos(yaw), -sin(yaw))  # local +X after a Y rotation
		for y in range(0, raster.size.y, 5):
			for x in range(0, raster.size.x, 5):
				var c := raster.center(x, y)
				var r := raster.at(c)
				var half := 0.0
				while r > 0.1:
					var a := PI * r * r + 4.0 * half * r
					if a > area and covers(points, c, axis, half, r):
						area = a
						best = {"center": c, "radius": r, "half": half, "yaw": yaw_step * 2.0}
					half += 0.01
					r = minf(r, minf(raster.at(c + axis * half), raster.at(c - axis * half)))
	return best

func mm(v: float) -> float: return floorf(v * 1000.0) / 1000.0

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenery.INVENTORY_PATH))
	fit = catalog.collision_fit_fraction
	for asset: Dictionary in catalog.assets:
		if asset.role not in ["tree", "shrub", "rock"]: continue
		var mesh := Scenery.Art.mesh_for(asset.id)
		var profile := {}
		if asset.role == "tree":
			# Low trunk, where the walker meets the tree; the trunk only narrows above.
			var outline := Outline.new(mesh, true, TREE_TOP_M)
			var c := best_cylinder(Raster.new(Outline.fan(outline.hull)), outline.solid_points)
			if not c.is_empty():
				profile = {"solid": true, "shape": "cylinder", "center_xz_m": [snappedf(c.center.x, 0.001), snappedf(c.center.y, 0.001)],
					"height_m": TREE_TOP_M, "radius_m": mm(c.radius)}
			else:
				# Splayed buttress roots (no inscribed primitive reaches their tips): the
				# smallest cylinder that does, kept within the model and its root spread.
				var center := Vector2.ZERO
				for step: float in [0.01, 0.002, 0.0005]:
					var start := center
					for iy in range(-10, 11):
						for ix in range(-10, 11):
							var at := start + Vector2(ix, iy) * step
							if outline.spread(at) < outline.spread(center): center = at
				center = Vector2(snappedf(center.x, 0.001), snappedf(center.y, 0.001))
				var radius := ceilf((outline.spread(center) - Walk.BODY_RADIUS + 0.002) / fit * 1000.0) / 1000.0
				profile = {"solid": true, "shape": "cylinder", "center_xz_m": [snappedf(center.x, 0.001), snappedf(center.y, 0.001)], "height_m": TREE_TOP_M, "radius_m": radius}
		else:
			var outline := Outline.new(mesh, false)
			var raster := Raster.new(outline.triangles)
			var c := best_cylinder(raster, outline.solid_points)
			var s := best_capsule(raster, outline.solid_points)
			var height := snappedf(mesh.get_aabb().size.y * 0.5, 0.01)
			if not s.is_empty() and (c.is_empty() or PI * s.radius * s.radius + 4.0 * s.half * s.radius > CAPSULE_GAIN * PI * c.radius * c.radius):
				profile = {"solid": true, "shape": "capsule", "center_xz_m": [snappedf(s.center.x, 0.001), snappedf(s.center.y, 0.001)],
					"radius_m": mm(s.radius), "length_m": mm(2.0 * (s.half + s.radius)), "yaw_degrees": s.yaw}
			elif not c.is_empty():
				profile = {"solid": true, "shape": "cylinder", "center_xz_m": [snappedf(c.center.x, 0.001), snappedf(c.center.y, 0.001)],
					"height_m": height, "radius_m": mm(c.radius)}
		print(asset.id, " ", JSON.stringify(profile) if not profile.is_empty() else "NO PROFILE KEEPS THE WALKER OUT")
	quit()
