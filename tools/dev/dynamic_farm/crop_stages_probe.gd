extends SceneTree
## Carrot stage and soil review (C-138) on C-34's local save, not the server: seven tilled cells in a row near the
## arrival, six of them sown so that each of the seven stages shows at once (tilled, sowing, emergence, leaf growth,
## root shoulders, root thickening, maturity), captured with dry soil and with the development wet-soil switch.
##   godot --path "$QA" --script res://tools/dev/dynamic_farm/crop_stages_probe.gd -- <farm.json> <out> [<now_ms> <lead_s>]
## With <now_ms> (a device's clock) the save in <out>/save is written for that clock plus <lead_s> seconds, so the stages
## are in the middle of each other when a package opens it later (emulator QA, gather_qa_apk.sh); nothing is captured.
## Scripted; not touch or device evidence. <out>/save is cleared first. With --headless: states only.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const CropArt = preload("res://modules/dynamic_farm/parcel_crop_art.gd")
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
	var now := int(args[2]) + int(args[3]) * 1000 if args.size() >= 4 else int(Time.get_unix_time_from_system() * 1000.0)
	var save_dir := out.path_join("save")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for name in DirAccess.get_files_at(save_dir): DirAccess.remove_absolute(save_dir.path_join(name))
	create_timer(90).timeout.connect(func():
		push_error("Crop stages probe timed out")
		quit(1))
	var clock := [now]
	var store := LocalStore.new(raw.block_id, save_dir)
	store.now_ms = func() -> int: return clock[0]
	await _open(store)
	var farming = scene._farming
	var row := _row(farming, CropArt.STAGES.size())
	if row.is_empty():
		push_error("No free row of seven core cells")
		quit(1)
		return
	var version: int = farming.farm_version
	for cell: Vector2i in row:
		version = store.send(version, [{"type": "till", "cell": ParcelFarm.key(cell)}]).farm_version
	# Enough seeds for six carrots; the save is a review fixture.
	var saved = JSON.parse_string(FileAccess.get_file_as_string(save_dir.path_join(raw.block_id.validate_filename() + ".json")))
	saved.farm.bag.seed_carrot = 6
	FileAccess.open(save_dir.path_join(raw.block_id.validate_filename() + ".json"), FileAccess.WRITE).store_string(JSON.stringify(saved))
	var grow := int(ParcelFarm.rules().crops.crop_carrot.grow_seconds) * 1000
	for stage in range(1, CropArt.STAGES.size()):
		# Planted so that `now` is in the middle of the stage (maturity: just ripe).
		var planted := now - grow - 1000 if stage == CropArt.MATURE else now - ((stage - 1) * 2 + 1) * grow / 10
		clock[0] = planted
		version = store.send(version, [{"type": "sow", "cell": ParcelFarm.key(row[stage]), "crop": "crop_carrot"}]).farm_version
	clock[0] = now
	scene.queue_free()
	await process_frame
	var report := {"row": row.map(func(c): return [c.x, c.y]), "save": save_dir}
	if args.size() >= 4:
		print("CROP_STAGES_SAVE ", JSON.stringify(report))
		quit(0)
		return
	await _open(store)
	farming = scene._farming
	var middle: Vector2i = row[3]
	scene._focus = scene._walk.point(middle)
	scene._place_camera()
	farming._draw_crops()
	report.dry = farming._crop_art.counts()
	await _shot(raw.block_id + "-stages-dry")
	farming.wet_soil_preview = true
	farming._draw_crops()
	report.wet = farming._crop_art.counts()
	await _shot(raw.block_id + "-stages-wet")
	FileAccess.open(out.path_join(raw.block_id + "-stages.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CROP_STAGES_PROBE ", JSON.stringify(report))
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

## `count` free core cells in a row (x increasing), off the path, obstacles and house, nearest the arrival first. The
## player standing at the arrival hides about three cells behind it on screen, so the row keeps out of that.
func _row(farming, count: int) -> Array:
	var data: Dictionary = scene._data
	var house := ParcelFarm.house_cells(farming.farm)
	var obstacles: Dictionary = farming.obstacle_cells()
	var free := func(at: Vector2i) -> bool:
		return data.by_cell.has(at) and data.by_cell[at].zone == "core" and not farming._path.has(at) \
			and not obstacles.has(at) and not house.has(at)
	var best: Array = []
	var best_d := INF
	for cell: Dictionary in data.cells:
		var row: Array = []
		for i in count: row.append(Vector2i(cell.x + i, cell.y))
		var hidden: bool = cell.y >= data.spawn.y and cell.y <= data.spawn.y + 3 \
			and data.spawn.x >= cell.x - 1 and data.spawn.x <= cell.x + count
		if hidden or not row.all(free): continue
		var d: float = (row[count / 2] - data.spawn).length()
		if d < best_d:
			best_d = d
			best = row
	return best
