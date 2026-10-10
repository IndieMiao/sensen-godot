class_name P0SettingsPage
extends Control
## Settings and its Legal pages (q(129); 不知火舞 on 280 4c8d286a and the Licenses brief), full screen on the cream
## surface: a fixed PageHeader (8 in, 16 down; E-12) and the page scrolling under it (16 in, content from 76).
##   SETTINGS  (SETTINGS-1-2 1252:88686, P0 subset) only rows that do something (不知火舞: no greyed rows): the
##             Legal group's `Licenses ›` and the read-only `Version` (`0.2.1 (2026101001)`). Terms of Service and
##             Privacy Policy join it once they have real addresses (奕星).
##   LICENSES  (SET-LICENSES 1254:88796) P0Legal's groups (Software, Map data), each row › to its text.
##   TEXT      no frame: the row's title in the header, its full text below — Regular 13 secondary, 16 in, paragraphs
##             8 apart (不知火舞: long legal text is too heavy in bold), the hard-wrapped lines joined (P0Legal).
## Emits back_pressed, open_pressed(what): "licenses" or a row id.

signal back_pressed
signal open_pressed(what: String)

enum Kind { SETTINGS, LICENSES, TEXT }

const _HEADER_X := 8.0      # PageHeader, 344 wide at 360
const _HEADER_Y := 16.0
const _HEADER_H := 48.0
const _CONTENT_TOP := 76.0  # where the content starts (12 under the header)
const _GROUP_GAP := 8       # group title → its card → the next title
const _BODY_SIZE := 13      # the licence text: Regular 13 (Caption R12 a step up; no 13 Regular style exported)
const _PARAGRAPH_GAP := 8

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
	pad.add_theme_constant_override(&"margin_top", int(_CONTENT_TOP - _HEADER_Y - _HEADER_H))
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

## SETTINGS (P0): Legal · `Licenses ›` and `Version`.
static func settings(version: String, safe_top := 0.0, safe_bottom := 0.0) -> P0SettingsPage:
	var page := P0SettingsPage.new(Kind.SETTINGS, "Settings", safe_top, safe_bottom)
	var licenses := UiSettingRow.new(UiSettingRow.Kind.LINK, "Licenses")
	licenses.name = "Licenses"
	licenses.pressed.connect(func(): page.open_pressed.emit("licenses"))
	var ver := UiSettingRow.new(UiSettingRow.Kind.VALUE, "Version", "", version)
	ver.name = "Version"
	page._group("Legal", [licenses, ver])
	return page

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

## TEXT: a credit's full text under its title.
static func text(title: String, full_text: String, safe_top := 0.0, safe_bottom := 0.0) -> P0SettingsPage:
	var page := P0SettingsPage.new(Kind.TEXT, title, safe_top, safe_bottom)
	for p in P0Legal.paragraphs(full_text):
		var l := UiKit.label(str(p), UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_SECONDARY)
		l.add_theme_font_size_override(&"font_size", _BODY_SIZE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.body.add_child(l)
	return page

## A group title (SETTINGS-1's: Bold 12 secondary) and its rows in one card.
func _group(title: String, rows: Array) -> void:
	var t := UiKit.label(title, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	t.name = "Group " + title
	body.add_child(t)
	body.add_child(UiSettingRow.group(rows))
