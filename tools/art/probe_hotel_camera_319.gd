extends SceneTree
## Run against the farm-dev checkout: capture native P0Room framing only, no gameplay changes.
var vp: SubViewport
var room
var runtime

func _initialize(): run.call_deferred()
func run():
	var args = OS.get_cmdline_user_args()
	assert(args.size() == 1)
	vp = SubViewport.new()
	vp.size = Vector2i(360, 800)
	vp.own_world_3d = true
	root.add_child(vp)
	runtime = load("res://modules/p0/p0_runtime.gd").new()
	runtime.session.transport = func(_method, _path, _body, _meta): pass
	vp.add_child(runtime)
	runtime.set_process(false)
	runtime.session.set_process(false)
	room = load("res://scenes/p0/rooms/p0_room.gd").new()
	room.use_runtime = false
	room.use_art("poi_hotel_lobby")
	vp.add_child(room)
	room.rt = runtime
	runtime.attach(room)
	for i in 12: await process_frame
	room.actor.visible = false
	room.frame_all()
	var transform: Transform3D = room.cam.global_transform
	transform.origin -= room.room.global_position
	var at: Vector3 = room.actor.position - room.room.position
	var spawn = room.anchor("spawn")
	assert(spawn != null)
	var requested: Vector3 = spawn.global_position - room.room.global_position
	assert(absf(room.cam.size - 6.72) < .001)
	assert(absf(room.cam.rotation_degrees.x + 43) < .001)
	var report = {"source": "Unmodified farm-dev P0Room.frame_all with native P0Ui bag-only layout",
		"layout_sha256": FileAccess.get_sha256("res://assets/rooms/poi_hotel_lobby/layout.json"),
		"viewport": [360, 800], "width_m": room.cam.size, "pitch": room.cam.rotation_degrees.x,
		"basis": [[transform.basis.x.x, transform.basis.x.y, transform.basis.x.z], [transform.basis.y.x, transform.basis.y.y, transform.basis.y.z], [transform.basis.z.x, transform.basis.z.y, transform.basis.z.z]],
		"origin": [transform.origin.x, transform.origin.y, transform.origin.z],
		"actual_actor_room_position": [at.x, at.y, at.z], "requested_spawn": [requested.x, requested.y, requested.z],
		"spawn_snap_distance_m": at.distance_to(requested), "bag_only": runtime.ui.bag_only(),
		"native_near": room.cam.near, "native_far": room.cam.far,
		"render_clip_note": "Framing retained exactly. Art review uses near=.1/far=40 for single-map daylight shadow precision; P2 integration must consume the art clip recommendation.",
		"anchor_visibility": {}}
	for a in room.layout.anchors:
		report.anchor_visibility[a.name] = room.anchor(a.name) != null
	assert(report.spawn_snap_distance_m < .12)
	assert(report.anchor_visibility.values().all(func(v): return v))
	report.hotel_identity_screen_bounds = {}
	var safe_band := Rect2(8, 100, 344, 610)
	for name_ in ["elevator", "wall_clock", "wall_clock_2", "wall_clock_3", "key_rack", "blank_name_plaque"]:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for mesh in room.art.get_node(name_).find_children("*", "MeshInstance3D", true, false):
			for i in 8:
				var pixel: Vector2 = room.cam.unproject_position(mesh.to_global(mesh.get_aabb().get_endpoint(i)))
				lo = lo.min(pixel)
				hi = hi.max(pixel)
		var bounds := Rect2(lo, hi - lo)
		report.hotel_identity_screen_bounds[name_] = {"rect": [lo.x, lo.y, bounds.size.x, bounds.size.y], "inside_safe_band": safe_band.encloses(bounds)}
	report.opening_passed = report.hotel_identity_screen_bounds.values().all(func(v): return v.inside_safe_band)
	FileAccess.open(args[0], FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("N1_NATIVE_CAMERA ", JSON.stringify(report))
	room.queue_free()
	runtime.queue_free()
	await process_frame
	quit(0 if report.opening_passed else 1)
