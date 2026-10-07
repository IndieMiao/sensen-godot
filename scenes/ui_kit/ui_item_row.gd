class_name UiItemRow
extends MarginContainer
## ItemRow 483:228 (SGODOT-212): 32 px icon, then title / state / effect, then the quantity column.
## Display only; a list that reacts to taps wraps rows in its own button. An empty field hides its part.

var icon: Texture2D: set = set_icon
var title := "": set = set_title
## Short state in primary, e.g. the rarity word "Common".
var state := "": set = set_state
## One sentence in secondary, e.g. "A simple pond fish".
var effect := "": set = set_effect
var quantity := "": set = set_quantity
var quantity_label := "": set = set_quantity_label

var _icon: TextureRect
var _title: Label
var _state: Label
var _effect: Label
var _qty_box: VBoxContainer
var _qty: Label
var _unit: Label

func _init(fields: Dictionary = {}) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"margin_top", int(UiTokens.SPACE_OVERLAY_BODY))
	add_theme_constant_override(&"margin_bottom", int(UiTokens.SPACE_OVERLAY_BODY))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_ITEM_ROW_GAP))
	add_child(row)
	_icon = UiKit.icon(null, UiTokens.SIZE_ITEM_ROW_ICON)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	row.add_child(text)
	_title = UiKit.label("", UiTokens.STYLE_ROW_TITLE_XB15)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_state = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_PRIMARY)
	_effect = UiKit.label("", UiTokens.STYLE_BODY_R14, UiTokens.COLOR_SECONDARY)
	_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for l in [_title, _state, _effect]: text.add_child(l)
	_qty_box = VBoxContainer.new()
	_qty_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_qty_box.custom_minimum_size.x = UiTokens.SIZE_ITEM_ROW_QTY_W
	_qty_box.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	_qty = UiKit.label("", UiTokens.STYLE_QUANTITY_XB24)
	_unit = UiKit.label("", UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_SECONDARY)
	_qty_box.add_child(_qty)
	_qty_box.add_child(_unit)
	row.add_child(_qty_box)
	for k in fields: set(k, fields[k])
	_refresh()

func set_icon(v: Texture2D) -> void: icon = v; _refresh()
func set_title(v: String) -> void: title = v; _refresh()
func set_state(v: String) -> void: state = v; _refresh()
func set_effect(v: String) -> void: effect = v; _refresh()
func set_quantity(v: String) -> void: quantity = v; _refresh()
func set_quantity_label(v: String) -> void: quantity_label = v; _refresh()

func _refresh() -> void:
	if _unit == null: return
	_icon.texture = icon
	_icon.visible = icon != null
	_title.text = title
	_state.text = state
	_state.visible = state != ""
	_effect.text = effect
	_effect.visible = effect != ""
	_qty.text = quantity
	_unit.text = quantity_label
	_unit.visible = quantity_label != ""
	_qty_box.visible = quantity != ""
