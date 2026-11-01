extends "res://modules/mining/monsters/slime_view.gd"
## F adapter: keep the existing HP/band/shadow nodes; the visual beneath Body is either a model or a tweened stand-in.

const TINT = preload("res://modules/mining/monsters/f_model_tint.gdshader")
const PHASE_ACTION := {"idle":"idle", "chase":"move", "fly_high":"fly_high", "windup":"windup", "dash":"attack",
	"recover":"recover", "stunned":"stunned", "hide":"hide", "spore":"spore"}

var family := ""
var model_path := ""
var using_model := false
var visual: Node3D
var flight: Node3D
var limbs: Array[Node3D] = []
var style := {}
var _painted: Array[MeshInstance3D] = []
var _model_material: ShaderMaterial
var _player: AnimationPlayer
var _motion: Tween
var _motion_done := false
var _from_height := 0.0
var _spores: CPUParticles3D
var _opacity := 1.0
var _flash := 0.0
var _elite := false

func build(spec: Dictionary, elite: bool) -> void:
	_elite = elite
	var fallback: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://modules/mining/monsters/placeholder/"+family+".json"))
	style = (meta.get("visual", fallback.get("visual", {})) as Dictionary).duplicate(true)
	super.build(spec, false)
	var body := get_node("Body") as MeshInstance3D
	body.mesh = null
	for child in body.get_children(): child.free()
	flight = Node3D.new()
	flight.name = "Flight"
	body.add_child(flight)
	visual = Node3D.new()
	visual.name = "Visual"
	flight.add_child(visual)
	model_path = str(meta.get("model", "res://assets/monsters/%s/%s.glb" % [family, family]))
	if ResourceLoader.exists(model_path):
		var packed := load(model_path) as PackedScene
		if packed != null:
			using_model = true
			var model := packed.instantiate() as Node3D
			visual.add_child(model)
			_model_material = ShaderMaterial.new()
			_model_material.shader = TINT
			var meshes := model.find_children("*", "MeshInstance3D", true, false)
			if model is MeshInstance3D: meshes.push_front(model)
			for node in meshes: node.material_override = _model_material
			var players := model.find_children("*", "AnimationPlayer", true, false)
			if not players.is_empty(): _player = players[0]
			if _player:
				_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				for key in _player.get_animation_list():
					var clip := _player.get_animation(key).duplicate() as Animation
					clip.loop_mode = Animation.LOOP_LINEAR if str(key).get_file() in LOOPS else Animation.LOOP_NONE
					var library_name := str(key).get_slice("/", 0) if str(key).contains("/") else ""
					var library := _player.get_animation_library(library_name).duplicate() as AnimationLibrary
					library.remove_animation(str(key).get_file())
					library.add_animation(str(key).get_file(), clip)
					_player.remove_animation_library(library_name)
					_player.add_animation_library(library_name, library)
	if not using_model: build_placeholder()
	var top := float(style.get("top", spec.radius*2.0)) + float(style.get("high_offset", 0.0))
	get_node("Health").position.y = top + 0.35
	get_node("HealthFill").position.y = top + 0.12
	get_node("HealthTrack").position.y = top + 0.12
	if family == "mob_shroomling":
		var warning := get_node("Warning") as MeshInstance3D
		var ring := warning.mesh as TorusMesh
		ring.inner_radius = maxf(0.01, float(meta.spore_range)-0.06)
		ring.outer_radius = float(meta.spore_range)
		(warning.material_override as StandardMaterial3D).albedo_color = Color(BAND_COLOR, 0.3)
		(warning.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	set_tint({"color": style.get("elite_color" if elite else "color", "ffffff"), "strength": 0.65 if elite else 0.0})
	_no_cast(self)
	action = ""

func build_placeholder() -> void:
	pass

func _ready() -> void:
	play("fly_high" if family == "mob_cave_bat" else "idle")
	set_process(false)

func _process(delta: float) -> void:
	if action == "die": _advance_visual(clampf(delta,0,0.1))

func part(parent: Node3D, title: String, size: Vector3, at: Vector3, color: Color, tintable := true) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = 0.5
	shape.height = 1.0
	shape.radial_segments = 12
	shape.rings = 6
	var node := _mesh(shape, color, at)
	node.name = title
	node.scale = size
	node.set_meta("base_color", color)
	node.set_meta("tintable", tintable)
	parent.add_child(node)
	_painted.append(node)
	return node

func face(parent: Node3D, at: Vector3, size := 1.0) -> void:
	var mesh := Meshes.surface()
	for side in [-1, 1]:
		_face_sphere(mesh, 0.035*size, 0.085*size, Color("292938"), at+Vector3(side*0.07,0,0)*size)
		_face_sphere(mesh, 0.012*size, 0.025*size, Color("fff9ec"), at+Vector3(side*0.07-0.008,0.02,0.028)*size)
		_face_sphere(mesh, 0.045*size, 0.04*size, Color("e5a7ba"), at+Vector3(side*0.13,-0.048,-0.005)*size, Vector3(1,1,0.35))
	var node := MeshInstance3D.new()
	node.name = "Face"
	mesh.index()
	node.mesh = mesh.commit()
	node.material_override = _face_jelly().duplicate()
	parent.add_child(node)
	_painted.append(node)
	node.set_meta("base_color", Color.WHITE)
	node.set_meta("tintable", false)

func set_tint(params: Dictionary) -> void:
	var value = params.get("color", style.get("color", "ffffff"))
	var color: Color = value if value is Color else Color(str(value))
	style["shown_color"] = color
	if _model_material:
		_model_material.set_shader_parameter("tint", color)
		_model_material.set_shader_parameter("tint_strength", float(params.get("strength", 0.65)))
	paint()

func paint() -> void:
	if _model_material:
		_model_material.set_shader_parameter("flash", _flash)
		_model_material.set_shader_parameter("opacity", _opacity)
	for part_node in _painted:
		var original: Color = part_node.get_meta("base_color", Color.WHITE)
		var color: Color = style.get("shown_color", original) if part_node.get_meta("tintable", false) else original
		color = color.lerp(Color("fff3d9"), _flash)
		color.a = _opacity
		var mat := part_node.material_override as StandardMaterial3D
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if _opacity < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED

func play(name: String) -> void:
	if name == action and name in LOOPS and (_motion != null or _player != null): return
	super.play(name)
	if _motion != null and _motion.is_valid(): _motion.kill()
	if not is_inside_tree() or visual == null: return
	_opacity = 1.0
	paint()
	visible = true
	visual.scale = Vector3.ONE
	visual.rotation = Vector3.ZERO
	_from_height = flight.position.y
	if family == "mob_cave_bat" and name in LOOPS:
		_from_height = float(style.high_offset)
		flight.position.y = _from_height
	var span := maxf(0.01, duration(name))
	if _player:
		var clip := ""
		for key in _player.get_animation_list():
			if str(key).get_file() == name: clip = str(key); break
		if clip != "":
			var length := _player.get_animation(clip).length
			_player.play(clip, -1, length / span)
			_player.advance(0.0)
	_motion = create_tween()
	_motion.pause()
	_motion_done = false
	_motion.finished.connect(func(): _motion_done = true)
	if name in LOOPS: _motion.set_loops()
	_motion.tween_method(_pose.bind(name), 0.0, 1.0, span)
	set_process(name == "die")
	if name == "die": _motion.tween_callback(func(): visible = false; set_process(false))
	if name == "spore":
		# Particle release uses the same normalized animation clock as the hit; _pose fires it once.
		set_meta("spore_released", false)

func _pose(progress: float, name: String) -> void:
	var wave := sin(progress * TAU)
	if family == "mob_cave_bat":
		var goal := float(style.get("dive_offset", 0.0)) if name == "attack" else float(style.get("high_offset", 0.0))
		flight.position.y = lerpf(_from_height, goal, progress)
	if not using_model:
		if name in ["idle", "move", "fly_high", "stunned"]:
			visual.rotation.z = wave * (0.08 if name == "stunned" else 0.025)
			for i in limbs.size(): limbs[i].rotation.z = wave * (0.5 if family == "mob_cave_bat" else 0.14) * (-1 if i%2 else 1)
		elif name == "windup": visual.scale = Vector3.ONE.lerp(SQUASH, progress)
		elif name == "attack": visual.scale = Vector3(1.0, 1.0+sin(progress*PI)*0.12, 1.0)
		elif name == "hide":
			var tucked := clampf(progress / 0.15, 0, 1) if progress < 0.85 else clampf((1.0-progress)/0.15, 0, 1)
			visual.scale = Vector3.ONE.lerp(Vector3(0.8,0.2,0.8), tucked)
		elif name == "spore": visual.scale = Vector3.ONE * (1.0 + sin(progress*PI)*0.08)
	if name == "die":
		if not using_model: visual.scale = Vector3.ONE * maxf(0.001, 1.0-progress)
		_opacity = 1.0-progress
		paint()
	elif name == "hit":
		_flash = 1.0-progress
		paint()
	if name == "spore" and not get_meta("spore_released", true) and progress*duration("spore") >= float(meta.get("spore_at", 0)):
		set_meta("spore_released", true)
		release_spores()

func release_spores() -> void:
	if _spores == null:
		_spores = CPUParticles3D.new()
		_spores.name = "Spores"
		_spores.emitting = false
		_spores.one_shot = true
		_spores.explosiveness = 1.0
		_spores.amount = 12
		_spores.spread = 180
		_spores.gravity = Vector3.ZERO
		var sphere := SphereMesh.new()
		sphere.radius = 0.035
		sphere.height = 0.07
		sphere.radial_segments = 6
		sphere.rings = 3
		_spores.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(str(style.get("spore_color", "d4efa0")))
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spores.material_override = material
		_spores.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_spores)
	var hit: Array = meta.get("hit_point", [0,0,0])
	_spores.position = Vector3(hit[0],hit[1],hit[2])
	_spores.lifetime = maxf(0.1, duration("spore")-float(meta.get("spore_at",0)))
	_spores.initial_velocity_min = float(meta.get("spore_range", 1.0)) / _spores.lifetime
	_spores.initial_velocity_max = _spores.initial_velocity_min
	_spores.restart()
	_spores.emitting = true

func _advance_visual(dt: float) -> void:
	action_time += dt
	if _motion != null and _motion.is_valid() and not _motion_done: _motion.custom_step(dt)
	if _player: _player.advance(dt)

func update(enemy: Dictionary, _was: String, delta: float, stepped: bool, _elapsed: float) -> void:
	if action == "die": return
	var phase := str(enemy.phase)
	var wanted := str(PHASE_ACTION.get(phase, "idle"))
	if family == "mob_cave_bat" and phase in ["idle","stunned"]: wanted = "fly_high" if phase=="idle" else "hit"
	var changed := wanted != action
	if changed: play(wanted)
	# A new phase starts after this frame's brain step, at zero; subsequent animation ticks share its clamped clock.
	if not changed and (stepped or wanted in ["idle","fly_high"]): _advance_visual(clampf(delta,0,0.1))
	_flash = 1.0 if float(enemy.flash)>0 else 0.0
	paint()
	if family == "mob_cave_bat":
		var top := float(style.top)+flight.position.y
		get_node("Health").position.y = top+0.35
		get_node("HealthFill").position.y = top+0.12
		get_node("HealthTrack").position.y = top+0.12
	var direction: Vector3 = enemy.direction if phase in ["windup","dash"] else enemy.mover.facing
	if Vector2(direction.x,direction.z).length_squared()>0.0001:
		get_node("Body").rotation.y = atan2(direction.x,direction.z)
	var band := get_node("Band") as Node3D
	band.visible = phase in ["windup","dash"] and family != "mob_shroomling"
	if band.visible: lay_band(band, enemy)
	get_node("Warning").visible = family == "mob_shroomling" and phase in ["windup","spore"]
