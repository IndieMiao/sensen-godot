extends SceneTree
## C-253 (C-190#94): on 711 PACIFIC AVE's big yard (p-0178001, pinned in fixtures/yard/) the rocks and weeds round the
## cottage left no ready coop or sheep pen spot nearby, and the placement preview started on the nearest ready one,
## about 60 cells away at (79,56), where its camera showed neither the cottage nor the player. Building.start_spot now
## looks within START_REACH_M of the player first: a ready spot there, else one that needs the fewest obstacles
## cleared there (C-175's "Clear the plants and rocks here first"); only with neither does it go farther.
## - Logic, on the fixture with the cottage where the recording built it (19,73): the old search (unlimited reach)
##   still lands far off (the fixture shows the case); the new start is within reach of the spawn and of the cottage's
##   door, valid once cleared; clearing just the obstacles on it makes that very spot ready, and the next preview
##   starts there. Which cells take a building is Building.reason's, unchanged: the start is judged by it alone.
## - The parcels passed after `--` (tools/ci/dynamic_farm_tests.sh's r4 set): a start exists exactly when the old one
##   did, is valid once cleared, and is ready whenever a ready spot lies within reach.
## - The real scene on the fixture: Build Coop and Build Sheep Pen open their preview within reach of the player, with
##   the preview and the cottage in the camera (it frames the preview, as before); with that spot's obstacles cleared (as a player clears
##   them) the coop's preview opens ready there and Build puts it up beside the cottage.
##   godot --headless --path "$QA" --script res://tests/dynamic_farm/test_start_spot.gd [-- <farm.json>…]
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const YARD := "res://tests/dynamic_farm/fixtures/yard/"
const BLOCK := "p-0178001"
const DATASET := "sf-dynamic-farm-20261125-r8"
## Where the C-190 recording built the cottage (C-190 report, observation 1).
const COTTAGE := Vector2i(19, 73)
## Where the old search put the coop and the sheep pen on this yard (C-190#94).
const FAR := Vector2i(79, 56)
const TYPES := ["coop", "sheep_pen"]
var checks := 0
var failures := 0
var scene

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	var raw = _yard_payload()
	if raw is Dictionary:
		_logic(raw)
		await _scene(raw)
	for path in OS.get_cmdline_user_args(): _other(JSON.parse_string(FileAccess.get_file_as_string(path)))
	print("START_SPOT_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _yard_payload() -> Variant:
	var sha := ""
	for line in FileAccess.get_file_as_string(YARD + "SHA256SUMS").split("\n", false):
		var parts := line.split(" ", false)
		if parts.size() == 2 and parts[1].trim_prefix("*") == BLOCK + ".json": sha = parts[0]
	var path := YARD + BLOCK + ".json"
	_check(sha != "" and FileAccess.get_sha256(path) == sha, "%s: the file matches its pinned SHA-256 (the dataset's bytes)" % BLOCK)
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(raw is Dictionary and raw.get("block_id") == BLOCK and raw.get("dataset_version") == DATASET
		and raw.get("address") == "711 PACIFIC AVE", "%s: the r8 payload of 711 PACIFIC AVE" % BLOCK)
	return raw if raw is Dictionary else null

## The fresh yard as the scene judges it: every core obstacle standing, the farm's buildings.
func _yard(raw: Dictionary, farm: Dictionary) -> Dictionary:
	var data := Data.decode(raw)
	var walk := Walk.new(data)
	var planned := Scenery.plan(data, walk)
	Shade.enforce_budget(planned, data, walk)
	var layout: Array = planned.core_obstacles.layout
	var owner := {} # cell → the obstacle standing on it (its anchor cell; one rock can cover several cells)
	for item: Dictionary in layout:
		for c: Vector2i in item.get("cells", [item.cell]): owner[c] = item.cell
	var y := {"data": data, "walk": walk, "layout": layout, "owner": owner, "path": Space.protected_path(data), "farm": farm}
	_judge(y, owner)
	return y

## The preview's inputs (DynamicFarm.begin_placement) with `standing` (cell → anchor) the obstacles still there.
func _judge(y: Dictionary, standing: Dictionary) -> void:
	var cells := {}
	for c: Vector2i in standing: cells[c] = true
	var buildings := ParcelFarm.building_cells(y.farm)
	y.obstacles = cells
	y.taken = Building.blocked(cells, y.farm)
	y.walk_blocked = Building.solid(y.layout, cells).merged(y.walk.reserved).merged(buildings)
	y.clear_taken = Building.blocked({}, y.farm)
	y.clear_walk_blocked = y.walk.reserved.merged(buildings)

func _start(y: Dictionary, near: Vector2i, type: String, reach_m := Building.START_REACH_M) -> Variant:
	var base := Building.base_of(ParcelFarm.rules().buildings[type])
	return Building.start_spot(y.data, near, base, y.taken, y.path, y.walk_blocked, type, y.obstacles, y.clear_taken,
		y.clear_walk_blocked, reach_m)

## Metres from `near` to the footprint's middle.
func _metres(y: Dictionary, start: Dictionary, near: Vector2i, type: String) -> float:
	var base := Building.base_of(ParcelFarm.rules().buildings[type])
	return Vector2(start.at + Building.middle(base, start.rotation) - near).length() * float(y.data.cell_m)

func _why(y: Dictionary, start: Dictionary, type: String, cleared := false) -> String:
	var base := Building.base_of(ParcelFarm.rules().buildings[type])
	return Building.reason(y.data, start.at, base, start.rotation, y.clear_taken if cleared else y.taken, y.path,
		y.clear_walk_blocked if cleared else y.walk_blocked, type)

func _cottage_farm() -> Dictionary:
	return {"buildings": [{"id": 1, "type": "cottage", "x": COTTAGE.x, "y": COTTAGE.y, "width": 3, "depth": 3, "rotation": 0}]}

func _logic(raw: Dictionary) -> void:
	var y := _yard(raw, _cottage_farm())
	var data: Dictionary = y.data
	_check(Building.reason(data, COTTAGE, Vector2i(3, 3), 0, Building.blocked({}, {}), y.path, y.walk.reserved, "cottage") == "",
		"the cottage stands where the recording built it")
	var door := COTTAGE + Vector2i(1, -1) # the cell before its front (grid y runs against the scene's +Z, the front)
	for type: String in TYPES:
		var old = _start(y, data.spawn, type, INF)
		_check(old != null and old.at == FAR, "%s: the old search (no reach) starts at %s, about 60 cells off: %s" % [type, FAR, old])
		if old != null:
			_check(_metres(y, old, data.spawn, type) > 40.0, "%s: ...%.1f m from the spawn" % [type, _metres(y, old, data.spawn, type)])
		for near: Vector2i in [data.spawn, door]:
			var start = _start(y, near, type)
			_check(start != null, "%s from %s: a start" % [type, near])
			if start == null: continue
			var m := _metres(y, start, near, type)
			var why := _why(y, start, type)
			# A spot refused only for what stands on it reads Building.CLEAR in the preview (BuildingPlacement.move_to).
			_check(m <= Building.START_REACH_M and _why(y, start, type, true) == "",
				"%s from %s: starts %.1f m away at %s turned %d (%s), valid once cleared" % [type, near, m, start.at, start.rotation, why if why != "" else "ready"])
		# The player clears what stands on it; then that spot is ready and the preview starts there.
		var spot = _start(y, data.spawn, type)
		if spot == null: continue
		var base := Building.base_of(ParcelFarm.rules().buildings[type])
		var gone := {}
		for c in Building.cells(spot.at, base, spot.rotation, Building.type_cutouts(type)) + Building.apron_cells(type, spot.at, base, spot.rotation):
			if y.owner.has(c): gone[y.owner[c]] = true
		var standing := {}
		for c: Vector2i in y.owner:
			if not gone.has(y.owner[c]): standing[c] = y.owner[c]
		var cleared := y.duplicate()
		_judge(cleared, standing)
		var again = _start(cleared, data.spawn, type)
		_check(gone.size() > 0 and gone.size() <= 3, "%s: %d obstacles to clear there" % [type, gone.size()])
		_check(again != null and _why(cleared, again, type) == "" and _metres(cleared, again, data.spawn, type) <= Building.START_REACH_M,
			"%s: with those %d cleared the preview starts ready within reach: %s" % [type, gone.size(), again])

## Any parcel: the start exists exactly when the old one did, is valid once cleared, and is ready when a ready spot lies
## within reach (both searched from the spawn on the fresh yard, no buildings).
func _other(raw: Variant) -> void:
	if not raw is Dictionary: return
	var y := _yard(raw, {})
	var data: Dictionary = y.data
	for type: String in TYPES:
		var base := Building.base_of(ParcelFarm.rules().buildings[type])
		var old = _start(y, data.spawn, type, INF)
		var start = _start(y, data.spawn, type)
		_check((old == null) == (start == null), "%s %s: a start exactly when the old search had one" % [data.block_id, type])
		if start == null: continue
		_check(_why(y, start, type, true) == "", "%s %s: the start is valid once cleared" % [data.block_id, type])
		var ready_near := false
		for rotation in 4:
			var at = Building.nearest(data, data.spawn, base, y.taken, y.path, y.walk_blocked, rotation, type)
			if at != null and _metres(y, {"at": at, "rotation": rotation}, data.spawn, type) <= Building.START_REACH_M: ready_near = true
		_check(not ready_near or _why(y, start, type) == "", "%s %s: ready when a ready spot lies within reach" % [data.block_id, type])
		_check(_metres(y, start, data.spawn, type) <= _metres(y, old, data.spawn, type) + 0.001 or _why(y, start, type) == "",
			"%s %s: never farther than the old start unless ready" % [data.block_id, type])

# ------------------------------------------------------------------ the real scene

func _open(raw: Dictionary, store: RefCounted) -> Node:
	var args := {"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true, "farm_store": store}
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup(args)
	var state := {"ready": false}
	scene.preview_ready.connect(func(_summary): state.ready = true)
	scene.preview_error.connect(func(message): push_error(message))
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 30000
	while not state.ready and Time.get_ticks_msec() < deadline: await process_frame
	_check(state.ready, "%s opens" % raw.block_id)
	await process_frame
	var farming: Node = scene.get_node("ParcelFarming")
	deadline = Time.get_ticks_msec() + 10000
	while not farming.loaded() and Time.get_ticks_msec() < deadline: await process_frame
	await process_frame
	return farming

func _close() -> void:
	scene.queue_free()
	await process_frame
	await process_frame

## The preview of `type` from the book; its spot, judged in the scene, and what the camera shows.
func _preview(type: String) -> Dictionary:
	if not scene.book_open(): scene._build.pressed.emit()
	await process_frame
	if scene._book == null or not scene._book.keys.has(type): return {}
	scene._book.keys[type].pressed.emit()
	await process_frame
	await process_frame
	var p = scene._placement
	if p == null or p.type != type: return {}
	var camera: Camera3D = scene._camera
	var cottage: Vector3 = Building.center(scene._walk, COTTAGE, Vector2i(3, 3))
	var actor: Vector3 = scene._actor.position
	var middle: Vector3 = Building.center(scene._walk, p.at, p.base, p.rotation_steps)
	var shown := func(point: Vector3) -> bool:
		return camera.is_position_in_frustum(point) and Rect2(Vector2.ZERO, scene.get_viewport().get_visible_rect().size) \
			.has_point(camera.unproject_position(point))
	var near: Vector2i = scene._walk.cell_at(actor)
	return {"at": p.at, "rotation": p.rotation_steps, "reason": p.reason, "bar": p._bar.reason, "near": near,
		"metres": Vector2(p.at + Building.middle(p.base, p.rotation_steps) - near).length() * float(scene._walk.cell_m),
		"cottage_shown": shown.call(cottage), "actor_shown": shown.call(actor), "preview_shown": shown.call(middle)}

func _scene(raw: Dictionary) -> void:
	var dir := "user://test_start_spot_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	var store := LocalStore.new(raw.block_id, dir)
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var cottage := {"model": "cottage", "x": COTTAGE.x, "y": COTTAGE.y, "width": 3, "depth": 3, "rotation": 0, "built_at": 0}
	var seeded := ParcelFarm.empty_state()
	seeded.buildings = [cottage.merged({"id": 1, "type": "cottage"})]
	seeded.house = cottage
	seeded.welcomed_at = now - 86400000
	seeded.grants = {"watering": now}
	seeded.level = 3
	seeded.bag = {"hoe_starter": 1, "pail": 1, "blueprint_coop": 1, "blueprint_sheep_pen": 1, "wood": 15, "stone": 15}
	store._save(seeded, 2)
	var farming := await _open(raw, store)
	var first := {}
	for type: String in TYPES:
		var v := await _preview(type)
		_check(not v.is_empty(), "%s: Build %s opens its preview" % [raw.block_id, type])
		if v.is_empty(): continue
		_check(v.metres <= Building.START_REACH_M and v.reason in ["", Building.CLEAR] and v.bar == v.reason,
			"%s: the preview starts %.1f m from the player (%s) at %s turned %d: %s" % [type, v.metres, v.near, v.at, v.rotation, v.reason if v.reason != "" else "ready"])
		_check(v.preview_shown and v.cottage_shown, "%s: the camera shows the preview and the cottage (player in view: %s)" % [type, v.actor_shown])
		first[type] = v
		scene.end_placement()
		await process_frame
	# The player clears the obstacles on the coop's spot (the save's `cleared`, as the clear command keeps it).
	if first.has("coop"):
		var base := Building.base_of(ParcelFarm.rules().buildings.coop)
		var cells := Building.cells(first.coop.at, base, first.coop.rotation, Building.type_cutouts("coop")) \
			+ Building.apron_cells("coop", first.coop.at, base, first.coop.rotation)
		var cleared := {}
		for c in cells:
			if farming._obstacles.has(c): cleared[ParcelFarm.key(farming._obstacles[c])] = true
		seeded.cleared = cleared.keys()
		store._save(seeded, 3)
		await _close()
		farming = await _open(raw, store)
		var v := await _preview("coop")
		_check(not v.is_empty() and v.reason == "" and v.metres <= Building.START_REACH_M and v.cottage_shown,
			"coop: with its %d obstacles cleared the preview opens ready %.1f m from the player, the cottage in view: %s" % [cleared.size(), v.get("metres", -1.0), v])
		if not v.is_empty() and v.reason == "":
			scene._placement._bar.confirmed.emit()
			var deadline := Time.get_ticks_msec() + 5000
			while scene._placement != null and Time.get_ticks_msec() < deadline: await process_frame
			for _i in 3: await process_frame
			var coops: Array = scene.buildings_state().filter(func(b): return b.type == "coop")
			_check(coops.size() == 1 and Building.at_of(coops[0]) == v.at, "coop: Build puts it up there, beside the cottage: %s" % [coops])
	await _close()
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
