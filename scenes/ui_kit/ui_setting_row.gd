class_name UiSettingRow
extends PanelContainer
## SettingRow (Figma 14 · Gensen Refactor/SettingRow 1236:107894, E-12): one row of a Settings sub-page, 52 minimum,
## 16 / 10 padding, the whole row the touch target (the content never takes a touch).
##   LINK   title (ExtraBold 15), an optional line under it (Bold 12 secondary, `MIT License`), › on the right; a data
##          credit (SET-LICENSES) has its attribution under the title, word for word and wrapping, and its licence 6
##          below it as its own line (q(129): so it never reads as the attribution's last line).
##   VALUE  title and its value on the right (Bold 14 secondary), read-only without › (`Version` · `0.2.1 (…)`).
## group(rows) puts rows in a 16-radius card, 1 apart on the border colour (SettingRow's Group).
## Emits pressed (LINK only).

signal pressed

enum Kind { LINK, VALUE }

const _MIN_H := 52.0
const _PAD_X := 16
const _PAD_Y := 10
const _GAP := 12
const _TEXT_GAP := 2
const _CREDIT_GAP := 6        # the attribution → its licence line (q(129))
const _CHEVRON_SIZE := 18     # › ExtraBold 18: Row Title XB15 three steps up (no 18 style exported yet)
const _GROUP_RADIUS := 16
const _GROUP_GAP := 1

var kind: Kind

func _init(kind_ := Kind.LINK, title := "", line := "", value := "", credit := "") -> void:
	kind = kind_
	custom_minimum_size.y = _MIN_H
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, 0).with_margins(_PAD_X, _PAD_Y, _PAD_X, _PAD_Y))
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", _GAP)
	add_child(row)
	var texts := VBoxContainer.new()
	texts.name = "Texts"
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override(&"separation", _TEXT_GAP)
	row.add_child(texts)
	texts.add_child(_text("Title", title, UiTokens.STYLE_ROW_TITLE_XB15, UiTokens.COLOR_TEXT))
	if credit != "":
		var lines := VBoxContainer.new()
		lines.name = "Credit"
		lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_theme_constant_override(&"separation", _CREDIT_GAP)
		lines.add_child(_text("Attribution", credit, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY))
		if line != "": lines.add_child(_text("Line", line, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY))
		texts.add_child(lines)
	elif line != "":
		texts.add_child(_text("Line", line, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY))
	if kind == Kind.VALUE:
		var v := UiKit.label(value, UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY)
		v.name = "Value"
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(v)
		return
	var chevron := UiKit.label("›", UiTokens.STYLE_ROW_TITLE_XB15, UiTokens.COLOR_SECONDARY)
	chevron.name = "Chevron"
	chevron.add_theme_font_size_override(&"font_size", _CHEVRON_SIZE)
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chevron)
	# The whole row is the target: a flat button over the content (a drag in a TouchScrollContainer cancels it).
	var hit := Button.new()
	hit.name = "Hit"
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]: hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.pressed.connect(func(): pressed.emit())
	add_child(hit)

static func _text(name_: String, text: String, style: StringName, color: Color) -> Label:
	var l := UiKit.label(text, style, color)
	l.name = name_
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

## SettingRow's Group: the rows in one card, radius 16, 1 apart on the border colour, the rows' corners clipped to it.
static func group(rows: Array) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Group"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	card.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_BORDER, _GROUP_RADIUS).with_margins(
		UiTokens.STROKE_DEFAULT, UiTokens.STROKE_DEFAULT, UiTokens.STROKE_DEFAULT, UiTokens.STROKE_DEFAULT))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", _GROUP_GAP)
	card.add_child(col)
	for r in rows: col.add_child(r)
	return card
