extends UiDrawer
## The Homestead Stall's Notice Board (q(164); 不知火舞's spec on SGODOT-284; NOTICE-BOARD 2608:133862, NOTICE-BOARD-LIST
## 2609:134212, 安其拉's frames): a half-screen drawer as MAP-8's Nearby cities, as tall as its content, at most 560,
## scrolling past that:
##   `Notice Board` (TitleXB20) over `San Francisco · Today · tap a place to see it on the map` (CaptionB12, secondary),
##   `Ponds` and `Outposts` (C12 XB section heads, as the Bite Board's),
##   a 64 row per place, no line between them, the whole row a tap with a `›` (XB15, secondary) on its right: the map
##     pin's own 40 disc (surface, a primary ring, the 24 glyph: pond, or the outpost's role), the short name
##     (RowTitleXB15) over its line (C13 B, secondary) — a pond's best bite today, an outpost's kind, or, while its pin
##     wears a mark, the reason with that mark (P0PlaceSheet.reason_row, q(103)) — and before the `›` the player's trap
##     in a pond (trap icon + `2/3`) or who is in an outpost (the pin's green count, person + `3`, none at 0, q(72)).
## A tap emits place_pressed(go) — `pond:<id>` / `outpost:<id>`: the P0 UI closes the drawer and the map flies there,
## moving nobody (q(31), k(1)). Everything comes from P0NoticeBoard.model(view, online).

signal place_pressed(go: String)

const Board := preload("res://modules/p0/p0_notice_board.gd")
const MAX_HEIGHT := 560.0
const ROW_H := 64.0
const _ICON := 40.0
const _ICON_GLYPH := 24.0
const _TOP := 12.0       # the title's ink 20 under the sheet's top, as MAP-8
const _GAP := 12
const _PERSON := "res://assets/ui/kit_icons/count_person.svg"
const _PERSON_SIDE := 9.0   # the map pin's count (UiMapDestination)
const _TRAP_SIDE := 18.0

var view := {}
var online := {}
var model := {}
var page: VBoxContainer
var rows: Array[Button] = []

var _scroll: TouchScrollContainer
var _key := 0
var _fit_frames := 0

func _init(view_: Dictionary = {}, online_: Dictionary = {}) -> void:
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
	online = online_
	refresh(view_)

## Follows the view while open (P0Ui calls it with each new view); rebuilds only when what it shows changed.
func refresh(v: Dictionary) -> void:
	view = v
	model = Board.model(view, online)
	var key := hash(model)
	if key == _key: return
	_key = key
	_build()

## The outposts' online counts came (GET /p0/presence): their person badges follow.
func set_online(o: Dictionary) -> void:
	online = o
	refresh(view)

func _build() -> void:
	for c in page.get_children():
		page.remove_child(c)
		c.queue_free()
	rows.clear()
	var head := VBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override(&"separation", 4)
	var title := UiKit.label(str(model.title), UiTokens.STYLE_TITLE_XB20)
	title.name = "Title"
	head.add_child(title)
	var sub := UiKit.label(str(model.subtitle), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	sub.name = "Subtitle"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(sub)
	page.add_child(head)
	for part in [["Ponds", model.ponds], ["Outposts", model.outposts]]:
		if (part[1] as Array).is_empty(): continue
		var l := UiKit.label(str(part[0]), UiTokens.STYLE_C12_XB)
		l.name = "Section_" + str(part[0])
		page.add_child(l)
		var list := VBoxContainer.new()
		list.name = str(part[0])
		list.add_theme_constant_override(&"separation", 0)
		for r in part[1]: list.add_child(_row(r))
		page.add_child(list)
	_fit_frames = 2   # the subtitle wraps once laid out: measure after that

func _process(_dt: float) -> void:
	if _fit_frames <= 0: return
	_fit_frames -= 1
	if _fit_frames == 0: _fit()

## As tall as the content, at most MAX_HEIGHT (the rest scrolls).
func _fit() -> void:
	var want := _TOP + page.get_combined_minimum_size().y + UiTokens.SPACE_PAGE + safe_bottom
	height = minf(MAX_HEIGHT, ceilf(want))

func _row(r: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Row_" + str(r.id)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = ROW_H
	var clear := StyleBoxEmpty.new()   # nothing drawn: rows sit straight under each other, as MAP-8's
	for s in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]: b.add_theme_stylebox_override(s, clear)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 12)
	var disc := Panel.new()   # the pin's own icon on a 40 round disc
	disc.name = "Icon"
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.custom_minimum_size = Vector2(_ICON, _ICON)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, _ICON * 0.5, UiTokens.COLOR_PRIMARY, UiTokens.STROKE_DEFAULT))
	var glyph := UiKit.icon(P0Logic.icon(str(r.icon)), _ICON_GLYPH)
	glyph.position = Vector2.ONE * (_ICON - _ICON_GLYPH) * 0.5
	disc.add_child(glyph)
	row.add_child(disc)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override(&"separation", 2)
	var name_ := UiKit.label(str(r.name), UiTokens.STYLE_ROW_TITLE_XB15)
	name_.name = "Name"
	text.add_child(name_)
	var why: Dictionary = r.get("reason", {})
	if not why.is_empty(): text.add_child(P0PlaceSheet.reason_row(why))   # the pin's mark and why (q(103))
	else:
		var said := UiKit.label(str(r.line), UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY)
		said.name = "Line"
		said.clip_text = true
		said.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(said)
	row.add_child(text)
	if str(r.get("trap", "")) != "": row.add_child(_trap(str(r.trap)))
	if int(r.get("online", 0)) > 0: row.add_child(_online(int(r.online)))
	var chevron := UiKit.label("›", UiTokens.STYLE_ROW_TITLE_XB15, UiTokens.COLOR_SECONDARY)
	chevron.name = "Chevron"
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chevron)
	b.add_child(row)
	var go := str(r.go)
	b.pressed.connect(func(): place_pressed.emit(go))
	rows.append(b)
	return b

## The player's trap in this pond: the trap's icon and `2/3` (fish in it / it keeps).
func _trap(count: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "Trap"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override(&"separation", 4)
	var icon := UiKit.icon(P0Logic.icon("trap_fish"), _TRAP_SIDE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var n := UiKit.label(count, UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY)
	n.name = "Count"
	box.add_child(n)
	return box

## Who is in an outpost: the map pin's count (UiMapDestination, q(137) ③) — a primary pill, a 9 person, C10 XB light.
func _online(n: int) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.name = "Online"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY, 8.0).with_margins(4.0, 1.0, 4.0, 1.0))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 2)
	var person := UiKit.icon(load(_PERSON), _PERSON_SIDE)
	person.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(person)
	var count := UiKit.label(str(n), UiTokens.STYLE_C10_XB, UiTokens.COLOR_SURFACE_RAISED)
	count.name = "Count"
	row.add_child(count)
	pill.add_child(row)
	return pill
