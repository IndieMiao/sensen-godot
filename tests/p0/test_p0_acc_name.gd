extends GdUnitTestSuite
## ACC-NAME (SGODOT-491, spec §1.5, 635:197051 / 635:197082): the key says what is missing, the check's no in red,
## Skip, Sign in, and a check answered for a name since changed is not this one's.

var _pending: Array = []   # [name, done] the fake check holds

func _page(sign_in := true) -> P0AccName:
	var p := P0AccName.new(sign_in)
	p.check = func(n: String, done: Callable): _pending.append([n, done])
	add_child(auto_free(p))
	p.size = Vector2(360, 800)
	_pending.clear()
	return p

func _type(p: P0AccName, t: String) -> void:
	p.field.input.text = t
	p.field.input.text_changed.emit(t)

func test_the_key_says_what_is_missing() -> void:
	var p := _page()
	assert_str(p.go.label).is_equal("Enter a name")
	assert_bool(p.go.disabled).is_true()
	_type(p, "M")
	assert_str(p.go.label).is_equal("Enter a name")
	p.go.activated.emit()   # the grey key on one letter: why, in red
	assert_str(p.field.helper_line.text).is_equal("2–16 letters or numbers")
	assert_object(p.field.helper_line.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_DANGER)
	_type(p, "Mi")
	assert_str(p.go.label).is_equal("Continue")
	assert_bool(p.go.disabled).is_false()
	_type(p, "Mi@ra")
	assert_str(p.go.label).is_equal("Try another name")
	assert_str(p.field.helper_line.text).is_equal("That character can't be used")
	_type(p, "Mira")
	assert_str(p.go.label).is_equal("Continue")
	assert_str(p.field.helper_line.text).is_equal("2–16 letters or numbers")

## As the server's name.ts (q(313)): the drawn scripts, digits, single spaces and `-_.'`, two marks at most; never
## stricter than the server (full-width as half-width, as NFKC); Latin mixed with Cyrillic or Greek is not allowed.
func test_what_a_name_may_be_made_of() -> void:
	var bad := ["a@b", "a#b", "a/b", "a:b", "ab!", "a&b", "ab" + String.chr(0x1F44D), "a%sb" % String.chr(0x200B),
		"a%sb" % String.chr(0x202E), "ab%s" % String.chr(0xFE0F), "مرحبا", "a" + String.chr(0x0301).repeat(3),
		"Tom" + String.chr(0x3164), "Tom" + String.chr(0x115F), "Tom" + String.chr(0x180B), "Tom" + String.chr(0x17B4),
		"Mi" + String.chr(0x00AD) + "ra", "Mi" + String.chr(0xFEFF) + "ra"]   # the unseen ones name.ts refuses (周瑜 a395c320a)
	for n in bad: assert_str(P0AccName.local_reason(n)).override_failure_message(n).is_equal("chars")
	var good := ["Mira", "Ana María", "田中花子", "Ζωή", "Борис", "O'Neil", "Jean-Luc", "R2D2", "mi_ra.", "コーヒー", "김민지",
		"Ｍｉｒａ", "田中%s花子" % String.chr(0x3000), "Nguyê" + String.chr(0x0303), "ミア" + String.chr(0x309A)]
	for n in good: assert_str(P0AccName.local_reason(n)).override_failure_message(n).is_empty()
	for n in [String.chr(0x0410) + "dmin", "G" + String.chr(0x0435) + "nsen", "Zeta" + String.chr(0x03B6)]:
		assert_str(P0AccName.local_reason(n)).override_failure_message(n).is_equal("blocked")

func test_mixed_alphabets_say_not_allowed_and_all_spaces_is_no_name() -> void:
	var p := _page()
	_type(p, String.chr(0x0410) + "dmin")   # Cyrillic А, Latin dmin
	assert_str(p.field.helper_line.text).is_equal("That name isn't allowed")
	assert_str(p.go.label).is_equal("Try another name")
	_type(p, "   " + String.chr(0x3000) + "  ")
	assert_str(p.go.label).is_equal("Enter a name")
	p.go.activated.emit()
	assert_array(_pending).is_empty()   # nothing sent
	p.check.call("x", func(_r): pass)
	_pending.clear()
	_type(p, "Mira")
	p.go.activated.emit()
	(_pending[0][1] as Callable).call({"ok": false, "code": "name_rejected", "reason": "empty"})
	assert_str(p.field.helper_line.text).is_equal("2–16 letters or numbers")

func test_continue_checks_and_a_yes_says_the_name() -> void:
	var p := _page()
	var said: Array = []
	p.named.connect(func(n: String, s: bool): said.append([n, s]))
	_type(p, "  Mira   Lin ")
	p.go.activated.emit()
	assert_int(_pending.size()).is_equal(1)
	assert_str(str(_pending[0][0])).is_equal("Mira Lin")   # ends dropped, a run of spaces one
	assert_bool(p.go.disabled).is_true()                   # grey while it checks, its words kept
	assert_str(p.go.label).is_equal("Continue")
	p.go.activated.emit()
	assert_int(_pending.size()).is_equal(1)                # not asked twice
	(_pending[0][1] as Callable).call({"ok": true})
	assert_array(said).is_equal([["Mira Lin", false]])

func test_a_no_says_why_in_red_and_one_letter_changed_clears_it() -> void:
	var p := _page()
	var said: Array = []
	p.named.connect(func(n: String, s: bool): said.append(n))
	_type(p, "GensenStaff")
	p.go.activated.emit()
	(_pending[0][1] as Callable).call({"ok": false, "code": "name_rejected", "reason": "blocked"})
	assert_array(said).is_empty()
	assert_str(p.field.helper_line.text).is_equal("That name isn't allowed")
	assert_str(p.go.label).is_equal("Try another name")
	assert_bool(p.go.disabled).is_true()
	_type(p, "GensenStaf")
	assert_str(p.field.helper_line.text).is_equal("2–16 letters or numbers")
	assert_str(p.go.label).is_equal("Continue")

func test_a_failed_check_says_so_and_an_answer_for_an_old_name_is_dropped() -> void:
	var p := _page()
	var failed: Array[String] = []
	var said: Array = []
	p.failed.connect(func(c: String): failed.append(c))
	p.named.connect(func(n: String, s: bool): said.append(n))
	_type(p, "Mira")
	p.go.activated.emit()
	(_pending[0][1] as Callable).call({"ok": false, "code": "rate_limited"})
	assert_array(failed).is_equal(["rate_limited"])
	assert_str(p.go.label).is_equal("Continue")
	assert_bool(p.go.disabled).is_false()
	p.go.activated.emit()
	_type(p, "Mirabel")   # typed on while it checked
	(_pending[1][1] as Callable).call({"ok": true})
	assert_array(said).is_empty()

func test_skip_sign_in_and_an_old_account_without_the_row() -> void:
	var p := _page()
	var said: Array = []
	var signs: Array[int] = []
	p.named.connect(func(n: String, s: bool): said.append([n, s]))
	p.sign_in_pressed.connect(func(): signs.append(1))
	p.skip.pressed.emit()
	(p.find_child("SignIn", true, false) as Button).pressed.emit()
	assert_array(said).is_equal([["", true]])
	assert_array(signs).is_equal([1])
	var old := _page(false)
	assert_bool(old.sign_in_row.visible).is_false()
	old.prefill("Mira")
	assert_str(old.field.text).is_equal("Mira")
	assert_str(old.go.label).is_equal("Continue")

## 不知火舞 on 491: `Already have a farm?` and `Sign in` 4 apart in English, none under 中文 (the ？ brings its own space).
func test_the_sign_in_row_has_no_gap_in_chinese() -> void:
	var en := _page()
	assert_int((en.find_child("Words", true, false) as HBoxContainer).get_theme_constant(&"separation")).is_equal(4)
	TranslationServer.set_locale("zh_CN")
	var zh := _page()
	var gap := (zh.find_child("Words", true, false) as HBoxContainer).get_theme_constant(&"separation")
	TranslationServer.set_locale("en")
	assert_int(gap).is_equal(0)
