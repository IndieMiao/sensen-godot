class_name P0SettingsPage
extends Control
## Settings and its Legal pages (q(129); 不知火舞 on 280 4c8d286a and the Licenses brief), full screen on the cream
## surface: a fixed PageHeader (E-12) where the profile's top bar is — its back on the profile's back, safe area included
## (不知火舞 on #292: pages of one path, the back never jumps) — and the page scrolling under it, 16 in, 12 below it.
##   SETTINGS  (SETTINGS-1-2 1252:88686, P0 subset) only rows that do something (不知火舞: no greyed rows): the
##             `Licenses ›`, visible `Test options ›`, and read-only `Version` (`0.2.1 (2026101001)`). Terms of Service and
##             Privacy Policy join it once they have real addresses (奕星).
##   LICENSES  (SET-LICENSES 1254:88796) P0Legal's groups (Software, Map data), each row › to its text.
##   TEXT      no frame: the row's title in the header, its full text below — Regular 13 secondary, 16 in, paragraphs
##             8 apart (不知火舞: long legal text is too heavy in bold), the hard-wrapped lines joined (P0Legal). A credit
##             with a link (DB-IP, q(205) ⑥) puts `db-ip.com ›` first, above the text: open_pressed("link").
##   MAP_DATA  (q(133) v3, Q133-V3-MAPDATA 2425:129113) from Licenses › Mapbox: `Credits` — `© Mapbox ›`,
##             `© OpenStreetMap contributors ›` — then an untitled group: `Improve this map ›` and the switch `Share
##             anonymous map usage` (`Helps Mapbox improve its maps`).
## Emits back_pressed, open_pressed(what): "licenses", a row id, or a Map data row ("mapbox_site", "osm_site",
## "improve"); toggled(what, on): "telemetry".

signal back_pressed
signal open_pressed(what: String)
signal toggled(what: String, on: bool)

enum Kind { SETTINGS, LICENSES, TEXT, MAP_DATA, TEST_OPTIONS }

const _HEADER_X := UiTokens.SIZE_QUICK_BAR_X   # the profile's top bar's x
const _HEADER_H := 48.0
## The profile's top bar's y, less half what the header is taller (48 vs its 44 buttons): the backs sit on one centre.
const _HEADER_Y := P0ProfilePage._TOP - (_HEADER_H - UiTokens.SIZE_CLOSE) * 0.5
const _CONTENT_GAP := 12    # header → content (SET-LICENSES: 64 → 76)
const _GROUP_GAP := 8       # group title → its card → the next title
const _BODY_SIZE := 13      # the licence text: Regular 13 (Caption R12 a step up; no 13 Regular style exported)
const _PARAGRAPH_GAP := 8
## A long text (Mapbox's LICENSE.md: 660 paragraphs, about 0.3 s laid out at once on a desktop) opens with its first
## screens and fills in the rest a batch a frame, so the page is up at once.
const _FIRST_PARAGRAPHS := 30
const _PARAGRAPHS_PER_FRAME := 20

var _to_add: Array = []     # TEXT: paragraphs not laid out yet

var kind: Kind
var header: UiPageHeader
var body: VBoxContainer
var scroll: TouchScrollContainer

func _init(kind_ := Kind.SETTINGS, title := "Settings", safe_top := 0.0, safe_bottom := 0.0) -> void:
	kind = kind_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UiTokens.COLOR_SURFACE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	scroll = TouchScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = _HEADER_Y + _HEADER_H + safe_top   # the header stays; the page scrolls under it
	add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override(&"margin_left", UiTokens.SPACE_PAGE)
	pad.add_theme_constant_override(&"margin_right", UiTokens.SPACE_PAGE)
	pad.add_theme_constant_override(&"margin_top", _CONTENT_GAP)
	pad.add_theme_constant_override(&"margin_bottom", int(UiTokens.SPACE_SECTION + safe_bottom))
	scroll.add_child(pad)
	body = VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override(&"separation", _PARAGRAPH_GAP if kind == Kind.TEXT else _GROUP_GAP)
	pad.add_child(body)
	header = UiPageHeader.new(title)
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = _HEADER_X
	header.offset_right = -_HEADER_X
	header.offset_top = _HEADER_Y + safe_top
	header.offset_bottom = header.offset_top + _HEADER_H
	header.back_pressed.connect(func(): back_pressed.emit())
	add_child(header)

## SETTINGS (P0): Home, an untitled `Test options ›` group, then the unchanged Legal group (Licenses and Version)
## (341 d559585e, corrected by 0d94c10d). `home` {name, line, open}: while the change is open, `Home city · Tokyo` ›
## with `Change once · 5 days left` under it, opening the change ("home"); once it is not, the same row read-only with
## `Set for good`. No home (a view not in yet): no Home group.
static func settings(version: String, safe_top := 0.0, safe_bottom := 0.0, home := {}) -> P0SettingsPage:
	var page := P0SettingsPage.new(Kind.SETTINGS, "Settings", safe_top, safe_bottom)
	if not home.is_empty():
		var title := "Home city · " + str(home.get("name", ""))
		var row := UiSettingRow.new(UiSettingRow.Kind.LINK if bool(home.get("open", false)) else UiSettingRow.Kind.VALUE, title,
			str(home.get("line", "")))
		row.name = "HomeCity"
		row.pressed.connect(func(): page.open_pressed.emit("home"))
		page._group("Home", [row])
	var tests := UiSettingRow.new(UiSettingRow.Kind.LINK, "Test options")
	tests.name = "TestOptions"
	tests.pressed.connect(func(): page.open_pressed.emit("test_options"))
	page._group("", [tests])
	var licenses := UiSettingRow.new(UiSettingRow.Kind.LINK, "Licenses")
	licenses.name = "Licenses"
	licenses.pressed.connect(func(): page.open_pressed.emit("licenses"))
	var ver := UiSettingRow.new(UiSettingRow.Kind.VALUE, "Version", "", version)
	ver.name = "Version"
	page._group("Legal", [licenses, ver])
	return page

## Visible test settings (341 d559585e), retaining the approved B page layout and copy (aa0e971b).
static func test_options(on: bool, is_test: bool, safe_top := 0.0, safe_bottom := 0.0) -> P0SettingsPage:
	var page := P0SettingsPage.new(Kind.TEST_OPTIONS, "Test options", safe_top, safe_bottom)
	var toggle := UiSettingRow.new(UiSettingRow.Kind.TOGGLE, "New-player guide", "For new test accounts")
	toggle.name = "GuideTestToggle"
	toggle.on = on
	toggle.toggled.connect(func(value): page.toggled.emit("guide_test", value))
	page._group("", [toggle])
	var current := UiSettingRow.new(UiSettingRow.Kind.VALUE, "Current account", "", "Test" if is_test else "Main")
	current.name = "CurrentAccount"
	page._group("", [current])
	var start := UiCommandButton.new("Start new test account", UiCommandButton.Kind.SECONDARY)
	start.name = "StartTestAccount"
	start.sends = false
	start.activated.connect(func(): page.open_pressed.emit("test_new"))
	page.body.add_child(start)
	if is_test:
		var back := UiCommandButton.new("Return to main account", UiCommandButton.Kind.SECONDARY)
		back.name = "ReturnMainAccount"
		back.sends = false
		back.activated.connect(func(): page.open_pressed.emit("test_main"))
		page.body.add_child(back)
	var note := UiKit.label("Test accounts are separate. Your main farm is kept.", UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_SECONDARY)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.body.add_child(note)
	return page

## 341 6d532fc2: the test account's escape from first city pick / failed launch, using the existing text button.
static func return_main_link(action: Callable) -> UiDismissButton:
	var button := UiDismissButton.new("Return to main account")
	button.name = "ReturnMainAccount"
	button.add_theme_font_override(&"font", UiKit.font(&"bold"))
	button.add_theme_font_size_override(&"font_size", UiKit.theme().get_font_size(&"font_size", UiTokens.STYLE_CAPTION_B12))
	for state in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		button.add_theme_color_override(state, UiTokens.COLOR_PRIMARY)
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(action)
	return button

## LICENSES: one group per P0Legal group, a row per credit (`MIT License` under it; a data credit's attribution, then
## its licence), each row › to its text.
static func licenses(groups: Array, safe_top := 0.0, safe_bottom := 0.0) -> P0SettingsPage:
	var page := P0SettingsPage.new(Kind.LICENSES, "Licenses", safe_top, safe_bottom)
	for g in groups:
		var rows: Array = []
		for r in g.get("rows", []):
			var id := str(r.get("id", ""))
			var row := UiSettingRow.new(UiSettingRow.Kind.LINK, str(r.get("title", "")), str(r.get("license", "")), "", str(r.get("credit", "")))
			row.name = id
			row.pressed.connect(func(): page.open_pressed.emit(id))
			rows.append(row)
		page._group(str(g.get("title", "")), rows)
	return page

## MAP_DATA (q(133) v3): Mapbox's credits, the feedback page and the telemetry switch (`sharing`: its state now).
static func map_data(sharing: bool, safe_top := 0.0, safe_bottom := 0.0) -> P0SettingsPage:
	var page := P0SettingsPage.new(Kind.MAP_DATA, "Map data", safe_top, safe_bottom)
	var credits: Array = []
	for spec in [["mapbox_site", "© Mapbox"], ["osm_site", "© OpenStreetMap contributors"]]:
		var row := UiSettingRow.new(UiSettingRow.Kind.LINK, spec[1])
		row.name = spec[0]
		row.pressed.connect(func(): page.open_pressed.emit(spec[0]))
		credits.append(row)
	page._group("Credits", credits)
	var improve := UiSettingRow.new(UiSettingRow.Kind.LINK, "Improve this map")
	improve.name = "improve"
	improve.pressed.connect(func(): page.open_pressed.emit("improve"))
	var share := UiSettingRow.new(UiSettingRow.Kind.TOGGLE, "Share anonymous map usage", "Helps Mapbox improve its maps")
	share.name = "telemetry"
	share.on = sharing
	share.toggled.connect(func(on: bool): page.toggled.emit("telemetry", on))
	page._group("", [improve, share])
	return page

## TEXT: a credit's full text under its title; `link` ({label}: the credit's own site, q(205) ⑥) a row above it.
static func text(title: String, full_text: String, safe_top := 0.0, safe_bottom := 0.0, link := {}) -> P0SettingsPage:
	var page := P0SettingsPage.new(Kind.TEXT, title, safe_top, safe_bottom)
	if str(link.get("label", "")) != "":
		var row := UiSettingRow.new(UiSettingRow.Kind.LINK, str(link.label))
		row.name = "link"
		row.pressed.connect(func(): page.open_pressed.emit("link"))
		page._group("", [row])
	page._to_add = P0Legal.paragraphs(full_text)
	page._add_paragraphs(_FIRST_PARAGRAPHS)
	return page

## TEXT: the paragraphs still to lay out, a batch a frame.
func _process(_dt: float) -> void:
	if _to_add.is_empty():
		set_process(false)
		return
	_add_paragraphs(_PARAGRAPHS_PER_FRAME)

func _add_paragraphs(n: int) -> void:
	for p in _to_add.slice(0, n):
		var l := UiKit.label(str(p), UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_SECONDARY)
		l.add_theme_font_size_override(&"font_size", _BODY_SIZE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(l)
	_to_add = _to_add.slice(n)

## TEXT: every paragraph is on the page (the batches done).
func complete() -> bool: return _to_add.is_empty()

## A group title (SETTINGS-1's: Bold 12 secondary) and its rows in one card. An untitled group keeps 8 more apart from
## the card above it (Q133-V3-MAPDATA: 24 between the two cards).
func _group(title: String, rows: Array) -> void:
	if title != "":
		var t := UiKit.label(title, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
		t.name = "Group " + title
		body.add_child(t)
	elif body.get_child_count() > 0:
		var gap := Control.new()
		gap.name = "Gap"
		gap.custom_minimum_size.y = _GROUP_GAP
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(gap)
	body.add_child(UiSettingRow.group(rows))
