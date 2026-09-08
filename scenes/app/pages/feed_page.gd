extends AppPage
## 动态 feed（B3 只读闭环 + 纯文字发布；后端 D4-b）：时间线 / 点赞 / 发布器 / 加载更多。
## 图片发布等 D4-c R2 接上传；评论 UI 归 B3 后续。举报 / 拉黑（E1）在每张非本人卡片上。
## auth / feed / safety 可注入。
##
## 发布的幂等键在重试间保持同一个：断网点两次「Post」不会发出两条一样的动态。

var auth: AuthSession
var feed: FeedApi
var safety: SafetyApi
var uploads: UploadApi
var images: ImageCache
var picker: PhotoPicker
## 压栈子页（动态详情 / 用户主页）；默认 AppRouter.push_instance。
var navigate: Callable

var composer: LineEdit
var post_button: Button
var photos_button: Button
var attached_label: Label
## 已选好、待随下一条动态上传的图（ImagePrep 的 item）。
var attached: Array = []
var status: Label
var list: VBoxContainer
var more_button: Button
var refresh_button: Button
var next_cursor := ""
## 服务端返回的帖子字典，按显示顺序。
var items: Array = []
## post id -> {"like": Button, "meta": Label}
var cards: Dictionary = {}
var busy := false
var pending_key := ""
var report_menu: PopupMenu
var block_confirm: ConfirmationDialog
## 举报菜单 / 拉黑确认框当前针对的帖子 id 与作者 id。
var pending_target := {"post_id": "", "author_id": ""}

func _init() -> void:
	page_title = "Feed"

func _build_body() -> void:
	var row := HBoxContainer.new()
	row.name = "Composer"
	row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	composer = LineEdit.new()
	composer.name = "Text"
	composer.placeholder_text = tr("What's new?")
	composer.max_length = 2000
	composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composer.custom_minimum_size.y = 44
	row.add_child(composer)
	photos_button = GameUi.button("", tr("Photos"), "PhotoPicker.pick(9)")
	photos_button.name = "Photos"
	photos_button.pressed.connect(func(): pick_photos())
	row.add_child(photos_button)
	post_button = GameUi.button("", tr("Post"), "POST /posts")
	post_button.name = "Post"
	post_button.pressed.connect(_on_post)
	row.add_child(post_button)
	body.add_child(row)
	attached_label = GameUi.label("", DesignTokens.UI_FONT_CAPTION, GameUi.MUTED)
	attached_label.name = "Attached"
	attached_label.visible = false
	body.add_child(attached_label)
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
	list.add_theme_constant_override("separation", DesignTokens.SPACE_2H)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	body.add_child(scroll)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	refresh_button = GameUi.button("", tr("Refresh"), "GET /feed")
	refresh_button.name = "Refresh"
	refresh_button.pressed.connect(func(): refresh())
	actions.add_child(refresh_button)
	more_button = GameUi.button("", tr("Load more"), "GET /feed?cursor")
	more_button.name = "More"
	more_button.visible = false
	more_button.pressed.connect(func(): load_more())
	actions.add_child(more_button)
	body.add_child(actions)
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

func _session() -> AuthSession:
	return auth if auth != null else Net.auth

func _feed() -> FeedApi:
	return feed if feed != null else Net.feed

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

## 选最多 9 张，先挂在发布器上，随下一条动态一起上传。
func pick_photos() -> bool:
	if busy:
		return false
	var picked: Dictionary = await _picker().pick(FeedApi.POST_IMAGES_MAX)
	if not bool(picked.get("ok", false)):
		status.text = describe_error(picked)
		return false
	var items: Array = picked.get("items", []) if picked.get("items") is Array else []
	if items.is_empty():
		return false
	attached = items
	attached_label.text = tr("%d photos attached") % attached.size()
	attached_label.visible = true
	return true

## Dev 会话没有真 token；服务端没部署时不刷屏报错，只给一句提示。
func _can_load() -> bool:
	var s := _session()
	return s != null and s.is_signed_in() and s.provider != "dev" and _feed() != null

func on_tab_shown() -> void:
	super()
	await refresh()

func refresh() -> bool:
	if not _can_load():
		status.text = tr("Nothing here yet. Follow people to see their posts.")
		return false
	if busy:
		return false
	busy = true
	var r: Dictionary = await _feed().timeline()
	busy = false
	if not bool(r.get("ok", false)):
		status.text = tr("Can't load the feed. Check your connection.")
		return false
	items = r.get("items", []) if r.get("items") is Array else []
	next_cursor = _text(r.get("next_cursor"))
	_render()
	return true

func load_more() -> bool:
	if not _can_load() or busy or next_cursor.is_empty():
		return false
	busy = true
	var r: Dictionary = await _feed().timeline(next_cursor)
	busy = false
	if not bool(r.get("ok", false)):
		status.text = tr("Can't load the feed. Check your connection.")
		return false
	for p in r.get("items", []):
		items.append(p)
	next_cursor = _text(r.get("next_cursor"))
	_render()
	return true

## 发布纯文字动态。返回是否成功。
func publish() -> bool:
	var text := composer.text.strip_edges()
	if (text.is_empty() and attached.is_empty()) or busy or _feed() == null:
		return false
	if pending_key.is_empty():
		pending_key = ApiClient.new_idempotency_key()
	busy = true
	post_button.disabled = true
	var image_refs: Array = []
	if not attached.is_empty():
		if _uploads() == null:
			busy = false
			post_button.disabled = false
			return false
		status.text = tr("Uploading…")
		var up: Dictionary = await _uploads().upload_images(attached)
		if not bool(up.get("ok", false)):
			busy = false
			post_button.disabled = false
			status.text = describe_error(up)
			return false
		image_refs = up.get("images", [])
	status.text = tr("Posting…")
	var r: Dictionary = await _feed().create_post(text, image_refs, pending_key)
	busy = false
	post_button.disabled = false
	if bool(r.get("ok", false)):
		_track("post_published", {"images": image_refs.size()})
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	pending_key = ""
	composer.text = ""
	attached = []
	attached_label.visible = false
	items.push_front(r)
	_render()
	status.text = tr("Posted.")
	return true

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
	_update_card(post_id)

func describe_error(r: Dictionary) -> String:
	match str(r.get("code", "")):
		"NETWORK":
			return tr("Can't reach the server. Check your connection and try again.")
		"SCHEMA":
			return tr("Please check the %s field.") % str(r.get("field", ""))
		"NO_ACCOUNT":
			return tr("Sign in again to set up your profile.")
		_:
			return str(r.get("code", "UNKNOWN"))

static func _text(v: Variant) -> String:
	return "" if v == null else str(v)

## 相对时间：列表里「3h ago」比完整时间戳好读。
func age_text(now_ms: int, created_ms: int) -> String:
	return PostCard.age_text(now_ms, created_ms)

func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func _item(post_id: String) -> Dictionary:
	for p in items:
		if str(p.get("id", "")) == post_id:
			return p
	return {}

func _render() -> void:
	# 直接 free 而不是 queue_free：重绘只在按钮回调里发生，卡片不在自己的信号里被释放；
	# queue_free 会让摘下来的卡片挂到帧尾，gdUnit 会把它们算成孤儿。
	for c in list.get_children():
		list.remove_child(c)
		c.free()
	cards.clear()
	for p in items:
		list.add_child(_card(p))
	more_button.visible = not next_cursor.is_empty()
	status.text = tr("Nothing here yet. Follow people to see their posts.") if items.is_empty() else ""

func _card(p: Dictionary) -> PanelContainer:
	var id := _text(p.get("id", ""))
	var panel := PostCard.build(p, card_ctx())
	cards[id] = panel
	return panel

## 三处列表（feed / 用户主页 / 详情）共用的卡片回调。
func card_ctx() -> Dictionary:
	var s := _session()
	return {
		"me_id": s.server_user_id if s != null else "", "now_ms": _now_ms, "images": _images(), "image_url": image_url,
		"on_like": toggle_like, "on_comments": open_post, "on_author": open_user,
		"on_report": open_report_menu, "on_block": open_block_confirm,
	}

func _update_card(post_id: String) -> void:
	var p := _item(post_id)
	if p.is_empty() or not cards.has(post_id):
		return
	PostCard.update(cards[post_id], p)

func open_post(post_id: String) -> void:
	var p := _item(post_id)
	if p.is_empty():
		return
	_push(AppRoutes.POST, {"post": p})

func open_user(author: Dictionary) -> void:
	var id := _text(author.get("user_id", ""))
	if id.is_empty():
		return
	_push(AppRoutes.USER, {"user_id": id})

func _push(route: String, args: Dictionary) -> void:
	if navigate.is_valid():
		navigate.call(route, args)
	else:
		AppRouter.push_instance(route, args)

func _is_me(author_id: String) -> bool:
	var s := _session()
	return s != null and not author_id.is_empty() and author_id == s.server_user_id

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

func open_report_menu(post_id: String, author_id: String) -> void:
	pending_target = {"post_id": post_id, "author_id": author_id}
	report_menu.popup_centered()

func open_block_confirm(post_id: String, author_id: String) -> void:
	pending_target = {"post_id": post_id, "author_id": author_id}
	block_confirm.popup_centered()

func _on_report_reason(index: int) -> void:
	if index < 0 or index >= SafetyApi.REASONS.size():
		return
	await report_post(str(pending_target.post_id), SafetyApi.REASONS[index])

## 举报一条动态。服务端同一人同一目标只记一条，重复点也只会告诉用户「已收到」。
func report_post(post_id: String, reason: String) -> bool:
	var api := _safety()
	if api == null or post_id.is_empty():
		return false
	var r: Dictionary = await api.report("post", post_id, reason)
	if bool(r.get("ok", false)):
		_track("content_reported", {"target": "post", "reason": reason})
		status.text = tr("Thanks, we've received your report.")
		return true
	status.text = describe_error(r)
	return false

func _on_block_confirmed() -> void:
	await block_author(str(pending_target.author_id))

## 拉黑作者：服务端双向不可见；本地立刻把这个人的卡片全撤掉，不等下一次刷新。
func block_author(author_id: String) -> bool:
	var api := _safety()
	if api == null or author_id.is_empty():
		return false
	var r: Dictionary = await api.block(author_id)
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	items = items.filter(func(p): return _text((p.get("author", {}) as Dictionary).get("user_id", "")) != author_id)
	_render()
	status.text = tr("Blocked. You won't see their posts anymore.")
	return true

func _on_post() -> void:
	await publish()
