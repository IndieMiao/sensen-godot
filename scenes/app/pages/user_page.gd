extends AppPage
## 用户主页（压栈）：B4「别人的资料页」+ D4 关注 / 取关 + E1 举报 / 拉黑入口 + 发消息 + 动态列表。
## setup({"user_id": uuid} 或 {"handle": "ali"})。被拉黑（任一方向）时服务端 404，页面提示「这个用户不可用」。
## auth / profile / feed / safety / im / images / navigate / leave_handler 可注入。

var auth: AuthSession
var profile: ProfileApi
var feed: FeedApi
var safety: SafetyApi
var im: ImApi
var images: ImageCache
var navigate: Callable
var leave_handler: Callable

var target := ""
var user: Dictionary = {}
var name_label: Label
var handle_label: Label
var bio_label: Label
var counts_label: Label
var follow_button: Button
var message_button: Button
var report_button: Button
var block_button: Button
var status: Label
var list: VBoxContainer
var more_button: Button
var items: Array = []
var cards: Dictionary = {}
var next_cursor := ""
var busy := false
## _ready 里 call_deferred("load") 与外部显式调用可能撞车（测试里就撞了）：只跑一次。
var loading := false
var loaded := false
var report_menu: PopupMenu
var block_confirm: ConfirmationDialog
var pending_report: Dictionary = {}

func _init() -> void:
	page_title = "Profile"
	stacked = true

func setup(args: Dictionary) -> void:
	var handle := str(args.get("handle", "")).strip_edges().trim_prefix("@").to_lower()
	target = "@" + handle if not handle.is_empty() else str(args.get("user_id", ""))

func _build_body() -> void:
	var card := PanelContainer.new()
	card.name = "Card"
	card.add_theme_stylebox_override("panel", GameUi.surface())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	name_label = GameUi.label("", 18)
	name_label.name = "Name"
	col.add_child(name_label)
	handle_label = GameUi.label("", 12, GameUi.MUTED)
	handle_label.name = "Handle"
	col.add_child(handle_label)
	bio_label = GameUi.label("", 14)
	bio_label.name = "Bio"
	bio_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(bio_label)
	counts_label = GameUi.label("", 12, GameUi.MUTED)
	counts_label.name = "Counts"
	col.add_child(counts_label)
	body.add_child(card)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 8)
	follow_button = GameUi.button("", tr("Follow"), "PUT/DELETE /users/:id/follow", true)
	follow_button.name = "Follow"
	follow_button.pressed.connect(func(): toggle_follow())
	actions.add_child(follow_button)
	message_button = GameUi.button("", tr("Message"), "POST /im/dm")
	message_button.name = "Message"
	message_button.pressed.connect(func(): open_chat())
	actions.add_child(message_button)
	report_button = GameUi.button("", tr("Report"), "POST /reports")
	report_button.name = "Report"
	report_button.pressed.connect(func(): open_report_menu("user", user_id()))
	actions.add_child(report_button)
	block_button = GameUi.button("", tr("Block"), "PUT /users/:id/block")
	block_button.name = "Block"
	block_button.pressed.connect(func(): _popup(block_confirm))
	actions.add_child(block_button)
	actions.visible = false
	body.add_child(actions)
	status = GameUi.label("", 12, GameUi.MUTED)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	body.add_child(scroll)
	more_button = GameUi.button("", tr("Load more"), "GET /users/:id/posts?cursor")
	more_button.name = "More"
	more_button.visible = false
	more_button.pressed.connect(func(): load_posts(true))
	body.add_child(more_button)
	report_menu = PopupMenu.new()
	report_menu.name = "ReportMenu"
	for i in SafetyApi.REASONS.size():
		report_menu.add_item(reason_label(SafetyApi.REASONS[i]), i)
	report_menu.id_pressed.connect(_on_report_reason)
	add_child(report_menu)
	block_confirm = ConfirmationDialog.new()
	block_confirm.name = "BlockConfirm"
	block_confirm.title = tr("Block this user?")
	block_confirm.dialog_text = tr("You won't see each other's posts or profiles, and you'll stop following each other.")
	block_confirm.ok_button_text = tr("Block")
	block_confirm.confirmed.connect(_on_block_confirmed)
	add_child(block_confirm)
	call_deferred("load")

func _session() -> AuthSession:
	return auth if auth != null else Net.auth

func _profile() -> ProfileApi:
	return profile if profile != null else Net.profile

func _feed() -> FeedApi:
	return feed if feed != null else Net.feed

func _safety() -> SafetyApi:
	return safety if safety != null else Net.safety

func _im() -> ImApi:
	return im if im != null else Net.im

func _images() -> ImageCache:
	return images if images != null else Net.images

func image_url(key: String) -> String:
	return Net.file_url(key)

func my_id() -> String:
	var s := _session()
	return s.server_user_id if s != null else ""

func user_id() -> String:
	return _text(user.get("user_id", ""))

func is_following() -> bool:
	var rel: Dictionary = user.get("relation", {}) if user.get("relation") is Dictionary else {}
	return bool(rel.get("following", false))

static func _text(v: Variant) -> String:
	return "" if v == null else str(v)

## 资料 + 第一页动态。
func load() -> bool:
	if loading or loaded or _profile() == null or target.is_empty():
		return false
	loading = true
	var r: Dictionary = await _profile().get_profile(target)
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		loading = false
		return false
	user = r
	_show_user()
	await load_posts(false)
	loaded = true
	loading = false
	return true

func _show_user() -> void:
	var name := _text(user.get("display_name", ""))
	name_label.text = name if not name.is_empty() else tr("Someone")
	title_label.text = name_label.text
	var handle := _text(user.get("handle", ""))
	handle_label.text = "@" + handle if not handle.is_empty() else ""
	handle_label.visible = not handle.is_empty()
	bio_label.text = _text(user.get("bio", ""))
	bio_label.visible = not bio_label.text.is_empty()
	var parts: Array = [tr("%d followers") % int(user.get("followers_count", 0))]
	if user.has("following_count") and user.get("following_count") != null:
		parts.append(tr("%d following") % int(user.get("following_count", 0)))
	var rel: Dictionary = user.get("relation", {}) if user.get("relation") is Dictionary else {}
	if bool(rel.get("followed_by", false)):
		parts.append(tr("Follows you"))
	counts_label.text = " · ".join(parts)
	var mine := user_id() == my_id()
	(follow_button.get_parent() as Control).visible = not mine and not user_id().is_empty()
	follow_button.text = tr("Following") if is_following() else tr("Follow")

func load_posts(more: bool) -> bool:
	if _feed() == null or user_id().is_empty() or busy:
		return false
	if more and next_cursor.is_empty():
		return false
	busy = true
	var r: Dictionary = await _feed().posts_of(user_id(), next_cursor if more else "")
	busy = false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	var page: Array = r.get("items", []) if r.get("items") is Array else []
	if not more:
		items = []
	items.append_array(page)
	next_cursor = _text(r.get("next_cursor", ""))
	more_button.visible = not next_cursor.is_empty()
	_render()
	return true

func _render() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.free()
	cards.clear()
	for p in items:
		var card := PostCard.build(p, card_ctx())
		cards[_text(p.get("id", ""))] = card
		list.add_child(card)
	if items.is_empty() and status.text.is_empty():
		status.text = tr("No posts yet.")

func card_ctx() -> Dictionary:
	return {
		"me_id": my_id(), "images": _images(), "image_url": image_url,
		"on_like": toggle_like, "on_comments": open_post,
		"on_report": func(post_id: String, _author_id: String): open_report_menu("post", post_id),
		"on_block": func(_post_id: String, _author_id: String): _popup(block_confirm),
	}

func _item(post_id: String) -> Dictionary:
	for p in items:
		if _text(p.get("id", "")) == post_id:
			return p
	return {}

func toggle_like(post_id: String) -> void:
	var p := _item(post_id)
	if p.is_empty() or _feed() == null:
		return
	var r: Dictionary
	if bool(p.get("liked", false)):
		r = await _feed().unlike(post_id)
	else:
		r = await _feed().like(post_id)
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return
	p["liked"] = bool(r.get("liked", false))
	p["like_count"] = int(r.get("like_count", 0))
	if cards.has(post_id):
		PostCard.update(cards[post_id], p)

func open_post(post_id: String) -> void:
	var p := _item(post_id)
	if not p.is_empty():
		_push(AppRoutes.POST, {"post": p})

## 关注 / 取关后重拉资料：计数与关系以服务端为准。
func toggle_follow() -> bool:
	var api := _profile()
	if api == null or user_id().is_empty() or busy:
		return false
	busy = true
	follow_button.disabled = true
	var r: Dictionary
	if is_following():
		r = await api.unfollow(user_id())
	else:
		r = await api.follow(user_id())
	var fresh: Dictionary = {}
	if bool(r.get("ok", false)):
		fresh = await api.get_profile(user_id())
	busy = false
	follow_button.disabled = false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	if bool(fresh.get("ok", false)):
		user = fresh
	_show_user()
	return true

## 发消息：找或建单聊，压栈聊天页。
func open_chat() -> bool:
	var api := _im()
	if api == null or user_id().is_empty() or busy:
		return false
	busy = true
	message_button.disabled = true
	var c: Dictionary = await api.open_dm(user_id())
	busy = false
	message_button.disabled = false
	if not bool(c.get("ok", false)):
		status.text = describe_error(c)
		return false
	_push(AppRoutes.CHAT, {"conversation": c})
	return true

func open_report_menu(target_type: String, id: String) -> void:
	pending_report = {"type": target_type, "id": id}
	_popup(report_menu)

func _on_report_reason(index: int) -> void:
	if index < 0 or index >= SafetyApi.REASONS.size():
		return
	await report(str(pending_report.get("type", "")), str(pending_report.get("id", "")), SafetyApi.REASONS[index])

func report(target_type: String, id: String, reason: String) -> bool:
	var api := _safety()
	if api == null or id.is_empty():
		return false
	var r: Dictionary = await api.report(target_type, id, reason)
	if bool(r.get("ok", false)):
		status.text = tr("Thanks, we've received your report.")
		return true
	status.text = describe_error(r)
	return false

func _on_block_confirmed() -> void:
	await block_user()

## 拉黑后这页没意义了：双向不可见，直接离开。
func block_user() -> bool:
	var api := _safety()
	if api == null or user_id().is_empty():
		return false
	var r: Dictionary = await api.block(user_id())
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	_leave()
	return true

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

func describe_error(r: Dictionary) -> String:
	match str(r.get("code", "")):
		"NOT_FOUND":
			return tr("This user isn't available.")
		"SELF_FOLLOW", "SELF_DM", "SELF_BLOCK", "SELF_REPORT":
			return tr("That's you.")
		"BLOCKED":
			return tr("You can't message this user.")
		"NETWORK":
			return tr("Can't reach the server. Check your connection and try again.")
		_:
			return str(r.get("code", "UNKNOWN"))

func _popup(p: Window) -> void:
	if is_inside_tree():
		p.popup_centered()

func _push(route: String, args: Dictionary) -> void:
	if navigate.is_valid():
		navigate.call(route, args)
	else:
		AppRouter.push_instance(route, args)

func _leave() -> void:
	if leave_handler.is_valid():
		leave_handler.call()
	else:
		AppRouter.pop_instance()
