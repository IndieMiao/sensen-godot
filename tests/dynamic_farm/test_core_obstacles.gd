extends SceneTree
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const CoreObstacles = preload("res://modules/dynamic_farm/farm_core_obstacles.gd")
var checks := 0
var failures := 0
var boxes := {}
var solid := {}

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _test(raw: Dictionary) -> String:
	var data := Data.decode(raw)
	_check(data.ok, "valid parcel")
	if not data.ok: return ""
	var original := data.duplicate(true)
	var walk := Walk.new(data)
	var planned := Scenery.plan(data, walk)
	Shade.enforce_budget(planned, data, walk)
	var core: Dictionary = planned.core_obstacles
	var occupied := {}
	var counts := {"weed":0, "stone":0, "bush":0, "sapling":0}
	var valid := true
	for item: Dictionary in core.layout:
		var at: Vector2i = item.cell
		var tr: Transform3D = item.transform
		var box: AABB = tr * boxes[item.asset]
		valid = valid and item.solid == solid[item.asset] and walk.cell_at(box.position) == at and walk.cell_at(box.end) == at
		valid = valid and data.by_cell[at].zone == "core" and not occupied.has(at) and tr.origin == walk.point(at)
		for arrival: Vector2i in [data.spawn, data.entry]:
			var delta := (at - arrival).abs()
			valid = valid and maxi(delta.x,delta.y) > 1
		occupied[at] = true
		counts[item.role] += 1
	_check(valid,"unique single-cell appearances inside core, clear of arrival")
	_check(counts == core.roles and counts.weed > counts.stone and counts.stone > counts.bush and counts.bush > counts.sapling and counts.sapling > 0,"four ordered roles")
	var ratio := float(occupied.size()) / int(data.counts.core)
	_check(ratio >= 0.10 and ratio <= 0.15,"actual occupied cells / entire core within approved bounds")
	# Baseline walk blockers are solely the surviving solid EXTENSION props. Compare
	# the full mask, not just connected(): removing a dead end can leave a connected map.
	var baseline := {}
	for item: Dictionary in planned.layout:
		if item.solid:
			for cell: Vector2i in item.cells: baseline[cell] = true
	_check(walk.reserved == baseline and walk.connected(),"same clear cells and every remaining core/extension cell reachable")
	# Q-16: stones, bushes and saplings block with their fitted profiles; weeds do not,
	# and no other cell loses its connection to spawn.
	var art := Scenery.build(planned, walk)
	var before := _reachable(walk, data)
	var core_art := Scenery.build(core, walk)
	var after := _reachable(walk, data)
	var props_ok := true
	var lost := 0
	for item: Dictionary in core.layout:
		props_ok = props_ok and walk.clear_position(walk.point(item.cell)) != item.solid
	for cell: Vector2i in before:
		var taken := false
		for item: Dictionary in core.layout: taken = taken or (item.solid and item.cell == cell)
		if not taken and not after.has(cell): lost += 1
	_check(props_ok,"stone/bush/sapling centres blocked, weed centres walkable")
	_check(lost == 0 and walk.clear_position(walk.point(data.spawn)) and walk.clear_position(walk.point(data.entry)),
		"no previously reachable cell cut off (%d lost)" % lost)
	art.root.free()
	core_art.root.free()
	_check(data == original,"decoded masks, permissions, spawn and entry unchanged")
	var reopened := Scenery.plan(original, Walk.new(original))
	_check(reopened.core_obstacles == core,"reopening reproduces every cell, kind, asset and transform")
	print("CORE_OBSTACLES parcel=%s core=%d occupied=%d ratio=%.5f counts=%s reachable=%d/%d walk_cells=%d->%d sha=%s" % [data.block_id,data.counts.core,occupied.size(),ratio,counts,data.cells.size()-walk.reserved.size(),data.cells.size()-baseline.size(),before.size(),after.size(),core.layout_sha256])
	return core.layout_sha256

## Cells holding a walker-reachable point of a 0.2 m lattice, flooded from spawn.
func _reachable(walk: RefCounted, data: Dictionary) -> Dictionary:
	var clear := {}
	for cell: Vector2i in data.by_cell:
		for sy in 4:
			for sx in 4:
				if walk.clear_position(walk.point(cell) + Vector3((sx-1.5)*0.2,0,-(sy-1.5)*0.2)):
					clear[cell*4+Vector2i(sx,sy)] = true
	var queue: Array[Vector2i] = []
	for sy in 4:
		for sx in 4:
			if clear.has(data.spawn*4+Vector2i(sx,sy)): queue.append(data.spawn*4+Vector2i(sx,sy))
	var seen := {}
	for key in queue: seen[key] = true
	var index := 0
	while index < queue.size():
		var key := queue[index]
		index += 1
		for offset: Vector2i in Walk.NEIGHBORS:
			if clear.has(key+offset) and not seen.has(key+offset):
				seen[key+offset] = true
				queue.append(key+offset)
	var cells := {}
	for key: Vector2i in seen: cells[Vector2i(key.x/4,key.y/4)] = true
	return cells

## Two core blocks joined by a one-cell neck bordered by void. Blocking props at a
## higher density must never take the neck or any cell that would seal an area.
func _pinch(inventory: Dictionary) -> void:
	var data := {"cell_m":0.8,"grid_size":Vector2i(44,13),"spawn":Vector2i(2,6),"entry":Vector2i(41,6),
		"cells":[],"by_cell":{},"counts":{"core":0}}
	for y in 13:
		for x in 44:
			if x >= 18 and x < 26 and y != 6: continue
			var cell := {"x":x,"y":y,"zone":"core"}
			data.cells.append(cell)
			data.by_cell[Vector2i(x,y)] = cell
	data.counts.core = data.cells.size()
	var recipe := {"coverage":0.2,"roles":{"weed":{"share":0.1,"ids":["wild_pz_grass_24"]},
		"stone":{"share":0.4,"ids":["wild_pz_rock_13","wild_pz_softrock_10"]},
		"bush":{"share":0.3,"ids":["wild_pz_bush_05","wild_pz_bush_07"]},"sapling":{"ids":["wild_pz_pine_03"]}}}
	for seed_text in ["pinch-a","pinch-b","pinch-c","pinch-d","pinch-e"]:
		var walk := Walk.new(data)
		var before := _reachable(walk, data)
		var core := CoreObstacles.plan(data, walk, inventory, recipe, Scenery.FixedRandom.new(seed_text.sha256_text()))
		var art := Scenery.build(core, walk)
		var after := _reachable(walk, data)
		var lost := 0
		var solids := 0
		for item: Dictionary in core.layout:
			if item.solid: solids += 1
		for cell: Vector2i in before:
			var taken := false
			for item: Dictionary in core.layout: taken = taken or (item.solid and item.cell == cell)
			if not taken and not after.has(cell): lost += 1
		_check(solids > 40 and lost == 0,"pinch %s: %d blocking props, %d cells cut off" % [seed_text,solids,lost])
		print("CORE_PINCH ", seed_text, " blocking=", solids, " lost=", lost)
		art.root.free()

func _run() -> void:
	var inventory = JSON.parse_string(FileAccess.get_file_as_string(Scenery.INVENTORY_PATH))
	for record: Dictionary in inventory.assets:
		var low: Array = record.bounds_godot_m[0]
		var high: Array = record.bounds_godot_m[1]
		solid[record.id] = bool(record.collision_proxy.solid)
		boxes[record.id] = AABB(Vector3(low[0],low[1],low[2]),Vector3(high[0]-low[0],high[1]-low[1],high[2]-low[2]))
	var by_id := {}
	for record: Dictionary in inventory.assets: by_id[record.id] = record
	_pinch(by_id)
	# Identical geometry and schema seed, different parcel identifiers.
	var first := _test(Fixture.farm("p-A"))
	var second := _test(Fixture.farm("p-B"))
	_check(first != second, "identity, not shared geometry/seed, keys the layout")
	for path in OS.get_cmdline_user_args():
		_test(JSON.parse_string(FileAccess.get_file_as_string(path)))
	print("DYNAMIC_CORE_OBSTACLE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
