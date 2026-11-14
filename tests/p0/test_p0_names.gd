extends GdUnitTestSuite
## Players' names (SGODOT-491; spec v1.1 §4; 后裔's roster / blocks `name`): the one way a member is named, a name never
## translated (Carrot, Apple, Home stay), and how it gives way — the tag at the widest default's width, a title's name
## alone, a drawer row with `…`.

const P0Names := preload("res://modules/p0/p0_names.gd")
const LocalizationScript := preload("res://modules/ui/localization.gd")

var _kept_translation
var _kept_locale := ""

func before_test() -> void:
	_kept_translation = Localization.p0_translation
	_kept_locale = TranslationServer.get_locale()

func after_test() -> void:
	Localization.p0_translation = _kept_translation
	TranslationServer.set_locale(_kept_locale)

func _chinese() -> void:
	var t = LocalizationScript.P0Translation.new()
	t.set_table({"Block %s?": "屏蔽 %s？", "Traveller %s": "旅人 %s", "Report %s": "举报 %s", "Carrot": "胡萝卜", "Apple": "苹果",
		"Home": "家园", "Reports are private. %s won't know it was you.": "举报是保密的，%s 不会知道是你举报的。"})
	Localization.p0_translation = t
	TranslationServer.set_locale("zh_CN")

func test_a_member_is_their_chosen_name_or_the_default() -> void:
	assert_str(P0Names.of({"player": "ab12cd34", "name": "Mira"})).is_equal("Mira")
	assert_str(P0Names.of({"player": "ab12cd34"})).is_equal("Traveller ab12")
	assert_str(P0Names.of({"player": "ab12cd34", "name": "  "})).is_equal("Traveller ab12")   # none chosen
	assert_str(P0Names.of({"handle": "5dd4ffff"})).is_equal("Traveller 5dd4")   # a blocks row
	assert_str(P0Names.of({"handle": "5dd4ffff", "name": "Carrot"})).is_equal("Carrot")

## 周瑜's five: the frame translates, the name never (Carrot / Apple / Home each); no key or English: the English frame;
## `{1}` order and the space rule from _fill.
func test_a_sentence_translates_its_frame_and_keeps_the_name() -> void:
	for n in ["Carrot", "Apple", "Home"]:
		assert_str(Localization.with_names("Block %s?", [n])).is_equal("Block %s?" % n)   # English
	_chinese()
	for n in ["Carrot", "Apple", "Home"]:
		assert_str(Localization.with_names("Block %s?", [n])).is_equal("屏蔽 %s？" % n)
		assert_str(Localization.with_names("Report %s", [n])).is_equal("举报 %s" % n)
	assert_str(Localization.with_names("Block %s?", ["米拉"])).is_equal("屏蔽米拉？")   # Chinese beside Chinese: no space
	assert_str(Localization.with_names("Unblock %s now", ["Mira"])).is_equal("Unblock Mira now")   # no key: English, never ""
	assert_str(P0Names.of({"player": "ab12"})).is_equal("旅人 ab12")   # only the default's frame translates

func test_a_long_name_gives_way_at_its_end() -> void:
	var font := UiKit.font(&"bold")
	var room := P0Names.tag_width(font, 28)
	assert_str(P0Names.fit("Mira", font, 28, room)).is_equal("Mira")
	var w16 := "WWWWWWWWWWWWWWWW"
	var cut := P0Names.fit(w16, font, 28, room)
	assert_str(cut).ends_with("…")
	assert_float(font.get_string_size(cut, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x).is_less_equal(room)
	assert_str(P0Names.fit("éééééééééééé", font, 28, 60.0)) \
		.not_contains("e…")   # cut between letters, never between a letter and its accent

func test_a_title_cuts_only_the_name_and_keeps_its_question_mark() -> void:
	var font := UiKit.font(&"extrabold")
	var t := P0Names.title("Block %s?", "WWWWWWWWWWWWWWWW", font, 20, 294.0)
	assert_str(t).starts_with("Block ")
	assert_str(t).ends_with("…?")
	assert_float(font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x).is_less_equal(294.0)
	assert_str(P0Names.title("Block %s?", "Mira", font, 20, 294.0)).is_equal("Block Mira?")
	_chinese()
	var zh := P0Names.title("Block %s?", "WWWWWWWWWWWWWWWW", font, 20, 200.0)   # the frame Chinese, the name cut
	assert_str(zh).starts_with("屏蔽 WWW")
	assert_str(zh).ends_with("…？")

func test_the_name_tag_shows_a_chosen_name_untranslated_and_no_wider_than_the_defaults() -> void:
	var Crowd := preload("res://modules/net/online_crowd.gd")
	var label: Label3D = auto_free(Label3D.new())
	label.font = UiKit.font(&"bold")
	label.font_size = 28
	assert_str(Crowd.tag_text({"player": "ab12cd34", "name": "Home"}, label)).is_equal("Home")
	assert_int(label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	var long: String = Crowd.tag_text({"player": "ab12cd34", "name": "WWWWWWWWWWWWWWWW"}, label)
	assert_str(long).ends_with("…")
	assert_float(label.font.get_string_size(long, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x).is_less_equal(P0Names.tag_width(label.font, 28))
	assert_str(Crowd.tag_text({"player": "ab12cd34"}, label)).is_equal("Traveller ab12")   # the default, translating as before
	assert_int(label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_INHERIT)

func test_a_drawer_row_name_ends_in_an_ellipsis_and_never_translates() -> void:
	var l: Label = auto_free(Label.new())
	preload("res://scenes/p0/panels/p0_people_drawer.gd")._as_name(l)
	assert_int(l.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_int(l.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
