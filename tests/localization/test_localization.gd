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
	assert_str(String(t.get_message("· Decorate"))).is_equal("· 布置")   # a caption's half on its own label


## B 档 shots (SGODOT-385, 11-03): spaces around a line and a `n/m` count after a title are read around; a bare
## number after a name is not (it may be part of the name).
func test_p0_table_reads_spaces_around_a_line_and_a_count_after_a_title() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.locale = "zh_CN"
	t.set_table({"Muscle Memory": "肌肉记忆", "Home Cook": "家常厨师", "Decorate": "布置", "Floor": "层"})
	assert_str(String(t.get_message("Muscle Memory "))).is_equal("肌肉记忆 ")
	assert_str(String(t.get_message("  Decorate\n"))).is_equal("  布置\n")
	assert_str(String(t.get_message("Home Cook 0/8"))).is_equal("家常厨师 0/8")
	assert_str(String(t.get_message("Home Cook 1,200/1,500 · Decorate"))).is_equal("家常厨师 1,200/1,500 · 布置")
	assert_str(String(t.get_message("Floor 10"))).is_equal("")   # a bare number: the English stays
	assert_str(String(t.get_message("Unknown 0/8"))).is_equal("")
	assert_str(String(t.get_message("   "))).is_equal("")

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

## #649 第二批 ①: one English word, two Chinese ones — `Cooking@skill` 烹饪 for the skill, the stove's plain `Cooking`
## 烹饪中; a word with no such key (and English, always) comes back as it is.
func test_p0_ctx_reads_a_words_context_key_under_chinese_only() -> void:
	var kept = Localization.p0_translation
	var t: Translation = LocalizationScript.P0Translation.new()
	t.set_table({"Cooking": "烹饪中", "Cooking@skill": "烹饪", "Water": "浇水", "Water@family": "水"})
	Localization.p0_translation = t
	assert_str(Localization.ctx("Cooking", "skill")).is_equal("烹饪")
	assert_str(Localization.ctx("Water", "family")).is_equal("水")
	assert_str(Localization.ctx("Farming", "skill")).is_equal("Farming")   # no key: the label's plain one reads it
	assert_str(String(t.get_message("Cooking"))).is_equal("烹饪中")   # the stove's is unchanged
	assert_str(String(t.get_message(Localization.ctx("Cooking", "skill")))).is_equal("")   # drawn again: stays 烹饪
	TranslationServer.set_locale("en")
	assert_str(Localization.ctx("Cooking", "skill")).is_equal("Cooking")
	Localization.p0_translation = kept

## #649 第二批 ④: the cities named in Chinese are the open home cities and each one's fallback ten (extract.py's
## p0_cities_en.json, from the server's homeCities / fallbackOf), their Chinese in the main table; any other city keeps
## its English.
func test_p0_city_list_is_the_home_cities_and_their_fallback_ten() -> void:
	var cities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/p0/i18n/p0_cities_en.json"))
	var homes := {}
	for name in cities:
		for h in cities[name].homes: homes[h] = true
	assert_int(homes.size()).is_equal(13)
	for name in ["San Francisco", "Tokyo", "Shanghai", "London", "Oxford", "Yokohama", "Paris"]:
		assert_bool(cities.has(name)).override_failure_message(name).is_equal(name not in ["Yokohama", "Paris"])
	var t: Translation = LocalizationScript.P0Translation.new()
	t.set_table({"Tokyo": "东京", "San Francisco": "旧金山"})
	assert_str(String(t.get_message("Tokyo"))).is_equal("东京")
	assert_str(String(t.get_message("Tokyo · Japan"))).is_equal("东京 · Japan")
	assert_str(String(t.get_message("San Francisco · "))).is_equal("旧金山 · ")   # the HUD's place pill, its tail apart
	assert_str(String(t.get_message("Paris"))).is_equal("")   # off the list: the English stays

## #649 第二批 ⑨: a line kept to a width is measured as it shows — under 中文 the Chinese, cut by its own width, and
## returned so (P0Board.place_line: the outpost's name cut, the city whole).
func test_p0_widths_are_measured_on_the_chinese() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.locale = "zh_CN"
	t.set_table({"The Old Riverside Botanical Tea Pavilion": "老河畔植物园茶亭", "Shanghai": "上海",
		"Botanical Tea Pavilion of the Long Riverside Walk": "长长的河畔步道旁边那座植物园里的茶亭和花园"})
	TranslationServer.add_translation(t)
	assert_str(P0Board.place_line("The Old Riverside Botanical Tea Pavilion", "Shanghai")).is_equal("老河畔植物园茶亭 · 上海")
	var cut := P0Board.place_line("Botanical Tea Pavilion of the Long Riverside Walk", "Shanghai")
	assert_bool(cut.ends_with("… · 上海")).override_failure_message(cut).is_true()
	assert_float(P0Logic.text_width(cut)).is_less_equal(P0Board.LINE_W)
	TranslationServer.remove_translation(t)

## #649 第二批 ②: `%s XP` is a skill's (「种植经验」, no space) or a number's (「+20 经验」, a space): as long a literal, the
## template with fewer %s goes first, so a number finds `%d XP` / `%+d XP` and a name `%s XP`, whatever the table's order.
func test_p0_a_number_template_goes_before_a_name_one_as_long() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.set_table({"%s XP": "%s经验", "%d XP": "%d 经验", "Farming": "种植"})
	assert_str(String(t.get_message("+20 XP"))).is_equal("+20 经验")
	assert_str(String(t.get_message("1,200 XP"))).is_equal("1,200 经验")
	assert_str(String(t.get_message("Farming XP"))).is_equal("种植经验")
	t.set_table({"%d XP": "%d 经验", "%s XP": "%s经验", "Farming": "种植"})
	assert_str(String(t.get_message("+20 XP"))).is_equal("+20 经验")
	assert_str(String(t.get_message("Farming XP"))).is_equal("种植经验")

## #649 第二批 ③: `Since %s` is one line with the date inside; under 中文 the date is Chinese (「10 月 2 日」, the year in
## front when not this one), so the table's `%s加入` reads 「10 月 2 日加入」.
func test_p0_since_is_one_line_with_a_chinese_date() -> void:
	var oct2 := Time.get_unix_time_from_datetime_dict({year = 2026, month = 10, day = 2, hour = 12}) * 1000.0
	var now := Time.get_unix_time_from_datetime_dict({year = 2026, month = 10, day = 8, hour = 12}) * 1000.0
	var later := Time.get_unix_time_from_datetime_dict({year = 2027, month = 1, day = 3, hour = 12}) * 1000.0
	assert_str(P0ProfilePage.since_text(oct2, now)).is_equal("10 月 2 日")   # before_test's zh_CN: the locale on screen
	assert_str(P0ProfilePage.since_text(oct2, later)).is_equal("2026 年 10 月 2 日")
	var t: Translation = LocalizationScript.P0Translation.new()
	t.set_table({"Since %s": "%s加入"})
	assert_str(String(t.get_message("Since %s" % P0ProfilePage.since_text(oct2, now)))).is_equal("10 月 2 日加入")
	TranslationServer.set_locale("en")
	assert_str(P0ProfilePage.since_text(oct2, now)).is_equal("Oct 2")

## #649 第二批 ⑦ (zh-24 「First cook +10 经验」): a template with no ` · ` of its own never takes a line that has one —
## `%s XP` caught the kitchen card's `Common · First cook +10 XP` whole; its parts go one by one.
func test_p0_a_one_part_template_leaves_a_line_of_parts_to_its_parts() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.set_table({"%s XP": "%s经验", "First cook +%d XP": "首次做出 +%d 经验", "Common": "常见",
		"%s · %d left": "%s · 剩 %d", "Carrot": "胡萝卜"})
	assert_str(String(t.get_message("Common · First cook +10 XP"))).is_equal("常见 · 首次做出 +10 经验")
	assert_str(String(t.get_message("Carrot · 3 left"))).is_equal("胡萝卜 · 剩 3")   # a template with ` · ` still does

## #649 第二批 ⑧ (zh-27): the city card's trip is `6 · Continental` in English and 「第 6 档 · 洲际」 under 中文 — the
## number's own words by `%d@trip` (Localization.ctx, a format), the ` · ` and the tier's name as before.
func test_p0_ctx_formats_the_trip_tier() -> void:
	var kept = Localization.p0_translation
	var t: Translation = LocalizationScript.P0Translation.new()
	t.set_table({"%d@trip": "第 %d 档", "Continental": "洲际"})
	Localization.p0_translation = t
	var line: String = "%s · %s" % [Localization.ctx("%d", "trip") % 6, "Continental"]
	assert_str(line).is_equal("第 6 档 · Continental")
	assert_str(String(t.get_message(line))).is_equal("第 6 档 · 洲际")
	assert_str(String(t.get_message("6 · Continental"))).is_equal("6 · 洲际")   # the old line: the number left bare (zh-27)
	TranslationServer.set_locale("en")
	assert_str("%s · %s" % [Localization.ctx("%d", "trip") % 6, "Continental"]).is_equal("6 · Continental")
	Localization.p0_translation = kept

## #649 第二批 ⑥ (zh-11 「距 上品鱼 Lands up · 咬钩窗口 2.2 秒」): the Gear row's rod line is one sentence, so the place
## line's `%s to %s · %s` no longer takes it; the shelf's `Lands up to %s fish` alone reads as before.
func test_p0_the_gear_rod_line_reads_as_one_sentence() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.set_table({"%s to %s · %s": "距 {2} {1} · {3}", "Lands up to %s fish": "最高可钓到%s鱼", "Fine": "上品",
		"Lands up to %s fish · Bite window %.1f s": "最高可钓到%s鱼 · 咬钩窗口 %.1f 秒"})
	assert_str(String(t.get_message("Lands up to Fine fish · Bite window 2.2 s"))).is_equal("最高可钓到上品鱼 · 咬钩窗口 2.2 秒")
	assert_str(String(t.get_message("Lands up to Fine fish"))).is_equal("最高可钓到上品鱼")

## #649 第二批 ⑤ (zh-01 「小萝卜种子」 past the slot): a quick slot's name under 中文 is broken by the character over the
## slot's 52, two lines at most; past two a last 「种子」 goes. English as before.
func test_p0_a_quick_slots_chinese_name_breaks_by_the_character() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.locale = "zh_CN"
	t.set_table({"Quick Radish Seeds": "小萝卜种子", "Giant Red Radish Seeds": "超级无敌快熟大红萝卜种子", "Lettuce Seeds": "生菜种子"})
	TranslationServer.add_translation(t)
	Localization.set_cjk_fonts(true)
	assert_str(UiItemCell.quick_name("Quick Radish Seeds")).is_equal("小萝卜\n种子")   # two lines: 种子 whole on the second
	assert_int(UiItemCell.quick_lines("小萝卜种子")).is_equal(2)   # 51 px: past the slot's padded 44
	assert_str(UiItemCell.quick_name("Lettuce Seeds")).is_equal("生菜种子")   # one line (41 px): as it is
	assert_int(UiItemCell.quick_lines("超级无敌快熟大红萝卜种子")).is_greater(2)
	assert_str(UiItemCell.quick_name("Giant Red Radish Seeds")).is_equal("超级无敌快熟大红萝卜")
	var cell := UiItemCell.new(UiItemCell.Density.QUICK)
	add_child(cell)
	cell.title = "Quick Radish Seeds"
	assert_int(cell._name.autowrap_mode).is_equal(TextServer.AUTOWRAP_ARBITRARY)
	TranslationServer.set_locale("en")
	assert_str(UiItemCell.quick_name("Quick Radish Seeds")).is_equal("Quick Radish")
	cell.title = "Radish Seeds"
	assert_int(cell._name.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD)
	cell.queue_free()
	Localization.set_cjk_fonts(false)
	TranslationServer.remove_translation(t)
