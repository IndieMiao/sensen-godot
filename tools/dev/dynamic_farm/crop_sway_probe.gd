extends SceneTree
## Crop sway review captures (C-141) on a local save planted full of carrots, in the real farm scene:
##   plain   the plant layers on the imported StandardMaterial3D (what C-139 drew)
##   off     the sway material with sway off: must read the same as plain (colour parity)
##   sway-{all,young,ripe}-{a,b}  sway on, no shakes, two clocks half a sway period apart, with every plant stage,
##           only the young stages (west of the focus column) or only the mature one: young carrots must not move
##   shake   one young and one ripe carrot shaken, at the shake's first peak (0.11 s), against shake-none
## Frame differences go to <out>/crop-sway.json, difference images (×4) to <out>/*-diff.png.
##   godot --path "$QA" [--rendering-method mobile|gl_compatibility] --script res://tools/dev/dynamic_farm/crop_sway_probe.gd -- <farm.json> <out>
## Scripted desktop renders, not touch, device or frame-rate evidence (crop_sway_qa.tscn on the emulator is).
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const CropArt = preload("res://modules/dynamic_farm/parcel_crop_art.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
var scene
var raw: Dictionary
var out := ""
var shots := {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	raw = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	out = args[1]
	DirAccess.make_dir_recursive_absolute(out)
	create_timer(120).timeout.connect(func():
		push_error("Crop sway probe timed out")
		quit(1))
	var save_dir := out.path_join("save")
	DirAccess.make_dir_recursive_absolute(save_dir)
	var data := Data.decode(raw)
	var walk := Walk.new(data)
	var focus: Vector2i = data.spawn + Vector2i(0, 4)
	var planted := _plant(data, walk, save_dir, focus)
	var store := LocalStore.new(raw.block_id, save_dir)
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup({"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true, "farm_store": store})
	var ready := [false]
	scene.preview_ready.connect(func(_summary): ready[0] = true)
	scene.preview_error.connect(func(message):
		push_error(message)
		quit(1))
	root.add_child(scene)
	while not ready[0] or scene._farming.farm.is_empty(): await process_frame
	var farming = scene._farming
	var art = farming._crop_art
	# The probe drives the clock itself: the scene's own update would advance it every frame.
	farming.sway = false
	scene._actor.visible = false
	scene._zoom = 0.6
	scene._focus = scene._walk.point(focus)
	scene._place_camera()
	farming._draw_crops()
	# Let the camera ease in and the entry's gain floats finish before anything is compared.
	await create_timer(4.0).timeout
	var report := {"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(),
		"carrots": planted, "stages": art.counts().stages}
	# Plain: the imported material, as before C-141; twice, for the frame-to-frame noise floor.
	var sway_mats := []
	for layer in art._stages:
		sway_mats.append(null if layer == null else layer.material_override)
		if layer != null: layer.material_override = null
	await _shot("plain")
	await _shot("plain-again")
	for i in art._stages.size():
		if art._stages[i] != null: art._stages[i].material_override = sway_mats[i]
	art.set_sway(false)
	art.set_clock(10.0)
	await _shot("off")
	# Ripe sway: two clocks half a period apart, with every stage, only the young stages, only the mature one.
	art.set_sway(true)
	for only in ["all", "young", "ripe"]:
		for stage in range(1, art._stages.size()):
			art._stages[stage].visible = only == "all" or (only == "ripe") == (stage == CropArt.MATURE)
		art.set_clock(10.0)
		await _shot("sway-%s-a" % only)
		art.set_clock(10.0 + 1.3)
		await _shot("sway-%s-b" % only)
	for stage in range(1, art._stages.size()): art._stages[stage].visible = true
	# Shake: a young carrot at root shoulders (stage 4: rows with y % 4 == 3) west of the focus column and a ripe one
	# east of it, pushed east, at the shake's first peak; against the same clock without shakes.
	var young := focus + Vector2i(-2, 3 - posmod(focus.y, 4))
	var ripe := focus + Vector2i(2, 0)
	var amp: Array = farming.get_script().SWAY_STAGE_AMP
	art.set_clock(10.0)
	art.shake(young, Vector2(1, 0) * float(amp[CropArt.stage_of(farming.farm.crops[ParcelFarm.key(young)], farming.server_now())]))
	art.shake(ripe, Vector2(1, 0) * float(amp[CropArt.stage_of(farming.farm.crops[ParcelFarm.key(ripe)], farming.server_now())]))
	art.set_clock(10.11)
	await _shot("shake")
	art.set_sway(false)
	art.set_sway(true)
	art.set_clock(10.11)
	await _shot("shake-none")
	if DisplayServer.get_name() != "headless":
		report.noise = _diff("plain", "plain-again")
		report.parity = _diff("plain", "off")
		for only in ["all", "young", "ripe"]: report["sway_" + only] = _diff("sway-%s-a" % only, "sway-%s-b" % only)
		report.shake = _diff("shake-none", "shake")
		report.shaken = {"young": ParcelFarm.key(young), "ripe": ParcelFarm.key(ripe)}
	FileAccess.open(out.path_join("crop-sway.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CROP_SWAY_PROBE ", JSON.stringify(report))
	quit(0)

## Every core cell off the protected path and the cleared obstacles holds a carrot; west of the focus column they are
## young (stages 2..5 by row), the rest ripe.
func _plant(data: Dictionary, walk: RefCounted, save_dir: String, focus: Vector2i) -> Dictionary:
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var state := ParcelFarm.empty_state()
	state.welcomed_at = now
	var plan := Scenery.plan(data, walk)
	if plan.ok:
		for item: Dictionary in plan.core_obstacles.layout: state.cleared.append(ParcelFarm.key(item.cell))
	var path := Space.protected_path(data)
	var hour := 3600 * 1000
	var count := {"ripe": 0, "young": 0}
	for c: Dictionary in data.cells:
		var cell := Vector2i(c.x, c.y)
		if c.zone != "core" or path.has(cell): continue
		var key := ParcelFarm.key(cell)
		state.tilled.append(key)
		if cell.x < focus.x:
			# Stage 2..5: a fifth of the growing time each (ParcelCropArt.stage_of).
			var share := 0.1 + 0.2 * float(posmod(cell.y, 4)) + 0.05
			state.crops[key] = {"crop": "crop_carrot", "planted_at": now - int(share * hour), "ripe_at": now + int((1.0 - share) * hour)}
			count.young += 1
		else:
			state.crops[key] = {"crop": "crop_carrot", "planted_at": now - 120000, "ripe_at": now - 60000}
			count.ripe += 1
	var file := FileAccess.open(save_dir.path_join(str(data.block_id).validate_filename() + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"block_id": data.block_id, "farm_version": 1, "farm": state}))
	file.close()
	return count

func _shot(name: String) -> void:
	for i in 3: await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	shots[name] = image
	image.save_png(out.path_join(name + ".png"))

## Mean absolute RGB difference (0..255) over the frame, its peak and the pixels changed by more than 2/255; the
## difference image (×4) is saved as `<a>-<b>-diff.png`.
func _diff(a: String, b: String) -> Dictionary:
	var ia: Image = shots[a]
	var ib: Image = shots[b]
	var size := ia.get_size()
	var diff := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	var total := 0.0
	var changed := 0
	var peak := 0.0
	for y in size.y:
		for x in size.x:
			var ca := ia.get_pixel(x, y)
			var cb := ib.get_pixel(x, y)
			var d := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			total += d
			if d * 255.0 > 2.0: changed += 1
			peak = maxf(peak, d * 255.0)
			diff.set_pixel(x, y, Color(minf(d * 4.0, 1.0), minf(d * 4.0, 1.0), minf(d * 4.0, 1.0)))
	diff.save_png(out.path_join("%s-%s-diff.png" % [a, b]))
	return {"frame_mean": snappedf(total / (size.x * size.y) * 255.0, 0.0001), "changed_px": changed, "peak": snappedf(peak, 0.01)}
