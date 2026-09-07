extends AppPage
## 设置（压栈子页）：隐私政策 / 条款 / 联系我们 / 删除账号 / 登出。
## 政策与条款用 OS.shell_open 跳外部浏览器（不做 WebView）；URL 由 SSLAUNCH B2/B3/B6 提供。

const PRIVACY_URL := ""
const TERMS_URL := ""

func _init() -> void:
	page_title = "Settings"
	stacked = true

var language_button: Button

func _build_body() -> void:
	language_button = GameUi.button("book-open", "", "AppLocale")
	language_button.name = "Language"
	language_button.pressed.connect(_on_language)
	_refresh_language_label()
	body.add_child(language_button)
	_link(tr("Privacy policy"), PRIVACY_URL, "Privacy")
	_link(tr("Terms of service"), TERMS_URL, "Terms")
	var delete := GameUi.button("x", tr("Delete account"), "R1: not wired yet")
	delete.name = "DeleteAccount"
	delete.disabled = true
	body.add_child(delete)
	var sign_out := GameUi.button("arrow-left", tr("Sign out"), "AuthSession.sign_out")
	sign_out.name = "SignOut"
	sign_out.pressed.connect(_on_sign_out)
	body.add_child(sign_out)

func _link(text: String, url: String, node_name: String) -> void:
	var b := GameUi.button("book-open", text, url if not url.is_empty() else "URL pending (SSLAUNCH B2/B3)")
	b.name = node_name
	b.disabled = url.is_empty()
	b.pressed.connect(func(): OS.shell_open(url))
	body.add_child(b)

func _refresh_language_label() -> void:
	language_button.text = tr("Language: %s") % AppLocale.display_name(AppLocale.current())

## 切语言后整壳重建：Godot 只会自动重译场景文件里的文本，代码里 tr() 赋的字串不会自己换。
func _on_language() -> void:
	AppLocale.apply(AppLocale.next(AppLocale.current()))
	_refresh_language_label()
	AppRouter.reload_shell()

func _on_sign_out() -> void:
	Net.auth.sign_out()
	if Net.ws != null:
		Net.ws.close()
	AppRouter.go_to_login()
