extends AppPage
## 登录页骨架（08-30 调研 §4.1：邮箱验证码 + Sign in with Apple + Google，不做短信）。
## B1 接 Firebase Identity Toolkit REST，C1 接原生 id_token；A1 只摆出结构，按钮先禁用。
## 调试构建有一条「Dev continue」直通壳，让路由 / Tab / 压栈在没有 Firebase 时也能走通。

var email: LineEdit
var code: LineEdit
var dev_button: Button

func _init() -> void:
	page_title = "Sign in"

func _build_body() -> void:
	email = LineEdit.new()
	email.name = "Email"
	email.placeholder_text = tr("Email")
	email.custom_minimum_size.y = 44
	body.add_child(email)
	code = LineEdit.new()
	code.name = "Code"
	code.placeholder_text = tr("Verification code")
	code.custom_minimum_size.y = 44
	body.add_child(code)
	var send := GameUi.button("", tr("Send code"), "B1: Firebase sendOobCode")
	send.name = "SendCode"
	send.disabled = true
	body.add_child(send)
	var sign_in := GameUi.button("check", tr("Sign in"), "B1: Firebase signInWithPassword", true)
	sign_in.name = "SignIn"
	sign_in.disabled = true
	body.add_child(sign_in)
	var apple := GameUi.button("", tr("Continue with Apple"), "C1: Sign in with Apple plugin")
	apple.name = "Apple"
	apple.disabled = true
	body.add_child(apple)
	var google := GameUi.button("", tr("Continue with Google"), "C1: Google Credential Manager plugin")
	google.name = "Google"
	google.disabled = true
	body.add_child(google)
	placeholder(tr("Sign-in wiring lands in B1 / C1. Buttons are disabled until then."))
	if OS.is_debug_build():
		dev_button = GameUi.button("footprints", tr("Dev: continue offline"), "Debug only: local session, no server")
		dev_button.name = "DevContinue"
		dev_button.pressed.connect(_on_dev_continue)
		body.add_child(dev_button)

func _on_dev_continue() -> void:
	Net.auth.complete_sign_in("dev-local", "dev-token", "", 3600, "dev")
	AppRouter.go_to_shell()
