class_name PostCard
extends RefCounted
## feed 卡片的统一构造：feed 时间线、用户主页的动态列表、动态详情页共用一套结构与节点名
## （Post_<id> / Author / Text / Pictures / Like / Meta / Report / Block），行为通过 ctx 里的回调注入。
## ctx: {me_id, now_ms: Callable, images: ImageCache, image_url: Callable(key),
##       on_like(id), on_comments(id), on_author(author: Dictionary), on_report(id, author_id), on_block(id, author_id)}

const THUMB := Vector2(96, 96)

static func _text(v: Variant) -> String:
	return "" if v == null else str(v)

static func build(p: Dictionary, ctx: Dictionary) -> PanelContainer:
	var id := _text(p.get("id", ""))
	var panel := PanelContainer.new()
	panel.name = "Post_%s" % id
	panel.add_theme_stylebox_override("panel", GameUi.surface())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", DesignTokens.SPACE_1H)
	panel.add_child(col)
	var author: Dictionary = p.get("author", {}) if p.get("author") is Dictionary else {}
	var handle := _text(author.get("handle", ""))
	var who := _text(author.get("display_name", ""))
	if not handle.is_empty():
		who += " @%s" % handle
	var now_ms: int = int(ctx.now_ms.call()) if ctx.get("now_ms") is Callable and (ctx.now_ms as Callable).is_valid() else int(Time.get_unix_time_from_system() * 1000.0)
	var head_row := HBoxContainer.new()
	head_row.name = "Head"
	head_row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	var thumb := AvatarThumb.new(28.0)
	thumb.name = "Avatar"
	head_row.add_child(thumb)
	thumb.show_avatar(author.get("avatar"))
	var head := GameUi.label("%s · %s" % [who, age_text(now_ms, int(p.get("created_at", 0)))], 12, GameUi.MUTED)
	head.name = "Author"
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var on_author: Callable = ctx.get("on_author", Callable())
	if on_author.is_valid():
		# 点作者名或头像进主页：Label / TextureRect 默认不收输入，这里让它们吃点击。
		var tap := func(e: InputEvent):
			if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
				on_author.call(author)
		head.mouse_filter = Control.MOUSE_FILTER_STOP
		head.gui_input.connect(tap)
		thumb.mouse_filter = Control.MOUSE_FILTER_STOP
		thumb.gui_input.connect(tap)
	head_row.add_child(head)
	col.add_child(head_row)
	var text := GameUi.label(_text(p.get("text", "")), DesignTokens.UI_FONT_BODY)
	text.name = "Text"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.visible = not text.text.is_empty()
	col.add_child(text)
	var pics: Array = p.get("images", []) if p.get("images") is Array else []
	if not pics.is_empty():
		var strip := HBoxContainer.new()
		strip.name = "Pictures"
		strip.add_theme_constant_override("separation", DesignTokens.SPACE_1H)
		var images: ImageCache = ctx.get("images")
		var image_url: Callable = ctx.get("image_url", Callable())
		for im in pics:
			if not (im is Dictionary):
				continue
			var frame := PanelContainer.new()
			frame.add_theme_stylebox_override("panel", GameUi.surface(GameUi.PAPER, 0, 6))
			var pic := PictureView.new()
			pic.name = "Picture"
			frame.add_child(pic)
			strip.add_child(frame)
			var url := str(image_url.call(_text(im.get("key", "")))) if image_url.is_valid() else ""
			pic.show_picture(images, url, int(im.get("w", 0)), int(im.get("h", 0)), THUMB)
		col.add_child(strip)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	var like := GameUi.button("", "", "PUT/DELETE /posts/:id/like")
	like.name = "Like"
	var on_like: Callable = ctx.get("on_like", Callable())
	if on_like.is_valid():
		like.pressed.connect(func(): on_like.call(id))
	actions.add_child(like)
	var meta := GameUi.button("", "", "GET /posts/:id/comments")
	meta.name = "Meta"
	meta.theme_type_variation = &"SecondaryButton"
	meta.focus_mode = Control.FOCUS_NONE
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var on_comments: Callable = ctx.get("on_comments", Callable())
	if on_comments.is_valid():
		meta.pressed.connect(func(): on_comments.call(id))
	actions.add_child(meta)
	var author_id := _text(author.get("user_id", ""))
	if not author_id.is_empty() and author_id != _text(ctx.get("me_id", "")):
		var on_report: Callable = ctx.get("on_report", Callable())
		if on_report.is_valid():
			var report := GameUi.button("", tr_s("Report"), "POST /reports")
			report.name = "Report"
			report.pressed.connect(func(): on_report.call(id, author_id))
			actions.add_child(report)
		var on_block: Callable = ctx.get("on_block", Callable())
		if on_block.is_valid():
			var block := GameUi.button("", tr_s("Block"), "PUT /users/:id/block")
			block.name = "Block"
			block.pressed.connect(func(): on_block.call(id, author_id))
			actions.add_child(block)
	col.add_child(actions)
	update(panel, p)
	return panel

## 点赞数 / 评论数变了只改文字，不重建卡片。
static func update(card: Node, p: Dictionary) -> void:
	var like := card.find_child("Like", true, false) as Button
	if like != null:
		like.text = "%s %d" % [tr_s("Liked") if bool(p.get("liked", false)) else tr_s("Like"), int(p.get("like_count", 0))]
	var meta := card.find_child("Meta", true, false) as Button
	if meta != null:
		meta.text = tr_s("%d comments") % int(p.get("comment_count", 0))

## 静态方法里没有 self.tr：走 TranslationServer；字串仍由 feed_page 里的 tr() 抽取。
static func tr_s(s: String) -> String:
	return TranslationServer.translate(s)

## 相对时间：刚刚 / n 分钟 / n 小时 / n 天（文案键与 feed_page 原有的一致，翻译已在 PO 里）。
static func age_text(now_ms: int, created_ms: int) -> String:
	var d := maxi(0, now_ms - created_ms) / 1000
	if d < 60:
		return tr_s("just now")
	if d < 3600:
		return tr_s("%dm ago") % int(d / 60)
	if d < 86400:
		return tr_s("%dh ago") % int(d / 3600)
	return tr_s("%dd ago") % int(d / 86400)
