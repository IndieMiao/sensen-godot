extends SceneTree
## C-59 review pictures of the market (Jasmine) and the carpenter (Scott): their drawn portraits and the greeting,
## counter and blueprint screens, on the device stand-in save (no server, no map). Not device or map evidence.
## C-149 adds Jasmine's seed shelf: Buy after the sale with the stepper at 2, and the counter after buying.
## C-152 adds Scott's farm upgrade: his greeting with Upgrade Farm, the sheet with enough for Lv2, after it (Lv3 short), the top.
##   godot --path <project> --resolution 360x800 --script res://tools/dev/dynamic_farm/town_shots.gd -- <empty out dir> [farm.json]
## With a schema-4 farm (e.g. an r4 parcel) it also opens that parcel on the same save: the bag row with the coins.
## Run with a display (or a virtual one); SENSEN_OFFLINE=1 keeps Net from signing in.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const PARCEL := "p-review"
var Town: GDScript
var out := ""
var dir := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	dir = out.path_join("save")
	DirAccess.make_dir_recursive_absolute(dir)
	Town = load("res://scenes/dynamic_farm/parcel_town.gd")
	root.size = Vector2i(360, 800)
	var backdrop := ColorRect.new()
	backdrop.color = Color("E7F0DF")   # the map's occlusion colour, standing in for the map
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var store := LocalStore.new(PARCEL, dir)
	store._save(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {},
		"bag": {"crop_carrot": 3, "wood": 2, "seed_carrot": 1, "hoe_starter": 1}, "welcomed_at": 0}), 1)
	await _figures()
	var town: Control = Town.open(root, Town.MARKET, store, PARCEL, dir.path_join("met.json"))
	await _settle(town)
	await _shot("01_jasmine_first_meeting")
	town.keys.trade.activated.emit()
	await _settle(town)
	town.counter.grid.select("crop_carrot")
	town.counter.select("crop_carrot")
	await _settle(town)
	await _shot("02_jasmine_counter")
	await town.sell("crop_carrot", 3)
	await _settle(town)
	await _shot("03_jasmine_sold")
	var row: UiShopRow = town.counter.row_of("seed_carrot")
	if row != null and row.stepper != null:
		row.stepper.value = 2
		await _settle(town)
		await _shot("03b_jasmine_buy_two")
		await town.buy("seed_carrot", 2)
		await _settle(town)
		await _shot("03c_jasmine_bought")
	town.close()
	town = Town.open(root, Town.MARKET, store, PARCEL, dir.path_join("met.json"))
	await _settle(town)
	await _shot("04_jasmine_again")
	town.close()
	town = Town.open(root, Town.CARPENTER, store, PARCEL, dir.path_join("met.json"))
	await _settle(town)
	await _shot("05_scott_offer")
	await town.claim_blueprint()
	await _settle(town)
	await _shot("06_scott_given")
	town.close()
	await _upgrade(store)
	if OS.get_cmdline_user_args().size() > 1: await _parcel(OS.get_cmdline_user_args()[1])
	print("TOWN_SHOTS done ", out)
	quit()

## C-152: Scott's greeting and upgrade sheet on a save with Lv2's price and a Timber short for Lv3; then Lv5, the top.
func _upgrade(store: RefCounted) -> void:
	var saved: Dictionary = store.read()
	var farm: Dictionary = saved.farm.duplicate(true)
	farm.coins = 100
	farm.bag.merge({"wood": 15, "stone": 12}, true)
	store._save(farm, int(saved.farm_version))
	var town: Control = Town.open(root, Town.CARPENTER, store, PARCEL, dir.path_join("met.json"))
	await _settle(town)
	await _shot("10_scott_upgrade_key")
	town.open_upgrade()
	await _settle(town)
	await _shot("11_upgrade_lv2")
	await town.upgrade()
	await _settle(town)
	await _shot("12_upgraded_lv3_short")
	town.close()
	saved = store.read()
	farm = saved.farm.duplicate(true)
	farm.level = 5
	store._save(farm, int(saved.farm_version))
	town = Town.open(root, Town.CARPENTER, store, PARCEL, dir.path_join("met.json"))
	await _settle(town)
	town.open_upgrade()
	await _settle(town)
	await _shot("13_upgrade_top")
	town.close()

## Both keepers' drawn portraits side by side (the greeting card's full figure and the counter's round head).
func _figures() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(12, 40)
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	for role in [Town.MARKET, Town.CARPENTER]:
		for card in [true, false]:
			var pic := TextureRect.new()
			pic.texture = Town.portrait(role, card)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.custom_minimum_size = Vector2(70, 154) if card else Vector2(70, 70)
			row.add_child(pic)
	for i in 240:
		await process_frame
	await _shot("00_portraits")
	row.queue_free()

## The owner's parcel on the same save (block id swapped in): the bag row starts with the parcel's coins.
func _parcel(path: String) -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(PARCEL + ".json")))
	var store := LocalStore.new(raw.block_id, dir)
	store._save(ParcelFarm.normalize(saved.farm), int(saved.farm_version))
	var scene: Node3D = (load("res://scenes/dynamic_farm/dynamic_farm.tscn") as PackedScene).instantiate()
	scene.setup({"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true, "farm_store": store})
	var state := {"ready": false}
	scene.preview_ready.connect(func(_summary): state.ready = true)
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 60000
	while not state.ready and Time.get_ticks_msec() < deadline: await process_frame
	for i in 90: await process_frame
	await _shot("07_parcel_coins")
	# UI v3 (C-105): the bag panel with an item picked, then a gain float rising over the scene.
	var farming: Node = scene._farming
	if farming != null and farming.has_method("open_bag"):
		farming.open_bag("crop_carrot" if farming.bag_ids().has("crop_carrot") else "")
		for i in 40: await process_frame
		await _shot("08_parcel_bag")
		farming.close_bag()
		for i in 40: await process_frame
		farming.announce_gains({"wood": 1, "seed_carrot": 2}, Vector2(180, 420))
		for i in 12: await process_frame
		await _shot("09_parcel_gain")
	scene.queue_free()

func _settle(_town: Control) -> void:
	for i in 40:
		await process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("C-59_%s.png" % name))
