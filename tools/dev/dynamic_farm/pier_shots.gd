extends SceneTree
## C-232 review pictures of the Aquatic Park pier on the device stand-in save (no server, no map): arrival with the
## Starter Rod toast, a tap on the water at one edge point (walked there, the float out, the bite, the reel, the result),
## then at a second edge point on the other side, and Jasmine's counter with the tackle shelf. The reel is auto-played
## (ParcelFishingPanel.auto_play). Not device or map evidence; the model is SEN-C-233's when the build has it.
##   godot --path <project> --resolution 360x800 --script res://tools/dev/dynamic_farm/pier_shots.gd -- <empty out dir>
## Run with a display (or a virtual one: xvfb-run); SENSEN_OFFLINE=1 keeps Net from signing in.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const PARCEL := "p-review"
var out := ""
var _t0 := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	var dir := out.path_join("save")
	DirAccess.make_dir_recursive_absolute(dir)
	root.size = Vector2i(360, 800)
	_t0 = Time.get_ticks_msec()
	var store := LocalStore.new(PARCEL, dir)
	var start := int(Time.get_unix_time_from_system() * 1000.0)
	store.now_ms = func() -> int: return start + Time.get_ticks_msec() - _t0
	store._save(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {},
		"bag": {"bait_worm": 3}, "welcomed_at": start - 86400000, "coins": 120, "level": 2}), 1)
	var pier: Node3D = (load("res://scenes/dynamic_farm/parcel_pier.tscn") as PackedScene).instantiate()
	pier.setup({"store": store, "parcel_id": PARCEL})
	root.add_child(pier)
	pier.panel.auto_play = true
	await _frames(60)
	await _shot("01_arrival")
	var spots := _spots(pier)
	for i in spots.size():
		var tag := "%02d" % (2 + i * 4)
		pier.tap_scene(pier.cam.unproject_position(spots[i]))
		await _until(func(): return pier.panel.visible, 30.0)
		await _frames(30)
		await _shot(tag + "_cast_%d" % (i + 1))
		await _until(func(): return pier.panel.phase == "hook", 15.0)
		await _shot("%02d_bite_%d" % [3 + i * 4, i + 1])
		await _until(func(): return pier.panel.phase == "playing" and int(pier.panel.model.get("step", 0)) > 50, 15.0)
		await _shot("%02d_reel_%d" % [4 + i * 4, i + 1])
		await _until(func(): return pier.panel.phase == "result", 40.0)
		await _frames(20)
		await _shot("%02d_result_%d" % [5 + i * 4, i + 1])
		await pier.panel.close()
		await _frames(10)
	print("pier shots: ", ParcelFarm.normalize(store.read().farm).get("fishing"))
	pier.queue_free()
	await _frames(5)
	var Town: GDScript = load("res://scenes/dynamic_farm/parcel_town.gd")
	var town: Control = Town.open(root, Town.MARKET, store, PARCEL, dir.path_join("met.json"))
	await _frames(40)
	town.keys.trade.activated.emit()
	await _frames(60)
	await _shot("10_jasmine_tackle")
	quit()

func _spots(pier: Node3D) -> Array:
	var outv := []
	var edge: PackedVector2Array = pier.fish_edge
	var total := 0.0
	for i in edge.size() - 1: total += edge[i].distance_to(edge[i + 1])
	for share in [0.15, 0.6]:
		var left: float = total * float(share)
		for i in edge.size() - 1:
			var seg := edge[i].distance_to(edge[i + 1])
			if left > seg:
				left -= seg
				continue
			var along: Vector2 = (edge[i + 1] - edge[i]).normalized()
			var at: Vector2 = edge[i] + along * left
			for side in [1.0, -1.0]:
				var w: Vector2 = at + Vector2(-along.y, along.x) * float(side) * 2.5
				if Geometry2D.is_point_in_polygon(w, pier.water_polygon) and not Geometry2D.is_point_in_polygon(w, pier.walk_polygon):
					outv.append(Vector3(w.x, pier.water_y, w.y))
					break
			break
	return outv

func _frames(n: int) -> void:
	for i in n: await process_frame

func _until(done: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not done.call() and Time.get_ticks_msec() < end: await process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("C-232_%s.png" % name))
