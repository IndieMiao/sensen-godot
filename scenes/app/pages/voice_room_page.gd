extends AppPage
## B6 语音房（压栈子页）：房间列表 / 建房 / 麦位 / 上下麦 / 静音 / 音量 / 说话人指示 / 举报。
##
## 能不能说话由服务端签的 LiveKit token 决定（D5）：上下麦、被静音、续期都会换一把新 token，
## 页面拿到就重连桥。原生桥（C4）没装时进只读模式——列表与麦位照看，麦克风按钮禁用并说明原因。
## voice / safety / bridge / navigate 可注入。

var auth: AuthSession
var voice: VoiceApi
var safety: SafetyApi
var bridge: VoiceBridge
var navigate: Callable

var status: Label
var title_edit: LineEdit
var create_button: Button
var list: VBoxContainer
var list_scroll: ScrollContainer
var new_room_row: HBoxContainer
var room_panel: VBoxContainer
var room_title: Label
var stage: VBoxContainer
var mic_button: Button
var leave_button: Button
var report_menu: PopupMenu

var rooms: Array = []
var room: Dictionary = {}
var busy := false
var mic_on := false
var speaking: Dictionary = {}
var pending_report := ""

func _init() -> void:
	page_title = "Voice room"
	stacked = true

func _build_body() -> void:
	status = GameUi.label("", DesignTokens.UI_FONT_CAPTION, GameUi.MUTED)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	var row := HBoxContainer.new()
	row.name = "NewRoom"
	row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	title_edit = LineEdit.new()
	title_edit.name = "Title"
	title_edit.placeholder_text = tr("Room name")
	title_edit.max_length = 40
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_edit.custom_minimum_size.y = DesignTokens.UI_TOUCH_MIN
	title_edit.text_submitted.connect(func(_t): create_room())
	row.add_child(title_edit)
	create_button = GameUi.button("", tr("Start"), "POST /voice/rooms", true)
	create_button.name = "Create"
	create_button.pressed.connect(func(): create_room())
	row.add_child(create_button)
	body.add_child(row)
	new_room_row = row
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	body.add_child(scroll)
	list_scroll = scroll

	room_panel = VBoxContainer.new()
	room_panel.name = "Room"
	room_panel.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	room_panel.visible = false
	room_title = GameUi.label("", DesignTokens.UI_FONT_LEAD)
	room_title.name = "RoomTitle"
	room_panel.add_child(room_title)
	stage = VBoxContainer.new()
	stage.name = "Stage"
	stage.add_theme_constant_override("separation", DesignTokens.SPACE_1)
	room_panel.add_child(stage)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	mic_button = GameUi.button("", tr("Take the mic"), "POST /voice/rooms/:id/stage")
	mic_button.name = "Mic"
	mic_button.pressed.connect(func(): toggle_stage())
	actions.add_child(mic_button)
	leave_button = GameUi.button("", tr("Leave"), "POST /voice/rooms/:id/leave")
	leave_button.name = "Leave"
	leave_button.pressed.connect(func(): leave())
	actions.add_child(leave_button)
	room_panel.add_child(actions)
	body.add_child(room_panel)

	report_menu = PopupMenu.new()
	report_menu.name = "ReportMenu"
	for i in SafetyApi.REASONS.size():
		report_menu.add_item(reason_label(SafetyApi.REASONS[i]), i)
	report_menu.id_pressed.connect(_on_report_reason)
	add_child(report_menu)

	if bridge == null:
		bridge = VoiceBridgeFactory.make()
	if bridge != null:
		bridge.connected.connect(func(): _refresh_mic_label())
		bridge.disconnected.connect(func(reason: String): status.text = describe_disconnect(reason))
		bridge.speaking_changed.connect(_on_speaking)
	call_deferred("fetch_rooms")

func _voice() -> VoiceApi:
	if voice != null:
		return voice
	return Net.voice if get_node_or_null("/root/Net") != null else null

func _safety() -> SafetyApi:
	if safety != null:
		return safety
	return Net.safety if get_node_or_null("/root/Net") != null else null

func _session() -> AuthSession:
	if auth != null:
		return auth
	var net := get_node_or_null("/root/Net")
	return net.auth if net != null else null

func my_id() -> String:
	var s := _session()
	return s.server_user_id if s != null else ""

static func _text(v: Variant) -> String:
	return "" if v == null else str(v)

## 房间列表。名字不叫 load：会覆盖全局的 load(path)，同一个类里再用就报参数不足。
func fetch_rooms() -> bool:
	var api := _voice()
	if api == null or busy:
		return false
	busy = true
	var r: Dictionary = await api.rooms()
	busy = false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	rooms = r.get("items", []) if r.get("items") is Array else []
	_render_list()
	return true

func _render_list() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.free()
	for item in rooms:
		if item is Dictionary:
			list.add_child(_room_row(item))
	if rooms.is_empty() and status.text.is_empty():
		status.text = tr("No rooms yet. Start one.")

func _room_row(r: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Room_%s" % _text(r.get("id", ""))
	b.theme_type_variation = &"SecondaryButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 56
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "%s\n%s · %s" % [_text(r.get("title", "")),
		tr("Host: %s") % _text(r.get("host_name", "")),
		tr("%d listening") % int(r.get("member_count", 0))]
	b.pressed.connect(func(): join(_text(r.get("id", ""))))
	return b

func join(room_id: String) -> bool:
	var api := _voice()
	if api == null or room_id.is_empty() or busy:
		return false
	busy = true
	var r: Dictionary = await api.join(room_id)
	busy = false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	_enter(r)
	_track("voice_room_joined")
	return true

func create_room() -> bool:
	var api := _voice()
	var title := title_edit.text.strip_edges()
	if api == null or busy:
		return false
	if title.is_empty():
		status.text = tr("Give the room a name.")
		return false
	busy = true
	var r: Dictionary = await api.create_room(title)
	busy = false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	title_edit.text = ""
	_enter(r)
	_track("voice_room_joined")
	return true

## 进房 / 状态更新：换 token 就重连桥（能不能说话以 token 为准）。
func _enter(state: Dictionary) -> void:
	var was := _text(room.get("token", ""))
	room = state
	# 在房间里就只看房间：列表与建房行让位，免得房间信息被空列表挤到屏幕最底下（真机复查）。
	room_panel.visible = true
	room_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.visible = false
	new_room_row.visible = false
	room_title.text = _text(room.get("title", ""))
	status.text = ""
	_render_stage()
	_refresh_mic_label()
	var token := _text(room.get("token", ""))
	if bridge != null and not token.is_empty() and token != was:
		bridge.connect_room(_text(room.get("livekit_url", "")), token)

func members() -> Array:
	return room.get("members", []) if room.get("members") is Array else []

func me_role() -> String:
	var me: Dictionary = room.get("me", {}) if room.get("me") is Dictionary else {}
	return _text(me.get("role", ""))

func is_host() -> bool:
	return _text(room.get("host_id", "")) == my_id()

func can_speak() -> bool:
	var me: Dictionary = room.get("me", {}) if room.get("me") is Dictionary else {}
	return me_role() != "listener" and not bool(me.get("muted", false))

func _render_stage() -> void:
	for c in stage.get_children():
		stage.remove_child(c)
		c.free()
	for m in members():
		if m is Dictionary:
			stage.add_child(_member_row(m))

func _member_row(m: Dictionary) -> HBoxContainer:
	var uid := _text(m.get("user_id", ""))
	var row := HBoxContainer.new()
	row.name = "Member_%s" % uid
	row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	var marks: Array = []
	if _text(m.get("role", "")) == "host":
		marks.append(tr("Host"))
	elif _text(m.get("role", "")) == "speaker":
		marks.append(tr("On mic"))
	if bool(m.get("muted", false)):
		marks.append(tr("Muted"))
	if bool(speaking.get(uid, false)):
		marks.append(tr("Speaking"))
	var name := GameUi.label("%s%s" % [_text(m.get("display_name", "")),
		"  " + " · ".join(marks) if not marks.is_empty() else ""], DesignTokens.UI_FONT_BODY)
	name.name = "Name"
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	if uid != my_id():
		if is_host():
			var mute := GameUi.button("", tr("Unmute") if bool(m.get("muted", false)) else tr("Mute"), "POST …/mute")
			mute.name = "Mute"
			mute.pressed.connect(func(): set_muted(uid, not bool(m.get("muted", false))))
			row.add_child(mute)
		var report := GameUi.button("", tr("Report"), "POST /reports")
		report.name = "Report"
		report.pressed.connect(func(): open_report(uid))
		row.add_child(report)
	return row

## 上下麦：服务端换 token，页面据此重连。
func toggle_stage() -> bool:
	var api := _voice()
	if api == null or room.is_empty() or busy:
		return false
	if me_role() == "host":
		return false # 房主始终在麦上，没有上下麦这回事
	if bridge == null and me_role() == "listener":
		status.text = tr("Voice isn't available on this device yet.")
		return false
	busy = true
	var r: Dictionary = await api.set_stage(_text(room.get("id", "")), me_role() == "listener")
	busy = false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	_enter(r)
	mic_on = can_speak()
	if bridge != null:
		bridge.set_mic(mic_on)
	return true

func set_muted(user_id: String, muted: bool) -> bool:
	var api := _voice()
	if api == null or room.is_empty():
		return false
	var r: Dictionary = await api.set_muted(_text(room.get("id", "")), user_id, muted)
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	_enter(r)
	return true

func leave() -> bool:
	var api := _voice()
	if api == null or room.is_empty():
		return false
	var r: Dictionary = await api.leave(_text(room.get("id", "")))
	if bridge != null:
		bridge.disconnect_room()
	room = {}
	room_panel.visible = false
	list_scroll.visible = true
	new_room_row.visible = true
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
	await fetch_rooms()
	return bool(r.get("ok", false))

func open_report(user_id: String) -> void:
	pending_report = user_id
	if is_inside_tree():
		report_menu.popup_centered()

func _on_report_reason(index: int) -> void:
	if index < 0 or index >= SafetyApi.REASONS.size():
		return
	await report(pending_report, SafetyApi.REASONS[index])

## 举报房间里的人：先本地静音他（房主还要单独处置），再送举报。
func report(user_id: String, reason: String) -> bool:
	var api := _safety()
	if api == null or user_id.is_empty():
		return false
	if bridge != null:
		bridge.set_volume(user_id, 0.0)
	var r: Dictionary = await api.report("user", user_id, reason)
	if bool(r.get("ok", false)):
		_track("content_reported", {"target": "voice_user", "reason": reason})
		status.text = tr("Thanks, we've received your report.")
		return true
	status.text = describe_error(r)
	return false

func _on_speaking(identity: String, is_speaking: bool) -> void:
	speaking[identity] = is_speaking
	if not room.is_empty():
		_render_stage()

func _refresh_mic_label() -> void:
	var speak := can_speak()
	# 房主永远在麦上：按钮禁用并直说，别让人点出一句「房主始终在麦上」的报错（真机复查）。
	if me_role() == "host":
		mic_button.text = tr("You're the host")
		mic_button.disabled = true
		return
	mic_button.text = tr("Leave the mic") if speak else tr("Take the mic")
	# 没有原生桥就只能听：按钮禁用并把原因说清楚，别让人以为坏了。
	mic_button.disabled = bridge == null and not speak
	if bridge == null and status.text.is_empty():
		status.text = tr("Listening only: voice isn't available on this device yet.")

func reason_label(reason: String) -> String:
	match reason:
		"spam": return tr("Spam or scam")
		"harassment": return tr("Harassment or bullying")
		"sexual": return tr("Sexual content")
		"violence": return tr("Violence or threats")
		"hate": return tr("Hate speech")
		"self_harm": return tr("Self-harm")
		"minor_safety": return tr("Child safety")
		_: return tr("Something else")

func describe_disconnect(reason: String) -> String:
	return tr("Disconnected from voice: %s") % reason if not reason.is_empty() else tr("Disconnected from voice.")

func describe_error(r: Dictionary) -> String:
	match str(r.get("code", "")):
		"VOICE_NOT_CONFIGURED": return tr("Voice rooms aren't available on this server yet.")
		"ROOM_FULL": return tr("This room is full.")
		"STAGE_FULL": return tr("All mic seats are taken.")
		"MUTED": return tr("The host muted you.")
		"NOT_HOST": return tr("Only the host can do that.")
		"NOT_IN_ROOM": return tr("You're not in this room.")
		"HOST_ALWAYS_ON_STAGE": return tr("The host is always on the mic.")
		"NOT_FOUND": return tr("This room has ended.")
		"NETWORK": return tr("Can't reach the server. Check your connection and try again.")
		_: return str(r.get("code", "UNKNOWN"))
