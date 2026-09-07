extends AppPage
## 我的主页（B4 部分）：会话信息 + 邮箱验证状态（Firebase lookup）+ 重发验证邮件；
## 资料卡 / 编辑 / 形象上传等待 D2 / D4 后端接口就位后接入。设置与语音房从这里压栈。

var auth: AuthSession
var firebase: FirebaseAuth

var user_label: Label
var verify_label: Label
var resend_button: Button
var email_verified := false

func _init() -> void:
	page_title = "Me"

func _build_body() -> void:
	user_label = GameUi.label("", 14)
	user_label.name = "User"
	body.add_child(user_label)
	verify_label = GameUi.label("", 12, GameUi.MUTED)
	verify_label.name = "Verify"
	body.add_child(verify_label)
	resend_button = GameUi.button("", tr("Resend verification email"), "Firebase sendOobCode VERIFY_EMAIL")
	resend_button.name = "Resend"
	resend_button.visible = false
	resend_button.pressed.connect(_on_resend)
	body.add_child(resend_button)
	_refresh_user()
	if _session() != null:
		_session().changed.connect(func(_s): _refresh_user())
	placeholder(tr("Profile lands in B4: profile card, edit, avatar entry, Space 3D."))
	var dress := GameUi.button("shirt", tr("Dressing room"), "avatar module (existing)")
	dress.name = "Dressing"
	dress.pressed.connect(AppRouter.go_to_dressing)
	body.add_child(dress)
	var voice := GameUi.button("users-round", tr("Voice room"), "B6")
	voice.name = "VoiceRoom"
	voice.pressed.connect(func(): AppRouter.push_instance(AppRoutes.VOICE_ROOM))
	body.add_child(voice)
	var settings := GameUi.button("list-checks", tr("Settings"), "R1/R2/R3")
	settings.name = "Settings"
	settings.pressed.connect(func(): AppRouter.push_instance(AppRoutes.SETTINGS))
	body.add_child(settings)

func _session() -> AuthSession:
	return auth if auth != null else Net.auth

func _fb() -> FirebaseAuth:
	return firebase if firebase != null else Net.firebase

func _refresh_user() -> void:
	var s := _session()
	if s == null or not s.is_signed_in():
		user_label.text = tr("Not signed in")
		verify_label.text = ""
		resend_button.visible = false
		return
	user_label.text = tr("Signed in as %s (%s)") % [s.email if not s.email.is_empty() else s.user_id, s.provider]

## Tab 显示时拉一次验证状态（password 提供方才有意义）。
func on_tab_shown() -> void:
	super()
	await refresh_verification()

func refresh_verification() -> void:
	var s := _session()
	var fb := _fb()
	if s == null or not s.is_signed_in() or s.provider != "password" or fb == null or not fb.configured():
		verify_label.text = ""
		resend_button.visible = false
		return
	var info: Dictionary = await fb.lookup(s.access_token())
	if not bool(info.get("ok", false)):
		return
	email_verified = bool(info.get("email_verified", false))
	verify_label.text = tr("Email verified") if email_verified else tr("Email not verified")
	resend_button.visible = not email_verified

func _on_resend() -> void:
	var s := _session()
	var fb := _fb()
	if s == null or fb == null:
		return
	resend_button.disabled = true
	var r: Dictionary = await fb.send_verification_email(s.access_token())
	verify_label.text = tr("Verification email sent.") if bool(r.get("ok", false)) else FirebaseAuth.describe(str(r.get("code", "")))
	resend_button.disabled = false
