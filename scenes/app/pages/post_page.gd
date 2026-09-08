extends AppPage
## 动态详情（压栈，B3 一级评论）：卡片 + 评论列表 + 评论框。别人的评论可举报（target comment）、作者可拉黑；
## 自己的评论可删。setup({"post": 帖子字典} 或 {"post_id": id})。auth / feed / safety / images / navigate 可注入。

var auth: AuthSession
var feed: FeedApi
var safety: SafetyApi
var images: ImageCache
var navigate: Callable
## 拉黑帖子作者后离开本页；默认 AppRouter.pop_instance。
var leave_handler: Callable

var post: Dictionary = {}
var post_id := ""
var comments: Array = []
var card: PanelContainer
var card_slot: VBoxContainer
var comment_list: VBoxContainer
var composer: LineEdit
var send_button: Button
var status: Label
var more_button: Button
var next_cursor := ""
var busy := false
var loading := false
var loaded := false
var report_menu: PopupMenu
var block_confirm: ConfirmationDialog
var pending_report: Dictionary = {}
var block_target := ""

func _init() -> void:
	keyboard_mode = KeyboardAvoider.Mode.SHRINK
	page_title = "Post"
	stacked = true

func setup(args: Dictionary) -> void:
	post = args.get("post", {}) if args.get("post") is Dictionary else {}
	post_id = _text(post.get("id", "")) if not post.is_empty() else str(args.get("post_id", ""))

func _build_body() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", DesignTokens.SPACE_2H)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	card_slot = VBoxContainer.new()
	card_slot.name = "CardSlot"
	col.add_child(card_slot)
	var heading := GameUi.label(tr("Comments"), DesignTokens.UI_FONT_BODY, GameUi.MUTED)
	heading.name = "CommentsHeading"
	col.add_child(heading)
	comment_list = VBoxContainer.new()
	comment_list.name = "Comments"
	comment_list.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	col.add_child(comment_list)
	more_button = GameUi.button("", tr("Load more"), "GET /posts/:id/comments?cursor")
	more_button.name = "More"
	more_button.visible = false
	more_button.pressed.connect(func(): load_comments(true))
	col.add_child(more_button)
	body.add_child(scroll)
	status = GameUi.label("", DesignTokens.UI_FONT_CAPTION, GameUi.MUTED)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	var row := HBoxContainer.new()
	row.name = "Composer"
	row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	composer = LineEdit.new()
	composer.name = "Text"
	composer.placeholder_text = tr("Write a comment…")
	composer.max_length = 500
	composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composer.custom_minimum_size.y = 44
	composer.text_submitted.connect(func(_t): add_comment())
	row.add_child(composer)
	send_button = GameUi.button("", tr("Send"), "POST /posts/:id/comments")
	send_button.name = "Send"
	send_button.pressed.connect(func(): add_comment())
	row.add_child(send_button)
	body.add_child(row)
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

func _feed() -> FeedApi:
	return feed if feed != null else Net.feed

func _safety() -> SafetyApi:
	return safety if safety != null else Net.safety

func _images() -> ImageCache:
	return images if images != null else Net.images

func image_url(key: String) -> String:
	return Net.file_url(key)

func my_id() -> String:
	var s := _session()
	return s.server_user_id if s != null else ""

static func _text(v: Variant) -> String:
	return "" if v == null else str(v)

## 没带帖子字典就先拉一次；然后卡片 + 第一页评论。
func load() -> bool:
	if loading or loaded or _feed() == null or post_id.is_empty():
		return false
	loading = true
	if post.is_empty():
		var r: Dictionary = await _feed().get_post(post_id)
		if not bool(r.get("ok", false)):
			status.text = describe_error(r)
			loading = false
			return false
		post = r
	_render_card()
	var ok := await load_comments(false)
	loaded = ok
	loading = false
	return ok

func _render_card() -> void:
	for c in card_slot.get_children():
		card_slot.remove_child(c)
		c.free()
	card = PostCard.build(post, {
		"me_id": my_id(), "images": _images(), "image_url": image_url,
		"on_like": toggle_like, "on_author": open_user,
		"on_report": func(id: String, _author_id: String): open_report_menu("post", id),
		"on_block": func(_id: String, author_id: String): open_block_confirm(author_id),
	})
	card_slot.add_child(card)

func toggle_like(_id: String) -> void:
	if _feed() == null:
		return
	var r: Dictionary
	if bool(post.get("liked", false)):
		r = await _feed().unlike(post_id)
	else:
		r = await _feed().like(post_id)
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return
	post["liked"] = bool(r.get("liked", false))
	post["like_count"] = int(r.get("like_count", 0))
	if post["liked"]:
		_track("post_liked", {"from": "post"})
	PostCard.update(card, post)

func open_user(author: Dictionary) -> void:
	var id := _text(author.get("user_id", ""))
	if not id.is_empty():
		_push(AppRoutes.USER, {"user_id": id})

func load_comments(more: bool) -> bool:
	if _feed() == null or busy or (more and next_cursor.is_empty()):
		return false
	busy = true
	var r: Dictionary = await _feed().comments(post_id, next_cursor if more else "")
	busy = false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	var page: Array = r.get("items", []) if r.get("items") is Array else []
	if not more:
		comments = []
		for c in comment_list.get_children():
			comment_list.remove_child(c)
			c.free()
	for c in page:
		if c is Dictionary:
			comments.append(c)
			comment_list.add_child(_row(c))
	next_cursor = _text(r.get("next_cursor", ""))
	more_button.visible = not next_cursor.is_empty()
	return true

func _row(c: Dictionary) -> PanelContainer:
	var id := _text(c.get("id", ""))
	var panel := PanelContainer.new()
	panel.name = "Comment_%s" % id
	panel.add_theme_stylebox_override("panel", GameUi.surface(GameUi.PAPER, 8, 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", DesignTokens.SPACE_1)
	panel.add_child(col)
	var author: Dictionary = c.get("author", {}) if c.get("author") is Dictionary else {}
	var who := _text(author.get("display_name", ""))
	var handle := _text(author.get("handle", ""))
	if not handle.is_empty():
		who += " @%s" % handle
	var head := GameUi.label("%s · %s" % [who, PostCard.age_text(int(Time.get_unix_time_from_system() * 1000.0), int(c.get("created_at", 0)))], DesignTokens.UI_FONT_CAPTION, GameUi.MUTED)
	head.name = "Author"
	col.add_child(head)
	var text := GameUi.label(_text(c.get("text", "")), DesignTokens.UI_FONT_BODY)
	text.name = "Text"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	var author_id := _text(author.get("user_id", ""))
	if author_id == my_id():
		var del := GameUi.button("", tr("Delete"), "DELETE /comments/:id")
		del.name = "Delete"
		del.pressed.connect(func(): delete_comment(id))
		actions.add_child(del)
	else:
		var report := GameUi.button("", tr("Report"), "POST /reports")
		report.name = "Report"
		report.pressed.connect(func(): open_report_menu("comment", id))
		actions.add_child(report)
		var block := GameUi.button("", tr("Block"), "PUT /users/:id/block")
		block.name = "Block"
		block.pressed.connect(func(): open_block_confirm(author_id))
		actions.add_child(block)
	col.add_child(actions)
	return panel

func add_comment() -> bool:
	var text := composer.text.strip_edges()
	if text.is_empty() or busy or _feed() == null:
		return false
	busy = true
	send_button.disabled = true
	var r: Dictionary = await _feed().add_comment(post_id, text)
	busy = false
	send_button.disabled = false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	composer.text = ""
	status.text = ""
	comments.append(r)
	comment_list.add_child(_row(r))
	post["comment_count"] = int(post.get("comment_count", 0)) + 1
	_track("comment_added")
	PostCard.update(card, post)
	return true

func delete_comment(id: String) -> bool:
	if _feed() == null:
		return false
	var r: Dictionary = await _feed().delete_comment(id)
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	for i in range(comments.size() - 1, -1, -1):
		if _text(comments[i].get("id", "")) == id:
			comments.remove_at(i)
	var row := comment_list.get_node_or_null("Comment_%s" % id)
	if row != null:
		comment_list.remove_child(row)
		row.free()
	post["comment_count"] = maxi(0, int(post.get("comment_count", 0)) - 1)
	PostCard.update(card, post)
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
		_track("content_reported", {"target": target_type, "reason": reason})
		status.text = tr("Thanks, we've received your report.")
		return true
	status.text = describe_error(r)
	return false

func open_block_confirm(author_id: String) -> void:
	block_target = author_id
	_popup(block_confirm)

func _on_block_confirmed() -> void:
	await block_user(block_target)

## 拉黑评论作者：把这个人的评论从本页撤掉；拉黑帖子作者：整页没意义了，回上一页。
func block_user(user_id: String) -> bool:
	var api := _safety()
	if api == null or user_id.is_empty():
		return false
	var r: Dictionary = await api.block(user_id)
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	_track("user_blocked", {"from": "post"})
	var post_author: Dictionary = post.get("author", {}) if post.get("author") is Dictionary else {}
	if _text(post_author.get("user_id", "")) == user_id:
		_leave()
		return true
	for i in range(comments.size() - 1, -1, -1):
		var a: Dictionary = comments[i].get("author", {}) if comments[i].get("author") is Dictionary else {}
		if _text(a.get("user_id", "")) == user_id:
			var row := comment_list.get_node_or_null("Comment_%s" % _text(comments[i].get("id", "")))
			if row != null:
				comment_list.remove_child(row)
				row.free()
			comments.remove_at(i)
	status.text = tr("Blocked.")
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
			return tr("That's no longer available.")
		"MODERATION_REJECTED":
			return tr("This message was blocked by our content rules.")
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
