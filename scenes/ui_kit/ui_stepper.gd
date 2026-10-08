class_name UiStepper
extends Control
## Compact/Stepper 1245:108953 (SGODOT-224, C1-01): the quantity picker left of an outlined Buy on a counter row.
## A 76 × 34 white pill (radius 17, hairline) inside a 44 px touch row: − value +. `value` stays in [1, max_value];
## the − / + ends grey out at the limits. Emits `changed(value)`.

signal changed(value: int)

# Stepper surface: − at x 5 (20 wide), the value box at x 26 (24 wide), + at x 51 (20 wide); glyphs 16 XB.
const _W := 76.0
const _END_W := 25.0

var value := 1: set = set_value
var max_value := 99: set = set_max_value

var _minus: Button
var _plus: Button
var _value: Label

func _init(max_ := 99) -> void:
	custom_minimum_size = Vector2(_W, UiTokens.SIZE_TOUCH)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface := Panel.new()
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED,
		UiTokens.RADIUS_COMPACT_COMMAND, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
	surface.position = Vector2(0, (UiTokens.SIZE_TOUCH - UiTokens.SIZE_COMMAND_COMPACT) * 0.5)
	surface.size = Vector2(_W, UiTokens.SIZE_COMMAND_COMPACT)
	add_child(surface)
	_minus = _end("−", 0.0)
	_minus.pressed.connect(func(): _step(-1))
	_plus = _end("+", _W - _END_W)
	_plus.pressed.connect(func(): _step(1))
	_value = UiKit.label("1", UiTokens.STYLE_C12_XB)
	_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.position = Vector2(_END_W, 0)
	_value.size = Vector2(_W - _END_W * 2.0, UiTokens.SIZE_TOUCH)
	add_child(_value)
	max_value = max_
	_refresh()

## One end: a flat button the full 44 px tall (touch row), its glyph centred.
func _end(glyph: String, x: float) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = Vector2(x, 0)
	b.size = Vector2(_END_W, UiTokens.SIZE_TOUCH)
	var l := UiKit.label(glyph, UiTokens.STYLE_C14_XB, UiTokens.COLOR_SECONDARY)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(l)
	add_child(b)
	return b

func set_value(v: int) -> void:
	var c := clampi(v, 1, maxi(1, max_value))
	var moved := c != value
	value = c
	_refresh()
	if moved: changed.emit(value)

func set_max_value(v: int) -> void:
	max_value = maxi(1, v)
	if value > max_value: set_value(max_value)
	else: _refresh()

func _step(d: int) -> void: set_value(value + d)

func _refresh() -> void:
	if _value == null: return
	_value.text = str(value)
	_minus.disabled = value <= 1
	_plus.disabled = value >= max_value
	for b in [_minus, _plus]:
		(b.get_child(0) as Label).add_theme_color_override(&"font_color", UiTokens.COLOR_DISABLED_INK if b.disabled else UiTokens.COLOR_SECONDARY)
