extends SceneTree
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
var checks := 0
var failures := 0
var boxes := {}

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
		valid = valid and not item.solid and walk.cell_at(box.position) == at and walk.cell_at(box.end) == at
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
	_check(data == original,"decoded masks, permissions, spawn and entry unchanged")
	var reopened := Scenery.plan(original, Walk.new(original))
	_check(reopened.core_obstacles == core,"reopening reproduces every cell, kind, asset and transform")
	print("CORE_OBSTACLES parcel=%s core=%d occupied=%d ratio=%.5f counts=%s reachable=%d/%d sha=%s" % [data.block_id,data.counts.core,occupied.size(),ratio,counts,data.cells.size()-walk.reserved.size(),data.cells.size()-baseline.size(),core.layout_sha256])
	return core.layout_sha256

func _run() -> void:
	var inventory = JSON.parse_string(FileAccess.get_file_as_string(Scenery.INVENTORY_PATH))
	for record: Dictionary in inventory.assets:
		var low: Array = record.bounds_godot_m[0]
		var high: Array = record.bounds_godot_m[1]
		boxes[record.id] = AABB(Vector3(low[0],low[1],low[2]),Vector3(high[0]-low[0],high[1]-low[1],high[2]-low[2]))
	# Identical geometry and schema seed, different parcel identifiers.
	var first := _test(Fixture.farm("p-A"))
	var second := _test(Fixture.farm("p-B"))
	_check(first != second, "identity, not shared geometry/seed, keys the layout")
	for path in OS.get_cmdline_user_args():
		_test(JSON.parse_string(FileAccess.get_file_as_string(path)))
	print("DYNAMIC_CORE_OBSTACLE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
