extends AppPage
## 消息 Tab（B2）：会话列表（对方 / 群名、最后一条、未读、时间）+ 用 @handle 发起单聊 + 建群
##（群名 + 一串 @handle，展开面板）；点会话压栈聊天页。实时事件（Net.im_event）到了就刷新列表。
## auth / im / profile / navigate 可注入。

var auth: AuthSession
var im: ImApi
var profile: ProfileApi
var navigate: Callable

var realtime: Label
var handle_edit: LineEdit
var new_chat_button: Button
var group_toggle: Button
var group_panel: VBoxContainer
var group_title_edit: LineEdit
var group_members_edit: LineEdit
var create_group_button: Button
var status: Label
var list: VBoxContainer
var items: Array = []
var busy := false

func _init() -> void:
	page_title = "Chats"

func _build_body() -> void:
	var row := HBoxContainer.new()
	row.name = "NewChat"
	row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	handle_edit = LineEdit.new()
	handle_edit.name = "Handle"
	handle_edit.placeholder_text = tr("@handle to start a chat")
	handle_edit.max_length = 21
	handle_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	handle_edit.custom_minimum_size.y = 44
	handle_edit.text_submitted.connect(func(_t): start_chat())
	row.add_child(handle_edit)
	new_chat_button = GameUi.button("", tr("Chat"), "GET /users/@handle/profile → POST /im/dm")
	new_chat_button.name = "StartChat"
	new_chat_button.pressed.connect(func(): start_chat())
	row.add_child(new_chat_button)
	group_toggle = GameUi.button("", tr("Group"), "POST /im/groups")
	group_toggle.name = "GroupToggle"
	group_toggle.pressed.connect(func(): group_panel.visible = not group_panel.visible)
	row.add_child(group_toggle)
	body.add_child(row)
	group_panel = VBoxContainer.new()
	group_panel.name = "GroupPanel"
	group_panel.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	group_panel.visible = false
	group_title_edit = LineEdit.new()
	group_title_edit.name = "GroupTitle"
	group_title_edit.placeholder_text = tr("Group name")
	group_title_edit.max_length = 60
	group_title_edit.custom_minimum_size.y = 44
	group_panel.add_child(group_title_edit)
	var members_row := HBoxContainer.new()
	members_row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	group_members_edit = LineEdit.new()
	group_members_edit.name = "GroupMembers"
	group_members_edit.placeholder_text = tr("@handles, separated by commas")
	group_members_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group_members_edit.custom_minimum_size.y = 44
	group_members_edit.text_submitted.connect(func(_t): create_group())
	members_row.add_child(group_members_edit)
	create_group_button = GameUi.button("", tr("Create"), "POST /im/groups")
	create_group_button.name = "CreateGroup"
	create_group_button.pressed.connect(func(): create_group())
	members_row.add_child(create_group_button)
	group_panel.add_child(members_row)
	body.add_child(group_panel)
	status = GameUi.label("", DesignTokens.UI_FONT_CAPTION, GameUi.MUTED)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
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
	realtime = GameUi.label("", DesignTokens.UI_FONT_CAPTION, GameUi.MUTED)
	realtime.name = "Realtime"
	body.add_child(realtime)
	if get_node_or_null("/root/Net") != null:
		Net.ws.state_changed.connect(_on_ws_state)
		_on_ws_state(Net.ws.state)
		Net.im_event.connect(_on_im_event)

func _session() -> AuthSession:
	return auth if auth != null else Net.auth

func _im() -> ImApi:
	return im if im != null else Net.im

func _profile() -> ProfileApi:
	return profile if profile != null else Net.profile

func _can_load() -> bool:
	var s := _session()
	return s != null and s.is_signed_in() and s.provider != "dev" and _im() != null

func on_tab_shown() -> void:
	super()
	await refresh()

func refresh() -> bool:
	if not _can_load():
		status.text = tr("Sign in to chat.")
		return false
	if busy:
		return false
	busy = true
	var r: Dictionary = await _im().conversations()
	busy = false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	items = r.get("items", []) if r.get("items") is Array else []
	_render()
	return true

## 用 @handle 发起单聊：先查资料拿 user_id，再找或建会话，然后进聊天页。
func start_chat() -> bool:
	var handle := handle_edit.text.strip_edges().trim_prefix("@").to_lower()
	if handle.is_empty() or busy or _profile() == null or _im() == null:
		return false
	busy = true
	new_chat_button.disabled = true
	var p: Dictionary = await _profile().get_profile("@" + handle)
	if not bool(p.get("ok", false)):
		busy = false
		new_chat_button.disabled = false
		status.text = tr("No one with that handle.") if int(p.get("status", 0)) == 404 else describe_error(p)
		return false
	var c: Dictionary = await _im().open_dm(str(p.get("user_id", "")))
	busy = false
	new_chat_button.disabled = false
	if not bool(c.get("ok", false)):
		status.text = describe_error(c)
		return false
	handle_edit.text = ""
	status.text = ""
	open_conversation(c)
	return true

## 建群：群名 + 一串 @handle。逐个查资料拿 user_id，哪一个不存在就指出哪一个。
func create_group() -> bool:
	var title := group_title_edit.text.strip_edges()
	var handles := ProfileApi.parse_handles(group_members_edit.text)
	if busy or _profile() == null or _im() == null:
		return false
	if title.is_empty():
		status.text = tr("Give the group a name.")
		return false
	if handles.is_empty():
		status.text = tr("Add at least one @handle.")
		return false
	busy = true
	create_group_button.disabled = true
	var ids: Dictionary = await _profile().user_ids_for(handles)
	var c: Dictionary = {}
	if bool(ids.get("ok", false)):
		c = await _im().create_group(title, ids.get("ids", []))
	busy = false
	create_group_button.disabled = false
	if not bool(ids.get("ok", false)):
		status.text = tr("No one with the handle @%s.") % str(ids.get("missing", "")) if int(ids.get("status", 0)) == 404 else describe_error(ids)
		return false
	if not bool(c.get("ok", false)):
		status.text = describe_error(c)
		return false
	group_title_edit.text = ""
	group_members_edit.text = ""
	group_panel.visible = false
	status.text = ""
	open_conversation(c)
	return true

func open_conversation(c: Dictionary) -> void:
	if navigate.is_valid():
		navigate.call(AppRoutes.CHAT, {"conversation": c})
	else:
		AppRouter.push_instance(AppRoutes.CHAT, {"conversation": c})

## 任何本人相关的 IM 事件都刷新列表；聊天页自己处理正在看的会话。
func _on_im_event(_e: Dictionary) -> void:
	if is_visible_in_tree():
		refresh()

func describe_error(r: Dictionary) -> String:
	match str(r.get("code", "")):
		"BLOCKED":
			return tr("You can't message this user.")
		"NETWORK":
			return tr("Can't reach the server. Check your connection and try again.")
		"IM_NOT_CONFIGURED":
			return tr("Chat isn't available on this server yet.")
		"NO_ACCOUNT":
			return tr("Sign in again to set up your profile.")
		_:
			return str(r.get("code", "UNKNOWN"))

static func _text(v: Variant) -> String:
	return "" if v == null else str(v)

func _render() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.free()
	for c in items:
		list.add_child(_row(c))
	status.text = tr("No chats yet. Start one with someone's @handle.") if items.is_empty() else ""

func _row(c: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Conv_%s" % str(c.get("id", ""))
	b.theme_type_variation = &"SecondaryButton"
	b.custom_minimum_size.y = 64
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	var unread := int(c.get("unread", 0))
	var last: Dictionary = c.get("last_message", {}) if c.get("last_message") is Dictionary else {}
	var preview := preview_for(last)
	var title := preload("res://scenes/app/pages/chat_page.gd").title_for(c)
	var at := int(c.get("last_message_at", 0)) if c.get("last_message_at") != null else 0
	var when := " · " + PostCard.age_text(_now_ms(), at) if at > 0 else ""
	b.text = "%s%s%s\n%s" % [title, "  (%d)" % unread if unread > 0 else "", when, preview]
	# 单聊显示对方形象，群聊用群图标；真图渲好了再换。
	var peer: Dictionary = c.get("peer", {}) if c.get("peer") is Dictionary else {}
	# 缩略图控件只负责取图，不显示（按钮自己的 icon 才是可见的那张，免得两张叠在一起）。
	var thumb := AvatarThumb.new(44.0)
	thumb.name = "Avatar"
	thumb.visible = false
	b.add_child(thumb)
	b.expand_icon = true
	b.add_theme_constant_override("h_separation", DesignTokens.SPACE_2)
	if peer.is_empty():
		b.icon = GameUi.icon("users-round")
	else:
		b.icon = thumb.placeholder_icon()
		thumb.texture_ready.connect(func(tex: Texture2D): AvatarThumb.apply_to_button(b, tex))
		thumb.show_avatar(peer.get("avatar"))
	b.pressed.connect(open_conversation.bind(c))
	return b

func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func preview_for(last: Dictionary) -> String:
	if last.is_empty():
		return tr("No messages yet")
	if bool(last.get("deleted", false)):
		return tr("Message deleted")
	var body: Dictionary = last.get("body", {}) if last.get("body") is Dictionary else {}
	if str(last.get("kind", "text")) == "image":
		return tr("[Photo]")
	return _text(body.get("text", ""))

func _on_ws_state(state: int) -> void:
	var names := {
		WsClient.State.IDLE: tr("idle"), WsClient.State.CONNECTING: tr("connecting"), WsClient.State.OPEN: tr("connected"),
		WsClient.State.RECONNECT_WAIT: tr("reconnecting"), WsClient.State.PAUSED: tr("paused"),
	}
	realtime.text = tr("Realtime: %s") % str(names.get(state, state))
