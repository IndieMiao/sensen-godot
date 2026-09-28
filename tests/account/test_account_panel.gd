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
	assert_bool(caption.visible).is_false()
	current.text = "correct horse"
	current.text_changed.emit(current.text)
	assert_bool(caption.visible).is_true()
	assert_str(caption.text).is_equal("Current password")
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
	assert_array(_actions(p)).not_contains(["apple"])
	AppleSignIn.force_available = true
	p.set_mode("sign_in")
	assert_array(_actions(p)).contains_exactly(["sign_in", "apple", "to_sign_up", "to_forgot"])
	p.set_mode("sign_up")
	assert_str(_actions(p)[1]).is_equal("apple")
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
