extends SceneTree
## C-34 in the real scene, on the local save: one press each clears, tills and sows; the
## carrot waits 60 s; harvest fills the bag; the three refusals show on the key; reopening
## keeps everything and grants nothing. C-73: a press first walks the player beside the cell,
## faces it and plays the labour clip; the result shows as the clip ends; a cell with nowhere to
## stand says so and sends nothing; the stick cancels a walk; the parcel stays covered until the
## save is applied. C-33: opening the house placement gives up a press still walking. Run in the private preview project (README), optionally
## with `-- <farm.json>`; without it the synthetic fixture parcel is used.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
var checks := 0
var failures := 0
var raw: Dictionary
var dir := ""
var shift := [0]
var scene

## Fails the first `failures` entries like a dropped connection, then answers from the local save.
class FlakyStore extends RefCounted:
	var inner: RefCounted
	var failures := 0
	var calls := 0
	var first_call_ready := false
	var covered_at_call := false
	var scene: Node
	func _init(p_inner: RefCounted, p_failures: int) -> void:
		inner = p_inner
		failures = p_failures
	func enter() -> Dictionary:
		if calls == 0 and scene != null:
			first_call_ready = scene._ready_sent
			covered_at_call = scene.get_node("ParcelFarming")._cover.visible
		calls += 1
		if failures > 0:
			failures -= 1
			return {"ok": false, "code": "NETWORK", "index": 0}
		return inner.enter()
	func send(base_version: int, commands: Array) -> Dictionary: return inner.send(base_version, commands)

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	raw = JSON.parse_string(FileAccess.get_file_as_string(args[0])) if not args.is_empty() else Fixture.farm()
	dir = "user://test_parcel_farming_scene_%d" % Time.get_ticks_usec()
	await _first_visit()
	await _reopen()
	await _placement_takes_over()
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
	print("PARCEL_FARMING_SCENE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _store() -> RefCounted:
	var store := LocalStore.new(raw.block_id, dir)
	store.now_ms = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0) + shift[0]
	return store

func _open(store: RefCounted = null) -> Node:
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup({"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true, "farm_store": store if store != null else _store()})
	if store is FlakyStore: store.scene = scene
	var state := {"ready": false}
	scene.preview_ready.connect(func(_summary): state.ready = true)
	scene.preview_error.connect(func(message): push_error(message))
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 30000
	while not state.ready and Time.get_ticks_msec() < deadline: await process_frame
	_check(state.ready, "own parcel opens")
	await process_frame
	return scene.get_node("ParcelFarming")

## Presses the key on `cell` and waits for the press to finish (walk, labour clip, result).
## Returns what was seen: {clips, moved, early}: the rig's animations while busy, the distance
## from the start, and whether the farm changed while the labour clip was still playing.
func _press(farming: Node, cell: Vector2i) -> Dictionary:
	farming.pick(cell)
	await process_frame
	await process_frame
	var seen := {"clips": {}, "moved": 0.0, "early": false}
	var start: Vector3 = scene._walk.position
	var version: int = farming.farm_version
	var player := scene._rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	farming._key.pressed_down.emit()
	var deadline := Time.get_ticks_msec() + 30000
	while farming.busy and Time.get_ticks_msec() < deadline:
		if player != null: seen.clips[player.current_animation] = true
		if scene._labour_left > 0.0 and farming.farm_version != version: seen.early = true
		await process_frame
	_check(not farming.busy, "a press finishes")
	await process_frame
	seen.moved = start.distance_to(scene._walk.position)
	return seen

## The player stands beside `cells` (not on them) and faces them.
func _beside(cells: Array) -> bool:
	var here: Vector2i = scene._walk.cell_at(scene._walk.position)
	if here in cells: return false
	var centre := Vector3.ZERO
	for cell: Vector2i in cells: centre += scene._walk.point(cell)
	var to: Vector3 = centre / cells.size() - scene._walk.position
	to.y = 0
	var near := false
	for cell: Vector2i in cells:
		var d: Vector2i = cell - here
		near = near or (absi(d.x) <= 1 and absi(d.y) <= 1)
	return near and scene._facing.dot(to.normalized()) > 0.9

func _key(farming: Node, cell: Vector2i) -> Array:
	farming.pick(cell)
	await process_frame
	await process_frame
	return [farming._key.verb, farming._key.cost, farming._key.state]

func _obstacle_instances(farming: Node) -> int:
	var count := 0
	for batch in farming._core_root.get_children():
		if batch is MultiMeshInstance3D: count += batch.multimesh.instance_count
	return count

func _first_visit() -> void:
	# Stand-in for C-33: a cottage already placed in the save before the first entry.
	var data: Dictionary = scene_data()
	var house_at := _free_block(data)
	var seeded := ParcelFarm.empty_state()
	seeded.house = {"model": "cottage", "x": house_at.x, "y": house_at.y, "width": 3, "depth": 3, "rotation": 0, "built_at": 0}
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join(raw.block_id.validate_filename() + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"block_id": raw.block_id, "farm_version": 0, "farm": seeded}))
	file.close()
	var flaky := FlakyStore.new(_store(), 2)
	var farming := await _open(flaky)
	_check(flaky.calls == 2 and flaky.first_call_ready, "entry starts once the scene is up and retries a lost request once")
	_check(flaky.covered_at_call, "the parcel is covered until the save is applied")
	_check(farming.farm.is_empty() and farming._key.visible and farming._key.verb == "Retry", "a failed entry offers Retry")
	_check(farming._cover.visible and farming._cover_label.text == farming.get_script().OPEN_FAILED, "a failed entry stays covered and says so")
	var spawn_at: Vector3 = scene._walk.position
	scene._movement = Vector2(1, 0)
	for _i in 5: await process_frame
	scene._movement = Vector2.ZERO
	_check(scene._walk.position == spawn_at, "no walking before the save is applied")
	farming._key.pressed_down.emit()
	await process_frame
	await process_frame
	_check(not farming._cover.visible, "the cover lifts once the save is applied")
	_check(farming.farm.bag.get("hoe_starter") == 1 and farming.farm.bag.get("seed_carrot") == 3, "first entry: 1 hoe, 3 carrot seeds")
	_check(farming._toast.current_text().begins_with("Received Starter Hoe ×1, Carrot Seeds ×3"), "the gift is announced")
	_check(not scene._hint.visible, "no preview hint on one's own farm")
	var chips: Array = farming._bag.get_children().map(func(c): return str(c.name))
	_check(chips == ["coins", "hoe_starter", "seed_carrot", "blueprint_cottage"], "bag row: coins, hoe, seeds and the cottage blueprint (C-59)")
	_check(farming._bag.get_child(0).get_child(1).text == "0", "a new parcel starts with 0 coins (C-59)")
	var walk = scene._walk
	# Clear a tree (a 2×2 block) with one press on a cell other than its anchor.
	var tree := {}
	for item: Dictionary in farming._core_plan.layout:
		if item.solid and item.get("cells", []).size() > 1:
			tree = item
			break
	_check(not tree.is_empty(), "the fixture has a tree")
	var obstacle: Vector2i = tree.get("cell", Vector2i(-1, -1))
	var block: Array = tree.get("cells", [])
	_check(not walk.clear_position(walk.point(obstacle)), "the obstacle blocks the walk")
	var before := _obstacle_instances(farming)
	var key: Array
	var all_clear := block.size() == 4
	for at: Vector2i in block:
		all_clear = all_clear and farming.obstacle_cells().has(at) and await _key(farming, at) == ["Clear", "Free", UiSceneAction.State.DEFAULT]
	_check(all_clear, "every cell under the tree offers Clear, none Till")
	_check(not _beside(block), "the tree starts out of reach")
	# The stick cancels the walk: nothing is sent.
	farming.pick(block.back())
	await process_frame
	var version: int = farming.farm_version
	farming._key.pressed_down.emit()
	for _i in 3: await process_frame
	var walking: bool = not scene._route.is_empty() and farming.busy and farming.target == block.back()
	scene._movement = Vector2(0, 1)
	await process_frame
	scene._movement = Vector2.ZERO
	await process_frame
	_check(walking and scene._route.is_empty() and not farming.busy and farming.farm_version == version and farming.farm.cleared.is_empty(), "the stick cancels a walk, nothing sent")
	var seen := await _press(farming, block.back())
	_check(seen.moved > data.cell_m and _beside(block), "the player walks beside the tree and faces it")
	_check(seen.clips.has("labour_clear") and not seen.early, "the clear clip plays, the tree goes as it ends")
	_check(farming.farm.cleared == [ParcelFarm.key(obstacle)] and _obstacle_instances(farming) == before - 1, "one press clears it, named by its anchor")
	var freed := true
	for at: Vector2i in block:
		freed = freed and not farming.obstacle_cells().has(at) and (await _key(farming, at))[0] != "Clear"
	_check(freed and walk.clear_position(walk.point(obstacle)), "and frees the whole block and the walk")
	_check(farming.farm.bag.get("hoe_starter") == 1, "clearing costs nothing")
	# Till, sow, wait, harvest.
	var cell := _free_cell(data, farming)
	_check(await _key(farming, cell) == ["Till", "Free", UiSceneAction.State.DEFAULT], "a free core cell offers Till")
	seen = await _press(farming, cell)
	_check(_beside([cell]) and seen.clips.has("labour_till") and not seen.early, "till: beside the cell, facing it, the till clip")
	_check(ParcelFarm.key(cell) in farming.farm.tilled and farming._soil.counts().get("soil", 0) == 1, "one press tills, soil drawn")
	_check(await _key(farming, cell) == ["Sow", "Carrot", UiSceneAction.State.DEFAULT], "tilled soil offers Sow")
	seen = await _press(farming, cell)
	_check(seen.moved < 0.01 and seen.clips.has("labour_sow"), "already beside it: no walk, the sow clip")
	var crop: Dictionary = farming.farm.crops.get(ParcelFarm.key(cell), {})
	_check(crop.get("ripe_at", 0) - crop.get("planted_at", 0) == 60000 and farming.farm.bag.seed_carrot == 2, "sown: 60 s to ripen, one seed used")
	key = await _key(farming, cell)
	_check(key[0] == "Growing" and key[1] in ["Ready in 1:00", "Ready in 0:59", "Ready in 0:58"] and key[2] == UiSceneAction.State.UNAVAILABLE, "growing counts down")
	await _press(farming, cell)
	_check(farming._toast.current_text() == "Not ripe yet" and not farming.farm.bag.has("crop_carrot"), "no harvest before 60 s")
	# The refusals: outside the core, on the protected path, under the house.
	_check(await _key(farming, _outside_cell(data)) == ["Till", "Not farmland", UiSceneAction.State.UNAVAILABLE], "outside the core refuses")
	_check(await _key(farming, data.spawn) == ["Till", "On the path", UiSceneAction.State.UNAVAILABLE], "the protected path refuses")
	var under_house := house_at
	for at: Vector2i in ParcelFarm.house_cells(farming.farm):
		if not farming._obstacles.has(at): under_house = at
	_check(await _key(farming, under_house) == ["Till", "House here", UiSceneAction.State.UNAVAILABLE], "the house refuses")
	version = farming.farm_version
	await _press(farming, data.spawn)
	_check(farming.farm_version == version and farming._toast.current_text() == "On the path", "a refused press sends nothing")
	# A free cell with nowhere to stand: fence its eight neighbours off the walk.
	var fenced := _free_cell(data, farming, [cell])
	var fence: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0: continue
			var post := Proxy.new({"shape": "cylinder", "radius_m": 0.4, "height_m": 1.0, "center_xz_m": [0, 0], "solid": true},
				Transform3D(Basis(), walk.point(fenced + Vector2i(dx, dy))), 1.0)
			walk.add_prop(post)
			fence.append(post)
	var at_start: Vector3 = walk.position
	seen = await _press(farming, fenced)
	_check(farming._toast.current_text() == farming.get_script().UNREACHABLE and farming.farm_version == version and seen.moved < 0.01, "nowhere to stand: says so, sends nothing")
	for post in fence: walk.remove_prop(post)
	_check(walk.position == at_start, "and the player stays put")
	shift[0] += 60000
	farming._clock_offset_ms += 60000
	_check(await _key(farming, cell) == ["Harvest", "Free", UiSceneAction.State.DEFAULT], "ripe after 60 s")
	seen = await _press(farming, cell)
	_check(_beside([cell]) and seen.clips.has("labour_harvest") and not seen.early, "harvest: beside the cell, the harvest clip")
	_check(farming.farm.bag.get("crop_carrot") == 1 and farming._toast.current_text() == "+1 Carrot", "harvest goes to the bag")
	_check(ParcelFarm.key(cell) in farming.farm.tilled and farming._crops.counts().get("C", 0) == 0, "the soil stays tilled, the carrot is gone")
	await _press(farming, cell)
	await _press(farming, cell)
	_check(farming.farm.crops.has(ParcelFarm.key(cell)), "sow again for the reopen check")
	scene.queue_free()
	await process_frame

func _reopen() -> void:
	shift[0] += 20000
	var flaky := FlakyStore.new(_store(), 1)
	var farming := await _open(flaky)
	_check(flaky.calls == 2 and not farming.unavailable and farming._key.verb != "Retry", "one lost entry request is retried without Retry")
	_check(flaky.covered_at_call and not farming._cover.visible, "covered while entering, uncovered with the save applied")
	_check(farming.farm.bag.get("seed_carrot") == 1 and farming.farm.bag.get("hoe_starter") == 1, "reopening grants nothing more")
	_check(not farming._toast.current_text().begins_with("Received"), "no second gift toast")
	_check(farming.farm.cleared.size() == 1 and _obstacle_instances(farming) == farming._core_plan.layout.size() - 1, "the cleared obstacle stays gone")
	_check(farming._soil.counts().get("soil", 0) == 1, "tilled soil is still drawn")
	var key: Array
	for crop_key: String in farming.farm.crops:
		key = await _key(farming, ParcelFarm.parse_key(crop_key))
		_check(farming.farm.crops[crop_key].ripe_at - farming.server_now() <= 40000, "the original ripening time is kept")
	_check(key.size() == 3 and key[0] == "Growing", "still growing after reopening")
	scene.queue_free()
	await process_frame

## C-33 on a fresh save (the welcome blueprint, no house): Build Cottage while a press is still
## walking to its cell ends the walk and sends nothing; the player holds still under the preview.
func _placement_takes_over() -> void:
	var house_dir := dir + "_house"
	var farming := await _open(LocalStore.new(raw.block_id, house_dir))
	_check(scene._build.visible, "a fresh save offers Build Cottage")
	var far := _free_cell(scene_data(), farming, [scene._walk.cell_at(scene._walk.position)])
	farming.pick(far)
	await process_frame
	var version: int = farming.farm_version
	farming._key.pressed_down.emit()
	for _i in 3: await process_frame
	var walking: bool = not scene._route.is_empty() and farming.busy
	scene._build.activated.emit()
	await process_frame
	var at: Vector3 = scene._walk.position
	for _i in 5: await process_frame
	_check(walking and scene._placement != null and scene._route.is_empty() and not farming.busy,
		"opening the placement gives up the walk")
	_check(scene._walk.position == at and farming.farm_version == version and farming.farm.tilled.is_empty(),
		"the player holds still and nothing was sent")
	scene.end_house_placement()
	scene.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(house_dir): DirAccess.remove_absolute(house_dir.path_join(name))
	DirAccess.remove_absolute(house_dir)

func scene_data() -> Dictionary:
	return preload("res://modules/dynamic_farm/farm_data.gd").decode(raw)

## A 3×3 core block away from the path and the arrival, for the stand-in house.
func _free_block(data: Dictionary) -> Vector2i:
	var path := preload("res://modules/dynamic_farm/parcel_space.gd").protected_path(data)
	for cell: Dictionary in data.cells:
		var at := Vector2i(cell.x, cell.y)
		var ok := true
		for dy in 3:
			for dx in 3:
				var c := at + Vector2i(dx, dy)
				ok = ok and data.by_cell.has(c) and data.by_cell[c].zone == "core" and not path.has(c)
		if ok and (at - data.spawn).length() > 6: return at
	return Vector2i(-1, -1)

func _free_cell(data: Dictionary, farming: Node, except: Array = []) -> Vector2i:
	var house := ParcelFarm.house_cells(farming.farm)
	var obstacles: Dictionary = farming.obstacle_cells()
	for cell: Dictionary in data.cells:
		var at := Vector2i(cell.x, cell.y)
		if cell.zone == "core" and not farming._path.has(at) and not obstacles.has(at) and not house.has(at) and not ParcelFarm.key(at) in farming.farm.tilled:
			var apart := true
			for other: Vector2i in except: apart = apart and (absi(other.x - at.x) > 2 or absi(other.y - at.y) > 2)
			if apart: return at
	return Vector2i(-1, -1)

func _outside_cell(data: Dictionary) -> Vector2i:
	for cell: Dictionary in data.cells:
		if cell.zone == "extension": return Vector2i(cell.x, cell.y)
	return Vector2i(-1, -1)
