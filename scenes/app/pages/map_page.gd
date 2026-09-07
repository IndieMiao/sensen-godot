extends AppPage
## 地图主页（B5）：Mapbox 原生 view 垫底 + Godot 透明层里的 3D 角色（自己 + 互相关注的好友）+ 地图 HUD。
## 地图场景（map_poc）第一次显示时才实例化，之后只在 Tab 显隐时 resume / suspend——原生 view 显隐、
## 相机 / 环境的归还与回收都在它自己的 suspend / resume 里。
## 位置：只在本页可见时上报（When-In-Use），按时间 + 位移节流；好友位置每 FRIENDS_POLL_S 拉一次。
## auth / location / make_map（返回地图节点的工厂）可注入。

const MAP_SCENE := "res://scenes/map_poc/map_poc.tscn"
const FRIENDS_POLL_S := 30.0
const REPORT_MIN_INTERVAL_S := 30.0
const REPORT_MIN_MOVE_M := 25.0

var auth: AuthSession
var location: LocationApi
var make_map: Callable

var map_scene: Node
var friends: Array = []
var friends_timer: Timer
var shown := false
var last_report_ms := 0
var last_report_lat := 0.0
var last_report_lng := 0.0
var report_count := 0
var busy := false

func _init() -> void:
	page_title = "Map"

func _build_body() -> void:
	# 地图要全屏透出来：本页自己的纸色底与标题栏都不画（HUD 在地图场景里）。
	var backdrop := get_node_or_null("Backdrop")
	if backdrop != null:
		backdrop.visible = false
	title_label.get_parent().visible = false
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
	return true

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
