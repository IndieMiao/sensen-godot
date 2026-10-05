class_name WaterShore
extends Node3D
## Shared decorative bank. Stones cross the exact water rim and plant roots sit
## just outside it. The ellipse and all decorative offsets use world metres;
## no navigation, collision, farming or fishing ownership is changed.

var _rng := RandomNumberGenerator.new()
var _rocks := SurfaceTool.new()
var _plants := SurfaceTool.new()
var _flowers := SurfaceTool.new()
var _pond := false

## Pond banks are seeded and deterministic, but generating them vertex by vertex costs ~0.8 s on a
## desktop M4 and several seconds on phones. The committed arrays are kept per pond (and can be
## made ahead on a worker thread with prewarm) so entering a pond only builds the meshes.
const CACHE_LIMIT := 8
static var _cache: Dictionary = {}     # key -> {"rocks": Array, "plants": Array, "flowers": Array}
static var _order: Array = []
static var _pending: Dictionary = {}   # key -> WorkerThreadPool task id
static var _lock := Mutex.new()

## Unit sphere / cylinder arrays, read once on the main thread. PrimitiveMesh arrays come back
## through the RenderingServer, which a worker thread can't reach while the main thread waits on it.
static var _unit: Dictionary = {}

static func _prepare_units() -> void:
	if not _unit.is_empty(): return
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 10
	sphere.rings = 4
	_unit["sphere"] = sphere.surface_get_arrays(0)
	for segments in [4, 5]:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.0
		cylinder.bottom_radius = 1.0
		cylinder.height = 1.0
		cylinder.radial_segments = segments
		cylinder.rings = 1
		_unit["cylinder%d" % segments] = cylinder.surface_get_arrays(0)

## Same output as PlaceScenery._oval / _cylinder (a radius-r, height-h cylinder is the unit one
## scaled by (r, h, r); its normals survive the inverse-transpose unchanged).
static func _oval(s: SurfaceTool, size: Vector3, center: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	_put(s, _unit.sphere, Transform3D(basis * Basis.from_scale(size), center), color)

static func _cylinder(s: SurfaceTool, radius: float, height: float, center: Vector3, color: Color, segments: int) -> void:
	_put(s, _unit["cylinder%d" % segments], Transform3D(Basis.from_scale(Vector3(radius, height, radius)), center), color)

static func _put(s: SurfaceTool, arrays: Array, transform: Transform3D, color: Color) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis := transform.basis.inverse().transposed()
	for index in indices:
		s.set_color(color)
		s.set_normal((normal_basis * normals[index]).normalized())
		s.add_vertex(transform * vertices[index])

static func _cacheable(spec: Dictionary) -> bool:
	return spec.has("polygon") and spec.get("space", "") != "street"

static func _cache_key(id: String, spec: Dictionary) -> String:
	return "%s:%d:%d" % [id, int(spec.get("decoration_seed", 0)), FishingModel._polygon(spec).size()]

## Start generating a pond's bank on a worker thread (e.g. when its map pin is selected).
static func prewarm(id: String, site_override: Dictionary = {}) -> void:
	_reap()
	_prepare_units()
	var spec := FishingModel.site(id, site_override)
	if not _cacheable(spec): return
	var key := _cache_key(id, spec)
	_lock.lock()
	var known := _cache.has(key) or _pending.has(key)
	_lock.unlock()
	if known: return
	_pending[key] = WorkerThreadPool.add_task(func(): _store(key, _generate(id, spec)), false, "WaterShore " + id)

## Every WorkerThreadPool task must be waited on once; collect the finished ones.
static func _reap() -> void:
	for key in _pending.keys():
		if WorkerThreadPool.is_task_completed(_pending[key]):
			WorkerThreadPool.wait_for_task_completion(_pending[key])
			_pending.erase(key)

static func _store(key: String, arrays: Dictionary) -> void:
	_lock.lock()
	_cache[key] = arrays
	_order.erase(key)
	_order.append(key)
	while _order.size() > CACHE_LIMIT: _cache.erase(_order.pop_front())
	_lock.unlock()

static func _pond_arrays(id: String, spec: Dictionary) -> Dictionary:
	var key := _cache_key(id, spec)
	if _pending.has(key):
		WorkerThreadPool.wait_for_task_completion(_pending[key])
		_pending.erase(key)
	_lock.lock()
	var hit: Dictionary = _cache.get(key, {})
	_lock.unlock()
	if hit.is_empty():
		hit = _generate(id, spec)
		_store(key, hit)
	return hit

## Thread-safe: builds the bank on a detached instance and returns committed, indexed arrays.
static func _generate(id: String, spec: Dictionary) -> Dictionary:
	var shore := WaterShore.new()
	shore._rng.seed = int(spec.decoration_seed) if spec.has("decoration_seed") else 190924 + id.hash()
	shore._rocks.begin(Mesh.PRIMITIVE_TRIANGLES)
	shore._plants.begin(Mesh.PRIMITIVE_TRIANGLES)
	shore._flowers.begin(Mesh.PRIMITIVE_TRIANGLES)
	shore._pond = true
	shore._pond_bank(FishingModel._polygon(spec))
	shore._rocks.generate_normals()
	var out := {}
	for pair in [["rocks", shore._rocks], ["plants", shore._plants], ["flowers", shore._flowers]]:
		var st: SurfaceTool = pair[1]
		st.index()
		out[pair[0]] = st.commit_to_arrays()
	shore.free()
	return out

static func build(id: String, site_override: Dictionary = {}) -> WaterShore:
	_prepare_units()
	var shore := WaterShore.new()
	shore.name = "NaturalWaterBank"
	shore._rng.seed = 190924 + id.hash()
	shore._rocks.begin(Mesh.PRIMITIVE_TRIANGLES)
	shore._plants.begin(Mesh.PRIMITIVE_TRIANGLES)
	shore._flowers.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spec := FishingModel.site(id, site_override)
	if spec.has("decoration_seed"): shore._rng.seed = int(spec.decoration_seed)
	if _cacheable(spec):
		shore._pond = true
		shore._add_banks(_pond_arrays(id, spec))
		return shore
	if spec.space == "street": shore._street_ground(spec)
	if spec.has("polygon"):
		shore._pond = true
		shore._pond_bank(FishingModel._polygon(spec))
	elif spec.has("center"):
		var center := Vector3(float(spec.center[0]), 0, float(spec.center[1]))
		var count := 48 if id == "farm_pond" else 34
		for index in count:
			var angle := TAU * (float(index) + shore._rng.randf_range(-0.20, 0.20)) / count
			var edge := Vector3(cos(angle) * float(spec.radii[0]), 0, sin(angle) * float(spec.radii[1]))
			# The radial direction is not the normal of an ellipse. Shrinking the
			# radii also moved every group into the water by a different distance,
			# leaving an exposed water strip beyond the reeds and far-bank stones.
			var outward := Vector3(cos(angle) / float(spec.radii[0]), 0, sin(angle) / float(spec.radii[1])).normalized()
			shore._bank_group(center + edge + outward * shore._rng.randf_range(-0.012, 0.012), outward, index, true)
	else:
		var path: Array = spec.path
		var index := 0
		for segment in path.size() - 1:
			var start := Vector3(path[segment][0], 0, path[segment][1])
			var end := Vector3(path[segment + 1][0], 0, path[segment + 1][1])
			var normal := Vector3.UP.cross((end - start).normalized())
			var count := ceili(start.distance_to(end) / 0.46)
			for step in count:
				for sign_value in [-1, 1]:
					var point := start.lerp(end, (float(step) + 0.5) / count)
					shore._bank_group(point + normal * sign_value * float(spec.width) * 0.47, normal * sign_value, index, false)
					index += 1
	var materials := shore._materials()
	if shore._pond: shore._rocks.generate_normals()
	shore._finish(shore._rocks, "BankStones", materials.rocks, true)
	shore._finish(shore._plants, "BankReedsAndGrass", materials.plants, true)
	shore._finish(shore._flowers, "BankFlowers", materials.flowers, false)
	return shore

func _materials() -> Dictionary:
	var rock_material := ShaderMaterial.new()
	rock_material.shader = preload("res://modules/fishing/shore_rock.gdshader")
	if _pond: rock_material.shader = preload("res://modules/ponds/pond_stone.gdshader")
	rock_material.set_shader_parameter("stone_detail", preload("res://assets/farm/art/water/shore_stone.png"))
	rock_material.set_shader_parameter("surface_flow", preload("res://assets/farm/art/water/surface_flow.png"))
	var plants := ShaderMaterial.new()
	plants.shader = preload("res://modules/fishing/bank_plants.gdshader")
	var flower_material := StandardMaterial3D.new()
	flower_material.vertex_color_use_as_albedo = true
	flower_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	flower_material.roughness = 0.85
	return {"rocks": rock_material, "plants": plants, "flowers": flower_material}

func _add_banks(arrays: Dictionary) -> void:
	var materials := _materials()
	for spec in [["rocks", "BankStones", true], ["plants", "BankReedsAndGrass", true], ["flowers", "BankFlowers", false]]:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays[spec[0]])
		_add_bank_node(spec[1], mesh, materials[spec[0]], spec[2])

func _finish(surface: SurfaceTool, label: String, material: Material, shadows: bool) -> void:
	surface.index()
	_add_bank_node(label, surface.commit(), material, shadows)

func _add_bank_node(label: String, mesh: Mesh, material: Material, shadows: bool) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	if not shadows: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _bank_group(point: Vector3, outward: Vector3, index: int, lake: bool) -> void:
	var tangent := Vector3.UP.cross(outward)
	var large := lake and _rng.randf() < 0.35
	if large or index % 2 == 0:
		var width := _rng.randf_range(0.22, 0.43) if large else _rng.randf_range(0.06, 0.16)
		# Taller clusters line the far bank; the open east/south banks stay low so
		# a near-shore float remains visible from the usual approach directions.
		if large and (outward.x < -0.40 or outward.z < -0.45):
			_rock(point + outward * width * 0.16, Vector3(width * 0.80, width * _rng.randf_range(0.60, 0.85), width), _rng.randf_range(0, TAU))
		else:
			_rock(point - outward * 0.015, Vector3(width * 0.40, width * _rng.randf_range(0.40, 0.58), width * _rng.randf_range(0.85, 1.1)), atan2(-outward.z, outward.x) + _rng.randf_range(-0.15, 0.15))
	for pebble in (5 if lake else 3):
		var width := _rng.randf_range(0.025, 0.085)
		_rock(point + tangent * _rng.randf_range(-0.20, 0.20) - outward * _rng.randf_range(0.04, 0.22), Vector3(width, width * 0.5, width * 0.8), _rng.randf_range(0, TAU))
	# Height/density follows clusters, leaving the near banks open for the player and float.
	var tall := index % (7 if lake else 13) in [0, 1]
	var origin := point + outward * (0.09 if lake else 0.02)
	for grass in (22 if lake else 10):
		var base := origin + tangent * _rng.randf_range(-0.22, 0.22) - outward * _rng.randf_range(0, 0.06 if lake else 0.08)
		var height := _rng.randf_range(0.30, 0.74) if tall else _rng.randf_range(0.07, 0.21)
		_blade(base, _rng.randf_range(0, TAU), height, tall)
	if tall:
		for stem in (3 if lake else 2):
			var base := origin + tangent * _rng.randf_range(-0.15, 0.15)
			var height := _rng.randf_range(0.52, 0.86)
			_cylinder(_plants, 0.009, height, base + Vector3.UP * height * 0.5, Color("7d873d").srgb_to_linear(), 5)
			_oval(_plants, Vector3(0.032, 0.11, 0.032), base + Vector3.UP * height, Color("a6814b").srgb_to_linear())
	if index % 4 == 2:
		for flower in 3:
			var base := origin + tangent * _rng.randf_range(-0.2, 0.2)
			_daisy(base, _rng.randf_range(0.13, 0.23))

func _rock(center: Vector3, radius: Vector3, yaw: float) -> void:
	var seed_value := _rng.randf_range(0, TAU)
	var tint := Color("d0cbb4").lerp(Color("829181"), _rng.randf()).srgb_to_linear()
	if _pond: tint = Color("cebdab").lerp(Color("b9b9ae"), _rng.randf_range(0.0, 0.6)).srgb_to_linear()
	var basis := Basis(Vector3.UP, yaw)
	var segments := 28 if _pond else 18
	var rings := 16 if _pond else 10
	for ring in rings:
		for segment in segments:
			var points: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for corner in [Vector2(segment, ring), Vector2(segment + 1, ring), Vector2(segment + 1, ring + 1), Vector2(segment, ring + 1)]:
				var a: float = corner.x / segments * TAU
				var b: float = corner.y / rings * PI
				var normal := Vector3(sin(b) * cos(a), cos(b), sin(b) * sin(a))
				var lump := 1.0 + sin(a * 3.0 + seed_value) * sin(b) * 0.15 + cos(b * 4.0 + seed_value) * 0.095
				if _pond: lump = 1.0 + sin(a * 3.0 + seed_value) * sin(b) * 0.065 + cos(b * 3.0 + seed_value) * 0.04
				var vertex := normal * radius * lump
				if _pond:
					# Worn fieldstone: broad top and oblique mineral faces, with
					# softened corners instead of a scaled sphere. Bounds remain
					# within the established bank/nav/float clearance envelope.
					var shaped := Vector3(signf(normal.x) * pow(absf(normal.x), .79), signf(normal.y) * pow(absf(normal.y), .74), signf(normal.z) * pow(absf(normal.z), .82))
					var face := Vector3(.72, .54, .42).normalized()
					var cut := shaped.dot(face)
					if cut > .96: shaped -= face * (cut - .96) * .80
					shaped.y = minf(shaped.y, .86 + shaped.x * .10 - shaped.z * .08)
					vertex = shaped * radius * lump
				vertex.y = maxf(-radius.y * 0.40, vertex.y)
				points.append(center + basis * vertex + Vector3.UP * radius.y * 0.34)
				normals.append(basis * ((normal / radius).normalized() if _pond else normal))
			for i in [0, 2, 1, 0, 3, 2]:
				_rocks.set_color(tint)
				_rocks.set_normal(normals[i])
				_rocks.add_vertex(points[i])

func _pond_bank(polygon: PackedVector2Array) -> void:
	# Sample arc length, not polygon vertices: even tessellation must not turn
	# every corner into a pebble pile. Large stones sit on the water side of the
	# immutable bank so they do not obstruct the server's walkable shoreline.
	var cursor := 0.0
	var next_stone := 0.15
	var index := 0
	for segment in polygon.size():
		var a := polygon[segment]
		var b := polygon[(segment + 1) % polygon.size()]
		var length := a.distance_to(b)
		var tangent := (b - a).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		if Geometry2D.is_point_in_polygon((a + b) * .5 + normal * .04, polygon): normal = -normal
		var out := Vector3(normal.x, 0, normal.y)
		var side := Vector3(tangent.x, 0, tangent.y)
		while next_stone < cursor + length:
			var at := a.lerp(b, (next_stone - cursor) / length)
			var point := Vector3(at.x, 0, at.y)
			var hero := index % 5 == 0 or index % 7 == 2
			var radius := _rng.randf_range(.38, .55) if hero else _rng.randf_range(.16, .30)
			var near := out.dot(Vector3(.16, 0, 1).normalized()) > .08
			var across := minf(radius * .60, .22) if near else radius * .78
			var height := minf(radius * .50, .16) if near else radius * .70
			# The reference's large stones spread ALONG the approach bank. Keep
			# their cross-bank extent and height low: the existing 0.55m default
			# landing must remain visible rather than disappearing inside a rock.
			var yaw := atan2(-out.z, out.x) + _rng.randf_range(-.12,.12)
			_rock(point - out * across * .50, Vector3(across, height, radius), yaw)
			if hero:
				_rock(point + side * radius * .94 - out * .10, Vector3(.14,.11,.20), _rng.randf_range(0, TAU))
			for blade in (30 if hero else 16):
				var base := point + out * _rng.randf_range(.06,.18) + side * _rng.randf_range(-.3,.3)
				_blade(base, _rng.randf_range(0, TAU), _rng.randf_range(.09,.23), false)
			if index % 6 == 3:
				for flower in 5: _daisy(point + out * .3 + side * _rng.randf_range(-.25,.25), _rng.randf_range(.17,.30))
			if index % 8 == 3:
				_flowering_cushion(point - out * .18, side)
			next_stone += radius * 1.7 + _rng.randf_range(.15,.34)
			index += 1
		# A continuous low grass lip hides the straight polygon facets.
		for blade in maxi(1, ceili(length * 36)):
			var at := a.lerp(b, _rng.randf())
			var base := Vector3(at.x, 0, at.y) + out * _rng.randf_range(.025,.14)
			_blade(base, _rng.randf_range(0,TAU), _rng.randf_range(.045,.12), false)
		cursor += length

func _flowering_cushion(center: Vector3, tangent: Vector3) -> void:
	# Low bank planting grows between the stones. Individual fleshy leaves and
	# white flowers read at the close fishing camera without a billboard.
	for leaf in 60:
		var angle := _rng.randf_range(0,TAU)
		var radial := sqrt(_rng.randf())
		var point := center + Vector3(cos(angle)*.40*radial, .08 + (1-radial)*.31, sin(angle)*.30*radial)
		var basis := Basis(Vector3.UP,-angle) * Basis(Vector3.FORWARD, _rng.randf_range(-.65,.35))
		var tint := Color("709b39").lerp(Color("cadb72"),_rng.randf()).srgb_to_linear()
		_plants.set_uv(Vector2(.5,.7))
		_oval(_plants,Vector3(.24,.055,.12),point,tint,basis)
	for flower in 9:
		var point := center + tangent * _rng.randf_range(-.29,.29) + Vector3(_rng.randf_range(-.1,.1),0,_rng.randf_range(-.15,.15))
		_daisy(point,_rng.randf_range(.29,.44))

func _blade(base: Vector3, yaw: float, height: float, reed: bool) -> void:
	var direction := Vector3(cos(yaw), 0, sin(yaw))
	var side := Vector3(-direction.z, 0, direction.x)
	var width := height * (0.095 if reed else 0.14)
	var color := Color("567d29").lerp(Color("b7c65b"), _rng.randf())
	for section in 3:
		var t0 := float(section) / 3.0
		var t1 := float(section + 1) / 3.0
		var start := base + Vector3.UP * height * t0 + direction * height * t0 * t0 * 0.40
		var end := base + Vector3.UP * height * t1 + direction * height * t1 * t1 * 0.40
		var left := side * width * (1.0 - t0)
		var right := side * width * (1.0 - t1)
		_quad(_plants, [start - left, start + left, end + right, end - right], color.srgb_to_linear(), t0, t1)

func _daisy(base: Vector3, height: float) -> void:
	_cylinder(_flowers, 0.005, height, base + Vector3.UP * height * 0.5, Color("647a34").srgb_to_linear(), 4)
	var center := base + Vector3.UP * height
	for petal in 6:
		var a := float(petal) / 6.0 * TAU
		var size := 1.65 if _pond else 1.0
		_oval(_flowers, Vector3(0.035, 0.009, 0.014) * size, center + Vector3(cos(a), 0, sin(a)) * 0.028 * size, Color("fff4ce").srgb_to_linear(), Basis(Vector3.UP, -a))
	_oval(_flowers, Vector3(0.016, 0.013, 0.016), center + Vector3.UP * 0.008, Color("dbb64a").srgb_to_linear())

static func _quad(surface: SurfaceTool, points: Array, color: Color, v0 := 0.0, v1 := 1.0) -> void:
	var normal: Vector3 = (points[2] - points[0]).cross(points[1] - points[0]).normalized()
	var uvs := [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]
	for index in [0, 1, 2, 0, 2, 3]:
		surface.set_color(color)
		surface.set_normal(normal)
		surface.set_uv(uvs[index])
		surface.add_vertex(points[index])

func _street_ground(spec: Dictionary) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if spec.has("center"):
		for index in 96:
			var points: Array[Vector3] = []
			for corner in [Vector2(index, 0), Vector2(index + 1, 0), Vector2(index + 1, 1), Vector2(index, 1)]:
				var angle: float = corner.x / 96.0 * TAU
				var spread: float = -0.04 + corner.y * (0.60 + sin(angle * 7.0) * 0.08)
				points.append(Vector3(spec.center[0] + cos(angle) * (spec.radii[0] + spread), -0.028,
					spec.center[1] + sin(angle) * (spec.radii[1] + spread)))
			_quad(surface, points, Color.WHITE)
	else:
		var path: Array = spec.path
		for side in [-1, 1]:
			var inner: Array[Vector3] = []
			var outer: Array[Vector3] = []
			for index in path.size():
				var a := Vector3(path[maxi(0, index - 1)][0], 0, path[maxi(0, index - 1)][1])
				var b := Vector3(path[mini(path.size() - 1, index + 1)][0], 0, path[mini(path.size() - 1, index + 1)][1])
				var normal: Vector3 = Vector3.UP.cross((b - a).normalized()) * side
				var center := Vector3(path[index][0], -0.028, path[index][1])
				inner.append(center + normal * (float(spec.width) * 0.5 - 0.04))
				outer.append(center + normal * (float(spec.width) * 0.5 + 0.60))
			for index in path.size() - 1:
				_quad(surface, [inner[index], inner[index + 1], outer[index + 1], outer[index]], Color.WHITE)
	var material := ShaderMaterial.new()
	material.shader = preload("res://modules/fishing/street_bank.gdshader")
	material.set_shader_parameter("grass_detail", preload("res://assets/farm/art/water/bank_grass.png"))
	_finish(surface, "BankGround", material, false)
