extends UiDrawer
## This layer's people (SGODOT-383; q(274); 不知火舞's spec 383 6d206dfb §3–6): the people pill's drawer, the kit's drawer
## shell (the titles drawer's head). The title names the space and its layer (`Fern Pond · Layer 1`), with a text key
## at the right of the title row, `Mute all` / `Unmute all` (this phone only). A row per other person, as P0VoiceRoom
## .people() gives them: the green dot while they speak, their name as their name tag writes it, and three small text
## keys — `Mute` / `Unmute` (grey while blocked), `Block` / `Unblock`, `Report`. People without voice (iOS, never
## turned the mic on) are listed all the same. Nobody else: one muted line, `No one else here`. The host acts on the
## keys (Block asks first, Unblock does not) and calls refresh with the room's new rows.
## As 安其拉's V3 has it (383 50108c43, Figma row 124): the keys are plain text keys (the compact navigation look, no
## chevron), a 1 px line under the title and between rows, and `Close` under the last row — no ✕ over the drawer.
## q(286) (Market Square's voice, SGODOT-415; 不知火舞's M1-b 476:195818, 302 3085a574): a title too long for its row
## breaks at its ` · ` into two lines (`Mission Market Square` / `Layer 1`), `Mute all` at the first; the rows scroll as
## Today's do — a 16 px fade at an edge with rows past it, a 3 px bar at the right while they overflow.
## q(289) (SGODOT-415; 不知火舞 415 89764920): the player's own row first, scrolling with the rest — their name as their
## name tag writes it and a grey `You` at the keys' right edge, no keys, not tappable; alone, `No one else here` under it.
## q(309) (the user, 11-10: 「iOS 人数 ok」; 不知火舞's spec v1 ④): with no voice on this phone (iOS, a 13+ no, the server's
## voice off) `Mute all` and each row's `Mute` are not there — not greyed: they would do nothing; Block and Report stay
## (a Block hides the two from each other in a room, a Report is the server's line: neither needs voice).

signal mute_pressed(peer: int, on: bool)
signal mute_all_pressed(on: bool)
signal block_pressed(peer: int, on: bool)
signal report_pressed(peer: int)

const HEIGHT := 447.0      # the titles drawer's most (MAP-8)
const ROW_H := 44.0       # a touch high, and the line under it
const _CHROME := 154.0    # handle, title row, its line, Close
const _CHROME_2 := 173.0  # … the title in two lines (q(286))
const _FADE := 16.0       # Today's (UiTodayPanel): the fade at an edge with rows past it
const _BAR_W := 3.0       # … and its bar, 4 px in from the drawer's edge
const _BAR_INSET := 4.0
const DOT := 8.0
const EMPTY := "No one else here"

var title: Label
var all_key: UiNavButton
var close: UiNavButton
var list: VBoxContainer
var rows: Array = []
var _scroll: TouchScrollContainer
var _held: Control          # the scroll and, over it, its fades and bar
var _fade_top: TextureRect
var _fade_bottom: TextureRect
var _bar: Panel
var _raw_title := ""
var _two := false           # the title in two lines
var voice := true           # this phone has voice in this room: the Mute keys (q(309))

func _init(title_: String = "", rows_: Array = [], voice_ := true) -> void:
	super(height_for(rows_.size() + (0 if rows_.any(func(r): return not bool(r.get("self", false))) else 1)))
	voice = voice_
	pad = UiTokens.SPACE_PAGE
	var head := HBoxContainer.new()
	head.name = "Head"
	_raw_title = title_
	title = UiKit.label(title_, UiTokens.STYLE_TITLE_XB20)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # two lines at its ` · ` (_fit_title), never cut
	title.resized.connect(_fit_title)
	head.add_child(title)
	all_key = _key("Mute all")
	all_key.name = "MuteAll"
	all_key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # at the title's first line
	all_key.pressed.connect(func(): mute_all_pressed.emit(not _all_muted()))
	head.add_child(all_key)
	body.add_child(head)
	body.add_child(_line())
	_held = Control.new()
	_held.name = "Rows"
	body.add_child(_held)   # as tall as its rows (refresh), Close right under them
	_scroll = TouchScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_held.add_child(_scroll)
	_fade_top = _fade(true)
	_fade_bottom = _fade(false)
	_bar = Panel.new()
	_bar.name = "Bar"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_BORDER, _BAR_W * 0.5))
	_held.add_child(_bar)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v): _mark())
	_held.resized.connect(_mark)
	list = VBoxContainer.new()
	list.name = "People"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 0)
	_scroll.add_child(list)
	list.resized.connect(_mark)
	close = _key("Close")
	close.name = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): close_requested.emit())
	body.add_child(close)
	var rest := Control.new()
	rest.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rest)
	refresh(rows_)

## The drawer for n rows, the title in one line or two (q(286): 173 then, the rows' most 447 − 173 = 274).
static func height_for(n: int, two_lines := false) -> float:
	return minf(HEIGHT, (_CHROME_2 if two_lines else _CHROME) + maxi(1, n) * (ROW_H + 1.0))

## The rows again (the room's `changed`): rebuilt, the drawer as tall as they need.
func refresh(rows_: Array) -> void:
	rows = rows_
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for r in rows:
		if list.get_child_count() > 0: list.add_child(_line())
		list.add_child(_self_row(r) if bool(r.get("self", false)) else _row(r))
	if _others().is_empty():
		if list.get_child_count() > 0: list.add_child(_line())
		var none := UiKit.label(EMPTY, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
		none.name = "Empty"
		none.custom_minimum_size.y = ROW_H
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		list.add_child(none)
	all_key.visible = voice and not _others().is_empty()
	all_key.label = "Unmute all" if _all_muted() else "Mute all"
	_size_rows()

## The drawer and its rows as tall as the rows need, under the title as it is broken now: the others and the player's
## own row, `No one else here` a row when alone (q(289): 2 then).
func _size_rows() -> void:
	var n := _lines()
	height = height_for(n, _two)
	_held.custom_minimum_size.y = minf(HEIGHT - (_CHROME_2 if _two else _CHROME), maxi(1, n) * (ROW_H + 1.0) - 1.0)

func _others() -> Array: return rows.filter(func(r): return not bool(r.get("self", false)))

## The list's lines: every row, and `No one else here` when nobody else is in.
func _lines() -> int: return rows.size() + (1 if _others().is_empty() else 0)

## The title in one line when it fits the room left of `Mute all`, else in two at a ` · ` (UiKit.break_at_dot, its dot
## dropped); the drawer follows (_CHROME_2).
func _fit_title() -> void:
	if title.size.x <= 0.0: return
	var text := UiKit.break_at_dot(_raw_title, title.get_theme_font(&"font"), title.get_theme_font_size(&"font_size"), title.size.x)
	if text != title.text: title.text = text
	var two := text.contains("\n")
	if two != _two:
		_two = two
		_size_rows()

## Rows past the top or the bottom: that edge fades; the bar shows, while they overflow, where the view is (UiTodayPanel).
func _mark() -> void:
	if not is_instance_valid(_bar): return
	var view_h := _held.size.y
	var list_h := list.size.y
	var at := float(_scroll.scroll_vertical)
	var scrolls := list_h > view_h + 0.5
	_fade_top.visible = scrolls and at > 0.5
	_fade_bottom.visible = scrolls and at < list_h - view_h - 0.5
	_bar.visible = scrolls
	for f in [_fade_top, _fade_bottom]: (f as TextureRect).size = Vector2(_held.size.x, _FADE)
	_fade_top.position = Vector2.ZERO
	_fade_bottom.position = Vector2(0.0, view_h - _FADE)
	if scrolls:
		var h := maxf(12.0, view_h * view_h / list_h)
		_bar.size = Vector2(_BAR_W, h)
		# out in the right padding, 4 px in from the drawer's edge (its border's), as Today's
		_bar.position = Vector2(_held.size.x + pad - UiTokens.STROKE_DEFAULT - _BAR_INSET - _BAR_W, (view_h - h) * at / maxf(1.0, list_h - view_h))

func _fade(top: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, UiTokens.COLOR_SURFACE)
	g.set_color(1, Color(UiTokens.COLOR_SURFACE, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0) if top else Vector2(0, 1)
	tex.fill_to = Vector2(0, 1) if top else Vector2(0, 0)
	var r := TextureRect.new()
	r.name = "FadeTop" if top else "FadeBottom"
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = false
	_held.add_child(r)
	return r

## Everyone else not blocked is muted (Unmute all then); with nobody to mute it stays Mute all. Never the player.
func _all_muted() -> bool:
	var open := _others().filter(func(r): return not bool(r.get("blocked", false)))
	return not open.is_empty() and open.all(func(r): return bool(r.get("muted", false)))

func _row(r: Dictionary) -> HBoxContainer:
	var peer := int(r.get("peer", 0))
	var muted := bool(r.get("muted", false))
	var blocked := bool(r.get("blocked", false))
	var row := HBoxContainer.new()
	row.name = "Person_%d" % peer
	row.custom_minimum_size.y = ROW_H
	row.add_theme_constant_override(&"separation", UiTokens.SPACE_WITHIN)
	var dot := Panel.new()
	dot.name = "Speaking"
	dot.custom_minimum_size = Vector2(DOT, DOT)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY, DOT * 0.5))
	dot.modulate.a = 1.0 if bool(r.get("speaking", false)) and not muted and not blocked else 0.0
	row.add_child(dot)
	var name_l := UiKit.label(str(r.get("name", "")), UiTokens.STYLE_ROW_TITLE_XB15)
	name_l.name = "Name"
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_l)
	var mute := _key("Unmute" if muted else "Mute")
	mute.name = "Mute"
	mute.disabled = blocked   # blocked: nothing to hear either way
	mute.pressed.connect(func(): mute_pressed.emit(peer, not muted))
	mute.visible = voice
	row.add_child(mute)
	var block := _key("Unblock" if blocked else "Block")
	block.name = "Block"
	block.pressed.connect(func(): block_pressed.emit(peer, not blocked))
	row.add_child(block)
	var report := _key("Report")
	report.name = "Report"
	report.pressed.connect(func(): report_pressed.emit(peer))
	row.add_child(report)
	return row

## The player's own row (q(289)): the dot while they speak, their name, a grey `You` at the right where the keys end.
## Nothing to tap.
func _self_row(r: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Self"
	row.custom_minimum_size.y = ROW_H
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", UiTokens.SPACE_WITHIN)
	var dot := Panel.new()
	dot.name = "Speaking"
	dot.custom_minimum_size = Vector2(DOT, DOT)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY, DOT * 0.5))
	dot.modulate.a = 1.0 if bool(r.get("speaking", false)) else 0.0
	row.add_child(dot)
	var name_l := UiKit.label(str(r.get("name", "")), UiTokens.STYLE_ROW_TITLE_XB15)
	name_l.name = "Name"
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_l)
	var you := UiKit.label("You", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	you.name = "You"
	you.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	you.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(you)
	return row

## A text key (V3): the compact navigation look without its chevron.
static func _key(text: String) -> UiNavButton:
	var k := UiNavButton.new(text, true)
	k.chevron = false
	return k

static func _line() -> ColorRect:
	var l := ColorRect.new()
	l.color = UiTokens.COLOR_BORDER
	l.custom_minimum_size.y = 1.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
