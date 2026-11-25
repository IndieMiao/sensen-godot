extends SceneTree
## C-60 in the real scene, on the local save: next to a tree, a flower and a rock the key reads
## Gather and one press puts one Timber / Wild Herb / Stone in the bag; the picked tree and rock
## fade, the flower is hidden, and none can be picked again until 24 h of server time have passed.
## Reopening keeps all of it with the same ids. The walk (reserved cells, bound profiles and every
## walkable lattice point) is identical before and after gathering and after reopening.
## `-- <farm.json> ...` (CI passes the r4 fixtures): the first file is used; default p-3139010.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const DEFAULT_FARM := "res://tests/dynamic_farm/fixtures/r4/p-3139010.json"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const DAY_MS := 86_400_000
const ITEMS := {"tree": ["wood", "Timber"], "flower": ["wild_herb", "Wild Herb"], "rock": ["stone", "Stone"]}
var checks := 0
var failures := 0
var raw: Dictionary
var dir := ""
var shift := [0]
var scene

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	raw = JSON.parse_string(FileAccess.get_file_as_string(args[0] if not args.is_empty() else DEFAULT_FARM))
	dir = "user://test_outer_gather_scene_%d" % Time.get_ticks_usec()
	var picked := await _first_visit()
	if not picked.is_empty():
		await _reopen(picked)
		await _grown_back(picked)
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
	print("OUTER_GATHER_SCENE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _store() -> RefCounted:
	var store := LocalStore.new(raw.block_id, dir)
	store.now_ms = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0) + shift[0]
	return store

func _open() -> Node:
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup({"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true, "farm_store": _store()})
	var state := {"ready": false}
	scene.preview_ready.connect(func(_summary): state.ready = true)
	scene.preview_error.connect(func(message): push_error(message))
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 30000
	while not state.ready and Time.get_ticks_msec() < deadline: await process_frame
	_check(state.ready, "own parcel opens")
	var farming: Node = scene.get_node("ParcelFarming")
	deadline = Time.get_ticks_msec() + 10000
	while farming.farm.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	await process_frame
	return farming

## Reserved cells, bound profiles per cell and every walkable 0.2 m lattice point.
func _walk_snapshot(walk: RefCounted) -> Dictionary:
	var buckets := {}
	for cell: Vector2i in walk._proxies_by_cell: buckets[cell] = walk._proxies_by_cell[cell].size()
	var open := PackedStringArray()
	for cell: Vector2i in walk.data.by_cell:
		for k in 16:
			var p: Vector3 = walk.point(cell) + Vector3((k % 4 - 1.5) * 0.2, 0, -(k / 4 - 1.5) * 0.2)
			if walk.clear_position(p): open.append("%d,%d:%d" % [cell.x, cell.y, k])
	open.sort()
	return {"reserved": walk.reserved.keys().size(), "reserved_hash": str(walk.reserved.keys()).hash(),
		"buckets": buckets, "open": "\n".join(open).sha256_text(), "open_count": open.size()}

## Instances drawn in the outer layer: [fresh, gathered].
func _drawn(farming: Node) -> Array:
	var fresh := 0
	var faded := 0
	for batch in farming._outer_root.get_children():
		if not batch is MultiMeshInstance3D or batch.is_queued_for_deletion(): continue
		if str(batch.name).begins_with("Gathered"): faded += batch.multimesh.instance_count
		else: fresh += batch.multimesh.instance_count
	return [fresh, faded]

## Stands the player on open ground just beside object `index` and faces it.
func _stand_by(farming: Node, index: int) -> bool:
	var object: Dictionary = farming.gatherables[index]
	var box: AABB = object.box
	var walk = scene._walk
	for step in 24:
		var angle := TAU * step / 24.0
		var out := Vector3(cos(angle), 0, sin(angle))
		for reach: float in [0.35, 0.5]:
			var p: Vector3 = object.origin + out * (maxf(box.size.x, box.size.z) * 0.5 + reach)
			p.y = 0.0
			if not walk.clear_position(p) or _gap(box, p) > farming.GATHER_REACH_M: continue
			walk.position = p
			scene._actor.position = p
			scene._facing = -out
			return true
	return false

func _gap(box: AABB, p: Vector3) -> float:
	var dx := maxf(maxf(box.position.x - p.x, p.x - box.end.x), 0.0)
	var dz := maxf(maxf(box.position.z - p.z, p.z - box.end.z), 0.0)
	return Vector2(dx, dz).length()

func _key(farming: Node) -> Array:
	await process_frame
	await process_frame
	return [farming._key.verb, farming._key.cost, farming._key.state]

## Presses the key and waits for the press to finish (C-73: a gather plays the harvest labour
## clip and its result lands as the clip ends). Returns {clips, moved, early} as in
## test_parcel_farming_scene: the rig's animations while busy, the distance walked and whether
## the farm changed while the clip was still playing.
func _press(farming: Node) -> Dictionary:
	var seen := {"clips": {}, "moved": 0.0, "early": false}
	var start: Vector3 = scene._walk.position
	var version: int = farming.farm_version
	var player := scene._rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	farming._key.pressed_down.emit()
	await process_frame
	var deadline := Time.get_ticks_msec() + 30000
	while farming.busy and Time.get_ticks_msec() < deadline:
		if player != null: seen.clips[player.current_animation] = true
		if scene._labour_left > 0.0 and farming.farm_version != version: seen.early = true
		await process_frame
	_check(not farming.busy, "a press finishes")
	for i in 2: await process_frame
	seen.moved = start.distance_to(scene._walk.position)
	return seen

## Picks the first standable object of each kind and gathers it. Returns {kind: id}.
func _first_visit() -> Dictionary:
	var farming := await _open()
	var walk = scene._walk
	var before := _walk_snapshot(walk)
	var objects: Array = farming.gatherables
	_check(objects.size() > 0, "the parcel has gatherable objects")
	_check(_drawn(farming) == [farming._outer_layout.size(), 0], "nothing is gathered on the first visit")
	var chosen := {}
	for i in objects.size():
		if not chosen.has(objects[i].kind) and _stand_by(farming, i): chosen[objects[i].kind] = i
	_check(chosen.size() == 3, "a tree, a flower and a rock the player can stand beside")
	if chosen.size() < 3: return {}
	# A tap on an object out of reach names it but asks to come closer.
	var far: int = chosen.tree
	scene._walk.position = farming.gatherables[far].origin + Vector3(8, 0, 8)
	scene._actor.position = scene._walk.position
	farming.picked_object = far
	_check(await _key(farming) == ["Gather", "Move closer", UiSceneAction.State.UNAVAILABLE], "out of reach: Move closer")
	# The tap ray picks the object drawn under the finger.
	var object: Dictionary = farming.gatherables[chosen.rock]
	var screen: Vector2 = scene._camera.unproject_position(object.origin + Vector3(0, object.box.size.y * 0.5, 0))
	scene._on_tapped(screen)
	_check(farming.picked_object >= 0 and farming.gatherables[farming.picked_object].box.intersects_ray(
		scene._camera.project_ray_origin(screen), scene._camera.project_ray_normal(screen)) != null, "a tap picks an object under it")
	# A tap whose ground point is a core cell keeps that cell, even through an object's bounds.
	var core := Vector2i(-1, -1)
	for cell: Vector2i in farming._data.by_cell:
		if farming._data.by_cell[cell].zone == "core":
			core = cell
			break
	var tree_box: AABB = farming.gatherables[far].box
	farming.pick(core, tree_box.get_center() + Vector3(0, 20, 0), Vector3.DOWN)
	_check(core.x >= 0 and farming.picked == core and farming.picked_object == -1, "a tap on a core cell keeps the cell")
	scene._on_tapped(screen)
	var picked := {}
	var faded := 0
	var hidden := 0
	for kind: String in ["tree", "flower", "rock"]:
		var index: int = chosen[kind]
		_stand_by(farming, index)
		farming.picked_object = index
		var key := await _key(farming)
		_check(key == ["Gather", ITEMS[kind][1], UiSceneAction.State.DEFAULT], "beside a %s the key reads Gather %s" % [kind, ITEMS[kind][1]])
		var had := int(farming.farm.bag.get(ITEMS[kind][0], 0))
		var seen := await _press(farming)
		_check(seen.clips.has("labour_harvest") and not seen.early and seen.moved < 0.01,
			"gathering a %s: no walk, the harvest clip, the result as it ends (%s)" % [kind, seen])
		_check(int(farming.farm.bag.get(ITEMS[kind][0], 0)) == had + 1, "one %s in the bag" % ITEMS[kind][0])
		_check(farming.last_gains == {ITEMS[kind][0]: 1} and ("+1 " + ITEMS[kind][1]) in _floats(farming),
			"the gain floats up and flies into the bag (%s)" % kind)
		_check(ITEMS[kind][0] in farming.bag_ids(),
			"%s shows in the bag" % ITEMS[kind][0])
		var id: String = farming.gatherables[index].id
		_check(farming.farm.gathered.has(id), "%s is recorded" % id)
		picked[kind] = id
		if farming._outer_layout[farming.gatherables[index].index].solid: faded += 1
		else: hidden += 1
		_check(_drawn(farming) == [farming._outer_layout.size() - faded - hidden, faded], "after the %s: picked ones faded or hidden" % kind)
		farming.picked_object = index
		key = await _key(farming)
		_check(key[0] == "Regrowing" and not str(key[1]).is_empty() and key[1] != ITEMS[kind][1] and key[2] == UiSceneAction.State.UNAVAILABLE,
			"the picked %s waits to grow back (%s)" % [kind, key])
		var version: int = farming.farm_version
		await _press(farming)
		_check(farming.farm_version == version and farming._toast.current_text() == "Not ready yet", "a second press sends nothing (%s)" % kind)
		# Even sent anyway, the store refuses it.
		var forced: Dictionary = await farming.send({"type": "gather", "object": id})
		_check(not forced.ok and forced.code == "NOT_RESPAWNED", "the save refuses a second %s" % kind)
	_check(faded == 2 and hidden == 1, "tree and rock fade, the flower is hidden")
	_check(_walk_snapshot(walk) == before, "gathering leaves the walk and collision as they were")
	_check(farming.farm.bag.get("wood") == 1 and farming.farm.bag.get("wild_herb") == 1 and farming.farm.bag.get("stone") == 1,
		"one of each material")
	picked["walk"] = before
	picked["ids"] = objects.map(func(o): return o.id)
	scene.queue_free()
	await process_frame
	return picked

func _reopen(picked: Dictionary) -> void:
	shift[0] += 60_000
	var farming := await _open()
	_check(farming.gatherables.map(func(o): return o.id) == picked.ids, "reopening numbers the objects the same way")
	_check(_walk_snapshot(scene._walk) == picked.walk, "the walk is the same with picked objects on reopening")
	_check(_drawn(farming) == [farming._outer_layout.size() - 3, 2], "picked objects stay faded / hidden after reopening")
	for kind: String in ["tree", "flower", "rock"]:
		var index := -1
		for i in farming.gatherables.size():
			if farming.gatherables[i].id == picked[kind]: index = i
		_check(index >= 0 and farming.gatherables[index].kind == kind, "%s is there again" % picked[kind])
		farming.picked_object = index
		var key := await _key(farming)
		_check(key[0] == "Regrowing" and key[2] == UiSceneAction.State.UNAVAILABLE, "after reopening the %s still waits" % kind)
	scene.queue_free()
	await process_frame

func _grown_back(picked: Dictionary) -> void:
	var farming := await _open()
	shift[0] += DAY_MS
	farming._clock_offset_ms += DAY_MS
	for i in 30: await process_frame
	var deadline := Time.get_ticks_msec() + 2000
	while _drawn(farming)[1] > 0 and Time.get_ticks_msec() < deadline: await process_frame
	_check(_drawn(farming) == [farming._outer_layout.size(), 0], "after 24 h every picked object is back")
	var index := -1
	for i in farming.gatherables.size():
		if farming.gatherables[i].id == picked.tree: index = i
	_stand_by(farming, index)
	farming.picked_object = index
	_check(await _key(farming) == ["Gather", "Timber", UiSceneAction.State.DEFAULT], "the tree can be gathered again")
	await _press(farming)
	_check(farming.farm.bag.get("wood") == 2, "a second Timber after 24 h")
	scene.queue_free()
	await process_frame

## The texts of the gain floats on screen (C-74).
func _floats(farming: Node) -> Array:
	return farming._ui.get_children().filter(func(n): return n is UiGainFloat).map(func(n): return n.text)
