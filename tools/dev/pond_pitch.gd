extends Node
## Captures the actual runtime scenery with identical camera/time on each GPU.
## Offline presentation fixture; it never requests or awards a catch.
var scene: FishingPondScene
var presentation: FishingPresentation
var _time := 12.0
var _fixed := true
var _output := "user://pond-art"
var _capture := false
var _shape := "gourd"
var _shot := "hero"
var _probe := ""
var _materials: Array[ShaderMaterial] = []
var _water_hash := ""
var _ready_to_measure := false
var _sample_elapsed := 0.0
var _samples := []
var _request_id := "initial"
var _command_age := 0.0
var _loading := true
var _warmup := 0.0
var _pan := preload("res://modules/farm/scene_pan.gd").new()
var _view_center := Vector3(6,0,-8)
var _view_width := 14.6

func _ready() -> void:
	assert(bool(ProjectSettings.get_setting("sensen/network/online_qa", false)))
	Engine.max_fps = 60
	_pan.free_pan = true
	if FileAccess.file_exists("user://art-shot.json"):
		var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://art-shot.json"))
		_shape = config.get("shape", _shape)
		_shot = config.get("shot", _shot)
		_time = config.get("time", _time)
		_fixed = not config.get("motion", false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _output = arg.trim_prefix("--out=")
		if arg.begins_with("--shape="): _shape = arg.trim_prefix("--shape=")
		if arg.begins_with("--shot="): _shot = arg.trim_prefix("--shot=")
		if arg.begins_with("--probe="): _probe = arg.trim_prefix("--probe=")
		if arg.begins_with("--time="): _time = float(arg.trim_prefix("--time="))
		if arg == "--capture": _capture = true
		if arg == "--motion": _fixed = false
	_run.call_deferred()

func _process(delta: float) -> void:
	if not _fixed: _time += delta
	if not _loading and is_instance_valid(scene):
		_pan.step(delta, scene.cam)
		_apply_camera()
	for material in _materials: material.set_shader_parameter("art_time", _time)
	if is_instance_valid(presentation):
		presentation._clock = _time
		presentation.step(0)
	if _ready_to_measure and _samples.size() < 24:
		_warmup += delta
		if _warmup < 4.0: return
		_sample_elapsed += delta
		if _sample_elapsed >= .5:
			_sample_elapsed = 0
			_samples.append({"fps": Engine.get_frames_per_second(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
			if _samples.size() == 24:
				FileAccess.open(_output.path_join("performance.json"), FileAccess.WRITE).store_string(JSON.stringify({"request_id":_request_id,"warmup_seconds":4,"samples":_samples},"\t"))
				print("POND_ART_PERFORMANCE ", JSON.stringify(_samples))
	_command_age += delta
	if not _loading and _command_age > .25:
		_command_age = 0
		if FileAccess.file_exists("user://art-command.json"):
			var command: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://art-command.json"))
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://art-command.json"))
			_loading = true
			_shape = command.get("shape", _shape)
			_shot = command.get("shot", _shot)
			_probe = command.get("probe", "")
			_time = command.get("time", 12.0)
			_fixed = not command.get("motion", false)
			_request_id = command.get("request_id", "command")
			_reload.call_deferred()

func _reload() -> void:
	_ready_to_measure = false
	_materials.clear()
	_samples.clear()
	_warmup = 0
	_sample_elapsed = 0
	_pan.reset()
	if is_instance_valid(presentation): presentation.finish()
	presentation = null
	if is_instance_valid(scene):
		remove_child(scene)
		scene.queue_free()
	await get_tree().process_frame
	_run()

func _run() -> void:
	if OS.has_feature("android"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT if _shot == "portrait" else DisplayServer.SCREEN_LANDSCAPE)
	var entry: Dictionary = SystemPonds.data().locations.filter(func(p): return p.template_id == _shape)[0]
	scene = load(SystemPonds.SCENE).instantiate()
	scene.setup({"pond_id": entry.id, "session": null})
	add_child(scene)
	for frame in 90: await get_tree().process_frame
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.canvas.hide()
	scene.mover.stop()
	var sun := scene.get_node("PondSun") as DirectionalLight3D
	var water := scene.get_node(str(entry.id)) as FishingWater
	if _probe == "sun-off": sun.light_specular = 0.0
	if _probe == "env-off": scene.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	if _probe == "flat": water.water_material.set_shader_parameter("wave_strength", 0.0)
	if _probe == "env-rotate": scene.environment.sky_rotation.y = PI * .5
	if _probe == "sun-rotate":
		sun.rotation_degrees.y += 60.0
		water.water_material.set_shader_parameter("sun_direction", sun.global_basis.z.normalized())
	_water_hash = FileAccess.get_sha256(scene.get_node(str(entry.id)).water_material.shader.resource_path)
	for node in scene.find_children("*", "GeometryInstance3D", true, false):
		if node.material_override is ShaderMaterial:
			var material: ShaderMaterial = node.material_override
			if material in _materials or not material.shader.code.contains("TIME"): continue
			var controlled := Shader.new()
			controlled.code = material.shader.code.replace("TIME", "art_time").replace("shader_type spatial;", "shader_type spatial;\nuniform float art_time = 12.0;")
			material.shader = controlled
			_materials.append(material)
	var target := Vector3(6.7, 0, -6.9)
	var plan := FishingModel.plan(str(entry.id), Vector3(9, 0, -3.5), target, scene.mover.grid, scene.site_spec)
	if not plan.is_empty():
		scene.player.position = plan.origin
		var animation := scene._rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if animation: animation.seek(0, true)
		presentation = FishingPresentation.new()
		scene.add_child(presentation)
		presentation.configure_remote({"target":[plan.target.x,plan.target.z],"phase":"waiting"}, scene.player, scene._rig, scene.cam)
		presentation.set_process(false)
		presentation._water = scene.get_node(str(entry.id))
	frame_camera()
	for frame in 20: await get_tree().process_frame
	assert(not Net.booted_once)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	assert(screenshot.save_png(_output.path_join(_shape + "-" + _shot + ".png")) == OK)
	var report := {
		"request_id": _request_id,
		"shape": _shape, "shot": _shot, "shader_time": _time, "engine": Engine.get_version_info().string,
		"probe": _probe, "sun_specular": sun.light_specular,
		"wave_strength": _shader_uniform(water.water_material, &"wave_strength"),
		"normal_strength": _shader_uniform(water.water_material, &"normal_strength"),
		"caustic_depth_falloff": _shader_uniform(water.water_material, &"caustic_depth_falloff"),
		"surface_roughness": _shader_uniform(water.water_material, &"surface_roughness"),
		"film_cutoff": _shader_uniform(water.water_material, &"film_cutoff"),
		"film_contrast": _shader_uniform(water.water_material, &"film_contrast"),
		"sparkle_cutoff": _shader_uniform(water.water_material, &"sparkle_cutoff"),
		"shimmer_strength": _shader_uniform(water.water_material, &"shimmer_strength"),
		"sun_direction": str(sun.global_basis.z.normalized()),
		"sun_angular_distance": sun.light_angular_distance,
		"environment_reflection_source": scene.environment.reflected_light_source,
		"environment_rotation": str(scene.environment.sky_rotation),
		"environment_energy": (scene.environment.sky.sky_material as PanoramaSkyMaterial).energy_multiplier,
		"sky_radiance_size": 32 << scene.environment.sky.radiance_size,
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "os": OS.get_name(),
		"size": [screenshot.get_width(), screenshot.get_height()],
		"display_safe_area": str(DisplayServer.get_display_safe_area()),
		"camera": str(scene.cam.transform), "orthographic_size": scene.cam.size,
		"msaa": get_viewport().msaa_3d, "network_booted": Net.booted_once,
		"shadow_size": ProjectSettings.get_setting_with_override("rendering/lights_and_shadows/directional_shadow/size"),
		"shadow_filter": ProjectSettings.get_setting_with_override("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"),
		"catalog_sha256": SystemPonds.revision(),
		"water_shader_sha256": _water_hash
	}
	FileAccess.open(_output.path_join(_shape + "-" + _shot + ".json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("POND_ART_READY ", JSON.stringify(report))
	_ready_to_measure = true
	_loading = false
	if _capture: get_tree().quit()

func _shader_uniform(material: ShaderMaterial, key: StringName) -> Variant:
	var value: Variant = material.get_shader_parameter(key)
	return value if value != null else RenderingServer.shader_get_parameter_default(material.shader.get_rid(), key)

func frame_camera() -> void:
	_view_center = Vector3(6, 0, -8)
	_view_width = 14.6
	if _shot == "detail":
		_view_center = Vector3(6.5, 0, -5.8)
		_view_width = 7.0
	elif _shot == "reference":
		_view_center = Vector3(6, 0, -8)
		_view_width = 11.4
	elif _shot == "bank":
		_view_center = Vector3(6.5, 0, -11.1)
		_view_width = 5.0
	elif _shot == "tree":
		_view_center = Vector3(.1, 1.1, -4)
		_view_width = 4.2
	elif _shot == "portrait":
		_view_width = 11.2
		scene.canvas.show()
	_apply_camera()

func _apply_camera() -> void:
	var center := _view_center + _pan.offset
	scene.cam.size = _view_width / _pan.zoom
	var direction := Vector3(0.16, 1.10, 1.0).normalized()
	if _probe == "view-turn": direction = direction.rotated(Vector3.UP, deg_to_rad(30))
	scene.cam.position = center + direction * 36
	scene.cam.look_at(center)

func _input(event: InputEvent) -> void:
	if not _loading and _pan.handle(event, scene.cam, false): get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _loading and _pan.handle(event, scene.cam, true): get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"): _fixed = not _fixed
	if event is InputEventKey and event.pressed and event.keycode == KEY_R: _pan.reset()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]: _pan.cancel()
