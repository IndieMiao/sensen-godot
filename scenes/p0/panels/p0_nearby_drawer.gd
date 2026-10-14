extends UiDrawer
## MAP-8 Nearby cities (q(159): the one page P1 makes of the destination lists; Figma row 85 MAP-8-LIST 2546:131161,
## 安其拉 279 a5a99803, 不知火舞's spec): a drawer 447 high (the sheet's top at y 353 of 800), 16 at the sides — the
## title's ink 20 from its top, `Nearby cities` (TitleXB20) over `From San Francisco · tap a city to see it on the map`
## (CaptionB12, secondary), then the ten cities nearest home (P0Travel.nearby), a CityRow each, straight under it,
## scrolling inside the drawer. A tap on a row asks for that city (city_pressed); the host closes the drawer and flies
## there.

signal city_pressed(cluster: String)

const CityRow := preload("res://scenes/p0/panels/p0_city_row.gd")
const HEIGHT := 447.0
const _HEAD_GAP := 4     # title to subtitle

var rows: Array = []
var list: VBoxContainer
var _scroll: TouchScrollContainer

## rows_: P0Travel.nearby(view); home: the home city's name.
func _init(rows_: Array = [], home := "") -> void:
	super(HEIGHT)
	pad = UiTokens.SPACE_PAGE   # the title's box starts at the pad, 16 under the sheet's top: its ink at about 20
	var head := VBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override(&"separation", _HEAD_GAP)
	var title := UiKit.label("Nearby cities", UiTokens.STYLE_TITLE_XB20)
	title.name = "Title"
	head.add_child(title)
	var sub := UiKit.label(subtitle(home), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	sub.name = "Subtitle"
	head.add_child(sub)
	body.add_child(head)
	_scroll = TouchScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	list = VBoxContainer.new()
	list.name = "Cities"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 0)
	_scroll.add_child(list)
	rows = rows_
	for r in rows:
		var row: Button = CityRow.new(r)
		var cluster := str(r.get("cluster", ""))
		row.pressed.connect(func(): city_pressed.emit(cluster))
		list.add_child(row)

## `From San Francisco · tap a city to see it on the map`.
static func subtitle(home: String) -> String:
	return "From %s · tap a city to see it on the map" % home
