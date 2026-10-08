class_name UiTapCard
extends Control
## TapCard 1135:101133 (SGODOT-221, LOCK-07): the finger card that floats over a facility the player is near,
## e.g. `Tap to cook`, `Rest · +60 Energy · once a day`, `Mei · Tap to talk`. A 32 px pill with the tap glyph,
## one line of copy and a pointer under it. Track it with WorldAnchor (bottom centre = the pointer tip at the
## facility's `use_` anchor); WorldAnchor calls point_at() after clamping so the pointer stays on the facility
## near the screen edges (the main's Pointer=Left / Center / Right are the ends of that range).
## Tapping the card does what tapping the facility does: `tapped`, only for a real tap (WP7-B F-04 §2: moved at
## most TAP_SLOP and released within TAP_MAX_MS), so a drag that starts on the card never opens the facility.
## `passive` cards take no touches at all: the scene layer under them then sees the press (the joystick can start
## on a card) and its owner resolves a tap on hit_rect() itself (P0Ui does, PR #12 review).

signal tapped

const TAP_GLYPH := preload("res://assets/ui/kit_icons/tap.svg")
const _PAD_X := 12.0              # TapCard auto-layout padding 7 / 12, gap 6
const _PAD_Y := 7.0
const _POINTER_INSET := 14.0      # Pointer=Left sits 14 px in from the left, Right 14 px from the right

var text := "": set = set_text
var passive := false: set = set_passive

var _down_at := Vector2.INF
var _down_ms := 0

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

func set_passive(v: bool) -> void:
	passive = v
	if _card: _card.mouse_filter = Control.MOUSE_FILTER_IGNORE if v else Control.MOUSE_FILTER_STOP

## The card's touch area in this control's parent space: the 32 px pill grown to the 44 px touch height.
func hit_rect() -> Rect2:
	var r := _card.get_global_rect()
	return r.grow_individual(0, (UiTokens.SIZE_TOUCH - r.size.y) * 0.5, 0, (UiTokens.SIZE_TOUCH - r.size.y) * 0.5)

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

## One event family only, as ModalStack's scrim: mouse buttons (touch is emulated as the mouse on phones), raw
## touches only where no touchscreen emulation runs — so one finger is never counted twice.
func _on_input(e: InputEvent) -> void:
	var is_mouse: bool = e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT
	var is_touch: bool = e is InputEventScreenTouch and not DisplayServer.is_touchscreen_available()
	if not (is_mouse or is_touch): return
	accept_event()
	if e.pressed:
		_down_at = e.position
		_down_ms = Time.get_ticks_msec()
		return
	var tap: bool = _down_at != Vector2.INF and e.position.distance_to(_down_at) <= GestureArbiter.TAP_SLOP \
		and Time.get_ticks_msec() - _down_ms <= GestureArbiter.TAP_MAX_MS
	_down_at = Vector2.INF
	if tap: tapped.emit()
