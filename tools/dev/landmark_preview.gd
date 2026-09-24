extends Node3D
## Isolated landmark art review; launch with open_landmark_art.command to disable network boot.
## Blender GLBs + layout.json, walkable only on
## the exported navigation cells, camera clamped to the play area. No Net session or save writes.
##
## LANDMARK_CAPTURE=<dir> writes overview/phone screenshots (+ a side-by-side with the design) and quits.

const ROOT := "res://assets/landmarks/griffith_observatory/"
const DESIGN := "res://docs/design/landmark-scenes-2026-09-23/griffith_observatory_scene_v1.png"
const PITCH := 45.0
const WALK_SPEED := 2.3
const PHONE_WIDTH := 7.0 # ortho width of one phone screen (m), like the farm camera

var layout: Dictionary
var _paint: ShaderMaterial
var _camera: Camera3D
var _player: Node3D
var _rig: AvatarRig
var _nav_map: RID
var _path: PackedVector3Array = []
var _path_i := 0
var _focus := Vector3.ZERO
var _pan := Vector2.ZERO
var _zoom := 1.0
var _dragging := false
var _drag_moved := 0.0
var _overview := false
var _closeup := false
var _running := false
var _touches: Dictionary = {}
var _pinched := false
var _hud: CanvasLayer
var _review_buttons: Array[Button] = []
var _state_elapsed := 0.0
var _touch_count := 0
var _last_input := ""
var _check_failed := false
var _frame_samples: Array[float] = []

func _ready() -> void:
	get_viewport().transparent_bg = false
	layout = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "layout.json"))
	var bounds: Array = layout.camera_bounds
	var rect := Vector4(bounds[0] - 2.0, bounds[1] + 2.0, bounds[2] - 1.5, bounds[3] + 2.5)
	_paint = ShaderMaterial.new()
	_paint.shader = preload("res://modules/landmark/shaders/landmark_paint.gdshader")
	_paint.set_shader_parameter("play_rect", rect)
	_paint.set_shader_parameter("fade", 7.0)
	var farm := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	var env := WorldEnvironment.new()
	env.environment = farm.get_node("WorldEnvironment").environment.duplicate()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("e3ebe8")
	env.environment.ambient_light_color = Color("d5e4ee")
	env.environment.ambient_light_energy = 0.72
	add_child(env)
	var sun := farm.get_node("Sun").duplicate() as DirectionalLight3D
	sun.directional_shadow_max_distance = 0.0
	# Warmer afternoon key light like the design.
	sun.rotation_degrees = Vector3(-56, -34, 0)
	sun.light_color = Color(1.0, 0.965, 0.88)
	sun.light_energy = 0.98
	sun.shadow_opacity = 0.48
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 0.28
	sun.shadow_blur = 1.8
	add_child(sun)
	farm.free()
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
	_spawn_player()
	_build_review_controls()
	var capture := OS.get_environment("LANDMARK_CAPTURE")
	if not capture.is_empty():
		_capture.call_deferred(capture)

func _mesh_instance(asset: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = asset.to_pascal_case()
	node.mesh = _mesh(asset)
	node.material_override = _paint
	return node

func _mesh(asset: String) -> Mesh:
	var scene := load(ROOT + asset + ".glb") as PackedScene
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
	add_child(region)
	_nav_map = get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(_nav_map, 0.25)
	NavigationServer3D.map_set_cell_height(_nav_map, 0.1)

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

func _process(delta: float) -> void:
	_step_walk(delta)
	_frame_samples.append(delta * 1000.0)
	if _frame_samples.size() > 180: _frame_samples.pop_front()
	_state_elapsed += delta
	var size := get_viewport().get_visible_rect().size
	var aspect := size.y / maxf(1.0, size.x)
	var width := PHONE_WIDTH / _zoom
	if _overview: width = (1536.0 / 58.0) / _zoom
	if _closeup: width = 10.5
	_camera.size = width
	var bounds: Array = layout.camera_bounds
	var depth := width * aspect / sin(deg_to_rad(PITCH))
	var target := _focus + Vector3(_pan.x, 0, _pan.y)
	if _overview: target = Vector3(clampf(_pan.x,bounds[0],bounds[1]),0,clampf(_pan.y,bounds[2],bounds[3]))
	elif _closeup: target = Vector3(0.3, 0.8, -2.6)
	else:
		target.x = clampf(target.x, bounds[0], bounds[1])
		target.z = clampf(target.z, bounds[2], bounds[3])
		_pan = Vector2(target.x - _focus.x, target.z - _focus.z)
	var dir := Vector3(0, sin(deg_to_rad(PITCH)), cos(deg_to_rad(PITCH)))
	_camera.position = target + dir * 40.0
	_camera.look_at(target, Vector3.UP)
	# Keep the orthographic shadow volume close to the actual scene, as on the farm.
	_camera.near = maxf(1.0, 40.0 - width * aspect * 0.9 - 8.0)
	_camera.far = 40.0 + width * aspect * 0.9 + 18.0
	# Sample after camera updates so touch automation observes one coherent frame.
	if _state_elapsed > 0.3 and OS.has_feature("journey_device_qa"):
		_state_elapsed = 0.0
		_write_review_state("user://landmark-review-state.json")

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

## Tap anywhere: walk to the nearest reachable point (never off the navigation cells).
func walk_to_screen(point: Vector2) -> void:
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
	_path = NavigationServer3D.map_get_path(_nav_map, _player.position, goal, true)
	_path_i = 0

func _build_review_controls() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = preload("res://assets/ui/app_theme.tres")
	_hud.add_child(root)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.position = Vector2(-128, -64)
	row.size = Vector2(256, 44)
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	for spec in [["Recenter", "回到角色"], ["Overview", "总览"]]:
		var button := Button.new()
		button.name = spec[0]
		button.text = spec[1]
		button.custom_minimum_size = Vector2(124,44)
		button.add_theme_font_size_override("font_size",16)
		row.add_child(button)
		_review_buttons.append(button)
		button.pressed.connect(func():
			_touch_count += 1
			_last_input = spec[0]
			if spec[0] == "Recenter":
				_overview = false
				_focus = _player.position
				_pan = Vector2.ZERO
			else:
				_overview = not _overview
				_pan = Vector2.ZERO
				_zoom = 1.0)
	var zoom_row := VBoxContainer.new()
	zoom_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	zoom_row.position = Vector2(-60,-48)
	root.add_child(zoom_row)
	for spec in [["ZoomIn", "+", 1.15],["ZoomOut", "−", 1.0/1.15]]:
		var button := Button.new()
		button.name = spec[0]
		button.text = spec[1]
		button.custom_minimum_size = Vector2(44,44)
		zoom_row.add_child(button)
		_review_buttons.append(button)
		button.pressed.connect(func():
			_touch_count += 1
			_last_input = spec[0]
			_zoom = clampf(_zoom * spec[2],0.65,1.7))

func _pan_pixels(delta: Vector2) -> void:
	var m := _camera.size / get_viewport().get_visible_rect().size.x
	_pan -= Vector2(delta.x*m,delta.y*m/sin(deg_to_rad(PITCH)))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touches.is_empty():
				_drag_moved = 0.0
				_pinched = false
			_touches[event.index] = event.position
			if _touches.size() > 1: _pinched = true
		else:
			if not _touches.has(event.index): return
			_touches.erase(event.index)
			if _touches.is_empty():
				_touch_count += 1
				_last_input = "pinch" if _pinched else "drag" if _drag_moved >= 8.0 else "walk"
				if not _pinched and _drag_moved < 8.0: walk_to_screen(event.position)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		if _touches.size() == 2:
			var keys := _touches.keys()
			var old_distance: float = _touches[keys[0]].distance_to(_touches[keys[1]])
			_touches[event.index] = event.position
			var new_distance: float = _touches[keys[0]].distance_to(_touches[keys[1]])
			if old_distance > 1.0:
				_zoom = clampf(_zoom * new_distance / old_distance,0.65,1.7)
		else:
			_touches[event.index] = event.position
			_drag_moved += event.relative.length()
			_pan_pixels(event.relative)
	elif event is InputEventMouseButton and not OS.has_feature("mobile") and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_moved = 0.0
		else:
			_dragging = false
			if _drag_moved < 8.0: walk_to_screen(event.position)
	elif event is InputEventMouseMotion and _dragging:
		_drag_moved += event.relative.length()
		_pan_pixels(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_zoom = clampf(_zoom * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.9),0.65,1.7)
	elif event is InputEventMagnifyGesture:
		_zoom = clampf(_zoom * event.factor,0.65,1.7)

func _review_state() -> Dictionary:
	var buttons: Array = []
	for b in _review_buttons:
		var r := b.get_global_rect()
		buttons.append({"name":b.name,"text":b.text,"rect":[r.position.x,r.position.y,r.size.x,r.size.y]})
	var vp := get_viewport().get_visible_rect().size
	var pos := _player.position
	var screen := _camera.unproject_position(pos)
	var path_left := _path.size()-_path_i
	var targets := {}
	for spec in [["garden",Vector3(-3,0,3)],["main_terrace",Vector3(-0.4,0.5,-1.8)],["west_terrace",Vector3(-9.1,0.5,-3)],["cafe_terrace",Vector3(10.2,0.5,0.1)]]:
		var point := NavigationServer3D.map_get_closest_point(_nav_map,spec[1])
		var pixel := _camera.unproject_position(point)
		targets[spec[0]]={"world":[point.x,point.y,point.z],"screen":[pixel.x,pixel.y]}
	var ap := _rig.get_node_or_null("AnimationPlayer") as AnimationPlayer

	var frames := _frame_samples.duplicate()
	frames.sort()
	return {"buttons":buttons,"walk_targets":targets,"animation":ap.current_animation if ap else "","viewport":[vp.x,vp.y],"window":[DisplayServer.window_get_size().x,DisplayServer.window_get_size().y],
		"player":[pos.x,pos.y,pos.z],"player_screen":[screen.x,screen.y],"path_remaining":path_left,
		"camera":[_camera.position.x,_camera.position.y,_camera.position.z],"zoom":_zoom,"overview":_overview,
		"touch_count":_touch_count,"last_input":_last_input,"network_booted":Net.booted_once,"network_booting":Net.booting,
		"navigation_distance":pos.distance_to(NavigationServer3D.map_get_closest_point(_nav_map,pos)),
		"frame_p95_ms":frames[int(frames.size()*.95)] if not frames.is_empty() else 0,
		"draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"rendered_primitives":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)}

func _write_review_state(path: String) -> void:
	var f := FileAccess.open(path,FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(_review_state(),"  "))

func _capture(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for f in 90: await get_tree().process_frame
	var mode := OS.get_environment("LANDMARK_VIEW")
	if mode == "checks":
		await _check_navigation_and_camera(dir)
	elif mode == "closeup":
		_closeup = true
		_hud.hide()
		for f in 60: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("closeup.png"))
	elif mode == "overview":
		_overview = true
		_hud.hide()
		for f in 30: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var shot := get_viewport().get_texture().get_image()
		shot.save_png(dir.path_join("overview.png"))
		var design := Image.load_from_file(ProjectSettings.globalize_path(DESIGN))
		design.resize(shot.get_width(), shot.get_height(), Image.INTERPOLATE_LANCZOS)
		var sheet := Image.create(shot.get_width() * 2 + 16, shot.get_height(), false, Image.FORMAT_RGB8)
		sheet.fill(Color.WHITE)
		design.convert(Image.FORMAT_RGB8)
		shot.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(design, Rect2i(Vector2i.ZERO, design.get_size()), Vector2i.ZERO)
		sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()), Vector2i(shot.get_width() + 16, 0))
		sheet.save_png(dir.path_join("comparison.png"))
	else:
		# Phone view: walk to the far corner to prove the boundary holds, then capture.
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("phone-spawn.png"))
		walk_to(NavigationServer3D.map_get_closest_point(_nav_map, Vector3(40, 0, 40)))
		for f in 600:
			await get_tree().process_frame
			if _path_i >= _path.size(): break
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("phone-boundary.png"))
		print("LANDMARK_BOUNDARY ", _player.position)
	_write_review_state(dir.path_join("metrics.json"))
	print("LANDMARK_CAPTURE_DONE")
	get_tree().quit(1 if _check_failed else 0)

func _check_navigation_and_camera(dir: String) -> void:
	var checks: Array = []
	var start := _player.position
	var initial_camera := _camera.position
	var initial_focus := _focus
	var targets := {
		"garden":Vector3(-3.0,0,3.0),
		"main_stairs_and_terrace":Vector3(-0.4,0.5,-1.8),
		"west_terrace":Vector3(-9.1,0.5,-3.0),
		"cafe_terrace":Vector3(10.2,0.5,0.1),
	}
	for label in targets:
		_player.position = start
		var desired: Vector3 = targets[label]
		var goal := NavigationServer3D.map_get_closest_point(_nav_map,desired)
		walk_to(goal)
		var count := _path.size()
		var travelled := 0.0
		var outside := 0.0
		for tick in 2400:
			var before := _player.position
			_step_walk(1.0/60.0)
			travelled += _player.position.distance_to(before)
			outside = maxf(outside,_player.position.distance_to(NavigationServer3D.map_get_closest_point(_nav_map,_player.position)))
			if _path_i >= _path.size(): break
		var error := _player.position.distance_to(goal)
		checks.append({"name":label,"passed":count>1 and error<0.15 and outside<0.1 and goal.distance_to(desired)<0.7,
			"path_points":count,"travel_m":travelled,"arrival_error_m":error,"max_off_nav_m":outside,"snap_m":goal.distance_to(desired)})
		await get_tree().process_frame
		checks.append({"name":label+"_camera_stays_free","passed":_camera.position.distance_to(initial_camera)<0.001})
	_player.position = start
	var border_goal := NavigationServer3D.map_get_closest_point(_nav_map,Vector3(40,0,40))
	walk_to(border_goal)
	for tick in 2400:
		_step_walk(1.0/60.0)
		if _path_i >= _path.size(): break
	checks.append({"name":"outside_tap_stays_on_navigation","passed":_player.position.distance_to(NavigationServer3D.map_get_closest_point(_nav_map,_player.position))<0.1})
	_player.position = start
	_path.clear()
	_path_i = 0
	_focus = initial_focus
	_pan = Vector2.ZERO
	var camera_before := _camera.position
	var player_before := _player.position
	_pan_pixels(Vector2(100,50))
	await get_tree().process_frame
	checks.append({"name":"drag_changes_camera_without_moving_player","passed":_camera.position.distance_to(camera_before)>0.2 and _player.position.distance_to(player_before)<0.001})
	_pan = Vector2.ZERO
	var touch_down := InputEventScreenTouch.new()
	touch_down.pressed = true
	touch_down.index = 0
	touch_down.position = Vector2(100,100)
	_unhandled_input(touch_down)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(160,140)
	drag.relative = Vector2(60,40)
	_unhandled_input(drag)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = drag.position
	up.pressed = false
	_unhandled_input(up)
	checks.append({"name":"touch_drag_release_does_not_walk","passed":_path.is_empty() and _last_input=="drag"})
	checks.append({"name":"offline_preview_never_boots_network","passed":not Net.booted_once and not Net.booting})
	_pan = Vector2.ZERO
	await get_tree().process_frame
	var passed := checks.all(func(c): return bool(c.passed))
	_check_failed = not passed
	FileAccess.open(dir.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks},"  "))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("checked-phone.png"))
	print("LANDMARK_CHECKS ",JSON.stringify({"passed":passed,"count":checks.size()}))
