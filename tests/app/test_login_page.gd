extends GdUnitTestSuite
## 登录页：输入校验、密码登录 / 注册 / 找回密码三条流、成功后写会话并导航、失败留在页面。
## auth / firebase / navigate 全部注入，不碰全局 Net.auth，也不真的切场景。

const LoginScript := preload("res://scenes/app/login_page.gd")

class NavRecorder extends RefCounted:
	var calls := 0
	func go() -> void:
		calls += 1

var nav: NavRecorder
var session: AuthSession
## D2 账号服务的假传输：默认没有脚本化响应（等于服务端不可达），单测里不能碰真网络。
var account_t: FakeTransport

func before_test() -> void:
	nav = NavRecorder.new()
	session = AuthSession.new()
	account_t = FakeTransport.new([])
	_cleanup()

func after_test() -> void:
	_cleanup()

func _cleanup() -> void:
	if FileAccess.file_exists(AuthSession.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthSession.PATH))

func _page(t: FakeTransport, api_key := "k") -> Control:
	var p := (load(AppRoutes.LOGIN) as PackedScene).instantiate()
	p.auth = session
	p.firebase = FirebaseAuth.new(api_key, t.callable())
	p.account = AccountApi.new(ApiClient.new("https://example.test/v1", account_t.callable()))
	p.navigate = nav.go
	add_child(auto_free(p))
	return p

func _session_json() -> Dictionary:
	return {"localId": "uid-1", "email": "a@b.co", "idToken": "id-1", "refreshToken": "rt-1", "expiresIn": "3600"}

func test_validate_is_pure() -> void:
	assert_str(LoginScript.validate("", "secret1")).is_equal("INVALID_EMAIL")
	assert_str(LoginScript.validate("nope", "secret1")).is_equal("INVALID_EMAIL")
	assert_str(LoginScript.validate("@x", "secret1")).is_equal("INVALID_EMAIL")
	assert_str(LoginScript.validate("a@b.co", "short")).is_equal("WEAK_PASSWORD")
	assert_str(LoginScript.validate("a@b.co", "", false)).is_empty()
	assert_str(LoginScript.validate(" a@b.co ", "secret1")).is_empty()

func test_unconfigured_firebase_disables_email_flow_and_explains() -> void:
	var p := _page(FakeTransport.new([]), "")
	assert_bool(p.sign_in_button.disabled).is_true()
	assert_bool(p.sign_up_button.disabled).is_true()
	assert_bool(p.forgot_button.disabled).is_true()
	assert_bool(p.status.text.contains("not configured")).is_true()
	assert_bool(p.apple_button.disabled).is_true()
	assert_bool(p.google_button.disabled).is_true()

func test_configured_firebase_enables_email_flow_and_keeps_idp_buttons_for_c1() -> void:
	var p := _page(FakeTransport.new([]))
	assert_bool(p.sign_in_button.disabled).is_false()
	assert_bool(p.sign_up_button.disabled).is_false()
	assert_bool(p.forgot_button.disabled).is_false()
	assert_bool(p.apple_button.disabled).is_true()
	assert_bool(p.google_button.disabled).is_true()

func test_invalid_input_never_hits_the_network() -> void:
	var t := FakeTransport.new([{"status": 200, "json": _session_json()}])
	var p := _page(t)
	p.email.text = "not-an-email"
	p.password.text = "secret1"
	await p._on_sign_in()
	assert_int(t.requests.size()).is_equal(0)
	assert_str(p.status.text).is_equal(FirebaseAuth.describe("INVALID_EMAIL"))
	p.email.text = "a@b.co"
	p.password.text = "123"
	await p._on_sign_in()
	assert_int(t.requests.size()).is_equal(0)
	assert_bool(session.is_signed_in()).is_false()
	assert_int(nav.calls).is_equal(0)

func test_successful_sign_in_completes_session_and_navigates() -> void:
	var t := FakeTransport.new([{"status": 200, "json": _session_json()}])
	var p := _page(t)
	p.email.text = " a@b.co "
	p.password.text = "secret1"
	await p._on_sign_in()
	assert_bool(session.is_signed_in()).is_true()
	assert_str(session.user_id).is_equal("uid-1")
	assert_str(session.email).is_equal("a@b.co")
	assert_str(session.provider).is_equal("password")
	assert_str(session.access_token()).is_equal("id-1")
	assert_int(nav.calls).is_equal(1)
	assert_bool(p.busy).is_false()
	assert_str(t.requests[0].body.email).is_equal("a@b.co")

func test_failed_sign_in_shows_message_and_stays_signed_out() -> void:
	var t := FakeTransport.new([{"status": 400, "json": {"error": {"message": "INVALID_PASSWORD"}}}])
	var p := _page(t)
	p.email.text = "a@b.co"
	p.password.text = "wrongpw"
	await p._on_sign_in()
	assert_bool(session.is_signed_in()).is_false()
	assert_int(session.state).is_equal(AuthSession.State.SIGNED_OUT)
	assert_str(session.last_error).is_equal("INVALID_PASSWORD")
	assert_str(p.status.text).is_equal(FirebaseAuth.describe("INVALID_PASSWORD"))
	assert_int(nav.calls).is_equal(0)
	assert_bool(p.sign_in_button.disabled).is_false() # 失败后按钮恢复可用

func test_sign_up_sends_verification_email_then_enters_shell() -> void:
	var t := FakeTransport.new([
		{"status": 200, "json": _session_json()},
		{"status": 200, "json": {"email": "a@b.co"}},
	])
	var p := _page(t)
	p.email.text = "a@b.co"
	p.password.text = "secret1"
	await p._on_sign_up()
	assert_int(t.requests.size()).is_equal(2)
	assert_bool(str(t.requests[0].url).contains("accounts:signUp")).is_true()
	assert_str(t.requests[1].body.requestType).is_equal("VERIFY_EMAIL")
	assert_bool(session.is_signed_in()).is_true()
	assert_int(nav.calls).is_equal(1)
	assert_bool(p.status.text.contains("Verification email")).is_true()

func test_transport_failure_is_reported_as_connection_problem() -> void:
	var t := FakeTransport.new([{"error": "timeout"}])
	var p := _page(t)
	p.email.text = "a@b.co"
	p.password.text = "secret1"
	await p._on_sign_in()
	assert_bool(p.status.text.contains("connection")).is_true()
	assert_int(nav.calls).is_equal(0)

func test_forgot_password_sends_reset_email_without_password() -> void:
	var t := FakeTransport.new([{"status": 200, "json": {"email": "a@b.co"}}])
	var p := _page(t)
	p.email.text = "a@b.co"
	await p._on_forgot()
	assert_int(t.requests.size()).is_equal(1)
	assert_str(t.requests[0].body.requestType).is_equal("PASSWORD_RESET")
	assert_bool(p.status.text.contains("reset email")).is_true()
	assert_bool(session.is_signed_in()).is_false()

func test_dev_continue_creates_local_session_in_debug_builds() -> void:
	var p := _page(FakeTransport.new([]), "")
	assert_object(p.dev_button).is_not_null()
	p._on_dev_continue()
	assert_bool(session.is_signed_in()).is_true()
	assert_str(session.provider).is_equal("dev")
	assert_int(nav.calls).is_equal(1)

## D2：登录成功后把 Firebase 身份映射到服务端自有 user id；服务端不可达不阻塞进壳。
func test_sign_in_links_server_account_and_stores_server_user_id() -> void:
	account_t.responses = [{"status": 201, "json": {"user_id": "srv-1", "created": true}}]
	var p := _page(FakeTransport.new([{"status": 200, "json": _session_json()}]))
	p.email.text = "a@b.co"
	p.password.text = "secret1"
	await p._on_sign_in()
	assert_str(session.server_user_id).is_equal("srv-1")
	assert_int(account_t.requests.size()).is_equal(1)
	assert_bool(str(account_t.requests[0].url).ends_with("/v1/auth/firebase")).is_true()
	assert_int(nav.calls).is_equal(1)

func test_sign_in_still_enters_shell_when_account_server_is_unreachable() -> void:
	account_t.responses = [{"error": "timeout"}]
	var p := _page(FakeTransport.new([{"status": 200, "json": _session_json()}]))
	p.email.text = "a@b.co"
	p.password.text = "secret1"
	await p._on_sign_in()
	assert_bool(session.is_signed_in()).is_true()
	assert_str(session.server_user_id).is_empty()
	assert_int(nav.calls).is_equal(1)
	assert_bool(p.busy).is_false()

func test_dev_continue_never_calls_the_account_server() -> void:
	if not OS.is_debug_build():
		return
	var p := _page(FakeTransport.new([]), "")
	p._on_dev_continue()
	await get_tree().process_frame
	assert_int(account_t.requests.size()).is_equal(0)
	assert_int(nav.calls).is_equal(1)
