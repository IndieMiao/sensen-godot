extends SceneTree
## C-34 against a running C-31 server (real save, real server clock; nothing is shifted):
## `-- <base_url ending in /v1> <bearer token of the parcel's owner> <farm.json>`.
## The owner must already have claimed that parcel and not entered it yet. Takes ~70 s:
## it waits for the carrot to ripen on the server clock. C-151: the carrot is sown dry and the server does not ripen it;
## Build Well, Fill at the well and Water start it, and it ripens 60 s after the watering. C-152: a short upgrade is refused.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const RemoteStore = preload("res://modules/dynamic_farm/parcel_farm_remote_store.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
var checks := 0
var failures := 0
var raw: Dictionary
var client: ApiClient
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
	raw = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	client = ApiClient.new(args[0], ApiClient.make_http_transport(root))
	client.token = args[1]
	var cell := await _first_visit()
	# After the first visit: entering grants the owner's gift whichever parcel the client asked about.
	var stranger: Dictionary = await RemoteStore.new(client, "p-0", raw.dataset_version).enter()
	_check(not stranger.ok and stranger.code == "OTHER_PARCEL" and not stranger.has("farm"), "a reply about another parcel is refused")
	await _reopen(cell)
	print("PARCEL_FARMING_SERVER checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _open() -> Node:
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup({"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true,
		"farm_store": RemoteStore.new(client, raw.block_id, raw.dataset_version)})
	var state := {"ready": false}
	scene.preview_ready.connect(func(_summary): state.ready = true)
	root.add_child(scene)
	var farming: Node
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		farming = scene.get_node_or_null("ParcelFarming")
		if state.ready and farming != null and not farming.farm.is_empty(): break
		await process_frame
	_check(state.ready and not farming.farm.is_empty(), "own parcel opens on the server save")
	return farming

func _settle(farming: Node) -> void:
	await process_frame
	var deadline := Time.get_ticks_msec() + 30000  # a press walks there first (C-73)
	while farming.busy and Time.get_ticks_msec() < deadline: await process_frame
	await process_frame

func _press(farming: Node, cell: Vector2i) -> void:
	farming.pick(cell)
	await process_frame
	await process_frame
	farming._key.pressed_down.emit()
	await _settle(farming)

func _first_visit() -> Vector2i:
	var farming := await _open()
	_check(farming.farm.bag.get("hoe_starter") == 1 and farming.farm.bag.get("seed_carrot") == 3, "the server grants 1 hoe, 3 carrot seeds")
	_check(farming.last_gains == {"hoe_starter": 1, "seed_carrot": 3, "blueprint_cottage": 1, "blueprint_well": 1, "pail": 1},
		"the gift and the watering grant are announced: %s" % [farming.last_gains])
	_check(absi(farming.server_now() - int(Time.get_unix_time_from_system() * 1000.0)) < 5000, "the clock follows server_time")
	var obstacle := Vector2i(-1, -1)
	for item: Dictionary in farming._core_plan.layout:
		if item.solid:
			obstacle = item.cell
			break
	await _press(farming, obstacle)
	_check(ParcelFarm.key(obstacle) in farming.farm.cleared and scene._walk.clear_position(scene._walk.point(obstacle)), "one press clears on the server")
	var cell := Vector2i(-1, -1)
	for item: Dictionary in scene._data.cells:
		var at := Vector2i(item.x, item.y)
		if item.zone == "core" and not farming._path.has(at) and not farming._obstacles.has(at):
			cell = at
			break
	await _press(farming, cell)
	_check(ParcelFarm.key(cell) in farming.farm.tilled, "one press tills on the server")
	await _press(farming, cell)
	var crop: Dictionary = farming.farm.crops.get(ParcelFarm.key(cell), {})
	_check(ParcelFarm.is_dry(crop) and crop.get("ripe_at") == ParcelFarm.NEVER and farming.farm.bag.get("seed_carrot") == 2, "the server sows it dry")
	_check(farming.farm.bag.get("hoe_starter") == 1, "nothing but the seed was used")
	var dry: Dictionary = await farming.store.send(farming.farm_version, [{"type": "harvest", "cell": ParcelFarm.key(cell)}])
	_check(not dry.ok and dry.code == "NOT_WATERED", "the server refuses to harvest a carrot not watered")
	var empty: Dictionary = await farming.store.send(farming.farm_version, [{"type": "water", "cell": ParcelFarm.key(cell)}])
	_check(not empty.ok and empty.code == "PAIL_EMPTY", "the server refuses water from an empty pail")
	# The Build key offers the cottage first (its blueprint is still in the bag here), then the well.
	for _i in 2:
		if not ParcelFarm.wells(farming.rules, farming.farm).is_empty() or not scene._build.visible: break
		scene._build.activated.emit()
		await process_frame
		scene._placement._bar.confirmed.emit()
		await _settle(farming)
	var wells: Array = ParcelFarm.wells(farming.rules, farming.farm)
	_check(wells.size() == 1, "Build Well stands the well on the server")
	if wells.is_empty(): return cell
	var well_cell := Vector2i(int(wells[0].x), int(wells[0].y))
	var energy: int = farming.energy_value()
	await _press(farming, well_cell)
	_check(farming.farm.pail_water == 3 and farming.energy_value() == energy - 2, "Fill at the well: a pail of 3 for 2 Energy on the server")
	await _press(farming, cell)
	crop = farming.farm.crops.get(ParcelFarm.key(cell), {})
	_check(crop.get("ripe_at", 0) - crop.get("watered_at", 0) == 60000 and farming.farm.pail_water == 2, "the server ripens it 60 s after watering")
	var twice: Dictionary = await farming.store.send(farming.farm_version, [{"type": "water", "cell": ParcelFarm.key(cell)}])
	_check(not twice.ok and twice.code == "ALREADY_WATERED", "the server refuses watering a cell twice")
	# The server itself refuses an early harvest, whatever the client shows.
	var early: Dictionary = await farming.store.send(farming.farm_version, [{"type": "harvest", "cell": ParcelFarm.key(cell)}])
	_check(not early.ok and early.code == "NOT_RIPE", "the server refuses an early harvest")
	scene.queue_free()
	await process_frame
	return cell

func _reopen(cell: Vector2i) -> void:
	var farming := await _open()
	_check(farming.farm.bag.get("seed_carrot") == 2 and farming.farm.bag.get("hoe_starter") == 1 and farming.farm.bag.get("pail") == 1
		and not farming.farm.bag.has("blueprint_well") and not farming.farm.bag.has("blueprint_cottage"), "reopening grants nothing more")
	_check(farming.last_gains.is_empty(), "no second gift announced")
	_check(farming.farm.cleared.size() == 1 and ParcelFarm.key(cell) in farming.farm.tilled, "cleared and tilled cells come back")
	var crop: Dictionary = farming.farm.crops.get(ParcelFarm.key(cell), {})
	_check(crop.get("ripe_at", 0) > farming.server_now() and crop.get("ripe_at", 0) < farming.server_now() + 120000, "the carrot is still growing")
	if crop.get("ripe_at", 0) >= farming.server_now() + 120000: return
	while farming.server_now() < int(crop.get("ripe_at", 0)) + 500: await create_timer(1.0).timeout
	farming.pick(cell)
	await process_frame
	await process_frame
	_check(farming._key.verb == "Harvest", "ripe on the server clock")
	await _press(farming, cell)
	_check(farming.farm.bag.get("crop_carrot") == 1 and farming.last_gains == {"crop_carrot": 1}, "the harvest is in the bag")
	var mine: ApiClient.Response = await client.request("GET", "/parcels/mine")
	_check(mine.json.get("parcel", {}).get("farm", {}).get("bag", {}).get("crop_carrot") == 1.0, "and in the server save")
	# C-152: Scott's upgrade without its Timber, Stone and coins: the server refuses it and the farm stays Lv1.
	var upgrade: Dictionary = await farming.store.send(farming.farm_version, [{"type": "upgrade_farm"}])
	_check(not upgrade.ok and upgrade.code == "NOT_ENOUGH" and upgrade.get("detail", {}).get("item") == "wood"
		and ParcelFarm.farm_level(upgrade.get("farm", {})) == 1, "the server refuses an upgrade without its materials, still Lv1")
	scene.queue_free()
	await process_frame
