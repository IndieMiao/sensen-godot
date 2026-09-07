extends AppPage
## 聊天页（B2，压栈）：历史消息 + 底部输入框；实时消息走 Net.im_event，断线补拉也从同一个信号来。
## 发送带幂等 client_id：失败时文字留在输入框，重发用同一个 client_id，服务端不会存两条。
## auth / im / navigate 可注入；测试直接调 _on_im_event() 模拟推送。

const HISTORY_PAGE := 30

var auth: AuthSession
var im: ImApi
var conversation: Dictionary = {}

var scroll: ScrollContainer
var list: VBoxContainer
var composer: LineEdit
var send_button: Button
var status: Label
## 已渲染的消息 id → 气泡节点；用来去重与撤回。
var bubbles: Dictionary = {}
## 按 seq 升序的消息字典。
var messages: Array = []
var pending_client_id := ""
var sending := false
var loading := false

func _init() -> void:
	page_title = "Chat"
	stacked = true

## AppRouter.push_instance 在 _ready 前调用：标题要在建头部前定下来。
func setup(args: Dictionary) -> void:
	conversation = args.get("conversation", {}) if args.get("conversation") is Dictionary else {}
	page_title = title_for(conversation)

static func title_for(c: Dictionary) -> String:
	if str(c.get("kind", "")) == "group":
		return str(c.get("title", "")) if c.get("title") != null else ""
	var peer: Dictionary = c.get("peer", {}) if c.get("peer") is Dictionary else {}
	var name := str(peer.get("display_name", "")) if peer.get("display_name") != null else ""
	return name if not name.is_empty() else "Chat"

func _build_body() -> void:
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = VBoxContainer.new()
	list.name = "Messages"
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	body.add_child(scroll)
	status = GameUi.label("", 12, GameUi.MUTED)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	var row := HBoxContainer.new()
	row.name = "Composer"
	row.add_theme_constant_override("separation", 8)
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
	if Engine.has_singleton("Net") or get_node_or_null("/root/Net") != null:
		Net.im_event.connect(_on_im_event)
	call_deferred("load_history")

func _session() -> AuthSession:
	return auth if auth != null else Net.auth

func _im() -> ImApi:
	return im if im != null else Net.im

func conversation_id() -> String:
	return str(conversation.get("id", ""))

func my_id() -> String:
	var s := _session()
	return s.server_user_id if s != null else ""

## 拉最近一页历史（服务端 seq 倒序），按升序渲染，并把已读推进到最后一条。
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
	await _mark_read()
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
	composer.text = ""
	status.text = ""
	_append(r)
	conversation["last_read_seq"] = maxi(int(conversation.get("last_read_seq", 0)), int(r.get("seq", 0)))
	_scroll_to_end()
	return true

## Net.im_event：只吃本会话的消息事件；其他会话的由列表页处理。
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
		_:
			return str(r.get("code", "UNKNOWN"))

static func _text(v: Variant) -> String:
	return "" if v == null else str(v)

func _append(m: Dictionary) -> void:
	var id := str(m.get("id", ""))
	if id.is_empty() or bubbles.has(id):
		return
	messages.append(m)
	messages.sort_custom(func(a, b): return int(a.get("seq", 0)) < int(b.get("seq", 0)))
	var row := HBoxContainer.new()
	row.name = "Msg_%s" % id
	var mine := str(m.get("sender_id", "")) == my_id()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bubble := PanelContainer.new()
	bubble.name = "Bubble"
	bubble.add_theme_stylebox_override("panel", GameUi.surface(GameUi.MINT if mine else GameUi.PAPER, 10, 12))
	bubble.custom_minimum_size.x = 60
	var label := GameUi.label(bubble_text(m), 14)
	label.name = "Text"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 120
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bubble.add_child(label)
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

func _mark_deleted(id: String) -> void:
	if not bubbles.has(id):
		return
	for m in messages:
		if str(m.get("id", "")) == id:
			m["deleted"] = true
	(bubbles[id].find_child("Text", true, false) as Label).text = tr("Message deleted")

func _scroll_to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
