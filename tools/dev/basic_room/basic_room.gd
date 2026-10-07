extends Node3D
## Offline art/movement benchmark. Uses the existing avatar assembly and locomotion clips.
## Run the isolated project from prepare_basic_room.py; it has no networking autoloads.

const KIT := "res://assets/rooms/basic_room/"
const Controls = preload("res://tools/dev/basic_room/room_controls.gd")
const SPEED := 3.75
const QA_DIR := "user://room-qa"
var layout: Dictionary
var assets: Dictionary = {}
var camera: Camera3D
var player: CharacterBody3D
var rig: AvatarRig
var controls: Control
var hud: Control
var metrics: Label
var fire: Node3D
var fire_light: OmniLight3D
var visual: Node3D
var input_value := Vector2.ZERO
var focus := Vector3(0, 1.75, 0)
var reference_focus := Vector3(0, 1.75, 0)
var camera_offset := Vector3(9.5, 6.8, 11.2)
var zoom := 10.75
var still_for := 0.0
var time := 0.0
var state_timer := 0.0
var ready_for_capture := false
var beauty := false
var follow := false
var hud_visible := true
var command_sequence := -1
var capture_path := ""
var screenshot_done := false
var square_capture := false
var initial_spawn := Vector3(1.4, .085, 1.65)
var collision_frames := 0
var test_input := Vector2.ZERO
var test_input_until := 0.0
var recenter_tween: Tween

func _ready() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string(KIT + "layout.json"))
	_setup_world()
	_setup_room()
	_setup_player()
	_setup_ui()
	DirAccess.make_dir_recursive_absolute(QA_DIR)
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--beauty": _set_beauty(true)
		if args[i] == "--capture" and i + 1 < args.size(): capture_path = args[i + 1]
		if args[i] == "--no-hud": hud.visible = false
		if args[i] == "--capture-square": square_capture = true
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	print("BASIC_ROOM_READY offline benchmark; 22 reusable kits; existing AvatarRig")

func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _setup_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e8e4c8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff0dc")
	environment.ambient_light_energy = 0.70
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "AfternoonWindowSun"
	sun.light_color = Color("ffe6c2")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 30
	sun.shadow_bias = 0.045
	sun.shadow_normal_bias = 0.4
	sun.light_angular_distance = 1.4
	add_child(sun)
	sun.position = Vector3(-6, 7, 1.5)
	sun.look_at(Vector3.ZERO)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	ground.position.y = -.345
	var ground_mat := ShaderMaterial.new()
	var backdrop_shader := Shader.new()
	backdrop_shader.code = """shader_type spatial;
render_mode unshaded;
uniform vec4 mint : source_color = vec4(0.71, 0.85, 0.80, 1.0);
uniform vec4 cream : source_color = vec4(1.0, 0.92, 0.74, 1.0);
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
 float gradient = smoothstep(-6.0, 6.0, dot(world_position.xz, vec2(0.65, 0.76)));
 float edge = max(abs(world_position.x - 0.12), abs(world_position.z - 0.14)) - 3.27;
 float contact = 1.0 - smoothstep(-0.1, 0.65, edge);
 ALBEDO = mix(mint.rgb, cream.rgb, gradient) * (1.0 - contact * 0.13);
}"""
	ground_mat.shader = backdrop_shader
	ground.material_override = ground_mat
	add_child(ground)
	camera = Camera3D.new()
	camera.name = "ReferenceCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = .1
	camera.far = 70
	add_child(camera)
	camera.current = true
	_update_camera_transform()
	fire_light = OmniLight3D.new()
	fire_light.name = "HearthGlow"
	fire_light.position = _vec(layout.fire_position)
	fire_light.light_color = Color("ff9b35")
	fire_light.light_energy = .75
	fire_light.omni_range = 1.25
	fire_light.omni_attenuation = 1.6
	fire_light.shadow_enabled = false
	add_child(fire_light)

func _setup_room() -> void:
	var art := preload("res://scenes/basic_room/basic_room_art.tscn").instantiate()
	add_child(art)
	assets = art.assets
	fire = art.fire

func _setup_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = initial_spawn
	player.floor_snap_length = .20
	player.safe_margin = .012
	var capsule := CapsuleShape3D.new()
	capsule.radius = .21
	capsule.height = 1.25
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = .625
	player.add_child(collision)
	add_child(player)
	visual = Node3D.new()
	player.add_child(visual)
	rig = Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:
			child.reduced_distance = 50
			child.sleep_distance = 80
	visual.add_child(rig)
	rig.config_applied.connect(func(_config: AvatarConfig) -> void:
		rig.play_motion("idle")
		ready_for_capture = true
	)
	# Only the isolated fixture outfit; do not load or change a player's saved outfit.
	rig.apply_config(Avatar.slot_table.default_config())

func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	controls = Controls.new()
	layer.add_child(controls)
	controls.movement_changed.connect(func(value: Vector2) -> void: input_value = value)
	controls.zoom_changed.connect(func(factor: float) -> void: zoom = clampf(zoom * factor, 5.0, 12.0))
	controls.recenter_requested.connect(_recenter)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	var title := Label.new()
	title.name = "RoomTitle"
	title.text = "BASIC ROOM"
	title.position = Vector2(18, 18)
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("54492e"))
	hud.add_child(title)
	var subtitle := Label.new()
	subtitle.name = "RoomSubtitle"
	subtitle.text = "A little place to come home to"
	subtitle.position = Vector2(18, 42)
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", Color("857455"))
	hud.add_child(subtitle)
	var row := HBoxContainer.new()
	row.name = "ReviewControls"
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.position = Vector2(-156, 18)
	row.add_theme_constant_override("separation", 5)
	hud.add_child(row)
	for spec in [["View", "ViewButton"], ["Reset", "ResetButton"], ["Stats", "StatsButton"]]:
		var button := Button.new()
		button.name = spec[1]
		button.text = spec[0]
		button.custom_minimum_size = Vector2(45, 28)
		button.add_theme_font_size_override("font_size", 11)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("f7eed6")
		style.set_corner_radius_all(8)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_color_override("font_color", Color("605539"))
		row.add_child(button)
		if spec[0] == "View": button.pressed.connect(func() -> void: _set_beauty(not beauty))
		if spec[0] == "Reset": button.pressed.connect(_reset)
		if spec[0] == "Stats": button.pressed.connect(func() -> void: metrics.visible = not metrics.visible)
	metrics = Label.new()
	metrics.position = Vector2(18, 78)
	metrics.add_theme_font_size_override("font_size", 10)
	metrics.add_theme_color_override("font_color", Color("574e38"))
	metrics.visible = false
	hud.add_child(metrics)
	var hint := Label.new()
	hint.name = "MovementHint"
	hint.text = "Drag anywhere to walk  ·  Pinch to look closer"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -38
	hint.offset_bottom = -18
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color("857455"))
	hud.add_child(hint)

func _set_beauty(on: bool) -> void:
	beauty = on
	player.visible = not beauty
	input_value = Vector2.ZERO
	if beauty:
		focus = reference_focus
		zoom = 10.75
		follow = false

func _reset() -> void:
	if recenter_tween and recenter_tween.is_valid(): recenter_tween.kill()
	player.position = initial_spawn
	player.velocity = Vector3.ZERO
	input_value = Vector2.ZERO
	test_input = Vector2.ZERO
	focus = reference_focus
	zoom = 10.75
	follow = false

func _recenter() -> void:
	follow = false
	if recenter_tween and recenter_tween.is_valid(): recenter_tween.kill()
	recenter_tween = create_tween()
	recenter_tween.tween_property(self, "focus", player.position + Vector3.UP * .7, .4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _fit_camera() -> void:
	_update_camera_transform()
	if hud == null: return
	var safe_top := 0.0
	var safe_bottom := 0.0
	if OS.get_name() == "Android":
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.window_get_size()
		var ratio := get_viewport().get_visible_rect().size.y / maxf(screen.y, 1)
		safe_top = safe.position.y * ratio
		safe_bottom = maxf(0, screen.y - safe.end.y) * ratio
	hud.get_node("RoomTitle").position.y = 18 + safe_top
	hud.get_node("RoomSubtitle").position.y = 42 + safe_top
	hud.get_node("ReviewControls").position.y = 18 + safe_top
	metrics.position.y = 78 + safe_top
	controls.top_exclusion_y = 70 + safe_top
	hud.get_node("MovementHint").offset_top = -38 - safe_bottom
	hud.get_node("MovementHint").offset_bottom = -18 - safe_bottom

func _update_camera_transform() -> void:
	if camera == null: return
	var aspect := get_viewport().get_visible_rect().size.aspect()
	camera.size = zoom * maxf(1.0, aspect)
	camera.position = focus + camera_offset
	camera.look_at(focus)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R: _reset()
		if event.physical_keycode == KEY_V: _set_beauty(not beauty)
		if event.physical_keycode == KEY_F1:
			hud_visible = not hud_visible
			hud.visible = hud_visible
		if event.physical_keycode == KEY_C:
			focus = reference_focus
			zoom = 10.75
			follow = false

func _physics_process(delta: float) -> void:
	time += delta
	var key := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	var move := key.limit_length(1.0) if key != Vector2.ZERO else input_value
	if time < test_input_until: move = test_input
	if beauty: move = Vector2.ZERO
	var right := camera.global_basis.x
	var forward := -camera.global_basis.z
	right.y = 0
	forward.y = 0
	var direction := (right.normalized() * move.x - forward.normalized() * move.y).limit_length(1.0)
	player.velocity.x = direction.x * SPEED
	player.velocity.z = direction.z * SPEED
	player.velocity.y = -2.0 if player.is_on_floor() else player.velocity.y - 18.0 * delta
	player.move_and_slide()
	if player.get_slide_collision_count() > 1: collision_frames += 1
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > .05
	if moving:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(direction.x, direction.z), minf(delta * 16, 1))
		rig.play_motion("run")
		still_for = 0
		follow = true
	else:
		rig.play_motion("idle")
		still_for += delta
	if follow and not beauty:
		var screen := camera.unproject_position(player.position + Vector3.UP * .7)
		var size := get_viewport().get_visible_rect().size
		var error := Vector2.ZERO
		if screen.x < size.x*.30: error.x = screen.x-size.x*.30
		elif screen.x > size.x*.70: error.x = screen.x-size.x*.70
		if screen.y < size.y*.275: error.y = screen.y-size.y*.275
		elif screen.y > size.y*.725: error.y = screen.y-size.y*.725
		focus += right.normalized()*error.x*camera.size/size.x + forward.normalized()*error.y*camera.size/size.x
		if still_for > 0.05:
			var target := player.position + Vector3.UP*.7
			# A compact room remains inside the reference frame; zoomed views follow fully.
			if zoom > 8.5: target = reference_focus.lerp(target, .24)
			focus = focus.lerp(target, clampf(delta / .6 * 4.0, 0, 1))
	_update_camera_transform()
	if fire:
		fire.scale.y = 1.0 + .035*sin(time*4.4) + .018*sin(time*7.3)
		fire_light.light_energy = .72 + .035*sin(time*4.4)
	state_timer += delta
	if state_timer > .20:
		state_timer = 0
		_read_command()
		_write_state()
	if not capture_path.is_empty() and ready_for_capture and time > 3 and not screenshot_done:
		screenshot_done = true
		_capture(capture_path, true)

func _write_state() -> void:
	var animation := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var head := rig.skeleton.find_bone("Head_M") if rig.skeleton else -1
	var bone := rig.skeleton.get_bone_global_pose(head) if head >= 0 else Transform3D.IDENTITY
	var state := {
		"pid": OS.get_process_id(), "ready": ready_for_capture, "time": time, "beauty": beauty,
		"command_sequence": command_sequence,
		"position": [player.position.x, player.position.y, player.position.z],
		"velocity": [player.velocity.x, player.velocity.y, player.velocity.z],
		"input": [input_value.x, input_value.y], "zoom": zoom,
		"pinch_updates": controls.pinch_updates, "touch_events": controls.touch_events,
		"last_pinch_ratio": controls.last_pinch_ratio,
		"input_event_trace": controls.event_trace,
		"animation": animation.current_animation if animation else "",
		"animation_time": animation.current_animation_position if animation else 0,
		"head_origin": [bone.origin.x, bone.origin.y, bone.origin.z],
		"fps": Engine.get_frames_per_second(),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"rendering_device": RenderingServer.get_video_adapter_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"on_floor": player.is_on_floor(), "collision_frames": collision_frames,
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"player_screen": [camera.unproject_position(player.position).x, camera.unproject_position(player.position).y]
	}
	var buttons: Array = []
	for button in hud.get_node("ReviewControls").get_children():
		var rect: Rect2 = button.get_global_rect()
		buttons.append({"name": button.name, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	state["buttons"] = buttons
	var f := FileAccess.open(QA_DIR + "/state.pending", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state))
		f.close()
		DirAccess.rename_absolute(QA_DIR + "/state.pending", QA_DIR + "/state.json")
	metrics.text = "%s\n%d FPS · %d draws · %d tris\n%.1f MiB reported GPU memory" % [state.rendering_method, state.fps, state.draw_calls, state.primitives, float(state.video_memory_bytes)/1048576]

func _read_command() -> void:
	var path := QA_DIR + "/command.json"
	if not FileAccess.file_exists(path): return
	var command: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not command is Dictionary: return
	var sequence := int(command.get("sequence", -1))
	if sequence <= command_sequence: return
	command_sequence = sequence
	if command.has("beauty"): _set_beauty(bool(command.beauty))
	if command.has("hud"): hud.visible = bool(command.hud)
	if command.has("reset"): _reset()
	if command.has("position"): player.position = _vec(command.position)
	if command.has("focus"): focus = _vec(command.focus)
	if command.has("zoom"): zoom = clampf(float(command.zoom), 5, 12)
	if command.has("input"):
		test_input = Vector2(float(command.input[0]), float(command.input[1]))
		test_input_until = time + float(command.get("duration", 1))
	if command.has("capture"): _capture(String(command.capture), false)

func _capture(path: String, exit_after: bool) -> void:
	if square_capture:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1600, 1600)
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.world_3d = get_world_3d()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var shot_camera := Camera3D.new()
		shot_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		shot_camera.size = zoom
		shot_camera.near = camera.near
		shot_camera.far = camera.far
		viewport.add_child(shot_camera)
		shot_camera.global_transform = camera.global_transform
		shot_camera.current = true
		for i in 4: await RenderingServer.frame_post_draw
		var result := viewport.get_texture().get_image().save_png(path)
		print("BASIC_ROOM_SQUARE_CAPTURE ", path, " error=", result)
		viewport.queue_free()
		if exit_after: get_tree().quit(result)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("BASIC_ROOM_CAPTURE ", path, " error=", error)
	if exit_after: get_tree().quit(error)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		input_value = Vector2.ZERO
		test_input_until = 0
