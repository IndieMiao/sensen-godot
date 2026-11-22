extends RefCounted
## Outer extension appearance: tree groves, shrub thickets, rock piles and flower clumps.
## Presentation only: schema-4 masks, farming permissions and saves are untouched, and
## nothing here is harvestable yet. Solid members reserve walk cells through the walker;
## members of one grove or pile may share their own group's cells, and the total never
## exceeds `budget` (the blocked cells of the previous approved layout on this parcel).
const ROLES := ["tree", "shrub", "rock", "flower", "groundcover"]
const REAR := Vector3(0.25, 0, 0.968)
const GOLDEN_ANGLE := 2.39996323
const MAX_ROLE_ATTEMPTS := 512

static func plan(walk: RefCounted, assets: Dictionary, recipe: Dictionary,
		pool: Array[Vector2i], budget: int, rngs: Dictionary) -> Dictionary:
	var spec: Dictionary = recipe.outer_groves
	var state := {"walk":walk, "assets":assets, "recipe":recipe, "layout":[], "roles":{},
		"signature":PackedStringArray(), "trunks":[], "groups":[]}
	for role: String in ROLES:
		var target: Dictionary = spec.targets[role]
		state.roles[role] = {"target":mini(int(target.cap), pool.size() / int(target.cells_per)),
			"accepted":0, "attempts":0, "rejected":0}
	# Cumulative shares: thickets, the least distinctive group, take what remains.
	var order := _shuffled(pool, rngs.grove)
	var room := _clearance(pool)
	var groves := _groves(state, order, room, true, int(budget * float(spec.budget_shares.groves)), rngs.grove)
	var piles := _rock_piles(state, pool, int(budget * float(spec.budget_shares.rock_piles)), rngs.pile)
	var thickets := _groves(state, order, room, false, budget, rngs.grove)
	var clumps := _flower_clumps(state, pool, rngs.clump)
	for role: String in ROLES:
		state.roles[role].rejected = state.roles[role].attempts - state.roles[role].accepted
	return {"layout":state.layout, "roles":state.roles,
		"layout_sha256":"\n".join(state.signature).sha256_text(),
		"summary":{"version":spec.version, "groves":groves, "thickets":thickets, "rock_piles":piles, "flower_clumps":clumps,
			"walk_budget_cells":budget, "blocked_cells":walk.blocked.size()}}

## Tree groves (`tree_pass`) use rear-half anchors with room for a full canopy: the approved
## 43/14.5 opening keeps tall pieces behind the player. Big trees overlap; young pines fill the
## edge. Shrub thickets take any remaining anchor, front or rear, apart from earlier groups.
static func _groves(state: Dictionary, order: Array[Vector2i], room: Dictionary, tree_pass: bool, cap_cells: int, rng: RefCounted) -> int:
	var spec: Dictionary = state.recipe.outer_groves.grove
	var walk: RefCounted = state.walk
	var count := 0
	var attempts := 0
	for anchor: Vector2i in order:
		if attempts >= int(state.recipe.outer_groves.max_group_attempts) or walk.blocked.size() >= cap_cells: break
		if _full(state, "tree" if tree_pass else "shrub"): break
		var center: Vector3 = walk.point(anchor)
		if tree_pass and (center.dot(REAR) > 0.0 or int(room[anchor]) < int(spec.tree_room_cells)): continue
		attempts += 1
		if walk.blocked.has(anchor) or _near(center, state.groups, float(spec.spacing_m if tree_pass else spec.thicket_spacing_m)): continue
		var shared := {}
		var placed := 0
		var turn := _unit(rng) * TAU
		var ring := 0.0
		if tree_pass:
			var trees := _range(rng, spec.trees)
			for k in trees:
				var radius := float(spec.member_step_m) * sqrt(float(k))
				if _slot(state, "tree", _weighted(rng, spec.tree_weights), center, radius, turn + k * GOLDEN_ANGLE, spec.tree_scale, shared, cap_cells, rng):
					placed += 1
			ring = float(spec.member_step_m) * sqrt(float(trees)) + 0.4
			for k in _range(rng, spec.young_pines):
				if _slot(state, "tree", spec.young_pine_id, center, ring, turn + PI * 0.5 + k * GOLDEN_ANGLE, spec.young_pine_scale, shared, cap_cells, rng):
					placed += 1
			ring += 0.4
		var shrub_ids: Array = state.recipe.roles.shrub.ids
		for k in _range(rng, spec.grove_shrubs if tree_pass else spec.thicket_shrubs):
			var radius := ring + float(spec.shrub_step_m) * sqrt(float(k))
			if _slot(state, "shrub", shrub_ids[_next(rng) % shrub_ids.size()], center, radius, turn + PI + k * GOLDEN_ANGLE, spec.shrub_scale, shared, cap_cells, rng):
				placed += 1
		if placed == 0: continue
		count += 1
		state.groups.append(center)
		var cover: Array = state.recipe.roles.groundcover.ids
		for k in _range(rng, spec.foot_groundcover):
			var angle := _unit(rng) * TAU
			var at := center + Vector3(cos(angle), 0, sin(angle)) * (ring + 0.6 + _unit(rng) * 0.8)
			_place(state, "groundcover", cover[_next(rng) % cover.size()], at, lerpf(0.85, 1.0, _unit(rng)), _unit(rng) * TAU, walk.blocked, -1)
	return count

## One grove member: a few deterministic positions around its golden-angle slot.
static func _slot(state: Dictionary, role: String, asset: String, center: Vector3, radius: float, angle: float,
		scale_range: Array, shared: Dictionary, cap_cells: int, rng: RefCounted) -> bool:
	for attempt in int(state.recipe.outer_groves.grove.slot_tries):
		var r := radius * lerpf(0.9, 1.15, _unit(rng)) if radius > 0.0 else _unit(rng) * 0.3
		var a := angle + attempt * 0.9
		var at := center + Vector3(cos(a), 0, sin(a)) * r
		if role == "tree" and at.dot(REAR) > 0.0: continue
		var item := _place(state, role, asset, at, _lerp(rng, scale_range), _unit(rng) * TAU, shared, cap_cells)
		if not item.is_empty():
			for cell: Vector2i in item.cells: shared[cell] = true
			return true
	return false

## Chebyshev distance (in cells) from each eligible cell to the nearest ineligible one.
static func _clearance(pool: Array[Vector2i]) -> Dictionary:
	var room := {}
	for cell: Vector2i in pool: room[cell] = -1
	var queue: Array[Vector2i] = []
	for cell: Vector2i in pool:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if not room.has(cell + Vector2i(dx, dy)) and room[cell] < 0:
					room[cell] = 0
					queue.append(cell)
	var index := 0
	while index < queue.size():
		var at := queue[index]
		index += 1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var next := at + Vector2i(dx, dy)
				if room.has(next) and int(room[next]) < 0:
					room[next] = int(room[at]) + 1
					queue.append(next)
	return room

## A main rock with smaller companions and a few flowers: reads as a pickable spot.
static func _rock_piles(state: Dictionary, pool: Array[Vector2i], budget: int, rng: RefCounted) -> int:
	var spec: Dictionary = state.recipe.outer_groves.rock_pile
	var walk: RefCounted = state.walk
	var target := mini(int(spec.cap), pool.size() / int(spec.cells_per))
	var flowers: Array = state.recipe.roles.flower.ids
	var piles := 0
	var attempts := 0
	for anchor: Vector2i in _shuffled(pool, rng):
		if piles >= target or attempts >= int(state.recipe.outer_groves.max_group_attempts) or _full(state, "rock"): break
		attempts += 1
		if walk.blocked.has(anchor): continue
		var center: Vector3 = walk.point(anchor) + Vector3(_unit(rng) - 0.5, 0, _unit(rng) - 0.5) * 0.3
		if _near(center, state.trunks, float(spec.trunk_clearance_m)): continue
		var main := _place(state, "rock", spec.main_ids[_next(rng) % spec.main_ids.size()], center,
			lerpf(0.85, 1.0, _unit(rng)), _unit(rng) * TAU, {}, budget)
		if main.is_empty(): continue
		var shared := {}
		for cell: Vector2i in main.cells: shared[cell] = true
		var turn := _unit(rng) * TAU
		for k in _range(rng, spec.companions):
			var angle := turn + k * GOLDEN_ANGLE
			var at := center + Vector3(cos(angle), 0, sin(angle)) * _lerp(rng, spec.companion_offset_m)
			var item := _place(state, "rock", spec.companion_ids[_next(rng) % spec.companion_ids.size()], at,
				_lerp(rng, spec.companion_scale), _unit(rng) * TAU, shared, budget)
			for cell: Vector2i in item.get("cells", []): shared[cell] = true
		for k in _range(rng, spec.flowers):
			var angle := turn + PI + k * 1.3
			var at := center + Vector3(cos(angle), 0, sin(angle)) * _lerp(rng, spec.flower_offset_m)
			_place(state, "flower", flowers[_next(rng) % flowers.size()], at, lerpf(0.85, 1.0, _unit(rng)), _unit(rng) * TAU, walk.blocked, -1)
		piles += 1
		state.groups.append(center)
	return piles

## Tight flower beds, mostly beside groves and rock piles, some alone in open grass.
static func _flower_clumps(state: Dictionary, pool: Array[Vector2i], rng: RefCounted) -> int:
	var spec: Dictionary = state.recipe.outer_groves.flower_clump
	var walk: RefCounted = state.walk
	var target := mini(int(spec.cap), pool.size() / int(spec.cells_per))
	var flowers: Array = state.recipe.roles.flower.ids
	var cover: Array = state.recipe.roles.groundcover.ids
	var centers: Array[Vector3] = []
	var attempts := 0
	for anchor: Vector2i in _shuffled(pool, rng):
		if centers.size() >= target or attempts >= int(state.recipe.outer_groves.max_group_attempts) or _full(state, "flower"): break
		attempts += 1
		var center: Vector3 = walk.point(anchor) + Vector3(_unit(rng) - 0.5, 0, _unit(rng) - 0.5) * 0.4
		if not state.groups.is_empty() and _unit(rng) < float(spec.near_group_share) and not _near(center, state.groups, float(spec.near_group_m)): continue
		if _near(center, centers, float(spec.spacing_m)) or _near(center, state.trunks, float(spec.trunk_clearance_m)): continue
		var placed := 0
		for k in _range(rng, spec.flowers):
			var angle := _unit(rng) * TAU
			var at := center + Vector3(cos(angle), 0, sin(angle)) * float(spec.radius_m) * sqrt(_unit(rng))
			if not _place(state, "flower", flowers[_next(rng) % flowers.size()], at, lerpf(0.85, 1.0, _unit(rng)), _unit(rng) * TAU, walk.blocked, -1).is_empty():
				placed += 1
		for k in _range(rng, spec.groundcover):
			var angle := _unit(rng) * TAU
			var at := center + Vector3(cos(angle), 0, sin(angle)) * (float(spec.radius_m) + 0.3)
			_place(state, "groundcover", cover[_next(rng) % cover.size()], at, lerpf(0.85, 1.0, _unit(rng)), _unit(rng) * TAU, walk.blocked, -1)
		if placed > 0: centers.append(center)
	return centers.size()

## Adds one instance if its role still has room and the walker accepts its footprint.
static func _place(state: Dictionary, role: String, asset: String, at: Vector3, scale_value: float, yaw: float,
		shared: Dictionary, cap_cells: int) -> Dictionary:
	var counter: Dictionary = state.roles[role]
	if counter.accepted >= counter.target or counter.attempts >= MAX_ROLE_ATTEMPTS: return {}
	counter.attempts += 1
	var record: Dictionary = state.assets[asset]
	var spec: Dictionary = state.recipe.roles[role]
	var walk: RefCounted = state.walk
	var low: Array = record.bounds_godot_m[0]
	var high: Array = record.bounds_godot_m[1]
	var box := AABB(Vector3(low[0],low[1],low[2]), Vector3(high[0]-low[0],high[1]-low[1],high[2]-low[2]))
	var solid := bool(spec.solid_collision)
	# Quarter turns keep a solid prop's axis-aligned reservation as tight as its model.
	if solid: yaw = snappedf(yaw, PI * 0.5)
	var transform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value), at)
	var world_box: AABB = transform * box
	var limit := maxi(cap_cells - walk.blocked.size(), 0) if solid and cap_cells >= 0 else -1
	var footprint: Array[Vector2i] = walk.try_box(world_box, solid, shared, limit)
	if footprint.is_empty(): return {}
	var item := {"asset":asset, "role":role, "transform":transform, "box":world_box, "solid":solid,
		"shadow":bool(spec.cast_shadow_flag), "cells":footprint, "triangles":int(record.triangles)}
	state.layout.append(item)
	if solid: state.trunks.append(at)
	state.signature.append("%s:%.8f,%.8f,%.8f:%.8f:%.8f" % [asset, at.x, at.y, at.z, yaw, scale_value])
	counter.accepted += 1
	return item

static func _full(state: Dictionary, role: String) -> bool:
	var counter: Dictionary = state.roles[role]
	return counter.accepted >= counter.target or counter.attempts >= MAX_ROLE_ATTEMPTS

static func _near(p: Vector3, points: Array, distance: float) -> bool:
	for other: Vector3 in points:
		if p.distance_to(other) < distance: return true
	return false

static func _unit(rng: RefCounted) -> float:
	return rng.unit()

static func _next(rng: RefCounted) -> int:
	return rng.next()

static func _weighted(rng: RefCounted, weights: Dictionary) -> String:
	var roll := _unit(rng)
	var last := ""
	for asset: String in weights:
		last = asset
		roll -= float(weights[asset])
		if roll < 0.0: return asset
	return last

static func _range(rng: RefCounted, bounds: Array) -> int:
	return int(bounds[0]) + int(_next(rng) % (int(bounds[1]) - int(bounds[0]) + 1))

static func _lerp(rng: RefCounted, bounds: Array) -> float:
	return lerpf(float(bounds[0]), float(bounds[1]), _unit(rng))

## Fisher-Yates over the canonical (y,x) pool order.
static func _shuffled(pool: Array[Vector2i], rng: RefCounted) -> Array[Vector2i]:
	var order := pool.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := int(_next(rng) % (i + 1))
		var swap: Vector2i = order[i]
		order[i] = order[j]
		order[j] = swap
	return order
