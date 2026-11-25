extends SceneTree
## C-34 in the real scene, on the local save: one press each clears, tills and sows; the
## carrot waits 60 s; harvest fills the bag; the three refusals show on the key; reopening
## keeps everything and grants nothing. C-73: a press first walks the player beside the cell,
## faces it and plays the labour clip; the result shows as the clip ends; a cell with nowhere to
## stand says so and sends nothing; the stick cancels a walk; the parcel stays covered until the
## save is applied. C-33: opening the house placement gives up a press still walking. C-114: Build pops the
## cottage in with dust round it; reopening shows it still, without dust. Run in the private preview project (README), optionally
## with `-- <farm.json>`; without it the synthetic fixture parcel is used.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
const House = preload("res://modules/dynamic_farm/farm_house.gd")
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
	await _house_pops_once()
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
	_check(farming.farm.is_empty() and farming._keys.visible and farming._key.verb == "Retry", "a failed entry offers Retry")
	_check(not farming._bar.visible, "no quick bar before the save is applied")
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
	_check(farming.last_gains == {"hoe_starter": 1, "seed_carrot": 3, "blueprint_cottage": 1}, "the gift is announced item by item, the blueprint too")
	_check(_floats(farming) == ["+1 Starter Hoe", "+3 Carrot Seeds", "+1 Cottage Blueprint"], "one float per gift item")
	_check(_flights(farming) == 3, "each gift item flies into the bag")
	_check(not farming._toast.current_text().begins_with("Received"), "no gift toast")
	_check(not scene._hint.visible, "no preview hint on one's own farm")
	_check(_tip(farming) == "Pick a spot in your yard and press Till.", "the guide's card teaches tilling once the house stands (C-35): " + _tip(farming))
	await process_frame
	var tip_rect: Rect2 = farming._tip.get_global_rect()
	_check(tip_rect.position.y >= scene._header.get_global_rect().end.y and tip_rect.end.y < farming._bar.get_global_rect().position.y,
		"the card sits under the top bar, above the quick bar: %s / %s / %s" % [tip_rect, scene._header.get_global_rect(), farming._bar.get_global_rect()])
	farming._tip.tapped.emit()
	_check(_tip(farming) == "", "a tap closes the card")
	_check(farming._bar.visible and _bar_counts(farming) == {"hoe_starter": 1, "seed_carrot": 3, "blueprint_cottage": 1}, "quick bar shows hoe, seeds and the blueprint")
	_check(farming._bar.slots[2].icon == load("res://modules/dynamic_farm/parcel_items.gd").icon_of("blueprint_cottage"), "the blueprint has the parcel adapter's placeholder icon (C-59)")
	_check(scene._coins_capsule.visible and scene._coins.text == "0", "the top bar shows the parcel's coins, 0 on a new parcel (C-59)")
	scene._on_farm_changed(farming.farm.merged({"coins": 12}, true))
	_check(scene._coins.text == "12", "the coins follow the save")
	scene._on_farm_changed(farming.farm)
	await _held(farming)
	_check(farming._keys.tool_icon != null and not farming._keys.switch_visible, "the action key shows the hoe, no switch")
	await _bag_drawer(farming)
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
	_check(_tip(farming) == "Press Sow to plant Carrot Seeds in your soil.", "the next step's card comes back after tilling: " + _tip(farming))
	_check(await _key(farming, cell) == ["Sow", "Carrot", UiSceneAction.State.DEFAULT], "tilled soil offers Sow")
	seen = await _press(farming, cell)
	_check(seen.moved < 0.01 and seen.clips.has("labour_sow"), "already beside it: no walk, the sow clip")
	var crop: Dictionary = farming.farm.crops.get(ParcelFarm.key(cell), {})
	_check(crop.get("ripe_at", 0) - crop.get("planted_at", 0) == 60000 and farming.farm.bag.seed_carrot == 2, "sown: 60 s to ripen, one seed used")
	_check(_bar_counts(farming).get("seed_carrot") == 2, "the quick bar's seed count follows at once")
	_check(_tip(farming) == "", "no card while the carrot grows")
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
	await create_timer(farming.get_script().REDRAW_S * 2).timeout
	_check(_tip(farming) == "Your carrot is ripe. Press Harvest!", "a ripe carrot brings the harvest card: " + _tip(farming))
	seen = await _press(farming, cell)
	_check(_beside([cell]) and seen.clips.has("labour_harvest") and not seen.early, "harvest: beside the cell, the harvest clip")
	_check(farming.farm.bag.get("crop_carrot") == 1 and farming.last_gains == {"crop_carrot": 1}, "harvest goes to the bag")
	_check("+1 Carrot" in _floats(farming) and _flights(farming) >= 1, "the harvest floats up and flies into the bag")
	_check(_bar_counts(farming).get("crop_carrot") == 1, "the quick bar shows the carrot")
	_check(_tip(farming) == "Head back to the map and tap Market to sell your carrot.", "after the first harvest the card sends the carrot to the Market (C-61): " + _tip(farming))
	_check(ParcelFarm.key(cell) in farming.farm.tilled and farming._crops.counts().get("C", 0) == 0, "the soil stays tilled, the carrot is gone")
	await _press(farming, cell)
	await _press(farming, cell)
	_check(farming.farm.crops.has(ParcelFarm.key(cell)), "sow again for the reopen check")
	scene.queue_free()
	await process_frame

func _reopen() -> void:
	shift[0] += 20000
	# The standalone package keeps Journey's zh_CN locale (P0's language setup never runs); the parcel stays English
	# without touching the global locale, so Journey's own UI over it keeps the player's language (C-77).
	var outside := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	var flaky := FlakyStore.new(_store(), 1)
	var farming := await _open(flaky)
	_check(TranslationServer.get_locale() == "zh_CN", "the parcel leaves the global locale alone while it is on screen")
	var overlay := Label.new()   # a global UI over the parcel, outside its non-translating tree
	overlay.text = "Carrot"
	root.add_child(overlay)
	await process_frame
	_check(overlay.can_auto_translate() and overlay.tr("Carrot") == "胡萝卜", "a global UI over the parcel still shows 中文")
	overlay.queue_free()
	_check(flaky.calls == 2 and not farming.unavailable and farming._key.verb != "Retry", "one lost entry request is retried without Retry")
	_check(flaky.covered_at_call and not farming._cover.visible, "covered while entering, uncovered with the save applied")
	_check(farming.farm.bag.get("seed_carrot") == 1 and farming.farm.bag.get("hoe_starter") == 1, "reopening grants nothing more")
	_check(farming.last_gains.is_empty() and _floats(farming).is_empty(), "no second gift announced")
	_check(_bar_counts(farming) == {"hoe_starter": 1, "seed_carrot": 1, "crop_carrot": 1, "blueprint_cottage": 1}, "the quick bar matches the save")
	var names: Array = farming._bar.cells().slice(0, 3).map(func(c): return str(c.get("_name").text).replace("\n", " "))
	_check(names == ["Starter Hoe", "Carrot Seeds", "Carrot"], "quick bar names stay English: %s" % [names])
	scene.suspend()
	_check(TranslationServer.get_locale() == "zh_CN", "suspended, the locale is unchanged")
	scene.resume()
	await process_frame
	_check(TranslationServer.get_locale() == "zh_CN", "resumed, the locale is still unchanged")
	names = farming._bar.cells().slice(0, 3).map(func(c): return str(c.get("_name").text).replace("\n", " "))
	_check(names == ["Starter Hoe", "Carrot Seeds", "Carrot"], "resumed, quick bar names stay English: %s" % [names])
	_check(farming.farm.cleared.size() == 1 and _obstacle_instances(farming) == farming._core_plan.layout.size() - 1, "the cleared obstacle stays gone")
	_check(farming._soil.counts().get("soil", 0) == 1, "tilled soil is still drawn")
	var key: Array
	for crop_key: String in farming.farm.crops:
		key = await _key(farming, ParcelFarm.parse_key(crop_key))
		_check(farming.farm.crops[crop_key].ripe_at - farming.server_now() <= 40000, "the original ripening time is kept")
	_check(key.size() == 3 and key[0] == "Growing", "still growing after reopening")
	await _full_bag(farming)
	scene.queue_free()
	await process_frame
	_check(TranslationServer.get_locale() == "zh_CN", "leaving the parcel leaves the locale unchanged")
	TranslationServer.set_locale(outside)

## C-61 (C-59#242): seven and more kinds of items with coins stay on screen. The bar shows the first five, the Bag
## the rest; the coins sit in the top bar, which keeps inside the screen.
func _full_bag(farming: Node) -> void:
	var save: Dictionary = farming.farm.duplicate(true)
	save.coins = 1234
	save.bag.merge({"stone": 3, "wild_herb": 2, "wood": 4, "blueprint_coop": 1})
	farming._adopt({"ok": true, "farm": save, "farm_version": farming.farm_version})
	await process_frame
	var screen: Rect2 = farming._ui.get_global_rect()
	var ids: Array = farming.bag_ids()
	_check(ids.size() == 8 and farming._bar.slots.size() == UiQuickBar.SLOTS, "8 kinds of items: the quick bar shows %d (%s)" % [farming._bar.slots.size(), ids])
	_check(screen.encloses(farming._bar.get_global_rect()), "the quick bar stays on screen: %s in %s" % [farming._bar.get_global_rect(), screen])
	_check(screen.encloses(scene._header.get_global_rect()) and scene._coins.text == "1234", "the top bar with 1234 coins stays on screen: %s" % scene._header.get_global_rect())
	farming.open_bag()
	await process_frame
	_check(farming._grid.items.size() == 8, "the Bag lists all 8: %d" % farming._grid.items.size())
	farming.close_bag()

## The guide's card text on screen (C-35), "" when it is hidden.
func _tip(farming: Node) -> String:
	return farming._tip.tip if farming._tip.visible else ""

## Texts of the gain floats on screen.
func _floats(farming: Node) -> Array:
	return farming._ui.get_children().filter(func(n): return n is UiFloatText).map(func(n): return n.text)

func _flights(farming: Node) -> int:
	return farming._ui.get_children().filter(func(n): return n is UiItemFly).size()

## id -> quantity on the quick bar.
func _bar_counts(farming: Node) -> Dictionary:
	var counts := {}
	for slot in farming._bar.slots:
		if slot is Dictionary and slot.has("id"): counts[slot.id] = slot.quantity
	return counts

## House placement (C-33) holds the farming UI: no key, no quick bar, the drawer closed; Build Cottage sits beside the
## key, clear of it and of the bar (C-74#17).
func _held(farming: Node) -> void:
	var build: Control = scene._build
	var key: Rect2 = farming._key.get_global_rect()
	var bar: Rect2 = farming._bar.get_global_rect()
	var at: Rect2 = build.get_global_rect()
	_check(at.size.x >= 180 and not at.intersects(key) and not at.intersects(bar) and is_equal_approx(at.end.y, key.end.y),
		"Build Cottage sits on the key's baseline, clear of the key and the bar: %s / %s / %s" % [at, key, bar])
	farming._bar.bag_requested.emit()
	await process_frame
	farming.held = true
	await process_frame
	_check(not farming.bag_open() and not farming._keys.visible and not farming._bar.visible, "held: no key, no quick bar, drawer closed")
	farming.held = false
	await process_frame
	_check(farming._keys.visible and farming._bar.visible, "released: key and quick bar back")

## The Bag end opens the compact drawer with the bar docked in it; a cell shows its name; Close and Back close it.
func _bag_drawer(farming: Node) -> void:
	var home: Node = farming._bar.get_parent()
	farming._bar.bag_requested.emit()
	await process_frame
	_check(farming.bag_open() and farming._bar.get_parent().get_parent() == farming._drawer.body and farming._bar.bag_open, "Bag opens the drawer, the quick bar docked on top")
	var ids: Array = farming._grid.shown_items().map(func(it): return it.id)
	_check(ids == ["hoe_starter", "seed_carrot", "blueprint_cottage"] and farming._grid.shown_items()[1].qty == 3, "the drawer lists the bag")
	farming._grid.select("seed_carrot")
	_check(farming._picked_name.text == "Carrot Seeds ×3", "a tapped cell shows its name")
	farming._bar.close_requested.emit()
	await process_frame
	_check(not farming.bag_open() and farming._bar.get_parent() == home and not farming._bar.bag_open, "Close puts the bar back")
	var bar_rect: Rect2 = farming._bar.get_global_rect()
	var ui_rect: Rect2 = farming._ui.get_global_rect()
	_check(is_equal_approx(bar_rect.end.y, ui_rect.end.y - UiTokens.SIZE_QUICK_BAR_BOTTOM) and is_equal_approx(bar_rect.position.x, UiTokens.SIZE_QUICK_BAR_X),
		"…at the bottom, where it was: %s in %s" % [bar_rect, ui_rect])
	# No long-press drag on this bar (no swap, Pin or Remove, C-74#39); a swipe up still opens the bag.
	var cell: UiItemCell = farming._bar.cells()[0]
	cell.gesture.emit({"kind": &"lift", "pos": cell.get_global_rect().get_center()})
	await process_frame
	_check(not farming._bar.is_lifted() and not farming._bar.is_dragging(), "a long press does not lift a slot")
	cell.gesture.emit({"kind": &"swipe_up", "pos": cell.get_global_rect().get_center()})
	await process_frame
	_check(farming.bag_open(), "a swipe up on a slot opens the bag")
	farming.close_bag()
	await process_frame
	farming._bar.slot_tapped.emit("seed_carrot")
	await process_frame
	_check(farming.bag_open() and farming._grid.selected_id == "seed_carrot", "a slot opens the drawer on its item")
	_check(scene.is_back_navigation_locked() and not farming.bag_open() and not scene._back_sent, "Back closes the drawer first, the farm stays")
	await process_frame
	# C-111: a tap on the dimmed area closes the drawer. 0.4.2 used the scrim after close_bag() had cleared it: a
	# SCRIPT ERROR here, a native crash (SIGSEGV in Control::accept_event) in the release package.
	farming._bar.bag_requested.emit()
	await process_frame
	var scrim: Control = farming._scrim
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = scrim.get_global_rect().position + Vector2(40, 40)
	scrim.gui_input.emit(release)
	_check(not farming.bag_open() and farming._scrim == null and farming._bar.get_parent() == home, "a tap on the dimmed area closes the drawer")
	await process_frame
	_check(not is_instance_valid(scrim), "…and frees its scrim")

## C-33 on a fresh save (the welcome blueprint, no house): Build Cottage while a press is still
## walking to its cell ends the walk and sends nothing; the player holds still under the preview.
func _placement_takes_over() -> void:
	var house_dir := dir + "_house"
	var farming := await _open(LocalStore.new(raw.block_id, house_dir))
	_check(scene._build.visible, "a fresh save offers Build Cottage")
	_check(_tip(farming) == "Tap Build Cottage to place your first home.", "the guide's first card points at Build Cottage")
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
	_check(_tip(farming) == "", "no card while the house is being placed")
	_check(scene._walk.position == at and farming.farm_version == version and farming.farm.tilled.is_empty(),
		"the player holds still and nothing was sent")
	scene.end_house_placement()
	scene.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(house_dir): DirAccess.remove_absolute(house_dir.path_join(name))
	DirAccess.remove_absolute(house_dir)

## C-114: a successful Build grows the cottage in (P0Fence.pop_in) with a puff (P0Fence.dust, enlarged) at the middle
## and at each of the footprint's eight rim points; it settles at full size and the dust is gone in a second. Reopening the save
## builds the same house at full size with no dust.
func _house_pops_once() -> void:
	var house_dir := dir + "_pop"
	await _open(LocalStore.new(raw.block_id, house_dir))
	scene._build.activated.emit()
	await process_frame
	scene._placement._bar.confirmed.emit()
	var built = scene.house_state()
	var house: Node3D = scene._house
	_check(built is Dictionary and house != null and house.scale.x < 0.1, "Build starts the cottage small")
	var dust: Array = _dust()
	_check(dust.size() == 9, "Build puffs dust at the middle and round the footprint (%d)" % dust.size())
	_check(dust.all(func(d): return d.scale_amount_min >= 0.2 and d.emitting),
		"the puffs are sized for the cottage and emitting")
	if built is Dictionary:
		var rim := House.rim(scene._walk, House.at_of(built), int(built.rotation))
		var far := 0.0
		for p: Vector3 in rim:
			var near := INF
			for d: Node3D in dust: near = minf(near, (d.position - Vector3(0, 0.05, 0)).distance_to(p))
			far = maxf(far, near)
		_check(rim.size() == 8 and far < 0.001, "a puff at every rim point")
	await create_timer(0.5).timeout
	_check(is_instance_valid(house) and house.scale.is_equal_approx(Vector3.ONE), "the cottage settles at full size")
	await create_timer(0.8).timeout
	_check(_dust().is_empty(), "the dust is gone")
	scene.queue_free()
	await process_frame
	await _open(LocalStore.new(raw.block_id, house_dir))
	_check(scene._house != null and scene._house.scale == Vector3.ONE, "reopening shows the cottage at full size")
	_check(_dust().is_empty(), "reopening puffs no dust")
	await create_timer(0.1).timeout
	_check(scene._house.scale == Vector3.ONE and _dust().is_empty(), "nothing pops after reopening")
	scene.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(house_dir): DirAccess.remove_absolute(house_dir.path_join(name))
	DirAccess.remove_absolute(house_dir)

func _dust() -> Array:
	return scene.get_children().filter(func(n): return n is CPUParticles3D)

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
