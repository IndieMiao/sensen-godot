extends Control
## The pot in the middle of the watch (SGODOT-419, q(288); 不知火舞 419 bd102c55, choice (b)): a 3D layer over the
## kitchen, its own small world drawn with a transparent background into the box x 80–280, y 150–330, the pot's mouth
## fixed at (180, 235) — the heat ring, the countdown and its bar line up under it, whatever the camera does. The same
## pot as on the stove, seen from the kitchen camera's side and lit warm from the upper left as the kitchen is; its
## `tumble` loop plays when the model has one (黄忠's cooking_pot_wait.tscn), else the stove's own pot stands in.
## There is one pot on the screen: the host hides the stove's while this shows. It flies in from the stove pot's place
## and size on the screen (0.25 s, ease out) and back the same way.

const BOX := Rect2(80, 150, 200, 180)
const MOUTH := Vector2(180, 235)
const FLY_S := 0.25
const POT_W_PX := 150.0   # the pot's width in the box
const POT_W_M := 0.30     # … the stove's Big Pot seen from the camera, handles in (manifest: 0.28 × 0.214)
const WAIT_SCENE := "res://assets/props/cooking_pot_wait/cooking_pot_wait.tscn"
const STOVE_POT := "res://assets/props/stove_pot/stove_pot.glb"
const LIGHT := Color(1.0, 0.9, 0.76)   # warm, as the kitchen's lamps

var view: SubViewport
var pot: Node3D
var _tex: TextureRect
var _cam: Camera3D
var _sun: DirectionalLight3D
var _tween: Tween

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = BOX.size
	pivot_offset = MOUTH - BOX.position   # scaled and moved about the mouth: it stays where the ring is
	view = SubViewport.new()
	view.name = "PotWorld"
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE   # hidden on the stove: not drawn (周瑜 on #764)
	add_child(view)
	_tex = TextureRect.new()
	_tex.name = "Pot"
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.size = BOX.size
	_tex.texture = view.get_texture()
	add_child(_tex)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	view.add_child(_cam)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = LIGHT
	e.ambient_light_energy = 0.55
	env.environment = e
	view.add_child(env)
	_sun = DirectionalLight3D.new()
	_sun.light_color = LIGHT
	_sun.light_energy = 1.1
	view.add_child(_sun)

## The pot as the stove's (`variant` pot_big / pot_normal, its yaw `pot_basis`), seen along the kitchen camera's
## `cam_basis`; `scale_k` the screen's pixels a design pixel (the layer is drawn sharp on a phone).
func setup(cam_basis: Basis, pot_basis: Basis, variant: String, scale_k: float) -> void:
	if pot: pot.queue_free()
	var waiting := ResourceLoader.exists(WAIT_SCENE)
	pot = (load(WAIT_SCENE if waiting else STOVE_POT) as PackedScene).instantiate() as Node3D
	pot.name = "WaitPot"
	pot.basis = pot_basis
	view.add_child(pot)
	if not waiting:
		for v in ["pot_big", "pot_normal"]:
			var n := pot.get_node_or_null(v) as Node3D
			if n: n.visible = v == variant
	var ap := pot.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation("tumble"): ap.play("tumble")
	view.size = Vector2i(roundi(BOX.size.x * scale_k), roundi(BOX.size.y * scale_k))
	var mouth := mouth_point(pot, variant if not waiting else "")
	var mpp := POT_W_M / POT_W_PX
	_cam.size = BOX.size.y * mpp
	var right := cam_basis.x
	var up := cam_basis.y
	var back := cam_basis.z
	var off := (MOUTH - BOX.get_center()) * mpp   # the mouth this far off the box's middle
	_cam.basis = cam_basis
	_cam.position = mouth - right * off.x + up * off.y + back * 5.0
	_sun.basis = Basis.looking_at((right * 0.6 - up * 0.8 - back * 0.5).normalized(), up)   # from the screen's upper left

## Where the model's mouth is (its world): the `mouth` node of the shown variant (any `mouth` in a model without
## variants), else the top of the Big Pot's.
static func mouth_point(model: Node3D, variant: String) -> Vector3:
	var m := model.get_node_or_null((variant + "/mouth") if variant != "" else "mouth") as Node3D
	if m == null: m = model.find_child("mouth", true, false) as Node3D
	if m == null: return model.transform * Vector3(0, 0.18, 0)
	var t := Transform3D()
	var at: Node = m
	while at != null and at != model.get_parent():
		t = (at as Node3D).transform * t
		at = at.get_parent()
	return t.origin

## The pot's mouth on the screen now (design px): the ring's centre.
func mouth_screen() -> Vector2:
	return position + pivot_offset

## In from the stove pot's place (`from` its mouth on the screen, `from_scale` its size ÷ the box pot's) to the box.
func fly_in(from: Vector2, from_scale: float) -> void:
	visible = true
	_go(from, from_scale, MOUTH, 1.0, Callable())

## Back to the stove pot's place and size; `done` then (the host shows the stove's pot again).
func fly_out(to: Vector2, to_scale: float, done: Callable) -> void:
	_go(mouth_screen(), scale.x, to, to_scale, func():
		visible = false
		if done.is_valid(): done.call())

func _go(from: Vector2, from_scale: float, to: Vector2, to_scale: float, done: Callable) -> void:
	if _tween and _tween.is_valid(): _tween.kill()
	position = from - pivot_offset
	scale = Vector2.ONE * from_scale
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position", to - pivot_offset, FLY_S)
	_tween.tween_property(self, "scale", Vector2.ONE * to_scale, FLY_S)
	if done.is_valid(): _tween.chain().tween_callback(done)

## Settled in the box (tests, shots).
func settle() -> void:
	if _tween and _tween.is_valid(): _tween.kill()
	position = BOX.position
	scale = Vector2.ONE
