extends GdUnitTestSuite
## 账号面板（SGODOT-135）：各状态的输入框与按钮、本地校验、资料页、登录墙关闭语义。

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())

func _panel(mode := "sign_in", reason := "") -> AccountPanel:
	var p := AccountPanel.new()
	p.mode = mode
	p.reason = reason
	add_child(p)
	return p

func _sign_in_locally(name := "") -> void:
	Net.account.token = "tok"
	Net.account.user_id = "u1"
	Net.account.email = "ada@example.com"
	Net.account.display_name = name

func _visible_fields(p: AccountPanel) -> Array:
	var out := []
	for name in ["Nickname", "Email", "Password", "Code", "NewPassword", "ConfirmPassword", "Gender", "GenderCustom", "Birthday"]:
		var f: Control = p.find_child(name, true, false)
		if f.visible: out.append(name)
	return out

func _actions(p: AccountPanel) -> Array:
	return p.find_child("Actions", true, false).get_children().map(func(b): return str(b.name))

func _providers(p: AccountPanel) -> Array:
	var row := p.find_child("Actions", true, false).get_node_or_null("Providers/Row")
	return [] if row == null else row.get_children().map(func(b): return str(b.name))

func _status(p: AccountPanel) -> String:
	return (p.find_child("Status", true, false) as Label).text

func test_modes_show_only_their_fields_and_actions() -> void:
	var p := _panel()
	assert_array(_visible_fields(p)).contains_exactly(["Email", "Password"])
	assert_array(_actions(p)).contains_exactly(["sign_in", "to_sign_up", "to_forgot"])
	p.set_mode("sign_up")
	assert_array(_visible_fields(p)).contains_exactly(["Email", "Password", "ConfirmPassword"])
	p.set_mode("forgot")
	assert_array(_visible_fields(p)).contains_exactly(["Email"])
	p._reset_code_sent = true
	p.set_mode("forgot")
	assert_array(_visible_fields(p)).contains_exactly(["Email", "Code", "NewPassword", "ConfirmPassword"])
	p.set_mode("verify")
	assert_array(_visible_fields(p)).contains_exactly(["Code"])
	p.set_mode("password")
	assert_array(_visible_fields(p)).contains_exactly(["Password", "NewPassword", "ConfirmPassword"])
	p.set_mode("profile")
	assert_array(_visible_fields(p)).contains_exactly(["Nickname", "Gender", "Birthday"])
	p.queue_free()

func test_login_wall_reason_is_shown() -> void:
	var p := _panel("sign_up", "Sign in to create your farm.")
	assert_str(p._subtitle.text).is_equal("Sign in to create your farm.")
	p.queue_free()

func test_local_validation_never_calls_the_server() -> void:
	var p := _panel("sign_up")
	(p.find_child("Email", true, false) as LineEdit).text = "not-an-email"
	await p._submit_login(true)
	assert_str(_status(p)).is_equal("Enter a valid email address.")
	(p.find_child("Email", true, false) as LineEdit).text = "ada@example.com"
	(p.find_child("Password", true, false) as LineEdit).text = "short"
	await p._submit_login(true)
	assert_str(_status(p)).is_equal("Use at least 8 characters for your password.")
	(p.find_child("Password", true, false) as LineEdit).text = "correct horse"
	(p.find_child("ConfirmPassword", true, false) as LineEdit).text = "correct horsy"
	await p._submit_login(true)
	assert_str(_status(p)).is_equal("The two passwords don't match.")
	assert_bool(p.busy).is_false()
	p.queue_free()

func test_passwords_are_masked_until_shown() -> void:
	var p := _panel("sign_up")
	for name in ["Password", "ConfirmPassword", "NewPassword"]:
		assert_bool((p.find_child(name, true, false) as LineEdit).secret).is_true()
	(p.find_child("ShowPasswords", true, false) as CheckBox).button_pressed = true
	for name in ["Password", "ConfirmPassword", "NewPassword"]:
		assert_bool((p.find_child(name, true, false) as LineEdit).secret).is_false()
	assert_bool((p.find_child("Email", true, false) as LineEdit).secret).is_false()
	p.queue_free()

func test_gender_options_follow_north_american_conventions() -> void:
	var p := _panel("profile")
	var gender := p.find_child("Gender", true, false) as OptionButton
	var labels := []
	for i in gender.item_count: labels.append(gender.get_item_text(i))
	assert_array(labels).contains_exactly(["Gender (optional)", "Woman", "Man", "Non-binary", "Prefer to self-describe", "Prefer not to say"])
	assert_bool((p.find_child("GenderCustom", true, false) as Control).visible).is_false()
	gender.select(4)
	gender.item_selected.emit(4)
	assert_bool((p.find_child("GenderCustom", true, false) as Control).visible).is_true()
	p.queue_free()

func test_profile_needs_a_nickname_and_a_whole_or_empty_birthday() -> void:
	_sign_in_locally()
	var p := _panel("profile")
	await p._submit_profile()
	assert_str(_status(p)).is_equal("Nicknames are 2–24 characters and can't be an email address.")
	(p.find_child("Nickname", true, false) as LineEdit).text = "Ada"
	(p.find_child("Month", true, false) as OptionButton).select(2)
	await p._submit_profile()
	assert_str(_status(p)).is_equal("Pick month, day and year, or leave the birthday empty.")
	(p.find_child("Day", true, false) as OptionButton).select(9)
	var year := p.find_child("Year", true, false) as OptionButton
	year.select(1)
	assert_str(str(p._selected_birthday())).is_equal("%s-02-09" % year.get_item_text(1))
	# The youngest selectable year still leaves the player at least 13.
	assert_int(Time.get_date_dict_from_system().year - int(year.get_item_text(1))).is_equal(13)
	p.queue_free()

func test_account_summary_shows_nickname_email_gender_and_age() -> void:
	_sign_in_locally("Ada")
	Net.account.email_verified = true
	Net.account.gender = "nonbinary"
	Net.account.age = 26
	var p := _panel("account")
	assert_str(p._subtitle.text).is_equal("Ada\nada@example.com\nVerified · Non-binary · Age 26")
	assert_array(_actions(p)).contains_exactly(["done", "edit_profile", "to_password", "sign_out", "delete"])
	p.set_mode("delete")
	assert_array(_actions(p)).contains_exactly(["delete_now", "to_account"])
	p.queue_free()

func test_signed_in_without_nickname_lands_on_the_profile_step() -> void:
	_sign_in_locally()
	var p := _panel("verify")
	p._after_sign_in()
	assert_str(p.mode).is_equal("profile")
	assert_array(_actions(p)).contains_exactly(["save_profile"])
	p.queue_free()

func test_closing_reports_guest_state() -> void:
	var p := _panel()
	var results := []
	p.closed.connect(func(v): results.append(v))
	p.dismiss()
	assert_array(results).is_equal([false])

func test_panel_is_a_modal_that_covers_the_screen() -> void:
	var p := _panel()
	assert_bool(p.is_in_group(GameUi.MODAL_GROUP)).is_true()
	var scrim := p.find_child("Scrim", true, false) as ColorRect
	assert_float(scrim.color.a).is_equal(1.0)
	assert_int(scrim.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	p.queue_free()

func test_filled_fields_keep_a_caption() -> void:
	var p := _panel("password")
	var current := p.find_child("Password", true, false) as LineEdit
	var caption := p.find_child("PasswordCaption", true, false) as Label
	# Empty field: the caption's line is kept (C-66) but has no words, so a screen reader reads only the
	# field's placeholder, not the same words twice (C-78).
	assert_bool(caption.visible).is_true()
	assert_str(caption.text).is_empty()
	current.text = "correct horse"
	current.text_changed.emit(current.text)
	assert_bool(caption.visible).is_true()
	assert_str(caption.text).is_equal("Current password")
	current.text = ""
	current.text_changed.emit(current.text)
	assert_str(caption.text).is_empty()
	p.queue_free()

func _rects(p: AccountPanel, names: Array) -> Dictionary:
	var out := {}
	for name in names: out[name] = (p.find_child(name, true, false) as Control).get_global_rect()
	return out

func _type(edit: LineEdit, text: String) -> void:
	edit.text = text
	edit.text_changed.emit(text)

## C-66: typing must not move the fields or buttons (two evidence runs tapped "Show passwords" or the
## wrong field after the panel reflowed under the finger).
func test_typing_keeps_fields_and_buttons_in_place() -> void:
	for mode in ["sign_in", "sign_up"]:
		var p := _panel(mode)
		var names := ["Email", "Password", "ShowPasswords", "sign_in" if mode == "sign_in" else "sign_up"]
		if mode == "sign_up": names.append("ConfirmPassword")
		await get_tree().process_frame
		await get_tree().process_frame
		var before := _rects(p, names)
		for step in [["Email", "q"], ["Email", "qa@example.com"], ["Password", "a"], ["Password", "abcdefgh"], ["ConfirmPassword", "abcdefgh"]]:
			if step[0] == "ConfirmPassword" and mode != "sign_up": continue
			_type(p.find_child(step[0], true, false) as LineEdit, step[1])
			await get_tree().process_frame
			await get_tree().process_frame
			assert_dict(_rects(p, names)).is_equal(before)
		assert_str((p.find_child("EmailCaption", true, false) as Label).text).is_equal("Email")
		p.queue_free()

## Every message the panel can show under its fields: local checks, progress and each server answer.
func _status_messages() -> Array:
	var out := ["Signing in…", "Enter your password.", "Enter a valid email address.", "Use at least 8 characters for your password.",
		"Enter the 6-digit code.", "A new code is on its way.", "If this email has an account, a code is on its way.",
		"Pick month, day and year, or leave the birthday empty.", "Profile saved.", "Password changed."]
	for code in ["INVALID_EMAIL", "WEAK_PASSWORD", "EMAIL_TAKEN", "INVALID_CREDENTIALS", "CODE_INVALID", "CODE_EXPIRED",
			"CODE_LOCKED", "CODE_COOLDOWN", "RATE_LIMITED", "LOGIN_REQUIRED", "INVALID_NAME", "INVALID_GENDER",
			"INVALID_BIRTH_DATE", "UNDER_AGE", "SAME_PASSWORD", "PASSWORD_MISMATCH", "TRANSPORT", "EMAIL_IN_USE",
			"GOOGLE_NO_ACCOUNT", "GOOGLE_UNAVAILABLE", "APPLE_UNAVAILABLE", "APPLE_FAILED", "GOOGLE_FAILED", "UNKNOWN"]:
		out.append(AccountSession.describe(code))
	return out

## C-78: a message appearing after a tap ("Signing in…", "Can't reach the server…") must not push the
## primary button or anything below it; neither may it clearing again. Chinese is the game's default
## language and English wraps the longest, so both are checked.
func test_status_messages_keep_the_buttons_in_place() -> void:
	var locale := TranslationServer.get_locale()
	for language in ["en", "zh_CN"]:
		TranslationServer.set_locale(language)
		for mode in ["sign_in", "sign_up"]:
			var p := _panel(mode)
			var names := ["Email", "Password", "ShowPasswords", mode, "to_sign_in" if mode == "sign_up" else "to_sign_up"]
			if mode == "sign_in": names.append("to_forgot")
			await get_tree().process_frame
			await get_tree().process_frame
			var before := _rects(p, names)
			var status := p.find_child("Status", true, false) as Label
			for message in _status_messages() + [""]:
				p._say(message)
				await get_tree().process_frame
				await get_tree().process_frame
				assert_bool(status.visible).is_true()
				assert_int(status.get_line_count()).is_less_equal(AccountPanel.STATUS_LINES)
				assert_dict(_rects(p, names)).override_failure_message("%s moved the buttons in %s (%s)" % [status.text, mode, language]).is_equal(before)
			p.queue_free()
	TranslationServer.set_locale(locale)

func test_local_validation_message_keeps_sign_in_in_place() -> void:
	var p := _panel()
	await get_tree().process_frame
	await get_tree().process_frame
	var sign_in := p.find_child("sign_in", true, false) as Control
	var before := sign_in.get_global_rect()
	await p._submit_login(false)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(_status(p)).is_equal("Enter a valid email address.")
	assert_object(sign_in.get_global_rect()).is_equal(before)
	p.set_mode("sign_in")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(_status(p)).is_empty()
	# The buttons are rebuilt for the mode; the new "Sign in" sits where the old one did.
	assert_object((p.find_child("sign_in", true, false) as Control).get_global_rect()).is_equal(before)
	p.queue_free()

func test_hidden_fields_reserve_no_caption_line() -> void:
	_sign_in_locally("Ada")
	var p := _panel("profile")
	# The self-describe field is hidden until picked; its caption line must not leave a gap.
	assert_bool((p.find_child("GenderCustomCaption", true, false) as Control).visible).is_false()
	assert_bool((p.find_child("EmailCaption", true, false) as Control).visible).is_false()
	# A nickname filled in from the account is labelled like a typed one.
	assert_str((p.find_child("NicknameCaption", true, false) as Label).text).is_equal("Nickname (2–24 characters)")
	var gender := p.find_child("Gender", true, false) as OptionButton
	gender.select(4)
	gender.item_selected.emit(4)
	assert_bool((p.find_child("GenderCustomCaption", true, false) as Control).visible).is_true()
	p.queue_free()

const APPLE_ACCOUNT := "user://test_account_panel_apple.json"

func _apple_net(responses: Array) -> FakeTransport:
	var t := FakeTransport.new(responses)
	Net.use_transport(t.callable())
	Net.account_path = APPLE_ACCOUNT
	return t

func _restore_net() -> void:
	AppleSignIn.force_available = false
	Net.account.clear(APPLE_ACCOUNT)
	Net.account_path = AccountSession.PATH

func test_apple_button_follows_the_primary_action_only_on_ios() -> void:
	var p := _panel()
	assert_array(_actions(p)).not_contains(["Providers"])
	AppleSignIn.force_available = true
	p.set_mode("sign_in")
	assert_array(_actions(p)).contains_exactly(["sign_in", "Providers", "to_sign_up", "to_forgot"])
	assert_array(_providers(p)).is_equal(["apple"])
	# Logo-only button: no text, an accessible name, and the Apple logo.
	var apple: Button = p.action_button("apple")
	assert_str(apple.text).is_empty()
	assert_str(apple.tooltip_text).is_equal("Sign in with Apple")
	assert_object(apple.icon).is_not_null()
	p.set_mode("sign_up")
	assert_str(_actions(p)[1]).is_equal("Providers")
	# Replaced rows are freed at the end of the frame.
	await get_tree().process_frame
	p.queue_free()
	_restore_net()

func test_apple_sign_in_sends_the_raw_nonce_and_adopts_a_password_less_account() -> void:
	AppleSignIn.force_available = true
	var t := _apple_net([{"status": 201, "json": {"token": "apple-token", "user_id": "u-apple", "player_id": "p-apple",
		"email": null, "email_verified": false, "display_name": "Avery", "profile_complete": true, "has_password": false, "created": true}}])
	var p := _panel()
	var hashes := []
	p.apple_transport = func(hash: String) -> String:
		hashes.append(hash)
		return "APPLE_OK|id.token.sig|Avery|Lee|"
	await p._submit_apple()
	var body: Dictionary = t.requests[0].body
	assert_str(t.requests[0].url).ends_with("/auth/apple")
	assert_str(body.identity_token).is_equal("id.token.sig")
	assert_str(str(body.nonce).sha256_text()).is_equal(hashes[0])
	assert_str(body.given_name).is_equal("Avery")
	assert_str(Net.account.user_id).is_equal("u-apple")
	assert_bool(Net.account.has_password).is_false()
	assert_bool(p.is_queued_for_deletion()).is_true()
	_restore_net()

func test_cancelled_apple_sheet_is_silent_and_calls_no_server() -> void:
	AppleSignIn.force_available = true
	var t := _apple_net([])
	var p := _panel()
	p.apple_transport = func(_hash: String) -> String: return "APPLE_ERR|canceled"
	await p._submit_apple()
	assert_array(t.requests).is_empty()
	assert_str(_status(p)).is_empty()
	assert_bool(p.busy).is_false()
	p.queue_free()
	_restore_net()

func test_password_less_account_hides_password_steps() -> void:
	_sign_in_locally("Avery")
	Net.account.email = ""
	Net.account.has_password = false
	var p := _panel("account")
	assert_array(_actions(p)).not_contains(["to_password", "start_verify"])
	assert_str(p._subtitle.text).contains("Signed in with Apple")
	p.set_mode("delete")
	assert_array(_visible_fields(p)).is_empty()
	assert_str(p._subtitle.text).contains("can't be undone")
	p.queue_free()
	Net.account.has_password = true
	Net.account.email = "ada@example.com"

func test_google_button_follows_apple_or_the_primary_action() -> void:
	GoogleSignIn.force_available = true
	var p := _panel()
	assert_array(_actions(p)).contains_exactly(["sign_in", "Providers", "to_sign_up", "to_forgot"])
	assert_array(_providers(p)).is_equal(["google"])
	AppleSignIn.force_available = true
	p.set_mode("sign_in")
	assert_array(_providers(p)).is_equal(["apple", "google"])
	assert_str(p.action_button("google").text).is_empty()
	await get_tree().process_frame
	p.queue_free()
	GoogleSignIn.force_available = false
	_restore_net()

## The dynamic farm release package (C-101): the full panel, as in every other package. The C-98 invite-only
## switch is gone, so an old setting left behind changes nothing; invite accounts sign in with email and password.
func test_release_package_offers_sign_up_reset_and_google() -> void:
	GoogleSignIn.force_available = true
	ProjectSettings.set_setting("sensen/account/invite_only", true)
	var p := _panel()
	assert_array(_visible_fields(p)).contains_exactly(["Email", "Password"])
	assert_array(_actions(p)).contains_exactly(["sign_in", "Providers", "to_sign_up", "to_forgot"])
	assert_array(_providers(p)).is_equal(["google"])
	assert_str(p._subtitle.text).is_equal("Sign in with your email to keep your farm on every device.")
	p.set_mode("sign_up")
	assert_str(p.mode).is_equal("sign_up")
	assert_array(_actions(p)).contains_exactly(["sign_up", "Providers", "to_sign_in"])
	p.set_mode("forgot")
	assert_str(p.mode).is_equal("forgot")
	assert_array(_actions(p)).contains_exactly(["send_reset", "to_sign_in"])
	await get_tree().process_frame
	p.queue_free()
	ProjectSettings.set_setting("sensen/account/invite_only", null)
	GoogleSignIn.force_available = false
	_restore_net()

## A server that takes no new accounts (invite accounts only) answers sign-up with a plain line, not "went wrong".
func test_sign_up_on_a_closed_server_says_so() -> void:
	_apple_net([{"status": 403, "json": {"code": "SIGNUP_CLOSED"}}])
	var p := _panel("sign_up")
	p._email.text = "ada@example.com"
	p._password.text = "correct horse"
	p._confirm_password.text = "correct horse"
	await p._submit_login(true)
	assert_str(_status(p)).is_equal("New accounts aren't open yet. Sign in with an existing account.")
	assert_bool(Net.account.signed_in()).is_false()
	p.queue_free()
	_restore_net()

func test_google_sign_in_sends_the_raw_nonce_and_adopts_the_account() -> void:
	GoogleSignIn.force_available = true
	var t := _apple_net([{"status": 201, "json": {"token": "g-token", "user_id": "u-google", "player_id": "p-google",
		"email": "ada@gmail.com", "email_verified": true, "display_name": "Ada", "profile_complete": true, "has_password": false, "created": true}}])
	var p := _panel()
	var hashes := []
	p.google_transport = func(hash: String) -> String:
		hashes.append(hash)
		return '{"ok":true,"id_token":"g.id.token","given_name":"Ada"}'
	await p._submit_google()
	assert_str(t.requests[0].url).ends_with("/auth/google")
	assert_str(t.requests[0].body.id_token).is_equal("g.id.token")
	assert_str(str(t.requests[0].body.nonce).sha256_text()).is_equal(hashes[0])
	assert_str(Net.account.user_id).is_equal("u-google")
	assert_bool(p.is_queued_for_deletion()).is_true()
	GoogleSignIn.force_available = false
	_restore_net()

func test_cancelled_google_picker_is_silent() -> void:
	GoogleSignIn.force_available = true
	var t := _apple_net([])
	var p := _panel()
	p.google_transport = func(_hash: String) -> String: return '{"ok":false,"code":"GOOGLE_CANCELED"}'
	await p._submit_google()
	assert_array(t.requests).is_empty()
	assert_str(_status(p)).is_empty()
	p.queue_free()
	GoogleSignIn.force_available = false
	_restore_net()

## Every step the panel has, with the most buttons each can show (both sign-in providers, every account action,
## the self-describe gender field), so the tallest layout of each is checked.
func _tallest_steps() -> Array:
	return [["sign_in", false], ["sign_up", false], ["forgot", false], ["forgot", true], ["verify", false],
		["profile", false], ["password", false], ["account", false], ["delete", false]]

func _open_step(step: Array) -> AccountPanel:
	if step[0] in ["verify", "profile", "password", "account", "delete"]:
		_sign_in_locally("Ada")
		Net.account.email_verified = false
		Net.account.has_password = true
		Net.account.gender = "self_describe"
		Net.account.gender_custom = "Ada"
	var p := _panel(step[0])
	if step[1]:
		p._reset_code_sent = true
		p.set_mode(step[0])
	return p

func _action_buttons(p: AccountPanel) -> Array:
	return p.find_child("Actions", true, false).find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree())

func _settle() -> void:
	for i in 3: await get_tree().process_frame

## Puts the finger down on the button's centre and lifts it away from every button, so nothing is triggered;
## true when the press reached that button, i.e. it is on screen and nothing covers it.
func _press_reaches(b: Button) -> bool:
	var hits := [0]
	var count := func(): hits[0] += 1
	b.button_down.connect(count)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = b.get_global_rect().get_center()
	down.global_position = down.position
	get_viewport().push_input(down, true)
	# Slide off first: a button decides on release from where the finger last moved, not where it lifts.
	var away := InputEventMouseMotion.new()
	away.button_mask = MOUSE_BUTTON_MASK_LEFT
	away.position = Vector2(2, 2)
	away.global_position = away.position
	get_viewport().push_input(away, true)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	up.position = Vector2(2, 2)
	up.global_position = up.position
	get_viewport().push_input(up, true)
	b.button_down.disconnect(count)
	return hits[0] == 1

## C-81: on a 16:9 screen (360x640 logical, the project's base size) the reset-code step ran ~100 px past the
## bottom edge with no way to scroll. Every button of every step must scroll into view and take a tap, in
## both languages, and a message appearing at the scrolled end must not move them (C-78).
func test_every_button_can_be_scrolled_to_and_pressed_on_a_16_9_screen() -> void:
	# The headless window is square; give it the shape of a 720x1280 phone, which the project's
	# 360x640 base size and expand stretch turn into a 360x640 logical screen.
	var window := get_window()
	var window_size := window.size
	window.size = Vector2i(720, 1280)
	await _settle()
	var view := get_viewport().get_visible_rect()
	assert_vector(view.size).is_equal(Vector2(360, 640))
	var locale := TranslationServer.get_locale()
	AppleSignIn.force_available = true
	GoogleSignIn.force_available = true
	var overflowing := []
	for language in ["en", "zh_CN"]:
		TranslationServer.set_locale(language)
		for step in _tallest_steps():
			var p := _open_step(step)
			await _settle()
			var where := "%s%s (%s)" % [step[0], " after the code was sent" if step[1] else "", language]
			var scroll := p.find_child("Scroll", true, false) as ScrollContainer
			var lowest := 0.0
			for b in _action_buttons(p): lowest = maxf(lowest, b.get_global_rect().end.y)
			if lowest > view.end.y: overflowing.append(where)
			for b in _action_buttons(p):
				scroll.ensure_control_visible(b)
				await _settle()
				var rect: Rect2 = b.get_global_rect()
				assert_bool(view.encloses(rect)).override_failure_message("%s is off screen in %s: %s" % [b.name, where, rect]).is_true()
				assert_bool(_press_reaches(b)).override_failure_message("a tap on %s missed it in %s" % [b.name, where]).is_true()
			# At the scrolled end a message still leaves the buttons where they are.
			var buttons := _action_buttons(p)
			var before := buttons.map(func(b): return b.get_global_rect())
			p._say(AccountSession.describe("TRANSPORT"))
			await _settle()
			assert_array(buttons.map(func(b): return b.get_global_rect())).override_failure_message("a message moved the buttons in %s" % where).is_equal(before)
			# Refreshing the same step (as "Send a new code" does) keeps the scroll; a new step starts at its top.
			var scrolled := scroll.scroll_vertical
			p.set_mode(step[0])
			await _settle()
			assert_int(scroll.scroll_vertical).override_failure_message("refreshing %s scrolled" % where).is_equal(scrolled)
			p.set_mode("verify" if step[0] != "verify" else "sign_in")
			await _settle()
			assert_int(scroll.scroll_vertical).is_equal(0)
			p.queue_free()
			Net.account._reset_fields()
	# The check above is only meaningful if some steps really are taller than the screen.
	assert_array(overflowing).contains(["forgot after the code was sent (en)", "forgot after the code was sent (zh_CN)"])
	TranslationServer.set_locale(locale)
	AppleSignIn.force_available = false
	GoogleSignIn.force_available = false
	window.size = window_size
