extends RefCounted
## Outer extension appearance: tree groves, shrub thickets, rock piles and flower clumps.
## Presentation only: schema-4 masks, farming permissions and saves are untouched, and
## nothing here is harvestable yet. Solid members reserve walk cells through the walker;
## members of one grove or pile may share their own group's cells, and the total never
## exceeds `budget` (the reserved cells of the previous approved layout on this parcel).
## Per Q-19 walking is also checked on the model-fitted profiles the walker will use
## (C-19): a cell may only close under a blocking prop's own profile, no open ground may
## be sealed off, and no more cells close than under the previous layout (`lost_budget`).
## The walker's centre is sampled on a 0.2 m lattice, four points a side per cell.
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
const ROLES := ["tree", "shrub", "rock", "flower", "groundcover"]
const LATTICE := 4
const REAR := Vector3(0.25, 0, 0.968)
const GOLDEN_ANGLE := 2.39996323
const MAX_ROLE_ATTEMPTS := 512

static func plan(walk: RefCounted, assets: Dictionary, recipe: Dictionary, pool: Array[Vector2i],
		budget: int, lost_budget: int, fit: float, rngs: Dictionary) -> Dictionary:
	var spec: Dictionary = recipe.outer_groves
	var state := {"walk":walk, "assets":assets, "recipe":recipe, "layout":[], "roles":{},
		"signature":PackedStringArray(), "trunks":[], "groups":[],
		"fitted":Walk.new(walk.data), "fit":fit, "open":{}, "lost":{}, "lost_budget":lost_budget}
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
			"walk_budget_cells":budget, "reserved_cells":walk.reserved.size(),
			"fitted_lost_budget":lost_budget, "fitted_lost_cells":state.lost.size()}}

## Cells among `layout`'s solid reservations that have open lattice points on the bare
## walker `walk` and none once the layout's fitted profiles are bound.
static func lost_cells(walk: RefCounted, layout: Array, assets: Dictionary, fit: float) -> int:
	var fitted := Walk.new(walk.data)
	var cells := {}
	for item: Dictionary in layout:
		var proxy := Proxy.new(assets[item.asset].collision_proxy, item.transform, fit)
		fitted.add_prop(proxy)
		if proxy.solid:
			for cell: Vector2i in item.cells: cells[cell] = true
	var lost := 0
	for cell: Vector2i in cells:
		var before := false
		var after := false
		for k in LATTICE * LATTICE:
			var p := _sample(walk, cell * LATTICE + Vector2i(k % LATTICE, k / LATTICE))
			before = before or walk.clear_position(p)
			after = after or fitted.clear_position(p)
		if before and not after: lost += 1
	return lost

## Tree groves (`tree_pass`) use rear-half anchors with room for a full canopy: the approved
## 43/14.5 opening keeps tall pieces behind the player. Big trees overlap; young pines fill the
## edge. Shrub thickets take any remaining anchor, front or rear, apart from earlier groups.
static func _groves(state: Dictionary, order: Array[Vector2i], room: Dictionary, tree_pass: bool, cap_cells: int, rng: RefCounted) -> int:
	var spec: Dictionary = state.recipe.outer_groves.grove
	var walk: RefCounted = state.walk
	var count := 0
	var attempts := 0
	for anchor: Vector2i in order:
		if attempts >= int(state.recipe.outer_groves.max_group_attempts) or walk.reserved.size() >= cap_cells: break
		if _full(state, "tree" if tree_pass else "shrub"): break
		var center: Vector3 = walk.point(anchor)
		if tree_pass and (center.dot(REAR) > 0.0 or int(room[anchor]) < int(spec.tree_room_cells)): continue
		attempts += 1
		if walk.reserved.has(anchor) or _near(center, state.groups, float(spec.spacing_m if tree_pass else spec.thicket_spacing_m)): continue
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
			_place(state, "groundcover", cover[_next(rng) % cover.size()], at, lerpf(0.85, 1.0, _unit(rng)), _unit(rng) * TAU, walk.reserved, -1)
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
		if walk.reserved.has(anchor): continue
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
			_place(state, "flower", flowers[_next(rng) % flowers.size()], at, lerpf(0.85, 1.0, _unit(rng)), _unit(rng) * TAU, walk.reserved, -1)
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
			if not _place(state, "flower", flowers[_next(rng) % flowers.size()], at, lerpf(0.85, 1.0, _unit(rng)), _unit(rng) * TAU, walk.reserved, -1).is_empty():
				placed += 1
		for k in _range(rng, spec.groundcover):
			var angle := _unit(rng) * TAU
			var at := center + Vector3(cos(angle), 0, sin(angle)) * (float(spec.radius_m) + 0.3)
			_place(state, "groundcover", cover[_next(rng) % cover.size()], at, lerpf(0.85, 1.0, _unit(rng)), _unit(rng) * TAU, walk.reserved, -1)
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
	var solid := bool(record.collision_proxy.solid)
	# Quarter turns keep a solid prop's axis-aligned reservation as tight as its model.
	if solid: yaw = snappedf(yaw, PI * 0.5)
	var transform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value), at)
	var world_box: AABB = transform * box
	var limit := maxi(cap_cells - walk.reserved.size(), 0) if solid and cap_cells >= 0 else -1
	var footprint: Array[Vector2i] = walk.try_box(world_box, solid, shared, limit)
	if footprint.is_empty(): return {}
	if solid and not _keeps_walkable(state, Proxy.new(record.collision_proxy, transform, state.fit), footprint):
		var added: Array[Vector2i] = []
		for cell in footprint:
			if not shared.has(cell): added.append(cell)
		walk.release(added)
		return {}
	var item := {"asset":asset, "role":role, "transform":transform, "box":world_box, "solid":solid,
		"shadow":bool(spec.cast_shadow_flag), "cells":footprint, "triangles":int(record.triangles)}
	state.layout.append(item)
	if solid: state.trunks.append(at)
	state.signature.append("%s:%.8f,%.8f,%.8f:%.8f:%.8f" % [asset, at.x, at.y, at.z, yaw, scale_value])
	counter.accepted += 1
	return item

## Binds `proxy` on the fitted walker unless it would close more cells than the budget
## allows or cut open lattice points off from the open ground. The proxy, grown by the
## body radius, stays inside its reserved `footprint`, so only those samples change.
static func _keeps_walkable(state: Dictionary, proxy: Proxy, footprint: Array[Vector2i]) -> bool:
	var walk: RefCounted = state.walk
	var fresh := {}
	var closed: Array[Vector2i] = []
	var shut: Array[Vector2i] = []
	for cell in footprint:
		var open := false
		var base := false
		for k in LATTICE * LATTICE:
			var key := cell * LATTICE + Vector2i(k % LATTICE, k / LATTICE)
			var was := _open(state, key)
			var now := was and not proxy.touches(_sample(walk, key), Walk.BODY_RADIUS)
			fresh[key] = now
			if was and not now: shut.append(key)
			open = open or now
			base = base or walk.clear_position(_sample(walk, key))
		if base and not open and not state.lost.has(cell): closed.append(cell)
	if state.lost.size() + closed.size() > int(state.lost_budget): return false
	if _seals(state, shut, fresh): return false
	state.fitted.add_prop(proxy)
	for key: Vector2i in fresh: state.open[key] = fresh[key]
	for cell in closed: state.lost[cell] = true
	return true

## True if an open sample next to a newly shut one can no longer reach open ground:
## any open sample in an unreserved cell, which the reserved-cell connectivity keeps joined.
static func _seals(state: Dictionary, shut: Array[Vector2i], fresh: Dictionary) -> bool:
	var walk: RefCounted = state.walk
	var escaped := {}
	for key in shut:
		for offset: Vector2i in Walk.NEIGHBORS:
			var start: Vector2i = key + offset
			if escaped.has(start) or not _open_now(state, start, fresh): continue
			var queue: Array[Vector2i] = [start]
			var seen := {start: true}
			var index := 0
			var out := false
			while index < queue.size() and not out:
				var at := queue[index]
				index += 1
				var cell := Vector2i(floori(at.x / float(LATTICE)), floori(at.y / float(LATTICE)))
				if escaped.has(at) or not walk.reserved.has(cell):
					out = true
					break
				for step: Vector2i in Walk.NEIGHBORS:
					var next: Vector2i = at + step
					if not seen.has(next) and _open_now(state, next, fresh):
						seen[next] = true
						queue.append(next)
			if not out: return true
			for at: Vector2i in seen: escaped[at] = true
	return false

static func _open_now(state: Dictionary, key: Vector2i, fresh: Dictionary) -> bool:
	return fresh[key] if fresh.has(key) else _open(state, key)

## Cached walker answer for a lattice sample against the profiles bound so far.
static func _open(state: Dictionary, key: Vector2i) -> bool:
	if not state.open.has(key):
		state.open[key] = state.fitted.clear_position(_sample(state.walk, key))
	return state.open[key]

static func _sample(walk: RefCounted, key: Vector2i) -> Vector3:
	var cell := Vector2i(floori(key.x / float(LATTICE)), floori(key.y / float(LATTICE)))
	var sub := Vector2(key - cell * LATTICE) - Vector2.ONE * (LATTICE - 1) * 0.5
	return walk.point(cell) + Vector3(sub.x, 0, -sub.y) * (walk.cell_m / LATTICE)

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
