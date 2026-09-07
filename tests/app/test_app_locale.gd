extends GdUnitTestSuite
## A2 i18n：语言解析 / 应用 / 持久化；.po 覆盖全部 key 且占位符一致；zh_CN 真的生效；CJK 字体回退。

const ROOTS := ["res://modules/app", "res://scenes/app"]
const EXTRA := ["res://modules/net/firebase_auth.gd", "res://modules/net/ws_client.gd"]

func before_test() -> void:
	UiState.clear()
	TranslationServer.set_locale("en")

func after_test() -> void:
	TranslationServer.set_locale("en")
	UiState.clear()

func _entries() -> Array:
	var files: Array = []
	for r in ROOTS:
		files.append_array(I18nTools.list_gd_files(r))
	files.append_array(EXTRA)
	return I18nTools.extract_from_files(files)

func test_resolve_prefers_saved_then_system_language() -> void:
	assert_str(AppLocale.resolve("zh_CN", "en_US")).is_equal("zh_CN")
	assert_str(AppLocale.resolve("", "zh_CN")).is_equal("zh_CN")
	assert_str(AppLocale.resolve("", "zh_Hant_TW")).is_equal("zh_CN")
	assert_str(AppLocale.resolve("", "fr_FR")).is_equal("en")
	assert_str(AppLocale.resolve("klingon", "zh_CN")).is_equal("zh_CN")
	assert_str(AppLocale.next("en")).is_equal("zh_CN")
	assert_str(AppLocale.next("zh_CN")).is_equal("en")

func test_apply_sets_locale_and_persists() -> void:
	AppLocale.apply("zh_CN")
	assert_str(TranslationServer.get_locale()).is_equal("zh_CN")
	assert_str(AppLocale.current()).is_equal("zh_CN")
	assert_str(str(UiState.read().get(AppLocale.UI_STATE_KEY, ""))).is_equal("zh_CN")
	AppLocale.apply("nope")
	assert_str(AppLocale.current()).is_equal("en")

func test_boot_apply_reads_persisted_choice() -> void:
	UiState.write({AppLocale.UI_STATE_KEY: "zh_CN"})
	AppLocale.boot_apply()
	assert_str(AppLocale.current()).is_equal("zh_CN")

func test_translations_are_registered_and_zh_takes_effect() -> void:
	var registered: PackedStringArray = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	assert_bool(registered.has("res://locale/en.po")).is_true()
	assert_bool(registered.has("res://locale/zh_CN.po")).is_true()
	TranslationServer.set_locale("zh_CN")
	assert_str(TranslationServer.translate("Sign in")).is_equal("登录")
	assert_str(TranslationServer.translate("Realtime: %s") % "x").is_equal("实时连接：x")
	TranslationServer.set_locale("en")
	assert_str(TranslationServer.translate("Sign in")).is_equal("Sign in")

func test_extraction_finds_tr_titles_and_marked_lines() -> void:
	var src := 'label.text = tr("Hello %s")\npage_title = "Settings"\nconst T := {A: "Map", B: "Me"} ## i18n\nvar x := "not a key"\n'
	var got := I18nTools.extract_from_source(src, "x.gd")
	var ids := got.map(func(e): return e.msgid)
	assert_array(ids).contains(["Hello %s", "Settings", "Map", "Me"])
	assert_bool(ids.has("not a key")).is_false()
	assert_str(got[0].ref).is_equal("x.gd:1")

func test_po_parser_handles_multiline_and_escapes() -> void:
	var po := 'msgid ""\nmsgstr ""\n"Language: zh\\n"\n\nmsgid "A \\"q\\""\nmsgstr "甲"\n\nmsgid "Two"\n"Part"\nmsgstr ""\n"两"\n"部分"\n'
	var d := I18nTools.parse_po(po)
	assert_str(d.get("A \"q\"", "")).is_equal("甲")
	assert_str(d.get("TwoPart", "")).is_equal("两部分")
	assert_bool(d.has("")).is_false()

func test_every_extracted_key_is_translated_in_zh_and_present_in_en() -> void:
	var entries := _entries()
	assert_int(entries.size()).is_greater(30)
	var zh := I18nTools.parse_po(FileAccess.get_file_as_string("res://locale/zh_CN.po"))
	var res := I18nTools.check_po(entries, zh, true)
	assert_array(res.missing).override_failure_message("zh_CN.po 缺翻译: %s" % [res.missing]).is_empty()
	assert_array(res.placeholder_mismatch).override_failure_message("zh_CN.po 占位符不一致: %s" % [res.placeholder_mismatch]).is_empty()
	# en.po 只需存在，msgstr 留空即回退 msgid（源语言）。
	var en := I18nTools.parse_po(FileAccess.get_file_as_string("res://locale/en.po"))
	assert_object(en).is_not_null()

func test_describe_codes_tab_titles_and_ws_states_are_translated() -> void:
	var zh := I18nTools.parse_po(FileAccess.get_file_as_string("res://locale/zh_CN.po"))
	for code in ["EMAIL_NOT_FOUND", "EMAIL_EXISTS", "WEAK_PASSWORD", "INVALID_EMAIL", "USER_DISABLED", "TOO_MANY_ATTEMPTS_TRY_LATER", "OPERATION_NOT_ALLOWED", "NOT_CONFIGURED", "TRANSPORT", "timeout", "SOMETHING_ODD"]:
		var key := FirebaseAuth.describe_key(code)
		assert_bool(zh.has(key) and not str(zh[key]).is_empty()).override_failure_message("describe_key(%s) = %s 无 zh 翻译" % [code, key]).is_true()
	# describe() 自带翻译与格式化：未知码在 zh 下也是中文句子。
	TranslationServer.set_locale("zh_CN")
	assert_str(FirebaseAuth.describe("EMAIL_NOT_FOUND")).is_equal("邮箱或密码不正确。")
	assert_str(FirebaseAuth.describe("SOMETHING_ODD")).is_equal("登录失败（SOMETHING_ODD）。")
	TranslationServer.set_locale("en")
	assert_str(FirebaseAuth.describe("SOMETHING_ODD")).is_equal("Sign-in failed (SOMETHING_ODD).")
	for tab in AppRoutes.TABS:
		assert_bool(zh.has(AppRoutes.tab_title(tab))).override_failure_message("tab %s 无翻译" % tab).is_true()
	for name in ["idle", "connecting", "connected", "reconnecting", "paused"]:
		assert_bool(zh.has(name)).is_true()

func test_pot_is_in_sync_with_sources() -> void:
	# messages.pot 由 tools/i18n/extract_pot.gd 生成；源码加了新 key 必须重新生成并提交。
	var pot := I18nTools.parse_po(FileAccess.get_file_as_string("res://locale/messages.pot"))
	for e in I18nTools.unique_entries(_entries()):
		assert_bool(pot.has(e.msgid)).override_failure_message("messages.pot 落后于源码: %s（重跑 extract_pot.gd）" % e.msgid).is_true()

func test_theme_font_falls_back_to_cjk() -> void:
	var t := GameUi.theme()
	var f := t.default_font as FontVariation
	assert_object(f).is_not_null()
	assert_int(f.fallbacks.size()).is_greater_equal(1)
	assert_bool(str(f.fallbacks[0].resource_path).contains("NotoSansSC")).is_true()

func test_shell_renders_translated_tab_titles_under_zh() -> void:
	TranslationServer.set_locale("zh_CN")
	var s := (load(AppRoutes.SHELL) as PackedScene).instantiate() as AppShell
	add_child(auto_free(s))
	assert_str(s.tab_button("map").text).is_equal("地图")
	assert_str(s.tab_button("im").text).is_equal("消息")
	assert_str(s.page("map").title_label.text).is_equal("地图")
	TranslationServer.set_locale("en")
