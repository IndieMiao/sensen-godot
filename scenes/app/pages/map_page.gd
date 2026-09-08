extends AppPage
## 地图主页（B5）：Mapbox 原生 view 垫底 + Godot 透明层里的 3D 角色（自己 + 互相关注的好友）+ 地图 HUD。
## 地图场景（map_poc）第一次显示时才实例化，之后只在 Tab 显隐时 resume / suspend——原生 view 显隐、
## 相机 / 环境的归还与回收都在它自己的 suspend / resume 里。
## 位置：只在本页可见时上报（When-In-Use），按时间 + 位移节流；好友位置每 FRIENDS_POLL_S 拉一次。
## auth / location / make_map（返回地图节点的工厂）可注入。

const MAP_SCENE := "res://scenes/map_poc/map_poc.tscn"
const FRIENDS_POLL_S := 30.0
## 好友条高度；地图 HUD 要在它之上收边。
const FRIEND_STRIP_H := 72.0
const REPORT_MIN_INTERVAL_S := 30.0
const REPORT_MIN_MOVE_M := 25.0

var auth: AuthSession
var location: LocationApi
var navigate: Callable
var make_map: Callable

var map_scene: Node
var friends: Array = []
var friends_timer: Timer
var shown := false
## 原生地图层是否在出画；false 时本页盖一层纸色底，免得透明视口下面是纯黑。
var presenting := false
var backdrop: ColorRect
## 底部好友条：头像 + 昵称，点进他的主页。没有好友时整条隐藏。
var strip_panel: PanelContainer
var strip: HBoxContainer
var strip_empty: Label
var last_report_ms := 0
var last_report_lat := 0.0
var last_report_lng := 0.0
var report_count := 0
var busy := false

func _init() -> void:
	page_title = "Map"

func _build_body() -> void:
	# 地图要全屏透出来：本页自己的纸色底与标题栏都不画（HUD 在地图场景里）。
	# 本页根 Control 默认 mouse_filter = STOP 会把整屏触摸吃掉，map_poc 的 _unhandled_input 永远收不到手势
	#（2026-09-08 真机：地图完全拖不动）。改成 IGNORE，空白处的触摸一路落到 unhandled。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# AppPage 建的 SafeArea / 列 / body 都是满屏容器，默认同样吃触摸——只放开根节点不够。
	for node in [get_node_or_null("SafeArea"), body, body.get_parent() if body != null else null]:
		if node is Control:
			(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop = get_node_or_null("Backdrop") as ColorRect
	if backdrop != null:
		backdrop.visible = true # 地图出画前先盖住，_on_presented 再决定
	title_label.get_parent().visible = false
	# 好友条压在壳的底栏之上；地图 HUD 的安全区也要给这两样让位（见 ensure_map）。
	strip_panel = PanelContainer.new()
	strip_panel.name = "Friends"
	strip_panel.add_theme_stylebox_override("panel", GameUi.surface(GameUi.PAPER, DesignTokens.SPACE_2))
	strip_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip_panel.offset_top = -FRIEND_STRIP_H
	strip_panel.offset_left = DesignTokens.SPACE_2
	strip_panel.offset_right = -DesignTokens.SPACE_2
	strip_panel.offset_bottom = -DesignTokens.SPACE_2
	strip_panel.visible = false
	add_child(strip_panel)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip_panel.add_child(scroll)
	strip = HBoxContainer.new()
	strip.name = "Strip"
	strip.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	scroll.add_child(strip)
	strip_empty = GameUi.label("", DesignTokens.UI_FONT_CAPTION, GameUi.MUTED)
	strip_empty.name = "StripEmpty"
	strip.add_child(strip_empty)
	friends_timer = Timer.new()
	friends_timer.name = "FriendsTimer"
	friends_timer.wait_time = FRIENDS_POLL_S
	friends_timer.one_shot = false
	friends_timer.timeout.connect(func(): refresh_friends())
	add_child(friends_timer)

func _session() -> AuthSession:
	return auth if auth != null else Net.auth

func _location() -> LocationApi:
	if location != null:
		return location
	return Net.location if get_node_or_null("/root/Net") != null else null

func _can_load() -> bool:
	var s := _session()
	return s != null and s.is_signed_in() and s.provider != "dev" and _location() != null

## 第一次显示才建地图场景（登录前壳不存在，登录后地图是首页）。
func ensure_map() -> Node:
	if map_scene != null:
		return map_scene
	if make_map.is_valid():
		map_scene = make_map.call()
	else:
		map_scene = (load(MAP_SCENE) as PackedScene).instantiate()
	if "demo_cohorts" in map_scene:
		map_scene.demo_cohorts = false
	if map_scene.has_signal("location_changed"):
		map_scene.location_changed.connect(_on_location)
	if map_scene.has_signal("presented"):
		map_scene.presented.connect(_on_presented)
	if map_scene.has_signal("friend_tapped"):
		map_scene.friend_tapped.connect(open_user)
	# 地图 HUD 的安全区不知道壳底栏与好友条的存在，自己会贴到屏幕底：这里替它让位。
	var hud_safe := map_scene.get_node_or_null("HUD/SafeArea")
	if hud_safe != null and "extra_bottom" in hud_safe:
		hud_safe.extra_bottom = AppShell.TAB_BAR_HEIGHT + FRIEND_STRIP_H
	map_scene.name = "MapScene"
	add_child(map_scene)
	return map_scene

func on_tab_shown() -> void:
	super()
	shown = true
	var first := map_scene == null
	ensure_map()
	# 场景刚建好时 _ready 已经把地图亮出来，不必再 resume；之后每次回到本页才恢复。
	if not first and map_scene.has_method("resume"):
		map_scene.resume()
	if not friends.is_empty() and map_scene.has_method("set_friends"):
		map_scene.set_friends(friends)
	friends_timer.start()
	await refresh_friends()

## 原生地图出画了就撤掉纸色底（让 Mapbox 透上来）；没出画就一直盖着。
func _on_presented(ok: bool) -> void:
	presenting = ok
	if backdrop != null:
		backdrop.visible = not ok

func on_tab_hidden() -> void:
	super()
	shown = false
	friends_timer.stop()
	if map_scene != null and map_scene.has_method("suspend"):
		map_scene.suspend()

## 拉好友位置并交给地图摆角色。
func refresh_friends() -> bool:
	if not shown or not _can_load() or busy:
		return false
	busy = true
	var r: Dictionary = await _location().friends()
	busy = false
	if not bool(r.get("ok", false)):
		return false
	friends = r.get("items", []) if r.get("items") is Array else []
	if map_scene != null and map_scene.has_method("set_friends"):
		map_scene.set_friends(friends)
	_render_strip()
	return true

## 好友条：一人一格（头像 + 昵称），点进主页。没有好友就整条收起来。
func _render_strip() -> void:
	for c in strip.get_children():
		if c != strip_empty:
			strip.remove_child(c)
			c.free()
	strip_panel.visible = not friends.is_empty()
	strip_empty.visible = friends.is_empty()
	for f in friends:
		if f is Dictionary:
			strip.add_child(_friend_chip(f))

func _friend_chip(f: Dictionary) -> Button:
	var uid := str(f.get("user_id", ""))
	var b := Button.new()
	b.name = "Friend_%s" % uid
	b.theme_type_variation = &"SecondaryButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(DesignTokens.UI_TOUCH_MIN, DesignTokens.UI_TOUCH_MIN)
	var name := str(f.get("display_name", ""))
	b.text = name if not name.is_empty() else "@" + str(f.get("handle", ""))
	b.expand_icon = true
	var thumb := AvatarThumb.new(36.0)
	thumb.name = "Avatar"
	thumb.visible = false
	b.add_child(thumb)
	b.icon = thumb.placeholder_icon()
	thumb.texture_ready.connect(func(tex: Texture2D): AvatarThumb.apply_to_button(b, tex))
	thumb.show_avatar(f.get("avatar"))
	b.pressed.connect(func(): open_user(uid))
	return b

## 进某人的主页（好友条与点地图角色共用）。
func open_user(user_id: String) -> void:
	if user_id.strip_edges().is_empty():
		return
	if navigate.is_valid():
		navigate.call(AppRoutes.USER, {"user_id": user_id})
	else:
		AppRouter.push_instance(AppRoutes.USER, {"user_id": user_id})

## 定位回传：本页可见且登录时上报，30 s 内只报一次，挪动不到 25 m 也不报。
func _on_location(lat: float, lng: float, accuracy: float) -> void:
	if not shown or not _can_load():
		return
	var now := Time.get_ticks_msec()
	if report_count > 0:
		var moved := MapGeoMath.geo_to_world(lat, lng, last_report_lat, last_report_lng).length()
		if now - last_report_ms < int(REPORT_MIN_INTERVAL_S * 1000.0) and moved < REPORT_MIN_MOVE_M:
			return
	last_report_ms = now
	last_report_lat = lat
	last_report_lng = lng
	report_count += 1
	await _location().report(lat, lng, accuracy)
