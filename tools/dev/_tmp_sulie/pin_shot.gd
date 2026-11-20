extends Node
## Temporary (苏烈, not committed): map destination pins side by side, to a PNG; silhouettes, children listed.
func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(OS.get_environment("BG") if OS.get_environment("BG") != "" else "dfe8d6")
	bg.size = Vector2(360, 160)
	add_child(bg)
	var x := 30.0
	for spec in [["mine_hut", "Golden", false], ["mine_hut", "Golden", true], ["travel", "Bridge", true], ["pot", "Oak", true]]:
		var pin := UiMapDestination.new(P0Logic.icon(spec[0]), spec[1])
		pin.theme = UiKit.theme()
		add_child(pin)
		pin.silhouette = spec[2]
		pin.position = Vector2(x, 50)
		x += 80.0
		if spec[2] and spec[0] == "mine_hut":
			await get_tree().process_frame
			for c in pin.find_children("*", "CanvasItem", true, false):
				var ci := c as CanvasItem
				if ci.is_visible_in_tree():
					print("CHILD ", c.get_path(), " ", c.get_class(), " ", (c as Control).get_global_rect() if c is Control else "")
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
	get_tree().quit()
