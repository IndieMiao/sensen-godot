extends SceneTree
## C-186#82 review burst of the level-up card (M-12, C-185 MS-17): Scott's sheet at Lv1 → Lv2, Upgrade pressed, then
## every drawn frame until the card has settled, on the device stand-in save (no server, no map). Run it with
## `--fixed-fps 60` so each frame is 1/60 s of game time however slow the capture is. Not device evidence.
##   godot --path <project> --resolution 1080x2400 --fixed-fps 60 --script res://tools/dev/dynamic_farm/level_card_burst.gd -- <empty out dir>
## Writes f000.png… (540×1200), frames.json (per frame: the card's place, scale and alpha, the scrim's and the light's
## alpha) and sheet.png (the frames around the card's arrival, in reading order, listed in sheet.txt).
## Run with a display (or a virtual one); SENSEN_OFFLINE=1 keeps Net from signing in.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const PARCEL := "p-review"
const FRAMES := 120
const THUMB := Vector2i(216, 480)
const COLUMNS := 8

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var dir := out.path_join("save")
	DirAccess.make_dir_recursive_absolute(dir)
	var Town: GDScript = load("res://scenes/dynamic_farm/parcel_town.gd")
	var backdrop := ColorRect.new()
	backdrop.color = Color("E7F0DF")   # the map's occlusion colour, standing in for the map
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var store := LocalStore.new(PARCEL, dir)
	store._save(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {},
		"bag": {"wood": 16, "stone": 12}, "welcomed_at": 0, "coins": 400}), 1)
	var town: Control = Town.open(root, Town.CARPENTER, store, PARCEL, dir.path_join("met.json"))
	for i in 60: await process_frame
	town.keys.upgrade.activated.emit()
	for i in 60: await process_frame
	var sheet = town.upgrade_sheet
	sheet.button.activated.emit()
	var log := []
	var first := -1
	for i in FRAMES:
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.resize(540, 1200, Image.INTERPOLATE_BILINEAR)
		image.save_png(out.path_join("f%03d.png" % i))
		var row := {"frame": i, "ms": snappedf(i * 1000.0 / 60.0, 0.1), "card": false}
		var layer: Control = town.get_node_or_null(^"LevelUp")
		if layer != null:
			var card: Control = layer.get_node_or_null(^"LevelCard")
			var scrim: CanvasItem = layer.get_node_or_null(^"Scrim")
			var glow: CanvasItem = layer.get_node_or_null(^"Glow")
			row.card = card != null
			if card != null:
				if first < 0: first = i
				row.merge({"card_pos": [card.position.x, card.position.y], "card_size": [card.size.x, card.size.y],
					"card_scale": snappedf(card.scale.x, 0.001), "card_alpha": snappedf(card.modulate.a, 0.001)})
			if scrim != null: row.scrim_alpha = snappedf(scrim.modulate.a, 0.001)
			if glow != null: row.glow_alpha = snappedf(glow.modulate.a, 0.001)
		log.append(row)
	var f := FileAccess.open(out.path_join("frames.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "fixed_fps": Engine.physics_ticks_per_second,
		"first_card_frame": first, "frames": log}, "  "))
	f.close()
	# The sheet: two frames before the card joins, every frame for the next 14, then every third to the end.
	var picks := []
	if first >= 0:
		for i in range(maxi(first - 2, 0), mini(first + 14, FRAMES)): picks.append(i)
		for i in range(first + 14, FRAMES, 3): picks.append(i)
	var rows := ceili(picks.size() / float(COLUMNS))
	var sheet_image := Image.create(THUMB.x * COLUMNS, maxi(THUMB.y * rows, 1), false, Image.FORMAT_RGBA8)
	sheet_image.fill(Color.WHITE)
	var legend := PackedStringArray()
	for n in picks.size():
		var thumb := Image.load_from_file(out.path_join("f%03d.png" % picks[n]))
		thumb.convert(Image.FORMAT_RGBA8)
		thumb.resize(THUMB.x - 4, THUMB.y - 4, Image.INTERPOLATE_BILINEAR)
		sheet_image.blit_rect(thumb, Rect2i(Vector2i.ZERO, thumb.get_size()), Vector2i(n % COLUMNS * THUMB.x + 2, n / COLUMNS * THUMB.y + 2))
		var r: Dictionary = log[picks[n]]
		legend.append("cell %d (row %d col %d): frame %d, %.1f ms after Upgrade%s" % [n + 1, n / COLUMNS + 1, n % COLUMNS + 1,
			picks[n], r.ms, (", card at %s alpha %s, scrim %s" % [r.card_pos, r.card_alpha, r.get("scrim_alpha", "-")]) if r.card else ""])
	sheet_image.save_png(out.path_join("sheet.png"))
	FileAccess.open(out.path_join("sheet.txt"), FileAccess.WRITE).store_string("\n".join(legend) + "\n")
	print("LEVEL_CARD_BURST first_card_frame=%d frames=%d" % [first, FRAMES])
	quit(0)
