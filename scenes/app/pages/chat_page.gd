extends AppPage
## 聊天页（B2，压栈）：历史消息 + 底部输入框；实时消息走 Net.im_event，断线补拉也从同一个信号来。
## 发送带幂等 client_id：失败时文字留在输入框，重发用同一个 client_id，服务端不会存两条。
## 第二刀：群聊（别人的气泡带昵称；页头菜单看成员 / 拉人 / 退群）、已读回执（单聊「已读」、群聊
## 「N 人已读」，只标在最后一条被读到的自己的消息上）、长按或右键气泡 → 举报消息 / 拉黑发送者 /
## 撤回自己的；单聊页头菜单 → 举报或拉黑对方。图片消息：「+」选一张 → 上传 → send_image，气泡里按尺寸占位后填图。
## auth / im / profile / safety / uploads / images / picker / leave_handler 可注入；测试直接调 _on_im_event() 模拟推送。

const HISTORY_PAGE := 30
## 长按判定：按住不动这么久弹菜单；期间移动超过 DRAG_CANCEL_PX 视为在滚列表，取消。
const LONG_PRESS_S := 0.5
const DRAG_CANCEL_PX := 12.0

enum MenuItem { REPORT_MESSAGE, BLOCK_USER, DELETE_MESSAGE, REPORT_USER, MEMBERS, ADD_PEOPLE, LEAVE_GROUP, VIEW_PROFILE }

var auth: AuthSession
var im: ImApi
var profile: ProfileApi
var safety: SafetyApi
var uploads: UploadApi
var images: ImageCache
var picker: PhotoPicker
## 退群 / 拉黑对方后离开本页；默认 AppRouter.pop_instance。
var leave_handler: Callable
## 压栈别的页（对方主页）；默认 AppRouter.push_instance。
var navigate: Callable
var conversation: Dictionary = {}

var scroll: ScrollContainer
var list: VBoxContainer
var composer: LineEdit
var send_button: Button
var attach_button: Button
var attaching := false
var status: Label
var menu_button: Button
var context_menu: PopupMenu
var reason_menu: PopupMenu
var block_confirm: ConfirmationDialog
var leave_confirm: ConfirmationDialog
var add_row: HBoxContainer
var add_edit: LineEdit
var add_button: Button
var long_press: Timer
## 已渲染的消息 id → 气泡行；用来去重、撤回、回执。
var bubbles: Dictionary = {}
## 按 seq 升序的消息字典。
var messages: Array = []
## user_id → 成员卡（display_name / last_read_seq…）。单聊一开始只有 peer 卡片。
var members: Dictionary = {}
## 单聊对方已读到的 seq：会话里带初始值，之后靠 read 事件推进。
var peer_read_seq := 0
var pending_client_id := ""
var sending := false
var loading := false
var pressed_id := ""
var pressed_at := Vector2.ZERO
## 长按 / 右键选中的消息 id；页头菜单打开时为空。
var menu_target := ""
var pending_report: Dictionary = {}
var block_target := ""

signal picture_loaded(message_id: String)

func _init() -> void:
	keyboard_mode = KeyboardAvoider.Mode.SHRINK
	page_title = "Chat"
	stacked = true

## AppRouter.push_instance 在 _ready 前调用：标题要在建头部前定下来。
func setup(args: Dictionary) -> void:
	conversation = args.get("conversation", {}) if args.get("conversation") is Dictionary else {}
	page_title = title_for(conversation)
	peer_read_seq = int(conversation.get("peer_read_seq", 0)) if conversation.get("peer_read_seq") != null else 0
	var peer: Dictionary = conversation.get("peer", {}) if conversation.get("peer") is Dictionary else {}
	if not _text(peer.get("user_id", "")).is_empty():
		members[str(peer.get("user_id", ""))] = peer

static func title_for(c: Dictionary) -> String:
	if str(c.get("kind", "")) == "group":
		return str(c.get("title", "")) if c.get("title") != null else ""
	var peer: Dictionary = c.get("peer", {}) if c.get("peer") is Dictionary else {}
	var name := str(peer.get("display_name", "")) if peer.get("display_name") != null else ""
	return name if not name.is_empty() else "Chat"

func _build_body() -> void:
	menu_button = GameUi.button("", "•••", "")
	menu_button.name = "Menu"
	menu_button.pressed.connect(open_page_menu)
	title_label.get_parent().add_child(menu_button)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = VBoxContainer.new()
	list.name = "Messages"
	list.add_theme_constant_override("separation", DesignTokens.SPACE_1H)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	body.add_child(scroll)
	status = GameUi.label("", DesignTokens.UI_FONT_CAPTION, GameUi.MUTED)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	add_row = HBoxContainer.new()
	add_row.name = "AddPeople"
	add_row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	add_row.visible = false
	add_edit = LineEdit.new()
	add_edit.name = "Handles"
	add_edit.placeholder_text = tr("@handles to add")
	add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_edit.custom_minimum_size.y = 44
	add_edit.text_submitted.connect(func(_t): add_people())
	add_row.add_child(add_edit)
	add_button = GameUi.button("", tr("Add"), "POST /im/groups/:id/members")
	add_button.name = "Add"
	add_button.pressed.connect(func(): add_people())
	add_row.add_child(add_button)
	body.add_child(add_row)
	var row := HBoxContainer.new()
	row.name = "Composer"
	row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	attach_button = GameUi.button("", "+", "PhotoPicker → POST /uploads → send_image")
	attach_button.name = "Attach"
	attach_button.pressed.connect(func(): attach_photo())
	row.add_child(attach_button)
	composer = LineEdit.new()
	composer.name = "Text"
	composer.placeholder_text = tr("Message")
	composer.max_length = 4000
	composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composer.custom_minimum_size.y = 44
	composer.text_submitted.connect(func(_t): send())
	row.add_child(composer)
	send_button = GameUi.button("", tr("Send"), "POST /im/conversations/:id/messages")
	send_button.name = "Send"
	send_button.pressed.connect(func(): send())
	row.add_child(send_button)
	body.add_child(row)
	context_menu = PopupMenu.new()
	context_menu.name = "ContextMenu"
	context_menu.id_pressed.connect(_on_menu)
	add_child(context_menu)
	reason_menu = PopupMenu.new()
	reason_menu.name = "ReasonMenu"
	for i in SafetyApi.REASONS.size():
		reason_menu.add_item(reason_label(SafetyApi.REASONS[i]), i)
	reason_menu.id_pressed.connect(_on_report_reason)
	add_child(reason_menu)
	block_confirm = ConfirmationDialog.new()
	block_confirm.name = "BlockConfirm"
	block_confirm.title = tr("Block this user?")
	block_confirm.dialog_text = tr("They won't be able to message you, and you won't see each other's posts or profiles.")
	block_confirm.ok_button_text = tr("Block")
	block_confirm.confirmed.connect(_on_block_confirmed)
	add_child(block_confirm)
	leave_confirm = ConfirmationDialog.new()
	leave_confirm.name = "LeaveConfirm"
	leave_confirm.title = tr("Leave this group?")
	leave_confirm.dialog_text = tr("You'll stop getting its messages.")
	leave_confirm.ok_button_text = tr("Leave")
	leave_confirm.confirmed.connect(_on_leave_confirmed)
	add_child(leave_confirm)
	long_press = Timer.new()
	long_press.name = "LongPress"
	long_press.one_shot = true
	long_press.wait_time = LONG_PRESS_S
	long_press.timeout.connect(_on_long_press)
	add_child(long_press)
	if Engine.has_singleton("Net") or get_node_or_null("/root/Net") != null:
		Net.im_event.connect(_on_im_event)
	call_deferred("load_history")

func _session() -> AuthSession:
	return auth if auth != null else Net.auth

func _im() -> ImApi:
	return im if im != null else Net.im

func _profile() -> ProfileApi:
	return profile if profile != null else Net.profile

func _safety() -> SafetyApi:
	return safety if safety != null else Net.safety

func _uploads() -> UploadApi:
	return uploads if uploads != null else Net.uploads

func _images() -> ImageCache:
	return images if images != null else Net.images

func _picker() -> PhotoPicker:
	if picker == null:
		picker = PhotoPicker.new()
	return picker

func image_url(key: String) -> String:
	return Net.file_url(key)

func conversation_id() -> String:
	return str(conversation.get("id", ""))

func is_group() -> bool:
	return str(conversation.get("kind", "")) == "group"

func peer_id() -> String:
	var peer: Dictionary = conversation.get("peer", {}) if conversation.get("peer") is Dictionary else {}
	return _text(peer.get("user_id", ""))

func my_id() -> String:
	var s := _session()
	return s.server_user_id if s != null else ""

## 拉最近一页历史（服务端 seq 倒序），按升序渲染；群聊再拉成员（昵称与已读进度）；把已读推进到最后一条。
func load_history() -> bool:
	var api := _im()
	if api == null or conversation_id().is_empty() or loading:
		return false
	loading = true
	var r: Dictionary = await api.messages(conversation_id(), 0, HISTORY_PAGE)
	loading = false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	var items: Array = r.get("items", []) if r.get("items") is Array else []
	items.reverse()
	for m in items:
		_append(m)
	_scroll_to_end()
	if is_group():
		await load_members()
	else:
		_update_receipts()
	await _mark_read()
	return true

## 成员列表：群聊气泡上的昵称、「N 人已读」都从这来。
func load_members() -> bool:
	var api := _im()
	if api == null or conversation_id().is_empty():
		return false
	var r: Dictionary = await api.members(conversation_id())
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	members.clear()
	for m in (r.get("items", []) if r.get("items") is Array else []):
		if m is Dictionary:
			members[str(m.get("user_id", ""))] = m
	_refresh_names()
	_update_receipts()
	return true

func _mark_read() -> void:
	if messages.is_empty():
		return
	var last_seq := int(messages[-1].get("seq", 0))
	if last_seq > int(conversation.get("last_read_seq", 0)):
		conversation["last_read_seq"] = last_seq
		await _im().mark_read(conversation_id(), last_seq)

## 发送输入框里的文字。返回是否成功。
func send() -> bool:
	var text := composer.text.strip_edges()
	var api := _im()
	if text.is_empty() or sending or api == null:
		return false
	if pending_client_id.is_empty():
		pending_client_id = ApiClient.new_idempotency_key()
	sending = true
	send_button.disabled = true
	var r: Dictionary = await api.send_text(conversation_id(), text, pending_client_id)
	sending = false
	send_button.disabled = false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	pending_client_id = ""
	_track("message_sent", {"kind": "text", "group": is_group()})
	composer.text = ""
	status.text = ""
	_append(r)
	conversation["last_read_seq"] = maxi(int(conversation.get("last_read_seq", 0)), int(r.get("seq", 0)))
	_update_receipts()
	_scroll_to_end()
	return true

## 「+」：选一张 → 上传 → 图片消息（输入框里的文字当图注一起发）。取消选图不算失败也不报错。
func attach_photo() -> bool:
	var api := _im()
	if attaching or api == null or _uploads() == null:
		return false
	attaching = true
	attach_button.disabled = true
	status.text = tr("Choosing…")
	var picked: Dictionary = await _picker().pick(1)
	var items: Array = picked.get("items", []) if picked.get("items") is Array else []
	if not bool(picked.get("ok", false)) or items.is_empty():
		status.text = describe_error(picked) if not bool(picked.get("ok", false)) else ""
		_attach_done()
		return false
	status.text = tr("Uploading…")
	var up: Dictionary = await _uploads().upload_image(items[0])
	if not bool(up.get("ok", false)):
		status.text = describe_error(up)
		_attach_done()
		return false
	var r: Dictionary = await api.send_image(conversation_id(), {"key": up.key, "w": int(up.w), "h": int(up.h)}, composer.text.strip_edges())
	_attach_done()
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	_track("message_sent", {"kind": "image", "group": is_group()})
	composer.text = ""
	status.text = ""
	_append(r)
	conversation["last_read_seq"] = maxi(int(conversation.get("last_read_seq", 0)), int(r.get("seq", 0)))
	_update_receipts()
	_scroll_to_end()
	return true

func _attach_done() -> void:
	attaching = false
	attach_button.disabled = false

## Net.im_event：只吃本会话的事件；其他会话的由列表页处理。
func _on_im_event(e: Dictionary) -> void:
	if str(e.get("conversation_id", "")) != conversation_id():
		return
	match str(e.get("type", "")):
		"message":
			_append({
				"id": str(e.get("message_id", "")), "seq": int(e.get("message_seq", 0)), "sender_id": str(e.get("sender_id", "")),
				"kind": str(e.get("kind", "text")), "body": e.get("body", {}) if e.get("body") is Dictionary else {},
				"created_at": int(e.get("created_at", 0)), "deleted": false,
			})
			_scroll_to_end()
			if is_visible_in_tree():
				_mark_read()
		"message_deleted":
			_mark_deleted(str(e.get("message_id", "")))
		"read":
			# 对方的已读进度；自己在另一台设备上的已读不算回执。群聊推进该成员卡上的 last_read_seq，
			# 「N 人已读」随之实时变；成员卡还没拉到时（进页早于 load_members）先补一张只带进度的卡。
			var who := str(e.get("user_id", ""))
			if who.is_empty() or who == my_id():
				return
			var read_seq := int(e.get("read_seq", 0))
			if is_group():
				var card: Dictionary = members.get(who, {}) if members.get(who) is Dictionary else {"user_id": who, "display_name": "", "handle": null, "avatar": null}
				card["last_read_seq"] = maxi(int(card.get("last_read_seq", 0)), read_seq)
				members[who] = card
			else:
				peer_read_seq = maxi(peer_read_seq, read_seq)
			_update_receipts()
		"members_added", "member_left":
			load_members()

func describe_error(r: Dictionary) -> String:
	match str(r.get("code", "")):
		"GREETING_LIMIT":
			return tr("You can send one message until they reply.")
		"BLOCKED":
			return tr("You can't message this user.")
		"MODERATION_REJECTED":
			return tr("This message was blocked by our content rules.")
		"NETWORK":
			return tr("Can't reach the server. Check your connection and try again.")
		"IM_NOT_CONFIGURED":
			return tr("Chat isn't available on this server yet.")
		"UPLOADS_NOT_CONFIGURED":
			return tr("Photos can't be uploaded on this server yet.")
		"UNSUPPORTED":
			return tr("No picker on this platform.")
		"NOT_GROUP":
			return tr("This isn't a group chat.")
		"FORBIDDEN":
			return tr("Only the sender can unsend a message.")
		"NOT_FOUND":
			return tr("That's no longer available.")
		_:
			return str(r.get("code", "UNKNOWN"))

## 举报原因的文案；键与服务端 REPORT_REASONS 一致。
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

static func _text(v: Variant) -> String:
	return "" if v == null else str(v)

func name_for(user_id: String) -> String:
	if user_id == my_id():
		return tr("You")
	var m: Dictionary = members.get(user_id, {}) if members.get(user_id) is Dictionary else {}
	var n := _text(m.get("display_name", ""))
	return n if not n.is_empty() else tr("Someone")

func _message(id: String) -> Dictionary:
	for m in messages:
		if str(m.get("id", "")) == id:
			return m
	return {}

func _append(m: Dictionary) -> void:
	var id := str(m.get("id", ""))
	if id.is_empty() or bubbles.has(id):
		return
	messages.append(m)
	messages.sort_custom(func(a, b): return int(a.get("seq", 0)) < int(b.get("seq", 0)))
	var row := HBoxContainer.new()
	row.name = "Msg_%s" % id
	var sender := str(m.get("sender_id", ""))
	var mine := sender == my_id()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bubble := PanelContainer.new()
	bubble.name = "Bubble"
	bubble.add_theme_stylebox_override("panel", GameUi.surface(GameUi.MINT if mine else GameUi.PAPER, 10, 12))
	bubble.custom_minimum_size.x = 60
	# PASS：自己收长按 / 右键，事件继续传给 ScrollContainer 滚列表。
	bubble.mouse_filter = Control.MOUSE_FILTER_PASS
	bubble.gui_input.connect(_on_bubble_input.bind(id))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", DesignTokens.SPACE_HALF)
	bubble.add_child(box)
	if is_group() and not mine:
		var who := GameUi.label(name_for(sender), DesignTokens.UI_FONT_TAB, GameUi.MUTED)
		who.name = "Who"
		box.add_child(who)
	var label := GameUi.label(bubble_text(m), DesignTokens.UI_FONT_BODY)
	label.name = "Text"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 120
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if str(m.get("kind", "text")) == "image" and not bool(m.get("deleted", false)):
		var pic := PictureView.new()
		pic.name = "Picture"
		box.add_child(pic)
		_show_picture(pic, label, id, m.get("body", {}) if m.get("body") is Dictionary else {})
	box.add_child(label)
	if mine:
		var receipt := GameUi.label("", DesignTokens.UI_FONT_TAB, GameUi.MUTED)
		receipt.name = "Receipt"
		receipt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		receipt.visible = false
		box.add_child(receipt)
	if mine:
		row.add_child(spacer)
		row.add_child(bubble)
	else:
		row.add_child(bubble)
		row.add_child(spacer)
	# 按 seq 插到正确位置：补拉回来的旧消息可能晚于实时推送到达。
	var index := messages.find(m)
	list.add_child(row)
	list.move_child(row, index)
	bubbles[id] = row

func bubble_text(m: Dictionary) -> String:
	if bool(m.get("deleted", false)):
		return tr("Message deleted")
	var body: Dictionary = m.get("body", {}) if m.get("body") is Dictionary else {}
	match str(m.get("kind", "text")):
		"image":
			var cap := _text(body.get("text", ""))
			return tr("[Photo]") if cap.is_empty() else "%s %s" % [tr("[Photo]"), cap]
		"system":
			return tr("Message deleted")
		_:
			return _text(body.get("text", ""))

func _refresh_names() -> void:
	for id in bubbles:
		var who := (bubbles[id] as Node).find_child("Who", true, false) as Label
		if who != null:
			who.text = name_for(str(_message(id).get("sender_id", "")))

## 一条自己的消息被读到的回执文案；没人读到返回空。
func receipt_for(seq: int) -> String:
	if is_group():
		var n := 0
		for uid in members:
			if uid != my_id() and int((members[uid] as Dictionary).get("last_read_seq", 0)) >= seq:
				n += 1
		return tr("Read by %d") % n if n > 0 else ""
	return tr("Read") if peer_read_seq >= seq else ""

## 回执只标在最后一条被读到的自己的消息上（其余隐藏），像常见 IM 那样不刷屏。
func _update_receipts() -> void:
	var last_id := ""
	var caption := ""
	for m in messages:
		if str(m.get("sender_id", "")) != my_id() or bool(m.get("deleted", false)):
			continue
		var text := receipt_for(int(m.get("seq", 0)))
		if not text.is_empty():
			last_id = str(m.get("id", ""))
			caption = text
	for id in bubbles:
		var r := (bubbles[id] as Node).find_child("Receipt", true, false) as Label
		if r == null:
			continue
		r.visible = id == last_id
		if r.visible:
			r.text = caption

## 图片气泡：先「[Photo]」占位，图到了换成图注（没有图注就只留图）。
func _show_picture(pic: PictureView, label: Label, id: String, body: Dictionary) -> void:
	var ok: bool = await pic.show_picture(_images(), image_url(_text(body.get("key", ""))), int(body.get("w", 0)), int(body.get("h", 0)), Vector2(220, 220))
	if ok and is_instance_valid(label):
		var cap := _text(body.get("text", ""))
		label.text = cap
		label.visible = not cap.is_empty()
	picture_loaded.emit(id)

func _mark_deleted(id: String) -> void:
	if not bubbles.has(id):
		return
	for m in messages:
		if str(m.get("id", "")) == id:
			m["deleted"] = true
	var row: Node = bubbles[id]
	var text := row.find_child("Text", true, false) as Label
	text.text = tr("Message deleted")
	text.visible = true
	var pic := row.find_child("Picture", true, false)
	if pic != null:
		pic.visible = false
	_update_receipts()

# —— 菜单：页头「•••」与气泡长按 / 右键 ——

func open_page_menu() -> void:
	menu_target = ""
	context_menu.clear()
	if is_group():
		context_menu.add_item(tr("Members"), MenuItem.MEMBERS)
		context_menu.add_item(tr("Add people"), MenuItem.ADD_PEOPLE)
		context_menu.add_item(tr("Leave group"), MenuItem.LEAVE_GROUP)
	else:
		context_menu.add_item(tr("View profile"), MenuItem.VIEW_PROFILE)
		context_menu.add_item(tr("Report user"), MenuItem.REPORT_USER)
		context_menu.add_item(tr("Block user"), MenuItem.BLOCK_USER)
	_popup(context_menu)

## 别人的消息：举报 / 拉黑发送者；自己的：撤回。已撤回的没有菜单。
func open_message_menu(id: String) -> bool:
	var m := _message(id)
	if m.is_empty() or bool(m.get("deleted", false)):
		return false
	menu_target = id
	context_menu.clear()
	var sender := str(m.get("sender_id", ""))
	if sender == my_id():
		context_menu.add_item(tr("Unsend"), MenuItem.DELETE_MESSAGE)
	else:
		context_menu.add_item(tr("Report message"), MenuItem.REPORT_MESSAGE)
		context_menu.add_item(tr("Block %s") % name_for(sender), MenuItem.BLOCK_USER)
	_popup(context_menu)
	return true

func _popup(p: Window) -> void:
	if is_inside_tree():
		p.popup_centered()

func _on_menu(id: int) -> void:
	var m := _message(menu_target)
	match id:
		MenuItem.REPORT_MESSAGE:
			pending_report = {"type": "message", "id": menu_target}
			_popup(reason_menu)
		MenuItem.REPORT_USER:
			pending_report = {"type": "user", "id": peer_id()}
			_popup(reason_menu)
		MenuItem.BLOCK_USER:
			block_target = str(m.get("sender_id", "")) if not m.is_empty() else peer_id()
			_popup(block_confirm)
		MenuItem.DELETE_MESSAGE:
			await unsend(menu_target)
		MenuItem.MEMBERS:
			await show_members()
		MenuItem.ADD_PEOPLE:
			add_row.visible = true
			add_edit.grab_focus()
		MenuItem.LEAVE_GROUP:
			_popup(leave_confirm)
		MenuItem.VIEW_PROFILE:
			if not peer_id().is_empty():
				if navigate.is_valid():
					navigate.call(AppRoutes.USER, {"user_id": peer_id()})
				else:
					AppRouter.push_instance(AppRoutes.USER, {"user_id": peer_id()})

func _on_report_reason(index: int) -> void:
	if index < 0 or index >= SafetyApi.REASONS.size():
		return
	await report(str(pending_report.get("type", "")), str(pending_report.get("id", "")), SafetyApi.REASONS[index])

## 举报一条消息或一个用户。服务端同一人同一目标只记一条，重复点也只会告诉用户「已收到」。
func report(target_type: String, target_id: String, reason: String) -> bool:
	var api := _safety()
	if api == null or target_id.is_empty():
		return false
	var r: Dictionary = await api.report(target_type, target_id, reason)
	if bool(r.get("ok", false)):
		_track("content_reported", {"target": target_type, "reason": reason})
		status.text = tr("Thanks, we've received your report.")
		return true
	status.text = describe_error(r)
	return false

func _on_block_confirmed() -> void:
	await block_user(block_target)

## 拉黑：服务端双向不可见。单聊拉黑对方后本页没意义了，直接离开；群聊留在页里。
func block_user(user_id: String) -> bool:
	var api := _safety()
	if api == null or user_id.is_empty():
		return false
	var r: Dictionary = await api.block(user_id)
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	_track("user_blocked", {"from": "chat"})
	status.text = tr("Blocked.")
	if not is_group():
		_leave()
	return true

## 撤回自己的消息（软删，服务端推 message_deleted 给全部成员）。
func unsend(id: String) -> bool:
	var api := _im()
	if api == null or id.is_empty():
		return false
	var r: Dictionary = await api.delete_message(id)
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	_mark_deleted(id)
	return true

func show_members() -> bool:
	if not await load_members():
		return false
	var names: Array = []
	for uid in members:
		names.append(name_for(uid))
	status.text = tr("Members: %s") % ", ".join(names)
	return true

## 拉人进群：一串 @handle → user_id → POST members；成功后重拉成员。
func add_people() -> bool:
	var handles := ProfileApi.parse_handles(add_edit.text)
	var api := _im()
	if api == null or _profile() == null:
		return false
	if handles.is_empty():
		status.text = tr("Add at least one @handle.")
		return false
	add_button.disabled = true
	var ids: Dictionary = await _profile().user_ids_for(handles)
	var r: Dictionary = {}
	if bool(ids.get("ok", false)):
		r = await api.add_members(conversation_id(), ids.get("ids", []))
	add_button.disabled = false
	if not bool(ids.get("ok", false)):
		status.text = tr("No one with the handle @%s.") % str(ids.get("missing", "")) if int(ids.get("status", 0)) == 404 else describe_error(ids)
		return false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	add_edit.text = ""
	add_row.visible = false
	status.text = ""
	await load_members()
	return true

func _on_leave_confirmed() -> void:
	await leave_group()

func leave_group() -> bool:
	var api := _im()
	if api == null:
		return false
	var r: Dictionary = await api.leave_group(conversation_id())
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	_leave()
	return true

func _leave() -> void:
	if leave_handler.is_valid():
		leave_handler.call()
	else:
		AppRouter.pop_instance()

# —— 长按 / 右键 ——

func _on_bubble_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_press()
			open_message_menu(id)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_press(id, event.pressed, event.position)
	elif event is InputEventScreenTouch:
		_press(id, event.pressed, event.position)
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and pressed_id == id:
		if event.position.distance_to(pressed_at) > DRAG_CANCEL_PX:
			_cancel_press()

func _press(id: String, pressed: bool, at: Vector2) -> void:
	if pressed:
		pressed_id = id
		pressed_at = at
		long_press.start()
	else:
		_cancel_press()

func _cancel_press() -> void:
	pressed_id = ""
	long_press.stop()

func _on_long_press() -> void:
	var id := pressed_id
	pressed_id = ""
	if not id.is_empty():
		open_message_menu(id)

func _scroll_to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
