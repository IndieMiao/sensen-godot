extends SceneTree
## Well and pail review (C-151) on C-34's local save, not the server: the first entry (the gift and the watering grant),
## Build Cottage and Build Well through the real placement, four carrots sown in a row beside the well, a pail drawn at
## the well and two of them watered. Captures the row (two wet, two dry), the key at the well and the key on a dry
## carrot; writes what the scene drew to <out>/watering.json.
##   godot --path "$QA" --script res://tools/dev/dynamic_farm/watering_probe.gd -- <farm.json> <out>
## Scripted; not touch or device evidence. <out>/save is cleared first. With --headless: states only.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
var scene
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
	create_timer(120).timeout.connect(func():
		push_error("Watering probe timed out")
		quit(1))
	var store := LocalStore.new(raw.block_id, save_dir)
	await _open(store)
	var farming = scene._farming
	var report := {"gift": farming.last_gains.duplicate()}
	# The cottage, then the well, each on the valid spot the placement starts on (nearest the player).
	for _i in 2:
		scene.begin_placement()
		await process_frame
		scene._placement._bar.confirmed.emit()
		while farming.busy or scene._placement != null: await process_frame
	var wells: Array = ParcelFarm.wells(farming.rules, farming.farm)
	if wells.is_empty():
		push_error("No well was built")
		quit(1)
		return
	var well_cell := Building.at_of(wells[0])
	var row := _row(farming, well_cell, 4)
	if row.is_empty():
		push_error("No four free cells beside the well")
		quit(1)
		return
	var version: int = farming.farm_version
	var commands: Array = []
	for cell: Vector2i in row: commands.append({"type": "till", "cell": ParcelFarm.key(cell)})
	version = store.send(version, commands).farm_version
	var saved = JSON.parse_string(FileAccess.get_file_as_string(save_dir.path_join(raw.block_id.validate_filename() + ".json")))
	saved.farm.bag.seed_carrot = 4   # enough for the row; the save is a review fixture
	FileAccess.open(save_dir.path_join(raw.block_id.validate_filename() + ".json"), FileAccess.WRITE).store_string(JSON.stringify(saved))
	commands = []
	for cell: Vector2i in row: commands.append({"type": "sow", "cell": ParcelFarm.key(cell), "crop": "crop_carrot"})
	version = store.send(version, commands).farm_version
	var watered := store.send(version, [{"type": "draw_water", "building": int(wells[0].id)},
		{"type": "water", "cell": ParcelFarm.key(row[0])}, {"type": "water", "cell": ParcelFarm.key(row[1])}])
	report.watered = watered.ok
	scene.queue_free()
	await process_frame
	await _open(store)
	farming = scene._farming
	scene._focus = (scene._walk.point(row[1]) + scene._walk.point(well_cell)) * 0.5
	scene._place_camera()
	farming._draw_crops()
	report.row = row.map(func(c): return [c.x, c.y])
	report.well = [well_cell.x, well_cell.y]
	report.pail_water = farming.farm.pail_water
	report.counts = farming._crop_art.counts()
	farming.pick(well_cell)
	await _shot("watering-well-key")
	report.well_key = [farming._key.verb, farming._key.cost]
	farming.pick(row[3])
	await _shot("watering-dry-key")
	report.dry_key = [farming._key.verb, farming._key.cost]
	farming.pick(row[0])
	await _shot("watering-wet-row")
	report.wet_key = [farming._key.verb, farming._key.cost]
	FileAccess.open(out.path_join("watering.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("WATERING_PROBE ", JSON.stringify(report))
	quit(0)

func _open(store: RefCounted) -> void:
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup({"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true, "farm_store": store})
	var ready := [false]
	scene.preview_ready.connect(func(_summary): ready[0] = true)
	scene.preview_error.connect(func(message):
		push_error(message)
		quit(1))
	root.add_child(scene)
	while not ready[0] or scene._farming.farm.is_empty(): await process_frame

func _shot(name: String) -> void:
	for i in 4: await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))

## `count` free core cells in a row along x nearest the well (off the path, obstacles and buildings), or [].
func _row(farming, well: Vector2i, count: int) -> Array:
	var data: Dictionary = scene._data
	var taken := ParcelFarm.building_cells(farming.farm)
	var obstacles: Dictionary = farming.obstacle_cells()
	var best: Array = []
	var best_d := INF
	for cell: Dictionary in data.cells:
		var row: Array = []
		for dx in count: row.append(Vector2i(cell.x + dx, cell.y))
		var ok := row.all(func(at: Vector2i) -> bool:
			return data.by_cell.has(at) and data.by_cell[at].zone == "core" and not farming._path.has(at) and not obstacles.has(at) \
				and not taken.has(at))
		var d := Vector2(row[0]).distance_to(Vector2(well))
		if ok and d >= 2.0 and d < best_d:
			best = row
			best_d = d
	return best
