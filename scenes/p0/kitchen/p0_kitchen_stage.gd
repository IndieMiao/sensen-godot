class_name P0KitchenStage
extends Node3D
## The 3D stove stage on one stove's pot (SGODOT-226, LOCK-20 v5; plan §7.2.7). Lives at the stove's drop_ anchor
## (the pot mouth) and shows, on the pot itself:
## - ingredients as camera-facing icon cards (Shiranui Mai 2026-10-07: unshaded, about 28–36 px on screen, a faint
##   contact shadow on the rim; fly in on an arc in 0.4 s, land with a small bounce and a puff of steam; spread along
##   the rim, one card per kind with ×N; they stay until the dish comes out; a removed one flies back);
## - ghosts of a Cookbook page's ingredients (translucent, no flight);
## - cooking: steam and a brighter hearth while the stove is busy;
## - the dish: a plate slides out of the pot with its rarity glow (q(16): same colour as the rarity dot, none for
##   Common).
## Screen-space parts (slot bar, preview capsule, heat ring) are the kitchen controller's; this node only draws 3D.

signal landed(id: String)

const CARD_PX := 32.0         # icon card size on screen
const FLY_S := 0.4
const BOUNCE_S := 0.18
const RIM_R := 0.16           # metres from the pot mouth centre to a card
const RIM_ARC := 0.9          # radians between neighbouring cards, spread on the camera-facing half
const LIFT := 0.05            # cards stand this far above the mouth
const GHOST_ALPHA := 0.45
const PLATE_R := 0.17
const PLATE_SLIDE := 0.32     # metres towards the camera
const PLATE_S := 0.45
const GLOW_R := 0.32

var cam: Camera3D
var glow_light: OmniLight3D   ## the room's hearth light, brightened while cooking
var _cards := {}              # id -> {node: Node3D, sprite: Sprite3D, count: Label3D, n: int}
var _order: Array = []        # ids in landing order (rim positions)
var _ghosts: Array[Node3D] = []
var _steam: CPUParticles3D
var _plate: Node3D
var _base_glow := 0.0
var _cooking := false

func _ready() -> void:
	_steam = _make_steam()
	add_child(_steam)
	if glow_light: _base_glow = glow_light.light_energy

func _process(_dt: float) -> void:
	if cam == null: return
	var px := world_per_px()
	for id in _cards:
		var s: Sprite3D = _cards[id].sprite
		if s.texture: s.pixel_size = px * CARD_PX / float(maxi(1, s.texture.get_width()))
	for g in _ghosts:
		var gs: Sprite3D = g.get_node("Card")
		if gs.texture: gs.pixel_size = px * CARD_PX / float(maxi(1, gs.texture.get_width()))

## Metres per screen pixel for the current orthographic camera (keep-width projection).
func world_per_px() -> float:
	if cam == null or not cam.is_inside_tree(): return 0.01
	return cam.size / maxf(1.0, cam.get_viewport().get_visible_rect().size.x)

# ---------------------------------------------------------------- ingredients
func has_card(id: String) -> bool: return _cards.has(id)
func card_count(id: String) -> int: return int(_cards[id].n) if _cards.has(id) else 0
func card_ids() -> Array: return _order.duplicate()

## Puts one `id` in the pot. `from_screen` (a slot or bag cell) starts the flight; Vector2.INF places it directly.
func add_ingredient(id: String, texture: Texture2D, from_screen := Vector2.INF) -> void:
	clear_ghosts()
	if _cards.has(id):
		_cards[id].n += 1
		_set_count(id)
		_bounce(_cards[id].node)
		_puff()
		return
	var node := _card(texture, false)
	add_child(node)
	_cards[id] = {node = node, sprite = node.get_node("Card"), count = node.get_node("Count"), n = 1}
	_order.append(id)
	_set_count(id)
	_relayout(id)
	var to := node.position
	if from_screen == Vector2.INF or cam == null:
		landed.emit(id)
		return
	var from := to_local(_screen_to_world(from_screen))
	node.position = from
	var t := create_tween()
	t.tween_method(func(k: float): node.position = _arc(from, to, k), 0.0, 1.0, FLY_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func():
		_bounce(node)
		_puff()
		landed.emit(id))

## Takes one `id` out; the last one flies back to `to_screen` (or just disappears).
func remove_ingredient(id: String, to_screen := Vector2.INF) -> void:
	if not _cards.has(id): return
	_cards[id].n -= 1
	if int(_cards[id].n) > 0:
		_set_count(id)
		return
	var node: Node3D = _cards[id].node
	_cards.erase(id)
	_order.erase(id)
	_relayout()
	if to_screen == Vector2.INF or cam == null:
		node.queue_free()
		return
	var from := node.position
	var to := to_local(_screen_to_world(to_screen))
	var t := create_tween()
	t.tween_method(func(k: float): node.position = _arc(from, to, k), 0.0, 1.0, FLY_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(node.queue_free)

func clear_ingredients() -> void:
	for id in _cards: (_cards[id].node as Node3D).queue_free()
	_cards.clear()
	_order.clear()

## Translucent cards of a Cookbook page's ingredients (unknown kinds use the question card). Replaces earlier ghosts.
func show_ghosts(textures: Array) -> void:
	clear_ghosts()
	for i in textures.size():
		var g := _card(textures[i], true)
		g.position = _rim(i, textures.size())
		add_child(g)
		_ghosts.append(g)

func clear_ghosts() -> void:
	for g in _ghosts: g.queue_free()
	_ghosts.clear()

func ghost_count() -> int: return _ghosts.size()

func _card(texture: Texture2D, ghost: bool) -> Node3D:
	var root := Node3D.new()
	var s := Sprite3D.new()
	s.name = "Card"
	s.texture = texture
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = false
	s.render_priority = 1
	s.modulate = Color(1, 1, 1, GHOST_ALPHA) if ghost else Color.WHITE
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.position = Vector3(0, LIFT + 0.12, 0)
	root.add_child(s)
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.08)
	q.orientation = PlaneMesh.FACE_Y
	shadow.mesh = q
	shadow.material_override = _shadow_material(0.10 if ghost else 0.22)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.position = Vector3(0, 0.005, 0)
	root.add_child(shadow)
	var count := Label3D.new()
	count.name = "Count"
	count.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	count.shaded = false
	count.fixed_size = true
	count.pixel_size = 0.0012
	count.font = UiKit.font(&"extrabold")
	count.font_size = UiTokens.SIZE_KITCHEN_CHECK + 3
	count.outline_size = 8
	count.modulate = UiTokens.COLOR_TEXT
	count.outline_modulate = UiTokens.COLOR_SURFACE
	count.position = Vector3(0.09, LIFT + 0.04, 0.02)
	count.visible = false
	root.add_child(count)
	return root

func _set_count(id: String) -> void:
	var c: Label3D = _cards[id].count
	c.text = "×%d" % int(_cards[id].n)
	c.visible = int(_cards[id].n) > 1

func _relayout(fresh := "") -> void:
	for i in _order.size():
		var node: Node3D = _cards[_order[i]].node
		var at := _rim(i, _order.size())
		if _order[i] == fresh or not is_inside_tree(): node.position = at
		else: create_tween().tween_property(node, "position", at, 0.2).set_trans(Tween.TRANS_SINE)

## Rim spot `i` of `n`, spread around the side of the mouth that faces the camera.
func _rim(i: int, n: int) -> Vector3:
	var toward := Vector3(0, 0, 1)
	if cam: toward = (cam.global_position - global_position) * Vector3(1, 0, 1)
	toward = toward.normalized() if toward.length() > 0.001 else Vector3(0, 0, 1)
	var base := atan2(toward.x, toward.z)
	var a := base + (float(i) - float(n - 1) * 0.5) * RIM_ARC
	return Vector3(sin(a) * RIM_R, LIFT, cos(a) * RIM_R)

func _arc(from: Vector3, to: Vector3, k: float) -> Vector3:
	return from.lerp(to, k) + Vector3.UP * sin(k * PI) * 0.35

func _bounce(node: Node3D) -> void:
	node.scale = Vector3.ONE * 1.18
	create_tween().tween_property(node, "scale", Vector3.ONE, BOUNCE_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A world point under a screen point, at the pot mouth's distance from the camera.
func _screen_to_world(p: Vector2) -> Vector3:
	var depth := (global_position - cam.global_position).dot(-cam.global_basis.z)
	return cam.project_position(p, depth)

# ---------------------------------------------------------------- steam, fire, plate
func set_cooking(on: bool) -> void:
	_cooking = on
	_steam.emitting = on
	if glow_light: create_tween().tween_property(glow_light, "light_energy", _base_glow * (2.2 if on else 1.0), 0.5)

func is_cooking() -> bool: return _cooking

func _puff() -> void:
	var p := _make_steam()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.7
	p.emitting = true
	add_child(p)
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

func _make_steam() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 14
	p.lifetime = 1.4
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 0.25, 0)
	p.initial_velocity_min = 0.18
	p.initial_velocity_max = 0.32
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.06
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.55))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = grad
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	mesh.material = m
	p.mesh = mesh
	p.position = Vector3(0, 0.06, 0)
	return p

## The dish comes out: a plate slides towards the camera with the dish card and its rarity glow (none for Common).
## `done` runs when it has settled.
func serve(texture: Texture2D, rarity: int, glow: Color, done := Callable()) -> void:
	clear_ghosts()
	set_cooking(false)
	clear_plate()
	_plate = Node3D.new()
	_plate.name = "Plate"
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = PLATE_R
	cyl.bottom_radius = PLATE_R * 0.8
	cyl.height = 0.03
	disc.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = UiTokens.COLOR_SURFACE
	pm.roughness = 0.6
	disc.material_override = pm
	_plate.add_child(disc)
	if rarity > 1:
		var halo := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * GLOW_R * 2.0
		q.orientation = PlaneMesh.FACE_Y
		halo.mesh = q
		var hm := StandardMaterial3D.new()
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		hm.albedo_color = glow
		hm.albedo_texture = _soft_dot()
		halo.material_override = hm
		halo.position = Vector3(0, 0.02, 0)
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_plate.add_child(halo)
	var dish := _card(texture, false)
	dish.position = Vector3(0, 0.0, 0)
	_plate.add_child(dish)
	_cards["__dish"] = {node = dish, sprite = dish.get_node("Card"), count = dish.get_node("Count"), n = 1}
	add_child(_plate)
	clear_ingredients_except_dish()
	var toward := Vector3(0, 0, 1)
	if cam: toward = ((cam.global_position - global_position) * Vector3(1, 0, 1)).normalized()
	_plate.position = Vector3(0, -0.04, 0)
	var t := create_tween()
	t.tween_property(_plate, "position", toward * PLATE_SLIDE + Vector3(0, -0.02, 0), PLATE_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if done.is_valid(): t.tween_callback(done)

func clear_ingredients_except_dish() -> void:
	for id in _cards.keys():
		if id == "__dish": continue
		(_cards[id].node as Node3D).queue_free()
		_cards.erase(id)
	_order.clear()

func clear_plate() -> void:
	if _plate: _plate.queue_free()
	_plate = null
	_cards.erase("__dish")

func has_plate() -> bool: return _plate != null

static var _dot_tex: Texture2D
static func _soft_dot() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_dot_tex = t
	return _dot_tex

static func _shadow_material(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.18, 0.14, 0.1, alpha)
	m.albedo_texture = _soft_dot()
	return m
