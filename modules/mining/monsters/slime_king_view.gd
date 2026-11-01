extends "res://modules/mining/monsters/slime_view.gd"
## The existing sculpted slime, enlarged by its json radius; the three guards differ only in tint and head ornament.

var ornament_path := ""
var _motion: Tween
var _motion_done := false
var _radius := 0.0
var _dying := false

func build(spec: Dictionary, _elite: bool) -> void:
	_radius = float(spec.radius)
	super.build(spec, false)
	var variants: Dictionary = meta.get("visual", {}).get("variants", {})
	var paint: Dictionary = variants.get(kind, variants.get("boss_slime_king", {}))
	set_tint(paint)
	var body := get_node("Body") as MeshInstance3D
	var top := body.mesh.get_aabb().end.y
	ornament_path = str(paint.get("ornament", ""))
	if ornament_path != "" and ResourceLoader.exists(ornament_path):
		var packed := load(ornament_path) as PackedScene
		if packed:
			var ornament := attach(packed, top)
			ornament.name = "GuardOrnament"
			ornament.reparent(body, false)
	else:
		var ornament := Node3D.new()
		ornament.name = "GuardOrnament"
		ornament.position.y = top
		body.add_child(ornament)
		var color := Color(str(paint.get("ornament_color", "f3cf73")))
		for i in 5:
			var shape := SphereMesh.new()
			shape.radius = _radius*0.09
			shape.height = _radius*(0.45 if kind.ends_with("quartz") else 0.23)
			shape.radial_segments = 10
			shape.rings = 5
			var angle := i*TAU/5
			var mesh := _mesh(shape, color, Vector3(cos(angle),0,sin(angle))*_radius*0.22)
			if kind.ends_with("iron"): mesh.scale = Vector3(1.6,0.7,1.6)
			ornament.add_child(mesh)
	_no_cast(self)
	action = ""

func set_tint(params: Dictionary) -> void:
	var value = params.get("color", "92c9a1")
	var color: Color = value if value is Color else Color(str(value))
	set_meta("color", color)
	if has_node("Body"): (get_node("Body").material_override as StandardMaterial3D).albedo_color = color

func _ready() -> void:
	play("idle")
	set_process(false)

func _process(delta: float) -> void:
	if _dying: _advance_visual(clampf(delta,0,0.1))

func play(name: String) -> void:
	if name == action and name in LOOPS and _motion != null: return
	super.play(name)
	if _motion != null and _motion.is_valid(): _motion.kill()
	if not is_inside_tree(): return
	_dying = name == "die"
	visible = true
	_motion = create_tween()
	_motion.pause()
	_motion_done = false
	_motion.finished.connect(func(): _motion_done = true)
	if name in LOOPS: _motion.set_loops()
	_motion.tween_method(_pose.bind(name), 0.0, 1.0, maxf(0.01,duration(name)))
	set_process(_dying)
	if _dying: _motion.tween_callback(func(): visible = false; set_process(false))

func _pose(progress: float, name: String) -> void:
	var body := get_node("Body") as MeshInstance3D
	body.position = Vector3.ZERO
	match name:
		"windup": body.scale = Vector3.ONE.lerp(SQUASH, progress)
		"attack":
			body.scale = Vector3(1,1+sin(progress*PI)*0.15,1)
			body.position.y = sin(progress*PI)*_radius*0.3
		"die": body.scale = Vector3.ONE*maxf(0.001,1-progress)
		_: body.scale = Vector3(1,1+sin(progress*TAU)*0.04,1)

func update(enemy: Dictionary, _was: String, delta: float, stepped: bool, _elapsed: float) -> void:
	if _dying: return
	var wanted := str(ACTIONS.get(str(enemy.phase),"idle"))
	var changed := wanted != action
	if changed: play(wanted)
	if not changed and (stepped or wanted == "idle"): _advance_visual(clampf(delta,0,0.1))
	var body := get_node("Body") as MeshInstance3D
	(body.material_override as StandardMaterial3D).albedo_color = Color("fff3bd") if enemy.flash>0 else get_meta("color")
	var band := get_node("Band") as Node3D
	band.visible = str(enemy.phase) in ["windup","dash"]
	if band.visible: lay_band(band, enemy)

func _advance_visual(dt: float) -> void:
	action_time += dt
	if _motion != null and _motion.is_valid() and not _motion_done: _motion.custom_step(dt)
