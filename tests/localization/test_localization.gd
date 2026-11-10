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

## A material's plural is its own name (奕星 11-04: `7 Claies` on the Stall Board), so the real table finds it: every
## material's `Need %d more %s` reads in Chinese, `Clay` 黏土, never a stray `Claies`.
func test_p0_table_finds_every_materials_plural() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.load_table("res://assets/localization/p0_zh_CN.json")
	for name in ["Timber", "Stone", "Clay", "Flax", "Hardwood", "Coal", "Rock Salt", "Copper Ore", "Iron Ore", "Quartz", "Reeds"]:
		var zh := String(t.get_message(name))
		assert_str(zh).override_failure_message("%s has no Chinese" % name).is_not_empty()
		# 398 第三批（李白）: the name first, `木材还差 7` (`{2}还差 {1}`)
		assert_str(String(t.get_message("Need 7 more %s" % P0Logic.plural(name)))).is_equal("%s还差 7" % zh)

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
	# a line quoted whole (the postcards page's `“…”`): the words inside
	t.set_table({"My kitchen is your kitchen.": "我的厨房就是你的厨房。"})
	assert_str(String(t.get_message("“My kitchen is your kitchen.”"))).is_equal("“我的厨房就是你的厨房。”")
	assert_str(String(t.get_message("“Unknown.”"))).is_equal("")

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
	# the pick alone: a run with SENSEN_LANGUAGE (the QA override use_p0 honours) set would win over it
	var override := OS.get_environment("SENSEN_LANGUAGE")
	OS.unset_environment("SENSEN_LANGUAGE")
	loc.use_p0(path)   # the next start: P0's table in, Journey's (this instance's) out, the picked locale
	if override != "": OS.set_environment("SENSEN_LANGUAGE", override)
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

## #649 第二批 ⑩ (the Skills page's 「下一级：Carrot and Herb」): a list's last item after ` and ` / ` or ` — 胡萝卜和香草,
## 胡萝卜、香草和土豆, 烤物或汤品 — when every item is known; a template still has the line first (`Try %s or %s`), and
## a sentence with a word the table does not hold stays English.
func test_p0_a_list_reads_its_last_and_or_or() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.set_table({"Carrot": "胡萝卜", "Herb": "香草", "Potato": "土豆", "Grilled": "烤物", "Soup": "汤品",
		"Next: %s": "下一级：%s", "Try %s or %s": "试试 %s 或 %s", "%s dishes": "%s类料理"})
	assert_str(String(t.get_message("Carrot and Herb"))).is_equal("胡萝卜和香草")
	assert_str(String(t.get_message("Next: Carrot and Herb"))).is_equal("下一级：胡萝卜和香草")
	assert_str(String(t.get_message("Carrot, Herb and Potato"))).is_equal("胡萝卜、香草和土豆")
	assert_str(String(t.get_message("Grilled or Soup dishes"))).is_equal("烤物或汤品类料理")
	assert_str(String(t.get_message("Try Carrot or Herb"))).is_equal("试试 胡萝卜 或 香草")   # the template's own
	assert_str(String(t.get_message("Carrot, Herb"))).is_equal("胡萝卜、香草")
	assert_str(String(t.get_message("Salt and pepper"))).is_equal("")   # not every item known: English
	t.set_table({"Rods and bait": "鱼竿和鱼饵", "Herb": "香草", "Carrot": "胡萝卜"})
	assert_str(String(t.get_message("Herb, Rods and bait"))).is_equal("香草、鱼竿和鱼饵")   # an item's own ` and `: the `, ` list
	assert_str(String(t.get_message("Rods and bait, Carrot and Herb"))).is_equal("鱼竿和鱼饵、胡萝卜和香草")

## 0.2.23 (李元芳 385 3c62ae6d, 不知火舞 15f1d114): lines pieced in code read whole — the Notice Board's bite clause
## without its bait, the Bite Board's sentence translated inside its quotes, `Change once · %d day%s left`, a keeper's
## small count in digits under 中文.
const BiteBoardScript := preload("res://modules/p0/p0_bite_board.gd")
func test_p0_pieced_lines_read_whole_under_chinese() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.locale = "zh_CN"
	t.set_table({"%s bite": "%s正在咬钩", "%s bite %s": "%s%s咬钩", "%s bite. %s": "%s正在咬钩。%s", "Bring worms.": "带上蚯蚓。",
		"Common Carp": "鲤鱼", "in the rain": "在雨天", "Change once · %d day%s left": "可改一次 · 还剩 {1} 天"})
	TranslationServer.add_translation(t)
	assert_str(String(t.get_message(BiteBoardScript.CLAUSE[0] % "Common Carp"))).is_equal("鲤鱼正在咬钩")
	assert_str(String(t.get_message(BiteBoardScript.CLAUSE[1] % ["Common Carp", "in the rain"]))).is_equal("鲤鱼在雨天咬钩")
	assert_str(P0Logic.shown("Common Carp bite. Bring worms.")).is_equal("鲤鱼正在咬钩。带上蚯蚓。")   # before the quotes go round it
	assert_str(String(t.get_message("Change once · %d day%s left" % [6, "s"]))).is_equal("可改一次 · 还剩 6 天")
	assert_str(String(t.get_message("Change once · %d day%s left" % [1, ""]))).is_equal("可改一次 · 还剩 1 天")
	assert_str(P0Logic._count_word(3)).is_equal("3")
	TranslationServer.set_locale("en")
	assert_str(P0Logic._count_word(3)).is_equal("three")
	TranslationServer.remove_translation(t)

## SGODOT-466 (不知火舞, 李白's key): the pond card's Biting more, the condition tags (Details, the Bite Board's pond rows)
## carry a factor like ×1.5 — the table's `%s ×%d` took only whole ones, so `Common Carp ×1.5` stayed English. `%s ×%.1f`
## takes both; Biting now's names joined by `, ` read item by item, an uncaught regional fish's `?` kept (its own key).
func test_p0_bite_factors_and_names_read_in_chinese() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.load_table("res://assets/localization/p0_zh_CN.json")
	TranslationServer.add_translation(t)
	var zh := func(s: String) -> String: return String(t.get_message(s))
	var rain := {"time": "Day", "weather": "rain", "fish": ["fish_carp"]}
	assert_str(BiteBoardScript.biting_more(rain, 1, {})).is_equal("Common Carp ×1.5")
	assert_str(zh.call(BiteBoardScript.biting_more(rain, 1, {}))).is_equal("鲤鱼 ×1.5")   # a decimal factor
	var night := {"time": "Night", "weather": "rain", "fish": ["fish_carp", "fish_catfish", "fish_eel", "fish_snakehead"]}
	assert_str(BiteBoardScript.biting_more(night, 9, {})).is_equal("? ×4 · Catfish ×3 · +2")
	assert_str(zh.call(BiteBoardScript.biting_more(night, 9, {}))).is_equal("? ×4 · 鲇鱼 ×3 · +2")   # whole ones, as before
	var catfish := {"time": {"night": 2.0}, "weather": {"rain": 1.5}}
	assert_str(BiteBoardScript.tags(catfish)).is_equal("Night ×2 · Rain ×1.5")
	assert_str(zh.call(BiteBoardScript.tags(catfish))).is_equal("夜晚 ×2 · 雨天 ×1.5")   # with its ` · `
	assert_str(zh.call(BiteBoardScript.details_line(catfish.merged({"level": 4}), false))).is_equal("钓鱼 Lv4 · 夜晚 ×2 · 雨天 ×1.5")
	assert_str(zh.call(" · " + BiteBoardScript.tags(catfish, "rain"))).is_equal(" · 夜晚 ×2 · 雨天 ×1.5")   # a Bite Board row's tags
	assert_str(zh.call("Common Carp, Catfish · +2 more")).is_equal("鲤鱼、鲇鱼 · 还有 2 条")   # Biting now (Fishing Lv8+)
	assert_str(zh.call("Sea Bass, ? · +2 more")).is_equal("海鲈、? · 还有 2 条")
	TranslationServer.remove_translation(t)

## SGODOT-467 (李白): the keeper's line with two conditions read `鲇鱼at且night in the rain咬钩` — `%s bite %s %s. %s` was
## cut at the first space. The conditions go as one phrase with a key of its own: every time × weather, bite and only
## bite, the keeper's sentence and the Notice Board's clause, the English as it was; a forecast's day by its `@weekday`
## key, a city called Mon still Mon; Clear 晴天.
func test_p0_bite_lines_with_two_conditions_read_whole_in_chinese() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.load_table("res://assets/localization/p0_zh_CN.json")
	TranslationServer.add_translation(t)
	var zh := func(s: String) -> String: return String(t.get_message(s))
	var times := {"at dawn and dusk": "在清晨和黄昏", "at night": "在夜里"}
	var weathers := {"in the rain": "在雨天", "in the wind": "在大风天", "in the sun": "在晴天"}
	for tw in times:
		for ww in weathers:
			var when := "%s %s" % [tw, ww]
			var both := "%s且%s" % [times[tw], weathers[ww]]
			assert_str(zh.call(BiteBoardScript.LINE[1] % ["Catfish", when, "Bring worms."])).is_equal("鲇鱼%s咬钩。带上蚯蚓。" % both)
			assert_str(zh.call(BiteBoardScript.LINE_ONLY % ["River Eels", when, "Bring worms."])).is_equal("河鳗只%s咬钩。带上蚯蚓。" % both)
			assert_str(zh.call(BiteBoardScript.CLAUSE[1] % ["Catfish", when])).is_equal("鲇鱼%s咬钩" % both)
			assert_str(zh.call(BiteBoardScript.CLAUSE_ONLY % ["River Eels", when])).is_equal("河鳗只%s咬钩" % both)
	# the lines as P0BiteBoard builds them: the English unchanged, one condition and none as before
	var line := func(ids: Array, weather: String, bait := true) -> String: return BiteBoardScript.line(ids, weather, 9, {}, bait)
	assert_str(line.call(["fish_catfish"], "rain")).is_equal("Catfish bite at night in the rain. Bring worms.")
	assert_str(zh.call(line.call(["fish_catfish"], "rain"))).is_equal("鲇鱼在夜里且在雨天咬钩。带上蚯蚓。")
	assert_str(line.call(["fish_eel"], "rain", false)).is_equal("River Eels only bite at night in the rain")
	assert_str(zh.call(line.call(["fish_eel"], "rain", false))).is_equal("河鳗只在夜里且在雨天咬钩")
	assert_str(zh.call(line.call(["fish_catfish"], "sun"))).is_equal("鲇鱼在夜里咬钩。带上蚯蚓。")
	assert_str(zh.call(line.call(["fish_eel"], "sun"))).is_equal("河鳗只在夜里咬钩。带上蚯蚓。")
	assert_str(zh.call(line.call(["fish_carp"], "sun", false))).is_equal("鲤鱼正在咬钩")
	assert_str(zh.call("Clear")).is_equal("晴天")
	var kept = Localization.p0_translation
	Localization.p0_translation = t
	var place := {"forecast": [{"day": "Mon", "weather": "sun"}, {"day": "Tue", "weather": "rain"}, {"day": "Sun", "weather": "wind"}]}
	assert_array(BiteBoardScript.forecast(place, 3).map(func(d): return d[0])).contains_exactly(["周一", "周二", "周日"])
	assert_str(zh.call("Mon")).is_equal("")   # the city called Mon keeps its name
	TranslationServer.set_locale("en")
	assert_array(BiteBoardScript.forecast(place, 3).map(func(d): return d[0])).contains_exactly(["Mon", "Tue", "Sun"])
	Localization.p0_translation = kept
	TranslationServer.remove_translation(t)

## 0.2.23 (不知火舞 385 fd216262): a Nearby row's name and ` · state` are measured as they show — 「费尔菲尔德」 was cut at
## Fairfield's English width and the gap before 「· 加州」 followed the English.
const CityRowScript := preload("res://scenes/p0/panels/p0_city_row.gd")
const HomePinScript := preload("res://modules/p0/p0_home_pin.gd")
const BackPillScript := preload("res://scenes/p0/panels/p0_back_pill.gd")
func test_p0_a_city_rows_name_is_measured_in_chinese() -> void:
	var t: Translation = LocalizationScript.P0Translation.new()
	t.locale = "zh_CN"
	t.set_table({"Fairfield": "费尔菲尔德", "California": "加州"})
	TranslationServer.add_translation(t)
	var first := HBoxContainer.new()
	first.theme = UiKit.theme()
	first.size = Vector2(300, 24)
	add_child(first)
	var city := UiKit.label("Fairfield", UiTokens.STYLE_ROW_TITLE_XB15)
	var region := UiKit.label(" · California", UiTokens.STYLE_C13_B)
	first.add_child(city)
	first.add_child(region)
	CityRowScript._fit_first(first, city, region)
	var font := city.get_theme_font(&"font")
	var zh_w := ceilf(font.get_string_size("费尔菲尔德", HORIZONTAL_ALIGNMENT_LEFT, -1, city.get_theme_font_size(&"font_size")).x)
	assert_float(city.custom_minimum_size.x).is_equal(zh_w)
	assert_bool(region.visible).is_true()
	assert_str(String(region.atr(region.text))).is_equal(" · 加州")
	first.queue_free()
	TranslationServer.remove_translation(t)

## 0.2.23 (不知火舞 385 bd107de1): 中文 has no italic — a Bold Italic line (the Bite Board keeper's, a Kindred line) is
## the upright bold there; English keeps its slant.
func test_p0_bold_italic_is_upright_bold_under_chinese() -> void:
	assert_object(UiKit.bold_italic()).is_same(UiKit.font(&"bold"))   # before_test's zh_CN
	assert_bool(UiKit.bold_italic().variation_transform == Transform2D.IDENTITY).is_true()
	TranslationServer.set_locale("en")
	assert_object(UiKit.bold_italic()).is_not_same(UiKit.font(&"bold"))
	assert_float(UiKit.bold_italic().variation_transform.x.y).is_not_equal(0.0)   # slanted

## 11-08 (445's Chinese shots): a toast's figure keeps its word by a no-break space (ToastLayer.keep_units), and the
## table's keys have plain spaces. The line is looked up with plain ones — whole, or part by part along ` · ` — and the
## Chinese keeps its figures with their words again; a part with no Chinese stays English with its no-break space, and
## a line with none at all gives "" (the source shown as it was, English mode's too).
func test_p0_a_toasts_no_break_space_is_looked_up_as_a_space() -> void:
	var t := Localization.P0Translation.new()
	t.load_table("res://assets/localization/p0_zh_CN.json")
	var zh := func(s: String) -> String: return String(t._get_message(ToastLayer.keep_units(s), &""))
	var plain := func(s: String) -> String: return s.replace(char(0xa0), " ")
	# a figure and its word, the whole line in the table
	assert_str(ToastLayer.keep_units("Request complete · +20 coins")).contains(char(0xa0))
	assert_str(plain.call(zh.call("Request complete · +20 coins"))).is_equal("委托完成 · +20 金币")
	assert_str(zh.call("Request complete · +20 coins")).is_equal(ToastLayer.keep_units("委托完成 · +20 金币"))   # still kept together
	# the priest's two (q(300) v1.2)
	assert_str(plain.call(zh.call("Twin Catch · back to 20 min"))).is_equal("双倍渔获 · 重新计时 20 分钟")
	# one line each in the table: the toast breaks them after their second ` · ` itself (break_at_dot, q(305); was a "\n"
	# in the table, SGODOT-452) — the demo week's fish line, the line from 11-15, and the farm one
	assert_str(plain.call(zh.call("Swift Growth · 20 min · sow now, grow 2× faster"))).is_equal("加速生长 · 20 分钟 · 现在种下的作物长得快一倍")
	assert_str(plain.call(zh.call("Twin Catch · 20 min · every fish lands ×2"))).is_equal("双倍渔获 · 20 分钟 · 每条鱼都 ×2")
	assert_str(plain.call(zh.call("Twin Catch · 20 min · fish ×2, Legendary ×1"))).is_equal("双倍渔获 · 20 分钟 · 每条鱼 ×2，传说鱼 ×1")
	# two Info toasts that broke a word at 182 px (李白's list, shot under 中文): whole sentences in the table, their toasts
	# break at a ` · ` as they read (P0Ui._break_at_dot; test_p0_the_spice_rack_and_mix_toasts_break_at_their_dot)
	assert_str(zh.call("Spice Rack · seasonings off your bag · Home Lv2")).is_equal("调味架 · 调味料不占背包 · 家园 Lv2")
	assert_str(plain.call(zh.call("Mix 1–3 ingredients · unknown mixes may become a Mystery Dish"))).is_equal("放 1–3 样食材 · 新搭配可能做出黑暗料理")
	# part by part along ` · `: the known part in Chinese, the unknown one English with its no-break space kept
	assert_str(zh.call("Twin Catch · 20 zorbs")).is_equal("双倍渔获 · 20" + char(0xa0) + "zorbs")
	# no part known: "" (English mode and an untranslated line show the source, no-break space and all)
	assert_str(zh.call("Zorb 20 quarks")).is_empty()

## SGODOT-450 / q(303) (李白, 不知火舞): the Decorate entry at the cap, `Decor 52/52 · Store one to place this`
## (P0Decor.cap_line), was eaten whole by `%s · %s to %s` (`{1} · 距 {3} {2}`) and read 「摆件 52/52 · 距 place this
## Store one」; its own whole-line template reads it, and the Decor page head stays as it was.
func test_p0_the_decor_cap_line_reads_as_one_sentence() -> void:
	var t := Localization.P0Translation.new()
	t.load_table("res://assets/localization/p0_zh_CN.json")
	var zh := func(s: String) -> String: return String(t._get_message(s, &""))
	# the English as P0Decor draws it, then its Chinese: at the cap (decor_max.max 52), below it, and the Decor page head
	var m := {"base": 20, "per_level": 4, "max": 52}
	var v := {"homestead": {"level": 9}, "decor": {"placed": [], "cap": 52, "stored": {}}}
	for i in 52: v.decor.placed.append({"uid": i + 1, "id": "deco_planter", "x": 99, "y": i, "rot": 0})
	var full := P0Decor.cap_line(v, m)
	assert_str(full).is_equal("Decor 52/52 · Store one to place this")
	assert_str(zh.call(full)).is_equal("摆件 52/52 · 先收起一件再摆")
	v.homestead.level = 2
	v.decor.cap = 24
	v.decor.placed.resize(24)
	var below := P0Decor.cap_line(v)
	assert_str(below).is_equal("Decor 24/24 · Home Lv3 adds 4")
	assert_str(zh.call(below)).is_equal("摆件 24/24 · 家园 Lv3 时 +4")
	v.decor.placed.resize(12)
	var head := P0Decor.header_line(v)
	assert_str(head).is_equal("Decor 12/24 · Goes to Farm Storage")
	assert_str(zh.call(head)).is_equal("摆件 12/24 · 放入仓库")

## The same `%s · %s to %s` / `%s to %s · %s` ate two more lines joined by ` · ` (哪吒's sweep for 450, 李白's Chinese):
## the Inbox's `3 new · 2 to do` (P0Inbox.new_line) read 「新 3 · 距 do 2」, a skill gate's `18 XP to go · harvest 9
## radishes` (P0Logic.gate_spec's note) 「距 go 18 经验 · …」. Each its own whole-line template; its halves as before.
func test_p0_lines_with_a_to_are_not_read_as_a_distance() -> void:
	var t := Localization.P0Translation.new()
	t.load_table("res://assets/localization/p0_zh_CN.json")
	var zh := func(s: String) -> String: return String(t._get_message(s, &""))
	assert_str(zh.call("3 new · 2 to do")).is_equal("新 3 · 待办 2")
	assert_str(zh.call("2 to do")).is_equal("待办 2")
	assert_str(zh.call("18 XP to go · harvest 9 radishes")).is_equal("还差 18 经验 · 收获 9 个小萝卜")
	assert_str(zh.call("18 XP to go · about 6 casts")).is_equal("还差 18 经验 · 约 6 竿")
	assert_str(zh.call("18 XP to go · about 1 new dish")).is_equal("还差 18 经验 · 约 1 道新料理")
	assert_str(zh.call("18 XP to go · about 2 Fine dishes")).is_equal("还差 18 经验 · 约 2 份上品料理")
	assert_str(zh.call("Fishing Lv3 · 40 XP to go")).is_equal("钓鱼 Lv3 · 还差 40 经验")
	# what the two were for, the home pin's distance to a pond, reads as it did
	assert_str(zh.call("San Francisco · 0.8 km to Fern Pond")).is_equal("旧金山 · 距 Fern 塘 0.8 km")

## The home pin's two lines keep ` km` in their own words (P0HomePin.km_figure), so 中文's `%s km to %s · %s` /
## `%s · %s km to %s` take only a distance: a bare `%s to %s` took any line with a ` to ` joined by ` · ` (周瑜 on #907,
## SGODOT-450). The pin card's side reads by its own eight lines (李白: 「X 侧」), no bare `west` key for other lines.
func test_p0_the_home_pins_distance_lines_take_only_a_distance() -> void:
	var t := Localization.P0Translation.new()
	t.load_table("res://assets/localization/p0_zh_CN.json")
	var zh := func(s: String) -> String: return String(t._get_message(s, &""))
	var pond := {"name": "Fern Pond", "at": Vector2(37.76, -122.44)}
	var west := Vector2(37.76, -122.44909)   # 0.8 km west of the pond (test_p1_home_pin's W08)
	var card: String = HomePinScript.card_line(west, pond)
	assert_str(card).is_equal("0.8 km to Fern Pond · west")
	assert_str(zh.call(card)).is_equal("距 Fern 塘 0.8 km · 西侧")
	var confirm: String = HomePinScript.confirm_line("San Francisco", west, pond)
	assert_str(confirm).is_equal("San Francisco · 0.8 km to Fern Pond")
	assert_str(zh.call(confirm)).is_equal("旧金山 · 距 Fern 塘 0.8 km")
	assert_str(zh.call("8,269 km to Fern Pond · northeast")).is_equal("距 Fern 塘 8,269 km · 东北侧")
	assert_str(zh.call("11 km to Fern Pond · north")).is_equal("距 Fern 塘 11 km · 北侧")
	# a line with a ` to ` joined by ` · ` reads part by part now, its halves as the table has them
	assert_str(zh.call("Carrot · Back to map")).is_equal("%s · %s" % [zh.call("Carrot"), zh.call("Back to map")])
	assert_str(zh.call("Back to map · Carrot")).is_equal("%s · %s" % [zh.call("Back to map"), zh.call("Carrot")])
	assert_str(zh.call("Carrot · Tap to skip")).is_equal("%s · %s" % [zh.call("Carrot"), zh.call("Tap to skip")])
	assert_str(zh.call("Back to map · Carrot")).not_contains("距")
	# no bare side word in the table: elsewhere `west` stays as it is
	assert_str(zh.call("west")).is_empty()

## The pin and pick pages' back key (P0BackPill, `‹  Change city` / `‹  Settings`) stayed English: the whole string is
## not in the table and nothing read past a leading `‹` (李白 on 450's shots). The arrow and its spaces stay, the words
## after it are the table's own; a word the table does not know leaves the key English.
func test_p0_a_back_keys_words_are_translated_after_its_arrow() -> void:
	var t := Localization.P0Translation.new()
	t.load_table("res://assets/localization/p0_zh_CN.json")
	var zh := func(s: String) -> String: return String(t._get_message(s, &""))
	var pill: Button = BackPillScript.new("Change city")
	assert_str(pill.text).is_equal("‹  Change city")
	assert_str(zh.call(pill.text)).is_equal("‹  更换城市")
	pill.free()
	assert_str(zh.call("‹  Settings")).is_equal("‹  设置")
	assert_str(zh.call("‹  Zorb quarks")).is_empty()
	assert_str(zh.call("‹")).is_empty()

## q(303) (SGODOT-450, 李白): the Kitchen Wing's held cells — the two new lines, and Today's line past Lv8 read from its
## two parts (`Kitchen Wing` · `Space taken`); the toast's Decorate › is the existing word.
func test_p0_the_held_wings_lines() -> void:
	var t := Localization.P0Translation.new()
	t.load_table("res://assets/localization/p0_zh_CN.json")
	var zh := func(s: String) -> String: return String(t._get_message(s, &""))
	assert_str(zh.call(P0Logic.HOME_BLOCKED_TAP)).is_equal("位置已被占用 · 先清空")
	assert_str(zh.call("Home Lv8 · Space taken")).is_equal("家园 Lv8 · 位置已被占用")
	assert_str(zh.call("Kitchen Wing · Space taken")).is_equal("灶房扩建 · 位置已被占用")
	assert_str(zh.call("Master Farmhouse · Space taken")).is_equal("大师农舍 · 位置已被占用")
	assert_str(zh.call("Lv8 look · Kitchen Wing")).is_equal("Lv8 外观 · 灶房扩建")
	assert_str(zh.call(P0Ui.DECORATE_ACTION)).is_equal("布置")

## SGODOT-453 (李白): `+%d %s` — a reward or a gather's float (`+5 Carrot Seeds` on a skill's level-up card, `+2 Timber`)
## had no template and stayed English. Every `+N` line the game draws, as its code builds it, reads as before or now in
## Chinese; the longer templates still take theirs (as #909's sweep: a short template takes only what nothing else does).
func test_p0_a_plus_count_and_its_item_reads_in_chinese() -> void:
	var t := Localization.P0Translation.new()
	t.load_table("res://assets/localization/p0_zh_CN.json")
	var zh := func(s: String) -> String: return String(t._get_message(s, &""))
	var lines := {
		"+5 Carrot Seeds": "+5 胡萝卜种子",                         # P0Logic.level_up_card's gifts (p0_logic.gd)
		"+2 Timber": "+2 木材",                                      # a gather's / the workbench's float (p0_runtime, p0_farm_materials)
		"+20 Energy": "+20 体力",
		"+30 coins": "+30 金币",
		"+1,200 coins": "+1,200 金币",                               # `+%s coins`
		"+12 Fishing XP": "+12 钓鱼经验",
		"+5 Carrot Seeds · Stored": "+5 胡萝卜种子 · 已入库",
		"+5 bag slots": "背包 +5 格",
		"+3 Friendship": "+3 好感",
		"+10 HP": "+10 生命",
		"+20 Energy back": "返还 20 体力",
		"+20 Energy · Meals today 1/3": "+20 体力 · 今日饭量 1/3",
		"+2 more": "还有 2 条",
		"+4h": "+4 小时",
	}
	for en in lines: assert_str(zh.call(en)).override_failure_message(en).is_equal(str(lines[en]))
	# (the lines after `+5 Carrot Seeds · Stored` are their own longer templates' still, not `+%d %s`'s)
	assert_str(zh.call("+20 XP")).is_equal("+20 经验")   # `%d XP` before it, as before
	assert_str(zh.call("+3")).is_empty()   # a bare figure: nothing to translate
	# every item the game names, after a count: its own Chinese
	var names := {}
	for list in ["crops", "fish", "dishes", "materials", "items", "seeds", "bait"]:
		var rows = P0Logic.content().get(list, [])
		if rows is Dictionary: rows = (rows as Dictionary).values()
		if not rows is Array: continue
		for r in rows: if r is Dictionary and str(r.get("name", "")) != "": names[str(r.name)] = true
	var checked := 0
	for name in names:
		var cn: String = zh.call(str(name))
		if cn == "": continue
		assert_str(zh.call("+5 " + str(name))).override_failure_message(str(name)).is_equal("+5 " + cn)
		checked += 1
	assert_int(checked).is_greater(30)
	# a count taken (`−2 Radish`, a batch's ingredients): P0Ui._flush_floats writes its minus as U+2212, so does the
	# template (李白); the ones with their own templates read as before
	var taken := {"−2 Radish": "−2 小萝卜", "−1 Carrot Seeds": "−1 胡萝卜种子", "−2 Timber": "−2 木材", "−3 Friendship": "−3 好感",
		"−5 Energy": "−5 体力", "−30 coins": "−30 金币", "−10 XP": "−10经验"}
	for en in taken: assert_str(zh.call(en)).override_failure_message(en).is_equal(str(taken[en]))
	assert_str(zh.call("-2 Radish")).is_empty()   # an ASCII hyphen is not the floats' minus: no template for it


## A toast broken at its ` · ` (P0Ui._break_at_dot) under 中文: the whole line is looked up first, then broken as it
## reads — broken in English first, `Fish from a pond` / `open one from the map` were looked up apart and stayed English
## (李白's 452 list, 哪吒's shots). English breaks as before.
func test_p0_a_toast_is_translated_before_it_breaks_at_its_dot() -> void:
	var t := Localization.P0Translation.new()
	t.load_table("res://assets/localization/p0_zh_CN.json")
	TranslationServer.add_translation(t)
	var ui: P0Ui = auto_free(P0Ui.new())
	add_child(ui)
	var line := "Fish from a pond · open one from the map"
	var was := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	var zh := ui._break_at_dot(line)
	TranslationServer.set_locale("en")
	var en := ui._break_at_dot(line)
	TranslationServer.set_locale(was)   # as the run had it (周瑜 on #921)
	TranslationServer.remove_translation(t)
	assert_bool(zh.contains("Fish") or zh.contains("open one")).override_failure_message(zh).is_false()
	assert_str(zh.replace("\n", " · ")).is_equal("去鱼塘钓鱼 · 从地图上打开一个")
	assert_bool(en.begins_with("Fish from a pond")).is_true()   # English as it was, broken or not by its own width

## SGODOT-461 (the user, 11-10: "把homestead换成home"; 不知火舞's spec, 李白's q(306)): the English says Home where it said
## Homestead, its Chinese still 家园. The table keeps every old Homestead key beside its new one (a new build against
## an old server, and the server's own lines until it is deployed after 0.3.5, still read in Chinese); bare `Home` is the
## homestead now and the home city is `Home city`; Homestead, Florida (a real city in the clusters) keeps its name.
func test_p0_homestead_reads_home_and_both_keys_keep_their_chinese() -> void:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/localization/p0_zh_CN.json"))
	var olds := table.keys().filter(func(k): return str(k).contains("Homestead"))
	assert_int(olds.size()).is_greater(30)
	for old in olds:
		var new_key: String = "Back Home" if old == "Back to Homestead" else str(old).replace("Homestead", "Home")
		assert_bool(table.has(new_key)).override_failure_message(new_key).is_true()
		if new_key != "Home": assert_str(str(table[new_key])).override_failure_message(new_key).is_equal(str(table[old]))
	assert_str(str(table["Home"])).is_equal("家园")
	assert_str(str(table["Home city"])).is_equal("家城")
	assert_str(str(table["Home city only"])).is_equal("仅限家城鱼塘")
	assert_str(str(preload("res://modules/p0/p0_clusters.gd").get_cluster("gn-4159050").get("name", ""))).is_equal("Homestead")   # Florida's, untouched

## SGODOT-452 (李白): the Spice Rack's and the Mix's Info toasts lost the "\n" their Chinese had set by hand. Under 中文
## they opt in to P0Ui._break_at_dot (P0Ui.break_in_chinese) and break after a ` · ` — the dot dropped, both lines inside
## the toast's width, no word cut; English does not opt in and wraps by words as before (李白: its breaking is unapproved).
func test_p0_the_spice_rack_and_mix_toasts_break_at_their_dot_in_chinese_only() -> void:
	var t := Localization.P0Translation.new()
	t.load_table("res://assets/localization/p0_zh_CN.json")
	TranslationServer.add_translation(t)
	var ui: P0Ui = auto_free(P0Ui.new())
	add_child(ui)
	var lines := ["Spice Rack · seasonings off your bag · Home Lv2", "Mix 1–3 ingredients · unknown mixes may become a Mystery Dish"]
	var was := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	var zh_opts := P0Ui.break_in_chinese()
	var zh: Array = lines.map(func(l): return ui._break_at_dot(l))
	TranslationServer.set_locale("en")
	var en_opts := P0Ui.break_in_chinese()
	TranslationServer.set_locale(was)
	TranslationServer.remove_translation(t)
	assert_bool(zh_opts).is_true()
	assert_bool(en_opts).is_false()   # English: the line as it was, the label wrapping it by words
	var label: Label = ui._toasts._label
	var font := label.get_theme_font(&"font")
	var size := label.get_theme_font_size(&"font_size")
	for broken in zh:
		for part in (broken as String).split("\n"):
			assert_bool(font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= ui.toast_text_width()).override_failure_message(broken).is_true()
			assert_bool(part.ends_with("·") or part.begins_with("·")).override_failure_message(broken).is_false()
	assert_str(zh[0]).is_equal("调味架 · 调味料不占背包\n家园 Lv2")
	assert_str(zh[1]).is_equal("放 1–3 样食材\n新搭配可能做出黑暗料理")
