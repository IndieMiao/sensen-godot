extends SceneTree
## C-107 review pictures of the in-game phone on one's own parcel (design C-85 ⑧), on the device stand-in save (no
## server, no map): the task button's dot, the drop-down, the phone's Tasks / Inbox / Collection pages and a step
## finished with the drop-down up. Not device evidence (the emulator recording is).
##   godot --path <project> --resolution 360x800 --script res://tools/dev/dynamic_farm/phone_shots.gd -- <empty out dir> <farm.json>
## Run with a display (or a virtual one); SENSEN_OFFLINE=1 keeps Net from signing in.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
var out := ""
var farming: Node
var scene: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var dir := out.path_join("save")
	DirAccess.make_dir_recursive_absolute(dir)
	root.size = Vector2i(360, 800)
	var store := LocalStore.new(raw.block_id, dir)
	scene = (load("res://scenes/dynamic_farm/dynamic_farm.tscn") as PackedScene).instantiate()
	scene.setup({"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true, "farm_store": store})
	var state := {"ready": false}
	scene.preview_ready.connect(func(_summary): state.ready = true)
	root.add_child(scene)
	farming = scene.get_node("ParcelFarming")
	farming.phone_seen_path = dir.path_join("phone.json")
	var deadline := Time.get_ticks_msec() + 60000
	while not (state.ready and farming.loaded()) and Time.get_ticks_msec() < deadline: await process_frame
	await _settle(90)
	await _shot("01_hud_new_task")
	farming.toggle_tasks()
	await _settle(30)
	await _shot("02_drop_down")
	farming.drop_down.fold()
	await _settle(20)
	farming.open_phone()
	await _settle(40)
	await _shot("03_phone_tasks_first_visit")
	farming.close_phone()
	await _settle(30)
	# A step done with the drop-down up: the row's beat, then the rows move on.
	farming.toggle_tasks()
	await _settle(20)
	var next: Dictionary = farming.farm.duplicate(true)
	next.house = {"model": "cottage", "x": 0, "y": 0, "width": 3, "depth": 3, "rotation": 0, "built_at": 0}
	next.buildings = []
	next.tilled = ["0,0"]
	next.bag.erase("blueprint_cottage")
	farming._adopt({"ok": true, "farm": next, "farm_version": farming.farm_version + 1})
	await _settle(8)
	await _shot("04_drop_down_step_done")
	await _settle(110)
	await _shot("05_drop_down_moved_on")
	farming.drop_down.fold()
	await _settle(20)
	farming.open_phone()
	await _settle(40)
	await _shot("06_phone_tasks_sow")
	farming.phone.tab_selected.emit(1)
	await _settle(30)
	await _shot("07_phone_inbox")
	farming.phone.tab_selected.emit(2)
	await _settle(30)
	await _shot("08_phone_collection")
	# The pages over P0-style data, as the main farm would fill them (the dynamic farm has none yet).
	var view := {"inbox": {"parcels": [
			{"key": "p1", "id": "crop_radish", "qty": 5, "source": "Order reward", "left": 86400000, "can_claim": true},
			{"key": "p2", "id": "tea", "qty": 1, "source": "Gift from Mia", "left": 2 * 86400000, "can_claim": true}],
		"updates": []}, "bag": {"capacity": 25, "free": 6}}
	var fish := {"id": "fish", "name": "Fish", "icon": UiArt.item("fish_koi"), "got": 2, "total": 8, "items": []}
	for id in ["fish_koi", "fish_perch", "fish_crucian", "fish_sturgeon"]:
		fish.items.append({"icon": UiArt.item(id), "got": id in ["fish_koi", "fish_perch"]})
	for id in ["fish_koi", "fish_perch", "fish_crucian", "fish_sturgeon"]: fish.items.append({"icon": UiArt.item(id), "got": false})
	farming.phone.refresh(farming.phone.tasks, view, [fish, {"id": "pages", "name": "Pages", "icon": UiArt.item("vegetable_soup"),
		"got": 12, "total": 48, "items": []}])
	await _settle(40)
	await _shot("09_phone_collection_data")
	(farming.phone.page.find_child("Card_fish", true, false) as Button).pressed.emit()
	await _settle(30)
	await _shot("10_phone_collection_grid")
	farming.phone.tab_selected.emit(1)
	await _settle(30)
	await _shot("11_phone_inbox_data")
	print("PHONE_SHOTS done ", out)
	quit()

func _settle(frames: int) -> void:
	for i in frames: await process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("C-107_%s.png" % name))
