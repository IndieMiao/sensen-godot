class_name UiPinMenu
extends Control
## PinMenu 1141:80291 (SGODOT-221, LOCK-05; plan §10.3.3): the result bubble of a long press on a quick slot.
## The pin state toggles when the finger lifts (no second tap; 不知火舞 2026-10-07 on SGODOT-221); the bubble then
## shows the NEW state and undoes it in one tap: after pinning `Unpin` with the slot's pin badge +
## "Pinned slots stay when the bar refills"; after unpinning `Pin` + "Pin to keep it when the bar refills".
## The pointer sits under the slot it belongs to: set `pointer_x` to that slot's centre in local x.
## Emits `toggled` when the button is tapped (the owner flips the pin and closes the card), and `dismissed`
## after DISMISS_S or on any press outside the card (the press still goes through). One at a time is the
## owner's job; a long press that turns into a drag never opens one (UiQuickBar emits no pin_toggled).

signal toggled
signal dismissed

const PIN_GLYPH := preload("res://assets/ui/kit_icons/pin.svg")
const NOTE_PINNED := "Pinned slots stay when the bar refills"
const NOTE_UNPINNED := "Pin to keep it when the bar refills"
const DISMISS_S := 3.0     # the main's description: dismisses after 3 s
const _POINTER_X := 19.0   # PinMenu pointer at x 19 of the 200 px card: under the first slot's centre
## Where the pointer's tip sits in the main: owners place the card so the slot's centre lands here when room allows.
const POINTER_TIP_X := _POINTER_X + UiTokens.SIZE_POINTER_W * 0.5
const _PAD := 10.0         # PinMenu auto-layout padding 10 on all sides, gap 6 (SPACE_WITHIN)
# "Pin badge (same as slot)" in Pinned=yes: 20 × 20, radius 7, glyph 14, at x 18 inside the button, centred.
const _BADGE := 20.0
const _BADGE_R := 7.0
const _BADGE_GLYPH := 14.0
const _BADGE_X := 18.0

var pinned := true: set = set_pinned
## Local x of the pointer's left edge; default as drawn in the main.
var pointer_x := _POINTER_X: set = set_pointer_x

var _card: PanelContainer
var _button: UiCommandButton
var _badge: Panel
var _verb: Label
var _note: Label
var _pointer: UiPointer
var _left := DISMISS_S
var _done := false

func _init(pinned_ := true) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_PIN_MENU, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_MENU
	box.shadow_size = UiTokens.SIZE_SHADOW_MENU_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_MENU_OFFSET_Y)
	box.with_margins(_PAD, _PAD, _PAD, _PAD)
	_card.add_theme_stylebox_override(&"panel", box)
	_card.custom_minimum_size.x = UiTokens.SIZE_PIN_MENU_W
	add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	_card.add_child(v)
	# The button's own text stays empty so UiCommandButton keeps its secondary look and 48 px height; the verb is
	# centred over the whole button and the badge sits at its left edge, as in the main.
	_button = UiCommandButton.new("", UiCommandButton.Kind.SECONDARY)
	_button.activated.connect(func(): toggled.emit())
	v.add_child(_button)
	_verb = UiKit.label("", UiTokens.STYLE_BUTTON_XB15, UiTokens.COLOR_PRIMARY)
	_verb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_verb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_verb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_verb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button.add_child(_verb)
	_badge = Panel.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PIN_AMBER, _BADGE_R,
		UiTokens.COLOR_SURFACE, UiTokens.STROKE_PIN_BADGE))
	_badge.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_badge.offset_left = _BADGE_X
	_badge.offset_right = _BADGE_X + _BADGE
	_badge.offset_top = -_BADGE * 0.5
	_badge.offset_bottom = _BADGE * 0.5
	var glyph := UiKit.icon(PIN_GLYPH, _BADGE_GLYPH)
	glyph.self_modulate = UiTokens.COLOR_SURFACE_RAISED
	glyph.position = Vector2((_BADGE - _BADGE_GLYPH) * 0.5, (_BADGE - _BADGE_GLYPH) * 0.5)
	glyph.size = Vector2(_BADGE_GLYPH, _BADGE_GLYPH)
	_badge.add_child(glyph)
	_button.add_child(_badge)
	_note = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = UiTokens.SIZE_PIN_MENU_W - _PAD * 2.0
	v.add_child(_note)
	_pointer = UiPointer.new()
	add_child(_pointer)
	_card.resized.connect(_layout)
	# Wrapped notes settle their height after layout; shrink the card (and this control) with them.
	_card.minimum_size_changed.connect(_layout)
	pinned = pinned_

func set_pinned(v: bool) -> void:
	pinned = v
	if _button == null: return
	_verb.text = "Unpin" if pinned else "Pin"
	_badge.visible = pinned   # only Pinned=yes carries the badge
	_note.text = NOTE_PINNED if pinned else NOTE_UNPINNED

func _process(dt: float) -> void:
	_left -= dt
	if _left <= 0.0: _dismiss()

func _input(e: InputEvent) -> void:
	var down: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed)
	if down and is_visible_in_tree() and not _card.get_global_rect().has_point(e.position): _dismiss()

func _dismiss() -> void:
	if _done: return
	_done = true
	set_process(false)
	dismissed.emit()

func set_pointer_x(v: float) -> void: pointer_x = v; _layout()

func button() -> UiCommandButton: return _button
func verb() -> String: return _verb.text

func _get_minimum_size() -> Vector2:
	if _card == null: return Vector2.ZERO
	var c := _card.get_combined_minimum_size()
	return Vector2(c.x, c.y + UiTokens.SIZE_POINTER_H)

func _layout() -> void:
	if _pointer == null: return
	_card.position = Vector2.ZERO
	_card.size = _card.get_combined_minimum_size()
	_pointer.position = Vector2(pointer_x, _card.size.y)
	update_minimum_size()
