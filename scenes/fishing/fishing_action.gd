extends Button
## A single thumb target for casting, hooking and holding tension.
## SGODOT-480 (不知火舞's spec v1, 480 f104605d; the user: 「上钩的时候把hook按钮的效果做的更明显一些，加一些动效」): while a
## fish is on (hook, set by the panel) the key turns solid primary with white words and fish, pops once (POP_SCALE over
## POP_S, the fish swinging ±SWING_DEG twice), breathes (BREATH_SCALE, BREATH_S) and sends a primary ring RING_PX out at
## each breath's top; a bite whose window never closes (q(219)'s sure bite) pops again every REPOP_S with a REPOP_BUZZ_MS
## buzz. The ring (v1.1, 不知火舞 after the first recording: a primary one alone went unseen on the woods' green) is
## RING_WIDTH of surface with a RING_EDGE primary outline outside it, both fading. The look only: the key's place, size and tap area stay (_has_point is the unscaled key), the ring takes no taps,
## and it is the plain key again the moment the fish is hooked, gets away or the panel closes.

var progress := 0.0
var pulling := false
static var _symbol: Texture2D

const POP_SCALE := 1.18
const POP_S := 0.28
const SWING_DEG := 10.0
const BREATH_SCALE := 1.06
const BREATH_S := 0.6
const RING_PX := 18.0
const RING_WIDTH := 3.0   # surface
const RING_EDGE := 1.0    # primary, round its outside
const RING_ALPHA := 0.8
const REPOP_S := 2.5
const REPOP_BUZZ_MS := 40

var hooking := false   # a fish is on: the key stands out (hook())
var repop := false     # … and its window never closes: it pops again every REPOP_S
var _swing := SwingIcon.new()   # the icon, drawn turned while it swings
var _ring: Control
var _t := 0.0          # s since the fish came on
var _pop_t := -1.0     # s into the pop now (< 0: none)
var _next_pop := REPOP_S

func _ready() -> void:
	if _symbol == null:
		var pixels := GameUi.icon("fish").get_image()
		pixels.convert(Image.FORMAT_RGBA8)
		for y in pixels.get_height():
			for x in pixels.get_width(): pixels.set_pixel(x, y, Color(1, 1, 1, pixels.get_pixel(x, y).a))
		_symbol = ImageTexture.create_from_image(pixels)
		_symbol.set_size_override(Vector2i(24, 24))
	_swing.base = _symbol
	icon = _swing
	_ring = _Ring.new()
	_ring.name = "HookRing"
	_ring.show_behind_parent = true
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	add_child(_ring)
	set_process(hooking)   # hooking already only if hook() came before the tree (哪吒 on #979)
	visibility_changed.connect(func(): if not is_visible_in_tree(): hook(false))

## The fish on or off (the panel, each time it refreshes the key): on, the key stands out and pops; off, it is the plain
## key at once. `again`: the bite's window stays open (q(219)), so it pops again now and then.
func hook(on: bool, again := false) -> void:
	repop = on and again
	if on == hooking: return
	hooking = on
	_t = 0.0
	_next_pop = REPOP_S
	_pop_t = 0.0 if on else -1.0
	_swing.angle = 0.0
	scale = Vector2.ONE
	if _ring: _ring.visible = false   # null before _ready: nothing drawn yet either
	_paint()
	set_process(on)
	queue_redraw()

## Solid primary with white words and fish while hooking; the theme's own (AccentButton) otherwise.
func _paint() -> void:
	const STATES := ["normal", "hover", "pressed", "hover_pressed", "focus"]
	var font_of := func(s: String) -> String: return "font_color" if s == "normal" else "font_%s_color" % s   # Button's names
	if not hooking:
		for s in STATES:
			remove_theme_stylebox_override(s)
			remove_theme_color_override(font_of.call(s))
			remove_theme_color_override("icon_%s_color" % s)
		return
	var base := get_theme_stylebox(&"normal") as StyleBoxFlat
	for s in STATES:
		var sb := (base.duplicate() if base != null else StyleBoxFlat.new()) as StyleBoxFlat
		sb.bg_color = UiTokens.COLOR_PRIMARY.darkened(0.12) if s in ["pressed", "hover_pressed"] else UiTokens.COLOR_PRIMARY
		add_theme_stylebox_override(s, sb)
		add_theme_color_override(font_of.call(s), UiTokens.COLOR_SURFACE)
		add_theme_color_override("icon_%s_color" % s, UiTokens.COLOR_SURFACE)

func _process(dt: float) -> void:
	if not hooking: return
	step(dt)

## One frame of the hook's motion (tests drive it): the pop, the breath, the ring, the sure bite's next pop.
func step(dt: float) -> void:
	_t += dt
	if repop and _t >= _next_pop:
		_next_pop += REPOP_S
		_pop_t = 0.0
		Input.vibrate_handheld(REPOP_BUZZ_MS)
	var pop := 1.0
	_swing.angle = 0.0
	if _pop_t >= 0.0:
		_pop_t += dt
		var k := clampf(_pop_t / POP_S, 0.0, 1.0)
		pop = pop_scale(k)
		_swing.angle = deg_to_rad(SWING_DEG) * sin(TAU * 2.0 * k) if k < 1.0 else 0.0
		if k >= 1.0: _pop_t = -1.0
	pivot_offset = size * 0.5
	scale = Vector2.ONE * pop * breath_scale(_t)
	var ring := ring_at(_t)
	if _ring == null: return
	_ring.visible = ring.x >= 0.0
	if _ring.visible:
		_ring.size = size
		_ring.set("grow", ring.x)
		_ring.set("alpha", ring.y)
		_ring.queue_redraw()
	queue_redraw()

## The pop's scale at `k` (0..1 of POP_S): up to POP_SCALE quickly, back to 1 with a little overshoot (back easing).
static func pop_scale(k: float) -> float:
	const UP := 0.35
	if k <= 0.0 or k >= 1.0: return 1.0
	if k < UP: return lerpf(1.0, POP_SCALE, ease(k / UP, 0.4))
	var x := (k - UP) / (1.0 - UP) - 1.0   # back ease-out, from POP_SCALE to 1
	const C1 := 1.70158
	return lerpf(POP_SCALE, 1.0, 1.0 + (C1 + 1.0) * x * x * x + C1 * x * x)

## The breath at `t` s into the hook: 1 → BREATH_SCALE → 1 every BREATH_S (a sine).
static func breath_scale(t: float) -> float:
	return 1.0 + (BREATH_SCALE - 1.0) * 0.5 * (1.0 - cos(TAU * t / BREATH_S))

## The ring at `t`: (px out from the key's edge, alpha), sent at each breath's top; (-1, 0) before the first.
static func ring_at(t: float) -> Vector2:
	var since := t - BREATH_S * 0.5
	if since < 0.0: return Vector2(-1.0, 0.0)
	var k := fposmod(since, BREATH_S) / BREATH_S
	return Vector2(RING_PX * k, RING_ALPHA * (1.0 - k))

## The tap area is the key as laid out, whatever the pop or the breath make of it on screen.
func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(pivot_offset + (point - pivot_offset) * scale)

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 3
	if progress > 0:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 64, GameUi.GOLD, 3.0, true)
	if pulling:
		draw_arc(center, radius - 5, 0, TAU, 64, Color(GameUi.PAPER, 0.65), 1.5, true)

## The key's icon drawn through: turned about its middle by `angle` (the hook's swing), else exactly as the base draws.
class SwingIcon extends Texture2D:
	var base: Texture2D
	var angle := 0.0

	func _get_width() -> int: return base.get_width() if base else 1
	func _get_height() -> int: return base.get_height() if base else 1
	func _has_alpha() -> bool: return true

	func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
		_draw_rect(to_canvas_item, Rect2(pos, get_size()), false, modulate, transpose)

	func _draw_rect(to_canvas_item: RID, rect: Rect2, tile: bool, modulate: Color, transpose: bool) -> void:
		if base == null: return
		if angle == 0.0:
			base.draw_rect(to_canvas_item, rect, tile, modulate, transpose)
			return
		var c := rect.get_center()
		RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D(angle, c) * Transform2D(0.0, -c))
		base.draw_rect(to_canvas_item, rect, tile, modulate, transpose)
		RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D())

	func _draw_rect_region(to_canvas_item: RID, rect: Rect2, src_rect: Rect2, modulate: Color, transpose: bool, clip_uv: bool) -> void:
		if base == null: return
		if angle == 0.0:
			base.draw_rect_region(to_canvas_item, rect, src_rect, modulate, transpose, clip_uv)
			return
		var c := rect.get_center()
		RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D(angle, c) * Transform2D(0.0, -c))
		base.draw_rect_region(to_canvas_item, rect, src_rect, modulate, transpose, clip_uv)
		RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D())

## The ring behind the key: its rounded edge grown `grow` px — RING_WIDTH of surface inside, RING_EDGE of primary
## round it (v1.1: the cream shows on the woods, the green edge on the sand), both at `alpha`.
class _Ring extends Control:
	var grow := 0.0
	var alpha := 0.0

	func _draw() -> void:
		var key := get_parent() as Control
		var base := key.get_theme_stylebox(&"normal") as StyleBoxFlat if key else null
		var radius := float(base.corner_radius_top_left) if base else 16.0
		for band in [[UiTokens.COLOR_SURFACE, RING_WIDTH, 0.0], [UiTokens.COLOR_PRIMARY, RING_EDGE, RING_EDGE]]:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_border_width_all(int(band[1]))
			sb.border_color = Color(band[0], alpha)
			sb.set_corner_radius_all(int(radius + grow + float(band[2])))
			sb.anti_aliasing = true
			sb.draw(get_canvas_item(), Rect2(Vector2.ZERO, size).grow(grow + float(band[2])))
