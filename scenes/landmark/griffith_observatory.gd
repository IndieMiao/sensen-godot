class_name GriffithObservatory
extends Node3D
## Local landmark visit using the owner's saved outfit and farm camera gestures.
## The map remains below this instance; walking never writes farm state or rewards.

const ROOT := "res://assets/landmarks/griffith_observatory/"
const PITCH := 45.0
const WALK_SPEED := 2.3
const PHONE_WIDTH := 7.0
const ASSETS := {
	"bench": preload("res://assets/landmarks/griffith_observatory/bench.glb"),
	"bush": preload("res://assets/landmarks/griffith_observatory/bush.glb"),
	"bush_round": preload("res://assets/landmarks/griffith_observatory/bush_round.glb"),
	"cafe": preload("res://assets/landmarks/griffith_observatory/cafe.glb"),
	"city": preload("res://assets/landmarks/griffith_observatory/city.glb"),
	"cypress": preload("res://assets/landmarks/griffith_observatory/cypress.glb"),
	"fence_post": preload("res://assets/landmarks/griffith_observatory/fence_post.glb"),
	"flowers": preload("res://assets/landmarks/griffith_observatory/flowers.glb"),
	"fountain_0": preload("res://assets/landmarks/griffith_observatory/fountain_0.glb"),
	"fountain_1": preload("res://assets/landmarks/griffith_observatory/fountain_1.glb"),
	"fountain_2": preload("res://assets/landmarks/griffith_observatory/fountain_2.glb"),
	"grass_clump": preload("res://assets/landmarks/griffith_observatory/grass_clump.glb"),
	"lamp": preload("res://assets/landmarks/griffith_observatory/lamp.glb"),
	"lawns": preload("res://assets/landmarks/griffith_observatory/lawns.glb"),
	"observatory": preload("res://assets/landmarks/griffith_observatory/observatory.glb"),
	"plaza": preload("res://assets/landmarks/griffith_observatory/plaza.glb"),
	"rock": preload("res://assets/landmarks/griffith_observatory/rock.glb"),
	"rope": preload("res://assets/landmarks/griffith_observatory/rope.glb"),
	"telescope": preload("res://assets/landmarks/griffith_observatory/telescope.glb"),
	"terrace": preload("res://assets/landmarks/griffith_observatory/terrace.glb"),
	"terrain": preload("res://assets/landmarks/griffith_observatory/terrain.glb"),
	"tree_big": preload("res://assets/landmarks/griffith_observatory/tree_big.glb"),
	"tree_olive": preload("res://assets/landmarks/griffith_observatory/tree_olive.glb"),
	"tree_round": preload("res://assets/landmarks/griffith_observatory/tree_round.glb"),
}
const ScenePan := preload("res://modules/farm/scene_pan.gd")
const FarmCamera := preload("res://modules/farm/farm_camera.gd")
const P0LandmarkVisit := preload("res://modules/p0/p0_landmark_visit.gd")

var layout: Dictionary
var camera_pan := ScenePan.new()
var _paint: ShaderMaterial
var _camera: Camera3D
var _player: Node3D
var _rig: AvatarRig
var _nav_map: RID
var _path: PackedVector3Array = []
var _path_i := 0
var _focus := Vector3.ZERO
var _overview := false
var _closeup := false
var _running := false
var _hud: CanvasLayer
var _hud_root: Control
var _focus_button: AvatarFocusButton
var _environment: WorldEnvironment
var _saved_environment: Environment
var _camera_recenter: Tween
## Opened from the P0 map (q(295)): P0's HUD and stick instead of this scene's own controls; the camera follows.
var p0_visit: P0LandmarkVisit
## The landmark's voice (SGODOT-462): P0LandmarkVisit's, read by P0Runtime for the HUD's mic key and people drawer.
var voice_room: Node
## The P0 stick is walking the player: the run plays on (as Alcatraz's; 用户 0.3.2, 424 da2e9368).
var stick_moving := false
var _stick_still := 0.0   # seconds the stick has pushed without moving the player

func setup(args: Dictionary) -> void:
	if P0LandmarkVisit.wanted(args): p0_visit = P0LandmarkVisit.new(self, args)

func _ready() -> void:
	get_viewport().transparent_bg = false
	layout = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "layout.json"))
	var bounds: Array = layout.camera_bounds
	var rect := Vector4(bounds[0] - 2.0, bounds[1] + 2.0, bounds[2] - 1.5, bounds[3] + 2.5)
	_paint = ShaderMaterial.new()
	_paint.shader = preload("res://modules/landmark/shaders/landmark_paint.gdshader")
	_paint.set_shader_parameter("play_rect", rect)
	_paint.set_shader_parameter("fade", 7.0)
	_environment = WorldEnvironment.new()
	_environment.environment = Environment.new()
	_environment.environment.background_mode = Environment.BG_COLOR
	_environment.environment.background_color = Color("e3ebe8")
	_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.environment.ambient_light_color = Color("d5e4ee")
	_environment.environment.ambient_light_energy = 0.72
	add_child(_environment)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 0.0
	sun.directional_shadow_fade_start = 1.0
	sun.directional_shadow_pancake_size = 4.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.rotation_degrees = Vector3(-56, -34, 0)
	sun.light_color = Color(1.0, 0.965, 0.88)
	sun.light_energy = 0.98
	sun.shadow_opacity = 0.48
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 0.28
	sun.shadow_blur = 1.8
	add_child(sun)
	for asset in layout.unique:
		var node := _mesh_instance(str(asset))
		if asset in ["terrain", "lawns"]:
			var ground := ShaderMaterial.new()
			ground.shader = preload("res://modules/landmark/shaders/landmark_terrain.gdshader")
			ground.set_shader_parameter("meadow_texture", preload("res://assets/farm/art/meadow.png"))
			ground.set_shader_parameter("play_rect", rect)
			node.material_override = ground
		if asset == "city":
			# The distant city is meant to be seen: light haze only, no shadows.
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var far := ShaderMaterial.new()
			far.shader = preload("res://modules/landmark/shaders/landmark_city.gdshader")
			node.material_override = far
		add_child(node)
	for asset in layout.props:
		add_child(_batch(str(asset), layout.props[asset]))
	for water in layout.water:
		add_child(_water(water))
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
	if p0_visit == null: _build_controls()
	_update_camera()
	if p0_visit: p0_visit.start()

func _mesh_instance(asset: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = asset.to_pascal_case()
	node.mesh = _mesh(asset)
	node.material_override = _paint
	return node

func _mesh(asset: String) -> Mesh:
	var scene: PackedScene = ASSETS[asset]
	var root := scene.instantiate()
	var found := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D: found.push_front(root)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh
	root.free()
	return mesh

func _batch(asset: String, items: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh(asset)
	mm.instance_count = items.size()
	for i in items.size():
		var p: Array = items[i]
		var basis := Basis(Vector3.UP, float(p[3]))
		# Rope segments stretch along x to their span; everything else scales uniformly.
		basis = basis.scaled(Vector3(float(p[4]), 1, 1) if asset == "rope" else Vector3.ONE * float(p[4]))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(p[0], p[1], p[2])))
	var node := MultiMeshInstance3D.new()
	node.name = asset.to_pascal_case() + "Batch"
	node.multimesh = mm
	node.material_override = _paint
	return node

func _water(water: Dictionary) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var pos: Array = water.pos
	node.position = Vector3(pos[0], pos[1], pos[2])
	var r := float(water.radius)
	if water.kind == "jet":
		node.mesh = _jet_mesh(r, float(water.height))
		var jet := ShaderMaterial.new()
		jet.shader = preload("res://modules/landmark/shaders/landmark_jet.gdshader")
		node.material_override = jet
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return node
	var disc := CylinderMesh.new()
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 0.02
	disc.radial_segments = 40
	node.mesh = disc
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://modules/landmark/shaders/landmark_water.gdshader")
	mat.set_shader_parameter("radius", r)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

## Tiered spray like the design: stacked crystal tiers up the jet, then a falling sheet over the bowl.
func _jet_mesh(r: float, h: float) -> ArrayMesh:
	var profile := [Vector2(r * 1.05, 0.0), Vector2(r * 0.85, h * 0.18), Vector2(r * 0.42, h * 0.40), Vector2(r * 0.62, h * 0.43),
		Vector2(r * 0.30, h * 0.68), Vector2(r * 0.40, h * 0.71), Vector2(r * 0.12, h * 0.92), Vector2(0.01, h)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	for k in profile.size() - 1:
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var quad := [[profile[k], a0], [profile[k], a1], [profile[k + 1], a1], [profile[k + 1], a0]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var p: Vector2 = quad[idx][0]
				var a: float = quad[idx][1]
				st.set_uv(Vector2(a / TAU, p.y / h))
				st.set_normal(Vector3(cos(a), 0.35, sin(a)).normalized())
				st.add_vertex(Vector3(cos(a) * p.x, p.y, sin(a) * p.x))
	st.index()
	return st.commit()

func _build_navigation() -> void:
	var nav := NavigationMesh.new()
	var verts := PackedVector3Array()
	for v in layout.navigation.vertices: verts.append(Vector3(v[0], v[1], v[2]))
	nav.vertices = verts
	for poly in layout.navigation.polygons: nav.add_polygon(PackedInt32Array(poly))
	nav.cell_size = 0.25
	nav.cell_height = 0.1
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nav
	_nav_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_nav_map, true)
	NavigationServer3D.map_set_cell_size(_nav_map, 0.25)
	NavigationServer3D.map_set_cell_height(_nav_map, 0.1)
	add_child(region)
	# Entering the tree initially attaches a region to the world's default map.
	region.set_navigation_map(_nav_map)

func _spawn_player() -> void:
	_player = Node3D.new()
	add_child(_player)
	var s: Array = layout.spawn
	_player.position = Vector3(s[0], s[1], s[2])
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

func _animation(name: String) -> void:
	var ap := _rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation(name): ap.play(name)

func _step_walk(delta: float) -> void:
	if _path_i >= _path.size():
		if _running and not stick_moving:   # the stick's walk is the stick's to end (step_stick)
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

## Tap anywhere: walk to the nearest reachable point (never off the navigation cells).
func navigation_ready() -> bool:
	# The first map iteration can precede the region's asynchronous mesh sync.
	return NavigationServer3D.map_get_iteration_id(_nav_map) > 0 \
		and NavigationServer3D.map_get_closest_point_owner(_nav_map, _player.position).is_valid()

func walk_to_screen(point: Vector2) -> void:
	if not navigation_ready(): return
	var origin := _camera.project_ray_origin(point)
	var normal := _camera.project_ray_normal(point)
	var y := 0.0
	var goal := Vector3.ZERO
	for i in 3:
		var hit = Plane(Vector3.UP, y).intersects_ray(origin, normal)
		if hit == null: return
		goal = NavigationServer3D.map_get_closest_point(_nav_map, hit)
		y = goal.y
	walk_to(goal)

func walk_to(goal: Vector3) -> void:
	if not navigation_ready(): return
	_path = NavigationServer3D.map_get_path(_nav_map, _player.position, goal, true)
	_path_i = 0

func _build_controls() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	add_child(_hud)
	var safe := SafeAreaMargin.new()
	safe.name = "SafeArea"
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.theme = GameUi.theme()
	_hud.add_child(safe)
	_hud_root = Control.new()
	_hud_root.name = "Root"
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(_hud_root)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.add_theme_constant_override("separation", 8)
	_hud_root.add_child(header)
	var back := GameUi.button("arrow-left", "", L10n.text("Return to map"))
	back.name = "LandmarkBack"
	back.custom_minimum_size = Vector2(44, 44)
	back.pressed.connect(_leave)
	header.add_child(back)
	var title := GameUi.label(L10n.text("Griffith Observatory"), 15)
	title.name = "LandmarkTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(title)
	var overview := GameUi.button("map", L10n.text("Overview"), L10n.text("Overview"))
	overview.name = "LandmarkOverview"
	overview.pressed.connect(toggle_overview)
	header.add_child(overview)
	_focus_button = AvatarFocusButton.new()
	_hud_root.add_child(_focus_button)
	_focus_button.pressed.connect(recenter_on_player)

func _process(delta: float) -> void:
	_step_walk(delta)
	camera_pan.step(delta, _camera)
	if p0_visit and not _camera_recenter: _focus = _focus.lerp(_player.position, 1.0 - exp(-8.0 * delta))
	_update_camera()

func _update_camera() -> void:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.y / maxf(1.0, size.x)
	var width := (1536.0 / 58.0 if _overview else PHONE_WIDTH) / camera_pan.zoom
	if _closeup: width = 10.5
	_camera.size = width
	# The farm commits released pan and zoom-anchor offsets into a persistent center.
	if not camera_pan.active():
		_focus += camera_pan.offset
		camera_pan.offset = Vector3.ZERO
		camera_pan._raw_offset = Vector3.ZERO
	var target := _focus + camera_pan.offset
	if _closeup: target = Vector3(0.3, 0.8, -2.6)
	# In P0 the camera turns FarmCamera's yaw (14.5°) like every outdoor world (the user 11-07, 户外14.5ok); the Journey
	# visit keeps its square-on view.
	var yaw := deg_to_rad(FarmCamera.YAW_DEG) if p0_visit else 0.0
	var dir := Vector3(sin(yaw) * cos(deg_to_rad(PITCH)), sin(deg_to_rad(PITCH)), cos(yaw) * cos(deg_to_rad(PITCH)))
	_camera.position = target + dir * 40.0
	_camera.look_at(target, Vector3.UP)
	_camera.near = maxf(1.0, 40.0 - width * aspect * 0.9 - 8.0)
	_camera.far = 40.0 + width * aspect * 0.9 + 18.0
	if _focus_button:
		var viewport_rect := get_viewport().get_visible_rect()
		var area := _hud_root.get_global_rect()
		area.position.y += 52
		area.size.y = maxf(0, area.size.y - 52)
		_focus_button.update_indicator(_camera.unproject_position(_player.position + Vector3.UP * 0.7),
			viewport_rect, area, _camera.is_position_behind(_player.position))

func _input(event: InputEvent) -> void:
	if p0_visit == null: _handle_camera_input(event, false)

func _unhandled_input(event: InputEvent) -> void:
	if p0_visit == null: _handle_camera_input(event, true)

func _handle_camera_input(event: InputEvent, allow_start: bool) -> bool:
	if camera_pan.handle(event, _camera, allow_start):
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
	camera_pan.cancel()
	_focus += camera_pan.offset
	camera_pan.offset = Vector3.ZERO
	camera_pan._raw_offset = Vector3.ZERO
	_overview = false
	_closeup = false
	var start := _focus
	_camera_recenter = create_tween()
	_camera_recenter.tween_method(func(weight: float):
		_focus = start.lerp(_player.position, weight)
		_update_camera(), 0.0, 1.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# done, the P0 visit follows the player again (周瑜 on #870: it waited on a finished tween, never null)
	_camera_recenter.finished.connect(func(): _camera_recenter = null)

func toggle_overview() -> void:
	_stop_camera_recenter()
	camera_pan.reset()
	_closeup = false
	_overview = not _overview
	_focus = Vector3.ZERO if _overview else _player.position
	_update_camera()

func _leave() -> void:
	if AppRouter.top_instance() == self: AppRouter.handle_back()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		camera_pan.cancel()
		_stop_camera_recenter()

func suspend() -> void:
	_stop_camera_recenter()
	camera_pan.cancel()
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	for child in get_children():
		if child is CanvasLayer: child.visible = false
	_camera.current = false
	_saved_environment = _environment.environment
	_environment.environment = null

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	for child in get_children():
		if child is CanvasLayer: child.visible = true
	get_viewport().transparent_bg = false
	_environment.environment = _saved_environment
	_camera.make_current()
	_update_camera()
	if p0_visit: p0_visit.resume()

func _exit_tree() -> void:
	if p0_visit: p0_visit.clear()
	_stop_camera_recenter()
	camera_pan.cancel()
	if _nav_map.is_valid():
		NavigationServer3D.free_rid(_nav_map)
		_nav_map = RID()

# ---------------------------------------------------------------- P0 world (P0LandmarkVisit, q(295))
func p0_surface() -> String: return "visit"
## q(311) ② (不知火舞 on #988): what can hide a person from the camera — the props (telescopes, benches, lamps, fence
## posts, trees, bushes, rocks; not the grass clumps and flowers) and the buildings, each its mesh's box in its own space: [Transform3D, AABB, name]. Read once.
const _NOT_IN_THE_WAY := ["terrain", "lawns", "plaza", "terrace", "city", "grass_clump", "flowers"]   # ground, and what is too low to hide anyone
var _occluders: Array = []
func occluders() -> Array:
	if _occluders.is_empty():
		for asset in layout.unique:
			if str(asset) in _NOT_IN_THE_WAY: continue
			var m := _mesh(str(asset))
			if m != null: _occluders.append([Transform3D.IDENTITY, m.get_aabb(), str(asset)])
		for asset in layout.props:
			if str(asset) in _NOT_IN_THE_WAY: continue
			var m := _mesh(str(asset))
			if m == null: continue
			for i in (layout.props[asset] as Array).size():
				var q: Array = layout.props[asset][i]
				var basis := Basis(Vector3.UP, float(q[3]))
				basis = basis.scaled(Vector3(float(q[4]), 1, 1) if asset == "rope" else Vector3.ONE * float(q[4]))
				_occluders.append([Transform3D(basis, Vector3(q[0], q[1], q[2])), m.get_aabb(), "%s_%d" % [asset, i]])
	return _occluders
## q(311) ④: the arrival cover waits for the room to say where the player stands (P0LandmarkVisit.landing).
func p0_landing_pending() -> bool: return p0_visit != null and p0_visit.landing_pending()
func p0_frame(_v: Dictionary, dt: float) -> void: p0_visit.frame(dt)
func p0_tap(screen: Vector2) -> void: p0_visit.tap(screen)
func p0_recenter() -> void: recenter_on_player()
func p0_zoom_end() -> void: pass

func p0_joystick(v: Vector2) -> void:
	p0_visit.stick = v
	if v != Vector2.ZERO: _path = PackedVector3Array()   # the stick takes over from a tap's walk

## A pinch: about the player, who stays followed.
func p0_zoom(f: float, _at := Vector2.INF) -> void:
	_stop_camera_recenter()
	camera_pan.reset(clampf(camera_pan.zoom * f, camera_pan.min_zoom, camera_pan.max_zoom))
	_overview = false
	_update_camera()

func p0_dev(step: Array) -> bool: return p0_visit.dev(step)

## Dev: a named point to walk the lawn by (李元芳's frame-rate route), INF for none; the player stood there.
const DEV_POINTS := {"opening": Vector3(-1.34, 0.03, 6.64), "lawn_west": Vector3(-9.0, 0.0, 4.0),
	"lawn_east": Vector3(9.0, 0.0, 4.0), "building": Vector3(0.3, 0.0, -2.0),
	# the walkable corners: the camera's edge check (q(295) 14.5°)
	"sw": Vector3(-12.0, 0.0, 9.8), "se": Vector3(12.2, 0.0, 9.8), "nw": Vector3(-12.0, 0.0, -7.9), "ne": Vector3(12.2, 0.0, -7.9)}

func dev_point(n: String) -> Vector3:
	return DEV_POINTS.get(n, Vector3.INF)

func dev_stand(at: Vector3) -> void:
	_path = PackedVector3Array()
	_player.position = NavigationServer3D.map_get_closest_point(_nav_map, at) if navigation_ready() else at
	_focus = _player.position

func player_position() -> Vector3: return _player.position
## The walkable ground (P0LandmarkVisit: the others stood on it, SGODOT-462).
func nav_map() -> RID: return _nav_map
## The way out (q(295) ④: a door prompt and Map, 不知火舞 on #870): on the path south of the spawn, where the visit
## came up; snapped to the walkable ground once the navigation is ready.
const EXIT := Vector3(-1.34, 0.0, 9.6)
var _exit := Vector3.INF

func exit_position() -> Vector3:
	if _exit == Vector3.INF and navigation_ready(): _exit = NavigationServer3D.map_get_closest_point(_nav_map, EXIT)
	return _exit if _exit != Vector3.INF else EXIT
func walking() -> bool: return _path_i < _path.size()

## The stick (P0LandmarkVisit.stick_step): the player runs while it is pushed, along an edge at the slide's speed;
## held against one it cannot pass, it stands after P0Actor.PUSH_IDLE_S (SGODOT-306, the slide spec).
func step_stick(v: Vector2, dt: float) -> void:
	if not navigation_ready(): return
	var went := P0LandmarkVisit.stick_step(_player, _nav_map, _camera, WALK_SPEED, v, dt)
	stick_moving = went >= 0.0
	if not stick_moving:
		_stick_still = 0.0
		P0LandmarkVisit.run_speed(_rig, 1.0)
		if _running and not walking():
			_running = false
			_animation("idle")
		return
	_stick_still = _stick_still + dt if went < PlayerMover.STUCK_RATIO else 0.0
	var run := _stick_still < P0Actor.PUSH_IDLE_S
	if run != _running:
		_running = run
		_animation("run" if run else "idle")
	P0LandmarkVisit.run_speed(_rig, went if run and went >= PlayerMover.STUCK_RATIO else 1.0)
