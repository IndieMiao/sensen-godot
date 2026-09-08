extends GdUnitTestSuite
## B5 地图 Tab 页：首次显示才建地图（演示内容关掉）、显隐驱动 resume / suspend、好友位置拉取并交给地图、
## 定位上报只在可见且登录时发生并按时间 / 位移节流。地图场景用替身，不实例化 map_poc。

class FakeMap extends Node3D:
	signal location_changed(lat: float, lng: float, accuracy: float)
	signal presented(ok: bool)
	signal friend_tapped(user_id: String)
	signal map_tapped()
	var demo_cohorts := true
	var suspended := 0
	var resumed := 0
	var friends_sets: Array = []
	func suspend() -> void:
		suspended += 1
	func resume() -> void:
		resumed += 1
	func set_friends(items: Array) -> void:
		friends_sets.append(items)

class NavRecorder extends RefCounted:
	var calls: Array = []
	func go(route: String, args: Dictionary) -> void:
		calls.append({"route": route, "args": args})

var session: AuthSession
var t: FakeTransport
var fake: FakeMap
var nav: NavRecorder

func before_test() -> void:
	session = AuthSession.new()
	session.complete_sign_in("uid-1", "id-1", "rt-1", 3600, "password", "a@b.co")
	session.set_server_user("me-1")
	t = FakeTransport.new([])
	fake = FakeMap.new()
	nav = NavRecorder.new()

func after_test() -> void:
	# 没被页面收养的替身地图要自己回收，否则 gdUnit 记成 orphan（页面收养过的随页面一起走）。
	if is_instance_valid(fake) and fake.get_parent() == null:
		fake.free()
	if FileAccess.file_exists(AuthSession.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthSession.PATH))

func _page() -> Control:
	var p := (load(AppRoutes.tab_scene("map")) as PackedScene).instantiate()
	p.auth = session
	p.location = LocationApi.new(ApiClient.new("https://example.test/v1", t.callable()))
	p.navigate = nav.go
	p.make_map = func(): return fake
	p.in_shell = true
	add_child(auto_free(p))
	return p

func _friend(id: String, lat: float, lng: float) -> Dictionary:
	return {"user_id": id, "display_name": id, "handle": id, "avatar": null, "lat": lat, "lng": lng, "accuracy_m": null, "updated_at": 0}

func test_first_show_builds_map_without_demo_content_and_pulls_friends() -> void:
	t.responses = [{"status": 200, "json": {"items": [_friend("u-a", 31.2, 121.5)]}}]
	var p := _page()
	assert_object(p.map_scene).is_null()
	assert_bool(p.get_node("Backdrop").visible).is_true() # 地图出画前先盖着（见下一条用例）
	await p.on_tab_shown()
	assert_object(p.map_scene).is_same(fake)
	assert_bool(fake.demo_cohorts).is_false()
	assert_int(fake.resumed).is_equal(0) # 刚建好的场景自己就是亮的，不重复 resume
	assert_bool(str(t.requests[0].url).ends_with("/v1/friends/locations")).is_true()
	assert_int(fake.friends_sets.size()).is_equal(1)
	assert_str(str(fake.friends_sets[0][0].user_id)).is_equal("u-a")
	assert_bool(p.friends_timer.is_stopped()).is_false()
	assert_float(p.friends_timer.wait_time).is_equal(30.0)
	p.on_tab_hidden()
	assert_int(fake.suspended).is_equal(1)
	assert_bool(p.friends_timer.is_stopped()).is_true()
	t.responses.append({"status": 200, "json": {"items": []}})
	await p.on_tab_shown()
	assert_int(fake.resumed).is_equal(1)
	# 回到本页先用上次的好友列表摆人，再拉新的。
	assert_int(fake.friends_sets.size()).is_equal(3)
	assert_int((fake.friends_sets[2] as Array).size()).is_equal(0)

func test_location_reports_are_throttled_and_only_while_visible_and_signed_in() -> void:
	t.responses = [
		{"status": 200, "json": {"items": []}},
		{"status": 200, "json": {"ok": true, "updated_at": 1}},
		{"status": 200, "json": {"ok": true, "updated_at": 2}},
	]
	var p := _page()
	await p.on_tab_shown()
	fake.location_changed.emit(31.2304, 121.4737, 12.0)
	await get_tree().process_frame
	assert_int(t.requests.size()).is_equal(2)
	assert_str(t.requests[1].method).is_equal("PUT")
	assert_bool(str(t.requests[1].url).ends_with("/v1/location")).is_true()
	assert_that(t.requests[1].body).is_equal({"lat": 31.2304, "lng": 121.4737, "accuracy_m": 12.0})
	# 30 s 内挪了 10 m：不报。
	fake.location_changed.emit(31.2304 + 10.0 / MapGeoMath.M_PER_DEG_LAT, 121.4737, 12.0)
	await get_tree().process_frame
	assert_int(t.requests.size()).is_equal(2)
	# 挪了 100 m：报（位移条件），精度未知时不带 accuracy_m。
	fake.location_changed.emit(31.2304 + 100.0 / MapGeoMath.M_PER_DEG_LAT, 121.4737, -1.0)
	await get_tree().process_frame
	assert_int(t.requests.size()).is_equal(3)
	assert_bool(t.requests[2].body.has("accuracy_m")).is_false()
	# 页面隐藏后不报。
	p.on_tab_hidden()
	fake.location_changed.emit(30.0, 120.0, 5.0)
	await get_tree().process_frame
	assert_int(t.requests.size()).is_equal(3)

func test_dev_session_neither_pulls_friends_nor_reports() -> void:
	session.complete_sign_in("dev", "", "", 3600, "dev", "")
	var p := _page()
	await p.on_tab_shown()
	assert_object(p.map_scene).is_same(fake)
	fake.location_changed.emit(31.0, 121.0, 5.0)
	await get_tree().process_frame
	assert_int(t.requests.size()).is_equal(0)

func test_nothing_on_the_page_eats_touches_so_map_gestures_reach_unhandled_input() -> void:
	var p := _page()
	assert_int(p.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	for path in ["SafeArea", "Backdrop"]:
		var n := p.get_node_or_null(path) as Control
		assert_object(n).is_not_null()
		assert_int(n.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(p.body.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int((p.body.get_parent() as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

func test_paper_backdrop_covers_until_the_native_map_presents() -> void:
	var p := _page()
	assert_bool(p.backdrop.visible).is_true() # 建页时先盖住：透明视口下面没有地图就是纯黑
	await p.on_tab_shown()
	fake.presented.emit(true)
	assert_bool(p.presenting).is_true()
	assert_bool(p.backdrop.visible).is_false()
	fake.presented.emit(false) # 没 token / 没桥 / 桌面
	assert_bool(p.backdrop.visible).is_true()

func test_friend_strip_lists_friends() -> void:
	t.responses = [{"status": 200, "json": {"items": [_friend("u-a", 31.2, 121.5), _friend("u-b", 31.3, 121.6)]}}]
	var p := _page()
	assert_bool(p.strip_panel.visible).is_false() # 没好友时整条收起
	await p.on_tab_shown()
	assert_bool(p.strip_panel.visible).is_true()
	var chip := p.strip.get_node("Friend_u-a") as Button
	assert_object(chip).is_not_null()
	assert_str(chip.text).is_equal("u-a") # 还没上报过自己的位置：不硬编一个距离出来
	# 图标不能被文字挤没（expand_icon 会这么干）：占位图标就位、尺寸有上限。
	assert_object(chip.icon).is_not_null()
	assert_bool(chip.expand_icon).is_false()
	assert_int(chip.get_theme_constant(&"icon_max_width")).is_equal(36)
	assert_object(p.strip.get_node_or_null("Friend_u-b")).is_not_null()
	# 好友都走光了：条收起来。
	t.responses.append({"status": 200, "json": {"items": []}})
	assert_bool(await p.refresh_friends()).is_true()
	assert_bool(p.strip_panel.visible).is_false()
	assert_object(p.strip.get_node_or_null("Friend_u-a")).is_null()

## 点好友先弹小卡，不再直接跳走——地图上多数时候只是想看一眼这人在哪。
func test_tapping_a_friend_opens_a_card_and_the_card_opens_their_page() -> void:
	t.responses = [{"status": 200, "json": {"items": [_friend("u-a", 31.2, 121.5), _friend("u-b", 31.3, 121.6)]}}]
	var p := _page()
	await p.on_tab_shown()
	assert_object(p.card_panel).is_null()
	(p.strip.get_node("Friend_u-a") as Button).pressed.emit()
	assert_object(p.card_panel).is_not_null()
	assert_str(p.card_user_id).is_equal("u-a")
	assert_str((p.card_panel.find_child("Who", true, false) as Label).text).is_equal("u-a")
	assert_int(nav.calls.size()).is_equal(0) # 弹卡不等于跳页
	# 点地图上的角色换成另一个人。
	fake.friend_tapped.emit("u-b")
	assert_str(p.card_user_id).is_equal("u-b")
	# 再点同一个人 = 收起来；点地图空处也收。
	fake.friend_tapped.emit("u-b")
	assert_object(p.card_panel).is_null()
	fake.friend_tapped.emit("u-a")
	fake.map_tapped.emit()
	assert_object(p.card_panel).is_null()
	# 卡上的「主页」才真的跳。
	fake.friend_tapped.emit("u-a")
	(p.card_panel.find_child("Profile", true, false) as Button).pressed.emit()
	assert_str(nav.calls[-1].route).is_equal(AppRoutes.USER)
	assert_that(nav.calls[-1].args).is_equal({"user_id": "u-a"})

## 上报过自己的位置之后：好友条按远近排序，名字下面带距离。
func test_friends_are_sorted_by_distance_once_we_know_where_we_are() -> void:
	var far := _friend("u-far", 31.40, 121.50)   # 约 22 km
	var near := _friend("u-near", 31.2015, 121.50) # 约 170 m
	# 依次是：进页时的第一次好友拉取、位置上报、上报后的再拉一次。
	t.responses = [{"status": 200, "json": {"items": []}}, {"status": 200, "json": {}},
		{"status": 200, "json": {"items": [far, near]}}]
	var p := _page()
	await p.on_tab_shown()
	p.shown = true
	await p._on_location(31.20, 121.50, 10.0)
	assert_int(p.report_count).is_equal(1)
	assert_bool(await p.refresh_friends()).is_true()
	assert_str(str(p.friends[0]["user_id"])).is_equal("u-near")
	var chip := p.strip.get_node("Friend_u-near") as Button
	assert_str(chip.text).contains("u-near")
	assert_str(chip.text).contains("away")
	assert_int(p.strip.get_children().find(chip)).is_less(
		p.strip.get_children().find(p.strip.get_node("Friend_u-far")))

func test_map_hud_leaves_room_for_the_tab_bar_and_the_friend_strip() -> void:
	var p := _page()
	var safe := auto_free(SafeAreaMargin.new()) as SafeAreaMargin
	safe.name = "SafeArea"
	var hud := Node.new()
	hud.name = "HUD"
	hud.add_child(safe)
	fake.add_child(hud)
	await p.on_tab_shown()
	assert_float(safe.extra_bottom).is_equal(AppShell.TAB_BAR_HEIGHT + p.FRIEND_STRIP_H)
	safe.apply_margins(Rect2i(), Vector2i(360, 640), Vector2(360, 640))
	assert_float(float(safe.get_theme_constant(&"margin_bottom"))).is_greater(AppShell.TAB_BAR_HEIGHT)

