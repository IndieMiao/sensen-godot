extends SceneTree
## Actual Godot rendering with scripted GUI input; not a phone/performance recording.
const Farm = preload("res://scenes/geo_farm_demo/farm_view.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _save(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path.get_file(), " result=", result)

func _touch(grid, index: int, pressed: bool, position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	grid._gui_input(event)

func _drag(grid, index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	grid._gui_input(event)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		quit(1)
		return
	var motion := args.has("--motion")
	root.size = Vector2i(360, 640) if motion else Vector2i(720, 1280)
	root.content_scale_size = Vector2i(360, 640)
	var view = Farm.instantiate()
	root.add_child(view)
	if not motion:
		for path in args.slice(1):
			if not view.load_block_file(path):
				quit(1)
				return
			await _save(args[0].path_join(path.get_file().get_basename() + "-overview.png"))
			view._grid.zoom_at(2.5, view._grid.size * 0.5)
			await _save(args[0].path_join(path.get_file().get_basename() + "-detail.png"))
		root.size = Vector2i(320, 568)
		root.content_scale_size = Vector2i(320, 568)
		view._grid.fit()
		await _save(args[0].path_join("parcel-small.png"))
	else:
		if not view.load_block_file(args[1]):
			quit(1)
			return
		for i in 4:
			await process_frame
		var grid = view._grid
		var center: Vector2 = grid.size * 0.5
		for frame in 96:
			if frame == 12:
				_touch(grid, 0, true, center - Vector2(20, 0))
				_touch(grid, 1, true, center + Vector2(20, 0))
			if frame > 12 and frame <= 32:
				_drag(grid, 1, center + Vector2(20 + (frame - 12) * 3, 0))
			if frame == 33:
				_touch(grid, 1, false, center + Vector2(80, 0))
			if frame > 36 and frame <= 52:
				_drag(grid, 0, center - Vector2(20, (frame - 36) * 4))
			if frame == 53:
				_touch(grid, 0, false, center - Vector2(20, 64))
			if frame == 66:
				view._fit.pressed.emit()
			if frame == 80:
				view.load_block_file(args[2])
			await process_frame
	view.queue_free()
	await process_frame
	quit(0)
