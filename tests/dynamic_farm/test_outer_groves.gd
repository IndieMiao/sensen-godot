extends SceneTree
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const CoreObstacles = preload("res://modules/dynamic_farm/farm_core_obstacles.gd")
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
# Reachable cells before this change, audited on the C-18 review set (V-20, attachment-68).
const BEFORE_REACHABLE := {"p-3139010": 1539, "p-3139019": 1470, "p-5402049": 3962}
var checks := 0
var failures := 0
var inventory := {}
var fit := 1.0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

## Binds the model-fitted profiles exactly like Scenery.build, without loading the art.
func _bind(walk: RefCounted, layout: Array) -> Array:
	var proxies := []
	for item: Dictionary in layout:
		var proxy := Proxy.new(inventory[item.asset].collision_proxy, item.transform, fit)
		walk.add_prop(proxy)
		proxies.append(proxy)
	return proxies

func _sample(walk: RefCounted, key: Vector2i) -> Vector3:
	var cell := Vector2i(floori(key.x / 4.0), floori(key.y / 4.0))
	return walk.point(cell) + Vector3((key.x - cell.x * 4 - 1.5) * 0.2, 0, -(key.y - cell.y * 4 - 1.5) * 0.2)

## Walker centres on a 0.2 m lattice (as in test_core_obstacles), flooded from spawn:
## `clear` lattice keys, `seen` keys reached, `cells` cells holding a reached key.
func _lattice(walk: RefCounted, data: Dictionary) -> Dictionary:
	var clear := {}
	for cell: Vector2i in data.by_cell:
		for sy in 4:
			for sx in 4:
				var key := cell * 4 + Vector2i(sx, sy)
				if walk.clear_position(_sample(walk, key)): clear[key] = true
	var queue: Array[Vector2i] = []
	var seen := {}
	for sy in 4:
		for sx in 4:
			var key: Vector2i = data.spawn * 4 + Vector2i(sx, sy)
			if clear.has(key):
				queue.append(key)
				seen[key] = true
	var index := 0
	while index < queue.size():
		var key := queue[index]
		index += 1
		for offset: Vector2i in Walk.NEIGHBORS:
			if clear.has(key + offset) and not seen.has(key + offset):
				seen[key + offset] = true
				queue.append(key + offset)
	var cells := {}
	for key: Vector2i in seen: cells[Vector2i(floori(key.x / 4.0), floori(key.y / 4.0))] = true
	return {"clear":clear, "seen":seen, "cells":cells}

## Q-19 on the walker itself (C-19 fitted profiles, core obstacles included on both sides):
## a cell walkable before may only be lost under a new blocking prop's own profile.
func _fitted(data: Dictionary, planned: Dictionary, walk: RefCounted, reference: Dictionary, reference_walk: RefCounted) -> void:
	var recipe: Dictionary = planned.recipe
	var core_rng := Scenery.FixedRandom.new((data.block_id + "|" + str(recipe.core_obstacles.version)).sha256_text())
	var reference_core := CoreObstacles.plan(data, reference_walk, inventory, recipe.core_obstacles, core_rng)
	var old_walk := Walk.new(data)
	old_walk.reserved = reference_walk.reserved
	_bind(old_walk, reference.layout)
	_bind(old_walk, reference_core.layout)
	var new_walk := Walk.new(data)
	new_walk.reserved = walk.reserved
	var solids := []
	var proxies := _bind(new_walk, planned.layout)
	for i in proxies.size():
		if proxies[i].solid: solids.append([proxies[i], planned.layout[i]])
	_bind(new_walk, planned.core_obstacles.layout)
	var before := _lattice(old_walk, data)
	var after := _lattice(new_walk, data)
	var lost := PackedStringArray()
	var unowned := 0
	for cell: Vector2i in before.cells:
		if after.cells.has(cell): continue
		var owner := ""
		for sy in 4:
			for sx in 4:
				var p := _sample(new_walk, cell * 4 + Vector2i(sx, sy))
				for pair: Array in solids:
					if owner.is_empty() and pair[0].touches(p, Walk.BODY_RADIUS): owner = pair[1].asset
		if owner.is_empty(): unowned += 1
		lost.append("%d,%d:%s" % [cell.x, cell.y, owner if not owner.is_empty() else "NONE"])
	# Open ground nobody can reach: lattice points that are clear yet were cut off.
	var sealed := 0
	for key: Vector2i in after.clear:
		if not after.seen.has(key) and before.seen.has(key): sealed += 1
	var kept := true
	for at: Vector2i in data.by_cell:
		if (data.by_cell[at].zone == "core" or data.protected.has(at) or at == data.spawn or at == data.entry) \
				and before.cells.has(at) and not after.cells.has(at): kept = false
	_check(reference_core.layout_sha256 == planned.core_obstacles.layout_sha256, "core obstacle layer unchanged by the outer layout")
	_check(unowned == 0, "every lost walkable cell lies under a new blocking prop's own fitted profile (%d not)" % unowned)
	_check(sealed == 0, "no open ground sealed off (%d lattice points)" % sealed)
	_check(after.cells.size() >= before.cells.size(), "walkable cells not fewer with fitted collision (%d -> %d)" % [before.cells.size(), after.cells.size()])
	_check(kept and after.cells.has(data.spawn) and after.cells.has(data.entry), "spawn, entry, core and protected cells stay walkable")
	print("OUTER_FITTED parcel=%s walkable=%d->%d lost=%d gained=%d sealed=%d" % [data.block_id, before.cells.size(), after.cells.size(),
		lost.size(), after.cells.size() - before.cells.size() + lost.size(), sealed])
	print("OUTER_LOST parcel=%s %s" % [data.block_id, " ".join(lost)])

## BFS over clear cells from spawn, independent of Walk.connected().
func _reachable(data: Dictionary, walk: RefCounted) -> Dictionary:
	var seen := {data.spawn: true}
	var queue: Array[Vector2i] = [data.spawn]
	var index := 0
	while index < queue.size():
		var at := queue[index]
		index += 1
		for offset: Vector2i in Walk.NEIGHBORS:
			var next := at + offset
			if data.by_cell.has(next) and not walk.reserved.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen

func _parcel(raw: Dictionary) -> void:
	var data := Data.decode(raw)
	_check(data.ok, "valid parcel")
	if not data.ok: return
	var original := data.duplicate(true)
	var walk := Walk.new(data)
	var planned := Scenery.plan(data, walk)
	_check(planned.ok, "scenery plan")
	if not planned.ok: return
	Shade.enforce_budget(planned, data, walk)
	var recipe: Dictionary = planned.recipe
	var outer: Dictionary = planned.outer

	# Walk range: the previous approved layout of this parcel is the "before".
	var reference := {"layout":[], "roles":{}}
	var reference_walk := Walk.new(data)
	var pool: Array[Vector2i] = []
	for cell: Dictionary in data.cells:
		var at := Vector2i(cell.x, cell.y)
		if cell.zone == "extension" and not data.protected.has(at): pool.append(at)
	pool.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for role: String in recipe.outer_groves.reference_roles:
		Scenery._scatter(reference, data, reference_walk, recipe, recipe.outer_groves.reference_art_version, role, inventory, pool)
	Shade.enforce_budget(reference, data, reference_walk)
	var before := _reachable(data, reference_walk)
	var after := _reachable(data, walk)
	if BEFORE_REACHABLE.has(data.block_id):
		_check(before.size() == BEFORE_REACHABLE[data.block_id], "reference replays the audited previous layout")
	_check(walk.reserved.size() <= reference_walk.reserved.size() and outer.walk_budget_cells == reference_walk.reserved.size(), "never more blocked cells than before")
	_check(after.size() >= before.size() and after.size() == data.by_cell.size() - walk.reserved.size(), "walkable range not smaller; every clear cell reachable")
	var corridors := true
	for at: Vector2i in data.by_cell:
		if (data.by_cell[at].zone == "core" or data.protected.has(at)) and not after.has(at): corridors = false
	_check(corridors and after.has(data.entry) and walk.connected(), "all core, protected corridor, spawn and entry cells reachable")
	_check(data == original, "decoded masks, permissions, spawn and entry unchanged")
	_fitted(data, planned, walk, reference, reference_walk)

	# Placement contract.
	var solid_cells := {}
	var valid := true
	var trees: Array[Vector3] = []
	var rocks: Array[Vector3] = []
	var flowers: Array[Vector3] = []
	var allowed := {}
	for role: String in recipe.roles:
		for asset: String in recipe.roles[role].ids: allowed[asset] = role
	for item: Dictionary in planned.layout:
		valid = valid and allowed.get(item.asset, "") == item.role and inventory.has(item.asset)
		valid = valid and item.solid == bool(inventory[item.asset].collision_proxy.solid)
		for cell: Vector2i in item.cells:
			valid = valid and data.by_cell.has(cell) and data.by_cell[cell].zone == "extension" and not data.protected.has(cell)
			if item.solid: solid_cells[cell] = true
		var at: Vector3 = item.transform.origin
		if item.role == "tree":
			valid = valid and at.dot(Vector3(0.25, 0, 0.968)) <= 0.0
			trees.append(at)
		elif item.role == "rock": rocks.append(at)
		elif item.role == "flower": flowers.append(at)
	_check(valid, "13-model palette, model collision flag, extension-only footprints, trees in the rear half")
	_check(solid_cells == walk.reserved, "blocked cells are exactly the solid footprints; flowers and grass never block")
	for role: String in planned.roles:
		var counter: Dictionary = planned.roles[role]
		_check(counter.accepted <= counter.target and counter.attempts <= 512, "bounded placement " + role)

	# Groups: overlapping grove canopies, rock piles, flower clumps.
	_check(outer.groves >= 1 and _pairs(trees, 2.0) >= 1, "at least one grove with overlapping tree canopies")
	_check(outer.rock_piles >= 1 and _pairs(rocks, 1.0) >= 1, "at least one rock pile with companion stones")
	_check(outer.flower_clumps >= 1 and _cluster(flowers, 0.9, 3), "at least one flower clump of three or more")

	# Same parcel, same layout.
	var again_walk := Walk.new(original)
	var again := Scenery.plan(original, again_walk)
	Shade.enforce_budget(again, original, again_walk)
	_check(again.layout_sha256 == planned.layout_sha256 and again_walk.reserved == walk.reserved and again.outer == outer, "reopening reproduces layout and blockers")
	print("OUTER_GROVES parcel=%s trees=%d rocks=%d flowers=%d groves=%d thickets=%d piles=%d clumps=%d blocked=%d/%d reachable=%d/%d sha=%s" % [
		data.block_id, trees.size(), rocks.size(), flowers.size(), outer.groves, outer.thickets, outer.rock_piles, outer.flower_clumps,
		walk.reserved.size(), reference_walk.reserved.size(), after.size(), before.size(), planned.layout_sha256])

func _pairs(points: Array[Vector3], distance: float) -> int:
	var count := 0
	for i in points.size():
		for j in range(i + 1, points.size()):
			if points[i].distance_to(points[j]) < distance: count += 1
	return count

func _cluster(points: Array[Vector3], radius: float, size: int) -> bool:
	for p in points:
		var near := 0
		for q in points:
			if p.distance_to(q) <= radius * 2.0: near += 1
		if near >= size: return true
	return false

## The incremental connectivity check must accept and reject exactly like a full flood.
func _incremental_matches_full() -> void:
	var data := Data.decode(Fixture.farm("p-A"))
	data.protected = {}
	for at: Vector2i in data.by_cell:
		if data.by_cell[at].zone == "core": data.protected[at] = true
	var fast := Walk.new(data)
	var full := Walk.new(data)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20
	var same := true
	var accepted := 0
	for i in 400:
		var size := Vector3(rng.randf_range(0.2, 2.6), 1, rng.randf_range(0.2, 2.6))
		var at := Vector3(rng.randf_range(-19.2, 19.2), 0, rng.randf_range(-11.2, 11.2))
		var box := AABB(at - size * 0.5, size)
		full._connected_size = -1
		var a := fast.try_box(box, true)
		var b := full.try_box(box, true)
		same = same and a == b and fast.reserved == full.reserved
		if not a.is_empty(): accepted += 1
	_check(same and accepted > 20 and fast.connected(), "incremental connectivity equals full flood fill (%d accepted)" % accepted)
	# Shared cells and the new-cell limit.
	var walk := Walk.new(data)
	var first := walk.try_box(AABB(Vector3(-18.4, 0, -10.4), Vector3(0.5, 1, 0.5)), true)
	var overlap := AABB(Vector3(-18.0, 0, -10.4), Vector3(0.5, 1, 0.5))
	var shared := {}
	for cell in first: shared[cell] = true
	_check(not first.is_empty() and walk.try_box(overlap, true).is_empty(), "solid overlap rejected without sharing")
	var blocked_before := walk.reserved.size()
	_check(walk.try_box(overlap, true, shared, 0).is_empty() and walk.reserved.size() == blocked_before, "new-cell limit rejects without side effects")
	var second := walk.try_box(overlap, true, shared)
	_check(not second.is_empty() and walk.reserved.size() > blocked_before, "group members may share their own cells")
	# Shadow-budget pruning of one member keeps the cells its group mate still holds.
	var layout := [{"solid":true, "cells":first}, {"solid":true, "cells":second}]
	Shade.unreserve(layout, 1, walk)
	var held := true
	for cell in first: held = held and walk.reserved.has(cell)
	_check(held and walk.reserved.size() == blocked_before, "pruning a member frees only cells no other member holds")
	# A refused placement is undone exactly.
	var third := walk.try_box(AABB(Vector3(-10.4, 0, -10.4), Vector3(0.5, 1, 0.5)), true)
	walk.release(third)
	_check(not third.is_empty() and walk.reserved.size() == blocked_before and walk.connected(), "release restores the earlier reserved cells")

func _run() -> void:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(Scenery.INVENTORY_PATH))
	for record: Dictionary in catalog.assets: inventory[record.id] = record
	fit = float(catalog.collision_fit_fraction)
	_check(inventory.size() == 13, "existing 13-model inventory")
	_incremental_matches_full()
	var files := OS.get_cmdline_user_args()
	if files.is_empty(): print("OUTER_GROVES SKIP real parcels (pass r4 JSON paths after --)")
	for path in files:
		_parcel(JSON.parse_string(FileAccess.get_file_as_string(path)))
	print("DYNAMIC_OUTER_GROVE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
