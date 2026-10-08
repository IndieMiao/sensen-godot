class_name UiHeatRing
extends Control
## HeatRing 483:355 (SGODOT-226, LOCK-20; plan §7.2.4): the heat ring over the 3D pot. A 120 px cream disc with
## an 8 px track (r 42–50), the gold timing zone and a needle that turns once from 12 o'clock. `gold` / `width`
## are fractions of the turn (the server's heat), `turn` 0–1 the needle. `grow` scales the ring in during the
## second before it starts. `result` marks the judged ring: 1 hit (gold dot), 0 miss (border dot), -1 none.
## Display only: the whole pot takes the tap.

const _SIDE := 120.0
const _OUTER := 50.0
const _TRACK := 8.0
const _NEEDLE := Vector2(3, 43)
const _MARK := 9.0
const _SEGMENTS := 64

var gold := 0.25: set = set_gold
var width := 0.35: set = set_width
var turn := 0.0: set = set_turn
var grow := 1.0: set = set_grow
var result := -1: set = set_result

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

func _draw() -> void:
	var c := Vector2(_SIDE, _SIDE) * 0.5
	var r := _OUTER - _TRACK * 0.5
	draw_arc(c, r, 0.0, TAU, _SEGMENTS, UiTokens.COLOR_BORDER, _TRACK, true)
	var g0 := -PI * 0.5 + TAU * gold
	draw_arc(c, r, g0, g0 + TAU * width, _SEGMENTS, UiTokens.COLOR_GOLD, _TRACK, true)
	var ang := -PI * 0.5 + TAU * turn
	var dir := Vector2(cos(ang), sin(ang))
	draw_line(c, c + dir * _NEEDLE.y, UiTokens.COLOR_TEXT, _NEEDLE.x, true)
	draw_circle(c, _NEEDLE.x, UiTokens.COLOR_TEXT, true, -1.0, true)
	if result >= 0:
		var at := c + Vector2(r * 0.7, -r * 0.7)
		draw_circle(at, _MARK, UiTokens.COLOR_GOLD if result == 1 else UiTokens.COLOR_BORDER, true, -1.0, true)
