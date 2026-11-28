class_name P0SettingsPage
extends Control
## Settings and its Legal pages (q(129); 不知火舞 on 280 4c8d286a and the Licenses brief), full screen on the cream
## surface: a fixed PageHeader (E-12) where the profile's top bar is — its back on the profile's back, safe area included
## (不知火舞 on #292: pages of one path, the back never jumps) — and the page scrolling under it, 16 in, 12 below it.
##   SETTINGS  (SETTINGS-1-2 1252:88686, P0 subset) only rows that do something (不知火舞: no greyed rows): the
##             `Licenses ›`, visible `Test options ›`, and read-only `Version` (`0.2.1 (2026101001)`); Terms of Service
##             and Privacy Policy with their real addresses.
##   LICENSES  (SET-LICENSES 1254:88796) P0Legal's groups (Software, Map data), each row › to its text.
##   TEXT      no frame: the row's title in the header, its full text below — Regular 13 secondary, 16 in, paragraphs
##             8 apart (不知火舞: long legal text is too heavy in bold), the hard-wrapped lines joined (P0Legal). A credit
##             with a link (DB-IP, q(205) ⑥) puts `db-ip.com ›` first, above the text: open_pressed("link").
##   MAP_DATA  (q(133) v3, Q133-V3-MAPDATA 2425:129113) from Licenses › Mapbox: `Credits` — `© Mapbox ›`,
##             `© OpenStreetMap contributors ›` — then an untitled group: `Improve this map ›` and the switch `Share
##             anonymous map usage` (`Helps Mapbox improve its maps`).
##   NOTIFICATIONS (SET-NOTIF 9:120045, q(236) ⑤, q(237); Android only) from Settings' `Notifications ›`: the one
##             switch `Crops ready` (`When a plot is ready to harvest`); when the system has said no, above it the Info
##             toast card `Notifications are off for <the app's name>` with `Open system settings ›` (不知火舞 350
##             7bffafd7) — and the switch reads off whatever the frame drew (dbd8d596).
##   BLOCKED   (SGODOT-384; q(28) §12.1.6; 不知火舞's spec 383, BP2 / BP3 row 127) from Settings' `Blocked players ›`:
##             the voice blocks, the only way to lift one now that the two never see each other in a room. A row each in
##             one card, the name as their name tag writes it (`Traveller 5dd4`) and the people drawer's text key
##             `Unblock`; a tap takes the row away at once — no card, no toast — and emits open_pressed(handle). No one:
##             `No one blocked`, secondary, centred — only once the list has been read. Never read this launch and
##             the read failed: in the list's place the empty state (wifi_off, `Check your connection and try again.`)
##             and `Retry` (Compact secondary), as the home pick's error (不知火舞 384 6e014af3); Retry emits
##             open_pressed("retry"), nothing retries by itself. No date under a name: the server keeps none (后裔 #661).
## Emits back_pressed, open_pressed(what): "licenses", a row id, or a Map data row ("mapbox_site", "osm_site",
## "improve", "notifications", "system_settings", "blocked_players", "voice_chat"), a blocked player's handle or
## "retry" on BLOCKED;
## toggled(what, on): "telemetry", "crops_ready".

signal back_pressed
signal open_pressed(what: String)
signal toggled(what: String, on: bool)

enum Kind { SETTINGS, LICENSES, TEXT, MAP_DATA, TEST_OPTIONS, NOTIFICATIONS, BLOCKED, LANGUAGE, DELETE }

const _HEADER_X := UiTokens.SIZE_QUICK_BAR_X   # the profile's top bar's x
const _HEADER_H := 48.0
## The profile's top bar's y, less half what the header is taller (48 vs its 44 buttons): the backs sit on one centre.
const _HEADER_Y := P0ProfilePage._TOP - (_HEADER_H - UiTokens.SIZE_CLOSE) * 0.5
const _CONTENT_GAP := 12    # header → content (SET-LICENSES: 64 → 76)
const _GROUP_GAP := 8       # group title → its card → the next title
const _BODY_SIZE := 13      # the licence text: Regular 13 (Caption R12 a step up; no 13 Regular style exported)
const _PARAGRAPH_GAP := 8
const _EMPTY_TOP := 15      # BLOCKED's `No one blocked` under the header: 68 from its middle (BP3)
const NO_ONE_BLOCKED := "No one blocked"
const READ_FAILED := "Check your connection and try again."
## settings(blocked): no Privacy group, or the row with no number (the list not read this launch)
const BLOCKED_NONE := -1
const BLOCKED_UNREAD := -2
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

## SETTINGS (P0): Home, an untitled `Notifications ›` group, an untitled `Test options ›` group, then the unchanged
## Legal group (Licenses and Version) (341 d559585e, corrected by 0d94c10d: Home → Notifications → Test options → Legal). `home` {name, line, open}: while the change is open, `Home city · Tokyo` ›
## with `Change once · 5 days left` under it, opening the change ("home"); once it is not, the same row read-only with
## `Set for good`. No home (a view not in yet): no Home group. `notifications` "On" / "Off": one row, `Notifications`
## with that value › (SGODOT-350, 不知火舞 7bffafd7); "" (no phone side): no Notifications group. `blocked` ≥ 0: the
## `Privacy` group before Legal, one row `Blocked players` with how many ›, 0 too (BP1, SGODOT-384); BLOCKED_UNREAD the
## row with › alone (not read this launch); BLOCKED_NONE no such row. `voice_chat`: under it in the same card
## `Voice chat ›`, no value (q(277); only while this phone is offered voice, 不知火舞). Neither: no Privacy group.
## `language` (0.2.22 中文版): the row's value, the language in use in its own words (`English` / `中文`); "" for none.
## q(281) (SGODOT-390, 不知火舞's spec 302 e92f4ff9 + 18f24a30, row 131): `privacy_url` "" or the policy's address —
## Legal's first row `Privacy Policy ›` ("privacy") — after `Terms of Service ›` ("terms") when `terms_url` is given
## (SGODOT-491, frame 720:201692, the same look); `support_code` "" or `XXXXX-XXXXX` — Legal's last row after Version,
## `Support code` / `Tap to copy` with the code on the right and no ›, the whole row copying it ("support_code"), and
## under the card `Send this code with any request about your data.`
## SGODOT-491 (不知火舞's account spec v2 §5; 720:201692): `account` — how this farm signs in, "apple" / "google" / "email"
## / "code" ("" before accounts: none of this) — puts an `Account` group first, one info row `Signed in with …` (no ›,
## no sub-page), and at the end, 24 under Legal, the outlined `Sign out` (48, the page's width; "sign_out") and 12
## under it the Danger row `Delete account ›` / `Deletes your farm, items and progress` in its own card
## ("delete_account").
## The dynamic farm (C-128) shows only what applies to it there: `show_tests` false leaves out `Test options ›` (P0's test
## accounts), and a `version` of "" leaves out the Version row (its package's version could not be read).
const ACCOUNT_ROW := {"apple": "Signed in with Apple", "google": "Signed in with Google", "email": "Signed in with email",
	"code": "Signed in with a test code"}
const _END_GAP := 8     # Legal → Sign out: 24 with the column's two 8s
const _END_SEP := 12    # Sign out → Delete account
static func settings(version: String, safe_top := 0.0, safe_bottom := 0.0, home := {}, notifications := "",
		blocked := BLOCKED_NONE, voice_chat := false, language := "", privacy_url := "", support_code := "",
		account := "", terms_url := "", show_tests := true) -> P0SettingsPage:
	var page := P0SettingsPage.new(Kind.SETTINGS, "Settings", safe_top, safe_bottom)
	if ACCOUNT_ROW.has(account):
		var who := UiSettingRow.new(UiSettingRow.Kind.VALUE, str(ACCOUNT_ROW[account]))
		who.name = "SignedInWith"
		page._group("Account", [who])
	if not home.is_empty():
		var title := "Home city · " + str(home.get("name", ""))
		var row := UiSettingRow.new(UiSettingRow.Kind.LINK if bool(home.get("open", false)) else UiSettingRow.Kind.VALUE, title,
			str(home.get("line", "")))
		row.name = "HomeCity"
		row.pressed.connect(func(): page.open_pressed.emit("home"))
		page._group("", [row])   # no group title: bare `Home` reads as the homestead now (SGODOT-461, 不知火舞: its own group)
	if notifications != "":
		var notif := UiSettingRow.new(UiSettingRow.Kind.LINK, "Notifications", "", notifications)
		notif.name = "Notifications"
		notif.pressed.connect(func(): page.open_pressed.emit("notifications"))
		page._group("", [notif])
	if language != "":   # General · Language › between Home and Legal (不知火舞 on the 中文版, 11-02)
		var lang := UiSettingRow.new(UiSettingRow.Kind.LINK, "Language", "", language)
		lang.name = "Language"
		lang.pressed.connect(func(): page.open_pressed.emit("language"))
		page._group("General", [lang])
	if show_tests and not P0Build.store():   # SGODOT-483: no test accounts in the store build (App Review 2.2 / 2.3.1)
		var tests := UiSettingRow.new(UiSettingRow.Kind.LINK, "Test options")
		tests.name = "TestOptions"
		tests.pressed.connect(func(): page.open_pressed.emit("test_options"))
		page._group("", [tests])
	var privacy: Array = []
	if blocked != BLOCKED_NONE:
		var row := UiSettingRow.new(UiSettingRow.Kind.LINK, "Blocked players", "", str(blocked) if blocked >= 0 else "")
		row.name = "BlockedPlayers"
		row.pressed.connect(func(): page.open_pressed.emit("blocked_players"))
		privacy.append(row)
	if voice_chat:
		var row := UiSettingRow.new(UiSettingRow.Kind.LINK, "Voice chat")
		row.name = "VoiceChat"
		row.pressed.connect(func(): page.open_pressed.emit("voice_chat"))
		privacy.append(row)
	if not privacy.is_empty(): page._group("Privacy", privacy)
	var legal: Array = []
	if terms_url != "":
		var terms := UiSettingRow.new(UiSettingRow.Kind.LINK, "Terms of Service")
		terms.name = "TermsOfService"
		terms.pressed.connect(func(): page.open_pressed.emit("terms"))
		legal.append(terms)
	if privacy_url != "":
		var policy := UiSettingRow.new(UiSettingRow.Kind.LINK, "Privacy Policy")
		policy.name = "PrivacyPolicy"
		policy.pressed.connect(func(): page.open_pressed.emit("privacy"))
		legal.append(policy)
	var licenses := UiSettingRow.new(UiSettingRow.Kind.LINK, "Licenses")
	licenses.name = "Licenses"
	licenses.pressed.connect(func(): page.open_pressed.emit("licenses"))
	legal.append(licenses)
	if version != "":
		var ver := UiSettingRow.new(UiSettingRow.Kind.VALUE, "Version", "", version)
		ver.name = "Version"
		legal.append(ver)
	if support_code != "":
		var code := UiSettingRow.new(UiSettingRow.Kind.LINK, "Support code", "Tap to copy", support_code, "", false)
		code.name = "SupportCode"
		(code.find_child("Value", true, false) as Node).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # a code, no words
		code.pressed.connect(func(): page.open_pressed.emit("support_code"))
		legal.append(code)
	page._group("Legal", legal)
	if support_code != "":
		var note := UiKit.label("Send this code with any request about your data.", UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_SECONDARY)
		note.name = "SupportNote"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page.body.add_child(note)
	if ACCOUNT_ROW.has(account):
		var gap := Control.new()
		gap.custom_minimum_size.y = _END_GAP
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.body.add_child(gap)
		var end := VBoxContainer.new()
		end.name = "End"
		end.add_theme_constant_override(&"separation", _END_SEP)
		page.body.add_child(end)
		var out := UiCommandButton.new("Sign out", UiCommandButton.Kind.SECONDARY)
		out.name = "SignOut"
		out.sends = false
		out.activated.connect(func(): page.open_pressed.emit("sign_out"))
		end.add_child(out)
		page.add_delete_account(end)
	return page

## The Danger row `Delete account ›` / `Deletes your farm, items and progress` in its own card ("delete_account"):
## in `end` (P0: 12 under Sign out), or with no `end` at the page's foot, 24 under Legal — the dynamic farm's Settings,
## whose Sign out stays on the map's account chip (C-243).
func add_delete_account(end: Container = null) -> UiSettingRow:
	if end == null:
		var gap := Control.new()
		gap.custom_minimum_size.y = _END_GAP
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(gap)
	var del := UiSettingRow.new(UiSettingRow.Kind.LINK, "Delete account", "Deletes your farm, items and progress")
	del.name = "DeleteAccount"
	del.set_danger()
	del.pressed.connect(func(): open_pressed.emit("delete_account"))
	var card := UiSettingRow.group([del])
	if end != null: end.add_child(card)
	else: body.add_child(card)
	return del

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

## NOTIFICATIONS: see the head. `refused_for` is the app's name when the system has said no, else "".
static func notifications(on: bool, refused_for: String, safe_top := 0.0, safe_bottom := 0.0) -> P0SettingsPage:
	var page := P0SettingsPage.new(Kind.NOTIFICATIONS, "Notifications", safe_top, safe_bottom)
	if refused_for != "":
		var notice := ToastLayer.card(ToastLayer.Severity.INFO, "Notifications are off for %s" % refused_for, "Open system settings")
		notice.name = "SystemOff"
		var link := notice.find_child("Action", true, false) as Label
		link.mouse_filter = Control.MOUSE_FILTER_STOP
		link.gui_input.connect(func(e: InputEvent): if P0Ui.is_tap(e): page.open_pressed.emit("system_settings"))
		page.body.add_child(notice)
	var crops := UiSettingRow.new(UiSettingRow.Kind.TOGGLE, "Crops ready", "When a plot is ready to harvest")
	crops.name = "CropsReady"
	crops.on = on
	crops.toggled.connect(func(value: bool): page.toggled.emit("crops_ready", value))
	page._group("", [crops])
	return page

## BLOCKED: `rows` [{handle, name}] in the server's order; `read` "ok" (as last read), "reading" (not yet: nothing
## shown, never `No one blocked`) or "failed" (never read this launch: the empty state and Retry).
static func blocked_players(rows: Array, safe_top := 0.0, safe_bottom := 0.0, read := "ok") -> P0SettingsPage:
	var page := P0SettingsPage.new(Kind.BLOCKED, "Blocked players", safe_top, safe_bottom)
	var list: Array = []
	for r in rows:
		var handle := str(r.get("handle", ""))
		var row := UiSettingRow.new(UiSettingRow.Kind.VALUE, str(r.get("name", "")))
		row.name = "Blocked_" + handle
		var who := row.find_child("Title", true, false) as Label   # their name now (SGODOT-491): untranslated, one line, `…`
		who.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		who.autowrap_mode = TextServer.AUTOWRAP_OFF
		who.clip_text = true
		who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var none := row.find_child("Value", true, false)   # VALUE's value slot, empty here: the key takes its place
		none.get_parent().remove_child(none)
		none.free()
		var key := UiNavButton.new("Unblock", true)
		key.name = "Unblock"
		key.chevron = false
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		key.pressed.connect(func(): page._unblocked(row, handle))
		row.find_child("Row", true, false).add_child(key)
		list.append(row)
	if not list.is_empty(): page._group("", list)
	elif read == "ok": page._no_one()
	elif read == "failed": page._read_failed()
	return page

## BLOCKED: the row goes at once, the card closing up; the last one leaves `No one blocked`.
func _unblocked(row: Control, handle: String) -> void:
	var card := row.get_parent()
	row.get_parent().remove_child(row)
	row.queue_free()
	if card.get_child_count() == 0:
		for c in body.get_children(): c.queue_free()
		_no_one()
	open_pressed.emit(handle)

func _read_failed() -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = _EMPTY_TOP
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(gap)
	var box := VBoxContainer.new()
	box.name = "Error"
	box.add_theme_constant_override(&"separation", 4)
	box.add_child(UiEmptyState.new(READ_FAILED, preload("res://assets/ui/kit_icons/wifi_off.svg")))
	var retry := UiCommandButton.new("Retry", UiCommandButton.Kind.SECONDARY, true)
	retry.name = "Retry"
	retry.fit_text = true
	retry.min_width = 68   # Compact/Command: hugs its label, at least 68
	retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	retry.activated.connect(func(): open_pressed.emit("retry"))
	box.add_child(retry)
	body.add_child(box)

func _no_one() -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = _EMPTY_TOP
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(gap)
	var none := UiKit.label(NO_ONE_BLOCKED, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	none.name = "NoOneBlocked"
	none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(none)

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

## Settings › Delete account (SGODOT-491; 不知火舞's account spec v1.1 §2.6: the design's SET-DELETE-1 / -3 without -2's
## sign-in again; ACC-DELETE-1 641:197426 / -2 641:197438, Homestead read Home as q(318)). The header ‹ `Delete account`;
## 12 under it the title (XB20), 8 the body (Bold 14, secondary), 24 the danger key, 8 the info NavigationRow `Keep my
## account ›`. Step 1: `Delete your account?` / `Your farm, items, coins and progress will be deleted. This can't be
## undone.` and, 8 under it, `Gensen will also lose access to your Apple ID.` for an Apple-bound farm / `Continue`
## ("continue"). Step 2: `Delete your account for good?` / what this farm has (delete_summary) / `Delete my account`
## ("delete"). Keep my account is "keep" (the header's ‹ too: back_pressed). Deleting, the key greys in its pending
## look (set_deleting; the kit's CommandButton in flight, no spinner) till the host answers.
const DELETE_TITLE := {1: "Delete your account?", 2: "Delete your account for good?"}
const DELETE_BODY := "Your farm, items, coins and progress will be deleted. This can't be undone."
const DELETE_APPLE := "Gensen will also lose access to your Apple ID."
const DELETE_KEY := {1: "Continue", 2: "Delete my account"}
const KEEP_ACCOUNT := "Keep my account"
const _DELETE_KEY_GAP := 8   # body → key: 24 with the column's two 8s
static func delete_account(step: int, apple := false, view := {}, safe_top := 0.0, safe_bottom := 0.0) -> P0SettingsPage:
	var page := P0SettingsPage.new(Kind.DELETE, "Delete account", safe_top, safe_bottom)
	var title := UiKit.label(str(DELETE_TITLE[step]), UiTokens.STYLE_TITLE_XB20, UiTokens.COLOR_TEXT)
	title.name = "Title"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.body.add_child(title)
	var lines: Array = [DELETE_BODY] + ([DELETE_APPLE] if apple else []) if step == 1 else [delete_summary(view)]
	for i in lines.size():
		var l := UiKit.label(str(lines[i]), UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY)
		l.name = "Line" if i == 0 else "Line%d" % (i + 1)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page.body.add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size.y = _DELETE_KEY_GAP
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.body.add_child(gap)
	var go := UiCommandButton.new(str(DELETE_KEY[step]), UiCommandButton.Kind.DESTRUCTIVE)
	go.name = "Go"
	go.activated.connect(func():
		if go.phase == CommandLifecycle.State.IDLE: page.open_pressed.emit("continue" if step == 1 else "delete"))
	page.body.add_child(go)
	var keep := UiNavButton.new(KEEP_ACCOUNT)
	keep.name = "Keep"
	keep.pressed.connect(func(): page.open_pressed.emit("keep"))
	page.body.add_child(keep)
	return page

## ACC-DELETE-2's line, what this farm really has (the design's sentence; 0s left out, 1 in the singular): `Your Home
## Lv6, 230 coins and 19 bag items will be gone.`; a farm with nothing else `Your Home Lv1 will be gone.` — the table's
## three templates (李白), each %s a part it translates again (`%d coins`, `1 coin`, `%d bag items`, `1 bag item`).
static func delete_summary(view: Dictionary) -> String:
	var level := int(view.get("homestead", {}).get("level", 1))
	var coins := int(view.get("coins", 0))
	var items := 0
	for slot in view.get("bag", {}).get("slots", []): items += int(slot.get("qty", 0))
	var parts: Array = []
	if coins > 0: parts.append("1 coin" if coins == 1 else "%d coins" % coins)
	if items > 0: parts.append("1 bag item" if items == 1 else "%d bag items" % items)
	match parts.size():
		2: return "Your Home Lv%d, %s and %s will be gone." % [level, parts[0], parts[1]]
		1: return "Your Home Lv%d and %s will be gone." % [level, parts[0]]
	return "Your Home Lv%d will be gone." % level

## Step 2 while the delete is in flight: the key in its pending look, deaf; false gives it back (a failure's toast is the
## host's).
func set_deleting(on: bool) -> void:
	var go := body.find_child("Go", false, false) as UiCommandButton
	if go: go.phase = CommandLifecycle.State.PENDING if on else CommandLifecycle.State.IDLE

## Settings › Language (0.2.21 中文版): `English` and `中文`, each in its own words (never translated), a ✓ on the one
## picked; a pick is kept for the next start — the line under says so (the user's pick: a restart applies it).
## `current` the language picked (P0_SUPPORTED's), `running` the one this start shows.
static func language(current: String, running: String, safe_top := 0.0, safe_bottom := 0.0) -> P0SettingsPage:
	var page := P0SettingsPage.new(Kind.LANGUAGE, "Language", safe_top, safe_bottom)
	var rows: Array = []
	for pair in [["en", "English"], ["zh_CN", "简体中文"]]:
		var row := UiSettingRow.new(UiSettingRow.Kind.LINK, str(pair[1]), "", "✓" if current == pair[0] else "")
		row.name = "Language_" + str(pair[0])
		row.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # a language's own name, in its own words
		var locale := str(pair[0])
		row.pressed.connect(func(): page.open_pressed.emit("language:" + locale))
		rows.append(row)
	page._group("", rows)
	if current != running:
		var note := UiKit.label("Restart the app to use the new language", UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_SECONDARY)
		note.name = "RestartNote"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page.body.add_child(note)
	return page
