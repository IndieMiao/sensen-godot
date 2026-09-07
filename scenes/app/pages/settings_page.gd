extends AppPage
## 设置（压栈子页）：语言 / 隐私政策 / 服务条款 / 联系我们 / 删除账号 / 登出。
## 政策与条款 OS.shell_open 跳外部浏览器（不做 WebView）；URL 在 LegalLinks，由 SSLAUNCH B2/B3/B6 提供。
## 删号（R1，Apple 5.1.1(v)）：确认 → Firebase accounts:delete → 本地登出 → 登录页。
## 服务端级联删除与 Apple token revocation 归 D2 账号服务，接口就位后在 _delete_account 里追加一步。

var auth: AuthSession
var firebase: FirebaseAuth
var navigate: Callable

var language_button: Button
var delete_button: Button
var status: Label
var confirm: ConfirmationDialog
var busy := false

func _init() -> void:
	page_title = "Settings"
	stacked = true

func _build_body() -> void:
	language_button = GameUi.button("book-open", "", "AppLocale")
	language_button.name = "Language"
	language_button.pressed.connect(_on_language)
	_refresh_language_label()
	body.add_child(language_button)
	_link(tr("Privacy policy"), LegalLinks.PRIVACY_URL, "Privacy")
	_link(tr("Terms of service"), LegalLinks.TERMS_URL, "Terms")
	var contact := GameUi.button("", tr("Contact us"), LegalLinks.SUPPORT_EMAIL if not LegalLinks.SUPPORT_EMAIL.is_empty() else "email pending (SSLAUNCH C6)")
	contact.name = "Contact"
	contact.disabled = LegalLinks.SUPPORT_EMAIL.is_empty()
	contact.pressed.connect(func(): LegalLinks.open("mailto:%s" % LegalLinks.SUPPORT_EMAIL))
	body.add_child(contact)
	delete_button = GameUi.button("x", tr("Delete account"), "Firebase accounts:delete + local sign-out")
	delete_button.name = "DeleteAccount"
	delete_button.pressed.connect(_on_delete_pressed)
	body.add_child(delete_button)
	var sign_out := GameUi.button("arrow-left", tr("Sign out"), "AuthSession.sign_out")
	sign_out.name = "SignOut"
	sign_out.pressed.connect(_on_sign_out)
	body.add_child(sign_out)
	status = GameUi.label("", 12, GameUi.MUTED)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	if OS.is_debug_build():
		var probe := GameUi.button("timer", tr("Dev: lifecycle probe"), "A6 iOS/Android lifecycle notifications")
		probe.name = "LifecycleProbe"
		probe.pressed.connect(func(): AppRouter.push_instance(AppRoutes.LIFECYCLE_PROBE))
		body.add_child(probe)
	confirm = ConfirmationDialog.new()
	confirm.name = "ConfirmDelete"
	confirm.title = tr("Delete account?")
	confirm.dialog_text = tr("This permanently deletes your account and data. This cannot be undone.")
	confirm.ok_button_text = tr("Delete")
	confirm.confirmed.connect(_on_delete_confirmed)
	add_child(confirm)

func _session() -> AuthSession:
	return auth if auth != null else Net.auth

func _fb() -> FirebaseAuth:
	return firebase if firebase != null else Net.firebase

func _link(text: String, url: String, node_name: String) -> void:
	var b := GameUi.button("book-open", text, url if not url.is_empty() else "URL pending (SSLAUNCH B2/B3)")
	b.name = node_name
	b.disabled = url.is_empty()
	b.pressed.connect(func(): LegalLinks.open(url))
	body.add_child(b)

func _refresh_language_label() -> void:
	language_button.text = tr("Language: %s") % AppLocale.display_name(AppLocale.current())

## 切语言后整壳重建：Godot 只会自动重译场景文件里的文本，代码里 tr() 赋的字串不会自己换。
func _on_language() -> void:
	AppLocale.apply(AppLocale.next(AppLocale.current()))
	_refresh_language_label()
	AppRouter.reload_shell()

func _on_delete_pressed() -> void:
	confirm.popup_centered()

func _on_delete_confirmed() -> void:
	await _delete_account()

## 返回是否删除成功。Dev 会话（provider=dev）没有 Firebase 账号，直接本地登出。
func _delete_account() -> bool:
	if busy:
		return false
	var s := _session()
	if s == null or not s.is_signed_in():
		_finish_sign_out()
		return true
	busy = true
	delete_button.disabled = true
	status.text = tr("Deleting account…")
	var ok := true
	if s.provider != "dev":
		var fb := _fb()
		var r: Dictionary = await fb.delete_account(s.access_token()) if fb != null else {"ok": false, "code": "NOT_CONFIGURED"}
		ok = bool(r.get("ok", false))
		if not ok:
			var code := str(r.get("code", ""))
			# CREDENTIAL_TOO_OLD_LOGIN_AGAIN：Firebase 要求近期登录过才能删号——提示重新登录再删。
			status.text = tr("Please sign in again, then delete your account.") if code == "CREDENTIAL_TOO_OLD_LOGIN_AGAIN" else FirebaseAuth.describe(code)
			busy = false
			delete_button.disabled = false
			return false
	# TODO(D2)：这里追加服务端级联删除（资料 / IM / feed / 位置 / 关注 / 推送 token）与 Apple token revocation。
	busy = false
	_finish_sign_out()
	return true

func _on_sign_out() -> void:
	_finish_sign_out()

func _finish_sign_out() -> void:
	var s := _session()
	if s != null:
		s.sign_out()
	if Net.ws != null:
		Net.ws.close()
	if navigate.is_valid():
		navigate.call(AppRoutes.LOGIN)
	else:
		AppRouter.go_to_login()
