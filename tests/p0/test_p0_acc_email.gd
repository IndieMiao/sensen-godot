extends GdUnitTestSuite
## ACC-EMAIL / ACC-EMAIL-CODE (SGODOT-497, 不知火舞's email spec v1 §2 §3, q(323); row 163): the key says what is
## missing, the server's no in red under the field (never a toast), six digits say themselves, the wait before
## `Resend code`, a wrong code kept and selected, five tries and an expired code grey, and the flow's way through.

const RECORD := "user://test_p0_acc_email.json"

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORD))

func _email() -> P0AccEmail:
	var p := P0AccEmail.new()
	add_child(auto_free(p))
	p.size = Vector2(360, 800)
	return p

func _code(address := "lin.z@icloud.com") -> P0AccEmailCode:
	var p := P0AccEmailCode.new(address)
	add_child(auto_free(p))
	p.size = Vector2(360, 800)
	return p

func _type(p: P0AccEmail, t: String) -> void:
	p.field.input.text = t
	p.field.input.text_changed.emit(t)

func _digits(p: P0AccEmailCode, t: String) -> void:
	p.input.text = t
	p.input.text_changed.emit(t)

func test_the_key_says_what_is_missing() -> void:
	var p := _email()
	assert_str(p.go.label).is_equal("Enter a valid email")
	assert_bool(p.go.disabled).is_true()
	assert_bool(p.field.helper_line.visible).is_false()   # no helper line here: only the red takes it
	for bad in ["lin", "lin@", "lin@icloud", "lin@icloud.c", "li n@icloud.com", "a@b@icloud.com"]:
		_type(p, bad)
		assert_str(p.go.label).override_failure_message(bad).is_equal("Enter a valid email")
	_type(p, "  lin.z@icloud.com ")
	assert_str(p.go.label).is_equal("Continue")
	assert_bool(p.go.disabled).is_false()
	var said: Array = []
	p.submitted.connect(func(e: String): said.append(e))
	p.go.activated.emit()
	assert_array(said).is_equal(["lin.z@icloud.com"])   # trimmed; the case is the server's
	assert_bool(p.go.disabled).is_true()   # meanwhile grey, its words kept
	assert_str(p.go.label).is_equal("Continue")
	p.go.activated.emit()
	assert_int(said.size()).is_equal(1)

func test_the_servers_no_is_red_under_the_field_till_the_address_changes() -> void:
	var p := _email()
	_type(p, "lin.z@icloud.com")
	p.show_error("rate_limited", {"retry_in": 270})
	assert_str(p.field.helper_line.text).is_equal("Too many codes requested. Try again in 5m.")
	assert_bool(p.field.helper_line.visible).is_true()
	assert_object(p.field.helper_line.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_DANGER)
	assert_bool(p.go.disabled).is_true()
	assert_str(p.go.label).is_equal("Continue")   # 715:201578: grey, the words kept
	_type(p, "lin.z@icloud.co")
	assert_bool(p.field.helper_line.visible).is_false()
	assert_bool(p.go.disabled).is_false()
	p.show_error("rate_limited", {"retry_in": 3600})
	assert_str(p.field.helper_line.text).is_equal("Too many codes requested. Try again in 1h.")
	for code in ["email_unavailable", "provider_unavailable"]:
		p.show_error(code)
		assert_str(p.field.helper_line.text).is_equal("We can't send codes right now. Please try again later.")
	p.show_error("network")
	assert_str(p.field.helper_line.text).is_equal("Check your connection and try again.")
	_type(p, "lin.z@icloud.com")
	p.show_error("schema")   # the server's shape: the grey key, no red
	assert_bool(p.field.helper_line.visible).is_false()
	assert_str(p.go.label).is_equal("Enter a valid email")

func test_the_code_page_shows_the_whole_address_and_waits_60_s_to_resend() -> void:
	var p := _code()
	assert_str(p.sent_line.get_parsed_text()).is_equal("We sent a 6-digit code to lin.z@icloud.com.")
	assert_bool(p.wait_line.visible).is_true()
	assert_bool(p.resend_key.visible).is_false()
	assert_str(p.wait_line.text).is_equal("Resend code in 1:00")
	p.tick(18.0)
	assert_str(p.wait_line.text).is_equal("Resend code in 0:42")
	var row_h: float = (p.find_child("ResendRow", true, false) as Control).size.y
	p.tick(42.0)
	assert_bool(p.wait_line.visible).is_false()
	assert_bool(p.resend_key.visible).is_true()
	assert_float((p.find_child("ResendRow", true, false) as Control).size.y).is_equal(row_h)   # 44 both ways: nothing jumps
	var asked: Array = []
	p.resend_pressed.connect(func(): asked.append(true))
	_digits(p, "48")
	p.resend_key.pressed.emit()
	assert_int(asked.size()).is_equal(1)
	assert_str(p.code()).is_equal("")
	p.code_sent(60)
	assert_str(p.wait_line.text).is_equal("Resend code in 1:00")

func test_a_long_address_loses_its_middle_and_keeps_its_domain() -> void:
	assert_str(P0AccEmailCode.short_address("lin.z@icloud.com")).is_equal("lin.z@icloud.com")
	var long := "averyveryverylongname.with.dots@example-company.co.uk"
	var s := P0AccEmailCode.short_address(long)
	assert_int(s.length()).is_equal(P0AccEmailCode.ADDRESS_MAX)
	assert_bool(s.ends_with("@example-company.co.uk")).is_true()
	assert_bool(s.begins_with("avery")).is_true()
	assert_bool(s.contains("…")).is_true()
	var p := _code("a[b]@x.io")   # brackets stay letters, not markup
	assert_str(p.sent_line.get_parsed_text()).is_equal("We sent a 6-digit code to a[b]@x.io.")

func test_six_digits_say_themselves_and_a_paste_keeps_its_digits() -> void:
	var p := _code()
	var said: Array = []
	p.entered.connect(func(c: String): said.append(c))
	_digits(p, "4827")
	assert_array(said).is_empty()
	assert_str(p.digits[3].text).is_equal("7")
	assert_str(p.digits[4].text).is_equal("")
	_digits(p, "Code: 482 719")
	assert_str(p.code()).is_equal("482719")
	assert_array(said).is_equal(["482719"])
	assert_bool(p.input.editable).is_false()   # locked till the host answers

func test_a_wrong_code_keeps_its_digits_selected_and_red_till_one_changes() -> void:
	var p := _code()
	_digits(p, "482719")
	p.show_error("bad_code", {"attempts_left": 3})
	assert_str(p.red.text).is_equal("That code didn't work. 3 tries left.")
	assert_bool(p.red.visible).is_true()
	assert_str(p.code()).is_equal("482719")
	assert_bool(p.input.has_selection()).is_true()
	assert_bool(p.input.editable).is_true()
	var box := p.cells[0].get_theme_stylebox(&"panel") as UiStyleBox
	assert_object(box.border_color).is_equal(UiTokens.COLOR_DANGER)
	p.show_error("bad_code", {"attempts_left": 1})
	assert_str(p.red.text).is_equal("That code didn't work. 1 try left.")
	_digits(p, "4")   # typed over the selection
	assert_bool(p.red.visible).is_false()
	box = p.cells[0].get_theme_stylebox(&"panel") as UiStyleBox
	assert_object(box.border_color).is_not_equal(UiTokens.COLOR_DANGER)

func test_five_tries_or_an_expired_code_grey_the_cells_till_resend() -> void:
	for c in [["bad_code", {"attempts_left": 0}, "Too many tries. Get a new code."], ["code_expired", {}, "That code has expired. Get a new code."]]:
		var p := _code()
		_digits(p, "482719")
		p.tick(60.0)
		p.show_error(str(c[0]), c[1])
		assert_str(p.red.text).is_equal(str(c[2]))
		assert_bool(p.locked).is_true()
		assert_str(p.code()).is_equal("")
		assert_bool(p.input.editable).is_false()
		var box := p.cells[2].get_theme_stylebox(&"panel") as UiStyleBox
		assert_object(box.bg_color).is_equal(UiTokens.COLOR_DISABLED)
		assert_bool(p.resend_key.visible).is_true()
		p.resend_key.pressed.emit()
		p.code_sent(60)
		assert_bool(p.locked).is_false()
		assert_bool(p.red.visible).is_false()
		assert_bool(p.input.editable).is_true()

func test_the_other_nos_on_the_code_page() -> void:
	var p := _code()
	_digits(p, "482719")
	p.show_error("network")
	assert_str(p.red.text).is_equal("Check your connection and try again.")
	assert_str(p.code()).is_equal("482719")   # kept: one changed sends them again
	var said: Array = []
	p.entered.connect(func(c: String): said.append(c))
	_digits(p, "48271")
	_digits(p, "482713")
	assert_array(said).is_equal(["482713"])
	p.show_error("rate_limited", {"retry_in": 45})
	assert_str(p.red.text).is_equal("Too many codes requested. Try again in 1m.")
	assert_str(p.wait_line.text).is_equal("Resend code in 0:45")
	p.show_error("email_unavailable")
	assert_str(p.red.text).is_equal("We can't send codes right now. Please try again later.")

func test_the_flow_goes_email_then_code_and_back() -> void:
	var f := P0AccFlow.new("old_signin", Callable(), ["google", "email"], {}, 2026)
	f.record_path = RECORD
	add_child(auto_free(f))
	f.size = Vector2(360, 800)
	var said: Array = []
	f.email_submitted.connect(func(e: String): said.append(["email", e]))
	f.code_submitted.connect(func(e: String, c: String): said.append(["code", e, c]))
	f.resend_requested.connect(func(e: String): said.append(["resend", e]))
	var signs: Array = []
	f.sign_in.connect(func(p: String): signs.append(p))
	assert_object(f.page).is_instanceof(P0AccSignIn)
	(f.page as P0AccSignIn).provider_pressed.emit("email")
	assert_array(signs).is_empty()   # not the host's sheet: the email page here
	assert_object(f.page).is_instanceof(P0AccEmail)
	_type(f.page as P0AccEmail, "lin.z@icloud.com")
	(f.page as P0AccEmail).go.activated.emit()
	f.show_error("network")
	assert_str((f.page as P0AccEmail).field.helper_line.text).is_equal("Check your connection and try again.")
	_type(f.page as P0AccEmail, "lin.z@icloud.com")
	(f.page as P0AccEmail).go.activated.emit()
	f.code_sent(60)
	assert_object(f.page).is_instanceof(P0AccEmailCode)
	_digits(f.page as P0AccEmailCode, "482719")
	f.show_error("bad_code", {"attempts_left": 4})
	assert_str((f.page as P0AccEmailCode).red.text).is_equal("That code didn't work. 4 tries left.")
	(f.page as P0AccEmailCode).tick(60.0)
	(f.page as P0AccEmailCode).resend_key.pressed.emit()
	assert_array(said).is_equal([["email", "lin.z@icloud.com"], ["email", "lin.z@icloud.com"],
		["code", "lin.z@icloud.com", "482719"], ["resend", "lin.z@icloud.com"]])
	assert_bool(f.back()).is_true()   # the code page → ACC-EMAIL, the address kept
	assert_object(f.page).is_instanceof(P0AccEmail)
	assert_str((f.page as P0AccEmail).field.text).is_equal("lin.z@icloud.com")
	assert_bool(f.back()).is_true()   # → Sign in
	assert_object(f.page).is_instanceof(P0AccSignIn)
