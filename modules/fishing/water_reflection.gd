class_name WaterReflection
extends Node3D
## A small planar capture of static bank scenery. Only camera changes refresh it;
## shader waves distort the cached reflection while the player stands fishing.
var material: ShaderMaterial
var _viewport: SubViewport
var _camera: Camera3D
var _last := Transform3D()
var _age := 10.0
var _initialized := false
var _captures := 0
var _last_frame := Vector2.ZERO
var _last_lens := Vector4.ZERO

func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "WaterReflectionCapture"
	_viewport.transparent_bg = true
	_viewport.size = Vector2i(384, 512)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	_viewport.world_3d = get_world_3d()
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.cull_mask = 4
	_camera.current = true
	_camera.environment = Environment.new()
	_camera.environment.background_mode = Environment.BG_COLOR
	_camera.environment.background_color = Color("adc8d2")
	_camera.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_camera.environment.ambient_light_color = Color("c0d3dc")
	_camera.environment.ambient_light_energy = 0.45
	_viewport.add_child(_camera)
	material.set_shader_parameter("bank_reflection", _viewport.get_texture())

static func _mirror(point: Vector3) -> Vector3:
	return Vector3(point.x, -point.y, point.z)

func _process(delta: float) -> void:
	var visibility := get_parent().get_node_or_null("WaterVisibility") as VisibleOnScreenNotifier3D
	if visibility and not visibility.is_on_screen(): return
	var camera := get_viewport().get_camera_3d()
	if camera == null or _camera == null: return
	_age += delta
	if _initialized and _age < 0.16: return
	var actual := camera.global_transform
	var frame := get_viewport().get_visible_rect().size
	var lens := Vector4(camera.size, camera.fov, camera.h_offset, camera.v_offset)
	if _initialized and actual.is_equal_approx(_last) and frame == _last_frame and lens == _last_lens: return
	_age = 0
	_last = actual
	_last_frame = frame
	_last_lens = lens
	_viewport.size = Vector2i(384, maxi(192, roundi(384 * frame.y / maxf(frame.x, 1))))
	_camera.projection = camera.projection
	_camera.keep_aspect = camera.keep_aspect
	_camera.size = camera.size
	_camera.fov = camera.fov
	_camera.near = 0.05
	_camera.far = 100
	_camera.v_offset = camera.v_offset
	_camera.h_offset = -camera.h_offset
	_camera.global_transform = Transform3D(Basis(-_mirror(actual.basis.x), _mirror(actual.basis.y), _mirror(actual.basis.z)), _mirror(actual.origin) + Vector3.UP * 0.11)
	_captures += 1
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not _initialized:
		_initialized = true
		_enable.call_deferred()

func _enable() -> void:
	await RenderingServer.frame_post_draw
	if is_inside_tree(): material.set_shader_parameter("has_bank_reflection", true)
