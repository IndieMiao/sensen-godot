extends SceneTree
var farm: Node3D
func _initialize() -> void:
	ProjectSettings.set_setting("sensen/network/online_qa", true)
	create_timer(12).timeout.connect(func(): quit(1))
	call_deferred("_run")
func _run() -> void:
	TranslationServer.set_locale("zh_CN")
	DisplayServer.window_set_size(Vector2i(810, 1080))
	root.content_scale_size = Vector2i(360, 480)
	var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://output/water-material-2026-09-19/device/private/before-farm.json"))
	var session := FarmSession.new(null, "user://water-visual-journal")
	session._adopt(snapshot)
	var site := "farm_pond"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--site="): site = arg.trim_prefix("--site=")
	var street := site != "farm_pond"
	farm = (load("res://scenes/map/journey_street.tscn" if street else "res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	farm.setup({"session": session, "blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path(str(snapshot.layout_patch_id), int(snapshot.blueprint_revision)))})
	root.add_child(farm)
	farm.set_process(false)
	for node in farm.get_children():
		if node is CanvasLayer: node.hide()
	if farm.online: farm.online.hud.hide()
	var spec := FishingModel.site(site)
	var center: Array = spec.center if spec.has("center") else spec.path[1]
	var focus := Vector3(center[0], 0, center[1])
	farm.player.position = FishingModel.stand(site)
	farm.cam.position = focus + Vector3(2.5, 9, 7.75)
	farm.cam.look_at(focus + Vector3(0, 0, 0.4))
	farm.cam.size = 9.2 if site == "farm_pond" else 6.5
	farm.cam.v_offset = 0
	await create_timer(2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/water-detail-2026-09-19/native/" + site + "_" + RenderingServer.get_current_rendering_method() + ".png")
	var water := farm.find_child(site, true, false)
	var reflection := water.get_node_or_null("PlanarBankReflection") if water else null
	if reflection: reflection._viewport.get_texture().get_image().save_png("res://output/water-detail-2026-09-19/native/reflection.png")
	farm.queue_free()
	for frame in 5: await process_frame
	quit()
