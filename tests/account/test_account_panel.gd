extends GdUnitTestSuite
## 账号面板（SGODOT-135）：五种状态、本地校验、登录墙关闭语义。

func _panel(mode := "sign_in", reason := "") -> AccountPanel:
	var p := AccountPanel.new()
	p.mode = mode
	p.reason = reason
	add_child(p)
	return p

func _visible_fields(p: AccountPanel) -> Array:
	var out := []
	for name in ["Email", "Password", "Code", "NewPassword"]:
		var f: Control = p.find_child(name, true, false)
		if f.visible: out.append(name)
	return out

func test_modes_show_only_their_fields() -> void:
	var p := _panel()
	assert_array(_visible_fields(p)).contains_exactly(["Email", "Password"])
	p.set_mode("forgot")
	assert_array(_visible_fields(p)).contains_exactly(["Email"])
	p._reset_code_sent = true
	p.set_mode("forgot")
	assert_array(_visible_fields(p)).contains_exactly(["Email", "Code", "NewPassword"])
	p.set_mode("verify")
	assert_array(_visible_fields(p)).contains_exactly(["Code"])
	p.queue_free()

func test_login_wall_reason_is_shown() -> void:
	var p := _panel("sign_up", "Sign in to create your farm.")
	var subtitle: Label = p._subtitle
	assert_str(subtitle.text).is_equal("Sign in to create your farm.")
	p.queue_free()

func test_local_validation_never_calls_the_server() -> void:
	var p := _panel("sign_up")
	(p.find_child("Email", true, false) as LineEdit).text = "not-an-email"
	await p._submit_login(true)
	assert_str((p.find_child("Status", true, false) as Label).text).is_equal("Enter a valid email address.")
	(p.find_child("Email", true, false) as LineEdit).text = "ada@example.com"
	(p.find_child("Password", true, false) as LineEdit).text = "short"
	await p._submit_login(true)
	assert_str((p.find_child("Status", true, false) as Label).text).is_equal("Use at least 8 characters for your password.")
	assert_bool(p.busy).is_false()
	p.queue_free()

func test_passwords_are_masked() -> void:
	var p := _panel()
	assert_bool((p.find_child("Password", true, false) as LineEdit).secret).is_true()
	assert_bool((p.find_child("NewPassword", true, false) as LineEdit).secret).is_true()
	assert_bool((p.find_child("Email", true, false) as LineEdit).secret).is_false()
	p.queue_free()

func test_closing_reports_guest_state() -> void:
	var p := _panel()
	var results := []
	p.closed.connect(func(v): results.append(v))
	p.dismiss()
	assert_array(results).is_equal([Net.account.signed_in()])

func test_panel_is_a_modal() -> void:
	var p := _panel()
	assert_bool(p.is_in_group(GameUi.MODAL_GROUP)).is_true()
	p.queue_free()
