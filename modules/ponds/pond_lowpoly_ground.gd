extends RefCounted
## The wild's lowpoly flat ground (SGODOT-422, 盘古's sample 11-09; the user 11-08: the ground "like pasted textures",
## make it lowpoly flat and blocky): one vertex-coloured mesh of jittered triangles, every face its own flat colour and
## normal. The walk (PondWalk.WALK) stays at y 0 — the walk and the navigation as they are — and reads by its colour
## blocks; past it the bank rises in two hard-folded terraces with warm rock faces, then low hills that pale with
## distance (the far layer). A warm sand band meets the water; under the water the ground dips (the water is opaque).
## The camera's side (south, +z) stays low. Seeded from the pond: the same pond grounds the same way.

const PondWalk := preload("res://modules/ponds/pond_walk.gd")
const Art = preload("res://modules/farm/farm_art.gd")
const AREA := Rect2(-34, -52, 82, 80)   # x, z: past the farthest pinch's corners
## Two looks for the user to pick (P0_WILD_LOWPOLY=1 / 2): A fine facets, B big blocks with quieter facets.
static var STYLE := {"cell": 1.3, "shade": 0.07, "patch": 3.2} if OS.get_environment("P0_WILD_LOWPOLY") != "2" else {"cell": 2.2, "shade": 0.035, "patch": 4.6}
static var CELL_M: float = STYLE.cell
const JITTER := 0.3
const SINK_M := -0.08   # under the water
const BANK_M := 0.45    # the sand band round the water
## Warm palette (the farm's and Alcatraz's garden greens, road and rock; not the reference video's).
const MEADOW_TONES := [Color("8db04a"), Color("a6c25a"), Color("789e43"), Color("5e883b")]
const MEADOW_WEIGHTS := [0.42, 0.22, 0.22, 0.14]
static var PATCH_M: float = STYLE.patch
const PATH := Color("d7bc8a")
const PATH_EDGE := Color("c2a675")
const BANK := Color("cdb27a")
const RIM := [Color("7a9f45"), Color("678c3f"), Color("71943f")]
const ROCK := [Color("b6a189"), Color("ad9d86"), Color("c0b099"), Color("a88a5c")]
const HAZE := Color("cfd3a6")
const SPAWN := Vector2(6.125, -1.625)
## 赵云's 442 v0.1 paths (the left one, A): control points x, z per shape; width 0.76 m (Willow 0.5).
const PATHS := {
	"crescent": [[5.4, -1.9], [4.9, -0.78], [4.45, 0.32], [3.5, 0.8], [2.5, 0.95], [1.5, 0.95]],
	"gourd": [[6.07, -0.7], [5.79, 0.345], [5.53, 1.2], [4.2, 1.4], [2.9, 1.39], [1.5, 0.95]],
	"meander": [[5.95, -1.2], [5.65, -0.25], [5.35, 0.7], [5.05, 1.4], [3.25, 1.4], [1.5, 0.95]],
}

static func build(entry: Dictionary, spec: Dictionary) -> MeshInstance3D:
	var seed_value := int(entry.decoration_seed)
	var polygon := PackedVector2Array()
	for p in spec.get("polygon", []): polygon.append(Vector2(float(p[0]), float(p[1])))
	var path: Array = PATHS.get(str(spec.get("template_id", "")), [])
	var rows := int(AREA.size.y / (CELL_M * 0.866)) + 1
	var cols := int(AREA.size.x / CELL_M) + 1
	var grid: Array = []   # rows of Vector3
	for j in rows + 1:
		var row: Array = []
		for i in cols + 1:
			var x := AREA.position.x + (i + (0.5 if j % 2 == 1 else 0.0)) * CELL_M
			var z := AREA.position.y + j * CELL_M * 0.866
			var r := _hash2(i, j, seed_value)
			var p := Vector2(x + (r.x - 0.5) * 2.0 * JITTER * CELL_M, z + (r.y - 0.5) * 2.0 * JITTER * CELL_M)
			row.append(Vector3(p.x, _height(p, polygon, seed_value), p.y))
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sites := _patch_sites(seed_value)
	for j in rows:
		for i in cols:
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j][i + 1]
			var c: Vector3 = grid[j + 1][i]
			var d: Vector3 = grid[j + 1][i + 1]
			var tris := [[a, c, b], [b, c, d]] if j % 2 == 0 else [[a, c, d], [a, d, b]]
			for k in 2:
				var t: Array = tris[k]
				_face(st, t[0], t[1], t[2], _colour(t, polygon, path, sites, seed_value, i * 2 + k, j))
	var mesh := st.commit()
	var node := MeshInstance3D.new()
	node.name = "LowpolyGround"
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.metallic_specular = 0.1
	node.material_override = material
	node.add_child(_treeline(seed_value, polygon))
	return node

## The far layer's tree line: clumps of the wild's pines and round trees and the farm's trees on the terraces, west,
## north and east (the camera's side keeps low pieces only), thinning outward; none in the walk or near the water.
const TREE_ASSETS := ["wild_tree_pine", "wild_tree_round", "tree_0", "tree_1", "tree_2", "wild_tree_pine"]
static func _treeline(seed_value: int, polygon: PackedVector2Array) -> Node3D:
	var root := Node3D.new()
	root.name = "TreeLine"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 4422
	var out := {}
	var placed: Array = []
	for k in 900:
		var p := Vector2(rng.randf_range(AREA.position.x + 8, AREA.end.x - 8), rng.randf_range(AREA.position.y + 10, PondWalk.WALK.end.y + 1.0))
		var o := _outside(p)
		if o.y > 0.5 or o.x < 2.6 or o.x > 22.0: continue
		if rng.randf() > lerpf(1.0, 0.25, clampf((o.x - 3.0) / 16.0, 0.0, 1.0)): continue   # thinning outward
		if _noise(p * 0.22, seed_value ^ 31) < 0.42: continue   # clumps with gaps, not a wall
		if not polygon.is_empty() and p.distance_to(_nearest(p, polygon)) < 2.0: continue
		var crowded := false
		for q in placed:
			if p.distance_to(q) < 1.7:
				crowded = true
				break
		if crowded: continue
		placed.append(p)
		var asset: String = TREE_ASSETS[rng.randi() % TREE_ASSETS.size()]
		var scale := rng.randf_range(0.9, 1.35) * (1.0 + clampf((o.x - 6.0) / 20.0, 0.0, 0.35))
		var at := Vector3(p.x, _height(p, polygon, seed_value) - 0.05, p.y)
		if not out.has(asset): out[asset] = []
		out[asset].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * scale), at))
	for asset in out: root.add_child(Art.batch(asset, out[asset]))
	return root

static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
		var swap := b
		b = c
		c = swap
	for v in [a, c, b]:   # Godot's front faces wind clockwise
		st.set_color(colour)
		st.set_normal(n)
		st.add_vertex(v)

## Metres outside the walk (0 inside) and which side: the camera's (south) stays low.
static func _outside(p: Vector2) -> Vector2:
	var w := PondWalk.WALK
	var dx := maxf(maxf(w.position.x - p.x, p.x - w.end.x), 0.0)
	var dz := maxf(maxf(w.position.y - p.y, p.y - w.end.y), 0.0)
	return Vector2(Vector2(dx, dz).length(), 1.0 if p.y > w.end.y and dx < dz else 0.0)

static func _height(p: Vector2, polygon: PackedVector2Array, seed_value: int) -> float:
	if not polygon.is_empty() and Geometry2D.is_point_in_polygon(p, polygon): return SINK_M
	var o := _outside(p)
	if o.x <= 0.0: return 0.0
	var d := _fold_distance(p, o.x, seed_value)
	var lift := 0.0
	lift += 0.45 * clampf((d - 1.6) / 0.5, 0.0, 1.0)   # the first terrace: a hard fold
	lift += 0.85 * clampf((d - 4.6) / 0.6, 0.0, 1.0)   # the second, with rock faces
	var n := _noise(p * 0.11, seed_value)
	lift += clampf((d - 8.0) / 6.0, 0.0, 1.0) * (0.6 + 2.2 * n)   # low hills, the far layer
	lift += (_hash2(int(p.x * 7.0), int(p.y * 7.0), seed_value).x - 0.5) * 0.16 * clampf(d - 1.6, 0.0, 1.0)
	return lift * (0.35 if o.y > 0.5 else 1.0)

## The terraces' edges meander and cut the walk's corners on a slant (LOCK-34: no straight runs on screen): the
## distance out of the walk, pulled in and out by a slow noise and by a 30° grain across the bank.
static func _fold_distance(p: Vector2, d: float, seed_value: int) -> float:
	var slant := sin((p.x * cos(deg_to_rad(30.0)) + p.y * sin(deg_to_rad(30.0))) * 0.35)
	return d + (_noise(p * 0.13, seed_value ^ 17) - 0.5) * 2.6 + slant * 0.7 * clampf(d - 0.8, 0.0, 1.0)

static func _colour(t: Array, polygon: PackedVector2Array, path: Array, sites: Array, seed_value: int, i: int, j: int) -> Color:
	var a: Vector3 = t[0]
	var b: Vector3 = t[1]
	var c: Vector3 = t[2]
	var centre := (a + b + c) / 3.0
	var p := Vector2(centre.x, centre.z)
	var n := (b - a).cross(c - a).normalized().abs()
	var jitter := 1.0 + (_hash2(i, j, seed_value ^ 77).x - 0.5) * float(STYLE.shade)
	var out := _outside(p).x
	var colour: Color
	var water := INF
	if not polygon.is_empty():
		water = p.distance_to(_nearest(p, polygon)) * (-1.0 if Geometry2D.is_point_in_polygon(p, polygon) else 1.0)
	var south := _outside(p).y > 0.5
	if south and n.y < 0.975:   # the camera's side: the folds stay grass, a shade deeper
		colour = RIM[1].darkened(0.08)
	elif n.y < 0.88 or (n.y < 0.975 and out < 7.0):   # fold faces: warm rock and soil
		colour = ROCK[int(_hash2(i, j, seed_value ^ 5).y * ROCK.size())]
	elif water < BANK_M:
		colour = BANK
	elif _on_path(p, path) < 0.0:
		colour = PATH if _on_path(p, path) < -0.18 else PATH_EDGE
	elif p.distance_to(SPAWN) < 0.7 and water > 1.2:
		colour = PATH
	elif out > 0.6:
		colour = RIM[int(_noise(p * 0.3, seed_value ^ 9) * 2.99)]
		colour = colour.lerp(HAZE, clampf((out - 9.0) / 18.0, 0.0, 0.55))   # the far layer pales
	else:
		colour = MEADOW_TONES[_patch(p, sites)]
	return Color(colour.r * jitter, colour.g * jitter, colour.b * jitter)

## <0 inside the path (how far in), from its centre line less half its width.
static func _on_path(p: Vector2, path: Array) -> float:
	var best := INF
	for k in path.size() - 1:
		var a := Vector2(path[k][0], path[k][1])
		var b := Vector2(path[k + 1][0], path[k + 1][1])
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best - 0.55

static func _nearest(p: Vector2, polygon: PackedVector2Array) -> Vector2:
	var best := polygon[0]
	for k in polygon.size():
		var q := Geometry2D.get_closest_point_to_segment(p, polygon[k], polygon[(k + 1) % polygon.size()])
		if q.distance_squared_to(p) < best.distance_squared_to(p): best = q
	return best

## The meadow's colour blocks: jittered sites PATCH_M apart, each a tone; a face takes its nearest site's.
static func _patch_sites(seed_value: int) -> Array:
	var out: Array = []
	var w := PondWalk.WALK.grow(2.0)
	var gx := int(w.size.x / PATCH_M) + 1
	var gz := int(w.size.y / PATCH_M) + 1
	for j in gz:
		for i in gx:
			var r := _hash2(i + 500, j + 500, seed_value)
			var at := Vector2(w.position.x + (i + r.x) * PATCH_M, w.position.y + (j + r.y) * PATCH_M)
			var pick := _hash2(i + 900, j + 900, seed_value).x
			var tone := 0
			var acc := 0.0
			for k in MEADOW_WEIGHTS.size():
				acc += MEADOW_WEIGHTS[k]
				if pick <= acc:
					tone = k
					break
			out.append([at, tone])
	return out

static func _patch(p: Vector2, sites: Array) -> int:
	var best := 0
	var bd := INF
	for s in sites:
		var dd := p.distance_squared_to(s[0])
		if dd < bd:
			bd = dd
			best = s[1]
	return best

static func _hash2(i: int, j: int, seed_value: int) -> Vector2:
	var h := hash([i, j, seed_value])
	return Vector2(float(h & 0xffff) / 65535.0, float((h >> 16) & 0xffff) / 65535.0)

## Value noise 0–1, smooth enough for the hills' heights.
static func _noise(p: Vector2, seed_value: int) -> float:
	var i := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(i)
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var v00 := _hash2(i.x, i.y, seed_value).x
	var v10 := _hash2(i.x + 1, i.y, seed_value).x
	var v01 := _hash2(i.x, i.y + 1, seed_value).x
	var v11 := _hash2(i.x + 1, i.y + 1, seed_value).x
	return lerpf(lerpf(v00, v10, f.x), lerpf(v01, v11, f.x), f.y)

## The bank as faceted slabs (the shore option, for the user to decide: 11-05 kept the water and its stones as they
## are): the pack's flat hard rocks (pg_rock_*, warm-recoloured) along the rim, mostly on the water's side and low —
## lower still on the bank facing the camera, where the default landing must stay in sight — a chunk now and then on
## the far bank; gaps of sand between.
const SLABS := ["pg_rock_12", "pg_rock_24", "pg_rock_26", "pg_rock_28"]
const CHUNKS := ["pg_rock_13", "pg_rock_22"]
static func shore(entry: Dictionary, spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "FacetedBank"
	var rng := RandomNumberGenerator.new()
	rng.seed = int(entry.decoration_seed) ^ 1105
	var polygon := PackedVector2Array()
	for p in spec.get("polygon", []): polygon.append(Vector2(float(p[0]), float(p[1])))
	if polygon.is_empty(): return root
	var out := {}
	var put := func(asset: String, t: Transform3D) -> void:
		if not out.has(asset): out[asset] = []
		out[asset].append(t)
	var cursor := 0.0
	var next := 0.2
	var index := 0
	for k in polygon.size():
		var a := polygon[k]
		var b := polygon[(k + 1) % polygon.size()]
		var length := a.distance_to(b)
		if length < 0.0001: continue
		var tangent := (b - a) / length
		var normal := Vector2(-tangent.y, tangent.x)
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + normal * 0.04, polygon): normal = -normal
		while next < cursor + length:
			var at := a.lerp(b, (next - cursor) / length)
			var near := Vector3(normal.x, 0, normal.y).dot(Vector3(0.16, 0, 1).normalized()) > 0.08   # facing the camera
			var yaw := atan2(-tangent.y, tangent.x) + rng.randf_range(-0.25, 0.25)
			var s := rng.randf_range(0.32, 0.44) if near else rng.randf_range(0.4, 0.6)
			var flat := 0.55 if near else 0.9
			var centre := at - normal * rng.randf_range(0.12, 0.28)
			put.call(SLABS[rng.randi() % SLABS.size()], Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * flat, s)), Vector3(centre.x, -0.02, centre.y)))
			if not near and index % 4 == 1:
				var c := at - normal * 0.05 + tangent * rng.randf_range(0.3, 0.5)
				var cs := rng.randf_range(0.35, 0.5)
				put.call(CHUNKS[rng.randi() % CHUNKS.size()], Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * cs), Vector3(c.x, -0.03, c.y)))
			next += s * 2.0 + rng.randf_range(0.15, 0.6)
			index += 1
		cursor += length
	for asset in out: root.add_child(Art.batch(asset, out[asset]))
	return root
