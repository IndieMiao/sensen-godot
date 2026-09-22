class_name AvatarFocusButton
extends Button
## A cached saved-outfit portrait marking the direction to an offscreen player.

signal portrait_ready

const RENDER_SIZE := 288
const CACHE_LIMIT := 32
const TOUCH_SIZE := 56.0
const EDGE_GAP := 4.0
static var _cache: Dictionary = {}

var portrait: TextureRect
var _direction_arrow: TextureRect
var _viewport: SubViewport
var _camera: Camera3D
var _rig: AvatarRig
var _desired: AvatarConfig
var _desired_key := ""
var _shown_key := ""
var _rendering := false
var _render_generation := 0
var _foreground := true
var _visibility_sources: Array[Node] = []
var _offscreen := false
var renders := 0

func _ready() -> void:
	name = "AvatarFocus"
	custom_minimum_size = Vector2.ONE * TOUCH_SIZE
	size = custom_minimum_size
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hide()
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = &"ChoiceButton"
	_style_portrait()
	tooltip_text = L10n.text("Center on your character")
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.texture = GameUi.icon("user-round")
	portrait.modulate = GameUi.BLUE
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 3
	portrait.offset_top = 2
	portrait.offset_right = -3
	portrait.offset_bottom = -2
	add_child(portrait)
	_direction_arrow = GameUi.picture(GameUi.icon("arrow-right"), 18)
	_direction_arrow.name = "DirectionArrow"
	_direction_arrow.size = Vector2.ONE * 18
	_direction_arrow.pivot_offset = _direction_arrow.size * 0.5
	_direction_arrow.modulate = GameUi.GREEN
	add_child(_direction_arrow)
	var ancestor: Node = self
	while ancestor:
		if ancestor.has_signal("visibility_changed"):
			ancestor.connect("visibility_changed", _sync_render_state)
			_visibility_sources.append(ancestor)
		ancestor = ancestor.get_parent()
	Avatar.outfit_saved.connect(set_outfit)
	set_outfit(Avatar.load_outfit())

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_foreground = false
		_sync_render_state()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_foreground = true
		_sync_render_state()
	elif what in [NOTIFICATION_ENABLED, NOTIFICATION_DISABLED]:
		_sync_render_state()

func _exit_tree() -> void:
	_cancel_render()
	for source in _visibility_sources:
		if is_instance_valid(source) and source.is_connected("visibility_changed", _sync_render_state):
			source.disconnect("visibility_changed", _sync_render_state)
	_visibility_sources.clear()

func set_offscreen(value: bool) -> void:
	if _offscreen == value: return
	_offscreen = value
	theme_type_variation = &"ChoiceSelectedButton" if value else &"ChoiceButton"
	_style_portrait()

func update_indicator(projected: Vector2, viewport_rect: Rect2, placement_rect: Rect2,
		behind_camera := false, suppressed := false) -> void:
	var outside := behind_camera or not viewport_rect.has_point(projected)
	set_offscreen(outside)
	# Visibility uses the actual camera viewport. The inset only places the button;
	# it never makes an onscreen player "offscreen" or constrains camera/movement.
	if suppressed or not outside or not projected.is_finite() or not viewport_rect.has_area():
		hide()
		return
	var allowed := viewport_rect.intersection(placement_rect).grow(-(TOUCH_SIZE * 0.5 + EDGE_GAP))
	if allowed.size.x <= 0 or allowed.size.y <= 0:
		hide()
		return
	var direction := projected - viewport_rect.get_center()
	if direction.is_zero_approx(): direction = Vector2.DOWN
	var origin := viewport_rect.get_center().clamp(allowed.position, allowed.end)
	var distance := INF
	if not is_zero_approx(direction.x):
		distance = minf(distance, ((allowed.end.x if direction.x > 0 else allowed.position.x) - origin.x) / direction.x)
	if not is_zero_approx(direction.y):
		distance = minf(distance, ((allowed.end.y if direction.y > 0 else allowed.position.y) - origin.y) / direction.y)
	global_position = origin + direction * distance - Vector2.ONE * TOUCH_SIZE * 0.5
	_direction_arrow.position = Vector2.ONE * TOUCH_SIZE * 0.5 + direction.normalized() * 15 - _direction_arrow.size * 0.5
	_direction_arrow.rotation = direction.angle()
	show()

func _style_portrait() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := GameUi.card_style(_offscreen or state == "pressed", 2)
		style.set_corner_radius_all(28)
		style.set_border_width_all(2)
		style.shadow_size = 3
		style.shadow_offset = Vector2(0, 2)
		add_theme_stylebox_override(state, style)

func set_outfit(config: AvatarConfig) -> void:
	_desired = config.duplicate_config()
	_desired_key = config.to_json_text().sha256_text()
	_sync_render_state()

func _can_render() -> bool:
	return _foreground and not is_queued_for_deletion() and GameUi._visible_branch(self)

func _sync_render_state() -> void:
	if portrait == null or _desired == null: return
	if not _can_render():
		_cancel_render()
		return
	if _shown_key == _desired_key: return
	if _cache.has(_desired_key):
		_cancel_render()
		portrait.texture = _cache[_desired_key]
		portrait.modulate = Color.WHITE
		_shown_key = _desired_key
		portrait_ready.emit()
		return
	if not _rendering: _render_portrait.call_deferred()

func _release_rig() -> void:
	if not is_instance_valid(_rig): return
	_rig.get_parent().remove_child(_rig)
	_rig.free()
	_rig = null

func _cancel_render() -> void:
	_render_generation += 1
	_rendering = false
	if is_instance_valid(_viewport): _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_release_rig()

func _continue_render(generation: int) -> bool:
	if generation != _render_generation: return false
	if not _can_render():
		_cancel_render()
		return false
	return true

func _create_stage() -> void:
	if _viewport != null: return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER_SIZE, RENDER_SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("edf0ff")
	environment.environment.ambient_light_energy = 0.72
	_viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -28, 0)
	sun.light_energy = 0.95
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.02
	_camera.far = 6
	_viewport.add_child(_camera)
	_camera.make_current()

func _render_portrait() -> void:
	if _rendering or not _can_render() or _desired == null: return
	_rendering = true
	_render_generation += 1
	var generation := _render_generation
	while _shown_key != _desired_key:
		if not _continue_render(generation): return
		var key := _desired_key
		var config := _desired.duplicate_config()
		_create_stage()
		_rig = Avatar.create_rig()
		# The portrait renders only after appearance changes; it needs no distance polling.
		for child in _rig.get_children():
			if child is RigActivity:
				_rig.remove_child(child)
				child.free()
		_viewport.add_child(_rig)
		_rig.apply_config(config)
		while _rig.is_busy():
			await get_tree().process_frame
			if not _continue_render(generation): return
		_rig.play_motion("idle")
		var animation := _rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if animation: animation.pause()
		await get_tree().process_frame
		if not _continue_render(generation): return
		var head := Vector3(0, 1.15, 0)
		if _rig.skeleton:
			var bone := _rig.skeleton.find_bone("Head_M")
			if bone >= 0: head = _rig.skeleton.get_bone_global_pose(bone).origin
		var bounds := DressingCamera.merged_aabb(_rig)
		_camera.size = clampf(bounds.end.y - head.y + 0.55, 0.88, 1.35)
		var focus := head + Vector3.UP * (_camera.size * 0.5 - 0.40)
		_camera.position = focus + Vector3(0, 0.02, 2.4)
		_camera.look_at(focus, Vector3.UP)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		else: await get_tree().process_frame
		if not _continue_render(generation): return
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var picture: Image = null
		var notify_ready := false
		if DisplayServer.get_name() != "headless": picture = _viewport.get_texture().get_image()
		if picture != null and not picture.is_empty():
			_round_portrait(picture)
			var texture := ImageTexture.create_from_image(picture)
			while _cache.size() >= CACHE_LIMIT: _cache.erase(_cache.keys()[0])
			_cache[key] = texture
			if key == _desired_key:
				portrait.texture = texture
				portrait.modulate = Color.WHITE
				_shown_key = key
				renders += 1
				notify_ready = true
		else:
			_shown_key = key
		_release_rig()
		if notify_ready: portrait_ready.emit()
	if generation == _render_generation: _rendering = false

static func _round_portrait(picture: Image) -> void:
	picture.convert(Image.FORMAT_RGBA8)
	var bytes := picture.get_data()
	var middle := Vector2(picture.get_size()) * 0.5
	var radius := minf(middle.x, middle.y)
	for y in picture.get_height():
		for x in picture.get_width():
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(middle)
			var opacity := clampf((radius - distance) / 1.5, 0.0, 1.0)
			var index := (y * picture.get_width() + x) * 4 + 3
			bytes[index] = roundi(float(bytes[index]) * opacity)
	picture.set_data(picture.get_width(), picture.get_height(), false, Image.FORMAT_RGBA8, bytes)
