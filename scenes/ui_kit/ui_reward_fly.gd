class_name UiRewardFly
extends Control
## C-185 MS-04 / MS-05 (C-186): the v3 reward flight, apart from P0's UiItemFly (its cream disc, trail and ×N pill stay
## on the main farm). The item's 32 icon alone, no disc, no trail, no count — the float says how many (MS-06):
##   reward (harvest, gather, a gift): pops 0 → 1.15 → 1 at the source in 200 (pop), holds 120, then flies a quadratic
##     bézier (control point MOTION_OFFSET_FLY_ARC above the midpoint) over 520 (arc easing), shrinking to 0.6;
##   pickup (an egg, milk, wool, after the 3D hop to the chest): pops 200 above the head and flies at once (~720).
## on_land runs as it reaches the middle of `to`; the caller bumps the target (UiMotion.land) and rolls its count.
## A batch is one icon per kind, MOTION_STAGGER_MS_REWARD apart, at most MOTION_LIMIT_REWARD_ICONS (the rest only count).
## Reduced motion (UiMotion.reduced): nothing flies; on_land runs after the delay, so the target still bumps and counts.
## Never takes input. launch() returns null when `to` is missing or hidden (the Bag under an open panel): no flight.

signal landed

const ICON := 32.0

var from := Vector2.ZERO
var to: Control
var pickup := false
var _t := 0.0          # seconds since the delay ended
var _delay := 0.0
var _on_land := Callable()
var _icon: TextureRect
var _done := false

static func pop_s() -> float: return UiTokens.MOTION_DURATION_BASE_MS / 1000.0
static func hold_s(pickup_ := false) -> float: return 0.0 if pickup_ else UiTokens.MOTION_DURATION_REWARD_HOLD_MS / 1000.0
static func fly_s() -> float: return UiTokens.MOTION_DURATION_FLY_MS / 1000.0
## From launch (after any delay) to reaching the target: 840 for a reward, 720 for a pickup; 0 with reduced motion.
static func duration_s(pickup_ := false) -> float:
	return 0.0 if UiMotion.reduced else pop_s() + hold_s(pickup_) + fly_s()
## The delay of the `index`-th icon of a batch.
static func stagger_s(index: int) -> float: return index * UiTokens.MOTION_STAGGER_MS_REWARD / 1000.0

## Starts a flight on `host` (a full-screen layer) from screen point `from_` to the middle of `to_`; null when `to_` is
## missing or not visible (the caller then says it some other way).
static func launch(host: Control, from_: Vector2, to_: Control, icon: Texture2D, delay := 0.0, on_land := Callable(),
		pickup_ := false) -> UiRewardFly:
	if host == null or to_ == null or not is_instance_valid(to_) or not to_.is_visible_in_tree(): return null
	var f := UiRewardFly.new(icon)
	f.from = from_
	f.to = to_
	f.pickup = pickup_
	f._delay = delay
	f._on_land = on_land
	host.add_child(f)
	f._place(from_)
	f.scale = Vector2.ZERO if not UiMotion.reduced else Vector2.ONE
	f.visible = false
	return f

func _init(icon: Texture2D = null) -> void:
	name = "RewardFly"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(ICON, ICON)
	pivot_offset = size * 0.5
	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.texture = icon
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_icon)

func icon() -> Texture2D: return _icon.texture

func _process(dt: float) -> void:
	if _done: return
	if _delay > 0.0:
		_delay -= dt
		if _delay > 0.0: return
	if not is_instance_valid(to):
		queue_free()
		return
	if UiMotion.reduced:
		_land()
		return
	visible = true
	_t += dt
	var pop := pop_s()
	var hold := hold_s(pickup)
	var fly := fly_s()
	if _t < pop:
		# 0 → 1.15 → 1: back-out overshoot.
		scale = Vector2.ONE * _back_out(_t / pop)
		_place(from)
		return
	if _t < pop + hold:
		scale = Vector2.ONE
		_place(from)
		return
	var k := clampf((_t - pop - hold) / fly, 0.0, 1.0)
	var e := ease(k, -2.0)   # arc: quad in-out
	var end := to.get_global_rect().get_center()
	var ctrl := (from + end) * 0.5 - Vector2(0, UiTokens.MOTION_OFFSET_FLY_ARC)
	var a := from.lerp(ctrl, e)
	var b := ctrl.lerp(end, e)
	_place(a.lerp(b, e))
	scale = Vector2.ONE * lerpf(1.0, UiTokens.MOTION_SCALE_FLY_END, e)
	if k >= 1.0: _land()

func _land() -> void:
	_done = true
	landed.emit()
	if _on_land.is_valid(): _on_land.call()
	queue_free()

## 0 → 1 with a back-out overshoot of ≈ 15 % (MOTION_SCALE_REWARD_POP 1.15; s = 2.15 peaks at 1.149).
static func _back_out(x: float) -> float:
	var s := 2.15
	var y := x - 1.0
	return 1.0 + y * y * ((s + 1.0) * y + s)

func _place(centre: Vector2) -> void:
	global_position = centre - size * 0.5
