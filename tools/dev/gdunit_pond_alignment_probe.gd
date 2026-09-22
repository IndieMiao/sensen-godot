extends SceneTree
## Read-only saved-terrain render in the isolated gallery project. Never sends commands.

var farm: Node3D
var output := ""
var label := "before"

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	assert(not output.is_empty())
	create_timer(35).timeout.connect(func(): quit(2))
	call_deferred("_run")

func _run() -> void:
	var snapshot := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--snapshot="): snapshot = argument.trim_prefix("--snapshot=")
	assert(not snapshot.is_empty())
	var dto: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(snapshot))
	var session := FarmSession.new(null, "user://pond-alignment-journal")
	session._adopt(dto)
	var net := root.get_node("Net")
	net.session = session
	net.online_available = false
	net.booted_once = true
	TranslationServer.set_locale("zh_CN")
	DisplayServer.window_set_size(Vector2i(900, 720))
	root.content_scale_size = Vector2i(900, 720)
	farm = load("res://scenes/farm/farm.tscn").instantiate()
	farm.setup({"session": session})
	root.add_child(farm)
	farm.set_process(false)
	if farm.online: farm.online.stop()
	for node in farm.get_children():
		if node is CanvasLayer: node.hide()
	if farm.online: farm.online.hud.hide()
	var spec: Dictionary = farm.fishing_site
	var focus := Vector3(spec.center[0], 0, spec.center[1])
	farm.player.position = FishingModel.stand("farm_pond", spec)
	DirAccess.make_dir_recursive_absolute(output)
	for view in ["overhead", "east"]:
		farm.cam.position = focus + (Vector3(0, 12, 0.001) if view == "overhead" else Vector3(6.5, 10, 6.0))
		farm.cam.look_at(focus)
		farm.cam.size = 10.5
		farm.cam.v_offset = 0
		farm.cam.h_offset = 0
		await create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(label + "-" + view + ".png"))
		print("POND_ALIGNMENT_CAPTURE ", label, " ", view)
	var water: FishingWater = farm.get_node("farm_pond")
	FileAccess.open(output.path_join(label + "-geometry.json"), FileAccess.WRITE).store_string(JSON.stringify({
		"center": spec.center, "radii": spec.radii, "surface_aabb": str(water.get_node("FishingWaterSurface").mesh.get_aabb()),
		"bank_aabb": str(water.get_node("NaturalWaterBank/BankStones").mesh.get_aabb()),
		"basin": str(water.water_material.get_shader_parameter("basin")), "state_unchanged": session.state == dto.state}, "\t"))
	farm.queue_free()
	for frame in 6: await process_frame
	quit()
