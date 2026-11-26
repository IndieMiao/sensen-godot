extends SceneTree
## C-34 in the real scene, on the local save: one press each clears, tills and sows; the
## carrot waits 60 s; harvest fills the bag; the three refusals show on the key; reopening
## keeps everything and grants nothing. C-73: a press first walks the player beside the cell,
## faces it and plays the labour clip; the result shows as the clip ends; a cell with nowhere to
## stand says so and sends nothing; the stick cancels a walk; the parcel stays covered until the
## save is applied. C-33: opening the house placement gives up a press still walking. C-114: Build pops the
## cottage in with dust round it; reopening shows it still, without dust. C-138: the carrot's stage and the dry soil block
## are drawn; the development switch draws the soil wet. C-136: a claim made on an older dataset opens on the
## server save once the enter request names the opened farm's dataset (Q-168), the lost first try included. C-113: with
## the map on r8, an r6 home opens its r6 farm and its enter names r6 (Q-172: not moved); an r4 home opens in r8 and its
## enter names r8 (moved, Q-168). C-151: Build Well, dry carrots that do not grow, Fill at the well for 2 Energy, Water
## three cells from one pail (wet soil, growing from then), Pail empty for the fourth until the pail is filled again.
## C-152: at Lv1 one well stands, a spare well blueprint offers nothing; at Lv3 the Build key offers the second and the
## Energy chip tops at 220. C-171: beside the coop's feeder a tapped cell with a step to do keeps its key (the well's Fill, a
## free cell's Till); untapped, or tapped on a cell with nothing to do, the key feeds.
## Run in the private preview project (README), optionally
## with `-- <farm.json>`; without it the synthetic fixture parcel is used.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const RemoteStore = preload("res://modules/dynamic_farm/parcel_farm_remote_store.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
## Pixels the quick bar's global rect may sit off its rest after M-16's slide back (C-147). Control only refreshes its
## cached global transform when the position moves by more than is_equal_approx (relative 1e-5, about 0.006 px at
## y 600), so a tween's last sub-0.006 px step leaves get_global_rect() one frame behind, for good. Far below the
## 24 px slide (UiMotion.BAR_HIDE_Y) the assertion has to catch.
const BAR_REST_TOLERANCE_PX := 0.1
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

## C-136 stand-in for the server's /parcels/mine endpoints holding the player's claim on an older dataset: an enter
## naming a dataset moves the claim to it (Q-168 rebase; the cell progress is gone, the bag kept); anything else answers
## the claim as it is. The first `drop` requests are lost like a dropped connection.
class OldClaimServer extends RefCounted:
	var block_id: String
	var dataset: String
	var farm: Dictionary
	var drop := 0
	var enters: Array = [] # Bodies of the enter requests that reached the server, lost ones included.
	func handle(method: String, url: String, _headers: PackedStringArray, body: String) -> ApiClient.Response:
		var data = JSON.parse_string(body) if not body.is_empty() else {}
		if method == "POST" and url.ends_with("/parcels/mine/enter"):
			enters.append(data)
			if data is Dictionary and data.get("dataset_version") is String: dataset = data.dataset_version
		if drop > 0:
			drop -= 1
			return ApiClient.Response.new(false, 0, {}, "transport error")
		return ApiClient.Response.new(true, 200, {"granted": false, "server_time": int(Time.get_unix_time_from_system() * 1000.0),
			"parcel": {"parcel_id": block_id, "dataset_version": dataset, "farm_version": 5, "farm": farm}})

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
	await _placement_turns()
	await _energy_short_and_rest()
	await _energy_comes_back()
	await _watering_loop()
	await _level_wells()
	await _feeder_yields_to_tapped_cell()
	await _older_dataset_claim()
	await _release_named_on_enter()
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
	print("PARCEL_FARMING_SCENE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _store() -> RefCounted:
	var store := LocalStore.new(raw.block_id, dir)
	store.now_ms = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0) + shift[0]
	return store

## `farm` defaults to the fixture; `net_store` leaves the save to the scene's own server store, as the map opens it.
func _open(store: RefCounted = null, farm: Dictionary = {}, net_store := false) -> Node:
	var opened := raw if farm.is_empty() else farm
	var args := {"farm": opened, "dataset": opened.dataset_version, "block_id": opened.block_id, "own_parcel": true}
	if not net_store: args.farm_store = store if store != null else _store()
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup(args)
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
	var seen := {"clips": {}, "moved": 0.0, "early": false, "pail": false}
	var start: Vector3 = scene._walk.position
	var version: int = farming.farm_version
	var player := scene._rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	farming._key.pressed_down.emit()
	var deadline := Time.get_ticks_msec() + 30000
	while farming.busy and Time.get_ticks_msec() < deadline:
		if player != null: seen.clips[player.current_animation] = true
		var pail = scene._rig.get_node_or_null("BucketGesture")
		if pail != null and pail.visible and scene._labour_left > 0.0: seen.pail = true
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
	# Stand-in for C-33: a cottage already placed in a save from before C-150 (only `house`, no `buildings`).
	var data: Dictionary = scene_data()
	var house_at := _free_block(data)
	var seeded := ParcelFarm.empty_state()
	seeded.erase("buildings")
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
	# C-151: the one-off grant (the well blueprint and the pail) comes with the first-entry gift.
	_check(farming.last_gains == {"hoe_starter": 1, "seed_carrot": 3, "blueprint_cottage": 1, "blueprint_well": 1, "pail": 1},
		"the gift is announced item by item, the blueprints and the pail too: %s" % [farming.last_gains])
	# Floats stack at most UiMotion.FLOAT_STACK_MAX lines (the motion rule); every item still flies into the bag.
	_check(_floats(farming) == ["+1 Starter Hoe", "+3 Carrot Seeds", "+1 Cottage Blueprint", "+1 Well Blueprint"].slice(0, UiMotion.FLOAT_STACK_MAX),
		"one float per gift item, as many as stack: %s" % [_floats(farming)])
	_check(_flights(farming) == 5, "each gift item flies into the bag")
	_check(not farming._toast.current_text().begins_with("Received"), "no gift toast")
	_check(not scene._hint.visible, "no preview hint on one's own farm")
	_check(_tip(farming) == "Pick a spot in your yard and press Till.", "the guide's card teaches tilling once the house stands (C-35): " + _tip(farming))
	await process_frame
	var tip_rect: Rect2 = farming._tip.get_global_rect()
	_check(tip_rect.position.y >= scene._place_chip.get_global_rect().end.y and tip_rect.end.y < farming._bar.get_global_rect().position.y,
		"the card sits under the top bar's two rows, above the quick bar: %s / %s / %s" % [tip_rect, scene._place_chip.get_global_rect(), farming._bar.get_global_rect()])
	await _profile_from_avatar(farming)
	farming._tip.tapped.emit()
	_check(_tip(farming) == "", "a tap closes the card")
	_check(farming._bar.visible and _bar_counts(farming) == {"hoe_starter": 1, "pail": 1, "seed_carrot": 3, "blueprint_cottage": 1, "blueprint_well": 1},
		"quick bar shows hoe, pail, seeds and the blueprints")
	_check(farming._bar.slots.map(func(slot): return slot.id) == ["hoe_starter", "pail", "seed_carrot", "blueprint_cottage", "blueprint_well"],
		"the tools first, the pail beside the hoe (C-151)")
	_check(farming._bar.slots[3].icon == load("res://modules/dynamic_farm/parcel_items.gd").icon_of("blueprint_cottage"), "the blueprint has the parcel adapter's placeholder icon (C-59)")
	_check(farming._bar.slots[0].icon == UiArt.item("row_tool") and farming._bar.slots[2].icon == UiArt.item("seed_carrot"),
		"the hoe and the seeds show C-86's v3 item art (C-105)")
	_check(farming._bar.slots[1].icon == load("res://modules/dynamic_farm/parcel_items.gd").icon_of("pail") and farming._bar.slots[1].icon != null,
		"the pail has its icon (C-151)")
	_check(farming._bar.bag_icon == UiArt.SYS_BAG and (scene._coins_capsule as UiGlassCapsule).icon == UiArt.COIN,
		"the Bag end and the coins capsule show the v3 bag and coin (C-105)")
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
		all_clear = all_clear and farming.obstacle_cells().has(at) and await _key(farming, at) == ["Clear", "2 Energy", UiSceneAction.State.DEFAULT]
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
	_check(farming.farm.bag.get("hoe_starter") == 1 and farming.energy_value() == 198, "clearing uses no item, 2 Energy (C-148)")
	_check("−2 Energy" in _floats(farming), "the Energy it cost floats up: %s" % [_floats(farming)])
	# Till, sow, wait, harvest.
	var cell := _free_cell(data, farming)
	_check(await _key(farming, cell) == ["Till", "2 Energy", UiSceneAction.State.DEFAULT], "a free core cell offers Till for 2 Energy")
	seen = await _press(farming, cell)
	_check(_beside([cell]) and seen.clips.has("labour_till") and not seen.early, "till: beside the cell, facing it, the till clip")
	_check(ParcelFarm.key(cell) in farming.farm.tilled and farming._crop_art.counts().soil == {"dry": 1, "wet": 0}, "one press tills, one dry soil block drawn")
	_check(_tip(farming) == "Press Sow to plant Carrot Seeds in your soil.", "the next step's card comes back after tilling: " + _tip(farming))
	_check(await _key(farming, cell) == ["Sow", "3 Energy", UiSceneAction.State.DEFAULT], "tilled soil offers Sow for 3 Energy")
	seen = await _press(farming, cell)
	_check(seen.moved < 0.01 and seen.clips.has("labour_sow"), "already beside it: no walk, the sow clip")
	var crop: Dictionary = farming.farm.crops.get(ParcelFarm.key(cell), {})
	_check(ParcelFarm.is_dry(crop) and crop.get("ripe_at") == ParcelFarm.NEVER and farming.farm.bag.seed_carrot == 2, "sown: dry, not counting time (C-151), one seed used")
	_check(farming.energy_value() == 193 and scene._header.get_node("Energy").value_label.text == "193/200", "clear 2 + till 2 + sow 3: the top bar's chip reads 193/200")
	_check(_bar_counts(farming).get("seed_carrot") == 2, "the quick bar's seed count follows at once")
	_check(farming._crop_art.counts().stages == [0, 1, 0, 0, 0, 0, 0], "C-138: the sown carrot shows its sowing stage at once")
	_check(not farming.wet_soil_preview and farming._crop_art.counts().soil == {"dry": 1, "wet": 0}, "C-138: no watering yet, the soil is dry")
	farming.wet_soil_preview = true
	farming._draw_crops()
	_check(farming._crop_art.counts().soil == {"dry": 0, "wet": 1}, "C-138: the development switch previews wet soil")
	farming.wet_soil_preview = false
	farming._draw_crops()
	# C-151: the dry carrot waits for water: the guide asks for the well, the key for water the pail does not hold yet.
	_check(_tip(farming) == "Tap Build Well to place your well.", "a dry carrot and no well: the card asks for the well: " + _tip(farming))
	_check(await _key(farming, cell) == ["Water", "Pail empty", UiSceneAction.State.UNAVAILABLE], "a dry carrot: Water, the pail empty")
	version = farming.farm_version
	await _press(farming, cell)
	_check(farming._toast.current_text() == "Pail empty" and farming.farm_version == version, "pressed with an empty pail: says so, sends nothing")
	scene._build.activated.emit()
	await process_frame
	_check(scene._placement != null and scene._placement.type == "well", "Build Well opens the placement for the well")
	scene._placement._bar.confirmed.emit()
	for _i in 3: await process_frame
	var well_cell := Building.at_of(ParcelFarm.wells(farming.rules, farming.farm)[0])
	_check(_tip(farming) == "Fill your pail at the well, then press Water on your seeds.", "with the well up the card asks for water: " + _tip(farming))
	_check(await _key(farming, well_cell) == ["Fill", "2 Energy", UiSceneAction.State.DEFAULT], "at the well: Fill for 2 Energy")
	seen = await _press(farming, well_cell)
	_check(_beside([well_cell]) and farming.farm.pail_water == 3 and farming.energy_value() == 191, "fill: beside the well, the pail full, 2 Energy")
	seen = await _press(farming, cell)
	_check(_beside([cell]) and seen.clips.has("pail/pour") and not ParcelFarm.is_dry(farming.farm.crops[ParcelFarm.key(cell)])
		and farming.farm.pail_water == 2, "water: beside the cell, the pail's pour (C-153), one of the pail's 3 used")
	_check(farming._crop_art.counts().soil == {"dry": 0, "wet": 1}, "C-151: the watered cell's soil turns wet")
	_check(_tip(farming) == "", "no card while the carrot grows")
	key = await _key(farming, cell)
	_check(key[0] == "Growing" and key[1] in ["Ready in 1:00", "Ready in 0:59", "Ready in 0:58"] and key[2] == UiSceneAction.State.UNAVAILABLE, "growing counts down from the watering")
	await _press(farming, cell)
	_check(farming._toast.current_text() == "Not ripe yet" and not farming.farm.bag.has("crop_carrot"), "no harvest before 60 s")
	# The refusals: outside the core, on the protected path, under the house.
	_check(await _key(farming, _outside_cell(data)) == ["Till", "Not farmland", UiSceneAction.State.UNAVAILABLE], "outside the core refuses")
	_check(await _key(farming, data.spawn) == ["Till", "On the path", UiSceneAction.State.UNAVAILABLE], "the protected path refuses")
	var under_house := house_at
	for at: Vector2i in ParcelFarm.building_footprint(ParcelFarm.home_building(farming.farm)):
		if not farming._obstacles.has(at) and not Space.door_row(farming.farm).has(at): under_house = at
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
	_check(await _key(farming, cell) == ["Harvest", "", UiSceneAction.State.DEFAULT], "ripe after 60 s; harvesting is free, no price (LOCK-02)")
	await create_timer(farming.get_script().REDRAW_S * 2).timeout
	_check(_tip(farming) == "Your carrot is ripe. Press Harvest!", "a ripe carrot brings the harvest card: " + _tip(farming))
	_check(farming._crop_art.counts().stages == [0, 0, 0, 0, 0, 0, 1], "C-138: the ripe carrot is drawn mature")
	seen = await _press(farming, cell)
	_check(_beside([cell]) and seen.clips.has("labour_harvest") and not seen.early, "harvest: beside the cell, the harvest clip")
	_check(farming.farm.bag.get("crop_carrot") == 1 and farming.last_gains == {"crop_carrot": 1}, "harvest goes to the bag")
	_check("+1 Carrot" in _floats(farming) and _flights(farming) >= 1, "the harvest floats up and flies into the bag")
	_check(_bar_counts(farming).get("crop_carrot") == 1, "the quick bar shows the carrot")
	_check(_tip(farming) == "Head back to the map and tap Washington Square to sell your carrot.", "after the first harvest the card sends the carrot to the Market (C-61, C-115: at Washington Square): " + _tip(farming))
	_check(ParcelFarm.key(cell) in farming.farm.tilled and farming._crop_art.counts().stages == [1, 0, 0, 0, 0, 0, 0], "the soil stays tilled, the carrot is gone")
	_check(farming._crop_art.counts().soil == {"dry": 1, "wet": 0}, "C-151: harvested, the soil is dry again")
	await _press(farming, cell)
	await _press(farming, cell)
	_check(farming.farm.crops.has(ParcelFarm.key(cell)) and not ParcelFarm.is_dry(farming.farm.crops[ParcelFarm.key(cell)]),
		"sow and water again for the reopen check")
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
	_check(_bar_counts(farming) == {"hoe_starter": 1, "pail": 1, "seed_carrot": 1, "crop_carrot": 1, "blueprint_cottage": 1}, "the quick bar matches the save")
	var names: Array = farming._bar.cells().slice(0, 4).map(func(c): return str(c.get("_name").text).replace("\n", " "))
	_check(names == ["Starter Hoe", "Pail", "Carrot Seeds", "Carrot"], "quick bar names stay English: %s" % [names])
	scene.suspend()
	_check(TranslationServer.get_locale() == "zh_CN", "suspended, the locale is unchanged")
	scene.resume()
	await process_frame
	_check(TranslationServer.get_locale() == "zh_CN", "resumed, the locale is still unchanged")
	names = farming._bar.cells().slice(0, 4).map(func(c): return str(c.get("_name").text).replace("\n", " "))
	_check(names == ["Starter Hoe", "Pail", "Carrot Seeds", "Carrot"], "resumed, quick bar names stay English: %s" % [names])
	_check(farming.farm.cleared.size() == 1 and _obstacle_instances(farming) == farming._core_plan.layout.size() - 1, "the cleared obstacle stays gone")
	_check(farming._crop_art.counts().soil == {"dry": 0, "wet": 1}, "tilled soil is still drawn, wet where watered")
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
## C-108 (C-85 ①: the HUD avatar opens the profile): row 1 of the top bar is ‹, the C-H1 avatar, Energy and coins; the
## place capsule is row 2 under it. The avatar opens the profile over the parcel (its HUD hides, its touches stop), with
## the parcel as My farm; the card and Android Back close it.
func _profile_from_avatar(farming: Node) -> void:
	var avatar: Button = scene._header.get_node_or_null("Avatar")
	_check(avatar != null and avatar.get_script() == load("res://scenes/ui_kit/ui_hud_avatar.gd") and avatar.get_index() == 1 and avatar.size == Vector2(52, 52), "the top bar's avatar: Ø52, after Back")
	var head: Rect2 = scene._header.get_global_rect()
	var place: Rect2 = scene._place_chip.get_global_rect()
	_check(is_equal_approx(place.position.x, 12.0) and place.position.y >= head.end.y and place.end.x <= farming._ui.get_global_rect().end.x - 12.0,
		"the place capsule is row 2, 12 in: %s under %s" % [place, head])
	_check(scene._title.custom_minimum_size.x > 0.0 and place.size.x < farming._ui.size.x - 24.0, "as wide as its lines: %s" % place)
	avatar.pressed.emit()
	await process_frame
	_check(scene.profile_open() and not scene._canvas.visible and scene._controls.process_mode == Node.PROCESS_MODE_DISABLED,
		"the avatar opens the profile; the parcel's HUD hides and its touches stop")
	var page: Control = scene._profile.top()
	_check(page.get_script() == load("res://scenes/dynamic_farm/parcel_profile_page.gd") and page.farm_card != null, "the profile shows My farm")
	var expected: String = scene._data.address if not str(scene._data.get("address", "")).is_empty() else str(scene._data.get("name", ""))
	_check(page.farm_card.find_child("FarmName", true, false).text == expected, "its card is this parcel: %s" % expected)
	_check(scene.close_modal() and not scene.profile_open(), "Android Back closes the profile")
	await process_frame
	_check(scene._canvas.visible and scene._controls.process_mode == Node.PROCESS_MODE_INHERIT, "the HUD and touches come back")
	avatar.pressed.emit()
	await process_frame
	scene._profile.top().farm_pressed.emit()
	await process_frame
	_check(not scene.profile_open() and scene._canvas.visible, "the farm card closes it too: home is here")
	var now := 1_000_000
	var farm := {"crops": {"1,1": {"crop": "crop_carrot", "ripe_at": now + 3 * 3600000 + 32 * 60000}}}
	_check(scene.home_status(farm, now).text == "Carrots ready in 3h 32m", "status: %s" % scene.home_status(farm, now))
	farm.crops["2,2"] = {"crop": "crop_carrot", "ripe_at": now - 1}
	_check(scene.home_status(farm, now) == {"text": "Carrots ready to harvest", "ready": true}, "ready: the main farm's line, deep green")
	_check(scene.home_status({}, now).text == "", "nothing sown: no status line")
	var dry := {"crops": {"1,1": {"crop": "crop_carrot", "planted_at": now, "ripe_at": ParcelFarm.NEVER, "watered_at": null}}}
	_check(scene.home_status(dry, now).text == "", "a dry crop is not growing (C-151): no status line")
	dry.crops["2,2"] = {"crop": "crop_carrot", "ripe_at": now + 60 * 60000, "watered_at": now}
	_check(scene.home_status(dry, now).text == "Carrots ready in 1h", "the watered one is: %s" % scene.home_status(dry, now))

func _full_bag(farming: Node) -> void:
	var save: Dictionary = farming.farm.duplicate(true)
	save.coins = 1234
	save.bag.merge({"stone": 3, "wild_herb": 2, "wood": 4, "blueprint_coop": 1})
	farming._adopt({"ok": true, "farm": save, "farm_version": farming.farm_version})
	await process_frame
	var screen: Rect2 = farming._ui.get_global_rect()
	var ids: Array = farming.bag_ids()
	_check(ids.size() == 9 and farming._bar.slots.size() == UiQuickBar.SLOTS, "9 kinds of items: the quick bar shows %d (%s)" % [farming._bar.slots.size(), ids])
	_check(screen.encloses(farming._bar.get_global_rect()), "the quick bar stays on screen: %s in %s" % [farming._bar.get_global_rect(), screen])
	_check(screen.encloses(scene._header.get_global_rect()) and scene._coins.text == "1234", "the top bar with 1234 coins stays on screen: %s" % scene._header.get_global_rect())
	farming.open_bag()
	await process_frame
	_check(farming._bag_slots.size() == 9 and farming._slots.get_child_count() == 9, "the Bag lists all 9: %d" % farming._bag_slots.size())
	farming.close_bag()

## C-148: a save short of Energy: the chip, the amber key that opens P0's Energy card instead of sending, its tiles,
## Rest at the cottage's door (+60 once a player day) and the chip's panel.
func _energy_short_and_rest() -> void:
	var data: Dictionary = scene_data()
	var house_at := _free_block(data)
	var now: int = int(Time.get_unix_time_from_system() * 1000.0) + shift[0]
	var seeded := ParcelFarm.empty_state()
	# C-150 save: the cottage is building 1 of the building list (house is only its mirror for older clients).
	var cottage := {"model": "cottage", "x": house_at.x, "y": house_at.y, "width": 3, "depth": 3, "rotation": 0, "built_at": 0}
	seeded.buildings = [cottage.merged({"id": 1, "type": "cottage"})]
	seeded.house = cottage
	seeded.welcomed_at = now - 8 * 86400000
	seeded.bag = {"hoe_starter": 1, "seed_carrot": 3}
	seeded.energy = {"value": 1, "at": now, "rested_on": null}
	var energy_dir := dir + "_energy"
	DirAccess.make_dir_recursive_absolute(energy_dir)
	var file := FileAccess.open(energy_dir.path_join(raw.block_id.validate_filename() + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"block_id": raw.block_id, "farm_version": 3, "farm": seeded}))
	file.close()
	var store := LocalStore.new(raw.block_id, energy_dir)
	store.now_ms = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0) + shift[0]
	var farming := await _open(store)
	var chip: UiEnergyChip = scene._header.get_node_or_null("Energy")
	_check(chip != null and chip.visible and chip.get_index() == scene._coins_capsule.get_index() - 1, "the top bar shows P0's Energy chip before the coins")
	_check(chip.value_label.text == "1/200" and chip.regen_text().begins_with("+1 in "), "the chip: 1/200, +1 in m:ss: %s %s" % [chip.value_label.text, chip.regen_text()])
	var screen: Rect2 = farming._ui.get_global_rect()
	_check(screen.encloses(scene._header.get_global_rect()), "the top bar with the chip stays on screen: %s" % scene._header.get_global_rect())
	var cell := _free_cell(data, farming)
	_check(await _key(farming, cell) == ["Till", "Need 2 Energy", UiSceneAction.State.INSUFFICIENT], "short: the key turns amber, Need 2 Energy (LOCK-10)")
	_check(chip.state() == UiHud.Energy.LOW, "short of the next action the chip is amber too (LOCK-06)")
	var version: int = farming.farm_version
	farming._key.pressed_down.emit()
	await process_frame
	_check(farming.energy_modal == "card" and farming.farm_version == version and not farming.busy, "the press opens the Energy card and sends nothing")
	var card := farming._ui.find_child("EnergyCard", true, false) as UiEnergyCard
	_check(card != null and (card.find_child("Fact", true, false) as Label).text == "Till needs 2 Energy · you have 1",
		"the card says what it needs and what there is (LOCK-09)")
	var tiles := card.find_children("*", "UiEnergyTile", true, false)
	var on := tiles.filter(func(t): return t.available)
	_check(tiles.size() == 4 and on.size() == 1, "four RECOVER tiles; only Rest can be used here: %d" % on.size())
	_check(card.find_child("Free", true, false) is UiCommandButton, "one button: Free to do now")
	card.tile_pressed.emit("home")
	await process_frame
	var home_node = scene._buildings.get(1, {}).get("node")
	_check(farming.energy_modal == "" and scene._showing_house and home_node is Node3D
		and scene._focus.is_equal_approx(home_node.position), "the Rest tile only turns the camera to the cottage")
	# Rest at the cottage's door.
	var door = load("res://modules/dynamic_farm/parcel_space.gd").door_cell(farming.farm)
	_check(await _key(farming, door) == ["Rest", "+60 Energy", UiSceneAction.State.DEFAULT], "at the cottage's door: Rest +60 Energy")
	var seen := await _press(farming, door)
	_check(farming.energy_value() == 61 and farming.farm.energy.rested_on != null, "one press rests: 1 -> 61")
	_check("+60 Energy" in _floats(farming), "the Energy it gave floats up")
	_check(seen.moved > 0.0 or _beside([door]), "the player stands at the door")
	_check(await _key(farming, door) == ["Rest", "Rested today", UiSceneAction.State.UNAVAILABLE], "once a player day")
	_check(await _key(farming, cell) == ["Till", "2 Energy", UiSceneAction.State.DEFAULT], "with Energy again the key works")
	chip.pressed.emit()
	await process_frame
	var panel := farming._ui.find_child("EnergyPanel", true, false) as UiEnergyCard
	_check(farming.energy_modal == "panel" and panel != null, "a tap on the chip opens P0's Energy panel")
	_check(scene.close_modal() and farming.energy_modal == "", "Back closes it")
	scene.queue_free()
	await process_frame

## C-148: away for a while, the Energy that came back by server time is there on return (offline regen).
func _energy_comes_back() -> void:
	var energy_dir := dir + "_energy"
	var store := LocalStore.new(raw.block_id, energy_dir)
	store.now_ms = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0) + shift[0]
	var before := int(store.read().farm.energy.value)
	shift[0] += 8 * 60000 + 1000
	var farming := await _open(store)
	_check(farming.energy_value() == before + 2, "8 minutes away: +2 (%d -> %d)" % [before, farming.energy_value()])
	_check(scene._header.get_node("Energy").value_label.text == "%d/200" % (before + 2), "the chip shows it")
	scene.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(energy_dir): DirAccess.remove_absolute(energy_dir.path_join(name))
	DirAccess.remove_absolute(energy_dir)

## The guide's card text on screen (C-35), "" when it is hidden.
func _tip(farming: Node) -> String:
	return farming._tip.tip if farming._tip.visible else ""

## Texts of the gain floats on screen.
func _floats(farming: Node) -> Array:
	return farming._ui.get_children().filter(func(n): return n is UiGainFloat).map(func(n): return n.text)

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
	_check(not farming.bag_open() and not farming._keys.visible and not farming._bar.visible, "held: no key, no quick bar, bag closed")
	farming.held = false
	await process_frame
	_check(farming._keys.visible and farming._bar.visible, "released: key and quick bar back")

## The Bag end opens the UI v3 bag panel (C-105): the quick bar slides away (M-16) and comes back where it was; a
## slot shows its name; ✕, Back and a tap on the dimmed area close it.
func _bag_drawer(farming: Node) -> void:
	farming._bar.bag_requested.emit()
	await process_frame
	_check(farming.bag_open() and farming._bag.title == "Bag" and farming._bag.hero == UiArt.HERO_BAG, "Bag opens the bag panel, C-86's bag as its hero")
	var ids: Array = farming._bag_slots.keys()
	_check(ids == ["hoe_starter", "pail", "seed_carrot", "blueprint_cottage", "blueprint_well"] and farming._bag_slots.seed_carrot.item.qty == 3,
		"the panel lists the bag: %s" % [ids])
	_check(farming._slots.get_child_count() == 9 and farming._slots.columns == 3, "three rows of three round slots")
	farming._bag_slots.seed_carrot.tapped.emit("seed_carrot")
	_check(farming._picked_name.text == "Carrot Seeds ×3" and farming.bag_selected == "seed_carrot"
		and farming._bag_slots.seed_carrot.state == UiBagSlot.State.SELECTED, "a tapped slot is selected and named")
	await create_timer(0.35).timeout
	_check(not farming._bar.visible, "the quick bar is hidden while the bag is open (M-16)")
	var panel: UiModalPanel = farming._bag
	panel.close_button().pressed.emit()
	await process_frame
	_check(not farming.bag_open() and panel.closing, "✕ closes it")
	await create_timer(0.4).timeout
	_check(not is_instance_valid(panel), "…and the panel frees itself after its exit")
	var bar_rect: Rect2 = farming._bar.get_global_rect()
	var ui_rect: Rect2 = farming._ui.get_global_rect()
	_check(farming._bar.visible and is_equal_approx(farming._bar.modulate.a, 1.0)
		and absf(bar_rect.end.y - (ui_rect.end.y - UiTokens.SIZE_QUICK_BAR_BOTTOM)) <= BAR_REST_TOLERANCE_PX
		and absf(bar_rect.position.x - UiTokens.SIZE_QUICK_BAR_X) <= BAR_REST_TOLERANCE_PX,
		"the quick bar comes back at the bottom, where it was: %s in %s" % [bar_rect, ui_rect])
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
	_check(farming.bag_open() and farming.bag_selected == "seed_carrot", "a slot opens the bag on its item")
	_check(scene.is_back_navigation_locked() and not farming.bag_open() and not scene._back_sent, "Back closes the bag first, the farm stays")
	await process_frame
	# C-111: a tap on the dimmed area closes the bag. 0.4.2 used the scrim after close_bag() had cleared it: a
	# SCRIPT ERROR here, a native crash (SIGSEGV in Control::accept_event) in the release package.
	farming._bar.bag_requested.emit()
	await process_frame
	panel = farming._bag
	var scrim: Control = panel.scrim
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = scrim.get_global_rect().position + Vector2(40, 40)
	scrim.gui_input.emit(release)
	_check(not farming.bag_open() and farming._bag == null, "a tap on the dimmed area closes the bag")
	await create_timer(0.4).timeout
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
	scene.end_placement()
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
	var built = scene.buildings_state()[0] if scene.buildings_state().size() == 1 else null
	var house: Node3D = scene._buildings.get(1, {}).get("node")
	_check(built is Dictionary and house != null and house.scale.x < 0.1, "Build starts the cottage small")
	var dust: Array = _dust()
	_check(dust.size() == 9, "Build puffs dust at the middle and round the footprint (%d)" % dust.size())
	_check(dust.all(func(d): return d.scale_amount_min >= 0.2 and d.emitting),
		"the puffs are sized for the cottage and emitting")
	if built is Dictionary:
		var rim := Building.rim(scene._walk, Building.at_of(built), Building.base_of(built), int(built.rotation))
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
	var reopened: Node3D = scene._buildings.get(1, {}).get("node")
	_check(reopened != null and reopened.scale == Vector3.ONE, "reopening shows the cottage at full size")
	_check(_dust().is_empty(), "reopening puffs no dust")
	await create_timer(0.1).timeout
	_check(reopened.scale == Vector3.ONE and _dust().is_empty(), "nothing pops after reopening")
	scene.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(house_dir): DirAccess.remove_absolute(house_dir.path_join(name))
	DirAccess.remove_absolute(house_dir)

## C-150: the placement bar is Cancel · Rotate · Build; each Rotate turns the preview a quarter about its middle
## (0, 90, 180, 270°, then 0 again) and Build sends place_building with that turn. The cottage stands turned, keeps
## it after reopening, and the player still stops at its walls.
func _placement_turns() -> void:
	var turn_dir := dir + "_turn"
	await _open(LocalStore.new(raw.block_id, turn_dir))
	_check(scene._build.label == "Build Cottage", "the Build key names the cottage")
	scene._build.activated.emit()
	await process_frame
	var p = scene._placement
	_check(p._bar.secondary == "Rotate" and p._bar.confirm == "Build" and p._bar.cancel == "Cancel", "the bar: Cancel · Rotate · Build")
	_check(p.type == "cottage" and p.base == Vector2i(3, 3), "the cottage's footprint from the rules")
	var start: Vector2i = p.at
	var turns: Array = []
	var still := true
	for i in 4:
		p._bar.secondary_pressed.emit()
		turns.append(p.rotation_steps)
		var facing: Vector3 = p._ghost.transform.basis.z
		still = still and p.at == start and facing.is_equal_approx(Vector3.BACK.rotated(Vector3.UP, p.rotation_steps * PI * 0.5))
	_check(turns == [1, 2, 3, 0] and still, "Rotate turns the preview a quarter in place each press (%s)" % [turns])
	p._bar.secondary_pressed.emit()
	p._bar.secondary_pressed.emit()
	var reason: String = p.reason
	p._bar.confirmed.emit()
	for _i in 3: await process_frame
	var built: Array = scene.buildings_state()
	_check(reason == "" and built.size() == 1 and int(built[0].rotation) == 2 and Building.at_of(built[0]) == start and built[0].type == "cottage",
		"Build places the cottage turned half way round: %s" % [built])
	_check(scene._build.label == "Build Well" and scene._placement == null, "one cottage: the Build key moves on to the well (C-151)")
	scene.queue_free()
	await process_frame
	await _open(LocalStore.new(raw.block_id, turn_dir))
	var node: Node3D = scene._buildings.get(1, {}).get("node")
	var middle := Building.center(scene._walk, start, Vector2i(3, 3), 2)
	_check(node != null and node.transform.basis.z.is_equal_approx(Vector3.FORWARD) and node.position.is_equal_approx(middle),
		"reopened, the cottage stands where and as it was turned")
	_check(not scene._walk.clear_position(middle) and not scene._buildings[1].proxies.is_empty(), "its walls still stop the player")
	scene.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(turn_dir): DirAccess.remove_absolute(turn_dir.path_join(name))
	DirAccess.remove_absolute(turn_dir)

## C-151 (owner SEN-C-137#6, #15): the well and the pail, the whole round in the real scene. A save from before
## watering (a cottage, four carrots sown on dry soil, no grant yet): entering grants the well blueprint and the pail;
## Build Well stands the well (1×1, its ring stops the player); the carrots stay at sowing on dry soil however long;
## Fill at the well draws a pail for 2 Energy; three carrots are watered from it, their soil turns wet and they grow
## from then; the fourth says Pail empty until the pail is filled at the well again.
func _watering_loop() -> void:
	var data: Dictionary = scene_data()
	var house_at := _free_block(data)
	var now: int = int(Time.get_unix_time_from_system() * 1000.0) + shift[0]
	var cottage := {"model": "cottage", "x": house_at.x, "y": house_at.y, "width": 3, "depth": 3, "rotation": 0, "built_at": 0}
	var seeded := ParcelFarm.empty_state()
	seeded.erase("grants")
	seeded.erase("pail_water")
	seeded.buildings = [cottage.merged({"id": 1, "type": "cottage"})]
	seeded.house = cottage
	seeded.welcomed_at = now - 8 * 86400000
	seeded.bag = {"hoe_starter": 1}
	var water_dir := dir + "_water"
	var store := LocalStore.new(raw.block_id, water_dir)
	store.now_ms = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0) + shift[0]
	DirAccess.make_dir_recursive_absolute(water_dir)
	store._save(seeded, 6)
	var farming := await _open(store)
	_check(farming.last_gains == {"blueprint_well": 1, "pail": 1} and farming.farm_version == 7, "an older farm gets the well blueprint and the pail on entering")
	var cells := _free_row(data, farming, 4)
	_check(cells.size() == 4, "four free cells in a row: %s" % [cells])
	if cells.size() != 4: return
	var sown: Dictionary = farming.farm.duplicate(true)
	for at: Vector2i in cells:
		sown.tilled.append(ParcelFarm.key(at))
		sown.crops[ParcelFarm.key(at)] = {"crop": "crop_carrot", "planted_at": now, "ripe_at": ParcelFarm.NEVER, "watered_at": null}
	store._save(sown, 7)
	scene.queue_free()
	await process_frame
	shift[0] += 10 * 60000
	farming = await _open(store)
	_check(farming.last_gains.is_empty(), "the grant comes once")
	_check(farming._crop_art.counts().soil == {"dry": 4, "wet": 0} and farming._crop_art.counts().stages == [0, 4, 0, 0, 0, 0, 0],
		"ten minutes on, the four dry carrots are still at sowing: %s" % [farming._crop_art.counts()])
	_check(scene._build.visible and scene._build.label == "Build Well", "the blueprint offers Build Well")
	_check(_tip(farming) == "Tap Build Well to place your well.", "the card asks for the well: " + _tip(farming))
	scene._build.activated.emit()
	await process_frame
	var p = scene._placement
	_check(p != null and p.type == "well" and p.base == Vector2i(1, 1) and p._bar.secondary == "Rotate", "the well's placement: 1×1, Rotate as the cottage's")
	p._bar.confirmed.emit()
	for _i in 3: await process_frame
	var wells: Array = ParcelFarm.wells(farming.rules, farming.farm)
	_check(wells.size() == 1 and not scene._build.visible, "the well stands; one at level 1, so the Build key goes")
	if wells.is_empty(): return
	var well: Dictionary = wells[0]
	var built: Dictionary = scene._buildings.get(int(well.id), {})
	var well_cell := Building.at_of(well)
	var middle := Building.center(scene._walk, well_cell, Vector2i.ONE)
	_check(built.get("node") is Node3D and built.node.get_child_count() == 1 and not built.get("proxies", []).is_empty() and not scene._walk.clear_position(middle),
		"the well's model stands and its ring stops the player")
	_check(not cells.any(func(at): return at == well_cell), "the well keeps off the carrots")
	_check(await _key(farming, cells[0]) == ["Water", "Pail empty", UiSceneAction.State.UNAVAILABLE], "an empty pail cannot water")
	var energy: int = farming.energy_value()
	_check(await _key(farming, well_cell) == ["Fill", "2 Energy", UiSceneAction.State.DEFAULT], "at the well: Fill for 2 Energy")
	var seen := await _press(farming, well_cell)
	_check(_beside([well_cell]) and farming.farm.pail_water == 3 and farming.energy_value() == energy - 2 and "−2 Energy" in _floats(farming),
		"Fill: beside the well, a full pail of 3, 2 Energy")
	_check(seen.clips.has("pail/draw") and seen.pail, "Fill plays C-153's draw with the pail in hand")
	var settle := Time.get_ticks_msec() + 5000   # the labour clip runs on frame time, the press on the clock
	while scene._labour_left > 0.0 and Time.get_ticks_msec() < settle: await process_frame
	await process_frame
	var hand: Node3D = scene._rig.get_node_or_null("BucketGesture")
	_check(hand != null and not hand.visible and (hand.get_node("Hand") as BoneAttachment3D).get_skeleton() == scene._rig.skeleton,
		"the pail hangs from the rig's right wrist, put away once the action ends")
	var player := scene._rig.get_node("AnimationPlayer") as AnimationPlayer
	var resolved := true
	for motion in ["pail/draw", "pail/pour"]:
		var anim := player.get_animation(motion)
		for t in anim.get_track_count():
			var path := anim.track_get_path(t)
			var node: Node = scene._rig.get_node_or_null(NodePath(path.get_concatenated_names()))
			var sub := String(path.get_concatenated_subnames())
			resolved = resolved and node != null and (sub.is_empty() or (node is Skeleton3D and (node as Skeleton3D).find_bone(sub) >= 0)
				or (not node is Skeleton3D and node.get_indexed(NodePath(sub)) != null))
	_check(resolved, "every track of the pail's draw and pour finds its node on the rig")
	_check(is_equal_approx(scene.labour_seconds("fill", 1.2), 2.22) and is_equal_approx(scene.labour_seconds("water", 1.2), 2.28)
		and is_equal_approx(scene.labour_seconds("till", 1.2), 1.2), "the pail's actions play for their own lengths")
	_check(await _key(farming, well_cell) == ["Fill", "Pail full", UiSceneAction.State.UNAVAILABLE], "a full pail is not filled again")
	for i in 3:
		_check(await _key(farming, cells[i]) == ["Water", "", UiSceneAction.State.DEFAULT], "a dry carrot: Water, free (LOCK-02)")
		seen = await _press(farming, cells[i])
		_check(_beside([cells[i]]) and seen.clips.has("pail/pour") and seen.pail and farming.farm.pail_water == 2 - i,
			"watering carrot %d: the pail's pour, the pail at %d" % [i + 1, 2 - i])
	_check(farming.energy_value() == energy - 2, "watering costs no Energy")
	_check(farming._crop_art.counts().soil == {"dry": 1, "wet": 3}, "three wet cells, one still dry: %s" % [farming._crop_art.counts()])
	_check(await _key(farming, cells[3]) == ["Water", "Pail empty", UiSceneAction.State.UNAVAILABLE], "the fourth: the pail is empty")
	var version: int = farming.farm_version
	await _press(farming, cells[3])
	_check(farming._toast.current_text() == "Pail empty" and farming.farm_version == version, "pressed: Pail empty, nothing sent")
	shift[0] += 13000
	farming._clock_offset_ms += 13000
	await create_timer(farming.get_script().REDRAW_S * 2).timeout
	_check(farming._crop_art.counts().stages == [0, 1, 3, 0, 0, 0, 0], "13 s after watering the three show emergence, the dry one sowing: %s" % [farming._crop_art.counts()])
	await _press(farming, well_cell)
	_check(farming.farm.pail_water == 3, "back at the well the pail fills again")
	await _press(farming, cells[3])
	_check(farming._crop_art.counts().soil == {"dry": 0, "wet": 4} and farming.farm.pail_water == 2, "and the fourth is watered")
	shift[0] += 47000
	farming._clock_offset_ms += 47000
	_check(await _key(farming, cells[0]) == ["Harvest", "", UiSceneAction.State.DEFAULT], "60 s after its watering the first is ripe")
	_check((await _key(farming, cells[3]))[0] == "Growing", "the one watered later is still growing")
	scene.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(water_dir): DirAccess.remove_absolute(water_dir.path_join(name))
	DirAccess.remove_absolute(water_dir)

## C-152: the Build key follows the farm level's well limit (1 at Lv1, 2 from Lv3); the chip's top follows the level.
func _level_wells() -> void:
	var data: Dictionary = scene_data()
	var house_at := _free_block(data)
	var now: int = int(Time.get_unix_time_from_system() * 1000.0) + shift[0]
	var cottage := {"model": "cottage", "x": house_at.x, "y": house_at.y, "width": 3, "depth": 3, "rotation": 0, "built_at": 0}
	var seeded := ParcelFarm.empty_state()
	seeded.buildings = [cottage.merged({"id": 1, "type": "cottage"})]
	seeded.house = cottage
	seeded.welcomed_at = now - 8 * 86400000
	seeded.grants = {"watering": now}
	seeded.bag = {"hoe_starter": 1, "pail": 1, "blueprint_well": 2}
	var level_dir := dir + "_levels"
	var store := LocalStore.new(raw.block_id, level_dir)
	store.now_ms = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0) + shift[0]
	DirAccess.make_dir_recursive_absolute(level_dir)
	store._save(seeded, 3)
	var farming := await _open(store)
	_check(scene._build.visible and scene._build.label == "Build Well", "Lv1 without a well: Build Well")
	scene._build.activated.emit()
	await process_frame
	scene._placement._bar.confirmed.emit()
	for _i in 3: await process_frame
	_check(ParcelFarm.wells(farming.rules, farming.farm).size() == 1 and farming.farm.bag.blueprint_well == 1 and not scene._build.visible,
		"Lv1: one well stands; the spare blueprint offers no second")
	var saved: Dictionary = store.read()
	saved.farm.level = 3
	store._save(saved.farm, int(saved.farm_version))
	scene.queue_free()
	await process_frame
	farming = await _open(store)
	# The save's 200 (full at Lv1) stays; the top is now Lv3's 220, and the 20 come back with time.
	_check(scene._header.get_node("Energy").value_label.text == "200/220", "Lv3: the chip tops at 220: " + scene._header.get_node("Energy").value_label.text)
	_check(scene._build.visible and scene._build.label == "Build Well", "Lv3: the spare blueprint offers the second well")
	scene._build.activated.emit()
	await process_frame
	scene._placement._bar.confirmed.emit()
	for _i in 3: await process_frame
	_check(ParcelFarm.wells(farming.rules, farming.farm).size() == 2 and not scene._build.visible, "Lv3: two wells stand")
	scene.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(level_dir): DirAccess.remove_absolute(level_dir.path_join(name))
	DirAccess.remove_absolute(level_dir)

## C-171 (SEN-C-154#139): standing within FEED_REACH_M of the coop's feeder, a tapped cell with a step to do keeps its key:
## the well's Fill (pressed, the pail fills as ever) and a free cell's Till. Untapped, or tapped on a cell with nothing to
## do (the well with a full pail, the coop's floor), the key is Feed, and the press feeds.
func _feeder_yields_to_tapped_cell() -> void:
	var data: Dictionary = scene_data()
	var house_at := _free_block(data)
	var now: int = int(Time.get_unix_time_from_system() * 1000.0) + shift[0]
	var cottage := {"model": "cottage", "x": house_at.x, "y": house_at.y, "width": 3, "depth": 3, "rotation": 0, "built_at": 0}
	var seeded := ParcelFarm.empty_state()
	seeded.buildings = [cottage.merged({"id": 1, "type": "cottage"})]
	seeded.house = cottage
	seeded.welcomed_at = now - 8 * 86400000
	seeded.grants = {"watering": now}
	seeded.bag = {"hoe_starter": 1, "pail": 1, "blueprint_well": 1, "blueprint_coop": 1, "crop_carrot": 2}
	var feed_dir := dir + "_feeder"
	var store := LocalStore.new(raw.block_id, feed_dir)
	store.now_ms = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0) + shift[0]
	DirAccess.make_dir_recursive_absolute(feed_dir)
	store._save(seeded, 3)
	var farming := await _open(store)
	# The core's obstacles cleared, so the 7×5 coop finds room; it goes where it fits, then the well from the Build key.
	var cleared := {}
	for anchor: Vector2i in farming._obstacles.values(): cleared[ParcelFarm.key(anchor)] = true
	seeded.cleared = cleared.keys()
	store._save(seeded, 4)
	scene.queue_free()
	await process_frame
	farming = await _open(store)
	var obstacles: Dictionary = farming.obstacle_cells()
	for turns in 4:
		var at = Building.nearest(scene._data, data.spawn, Vector2i(7, 5), Building.blocked(obstacles, farming.farm), farming.protected_path(),
			scene._walk_blocked(obstacles), turns, "coop")
		if at == null: continue
		await farming.send({"type": "place_building", "building": "coop", "x": at.x, "y": at.y, "rotation": turns})
		break
	for _i in 3: await process_frame
	if scene._build.visible:
		scene._build.activated.emit()
		await process_frame
		scene._placement._bar.confirmed.emit()
		for _j in 3: await process_frame
	var wells: Array = ParcelFarm.wells(farming.rules, farming.farm)
	var coops: Array = scene.buildings_state().filter(func(b): return b.type == "coop")
	_check(wells.size() == 1 and coops.size() == 1, "the well and the coop stand: %s" % [scene.buildings_state()])
	if wells.size() != 1 or coops.size() != 1: return
	var well_cell := Building.at_of(wells[0])
	# A clear spot within reach of a feeder (the feeders stand inside the coop, by its open floor).
	var stand = null
	for p: Vector3 in farming.livestock._yards.values()[0].feeder_points:
		for r in [0.5, 0.7, 0.9]:
			for k in 16:
				var q: Vector3 = p + Vector3(r, 0, 0).rotated(Vector3.UP, k * TAU / 16)
				if stand == null and scene._walk.clear_position(q): stand = q
	_check(stand != null, "a clear spot by the feeder")
	if stand == null: return
	var to_feeder := func() -> void:
		scene._walk.position = stand
		scene._actor.position = stand
		farming.picked = null
		await process_frame
		await process_frame
	await to_feeder.call()
	_check(not farming.livestock.feeder_near(scene._actor.position, farming.get_script().FEED_REACH_M).is_empty()
		and [farming._key.verb, farming._key.cost] == ["Feed", "1 Energy"], "by the feeder, nothing tapped: Feed")
	_check(await _key(farming, well_cell) == ["Fill", "2 Energy", UiSceneAction.State.DEFAULT], "by the feeder, the well tapped: Fill")
	var energy: int = farming.energy_value()
	await _press(farming, well_cell)
	_check(farming.farm.pail_water == 3 and farming.energy_value() == energy - 2 and farming.farm.bag.crop_carrot == 2,
		"Fill pressed by the feeder fills the pail and feeds nothing")
	await to_feeder.call()
	var free := _free_cell(data, farming)
	_check(not farming.livestock.covers(free) and await _key(farming, free) == ["Till", "2 Energy", UiSceneAction.State.DEFAULT],
		"by the feeder, a free cell tapped: Till")
	await to_feeder.call()
	_check((await _key(farming, well_cell))[0] == "Feed", "by the feeder, the well tapped with a full pail: Feed")
	var floor_cell: Vector2i = scene._walk.cell_at(stand)
	_check(farming.livestock.covers(floor_cell) and (await _key(farming, floor_cell))[0] == "Feed", "by the feeder, the coop's floor tapped: Feed")
	farming.picked = null
	await process_frame
	await process_frame
	energy = farming.energy_value()
	farming._key.pressed_down.emit()
	var deadline := Time.get_ticks_msec() + 30000
	while farming.busy and Time.get_ticks_msec() < deadline: await process_frame
	_check(farming.farm.bag.get("crop_carrot", 0) == 1 and farming.energy_value() == energy - 1 and farming.farm.pail_water == 3,
		"Feed pressed: a carrot and 1 Energy, the hens fed")
	scene.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(feed_dir): DirAccess.remove_absolute(feed_dir.path_join(name))
	DirAccess.remove_absolute(feed_dir)

## `n` free core cells side by side along x, or [].
func _free_row(data: Dictionary, farming: Node, n: int) -> Array:
	var house := ParcelFarm.building_cells(farming.farm)
	var obstacles: Dictionary = farming.obstacle_cells()
	var free := func(at: Vector2i) -> bool:
		return data.by_cell.has(at) and data.by_cell[at].zone == "core" and not farming._path.has(at) and not obstacles.has(at) \
			and not house.has(at) and not Space.door_row(farming.farm).has(at) and (at - data.spawn).length() > 3
	for cell: Dictionary in data.cells:
		var row: Array = []
		for dx in n: row.append(Vector2i(cell.x + dx, cell.y))
		if row.all(free): return row
	return []

func _older_dataset_claim() -> void:
	var server := OldClaimServer.new()
	server.block_id = raw.block_id
	server.dataset = "sf-dynamic-farm-older"
	var bag := {"hoe_starter": 1, "seed_carrot": 2, "blueprint_cottage": 1, "blueprint_coop": 1}
	server.farm = ParcelFarm.empty_state()
	server.farm.bag = bag; server.farm.welcomed_at = 0; server.farm.coins = 12; server.farm.sales = 1
	var client := ApiClient.new("https://fake.invalid/v1", server.handle)
	client.token = "player"
	# Before C-136 nothing named the dataset: the reply is about the claim's older dataset and is refused.
	var old: Dictionary = await RemoteStore.new(client, raw.block_id, raw.dataset_version).read()
	_check(not old.ok and old.code == "OTHER_PARCEL", "a reply on the claim's older dataset is still refused")
	server.drop = 1
	var farming := await _open(RemoteStore.new(client, raw.block_id, raw.dataset_version))
	var deadline := Time.get_ticks_msec() + 30000
	while (farming.busy or not farming.loaded()) and Time.get_ticks_msec() < deadline: await process_frame
	_check(server.enters.size() == 2 and server.enters.all(func(b): return b is Dictionary and b.get("dataset_version") == raw.dataset_version),
		"each enter, the lost one and its retry, names the opened farm's dataset")
	_check(farming.loaded() and not farming.unavailable and not farming._cover.visible, "the moved claim opens: no Could not open your farm")
	_check(farming.farm.get("bag") == bag and farming.farm.get("coins") == 12 and farming.farm.get("house", 0) == null and farming.farm.get("tilled") == [],
		"the moved save shows the kept bag and coins on fresh cells")
	scene.queue_free()
	await process_frame
	# Retry from the cover goes the same way: both tries lost, then the key's Retry opens it.
	server.drop = 2
	server.enters.clear()
	server.dataset = "sf-dynamic-farm-older"
	farming = await _open(RemoteStore.new(client, raw.block_id, raw.dataset_version))
	deadline = Time.get_ticks_msec() + 30000
	while farming.busy and Time.get_ticks_msec() < deadline: await process_frame
	_check(farming.unavailable and farming._cover.visible and farming._cover_label.text == "Could not open your farm.", "two lost tries leave the cover up")
	farming._on_key()
	deadline = Time.get_ticks_msec() + 30000
	while (farming.busy or not farming.loaded()) and Time.get_ticks_msec() < deadline: await process_frame
	_check(server.enters.size() == 3 and server.enters[2].get("dataset_version") == raw.dataset_version and farming.loaded() and not farming.unavailable,
		"Retry names the dataset and opens the moved claim")
	scene.queue_free()
	await process_frame

## C-113: the scene's own server store (the one the map's "Enter my farm" gets) names the release of the farm file it
## opened, not the map's: an r6 home's r6 farm names r6, so the server leaves it on r6 (Q-172); an r4 home opens in r8
## and names r8, so the server moves it (Q-168).
func _release_named_on_enter() -> void:
	var net = root.get_node_or_null("Net")
	if net == null:
		_check(false, "Net autoload is present"); return
	var was_client = net.client
	var was_local = ProjectSettings.get_setting("sensen/dynamic_farm/local_farm_save", false)
	ProjectSettings.set_setting("sensen/dynamic_farm/local_farm_save", false)
	for case in [["sf-dynamic-farm-20261124-r6", "sf-dynamic-farm-20261124-r6", "an r6 home opened in its r6 farm names r6 and stays on r6"],
			["sf-dynamic-farm-20261118-r4", "sf-dynamic-farm-20261125-r8", "an r4 home opened in r8 names r8 and moves to r8"]]:
		var server := OldClaimServer.new()
		server.block_id = raw.block_id
		server.dataset = case[0]
		server.farm = ParcelFarm.empty_state()
		server.farm.bag = {"hoe_starter": 1}; server.farm.welcomed_at = 0
		net.client = ApiClient.new("https://fake.invalid/v1", server.handle)
		net.client.token = "player"
		var farm := raw.duplicate(true)
		farm.dataset_version = case[1]
		var farming := await _open(null, farm, true)
		var deadline := Time.get_ticks_msec() + 30000
		while (farming.busy or not farming.loaded()) and Time.get_ticks_msec() < deadline: await process_frame
		_check(server.enters.size() == 1 and server.enters[0].get("dataset_version") == case[1] and server.dataset == case[1]
			and farming.loaded() and not farming.unavailable, case[2])
		scene.queue_free()
		await process_frame
	net.client = was_client
	ProjectSettings.set_setting("sensen/dynamic_farm/local_farm_save", was_local)

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
	var house := ParcelFarm.building_cells(farming.farm)
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
