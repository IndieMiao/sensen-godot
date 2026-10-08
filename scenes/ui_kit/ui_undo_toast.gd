class_name UiUndoToast
extends PanelContainer
## Toast · Tone=Info with its Action row (1178:82247; LOCK-05 v1.10 BAR-DRAG-4): `<Item> off the bar` with `Undo`
## under it, 232 wide, surface card with a hairline edge and the soft shadow, the info glyph on the left. The owner
## places it (BAR-DRAG-4: left 16, 8 above the quick bar's top edge) and frees it; it hides itself after SECONDS.
## `undo_pressed` once, from the Undo action.

signal undo_pressed

const INFO_GLYPH := preload("res://assets/ui/kit_icons/info.svg")
const SECONDS := 5.0
const _PAD := Vector4(10, 9, 12, 9)   # left, top, right, bottom
const _GAP := 4.0
const _ICON_GAP := 8.0                # message at x 39 of the card, icon 20 at x 11

var text := "": set = set_text

var _message: Label
var _undo: Label
var _left := SECONDS

func _init(text_ := "") -> void:
	custom_minimum_size.x = UiTokens.SIZE_TOAST_W
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_LIFT_SHADOW
	box.shadow_size = 12
	box.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override(&"panel", box.with_margins(_PAD.x, _PAD.y, _PAD.z, _PAD.w))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", int(_GAP))
	add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(_ICON_GAP))
	col.add_child(row)
	var icon := UiKit.icon(INFO_GLYPH, UiTokens.SIZE_TOAST_ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	_message = UiKit.label("", UiTokens.STYLE_C14_XB)
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_message)
	var actions := MarginContainer.new()
	actions.add_theme_constant_override(&"margin_left", int(UiTokens.SIZE_TOAST_ICON + _ICON_GAP))
	col.add_child(actions)
	_undo = UiKit.label("Undo", UiTokens.STYLE_C12_XB, UiTokens.COLOR_INFO)
	_undo.mouse_filter = Control.MOUSE_FILTER_STOP
	_undo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_undo.gui_input.connect(func(e: InputEvent):
		var up: bool = (e is InputEventScreenTouch and not e.pressed) or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed)
		if up and visible:
			undo_pressed.emit()
			hide())
	actions.add_child(_undo)
	text = text_

func set_text(v: String) -> void:
	text = v
	_message.text = v

func undo_label() -> Label: return _undo

func _process(delta: float) -> void:
	if not visible: return
	_left -= delta
	if _left <= 0.0: hide()
