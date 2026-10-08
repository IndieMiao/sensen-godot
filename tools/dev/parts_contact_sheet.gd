extends SceneTree
## Renders avatar parts on the base rig as a labelled contact sheet (the PNGs in assets/avatar/thumbs are grey
## placeholders): one cell per part, the default outfit with only that slot changed, front and 3/4 views.
## Used to pick NPC outfits (SGODOT-227) for the art director. Needs a window (no --headless):
##   godot --path . --script res://tools/dev/parts_contact_sheet.gd -- [--slots=hairHat,cloth] [--out=output/parts-sheet]
## Only catalogue parts are shown (the demo denylist is already applied), so every cell is assignable.

const W := 300
const H := 420
var _slots: PackedStringArray = ["hairHat", "cloth"]
var _out := "output/parts-sheet"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--slots="): _slots = a.trim_prefix("--slots=").split(",", false)
		elif a.begins_with("--out="): _out = a.trim_prefix("--out=")
	if DisplayServer.get_name() == "headless":
		printerr("needs a window: drop --headless")
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	var out_abs := ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out
	DirAccess.make_dir_recursive_absolute(out_abs)
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.87, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	vp.add_child(light)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	var avatar: Node = root.get_node("Avatar")   # autoload names are not identifiers in --script mode
	var rig: AvatarRig = avatar.create_rig()
	for c in rig.get_children():
		if c is RigActivity: c.free()
	rig.assembler = AvatarAssemblerMerged.new()
	vp.add_child(rig)
	var font := ThemeDB.fallback_font
	var failed := 0
	for slot in _slots:
		var ids: Array = avatar.catalog.parts_for_slot(StringName(slot)).map(func(m): return str(m.id))
		ids.sort()
		if ids.is_empty():
			printerr("no parts for slot " + slot)
			failed += 1
			continue
		var cells: Array[Image] = []
		for id in ids:
			var config: AvatarConfig = avatar.slot_table.default_config()
			config.slots[StringName(slot)] = id
			rig.apply_config(config)
			var waited := 0
			while rig.is_busy() and waited < 900:
				await process_frame
				waited += 1
			await process_frame
			rig.play_motion("idle")
			var views: Array[Image] = []
			for side in [Vector3(0.0, 1.0, 3.2), Vector3(1.9, 1.0, 2.6)]:
				cam.look_at_from_position(side, Vector3(0.0, 0.95, 0.0), Vector3.UP)
				vp.render_target_update_mode = SubViewport.UPDATE_ONCE
				await RenderingServer.frame_post_draw
				views.append(vp.get_texture().get_image())
			var cell := Image.create_empty(W * 2, H + 36, false, views[0].get_format())
			cell.fill(Color(0.97, 0.96, 0.93))
			cell.blit_rect(views[0], Rect2i(0, 0, W, H), Vector2i(0, 36))
			cell.blit_rect(views[1], Rect2i(0, 0, W, H), Vector2i(W, 36))
			cells.append(await _label(cell, "%s · %s" % [slot, id], font))
		var cols := 3
		var rows := int(ceil(cells.size() / float(cols)))
		var cw := cells[0].get_width()
		var ch := cells[0].get_height()
		var sheet := Image.create_empty(cols * cw + (cols + 1) * 8, rows * ch + (rows + 1) * 8, false, cells[0].get_format())
		sheet.fill(Color(0.8, 0.79, 0.75))
		for i in cells.size():
			sheet.blit_rect(cells[i], Rect2i(Vector2i.ZERO, cells[i].get_size()), Vector2i(8 + (i % cols) * (cw + 8), 8 + (i / cols) * (ch + 8)))
		var path := out_abs.path_join("%s.png" % slot)
		if sheet.save_png(path) != OK:
			failed += 1
			continue
		print("rendered %s (%d parts: %s)" % [path, ids.size(), ", ".join(ids)])
	quit(1 if failed > 0 else 0)

## Writes the caption into the top strip of a cell (CPU raster: a Label in its own SubViewport).
func _label(cell: Image, text: String, font: Font) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(cell.get_width(), 36)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bg := ColorRect.new()
	bg.color = Color(0.97, 0.96, 0.93)
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.15, 0.17, 0.18))
	l.position = Vector2(12, 3)
	vp.add_child(l)
	root.add_child(vp)
	await RenderingServer.frame_post_draw
	var strip := vp.get_texture().get_image()
	strip.convert(cell.get_format())
	cell.blit_rect(strip, Rect2i(Vector2i.ZERO, strip.get_size()), Vector2i.ZERO)
	vp.queue_free()
	return cell
