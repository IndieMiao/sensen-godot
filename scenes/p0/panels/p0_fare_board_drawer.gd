extends UiDrawer
## q(165) Trip fares (FARE-BOARD 2631:134814, 安其拉 29778dba; 不知火舞's spec, accepted 9fb66366): the Travel Post's Fare
## Board, read only. A drawer 476 high (the sheet's top at y 324 of 800), the MAP-8 shell, 16 at the sides: `Trip fares`
## (TitleXB20, a 27 row) and straight under it the seven tiers (P0Travel.fares), 58 a row, not tappable and no ›: the
## tier `Trip 1 · Local` (RowTitleXB15, 20) over its bounds (CaptionB12, secondary, 16), 2 apart, the pair 10 from the
## row's top; `Free` (RowTitleB15, primary: all free reads as the good news it is, where grey would read "not
## available") right, centred on the whole row.

const HEIGHT := 476.0
const ROW_H := 58.0
const _TITLE_H := 27.0
const _LINE_GAP := 2

var rows: Array = []
var list: VBoxContainer

## rows_: P0Travel.fares().
func _init(rows_: Array = []) -> void:
	super(HEIGHT)
	pad = UiTokens.SPACE_PAGE   # the title's box starts at the pad, 16 under the sheet's top
	var head := Control.new()   # the frame's 27 row: TitleXB20's own line is 29, its ink inside the 27
	head.name = "Head"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.custom_minimum_size.y = _TITLE_H
	var title := UiKit.label("Trip fares", UiTokens.STYLE_TITLE_XB20)
	title.name = "Title"
	head.add_child(title)
	body.add_child(head)
	list = VBoxContainer.new()
	list.name = "Fares"
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override(&"separation", 0)
	body.add_child(list)
	rows = rows_
	for i in rows.size(): list.add_child(_row(rows[i], i + 1))

func _row(r: Dictionary, n: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "Trip%d" % n
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = ROW_H
	var text := VBoxContainer.new()
	text.name = "Text"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override(&"separation", _LINE_GAP)
	var tier := UiKit.label(str(r.get("title", "")), UiTokens.STYLE_ROW_TITLE_XB15)
	tier.name = "Tier"
	text.add_child(tier)
	var bounds := UiKit.label(str(r.get("line", "")), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	bounds.name = "Bounds"
	text.add_child(bounds)
	row.add_child(text)
	var fare := UiKit.label(str(r.get("fare", "")), UiTokens.STYLE_ROW_TITLE_B15, UiTokens.COLOR_PRIMARY)
	fare.name = "Fare"
	fare.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fare.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(fare)
	return row
