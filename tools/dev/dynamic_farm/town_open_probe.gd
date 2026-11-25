extends SceneTree
## C-61 probe: how long a cold start's first Market open takes, and in which step (script load, the town's first frame,
## the keeper portrait's first draw), with frame times. Desktop numbers only show where the time goes; device timing
## comes from the map's DYNAMIC_TOWN_OPEN line on the emulator.
##   godot --path <project> --resolution 360x800 --script res://tools/dev/dynamic_farm/town_open_probe.gd -- <empty dir>
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var dir: String = OS.get_cmdline_user_args()[0]
	var store := LocalStore.new("p-probe", dir)
	store._save(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {},
		"bag": {"crop_carrot": 1}, "welcomed_at": 0}), 1)
	await process_frame
	var t0 := Time.get_ticks_usec()
	var town_script: GDScript = load("res://scenes/dynamic_farm/parcel_town.gd")
	var t_load := Time.get_ticks_usec()
	var town: Control = town_script.open(root, "market", store, "p-probe", dir.path_join("met.json"))
	var t_open := Time.get_ticks_usec()
	var portraits = load("res://modules/p0/p0_keeper_portraits.gd")
	var frames := []
	var last := Time.get_ticks_usec()
	for i in 240:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(int((now - last) / 1000))
		last = now
		if portraits.drawn > 0 and i > 5: break
	print("TOWN_OPEN_PROBE load_ms=%d open_ms=%d frames_ms=%s drawn=%d total_ms=%d" % [(t_load - t0) / 1000, (t_open - t_load) / 1000,
		str(frames), portraits.drawn, (Time.get_ticks_usec() - t0) / 1000])
	town.close()
	quit()
