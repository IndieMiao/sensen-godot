extends Control
## Choose your home city (HOME-PICK-1 2552:131461 / -2 2555:131560, SGODOT-303; q(188), q(205), q(207)): a new
## player's first page, before any world.
##   `Choose your home city` (ExtraBold 22) at 40 and its line (Regular 14, secondary) at 74; the search field
##   (TextField 1236:107829, Empty / Focused) 328 × 48 at 124; the list 344 wide from 180 to 720, scrolling under the
##   bottom fade (108, surface from 30 %) and `Continue` (CommandButton, 736).
##   The list (P0HomePick.sections): `Near you` and its row (the city the address is near, picked when the page opens),
##   `Recommended` and the climate groups; with no city near (q(205), HOME-PICK-1-NOIP 2771:162818) no `Near you` and
##   nothing picked: the key is the grey `Pick a city` (LOCK-10) until a row is picked. Typing two letters or more
##   searches (HOME-PICK-2): the matches only, no titles; one that cannot be picked reads grey with why (CityRow PICK).
##   q(207): the list fails — `Couldn't load cities` and Retry in its place (PICK-ERR-LIST 2773:182247; a failed search
##   too); a search finds nothing — `No matching cities` under the field (13 Bold secondary, PICK-SEARCH-EMPTY
##   2773:182352), no list. The key follows the city picked either way.
##   CHANGE (HOME-CHANGE-PICK 2647:135097, q(188) ④ / q(205) ④; SGODOT-303 PR-4), from Settings: BackPill
##   `‹  Settings` 12 / 16; `Change home city` at 72 and `Your farm and everything on it move with you.` at 106; the
##   field at 137 and the list from 193. Nothing picked when it opens; the home city reads grey, `Your home city`.
## Emits picked(row), unavailable(text), back_pressed (CHANGE) and asks the host to read with read_cities(query) (the host answers with
## show_cities / show_failed).

signal picked(row: Dictionary)
signal unavailable(text: String)
signal read_cities(query: String)
signal back_pressed

const P0HomePick := preload("res://modules/p0/p0_home_pick.gd")
const P0CityRow := preload("res://scenes/p0/panels/p0_city_row.gd")
const P0Travel := preload("res://modules/p0/p0_travel.gd")
const SpotPage := preload("res://scenes/p0/panels/p0_home_spot_page.gd")
## CHANGE: the title and its line 32 lower (under the back pill), the field and the list 13 (the line is one line).
const _CHANGE_HEAD_DY := 32.0
const _CHANGE_DY := 13.0

const _TITLE_Y := 40.0
const _BODY_Y := 74.0
const _FIELD_Y := 124.0
const _FIELD_H := 48.0
const _LIST_Y := 180.0
const _LIST_BOTTOM := 720.0
const _LIST_W := 344.0
const _FADE_H := 108.0
const _KEY_Y := 736.0
const _KEY_H := 48.0
const _NONE_Y := 184.0       # PICK-SEARCH-EMPTY's line
const _ERROR_Y := 324.0      # PICK-ERR-LIST's block
const _TITLE_SIZE := 22
const SEARCH_WAIT_S := 0.3   # a search goes out once the typing stops this long

var heading := "Choose your home city"
var line := "Your farm, outposts and first pond will be here. You can change it once while your farm is new."
var home := ""               # a change of home: the city it is now (grey, `Your home city`)
var choice := ""             # the city picked
var query := ""
var open_rows: Array = []
var near: Variant = null
var _no_preselect := false   # CHANGE, or come from HOME-WELCOME: Near you is shown, not picked
var matches: Variant = null  # the search's rows, null when not searching
var field: SearchField
var list: VBoxContainer
var scroll: TouchScrollContainer
var key: UiCommandButton
var none: Label
var error: Control
var rows := {}               # city id → its CityRow
var _rows_data := {}         # city id → its row
var _wait := -1.0
var _opened := false         # the first answer has picked what the page opens with

## change_from: the home city now — the change of home (CHANGE); "" for a new player's first pick.
## back_to: a first pick come from HOME-WELCOME (SGODOT-340 §4) — `‹ Back` to it, and `Near you` stays but is not
## picked (`Pick a city` grey until a row is), as on the change of home.
func _init(safe_top := 0.0, safe_bottom := 0.0, change_from := "", back_to := "") -> void:
	name = "HomePickPage"
	home = change_from
	_no_preselect = home != "" or back_to != ""
	var back_text := "Settings" if home != "" else back_to
	var dy_head := _CHANGE_HEAD_DY if back_text != "" else 0.0
	# CHANGE's one-line body takes 19 of the pill's 32 back; the first pick's two lines keep all 32 (from HOME-WELCOME)
	var dy := (_CHANGE_DY if home != "" else _CHANGE_HEAD_DY) if back_text != "" else 0.0
	if home != "":
		heading = "Change home city"
		line = "Your farm and everything on it move with you."
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UiTokens.COLOR_SURFACE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var t := UiKit.label(heading, UiTokens.STYLE_TITLE_XB20)
	t.name = "Title"
	t.add_theme_font_size_override(&"font_size", _TITLE_SIZE)
	_place(t, _TITLE_Y + dy_head + safe_top)
	var b := UiKit.label(line, UiTokens.STYLE_BODY_R14, UiTokens.COLOR_SECONDARY)
	b.name = "Line"
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place(b, _BODY_Y + dy_head + safe_top)
	scroll = TouchScrollContainer.new()
	scroll.name = "List"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8
	scroll.offset_right = -8
	scroll.offset_top = _LIST_Y + dy + safe_top
	scroll.offset_bottom = _LIST_BOTTOM - 800.0 - safe_bottom
	add_child(scroll)
	list = VBoxContainer.new()
	list.name = "Rows"
	list.custom_minimum_size.x = _LIST_W
	list.add_theme_constant_override(&"separation", 0)
	scroll.add_child(list)
	field = SearchField.new()
	field.name = "Search"
	_place(field, _FIELD_Y + dy + safe_top)
	field.text_changed.connect(_typed)
	none = UiKit.label("No matching cities", UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY)
	none.name = "NoMatches"
	none.visible = false
	_place(none, _NONE_Y + dy + safe_top)
	error = _error(_ERROR_Y + dy + safe_top)
	if back_text != "":
		var back := SpotPage.BackPill.new(back_text)
		back.position = Vector2(12, 16 + safe_top)
		back.pressed.connect(func(): back_pressed.emit())
		add_child(back)
	var fade := TextureRect.new()
	fade.name = "Fade"
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(UiTokens.COLOR_SURFACE, 0.0), UiTokens.COLOR_SURFACE, UiTokens.COLOR_SURFACE])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	fade.offset_top = -_FADE_H - safe_bottom
	add_child(fade)
	key = UiCommandButton.new("Continue")
	key.name = "Continue"
	key.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	key.offset_left = UiTokens.SPACE_PAGE
	key.offset_right = -UiTokens.SPACE_PAGE
	key.offset_top = _KEY_Y - 800.0 - safe_bottom
	key.offset_bottom = key.offset_top + _KEY_H
	key.activated.connect(func(): if _rows_data.has(choice): picked.emit(_rows_data[choice]))
	key.unavailable_pressed.connect(func(text: String): unavailable.emit(text))
	add_child(key)
	_refresh_key()

func _place(c: Control, y: float) -> void:
	c.position = Vector2(UiTokens.SPACE_PAGE, y)
	c.size.x = 328
	if c is Label: (c as Label).custom_minimum_size.x = 328
	add_child(c)

func _error(y: float) -> Control:
	var box := VBoxContainer.new()
	box.name = "Error"
	box.add_theme_constant_override(&"separation", 4)
	box.position = Vector2(32, y)
	box.custom_minimum_size.x = 296
	box.add_child(UiEmptyState.new("Couldn't load cities", preload("res://assets/ui/kit_icons/wifi_off.svg")))
	var retry := UiCommandButton.new("Retry", UiCommandButton.Kind.SECONDARY, true)
	retry.name = "Retry"
	retry.fit_text = true
	retry.min_width = 68   # Compact/Command: hugs its label, at least 68
	retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	retry.activated.connect(func():
		box.visible = false
		read_cities.emit(query))
	box.add_child(retry)
	box.visible = false
	add_child(box)
	return box

func _process(dt: float) -> void:
	if _wait < 0.0: return
	_wait -= dt
	if _wait < 0.0: read_cities.emit(query)

func _typed(text: String) -> void:
	query = text.strip_edges()
	if query.length() < P0HomePick.SEARCH_MIN:
		_wait = -1.0
		matches = null
		_lay_out()
	else:
		_wait = SEARCH_WAIT_S

## Whether an answer read for `q` is still the one the page wants (a late one for an older search is dropped).
func _current(q: String) -> bool:
	return q == query or (q.length() < P0HomePick.SEARCH_MIN and query.length() < P0HomePick.SEARCH_MIN)

## The route's answer read for `for_query`.
func show_cities(data: Dictionary, for_query := "") -> void:
	if not _current(for_query): return
	open_rows = data.get("open", [])
	near = data.get("near", null)
	for r in open_rows + ([near] if near is Dictionary else []): _rows_data[str(r.get("id", ""))] = r
	if not _opened:
		_opened = true
		choice = P0HomePick.preselect(near, _no_preselect)
	matches = data.get("matches", []) if query.length() >= P0HomePick.SEARCH_MIN else null
	error.visible = false
	_lay_out()

## PICK-ERR-LIST: the read did not come (the list, or a search).
func show_failed(for_query := "") -> void:
	if not _current(for_query): return
	for c in list.get_children(): c.queue_free()
	rows.clear()
	none.visible = false
	scroll.visible = false
	error.visible = true

func _lay_out() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	rows.clear()
	error.visible = false
	var parts := P0HomePick.sections(open_rows, near, matches, home)
	var searching := matches is Array
	none.visible = searching and (matches as Array).is_empty()
	scroll.visible = not none.visible
	for p in parts:
		match str(p.kind):
			"title": list.add_child(_title(str(p.text)))
			"band": list.add_child(_band(str(p.band), str(p.text)))
			"row": list.add_child(_row(p.row))
	var end := Control.new()
	end.name = "End"
	end.custom_minimum_size.y = _FADE_H - (800.0 - _LIST_BOTTOM)
	list.add_child(end)
	_refresh_key()

## `Near you` / `Recommended`: ExtraBold 13 secondary, 12 over and 4 under, 8 in (the list's 328 column).
func _title(text: String) -> Control:
	var m := _indent(12, 4)
	m.name = "Title_" + text.replace(" ", "")
	m.add_child(UiKit.label(text, UiTokens.STYLE_C13_XB, UiTokens.COLOR_SECONDARY))
	return m

## A climate group's title: its glyph 14 in the band's colour, 6, the band (Bold 12 secondary); 12 over, 4 under.
func _band(b: String, text: String) -> Control:
	var m := _indent(12, 4)
	m.name = "Band_" + b
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 6)
	var glyph := UiKit.icon(GameUi.icon("i-climate-" + b), 14)
	var tint: ShaderMaterial = P0CityRow._material()   # the glyph's own fill is dark: tinted, not multiplied
	tint.set_shader_parameter(&"mode", 1)
	tint.set_shader_parameter(&"tint", (P0CityRow.BANDS.get(b, P0CityRow.BANDS.temperate) as Dictionary).ink)
	glyph.material = tint
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(glyph)
	h.add_child(UiKit.label(text, UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY))
	m.add_child(h)
	return m

func _indent(top: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [[&"margin_left", 8], [&"margin_right", 8], [&"margin_top", top], [&"margin_bottom", bottom]]:
		m.add_theme_constant_override(side[0], side[1])
	return m

func _row(r: Dictionary) -> Control:
	var id := str(r.get("id", ""))
	var shown := {cluster = id, name = str(r.get("name", "")), region = str(r.get("region", "")),
		climate = str(r.get("climate", "")), landmark = P0Travel.landmark_stamp(id)}
	var row = P0CityRow.new(shown, P0HomePick.note(r, home))
	row.picked = id == choice
	row.pressed.connect(func(): set_choice(id))
	rows[id] = row
	_rows_data[id] = r
	return row

func set_choice(id: String) -> void:
	choice = id
	for k in rows: rows[k].picked = k == id
	_refresh_key()

func _refresh_key() -> void:
	key.reason = "" if choice != "" and _rows_data.has(choice) else "Pick a city"

## TextField (1236:107829) as the search: 48 high, surface, 1 px border, radius 12, 14 in; Bold 15, the placeholder
## `Search a city` in secondary; focused, a 2 px primary edge and the text in text colour.
class SearchField extends LineEdit:
	func _init() -> void:
		placeholder_text = "Search a city"
		custom_minimum_size.y = 48
		size.y = 48
		theme_type_variation = UiTokens.STYLE_ROW_TITLE_B15
		add_theme_font_size_override(&"font_size", 15)
		add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT)
		add_theme_color_override(&"font_placeholder_color", UiTokens.COLOR_SECONDARY)
		add_theme_color_override(&"caret_color", UiTokens.COLOR_PRIMARY)
		clear_button_enabled = false
		virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
		for s in [[&"normal", false], [&"focus", true], [&"read_only", false]]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiTokens.COLOR_SURFACE
			sb.border_color = UiTokens.COLOR_PRIMARY if s[1] else UiTokens.COLOR_BORDER
			sb.set_border_width_all(2 if s[1] else 1)
			sb.set_corner_radius_all(12)
			sb.content_margin_left = 14
			sb.content_margin_right = 14
			add_theme_stylebox_override(s[0], sb)
