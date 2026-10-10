extends Node3D
## The homestead fence by Homestead level (plan §8.3, q(35); 不知火舞 on SGODOT-228 7e1db1f8): the stretch
## in front of the farmhouse is always there; Homestead Lv3 completes the ring. When Lv3 is reached in this
## session the ring drops in from above with a little dust within the HOME-2 banner's 3 s; a save that is
## already Lv3 shows it at once. Layout data lives in P0Garden (fence_front / fence_ring).
## From Lv3 the whole fence is the Fence & Mailbox look (LOOK-PICK, SGODOT-282): a = this timber fence, b = a Stone Wall
## on the same run (P0Garden.stone_wall); a change pops the new one in with dust (pop_in, as the other looks).

const FarmArt = preload("res://modules/farm/farm_art.gd")
const DROP_H := 1.4
const DROP_S := 0.45
const SPREAD_S := 1.8     # last segment lands by SPREAD_S + DROP_S < 3 s

const POP_S := 0.3          # a look swapped in: 0 → full size, a little past it and back

var _ring: Array[Node3D] = []
var _front: Node3D          # the timber stretch in front of the farmhouse (always, until a Stone Wall takes it)
var _stone: Node3D          # the Stone Wall (front and ring), built when first shown
var _seen := false        # a view has been read (the first one decides "already Lv3")
var _shown := false
var look := "a"           # the Fence & Mailbox look on show
var preview := ""         # LOOK-PICK's preview ("" = the view's look)
var _bp: FarmBlueprint

func build(bp: FarmBlueprint) -> void:
	name = "Fence"
	_bp = bp
	var front: Array = []
	for seg in P0Garden.fence_front(bp): front.append(_xf(seg))
	_front = FarmArt.batch("fence", front)
	add_child(_front)
	for seg in P0Garden.fence_ring(bp):
		var m := FarmArt.instance("fence")
		m.transform = _xf(seg)
		m.visible = false
		add_child(m)
		_ring.append(m)

## Call every frame with the projected view (cheap until the unlock or the look flips).
func sync(view: Dictionary) -> void:
	var on := bool(view.get("homestead", {}).get("unlocks", {}).get("fence", false))
	if on and not _shown:
		_shown = true
		if _seen: drop_in()
		else: for m in _ring: m.visible = true
	_seen = true
	var have := P0Logic.look_of(view, "fence") if on else "a"
	if preview == have: preview = ""   # the card's Use landed, or a preview of what is there already
	var want := preview if preview != "" else have
	if want != "" and want != look: set_look(want, _shown)

func ring_shown() -> bool: return _shown

## a: the timber fence; b: the Stone Wall in its place (front stretch and ring). animate: pop in with dust.
func set_look(v: String, animate := true) -> void:
	look = v
	var stone := v == "b"
	if stone and _stone == null: _stone = _build_stone()
	_front.visible = not stone
	for m in _ring: m.visible = _shown and not stone
	if _stone: _stone.visible = stone
	# The timber front is one batch about the world origin: it just shows; the ring's and the wall's pieces pop.
	if animate: pop_in(self, (_stone if stone else self).get_children().filter(func(n): return n is MeshInstance3D and (n as Node3D).visible))

func _build_stone() -> Node3D:
	var root := Node3D.new()
	root.name = "StoneWall"
	add_child(root)
	for p in P0Garden.stone_wall(P0Garden.fence_front(_bp) + P0Garden.fence_ring(_bp)):
		var m := FarmArt.instance(str(p.asset))
		m.transform = Transform3D(Basis(Vector3.UP, float(p.yaw)) * Basis.from_scale(p.scale), p.pos)
		root.add_child(m)
	return root

## LOOK-PICK's swap (49498df6): each part grows in over POP_S with a touch of overshoot, a little dust under every third.
static func pop_in(host: Node3D, parts: Array) -> void:
	for i in parts.size():
		var n: Node3D = parts[i]
		var full := n.scale
		n.scale = full * 0.01
		var tw := n.create_tween()
		tw.tween_property(n, "scale", full, POP_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if i % 3 == 0: dust(host, n.global_position - host.global_position)

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
		tw.tween_callback(dust.bind(self, rest))

## A small puff of dust at `at` (host's space), gone in a second: the fence landing, a look swapped in.
static func dust(host: Node3D, at: Vector3) -> void:
	if not host.is_inside_tree(): return
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
	host.add_child(p)
	p.emitting = true
	host.get_tree().create_timer(1.0).timeout.connect(p.queue_free)

static func _xf(seg: Dictionary) -> Transform3D:
	var basis := Basis(Vector3.UP, float(seg.yaw)) * Basis.from_scale(Vector3(float(seg.get("stretch", 1.0)), 1, 1))
	return Transform3D(basis, seg.pos)
