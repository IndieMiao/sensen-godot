extends RefCounted
## The wild's ground and its woods (SGODOT-422, 盘古, the user's v7 11-09): flat painted ground — one warm grass, sand and
## path colour with soft, frayed outlines (pond_wild_ground.gdshader, from a baked distance to the water), a large soft
## light and colour wander, a pale soft band where the meadow meets the sand and the path; the walk at y 0 (navigation as
## it is), past it one rounded terrace. The bank: a sand band with a pale wet line and 3–4 groups of faceted rocks at its
## bends. The dressing (regroup): the Pandazole pack's plants in clumps, layered edges, and the pond closed in by woods
## on three sides with a trail's mouth into the south wood. Seeded from the pond: the same pond, the same ground.

const PondWalk := preload("res://modules/ponds/pond_walk.gd")
const PondWildGroundBake := preload("res://modules/ponds/pond_wild_ground_bake.gd")
const Art = preload("res://modules/farm/farm_art.gd")
const AREA := Rect2(-26, -46, 66, 64)
const CELL_M := 0.7
const SINK_M := -0.08
const SDF_ORIGIN := Vector2(-6, -22)
const SDF_EXTENT := Vector2(24, 28)
const SDF_PX := 0.25
const TERRACE_M := 0.6   # the terrace past the walk
const SAND_M := 0.85     # the sand band's width round the water
## The shader's settings (the user's v7): light, colour wander, grain, edges, the shadows' colours (linear, no sRGB).
const LOOK := {"gradient": 0.30, "sand_m": SAND_M, "vignette": 0.22, "south_dark": 0.07, "dapple": 0.095, "detail": 0.07,
	"edge_break": 0.4, "path_taper": 1.0, "big_tone": 0.13, "fine_edge": 1.0, "seam_fix": 1.0,
	"shadow_tint": Vector3(0.0, 0.05, 0.12), "shadow_tint_sand": Vector3(0.30, 0.33, 0.36),
	"shadow_cool": Vector3(0.0, 0.012, 0.03), "shadow_cool_sand": Vector3(0.0, 0.006, 0.022)}
const PATHS := {
	"crescent": [[5.4, -1.9], [4.9, -0.78], [4.45, 0.32], [3.5, 0.8], [2.5, 0.95], [1.5, 0.95]],
	"gourd": [[6.07, -0.7], [5.79, 0.345], [5.53, 1.2], [4.2, 1.4], [2.9, 1.39], [1.5, 0.95]],
	"meander": [[5.95, -1.2], [5.65, -0.25], [5.35, 0.7], [5.05, 1.4], [3.25, 1.4], [1.5, 0.95]],
}
const SPAWN := Vector2(6.125, -1.625)
## Warm palette (the farm's and Alcatraz's), sRGB (the shader's defaults are not): the grass in two shades, the terrace's
## top and side, sand, the wet line, path; the colour wander's two ends.
const COLOURS := {"grass": Color("86a74b"), "grass_far": Color("749543"), "plateau": Color("789a45"), "rock": Color("66883d"),
	"sand": Color("dcc79a"), "wet": Color("efe4c6"), "path_colour": Color("d2b98a"), "dapple_warm": Color("a3b54e"),
	"dapple_cool": Color("6f9b52"), "soft_grass": Color("a8b46b")}

const CACHE_MAX := 4   # a rebuild and the last few ponds reuse it; the memory stays bounded (under 1 MB each)
static var _CACHE := {}   # "shape hash|seed" -> [ground mesh, water distance texture], shared and never edited
# (the ground's baked textures, ~14 MB, are kept apart and only one: PondWildGroundBake)
## `trees`: the bank's tree points (the ground deepens to blue-green under them).
static func build(entry: Dictionary, spec: Dictionary, clear: Array = [], trees: Array = []) -> Node3D:
	var seed_value := int(entry.decoration_seed)
	var polygon := PackedVector2Array()
	for p in spec.get("polygon", []): polygon.append(Vector2(float(p[0]), float(p[1])))
	var root := Node3D.new()
	root.name = "WildGround"
	var ground := MeshInstance3D.new()
	ground.name = "PaintedGround"
	# the ground's mesh and its distance-to-water texture depend on the pond's shape and seed only: built once a pond
	# (周瑜 on #917: the texture alone ~98 ms; the scenery is built again when the gathering points come)
	var shape_key := "%s|%d" % [str(polygon).hash(), seed_value]
	if not _CACHE.has(shape_key):
		if _CACHE.size() >= CACHE_MAX: _CACHE.erase(_CACHE.keys()[0])   # the oldest (a Dictionary keeps insertion order)
		var distances := _water_distances(polygon)
		_CACHE[shape_key] = [_mesh(polygon, TERRACE_M, seed_value), _sdf_texture(distances), distances]
	ground.mesh = _CACHE[shape_key][0]
	root.set_meta("water_distances", _CACHE[shape_key][2])   # the shore foam's too (PondWildFoam, via PondScenery)
	var material := ShaderMaterial.new()
	material.shader = preload("res://modules/ponds/pond_wild_ground.gdshader")
	material.set_shader_parameter("water_sdf", _CACHE[shape_key][1])
	material.set_shader_parameter("sdf_origin", SDF_ORIGIN)
	material.set_shader_parameter("sdf_extent", SDF_EXTENT)
	var path: Array = PATHS.get(str(spec.get("template_id", "")), [])
	var points := PackedVector2Array()
	for q in path: points.append(Vector2(q[0], q[1]))
	while points.size() < 6: points.append(points[-1] if not points.is_empty() else SPAWN)
	material.set_shader_parameter("path_points", points)
	material.set_shader_parameter("path_count", path.size())
	var w := PondWalk.WALK
	material.set_shader_parameter("walk", Vector4(w.position.x, w.position.y, w.end.x, w.end.y))
	for key in LOOK: material.set_shader_parameter(key, LOOK[key])
	var under := PackedVector2Array()   # the ground under the bank's trees a deeper blue-green
	for t in trees: if under.size() < 8: under.append(Vector2(t.x, t.z))
	while under.size() < 8: under.append(Vector2(1e4, 1e4))
	material.set_shader_parameter("under_trees", under)
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = seed_value
	material.set_shader_parameter("seed_off", Vector2(seed_rng.randf_range(-60, 60), seed_rng.randf_range(-60, 60)))
	for key in COLOURS: material.set_shader_parameter(key, COLOURS[key])
	material.set_shader_parameter("trail_points", PackedVector2Array(TRAIL))   # the trail into the south-west wood
	material.set_shader_parameter("trail_w", 0.34)
	material.set_shader_parameter("soft_m", 2.2)   # the soft band: the grass 40 % toward the sand, a quarter less saturated (上官婉儿 on 532)
	var centre := Vector2.ZERO
	for q in polygon: centre += q
	material.set_shader_parameter("centre", centre / maxf(polygon.size(), 1.0) if not polygon.is_empty() else Vector2(6, -8))
	ground.material_override = material
	root.add_child(ground)
	# the ground baked into textures once it is in the tree (#917: GLES frame rate); this material until then / headless
	var bake := PondWildGroundBake.new()
	bake.name = "GroundBake"
	bake.ground = ground
	bake.shape_key = shape_key
	bake.area = AREA
	root.add_child(bake)
	root.add_child(_bank_rocks(entry, polygon, clear))
	return root

static func _outside(p: Vector2) -> Vector2:
	var w := PondWalk.WALK
	var dx := maxf(maxf(w.position.x - p.x, p.x - w.end.x), 0.0)
	var dz := maxf(maxf(w.position.y - p.y, p.y - w.end.y), 0.0)
	return Vector2(Vector2(dx, dz).length(), 1.0 if p.y > w.end.y and dx < dz else 0.0)

static func _height(p: Vector2, polygon: PackedVector2Array, terrace: float, seed_value: int) -> float:
	if not polygon.is_empty() and Geometry2D.is_point_in_polygon(p, polygon): return SINK_M
	var o := _outside(p)
	if o.x <= 0.0 or o.y > 0.5 or terrace <= 0.0: return 0.0   # the camera's side stays flat
	# one terrace, its edge a slow, wide curve (no straight runs, no wiggle)
	var d := o.x + (_noise(p * 0.07, seed_value) - 0.5) * 3.0
	return terrace * smoothstep(2.4, 3.2, d)

static func _mesh(polygon: PackedVector2Array, terrace: float, seed_value: int) -> ArrayMesh:
	var cols := int(AREA.size.x / CELL_M) + 1
	var rows := int(AREA.size.y / CELL_M) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rows:
		for i in cols:
			var p := Vector2(AREA.position.x + i * CELL_M, AREA.position.y + j * CELL_M)
			st.add_vertex(Vector3(p.x, _height(p, polygon, terrace, seed_value), p.y))
	for j in rows - 1:
		for i in cols - 1:
			var a := j * cols + i
			for k in [a, a + 1, a + cols, a + 1, a + cols + 1, a + cols]: st.add_index(k)
	st.generate_normals()
	return st.commit()

## Metres to the water's edge on a 0.25 m grid (<0 in the water), for the shader's rounded sand band.
static func _water_sdf(polygon: PackedVector2Array) -> ImageTexture:
	return _sdf_texture(_water_distances(polygon))

## The same distances, row by row (SDF_EXTENT / SDF_PX cells): the ground's texture and the shore foam both read them.
static func _water_distances(polygon: PackedVector2Array) -> PackedFloat32Array:
	var w := int(SDF_EXTENT.x / SDF_PX)
	var h := int(SDF_EXTENT.y / SDF_PX)
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in h:
		for x in w:
			var p := SDF_ORIGIN + (Vector2(x, y) + Vector2(0.5, 0.5)) * SDF_PX
			var d := 99.0
			if not polygon.is_empty():
				d = p.distance_to(_nearest(p, polygon))
				if Geometry2D.is_point_in_polygon(p, polygon): d = -d
			out[y * w + x] = d
	return out

static func _sdf_texture(distances: PackedFloat32Array) -> ImageTexture:
	var w := int(SDF_EXTENT.x / SDF_PX)
	var h := int(SDF_EXTENT.y / SDF_PX)
	# half float, not FORMAT_RF: 32-bit float textures are not filterable on iOS (Metal) and on many GLES3 phones (no
	# OES_texture_float_linear), so they fell back to nearest there and every sand / grass edge stepped in 0.25 m
	# squares (the user's 0.3.4 (2) shots, bot 589 / 590); 16-bit float filters everywhere, a few mm off at these values
	var img := Image.create_empty(w, h, false, Image.FORMAT_RH)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(distances[y * w + x], 0, 0))
	return ImageTexture.create_from_image(img)

static func _nearest(p: Vector2, polygon: PackedVector2Array) -> Vector2:
	var best := polygon[0]
	for k in polygon.size():
		var q := Geometry2D.get_closest_point_to_segment(p, polygon[k], polygon[(k + 1) % polygon.size()])
		if q.distance_squared_to(p) < best.distance_squared_to(p): best = q
	return best

## The opening's action keys' own ground (#906's measure: Fern x 8.84–11.60, z −2.88–1.85; Willow / Clover x 7.89–10.64,
## z −2.64–2.10), 0.5 m out, and on to the screen's bottom (a tall thing below them stands up over them): nothing tall.
const KEY_ZONE := Rect2(7.4, -3.4, 4.7, 9.9)
## The bank's rock groups (the user on v5: "这个石头没什么结构, 过于平"): each a chunky rock, a pillar and a small one, high
## and low, upright, five tones by slope and side, moss only on the upper top faces (上官婉儿: the reference's pale grey
## pillars).
const ROCKS_BIG := ["wild_pz_rock_27", "wild_pz_rock_08", "wild_pz_rock_16"]
const ROCKS_PILLAR := ["wild_pz_rock_19", "wild_pz_rock_30", "wild_pz_rock_21"]
const ROCKS_SMALL := ["wild_pz_rock_13", "wild_pz_rock_22", "wild_pz_rock_29"]
## 3–4 groups at the bank's bends, none on the bank in front of the spawn (the opening's cast), the whole group ≥ 4 m off
## a gathering point (read as gatherable), none behind the keys (KEY_ZONE); a ring of blades hides each rock's foot.
static func _bank_rocks(entry: Dictionary, polygon: PackedVector2Array, clear: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "BankRockGroups"
	if polygon.size() < 8: return root
	var rng := RandomNumberGenerator.new()
	rng.seed = int(entry.decoration_seed) ^ 1109
	var n := polygon.size()
	var bends: Array = []
	for k in n:
		var a := polygon[(k - 4 + n) % n]
		var b := polygon[k]
		var c := polygon[(k + 4) % n]
		bends.append([absf((b - a).normalized().angle_to((c - b).normalized())), k])
	bends.sort_custom(func(x, y): return x[0] > y[0])
	var picked: Array = []
	for item in bends:
		var at: Vector2 = polygon[item[1]]
		if at.distance_to(SPAWN) < 4.0: continue
		if clear.any(func(c): return at.distance_to(Vector2(c.x, c.z)) < 4.0): continue
		if KEY_ZONE.has_point(at): continue
		if picked.any(func(q): return q.distance_to(at) < 4.5): continue
		picked.append(at)
		if picked.size() >= 4: break
	var out := {}
	var contacts: Array = []   # Vector3(x, z, radius) a rock: where the shore foam rings (PondWildFoam)
	for at in picked:
		var k := 0
		for i in n:
			if polygon[i] == at: k = i
		var tangent := (polygon[(k + 1) % n] - polygon[(k - 1 + n) % n]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		if Geometry2D.is_point_in_polygon(at + normal * 0.1, polygon): normal = -normal
		var yaw := atan2(-tangent.y, tangent.x)
		rng.randf_range(0.6, 0.75)   # three draws the earlier flat slabs' sizes took: the seeds' groups stay as approved
		rng.randf_range(0.45, 0.55)
		rng.randf_range(0.5, 0.65)
		var pieces := [[ROCKS_BIG, 0.0, -0.1, rng.randf_range(0.62, 0.75)], [ROCKS_PILLAR, 0.72, 0.05, rng.randf_range(0.6, 0.75)],
			[ROCKS_SMALL, -0.7, 0.12, rng.randf_range(0.42, 0.55)]]
		for piece in pieces:
			var list: Array = piece[0]
			var p: Vector2 = at + tangent * float(piece[1]) + normal * float(piece[2])
			var s := float(piece[3])
			var asset: String = list[rng.randi() % list.size()]
			var sink := -0.12 * s   # half sunk
			for t in rng.randi_range(4, 6):   # a ring of grass hides the contact line
				var f: Vector2 = p + Vector2.from_angle(rng.randf() * TAU) * s * rng.randf_range(0.6, 0.85)
				var g: String = GROUND_GRASS[rng.randi() % GROUND_GRASS.size()]
				if not out.has(g): out[g] = []
				out[g].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.5, 0.8)), Vector3(f.x, -0.02, f.y)))
			if not out.has(asset): out[asset] = []
			out[asset].append(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.4, 0.4)).scaled(Vector3(s, s, s)), Vector3(p.x, sink, p.y)))
			contacts.append(Vector3(p.x, p.y, footprint(asset) * s))
	for asset in out: root.add_child(Art.batch(asset, out[asset]))
	root.set_meta("contacts", contacts)
	return root

## A piece's radius on the ground at scale 1: its mesh's box, the mean of its half sizes, a little in from the box's
## corners (the pack's rocks are rounded); 0.3 m when the piece is not in this build.
static func footprint(asset: String) -> float:
	var mesh: Mesh = Art.mesh_for(asset) if ResourceLoader.exists(Art.ROOT + asset + ".glb") else null
	if mesh == null: return 0.3
	var box := mesh.get_aabb()
	return (box.size.x + box.size.z) * 0.25 * 0.9

static func _hash2(i: int, j: int, seed_value: int) -> float:
	return float(hash([i, j, seed_value]) & 0xffff) / 65535.0

static func _noise(p: Vector2, seed_value: int) -> float:
	var i := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(i)
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	return lerpf(lerpf(_hash2(i.x, i.y, seed_value), _hash2(i.x + 1, i.y, seed_value), f.x),
		lerpf(_hash2(i.x, i.y + 1, seed_value), _hash2(i.x + 1, i.y + 1, seed_value), f.x), f.y)

## The wild's dressing (PondWildProps.layout's) made the woods' (上官婉儿 on v2–v7): the scattered flowers, clover,
## pebbles and tufts go; the bank's trees become the pack's; the pack's plants in clumps round the meadow and the
## opening; layered edges; the opening's bushes leafy; the woods; every plant rooted. The trees, the corner logs and the
## cattails stay.
const CRUMBS := ["wild_flower_white", "wild_flower_yellow", "wild_flower_lilac", "wild_clover", "wild_pebbles_a", "wild_pebbles_b", "grass_clump"]
const MEADOW_FREE := Rect2(-2.8, -18.5, 17.6, 26.0)
static func regroup(layout: Dictionary, entry: Dictionary, spec: Dictionary, clear: Array) -> Dictionary:
	var out := {}
	for asset in layout:
		if asset not in CRUMBS: out[asset] = layout[asset]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(entry.decoration_seed) ^ 4221
	var polygon := PackedVector2Array()
	for p in spec.get("polygon", []): polygon.append(Vector2(float(p[0]), float(p[1])))
	var band := SAND_M
	var path: Array = PATHS.get(str(spec.get("template_id", "")), [])
	var free := func(p: Vector2) -> bool:
		# on the meadow (no collision: past the walk is fine), never behind the keys
		if not MEADOW_FREE.has_point(p) or KEY_ZONE.has_point(p): return false
		if polygon.is_empty() or Geometry2D.is_point_in_polygon(p, polygon): return false
		if p.distance_to(_nearest(p, polygon)) < band + 0.15: return false   # on the sand
		if PondScenery._near(Vector3(p.x, 0, p.y), clear): return false
		if p.distance_to(SPAWN + Vector2(0, 0.5)) < 1.2: return false   # the player's feet at the spawn
		for k in path.size() - 1:
			var a := Vector2(path[k][0], path[k][1])
			var b := Vector2(path[k + 1][0], path[k + 1][1])
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < 0.6: return false   # on the path
		return true
	var centres: Array = []
	var tries := 0
	while centres.size() < 2 and tries < 600:   # just outside the sand band, on the opening's side of the pond
		tries += 1
		var c := Vector2(rng.randf_range(-1.5, 13.5), rng.randf_range(-12.0, 0.5))
		if polygon.is_empty(): break
		var d := c.distance_to(_nearest(c, polygon))
		if Geometry2D.is_point_in_polygon(c, polygon) or d < band + 0.5 or d > band + 1.1: continue
		if not free.call(c) or centres.any(func(o): return o.distance_to(c) < 4.0): continue
		centres.append(c)
	tries = 0
	while centres.size() < 4 and tries < 600 and path.size() > 1:   # beside the path
		tries += 1
		var k := rng.randi_range(0, path.size() - 2)
		var a := Vector2(path[k][0], path[k][1])
		var b := Vector2(path[k + 1][0], path[k + 1][1])
		var t := a.lerp(b, rng.randf())
		var side := (b - a).normalized().orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		var c := t + side * rng.randf_range(1.0, 1.4)
		if not free.call(c) or centres.any(func(o): return o.distance_to(c) < 3.0): continue
		centres.append(c)
	# the meadow's bushes (the bank's and the clumps') wait aside until the edges are placed, then join the same kinds'
	# lists after the edges' own — the order the opening's leafy swap draws in
	var bushes := {}
	_trees(out, bushes, rng)
	_clumps(out, rng, free, clear)
	_plants(out, bushes, rng, centres, free, polygon, band, layout, clear)
	_edges(out, bushes, rng, free, clear, polygon, band)
	for asset in bushes:
		if not out.has(asset): out[asset] = []
		out[asset].append_array(bushes[asset])
	_opening_leafy(out, rng, clear)
	_forest(out, rng, clear, polygon, band)
	return _rooted(out, rng)

## The packs' grass, flowers and small bushes in clumps — a small bush, 2–3 tufts and 2–3 flowers of one kind — on the
## clump centres, at the bank trees' feet, and tufts along the sand's edge; the open middle and the keys' back left clear.
const TUFTS := ["wild_pz_grass_24", "wild_pz_grass_40", "wild_pz_grass_41"]   # leafy round tufts (the spiky one read too sharp)
const PACK_FLOWERS := ["wild_pz_flower_20", "wild_pz_flower_23", "wild_pz_flower_26"]
const PACK_BUSHES := ["wild_pz_bush_05", "wild_pz_bush_07", "wild_pz_bush_11", "wild_pz_bush_15"]   # the lighter conversion (the user on v5: "这个植被颜色过深")
const TUFT_CLEAR_M := 2.2
static func _plants(out: Dictionary, bushes: Dictionary, rng: RandomNumberGenerator, centres: Array, free: Callable,
		polygon: PackedVector2Array, band: float, layout: Dictionary, clear: Array) -> void:
	var put := func(asset: String, p: Vector2, s: float) -> void:
		# a leafy tuft reads like Wild Herb (不知火舞 on v3): near any gathering point it is a flower instead
		if asset in TUFTS and clear.any(func(c): return p.distance_to(Vector2(c.x, c.z)) < TUFT_CLEAR_M):
			asset = PACK_FLOWERS[rng.randi() % PACK_FLOWERS.size()]
			s = minf(s, 0.9)
		if asset in TUFTS and p.distance_to(SPAWN) < 1.4: return   # nothing leafy behind the player's head at the spawn
		var to: Dictionary = bushes if asset in PACK_BUSHES else out
		if not to.has(asset): to[asset] = []
		to[asset].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * s), Vector3(p.x, 0.0, p.y)))
	var feet: Array = []
	for asset in layout:
		if str(asset).begins_with("wild_tree"):
			for t in layout[asset]: feet.append(Vector2(t.origin.x, t.origin.z))
	# the opening sees the ground round the spawn, left of the keys: clumps there (上官婉儿 on v3: 4–6 in sight), by the
	# path, on the sand's edge and at the trees' feet first; then a few more round the meadow
	var spots: Array = []
	# the opening's ground in screen terms from the spawn (14.5° yaw; ~54 px a metre across, ~36 down the ground): from
	# 1.8 m left to 2.4 m right of the player and 0.6–5.2 m down toward the quick bar, the keys' corner left out
	var right := Vector2(cos(deg_to_rad(14.5)), -sin(deg_to_rad(14.5)))
	var down := Vector2(sin(deg_to_rad(14.5)), cos(deg_to_rad(14.5)))
	var tries := 0
	while spots.size() < 4 and tries < 6000:
		tries += 1
		# first two up by the player and the water (the sand's outer edge, the rocks' and trees' feet), then the lower
		# half (上官婉儿: not all crowded down by the keys)
		var upper := spots.size() < 2 and tries < 1500   # a crowded upper half (Fern: two points by the spawn) gives way
		var u := rng.randf_range(-1.8, 0.9)   # right of this the ⇄ / main key column: clean, also pinched in
		var v := rng.randf_range(-2.4, 0.3) if upper else rng.randf_range(1.2, 5.0)
		var c := SPAWN + right * u + down * v
		if not free.call(c) or KEY_ZONE.has_point(c) or spots.any(func(o): return o.distance_to(c) < 1.35): continue
		spots.append(c)
	for c in centres + feet:
		if spots.size() >= 9: break
		if free.call(c) and not spots.any(func(o): return o.distance_to(c) < 1.6): spots.append(c)
	for c in spots:
		var flower: String = PACK_FLOWERS[rng.randi() % PACK_FLOWERS.size()]
		var n := rng.randi_range(4, 7)
		if rng.randf() < 0.55 and not KEY_ZONE.has_point(c) and (c - SPAWN).dot(right) < -0.6:   # bushes well left of the keys, even close up
			put.call(PACK_BUSHES[rng.randi() % PACK_BUSHES.size()], c, rng.randf_range(0.6, 0.85))   # the clump's tall one
			n -= 1
		for i in n:
			var p: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 0.7)
			if not free.call(p) or (p - SPAWN).dot(right) > 1.0: continue   # nothing in the keys' column, flowers nor tufts
			if rng.randf() < 0.6: put.call(TUFTS[rng.randi() % TUFTS.size()], p, rng.randf_range(0.85, 1.15))
			else: put.call(flower, p, rng.randf_range(0.75, 0.9))
	# tufts along the sand's edge, sparse, on the grass side
	if not polygon.is_empty():
		var n := polygon.size()
		var step := 0
		for k in range(0, n, 3):
			var a := polygon[k]
			var b := polygon[(k + 1) % n]
			var normal := (b - a).normalized().orthogonal()
			if Geometry2D.is_point_in_polygon(a + normal * 0.1, polygon): normal = -normal
			step += 1
			if (step % 3) != 0 or rng.randf() < 0.35: continue
			var p := a + normal * (band + rng.randf_range(0.2, 0.45))
			if free.call(p): put.call(TUFTS[rng.randi() % TUFTS.size()], p, rng.randf_range(0.5, 0.7))

## The bank's trees (the user: thick outside, thin by the water, the opening clear; pines with a clear structure —
## 上官婉儿 on the pick): only the far bank's stay, as round crowns (PondScenery.tree_points drops the sides', so their
## trunks walk again; the sides' four a low bush and stone clump on the same spot); beyond the walk, three rows thickening
## outward — pines about 65 % (Tree_01, Tree_04 the last row), the round Tree_20 the rest — and none on the camera's
## side. A tuft ring at every trunk that can be seen. No Tree_15 nor Tree_19 (the user on v5, 530: "这个树换掉").
const PINES := ["wild_pz_pine_01", "wild_pz_pine_01", "wild_pz_pine_04"]
const ROUND := "wild_pz_tree_20"
const PINE_SCALE := {"wild_pz_pine_01": 0.95, "wild_pz_pine_04": 0.55, "wild_pz_tree_20": 0.8}   # ~3.5–4 m
const GROUND_GRASS := ["wild_pz_foot_leafy"]   # mid green, short and round (上官婉儿 on v5)
## The round crown: one draw, as when there were two kinds to pick from (the seeds' woods stay as approved).
static func _round(rng: RandomNumberGenerator) -> String:
	rng.randi()
	return ROUND

static func _trees(out: Dictionary, bushes: Dictionary, rng: RandomNumberGenerator) -> void:
	var at: Array = []
	for asset in ["wild_tree_pine", "wild_tree_round"]:
		for t in out.get(asset, []): at.append(t.origin)
		out.erase(asset)
	var put := func(asset: String, p: Vector3, s: float) -> void:
		var to: Dictionary = bushes if asset in PACK_BUSHES else out
		if not to.has(asset): to[asset] = []
		to[asset].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * s), p))
	var feet := func(p: Vector3, n: int) -> void:
		for k in n:
			var f: Vector3 = p + Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(0.25, 0.6)
			put.call(GROUND_GRASS[rng.randi() % GROUND_GRASS.size()], Vector3(f.x, -0.02, f.z), rng.randf_range(0.5, 0.8))
	for p in at:
		if p.z < -15.0:   # the far bank's two stay trees, round crowns
			put.call(_round(rng), p, 0.5 * rng.randf_range(0.88, 1.12))
			feet.call(p, 4)
			continue
		# the sides' four (by the water, at the opening's edges) become a low bush and stone clump on the same spot —
		# their trunks still block as before (上官婉儿: the walk mask stays the server's), nothing tall in the way
		put.call(["wild_pz_bush_05", "wild_pz_bush_15"][rng.randi() % 2], p + Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)), rng.randf_range(0.7, 0.85))
		for k in rng.randi_range(2, 3):
			var q: Vector3 = p + Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(0.4, 0.7)
			put.call(["wild_pz_rock_13", "wild_pz_rock_22", "wild_pz_bush_11"][rng.randi() % 3], Vector3(q.x, -0.06, q.z), rng.randf_range(0.28, 0.4))   # no flat stones
		feet.call(p, 5)
	var w := PondWalk.WALK
	for row in 3:
		var out_m := 1.6 + row * 2.4
		var step_lo := 2.6 - row * 0.7   # denser outward
		var sides := [[Vector2(w.position.x - out_m, w.end.y - 2.0 - row * 1.5), Vector2(w.position.x - out_m, w.position.y - out_m)],
			[Vector2(w.position.x - out_m, w.position.y - out_m), Vector2(w.end.x + out_m, w.position.y - out_m)],
			[Vector2(w.end.x + out_m, w.position.y - out_m), Vector2(w.end.x + out_m, w.end.y - 4.0 - row * 1.5)]]
		for r in sides:
			var a: Vector2 = r[0]
			var b: Vector2 = r[1]
			var length := a.distance_to(b)
			var t := rng.randf_range(0.0, 1.2)
			while t < length:
				if rng.randf() < 0.55 + row * 0.15:
					var q := a.lerp(b, t / length) + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
					var pine := rng.randf() < 0.65
					var asset: String = PINES[rng.randi() % PINES.size()] if pine else _round(rng)
					if pine and row == 2: asset = "wild_pz_pine_04"   # the tall slim one is the last row
					var s: float = float(PINE_SCALE.get(asset, 0.5)) * rng.randf_range(0.85, 1.15)
					put.call(asset, Vector3(q.x, 0.0, q.y), s)
					if row == 0: feet.call(Vector3(q.x, 0, q.y), 3)
				t += rng.randf_range(step_lo, step_lo + 1.1)

## Small plants in clumps (the user: in clusters, a natural spread; 上官婉儿: dense in the middle, sparse out, one or two
## big ones with small ones, uneven gaps): up to 10 clumps on the open meadow, the opening's first; each a tuft heart
## with flowers and blades round it, falling off outward. No loose single pieces, no leaves.
static func _clumps(out: Dictionary, rng: RandomNumberGenerator, free: Callable, clear: Array) -> void:
	var right := Vector2(cos(deg_to_rad(14.5)), -sin(deg_to_rad(14.5)))
	var down := Vector2(sin(deg_to_rad(14.5)), cos(deg_to_rad(14.5)))
	var spots: Array = []
	var tries := 0
	while spots.size() < 10 and tries < 6000:
		tries += 1
		var opening := spots.size() < 3 and tries < 3000
		var c := SPAWN + right * rng.randf_range(-2.4, 0.8) + down * rng.randf_range(1.2, 5.2) if opening \
			else Vector2(rng.randf_range(-2.2, 14.2), rng.randf_range(-15.6, 1.2))
		var gap := rng.randf_range(1.8, 4.0)   # uneven spacing
		if KEY_ZONE.has_point(c) or not free.call(c) or spots.any(func(o): return o.distance_to(c) < gap): continue
		spots.append(c)
	var put := func(asset: String, p: Vector2, s: float) -> void:
		if not out.has(asset): out[asset] = []
		out[asset].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * s), Vector3(p.x, -0.03, p.y)))
	for c in spots:
		var flower: String = PACK_FLOWERS[rng.randi() % PACK_FLOWERS.size()]
		var big := rng.randi_range(1, 2)
		for i in big: put.call(TUFTS[rng.randi() % TUFTS.size()], c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 0.2), rng.randf_range(0.75, 0.95))
		for i in rng.randi_range(5, 9):
			var r := 0.18 + 0.75 * pow(rng.randf(), 1.6)   # dense in the middle, sparse outward
			var p: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * r
			if not free.call(p) or KEY_ZONE.has_point(p): continue
			var roll := rng.randf()
			if roll < 0.4: put.call(GROUND_GRASS[rng.randi() % GROUND_GRASS.size()], p, rng.randf_range(0.5, 0.8))
			elif roll < 0.75 and not clear.any(func(q): return p.distance_to(Vector2(q.x, q.z)) < 2.2): put.call(flower, p, rng.randf_range(0.7, 0.9))
			elif rng.randf() < 0.5: put.call("wild_pz_softrock_10", p, rng.randf_range(0.14, 0.22))   # a pebble, not a boulder
			else: put.call("wild_pz_grass_41", p, rng.randf_range(0.45, 0.6))

## Rooting (the user: the near plants grounded): every flower, tuft and bush sunk 3 cm, each flower with a rosette of
## flat leaves at its foot so the stem goes into leaves, not into air.
static var CONTACTS: Array = []   # the plants' feet, for the ground's contact darkening (PondScenery sets it)
static func _rooted(out: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	CONTACTS.clear()
	var add: Array = []
	for asset in out:
		var a := str(asset)
		if not (a.begins_with("wild_pz_flower") or a.begins_with("wild_pz_grass") or a.begins_with("wild_pz_bush")): continue
		var list: Array = out[asset]
		for k in list.size():
			var t: Transform3D = list[k]
			t.origin.y = minf(t.origin.y, -0.03)
			list[k] = t
			if a.begins_with("wild_pz_flower"):   # a rosette of flat leaves round the stem: it grows out of them, its shadow on them
				add.append(["wild_pz_rosette", Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * rng.randf_range(0.32, 0.42)), Vector3(t.origin.x, 0.006, t.origin.z))])
			CONTACTS.append(Vector2(t.origin.x, t.origin.z))
	for a in add:
		if not out.has(a[0]): out[a[0]] = []
		out[a[0]].append(a[1])
	return out

## The 64 plant feet nearest the spawn, for the ground's contact darkening (a patch ~10 % darker under each).
static func contact_points() -> PackedVector2Array:
	var pts := CONTACTS.duplicate()
	pts.sort_custom(func(a, b): return a.distance_squared_to(SPAWN) < b.distance_squared_to(SPAWN))
	var out := PackedVector2Array()
	for k in mini(64, pts.size()): out.append(pts[k])
	while out.size() < 64: out.append(Vector2(1e4, 1e4))
	return out

## Layered edges (the user on v5: gaps are fine but no large empty ground in view, and the scene's edges with trees,
## plants and stones so it reads in depth; 上官婉儿: true at the opening and at the farthest 0.68, crowns cut by the
## screen's edge in front). Three bands, in screen terms from the spawn (14.5° yaw):
## - the front (the camera's side, past the walk's south edge — no trunk in the walk, the walk mask the same): trees
##   down the left and below the quick bar, crowns half off screen; bushes and stones between; nothing tall under the
##   keys or below them (KEY_ZONE), only low blades and pebbles there;
## - the sides: a bush-and-stone clump every ~2.5 m down the left edge and on the right between the water and ⇄;
## - the lower meadow (between the spawn and the front): a few more clumps so no stretch of plain grass is wider than
##   ~3 m on screen.
## `bushes`: the meadow's bushes not yet joined to `out` (a clump keeps off them too).
const EDGE_TREES := ["wild_pz_tree_20", "wild_pz_pine_01", "wild_pz_pine_01", "wild_pz_pine_04"]
const EDGE_BUSHES := ["wild_pz_bush_05", "wild_pz_bush_15", "wild_pz_bush_11", "wild_pz_bush_07"]
const EDGE_STONES := ["wild_pz_rock_13", "wild_pz_rock_22", "wild_pz_rock_29"]   # small, but with facets (the user: no flat stones)
const TALL_OR_LEAFY := ["wild_pz_bush", "wild_pz_grass", "wild_pz_tree", "wild_pz_pine"]
static func _edges(out: Dictionary, bushes: Dictionary, rng: RandomNumberGenerator, free: Callable, clear: Array, polygon: PackedVector2Array, band: float) -> void:
	var right := Vector2(cos(deg_to_rad(14.5)), -sin(deg_to_rad(14.5)))
	var down := Vector2(sin(deg_to_rad(14.5)), cos(deg_to_rad(14.5)))
	var w := PondWalk.WALK
	var put := func(asset: String, p: Vector2, s: float, y := 0.0) -> void:
		if not out.has(asset): out[asset] = []
		out[asset].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y)))
	var on_meadow := func(p: Vector2) -> bool:   # free, but the front band past the walk counts too
		if KEY_ZONE.has_point(p) or Geometry2D.is_point_in_polygon(p, polygon): return false
		if not polygon.is_empty() and p.distance_to(_nearest(p, polygon)) < band + 0.15: return false
		if PondScenery._near(Vector3(p.x, 0, p.y), clear): return false
		return p.y > w.end.y + 0.3 or free.call(p)
	var clump := func(c: Vector2, big: bool) -> void:   # a bush heart, 1–2 stones, blades and a flower round it
		put.call(EDGE_BUSHES[rng.randi() % (2 if big else EDGE_BUSHES.size())], c, rng.randf_range(0.85, 1.15) if big else rng.randf_range(0.6, 0.85), -0.03)
		for k in rng.randi_range(1, 2):
			var q: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.45, 0.8)
			if on_meadow.call(q): put.call(EDGE_STONES[rng.randi() % EDGE_STONES.size()], q, rng.randf_range(0.24, 0.36), -0.06)
		for k in rng.randi_range(3, 5):
			var q: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.35, 0.9)
			if not on_meadow.call(q): continue
			if rng.randf() < 0.3 and not clear.any(func(g): return q.distance_to(Vector2(g.x, g.z)) < 2.2):
				put.call(PACK_FLOWERS[rng.randi() % PACK_FLOWERS.size()], q, rng.randf_range(0.7, 0.85))
			else: put.call("wild_pz_foot_leafy", q, rng.randf_range(0.5, 0.8), -0.02)
	# the front: trees past the walk's south edge, left of the keys' column (screen u < 0.4 m), a crown every ~2.2 m
	var x := w.position.x - 1.0
	while x < KEY_ZONE.position.x - 0.6:
		var p := Vector2(x + rng.randf_range(-0.4, 0.4), w.end.y + rng.randf_range(1.2, 3.4))
		# straight below the player or a gathering point a crown would stand up over them: a bush clump there instead
		if absf(p.x - SPAWN.x) < 1.8 or PondScenery._in_front(Vector3(p.x, 0, p.y), clear):
			if on_meadow.call(p): clump.call(p, true)
		elif on_meadow.call(p):
			var asset: String = EDGE_TREES[rng.randi() % EDGE_TREES.size()]
			put.call(asset, p, float(PINE_SCALE.get(asset, 0.5)) * rng.randf_range(0.8, 1.05))
			for k in 3: put.call("wild_pz_foot_leafy", p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 0.6), rng.randf_range(0.5, 0.8), -0.02)
		x += rng.randf_range(1.8, 2.6)
	# beyond the keys on the right (past the walk's east edge) the same, so the farthest zoom's right edge is not bare
	for z in [-9.0, -6.5, -4.0]:
		var p := Vector2(w.end.x + rng.randf_range(0.8, 2.0), z + rng.randf_range(-0.6, 0.6))
		if on_meadow.call(p):
			var asset: String = EDGE_TREES[rng.randi() % EDGE_TREES.size()]
			put.call(asset, p, float(PINE_SCALE.get(asset, 0.5)) * rng.randf_range(0.8, 1.05))
	# the front's undergrowth: clumps between the trees and along the walk's south edge
	for k in 7:
		var p := Vector2(rng.randf_range(w.position.x - 0.5, KEY_ZONE.position.x - 0.3), w.end.y + rng.randf_range(-0.6, 2.4))
		if on_meadow.call(p): clump.call(p, rng.randf() < 0.5)
	# under and below the keys: low clumps only (#906 / 上官婉儿: nothing tall behind the buttons) — the opening hides them
	# behind the keys, the farthest zoom sees this ground up from ⇄ (the user circled it bare): blades, short tufts, a
	# small flower, in loose groups; no pebbles (tiny dark dots read as dirt)
	var groups := 0
	var gtries := 0
	while groups < 10 and gtries < 300:
		gtries += 1
		var c := Vector2(rng.randf_range(KEY_ZONE.position.x, KEY_ZONE.end.x), rng.randf_range(KEY_ZONE.position.y, KEY_ZONE.end.y))
		if Geometry2D.is_point_in_polygon(c, polygon) or (not polygon.is_empty() and c.distance_to(_nearest(c, polygon)) < band + 0.3): continue
		if PondScenery._near(Vector3(c.x, 0, c.y), clear) or c.distance_to(SPAWN) < 1.4: continue
		groups += 1
		for k in rng.randi_range(4, 7):
			var q: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 0.55) * (1.0 if k else 0.0)
			if Geometry2D.is_point_in_polygon(q, polygon): continue
			var roll := rng.randf()
			if roll < 0.6: put.call("wild_pz_foot_leafy", q, rng.randf_range(0.55, 0.85), -0.02)
			elif roll < 0.85: put.call("wild_pz_grass_41", q, rng.randf_range(0.4, 0.5), -0.03)
			elif not clear.any(func(g): return q.distance_to(Vector2(g.x, g.z)) < 2.2): put.call(PACK_FLOWERS[rng.randi() % PACK_FLOWERS.size()], q, rng.randf_range(0.6, 0.7), -0.03)
	# the sides: down the left edge of the farthest view, and on the right between the water and ⇄
	var lefts: Array = []
	for v in [-4.0, -1.5, 1.0, 3.5]:
		lefts.append(SPAWN + right * rng.randf_range(-4.6, -3.4) + down * (v + rng.randf_range(-0.5, 0.5)))
	var rights: Array = []
	for v in [-5.0, -3.2]:
		rights.append(SPAWN + right * rng.randf_range(2.6, 4.2) + down * (v + rng.randf_range(-0.4, 0.4)))
	for z in [-7.2, -5.4, -3.9]:   # the right bank above the keys (the user circled the bare ground up from ⇄)
		rights.append(Vector2(rng.randf_range(11.4, 14.0), z + rng.randf_range(-0.4, 0.3)))
	for c in lefts + rights:
		if on_meadow.call(c): clump.call(c, true)
	# the lower meadow between the spawn and the front: no plain stretch wider than ~3 m on screen
	var tries := 0
	var placed := 0
	while placed < 4 and tries < 400:
		tries += 1
		var c := SPAWN + right * rng.randf_range(-3.0, 1.2) + down * rng.randf_range(1.6, 4.4)
		if c.distance_to(SPAWN) < 1.6 or not on_meadow.call(c): continue
		var near := false
		for d in [out, bushes]:
			for asset in d:
				if near: break
				if not TALL_OR_LEAFY.any(func(prefix): return str(asset).begins_with(prefix)): continue
				for t in d[asset]:
					if Vector2(t.origin.x, t.origin.z).distance_to(c) < 1.5:
						near = true
						break
		if near: continue
		clump.call(c, false)
		placed += 1

## The opening's bushes (不知火舞 on v6, for the user's "这个植被颜色过深"): on the opening screen the big round faceted
## bushes read heavy even lightened — there they become pale leafy clumps (the packs' broad tufts, a size up); within
## TUFT_CLEAR_M of a gathering point a leafy tuft reads as Wild Herb, so a smaller bush stays there; past the opening
## (the farthest zoom's edges) the bushes stay.
static func _opening_leafy(out: Dictionary, rng: RandomNumberGenerator, clear: Array) -> void:
	var right := Vector2(cos(deg_to_rad(14.5)), -sin(deg_to_rad(14.5)))
	var down := Vector2(sin(deg_to_rad(14.5)), cos(deg_to_rad(14.5)))
	for asset in out.keys():
		if not str(asset).begins_with("wild_pz_bush_"): continue
		var keep: Array = []
		for t in out[asset]:
			var p := Vector2(t.origin.x, t.origin.z)
			var u := (p - SPAWN).dot(right)
			var v := (p - SPAWN).dot(down)
			var s: float = (t as Transform3D).basis.get_scale().x
			if absf(u) > 3.7 or v < -6.5 or v > 6.0:
				keep.append(t)
				continue
			if clear.any(func(c): return p.distance_to(Vector2(c.x, c.z)) < TUFT_CLEAR_M):
				keep.append(Transform3D((t as Transform3D).basis.scaled(Vector3.ONE * 0.7), t.origin))
				continue
			var leafy: String = ["wild_pz_grass_40", "wild_pz_grass_24"][rng.randi() % 2]
			if not out.has(leafy): out[leafy] = []
			out[leafy].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * clampf(s * 1.3, 0.95, 1.35)), Vector3(p.x, -0.03, p.y)))
		out[asset] = keep

## The woods (the user on v6, 552: "画面的边缘仍然显得空 … 被树林包围的感觉，不要担心被前面的 UI 遮挡，再加一些树木"; 奕星 /
## 上官婉儿: three sides closed, keys and HUD may have crowns behind them, the walk and the lines of sight kept).
## Measured: the opening's bottom edge stands on z 4.6–6.5, the farthest zoom's on z 9.2–11.9, all past the walk's
## south edge (z 1.5) — so the woods there are real trees, trunks outside the walk; the screen's left / right edges at
## mid height are inside the walk (x ~1–3.5), so there a wood's edge of mixed bushes, upright stones and the outer
## trees' crowns — no trunk anyone walks through, the walk mask the same.
## - the south wood: rows z 2.4 … 12, ~1.7–2.3 m apart, staggered, x −5 … 19; the near rows layered pines and Tree_20,
##   the far ones (the screen's very bottom) the low-poly Pine_03 / Tree_20 13 % darker (上官婉儿: darker, not black);
## - west / east: three rows just past the walk's sides, and one more ring beyond the far bank;
## - the woods' edge inside the walk down both sides of the screen: 2–3 bush kinds high and low, a pillar stone now and
##   then, a few metres apart, never a hedge;
## - lines of sight: a tall tree whose crown would stand over the player at the spawn or a gathering stand on screen
##   becomes a low bush there.
const FOREST_NEAR := ["wild_pz_pine_01", "wild_pz_pine_03", "wild_pz_tree_20", "wild_pz_pine_01", "wild_pz_pine_03"]   # pines most; the round crowns read big and bright up close
const FOREST_FAR := ["wild_pz_pine_03_dk", "wild_pz_tree_20_dk", "wild_pz_pine_03_dk", "wild_pz_pine_01_dk"]
const FOREST_SCALE := {"wild_pz_pine_01": 0.95, "wild_pz_pine_01_dk": 0.95, "wild_pz_pine_03": 0.78, "wild_pz_pine_03_dk": 0.78,
	"wild_pz_pine_03_lt": 0.78, "wild_pz_tree_20": 0.8, "wild_pz_tree_20_dk": 0.8, "wild_pz_tree_20_lt": 0.8, "wild_pz_pine_04": 0.55}
## (上官婉儿: the near wood one green carpet): along each near row a sunlit crown, then plain, a deep pine, plain —
## light, dark, light; the far rows stay the darker kinds
const RHYTHM := [["wild_pz_tree_20_lt", "wild_pz_pine_03_lt"], [], ["wild_pz_pine_01_dk"], [], []]
## The adventure (the user: "被树林包围的水塘的感觉，有冒险感的场景"; 奕星: depth, a trail's mouth, fallen logs, big stones
## — something in the woods to find): a narrow trail runs from the spawn's sand down-left into the south wood (TRAIL, the
## shader paints it; trees and small pieces keep off it), its mouth at z ~1.9 just past the walk — in sight above the
## quick bar, left of the keys, on the opening and the farthest zoom (上官婉儿) — framed by a mossy log / big stone each
## side and two trees, the trail on into the wood under the crowns; a log or a big stone or two at the woods' edges.
const TRAIL := [Vector2(6.3, -0.7), Vector2(6.8, 1.9), Vector2(5.9, 5.6)]
static func _forest(out: Dictionary, rng: RandomNumberGenerator, clear: Array, polygon: PackedVector2Array, band: float) -> void:
	var right := Vector2(cos(deg_to_rad(14.5)), -sin(deg_to_rad(14.5)))
	var down := Vector2(sin(deg_to_rad(14.5)), cos(deg_to_rad(14.5)))
	var w := PondWalk.WALK
	var keep_seen: Array = [SPAWN]
	for c in clear: keep_seen.append(Vector2(c.x, c.z))
	# the trail's mouth and its log / stone stay in sight too (a crown nearer the camera would cover them on screen)
	var mouth_seen: Vector2 = TRAIL[1]   # the mouth: only the row right in front of it gives way (the trail then goes under the crowns)
	var trunks: Array = []
	for asset in out.keys():   # the trail clear of the small pieces already placed (blades, flowers, tufts, bushes, stones)
		var a0 := str(asset)
		if not (a0.begins_with("wild_pz_") and not a0.begins_with("wild_pz_pine") and not a0.begins_with("wild_pz_tree")): continue
		out[asset] = out[asset].filter(func(t):
			var q := Vector2(t.origin.x, t.origin.z)
			for k in TRAIL.size() - 1:
				if q.distance_to(Geometry2D.get_closest_point_to_segment(q, TRAIL[k], TRAIL[k + 1])) < 0.55: return false
			return true)
	for asset in out:
		var a := str(asset)
		if a.begins_with("wild_pz_pine") or a.begins_with("wild_pz_tree") or a.begins_with("wild_tree"):
			for t in out[asset]: trunks.append(Vector2(t.origin.x, t.origin.z))
	var put := func(asset: String, p: Vector2, s: float, y := 0.0) -> void:
		if not out.has(asset): out[asset] = []
		out[asset].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y)))
	# a crown h m tall, r m round at p hides q on screen if it stands nearer the camera, across within r + 0.4 m, and
	# reaches up past q (43° pitch: a metre up covers 0.73 / 0.68 m of ground behind)
	var hides := func(p: Vector2, h: float, r: float) -> bool:
		for q in keep_seen:
			var dv: float = (p - q).dot(down)
			if dv > 0.0 and absf((p - q).dot(right)) < r + 0.4 and dv < (h * 0.731 + 0.4) / 0.682: return true
		var dm: float = (p - mouth_seen).dot(down)
		return dm > 0.0 and dm < 1.9 and absf((p - mouth_seen).dot(right)) < r + 0.2
	# trunks keep off the trail only to just inside the wood (its first ~1.3 m past the mouth); beyond, it runs on under
	# the crowns (上官婉儿: a short way in, then hidden) and the wood's bottom edge stays full
	var trail_in: Vector2 = TRAIL[1] + (TRAIL[2] - TRAIL[1]).normalized() * 1.3
	var on_trail := func(p: Vector2, m: float) -> bool:
		for seg_ab in [[TRAIL[0], TRAIL[1]], [TRAIL[1], trail_in]]:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg_ab[0], seg_ab[1])) < m: return true
		return false
	var beat := [0]
	var tree := func(p: Vector2, list: Array) -> void:
		if trunks.any(func(o): return o.distance_to(p) < 1.25) or on_trail.call(p, 1.3): return
		var asset: String = list[rng.randi() % list.size()]
		if list == FOREST_NEAR:
			var r: Array = RHYTHM[beat[0] % RHYTHM.size()]
			beat[0] += 1
			if not r.is_empty(): asset = r[rng.randi() % r.size()]
		var s: float = float(FOREST_SCALE.get(asset, 0.8)) * rng.randf_range(0.85, 1.12)
		var h := (3.6 if asset.begins_with("wild_pz_pine_01") else (4.7 if asset.begins_with("wild_pz_pine_03") else 4.46)) * s
		if hides.call(p, h, 1.4 * s):
			if not hides.call(p, 0.9, 0.6): put.call("wild_pz_bush_15", p, rng.randf_range(0.8, 1.0), -0.03)   # a low one keeps the spot
			return
		put.call(asset, p, s)
		trunks.append(p)
	# the south wood, the near rows first so the far rows fill round them
	var z := w.end.y + 1.5   # a strip of meadow left below the player on the opening screen (上官婉儿: the ground at the spawn's feet seen)
	var row := 0
	while z < 12.6:
		var x := w.position.x - 2.5 + rng.randf_range(0.0, 1.2) + (0.9 if row % 2 else 0.0)
		while x < w.end.x + 4.5:
			tree.call(Vector2(x + rng.randf_range(-0.35, 0.35), z + rng.randf_range(-0.45, 0.45)), FOREST_NEAR if z < 5.2 else FOREST_FAR)
			x += rng.randf_range(1.7, 2.3)
		z += rng.randf_range(1.3, 1.7)
		row += 1
	# west and east, three rows just past the walk's sides, from the far bank down to the south wood
	for side in [-1.0, 1.0]:
		for k in 3:
			var x0: float = (w.position.x - 1.0 - k * 1.8) if side < 0.0 else (w.end.x + 1.0 + k * 1.8)
			var zz := w.position.y - 2.0 + rng.randf_range(0.0, 1.0)
			while zz < w.end.y + 0.8:
				tree.call(Vector2(x0 + rng.randf_range(-0.4, 0.4), zz), FOREST_NEAR)
				zz += rng.randf_range(1.7, 2.4)
	# beyond the far bank one more ring, the low-poly kinds
	var xx := w.position.x - 3.0
	while xx < w.end.x + 3.0:
		tree.call(Vector2(xx + rng.randf_range(-0.4, 0.4), w.position.y - 8.8 + rng.randf_range(-0.5, 0.5)), ["wild_pz_pine_03", "wild_pz_tree_20"])
		xx += rng.randf_range(1.8, 2.5)
	# the wood's edge inside the walk down the screen's two sides (the opening's edge and the farthest zoom's)
	for side in [-1.0, 1.0]:
		for u in ([-3.3, -4.6] if side < 0.0 else [3.5, 4.8]):
			var v := -9.0 + rng.randf_range(0.0, 1.0)
			while v < 2.6:
				var c: Vector2 = SPAWN + right * (u + rng.randf_range(-0.4, 0.4)) + down * v
				v += rng.randf_range(1.6, 2.6)
				if not w.has_point(c) or c.distance_to(SPAWN) < 2.0: continue
				if clear.any(func(g): return c.distance_to(Vector2(g.x, g.z)) < 2.2): continue
				if Geometry2D.is_point_in_polygon(c, polygon) or (not polygon.is_empty() and c.distance_to(_nearest(c, polygon)) < band + 0.3): continue
				var pick := rng.randf()
				if pick < 0.55: put.call(["wild_pz_bush_05", "wild_pz_bush_07", "wild_pz_bush_15"][rng.randi() % 3], c, rng.randf_range(0.9, 1.45), -0.03)
				elif pick < 0.75: put.call("wild_pz_rock_19", c, rng.randf_range(0.5, 0.7), -0.08)
				else: put.call("wild_pz_bush_11", c, rng.randf_range(1.0, 1.4), -0.03)
				for k in 2: put.call("wild_pz_foot_leafy", c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.4, 0.7), rng.randf_range(0.5, 0.8), -0.02)
	# the trail's mouth: a mossy log along one side, a big stone on the other, a few blades; and in the woods' edges
	# a log and a big stone or two, ≥ 4 m off any gathering point (a log by a point reads as Hardwood)
	var mouth: Vector2 = TRAIL[1]
	var along: Vector2 = (TRAIL[2] - TRAIL[1]).normalized()
	var side: Vector2 = along.orthogonal()
	var bits := [["wild_log_moss", mouth + side * 0.95 + along * 0.15, 1.05, -0.02], ["wild_pz_rock_27", mouth - side * 1.0 + along * 0.3, 0.6, -0.12],
		["wild_pz_rock_19", mouth - side * 0.75 - along * 0.35, 0.45, -0.06]]
	for f in [mouth + side * 2.1 + along * 0.9, mouth - side * 2.2 + along * 1.1]:   # the gate's two trees, just outside the walk
		if f.y > w.end.y + 0.4: tree.call(f, ["wild_pz_pine_01", "wild_pz_pine_03"])
	var spots: Array = [Vector2(w.position.x - 0.6, -6.0), Vector2(w.end.x + 0.6, -9.0), Vector2(w.end.x - 1.5, w.end.y + 1.2), Vector2(3.5, w.end.y + 2.2)]
	for c in spots:
		if clear.any(func(g): return c.distance_to(Vector2(g.x, g.z)) < 4.0) or Geometry2D.is_point_in_polygon(c, polygon): continue
		bits.append(["wild_log_moss" if rng.randf() < 0.5 else "wild_pz_rock_27", c, rng.randf_range(0.9, 1.15) if rng.randf() < 0.5 else 0.6, -0.08])
	for b in bits:
		var at: Vector2 = b[1]
		var asset: String = b[0]
		if clear.any(func(g): return at.distance_to(Vector2(g.x, g.z)) < 4.0):
			if asset != "wild_log_moss" or clear.any(func(g): return at.distance_to(Vector2(g.x, g.z)) < 3.0): continue
			asset = "wild_pz_rock_27"   # a log this near a point reads as Hardwood: a big stone in its place
		put.call(asset, at, float(b[2]) if asset != "wild_pz_rock_27" else rng.randf_range(0.55, 0.7), float(b[3]))
		for k in 3: put.call("wild_pz_foot_leafy", at + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.5, 0.9), rng.randf_range(0.5, 0.8), -0.02)
