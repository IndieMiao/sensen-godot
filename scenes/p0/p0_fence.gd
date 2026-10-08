extends Node3D
## The homestead fence by Homestead level (plan §8.3, q(35); 不知火舞 on SGODOT-228 7e1db1f8): the stretch
## in front of the farmhouse is always there; Homestead Lv3 completes the ring. When Lv3 is reached in this
## session the ring drops in from above with a little dust within the HOME-2 banner's 3 s; a save that is
## already Lv3 shows it at once. Layout data lives in P0Garden (fence_front / fence_ring).

const FarmArt = preload("res://modules/farm/farm_art.gd")
const DROP_H := 1.4
const DROP_S := 0.45
const SPREAD_S := 1.8     # last segment lands by SPREAD_S + DROP_S < 3 s

var _ring: Array[Node3D] = []
var _seen := false        # a view has been read (the first one decides "already Lv3")
var _shown := false

func build(bp: FarmBlueprint) -> void:
	name = "Fence"
	var front: Array = []
	for seg in P0Garden.fence_front(bp): front.append(_xf(seg))
	add_child(FarmArt.batch("fence", front))
	for seg in P0Garden.fence_ring(bp):
		var m := FarmArt.instance("fence")
		m.transform = _xf(seg)
		m.visible = false
		add_child(m)
		_ring.append(m)

## Call every frame with the projected view (cheap until the unlock flips).
func sync(view: Dictionary) -> void:
	var on := bool(view.get("homestead", {}).get("unlocks", {}).get("fence", false))
	if on and not _shown:
		_shown = true
		if _seen: drop_in()
		else: for m in _ring: m.visible = true
	_seen = true

func ring_shown() -> bool: return _shown

func drop_in() -> void:
	var n := _ring.size()
	for i in n:
		var m := _ring[i]
		var rest := m.position
		m.position = rest + Vector3(0, DROP_H, 0)
		m.visible = true
		var tw := create_tween()
		tw.tween_interval(SPREAD_S * float(i) / maxf(1.0, float(n - 1)))
		tw.tween_property(m, "position", rest, DROP_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(_dust.bind(rest))

func _dust(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.6
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0, -0.6, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.12
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.86, 0.78, 0.64, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	p.mesh = mesh
	p.position = at + Vector3(0, 0.05, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

static func _xf(seg: Dictionary) -> Transform3D:
	var basis := Basis(Vector3.UP, float(seg.yaw)) * Basis.from_scale(Vector3(float(seg.get("stretch", 1.0)), 1, 1))
	return Transform3D(basis, seg.pos)
