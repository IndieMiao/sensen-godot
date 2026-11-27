extends SceneTree
## Barn feeder key captures (C-192) on C-34's local save, not the server: the main key by the barn's feeder with no
## carrots (`Feed` over `Need 2 more`, the tap's toast `Need 2 more Carrot`), with the ground full (2, SEN-Q-282) of milk
## on its way (`Cows are fed`) and of milk given (`Pick up milk first`), each as the whole screen after the tap and the key
## enlarged. Scripted state; not touch or device evidence.
##   godot --path "$QA" --script res://tools/dev/dynamic_farm/barn_key_shots.gd -- <farm.json> <out>
## With --headless it prints the same key texts without images. The save lives in <out>/save and is removed first.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const KEY_ZOOM := 4
var scene
var store
var raw: Dictionary
var out := ""
var report := {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	raw = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	out = args[1]
	var save_dir := out.path_join("save")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for name in DirAccess.get_files_at(save_dir): DirAccess.remove_absolute(save_dir.path_join(name))
	store = LocalStore.new(raw.block_id, save_dir)
	var data: Dictionary = preload("res://modules/dynamic_farm/farm_data.gd").decode(raw)
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var seeded := ParcelFarm.empty_state()
	seeded.welcomed_at = now - 8 * 86400000
	seeded.bag = {"hoe_starter": 1, "blueprint_barn": 1, "crop_carrot": 2, "wood": 20, "stone": 10}
	store._save(seeded, 1)
	var farming := await _open()
	var cleared := {}
	for anchor: Vector2i in farming._obstacles.values(): cleared[ParcelFarm.key(anchor)] = true
	seeded.cleared = cleared.keys()
	store._save(seeded, 2)
	farming = await _reopen()
	var obstacles: Dictionary = farming.obstacle_cells()
	var at = Building.nearest(scene._data, data.spawn, Vector2i(8, 6), Building.blocked(obstacles, farming.farm), farming.protected_path(),
		scene._walk_blocked(obstacles), 0, "barn")
	var placed: Dictionary = await farming.send({"type": "place_building", "building": "barn", "x": at.x, "y": at.y, "rotation": 0}) \
		if at != null else {}
	report.placed = placed.get("ok", false)
	var barn: Dictionary = ParcelFarm.buildings_of(farming.farm).filter(func(b): return b.type == "barn")[0]
	await _to_feeder(farming)
	report.before_feed = [farming._key.verb, farming._key.cost]
	farming._key.pressed_down.emit()
	while farming.busy: await process_frame
	for i in 90: await process_frame   # the gain float and the labour clip settle
	await _to_feeder(farming)
	await _tap_and_shoot(farming, "need_2_more")
	# Two milks (one per cow) on spots away from the feeder, so standing there picks neither up: on their way, then given.
	var t := int(Time.get_unix_time_from_system() * 1000.0)
	for shot: Array in [["cows_are_fed", t + 900000], ["pick_up_milk_first", t - 1000]]:
		var full: Dictionary = farming.farm.duplicate(true)
		full.bag.crop_carrot = 2
		full.drops = []
		for i in 2: full.drops.append({"id": i + 1, "item": "milk", "amount": 1, "building": int(barn.id), "animal": i, "spot": [3, 4][i],
			"ready_at": shot[1]})
		full.drop_seq = 2
		store._save(full, farming.farm_version + 1)
		farming = await _reopen()
		await _to_feeder(farming)
		await _tap_and_shoot(farming, shot[0])
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("BARN_KEY_SHOTS ", JSON.stringify(report))
	quit(0)

func _open() -> Node:
	var args := {"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true, "farm_store": store}
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup(args)
	var state := {"ready": false}
	scene.preview_ready.connect(func(_summary): state.ready = true)
	root.add_child(scene)
	while not state.ready: await process_frame
	var farming: Node = scene.get_node("ParcelFarming")
	while farming.busy or not farming.loaded(): await process_frame
	return farming

func _reopen() -> Node:
	scene.queue_free()
	await process_frame
	return await _open()

## The player on a clear spot by the barn's feeder (as the coop's tests stand), nothing tapped.
func _to_feeder(farming: Node) -> void:
	var stand = null
	for p: Vector3 in farming.livestock._yards.values()[0].feeder_points:
		for r in [0.5, 0.7, 0.9]:
			for k in 16:
				var q: Vector3 = p + Vector3(r, 0, 0).rotated(Vector3.UP, k * TAU / 16)
				if stand == null and scene._walk.clear_position(q): stand = q
	scene._walk.position = stand
	scene._actor.position = stand
	farming.picked = null
	for i in 3: await process_frame

## Taps the refused key (its toast says the whole sentence), then saves the screen and the key enlarged.
func _tap_and_shoot(farming: Node, name: String) -> void:
	farming._key.pressed_down.emit()
	farming._key.released.emit()
	for i in 12: await process_frame
	report[name] = {"verb": farming._key.verb, "cost": farming._key.cost, "fits": UiSceneAction.cost_fits(farming._key.cost),
		"toast": farming._toast.current_text()}
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out.path_join("C-192-%s.png" % name))
	var scale := root.get_final_transform().get_scale()
	var rect: Rect2 = farming._key.get_global_rect()
	var crop: Rect2i = Rect2i(Vector2i(rect.position * scale), Vector2i(rect.size * scale)).grow(int(8 * scale.x)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var key := image.get_region(crop)
	key.resize(key.get_width() * KEY_ZOOM / int(maxf(scale.x, 1.0)), key.get_height() * KEY_ZOOM / int(maxf(scale.x, 1.0)), Image.INTERPOLATE_NEAREST)
	key.save_png(out.path_join("C-192-%s-key.png" % name))
