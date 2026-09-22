class_name FishingPresentation
extends Node3D
## Shared local/remote pose rendering; only server-confirmed state can show a catch.

var remote := false
var remote_state: Dictionary = {}
var panel: FishingPanel
var actor: Node3D
var rig: AvatarRig
var camera: Camera3D
var bobber_position := Vector3.ZERO
var rod_tip := Vector3.ZERO
var hand_position := Vector3.ZERO
var line_points := PackedVector3Array()
var rod_points := PackedVector3Array()
var pull := 0.0
var _skeleton: Skeleton3D
var _animation: AnimationPlayer
var _poses: Array[Transform3D] = []
var _bones: Dictionary = {}
var _hidden: Array = []
var _rig_transform: Transform3D
var _camera_transform: Transform3D
var _camera_size := 6.0
var _camera_offset := 0.0
var _camera_near := 0.05
var _camera_far := 32.0
var _forward := Vector3.FORWARD
var _side := Vector3.LEFT
var _landing := Vector3.ZERO
var _rod := ImmediateMesh.new()
var _line := ImmediateMesh.new()
var _rod_material: StandardMaterial3D
var _line_material: StandardMaterial3D
var _bobber: Node3D
var _reel: Node3D
var _crank: Node3D
var _crank_angle := 0.0
var _catch: Node3D
var _catch_material: StandardMaterial3D
var _splash: MeshInstance3D
var _splash_material: StandardMaterial3D
var _water: FishingWater
var _clock := 0.0
var _phase := ""
var _phase_age := 0.0
var _cast_age := 10.0
var _splash_age := 10.0
var _finished := false

func configure(value: FishingPanel, player: Node3D, avatar: AvatarRig, cam: Camera3D, obscuring_ui: Array) -> void:
	panel = value
	panel.cast_started.connect(_start_cast)
	actor = player
	rig = avatar
	camera = cam
	process_priority = 50
	_rig_transform = rig.transform
	_camera_transform = cam.transform
	_camera_size = cam.size
	_camera_offset = cam.v_offset
	_camera_near = cam.near
	_camera_far = cam.far
	for node in obscuring_ui:
		if is_instance_valid(node):
			_hidden.append({"node": node, "visible": node.visible})
			node.hide()
	_landing = panel.landing + Vector3.UP * 0.11
	_prepare_actor()
	_water = get_parent().find_child(panel.site_id, true, false) as FishingWater
	_build()
	_frame_camera(1.0)
	step(0.0)

func configure_remote(state: Dictionary, player: Node3D, avatar: AvatarRig, cam: Camera3D) -> void:
	remote = true
	remote_state = state
	actor = player
	rig = avatar
	camera = cam
	process_priority = 110
	_rig_transform = rig.transform
	_landing = Vector3(state.target[0], 0.11, state.target[1])
	_cast_age = float(state.get("cast_age", 10))
	_prepare_actor()
	_build()
	step(0)

func _prepare_actor() -> void:
	_forward = (_landing - actor.global_position) * Vector3(1, 0, 1)
	_forward = _forward.normalized()
	_side = Vector3.UP.cross(_forward).normalized()
	rig.global_basis = Basis(Vector3.UP, atan2(_forward.x, _forward.z))
	_skeleton = rig.skeleton
	_animation = rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _animation: _animation.pause()
	if _skeleton:
		for index in _skeleton.get_bone_count():
			_poses.append(_skeleton.get_bone_pose(index))
			_bones[str(_skeleton.get_bone_name(index))] = index

func _start_cast() -> void:
	_cast_age = 0

func _build() -> void:
	_rod_material = StandardMaterial3D.new()
	_rod_material.vertex_color_use_as_albedo = true
	_rod_material.roughness = 0.65
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.albedo_color = Color("f5e9c9")
	_line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for spec in [[_rod, _rod_material, "Rod"], [_line, _line_material, "FishingLine"]]:
		var mesh := MeshInstance3D.new()
		mesh.name = spec[2]
		mesh.mesh = spec[0]
		mesh.material_override = spec[1]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
	_bobber = Node3D.new()
	_bobber.name = "Float"
	add_child(_bobber)
	_oval(_bobber, Vector3(0.07, 0.11, 0.07), Vector3.ZERO, Color("fff2d1"))
	_oval(_bobber, Vector3(0.055, 0.06, 0.055), Vector3(0, 0.075, 0), Color("db654f"))
	_reel = Node3D.new()
	_reel.name = "FishingReel"
	add_child(_reel)
	_oval(_reel, Vector3(0.07, 0.045, 0.07), Vector3.ZERO, Color("706c52"))
	_oval(_reel, Vector3(0.055, 0.05, 0.055), Vector3.ZERO, Color("c5aa6d"))
	_crank = Node3D.new()
	_reel.add_child(_crank)
	_oval(_crank, Vector3(0.018, 0.025, 0.018), Vector3(0.035, 0.09, 0), Color("414e44"))
	_catch = Node3D.new()
	_catch.name = "LandedFish"
	add_child(_catch)
	_catch_material = _oval(_catch, Vector3(0.23, 0.10, 0.07), Vector3.ZERO, Color("a7c1a5")).material_override
	_oval(_catch, Vector3(0.07, 0.13, 0.045), Vector3(0.24, 0, 0), Color("91b8aa"))
	_oval(_catch, Vector3.ONE * 0.018, Vector3(-0.14, 0.025, 0.065), Color("233f3d"))
	_catch.hide()
	_splash = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.11
	torus.outer_radius = 0.13
	torus.rings = 28
	torus.ring_segments = 6
	_splash.mesh = torus
	_splash_material = StandardMaterial3D.new()
	_splash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_splash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_splash_material.albedo_color = Color("e6f4e5")
	_splash.material_override = _splash_material
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)

func _oval(parent: Node3D, radii: Vector3, position_at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1
	sphere.height = 2
	sphere.radial_segments = 12
	sphere.rings = 6
	mesh.mesh = sphere
	mesh.scale = radii
	mesh.position = position_at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _process(dt: float) -> void:
	if remote:
		if not _finished: step(minf(dt, 0.1))
		return
	if _finished or not is_instance_valid(panel): return
	if not panel.visible:
		finish()
		return
	step(minf(dt, 0.1))

func step(dt: float) -> void:
	if _finished or not is_instance_valid(actor) or not is_instance_valid(camera): return
	_clock += dt
	_phase_age += dt
	_cast_age += dt
	_splash_age += dt
	var current_phase := str(remote_state.get("phase", "waiting")) if remote else panel.phase
	var held := bool(remote_state.get("held", false)) if remote else panel.held
	var model: Dictionary = remote_state if remote else panel.model
	var result: Dictionary = remote_state if remote else panel.session.state.get("fishing", {}).get("last", {})
	if _phase != current_phase:
		_phase = current_phase
		_phase_age = float(remote_state.get("age", 0)) if remote else 0
		if _phase == "casting": _cast_age = float(remote_state.get("cast_age", 0)) if remote else 0
		if _phase == "hook": _splash_age = 0
		if _phase == "playing": _splash_age = 0
		if _phase == "error": _cast_age = 10
	var fighting := _phase in ["playing", "settling"]
	if fighting and held: _crank_angle += dt * 10.0
	var tension := 1.0 if fighting and held else 0.12 if fighting else 0.0
	pull = lerpf(pull, tension, 1.0 - exp(-dt * 12.0))
	var elevation := lerpf(0.35, 1.16, pull)
	var sweep := sin(_clock * 2.4) * 0.025
	if _phase in ["ready", "error", "result"]: elevation = 0.85
	if _cast_age < 0.95:
		if _cast_age < 0.25: elevation = lerpf(0.85, 1.85, _cast_age / 0.25)
		else: elevation = lerpf(1.85, 0.35, smoothstep(0, 1, (_cast_age - 0.25) / 0.45))
	if _phase == "playing" and _phase_age < 0.3: elevation += sin(_phase_age / 0.3 * PI) * 0.45
	var grip_local := Vector3(-0.15, 1.04 + pull * 0.16, 0.38 - pull * 0.02)
	if _cast_age < 0.25: grip_local.z -= sin(_cast_age / 0.25 * PI * 0.5) * 0.16
	var grip := rig.to_global(grip_local)
	var rod_direction := (_forward * cos(elevation) + Vector3.UP * sin(elevation) + _side * sweep).normalized()
	_pose_body(grip, rod_direction, dt)
	# The grip follows the posed hand, so the pole never floats beside an idle arm.
	var wrist := _bones.get("Wrist_R", -1) as int
	if _skeleton and wrist >= 0: grip = _skeleton.to_global(_global_pose(wrist).origin) + _forward * 0.065
	hand_position = grip
	_reel.global_position = grip - rod_direction * 0.12 + _side * 0.075
	_reel.global_basis = Basis(Quaternion(Vector3.UP, _side))
	_crank.rotation.y = _crank_angle
	var pole := PackedVector3Array()
	for i in 13:
		var t := float(i) / 12.0
		var bend := (0.03 + pull * 0.50 + (0.045 * sin(_clock * 11.0) if fighting else 0.0)) * t * t
		pole.append(grip + rod_direction * 1.8 * t + (_forward - Vector3.UP * 0.75) * bend)
	rod_points = pole
	rod_tip = pole[-1]
	_draw_rod(pole)
	var active_float := _phase in ["casting", "waiting", "hook", "playing", "settling"]
	bobber_position = _landing + Vector3.UP * sin(_clock * 3.5) * 0.025
	if fighting:
		bobber_position += _side * (float(model.get("fish", 0.5)) - 0.5) * 0.75
		bobber_position -= _forward * pull * 0.20
		bobber_position.y += sin(_clock * 10.0) * 0.025
	if _phase == "hook": bobber_position.y -= 0.07 + sin(_clock * 16) * 0.04
	if _cast_age < 0.9:
		var flight := clampf((_cast_age - 0.25) / 0.65, 0, 1)
		bobber_position = grip.lerp(_landing, flight) + Vector3.UP * sin(flight * PI) * 1.2
		if _cast_age - dt < 0.85 and _cast_age >= 0.85: _splash_age = 0
	var landed: bool = _phase == "result" and model.get("outcome") == "caught" and result.get("outcome") == "caught"
	if landed and _phase_age < 1.25:
		active_float = true
		var lift := smoothstep(0, 1, _phase_age / 1.25)
		bobber_position = _landing.lerp(grip + Vector3.UP * 0.25, lift) + Vector3.UP * sin(lift * PI) * 1.7
		_catch.global_position = bobber_position - Vector3.UP * 0.15
		_catch.rotation = Vector3(0, _clock * 3.0, sin(_clock * 17) * 0.3)
		var id := str(result.get("fish_id", ""))
		var tier := int(FishingModel.fish(id).get("tier", 1))
		_catch_material.albedo_color = [Color("a7c1a5"), Color("71aaba"), Color("e4ba63"), Color("bcb8df")][clampi(tier - 1, 0, 3)]
	_catch.visible = landed and _phase_age < 1.25
	_bobber.visible = active_float and not _catch.visible
	_bobber.global_position = bobber_position
	if not active_float: bobber_position = rod_tip - Vector3.UP * 0.3
	_draw_line(rod_tip, bobber_position, 0.025 if pull > 0.5 else 0.22)
	_splash.visible = _splash_age < 0.75 and active_float
	_splash.global_position = Vector3(bobber_position.x, 0.085, bobber_position.z)
	_splash.scale = Vector3.ONE * (0.5 + _splash_age * 4.0)
	_splash_material.albedo_color.a = maxf(0, 0.8 - _splash_age)
	if is_instance_valid(_water): _water.interact(bobber_position, 0.7 if fighting else 0.3 if active_float and _cast_age >= 0.85 else 0.0)
	_frame_camera(1.0 - exp(-dt * 7.0))
	if not remote: panel.anchor_gauge(camera.unproject_position(_landing))

func _global_pose(bone: int) -> Transform3D:
	var pose := _skeleton.get_bone_pose(bone)
	var parent := _skeleton.get_bone_parent(bone)
	while parent >= 0:
		pose = _skeleton.get_bone_pose(parent) * pose
		parent = _skeleton.get_bone_parent(parent)
	return pose

func _rotate_global(bone: int, rotation: Basis) -> void:
	var parent := _skeleton.get_bone_parent(bone)
	var parent_basis := _global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * rotation).get_rotation_quaternion().normalized())

func _aim(bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < 0.00001 or to.length_squared() < 0.00001: return
	_rotate_global(bone, Basis(Quaternion(from.normalized(), to.normalized())) * _global_pose(bone).basis)

func _arm(side: String, target_world: Vector3) -> void:
	var upper: int = _bones.get("Shoulder_" + side, -1)
	var elbow: int = _bones.get("Elbow_" + side, -1)
	var wrist: int = _bones.get("Wrist_" + side, -1)
	if mini(upper, mini(elbow, wrist)) < 0: return
	var a := _global_pose(upper).origin
	var b := _global_pose(elbow).origin
	var c := _global_pose(wrist).origin
	var goal := _skeleton.to_local(target_world)
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var direction := (goal - a).normalized()
	var distance := clampf(goal.distance_to(a), 0.02, l1 + l2 - 0.003)
	var along := (l1 * l1 - l2 * l2 + distance * distance) / (2.0 * distance)
	var pole := rig.global_basis * Vector3(-0.8 if side == "R" else 0.8, -0.7, -0.2)
	pole = _skeleton.global_basis.inverse() * pole
	pole = (pole - direction * pole.dot(direction)).normalized()
	var bend := a + direction * along + pole * sqrt(maxf(0.00001, l1 * l1 - along * along))
	_aim(upper, b - a, bend - a)
	b = _global_pose(elbow).origin
	c = _global_pose(wrist).origin
	_aim(elbow, c - b, goal - b)
	var finger: int = _bones.get("MiddleFinger1_" + side, -1)
	if finger >= 0:
		var palm := _global_pose(finger).origin - _global_pose(wrist).origin
		_aim(wrist, palm, _skeleton.global_basis.inverse() * _forward)

func _pose_body(grip: Vector3, direction: Vector3, _dt: float) -> void:
	if not _skeleton: return
	if _animation and _animation.is_playing(): _animation.pause()
	for index in _poses.size():
		_skeleton.set_bone_pose_position(index, _poses[index].origin)
		_skeleton.set_bone_pose_rotation(index, _poses[index].basis.get_rotation_quaternion())
	var chest: int = _bones.get("Chest_M", -1)
	if chest >= 0:
		var lean := -pull * 0.26 + sin(_clock * 2.8) * 0.018
		if _cast_age < 0.65: lean += sin(_cast_age / 0.65 * TAU) * 0.13
		_rotate_global(chest, Basis(Vector3.RIGHT, lean) * _global_pose(chest).basis)
	_arm("R", grip - _forward * 0.065)
	var reel := grip - direction * 0.12 + _side * 0.165
	reel += Basis(Quaternion(Vector3.UP, _side)) * Basis(Vector3.UP, _crank_angle) * Vector3(0.035, 0, 0)
	_arm("L", reel - _forward * 0.065)
	for name in _bones:
		if str(name).contains("Finger2_"):
			var index: int = _bones[name]
			_skeleton.set_bone_pose_rotation(index, (_poses[index].basis * Basis(Vector3.FORWARD, 0.7 if str(name).ends_with("R") else -0.7)).get_rotation_quaternion())

func _draw_rod(points: PackedVector3Array) -> void:
	_rod.clear_surfaces()
	_rod.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in points.size() - 1:
		var direction := (points[index + 1] - points[index]).normalized()
		var right := direction.cross(Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.95 else Vector3.UP).normalized()
		var up := direction.cross(right)
		var radius := lerpf(0.027, 0.006, float(index) / (points.size() - 1))
		for side in 8:
			var a := (right * cos(side * TAU / 8) + up * sin(side * TAU / 8)) * radius
			var b := (right * cos((side + 1) * TAU / 8) + up * sin((side + 1) * TAU / 8)) * radius
			var color := Color("544e3c") if index < 2 else Color("b88a51")
			for vertex in [points[index] + a, points[index + 1] + a, points[index + 1] + b, points[index] + a, points[index + 1] + b, points[index] + b]:
				_rod.surface_set_color(color)
				_rod.surface_set_normal(a.normalized())
				_rod.surface_add_vertex(to_local(vertex))
	_rod.surface_end()

func _draw_line(from: Vector3, to: Vector3, slack: float) -> void:
	line_points.clear()
	for i in 21:
		var t := float(i) / 20.0
		line_points.append(from.lerp(to, t) - Vector3.UP * sin(t * PI) * slack)
	_line.clear_surfaces()
	_line.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in line_points.size() - 1:
		var direction := (line_points[i + 1] - line_points[i]).normalized()
		var edge := direction.cross(camera.global_position - line_points[i]).normalized() * 0.006
		for vertex in [line_points[i] - edge, line_points[i] + edge, line_points[i + 1] + edge, line_points[i] - edge, line_points[i + 1] + edge, line_points[i + 1] - edge]:
			_line.surface_add_vertex(to_local(vertex))
	_line.surface_end()

func _frame_camera(blend: float) -> void:
	if remote: return
	if not is_instance_valid(camera): return
	var focus := actor.global_position.lerp(_landing, 0.43) + Vector3.UP * 0.58
	var target := Transform3D(Basis.IDENTITY, focus - _forward * 2.6 + _side * 7.6 + Vector3.UP * 6.8).looking_at(focus)
	camera.global_transform = camera.global_transform.interpolate_with(target, clampf(blend, 0, 1))
	camera.v_offset = 0
	var size := get_viewport().get_visible_rect().size
	camera.size = maxf(6.4, size.x / maxf(1, size.y) * 6.0)
	preload("res://modules/farm/farm_camera.gd").fit_ground_depth(camera)

func finish() -> void:
	if _finished: return
	_finished = true
	if is_instance_valid(_water): _water.interact(Vector3.ZERO, 0)
	for item in _hidden:
		if is_instance_valid(item.node): item.node.visible = item.visible
	if is_instance_valid(rig):
		if not remote: rig.transform = _rig_transform
		if is_instance_valid(_skeleton):
			for index in _poses.size(): _skeleton.set_bone_pose(index, _poses[index])
		rig.play_motion("idle")
	if not remote and is_instance_valid(camera):
		camera.transform = _camera_transform
		camera.size = _camera_size
		camera.v_offset = _camera_offset
		camera.near = _camera_near
		camera.far = _camera_far
	queue_free()

func _exit_tree() -> void:
	if not _finished: finish()
