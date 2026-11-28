extends SceneTree
## C-60 / C-236 in the real scene, on the local save. Next to a tree the key reads `Chop · 3 Energy` with the axe badge,
## next to a rock `Break · 2 Energy` (the pick), next to a wild herb `Pick · 2 Energy` (the hand) (SEN-Q-345 Q1,
## SEN-Q-342). A tree takes three presses, a rock two (or one held press), a herb one: hits before the last send nothing;
## the last sends the one `gather`, and only then the drop, `+2 Timber` / `−3 Energy` and the bag. A felled tree leaves
## its stump, a broken rock its scree, a picked herb nothing (C-234#50), until 24 h of server time have passed. Walking
## off between hits keeps them for 30 s; the stick before a hit lands takes it back; a refused last hit puts the
## object back and gives nothing. Reopening keeps all of it with the same ids. The walk (reserved cells, bound
## profiles and every walkable lattice point) is identical before and after gathering and after reopening.
## `-- <farm.json> ...` (CI passes the r4 fixtures): the first file is used; default p-3139010.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const DEFAULT_FARM := "res://tests/dynamic_farm/fixtures/r4/p-3139010.json"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const DAY_MS := 86_400_000
const ITEMS := {"tree": ["wood", "Timber"], "flower": ["wild_herb", "Wild Herb"], "rock": ["stone", "Stone"]}
const GatherFx = preload("res://modules/dynamic_farm/gather_fx.gd")
## Per kind (SEN-Q-342): [key verb, hits, Energy, amount].
const NUMBERS := {"tree": ["Chop", 3, 3, 2], "rock": ["Break", 2, 2, 1], "flower": ["Pick", 1, 2, 1]}

## Answers every command with a refusal (the store's own reply stands for a server that disagreed).
class Refusing:
	extends RefCounted
	var inner: RefCounted
	func _init(store: RefCounted) -> void: inner = store
	func enter() -> Dictionary: return await inner.enter()
	func send(_version: int, _commands: Array) -> Dictionary:
		var now: Dictionary = await inner.enter()
		return {"ok": false, "code": "NOT_RESPAWNED", "detail": {}, "farm": now.get("farm"), "farm_version": now.get("farm_version"),
			"server_time": now.get("server_time")}
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

## Instances drawn in the outer layer: [growing, spent pieces (stumps, scree)].
func _drawn(farming: Node) -> Array:
	var fresh := 0
	var spent := 0
	for batch in farming._outer_root.get_children():
		if not batch is MultiMeshInstance3D or batch.is_queued_for_deletion(): continue
		if str(batch.name).begins_with("Spent_"): spent += batch.multimesh.instance_count
		else: fresh += batch.multimesh.instance_count
	return [fresh, spent]

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

## Presses the key (a tap, or held down until the press is over with `hold`) and waits for it to finish. Returns
## {clips, moved, early, versions}: the rig's clips meanwhile, the distance walked, whether the farm changed before the
## last hit's contact and the farm versions seen.
func _press(farming: Node, hold := false) -> Dictionary:
	var seen := {"clips": {}, "moved": 0.0, "early": false, "floats": []}
	var start: Vector3 = scene._walk.position
	var player := scene._rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	farming._key.pressed_down.emit()
	if not hold: farming._key.released.emit()
	await process_frame
	var deadline := Time.get_ticks_msec() + 30000
	while (farming.busy or farming.swinging) and Time.get_ticks_msec() < deadline:
		if player != null: seen.clips[player.current_animation] = true
		for text in _floats(farming): if not text in seen.floats: seen.floats.append(text)
		await process_frame
	if hold: farming._key.released.emit()
	_check(not farming.busy and not farming.swinging, "a press finishes")
	for i in 2: await process_frame
	seen.moved = start.distance_to(scene._walk.position)
	return seen

## Waits until the stage has let the object go (its last clip played out), at most a few seconds.
func _settled(farming: Node) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while farming.gather_stage.active() and Time.get_ticks_msec() < deadline: await process_frame
	for i in 3: await process_frame

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
	_check(await _key(farming) == ["Chop", "Move closer", UiSceneAction.State.UNAVAILABLE], "out of reach: Move closer")
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
	var spent := 0
	var hidden := 0
	for kind: String in ["tree", "flower", "rock"]:
		var index: int = chosen[kind]
		var numbers: Array = NUMBERS[kind]
		_stand_by(farming, index)
		farming.picked_object = index
		var key := await _key(farming)
		# C-236: the object's own verb and its whole price; the badge is its tool.
		_check(key == [numbers[0], "%d Energy" % numbers[2], UiSceneAction.State.DEFAULT], "beside a %s the key reads %s: %s" % [kind, numbers, key])
		_check(farming._keys.tool_icon == GatherFx.tool_icon(GatherFx.OUTER[kind]), "the %s's tool on the badge" % kind)
		var had := int(farming.farm.bag.get(ITEMS[kind][0], 0))
		var energy_had: int = farming.energy_value()
		var id: String = farming.gatherables[index].id
		if kind == "tree": await _walk_off_and_back(farming, index)
		# Hits before the last send nothing (SEN-Q-345 Q3): a tap is one hit.
		var floats := []
		for hit in range(farming.damage.done(id, Time.get_ticks_msec()), numbers[1] - 1):
			var version: int = farming.farm_version
			var seen := await _press(farming, kind == "rock")
			floats = seen.floats
			if kind == "rock": break   # held down: the rock's two hits in one press
			_check(farming.farm_version == version and farming.energy_value() == energy_had and int(farming.farm.bag.get(ITEMS[kind][0], 0)) == had,
				"hit %d of the %s sends nothing" % [hit + 1, kind])
			_check(farming.damage.done(id, Time.get_ticks_msec()) == hit + 1, "the %s has taken %d hits" % [kind, hit + 1])
			_check(seen.clips.has(GatherFx.clip(kind)) and seen.moved < 0.01, "the %s is struck with its own clip (%s)" % [kind, seen])
			_check(farming.gather_stage.active() and farming.gather_stage.key() == id, "the %s's own scene stands in for it" % kind)
			# (Headless, the dummy renderer keeps no instance transforms: the stage's record of the one it hid is checked.)
			var hid: Array = farming.gather_stage._hidden
			_check(hid.size() == 3 and hid[0] == farming._outer_instance(farming.gatherables[index].index)[0],
				"its batch instance is hidden meanwhile")
		if kind != "rock":
			var seen := await _press(farming)
			floats = seen.floats
			_check(seen.clips.has(GatherFx.clip(kind)) and seen.moved < 0.01, "the last hit on the %s plays its clip (%s)" % [kind, seen])
		var played: Array = farming.gather_stage.played
		_check("finish %s" % GatherFx.OUTER[kind] in played, "the %s's last hit plays its end (%s)" % [kind, played.slice(-6)])
		_check(int(farming.farm.bag.get(ITEMS[kind][0], 0)) == had + numbers[3], "%d %s in the bag" % [numbers[3], ITEMS[kind][0]])
		_check(farming.energy_value() == energy_had - numbers[2], "the %s cost its %d Energy once" % [kind, numbers[2]])
		_check(farming.last_gains == {ITEMS[kind][0]: numbers[3]} and ("+%d %s" % [numbers[3], ITEMS[kind][1]]) in floats
			and ("−%d Energy" % numbers[2]) in floats, "the gain and the Energy float up (%s: %s)" % [kind, floats])
		if kind == "tree":
			_check(played.find("landed tree") >= 0 and played.find("drop wood") > played.find("landed tree"),
				"the log pops out only once the tree is down (%s)" % [played])
		if kind == "rock":
			_check("drop stone" in played, "a stone pops out of the pieces")
			var c: Array = farming.contacts.slice(-2)
			_check(c.size() == 2 and int(c[1]) - int(c[0]) >= 880, "held down, the two hits land 0.9 s apart (%s)" % [c])
		_check(ITEMS[kind][0] in farming.bag_ids(), "%s shows in the bag" % ITEMS[kind][0])
		_check(farming.farm.gathered.has(id), "%s is recorded" % id)
		picked[kind] = id
		await _settled(farming)
		if farming._outer_layout[farming.gatherables[index].index].solid: spent += 1
		else: hidden += 1
		_check(_drawn(farming) == [farming._outer_layout.size() - spent - hidden, spent],
			"after the %s: a stump or scree is left, a herb leaves nothing (%s)" % [kind, _drawn(farming)])
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
	_check(spent == 2 and hidden == 1, "tree and rock leave a stump and scree, the herb is gone")
	var stumps: Array = farming._outer_root.get_children().filter(func(b): return str(b.name).begins_with("Spent_"))
	_check(stumps.size() == 2, "one stump batch, one scree batch")
	await _refused(farming, chosen)
	_check(_walk_snapshot(walk) == before, "gathering leaves the walk and collision as they were")
	_check(farming.farm.bag.get("wood") == 2 and farming.farm.bag.get("wild_herb") == 1 and farming.farm.bag.get("stone") == 1,
		"2 Timber, 1 Wild Herb, 1 Stone")
	picked["walk"] = before
	picked["ids"] = objects.map(func(o): return o.id)
	scene.queue_free()
	await process_frame
	return picked

## The stick before a hit lands takes it back; walking off after one keeps it (30 s), coming back goes on from there.
func _walk_off_and_back(farming: Node, index: int) -> void:
	var id: String = farming.gatherables[index].id
	farming._key.pressed_down.emit()
	farming._key.released.emit()
	await process_frame
	scene._movement = Vector2(1, 0)
	var deadline := Time.get_ticks_msec() + 3000
	while farming.swinging and Time.get_ticks_msec() < deadline: await process_frame
	scene._movement = Vector2.ZERO
	_check(farming.damage.done(id, Time.get_ticks_msec()) == 0, "the stick during the wind-up takes the hit back")
	_stand_by(farming, index)
	farming.picked_object = index
	await _key(farming)
	await _press(farming)
	_check(farming.damage.done(id, Time.get_ticks_msec()) == 1, "one chop landed")
	var away: Vector3 = farming.gatherables[index].origin + Vector3(6, 0, 6)
	scene._walk.position = away
	scene._actor.position = away
	for i in 10: await process_frame
	_stand_by(farming, index)
	farming.picked_object = index
	await _key(farming)
	_check(farming.damage.done(id, Time.get_ticks_msec()) == 1, "walking off and back keeps the chop (30 s)")
	var memory := GatherFx.damage()
	memory.hit(id, 0)
	_check(memory.done(id, 30000) == 1 and memory.done(id, 30001) == 0, "after 30 s the hits are forgotten")
	_check(int(GatherFx.common().min_hit_interval_ms) == 900, "hits land at least 0.9 s apart (SEN-Q-342, C-236#14)")
	_check(GatherFx.stage("tree", 1, 3) == 0 and GatherFx.stage("tree", 2, 3) == 1 and GatherFx.stage("tree", 4, 5) == 2,
		"scar stages by >= the approved thresholds")

## A last hit the server refuses (another tree, the store standing in for a server that disagreed): the tree stands up
## again, nothing is given or charged, nothing is recorded.
func _refused(farming: Node, chosen: Dictionary) -> void:
	var index := -1
	for i in farming.gatherables.size():
		if farming.gatherables[i].kind == "tree" and i != chosen.tree and _stand_by(farming, i):
			index = i
			break
	if index < 0: return
	farming.picked_object = index
	await _key(farming)
	var real: RefCounted = farming.store
	farming.store = Refusing.new(real)
	var bag: Dictionary = farming.farm.bag.duplicate()
	var energy: int = farming.energy_value()
	await _press(farming, true)
	farming.store = real
	_check("refuse tree" in farming.gather_stage.played, "a refused last hit puts the tree back")
	_check(farming.farm.bag == bag and farming.energy_value() == energy and not farming.farm.gathered.has(farming.gatherables[index].id),
		"refused: nothing given, nothing charged")
	await _settled(farming)
	_check(not farming.gather_stage.active(), "the stage lets the tree go again")

func _reopen(picked: Dictionary) -> void:
	shift[0] += 60_000
	var farming := await _open()
	_check(farming.gatherables.map(func(o): return o.id) == picked.ids, "reopening numbers the objects the same way")
	_check(_walk_snapshot(scene._walk) == picked.walk, "the walk is the same with picked objects on reopening")
	_check(_drawn(farming) == [farming._outer_layout.size() - 3, 2], "the stump and scree are still there after reopening, the herb still gone")
	for kind: String in ["tree", "flower", "rock"]:
		var index := -1
		for i in farming.gatherables.size():
			if farming.gatherables[i].id == picked[kind]: index = i
		_check(index >= 0 and farming.gatherables[index].kind == kind, "%s is there again" % picked[kind])
		farming.picked_object = index
		var key := await _key(farming)
		_check(key[0] == "Regrowing" and key[2] == UiSceneAction.State.UNAVAILABLE, "after reopening the %s still waits" % kind)
	_check(farming.damage.done(picked.tree, Time.get_ticks_msec()) == 0, "leaving the scene drops the hits")
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
	_check(await _key(farming) == ["Chop", "3 Energy", UiSceneAction.State.DEFAULT], "the tree can be chopped again")
	await _press(farming, true)
	_check(farming.farm.bag.get("wood") == 4, "held down, three chops fell it again: 2 more Timber after 24 h")
	scene.queue_free()
	await process_frame

## The texts of the gain floats on screen (C-74).
func _floats(farming: Node) -> Array:
	return farming._ui.get_children().filter(func(n): return n is UiGainFloat).map(func(n): return n.text)
