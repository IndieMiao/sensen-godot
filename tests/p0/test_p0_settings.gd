extends GdUnitTestSuite
## Settings › Legal › Licenses (q(129); SETTINGS-1-2 / SET-LICENSES, 不知火舞 280 4c8d286a): the P0 Settings page holds
## only rows that work (Licenses, Version); the Licenses page lists the credits as data — Software, then Map data with
## each attribution word for word and its licence 6 under it; a row opens its full text, joined from the hard-wrapped
## file; ‹ goes back one page at a time to the profile, whose gear opens Settings.

const STORE := "user://test_p0_settings.json"
const TIPS := "user://test_p0_settings_tips.json"
const WORLDCOVER := "© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium"

func after_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)

func test_the_credits_are_the_frame_and_q129_word_for_word() -> void:
	var g := P0Legal.groups()
	assert_array(g.map(func(x): return x.title)).is_equal(["Software", "Map data"])
	assert_array(g[0].rows.map(func(r): return [r.title, r.license])).is_equal([["Godot Engine", "MIT License"],
		["Nunito", "SIL Open Font License 1.1"], ["Phosphor Icons", "MIT License"], ["Mapbox Maps SDK", "Mapbox Terms of Service"]])
	assert_array(g[1].rows.map(func(r): return [r.title, r.credit, r.license])).is_equal([
		["Mapbox", "© Mapbox", "Mapbox Terms of Service"],   # q(133) v3: first in Map data, its › to the Map data page
		["OpenStreetMap", "© OpenStreetMap contributors", "ODbL 1.0"],
		["GeoNames", "Contains data from GeoNames (geonames.org)", "CC BY 4.0"],
		["ESA WorldCover", WORLDCOVER, "CC BY 4.0"],
		["DB-IP", "IP Geolocation by DB-IP", "CC BY 4.0"],   # the home pick's Near you (q(188) ①); its site on its text page (q(205) ⑥)
		["Unicode CLDR", "Copyright © 2004-2026 Unicode, Inc.", "Unicode License v3"]])   # the city rows' country names (q(210) ④)
	assert_str(str(P0Legal.row("mapbox_data").get("page", ""))).is_equal("map_data")
	for grp in g:
		for r in grp.rows:   # every other › opens a text that ships with the package
			if r.has("page"): continue
			assert_int(P0Legal.full_text(r).length()).override_failure_message(str(r.id)).is_greater(50)
	assert_str(P0Legal.full_text(P0Legal.row("godot"))).contains("Third-party components")
	assert_str(P0Legal.full_text(P0Legal.row("osm"))).contains("Open Database License")
	assert_str(P0Legal.full_text(P0Legal.row("worldcover"))).contains("Attribution 4.0 International")

func test_paragraphs_join_the_hard_wraps_and_keep_every_word() -> void:
	var src := "## ODC Open Database\n\nThe Open Database License (ODbL) is a license agreement intended to\nallow users to freely share.\n\n=====\n\n  a. Adapted Material means\n     material subject to Copyright."
	assert_array(P0Legal.paragraphs(src)).is_equal(["ODC Open Database",
		"The Open Database License (ODbL) is a license agreement intended to allow users to freely share.",
		"a. Adapted Material means material subject to Copyright."])
	assert_array(P0Legal.paragraphs("## Additional licenses\nMapbox uses portions of it.")).is_equal(
		["Additional licenses", "Mapbox uses portions of it."])   # a heading stands alone, blank line or not
	assert_array(P0Legal.paragraphs("other CC-\nlicensed material, any reason--for\nexample")).is_equal(
		["other CC-licensed material, any reason--for example"])   # a word broken at its hyphen joins whole
	assert_array(P0Legal.paragraphs("met:\n* Redistributions of source code must\n  retain the above notice.\n* Neither the name")).is_equal(
		["met:", "* Redistributions of source code must retain the above notice.", "* Neither the name"])   # BSD's clauses, one each
	# whole files: not a character lost or changed, only the line breaks, the #s and the ===== rules
	var bare := func(t: String) -> String:
		var lines := Array(t.split("\n")).filter(func(l): return l.strip_edges().replace("=", "") != "" and l.strip_edges().replace("-", "") != "")
		return "".join(lines).replace("#", "").replace(" ", "").replace("\t", "").replace("\r", "")   # Phosphor's file has CRLF
	for id in ["geonames", "osm", "nunito", "phosphor"]:
		var whole := P0Legal.full_text(P0Legal.row(id))
		assert_str(bare.call("\n".join(P0Legal.paragraphs(whole)))).override_failure_message(id).is_equal(bare.call(whole))

func test_the_version_row_reads_name_and_code() -> void:
	assert_str(P0Legal.version_line({"version": 2026101001, "name": "0.2.1"})).is_equal("0.2.1 (2026101001)")
	assert_str(P0Legal.version_line({})).is_equal("dev")
	var cfg := P0Session.demo_config('{"url": "https://x.example/v1", "key": "k", "version": 2026101001, "name": "0.2.1"}')
	assert_str(P0Legal.version_line(cfg)).is_equal("0.2.1 (2026101001)")

## With a home and the phone side, the groups run Home → Notifications → Test options → Legal (不知火舞 341 0d94c10d,
## SGODOT-350), Notifications and Test options each an untitled group of one row.
func test_settings_groups_run_home_notifications_test_options_legal() -> void:
	var page: P0SettingsPage = auto_free(P0SettingsPage.settings("0.2.1 (2026101001)", 0.0, 0.0,
		{"name": "Tokyo", "line": "Set for good", "open": false}, "On"))
	add_child(page)
	await await_idle_frame()
	# "": the read-only Home row's empty value (a VALUE row always has one)
	assert_array(_labels(page.body)).is_equal(["Home", "Home city · Tokyo", "Set for good", "", "Notifications", "On", "›",
		"Test options", "›", "Legal", "Licenses", "›", "Version", "0.2.1 (2026101001)"])
	var notif: UiSettingRow = page.body.find_child("Notifications", true, false)
	var tests: UiSettingRow = page.body.find_child("TestOptions", true, false)
	assert_int(notif.get_parent().get_child_count()).is_equal(1)
	assert_object(notif.get_parent()).is_not_same(tests.get_parent())

func test_settings_holds_only_rows_that_work() -> void:
	var page: P0SettingsPage = auto_free(P0SettingsPage.settings("0.2.1 (2026101001)"))
	add_child(page)
	await await_idle_frame()
	assert_str(page.header.title).is_equal("Settings")
	assert_array(_labels(page.body)).is_equal(["Test options", "›", "Legal", "Licenses", "›", "Version", "0.2.1 (2026101001)"])
	var said := []
	page.open_pressed.connect(func(w): said.append(w))
	var licenses := page.body.find_child("Licenses", true, false) as UiSettingRow
	var hit := licenses.find_child("Hit", true, false) as Button
	assert_object(hit.get_global_rect()).is_equal(licenses.get_global_rect())   # the whole row, edge to edge (刘邦 on #292)
	assert_float(hit.size.y).is_greater_equal(52.0)
	hit.pressed.emit()
	assert_array(said).is_equal(["licenses"])
	assert_object(page.body.find_child("Version", true, false).find_child("Hit", true, false)).is_null()   # read-only
	var entry: UiSettingRow = page.body.find_child("TestOptions", true, false)
	var version: UiSettingRow = page.body.find_child("Version", true, false)
	assert_int(entry.kind).is_equal(UiSettingRow.Kind.LINK)
	assert_array(_labels(entry)).is_equal(["Test options", "›"])
	assert_int(entry.get_parent().get_child_count()).is_equal(1)   # its own untitled group
	assert_object(entry.get_parent()).is_not_same(licenses.get_parent())
	assert_object(entry.get_parent()).is_not_same(version.get_parent())
	assert_object(licenses.get_parent()).is_same(version.get_parent())
	assert_float(entry.get_global_rect().end.y).is_less(licenses.get_global_rect().position.y)
	assert_float(version.get_global_rect().position.y).is_greater(licenses.get_global_rect().end.y)
	(entry.find_child("Hit", true, false) as Button).pressed.emit()
	assert_array(said).is_equal(["licenses", "test_options"])
	# The old seven-tap/hold path has no listener or timer; Version remains a plain VALUE row.
	assert_array(version.get_signal_connection_list("gui_input")).is_empty()
	for i in 8:
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			version.gui_input.emit(event)
	page._process(3.0)
	assert_array(said).is_equal(["licenses", "test_options"])

func test_licenses_lists_the_groups_and_a_credit_reads_as_three_parts() -> void:
	var page: P0SettingsPage = auto_free(P0SettingsPage.licenses(P0Legal.groups()))
	add_child(page)
	await await_idle_frame()
	assert_str(page.header.title).is_equal("Licenses")
	var row := page.body.find_child("worldcover", true, false) as UiSettingRow
	assert_str((row.find_child("Title", true, false) as Label).text).is_equal("ESA WorldCover")
	var att := row.find_child("Attribution", true, false) as Label
	assert_str(att.text).is_equal(WORLDCOVER)   # word for word, wrapping, never cut
	assert_int(att.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	assert_int(att.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
	var lic := row.find_child("Line", true, false) as Label
	assert_str(lic.text).is_equal("CC BY 4.0")
	assert_float(lic.get_global_rect().position.y - att.get_global_rect().end.y).is_equal_approx(6.0, 0.5)   # its own line, 6 under
	assert_float(row.size.y).is_greater(52.0)   # the row grows with the attribution
	assert_object((row.find_child("Hit", true, false) as Button).get_global_rect()).is_equal(row.get_global_rect())   # tall rows too
	var said := []
	page.open_pressed.connect(func(w): said.append(w))
	(page.body.find_child("osm", true, false).find_child("Hit", true, false) as Button).pressed.emit()
	assert_array(said).is_equal(["osm"])

func test_a_licence_text_is_regular_13_in_paragraphs() -> void:
	var page: P0SettingsPage = auto_free(P0SettingsPage.text("Nunito", P0Legal.full_text(P0Legal.row("nunito"))))
	add_child(page)
	await await_idle_frame()
	assert_str(page.header.title).is_equal("Nunito")
	var first := page.body.get_child(0) as Label
	assert_int(first.get_theme_font_size(&"font_size")).is_equal(13)
	assert_str(first.get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_SECONDARY.to_html())
	assert_int(page.body.get_theme_constant(&"separation")).is_equal(8)
	assert_int(page.body.get_child_count()).is_greater(10)

## q(205) ⑥: DB-IP's site is the first row of its text page (`db-ip.com ›`, to the browser), not in its Licenses row.
func test_a_credit_with_a_link_puts_it_above_its_text() -> void:
	var r := P0Legal.row("dbip")
	assert_str(str(r.credit)).is_equal("IP Geolocation by DB-IP")
	var page: P0SettingsPage = auto_free(P0SettingsPage.text("DB-IP", P0Legal.full_text(r), 0.0, 0.0, r.link))
	add_child(page)
	await await_idle_frame()
	var row := page.body.find_child("link", true, false) as UiSettingRow
	assert_object(row).is_not_null()
	assert_int(row.get_index()).is_less(page.body.get_child_count() - 1)
	var opened: Array = []
	page.open_pressed.connect(func(what): opened.append(what))
	row.pressed.emit()
	assert_array(opened).is_equal(["link"])
	assert_str(str(r.link.url)).is_equal("https://db-ip.com")
	var plain: P0SettingsPage = auto_free(P0SettingsPage.text("Nunito", P0Legal.full_text(P0Legal.row("nunito"))))
	add_child(plain)
	await await_idle_frame()
	assert_object(plain.body.find_child("link", true, false)).is_null()   # no link: the text alone, as before

## The profile's gear opens Settings; each page's ‹ goes back one page, to the profile in the end.
func test_the_gear_opens_settings_and_back_goes_one_page_at_a_time() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view({"energy": {"value": 150, "max": 200}, "coins": 40, "skills": {}, "bag": {"capacity": 25, "slots": []}})
	ui.open_profile()
	await await_idle_frame()
	var gear := ui._profile.top_bar.right_button()
	assert_float(gear.modulate.a).is_equal(1.0)
	assert_int(gear.mouse_filter).is_not_equal(Control.MOUSE_FILTER_IGNORE)   # tappable (the scroll makes it PASS)
	gear.pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("settings")
	(ui._modal.find_child("Licenses", true, false).find_child("Hit", true, false) as Button).pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("licenses")
	(ui._modal.find_child("worldcover", true, false).find_child("Hit", true, false) as Button).pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("license_text")
	assert_str((ui._modal.find_children("*", "P0SettingsPage", true, false)[0] as P0SettingsPage).header.title).is_equal("ESA WorldCover")
	for kind in ["licenses", "settings", "profile"]:
		(ui._modal.find_children("*", "P0SettingsPage", true, false)[0] as P0SettingsPage).back_pressed.emit()
		await await_idle_frame()
		assert_str(ui.modal_kind).is_equal(kind)
	# q(133) v3: Licenses › Mapbox opens Map data, and its ‹ comes back to Licenses
	ui.open_licenses(func(): ui.open_settings())
	await await_idle_frame()
	(ui._modal.find_child("mapbox_data", true, false).find_child("Hit", true, false) as Button).pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("map_data")
	assert_float(ui.modal_top()).is_equal(0.0)   # a page over the world: the map's credit line is not drawn
	(ui._modal.find_children("*", "P0SettingsPage", true, false)[0] as P0SettingsPage).back_pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("licenses")
	ui.close_modal()
	assert_float(ui.modal_top()).is_equal(INF)

## q(133) v3 (Q133-V3-MAPDATA 2425:129113): `Credits` — © Mapbox ›, © OpenStreetMap contributors › — then an untitled
## group 24 under it: Improve this map › and the switch Share anonymous map usage, its line under it; a tap anywhere on
## the row flips the switch.
func test_map_data_holds_the_credits_feedback_and_the_switch() -> void:
	var page: P0SettingsPage = auto_free(P0SettingsPage.map_data(true))
	add_child(page)
	await await_idle_frame()
	assert_str(page.header.title).is_equal("Map data")
	assert_array(_labels(page.body).filter(func(t): return t in ["Credits", "© Mapbox", "© OpenStreetMap contributors",
		"Improve this map", "Share anonymous map usage", "Helps Mapbox improve its maps"])).is_equal(["Credits", "© Mapbox",
		"© OpenStreetMap contributors", "Improve this map", "Share anonymous map usage", "Helps Mapbox improve its maps"])
	var cards: Array = page.body.get_children().filter(func(c): return c is PanelContainer)
	assert_int(cards.size()).is_equal(2)
	assert_float((cards[1] as Control).position.y - (cards[0] as Control).get_rect().end.y).is_equal_approx(24.0, 0.5)
	var said := []
	page.open_pressed.connect(func(w): said.append(w))
	var switched := []
	page.toggled.connect(func(w, on): switched.append([w, on]))
	for id in ["mapbox_site", "osm_site", "improve"]:
		(page.body.find_child(id, true, false).find_child("Hit", true, false) as Button).pressed.emit()
	assert_array(said).is_equal(["mapbox_site", "osm_site", "improve"])
	var share := page.body.find_child("telemetry", true, false) as UiSettingRow
	assert_bool(share.on).is_true()   # on by default
	assert_vector((share.find_child("Toggle", true, false) as Control).size).is_equal(Vector2(48, 28))
	(share.find_child("Hit", true, false) as Button).pressed.emit()
	assert_bool(share.on).is_false()
	assert_array(switched).is_equal([["telemetry", false]])

## q(133) v3: the switch is the SDK's (Android: the map plugin), with the game's own copy where it cannot ask (here:
## the desktop); Improve this map goes to the map's last view, else to the fallback (the home city's centre).
func test_map_usage_keeps_the_choice_and_builds_the_feedback_address() -> void:
	var was := MapUsage.enabled()
	MapUsage.set_enabled(false)
	assert_bool(MapUsage.enabled()).is_false()
	MapUsage.set_enabled(true)
	assert_bool(MapUsage.enabled()).is_true()
	MapUsage.set_enabled(was)
	var saved := MapUsage.last_view
	MapUsage.last_view = Vector3.ZERO
	assert_str(MapUsage.feedback_url(Vector3(37.7749, -122.4194, 12.0))).is_equal("https://apps.mapbox.com/feedback/#/-122.41940/37.77490/12.00")
	MapUsage.last_view = Vector3(35.6842, 139.7128, 14.0)
	assert_str(MapUsage.feedback_url(Vector3(37.7749, -122.4194, 12.0))).is_equal("https://apps.mapbox.com/feedback/#/139.71280/35.68420/14.00")
	MapUsage.last_view = saved

## 不知火舞 on #292: Settings, Licenses and a text page are pages of one path from the profile: the header's back sits
## exactly on the profile top bar's back (the safe area too), so it never jumps.
func test_the_back_sits_where_the_profile_back_is() -> void:
	var profile: P0ProfilePage = auto_free(P0ProfilePage.new({"skills": {}}, 24.0))
	var page: P0SettingsPage = auto_free(P0SettingsPage.settings("dev", 24.0))
	for n in [profile, page]:
		n.size = Vector2(360, 800)
		add_child(n)
	await await_idle_frame()
	var a := (profile.top_bar.get_child(0) as Control).get_global_rect()
	var b := (page.header.find_child("Back", true, false) as Control).get_global_rect()
	assert_vector(b.position).is_equal_approx(a.position, Vector2.ONE * 0.5)
	assert_vector(b.size).is_equal(a.size)

## 李白 on #292: the Mapbox row's text is the packed SDK version's own LICENSE.md (its copyright, the TOS, the licenses
## it bundles; tools/p0/update_mapbox_license.sh), not a sentence of ours; Godot's lists the engine's components and texts.
func test_mapbox_and_godot_texts_come_from_the_sdk_and_the_engine() -> void:
	# the tracked source of the Android build's Mapbox version (android/ is laid out from it and not in the repo; 刘邦 on #292)
	var gradle := FileAccess.get_file_as_string("res://tools/android/overlay/build.gradle")
	var m := RegEx.create_from_string("com\\.mapbox\\.maps:android:([0-9.]+)").search(gradle)
	assert_object(m).is_not_null()
	var mapbox := P0Legal.full_text(P0Legal.row("mapbox"))
	assert_str(mapbox).contains("Mapbox Maps for Android version %s" % m.get_string(1))   # bump the SDK: run the tool
	assert_str(mapbox).contains("Additional Mapbox Maps Android licenses")
	var first: String = P0Legal.paragraphs(mapbox).filter(func(p): return str(p).begins_with("Copyright"))[0]
	assert_str(first).is_equal("Copyright © 2021 - 2026 Mapbox, Inc. All rights reserved.")   # &copy; reads as ©
	var godot := P0Legal.full_text(P0Legal.row("godot"))
	assert_str(godot).contains("Third-party components")
	assert_str(godot).contains("\n\nLicenses\n\n")
	for name in Engine.get_license_info(): assert_str(godot).contains(str(name))

## A long text (Mapbox's 660 paragraphs) opens with its first screens and fills in the rest a batch a frame: all of it
## ends up on the page, in order.
func test_a_long_text_fills_in_over_frames() -> void:
	var text := P0Legal.full_text(P0Legal.row("mapbox"))
	var all := P0Legal.paragraphs(text)
	var page: P0SettingsPage = auto_free(P0SettingsPage.text("Mapbox Maps SDK", text))
	assert_int(page.body.get_child_count()).is_equal(P0SettingsPage._FIRST_PARAGRAPHS)
	add_child(page)
	for i in 100:
		if page.complete(): break
		await await_idle_frame()
	assert_bool(page.complete()).is_true()
	assert_int(page.body.get_child_count()).is_equal(all.size())
	assert_str((page.body.get_child(all.size() - 1) as Label).text).is_equal(str(all[-1]))

## 0.2.21 中文版 (不知火舞 on it, 11-02): General · Language › between Home / Notifications and Test options, its value the
## language in use in its own words; its page lists English and 中文 untranslated, a ✓ on the pick, and while the pick is
## not the language on screen a line says a restart applies it. The three UiKit weights draw Chinese (Noto Sans SC).
func test_settings_offers_language_between_notifications_and_test_options() -> void:
	var page: P0SettingsPage = auto_free(P0SettingsPage.settings("0.2.21 (2026110301)", 0.0, 0.0, {}, "On", P0SettingsPage.BLOCKED_NONE, false, "English"))
	add_child(page)
	await await_idle_frame()
	assert_array(_labels(page.body)).is_equal(["Notifications", "On", "›", "General", "Language", "English", "›",
		"Test options", "›", "Legal", "Licenses", "›", "Version", "0.2.21 (2026110301)"])
	var said := []
	page.open_pressed.connect(func(w): said.append(w))
	(page.body.find_child("Language", true, false).find_child("Hit", true, false) as Button).pressed.emit()
	assert_array(said).is_equal(["language"])

func test_the_language_page_marks_the_pick_and_says_a_restart_applies_it() -> void:
	var page: P0SettingsPage = auto_free(P0SettingsPage.language("zh_CN", "en"))
	add_child(page)
	await await_idle_frame()
	assert_str(page.header.title).is_equal("Language")
	var en: UiSettingRow = page.body.find_child("Language_en", true, false)
	var zh: UiSettingRow = page.body.find_child("Language_zh_CN", true, false)
	assert_array(_labels(en)).is_equal(["English", "›"])   # no value on the one not picked
	assert_array(_labels(zh)).is_equal(["简体中文", "✓", "›"])
	assert_int(zh.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	assert_object(page.body.find_child("RestartNote", true, false)).is_not_null()
	var said := []
	page.open_pressed.connect(func(w): said.append(w))
	(en.find_child("Hit", true, false) as Button).pressed.emit()
	assert_array(said).is_equal(["language:en"])
	var same: P0SettingsPage = auto_free(P0SettingsPage.language("en", "en"))   # the pick is on screen: no line
	add_child(same)
	await await_idle_frame()
	assert_object(same.body.find_child("RestartNote", true, false)).is_null()

func test_the_ui_weights_draw_chinese_through_noto_sans_sc_only_under_chinese() -> void:
	var paths := [UiTokens.FONT_REGULAR_PATH, UiTokens.FONT_BOLD_PATH, UiTokens.FONT_EXTRABOLD_PATH]
	var heights := paths.map(func(p): return (load(p) as Font).get_height(14))
	for path in paths: assert_int((load(path) as FontVariation).fallbacks.size()).is_equal(0)   # English: as measured
	Localization.set_cjk_fonts(true)
	# held by the autoload: when nothing else holds a weight yet (P0's start, before the theme), it must not leave the
	# cache and come back from the next load() without its fallback (B 档 shots: 远 and 鉴 boxes, no bold, 11-03)
	assert_int(Localization._cjk_held.size()).is_equal(3)
	for path in paths:
		var font := load(path) as FontVariation
		assert_int(font.fallbacks.size()).override_failure_message(path).is_equal(1)
		assert_bool(font.has_char(0x4E2D)).override_failure_message(path).is_true()   # 中
		assert_float(font.get_string_size("中文", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x).is_greater(20.0)
	Localization.set_cjk_fonts(false)
	assert_int(Localization._cjk_held.size()).is_equal(0)
	for i in paths.size(): assert_float((load(paths[i]) as Font).get_height(14)).is_equal(heights[i])
