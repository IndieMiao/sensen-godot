class_name UiChipToken
extends Control
## ChipToken (SGODOT-351, 不知火舞 on 351 7cdf40a9 ①): a 48 betting chip on the Blackjack table — Value 5 / 10 / 50 /
## 100 / 500 / 1K × State Default / Disabled / Dragging. A coloured disc, a ring of six stripes and the value in the
## middle; 5 green, 10 blue, 50 red, 100 orange (kept apart from the coins capsule's gold), 500 purple, 1K ink with a gold
## edge, all from the kit palette. Disabled is greyed; Dragging draws 1.1× with a drop shadow. Display only: the tray
## handles the touch. Drawn here until 安其拉's master lands (bd0fced2); colours and the stripe ring follow it then.

enum State { DEFAULT, DISABLED, DRAGGING }

const SIZE := 48.0
const DRAG_SCALE := 1.1
const _STRIPES := 6
const _STRIPE_W := 0.22   # of each sixth of the ring
const _RING := 6.0        # stripe ring width
const _INNER := 0.70      # inner disc radius, of the whole
## Fill and edge per value (kit palette: primary, tackle blue, danger, gift coral, event violet, ink with gold deep).
const COLORS := {
	5: [Color("3E7D43"), Color("FBF8F1")],
	10: [Color("2C6A8E"), Color("FBF8F1")],
	50: [Color("9C3F2E"), Color("FBF8F1")],
	100: [Color("E07A5F"), Color("FBF8F1")],
	500: [Color("8D75ED"), Color("FBF8F1")],
	1000: [Color("2F3A33"), Color("D9A521")],
}

var value := 5: set = set_value
var state: State = State.DEFAULT: set = set_state

var _label: Label

func _init(value_ := 5, state_: State = State.DEFAULT) -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	pivot_offset = custom_minimum_size * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiKit.label("", UiTokens.STYLE_BODY_XB14, UiTokens.COLOR_SURFACE)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	value = value_
	state = state_

func set_value(v: int) -> void:
	value = v
	if _label != null: _label.text = P0Blackjack.chip_label(v)
	queue_redraw()

func set_state(v: State) -> void:
	state = v
	scale = Vector2.ONE * (DRAG_SCALE if v == State.DRAGGING else 1.0)
	if _label != null: _label.modulate = Color(1, 1, 1, 0.75) if v == State.DISABLED else Color.WHITE
	queue_redraw()

func fill_color() -> Color:
	var c: Color = COLORS.get(value, COLORS[5])[0]
	return UiTokens.COLOR_DISABLED_INK if state == State.DISABLED else c

func _draw() -> void:
	var r := SIZE * 0.5
	var c := Vector2(r, r)
	var pair: Array = COLORS.get(value, COLORS[5])
	var fill := fill_color()
	var edge: Color = UiTokens.COLOR_DISABLED if state == State.DISABLED else pair[1]
	if state == State.DRAGGING: draw_circle(c + Vector2(0, 4), r, UiTokens.COLOR_LIFT_SHADOW)
	draw_circle(c, r, fill)
	# six stripes on the rim
	for i in _STRIPES:
		var a0 := TAU * i / _STRIPES - TAU / _STRIPES * _STRIPE_W * 0.5
		var a1 := a0 + TAU / _STRIPES * _STRIPE_W
		var pts := PackedVector2Array()
		for k in 7:
			var a := lerpf(a0, a1, k / 6.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		for k in 7:
			var a := lerpf(a1, a0, k / 6.0)
			pts.append(c + Vector2(cos(a), sin(a)) * (r - _RING))
		draw_colored_polygon(pts, edge)
	draw_arc(c, r * _INNER, 0.0, TAU, 48, UiKit.alpha(edge, 0.85), 1.5, true)
	if value == 1000 and state != State.DISABLED: draw_arc(c, r - 0.75, 0.0, TAU, 48, pair[1], 1.5, true)
