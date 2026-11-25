extends SceneTree
## Building placement review captures (C-33 first house, C-150 turns) on C-34's local save, not the server: the gift
## on first entry, the placement preview on a valid spot, turned through 90, 180 and 270° with Rotate, and on each
## refused kind (outside the core, over an obstacle, on the protected path), the cottage built turned (the last turn
## pressed) popping in with dust (C-114, three frames 0.1 s apart) and settled, the player against its wall, then a
## reopened scene with it in place and turned the same (no pop, no dust).
##   godot --path "$QA" [--debug-collisions] --script res://tools/dev/dynamic_farm/building_probe.gd -- <farm.json> <out> [turns]
## `turns` (0–3, default 1) is how far the built cottage is turned.
## Scripted input; not touch or device evidence. The save lives in <out>/save and is removed first.
## With --headless it checks the same states without images.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
var scene
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
	var build_turns := int(args[2]) % 4 if args.size() > 2 else 1
	var save_dir := out.path_join("save")
	for name in DirAccess.get_files_at(save_dir): DirAccess.remove_absolute(save_dir.path_join(name))
	create_timer(90).timeout.connect(func():
		push_error("House probe timed out")
		quit(1))
	await _open(save_dir)
	var id: String = raw.block_id
	report.entered = {"build":scene._build_type, "build_label":scene._build.label, "build_visible":scene._build.visible}
	await _shot(id + "-1-entered")
	scene.begin_placement()
	var p = scene._placement
	report.start = {"at":[p.at.x, p.at.y], "reason":p.reason, "farming_key_held":not scene._farming._key.visible,
		"bar":[p._bar.cancel, p._bar.secondary, p._bar.confirm]}
	await _shot(id + "-2-valid")
	report.turns = []
	for i in 4:
		p._bar.secondary_pressed.emit()
		var z: Vector3 = p._ghost.transform.basis.z
		report.turns.append({"rotation":p.rotation_steps, "at":[p.at.x, p.at.y], "reason":p.reason, "front":[snappedf(z.x, 0.001), snappedf(z.z, 0.001)]})
		await _shot(id + "-2-turn-%d" % p.rotation_steps)
	var kinds := _refused_spots()
	for kind: String in kinds:
		p.move_to(kinds[kind])
		report[kind] = {"at":[p.at.x, p.at.y], "reason":p.reason}
		await _shot(id + "-3-" + kind)
	p.move_to(Vector2i(report.start.at[0], report.start.at[1]))
	for i in build_turns: p._bar.secondary_pressed.emit()
	p._bar.confirmed.emit()
	scene._focus = _center()
	scene._place_camera()
	report.pop = []
	for i in 3:
		await create_timer(0.1).timeout
		report.pop.append({"scale":_node().scale.x, "dust":_dust()})
		await _shot(id + "-4-pop-%d" % i, false)
	await create_timer(1.0).timeout
	report.built = {"buildings":scene.buildings_state(), "house":scene._farming.farm.house, "build_visible":scene._build.visible}
	scene._focus = scene._actor.position
	await _shot(id + "-4-built")
	report.wall = _walk_to_wall()
	scene._focus = scene._actor.position
	scene._place_camera()
	await _shot(id + "-5-wall")
	scene.queue_free()
	await process_frame
	await _open(save_dir)
	var front: Vector3 = _node().transform.basis.z
	report.reopened = {"buildings":scene.buildings_state(), "build_visible":scene._build.visible,
		"node":is_instance_valid(_node()), "scale":_node().scale.x, "front":[snappedf(front.x, 0.001), snappedf(front.z, 0.001)], "dust":_dust()}
	scene._focus = _center()
	scene._place_camera()
	await _shot(id + "-6-reopened")
	var file := FileAccess.open(out.path_join(id + "-building.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("BUILDING_PROBE ", JSON.stringify(report))
	quit(0)

func _open(save_dir: String) -> void:
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup({"farm":raw, "dataset":raw.dataset_version, "block_id":raw.block_id, "own_parcel":true,
		"farm_store":LocalStore.new(raw.block_id, save_dir)})
	var ready := [false]
	scene.preview_ready.connect(func(_summary): ready[0] = true)
	scene.preview_error.connect(func(message):
		push_error(message)
		quit(1))
	root.add_child(scene)
	while not ready[0] or scene._farming.farm.is_empty(): await process_frame

func _shot(name: String, settle := true) -> void:
	if settle: for i in 4: await process_frame
	if DisplayServer.get_name() == "headless": return   # states only
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))

## The first building (the cottage) and its middle.
func _first() -> Dictionary:
	return scene.buildings_state()[0]

func _node() -> Node3D:
	return scene._buildings[int(_first().id)].node

func _center() -> Vector3:
	var b := _first()
	return Building.center(scene._walk, Building.at_of(b), Building.base_of(b), int(b.rotation))

func _dust() -> int:
	return scene.get_children().filter(func(n): return n is CPUParticles3D).size()

## One spot of each refused kind near the start, judged by the same rules the preview uses.
func _refused_spots() -> Dictionary:
	var p = scene._placement
	var found := {}
	var wanted := {Building.OUTSIDE:"outside", Building.TAKEN:"obstacle", Building.PATH:"path"}
	var start: Vector2i = p.at
	for r in range(1, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r: continue
				var at: Vector2i = start + Vector2i(dx, dy)
				var why := Building.reason(scene._data, at, p.base, p.rotation_steps, p._taken, p._path, p._walk_blocked)
				if wanted.has(why) and not found.has(wanted[why]): found[wanted[why]] = at
		if found.size() == wanted.size(): break
	return found

## Walk the player straight at a cottage wall (the front first) from 1.6 m out.
func _walk_to_wall() -> Dictionary:
	var c := _center()
	for side in [Vector3.BACK, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD]:
		if not scene._walk.clear_position(c + side * 1.6): continue
		scene._walk.position = c + side * 1.6
		for i in 40: scene._walk.move(-side * 0.05)
		scene._actor.position = scene._walk.position
		scene._actor.look_at(scene._actor.position - side, Vector3.UP)
		var proxy = scene._buildings[int(_first().id)].proxy
		return {"side":[side.x, side.z], "position":[scene._walk.position.x, scene._walk.position.z],
			"gap_m":proxy.gap(scene._walk.position) - 0.3}
	return {}
