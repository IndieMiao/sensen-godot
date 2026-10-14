extends UiDrawer
## Titles (q(180) ⑤; TITLES 2595:153099, 安其拉 769e4881, 不知火舞 accepted e9024731): opened from the title beside the
## name on the profile. A half-screen drawer in MAP-8's shell, 16 at the sides: `Titles` (TitleXB20) over `Tap a title
## to wear it` (CaptionB12, secondary), then a row per title in the server's fixed order (the worn one is not moved
## up), 58 high and tappable as a whole: the title's full name (RowTitleXB15) over where it came from (CaptionB12,
## secondary), and on the worn row the 22 primary disc with its white check, right. As tall as its rows (five: 388, the
## frame's), at most MAP-8's 447, scrolling past that. No button at the bottom; the host puts Close 44 above the sheet.
## A tap on another row asks to wear it (title_picked); a tap on the worn row only closes (close_requested).

signal title_picked(id: String)

const HEIGHT := 447.0         # MAP-8's: the most it grows to
const ROW_H := 58.0
const _CHROME := 98.0         # the frame's 388 less its five rows: the handle band, the head and the bottom
const _HEAD_GAP := 4          # title to subtitle
const _LINE_GAP := 2          # a row's name to its source
const SUBTITLE := "Tap a title to wear it"

var rows: Array = []
var list: VBoxContainer
var _scroll: TouchScrollContainer

## rows_: P0Titles.rows(view, pending).
func _init(rows_: Array = []) -> void:
	super(height_for(rows_.size()))
	pad = UiTokens.SPACE_PAGE   # the title's box starts at the pad, 16 under the sheet's top, as MAP-8
	var head := VBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override(&"separation", _HEAD_GAP)
	var title := UiKit.label("Titles", UiTokens.STYLE_TITLE_XB20)
	title.name = "Title"
	head.add_child(title)
	var sub := UiKit.label(SUBTITLE, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	sub.name = "Subtitle"
	head.add_child(sub)
	body.add_child(head)
	_scroll = TouchScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	list = VBoxContainer.new()
	list.name = "Titles"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 0)
	_scroll.add_child(list)
	rows = rows_
	for r in rows: list.add_child(_row(r))

## The drawer's height for n rows: the frame's 388 at five, at most 447.
static func height_for(n: int) -> float:
	return minf(HEIGHT, _CHROME + maxi(1, n) * ROW_H)

func _row(r: Dictionary) -> Button:
	var row := Button.new()
	row.name = ("Title_" + str(r.get("id", "")).replace(":", "_")).validate_node_name()
	row.flat = true
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = ROW_H
	for s in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		row.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(line)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override(&"separation", _LINE_GAP)
	var title := UiKit.label(str(r.get("name", "")), UiTokens.STYLE_ROW_TITLE_XB15)
	title.name = "Name"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(title)
	var source := UiKit.label(str(r.get("source", "")), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	source.name = "Source"
	source.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(source)
	line.add_child(text)
	if bool(r.get("worn", false)):
		var mark := _Worn.new()
		mark.name = "Worn"
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.custom_minimum_size = Vector2(UiLookOption.CHECK, UiLookOption.CHECK)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(mark)
	var id := str(r.get("id", ""))
	var worn := bool(r.get("worn", false))
	row.pressed.connect(func():
		if worn: close_requested.emit()
		else: title_picked.emit(id))
	return row

## The worn row's mark: the 22 primary disc with the white check, as a picked look (UiLookOption's Selected check).
class _Worn extends Control:
	const _GLYPH := preload("res://assets/ui/kit_icons/check.svg")
	func _draw() -> void:
		draw_circle(size * 0.5, UiLookOption.CHECK * 0.5, UiTokens.COLOR_PRIMARY)
		var g := UiLookOption.CHECK_GLYPH
		draw_texture_rect(_GLYPH, Rect2((size - Vector2(g, g)) * 0.5, Vector2(g, g)), false, Color.WHITE)
