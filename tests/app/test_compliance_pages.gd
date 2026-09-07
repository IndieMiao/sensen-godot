extends GdUnitTestSuite
## 年龄门页 / 同意页 / 设置页删号 / 我的页验证状态。全部注入 first_run / auth / firebase / navigate。

class NavRecorder extends RefCounted:
	var routes: Array = []
	func go(route: String) -> void:
		routes.append(route)

const TODAY := {"year": 2026, "month": 9, "day": 7}

var nav: NavRecorder
var fr: FirstRun
var session: AuthSession
## D2 服务端删号的假传输：默认一条成功响应；具体用例按需改 responses。
var account_t: FakeTransport
## D4 资料 API 的假传输：默认没有脚本化响应（服务端不可达）。
var profile_t: FakeTransport

func before_test() -> void:
	nav = NavRecorder.new()
	fr = FirstRun.new()
	session = AuthSession.new()
	account_t = FakeTransport.new([{"status": 200, "json": {"ok": true, "deleted": true}}])
	profile_t = FakeTransport.new([])
	FirstRun.clear()
	_clear_auth()

func after_test() -> void:
	FirstRun.clear()
	_clear_auth()

func _clear_auth() -> void:
	if FileAccess.file_exists(AuthSession.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthSession.PATH))

func _age_gate() -> Control:
	var p := (load(AppRoutes.AGE_GATE) as PackedScene).instantiate()
	p.first_run = fr
	p.today = TODAY
	p.navigate = nav.go
	add_child(auto_free(p))
	return p

func _pick(p: Control, y: int, m: int, d: int) -> void:
	p.year.select(p.year.get_item_index(y))
	p.month.select(p.month.get_item_index(m))
	p.day.select(p.day.get_item_index(d))

func test_age_gate_requires_full_date() -> void:
	var p := _age_gate()
	p._on_continue()
	assert_bool(p.status.text.contains("full date")).is_true()
	assert_array(nav.routes).is_empty()
	assert_bool(fr.age_gate_passed or fr.age_gate_blocked).is_false()

func test_age_gate_passes_at_exactly_thirteen_and_goes_to_consent() -> void:
	var p := _age_gate()
	_pick(p, 2013, 9, 7)
	p._on_continue()
	assert_bool(fr.age_gate_passed).is_true()
	assert_array(nav.routes).is_equal([AppRoutes.CONSENT])

func test_age_gate_blocks_under_thirteen_neutrally_and_persistently() -> void:
	var p := _age_gate()
	_pick(p, 2013, 9, 8)
	p._on_continue()
	assert_bool(fr.age_gate_blocked).is_true()
	assert_array(nav.routes).is_empty()
	assert_bool(p.continue_button.disabled).is_true()
	assert_bool(p.year.disabled).is_true()
	assert_bool(p.status.text.contains("13")).is_false() # 中立措辞不透露门槛
	# 重开页面（模拟重启）仍然被拒
	var again := _age_gate()
	assert_bool(again.continue_button.disabled).is_true()

func _consent() -> Control:
	var p := (load(AppRoutes.CONSENT) as PackedScene).instantiate()
	p.first_run = fr
	p.auth = session
	p.navigate = nav.go
	add_child(auto_free(p))
	return p

func test_consent_requires_checkbox_and_records_version() -> void:
	var p := _consent()
	assert_bool(p.continue_button.disabled).is_true()
	p._on_continue()
	assert_array(nav.routes).is_empty()
	p.agree.button_pressed = true
	assert_bool(p.continue_button.disabled).is_false()
	p._on_continue()
	assert_bool(fr.consent_current()).is_true()
	assert_array(nav.routes).is_equal([AppRoutes.LOGIN])

func test_consent_returns_to_shell_when_already_signed_in() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	var p := _consent()
	p.agree.button_pressed = true
	p._on_continue()
	assert_array(nav.routes).is_equal([AppRoutes.SHELL])

func test_consent_links_disabled_until_urls_are_provided() -> void:
	var p := _consent()
	assert_bool((p.find_child("Privacy", true, false) as Button).disabled).is_equal(not LegalLinks.has_privacy())
	assert_bool((p.find_child("Terms", true, false) as Button).disabled).is_equal(not LegalLinks.has_terms())

func _settings(t: FakeTransport, api_key := "k") -> Control:
	var p := (load(AppRoutes.SETTINGS) as PackedScene).instantiate()
	p.auth = session
	p.firebase = FirebaseAuth.new(api_key, t.callable())
	p.account = AccountApi.new(ApiClient.new("https://example.test/v1", account_t.callable()))
	p.navigate = nav.go
	add_child(auto_free(p))
	return p

func test_delete_account_calls_firebase_then_signs_out() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	var t := FakeTransport.new([{"status": 200, "json": {}}])
	var p := _settings(t)
	assert_bool(await p._delete_account()).is_true()
	assert_int(t.requests.size()).is_equal(1)
	assert_bool(str(t.requests[0].url).contains("accounts:delete")).is_true()
	assert_str(t.requests[0].body.idToken).is_equal("id-1")
	assert_bool(session.is_signed_in()).is_false()
	assert_array(nav.routes).is_equal([AppRoutes.LOGIN])

func test_delete_account_failure_keeps_session_and_explains() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	var t := FakeTransport.new([{"status": 400, "json": {"error": {"message": "CREDENTIAL_TOO_OLD_LOGIN_AGAIN"}}}])
	var p := _settings(t)
	assert_bool(await p._delete_account()).is_false()
	assert_bool(session.is_signed_in()).is_true()
	assert_bool(p.status.text.contains("sign in again")).is_true()
	assert_bool(p.delete_button.disabled).is_false()
	assert_array(nav.routes).is_empty()

## D2：先服务端级联再 Firebase——服务端要靠还有效的 ID token 认人。
func test_delete_account_cascades_on_server_before_firebase() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	var t := FakeTransport.new([{"status": 200, "json": {}}])
	var p := _settings(t)
	assert_bool(await p._delete_account()).is_true()
	assert_int(account_t.requests.size()).is_equal(1)
	assert_str(account_t.requests[0].method).is_equal("DELETE")
	assert_bool(str(account_t.requests[0].url).ends_with("/v1/users/me")).is_true()
	assert_int(t.requests.size()).is_equal(1)
	assert_array(nav.routes).is_equal([AppRoutes.LOGIN])

func test_server_delete_failure_blocks_firebase_delete_and_keeps_session() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	account_t.responses = [{"error": "timeout"}]
	var t := FakeTransport.new([{"status": 200, "json": {}}])
	var p := _settings(t)
	assert_bool(await p._delete_account()).is_false()
	assert_int(t.requests.size()).is_equal(0) # 服务端还留着数据时绝不能先删 Firebase 账号
	assert_bool(session.is_signed_in()).is_true()
	assert_bool(p.status.text.contains("server")).is_true()
	assert_bool(p.delete_button.disabled).is_false()
	assert_array(nav.routes).is_empty()

func test_old_server_or_unconfigured_accounts_do_not_block_delete() -> void:
	for resp in [{"status": 404, "json": {"message": "Route DELETE:/v1/users/me not found"}}, {"status": 503, "json": {"code": "ACCOUNTS_NOT_CONFIGURED"}}]:
		before_test()
		session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
		account_t.responses = [resp]
		var t := FakeTransport.new([{"status": 200, "json": {}}])
		var p := _settings(t)
		assert_bool(await p._delete_account()).override_failure_message(str(resp)).is_true()
		assert_int(t.requests.size()).is_equal(1)
		assert_bool(session.is_signed_in()).is_false()

func test_delete_dev_session_skips_firebase() -> void:
	session.complete_sign_in("dev-local", "dev-token", "", 3600, "dev", "dev@local")
	var t := FakeTransport.new([])
	var p := _settings(t, "")
	assert_bool(await p._delete_account()).is_true()
	assert_int(t.requests.size()).is_equal(0)
	assert_int(account_t.requests.size()).is_equal(0)
	assert_bool(session.is_signed_in()).is_false()
	assert_array(nav.routes).is_equal([AppRoutes.LOGIN])

func test_sign_out_clears_session_and_navigates() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	var p := _settings(FakeTransport.new([]))
	p._on_sign_out()
	assert_bool(session.is_signed_in()).is_false()
	assert_array(nav.routes).is_equal([AppRoutes.LOGIN])

func _profile(t: FakeTransport, api_key := "k") -> Control:
	var p := (load(AppRoutes.tab_scene("profile")) as PackedScene).instantiate()
	p.auth = session
	p.firebase = FirebaseAuth.new(api_key, t.callable())
	p.profile = ProfileApi.new(ApiClient.new("https://example.test/v1", profile_t.callable()))
	add_child(auto_free(p))
	return p

func test_profile_shows_verification_state_and_resends() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	var t := FakeTransport.new([
		{"status": 200, "json": {"users": [{"localId": "u1", "email": "a@b.co", "emailVerified": false}]}},
		{"status": 200, "json": {"email": "a@b.co"}},
	])
	var p := _profile(t)
	assert_bool(p.user_label.text.contains("a@b.co")).is_true()
	await p.refresh_verification()
	assert_str(p.verify_label.text).is_equal("Email not verified")
	assert_bool(p.resend_button.visible).is_true()
	await p._on_resend()
	assert_str(t.requests[1].body.requestType).is_equal("VERIFY_EMAIL")
	assert_str(p.verify_label.text).is_equal("Verification email sent.")

func test_profile_hides_verification_for_verified_or_non_password_sessions() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	var t := FakeTransport.new([{"status": 200, "json": {"users": [{"localId": "u1", "emailVerified": true}]}}])
	var p := _profile(t)
	await p.refresh_verification()
	assert_str(p.verify_label.text).is_equal("Email verified")
	assert_bool(p.resend_button.visible).is_false()
	session.sign_out()
	session.complete_sign_in("dev-local", "dev-token", "", 3600, "dev", "dev@local")
	var q := _profile(FakeTransport.new([]), "")
	await q.refresh_verification()
	assert_str(q.verify_label.text).is_empty()
	assert_bool(q.resend_button.visible).is_false()

## D4-a：资料页从服务端拉自己的资料并填进编辑框；保存整体提交；handle 冲突与字段错误有提示。
func _profile_json() -> Dictionary:
	return {"user_id": "srv-1", "display_name": "Sen", "handle": "sen_01", "bio": "hi", "followers_count": 3, "following_count": 2, "new_followers_unread": 1}

func test_profile_loads_server_profile_into_card_and_fields() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	profile_t.responses = [{"status": 200, "json": _profile_json()}]
	var p := _profile(FakeTransport.new([]))
	await p.refresh_profile()
	assert_bool(str(profile_t.requests[0].url).ends_with("/v1/users/me/profile")).is_true()
	assert_str(p.profile_label.text).is_equal("Sen @sen_01 · 3 followers · 2 following")
	assert_str(p.name_edit.text).is_equal("Sen")
	assert_str(p.handle_edit.text).is_equal("sen_01")
	assert_str(p.bio_edit.text).is_equal("hi")

func test_profile_save_sends_patch_and_explains_handle_conflict() -> void:
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	var saved := _profile_json()
	saved["display_name"] = "Sen Two"
	saved["handle"] = null
	profile_t.responses = [{"status": 200, "json": saved}, {"status": 409, "json": {"code": "HANDLE_TAKEN"}}]
	var p := _profile(FakeTransport.new([]))
	p.name_edit.text = " Sen Two "
	p.handle_edit.text = ""
	p.bio_edit.text = "bio"
	p.visible_toggle.button_pressed = false
	assert_bool(await p.save_profile()).is_true()
	assert_str(profile_t.requests[0].method).is_equal("PUT")
	assert_that(profile_t.requests[0].body).is_equal({"display_name": "Sen Two", "bio": "bio", "handle": null, "following_visible": false})
	assert_str(p.profile_label.text).is_equal("Sen Two · 3 followers · 2 following")
	assert_str(p.profile_status.text).is_equal("Profile saved.")
	p.handle_edit.text = "@Taken"
	assert_bool(await p.save_profile()).is_false()
	assert_str(profile_t.requests[1].body.handle).is_equal("taken")
	assert_str(p.profile_status.text).is_equal("That handle is already taken.")
	assert_bool(p.save_button.disabled).is_false()

func test_profile_refresh_is_silent_for_dev_sessions_and_unreachable_server() -> void:
	session.complete_sign_in("dev-local", "dev-token", "", 3600, "dev", "dev@local")
	var p := _profile(FakeTransport.new([]), "")
	await p.refresh_profile()
	assert_int(profile_t.requests.size()).is_equal(0)
	session.sign_out()
	session.complete_sign_in("u1", "id-1", "rt-1", 3600, "password", "a@b.co")
	profile_t.responses = [{"error": "timeout"}, {"status": 404, "json": {"code": "NO_ACCOUNT"}}]
	var q := _profile(FakeTransport.new([]))
	await q.refresh_profile()
	assert_str(q.profile_label.text).is_empty()
	await q.refresh_profile()
	assert_bool(q.profile_status.text.contains("Sign in again")).is_true()
	assert_str(q.describe_save_error({"code": "SCHEMA", "field": "bio"})).is_equal("Please check the bio field.")
	assert_str(q.describe_save_error({"code": "NETWORK"})).contains("connection")

## 拦截后 debug 构建给一个重置入口；重置后可重新选择并继续。
func test_blocked_age_gate_offers_dev_reset_in_debug_builds() -> void:
	if not OS.is_debug_build():
		return
	var p := _age_gate()
	_pick(p, 2026, 1, 1)
	p._on_continue()
	assert_bool(p.continue_button.disabled).is_true()
	var reset: Button = p.find_child("DevReset", true, false)
	assert_bool(reset != null).is_true()
	p._on_dev_reset()
	await get_tree().process_frame
	assert_bool(p.continue_button.disabled).is_false()
	assert_bool(p.year.disabled).is_false()
	assert_bool(FirstRun.load_state().age_gate_blocked).is_false()
	_pick(p, 2000, 1, 1)
	p._on_continue()
	assert_array(nav.routes).is_equal([AppRoutes.CONSENT])

func test_age_gate_clears_hint_once_a_date_is_picked() -> void:
	var p := _age_gate()
	p._on_continue()
	assert_bool(p.status.text.contains("full date")).is_true()
	_pick(p, 2000, 1, 1)
	# OptionButton.select() 不发 item_selected；真机上是用户点选触发，这里手动发信号走同一条线。
	p.year.item_selected.emit(p.year.selected)
	assert_str(p.status.text).is_empty()

## 真机截图（2026-09-07）：语言按钮的图标压在文字上——建按钮时文字为空导致图标居中。
func test_settings_language_button_keeps_icon_left_of_text() -> void:
	var p := _settings(FakeTransport.new([]))
	assert_bool(p.language_button.text.begins_with("Language: ")).is_true()
	assert_int(p.language_button.icon_alignment).is_equal(HORIZONTAL_ALIGNMENT_LEFT)
