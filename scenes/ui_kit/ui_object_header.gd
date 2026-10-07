class_name UiObjectHeader
extends VBoxContainer
## ObjectHeader 483:196 (SGODOT-212): the top of a detail card or sheet. Title and quantity on one row, then
## an optional state line and an optional effect sentence; each field stays separate (no merged sentences).
## Display only. An empty field hides its part.

var title := "": set = set_title
## Quantity value and unit, e.g. "7" / "fish"; "" hides the quantity column.
var quantity := "": set = set_quantity
var quantity_label := "": set = set_quantity_label
## Short state word, e.g. "Ready".
var state := "": set = set_state
## One functional sentence, e.g. "Restores 40 Energy."
var effect := "": set = set_effect

var _title: Label
var _qty_box: VBoxContainer
var _qty: Label
var _unit: Label
var _state: Label
var _effect: Label

func _init(fields: Dictionary = {}) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_OVERLAY_BODY))
	add_child(row)
	_title = UiKit.label("", UiTokens.STYLE_TITLE_XB20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_title)
	_qty_box = VBoxContainer.new()
	_qty_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty_box.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	_qty_box.custom_minimum_size.x = UiTokens.SIZE_OBJECT_HEADER_QTY_W
	_qty = UiKit.label("", UiTokens.STYLE_QUANTITY_XB24)
	_unit = UiKit.label("", UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_SECONDARY)
	_qty_box.add_child(_qty)
	_qty_box.add_child(_unit)
	row.add_child(_qty_box)
	_state = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	add_child(_state)
	_effect = UiKit.label("", UiTokens.STYLE_EFFECT_B15)
	_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_effect)
	for k in fields: set(k, fields[k])
	_refresh()

func set_title(v: String) -> void: title = v; _refresh()
func set_quantity(v: String) -> void: quantity = v; _refresh()
func set_quantity_label(v: String) -> void: quantity_label = v; _refresh()
func set_state(v: String) -> void: state = v; _refresh()
func set_effect(v: String) -> void: effect = v; _refresh()

func _refresh() -> void:
	if _effect == null: return
	_title.text = title
	_qty.text = quantity
	_unit.text = quantity_label
	_unit.visible = quantity_label != ""
	_qty_box.visible = quantity != ""
	_state.text = state
	_state.visible = state != ""
	_effect.text = effect
	_effect.visible = effect != ""
