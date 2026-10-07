class_name UiPinMenu
extends Control
## PinMenu 1141:80291 (SGODOT-221, LOCK-05; plan §10.3.3): the small card a long press leaves above a quick
## slot. The pin state has already toggled when it appears (WP7-B F-04 §3, confirmed by WP1a); the card says
## which state the slot is now in and offers the reverse in one tap: `Unpin` with the amber pin badge before
## it, then "Pinned slots stay when the bar refills." (or `Pin` / "Pin to keep it when the bar refills.").
## The pointer sits under the slot it belongs to: set `pointer_x` to that slot's centre in local x.
## Emits `toggled` when the button is tapped; the owner flips the pin and closes the card.

signal toggled

const PIN_GLYPH := preload("res://assets/ui/kit_icons/pin.svg")
const NOTE_PINNED := "Pinned slots stay when the bar refills."
const NOTE_UNPINNED := "Pin to keep it when the bar refills."
const _POINTER_X := 19.0   # PinMenu pointer at x 19 of the 200 px card: under the first slot's centre
const _PAD := 10.0         # PinMenu auto-layout padding 10 on all sides, gap 6 (SPACE_WITHIN)

var pinned := true: set = set_pinned
## Local x of the pointer's left edge; default as drawn in the main.
var pointer_x := _POINTER_X: set = set_pointer_x

var _card: PanelContainer
var _button: UiCommandButton
var _badge: Panel
var _verb: Label
var _note: Label
var _pointer: UiPointer

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
	# The verb is drawn by a centred badge + label pair inside the button (badge before `Unpin`, as in the main);
	# the button's own text stays empty so UiCommandButton keeps its secondary look and 48 px height.
	_button = UiCommandButton.new("", UiCommandButton.Kind.SECONDARY)
	_button.activated.connect(func(): toggled.emit())
	v.add_child(_button)
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	_button.add_child(content)
	_badge = Panel.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := UiTokens.SIZE_PIN_BADGE
	_badge.custom_minimum_size = Vector2(b, b)
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PIN_AMBER, b * 0.5,
		UiTokens.COLOR_SURFACE, UiTokens.STROKE_PIN_BADGE))
	var glyph := UiKit.icon(PIN_GLYPH, UiTokens.SIZE_PIN_ICON)
	glyph.self_modulate = UiTokens.COLOR_SURFACE_RAISED
	glyph.position = Vector2((b - UiTokens.SIZE_PIN_ICON) * 0.5, (b - UiTokens.SIZE_PIN_ICON) * 0.5)
	glyph.size = Vector2(UiTokens.SIZE_PIN_ICON, UiTokens.SIZE_PIN_ICON)
	_badge.add_child(glyph)
	content.add_child(_badge)
	_verb = UiKit.label("", UiTokens.STYLE_BUTTON_B15, UiTokens.COLOR_PRIMARY)
	_verb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(_verb)
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
	_note.text = NOTE_PINNED if pinned else NOTE_UNPINNED

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
