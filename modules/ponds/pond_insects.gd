extends RefCounted
## The wild's bees, butterflies and dragonflies (SGODOT-454; the user: "注意实现方式和性能"; 上官婉儿's plan and spec):
## no models — each kind a tiny mesh made here (12 faces or fewer, 16 the dragonfly's), all of a kind one
## MultiMeshInstance3D (3 draw calls in all), flying and beating their wings in pond_insects.gdshader from TIME, so the
## CPU does nothing per frame; unshaded, no shadows. Bees and butterflies round the wild's flowers and bushes (else its
## leafy clumps; a butterfly, last, the cattails), dragonflies over the water 0.3–1.5 m off the shore; every anchor CLEAR_M
## off the gathering points and the spawn, and its flight off the opening screen's keys, the player and the points and
## the name bar. Half as many under gl_compatibility. Seeded from the pond: the same pond has them in the same places
## (their flights by each device's clock). Built with the bank's scenery, freed with it.

const SHADER := preload("res://modules/ponds/pond_insects.gdshader")
const PondWildGround := preload("res://modules/ponds/pond_wild_ground.gd")
const KINDS := ["bee", "butterfly", "dragonfly"]
const COUNT := {"bee": 6, "butterfly": 6, "dragonfly": 4}
## On the opening screen (its anchor where it shows the world) at most this many of a kind (上官婉儿: 3–6 in all there), the
## rest round the meadow; two dragonflies, as some ponds open on little but water and sand (Fern).
const OPENING := {"bee": 2, "butterfly": 2, "dragonfly": 2}
## Height over the ground (the water's for a dragonfly) the whole flight keeps in, and the shader's rise and fall about
## its anchor (bee_path's 0.08, butterfly_path's 0.15 and the 0.02 its wings lift it, the dragonfly's 0.04).
const HEIGHT := {"bee": Vector2(0.4, 1.0), "butterfly": Vector2(0.6, 1.6), "dragonfly": Vector2(0.2, 0.6)}
const BOB := {"bee": 0.08, "butterfly": 0.17, "dragonfly": 0.04}
const RADIUS := {"bee": Vector2(0.4, 0.8), "butterfly": Vector2(0.6, 1.2), "dragonfly": Vector2(0.7, 0.85)}
const WATER_Y := 0.055   # FishingWater's surface
const CLEAR_M := 1.5
const SPACING_M := 1.6   # between any two anchors
const SHORE := Vector2(0.3, 1.5)   # a dragonfly's anchor: in the water, this far off its edge
const SCALE_JITTER := 0.12
## The meshes are the spec's sizes; on the phone (~45 px/m at the opening) they read as white specks, so they are drawn
## this much bigger (上官婉儿 on #929: bee 8–10 px, butterfly 12–14, dragonfly 16–18).
const SIZE := {"bee": 1.9, "butterfly": 1.9, "dragonfly": 1.3}
## Half a mesh's longest reach (its wings or its body), unscaled: what a flight's box adds round its path.
const HALF := {"bee": 0.09, "butterfly": 0.13, "dragonfly": 0.17}
## Colours (sRGB, 上官婉儿's spec), in the shader's palette order.
const PALETTE := {
	"bee": ["f2c230", "3a2e26", "eaf4ff"],   # body, stripes, wings
	"butterfly": ["3e3a36", "f5d547", "f7f3e8", "c9a7e8", "e8a23a", "4a4a4a", "f2e6ff"],   # body; yellow, white, lilac; tip, dot, inner
	# green, blue (上官婉儿 on #929: a shade deeper, and paler wings edged in the body's colour, to show on the water);
	# their heads a shade darker; wings
	"dragonfly": ["23845f", "1f6e8c", "1b674a", "18566d", "eef6fa"],
}

## Timing them (李元芳's frame times, one build measured twice): a user://p0_no_insects marker (adb shell run-as <package>
## touch files/p0_no_insects; removed, they are back) or P0_NO_INSECTS=1 leaves them out, from the next pond on.
const OFF_FILE := "user://p0_no_insects"
static func wanted() -> bool:
	return not (FileAccess.file_exists(OFF_FILE) or OS.get_environment("P0_NO_INSECTS") == "1")

## {kind: [{at: Vector3 (the anchor, at its height), radius, phase, variant, scale}]} for this pond. `wild`: points(),
## where its plants and cattails stand. `opening`: {screen: (corners: PackedVector3Array) -> Rect2 on the opening screen,
## keep_off: [Rect2] its keys / quick bar / player / points / name bar, shown: Rect2 the world it shows}; empty, no screen.
static func layout(entry: Dictionary, spec: Dictionary, wild: Dictionary, clear: Array, spawn: Vector3, opening := {},
		gles := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(entry.decoration_seed) ^ 454
	var id := str(entry.id)
	var screen: Callable = opening.get("screen", Callable())
	var keep_off: Array = opening.get("keep_off", [])
	var shown: Rect2 = opening.get("shown", Rect2())
	var taken: Array = []
	var out := {}
	for kind in ["dragonfly", "bee", "butterfly"]:   # the water's few first: the bank's plants are many
		out[kind] = []
		var want: int = COUNT[kind]
		var reeds: Array = wild.get("reeds", [])
		var points := _water_points(id, spec, int(entry.decoration_seed), reeds) if kind == "dragonfly" \
			else _shuffled(wild.get("flowers", []), rng) + _shuffled(wild.get("leafy", []), rng)
		if kind == "butterfly": points += _shuffled(reeds, rng)   # last, a pond opening on water (Fern)
		# the opening's share from the plants nearest the player (上官婉儿 on #929: a bee and a butterfly on the clumps
		# 3–5 m off), the rest round the meadow in the seeded order
		var nearest := points.duplicate()
		if kind != "dragonfly": nearest.sort_custom(func(a, b): return _flat(a, spawn) < _flat(b, spawn))
		var seen := 0
		for later in [false, true]:   # the opening's share first (OPENING), then off it round the meadow
			for p in (points if later else nearest):
				if out[kind].size() >= want: break
				var a := _anchor(kind, p, rng, not p in reeds)
				if not _free(a, taken, clear, spawn): continue
				if screen.is_valid():
					var box: Rect2 = screen.call(_flight_box(kind, a))
					if keep_off.any(func(r): return (r as Rect2).intersects(box)): continue
					var on_screen := shown.has_point((screen.call(PackedVector3Array([a.at])) as Rect2).position)
					if on_screen == later or (on_screen and seen >= OPENING[kind]): continue
					if on_screen: seen += 1
				out[kind].append(a)
				taken.append(a.at)
			if not screen.is_valid(): break
		# gl_compatibility: the first half of the same draw (the opening's share first), so a GLES phone shows some of the
		# very insects a Vulkan one does (周瑜 on #929)
		if gles: out[kind] = (out[kind] as Array).slice(0, floori(COUNT[kind] / 2.0))
	return out

## `grass`: over the meadow's plants (not a cattail in the water), where a white butterfly may fly.
static func _anchor(kind: String, p: Vector3, rng: RandomNumberGenerator, grass := true) -> Dictionary:
	var h: Vector2 = HEIGHT[kind]
	var r: Vector2 = RADIUS[kind]
	var bob: float = BOB[kind]
	var ground := WATER_Y if kind == "dragonfly" else 0.0
	var variant := 0
	if kind == "butterfly":   # yellow : white : lilac, 5 : 1 : 4 (上官婉儿 / 不知火舞 on #929: a white one melts into the
		var roll := rng.randf()   # grass's light and the sand; it flies only over the meadow's plants, else a lilac one)
		variant = 0 if roll < 0.5 else (1 if roll < 0.6 and grass else 2)
	elif kind == "dragonfly":
		variant = rng.randi() % 2
	return {"at": Vector3(p.x, ground + rng.randf_range(h.x + bob, h.y - bob), p.z), "radius": rng.randf_range(r.x, r.y),
		"phase": rng.randf(), "variant": variant, "scale": SIZE[kind] * (1.0 + rng.randf_range(-SCALE_JITTER, SCALE_JITTER))}

static func _flat(p: Vector3, q: Vector3) -> float: return Vector2(p.x - q.x, p.z - q.z).length()

static func _free(a: Dictionary, taken: Array, clear: Array, spawn: Vector3) -> bool:
	var at: Vector3 = a.at
	if PondScenery._near(at, clear) or _flat(at, spawn) < CLEAR_M: return false
	return not taken.any(func(o): return _flat(o, at) < SPACING_M)

## The box a flight keeps in (its radius round the anchor, its rise and fall, the insect's own size): the 8 corners.
static func _flight_box(kind: String, a: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var own: float = HALF[kind] * a.scale
	var r: float = a.radius + own
	var bob: float = BOB[kind] + own
	for k in 8:
		out.append(a.at + Vector3(r if k & 1 else -r, bob if k & 2 else -bob, r if k & 4 else -r))
	return out

static func _shuffled(points: Array, rng: RandomNumberGenerator) -> Array:
	var out := points.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = out[i]
		out[i] = out[j]
		out[j] = swap
	return out

## Points over the water SHORE off its edge, those beside the cattails first.
static func _water_points(id: String, spec: Dictionary, seed_value: int, reeds: Array) -> Array:
	var near: Array = []
	var far: Array = []
	for p in _water_band(id, spec, seed_value):
		if reeds.any(func(q): return Vector2(q.x - p.x, q.z - p.z).length() < 1.5): near.append(p)
		else: far.append(p)
	return near + far

## The water's band SHORE off its edge, sampled from the pond's seed: up to 80 points. Some 15–19 ms on an M4 (800 tries,
## 17 FishingModel.contains each), so kept per pond — the scenery is built again as the gathering points come or change
## (周瑜 on #929), and the band depends on neither.
const BAND_CACHE_MAX := 8
static var _bands := {}
static func _water_band(id: String, spec: Dictionary, seed_value: int) -> Array:
	var key := "%s|%d" % [id, seed_value]
	if _bands.has(key): return _bands[key]
	var out: Array = []
	var r := FishingModel.water_rect(id, spec)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 4541
	for k in (800 if r.has_area() else 0):
		var p := Vector3(rng.randf_range(r.position.x, r.end.x), 0, rng.randf_range(r.position.y, r.end.y))
		if not FishingModel.contains(id, p, 0.0, spec): continue
		var inside := true
		var reaches := false
		for a in 8:
			var d := Vector3(cos(a * TAU / 8.0), 0, sin(a * TAU / 8.0))
			if not FishingModel.contains(id, p + d * SHORE.x, 0.0, spec): inside = false
			if not FishingModel.contains(id, p + d * SHORE.y, 0.0, spec): reaches = true
		if inside and reaches: out.append(p)
		if out.size() >= 80: break
	if _bands.size() >= BAND_CACHE_MAX: _bands.clear()
	_bands[key] = out
	return out

## Where a built PondScenery's plants stand (PondWildProps' layout, kept on its node): {flowers: the flowers' and
## bushes', leafy: the pale leafy clumps' (on the opening screen the bushes became these, PondWildGround._opening_leafy;
## the bees' and butterflies' second choice), reeds: the cattails' (the butterflies' last)}.
const LEAFY := ["wild_pz_grass_40", "wild_pz_grass_24"]
static func points(scenery: Node) -> Dictionary:
	return {"flowers": _points(scenery, PondWildGround.PACK_FLOWERS + PondWildGround.PACK_BUSHES + ["wild_bush_dark", "wild_bush_olive"]),
		"leafy": _points(scenery, LEAFY), "reeds": _points(scenery, ["wild_cattail_water"])}

static func _points(scenery: Node, assets: Array) -> Array:
	var out: Array = []
	var props := scenery.find_child("WildProps", true, false) if scenery else null
	if props == null: return out
	var layout: Dictionary = props.get_meta("layout", {})
	for asset in assets:
		for t in layout.get(asset, []): out.append((t as Transform3D).origin)
	return out

## The insects of `layout` as one node: a MultiMeshInstance3D a kind (none for a kind with no anchor).
static func build(entry: Dictionary, spec: Dictionary, scenery: Node, clear: Array, spawn: Vector3, opening := {},
		gles := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Insects"
	var l := layout(entry, spec, points(scenery), clear, spawn, opening, gles)
	for kind in KINDS:
		if (l[kind] as Array).is_empty(): continue
		root.add_child(_batch(kind, l[kind]))
	return root

static func _batch(kind: String, anchors: Array) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = kind.to_pascal_case()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh(kind)
	mm.instance_count = anchors.size()
	var bounds := AABB()
	for i in anchors.size():
		var a: Dictionary = anchors[i]
		mm.set_instance_transform(i, Transform3D(Basis(), a.at))
		mm.set_instance_custom_data(i, Color(a.radius, a.phase, a.variant, a.scale))
		var reach: Vector3 = Vector3(a.radius, BOB[kind], a.radius) + Vector3.ONE * (HALF[kind] * a.scale + 0.05)   # the flight, the insect
		var box := AABB(a.at - reach, reach * 2.0)
		bounds = box if i == 0 else bounds.merge(box)
	node.multimesh = mm
	node.custom_aabb = bounds   # the shader moves them off their anchors: the culling box is their flights'
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("kind", KINDS.find(kind))
	var colours := PackedColorArray()
	for hex in PALETTE[kind]: colours.append(Color(hex))
	material.set_shader_parameter("palette", colours)
	node.material_override = material
	return node

## A kind's mesh (metres, forward +Z; 上官婉儿's sizes): a body of two cones on a ring, and flat wings hinged on its long
## axis, UV / UV2 as pond_insects.gdshader reads them.
static func mesh(kind: String) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	match kind:
		"bee":   # 0.16 long, 0.18 across the wings: 8 + 4 faces
			_body(v, uv, uv2, Vector3(0, 0, 0.08), Vector3(0, -0.005, -0.08), -0.005,
				[Vector2(0.035, 0), Vector2(0, 0.03), Vector2(-0.035, 0), Vector2(0, -0.03)])
			for side in [1.0, -1.0]: _wing(v, uv, uv2, side, 0, 0.028, -0.02, 0.035, 0.09, 0.03)
		"butterfly":   # 0.10 long, 0.26 across: 6 + 4 faces
			_body(v, uv, uv2, Vector3(0, 0, 0.05), Vector3(0, 0, -0.05), 0.01, _ring(0.01))
			for side in [1.0, -1.0]: _wing(v, uv, uv2, side, 0, 0.0, -0.055, 0.05, 0.13, 0.0)
		"dragonfly":   # 0.30 long, 0.32 across: 6 + 8 faces; the body 1.3 × thicker (上官婉儿 on #929)
			_body(v, uv, uv2, Vector3(0, 0, 0.13), Vector3(0, 0, -0.17), 0.07, _ring(0.026))
			for side in [1.0, -1.0]:
				_wing(v, uv, uv2, side, 0, 0.015, 0.08, 0.115, 0.16, 0.01)
				_wing(v, uv, uv2, side, 1, 0.015, 0.035, 0.075, 0.155, 0.015)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out

static func _ring(r: float) -> Array:
	return [Vector2(0, r), Vector2(-r * 0.866, -r * 0.5), Vector2(r * 0.866, -r * 0.5)]

## A cone from `front` and one from `back` to a ring at z `ring_z`.
static func _body(v: PackedVector3Array, uv: PackedVector2Array, uv2: PackedVector2Array, front: Vector3, back: Vector3,
		ring_z: float, ring: Array) -> void:
	for i in ring.size():
		var a := Vector3(ring[i].x, ring[i].y, ring_z)
		var b := Vector3(ring[(i + 1) % ring.size()].x, ring[(i + 1) % ring.size()].y, ring_z)
		for p in [front, a, b, back, b, a]:
			v.append(p)
			uv.append(Vector2.ZERO)
			uv2.append(Vector2.ZERO)

## A wing on `side`: a quad from its hinge (x 0, height `y`, z `z0`–`z1`) out `span`, its tip swept back `sweep`.
static func _wing(v: PackedVector3Array, uv: PackedVector2Array, uv2: PackedVector2Array, side: float, index: int,
		y: float, z0: float, z1: float, span: float, sweep: float) -> void:
	var corners := [Vector3(0, y, z0), Vector3(0, y, z1), Vector3(side * span, y, z1 - sweep), Vector3(side * span, y, z0 - sweep)]
	var own := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	for k in [0, 1, 2, 0, 2, 3]:
		v.append(corners[k])
		uv.append(Vector2(side, index))
		uv2.append(own[k])
