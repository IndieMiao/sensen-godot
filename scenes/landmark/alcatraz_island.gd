class_name AlcatrazIsland
extends Node3D
## SGODOT-424 blockout. Local sightseeing only; no network/rewards/save writes.
## Walking, isolated nav map and ScenePan gestures follow Griffith's implementation.
## The brief explicitly requests follow; that addition is local to this scene.

signal exit_requested
const ROOT := "res://assets/landmarks/alcatraz_island/"
const ScenePan := preload("res://modules/farm/scene_pan.gd")
const PHONE_WIDTH := 7.0
const PITCH := 45.0
const WALK_SPEED := 2.3
var layout: Dictionary
var camera_pan := ScenePan.new()
var _camera: Camera3D
var _player: Node3D
var _rig: AvatarRig
var _nav_map: RID
var _path := PackedVector3Array()
var _path_i := 0
var _running := false
var _focus := Vector3.ZERO
var _following := true
var _overview := false
var _environment: WorldEnvironment
var _saved_environment: Environment
var _hud: CanvasLayer
var _exit_button: Button
var _exit_marker: VBoxContainer
var _camera_recenter: Tween
var mesh_nodes: Array[MeshInstance3D] = []
var _mesh_cache := {}

func _ready() -> void:
	get_viewport().transparent_bg = false
	layout = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "layout.json"))
	_environment = WorldEnvironment.new()
	_environment.environment = Environment.new()
	_environment.environment.background_mode = Environment.BG_COLOR
	# Diagnostic magenta: no review pixel should expose this behind the ocean.
	_environment.environment.background_color = Color("d000d0")
	_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.environment.ambient_light_color = Color("d5e4ee")
	_environment.environment.ambient_light_energy = 0.72
	add_child(_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56, -34, 0)
	sun.light_color = Color(1.0, 0.965, 0.88)
	sun.light_energy = 0.98
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_opacity = 0.48
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 0.28
	add_child(sun)
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.roughness = 0.94
	paint.metallic_specular = 0.15
	for p in layout.placements:
		var asset := str(p.asset)
		var node := MeshInstance3D.new()
		node.name = asset.to_pascal_case() + str(mesh_nodes.size())
		if not _mesh_cache.has(asset):
			var source := (load(ROOT + asset + ".glb") as PackedScene).instantiate()
			var found := source.find_children("*", "MeshInstance3D", true, false)
			if source is MeshInstance3D: found.push_front(source)
			_mesh_cache[asset] = (found[0] as MeshInstance3D).mesh
			source.free()
		node.mesh = _mesh_cache[asset]
		node.material_override = paint
		node.position = _vec(p.position)
		node.rotation.y = float(p.yaw)
		node.scale = Vector3.ONE * float(p.scale)
		add_child(node)
		mesh_nodes.append(node)
		if bool(p.collision): node.create_trimesh_collision()
		if asset.ends_with("backdrop"):
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * float(layout.sea_size)
	sea.mesh = plane
	sea.position.y = -0.15
	var water := StandardMaterial3D.new()
	water.albedo_color = Color("8fa8af")
	water.roughness = 0.93
	water.metallic_specular = 0.12
	sea.material_override = water
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	for key in ["spawn", "exit", "cam0"]:
		var anchor := Marker3D.new()
		anchor.name = key
		anchor.position = _vec(layout[key])
		add_child(anchor)
	_build_navigation()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(_camera)
	_camera.make_current()
	_spawn_player()
	camera_pan.free_pan = true
	camera_pan.hold_enabled = false
	camera_pan.tapped.connect(walk_to_screen)
	_build_controls()
	_update_camera()

static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _build_navigation() -> void:
	var nav := NavigationMesh.new()
	var vertices := PackedVector3Array()
	for v in layout.navigation.vertices: vertices.append(_vec(v))
	nav.vertices = vertices
	for p in layout.navigation.polygons: nav.add_polygon(PackedInt32Array(p))
	nav.cell_size = 0.25
	nav.cell_height = 0.1
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nav
	_nav_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_nav_map, true)
	NavigationServer3D.map_set_cell_size(_nav_map, 0.25)
	NavigationServer3D.map_set_cell_height(_nav_map, 0.1)
	add_child(region)
	region.set_navigation_map(_nav_map)

func _spawn_player() -> void:
	_player = Node3D.new()
	_player.name = "Visitor"
	_player.position = _vec(layout.spawn)
	add_child(_player)
	_rig = Avatar.create_rig()
	_rig.assembler = AvatarAssemblerMerged.new()
	_rig.rotation.y = PI
	for child in _rig.get_children():
		if child is RigActivity:
			child.sleep_distance = 80
			child.reduced_distance = 60
	_player.add_child(_rig)
	_rig.config_applied.connect(func(_c): _animation("idle"))
	_rig.apply_config(Avatar.load_outfit())
	_focus = _player.position

func _animation(motion: String) -> void:
	_rig.play_motion(motion)

func navigation_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(_nav_map) > 0 \
		and NavigationServer3D.map_get_closest_point_owner(_nav_map, _player.position).is_valid()

func walk_to_screen(point: Vector2) -> void:
	if not navigation_ready(): return
	var origin := _camera.project_ray_origin(point)
	var normal := _camera.project_ray_normal(point)
	# Actual geometry hit resolves multi-level stairs without projecting through a higher terrace.
	var query := PhysicsRayQueryParameters3D.create(origin, origin + normal * 200.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var goal: Vector3
	if hit.is_empty():
		var ground = Plane(Vector3.UP, _player.position.y).intersects_ray(origin, normal)
		if ground == null: return
		goal = NavigationServer3D.map_get_closest_point(_nav_map, ground)
	else:
		goal = NavigationServer3D.map_get_closest_point(_nav_map, hit.position)
	walk_to(goal)

func walk_to(goal: Vector3) -> void:
	if not navigation_ready(): return
	_path = NavigationServer3D.map_get_path(_nav_map, _player.position, goal, true)
	_path_i = 0
	_following = true
	_overview = false
	camera_pan.reset(camera_pan.zoom)
	_stop_camera_recenter()

func _step_walk(delta: float) -> void:
	if _path_i >= _path.size():
		if _running:
			_running = false
			_animation("idle")
		return
	var goal := _path[_path_i]
	var to := goal - _player.position
	var step := WALK_SPEED * delta
	if to.length() <= step:
		_player.position = goal
		_path_i += 1
	else:
		_player.position += to.normalized() * step
		var flat := Vector3(to.x, 0, to.z)
		if flat.length() > 0.01: _player.look_at(_player.position + flat, Vector3.UP)
	if not _running:
		_running = true
		_animation("run")

func _process(delta: float) -> void:
	_step_walk(delta)
	camera_pan.step(delta, _camera)
	if _following and not _overview and not camera_pan.active() and not _camera_recenter:
		_focus = _focus.lerp(_player.position, 1.0 - exp(-8.0 * delta))
	_update_camera()

func _update_camera() -> void:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.y / maxf(1.0, size.x)
	var width := (32.0 if _overview else PHONE_WIDTH) / camera_pan.zoom
	_camera.size = width
	if not camera_pan.active():
		_focus += camera_pan.offset
		camera_pan.offset = Vector3.ZERO
		camera_pan._raw_offset = Vector3.ZERO
	# Bound manual exploration well inside the 512 m ocean backdrop.
	_focus.x = clampf(_focus.x, -25, 25)
	_focus.z = clampf(_focus.z, -30, 30)
	var target := _focus + camera_pan.offset
	var dir := Vector3(0, sin(deg_to_rad(PITCH)), cos(deg_to_rad(PITCH)))
	_camera.position = target + dir * 40.0
	_camera.look_at(target, Vector3.UP)
	_camera.near = maxf(0.1, 40.0 - width * aspect * 0.9 - 12.0)
	_camera.far = 160.0
	if _exit_button:
		var point := _camera.unproject_position(_vec(layout.exit) + Vector3.UP * .45)
		_exit_marker.visible = not _overview and not _camera.is_position_behind(_vec(layout.exit)) \
			and Rect2(Vector2(30,60), size - Vector2(60,130)).has_point(point)
		_exit_marker.position = point - Vector2(24,20)

func _build_controls() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	add_child(_hud)
	var title := Label.new()
	title.text = "Alcatraz Island"
	title.position = Vector2(16,14)
	title.add_theme_color_override("font_color", Color("343b3c"))
	title.add_theme_font_size_override("font_size",18)
	_hud.add_child(title)
	_exit_marker = VBoxContainer.new()
	_exit_marker.name = "DockExitMarker"
	_exit_marker.add_theme_constant_override("separation",2)
	_hud.add_child(_exit_marker)
	_exit_button = Button.new()
	_exit_button.name = "DockMapExit"
	_exit_button.icon = preload("res://assets/ui/icons/game/door-open.svg")
	_exit_button.expand_icon = true
	_exit_button.add_theme_constant_override("icon_max_width",22)
	_exit_button.custom_minimum_size = Vector2(48,44)
	_exit_button.pressed.connect(_leave)
	_exit_marker.add_child(_exit_button)
	var map_name := Label.new()
	map_name.text = "Map"
	map_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_name.add_theme_font_size_override("font_size",13)
	var name_background := StyleBoxFlat.new()
	name_background.bg_color = Color(0.18,0.22,0.23,.9)
	map_name.add_theme_stylebox_override("normal",name_background)
	_exit_marker.add_child(map_name)
	var controls := HBoxContainer.new()
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_top = -56
	controls.offset_bottom = -12
	controls.offset_left = 12
	controls.offset_right = -12
	_hud.add_child(controls)
	for caption in ["Follow", "Overview"]:
		var button := Button.new()
		button.text = caption
		button.custom_minimum_size = Vector2(88,44)
		controls.add_child(button)
		button.pressed.connect(recenter_on_player if caption == "Follow" else toggle_overview)

func _input(event: InputEvent) -> void:
	_handle_camera_input(event, false)

func _unhandled_input(event: InputEvent) -> void:
	_handle_camera_input(event, true)

func _handle_camera_input(event: InputEvent, allow_start: bool) -> bool:
	if camera_pan.handle(event, _camera, allow_start):
		if camera_pan.dragged or camera_pan.multi:
			_following = false
			_stop_camera_recenter()
		_update_camera()
		get_viewport().set_input_as_handled()
		return true
	return false

func _stop_camera_recenter() -> void:
	if _camera_recenter:
		_camera_recenter.kill()
		_camera_recenter = null

func recenter_on_player() -> void:
	_stop_camera_recenter()
	camera_pan.reset(camera_pan.zoom)
	_overview = false
	_following = true
	var start := _focus
	_camera_recenter = create_tween()
	_camera_recenter.tween_method(func(w: float):
		_focus = start.lerp(_player.position, w)
		_update_camera(), 0.0, 1.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_camera_recenter.finished.connect(func(): _camera_recenter = null)

func toggle_overview() -> void:
	_stop_camera_recenter()
	camera_pan.reset()
	_overview = not _overview
	_following = not _overview
	_focus = Vector3(0,2,0) if _overview else _player.position
	_update_camera()

func _leave() -> void:
	exit_requested.emit()
	var router := get_node_or_null("/root/AppRouter")
	if router and router.top_instance() == self: router.handle_back()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		camera_pan.cancel()
		_stop_camera_recenter()

func suspend() -> void:
	_stop_camera_recenter()
	camera_pan.cancel()
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	_hud.visible = false
	_camera.current = false
	_saved_environment = _environment.environment
	_environment.environment = null

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	_hud.visible = true
	get_viewport().transparent_bg = false
	_environment.environment = _saved_environment
	_camera.make_current()
	_update_camera()

func _exit_tree() -> void:
	_stop_camera_recenter()
	camera_pan.cancel()
	if _nav_map.is_valid():
		NavigationServer3D.free_rid(_nav_map)
		_nav_map = RID()
