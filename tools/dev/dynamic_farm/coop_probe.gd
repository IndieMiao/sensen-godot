extends SceneTree
## Coop review captures and the egg pickup prototype (C-154) on C-34's local save, not the server: the Build Coop
## key, the placement preview through the four turns, the coop built with its three hens, Feed at a feeder (a carrot
## and 1 Energy), the fed hen pecking, the egg laid beside her on the ground (the probe moves the store's clock), the
## player walking up to it and the egg flying in and on into the Bag (+1 Egg), then a reopened scene with a second egg
## still on the ground.
##   godot --path "$QA" --script res://tools/dev/dynamic_farm/coop_probe.gd -- <farm.json> <out> [turns]
##   add --write-movie <out>/pickup.avi --fixed-fps 30 for the prototype recording (desktop, scripted input).
## `turns` (0–3, default 1) is how far the built coop is turned. Scripted input; not touch or device evidence.
## With --headless it checks the same states without images. The save lives in <out>/save and is removed first.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Livestock = preload("res://modules/dynamic_farm/farm_livestock.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
var scene
var store
var raw: Dictionary
var out := ""
var report := {}
var shift_ms := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	raw = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	out = args[1]
	var build_turns := int(args[2]) % 4 if args.size() > 2 else 1
	var save_dir := out.path_join("save")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for name in DirAccess.get_files_at(save_dir): DirAccess.remove_absolute(save_dir.path_join(name))
	create_timer(150).timeout.connect(func():
		push_error("Coop probe timed out")
		quit(1))
	# The core's obstacles are cleared in the seeded save, so a 7×5 coop has room in every turn near the player.
	_seed(save_dir, [])
	await _open(save_dir)
	var cleared: Array = scene._farming._anchors.keys().map(func(c: Vector2i): return ParcelFarm.key(c))
	scene.queue_free()
	await process_frame
	_seed(save_dir, cleared)
	await _open(save_dir)
	var id: String = raw.block_id
	report.entered = {"build": scene._build_type, "build_label": scene._build.label, "build_visible": scene._build.visible}
	await _shot(id + "-1-build-key")
	scene.begin_placement()
	var p = scene._placement
	report.start = {"at": [p.at.x, p.at.y], "reason": p.reason, "bar": [p._bar.cancel, p._bar.secondary, p._bar.confirm]}
	await _shot(id + "-2-place")
	report.turns = []
	for i in 4:
		p._bar.secondary_pressed.emit()
		var spot = Building.nearest(scene._data, p.at + Building.middle(p.base, p.rotation_steps), p.base, p._taken, p._path, p._walk_blocked, p.rotation_steps)
		if spot != null: p.move_to(spot)
		report.turns.append({"rotation": p.rotation_steps, "at": [p.at.x, p.at.y], "reason": p.reason})
		await _shot(id + "-2-turn-%d" % p.rotation_steps)
	for i in build_turns: p._bar.secondary_pressed.emit()
	var spot = Building.nearest(scene._data, p.at + Building.middle(p.base, p.rotation_steps), p.base, p._taken, p._path, p._walk_blocked, p.rotation_steps)
	if spot != null: p.move_to(spot)
	report.build_at = {"at": [p.at.x, p.at.y], "rotation": p.rotation_steps, "reason": p.reason}
	p._bar.confirmed.emit()
	for i in 30: await process_frame
	await create_timer(1.0).timeout
	var coop := _coop()
	report.built = {"buildings": scene.buildings_state(), "build_visible": scene._build.visible,
		"walls": scene._buildings[int(coop.id)].proxies.size()}
	_look_at_coop()
	await _shot(id + "-3-built")
	# In through the entry: the player stands just inside the opening.
	var entry: Vector2 = Livestock._vec(Livestock.building_art("coop").get("entry"))
	report.entry = {"inside_clear": scene._walk.clear_position(_yard_point(entry + Vector2(0, -0.6))),
		"outside_clear": scene._walk.clear_position(_yard_point(entry + Vector2(0, 0.6))),
		"fence_blocks": not scene._walk.clear_position(_yard_point(Vector2(2.5, 5.0)))}
	# To the feeder: the key reads Feed · 1 Energy.
	var feeder: Vector2 = Livestock.feeders("coop")[0]
	_stand(_yard_point(feeder + Vector2(0, 0.75)), _yard_point(feeder))
	for i in 6: await process_frame
	var f = scene._farming
	report.feed_key = {"verb": f._key.verb, "cost": f._key.cost, "carrots": int(f.farm.bag.get("crop_carrot", 0))}
	await _shot(id + "-4-feed-key")
	f._on_key()
	await create_timer(1.5).timeout
	report.fed = {"drops": f.farm.drops, "carrots": int(f.farm.bag.get("crop_carrot", 0)), "energy": f.energy_value()}
	await _shot(id + "-5-fed")
	await create_timer(2.0).timeout
	await _shot(id + "-5-pecking")
	# Two minutes on: the hen walks to the spot and lays (the clock jumps to 5 s before the egg is due).
	var due: int = int(f.farm.drops[0].ready_at)
	_jump(due - 5000 - f.server_now())
	await create_timer(6.5).timeout
	report.laid = {"drawn": f.livestock.snapshot()}
	var egg = f.livestock.drop_position(int(f.farm.drops[0].id))
	report.egg_at = [egg.x, egg.z] if egg is Vector3 else null
	scene._focus = egg if egg is Vector3 else scene._focus
	scene._place_camera()
	await _shot(id + "-6-laid")
	# Walk up to it with the stick: in reach (0.8 m) it hops into the player and on into the Bag.
	if egg is Vector3:
		var from: Vector3 = egg + (scene._actor.position - egg).normalized() * 2.2
		_stand(from, egg)
		for i in 4: await process_frame
		var bag_before: int = int(f.farm.bag.get("egg", 0))
		var dir: Vector3 = (egg - from).normalized()
		var shots := 0
		for i in 120:
			if scene._walk.position.distance_to(egg) > 0.35: scene._movement = _stick(dir)
			else: scene._movement = Vector2.ZERO
			await process_frame
			if f._picking.size() > 0 and shots < 3:
				shots += 1
				await _shot(id + "-7-pickup-%d" % shots, false)
		scene._movement = Vector2.ZERO
		await create_timer(1.2).timeout
		report.picked = {"eggs": int(f.farm.bag.get("egg", 0)) - bag_before, "drops": f.farm.drops, "gain": f.last_gains}
		await _shot(id + "-8-in-bag")
	if args.size() > 3 and args[3] == "tour": await _tour(feeder)
	# A second egg left on the ground, then the scene is closed and opened again: it is still there.
	_stand(_yard_point(feeder + Vector2(0, 0.75)), _yard_point(feeder))
	for i in 6: await process_frame
	await f.feed(f._feed_action(f.livestock.feeder_near(scene._actor.position, 1.5)))
	var second: Array = f.farm.drops.duplicate(true)
	scene.queue_free()
	await process_frame
	shift_ms += 130000
	await _open(save_dir)
	f = scene._farming
	for i in 10: await process_frame
	report.reopened = {"drops": f.farm.drops, "same": f.farm.drops == second, "drawn": f.livestock.snapshot()}
	_look_at_coop()
	await _shot(id + "-9-reopened")
	var file := FileAccess.open(out.path_join(id + "-coop.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("COOP_PROBE ", JSON.stringify(report))
	quit(0)

## The pickup prototype up close (`tour`): three carrots for the three hens, the eggs laid round the yard, then the
## player walks from egg to egg and each one flies in on the way.
func _tour(feeder: Vector2) -> void:
	var f = scene._farming
	scene._zoom = 0.8
	_stand(_yard_point(feeder + Vector2(0, 0.75)), _yard_point(feeder))
	for i in 6: await process_frame
	for k in 3: await f.feed(f._feed_action(f.livestock.feeder_near(scene._actor.position, 1.5)))
	await create_timer(2.5).timeout
	var due := 0
	for d: Dictionary in f.farm.drops: due = maxi(due, int(d.ready_at))
	_jump(due - 5000 - f.server_now())
	_stand(_yard_point(Vector2(5.5, 4.4)), _yard_point(Vector2(3.5, 2.5)))
	await create_timer(6.5).timeout
	var before: int = int(f.farm.bag.get("egg", 0))
	var left := 60.0
	while left > 0.0:
		var next = null
		for d: Dictionary in f.farm.drops:
			var at = f.livestock.drop_position(int(d.id))
			if at is Vector3 and int(d.ready_at) <= f.server_now() and (next == null or scene._walk.position.distance_to(at) < scene._walk.position.distance_to(next)):
				next = at
		if next == null: break
		# Round the parts on the scene's own route (C-73), then the last steps straight at the egg.
		var to: Vector3 = next - scene._walk.position
		to.y = 0
		if to.length() > 1.6 and f._picking.is_empty():
			scene._movement = Vector2.ZERO
			await scene.approach([scene._walk.cell_at(next)])
			left -= 2.0
			continue
		scene._movement = _stick(to.normalized()) * 0.6
		await process_frame
		left -= 1.0 / 30.0
	scene._movement = Vector2.ZERO
	await create_timer(1.5).timeout
	report.tour = {"eggs": int(f.farm.bag.get("egg", 0)) - before, "left": f.farm.drops.size()}
	scene._zoom = 1.0

## The save before opening: welcomed, Scott's coop blueprint claimed after a sale, five carrots, no cottage blueprint
## (so the Build key is the coop's), `cleared` core obstacles.
func _seed(save_dir: String, cleared: Array) -> void:
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var farm: Dictionary = ParcelFarm.welcome(ParcelFarm.rules(), ParcelFarm.empty_state(), now - 60000)
	farm.bag.erase("blueprint_cottage")
	farm.bag.blueprint_coop = 1
	farm.bag.crop_carrot = 5
	farm.sales = 1
	farm.coins = 12
	farm.blueprints_claimed = {"coop": now - 30000}
	farm.cleared = cleared
	var file := FileAccess.open(save_dir.path_join(str(raw.block_id).validate_filename() + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"block_id": raw.block_id, "farm_version": 1, "farm": farm}))
	file.close()

func _open(save_dir: String) -> void:
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	store = LocalStore.new(raw.block_id, save_dir)
	store.now_ms = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0) + shift_ms
	scene.setup({"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true, "farm_store": store})
	var ready := [false]
	scene.preview_ready.connect(func(_summary): ready[0] = true)
	scene.preview_error.connect(func(message):
		push_error(message)
		quit(1))
	root.add_child(scene)
	while not ready[0] or scene._farming.farm.is_empty(): await process_frame

## Moves the store's clock and the scene's view of it together.
func _jump(ms: int) -> void:
	shift_ms += ms
	scene._farming._clock_offset_ms += ms

func _coop() -> Dictionary:
	for b: Dictionary in scene.buildings_state():
		if b.type == "coop": return b
	return {}

func _yard_point(local: Vector2) -> Vector3:
	var b := _coop()
	var at := Building.transform(scene._walk, Building.at_of(b), Building.base_of(b), int(b.rotation))
	return at * Livestock.model_point(local, Building.base_of(b), scene._walk.cell_m)

func _look_at_coop() -> void:
	var b := _coop()
	scene._focus = Building.center(scene._walk, Building.at_of(b), Building.base_of(b), int(b.rotation))
	scene._place_camera()

## The player at `where` facing `toward`; the camera follows.
func _stand(where: Vector3, toward: Vector3) -> void:
	scene._walk.position = where
	scene._actor.position = where
	var to := toward - where
	to.y = 0
	if to.length() > 0.01:
		scene._facing = to.normalized()
		scene._actor.look_at(where + scene._facing, Vector3.UP)
	scene._focus = where
	scene._place_camera()

## The stick value that walks along `dir` (scene space) with this camera.
func _stick(dir: Vector3) -> Vector2:
	var right: Vector3 = scene._camera.global_basis.x
	right.y = 0
	var forward: Vector3 = -scene._camera.global_basis.z
	forward.y = 0
	return Vector2(dir.dot(right.normalized()), -dir.dot(forward.normalized())).limit_length(1.0)

func _shot(name: String, settle := true) -> void:
	if settle: for i in 4: await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
