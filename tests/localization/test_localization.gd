extends GdUnitTestSuite

var _locale: String
var _settings: String

func before_test() -> void:
	_locale = TranslationServer.get_locale()
	_settings = "user://language-test-%d.cfg" % Time.get_ticks_usec()
	TranslationServer.set_locale("zh_CN")

func after_test() -> void:
	TranslationServer.set_locale(_locale)
	if FileAccess.file_exists(_settings): DirAccess.remove_absolute(_settings)

func test_new_install_defaults_to_chinese_and_preference_survives_reload() -> void:
	assert_str(Localization.load_preference(_settings)).is_equal("zh_CN")
	assert_int(Localization.select_language("en", _settings)).is_equal(OK)
	assert_str(TranslationServer.get_locale()).is_equal("en")
	assert_str(Localization.load_preference(_settings)).is_equal("en")
	assert_int(Localization.select_language("zh_CN", _settings)).is_equal(OK)
	assert_str(Localization.load_preference(_settings)).is_equal("zh_CN")
	assert_int(Localization.select_language("invalid", _settings)).is_equal(ERR_INVALID_PARAMETER)
	assert_str(Localization.load_preference(_settings)).is_equal("zh_CN")

func test_failed_preference_save_does_not_switch_language() -> void:
	assert_int(Localization.select_language("en", "user://missing-language-dir/settings.cfg")).is_not_equal(OK)
	assert_str(TranslationServer.get_locale()).is_equal("zh_CN")

func test_dynamic_quantities_and_ingredients_use_chinese_without_changing_ids() -> void:
	assert_str(CropInfo.name_of("C")).is_equal("胡萝卜")
	assert_str(L10n.format_text("Bought %d %s seeds", [3, CropInfo.name_of("C")])).is_equal("已购买 3 颗胡萝卜种子")
	assert_str(L10n.format_text("Prepare %s", "tea")).is_equal("制作茶")
	for count in [0, 1, 2, 12]:
		assert_str(L10n.count_text("%d seed", "%d seeds", count)).is_equal("%d 颗种子" % count)
	assert_str(NextStep.doing_label("care", "R", "sunny")).is_equal("正在浇水…")
	assert_str(NextStep.doing_label("care", "R", "rain")).is_equal("正在排水…")
	assert_str(NextStep.doing_label("care", "R", "wind")).is_equal("正在加固…")
	assert_str(FarmHud.format_countdown(3_660_000)).is_equal("1 小时 01 分")
	assert_str(FarmHud.format_countdown(0)).is_equal("已就绪")
	assert_str(JourneyProgress.material_label({"wood": 2, "stone": 3, "fiber": 1})).is_equal("2 木料 + 3 石料 + 1 芦苇")
	assert_str(L10n.text("nursery_keeper")).is_equal("nursery_keeper")
	assert_str(L10n.text("unknown-player-name")).is_equal("unknown-player-name")
	TranslationServer.set_locale("en")
	assert_str(CropInfo.name_of("C")).is_equal("Carrot")
	assert_str(L10n.count_text("%d seed", "%d seeds", 1)).is_equal("1 seed")
	assert_str(L10n.count_text("%d seed", "%d seeds", 2)).is_equal("2 seeds")
	assert_str(NextStep.doing_label("care", "R", "rain")).is_equal("Draining…")

func test_catalog_preserves_format_specifiers_and_bundled_font_has_all_glyphs() -> void:
	var messages: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/localization/zh_CN.json"))
	var format := RegEx.create_from_string("%[-+0-9.]*[sdif]")
	var font := load("res://assets/ui/fonts/NotoSansSC-Regular.otf") as Font
	var missing := {}
	for source: String in messages:
		var translated := str(messages[source])
		assert_array(format.search_all(source).map(func(m): return m.get_string())).override_failure_message(source).is_equal(format.search_all(translated).map(func(m): return m.get_string()))
		for ch in translated:
			if ch.unicode_at(0) >= 0x2E80 and not font.has_char(ch.unicode_at(0)): missing[ch] = true
	assert_dict(missing).is_empty()
	var fallback := GameUi.theme().default_font.fallbacks
	assert_bool(fallback.any(func(f): return f.has_char("中".unicode_at(0)))).is_true()

func test_shared_content_stays_in_source_language_and_state_is_unchanged() -> void:
	var state := {"journey": {"version": 1, "facts": [], "unlocks": [], "wood": 0, "exploration": {"collected": [], "round": 0}}, "cells": {}, "inventory": {"seeds": {}, "produce": {}}, "wallet": 0}
	var original := JSON.stringify(state)
	var chinese := JourneyProgress.next_goal(state)
	assert_str(JourneyProgress.goal_label(chinese)).contains("看护人")
	assert_str(str(chinese.place)).is_equal("nursery")
	TranslationServer.set_locale("en")
	var english := JourneyProgress.next_goal(state)
	assert_str(str(english.place)).is_equal(str(chinese.place))
	assert_str(str(english.get("target", ""))).is_equal(str(chinese.get("target", "")))
	assert_str(JSON.stringify(state)).is_equal(original)
	assert_str(str(JourneyProgress.data().projects.seedbeds.name)).is_equal("Propagation beds")
	assert_str(str(ResidentCast.definition("nursery_keeper").name)).is_equal("Nursery keeper")

func test_city_switcher_is_visible_and_updates_in_both_directions() -> void:
	var city: Control = auto_free((load("res://scenes/city_select/city_select.tscn") as PackedScene).instantiate())
	add_child(city)
	await get_tree().process_frame
	var language := city.find_child("LanguageButton", true, false) as LanguageButton
	assert_object(language).is_not_null()
	assert_object(language.icon).is_not_null()
	assert_int(language.get_popup().item_count).is_equal(2)
	var title := city.get_node("SafeArea/VBox/Title") as Label
	assert_str(title.tr(title.text)).is_equal("选择城市")
	assert_str(city.region_buttons()[0].tr(city.region_buttons()[0].text)).is_equal("上海")
	assert_int(Localization.select_language("en", _settings)).is_equal(OK)
	assert_str(title.tr(title.text)).is_equal("Choose a city")
	assert_str(city.region_buttons()[0].tr(city.region_buttons()[0].text)).is_equal("Shanghai")
	assert_int(Localization.select_language("zh_CN", _settings)).is_equal(OK)
	assert_str(title.tr(title.text)).is_equal("选择城市")

func test_nearby_switch_preserves_selection_preview_and_scroll() -> void:
	var panel: NearbyPanel = auto_free(NearbyPanel.new())
	add_child(panel)
	panel.set_entries([{"farm_id": "a", "avatar_ref": "seed:abcd1234", "nursery_stage": "derelict"}], 3)
	panel.focus("a")
	var snapshot := {"farm_id": "a", "layout_patch_id": "sh_a", "blueprint_revision": 2, "cells": [{"state": "growing", "ripe": false}]}
	panel.set_preview(snapshot)
	assert_str(panel._preview_text.text).is_equal("生长中 1 · 已成熟 0")
	TranslationServer.set_locale("en")
	panel.refresh_language()
	assert_str(panel._title.text).is_equal("Nearby Farmers · 3")
	assert_str(panel._preview_text.text).is_equal("1 growing · 0 ripe")
	assert_str(panel.focused_id).is_equal("a")
	assert_bool(panel.visit_button.disabled).is_false()
	panel.clear_focus()
	assert_vector(panel._preview_counts).is_equal(Vector2i(-1, -1))

func test_marker_names_and_tooltips_follow_locale_without_replacing_nodes() -> void:
	var markers: FarmMarkers = auto_free(FarmMarkers.new())
	add_child(markers)
	var bp := FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_a", 2))
	markers.put("a", bp, SeededOutfit.short_name("seed:1234"), false, "seed:1234")
	markers.selected_id = "a"
	var button: Button = markers._buttons.a
	assert_str(markers._owner_labels.a.text).is_equal("农场主 1234")
	TranslationServer.set_locale("en")
	markers.refresh_language()
	assert_object(markers._buttons.a).is_same(button)
	assert_str(markers.selected_id).is_equal("a")
	assert_str(markers._owner_labels.a.text).is_equal("Farmer 1234")
	assert_str(button.tooltip_text).is_equal("Select Farmer 1234")
	TranslationServer.set_locale("zh_CN")
	markers.refresh_language()
	assert_str(markers._owner_labels.a.text).is_equal("农场主 1234")
