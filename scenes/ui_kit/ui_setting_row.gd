class_name UiSettingRow
extends PanelContainer
## SettingRow (Figma 14 · Gensen Refactor/SettingRow 1236:107894, E-12): one row of a Settings sub-page, 52 minimum,
## 16 / 10 padding, the whole row the touch target (the content never takes a touch).
##   LINK   title (ExtraBold 15), an optional line under it (Bold 12 secondary, `MIT License`), › on the right; a data
##          credit (SET-LICENSES) has its attribution under the title, word for word and wrapping, and its licence 6
##          below it as its own line (q(129): so it never reads as the attribution's last line). A value given shows
##          before the › as VALUE's does (`Notifications` · `On ›`, SGODOT-350).
##          `chevron` false (q(281) `Support code`): a LINK without its ›, the value alone on the right — the row still
##          takes the tap (it copies, it does not go anywhere).
##   VALUE  title and its value on the right (Bold 14 secondary), read-only without › (`Version` · `0.2.1 (…)`).
##   TOGGLE title, an optional line, the 48 × 28 Toggle on the right (Gensen Refactor/Toggle 1236:107861: green track
##          on, neutral off); the whole row switches it (q(133) v3 `Share anonymous map usage`).
## group(rows) puts rows in a 16-radius card, 1 apart on the border colour (SettingRow's Group).
## Emits pressed (LINK), toggled(on) (TOGGLE).

signal pressed
signal toggled(on: bool)

enum Kind { LINK, VALUE, TOGGLE }

const _TOGGLE_SIZE := Vector2(48, 28)
const _TOGGLE_ON := "res://assets/ui/kit_icons/toggle_on.svg"
const _TOGGLE_OFF := "res://assets/ui/kit_icons/toggle_off.svg"

## TOGGLE: whether it is on. Setting it redraws the switch; a tap on the row flips it and emits toggled.
var on := false: set = set_on
var _switch: TextureRect

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

func _init(kind_ := Kind.LINK, title := "", line := "", value := "", credit := "", chevron_ := true) -> void:
	kind = kind_
	custom_minimum_size.y = _MIN_H
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The padding is on a margin box inside, not on the panel's style: the panel would take it off Hit too (刘邦 on #292).
	add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, 0))
	var pad := MarginContainer.new()
	pad.name = "Pad"
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [&"margin_left", &"margin_right"]: pad.add_theme_constant_override(side, _PAD_X)
	for side in [&"margin_top", &"margin_bottom"]: pad.add_theme_constant_override(side, _PAD_Y)
	add_child(pad)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", _GAP)
	pad.add_child(row)
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
		row.add_child(_value(value))
		return
	if kind == Kind.TOGGLE:
		_switch = TextureRect.new()
		_switch.name = "Toggle"
		_switch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_switch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_switch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_switch.custom_minimum_size = _TOGGLE_SIZE
		_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_switch)
		set_on(on)
	else:
		if value != "": row.add_child(_value(value))
		if chevron_:
			var chevron := UiKit.label("›", UiTokens.STYLE_ROW_TITLE_XB15, UiTokens.COLOR_SECONDARY)
			chevron.name = "Chevron"
			chevron.add_theme_font_size_override(&"font_size", _CHEVRON_SIZE)
			chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(chevron)
	# The whole row is the target, edge to edge: a flat button over the content (a drag in a TouchScrollContainer cancels it).
	var hit := Button.new()
	hit.name = "Hit"
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]: hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.pressed.connect(func():
		if kind == Kind.TOGGLE:
			on = not on
			toggled.emit(on)
		else: pressed.emit())
	add_child(hit)

func set_on(v: bool) -> void:
	on = v
	if _switch != null: _switch.texture = load(_TOGGLE_ON if v else _TOGGLE_OFF)

static func _value(text: String) -> Label:
	var v := UiKit.label(text, UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY)
	v.name = "Value"
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return v

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
