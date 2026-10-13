extends UiDrawer
## The Homestead Stall's Notice Board (q(164); 不知火舞's spec on SGODOT-284, the board's frame to come from 安其拉): a
## half-screen drawer as MAP-8's Nearby cities, as tall as its content, at most 560, scrolling past that:
##   `Notice Board` (C14 XB) over `San Francisco · Today · tap a place to see it on the map` (C12 B secondary),
##   `Ponds` and `Outposts` (C12 XB section heads, as the Bite Board's),
##   a 64 row per place, the whole row a tap with a `›` on its right: a 40 round icon (the pin's: pond, or the
##     outpost's role), the short name (C14 XB) over its line — a pond's best bite today, an outpost's kind, or, while
##     its pin wears a mark, the reason with that mark (P0PlaceSheet.reason_row, q(103)) — and before the `›` the
##     player's trap in a pond (trap icon + `2/3`) or who is in an outpost (person + `3`, none at 0, q(72)).
## A tap emits place_pressed(go) — `pond:<id>` / `outpost:<id>`: the P0 UI closes the drawer and the map flies there,
## moving nobody (q(31), k(1)). Everything comes from P0NoticeBoard.model(view, online).

signal place_pressed(go: String)

const Board := preload("res://modules/p0/p0_notice_board.gd")
const MAX_HEIGHT := 560.0
const ROW_H := 64.0
const _ICON := 40.0
const _ICON_GLYPH := 24.0
const _TOP := 20.0
const _GAP := 12
const _PERSON := "res://assets/ui/kit_icons/count_person.svg"

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
	var title := UiKit.label(str(model.title), UiTokens.STYLE_C14_XB)
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
	var line := StyleBoxFlat.new()   # a 1 px border line under the row, nothing else drawn
	line.bg_color = Color.TRANSPARENT
	line.border_color = UiTokens.COLOR_BORDER
	line.border_width_bottom = UiTokens.STROKE_DEFAULT
	for s in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]: b.add_theme_stylebox_override(s, line)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 12)
	var disc := Panel.new()   # the pin's own icon on a 40 round disc
	disc.name = "Icon"
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.custom_minimum_size = Vector2(_ICON, _ICON)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, _ICON * 0.5))
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
	var name_ := UiKit.label(str(r.name), UiTokens.STYLE_C14_XB)
	name_.name = "Name"
	text.add_child(name_)
	var why: Dictionary = r.get("reason", {})
	if not why.is_empty(): text.add_child(P0PlaceSheet.reason_row(why))   # the pin's mark and why (q(103))
	else:
		var said := UiKit.label(str(r.line), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
		said.name = "Line"
		said.clip_text = true
		said.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(said)
	row.add_child(text)
	if str(r.get("trap", "")) != "": row.add_child(_badge("Trap", P0Logic.icon("trap_fish"), 16, str(r.trap)))
	if int(r.get("online", 0)) > 0: row.add_child(_badge("Online", load(_PERSON), 12, str(int(r.online))))
	var chevron := UiKit.label("›", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_INFO)
	chevron.add_theme_font_size_override(&"font_size", 16)
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chevron)
	b.add_child(row)
	var go := str(r.go)
	b.pressed.connect(func(): place_pressed.emit(go))
	rows.append(b)
	return b

## An icon and its count before the `›`: the trap's `2/3`, or who is in (the pin's person count, q(137) ③).
func _badge(id: String, tex: Texture2D, side: float, count: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = id
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override(&"separation", 4)
	var icon := UiKit.icon(tex, side)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var n := UiKit.label(count, UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	n.name = "Count"
	box.add_child(n)
	return box
