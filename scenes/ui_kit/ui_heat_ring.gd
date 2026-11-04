class_name UiHeatRing
extends Control
## HeatRing 483:355 (SGODOT-226, LOCK-20; plan §7.2.4): the heat ring over the 3D pot. A 120 px cream disc with
## an 8 px track (r 42–50), the gold timing zone and a needle that turns once from 12 o'clock. `gold` / `width`
## are fractions of the turn (the server's heat), `turn` 0–1 the needle. `grow` scales the ring in during the
## second before it starts. `result` marks the judged ring: 1 hit, 0 miss, -1 none. The dot sits on the track where the
## needle was when it was judged (`mark_turn`, 0–1 like `turn`; -1 = where it is now), not at a fixed spot (用户 int10c,
## SGODOT-256 ⑩), and the needle stops on it until the ring folds away (不知火舞 on #131): a hit is gold-deep, a miss
## the disabled ink, both with a 2 px surface edge, the track's width + 6 across.
## q(288) (SGODOT-419; 不知火舞's spec v1 419 cd072712, LOCK-20 reviewed with it): `start` the needle's starting place
## (laps from 12 o'clock; the gold is placed from it), marked by a small tick outside the track; `ring` the laps the ring
## has drifted since (negative: anticlockwise) — the track, its gold, the tick and the result dot all turn with it, the
## needle does not. The track goes raw → done → burnt from the start along the needle's way, the gold full and thicker
## between two hard deep-gold edges: what is drawn gold is what hits. Both 0: from 12 o'clock, as before.
## Display only: the whole pot takes the tap.

const _SIDE := 120.0
const _OUTER := 50.0
const OUTER := _OUTER   # the track's outer radius at scale 1 (a host places things by the ring's edge)
const _TRACK := 8.0
const _NEEDLE := Vector2(3, 43)
const _MARK := (_TRACK + 6.0) * 0.5   # the result dot's radius: the track's width + 6 across (不知火舞 on #131)
const _MARK_EDGE := 2.0
const _SEGMENTS := 64
const _GOLD_IN := 40.0     # the gold zone, thicker than the track (r 40–52)
const _GOLD_OUT := 52.0
const _GOLD_EDGE := 2.0
const _TICK := Vector2(2, 6)   # the start's tick, outside the track

var gold := 0.25: set = set_gold
var width := 0.35: set = set_width
var turn := 0.0: set = set_turn
var grow := 1.0: set = set_grow
var result := -1: set = set_result
var mark_turn := -1.0: set = set_mark_turn
var start := 0.0: set = set_start
var ring := 0.0: set = set_ring
var _judged_ring := 0.0   # `ring` when the ring was judged: the result dot turns on with the ring from there

func _init() -> void:
	custom_minimum_size = Vector2(_SIDE, _SIDE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = custom_minimum_size * 0.5

func set_gold(v: float) -> void: gold = v; queue_redraw()
func set_width(v: float) -> void: width = v; queue_redraw()
func set_turn(v: float) -> void: turn = clampf(v, 0.0, 1.0); queue_redraw()
func set_grow(v: float) -> void:
	grow = clampf(v, 0.0, 1.0)
	scale = Vector2.ONE * lerpf(0.4, 1.0, grow)
func set_result(v: int) -> void: result = v; queue_redraw()
func set_mark_turn(v: float) -> void:
	if v >= 0.0 and mark_turn < 0.0: _judged_ring = ring
	mark_turn = v
	queue_redraw()
func set_start(v: float) -> void: start = v; queue_redraw()
func set_ring(v: float) -> void: ring = v; queue_redraw()

## Where the needle points (0–1): on its dot once the ring is judged, else turning.
func needle_turn() -> float:
	return clampf(mark_turn, 0.0, 1.0) if result >= 0 and mark_turn >= 0.0 else turn

## Where the result dot goes (this control's coordinates): on the track at the judged needle's angle.
func mark_point() -> Vector2:
	var t := turn if mark_turn < 0.0 else clampf(mark_turn, 0.0, 1.0)
	var ang := -PI * 0.5 + TAU * (start + t + (ring - _judged_ring if mark_turn >= 0.0 else 0.0))
	return Vector2(_SIDE, _SIDE) * 0.5 + Vector2(cos(ang), sin(ang)) * (_OUTER - _TRACK * 0.5)

## The track's colour `p` of the lap from the start (0–1): raw to near-gold before the gold, burnt after it.
func track_color(p: float) -> Color:
	var g1 := gold + width
	if p < gold: return UiTokens.COLOR_BORDER.lerp(UiTokens.COLOR_HEAT_NEAR, p / maxf(gold, 0.0001))   # raw to near-gold
	if p <= g1: return UiTokens.COLOR_GOLD
	return UiTokens.COLOR_HEAT_PAST.lerp(UiTokens.COLOR_HEAT_BURNT, (p - g1) / maxf(1.0 - g1, 0.0001))   # past to burnt

func _draw() -> void:
	var c := Vector2(_SIDE, _SIDE) * 0.5
	var r := _OUTER - _TRACK * 0.5
	var base := start + ring   # the start's place on the screen now
	var step := TAU / _SEGMENTS
	for i in _SEGMENTS:
		var a0 := -PI * 0.5 + TAU * base + step * i
		draw_arc(c, r, a0, a0 + step * 1.02, 3, track_color((i + 0.5) / _SEGMENTS), _TRACK, true)   # 2 % over: no seams
	var g0 := -PI * 0.5 + TAU * (base + gold)
	var gr := (_GOLD_IN + _GOLD_OUT) * 0.5
	draw_arc(c, gr, g0, g0 + TAU * width, _SEGMENTS, UiTokens.COLOR_GOLD, _GOLD_OUT - _GOLD_IN, true)
	for a in [g0, g0 + TAU * width]:
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * _GOLD_IN, c + d * _GOLD_OUT, UiTokens.COLOR_GOLD_DEEP, _GOLD_EDGE, true)
	var s0 := -PI * 0.5 + TAU * base
	var sd := Vector2(cos(s0), sin(s0))
	draw_line(c + sd * (_OUTER + 1.0), c + sd * (_OUTER + 1.0 + _TICK.y), Color(UiTokens.COLOR_TEXT, 0.4), _TICK.x, true)
	var ang := -PI * 0.5 + TAU * (start + needle_turn())
	var dir := Vector2(cos(ang), sin(ang))
	draw_line(c, c + dir * _NEEDLE.y, UiTokens.COLOR_TEXT, _NEEDLE.x, true)
	draw_circle(c, _NEEDLE.x, UiTokens.COLOR_TEXT, true, -1.0, true)
	if result >= 0:
		draw_circle(mark_point(), _MARK, UiTokens.COLOR_SURFACE, true, -1.0, true)
		draw_circle(mark_point(), _MARK - _MARK_EDGE, UiTokens.COLOR_GOLD_DEEP if result == 1 else UiTokens.COLOR_DISABLED_INK, true, -1.0, true)
