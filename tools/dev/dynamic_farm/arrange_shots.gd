extends SceneTree
## Arrange mode captures (C-229) on C-34's local save, not the server: the book with its Arrange key, the arrange
## mode's markers and Done, the coop's card (an egg laid, one on its way: Store waits), the well's Store question, the
## coop's move preview with its old outline dashed, and the yard after the coop moved and the well was stored. Scripted
## state; not touch or device evidence.
##   godot --path "$QA" --resolution 540x1170 --script res://tools/dev/dynamic_farm/arrange_shots.gd -- <farm.json> <out>
## The save lives in <out>/save and is removed first.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
var scene
var store
var raw: Dictionary
var out := ""

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
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var seeded := ParcelFarm.empty_state()
	seeded.welcomed_at = now - 86400000
	seeded.grants = {"watering": now}
	seeded.bag = {"hoe_starter": 1, "pail": 1, "blueprint_cottage": 1, "blueprint_coop": 1, "blueprint_well": 1, "crop_carrot": 2}
	store._save(seeded, 2)
	var farming := await _open()
	var cleared := {}
	for anchor: Vector2i in farming._obstacles.values(): cleared[ParcelFarm.key(anchor)] = true
	seeded.cleared = cleared.keys()
	store._save(seeded, 3)
	await _close()
	farming = await _open()
	for type in ["cottage", "coop", "well"]: await _place(type)
	await _close()
	var saved: Dictionary = store._load()
	var coop := 0
	for b: Dictionary in saved.farm.buildings:
		if b.type == "coop": coop = int(b.id)
	now = int(Time.get_unix_time_from_system() * 1000.0)
	saved.farm.drops = [{"id": 1, "item": "egg", "amount": 1, "building": coop, "animal": 0, "spot": 1, "ready_at": now - 60000},
		{"id": 2, "item": "egg", "amount": 1, "building": coop, "animal": 1, "spot": 4, "ready_at": now + 600000}]
	saved.farm.drop_seq = 2
	store._save(saved.farm, int(saved.version) + 1)
	farming = await _open()
	scene._build.pressed.emit()
	await _frames(20)
	_shot("1-book")
	scene._book.arrange_key.pressed.emit()
	await _frames(30)
	_shot("2-arrange")
	var arrange = scene._arrange
	arrange.select(coop)
	await _frames(30)
	_shot("3-coop-card")
	var well := 0
	for b: Dictionary in scene.buildings_state():
		if b.type == "well": well = int(b.id)
	arrange.select(well)
	await _frames(10)
	arrange.store_key.pressed.emit()
	await _frames(30)
	_shot("4-store-question")
	(arrange.card.find_child("StoreConfirm", true, false) as UiCommandButton).pressed.emit()
	await _frames(40)
	_shot("5-well-stored")
	arrange.select(coop)
	await _frames(10)
	arrange.move_key.pressed.emit()
	await _frames(10)
	var p = scene._placement
	var start: Vector2i = p.at
	var found := false
	for r in range(3, 30):
		for dy in range(-r, r + 1):
			for cell in [start + Vector2i(-r, dy), start + Vector2i(r, dy), start + Vector2i(dy, -r), start + Vector2i(dy, r)]:
				if found: break
				p.move_to(cell)
				found = p.reason == ""
	await _frames(20)
	_shot("6-move-preview")
	p._bar.confirmed.emit()
	await _frames(60)
	_shot("7-coop-moved")
	await _close()
	print("ARRANGE_SHOTS done %s" % out)
	quit(0)

func _open() -> Node:
	var args := {"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true, "farm_store": store}
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup(args)
	var state := {"ready": false}
	scene.preview_ready.connect(func(_summary): state.ready = true)
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 60000
	while not state.ready and Time.get_ticks_msec() < deadline: await process_frame
	var farming: Node = scene.get_node("ParcelFarming")
	deadline = Time.get_ticks_msec() + 20000
	while not farming.loaded() and Time.get_ticks_msec() < deadline: await process_frame
	await _frames(10)
	return farming

func _close() -> void:
	scene.queue_free()
	await _frames(2)

func _frames(n: int) -> void:
	for _i in n: await process_frame

func _place(type: String) -> void:
	if not scene.book_open(): scene._build.pressed.emit()
	await _frames(2)
	if scene._book == null or not scene._book.keys.has(type): return
	scene._book.keys[type].pressed.emit()
	await _frames(2)
	var p = scene._placement
	if p == null: return
	for i in 4:
		if p.reason == "": break
		p.turn()
	p._bar.confirmed.emit()
	var deadline := Time.get_ticks_msec() + 5000
	while (scene._placement != null or scene._sending) and Time.get_ticks_msec() < deadline: await process_frame
	await _frames(5)

func _shot(name: String) -> void:
	var image := root.get_texture().get_image()
	if image == null: return
	image.save_png(out.path_join("C-229-%s.png" % name))
