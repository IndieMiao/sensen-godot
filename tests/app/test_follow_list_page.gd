extends GdUnitTestSuite
## 关注者 / 关注中 / 新粉丝列表页：三种 kind 打对的接口、行文案与关系角标、翻页、点行进主页、403 私密解释。

class NavRecorder extends RefCounted:
	var calls: Array = []
	func go(route: String, args: Dictionary) -> void:
		calls.append({"route": route, "args": args})

var session: AuthSession
var t: FakeTransport
var nav: NavRecorder

func before_test() -> void:
	session = AuthSession.new()
	session.complete_sign_in("uid-1", "id-1", "rt-1", 3600, "password", "a@b.co")
	session.set_server_user("me-1")
	t = FakeTransport.new([])
	nav = NavRecorder.new()

func after_test() -> void:
	if FileAccess.file_exists(AuthSession.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthSession.PATH))

func _page(args: Dictionary) -> Control:
	var p := (load(AppRoutes.FOLLOW_LIST) as PackedScene).instantiate()
	p.auth = session
	p.profile = ProfileApi.new(ApiClient.new("https://example.test/v1", t.callable()))
	p.navigate = nav.go
	p.setup(args)
	add_child(auto_free(p))
	return p

func _card(id: String, name: String, handle: Variant, following := false, followed_by := false) -> Dictionary:
	return {"user_id": id, "display_name": name, "handle": handle, "avatar": null,
		"relation": {"following": following, "followed_by": followed_by, "close_friends": following and followed_by}, "followed_at": 0}

func test_followers_list_renders_rows_with_relation_badges_and_pages() -> void:
	t.responses = [
		{"status": 200, "json": {"items": [_card("u-a", "Ann", "ann", true, true), _card("u-b", "Ben", null, false, true), _card("me-1", "Me", "me")], "next_cursor": "c2"}},
		{"status": 200, "json": {"items": [_card("u-c", "Cy", "cy", true, false)], "next_cursor": null}},
	]
	var p := _page({"user_id": "u-x", "kind": "followers"})
	assert_str(p.title_label.text).is_equal("Followers")
	assert_bool(await p.fetch()).is_true()
	assert_bool(str(t.requests[0].url).contains("/v1/users/u-x/followers?limit=20")).is_true()
	assert_int(p.list.get_child_count()).is_equal(3)
	assert_str((p.list.get_node("User_u-a") as Button).text).is_equal("Ann @ann\nClose friends")
	assert_str((p.list.get_node("User_u-b") as Button).text).is_equal("Ben\nFollows you")
	assert_str((p.list.get_node("User_me-1") as Button).text).is_equal("Me @me\nYou")
	assert_object(p.list.get_node("User_u-a").find_child("Avatar", true, false)).is_not_null()
	assert_bool(p.more_button.visible).is_true()
	assert_bool(await p.fetch(true)).is_true()
	assert_bool(str(t.requests[1].url).contains("cursor=c2")).is_true()
	assert_int(p.list.get_child_count()).is_equal(4)
	assert_str((p.list.get_node("User_u-c") as Button).text).is_equal("Cy @cy\nFollowing")
	assert_bool(p.more_button.visible).is_false()
	(p.list.get_node("User_u-a") as Button).pressed.emit()
	assert_str(nav.calls[-1].route).is_equal(AppRoutes.USER)
	assert_that(nav.calls[-1].args).is_equal({"user_id": "u-a"})
	# 点自己那行不跳（自己的主页就是「我的」Tab）。
	(p.list.get_node("User_me-1") as Button).pressed.emit()
	assert_int(nav.calls.size()).is_equal(1)

func test_following_and_new_kinds_hit_their_endpoints_and_explain_private_or_empty() -> void:
	t.responses = [{"status": 403, "json": {"code": "FOLLOWING_PRIVATE"}}]
	var p := _page({"user_id": "u-x", "kind": "following"})
	assert_str(p.title_label.text).is_equal("Following")
	assert_bool(await p.fetch()).is_false()
	assert_bool(str(t.requests[0].url).contains("/v1/users/u-x/following?")).is_true()
	assert_str(p.status.text).is_equal("This user keeps their following list private.")
	t.responses.append({"status": 200, "json": {"items": [], "unread_count": 0, "next_cursor": null}})
	var q := _page({"kind": "new"})
	assert_str(q.title_label.text).is_equal("New followers")
	assert_bool(await q.fetch()).is_true()
	assert_bool(str(t.requests[1].url).contains("/v1/users/me/new-followers?")).is_true()
	assert_str(q.status.text).is_equal("No new followers.")

func test_avatar_thumb_parses_server_field_and_falls_back_to_placeholder() -> void:
	assert_object(AvatarThumb.config_from(null)).is_null()
	assert_object(AvatarThumb.config_from({})).is_null()
	assert_object(AvatarThumb.config_from({"version": 9, "slots": {}})).is_null()
	var cfg := AvatarThumb.config_from({"version": 1, "slots": {"hair": "hair01", "cloth": ""}})
	assert_object(cfg).is_not_null()
	assert_str(String(cfg.slots.get(&"hair", ""))).is_equal("hair01")
	var thumb := auto_free(AvatarThumb.new(32.0)) as AvatarThumb
	add_child(thumb)
	assert_object(thumb.texture).is_equal(GameUi.icon("user-round"))
	# 测试进程里离屏渲染一律关掉（异步渲染会在测试结束时留下 orphan）：保持占位且不报错。
	assert_bool(AvatarPortraits.shared().can_render()).is_false()
	assert_bool(await thumb.show_avatar({"version": 1, "slots": {"hair": "hair01"}})).is_false()
	assert_object(thumb.texture).is_equal(GameUi.icon("user-round"))
	assert_bool(await thumb.show_avatar(null)).is_false()
