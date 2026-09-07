extends AppPage
## 我的主页（B4 部分）：会话信息 + 邮箱验证状态（Firebase lookup）+ 重发验证邮件 +
## 资料卡与编辑（D4-a：昵称 / handle / 简介，服务端 /users/me/profile）。形象上传等 R2（D4-c）。
## 设置与语音房从这里压栈。auth / firebase / profile 可注入。

var auth: AuthSession
var firebase: FirebaseAuth
var profile: ProfileApi

var user_label: Label
var verify_label: Label
var resend_button: Button
var email_verified := false

var profile_label: Label
var name_edit: LineEdit
var handle_edit: LineEdit
var bio_edit: LineEdit
var save_button: Button
var profile_status: Label
## 最近一次从服务端拿到的资料；空字典表示还没拿到。
var loaded: Dictionary = {}
var saving := false

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
	profile_label = GameUi.label("", 14)
	profile_label.name = "ProfileCard"
	profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(profile_label)
	name_edit = _field("DisplayName", tr("Display name"), 30)
	handle_edit = _field("Handle", tr("Handle (letters, numbers, _)"), 20)
	bio_edit = _field("Bio", tr("Bio"), 160)
	save_button = GameUi.button("check", tr("Save profile"), "PUT /users/me/profile")
	save_button.name = "SaveProfile"
	save_button.pressed.connect(_on_save)
	body.add_child(save_button)
	profile_status = GameUi.label("", 12, GameUi.MUTED)
	profile_status.name = "ProfileStatus"
	profile_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(profile_status)
	placeholder(tr("Avatar upload and Space 3D land later in B4."))
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

func _profile_api() -> ProfileApi:
	return profile if profile != null else Net.profile

func _field(node_name: String, placeholder_text: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.name = node_name
	e.placeholder_text = placeholder_text
	e.max_length = max_len
	e.custom_minimum_size.y = 44
	body.add_child(e)
	return e

func _refresh_user() -> void:
	var s := _session()
	if s == null or not s.is_signed_in():
		user_label.text = tr("Not signed in")
		verify_label.text = ""
		resend_button.visible = false
		return
	user_label.text = tr("Signed in as %s (%s)") % [s.email if not s.email.is_empty() else s.user_id, s.provider]

## Tab 显示时拉一次验证状态（password 提供方才有意义）与服务端资料。
func on_tab_shown() -> void:
	super()
	await refresh_verification()
	await refresh_profile()

## 从服务端拉自己的资料。Dev 会话没有真 token；服务端没部署 / 断网时保留上次内容，不报错刷屏。
func refresh_profile() -> void:
	var s := _session()
	var api := _profile_api()
	if s == null or not s.is_signed_in() or s.provider == "dev" or api == null:
		return
	var r: Dictionary = await api.me()
	if bool(r.get("ok", false)):
		loaded = r
		_show_profile(r)
	elif str(r.get("code", "")) == "NO_ACCOUNT":
		profile_status.text = tr("Sign in again to set up your profile.")

static func _text(v: Variant) -> String:
	return "" if v == null else str(v)

func _show_profile(p: Dictionary) -> void:
	var name := _text(p.get("display_name", ""))
	var handle := _text(p.get("handle", ""))
	var who := name if handle.is_empty() else "%s @%s" % [name, handle]
	profile_label.text = tr("%s · %d followers · %d following") % [who, int(p.get("followers_count", 0)), int(p.get("following_count", 0))]
	name_edit.text = name
	handle_edit.text = handle
	bio_edit.text = _text(p.get("bio", ""))

## 把三个输入框整体提交；handle 空则清空（null）。返回是否保存成功。
func save_profile() -> bool:
	var api := _profile_api()
	if api == null or saving:
		return false
	var handle := handle_edit.text.strip_edges().trim_prefix("@").to_lower()
	var patch := {
		"display_name": name_edit.text.strip_edges(),
		"bio": bio_edit.text.strip_edges(),
		"handle": handle if not handle.is_empty() else null,
	}
	saving = true
	save_button.disabled = true
	profile_status.text = tr("Saving…")
	var r: Dictionary = await api.update(patch)
	saving = false
	save_button.disabled = false
	if bool(r.get("ok", false)):
		loaded = r
		_show_profile(r)
		profile_status.text = tr("Profile saved.")
		return true
	profile_status.text = describe_save_error(r)
	return false

func describe_save_error(r: Dictionary) -> String:
	match str(r.get("code", "")):
		"HANDLE_TAKEN":
			return tr("That handle is already taken.")
		"SCHEMA":
			return tr("Please check the %s field.") % str(r.get("field", ""))
		"NETWORK":
			return tr("Can't reach the server. Check your connection and try again.")
		_:
			return str(r.get("code", "UNKNOWN"))

func _on_save() -> void:
	await save_profile()

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
