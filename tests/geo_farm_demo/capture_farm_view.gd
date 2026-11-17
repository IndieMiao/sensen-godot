extends SceneTree
## Isolated QA capture only; arguments are real generated JSON paths and output dir.
const Farm = preload("res://scenes/geo_farm_demo/farm_view.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	root.size = Vector2i(720, 1280)
	root.content_scale_size = Vector2i(360, 640)
	var view = Farm.instantiate()
	root.add_child(view)
	for i in range(1, args.size()):
		if not view.load_block_file(args[i]):
			push_error("Could not load capture input")
			quit(1)
			return
		for frame in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := args[0].path_join("farm-" + args[i].get_file().get_basename() + ".png")
		var result := image.save_png(path)
		print("CAPTURE ", path.get_file(), " result=", result, " size=", image.get_size())
		if result != OK:
			quit(1)
			return
	# Show smallest supported portrait with the same real farm.
	root.size = Vector2i(320, 568)
	root.content_scale_size = Vector2i(320, 568)
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var small := root.get_texture().get_image()
	print("CAPTURE farm-small.png result=", small.save_png(args[0].path_join("farm-small.png")))
	view.queue_free()
	await process_frame
	quit(0)
