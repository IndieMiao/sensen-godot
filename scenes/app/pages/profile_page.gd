extends AppPage
## 我的主页占位：B4 资料 / 编辑 / avatar 入口 / Space 3D；设置与语音房从这里压栈。

var user_label: Label

func _init() -> void:
	page_title = "Me"

func _build_body() -> void:
	user_label = GameUi.label("", 14)
	user_label.name = "User"
	body.add_child(user_label)
	_refresh_user()
	if Net.auth != null:
		Net.auth.changed.connect(func(_s): _refresh_user())
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

func _refresh_user() -> void:
	if Net.auth == null or not Net.auth.is_signed_in():
		user_label.text = tr("Not signed in")
	else:
		user_label.text = tr("Signed in as %s (%s)") % [Net.auth.user_id, Net.auth.provider]
