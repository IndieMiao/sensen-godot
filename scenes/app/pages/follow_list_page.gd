class_name FollowListPage
extends AppPage
## 关注者 / 关注中 / 新粉丝列表（压栈，B4 收尾）。setup({"user_id": uuid, "kind": "followers"|"following"|"new"})。
## 行 = 头像 + 昵称 @handle + 关系角标；点行进用户主页。「关注中」列表被对方关掉可见时服务端 403，这里给一句解释。
## auth / profile / navigate 可注入。

const KIND_FOLLOWERS := "followers"
const KIND_FOLLOWING := "following"
const KIND_NEW := "new"

var auth: AuthSession
var profile: ProfileApi
var navigate: Callable

var target := ""
var kind := KIND_FOLLOWERS
var status: Label
var list: VBoxContainer
var more_button: Button
var items: Array = []
var next_cursor := ""
var busy := false
var loading := false
var loaded := false

func _init() -> void:
	page_title = "Followers"
	stacked = true

func setup(args: Dictionary) -> void:
	target = str(args.get("user_id", ""))
	kind = str(args.get("kind", KIND_FOLLOWERS))
	match kind:
		KIND_FOLLOWING: page_title = "Following"
		KIND_NEW: page_title = "New followers"
		_: page_title = "Followers"

func _build_body() -> void:
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
	more_button = GameUi.button("", tr("Load more"), "GET …?cursor")
	more_button.name = "More"
	more_button.visible = false
	more_button.pressed.connect(func(): fetch(true))
	body.add_child(more_button)
	call_deferred("fetch")

func _session() -> AuthSession:
	return auth if auth != null else Net.auth

func _profile() -> ProfileApi:
	return profile if profile != null else Net.profile

func my_id() -> String:
	var s := _session()
	return s.server_user_id if s != null else ""

static func _text(v: Variant) -> String:
	return "" if v == null else str(v)

## 拉一页（more=true 翻下一页）。名字不叫 load：会和全局 load(path) 撞。
func fetch(more := false) -> bool:
	var api := _profile()
	if api == null or (loading and not more) or (loaded and not more) or busy:
		return false
	if more and next_cursor.is_empty():
		return false
	if kind != KIND_NEW and target.is_empty():
		return false
	loading = true
	busy = true
	var cursor := next_cursor if more else ""
	var r: Dictionary
	match kind:
		KIND_FOLLOWING: r = await api.following(target, cursor)
		KIND_NEW: r = await api.new_followers(cursor)
		_: r = await api.followers(target, cursor)
	busy = false
	loading = false
	if not bool(r.get("ok", false)):
		status.text = describe_error(r)
		return false
	loaded = true
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
	for u in items:
		if u is Dictionary:
			list.add_child(_row(u))
	if items.is_empty():
		status.text = empty_text()
	else:
		status.text = ""

func empty_text() -> String:
	match kind:
		KIND_FOLLOWING: return tr("Not following anyone yet.")
		KIND_NEW: return tr("No new followers.")
		_: return tr("No followers yet.")

## 关系角标：互关 > 关注了你 > 已关注；自己不标。
func relation_text(u: Dictionary) -> String:
	if _text(u.get("user_id", "")) == my_id():
		return tr("You")
	var rel: Dictionary = u.get("relation", {}) if u.get("relation") is Dictionary else {}
	if bool(rel.get("close_friends", false)):
		return tr("Close friends")
	if bool(rel.get("followed_by", false)):
		return tr("Follows you")
	if bool(rel.get("following", false)):
		return tr("Following")
	return ""

func _row(u: Dictionary) -> Button:
	var b := Button.new()
	b.name = "User_%s" % _text(u.get("user_id", ""))
	b.theme_type_variation = &"SecondaryButton"
	b.custom_minimum_size.y = 56
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	var name := _text(u.get("display_name", ""))
	var handle := _text(u.get("handle", ""))
	var who := name if not name.is_empty() else tr("Someone")
	if not handle.is_empty():
		who += " @%s" % handle
	var rel := relation_text(u)
	b.text = who if rel.is_empty() else "%s\n%s" % [who, rel]
	# 缩略图控件只负责取图，不显示；可见的是按钮 icon。先连信号再取图：命中缓存时信号是同步发的。
	var thumb := AvatarThumb.new(44.0)
	thumb.name = "Avatar"
	thumb.visible = false
	b.add_child(thumb)
	b.add_theme_constant_override("h_separation", DesignTokens.SPACE_2)
	b.add_theme_constant_override("icon_max_width", 44)
	b.icon = thumb.placeholder_icon()
	b.expand_icon = true
	thumb.texture_ready.connect(func(tex: Texture2D): AvatarThumb.apply_to_button(b, tex))
	thumb.show_avatar(u.get("avatar"))
	b.pressed.connect(func(): open_user(_text(u.get("user_id", ""))))
	return b

func open_user(user_id: String) -> void:
	if user_id.is_empty():
		return
	if user_id == my_id():
		return
	_push(AppRoutes.USER, {"user_id": user_id})

func describe_error(r: Dictionary) -> String:
	match str(r.get("code", "")):
		"FOLLOWING_PRIVATE":
			return tr("This user keeps their following list private.")
		"NOT_FOUND":
			return tr("This user isn't available.")
		"NETWORK":
			return tr("Can't reach the server. Check your connection and try again.")
		_:
			return str(r.get("code", "UNKNOWN"))

func _push(route: String, args: Dictionary) -> void:
	if navigate.is_valid():
		navigate.call(route, args)
	else:
		AppRouter.push_instance(route, args)
