class_name BagCharacterPreview
extends TextureRect
## The committed local outfit, rendered only while the character page is visible.

const MAX_RENDER_SCALE := 4.0
const MAX_RENDER_EDGE := 1024

var viewport: SubViewport
var rig: AvatarRig
var _active := false
var _camera: Camera3D
var _pending_outfit: AvatarConfig
var _outfit_dirty := true
var _application_paused := false
var _visibility_sources: Array[Node] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	custom_minimum_size = Vector2(112, 196)
	viewport = SubViewport.new()
	viewport.name = "CharacterViewport"
	viewport.size = Vector2i(112, 196)
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	texture = viewport.get_texture()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("f3f0ff")
	environment.environment.ambient_light_energy = 0.72
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -24, 0)
	light.light_energy = 1.05
	light.shadow_enabled = true
	viewport.add_child(light)
	var camera := Camera3D.new()
	_camera = camera
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.18
	camera.near = 0.1
	camera.far = 12.0
	camera.position = Vector3(0, 1.0, 4.0)
	viewport.add_child(camera)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.make_current()
	_watch_visibility()
	Avatar.outfit_saved.connect(_outfit_changed)
	resized.connect(_resize_viewport)
	_sync_visibility()

func set_active(value: bool) -> void:
	_active = value
	if is_inside_tree():
		_watch_visibility()
		_sync_visibility()

func _watch_visibility() -> void:
	_disconnect_visibility()
	var ancestor: Node = self
	while ancestor:
		if ancestor.has_signal("visibility_changed"):
			ancestor.connect("visibility_changed", _sync_visibility)
			_visibility_sources.append(ancestor)
		ancestor = ancestor.get_parent()

func _disconnect_visibility() -> void:
	for source in _visibility_sources:
		if is_instance_valid(source) and source.is_connected("visibility_changed", _sync_visibility):
			source.disconnect("visibility_changed", _sync_visibility)
	_visibility_sources.clear()

func _exit_tree() -> void:
	_disconnect_visibility()

func _ensure_rig() -> void:
	if rig != null: return
	rig = Avatar.create_rig()
	rig.name = "SavedCharacter"
	rig.rotation_degrees.y = 12
	viewport.add_child(rig)
	rig.config_applied.connect(func(_config):
		rig.play_motion("idle")
		_sync_visibility())

func _outfit_changed(config: AvatarConfig) -> void:
	_pending_outfit = config.duplicate_config()
	_outfit_dirty = true
	_sync_visibility()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_application_paused = true
		_sync_visibility()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_application_paused = false
		_sync_visibility()
	elif what in [NOTIFICATION_ENABLED, NOTIFICATION_DISABLED]: _sync_visibility()

func _sync_visibility() -> void:
	if viewport == null: return
	var live := _active and GameUi._visible_branch(self) and not _application_paused
	if live:
		_ensure_rig()
		if _outfit_dirty:
			_outfit_dirty = false
			rig.apply_config(_pending_outfit if _pending_outfit != null else Avatar.load_outfit())
	set_process(live)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	if rig != null: rig.process_mode = Node.PROCESS_MODE_INHERIT if live else Node.PROCESS_MODE_DISABLED
	if live: _resize_viewport()

func _process(_delta: float) -> void:
	# Screen scale can change without a logical Control resize (window/DPI change).
	_resize_viewport()

func _resize_viewport() -> void:
	if viewport == null or not is_inside_tree(): return
	var screen := get_viewport().get_screen_transform() * get_global_transform_with_canvas()
	var pixel_scale := maxf(screen.x.length(), screen.y.length())
	var density := clampf(pixel_scale, 1.0, MAX_RENDER_SCALE)
	var target := Vector2(maxf(1, size.x), maxf(1, size.y)) * density
	var longest := maxf(target.x, target.y)
	if longest > MAX_RENDER_EDGE: target *= float(MAX_RENDER_EDGE) / longest
	var pixels := Vector2i(maxi(1, roundi(target.x)), maxi(1, roundi(target.y)))
	if viewport.size != pixels: viewport.size = pixels
	if _camera: _camera.size = maxf(2.18, 1.18 * size.y / maxf(1, size.x))
