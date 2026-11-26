extends SceneTree
## C-108: lays captured PNGs side by side with a caption over each, and saves the sheet.
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/dev/c108_compare.gd -- <out.png> <title> \
##       <caption>=<png> [<caption>=<png> ...]
## Each picture is shown at 360 wide (half of a 720 capture); a missing file shows as an empty column.

const COL_W := 360
const GAP := 16

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var title: String = args[1]
	var cols := args.slice(2)
	var col_h := 640
	var w := GAP + cols.size() * (COL_W + GAP)
	var h := 56 + 28 + col_h + GAP
	root.size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w, h))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var bg := ColorRect.new()
	bg.color = Color("F6F5F0")
	bg.size = Vector2(w, h)
	root.add_child(bg)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override(&"font_size", 22)
	t.add_theme_color_override(&"font_color", Color("2B2A26"))
	t.position = Vector2(GAP, 12)
	bg.add_child(t)
	var x := GAP
	for c in cols:
		var parts: PackedStringArray = str(c).split("=", true, 1)
		var cap := Label.new()
		cap.text = parts[0]
		cap.add_theme_font_size_override(&"font_size", 15)
		cap.add_theme_color_override(&"font_color", Color("5E5C55"))
		cap.position = Vector2(x, 56)
		bg.add_child(cap)
		if parts.size() > 1 and FileAccess.file_exists(parts[1]):
			var img := Image.load_from_file(parts[1])
			var tex := TextureRect.new()
			tex.texture = ImageTexture.create_from_image(img)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			tex.position = Vector2(x, 84)
			tex.size = Vector2(COL_W, col_h)
			bg.add_child(tex)
		x += COL_W + GAP
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("SHEET ", out)
	quit()
