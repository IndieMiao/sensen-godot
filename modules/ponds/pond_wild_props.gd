extends RefCounted
## The wild's dressing round a pond (SGODOT-422; 赵云's pieces #789 / #799, 不知火舞's rules, 上官婉儿's integration notes):
## the bank's six trees single pines and round trees (not the Timber grove's three-tree clump); along the water and both
## sides 3–5 piece clusters of flowers, clover, pebbles and bushes; in 2–3 of the meadow's corners a mossy log with
## mushrooms and a fern; the open middle and the path's sides sparse; under the main key's column low pieces only;
## cattails only in the shallows. Every piece keeps off the gathering points (PondScenery.CLEAR_M; trees also the strip
## in front, PondScenery._in_front). Seeded from the pond: the same pond dresses the same way.

const Art = preload("res://modules/farm/farm_art.gd")
const TREES := ["wild_tree_pine", "wild_tree_round"]
const CLUSTER := ["wild_flower_white", "wild_flower_yellow", "wild_flower_lilac", "wild_clover", "wild_pebbles_a",
	"wild_pebbles_b", "wild_bush_dark", "wild_bush_olive"]
const LOW := ["wild_flower_white", "wild_flower_yellow", "wild_flower_lilac", "wild_clover", "wild_pebbles_a", "wild_pebbles_b"]
const CORNER := ["wild_log_moss", "wild_mushrooms", "wild_fern"]
## The main key's column on the opening screen (world xz; spawn (6.125, -1.625), 43°, 6.72 m wide): low pieces only.
## Kept for a dressing built before the HUD has laid out; with the opening camera known, `in_key` (P0Pond._opening_keys)
## tells instead whether a piece's box on the opening screen touches the action keys (盘古 on 422: the tool badge, the
## switch and the main key, 8 px out — its whole box, a crown over them too, not only where it stands).
const KEY_COLUMN := Rect2(7.6, -6.0, 3.2, 6.6)
const MOVE_TRIES := 6       # a piece under the keys is moved this many times before a low one stands in for it
const MOVE_M := 1.6         # … this far at most
## The opening screen's dry ground (world xz round the spawn): the first clusters go here, so it opens with 10–15 pieces.
const OPENING := Rect2(2.8, -9.0, 6.7, 10.0)
const OPENING_CLUSTERS := 5
## Below the player down to the quick bar's top (不知火舞 422: screen y 560–700, x 20–260 of 360 × 800 — the left half
## and the middle, not the main key's column): two more clusters of clover, grass, pebbles and a few flowers, none in the
## metre in front of the player's feet at the spawn.
const LOWER := Rect2(2.9, 1.0, 4.4, 3.2)
const LOWER_CLUSTERS := 2
const LOWER_PIECES := ["wild_clover", "wild_clover", "grass_clump", "grass_clump", "wild_pebbles_a", "wild_pebbles_b",
	"wild_flower_white", "wild_flower_yellow", "wild_flower_lilac"]
const SPAWN := Vector3(6.125, 0, -1.625)
const FEET_CLEAR_M := 1.0
const PATH_HALF_M := 1.4   # the path up from the spawn (PondScenery's own keep-off): nothing on it
const SHALLOW_M := 0.6     # a cattail stands in water this near the bank

## {asset: [Transform3D]} for this pond. `trees`: the bank's six tree points, those PondScenery keeps. `in_key`:
## (corners: PackedVector3Array) -> bool, whether points in the world fall on the opening screen's action keys; empty,
## the old KEY_COLUMN. Only LOW pieces stand there: the others move off first (盘古: moved before replaced, so the
## column does not fill up), else a low one stands in; a corner's group goes to another corner; a cattail elsewhere.
static func layout(entry: Dictionary, spec: Dictionary, clear: Array, trees: Array, in_key := Callable()) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(entry.decoration_seed) ^ 422
	var out := {}
	var put := func(asset: String, at: Vector3, scale := 1.0) -> void:
		if not out.has(asset): out[asset] = []
		out[asset].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * scale), at))
	for t in trees: put.call(TREES[rng.randi() % TREES.size()], t, rng.randf_range(0.9, 1.1))
	var id := str(entry.id)
	var keyed := in_key.is_valid()
	# under the keys: by its box on the opening screen, else (no camera yet) a tall piece standing in KEY_COLUMN
	var under_keys := func(asset: String, p: Vector3, scale: float) -> bool:
		if not keyed: return KEY_COLUMN.has_point(Vector2(p.x, p.z))
		return bool(in_key.call(box_corners(asset, p, scale)))
	var free := func(p: Vector3, tall: bool) -> bool:
		if FishingModel.contains(id, p, 0.45, spec): return false
		if p.z > -3.0 and p.z < -0.75 and absf(p.x - 6.0) < PATH_HALF_M: return false   # the path, to the walk's edge
		if PondScenery._near(p, clear): return false
		if tall and ((not keyed and KEY_COLUMN.has_point(Vector2(p.x, p.z))) or PondScenery._in_front(p, clear)): return false
		return true
	# a piece other than LOW under the keys: moved off (MOVE_TRIES, MOVE_M), else a low one there; `p` where it stands
	var place := func(asset: String, p: Vector3, scale: float, tall: bool) -> void:
		if keyed and not asset in LOW and under_keys.call(asset, p, scale):
			for k in MOVE_TRIES:
				var q: Vector3 = p + Vector3(rng.randf_range(-MOVE_M, MOVE_M), 0, rng.randf_range(-MOVE_M, MOVE_M))
				if not under_keys.call(asset, q, scale) and free.call(q, tall):
					put.call(asset, q, scale)
					return
			asset = LOW[rng.randi() % LOW.size()]
			tall = false
		if free.call(p, tall): put.call(asset, p, scale)
	# clusters, 3–5 pieces each: first OPENING_CLUSTERS on the opening screen's dry ground, then on the bank (within 1.6 m
	# of the water) and down both sides
	var centres: Array = []
	var spaced := func(c: Vector3, gap: float) -> bool: return not centres.any(func(o): return Vector2(o.x - c.x, o.z - c.z).length() < gap)
	var tries := 0
	while centres.size() < OPENING_CLUSTERS and tries < 400:
		tries += 1
		var c := Vector3(rng.randf_range(OPENING.position.x, OPENING.end.x), 0.01, rng.randf_range(OPENING.position.y, OPENING.end.y))
		if FishingModel.contains(id, c, 0.8, spec) or not free.call(c, false) or not spaced.call(c, 1.8): continue
		centres.append(c)
	tries = 0
	while centres.size() < 16 and tries < 400:
		tries += 1
		var c := Vector3(rng.randf_range(-1.5, 13.5), 0.01, rng.randf_range(-18.0, 0.4))
		var bank := FishingModel.contains(id, c, 1.6, spec) and not FishingModel.contains(id, c, 0.6, spec)
		var side := c.x < 0.7 or c.x > 11.3
		if not (bank or side) or not spaced.call(c, 2.2): continue
		centres.append(c)
	for c in centres:
		for k in rng.randi_range(3, 5):
			var p: Vector3 = c + Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
			var asset: String = CLUSTER[rng.randi() % CLUSTER.size()]
			var tall := asset.begins_with("wild_bush")
			if keyed:
				place.call(asset, p, rng.randf_range(1.0, 1.3), tall)
				continue
			if tall and KEY_COLUMN.has_point(Vector2(p.x, p.z)): asset = LOW[rng.randi() % LOW.size()]
			if free.call(p, tall): put.call(asset, p, rng.randf_range(1.0, 1.3))
	# below the player: LOWER_CLUSTERS more, low pieces only, the spawn's front metre clear
	var lower: Array = []
	tries = 0
	while lower.size() < LOWER_CLUSTERS and tries < 200:
		tries += 1
		var c := Vector3(rng.randf_range(LOWER.position.x, LOWER.end.x), 0.01, rng.randf_range(LOWER.position.y, LOWER.end.y))
		if lower.any(func(o): return Vector2(o.x - c.x, o.z - c.z).length() < 1.6): continue
		lower.append(c)
	for c in lower:
		for k in rng.randi_range(3, 5):
			var p: Vector3 = c + Vector3(rng.randf_range(-0.55, 0.55), 0, rng.randf_range(-0.55, 0.55))
			if Vector2(p.x - SPAWN.x, p.z - (SPAWN.z + FEET_CLEAR_M * 0.5)).length() < FEET_CLEAR_M: continue
			var piece: String = LOWER_PIECES[rng.randi() % LOWER_PIECES.size()]
			if keyed: place.call(piece, p, rng.randf_range(1.0, 1.3), false)
			elif free.call(p, false): put.call(piece, p, rng.randf_range(1.0, 1.3))
	# the open middle and the path's sides: a few low pieces, far apart
	for k in 6:
		var p := Vector3(rng.randf_range(2.0, 10.0), 0.01, rng.randf_range(-10.0, 0.0))
		if free.call(p, false): put.call(LOW[rng.randi() % LOW.size()], p, rng.randf_range(0.8, 1.0))
	# corners: a mossy log, its mushrooms and a fern, in 2–3 of the meadow's four
	var corners := [Vector3(-1.6, 0.01, -17.0), Vector3(12.6, 0.01, -17.0), Vector3(-1.6, 0.01, -0.6), Vector3(12.6, 0.01, -0.6)]
	for i in range(corners.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = corners[i]
		corners[i] = corners[j]
		corners[j] = swap
	var group := [[CORNER[0], Vector3(0, 0, 0)], [CORNER[1], Vector3(0.45, 0, 0.3)], [CORNER[2], Vector3(-0.5, 0, 0.25)]]
	var wanted := rng.randi_range(2, 3)
	var used := 0
	for c in corners:   # shuffled: the first `wanted` the keys leave alone (all three pieces are tall but the mushrooms)
		if used == wanted: break
		if keyed and group.any(func(g): return under_keys.call(g[0], c + g[1], 1.1)): continue
		used += 1
		for g in group:
			var p: Vector3 = c + g[1]
			if free.call(p, g[0] != "wild_mushrooms"): put.call(g[0], p, rng.randf_range(0.9, 1.1))
	# cattails: in the water, within SHALLOW_M of its edge
	var reeds := 0
	tries = 0
	while reeds < 6 and tries < 600:
		tries += 1
		var p := Vector3(rng.randf_range(-1.5, 13.5), 0.0, rng.randf_range(-18.0, 0.4))
		if not FishingModel.contains(id, p, 0.0, spec): continue
		var edge := false
		for a in 8:
			var d := Vector3(cos(a * TAU / 8.0), 0, sin(a * TAU / 8.0)) * SHALLOW_M
			if not FishingModel.contains(id, p + d, 0.0, spec): edge = true
		if not edge or PondScenery._near(p, clear): continue
		var reed := rng.randf_range(0.85, 1.1)
		if keyed and under_keys.call("wild_cattail_water", p, reed): continue   # tall: another spot in the shallows
		put.call("wild_cattail_water", p, reed)
		reeds += 1
	return out

## A piece's box in the world, whatever way it turns (its mesh's own vertices' box, swept round its axis): the 8 corners.
static func box_corners(asset: String, at: Vector3, scale: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh := Art.mesh_for(asset) if ResourceLoader.exists(Art.ROOT + asset + ".glb") else null
	var box := mesh.get_aabb() if mesh else AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.0, 0.6))
	var r := 0.0
	for k in 4: r = maxf(r, Vector2(box.position.x if k % 2 == 0 else box.end.x, box.position.z if k < 2 else box.end.z).length())
	r *= scale
	for k in 8:
		out.append(at + Vector3(r if k & 1 else -r, (box.end.y if k & 2 else box.position.y) * scale, r if k & 4 else -r))
	return out

## The layout as batched meshes under one node.
static func build(entry: Dictionary, spec: Dictionary, clear: Array, trees: Array, in_key := Callable()) -> Node3D:
	var root := Node3D.new()
	root.name = "WildProps"
	var l := layout(entry, spec, clear, trees, in_key)
	for asset in l:
		if not ResourceLoader.exists(Art.ROOT + asset + ".glb"): continue   # #799's pieces not in this build yet
		var batch := Art.batch(asset, l[asset], asset.begins_with("wild_tree") or asset.begins_with("wild_bush"))
		batch.name = "Wild_" + asset   # the lower clusters' grass beside PondScenery's own grass_clump batch
		root.add_child(batch)
	return root
