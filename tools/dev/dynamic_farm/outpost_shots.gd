extends SceneTree
## C-115 review pictures on a desktop (not device evidence): the Union Square room (parcel_outpost.tscn) on the local
## stand-in save — the opening view, Jasmine's greeting and counter, Scott's greeting, the door's Map strip — and the map's
## Union Square pin and place card over a plain stand-in for the native map (the desktop has no Mapbox).
##   godot --path <project> --resolution 360x800 --script res://tools/dev/dynamic_farm/outpost_shots.gd -- <new empty dir>
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const CameraInput = preload("res://modules/dynamic_farm/map/geo_native_camera.gd")
const TownEntry = preload("res://scenes/dynamic_farm/town_entry.gd")
const PARCEL := "p-shots"
var out := ""

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("OUTPOST_SHOT ", path)

func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await process_frame

func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	var store := LocalStore.new(PARCEL, out.path_join("save"))
	store._save(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {},
		"bag": {"crop_carrot": 2, "wood": 3}, "welcomed_at": 0}), 1)
	var room: Node3D = (load("res://scenes/dynamic_farm/parcel_outpost.tscn") as PackedScene).instantiate()
	room.setup({"store": store, "parcel_id": PARCEL, "met_path": out.path_join("save/met.json")})
	root.add_child(room)
	await _wait(2.0)
	await _shot("01_room_opening")
	room.walk_to("npc_keeper")
	while not is_instance_valid(room.town): await process_frame
	await _wait(1.5)
	await _shot("02_jasmine_greeting")
	room.town.open_counter()
	await _wait(1.0)
	await _shot("03_jasmine_counter")
	await room.town.sell("crop_carrot", 2)
	room.town.close()
	await _wait(0.5)
	room.walk_to("npc_sam")
	while not is_instance_valid(room.town): await process_frame
	await _wait(1.5)
	await _shot("04_scott_greeting")
	room.town.close()
	await _wait(0.3)
	room.p0_dev(PackedStringArray(["nearexit"]))
	await _wait(1.0)
	await _shot("05_door_map")
	room.queue_free()
	await process_frame
	# The map's pin and card over a plain stand-in for the native map.
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(page)
	var cam: Control = CameraInput.new()
	page.add_child(cam)
	cam.frame_center(TownEntry.LON, TownEntry.LAT + 0.0012, 17.0)
	var entry: Control = TownEntry.new()
	entry.camera = cam
	entry.visible = true
	page.add_child(entry)
	await _wait(0.5)
	await _shot("06_map_pin")
	entry.home_center = [-122.4194, 37.7749]
	cam.frame_center(TownEntry.LON, TownEntry.LAT, 17.0)   # as the map flies a low pin to the middle
	entry.open_card()
	await _wait(0.6)
	await _shot("07_map_card")
	print("OUTPOST_SHOTS done ", out)
	quit(0)
