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

signal mute_pressed(peer: int, on: bool)
signal mute_all_pressed(on: bool)
signal block_pressed(peer: int, on: bool)
signal report_pressed(peer: int)

const HEIGHT := 447.0      # the titles drawer's most (MAP-8)
const ROW_H := 44.0       # a touch high, and the line under it
const _CHROME := 154.0    # handle, title row, its line, Close
const DOT := 8.0
const EMPTY := "No one else here"

var title: Label
var all_key: UiNavButton
var close: UiNavButton
var list: VBoxContainer
var rows: Array = []
var _scroll: TouchScrollContainer

func _init(title_: String = "", rows_: Array = []) -> void:
	super(height_for(rows_.size()))
	pad = UiTokens.SPACE_PAGE
	var head := HBoxContainer.new()
	head.name = "Head"
	title = UiKit.label(title_, UiTokens.STYLE_TITLE_XB20)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	all_key = _key("Mute all")
	all_key.name = "MuteAll"
	all_key.pressed.connect(func(): mute_all_pressed.emit(not _all_muted()))
	head.add_child(all_key)
	body.add_child(head)
	body.add_child(_line())
	_scroll = TouchScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)   # as tall as its rows (refresh), Close right under them
	list = VBoxContainer.new()
	list.name = "People"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 0)
	_scroll.add_child(list)
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

static func height_for(n: int) -> float:
	return minf(HEIGHT, _CHROME + maxi(1, n) * (ROW_H + 1.0))

## The rows again (the room's `changed`): rebuilt, the drawer as tall as they need.
func refresh(rows_: Array) -> void:
	rows = rows_
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	if rows.is_empty():
		var none := UiKit.label(EMPTY, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
		none.name = "Empty"
		none.custom_minimum_size.y = ROW_H
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		list.add_child(none)
	for r in rows:
		if list.get_child_count() > 0: list.add_child(_line())
		list.add_child(_row(r))
	all_key.visible = not rows.is_empty()
	all_key.label = "Unmute all" if _all_muted() else "Mute all"
	height = height_for(rows.size())
	_scroll.custom_minimum_size.y = minf(HEIGHT - _CHROME, maxi(1, rows.size()) * (ROW_H + 1.0) - 1.0)

## Everyone not blocked is muted (Unmute all then); with nobody to mute it stays Mute all.
func _all_muted() -> bool:
	var open := rows.filter(func(r): return not bool(r.get("blocked", false)))
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
