extends SceneTree
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
var scene
var finished := false
var frame_ms: Array[float] = []
var last_ms := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	var raw = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var packed := load(SCENE_PATH) as PackedScene
	scene = packed.instantiate()
	scene.setup({"farm":raw,"dataset":raw.dataset_version,"block_id":raw.block_id,"preview_only":true,
		"edge_decor_preview":args.has("--edge-decor"),"original_slope_material":args.has("--original-slope")})
	scene.preview_error.connect(func(message):
		push_error(message)
		finished=true
		quit(1))
	scene.preview_ready.connect(func(summary):
		print("PREVIEW_READY ",JSON.stringify(summary))
		_capture.call_deferred(args[1],summary))
	root.add_child(scene)
	await create_timer(40).timeout
	if not finished:
		push_error("Preview probe timed out")
		quit(1)

func _capture(folder: String, summary: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	summary.first_complete_draw_ms = Time.get_ticks_msec()-scene._started_ms
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var id: String = scene._data.block_id.replace("*","_star")
	var image := root.get_texture().get_image()
	image.save_png(folder.path_join(id+"-normal.png"))
	scene.set_review_overview(true)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id+"-overview.png"))
	scene.set_review_overview(false)
	last_ms=Time.get_ticks_usec()
	var sample_started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - sample_started < 8000:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now-last_ms)/1000.0)
		last_ms=now
	summary.frame_ms=frame_ms
	summary.sample_wall_ms=Time.get_ticks_msec()-sample_started
	summary.engine_fps=Engine.get_frames_per_second()
	summary.process_ms=Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
	summary.video_memory_bytes=Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	summary.renderer=RenderingServer.get_current_rendering_method()
	summary.viewport=str(root.size)
	summary.draw_calls=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	summary.render_objects=Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	summary.source="desktop, real-time idle samples after warm-up; not phone performance"
	var material_rows:Array=[]
	for node in scene._ground.get_children():
		if not node is MeshInstance3D or not node.material_override is ShaderMaterial:continue
		var material:ShaderMaterial=node.material_override
		var color:Color=material.get_shader_parameter("clearing_color")
		var original:Color=material.get_meta("original_clearing_color",color)
		var shade_rect:Vector4=material.get_shader_parameter("shade_rect") if material.get_shader_parameter("shade_rect") is Vector4 else Vector4.ZERO
		var mask=material.get_shader_parameter("shade_mask")
		material_rows.append({"mesh":node.name,"material_id":material.get_instance_id(),"shader_path":material.shader.resource_path,
			"clearing_color":[color.r,color.g,color.b,color.a],"original_clearing_color":[original.r,original.g,original.b,original.a],
			"linear_gain":material.get_meta("clearing_linear_gain",1.0),"shade_rect":[shade_rect.x,shade_rect.y,shade_rect.z,shade_rect.w],
			"shade_mask_id":mask.get_instance_id() if mask!=null else 0,"shade_opacity":material.get_shader_parameter("shade_opacity")})
	summary.ground_materials=material_rows
	var output := FileAccess.open(folder.path_join(id+"-metrics.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(summary,"\t"))
	var records: Array = []
	for item: Dictionary in scene._plan.layout:
		var at: Vector3 = item.transform.origin
		var basis: Basis = item.transform.basis
		var occupied: Array = []
		for cell: Vector2i in item.cells: occupied.append([cell.x,cell.y])
		records.append({"asset":item.asset,"role":item.role,"position":[at.x,at.y,at.z],
			"basis":[[basis.x.x,basis.x.y,basis.x.z],[basis.y.x,basis.y.y,basis.y.z],[basis.z.x,basis.z.y,basis.z.z]],
			"solid":item.solid,"shadow":item.shadow,"occupied_cells":occupied})
	var protected: Array = []
	for cell: Vector2i in scene._data.protected: protected.append([cell.x,cell.y])
	var blocked: Array = []
	for cell: Vector2i in scene._walk.reserved: blocked.append([cell.x,cell.y])
	var audit := FileAccess.open(folder.path_join(id+"-layout.json"),FileAccess.WRITE)
	audit.store_string(JSON.stringify({"dataset":scene._data.dataset_version,"block_id":id,
		"seed_hex":scene._data.seed_hex,"art_version":scene._plan.art_version,
		"layout_sha256":scene._plan.layout_sha256,"protected":protected,"placement_reservations":blocked,"instances":records},"\t"))
	if not scene._edge_plan.is_empty():
		var extra:Array=[]
		for item:Dictionary in scene._edge_plan.layout:
			var tr:Transform3D=item.transform
			var box:AABB=item.box
			var cells:Array=[]
			for cell:Vector2i in item.cells:cells.append([cell.x,cell.y])
			extra.append({"asset":item.asset,"position":[tr.origin.x,tr.origin.y,tr.origin.z],
				"basis":[[tr.basis.x.x,tr.basis.x.y,tr.basis.x.z],[tr.basis.y.x,tr.basis.y.y,tr.basis.y.z],[tr.basis.z.x,tr.basis.z.y,tr.basis.z.z]],
				"bounds":[[box.position.x,box.position.y,box.position.z],[box.end.x,box.end.y,box.end.z]],
				"cells":cells,"shadow":item.shadow,"solid":item.solid,"triangles":item.triangles})
		var clusters:Array=[]
		for cluster:Dictionary in scene._edge_plan.clusters:
			clusters.append({"ring":cluster.ring,"interval":[cluster.interval.x,cluster.interval.y],"instances":cluster.instances})
		var extra_file:=FileAccess.open(folder.path_join(id+"-edge-decor.json"),FileAccess.WRITE)
		extra_file.store_string(JSON.stringify({"layer":"edge_decor_v2","instances":extra,"clusters":clusters,
			"hash":scene._edge_plan.layout_sha256,"metrics":summary.edge_decor},"\t"))
	print("PROBE_COMPLETE ",id)
	finished=true
	scene.queue_free()
	await process_frame
	quit(0)
