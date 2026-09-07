extends AppPage
## 登录页（08-30 调研 §4.1）：邮箱 + 密码（注册 / 登录 / 找回密码，注册后发验证邮件）走 Firebase
## Identity Toolkit REST；Sign in with Apple / Google 的按钮等 C1 原生插件拿到 id_token 后调
## FirebaseAuth.sign_in_with_idp。不做短信。
##
## 说明：Firebase 没有「邮箱数字验证码」登录；邮箱链接登录需要 App Links / Universal Links 深链
## 插件，归 C1 之后评估。MVP 用密码 + 验证邮件。
##
## auth / firebase / navigate 可注入：测试不碰全局 Net.auth，也不真的切场景。

var auth: AuthSession
var firebase: FirebaseAuth
var navigate: Callable

var email: LineEdit
var password: LineEdit
var status: Label
var sign_in_button: Button
var sign_up_button: Button
var forgot_button: Button
var apple_button: Button
var google_button: Button
var dev_button: Button
var busy := false

func _init() -> void:
	page_title = "Sign in"

func _build_body() -> void:
	email = LineEdit.new()
	email.name = "Email"
	email.placeholder_text = tr("Email")
	email.custom_minimum_size.y = 44
	email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	body.add_child(email)
	password = LineEdit.new()
	password.name = "Password"
	password.placeholder_text = tr("Password (6+ characters)")
	password.secret = true
	password.custom_minimum_size.y = 44
	password.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	body.add_child(password)
	sign_in_button = GameUi.button("check", tr("Sign in"), "Firebase signInWithPassword", true)
	sign_in_button.name = "SignIn"
	sign_in_button.pressed.connect(_on_sign_in)
	body.add_child(sign_in_button)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	sign_up_button = GameUi.button("plus", tr("Create account"), "Firebase signUp + verification email")
	sign_up_button.name = "SignUp"
	sign_up_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sign_up_button.pressed.connect(_on_sign_up)
	row.add_child(sign_up_button)
	forgot_button = GameUi.button("", tr("Forgot password"), "Firebase sendOobCode PASSWORD_RESET")
	forgot_button.name = "Forgot"
	forgot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forgot_button.pressed.connect(_on_forgot)
	row.add_child(forgot_button)
	apple_button = GameUi.button("", tr("Continue with Apple"), "C1: Sign in with Apple plugin")
	apple_button.name = "Apple"
	apple_button.disabled = true
	body.add_child(apple_button)
	google_button = GameUi.button("", tr("Continue with Google"), "C1: Google Credential Manager plugin")
	google_button.name = "Google"
	google_button.disabled = true
	body.add_child(google_button)
	status = GameUi.label("", 12, GameUi.MUTED)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 32
	body.add_child(status)
	if OS.is_debug_build():
		dev_button = GameUi.button("footprints", tr("Dev: continue offline"), "Debug only: local session, no server")
		dev_button.name = "DevContinue"
		dev_button.pressed.connect(_on_dev_continue)
		body.add_child(dev_button)
	_refresh_enabled()

func _fb() -> FirebaseAuth:
	return firebase if firebase != null else Net.firebase

func _session() -> AuthSession:
	return auth if auth != null else Net.auth

func _refresh_enabled() -> void:
	var fb := _fb()
	var ready: bool = fb != null and fb.configured() and not busy
	sign_in_button.disabled = not ready
	sign_up_button.disabled = not ready
	forgot_button.disabled = not ready
	if fb == null or not fb.configured():
		status.text = tr("Sign-in is not configured yet (config/firebase.json).")

## 输入校验放客户端一层，省一次往返；真正的判定仍由 Firebase 做。
static func validate(p_email: String, p_password: String, need_password := true) -> String:
	var e := p_email.strip_edges()
	if e.is_empty() or not e.contains("@") or e.begins_with("@") or e.ends_with("@"):
		return "INVALID_EMAIL"
	if need_password and p_password.length() < 6:
		return "WEAK_PASSWORD"
	return ""

func _on_sign_in() -> void:
	await _password_flow(false)

func _on_sign_up() -> void:
	await _password_flow(true)

func _password_flow(create: bool) -> void:
	if busy:
		return
	var e := email.text.strip_edges()
	var p := password.text
	var invalid := validate(e, p)
	if not invalid.is_empty():
		status.text = FirebaseAuth.describe(invalid)
		return
	busy = true
	_refresh_enabled()
	status.text = tr("Creating account…") if create else tr("Signing in…")
	var s := _session()
	s.begin_sign_in()
	var r: Dictionary
	if create:
		r = await _fb().sign_up(e, p)
	else:
		r = await _fb().sign_in_with_password(e, p)
	if not bool(r.get("ok", false)):
		var code := str(r.get("code", "UNKNOWN"))
		s.fail_sign_in(code)
		status.text = FirebaseAuth.describe(code)
		busy = false
		_refresh_enabled()
		return
	if create:
		# 验证邮件发不出去不阻塞进壳；未验证状态由资料页与 UGC 门禁（E1）处理。
		await _fb().send_verification_email(str(r.id_token))
	s.complete_sign_in(str(r.user_id), str(r.id_token), str(r.refresh_token), int(r.expires_in_s), "password", str(r.email))
	busy = false
	status.text = tr("Verification email sent.") if create else ""
	_go()

func _on_forgot() -> void:
	if busy:
		return
	var e := email.text.strip_edges()
	var invalid := validate(e, "", false)
	if not invalid.is_empty():
		status.text = FirebaseAuth.describe(invalid)
		return
	busy = true
	_refresh_enabled()
	var r: Dictionary = await _fb().send_password_reset(e)
	busy = false
	_refresh_enabled()
	status.text = tr("Password reset email sent.") if bool(r.get("ok", false)) else FirebaseAuth.describe(str(r.get("code", "")))

func _on_dev_continue() -> void:
	_session().complete_sign_in("dev-local", "dev-token", "", 3600, "dev", "dev@local")
	_go()

func _go() -> void:
	if navigate.is_valid():
		navigate.call()
	else:
		AppRouter.go_to_shell()
