extends Node3D
## Read-only art review: no Net session, commands, FarmChoice writes or save migration.

const Art = preload("res://modules/farm/farm_art.gd")
const Scenery = preload("res://modules/farm/farm_scenery.gd")
const Pan = preload("res://modules/farm/scene_pan.gd")
const STYLE_NAMES := ["小房子", "蘑菇屋", "小草屋", "中东风情", "东亚韵味", "美式农场", "自由飞翔"]
const PLOT_COUNTS := [4, 4, 9, 9, 12, 12, 12]
var _stage: Node3D
var _camera: Camera3D
var _player: Node3D
var _mover: PlayerMover
var _rig: AvatarRig
var _style := 0
var _pan := Pan.new()
var _count: Label
var _picker: OptionButton
var _frames := 0
var _samples: Array[float] = []
var _report: Array = []
var _capture_dir := ""
var _capture_all := false
var _moving := false
var _last_frame_usec := 0
var _capture_failed := false
var _shadow_size := 0
var _shadow_filter := 0

func _ready() -> void:
	_shadow_size = int(ProjectSettings.get_setting_with_override("rendering/lights_and_shadows/directional_shadow/size"))
	if not OS.get_environment("FARM_ART_SHADOW_SIZE").is_empty():
		_shadow_size = maxi(256, int(OS.get_environment("FARM_ART_SHADOW_SIZE")))
		RenderingServer.directional_shadow_atlas_set_size(_shadow_size, true)
	_shadow_filter = int(ProjectSettings.get_setting_with_override("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))
	if not OS.get_environment("FARM_ART_SHADOW_FILTER").is_empty():
		_shadow_filter = clampi(int(OS.get_environment("FARM_ART_SHADOW_FILTER")), 0, 5)
		RenderingServer.directional_soft_shadow_filter_set_quality(_shadow_filter)
	_capture_dir = OS.get_environment("FARM_ART_CAPTURE")
	_capture_all = OS.get_environment("FARM_ART_ALL") == "1"
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_style = maxi(0, Art.STYLES.find(OS.get_environment("FARM_ART_STYLE")))
	var env := WorldEnvironment.new()
	var farm := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	env.environment = farm.get_node("WorldEnvironment").environment.duplicate()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("adc66f")
	add_child(env)
	var sun := farm.get_node("Sun").duplicate() as DirectionalLight3D
	add_child(sun)
	farm.free()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(_camera)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(96, 96)
	ground.mesh = plane
	ground.position.y = -0.008
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://modules/farm/shaders/meadow.gdshader")
	mat.set_shader_parameter("meadow_texture", preload("res://assets/farm/art/meadow.png"))
	ground.material_override = mat
	add_child(ground)
	_toolbar()
	_rebuild()
	_pan.radius = 3
	_pan.min_zoom = 0.7
	_pan.max_zoom = 1.7
	_pan.tapped.connect(_walk)
	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
		_capture.call_deferred()

func _toolbar() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = -64
	bar.offset_bottom = -16
	bar.add_theme_constant_override("separation", 8)
	layer.add_child(bar)
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.custom_minimum_size.y = 44
	for title in STYLE_NAMES: _picker.add_item(title)
	_picker.selected = _style
	_picker.item_selected.connect(func(index): _style = index; _rebuild())
	bar.add_child(_picker)
	_count = Label.new()
	_count.add_theme_color_override("font_color", Color("304839"))
	bar.add_child(_count)
	var reset := Button.new()
	reset.icon = GameUi.icon("rotate-ccw")
	reset.tooltip_text = "Reset camera"
	reset.custom_minimum_size = Vector2(44, 44)
	reset.pressed.connect(func(): _pan.reset())
	bar.add_child(reset)

func _rebuild() -> void:
	if _stage:
		remove_child(_stage)
		_stage.queue_free()
	_stage = Node3D.new()
	add_child(_stage)
	var source := FarmBlueprint.load_file("res://assets/blueprints/sh_a/r2/farm_blueprint.json")
	var bp := FarmPlot.blueprint_for()
	var count: int = PLOT_COUNTS[_style]
	_count.text = "%d 田块" % count
	var scenery := Scenery.new()
	_stage.add_child(scenery)
	scenery.build(bp, Art.STYLES[_style])
	scenery.set_expanded(count == 12)
	scenery._garden_path.visible = false
	_stage.add_child(Art.instance("house_" + Art.STYLES[_style], bp.cell_to_world(bp.anchor("house"))))
	_stage.add_child(Art.instance("well", bp.cell_to_world(bp.anchor("well"))))
	_stage.add_child(Art.instance("storage", bp.cell_to_world(bp.anchor("storage"))))
	var crop := CropField.new(bp)
	crop.ground_y = 0.15
	_stage.add_child(crop)
	var cells: Array = []
	var plots: Array = []
	for row in (2 if count == 4 else 3 if count == 9 else 4):
		for column in (2 if count == 4 else 3):
			var cell := Vector2i(4 + column * 2, 8 - row * 2)
			var pos := bp.cell_to_world(cell)
			plots.append(Transform3D(Basis.IDENTITY, pos))
			cells.append({"cell_id": "%d,%d" % [cell.x, cell.y], "state": "growing" if column == 0 or row == 1 else "sown",
				"crop": "R" if column == 0 else "L" if row == 1 and column == 1 and count > 4 else "C" if column == 2 else "R",
				"ripe": column == 0 or (row == 1 and count > 4)})
	var garden_center := bp.cell_to_world(Vector2i(5, 7)) if count == 4 else bp.cell_to_world(Vector2i(6, 6 if count == 9 else 5))
	var path := Art.instance("path_tile", garden_center + Vector3(0, 0.003, 0))
	path.scale = Vector3(2.08 if count == 4 else 3.1, 1, 2.08 if count == 4 else 3.1 if count == 9 else 4.12)
	path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(path)
	_stage.add_child(Art.batch("plot", plots))
	var benchmark_crop := OS.get_environment("FARM_ART_CROP")
	if benchmark_crop in CropField.CROPS:
		for slot in cells:
			slot.crop = benchmark_crop
			slot.state = "growing"
			slot.ripe = true
	crop.sync_snapshot(cells)
	_player = Node3D.new()
	_stage.add_child(_player)
	_rig = Avatar.create_rig()
	_rig.assembler = AvatarAssemblerMerged.new()
	_rig.rotation.y = PI
	for child in _rig.get_children():
		if child is RigActivity:
			child.sleep_distance = 60
			child.reduced_distance = 40
	_player.add_child(_rig)
	_rig.config_applied.connect(func(_config): _animation("idle"))
	_rig.apply_config(Avatar.load_outfit())
	if count == 4: bp.anchors.spawn = Vector2i(5, 4)
	_mover = PlayerMover.new(bp, BlueprintGrid.new(bp))
	_player.position = _mover.position
	_pan.reset()
	_frames = 0
	_samples.clear()

func _process(delta: float) -> void:
	if not _mover: return
	_mover.step(delta)
	_player.position = _mover.position
	if _mover.is_moving():
		_player.look_at(_player.position + _mover.facing, Vector3.UP)
	if _moving != _mover.is_moving():
		_moving = _mover.is_moving()
		_animation("run" if _moving else "idle")
	_pan.step(delta, _camera)
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(1.0, size.y)
	_camera.size = maxf(6.2 if PLOT_COUNTS[_style] == 4 else 6.6, 8.4 * aspect) / _pan.zoom
	var target := Vector3(4.2, 0.20, -5.3) if PLOT_COUNTS[_style] == 4 else Vector3(4.5, 0.20, -4.9)
	_camera.position = target + Vector3(3.1, 10.6, 11.0) + _pan.offset
	_camera.look_at(target + _pan.offset)
	preload("res://modules/farm/farm_camera.gd").fit_ground_depth(_camera)
	_frames += 1
	var now := Time.get_ticks_usec()
	if _frames > 90 and _last_frame_usec > 0: _samples.append(float(now - _last_frame_usec) / 1000)
	_last_frame_usec = now

func _animation(name: String) -> void:
	var player := _rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player and player.has_animation(name): player.play(name)

func _unhandled_input(event: InputEvent) -> void:
	if _pan.handle(event, _camera, true): get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if _camera and _pan.handle(event, _camera): get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _pan.cancel()

func _walk(point: Vector2) -> void:
	var hit = Plane(Vector3.UP, 0).intersects_ray(_camera.project_ray_origin(point), _camera.project_ray_normal(point))
	if hit is Vector3: _mover.set_target_position(hit)

func _capture() -> void:
	for frame in 210: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	for frame in 30: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var moved := get_viewport().get_texture().get_image()
	var changed_pixels := 0
	for y in range(0, screenshot.get_height() - 80, 2):
		for x in range(0, screenshot.get_width(), 2):
			var before := screenshot.get_pixel(x, y)
			var after := moved.get_pixel(x, y)
			if absf(before.r - after.r) + absf(before.g - after.g) + absf(before.b - after.b) > 0.06:
				changed_pixels += 1
	_capture_failed = _capture_failed or changed_pixels < 10
	var filename: String = Art.STYLES[_style] + "-%dx%d" % [screenshot.get_width(), screenshot.get_height()]
	screenshot.save_png(_capture_dir.path_join(filename + ".png"))
	_samples.sort()
	var sum := 0.0
	for sample in _samples: sum += sample
	var entry := {"style": Art.STYLES[_style], "size": screenshot.get_size(), "samples": _samples.size(), "animated_sample_pixels": changed_pixels,
		"camera_near": _camera.near, "camera_far": _camera.far, "shadow_atlas_size": _shadow_size, "shadow_filter": _shadow_filter,
		"frame_ms_mean": sum / maxf(1, _samples.size()),
		"frame_ms_p95": _samples[mini(_samples.size() - 1, int(_samples.size() * 0.95))] if not _samples.is_empty() else 0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"render_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())}
	if OS.get_environment("FARM_ART_CHECK_SHADOWS") == "1":
		var sun := get_node("Sun") as DirectionalLight3D
		sun.shadow_enabled = false
		for frame in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var unshadowed := get_viewport().get_texture().get_image()
		var shadow_pixels := 0
		for y in range(0, screenshot.get_height() - 80, 2):
			for x in range(0, screenshot.get_width(), 2):
				if unshadowed.get_pixel(x, y).get_luminance() - screenshot.get_pixel(x, y).get_luminance() > 0.045:
					shadow_pixels += 1
		entry["shadow_sample_pixels"] = shadow_pixels
		_capture_failed = _capture_failed or shadow_pixels < 500
		unshadowed.save_png(_capture_dir.path_join(filename + "-shadows-off.png"))
		sun.shadow_enabled = true
	_report.append(entry)
	print("FARM_ART_CAPTURE ", JSON.stringify(entry))
	if _capture_all and _style < Art.STYLES.size() - 1:
		_style += 1
		_picker.selected = _style
		_rebuild()
		_capture.call_deferred()
	else:
		if _capture_all:
			var sheet := Image.create(288 * Art.STYLES.size(), 540, false, Image.FORMAT_RGB8)
			for i in Art.STYLES.size():
				var path := _capture_dir.path_join(Art.STYLES[i] + "-%dx%d.png" % [screenshot.get_width(), screenshot.get_height()])
				var panel := Image.load_from_file(path)
				panel.convert(Image.FORMAT_RGB8)
				panel.resize(288, 540, Image.INTERPOLATE_LANCZOS)
				sheet.blit_rect(panel, Rect2i(0, 0, 288, 540), Vector2i(i * 288, 0))
			sheet.save_png(_capture_dir.path_join("reference-lineup.png"))
		var file := FileAccess.open(_capture_dir.path_join("metrics.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(_report, "\t") + "\n")
		get_tree().quit(1 if _capture_failed else 0)
