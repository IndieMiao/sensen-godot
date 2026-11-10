extends Node3D
## The homestead fence by Homestead level (plan §8.3, q(35); 不知火舞 on SGODOT-228 7e1db1f8): the stretch
## in front of the farmhouse is always there; Homestead Lv3 completes the ring. When Lv3 is reached in this
## session the ring drops in from above with a little dust within the HOME-2 banner's 3 s; a save that is
## already Lv3 shows it at once. Layout data lives in P0Garden (fence_front / fence_ring).
## From Lv3 the whole fence is the Fence & Mailbox look (LOOK-PICK, SGODOT-282): a = this timber fence, b = a Stone Wall
## on the same run (P0Garden.stone_wall); a change pops the new one in with dust (pop_in, as the other looks).
## Yard v2 (v4q(12) ③ ④): the ring stands round the yard of its level (P0Garden.yard_at: Lv13 the back stretch to
## z −13.0, Lv14 the east one to x 13.65); a level that moves it rebuilds the ring, dropped in again as at Lv3 when it
## comes in this session (set_level), at once otherwise.

const FarmArt = preload("res://modules/farm/farm_art.gd")
const DROP_H := 1.4
const DROP_S := 0.45
const SPREAD_S := 1.8     # last segment lands by SPREAD_S + DROP_S < 3 s

const POP_S := 0.3          # a look swapped in: 0 → full size, a little past it and back

var _ring: Array[Node3D] = []
var _front: Node3D          # the timber stretch in front of the farmhouse (always, until a Stone Wall takes it)
var _stone: Node3D          # the Stone Wall (front and ring), built when first shown
var _ring_dust: Array = []  # a few points along the Stone Wall's ring for the swap's dust
var _seen := false        # a view has been read (the first one decides "already Lv3")
var _shown := false
var look := "a"           # the Fence & Mailbox look on show
var preview := ""         # LOOK-PICK's preview ("" = the view's look)
var _bp: FarmBlueprint
var level := 1              # the yard level the ring stands round (P0Garden.yard_at)

func build(bp: FarmBlueprint) -> void:
	name = "Fence"
	_bp = bp
	var front: Array = []
	for seg in P0Garden.fence_front(bp): front.append(_xf(seg))
	_front = FarmArt.batch("fence", front)
	add_child(_front)
	_build_ring()

func _build_ring() -> void:
	for seg in P0Garden.fence_ring(_bp, level):
		var m := FarmArt.instance("fence")
		m.transform = _xf(seg)
		m.visible = false
		add_child(m)
		_ring.append(m)

## The ring round the yard of Homestead `lv` (yard v2): nothing when it stands where it is; else the old one goes and the
## new one is built — dropped in (timber) or popped in with dust (Stone Wall) when `animate`, shown at once otherwise.
func set_level(lv: int, animate: bool) -> void:
	if P0Garden.yard_at(lv).ring == P0Garden.yard_at(level).ring:
		level = lv
		return
	level = lv
	for m in _ring: m.queue_free()
	_ring.clear()
	_build_ring()
	if _stone != null:
		_stone.queue_free()
		_stone = null
		_ring_dust.clear()
	var stone := look == "b"
	if stone: _stone = _build_stone()
	for m in _ring: m.visible = _shown and not stone
	if not _shown or not animate: return
	if stone:
		pop_in(self, _stone.get_children().filter(func(n): return n is MeshInstance3D))
		for at in _ring_dust: dust(self, at)
	else: drop_in()

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
	# Batches (the timber front, the Stone Wall's ring) sit about the world origin: they just show; single pieces pop.
	if not animate: return
	pop_in(self, (_stone if stone else self).get_children().filter(func(n): return n is MeshInstance3D and (n as Node3D).visible))
	if stone: for at in _ring_dust: dust(self, at)

## The Stone Wall: the ring's rocks as one batch (one draw, ~120 rocks; 上官婉儿 on #250), the front stretch's few as
## their own pieces, so the swap pops those by the door and puffs dust along the ring.
func _build_stone() -> Node3D:
	var root := Node3D.new()
	root.name = "StoneWall"
	add_child(root)
	for p in P0Garden.stone_wall(P0Garden.fence_front(_bp)):
		var m := FarmArt.instance(str(p.asset))
		m.transform = _part_xf(p)
		root.add_child(m)
	var ring := P0Garden.stone_wall(P0Garden.fence_ring(_bp, level))
	var batch := FarmArt.batch("rock", ring.map(_part_xf))
	batch.name = "Ring"
	root.add_child(batch)
	for i in range(0, ring.size(), 12): _ring_dust.append(ring[i].pos)
	return root

static func _part_xf(p: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(p.yaw)) * Basis.from_scale(p.scale), p.pos)

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
