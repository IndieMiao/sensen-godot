extends SceneTree
## Renders the outpost NPCs (assets/p0/outpost_npcs.json) on the base rig for the art director (SGODOT-227): one
## cell per NPC with its portrait (when given), front and 3/4 views at its own scale, plus the default player for
## comparison. Needs a window (no --headless):
##   godot --path . --script res://tools/dev/npc_lineup.gd -- [--portraits=<dir of <npc>.png>] [--out=output/npc-lineup.png]
## A portrait is looked up as <dir>/<npc id without "res_">.png (ama.png, old_kai.png …); portraits are not in the repo.

const NPCS_PATH := "res://assets/p0/outpost_npcs.json"
const W := 300
const H := 420
const CAPTION := 36
var _portraits := ""
var _out := "output/npc-lineup.png"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--portraits="): _portraits = a.trim_prefix("--portraits=")
		elif a.begins_with("--out="): _out = a.trim_prefix("--out=")
	if DisplayServer.get_name() == "headless":
		printerr("needs a window: drop --headless")
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
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
	var npcs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NPCS_PATH)).get("npcs", {})
	var cast: Array = []
	for id in npcs: cast.append({"id": str(id), "def": npcs[id]})
	cast.append({"id": "player", "def": {"name": "Player (default outfit)", "scale": 1.0, "slots": {}}})
	var font := ThemeDB.fallback_font
	var cells: Array[Image] = []
	for entry in cast:
		var def: Dictionary = entry.def
		var slots: Dictionary = def.get("slots", {})
		var config: AvatarConfig = avatar.slot_table.default_config()   # what OnlineAppearance.config builds in the room
		for slot in slots:
			var part = avatar.catalog.part(str(slots[slot]))
			if part != null and part.slot == StringName(slot): config.slots[StringName(slot)] = str(slots[slot])
			else: printerr("%s: %s is not a %s part" % [entry.id, slots[slot], slot])
		rig.apply_config(config)
		rig.scale = Vector3.ONE * float(def.get("scale", 1.0))
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
		var portrait := _portrait(str(entry.id), views[0].get_format())
		var pw := portrait.get_width() if portrait else 0
		var cell := Image.create_empty(pw + W * 2, H + CAPTION, false, views[0].get_format())
		cell.fill(Color(0.97, 0.96, 0.93))
		if portrait: cell.blit_rect(portrait, Rect2i(Vector2i.ZERO, portrait.get_size()), Vector2i(0, CAPTION))
		cell.blit_rect(views[0], Rect2i(0, 0, W, H), Vector2i(pw, CAPTION))
		cell.blit_rect(views[1], Rect2i(0, 0, W, H), Vector2i(pw + W, CAPTION))
		var parts := ", ".join(slots.values()) if not slots.is_empty() else "hairhat0, cloth0, shoes0"
		var scale_note := "" if is_equal_approx(float(def.get("scale", 1.0)), 1.0) else " · scale %s" % def.scale
		cells.append(await _label(cell, "%s · %s%s" % [def.get("name", entry.id), parts, scale_note], font))
	var cols := 2
	var cw := 0
	for c in cells: cw = maxi(cw, c.get_width())
	var ch := cells[0].get_height()
	var rows := int(ceil(cells.size() / float(cols)))
	var sheet := Image.create_empty(cols * cw + (cols + 1) * 8, rows * ch + (rows + 1) * 8, false, cells[0].get_format())
	sheet.fill(Color(0.8, 0.79, 0.75))
	for i in cells.size():
		sheet.blit_rect(cells[i], Rect2i(Vector2i.ZERO, cells[i].get_size()), Vector2i(8 + (i % cols) * (cw + 8), 8 + (i / cols) * (ch + 8)))
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	if sheet.save_png(_out) != OK:
		printerr("could not write " + _out)
		quit(1)
		return
	print("rendered %s (%d cells)" % [_out, cells.size()])
	quit(0)

## The portrait scaled to the cell height, or null when there is none for this NPC.
func _portrait(id: String, format: Image.Format) -> Image:
	if _portraits == "": return null
	var path := _portraits.path_join(id.trim_prefix("res_") + ".png")
	if not FileAccess.file_exists(path): return null
	var img := Image.load_from_file(path)
	if img == null: return null
	img.convert(format)
	img.resize(int(round(img.get_width() * H / float(img.get_height()))), H, Image.INTERPOLATE_LANCZOS)
	return img

## Writes the caption into the top strip of a cell (CPU raster: a Label in its own SubViewport).
func _label(cell: Image, text: String, font: Font) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(cell.get_width(), CAPTION)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bg := ColorRect.new()
	bg.color = Color(0.97, 0.96, 0.93)
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.15, 0.17, 0.18))
	l.position = Vector2(12, 4)
	vp.add_child(l)
	root.add_child(vp)
	await RenderingServer.frame_post_draw
	var strip := vp.get_texture().get_image()
	strip.convert(cell.get_format())
	cell.blit_rect(strip, Rect2i(Vector2i.ZERO, strip.get_size()), Vector2i.ZERO)
	vp.queue_free()
	return cell
