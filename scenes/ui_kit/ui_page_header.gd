class_name UiPageHeader
extends HBoxContainer
## PageHeader (Figma 14 · Gensen Refactor/PageHeader 1236:107871, E-12): the header of a full-screen Settings sub-page —
## the 44 round back of ProfileTopBar (LOCK-22: the same geometry) and the title, ExtraBold 18, 12 apart, 48 high.
## Emits back_pressed.

signal back_pressed

const _GAP := 12
const _H := 48.0
const _TITLE_SIZE := 18   # ExtraBold 18: Row Title XB15 three steps up (no 18 style exported yet)

var title := "": set = set_title

var _title: Label

func _init(title_ := "") -> void:
	add_theme_constant_override(&"separation", _GAP)
	custom_minimum_size.y = _H
	var back := UiProfileTopBar._Round.new(UiProfileTopBar._Round.Glyph.BACK)
	back.name = "Back"
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)
	_title = UiKit.label("", UiTokens.STYLE_ROW_TITLE_XB15)
	_title.add_theme_font_size_override(&"font_size", _TITLE_SIZE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_title)
	title = title_

func set_title(v: String) -> void:
	title = v
	if _title != null: _title.text = v
