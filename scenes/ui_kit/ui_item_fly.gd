class_name UiItemFly
extends Control
## ItemFly (Figma 14 · Gensen Refactor/ItemFly 1226:104639, B2-08; Count ×N on SGODOT-289): an item flying from where it
## came from to where it lands — the creel badge for a trap's fish, the quick bar's Bag for a row's harvest. One per item
## kind, the same kind merged as ×N (shown for ×1 too), at most MAX_PER_BATCH a batch, each DELAY_STEP_S after the last
## (289: 0.12 s). A 34 px cream disc (1 px border, soft shadow) with its 22 px icon, the count's pill beside it, three
## trail dots (4 / 6 / 8 px) pointing back where it came from; a 0.5 s arc. It never takes input.
##   UiItemFly.launch(host, from, to, icon, count, delay, on_land) → the flight, or null when `to` is gone or hidden (the
##   Bag under an open drawer: no flight, q(49)). on_land runs as it reaches `to`; bump(to) is the landing's ×1.08.

signal landed

const DISC := 34.0
const ICON := 22.0
const FLIGHT_S := 0.5
const ARC_LIFT := 0.35         # the arc's height, of the flight's length
const MAX_PER_BATCH := 3
const DELAY_STEP_S := 0.12     # 289: one kind after another
const BUMP := 1.08             # the target's bump on each landing (TRAP-COLLECT-2)
const BUMP_S := 0.16
const TRAIL := [[4.0, 0.7], [6.0, 0.8], [8.0, 0.9]]   # dot size, alpha, from the tail in (#FBF8F1)
const TRAIL_GAP := 4.0

var count := 1
var from := Vector2.ZERO
var to: Control
var _t := 0.0
var _delay := 0.0
var _dir := Vector2.RIGHT
var _on_land := Callable()
var _disc: Panel
var _pill: PanelContainer

## Starts a flight on `host` (a full-screen layer) from screen point `from` to the middle of `to`; null when `to` is
## missing or not visible (the caller then says it some other way).
static func launch(host: Control, from_: Vector2, to_: Control, icon: Texture2D, count_ := 1, delay := 0.0, on_land := Callable()) -> UiItemFly:
	if host == null or to_ == null or not is_instance_valid(to_) or not to_.is_visible_in_tree(): return null
	var f := UiItemFly.new(icon, count_)
	f.from = from_
	f.to = to_
	f._delay = delay
	f._on_land = on_land
	host.add_child(f)
	f._place(from_)
	f.visible = delay <= 0.0
	return f

## The landing's bump on the target (×1.08 and back, about its middle).
static func bump(target: Control, peak := BUMP) -> void:
	if target == null or not is_instance_valid(target): return
	target.pivot_offset = target.size * 0.5
	var tw := target.create_tween()
	tw.tween_property(target, "scale", Vector2.ONE * peak, BUMP_S * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "scale", Vector2.ONE, BUMP_S * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _init(icon: Texture2D = null, count_ := 1) -> void:
	count = count_
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(DISC, DISC)
	_disc = Panel.new()
	_disc.name = "Disc"
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, DISC * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT   # the disc's lift (Figma 0 3 6 ink 22 %)
	box.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
	_disc.add_theme_stylebox_override(&"panel", box)
	_disc.size = Vector2(DISC, DISC)
	add_child(_disc)
	var pic := TextureRect.new()
	pic.name = "Icon"
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.texture = icon
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.position = Vector2(DISC - ICON, DISC - ICON) * 0.5
	pic.size = Vector2(ICON, ICON)
	_disc.add_child(pic)
	_pill = PanelContainer.new()
	_pill.name = "Count"
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := UiStyleBox.make(UiTokens.COLOR_SURFACE, 8)
	pill.shadow_color = UiTokens.COLOR_SHADOW_KEY
	pill.shadow_size = 2.0
	pill.shadow_offset = Vector2(0, 1)
	_pill.add_theme_stylebox_override(&"panel", pill.with_margins(5, 1, 5, 1))
	var n := UiKit.label("×%d" % count, UiTokens.STYLE_C11_XB)
	n.name = "Text"
	_pill.add_child(n)
	add_child(_pill)
	_pill.position = Vector2(DISC + 4.0, (DISC - 17.0) * 0.5)

func count_text() -> String: return "×%d" % count

func _process(dt: float) -> void:
	if _delay > 0.0:
		_delay -= dt
		if _delay > 0.0: return
		visible = true
	if not is_instance_valid(to):
		queue_free()
		return
	_t = minf(1.0, _t + dt / FLIGHT_S)
	var end := to.get_global_rect().get_center()
	var k := ease(_t, -1.8)   # in-out
	var flat := from.lerp(end, k)
	var lift := Vector2(0, -from.distance_to(end) * ARC_LIFT * 4.0 * k * (1.0 - k))
	var at := flat + lift
	var was := global_position + size * 0.5
	if at.distance_to(was) > 0.5: _dir = (at - was).normalized()
	_place(at)
	scale = Vector2.ONE * lerpf(1.0, 0.7, maxf(0.0, (_t - 0.7) / 0.3))
	queue_redraw()
	if _t >= 1.0:
		landed.emit()
		if _on_land.is_valid(): _on_land.call()
		queue_free()

func _place(centre: Vector2) -> void:
	global_position = centre - size * 0.5

## The trail: three dots behind the disc, pointing back the way it came.
func _draw() -> void:
	var c := size * 0.5
	var back := -_dir
	var d := DISC * 0.5 + TRAIL_GAP
	for i in range(TRAIL.size() - 1, -1, -1):   # 8 nearest the disc, 4 at the tail
		var r := float(TRAIL[i][0]) * 0.5
		d += r
		draw_circle(c + back * d, r, Color(UiTokens.COLOR_SURFACE, float(TRAIL[i][1])))
		d += r + TRAIL_GAP
