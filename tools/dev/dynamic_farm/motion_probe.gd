extends SceneTree
## Fixed-step normal-speed art review. Scripted joystick input, not device touch/performance evidence.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
var scene
var complete := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var raw = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var packed := load(SCENE_PATH) as PackedScene
	scene = packed.instantiate()
	scene.setup({"farm":raw,"dataset":raw.dataset_version,"block_id":raw.block_id,"preview_only":true})
	scene.preview_error.connect(func(message):
		push_error(message)
		quit(1))
	scene.preview_ready.connect(func(_summary): _walk.call_deferred(args[1]))
	root.add_child(scene)
	await create_timer(60).timeout
	if not complete: quit(1)

func _walk(output: String) -> void:
	var data: Dictionary = scene._data
	var queue: Array[Vector2i] = [data.spawn]
	var previous := {data.spawn:data.spawn}
	var index := 0
	while index < queue.size() and not previous.has(data.entry):
		var at := queue[index]
		index += 1
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = at+offset
			if data.protected.has(next) and not previous.has(next):
				previous[next]=at
				queue.append(next)
	if not previous.has(data.entry):
		push_error("No protected review route")
		quit(1)
		return
	var route: Array[Vector2i] = [data.entry]
	while route[-1] != data.spawn: route.append(previous[route[-1]])
	route.reverse()
	var route_index := 1
	var frames := 0
	var positions: Array = []
	var started := Engine.get_frames_drawn()
	while frames < 540:
		if frames < 30 or route_index >= route.size():
			scene._controls.movement_changed.emit(Vector2.ZERO)
		else:
			var target: Vector3 = scene._walk.point(route[route_index])
			var delta: Vector3 = target-scene._actor.position
			if delta.length() < 0.12:
				route_index += 1
			else:
				var right: Vector3 = scene._camera.global_basis.x
				var forward: Vector3 = -scene._camera.global_basis.z
				right.y=0
				forward.y=0
				var direction := delta.normalized()*minf(delta.length()/0.3,1.0)
				scene._controls.movement_changed.emit(Vector2(direction.dot(right.normalized()),-direction.dot(forward.normalized())))
		if frames % 15 == 0:
			var p: Vector3 = scene._actor.position
			positions.append([frames,p.x,p.y,p.z,scene._walk.clear_position(p)])
		frames += 1
		await process_frame
	scene._controls.movement_changed.emit(Vector2.ZERO)
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"block_id":data.block_id,"start_frame":started,"frames":frames,
		"route_cells":route.size(),"reached_entry":route_index>=route.size(),"positions":positions,
		"evidence":"Godot Movie Maker fixed 30 FPS; normal 3.75m/s control; scripted inputs, not real-time/device performance"},"\t"))
	print("MOTION_COMPLETE ",data.block_id," reached=",route_index>=route.size())
	complete=true
	scene.queue_free()
	await process_frame
	quit(0 if route_index>=route.size() else 1)
