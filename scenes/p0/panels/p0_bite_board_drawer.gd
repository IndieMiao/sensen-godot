extends UiDrawer
## The Tackle Shop's Bite Board (SGODOT-283; plan §6.9.3; 不知火舞 e61cda10 ③, 1e21c014, f74fafae; Figma BITE-BOARD-V2
## 2255:32861, BITE-BOARD-LV2-V2 2255:33188, BITE-BOARD-SCROLL-V2 2255:33436): a drawer as tall as its content, at most
## 560 (70 % of 800), scrolling past that; content 20 from the top, 16 at the sides and the bottom, 12 between parts:
##   `Bite Board · Mission Tackle Shop` (14 XB) over today's condition line,
##   the keeper's line in curly quotes (12 Bold Italic, secondary, two lines at most; q(119)),
##   `Ponds`: a row per pond of the city, nearest first — PondThumb 72 × 56 with today's fish on its badge, the name
##     (14 XB), `River · 1.6 km` (12 Bold secondary), the fish line (16 px icon, the fish's name in ink and its tags in
##     secondary), a `›`; 12 above and below, a 1 px border line under each. A pond with nothing over ×1 today has two
##     lines and no badge. A tap opens that pond's card (pond_pressed); nothing moves by itself.
##   `Regional fish`: the city's two, icon 32 and the name, an uncaught one a silhouette, `?` over `Fishing Lv8`.
##   `Forecast` (Fishing Lv3+): three equal cards — day, a 24 px weather icon, the word, one or two fish.
## Everything comes from P0BiteBoard.model(view, outpost); the drawer refreshes when it changes.

signal pond_pressed(id: String)

const Board := preload("res://modules/p0/p0_bite_board.gd")
const MAX_HEIGHT := 560.0
const _TOP := 20.0          # content top (2255:33437 at y 20 of the sheet)
const _GAP := 12
const _ROW_H := 81.0        # 12 + the 56 thumbnail + 12, and the 1 px line
const _REGIONAL_GAP := 24
const _ICON_TEXT_GAP := 10  # a regional fish's icon to its name
const _FORECAST_GAP := 8
const _ITALIC_SKEW := 0.2   # Nunito has no italic face: the bold one slanted for the keeper's line

var view := {}
var outpost := {}
var model := {}
var page: VBoxContainer
var pond_rows: Array[Button] = []

var _scroll: TouchScrollContainer
var _key := 0
var _fit_frames := 0

func _init(view_: Dictionary = {}, outpost_: Dictionary = {}) -> void:
	super(MAX_HEIGHT)
	pad = UiTokens.SPACE_PAGE
	var top := Control.new()
	top.custom_minimum_size.y = _TOP - UiTokens.SPACE_PAGE
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(top)
	_scroll = TouchScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	page = VBoxContainer.new()
	page.name = "Page"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override(&"separation", _GAP)
	_scroll.add_child(page)
	outpost = outpost_
	refresh(view_)

## Follows the view while open (P0Ui calls it with each new view); rebuilds only when what it shows changed.
func refresh(v: Dictionary) -> void:
	view = v
	model = Board.model(view, outpost)
	var key := hash(model)
	if key == _key: return
	_key = key
	_build()

func _build() -> void:
	for c in page.get_children():
		page.remove_child(c)
		c.queue_free()
	pond_rows.clear()
	var head := VBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override(&"separation", 4)
	var title := UiKit.label(str(model.title), UiTokens.STYLE_C14_XB)
	title.name = "Title"
	head.add_child(title)
	if not (model.conditions as Array).is_empty(): head.add_child(P0PlaceSheet.conditions_row(model.conditions))
	page.add_child(head)
	var line := UiKit.label(str(model.line), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	line.name = "KeeperLine"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.max_lines_visible = 2
	line.add_theme_font_override(&"font", _italic())
	page.add_child(line)
	var titles: Array = model.titles
	page.add_child(_section(str(titles[0])))
	var list := VBoxContainer.new()
	list.name = "Ponds"
	list.add_theme_constant_override(&"separation", 0)
	for r in model.ponds: list.add_child(_pond_row(r))
	page.add_child(list)
	if not (model.regional as Array).is_empty():
		page.add_child(_section(str(titles[1])))
		var reg := HBoxContainer.new()
		reg.name = "Regional"
		reg.add_theme_constant_override(&"separation", _REGIONAL_GAP)
		for r in model.regional: reg.add_child(_regional(r))
		page.add_child(reg)
	if titles.size() > 2 and not (model.forecast as Array).is_empty():
		page.add_child(_section(str(titles[2])))
		var days := HBoxContainer.new()
		days.name = "Forecast"
		days.add_theme_constant_override(&"separation", _FORECAST_GAP)
		for d in model.forecast: days.add_child(_day(d))
		page.add_child(days)
	_fit_frames = 2   # labels wrap once laid out: measure after that

func _process(_dt: float) -> void:
	if _fit_frames <= 0: return
	_fit_frames -= 1
	if _fit_frames == 0: _fit()

## As tall as the content, at most MAX_HEIGHT (the rest scrolls).
func _fit() -> void:
	var want := _TOP + page.get_combined_minimum_size().y + UiTokens.SPACE_PAGE + safe_bottom
	height = minf(MAX_HEIGHT, ceilf(want))

## The content's height (tests and the screenshot check it against MAX_HEIGHT).
func content_height() -> float: return page.get_combined_minimum_size().y

func _section(text: String) -> Label:
	var l := UiKit.label(text, UiTokens.STYLE_C12_XB)
	l.name = "Section_" + text.replace(" ", "_")
	return l

func _pond_row(r: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Pond_" + str(r.id)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = _ROW_H
	var line := StyleBoxFlat.new()   # the row's 1 px border line under it, nothing else drawn
	line.bg_color = Color.TRANSPARENT
	line.border_color = UiTokens.COLOR_BORDER
	line.border_width_bottom = UiTokens.STROKE_DEFAULT
	for s in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]: b.add_theme_stylebox_override(s, line)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 12)
	var thumb := UiPondThumb.new(str(r.template), UiPondThumb.ROW, str(r.fish))
	thumb.name = "Thumb"
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(thumb)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override(&"separation", 2)
	var name_ := UiKit.label(str(r.name), UiTokens.STYLE_C14_XB)
	name_.name = "Name"
	text.add_child(name_)
	var sub := UiKit.label(str(r.sub), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	sub.name = "Sub"
	text.add_child(sub)
	if str(r.fish) != "":
		var fish := HBoxContainer.new()
		fish.name = "Fish"
		fish.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fish.add_theme_constant_override(&"separation", 4)
		var icon := UiKit.icon(P0Logic.icon(str(r.fish)), 16)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if str(r.fish_name) == "?": icon.modulate = Color(0.13, 0.15, 0.14)   # an uncaught regional fish: its silhouette
		fish.add_child(icon)
		var words := HBoxContainer.new()
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_theme_constant_override(&"separation", 0)
		var fname := UiKit.label(str(r.fish_name), UiTokens.STYLE_CAPTION_B12)
		fname.name = "FishName"
		words.add_child(fname)
		if str(r.tags) != "":
			var tags := UiKit.label(str(r.tags), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
			tags.name = "Tags"
			words.add_child(tags)
		fish.add_child(words)
		text.add_child(fish)
	row.add_child(text)
	var chevron := UiKit.label("›", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_INFO)
	chevron.add_theme_font_size_override(&"font_size", 16)
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chevron)
	b.add_child(row)
	var id := str(r.id)
	b.pressed.connect(func(): pond_pressed.emit(id))
	pond_rows.append(b)
	return b

func _regional(r: Dictionary) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "Regional_" + str(r.id)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", _ICON_TEXT_GAP)
	var icon := UiKit.icon(P0Logic.icon(str(r.id)), 32)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not bool(r.caught): icon.modulate = Color(0.13, 0.15, 0.14)   # silhouette until caught (q(48))
	box.add_child(icon)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override(&"separation", 0)
	text.add_child(UiKit.label(str(r.name), UiTokens.STYLE_C14_XB))
	if str(r.sub) != "": text.add_child(UiKit.label(str(r.sub), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY))
	box.add_child(text)
	return box

func _day(d: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Day_" + str(d.day)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	card.custom_minimum_size.x = 1   # three equal widths, whatever their words
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, 12, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	card.add_theme_stylebox_override(&"panel", box.with_margins(8, 10, 8, 10))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override(&"separation", 4)
	var day := UiKit.label(str(d.day), UiTokens.STYLE_C12_XB)
	day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(day)
	var icon := UiKit.icon(P0Logic.icon(str(d.icon)), 24)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon)
	var word := UiKit.label(str(d.word), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(word)
	for f in d.fish:
		var l := UiKit.label(str(f), UiTokens.STYLE_CAPTION_B12)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		col.add_child(l)
	card.add_child(col)
	return card

static var _slant: FontVariation
static func _italic() -> FontVariation:
	if _slant == null:
		_slant = FontVariation.new()
		_slant.base_font = load(UiTokens.FONT_BOLD_PATH)
		_slant.variation_transform = Transform2D(Vector2(1, 0), Vector2(-_ITALIC_SKEW, 1), Vector2.ZERO)
	return _slant
