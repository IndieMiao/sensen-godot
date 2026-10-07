class_name UiTapCard
extends Control
## TapCard 1135:101133 (SGODOT-221, LOCK-07): the finger card that floats over a facility the player is near,
## e.g. `Tap to cook`, `Rest · +60 Energy · once a day`, `Mei · Tap to talk`. A 32 px pill with the tap glyph,
## one line of copy and a pointer under it. Track it with WorldAnchor (bottom centre = the pointer tip at the
## facility's `use_` anchor); WorldAnchor calls point_at() after clamping so the pointer stays on the facility
## near the screen edges (the main's Pointer=Left / Center / Right are the ends of that range).
## Tapping the card does what tapping the facility does: `tapped`.

signal tapped

const TAP_GLYPH := preload("res://assets/ui/kit_icons/tap.svg")
const _PAD_X := 12.0              # TapCard auto-layout padding 7 / 12, gap 6
const _PAD_Y := 7.0
const _POINTER_INSET := 14.0      # Pointer=Left sits 14 px in from the left, Right 14 px from the right

var text := "": set = set_text

var _card: PanelContainer
var _label: Label
var _pointer: UiPointer
var _aim := NAN   # last point_at() target; NAN = centred

func _init(text_ := "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := UiTokens.SIZE_TAP_CARD_H
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, h * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
	box.with_margins(_PAD_X, _PAD_Y, _PAD_X, _PAD_Y)
	_card.add_theme_stylebox_override(&"panel", box)
	_card.custom_minimum_size.y = h
	_card.gui_input.connect(_on_input)
	add_child(_card)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	_card.add_child(row)
	var glyph := UiKit.icon(TAP_GLYPH, UiTokens.SIZE_TAP_GLYPH)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)
	_label = UiKit.label("", UiTokens.STYLE_CAPTION_XB12)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_label)
	_pointer = UiPointer.new()
	add_child(_pointer)
	_card.resized.connect(_layout)
	_card.minimum_size_changed.connect(_layout)
	text = text_

func set_text(v: String) -> void:
	text = v
	if _label: _label.text = v

func _get_minimum_size() -> Vector2:
	if _card == null: return Vector2.ZERO
	var c := _card.get_combined_minimum_size()
	return Vector2(c.x, c.y + UiTokens.SIZE_POINTER_H)

## Local x of the facility inside this card; the pointer's tip goes there, kept clear of the rounded ends.
func point_at(local_x: float) -> void:
	_aim = local_x
	_aim_pointer()

func _aim_pointer() -> void:
	var local_x := _card.size.x * 0.5 if is_nan(_aim) else _aim
	var w := _card.size.x
	var half := UiTokens.SIZE_POINTER_W * 0.5
	var tip := clampf(local_x, _POINTER_INSET + half, maxf(_POINTER_INSET + half, w - _POINTER_INSET - half))
	_pointer.position = Vector2(tip - half, _card.size.y)

func pointer_tip_x() -> float: return _pointer.position.x + UiTokens.SIZE_POINTER_W * 0.5

func _layout() -> void:
	if _pointer == null: return
	_card.position = Vector2.ZERO
	_card.size = _card.get_combined_minimum_size()
	_aim_pointer()   # keep the last aim when the copy changes size
	update_minimum_size()

func _on_input(e: InputEvent) -> void:
	var up: bool = (e is InputEventScreenTouch and not e.pressed) or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed)
	if up:
		accept_event()
		tapped.emit()
