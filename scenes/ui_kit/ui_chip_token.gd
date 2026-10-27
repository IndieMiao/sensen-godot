class_name UiChipToken
extends Control
## ChipToken 171:165648 (SGODOT-351; 安其拉, accepted by 不知火舞 on 351 f14b3bba): a 48 betting chip on the Blackjack
## table — Value 5 / 10 / 50 / 100 / 500 / 1K × State Default / Disabled / Dragging. A coloured rim with eight notches,
## a white core ringed in the rim colour and the value in the value's deep colour: 5 #5FA85A, 10 #4F8FCB, 50 #D9614A,
## 100 #E8893A, 500 #9576CF, 1K ink #2F3A33 with gold notches #F0D75E. Disabled mixes the rim 80% toward #D6D5CE with the
## number #8A918C; Dragging draws 1.1× with a drop shadow. Display only: the tray handles the touch.

enum State { DEFAULT, DISABLED, DRAGGING }

const SIZE := 48.0
const DRAG_SCALE := 1.1
const _NOTCHES := 8
const _NOTCH := Vector2(4.0, 5.0)   # each notch across × along the radius, on the rim
const _CORE := 15.0                 # white core radius
const _CORE_RING := 13.0            # the thin rim-coloured ring inside the core
## Rim, notches and number per value.
const COLORS := {
	5: [Color("5FA85A"), Color.WHITE, Color("3E7D43")],
	10: [Color("4F8FCB"), Color.WHITE, Color("2C6A8E")],
	50: [Color("D9614A"), Color.WHITE, Color("9C3F2E")],
	100: [Color("E8893A"), Color.WHITE, Color("A85A1C")],
	500: [Color("9576CF"), Color.WHITE, Color("5F4596")],
	1000: [Color("2F3A33"), Color("F0D75E"), Color("2F3A33")],
}

var value := 5: set = set_value
var state: State = State.DEFAULT: set = set_state

var _label: Label

func _init(value_ := 5, state_: State = State.DEFAULT) -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	pivot_offset = custom_minimum_size * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiKit.label("", UiTokens.STYLE_C13_XB)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	value = value_
	state = state_

func set_value(v: int) -> void:
	value = v
	if _label != null:
		_label.text = P0Blackjack.chip_label(v)
		_label.add_theme_font_size_override(&"font_size", 11 if _label.text.length() >= 3 else 13)
	set_state(state)

func set_state(v: State) -> void:
	state = v
	scale = Vector2.ONE * (DRAG_SCALE if v == State.DRAGGING else 1.0)
	if _label != null:
		_label.add_theme_color_override(&"font_color", UiTokens.COLOR_DISABLED_INK if v == State.DISABLED else _pair()[2])
	queue_redraw()

func _pair() -> Array: return COLORS.get(value, COLORS[5])

func fill_color() -> Color:
	var c: Color = _pair()[0]
	return c.lerp(UiTokens.COLOR_DISABLED, 0.8) if state == State.DISABLED else c

func _draw() -> void:
	var r := SIZE * 0.5
	var c := Vector2(r, r)
	var rim := fill_color()
	var notch: Color = _pair()[1]
	if state == State.DISABLED: notch = notch.lerp(UiTokens.COLOR_DISABLED, 0.5)
	if state == State.DRAGGING: draw_circle(c + Vector2(0, 4), r, UiTokens.COLOR_LIFT_SHADOW)
	draw_circle(c, r, rim)
	for i in _NOTCHES:
		var a := TAU * i / _NOTCHES
		var dir := Vector2(cos(a), sin(a))
		var mid := c + dir * (r - _NOTCH.y * 0.5 - 1.5)
		var side := Vector2(-dir.y, dir.x) * _NOTCH.x * 0.5
		var along := dir * _NOTCH.y * 0.5
		draw_colored_polygon(PackedVector2Array([mid - side - along, mid + side - along, mid + side + along, mid - side + along]), notch)
	draw_circle(c, _CORE, Color.WHITE if state != State.DISABLED else UiTokens.COLOR_SURFACE)
	draw_arc(c, _CORE_RING, 0.0, TAU, 48, rim, 1.0, true)
