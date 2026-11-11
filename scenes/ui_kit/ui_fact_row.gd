class_name UiFactRow
extends MarginContainer
## Fact 483:222 and Cost 483:225 (SGODOT-212): one label / value line of a detail card, e.g. "Progress 2/8",
## "Cost 120 coins". Cost sets the value one step larger (RowTitle 15 vs Body 14). Display only. Have / need
## counts are NEED-TILEs (LOCK-10), not fact rows. `icon` (none unless set): a 16 glyph ahead of the label, 4 off it and
## centred on it — the travel cards' Energy and Coins rows (q(318) v3, the user's bot 746); a row without one is as before.

enum Kind { FACT, COST }

var kind: Kind = Kind.FACT: set = set_kind
var label := "": set = set_label
var value := "": set = set_value
var icon: Texture2D: set = set_icon

var _icon: TextureRect
var _label: Label
var _value: Label

func _init(label_: String = "", value_: String = "", kind_: Kind = Kind.FACT) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"margin_top", int(UiTokens.SPACE_WITHIN))
	add_theme_constant_override(&"margin_bottom", int(UiTokens.SPACE_WITHIN))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_OVERLAY_BODY))
	add_child(row)
	var lead := HBoxContainer.new()   # the glyph (hidden without one) and the label, taking the row's free width
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lead.add_theme_constant_override(&"separation", 4)
	row.add_child(lead)
	_icon = UiKit.icon(null, 16)
	_icon.name = "Icon"
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.visible = false
	lead.add_child(_icon)
	_label = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lead.add_child(_label)
	_value = UiKit.label("", UiTokens.STYLE_BODY_XB14)
	_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_value)
	label = label_
	value = value_
	kind = kind_

func set_kind(v: Kind) -> void:
	kind = v
	if _value != null: _value.theme_type_variation = UiTokens.STYLE_ROW_TITLE_XB15 if kind == Kind.COST else UiTokens.STYLE_BODY_XB14

func set_label(v: String) -> void:
	label = v
	if _label != null: _label.text = v

func set_value(v: String) -> void:
	value = v
	if _value != null: _value.text = v

func set_icon(v: Texture2D) -> void:
	icon = v
	if _icon != null:
		_icon.texture = v
		_icon.visible = v != null
