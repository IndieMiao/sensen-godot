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
var avatar_thumb: AvatarThumb
var followers_button: Button
var following_button: Button
var new_followers_button: Button
var avatar_api: Node
var name_edit: LineEdit
var handle_edit: LineEdit
var bio_edit: LineEdit
var visible_toggle: CheckButton
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
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 10)
	avatar_thumb = AvatarThumb.new(64.0)
	avatar_thumb.name = "Avatar"
	head.add_child(avatar_thumb)
	profile_label = GameUi.label("", 14)
	profile_label.name = "ProfileCard"
	profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profile_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(profile_label)
	body.add_child(head)
	var counts_row := HBoxContainer.new()
	counts_row.name = "CountsRow"
	counts_row.add_theme_constant_override("separation", 8)
	followers_button = GameUi.button("", tr("Followers"), "GET /users/me/followers")
	followers_button.name = "Followers"
	followers_button.theme_type_variation = &"SecondaryButton"
	followers_button.pressed.connect(func(): open_follow_list(FollowListPage.KIND_FOLLOWERS))
	counts_row.add_child(followers_button)
	following_button = GameUi.button("", tr("Following"), "GET /users/me/following")
	following_button.name = "Following"
	following_button.theme_type_variation = &"SecondaryButton"
	following_button.pressed.connect(func(): open_follow_list(FollowListPage.KIND_FOLLOWING))
	counts_row.add_child(following_button)
	new_followers_button = GameUi.button("", tr("New followers"), "GET /users/me/new-followers")
	new_followers_button.name = "NewFollowers"
	new_followers_button.theme_type_variation = &"SecondaryButton"
	new_followers_button.visible = false
	new_followers_button.pressed.connect(func(): open_follow_list(FollowListPage.KIND_NEW))
	counts_row.add_child(new_followers_button)
	body.add_child(counts_row)
	name_edit = _field("DisplayName", tr("Display name"), 30)
	handle_edit = _field("Handle", tr("Handle (letters, numbers, _)"), 20)
	bio_edit = _field("Bio", tr("Bio"), 160)
	# Follow v1.2 §隐私：关注列表默认公开，可关；关注者列表永远公开。
	visible_toggle = CheckButton.new()
	visible_toggle.name = "FollowingVisible"
	visible_toggle.text = tr("Show who I follow")
	visible_toggle.button_pressed = true
	body.add_child(visible_toggle)
	save_button = GameUi.button("check", tr("Save profile"), "PUT /users/me/profile")
	save_button.name = "SaveProfile"
	save_button.pressed.connect(_on_save)
	body.add_child(save_button)
	profile_status = GameUi.label("", 12, GameUi.MUTED)
	profile_status.name = "ProfileStatus"
	profile_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(profile_status)
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
	# 键盘上的「完成 / 换行」= 收键盘：资料字段没有提交动作，失焦即可。
	e.text_submitted.connect(func(_t): e.release_focus())
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
		await sync_avatar(r)
	elif str(r.get("code", "")) == "NO_ACCOUNT":
		profile_status.text = tr("Sign in again to set up your profile.")

## B7 装扮双向对齐：服务端没有而本地有 → 推上去（老用户第一次登录海外版）；
## 服务端有而本地没有 → 落地（换机 / 重装）。两边都有以服务端为准不动本地——换装房保存时已同步。
## 返回 "pushed" / "adopted" / ""。
func sync_avatar(p: Dictionary) -> String:
	var av := _avatar()
	var api := _profile_api()
	if av == null or api == null:
		return ""
	var remote: Variant = p.get("avatar")
	var remote_has := remote is Dictionary and not (remote as Dictionary).is_empty()
	if not remote_has and av.has_saved_outfit():
		var r: Dictionary = await api.update({"avatar": av.outfit_dict()})
		if bool(r.get("ok", false)):
			loaded = r
			_show_profile(r)
			return "pushed"
		return ""
	if remote_has and not av.has_saved_outfit():
		return "adopted" if av.adopt_outfit(remote) == OK else ""
	return ""

func _avatar() -> Node:
	return avatar_api if avatar_api != null else get_node_or_null("/root/Avatar")

func open_follow_list(kind: String) -> void:
	var s := _session()
	var me := s.server_user_id if s != null else ""
	if me.is_empty() and kind != FollowListPage.KIND_NEW:
		return
	AppRouter.push_instance(AppRoutes.FOLLOW_LIST, {"user_id": me, "kind": kind})

static func _text(v: Variant) -> String:
	return "" if v == null else str(v)

func _show_profile(p: Dictionary) -> void:
	var name := _text(p.get("display_name", ""))
	var handle := _text(p.get("handle", ""))
	var who := name if handle.is_empty() else "%s @%s" % [name, handle]
	profile_label.text = who
	avatar_thumb.show_avatar(p.get("avatar"))
	followers_button.text = tr("%d followers") % int(p.get("followers_count", 0))
	following_button.text = tr("%d following") % int(p.get("following_count", 0))
	var unread := int(p.get("new_followers_unread", 0)) if p.get("new_followers_unread") != null else 0
	new_followers_button.visible = unread > 0
	new_followers_button.text = tr("%d new") % unread
	name_edit.text = name
	handle_edit.text = handle
	bio_edit.text = _text(p.get("bio", ""))
	visible_toggle.button_pressed = bool(p.get("following_visible", true)) if p.get("following_visible") != null else true

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
		"following_visible": visible_toggle.button_pressed,
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
