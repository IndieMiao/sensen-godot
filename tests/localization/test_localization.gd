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
	assert_str(NextStep.doing_label("water")).is_equal("正在浇水…")
	assert_str(FarmHud.format_countdown(3_660_000)).is_equal("1 小时 01 分")
	assert_str(FarmHud.format_countdown(0)).is_equal("已就绪")
	assert_str(JourneyProgress.material_label({"wood": 2, "stone": 3, "fiber": 1})).is_equal("2 木料 + 3 石料 + 1 芦苇")
	assert_str(L10n.text("nursery_keeper")).is_equal("nursery_keeper")
	assert_str(L10n.text("unknown-player-name")).is_equal("unknown-player-name")
	TranslationServer.set_locale("en")
	assert_str(CropInfo.name_of("C")).is_equal("Carrot")
	assert_str(L10n.count_text("%d seed", "%d seeds", 1)).is_equal("1 seed")
	assert_str(L10n.count_text("%d seed", "%d seeds", 2)).is_equal("2 seeds")

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

func test_mined_materials_and_their_recipes_have_localized_names() -> void:
	assert_str(JourneyProgress.material_label({"copper_ore": 3, "rock_salt": 1})).is_equal("3 铜矿石 + 1 岩盐")
	assert_str(L10n.dish_name("vegetable_soup")).is_equal("岩盐蔬菜汤")
	assert_str(L10n.text(str(JourneyProgress.data().workshop.recipes.crate.name))).is_equal("铜箍木箱")
	TranslationServer.set_locale("en")
	assert_str(L10n.material_name("copper_ore")).is_equal("Copper ore")
	assert_str(L10n.dish_name("vegetable_soup")).is_equal("Rock-salt vegetable soup")

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

## P0 中文版 (0.2.21): P0's own table — a line exactly, else as a %d / %s template with each %s caught translated again
## (an item's name), else line by line and by its ` · ` parts; `{1}` / `{2}` reorder; nothing known keeps the English.
const LocalizationScript := preload("res://modules/ui/localization.gd")

func _p0_table() -> Translation:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.locale = "zh_CN"
	t.set_table({"_note": "x", "Settings": "设置", "Upgrade": "升级", "Stone": "石料", "Copper Ore": "铜矿石",
		"Need %d more %s": "还差 %d 个%s", "Plots %d/%d": "田 %d/%d", "%s · %d coins": "%s · %d 金币",
		"%s Lv%d needed · now %d": "需要%s Lv%d · 现在 %d", "Visit %s with %s": "和{2}一起去{1}", "Fishing": "钓鱼"})
	return t

func test_p0_table_translates_lines_templates_parts_and_leaves_the_rest() -> void:
	var t := _p0_table()
	assert_str(String(t.get_message("Settings"))).is_equal("设置")
	assert_str(String(t.get_message("Need 2 more Stone"))).is_equal("还差 2 个石料")
	assert_str(String(t.get_message("Need 1,200 more Copper Ore"))).is_equal("还差 1,200 个铜矿石")
	assert_str(String(t.get_message("Plots 8/8"))).is_equal("田 8/8")
	assert_str(String(t.get_message("Fishing Lv3 needed · now 2"))).is_equal("需要钓鱼 Lv3 · 现在 2")
	assert_str(String(t.get_message("Visit Fern Pond with Mei"))).is_equal("和Mei一起去Fern Pond")   # {1} {2}: reordered
	assert_str(String(t.get_message("Upgrade · Stone"))).is_equal("升级 · 石料")   # by its ` · ` parts
	assert_str(String(t.get_message("Upgrade\nNeed 3 more Stone"))).is_equal("升级\n还差 3 个石料")   # line by line
	assert_str(String(t.get_message("Fern Pond"))).is_equal("")   # a name it does not hold: the English stays
	assert_str(String(t.get_message("270/270"))).is_equal("")   # no letters: nothing to translate
	assert_str(String(t.get_message("_note"))).is_equal("")   # notes are no lines

## B 档 shots (SGODOT-385, 11-03): a link's ` ›` and a list of known items are read around; a list with one unknown
## item stays English whole (a sentence with a comma is no list).
func test_p0_table_reads_a_links_arrow_and_a_list_of_known_items() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.locale = "zh_CN"
	t.set_table({"Edit look": "修改形象", "Carrot": "胡萝卜", "Herb": "香草", "Decorate": "布置"})
	assert_str(String(t.get_message("Edit look ›"))).is_equal("修改形象 ›")
	assert_str(String(t.get_message("Carrot, Herb"))).is_equal("胡萝卜、香草")
	assert_str(String(t.get_message("Carrot, Herb · Decorate ›"))).is_equal("胡萝卜、香草 · 布置 ›")
	assert_str(String(t.get_message("Carrot, Kale"))).is_equal("")   # Kale unknown: the whole list stays
	assert_str(String(t.get_message("Unknown ›"))).is_equal("")

func test_p0_language_is_english_until_picked_and_applies_from_the_next_start() -> void:
	var path := "user://p0-language-test-%d.cfg" % Time.get_ticks_usec()
	var loc: Node = LocalizationScript.new()
	TranslationServer.set_locale("zh_CN")   # a new instance's _init sets Journey's own pick
	assert_str(loc.p0_language(path)).is_equal("en")
	assert_int(loc.select_p0_language("fr", path)).is_equal(ERR_INVALID_PARAMETER)
	assert_int(loc.select_p0_language("zh_CN", path)).is_equal(OK)
	assert_str(TranslationServer.get_locale()).is_equal("zh_CN")   # before_test's; select does not switch now
	assert_str(loc.p0_language(path)).is_equal("zh_CN")
	TranslationServer.set_locale("en")
	loc.use_p0(path)   # the next start: P0's table in, Journey's (this instance's) out, the picked locale
	assert_str(TranslationServer.get_locale()).is_equal("zh_CN")
	assert_object(loc._journey).is_null()
	assert_object(loc.p0_translation).is_not_null()
	TranslationServer.remove_translation(loc.p0_translation)
	loc.free()
	DirAccess.remove_absolute(path)

## 李白's notes on the first draft (q(275)): %% is a percent sign, %+d / %.1f are numbers, a %s may be empty, and a
## plural's ending (`dish%s` → "" / s / es) never reaches the Chinese; a weekday or the like caught by a %s is looked up.
func test_p0_table_reads_percent_signs_signed_and_decimal_numbers_and_drops_plural_endings() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.locale = "zh_CN"
	t.set_table({"Crops ready %d%% sooner": "作物早 %d%% 成熟", "%+d Friendship": "好感 %+d", "%.1f km": "%.1f 公里",
		"%d dish%s in bag": "背包里有 %d 份料理%s", "%d slot%s free": "空 {1} 格", "Your day resets %s 4 AM": "每天%s凌晨 4 点重置",
		"Mon": "周一"})
	assert_str(String(t.get_message("Crops ready 20% sooner"))).is_equal("作物早 20% 成熟")
	assert_str(String(t.get_message("+5 Friendship"))).is_equal("好感 +5")
	assert_str(String(t.get_message("12.5 km"))).is_equal("12.5 公里")
	assert_str(String(t.get_message("1 dish in bag"))).is_equal("背包里有 1 份料理")
	assert_str(String(t.get_message("3 dishes in bag"))).is_equal("背包里有 3 份料理")
	assert_str(String(t.get_message("2 slots free"))).is_equal("空 2 格")   # {1} alone: the ending left out
	assert_str(String(t.get_message("Your day resets Mon 4 AM"))).is_equal("每天周一凌晨 4 点重置")
