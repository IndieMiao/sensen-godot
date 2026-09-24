extends Node
## Native rendering and real scene instances; no network or command mutations.
func _ready() -> void:
	assert(bool(ProjectSettings.get_setting("sensen/network/online_qa", false)))
	_run.call_deferred()

func _run() -> void:
	Localization.select_language("zh_CN")
	var destination := ProjectSettings.globalize_path("res://../gallery")
	DirAccess.make_dir_recursive_absolute(destination)
	var report := []
	for size in [Vector2i(390,844), Vector2i(360,640), Vector2i(480,640)]:
		get_window().size = size
		for shape in SystemPonds.TITLES:
			var location: Dictionary = SystemPonds.data().locations.filter(func(p): return p.template_id == shape)[0]
			var scene := load(SystemPonds.SCENE).instantiate() as FishingPondScene
			scene.setup({"pond_id": location.id, "session": null})
			get_tree().root.add_child(scene)
			for frame in 60: await get_tree().process_frame
			var stem := "%s-%dx%d" % [shape,size.x,size.y]
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(destination.path_join(stem + "-default.png"))
			var initial := scene.mover.position
			var plan := FishingModel.plan(str(location.id), initial, Vector3.INF, scene.mover.grid, scene.site_spec)
			assert(not plan.is_empty())
			assert(scene.mover.set_target_position(plan.origin))
			for frame in 180: await get_tree().process_frame
			assert(scene.mover.position.distance_to(plan.origin) < .05)
			scene.toggle_overview()
			for frame in 12: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(destination.path_join(stem + "-overview.png"))
			report.append({"template":shape,"window":[size.x,size.y],"reachable_shore":true,"water_mesh":scene.get_node(str(location.id)).get_node("FishingWaterSurface").mesh.get_surface_count(),"network_booted":Net.booted_once})
			get_tree().root.remove_child(scene)
			scene.queue_free()
			for frame in 4: await get_tree().process_frame
	FileAccess.open(destination.path_join("validation.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	get_tree().quit()
