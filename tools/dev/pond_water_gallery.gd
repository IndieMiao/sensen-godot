extends Node
## Isolated GPU inspection of the water material. No network or gameplay writes.
var root: Window
var _out := ""
var _movie := false

func _ready() -> void:
	root = get_tree().root
	ProjectSettings.set_setting("sensen/network/online_qa", true)
	_out = ProjectSettings.globalize_path("res://../water-gallery")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		if arg == "--motion": _movie = true
	DirAccess.make_dir_recursive_absolute(_out)
	call_deferred("_run")

func _run() -> void:
	TranslationServer.set_locale("zh_CN")
	root.size = Vector2i(390, 844)
	var report := []
	var shapes: Array = ["gourd"] if _movie else ["crescent", "gourd", "meander"]
	for shape in shapes:
		var entry: Dictionary = SystemPonds.data().locations.filter(func(p): return p.template_id == shape)[0]
		var scene := load(SystemPonds.SCENE).instantiate() as FishingPondScene
		scene.setup({"pond_id": entry.id, "session": null})
		root.add_child(scene)
		for frame in 60: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		assert(frame.save_png(_out.path_join(shape + "-default.png")) == OK)
		var water := scene.get_node(str(entry.id)) as FishingWater
		var reflection := water.get_node_or_null("PlanarBankReflection") as WaterReflection
		if reflection:
			assert(reflection._viewport.get_texture().get_image().save_png(_out.path_join(shape + "-reflection.png")) == OK)
		var measurements := []
		var points := []
		var view := root.get_visible_rect().size
		for y in range(4, 13):
			for x in range(2, 11):
				var p := Vector3(x + .17, 0.056, -y - .13)
				if not FishingModel.contains(str(entry.id), p, 0, scene.site_spec): continue
				var edge := FishingModel._nearest_polygon(Vector2(p.x, p.z), FishingModel._polygon(scene.site_spec))
				if Vector2(p.x, p.z).distance_to(edge) < .9: continue
				var screen := scene.cam.unproject_position(p)
				var pixel := Vector2i(roundi(screen.x / view.x * frame.get_width()), roundi(screen.y / view.y * frame.get_height()))
				if pixel.x < 0 or pixel.x >= frame.get_width() or pixel.y < 70 or pixel.y >= frame.get_height() - 110: continue
				var color := frame.get_pixelv(pixel)
				measurements.append([color.r, color.g, color.b])
				points.append([pixel.x, pixel.y])
		report.append({"template":shape,"rgb_samples":measurements,"sample_pixels":points,
			"flow_speed":RenderingServer.shader_get_parameter_default(water.water_material.shader.get_rid(), "flow_speed"),
			"ground_in_reflection":scene.get_node("Scenery/BankGround").get_layer_mask_value(3),
			"network_booted":Net.booted_once})
		if _movie:
			for frame_index in 150: await get_tree().process_frame
		root.remove_child(scene)
		scene.queue_free()
		for frame_index in 4: await get_tree().process_frame
	FileAccess.open(_out.path_join("measurements.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	get_tree().quit()
