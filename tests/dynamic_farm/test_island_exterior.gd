extends SceneTree
## Boundary probes run on the exact same walk state before and after rendering.
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Ground = preload("res://modules/dynamic_farm/farm_mesh.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const Cliff = preload("res://modules/dynamic_farm/island_cliff.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, reason: String) -> void:
	if not ok:
		failures += 1
		push_error(reason)

func _approach_edges(walk: RefCounted, data: Dictionary) -> PackedVector3Array:
	var stops := PackedVector3Array()
	var original: Vector3 = walk.position
	for cell: Vector2i in data.by_cell:
		if not walk.clear_cell(cell): continue
		for step: Vector2i in Walk.NEIGHBORS:
			if data.by_cell.has(cell + step): continue
			walk.position = walk.point(cell)
			var out := Vector3(step.x, 0, -step.y)
			var stop: Vector3 = walk.move(out * data.cell_m * 2.0)
			_check(walk.clear_position(stop) and walk.cell_at(stop) == cell, "walk escaped at %s" % cell)
			stops.append(stop)
	walk.position = original
	return stops

func _run() -> void:
	var files := OS.get_cmdline_user_args()
	_check(not files.is_empty(), "pass real schema-4 parcel JSON files")
	for file in files:
		var data := Data.decode(JSON.parse_string(FileAccess.get_file_as_string(file)))
		_check(data.ok, "invalid parcel: " + file)
		if not data.ok: continue
		var walk := Walk.new(data)
		var plan := Scenery.plan(data, walk)
		Shade.enforce_budget(plan, data, walk)
		var authority := data.duplicate(true)
		var blockers := walk.blocked.duplicate()
		var before := _approach_edges(walk, data)
		var ground := Ground.build(data, walk, plan.recipe, true, Shade.can_widen(plan, data, walk))
		var bounds: AABB = ground.get_node("EarthEdge").mesh.get_aabb()
		_check(bounds.position.y < -1.5 and bounds.position.y >= Cliff.LOWEST_Y - 0.001, "cliff missing or below camera floor")
		_check(ground.find_children("*", "CollisionObject3D", true, false).is_empty(), "visual rim added physics")
		_check(authority == data and blockers == walk.blocked, "renderer changed authoritative data or blockers")
		_check(not before.is_empty() and _approach_edges(walk, data) == before, "boundary stops changed")
		print("ISLAND_EDGE ", data.block_id, " cells=", data.counts, " edge_stops=", before.size(), " stops_sha256=", before.to_byte_array().hex_encode().sha256_text())
		ground.free()
	print("ISLAND_EXTERIOR failures=", failures)
	quit(1 if failures else 0)
